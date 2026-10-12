import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/jarvis_theme.dart';
import '../models/assistant_status.dart';

/// Animated circular assistant visualizer.
///
/// Budget phones ke liye halka rakha hai: ek repeating AnimationController aur
/// do vector draws (core + arcs). Koi ImageFiltered/blur nahi — blur hi
/// low-end devices par frame drop karata hai. `level` mic ka sound level hai,
/// listening ke dauran core ko pulse karta hai.
class JarvisOrb extends StatefulWidget {
  const JarvisOrb({
    super.key,
    required this.status,
    this.level = 0,
    this.size = 190,
  });

  final AssistantStatus status;
  final double level;
  final double size;

  @override
  State<JarvisOrb> createState() => _JarvisOrbState();
}

class _JarvisOrbState extends State<JarvisOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (6000 / _speedFor(widget.status)).round()),
  );

  @override
  void initState() {
    super.initState();
    _spin.repeat();
  }

  @override
  void didUpdateWidget(JarvisOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      // Status ke saath spin ki raftaar badalti hai (listening tez, error dheema).
      _spin.duration =
          Duration(milliseconds: (6000 / _speedFor(widget.status)).round());
    }
  }

  static double _speedFor(AssistantStatus status) => switch (status) {
        AssistantStatus.listening => 1.0,
        AssistantStatus.thinking => 2.2,
        AssistantStatus.speaking => 1.6,
        AssistantStatus.error => 0.4,
        _ => 0.55,
      };

  static Color _accentFor(AssistantStatus status) => switch (status) {
        AssistantStatus.idle => JarvisPalette.blue,
        AssistantStatus.listening => JarvisPalette.cyan,
        AssistantStatus.thinking => JarvisPalette.cyan,
        AssistantStatus.speaking || AssistantStatus.success =>
          JarvisPalette.success,
        AssistantStatus.error => JarvisPalette.error,
      };

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool active = widget.status.isBusy;
    final Color accent = _accentFor(widget.status);
    return AnimatedBuilder(
      animation: _spin,
      builder: (BuildContext context, Widget? child) {
        final double t = _spin.value;
        final double pulse = active
            ? 0.5 +
                0.5 * math.sin(t * 2 * math.pi * 3) +
                (widget.level.clamp(0, 12).toDouble() / 24)
            : 0.12;
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _OrbPainter(
              t: t,
              accent: accent,
              pulse: pulse,
              active: active,
              rings: widget.status == AssistantStatus.thinking ? 3 : 2,
            ),
            child: Center(
              child: Text(
                widget.status.shortLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter({
    required this.t,
    required this.accent,
    required this.pulse,
    required this.active,
    required this.rings,
  });

  final double t;
  final Color accent;
  final double pulse;
  final bool active;
  final int rings;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = math.min(size.width, size.height) / 2;

    final Paint thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = JarvisPalette.gridLine;
    canvas.drawCircle(c, r - 1, thin);

    final Paint core = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: <Color>[
          accent.withValues(alpha: (0.55 + 0.35 * pulse).clamp(0.0, 1.0).toDouble()),
          accent.withValues(alpha: 0.06),
        ],
        stops: const <double>[0.0, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r * 0.55));
    canvas.drawCircle(c, r * (0.30 + 0.09 * pulse), core);

    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = accent.withValues(alpha: active ? 0.95 : 0.45);
    for (int i = 0; i < rings; i++) {
      final double radius = r * (0.52 + 0.16 * i);
      final double sweep = math.pi * (0.35 + 0.25 * i) + pulse * 0.4;
      final double start = t * 2 * math.pi * (i.isEven ? 1 : -1.6) + i;
      arc.strokeWidth = i == 0 ? 3.2 : 1.8;
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: radius), start, sweep, false, arc);
    }

    // HUD tick marks — static, isliye mehenge nahi.
    final Paint tick = Paint()
      ..color = JarvisPalette.gridLine
      ..strokeWidth = 1.4;
    for (int i = 0; i < 24; i++) {
      final double a = i / 24 * 2 * math.pi;
      final Offset dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * (r - 6), c + dir * (r - 12), tick);
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.t != t ||
      old.accent != accent ||
      old.pulse != pulse ||
      old.active != active ||
      old.rings != rings;
}
