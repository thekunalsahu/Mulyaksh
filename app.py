from datetime import datetime, timedelta, timezone
from functools import wraps
from pathlib import Path
import hmac
import hashlib
import base64
import binascii
import os
import re
import secrets
import smtplib
import sqlite3
import threading
import uuid
import json
import urllib.error
import urllib.request
from email.message import EmailMessage
from urllib.parse import parse_qs, urlparse

import qrcode
from flask import Flask, abort, flash, jsonify, redirect, render_template, request, send_file, session, url_for
from io import BytesIO
from werkzeug.security import check_password_hash, generate_password_hash

ROOT = Path(__file__).resolve().parent
# Load private local settings from .env when present, without overriding process environment.
local_env = ROOT / ".env"
if local_env.exists():
    for line in local_env.read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.lstrip().startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip())
DB_PATH = ROOT / "mulyaksh.sqlite3"
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
app = Flask(__name__)
app.secret_key = os.environ.get("MULYAKSH_SECRET") or (
    hmac.new(DATABASE_URL.encode(), b"mulyaksh-session-signing-v1", hashlib.sha256).hexdigest()
    if DATABASE_URL else "local-dev-only-change-before-deploy"
)
app.config["MAX_CONTENT_LENGTH"] = 2 * 1024 * 1024
app.config.update(
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    SESSION_COOKIE_SECURE=os.environ.get("PUBLIC_BASE_URL", "").startswith("https://"),
)


def normalize_video_url(value):
    value = (value or "").strip()
    if not value:
        return ""
    parsed = urlparse(value)
    if parsed.scheme not in ("https", "http") or not parsed.netloc:
        return ""
    host = parsed.netloc.lower().split(":")[0]
    if host in ("youtube.com", "www.youtube.com", "m.youtube.com"):
        video_id = parse_qs(parsed.query).get("v", [""])[0]
        if parsed.path.startswith("/embed/"):
            video_id = parsed.path.split("/embed/", 1)[1].split("/", 1)[0]
        if video_id:
            return f"https://www.youtube.com/embed/{video_id}"
    if host == "youtu.be":
        video_id = parsed.path.strip("/").split("/", 1)[0]
        if video_id:
            return f"https://www.youtube.com/embed/{video_id}"
    return value[:500]


def safe_image_url(value):
    value = (value or "").strip()
    parsed = urlparse(value)
    if parsed.scheme in ("https", "http") and parsed.netloc:
        return value[:500]
    return ""


def is_direct_video(value):
    return urlparse(value or "").path.lower().endswith((".mp4", ".webm", ".ogg"))


