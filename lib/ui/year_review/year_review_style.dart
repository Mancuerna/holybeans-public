import 'package:flutter/material.dart';

const yearInk = Color(0xff321c29);
const yearPaper = Color(0xfffff6e8);
const yearWine = Color(0xff782b45);
const yearLime = Color(0xffd8ed91);
const yearLilac = Color(0xffdfd5ef);

class YearBackdrop extends StatelessWidget {
  const YearBackdrop({super.key, required this.child, this.color = yearPaper});
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _YearArt())),
        child,
      ],
    ),
  );
}

class _YearArt extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = yearWine.withValues(alpha: .07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 25;
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(size.width + 35, size.height * .22),
        90 + i * 42,
        paint,
      );
    }
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(20, size.height * .88),
        width: 170,
        height: 240,
      ),
      paint
        ..color = yearWine.withValues(alpha: .04)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_YearArt oldDelegate) => false;
}

TextStyle yearHeadline(double size) => TextStyle(
  fontFamily: 'PlexCondensed',
  fontWeight: FontWeight.w700,
  fontSize: size,
  height: 1.02,
  letterSpacing: -1,
  color: yearInk,
);

class YearMetric extends StatelessWidget {
  const YearMetric({super.key, required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: yearHeadline(48)),
      Text(label, style: const TextStyle(color: yearInk, fontSize: 15)),
    ],
  );
}
