// lib/widgets/rpm_gauge.dart
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';

class RpmGauge extends StatefulWidget {
  final double rpm;
  final double maxRpm;
  const RpmGauge({super.key, required this.rpm, this.maxRpm = 210});

  @override
  State<RpmGauge> createState() => _RpmGaugeState();
}

class _RpmGaugeState extends State<RpmGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  double _prev = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _anim = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(RpmGauge old) {
    super.didUpdateWidget(old);
    if (old.rpm != widget.rpm) {
      _anim = Tween<double>(begin: _prev, end: widget.rpm).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
      );
      _prev = widget.rpm;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => CustomPaint(
        painter: _GaugePainter(_anim.value, widget.maxRpm),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 60),
              Text(
                _anim.value.toStringAsFixed(0),
                style: RigTheme.monoLarge.copyWith(
                  fontSize: 36,
                  color: _rpmColor(_anim.value, widget.maxRpm),
                ),
              ),
              Text('RPM', style: RigTheme.label),
            ],
          ),
        ),
      ),
    );
  }

  Color _rpmColor(double v, double max) {
    final pct = v / max;
    if (pct > 0.85) return RigTheme.alarm;
    if (pct > 0.65) return RigTheme.warning;
    return RigTheme.accent;
  }
}

class _GaugePainter extends CustomPainter {
  final double rpm;
  final double maxRpm;
  _GaugePainter(this.rpm, this.maxRpm);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.62;
    final r = size.width * 0.42;

    const startAngle = pi * 0.75;
    const sweepAngle = pi * 1.5;

    // Track background
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..color = RigTheme.surface;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      startAngle, sweepAngle, false, bgPaint,
    );

    // Colored arc segments: green → orange → red
    _drawArcSegment(canvas, cx, cy, r, startAngle, sweepAngle * 0.65,
        RigTheme.accent, 14);
    _drawArcSegment(canvas, cx, cy, r, startAngle + sweepAngle * 0.65,
        sweepAngle * 0.20, RigTheme.warning, 14);
    _drawArcSegment(canvas, cx, cy, r, startAngle + sweepAngle * 0.85,
        sweepAngle * 0.15, RigTheme.alarm, 14);

    // Value fill (animated)
    final filled = sweepAngle * (rpm / maxRpm).clamp(0, 1);
    if (filled > 0) {
      final fillColor = _fillColor(rpm / maxRpm);
      final fillPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..color = fillColor.withOpacity(0.9);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        startAngle, filled, false, fillPaint,
      );
    }

    // Tick marks
    final tickPaint = Paint()
      ..color = RigTheme.labelColor
      ..strokeWidth = 1.5;
    for (int i = 0; i <= 10; i++) {
      final angle = startAngle + sweepAngle * (i / 10);
      final outer = Offset(cx + (r + 8) * cos(angle), cy + (r + 8) * sin(angle));
      final inner = Offset(cx + (r - 8) * cos(angle), cy + (r - 8) * sin(angle));
      canvas.drawLine(inner, outer, tickPaint);
    }

    // Needle
    final needleAngle = startAngle + sweepAngle * (rpm / maxRpm).clamp(0, 1);
    final needlePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final tip = Offset(
      cx + (r - 18) * cos(needleAngle),
      cy + (r - 18) * sin(needleAngle),
    );
    final base = Offset(cx - 18 * cos(needleAngle), cy - 18 * sin(needleAngle));
    canvas.drawLine(base, tip, needlePaint);

    // Center cap
    canvas.drawCircle(Offset(cx, cy), 8,
        Paint()..color = RigTheme.accent);
    canvas.drawCircle(Offset(cx, cy), 4,
        Paint()..color = RigTheme.bg);
  }

  void _drawArcSegment(Canvas canvas, double cx, double cy, double r,
      double start, double sweep, Color color, double width) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt
      ..color = color.withOpacity(0.25);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      start, sweep, false, paint,
    );
  }

  Color _fillColor(double pct) {
    if (pct > 0.85) return RigTheme.alarm;
    if (pct > 0.65) return RigTheme.warning;
    return RigTheme.accent;
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.rpm != rpm || old.maxRpm != maxRpm;
}
