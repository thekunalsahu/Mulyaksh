import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

final DateTime _launchAt = DateTime(2026, 10, 6);

const Color _black = Color(0xFF020202);
const Color _panel = Color(0xFF080808);
const Color _panelSoft = Color(0xFF0E0E0E);
const Color _line = Color(0xFF242424);
const Color _white = Color(0xFFF8F7F1);
const Color _muted = Color(0xFFA7A39A);
const Color _gold = Color(0xFFC29045);
const Color _green = Color(0xFF49D17E);

void main() {
  runApp(const MulyakshApp());
}

class MulyakshApp extends StatelessWidget {
  const MulyakshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mulyaksh | Coming Soon',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _gold,
          brightness: Brightness.dark,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(
            color: _muted,
            fontSize: 15,
            height: 1.55,
            fontFamilyFallback: ['Segoe UI', 'Inter', 'Arial', 'sans-serif'],
          ),
        ),
      ),
      home: const MulyakshLandingPage(),
    );
  }
}

class MulyakshLandingPage extends StatefulWidget {
  const MulyakshLandingPage({super.key});

  @override
  State<MulyakshLandingPage> createState() => _MulyakshLandingPageState();
}

class _MulyakshLandingPageState extends State<MulyakshLandingPage>
    with TickerProviderStateMixin {
  late final AnimationController _ambientController;
  late final AnimationController _introController;
  late final AnimationController _pulseController;
  late final Timer _timer;
  final TextEditingController _emailController = TextEditingController();

  Duration _remaining = _timeUntilLaunch();
  String _waitlistStatus = '';

  static Duration _timeUntilLaunch() {
    final remaining = _launchAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..forward();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _remaining = _timeUntilLaunch();
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _ambientController.dispose();
    _introController.dispose();
    _pulseController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: _black)),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ambientController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _AmbientFieldPainter(_ambientController.value),
                );
              },
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x00000000),
                    Color(0x66000000),
                    Color(0xDD000000),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 900;
                final edge = compact ? 22.0 : 46.0;
                final width = math.max(0.0, constraints.maxWidth - edge * 2);

                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: edge,
                        vertical: compact ? 18 : 30,
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: math.min(width, 1040),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildHeader(compact),
                              SizedBox(height: compact ? 54 : 166),
                              _buildStage(compact),
                              SizedBox(height: compact ? 64 : 116),
                              _Footer(compact: compact),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool compact) {
    final phase = _PhaseBadge(pulse: _pulseController);
    final brand = const _BrandLockup();

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [brand, const SizedBox(height: 16), phase],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [brand, phase],
    );
  }

  Widget _buildStage(bool compact) {
    final hero = _reveal(
      start: 0,
      horizontalOffset: -18,
      child: _HeroCopy(compact: compact),
    );
    final console = _reveal(
      start: 0.18,
      horizontalOffset: 20,
      child: _CountdownConsole(
        remaining: _remaining,
        compact: compact,
        emailController: _emailController,
        waitlistStatus: _waitlistStatus,
        pulse: _pulseController,
        onSubmit: _submitWaitlist,
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [hero, const SizedBox(height: 36), console],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 54, child: hero),
        const SizedBox(width: 88),
        SizedBox(width: 386, child: console),
      ],
    );
  }

  Widget _reveal({
    required double start,
    required double horizontalOffset,
    required Widget child,
  }) {
    return AnimatedBuilder(
      animation: _introController,
      builder: (context, _) {
        final raw = ((_introController.value - start) / (1 - start)).clamp(
          0.0,
          1.0,
        );
        final eased = Curves.easeOutCubic.transform(raw);
        return Opacity(
          opacity: eased,
          child: Transform.translate(
            offset: Offset(horizontalOffset * (1 - eased), 26 * (1 - eased)),
            child: child,
          ),
        );
      },
    );
  }

  void _submitWaitlist() {
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim();

    setState(() {
      if (email.isEmpty || !email.contains('@')) {
        _waitlistStatus = 'Enter an email to join early access.';
        return;
      }
      _waitlistStatus =
          'Early access request received. We will reach you soon.';
    });
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    final markSize = compact ? 54.0 : 64.0;
    final wordmarkSize = compact ? 25.0 : 30.0;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: math.max(0, MediaQuery.sizeOf(context).width - 44),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: markSize,
            height: markSize,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _white.withValues(alpha: 0.15)),
              boxShadow: [
                BoxShadow(
                  color: _gold.withValues(alpha: 0.08),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/mulyaksh_mark.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          SizedBox(width: compact ? 12 : 16),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MulyakshWordmark(size: wordmarkSize),
                const SizedBox(height: 7),
                const Text(
                  'EMPOWERING VALUE, ENRICHING LIVES',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _gold,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    height: 1,
                    fontFamilyFallback: [
                      'Segoe UI',
                      'Inter',
                      'Arial',
                      'sans-serif',
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MulyakshWordmark extends StatelessWidget {
  const _MulyakshWordmark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _WordmarkKAccentPainter(),
      child: Text(
        'Mulyaksh',
        style: TextStyle(
          color: _white,
          fontSize: size,
          fontWeight: FontWeight.w500,
          height: 0.92,
          letterSpacing: 0,
          fontFamilyFallback: const [
            'Times New Roman',
            'Georgia',
            'Cambria',
            'serif',
          ],
        ),
      ),
    );
  }
}

class _WordmarkKAccentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * 0.69;
    final y = size.height * 0.13;
    final leaf = Path()
      ..moveTo(x, y + size.height * 0.5)
      ..cubicTo(
        x + size.width * 0.02,
        y + size.height * 0.25,
        x + size.width * 0.09,
        y + size.height * 0.12,
        x + size.width * 0.13,
        y,
      )
      ..cubicTo(
        x + size.width * 0.09,
        y + size.height * 0.32,
        x + size.width * 0.04,
        y + size.height * 0.52,
        x,
        y + size.height * 0.76,
      )
      ..close();

    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE4B665), Color(0xFF9E6A23)],
      ).createShader(leaf.getBounds());

    canvas.drawPath(leaf, paint);

    final cut = Paint()
      ..color = _black.withValues(alpha: 0.6)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(x + size.width * 0.045, y + size.height * 0.45),
      Offset(x + size.width * 0.11, y + size.height * 0.1),
      cut,
    );
  }

  @override
  bool shouldRepaint(covariant _WordmarkKAccentPainter oldDelegate) => false;
}

