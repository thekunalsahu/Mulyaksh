# Mulyaksh website

Responsive Mulyaksh landing page, product verification pages, mobile QR scanner, and private developer dashboard backed by SQLite.

## Run locally (PowerShell)

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

A private `.env` file in this workspace contains the preview developer login and Flask session secret; it is excluded from Git. The `.env.example` shows the deployment settings. The current preview login is username `mulyaksh`; change both credentials before any public deployment.

```powershell
.\.venv\Scripts\python.exe app.py
```

Open http://127.0.0.1:5000. Developer dashboard: `/developer/login`. Client sign-in: `/client/login`; each client sees only their assigned products and scan totals. Create or reset client credentials from the developer dashboard; passwords are stored as hashes. Product and client records plus QR scan history are stored in `mulyaksh.sqlite3`. The starter demo product can be removed from the dashboard.

Each product gets a public information QR and a separate hidden single-use authenticity QR. The hidden code verifies the first scan and flags repeat scans. Product pages include the image/details, batch/origin/MRP fields, and an optional video. YouTube video links are converted to embeddable URLs. The camera scanner uses the browser's QR BarcodeDetector and needs browser support plus HTTPS when deployed; users can also scan a package with their phone's built-in QR reader.

The developer dashboard can set a QR price, validity in days (1–3,650), and the text printed below the QR. Expired QR links display an inactive page and no longer count scans. Saving a product starts its validity period from that day. The QR caption includes the selected brand/client label, product name, price when set, and expiry date.

The support chat uses Groq from the Flask server. Set `GROQ_API_KEY` in the private `.env` file and restart the app; the key is never sent to browser code. Text uses `GROQ_MODEL` (default `llama-3.3-70b-versatile`); attached JPG, PNG or WebP product photos are resized in the browser and analyzed with Groq's `qwen/qwen3.8-27b` vision model. Photos are only sent when a visitor attaches and submits one. If no key is configured, the chat points visitors to the contact form.

Set `PUBLIC_BASE_URL` to your public HTTPS domain before printing QR codes for real phone use. Each public product QR encodes that product's direct `/product/<id>` URL, so a phone camera or Google Lens opens its specific detail page. The hidden QR opens its separate single-use verification route. Localhost QR links only work on that same device. Do not use Flask's development server for production. Contact enquiries are appended to `leads.jsonl`; treat that file and the SQLite database as private business data.

Contact email is routed to `thekunalsahu@gmail.com` using Gmail SMTP. To enable delivery, add a Google App Password to the private `.env` file as `SMTP_PASSWORD=your-app-password` (do not use your normal Gmail password), then restart the app. The other Gmail SMTP settings are already set there: `SMTP_HOST=smtp.gmail.com`, `SMTP_PORT=587`, `SMTP_USER` and `SMTP_FROM` use the same Gmail address, and `CONTACT_EMAIL` is the destination. Until the App Password is configured, enquiries are saved locally in `leads.jsonl` and the form reports that email delivery is unavailable.

