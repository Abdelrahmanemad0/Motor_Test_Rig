// lib/widgets/gyro_3d.dart
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';

class Gyro3D extends StatefulWidget {
  final double gx, gy, gz;
  const Gyro3D({super.key, required this.gx, required this.gy, required this.gz});

  @override
  State<Gyro3D> createState() => _Gyro3DState();
}

class _Gyro3DState extends State<Gyro3D> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  // Accumulated rotation angles (integrated from gyro rate)
  double _rx = 0, _ry = 0, _rz = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..repeat();
    _ctrl.addListener(_integrate);
  }

  void _integrate() {
    const dt = 0.016; // ~60 fps
    setState(() {
      _rx += widget.gx * dt;
      _ry += widget.gy * dt;
      _rz += widget.gz * dt;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            painter: _CubePainter(_rx, _ry, _rz),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _axis('X', widget.gx, const Color(0xFFFF4444)),
            _axis('Y', widget.gy, const Color(0xFF44FF88)),
            _axis('Z', widget.gz, const Color(0xFF44AAFF)),
          ],
        ),
        const SizedBox(height: 4),
        Text('GYRO (rad/s)', style: RigTheme.label),
      ],
    );
  }

  Widget _axis(String label, double val, Color color) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
              text: '$label:',
              style: RigTheme.label.copyWith(color: color, fontSize: 10)),
          TextSpan(
              text: val.toStringAsFixed(3),
              style: RigTheme.monoLarge.copyWith(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}

class _CubePainter extends CustomPainter {
  final double rx, ry, rz;
  _CubePainter(this.rx, this.ry, this.rz);

  // Rotate a 3D point
  List<double> _rotate(double x, double y, double z) {
    // Rotate around X
    double y1 = y * cos(rx) - z * sin(rx);
    double z1 = y * sin(rx) + z * cos(rx);
    // Rotate around Y
    double x2 = x * cos(ry) + z1 * sin(ry);
    double z2 = -x * sin(ry) + z1 * cos(ry);
    // Rotate around Z
    double x3 = x2 * cos(rz) - y1 * sin(rz);
    double y3 = x2 * sin(rz) + y1 * cos(rz);
    return [x3, y3, z2];
  }

  Offset _project(double x, double y, double z, double cx, double cy) {
    const fov = 300.0;
    final scale = fov / (fov + z + 1.5);
    return Offset(cx + x * scale * 55, cy + y * scale * 55);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Unit cube vertices
    const verts = [
      [-1.0, -1.0, -1.0], [1.0, -1.0, -1.0], [1.0, 1.0, -1.0],
      [-1.0, 1.0, -1.0], [-1.0, -1.0, 1.0], [1.0, -1.0, 1.0],
      [1.0, 1.0, 1.0], [-1.0, 1.0, 1.0],
    ];

    // Faces: [vertex indices, color]
    final faces = [
      [0, 1, 2, 3], // back
      [4, 5, 6, 7], // front
      [0, 1, 5, 4], // bottom
      [2, 3, 7, 6], // top
      [0, 3, 7, 4], // left
      [1, 2, 6, 5], // right
    ];

    final faceColors = [
      const Color(0xFF1A3A2A),
      RigTheme.accent.withOpacity(0.6),
      const Color(0xFF1A2A3A),
      const Color(0xFF2A3A1A),
      const Color(0xFF3A2A1A),
      const Color(0xFF2A1A3A),
    ];

    // Project all vertices
    final projected = verts.map((v) {
      final r = _rotate(v[0], v[1], v[2]);
      return _project(r[0], r[1], r[2], cx, cy);
    }).toList();

    // Get rotated Z for depth sorting
    final rotatedZ = verts.map((v) {
      final r = _rotate(v[0], v[1], v[2]);
      return r[2];
    }).toList();

    // Sort faces by average Z (painter's algorithm)
    final sortedFaces = List.generate(faces.length, (i) => i)
      ..sort((a, b) {
        final za = faces[a].map((vi) => rotatedZ[vi]).reduce((s, e) => s + e) / 4;
        final zb = faces[b].map((vi) => rotatedZ[vi]).reduce((s, e) => s + e) / 4;
        return za.compareTo(zb);
      });

    // Draw faces
    for (final fi in sortedFaces) {
      final face = faces[fi];
      final path = Path()
        ..moveTo(projected[face[0]].dx, projected[face[0]].dy);
      for (int i = 1; i < face.length; i++) {
        path.lineTo(projected[face[i]].dx, projected[face[i]].dy);
      }
      path.close();

      canvas.drawPath(path, Paint()..color = faceColors[fi]);
      canvas.drawPath(
        path,
        Paint()
          ..color = RigTheme.accent.withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    // Axis arrows
    _drawAxis(canvas, cx, cy, 1, 0, 0, const Color(0xFFFF4444), 'X');
    _drawAxis(canvas, cx, cy, 0, 1, 0, const Color(0xFF44FF88), 'Y');
    _drawAxis(canvas, cx, cy, 0, 0, 1, const Color(0xFF44AAFF), 'Z');
  }

  void _drawAxis(Canvas canvas, double cx, double cy, double ax, double ay,
      double az, Color color, String label) {
    const len = 1.8;
    final r = _rotate(ax * len, ay * len, az * len);
    final tip = _project(r[0], r[1], r[2], cx, cy);
    final origin = Offset(cx, cy);

    canvas.drawLine(
      origin,
      tip,
      Paint()
        ..color = color.withOpacity(0.7)
        ..strokeWidth = 1.5,
    );

    final tp = TextPainter(
      text: TextSpan(
          text: label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, tip.translate(-5, -5));
  }

  @override
  bool shouldRepaint(_CubePainter old) =>
      old.rx != rx || old.ry != ry || old.rz != rz;
}