class _PhaseBadge extends StatelessWidget {
  const _PhaseBadge({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final glow = 0.35 + pulse.value * 0.65;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: _panel.withValues(alpha: 0.74),
            border: Border.all(color: _line),
            boxShadow: [
              BoxShadow(
                color: _green.withValues(alpha: 0.04 + glow * 0.05),
                blurRadius: 18,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.qr_code_2,
                color: _green.withValues(alpha: 0.55 + glow * 0.35),
                size: 14,
              ),
              const SizedBox(width: 9),
              Text(
                'SMART QR PRODUCT PAGES',
                style: TextStyle(
                  color: _muted.withValues(alpha: 0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  fontFamilyFallback: const [
                    'Segoe UI',
                    'Inter',
                    'Arial',
                    'sans-serif',
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Kicker(),
        const SizedBox(height: 28),
        _ComingSoonTitle(compact: compact),
        const SizedBox(height: 27),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: const Text(
            'Mulyaksh creates smart QR pages for products. A brand places a QR on its product, and customers scan it to see product details, how it is made, price, customer reviews, offers, and useful advertisements in one clean page.',
            style: TextStyle(
              color: _muted,
              fontSize: 15.5,
              height: 1.55,
              fontWeight: FontWeight.w400,
              fontFamilyFallback: ['Segoe UI', 'Inter', 'Arial', 'sans-serif'],
            ),
          ),
        ),
        const SizedBox(height: 38),
        const _FeatureTiles(),
      ],
    );
  }
}

class _Kicker extends StatelessWidget {
  const _Kicker();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.05),
        border: Border.all(color: _gold.withValues(alpha: 0.28)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 12, color: _gold),
          SizedBox(width: 7),
          Text(
            'QR PRODUCT EXPERIENCE',
            style: TextStyle(
              color: _gold,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFamilyFallback: ['Segoe UI', 'Inter', 'Arial', 'sans-serif'],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComingSoonTitle extends StatelessWidget {
  const _ComingSoonTitle({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 980),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: Transform.scale(
              scale: 0.96 + value * 0.04,
              alignment: Alignment.centerLeft,
              child: child,
            ),
          ),
        );
      },
      child: Text(
        'COMING SOON',
        maxLines: 2,
        style: TextStyle(
          color: _white,
          fontSize: compact ? 48 : 64,
          fontWeight: FontWeight.w900,
          height: 0.94,
          fontFamilyFallback: const [
            'Segoe UI Black',
            'Arial Black',
            'Segoe UI',
            'sans-serif',
          ],
        ),
      ),
    );
  }
}

class _FeatureTiles extends StatelessWidget {
  const _FeatureTiles();

