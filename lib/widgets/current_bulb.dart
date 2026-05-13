// lib/widgets/current_bulb.dart
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';

class CurrentBulb extends StatefulWidget {
  final double current;
  final double maxCurrent;
  const CurrentBulb({super.key, required this.current, this.maxCurrent = 2.0});

  @override
  State<CurrentBulb> createState() => _CurrentBulbState();
}

class _CurrentBulbState extends State<CurrentBulb>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _anim = Tween<double>(begin: 0, end: widget.current).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(CurrentBulb old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) {
      _anim = Tween<double>(begin: _anim.value, end: widget.current).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
      );
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
      builder: (_, __) {
        final pct = (_anim.value / widget.maxCurrent).clamp(0.0, 1.0);
        final color = _bulbColor(pct);

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: CustomPaint(
                painter: _BulbPainter(pct, color),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_anim.value.toStringAsFixed(3)} A',
              style: RigTheme.monoLarge.copyWith(color: color, fontSize: 18),
            ),
            Text('CURRENT', style: RigTheme.label),
          ],
        );
      },
    );
  }

  Color _bulbColor(double pct) {
    if (pct > 0.80) return RigTheme.alarm;
    if (pct > 0.50) return RigTheme.warning;
    return const Color(0xFFFFE066);
  }
}

class _BulbPainter extends CustomPainter {
  final double pct;
  final Color color;
  _BulbPainter(this.pct, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.48;
    final r = min(size.width, size.height) * 0.30;

    // Outer glow rings
    if (pct > 0.05) {
      for (int i = 3; i >= 1; i--) {
        final glowPaint = Paint()
          ..color = color.withOpacity(0.06 * pct * i)
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, r * 0.4 * i);
        canvas.drawCircle(Offset(cx, cy), r * (1 + 0.4 * i), glowPaint);
      }
    }

    // Bulb body
    final bulbPath = Path();
    bulbPath.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    // Base trapezoid
    final baseW = r * 0.55;
    final baseH = r * 0.45;
    bulbPath.moveTo(cx - baseW * 0.7, cy + r * 0.75);
    bulbPath.lineTo(cx - baseW, cy + r + baseH);
    bulbPath.lineTo(cx + baseW, cy + r + baseH);
    bulbPath.lineTo(cx + baseW * 0.7, cy + r * 0.75);
    bulbPath.close();

    // Fill with gradient
    final grad = RadialGradient(
      center: const Alignment(-0.3, -0.3),
      radius: 0.8,
      colors: [
        color.withOpacity(0.1 + 0.7 * pct),
        color.withOpacity(0.05 + 0.3 * pct),
        RigTheme.surface,
      ],
    );
    canvas.drawPath(
      bulbPath,
      Paint()
        ..shader = grad.createShader(
          Rect.fromCircle(center: Offset(cx, cy), radius: r),
        ),
    );

    // Bulb outline
    canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withOpacity(0.4 + 0.5 * pct));

    // Filament (visible when current flows)
    if (pct > 0.02) {
      final filPaint = Paint()
        ..color = color.withOpacity(0.6 * pct)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final path = Path();
      path.moveTo(cx, cy + r * 0.35);
      path.cubicTo(
          cx - r * 0.2, cy + r * 0.1, cx + r * 0.2, cy - r * 0.1, cx, cy - r * 0.35);
      canvas.drawPath(path, filPaint);

      // Base threads
      final threadPaint = Paint()
        ..color = RigTheme.labelColor
        ..strokeWidth = 1.5;
      for (int i = 0; i < 4; i++) {
        final y = cy + r + baseH * 0.3 + i * r * 0.12;
        canvas.drawLine(
          Offset(cx - baseW * (0.9 - i * 0.05), y),
          Offset(cx + baseW * (0.9 - i * 0.05), y),
          threadPaint,
        );
      }
    }

    // Specular highlight
    final hilightPaint = Paint()
      ..color = Colors.white.withOpacity(0.12 + 0.08 * pct)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx - r * 0.28, cy - r * 0.28),
          width: r * 0.35,
          height: r * 0.2),
      hilightPaint,
    );
  }

  @override
  bool shouldRepaint(_BulbPainter old) =>
      old.pct != pct || old.color != color;
}