def database_id(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return -1


class IndexedRow(dict):
    """Mapping-style DB row with sqlite-compatible integer indexing."""

    def __getitem__(self, key):
        if isinstance(key, int):
            return tuple(self.values())[key]
        return super().__getitem__(key)


class PostgresCursor:
    def __init__(self, cursor):
        self.cursor = cursor

    def fetchone(self):
        row = self.cursor.fetchone()
        return IndexedRow(row) if row is not None else None

    def fetchall(self):
        return [IndexedRow(row) for row in self.cursor.fetchall()]


class PostgresConnection:
    """Small compatibility layer for the app's existing sqlite-style SQL."""

    def __init__(self, connection):
        self.connection = connection

    def execute(self, statement, parameters=()):
        statement = re.sub(r"\?", "%s", statement)
        return PostgresCursor(self.connection.execute(statement, parameters))

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        try:
            if exc_type is None:
                self.connection.commit()
            else:
                self.connection.rollback()
        finally:
            self.connection.close()


def db():
    if DATABASE_URL:
        import psycopg
        from psycopg.rows import dict_row

        return PostgresConnection(psycopg.connect(DATABASE_URL, row_factory=dict_row))
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db():
    with db() as conn:
        if DATABASE_URL:
            conn.execute("SELECT pg_advisory_xact_lock(7821042601)")
            for statement in (
                """CREATE TABLE IF NOT EXISTS clients (
                    id BIGSERIAL PRIMARY KEY, name TEXT NOT NULL, business TEXT NOT NULL,
                    phone TEXT DEFAULT '', email TEXT DEFAULT '', login_username TEXT,
                    password_hash TEXT, created_at TEXT NOT NULL
                )""",
                """CREATE TABLE IF NOT EXISTS products (
                    id BIGSERIAL PRIMARY KEY, public_id TEXT NOT NULL UNIQUE,
                    hidden_code TEXT UNIQUE, client_id BIGINT NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
                    name TEXT NOT NULL, description TEXT DEFAULT '', batch TEXT DEFAULT '',
                    origin TEXT DEFAULT '', mrp TEXT DEFAULT '', video_url TEXT DEFAULT '',
                    details TEXT DEFAULT '', qr_label TEXT DEFAULT '', qr_price TEXT DEFAULT '',
                    qr_expires_at TEXT DEFAULT '', active INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL
                )""",
                """CREATE TABLE IF NOT EXISTS scans (
                    id BIGSERIAL PRIMARY KEY, product_id BIGINT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
                    scanned_at TEXT NOT NULL, user_agent TEXT DEFAULT '', scan_type TEXT NOT NULL DEFAULT 'public'
                )""",
                "CREATE TABLE IF NOT EXISTS app_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
            ):
                conn.execute(statement)
            product_columns = {
                row[0] for row in conn.execute(
                    "SELECT column_name FROM information_schema.columns WHERE table_schema=current_schema() AND table_name='products'"
                ).fetchall()
            }
            client_columns = {
                row[0] for row in conn.execute(
                    "SELECT column_name FROM information_schema.columns WHERE table_schema=current_schema() AND table_name='clients'"
                ).fetchall()
            }
            scan_columns = {
                row[0] for row in conn.execute(
                    "SELECT column_name FROM information_schema.columns WHERE table_schema=current_schema() AND table_name='scans'"
                ).fetchall()
            }
        else:
            conn.executescript("""
            CREATE TABLE IF NOT EXISTS clients (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                business TEXT NOT NULL,
                phone TEXT DEFAULT '', email TEXT DEFAULT '',
                login_username TEXT, password_hash TEXT,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS products (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                public_id TEXT NOT NULL UNIQUE,
                hidden_code TEXT UNIQUE,
                client_id INTEGER NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
                name TEXT NOT NULL, description TEXT DEFAULT '',
                batch TEXT DEFAULT '', origin TEXT DEFAULT '',
                mrp TEXT DEFAULT '', video_url TEXT DEFAULT '', details TEXT DEFAULT '',
                qr_label TEXT DEFAULT '', qr_price TEXT DEFAULT '', qr_expires_at TEXT DEFAULT '',
                active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS scans (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
                scanned_at TEXT NOT NULL,
                user_agent TEXT DEFAULT '', scan_type TEXT NOT NULL DEFAULT 'public'
            );
            CREATE TABLE IF NOT EXISTS app_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """)
            product_columns = {row[1] for row in conn.execute("PRAGMA table_info(products)")}
            client_columns = {row[1] for row in conn.execute("PRAGMA table_info(clients)")}
            scan_columns = {row[1] for row in conn.execute("PRAGMA table_info(scans)")}
        if "login_username" not in client_columns:
            conn.execute("ALTER TABLE clients ADD COLUMN login_username TEXT")
        if "password_hash" not in client_columns:
            conn.execute("ALTER TABLE clients ADD COLUMN password_hash TEXT")
        conn.execute("CREATE UNIQUE INDEX IF NOT EXISTS clients_login_username_unique ON clients(LOWER(login_username)) WHERE login_username IS NOT NULL")
        if "image_url" not in product_columns:
            conn.execute("ALTER TABLE products ADD COLUMN image_url TEXT DEFAULT ''")
        if "hidden_code" not in product_columns:
            conn.execute("ALTER TABLE products ADD COLUMN hidden_code TEXT")
        for column in ("qr_label", "qr_price", "qr_expires_at"):
            if column not in product_columns:
                conn.execute(f"ALTER TABLE products ADD COLUMN {column} TEXT DEFAULT ''")
        if "scan_type" not in scan_columns:
            conn.execute("ALTER TABLE scans ADD COLUMN scan_type TEXT NOT NULL DEFAULT 'public'")
        for row in conn.execute("SELECT id FROM products WHERE hidden_code IS NULL OR hidden_code='' ").fetchall():
            conn.execute("UPDATE products SET hidden_code=? WHERE id=?", (uuid.uuid4().hex[:16], row[0]))
        if not conn.execute("SELECT 1 FROM app_meta WHERE key='demo_seeded'").fetchone():
            if conn.execute("SELECT COUNT(*) FROM clients").fetchone()[0] == 0:
                cur = conn.execute("INSERT INTO clients(name,business,phone,email,created_at) VALUES(?,?,?,?,?) RETURNING id", ("Mulyaksh Demo", "Mulyaksh Sample Brand", "", "", datetime.now(timezone.utc).isoformat()))
                client_id = cur.fetchone()[0]
                conn.execute("INSERT INTO products(public_id,hidden_code,client_id,name,description,batch,origin,mrp,video_url,details,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)", (uuid.uuid4().hex[:12], uuid.uuid4().hex[:16], client_id, "Mulyaksh Sample Product", "A sample verified product. Replace this entry from the developer dashboard with your own product details.", "DEMO-001", "India", "299", "", "Every scan verifies authenticity. Contact the brand for care, warranty and product support.", datetime.now(timezone.utc).isoformat()))
            conn.execute("INSERT INTO app_meta(key,value) VALUES('demo_seeded','1')")


_database_initialized = False
_database_init_lock = threading.Lock()


@app.before_request
def ensure_database_initialized():
    global _database_initialized
    if not _database_initialized:
        with _database_init_lock:
            if not _database_initialized:
                init_db()
                _database_initialized = True


def csrf_token():
    session.setdefault("csrf", secrets.token_urlsafe(24))
    return session["csrf"]


app.jinja_env.globals["csrf_token"] = csrf_token


def qr_expired(product):
    expires = (product["qr_expires_at"] or "").strip()
    if not expires:
        return False
    try:
        return datetime.fromisoformat(expires.replace("Z", "+00:00")) <= datetime.now(timezone.utc)
    except ValueError:
        return True


def qr_days_remaining(product):
    expires = (product["qr_expires_at"] or "").strip()
    if not expires:
        return 365
    try:
        seconds = (datetime.fromisoformat(expires.replace("Z", "+00:00")) - datetime.now(timezone.utc)).total_seconds()
        return max(1, min(3650, int((seconds + 86399) // 86400)))
    except ValueError:
        return 365


app.jinja_env.globals["qr_expired"] = qr_expired
app.jinja_env.globals["qr_days_remaining"] = qr_days_remaining


def qr_expiry_from_days(value):
    days = int(value or 365)
    if not 1 <= days <= 3650:
        raise ValueError("QR validity must be between 1 and 3,650 days.")
    return (datetime.now(timezone.utc).replace(microsecond=0) + timedelta(days=days)).isoformat()


def csrf_valid():
    return hmac.compare_digest(str(request.form.get("csrf", "")), str(session.get("csrf", "")))


def admin_required(fn):
    @wraps(fn)
    def wrapped(*args, **kwargs):
        if not session.get("developer"):
            return redirect(url_for("admin_login", next=request.path))
        return fn(*args, **kwargs)
    return wrapped


def client_required(fn):
    @wraps(fn)
    def wrapped(*args, **kwargs):
        if not session.get("client_id"):
            return redirect(url_for("client_login", next=request.path))
        return fn(*args, **kwargs)
    return wrapped


@app.get("/")
def home():
    return render_template("index.html")


@app.post("/api/contact")
def contact():
    data = request.get_json(silent=True) or request.form
    name = str(data.get("name", "")).strip()
    phone = str(data.get("phone", "")).strip()
    business = str(data.get("business", "")).strip()
    if not name or not phone:
        return jsonify(ok=False, message="Please add your name and phone number."), 400
    import json
    lead = {"name": name[:100], "phone": phone[:40], "business": business[:120], "created_at": datetime.now(timezone.utc).isoformat()}
    with (ROOT / "leads.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps(lead, ensure_ascii=False) + "\n")
    smtp_host = os.environ.get("SMTP_HOST", "").strip()
    recipient = os.environ.get("CONTACT_EMAIL", "").strip()
    smtp_user = os.environ.get("SMTP_USER", "").strip()
    smtp_password = os.environ.get("SMTP_PASSWORD", "")
    sender = os.environ.get("SMTP_FROM", smtp_user).strip()
    if not all((smtp_host, recipient, smtp_user, smtp_password, sender)):
        return jsonify(ok=False, message="Your enquiry was saved locally, but email delivery is not configured yet. Please try again later."), 503
    message = EmailMessage()
    safe_name = " ".join(name.splitlines())[:100]
    message["Subject"] = f"Mulyaksh website enquiry from {safe_name}"
    message["From"] = sender
    message["To"] = recipient
    message.set_content(f"Name: {name[:100]}\nPhone: {phone[:40]}\nBusiness: {business[:120] or 'Not provided'}\nReceived: {lead['created_at']}\n")
    try:
        port = int(os.environ.get("SMTP_PORT", "587"))
        if port == 465:
            with smtplib.SMTP_SSL(smtp_host, port, timeout=15) as smtp:
                smtp.login(smtp_user, smtp_password)
                smtp.send_message(message)
        else:
            with smtplib.SMTP(smtp_host, port, timeout=15) as smtp:
                smtp.starttls()
                smtp.login(smtp_user, smtp_password)
                smtp.send_message(message)
    except (OSError, smtplib.SMTPException, ValueError):
        app.logger.exception("Unable to deliver Mulyaksh contact email")
        return jsonify(ok=False, message="Your enquiry was saved locally, but email could not be delivered. Please try again later."), 503
    return jsonify(ok=True, message="Thanks — your enquiry has been emailed to the Mulyaksh team.")


@app.post("/api/support-chat")
def support_chat():
    api_key = os.environ.get("GROQ_API_KEY", "").strip()
    if not api_key:
        return jsonify(ok=False, message="Support chat is not configured yet. Please use the contact form."), 503
    data = request.get_json(silent=True) or {}
    raw_history = data.get("messages", [])
    if not isinstance(raw_history, list):
        return jsonify(ok=False, message="Please send a valid chat message."), 400
    history = []
    for item in raw_history[-8:]:
        if not isinstance(item, dict) or item.get("role") not in ("user", "assistant"):
            continue
        content = str(item.get("content", "")).strip()[:1000]
        if content:
            history.append({"role": item["role"], "content": content})
    if not history or history[-1]["role"] != "user":
        return jsonify(ok=False, message="Type a message to start the chat."), 400
    image_data = str(data.get("image_data", ""))
    image_url = None
    if image_data:
        try:
            header, encoded = image_data.split(",", 1)
            mime = header.removeprefix("data:").removesuffix(";base64")
            if mime not in ("image/jpeg", "image/png", "image/webp") or len(encoded) > 1_750_000:
                raise ValueError("Unsupported or oversized image")
            raw_image = base64.b64decode(encoded, validate=True)
            if not raw_image or len(raw_image) > 1_300_000:
                raise ValueError("Image is too large")
            from PIL import Image
            with Image.open(BytesIO(raw_image)) as uploaded:
                if uploaded.format not in ("JPEG", "PNG", "WEBP"):
                    raise ValueError("Unsupported image format")
                if uploaded.width * uploaded.height > 20_000_000:
                    raise ValueError("Image dimensions are too large")
                uploaded.verify()
            image_url = image_data
        except (ValueError, OSError, binascii.Error):
            return jsonify(ok=False, message="Please attach a JPG, PNG, or WebP image under 1.3 MB."), 400
        last = history[-1]
        history[-1] = {
            "role": "user",
            "content": [
                {"type": "text", "text": last["content"] or "Please describe this product photo and answer the customer's question."},
                {"type": "image_url", "image_url": {"url": image_url}},
            ],
        }
    payload = {
        "model": "qwen/qwen3.8-27b" if image_url else os.environ.get("GROQ_MODEL", "llama-3.3-70b-versatile"),
        "messages": [{"role": "system", "content": "You are Mulyaksh's friendly customer and client support assistant. Answer concisely in the language the user uses (English or Hinglish). Mulyaksh provides product pages, public product QR codes, hidden authenticity checks, scan activity, client and developer portals, and a coming-soon wallet. If a photo is attached, describe visible packaging and readable details, and answer questions about what can actually be seen. Do not infer hidden product facts, claim to verify authenticity from a photo, or claim access to client/account records. Direct account/product changes to the assigned brand or Mulyaksh developer; direct new-business enquiries to the contact form. Never ask for passwords, API keys, OTPs, or payment credentials."}, *history],
        "temperature": 0.4,
        "max_tokens": 300,
    }
    req = urllib.request.Request("https://api.groq.com/openai/v1/chat/completions", data=json.dumps(payload).encode(), headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            result = json.loads(response.read().decode("utf-8"))
        reply = result["choices"][0]["message"]["content"].strip()
        return jsonify(ok=True, message=reply[:2500])
    except urllib.error.HTTPError as error:
        app.logger.warning("Groq support chat returned HTTP %s", error.code)
        return jsonify(ok=False, message="I couldn't reach support chat just now. Please try again or use the contact form."), 502
    except urllib.error.URLError as error:
        app.logger.warning("Groq support chat network error: %s", str(error.reason)[:120])
        return jsonify(ok=False, message="I couldn't reach support chat just now. Please try again or use the contact form."), 502
    except (TimeoutError, ValueError, KeyError, IndexError):
        app.logger.warning("Groq support chat response could not be read")
        return jsonify(ok=False, message="I couldn't reach support chat just now. Please try again or use the contact form."), 502


@app.get("/wallet")
def wallet():
    return render_template("wallet.html")


@app.get("/more-info")
def more_info():
    return render_template("more_info.html")


@app.route("/client/login", methods=["GET", "POST"])
def client_login():
    if request.method == "POST":
        if not csrf_valid():
            abort(400)
        username = request.form.get("username", "").strip()
        with db() as conn:
            client = conn.execute("SELECT id,password_hash FROM clients WHERE LOWER(login_username)=LOWER(?)", (username,)).fetchone()
        if client and client["password_hash"] and check_password_hash(client["password_hash"], request.form.get("password", "")):
            session.clear()
            session["client_id"] = client["id"]
            return redirect(url_for("client_dashboard"))
        flash("Those client login details did not match.", "error")
    return render_template("client_login.html")


@app.post("/client/logout")
@client_required
def client_logout():
    if not csrf_valid():
        abort(400)
    session.clear()
    return redirect(url_for("home"))


@app.get("/client")
@client_required
def client_dashboard():
    with db() as conn:
        client = conn.execute("SELECT id,name,business,email FROM clients WHERE id=?", (session["client_id"],)).fetchone()
        if not client:
            session.clear()
            return redirect(url_for("client_login"))
        products = conn.execute("""
            SELECT p.*, COUNT(s.id) AS scans,
                   COALESCE(SUM(CASE WHEN s.scan_type='hidden' THEN 1 ELSE 0 END),0) AS authenticity_scans,
                   MAX(s.scanned_at) AS last_scan
            FROM products p LEFT JOIN scans s ON s.product_id=p.id
            WHERE p.client_id=? GROUP BY p.id ORDER BY p.id DESC
        """, (client["id"],)).fetchall()
    return render_template("client_dashboard.html", client=client, products=products, scan_total=sum(row["scans"] for row in products))


@app.get("/scan")
def scanner():
    return render_template("scanner.html")


@app.get("/product/<public_id>")
def product_page(public_id):
    with db() as conn:
        product = conn.execute("SELECT p.*,c.business,c.name AS contact_name FROM products p JOIN clients c ON c.id=p.client_id WHERE p.public_id=? AND p.active=1", (public_id,)).fetchone()
        if not product:
            abort(404)
        if qr_expired(product):
            return render_template("qr_expired.html", product=product), 410
        previous = conn.execute("SELECT COUNT(*) FROM scans WHERE product_id=?", (product["id"],)).fetchone()[0]
        conn.execute("INSERT INTO scans(product_id,scanned_at,user_agent,scan_type) VALUES(?,?,?,?)", (product["id"], datetime.now(timezone.utc).isoformat(), request.headers.get("User-Agent", "")[:250], "public"))
    video_url = normalize_video_url(product["video_url"])
    return render_template("product.html", product=product, repeat=False, verification_scan=False, video_url=video_url, direct_video=is_direct_video(video_url))


@app.get("/verify/<hidden_code>")
def verify_product(hidden_code):
    with db() as conn:
        product = conn.execute("SELECT p.*,c.business,c.name AS contact_name FROM products p JOIN clients c ON c.id=p.client_id WHERE p.hidden_code=? AND p.active=1", (hidden_code,)).fetchone()
        if not product:
            abort(404)
        if qr_expired(product):
            return render_template("qr_expired.html", product=product), 410
        previous = conn.execute("SELECT COUNT(*) FROM scans WHERE product_id=? AND scan_type='hidden'", (product["id"],)).fetchone()[0]
        conn.execute("INSERT INTO scans(product_id,scanned_at,user_agent,scan_type) VALUES(?,?,?,?)", (product["id"], datetime.now(timezone.utc).isoformat(), request.headers.get("User-Agent", "")[:250], "hidden"))
    video_url = normalize_video_url(product["video_url"])
    return render_template("product.html", product=product, repeat=previous > 0, verification_scan=True, video_url=video_url, direct_video=is_direct_video(video_url))


@app.get("/product/<public_id>/qr.png")
def product_qr(public_id):
    with db() as conn:
        kind = "hidden" if request.args.get("kind") == "hidden" else "public"
        row = conn.execute("SELECT p.public_id,p.hidden_code,p.name,p.qr_label,p.qr_price,p.qr_expires_at,c.business FROM products p JOIN clients c ON c.id=p.client_id WHERE p.public_id=? AND p.active=1", (public_id,)).fetchone()
    if not row:
        abort(404)
    base = os.environ.get("PUBLIC_BASE_URL", "").strip().rstrip("/") or request.url_root.rstrip("/")
    target = f"{base}/verify/{row['hidden_code']}" if kind == "hidden" else f"{base}/product/{public_id}"
    qr = qrcode.QRCode(box_size=8, border=4)
    qr.add_data(target)
    qr.make(fit=True)
    code = qr.make_image(fill_color="#10243c", back_color="white").convert("RGB")
    label = (row["qr_label"] or row["business"] or "").strip()[:48]
    product_name = row["name"].strip()[:56]
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.load_default()
    draw_probe = ImageDraw.Draw(code)
    lines = [label] if label else []
    if label.lower() != product_name.lower():
        lines.append(product_name)
    if row["qr_price"]:
        lines.append(f"Value Rs. {row['qr_price']}")
    if row["qr_expires_at"]:
        lines.append(f"Active until {row['qr_expires_at'][:10]}")
    line_heights = [draw_probe.textbbox((0, 0), line, font=font)[3] + 12 for line in lines]
    image = Image.new("RGB", (code.width, code.height + sum(line_heights) + 12), "white")
    image.paste(code, (0, 0))
    draw = ImageDraw.Draw(image)
    y = code.height + 6
    for index, line in enumerate(lines):
        bounds = draw.textbbox((0, 0), line, font=font)
        draw.text(((image.width - (bounds[2] - bounds[0])) / 2, y), line, fill="#10243c" if index == 0 else "#5b6370", font=font)
        y += line_heights[index]
    buffer = BytesIO()
    image.save(buffer, format="PNG")
    buffer.seek(0)
    return send_file(buffer, mimetype="image/png", download_name=f"mulyaksh-{public_id}-{kind}.png")


@app.route("/developer/login", methods=["GET", "POST"])
def admin_login():
    if request.method == "POST":
        if not csrf_valid():
            abort(400)
        username = os.environ.get("DEVELOPER_USERNAME", "")
        password = os.environ.get("DEVELOPER_PASSWORD", "")
        if not username or not password:
            flash("Developer login is not configured. Set DEVELOPER_USERNAME and DEVELOPER_PASSWORD first.", "error")
        elif hmac.compare_digest(request.form.get("username", ""), username) and hmac.compare_digest(request.form.get("password", ""), password):
            session.clear()
            session["developer"] = True
            return redirect(url_for("admin_dashboard"))
        else:
            flash("Those login details did not match.", "error")
    return render_template("admin_login.html")


@app.post("/developer/logout")
@admin_required
def admin_logout():
    if not csrf_valid():
        abort(400)
    session.clear()
    return redirect(url_for("home"))


@app.route("/developer", methods=["GET", "POST"])
@admin_required
def admin_dashboard():
    if request.method == "POST":
        if not csrf_valid():
            abort(400)
        action = request.form.get("action")
        with db() as conn:
            if action == "add_client":
                name, business = request.form.get("name", "").strip(), request.form.get("business", "").strip()
                login_username = request.form.get("login_username", "").strip()
                login_password = request.form.get("login_password", "")
                if not name or not business or not login_username or len(login_password) < 10:
                    flash("Client details, a login ID, and a password of at least 10 characters are required.", "error")
                elif conn.execute("SELECT 1 FROM clients WHERE LOWER(login_username)=LOWER(?)", (login_username,)).fetchone():
                    flash("That client login ID is already in use.", "error")
                else:
                    conn.execute("INSERT INTO clients(name,business,phone,email,login_username,password_hash,created_at) VALUES(?,?,?,?,?,?,?)", (name[:100], business[:120], request.form.get("phone", "")[:40], request.form.get("email", "")[:120], login_username[:80], generate_password_hash(login_password), datetime.now(timezone.utc).isoformat()))
                    flash("Client added with login ID " + login_username + ". Share the password you entered with that client securely.", "success")
            elif action == "update_client":
                client_id = database_id(request.form.get("client_id"))
                name, business = request.form.get("name", "").strip(), request.form.get("business", "").strip()
                login_username = request.form.get("login_username", "").strip()
                login_password = request.form.get("login_password", "")
                duplicate = conn.execute("SELECT 1 FROM clients WHERE LOWER(login_username)=LOWER(?) AND id<>?", (login_username, client_id)).fetchone() if login_username else None
                current = conn.execute("SELECT password_hash FROM clients WHERE id=?", (client_id,)).fetchone()
                if not name or not business:
                    flash("Client and business name are required.", "error")
                elif duplicate:
                    flash("That client login ID is already in use.", "error")
                elif login_username and login_password and len(login_password) < 10:
                    flash("New client passwords must be at least 10 characters.", "error")
                elif login_username and not (login_password or (current and current["password_hash"])):
                    flash("Enter a password to enable this client's login.", "error")
                else:
                    password_hash = generate_password_hash(login_password) if login_password else (current["password_hash"] if current else None)
                    conn.execute("UPDATE clients SET name=?,business=?,phone=?,email=?,login_username=?,password_hash=? WHERE id=?", (name[:100], business[:120], request.form.get("phone", "")[:40], request.form.get("email", "")[:120], login_username[:80] or None, password_hash if login_username else None, client_id))
                    flash("Client details and login updated.", "success")
            elif action == "delete_client":
                conn.execute("DELETE FROM clients WHERE id=?", (database_id(request.form.get("client_id")),))
                flash("Client and their products removed.", "success")
            elif action == "add_product":
                name = request.form.get("name", "").strip()
                client_id = database_id(request.form.get("client_id"))
                if name and conn.execute("SELECT 1 FROM clients WHERE id=?", (client_id,)).fetchone():
                    public_id = uuid.uuid4().hex[:12]
                    try:
                        expires = qr_expiry_from_days(request.form.get("qr_active_days", "365"))
                    except ValueError as error:
                        flash(str(error), "error")
                        return redirect(url_for("admin_dashboard"))
                    conn.execute("INSERT INTO products(public_id,hidden_code,client_id,name,description,batch,origin,mrp,video_url,image_url,details,qr_label,qr_price,qr_expires_at,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (public_id, uuid.uuid4().hex[:16], client_id, name[:120], request.form.get("description", "")[:1000], request.form.get("batch", "")[:100], request.form.get("origin", "")[:120], request.form.get("mrp", "")[:40], normalize_video_url(request.form.get("video_url", "")), safe_image_url(request.form.get("image_url", "")), request.form.get("details", "")[:1500], request.form.get("qr_label", "")[:80], request.form.get("qr_price", "")[:30], expires, datetime.now(timezone.utc).isoformat()))
                    flash("Product added. Its QR code is ready below.", "success")
                else:
                    flash("Choose a client and enter a product name.", "error")
            elif action == "update_product":
                try:
                    expires = qr_expiry_from_days(request.form.get("qr_active_days", "365"))
                except ValueError as error:
                    flash(str(error), "error")
                    return redirect(url_for("admin_dashboard"))
                conn.execute("UPDATE products SET name=?,description=?,batch=?,origin=?,mrp=?,video_url=?,image_url=?,details=?,active=?,qr_label=?,qr_price=?,qr_expires_at=? WHERE id=?", (request.form.get("name", "").strip()[:120], request.form.get("description", "")[:1000], request.form.get("batch", "")[:100], request.form.get("origin", "")[:120], request.form.get("mrp", "")[:40], normalize_video_url(request.form.get("video_url", "")), safe_image_url(request.form.get("image_url", "")), request.form.get("details", "")[:1500], 1 if request.form.get("active") else 0, request.form.get("qr_label", "")[:80], request.form.get("qr_price", "")[:30], expires, database_id(request.form.get("product_id"))))
                flash("Product updated.", "success")
            elif action == "delete_product":
                conn.execute("DELETE FROM products WHERE id=?", (database_id(request.form.get("product_id")),))
                flash("Product removed.", "success")
        return redirect(url_for("admin_dashboard"))
    with db() as conn:
        clients = conn.execute("SELECT c.*,COUNT(p.id) AS product_count FROM clients c LEFT JOIN products p ON p.client_id=c.id GROUP BY c.id ORDER BY c.id DESC").fetchall()
        products = conn.execute("SELECT p.*,c.business,(SELECT COUNT(*) FROM scans s WHERE s.product_id=p.id) AS scans FROM products p JOIN clients c ON c.id=p.client_id ORDER BY p.id DESC").fetchall()
        scans = conn.execute("SELECT COUNT(*) FROM scans").fetchone()[0]
    return render_template("admin.html", clients=clients, products=products, scans=scans)


@app.errorhandler(404)
def missing(_error):
    return render_template("not_found.html"), 404


if __name__ == "__main__":
    app.run(debug=os.environ.get("FLASK_DEBUG", "0") == "1")


