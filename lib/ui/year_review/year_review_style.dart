import 'dart:math' as math;

import 'package:flutter/material.dart';

const yearInk = Color(0xff321c29);
const yearPaper = Color(0xfffff6e8);
const yearWine = Color(0xff782b45);
const yearLime = Color(0xffd8ed91);
const yearLilac = Color(0xffdfd5ef);

class YearBackdrop extends StatelessWidget {
  const YearBackdrop({
    super.key,
    required this.child,
    this.color = yearPaper,
    this.art = 0,
  });
  final Widget child;
  final Color color;
  final int art;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _YearArt(art))),
        child,
      ],
    ),
  );
}

class _YearArt extends CustomPainter {
  const _YearArt(this.variant);
  final int variant;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = yearWine.withValues(alpha: .09)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final center = Offset(size.width + 24, size.height * .22);
    for (var i = 0; i < 6; i++) {
      canvas.drawCircle(center, 42 + i * 22, paint);
    }
    canvas.save();
    canvas.translate(size.width * .88, size.height * .86);
    canvas.rotate(variant.isEven ? -.3 : .3);
    final path = Path();
    for (var i = 0; i < 32; i++) {
      final angle = i * math.pi / 16;
      final radius = i.isEven ? 80.0 : 62.0;
      final point = Offset(math.cos(angle), math.sin(angle)) * radius;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint..style = PaintingStyle.fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_YearArt oldDelegate) => variant != oldDelegate.variant;
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
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value, style: yearHeadline(48)),
      Text(label, style: const TextStyle(color: yearInk, fontSize: 15)),
    ],
  );
}

class YearBadge extends StatelessWidget {
  const YearBadge(this.text, {super.key, this.filled = false});
  final String text;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: filled ? yearInk : yearPaper.withValues(alpha: .65),
      border: Border.all(color: yearInk, width: 1.2),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: 'Plex',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: filled ? yearPaper : yearInk,
      ),
    ),
  );
}