  static const _features = [
    (
      icon: Icons.qr_code_2,
      title: 'Product QR',
      body: 'Every product gets a smart scan page.',
    ),
    (
      icon: Icons.inventory_2_outlined,
      title: 'Full Details',
      body: 'Price, specs, process, and product story.',
    ),
    (
      icon: Icons.reviews_outlined,
      title: 'Reviews',
      body: 'Customer reviews shown after scan.',
    ),
    (
      icon: Icons.campaign_outlined,
      title: 'Ads & Offers',
      body: 'Relevant promotions on the product page.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 460;
        final tileWidth = stacked
            ? constraints.maxWidth
            : (constraints.maxWidth - 14) / 2;

        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final feature in _features)
              SizedBox(
                width: tileWidth,
                child: _FeatureTile(
                  icon: feature.icon,
                  title: feature.title,
                  body: feature.body,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FeatureTile extends StatefulWidget {
  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  State<_FeatureTile> createState() => _FeatureTileState();
}

class _FeatureTileState extends State<_FeatureTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 70),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: _panel.withValues(alpha: _hovered ? 0.92 : 0.64),
          border: Border.all(
            color: _hovered
                ? _gold.withValues(alpha: 0.35)
                : _line.withValues(alpha: 0.88),
          ),
          boxShadow: [
            if (_hovered)
              BoxShadow(
                color: _gold.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(widget.icon, size: 16, color: _gold),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: _white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      fontFamilyFallback: [
                        'Segoe UI',
                        'Inter',
                        'Arial',
                        'sans-serif',
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.body,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 10.5,
                      height: 1.3,
                      fontFamilyFallback: [
                        'Segoe UI',
                        'Inter',
                        'Arial',
                        'sans-serif',
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountdownConsole extends StatelessWidget {
  const _CountdownConsole({
    required this.remaining,
    required this.compact,
    required this.emailController,
    required this.waitlistStatus,
    required this.pulse,
    required this.onSubmit,
  });

  final Duration remaining;
  final bool compact;
  final TextEditingController emailController;
  final String waitlistStatus;
  final Animation<double> pulse;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final glow = 0.32 + pulse.value * 0.68;
        return CustomPaint(
          foregroundPainter: _ConsoleFramePainter(glow),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              compact ? 22 : 31,
              compact ? 28 : 34,
              compact ? 22 : 31,
              compact ? 25 : 31,
            ),
            decoration: BoxDecoration(
              color: _panel.withValues(alpha: 0.87),
              border: Border.all(color: _line),
              boxShadow: [
                BoxShadow(
                  color: _gold.withValues(alpha: 0.04 + glow * 0.05),
                  blurRadius: 34,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'LAUNCH COUNTDOWN',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    fontFamilyFallback: [
                      'Segoe UI',
                      'Inter',
                      'Arial',
                      'sans-serif',
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Product QR pages are getting ready for brands and customers.',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 11,
                    height: 1.35,
                    fontFamilyFallback: [
                      'Segoe UI',
                      'Inter',
                      'Arial',
                      'sans-serif',
                    ],
                  ),
                ),
                const SizedBox(height: 34),
                _CountdownStrip(remaining: remaining),
                const SizedBox(height: 30),
                const Divider(height: 1, color: _line),
                const SizedBox(height: 24),
                const Text(
                  'GET EARLY ACCESS',
                  style: TextStyle(
                    color: _white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    fontFamilyFallback: [
                      'Segoe UI',
                      'Inter',
                      'Arial',
                      'sans-serif',
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Join the early list for product QR demos and launch updates.',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 10.5,
                    height: 1.35,
                    fontFamilyFallback: [
                      'Segoe UI',
                      'Inter',
                      'Arial',
                      'sans-serif',
                    ],
                  ),
                ),
                const SizedBox(height: 19),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(
                    color: _white,
                    fontSize: 13,
                    fontFamilyFallback: [
                      'Segoe UI',
                      'Inter',
                      'Arial',
                      'sans-serif',
                    ],
                  ),
                  cursorColor: _gold,
                  decoration: InputDecoration(
                    hintText: 'Enter email address',
                    hintStyle: TextStyle(
                      color: _muted.withValues(alpha: 0.55),
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: _panelSoft,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: _line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(
                        color: _gold.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                  onSubmitted: (_) => onSubmit(),
                ),
                const SizedBox(height: 10),
                _AdmittanceButton(onPressed: onSubmit),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: waitlistStatus.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          key: ValueKey(waitlistStatus),
                          padding: const EdgeInsets.only(top: 13),
                          child: Text(
                            waitlistStatus,
                            style: TextStyle(
                              color: waitlistStatus.contains('received')
                                  ? _green
                                  : _gold,
                              fontSize: 11,
                              height: 1.35,
                              fontFamilyFallback: const [
                                'Segoe UI',
                                'Inter',
                                'Arial',
                                'sans-serif',
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CountdownStrip extends StatelessWidget {
  const _CountdownStrip({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final values = [
      _CountdownValue('${remaining.inDays}', 'DAYS'),
      _CountdownValue(_twoDigits(remaining.inHours.remainder(24)), 'HOURS'),
      _CountdownValue(_twoDigits(remaining.inMinutes.remainder(60)), 'MINS'),
      _CountdownValue(_twoDigits(remaining.inSeconds.remainder(60)), 'SECS'),
    ];

    return Row(
      children: [
        for (var i = 0; i < values.length; i++) ...[
          Expanded(child: values[i]),
          if (i != values.length - 1)
            Container(
              width: 1,
              height: 56,
              color: _line.withValues(alpha: 0.92),
            ),
        ],
      ],
    );
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

class _CountdownValue extends StatelessWidget {
  const _CountdownValue(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: _white,
            fontSize: 29,
            fontWeight: FontWeight.w500,
            height: 1,
            fontFeatures: [FontFeature.tabularFigures()],
            fontFamilyFallback: ['Segoe UI', 'Inter', 'Arial', 'sans-serif'],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: _muted.withValues(alpha: 0.72),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            height: 1,
            fontFamilyFallback: const [
              'Segoe UI',
              'Inter',
              'Arial',
              'sans-serif',
            ],
          ),
        ),
      ],
    );
  }
}

class _AdmittanceButton extends StatefulWidget {
  const _AdmittanceButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_AdmittanceButton> createState() => _AdmittanceButtonState();
}

class _AdmittanceButtonState extends State<_AdmittanceButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 47,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: _hovered ? _gold : _white,
            boxShadow: [
              if (_hovered)
                BoxShadow(
                  color: _gold.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Flexible(
                child: Text(
                  'JOIN EARLY ACCESS',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _black,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                    fontFamilyFallback: [
                      'Segoe UI',
                      'Inter',
                      'Arial',
                      'sans-serif',
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Icon(Icons.north_east, color: _black, size: _hovered ? 17 : 15),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copyright = Text(
      '(C) 2026 MULYAKSH. ALL RIGHTS RESERVED.',
      style: TextStyle(
        color: _muted.withValues(alpha: 0.46),
        fontSize: 10,
        fontWeight: FontWeight.w600,
        fontFamilyFallback: const ['Segoe UI', 'Inter', 'Arial', 'sans-serif'],
      ),
    );
    final socials = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FooterIcon(icon: Icons.alternate_email),
        _FooterIcon(icon: Icons.hub_outlined),
        _FooterIcon(icon: Icons.public),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(color: _line.withValues(alpha: 0.62), height: 1),
        const SizedBox(height: 21),
        if (compact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [copyright, const SizedBox(height: 16), socials],
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [copyright, socials],
          ),
      ],
    );
  }
}

class _FooterIcon extends StatelessWidget {
  const _FooterIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 18),
      child: Icon(icon, size: 15, color: _muted.withValues(alpha: 0.45)),
    );
  }
}

class _ConsoleFramePainter extends CustomPainter {
  const _ConsoleFramePainter(this.glow);

  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final corner = Paint()
      ..color = _gold.withValues(alpha: 0.14 + glow * 0.16)
      ..strokeWidth = 1;
    const length = 33.0;

    canvas.drawLine(Offset.zero, const Offset(length, 0), corner);
    canvas.drawLine(Offset.zero, const Offset(0, length), corner);
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width - length, 0),
      corner,
    );
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, length), corner);
    canvas.drawLine(
      Offset(0, size.height),
      Offset(length, size.height),
      corner,
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(0, size.height - length),
      corner,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - length, size.height),
      corner,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - length),
      corner,
    );

    final sweep = Paint()
      ..color = _gold.withValues(alpha: 0.13 + glow * 0.14)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final start = size.width * (0.12 + glow * 0.16);
    canvas.drawLine(
      Offset(start, 0),
      Offset(math.min(start + 96, size.width - 12), 0),
      sweep,
    );
  }

  @override
  bool shouldRepaint(covariant _ConsoleFramePainter oldDelegate) {
    return oldDelegate.glow != glow;
  }
}

class _AmbientFieldPainter extends CustomPainter {
  const _AmbientFieldPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = _white.withValues(alpha: 0.018)
      ..strokeWidth = 1;
    final gridStep = size.width < 700 ? 46.0 : 62.0;
    final drift = progress * gridStep;

    for (var x = -gridStep + drift; x < size.width + gridStep; x += gridStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (
      var y = -gridStep + drift * 0.6;
      y < size.height + gridStep;
      y += gridStep
    ) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final scanY = (size.height + 160) * progress - 80;
    final scan = Paint()
      ..shader = LinearGradient(
        colors: [
          _gold.withValues(alpha: 0),
          _gold.withValues(alpha: 0.07),
          _green.withValues(alpha: 0.03),
          _gold.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, scanY - 24, size.width, 48));
    canvas.drawRect(Rect.fromLTWH(0, scanY - 24, size.width, 48), scan);

    final trace = Paint()
      ..color = _gold.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    final spark = Paint()..color = _green.withValues(alpha: 0.18);

    for (var i = 0; i < 24; i++) {
      final seed = i * 41.0;
      final x = (seed * 17 + progress * (32 + i % 5 * 9)) % size.width;
      final y =
          (seed * 11 + math.sin(progress * math.pi * 2 + i) * 18) % size.height;
      final segment = 18.0 + (i % 4) * 8;
      if (i.isEven) {
        canvas.drawLine(Offset(x, y), Offset(x + segment, y), trace);
      } else {
        canvas.drawLine(Offset(x, y), Offset(x, y + segment), trace);
      }
      if (i % 5 == 0) {
        canvas.drawCircle(Offset(x, y), 1.8, spark);
      }
    }

    final edge = Paint()
      ..color = _white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(size.width * 0.17, size.height - 54),
      Offset(size.width * 0.83, size.height - 54),
      edge,
    );
  }

  @override
  bool shouldRepaint(covariant _AmbientFieldPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
