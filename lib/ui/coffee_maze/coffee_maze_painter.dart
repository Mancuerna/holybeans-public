import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:holybeans/domain/coffee_maze.dart';

class CoffeeMazePainter extends CustomPainter {
  CoffeeMazePainter(this.game, {required Listenable repaint})
    : super(repaint: repaint);

  final CoffeeMaze game;
  static const background = Color(0xFF201714);
  static const cream = Color(0xFFFFE3AA);
  static const caramel = Color(0xFFE4A15C);
  static const _spirits = [
    Color(0xFFE87D8C),
    Color(0xFF8FCABB),
    Color(0xFFB4A2DD),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / CoffeeMaze.columns;
    canvas.save();
    canvas.scale(unit);
    final paint = Paint();
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(
          0,
          0,
          CoffeeMaze.columns * 1.0,
          CoffeeMaze.rows * 1.0,
        ),
        const Radius.circular(.5),
      ),
      paint..color = background,
    );
    for (var y = 0; y < CoffeeMaze.rows; y++) {
      for (var x = 0; x < CoffeeMaze.columns; x++) {
        if (game.isOpen(MazeCell(x, y))) continue;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x + .13, y + .13, .74, .74),
          const Radius.circular(.2),
        );
        canvas.drawRRect(rect, paint..color = const Color(0xFF493128));
        canvas.drawRRect(
          rect,
          paint
            ..color = const Color(0xFF80563B)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .045,
        );
        paint.style = PaintingStyle.fill;
      }
    }
    for (final bean in game.beans) {
      canvas.save();
      canvas.translate(bean.x + .5, bean.y + .5);
      canvas.rotate(-.5);
      canvas.drawOval(
        const Rect.fromLTWH(-.1, -.15, .2, .3),
        paint..color = caramel,
      );
      canvas.drawLine(
        const Offset(0, -.08),
        const Offset(0, .08),
        paint
          ..color = background
          ..strokeWidth = .035,
      );
      canvas.restore();
    }
    for (final espresso in game.espressos) {
      _cup(canvas, Offset(espresso.x + .5, espresso.y + .5), paint);
    }
    for (var i = 0; i < game.enemies.length; i++) {
      final enemy = game.enemies[i];
      final frightened = game.caffeine > 0;
      final flashing = game.caffeine < 2 && (game.elapsed * 6).floor().isEven;
      final color = frightened
          ? (flashing ? cream : const Color(0xFF8BBED8))
          : _spirits[i];
      _spirit(canvas, enemy, color, paint, i);
    }
    final player = game.player;
    canvas.save();
    canvas.translate(player.x + .5, player.y + .5);
    canvas.rotate(switch (player.direction) {
      MazeDirection.right => 0,
      MazeDirection.down => math.pi / 2,
      MazeDirection.left => math.pi,
      MazeDirection.up => -math.pi / 2,
    });
    final blink = game.protection > 0 && (game.elapsed * 8).floor().isEven;
    paint.color = blink ? cream.withValues(alpha: .55) : cream;
    final mouth = .14 + (math.sin(game.elapsed * 24).abs() * .45);
    canvas.drawArc(
      const Rect.fromLTWH(-.43, -.38, .86, .76),
      mouth,
      math.pi * 2 - mouth * 2,
      true,
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(-.12, -.29)
        ..cubicTo(-.35, -.1, .04, .08, -.16, .28),
      paint
        ..color = const Color(0xFF926040)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .055,
    );
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(.07, -.22), .052, paint..color = background);
    canvas.restore();
    canvas.restore();
  }

  void _cup(Canvas canvas, Offset center, Paint paint) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.drawCircle(
      Offset.zero,
      .42,
      paint..color = caramel.withValues(alpha: .13),
    );
    canvas.drawOval(
      const Rect.fromLTWH(.12, -.16, .22, .26),
      paint
        ..color = cream
        ..style = PaintingStyle.stroke
        ..strokeWidth = .07,
    );
    paint.style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-.23, -.2, .42, .4),
        const Radius.circular(.1),
      ),
      paint..color = cream,
    );
    canvas.drawOval(
      const Rect.fromLTWH(-.17, -.16, .3, .1),
      paint..color = const Color(0xFF80563B),
    );
    canvas.drawLine(
      const Offset(-.27, .27),
      const Offset(.25, .27),
      paint
        ..color = cream
        ..strokeWidth = .06,
    );
    canvas.restore();
  }

  void _spirit(
    Canvas canvas,
    MazeActor actor,
    Color color,
    Paint paint,
    int index,
  ) {
    canvas.save();
    canvas.translate(
      actor.x + .5,
      actor.y + .5 + math.sin(game.elapsed * 5 + index) * .045,
    );
    final shape = Path()
      ..moveTo(-.35, .32)
      ..lineTo(-.35, -.06)
      ..cubicTo(-.35, -.48, .35, -.48, .35, -.06)
      ..lineTo(.35, .32)
      ..quadraticBezierTo(.23, .14, .12, .32)
      ..quadraticBezierTo(0, .14, -.12, .32)
      ..quadraticBezierTo(-.24, .14, -.35, .32)
      ..close();
    canvas.drawPath(
      shape,
      paint..color = color.withValues(alpha: actor.resting > 0 ? .4 : .95),
    );
    for (final eye in [-.13, .13]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(eye, -.06), width: .16, height: .2),
        paint..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(
          eye + actor.direction.dx * .035,
          -.06 + actor.direction.dy * .035,
        ),
        .047,
        paint..color = background,
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(-.1, -.48)
        ..quadraticBezierTo(-.23, -.6, -.05, -.71)
        ..quadraticBezierTo(.06, -.82, -.03, -.9),
      paint
        ..color = color.withValues(alpha: .5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .055
        ..strokeCap = StrokeCap.round,
    );
    paint.style = PaintingStyle.fill;
    canvas.restore();
  }

  @override
  bool shouldRepaint(CoffeeMazePainter oldDelegate) => oldDelegate.game != game;
}
