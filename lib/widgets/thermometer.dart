// lib/widgets/thermometer.dart
import 'package:flutter/material.dart';
import '../theme.dart';

class Thermometer extends StatefulWidget {
  final double temp;
  final double minTemp;
  final double maxTemp;
  const Thermometer({
    super.key,
    required this.temp,
    this.minTemp = 0,
    this.maxTemp = 80,
  });

  @override
  State<Thermometer> createState() => _ThermometerState();
}

class _ThermometerState extends State<Thermometer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _anim = Tween<double>(begin: widget.temp, end: widget.temp).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(Thermometer old) {
    super.didUpdateWidget(old);
    if (old.temp != widget.temp) {
      _anim = Tween<double>(begin: _anim.value, end: widget.temp).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
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
        final pct =
            ((_anim.value - widget.minTemp) / (widget.maxTemp - widget.minTemp))
                .clamp(0.0, 1.0);
        final color = _tempColor(pct);

        return Column(
          children: [
            Expanded(
              child: CustomPaint(
                painter: _ThermoPainter(pct, color),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_anim.value.toStringAsFixed(1)}°C',
              style: RigTheme.monoLarge.copyWith(color: color, fontSize: 20),
            ),
            Text('TEMP', style: RigTheme.label),
          ],
        );
      },
    );
  }

  Color _tempColor(double pct) {
    if (pct > 0.75) return RigTheme.alarm;
    if (pct > 0.50) return RigTheme.warning;
    return const Color(0xFF00CFFF);
  }
}

class _ThermoPainter extends CustomPainter {
  final double pct;
  final Color color;
  _ThermoPainter(this.pct, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    const bulbR = 14.0;
    const tubeW = 10.0;
    final tubeTop = 12.0;
    final tubeBottom = size.height - bulbR * 2 - 4;
    final tubeH = tubeBottom - tubeTop;

    // Outer tube
    final outerPaint = Paint()..color = RigTheme.surface;
    final tubeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - tubeW / 2, tubeTop, tubeW, tubeH),
      const Radius.circular(5),
    );
    canvas.drawRRect(tubeRect, outerPaint);

    // Mercury fill
    final fillH = tubeH * pct;
    final fillTop = tubeBottom - fillH;
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    if (fillH > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - tubeW / 2 + 2, fillTop, tubeW - 4, fillH),
          const Radius.circular(3),
        ),
        fillPaint,
      );
    }

    // Glow
    if (pct > 0.5) {
      final glowPaint = Paint()
        ..color = color.withOpacity(0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - tubeW, fillTop - 4, tubeW * 2, fillH + 8),
          const Radius.circular(8),
        ),
        glowPaint,
      );
    }

    // Scale ticks
    final tickPaint = Paint()
      ..color = RigTheme.labelColor
      ..strokeWidth = 1;
    for (int i = 0; i <= 8; i++) {
      final y = tubeTop + tubeH * (1 - i / 8);
      canvas.drawLine(
        Offset(cx + tubeW / 2, y),
        Offset(cx + tubeW / 2 + (i % 4 == 0 ? 8 : 5), y),
        tickPaint,
      );
    }

    // Bulb
    final bulbCenter = Offset(cx, tubeBottom + bulbR + 2);
    canvas.drawCircle(bulbCenter, bulbR, Paint()..color = RigTheme.surface);
    canvas.drawCircle(bulbCenter, bulbR - 2, fillPaint);
    // Bulb glow
    final bglow = Paint()
      ..color = color.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(bulbCenter, bulbR, bglow);
  }

  @override
  bool shouldRepaint(_ThermoPainter old) =>
      old.pct != pct || old.color != color;
}
