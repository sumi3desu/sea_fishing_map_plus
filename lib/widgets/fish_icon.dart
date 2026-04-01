import 'package:flutter/material.dart';

class FishIcon extends StatelessWidget {
  const FishIcon({super.key, this.size = 24, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _FishPainter(c),
      ),
    );
  }
}

class _FishPainter extends CustomPainter {
  _FishPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final sx = size.width / 24.0;
    final sy = size.height / 24.0;
    canvas.save();
    canvas.scale(sx, sy);

    final body = Path()..addOval(const Rect.fromLTWH(3, 6, 13, 12));
    final tail = Path()
      ..moveTo(16, 12)
      ..lineTo(22, 6)
      ..lineTo(22, 18)
      ..close();
    final fin = Path()
      ..moveTo(8, 10)
      ..lineTo(11, 12)
      ..lineTo(8, 14)
      ..close();

    canvas.drawPath(body, paint);
    canvas.drawPath(tail, paint);
    canvas.drawPath(fin, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FishPainter oldDelegate) => oldDelegate.color != color;
}

