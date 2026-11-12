import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:holybeans/domain/extraction_profile.dart';
import 'package:holybeans/domain/flow_guide.dart';
import 'package:holybeans/ui/profiles/profile_editor_model.dart';
import 'package:holybeans/ui/profiles/profile_numbers.dart';
import 'package:holybeans/ui/profiles/profile_point_drag.dart';
import 'package:intl/intl.dart' show NumberFormat;

class ProfilePlot extends StatelessWidget {
  const ProfilePlot({
    super.key,
    required this.profile,
    this.editor,
    this.height = 230,
  });
  final ExtractionProfile profile;
  final ProfileEditorModel? editor;
  final double height;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = _ProfilePainter(
        profile,
        Theme.of(context).colorScheme,
        editor?.active,
        editor?.selected,
        Theme.of(context).textTheme.bodySmall!,
        profileNumber(context),
      );
      final size = Size(constraints.maxWidth, height);
      int? nearest(Offset position) {
        final model = editor;
        if (model == null) return null;
        var best = double.infinity;
        var index = 0;
        for (var i = 0; i < model.points.length; i++) {
          final distance =
              (painter.location(model.points[i], model.active, size) - position)
                  .distance;
          if (distance < best) {
            best = distance;
            index = i;
          }
        }
        return best < 32 ? index : null;
      }

      return RawGestureDetector(
        gestures: {
          if (editor != null)
            ProfilePointDrag:
                GestureRecognizerFactoryWithHandlers<ProfilePointDrag>(
                  ProfilePointDrag.new,
                  (gesture) {
                    gesture.hitsPoint = (position) => nearest(position) != null;
                    gesture.onStart = (e) {
                      final index = nearest(e.localPosition);
                      if (index == null) return;
                      editor!.select(editor!.active, index);
                      editor!.beginDrag();
                    };
                    gesture.onUpdate = (e) {
                      final model = editor!;
                      if (!model.dragging) return;
                      final i = model.selected;
                      final min = i == 0
                          ? 0
                          : model.points[i - 1].elapsedMs + 1;
                      final max = i == model.points.length - 1
                          ? profile.durationMs
                          : model.points[i + 1].elapsedMs - 1;
                      final ms =
                          ((e.localPosition.dx - 34) /
                                  (size.width - 68) *
                                  profile.durationMs)
                              .round()
                              .clamp(min, max);
                      final value =
                          ((height - 28 - e.localPosition.dy) /
                                  (height - 52) *
                                  painter.maximum(model.active))
                              .clamp(0.0, 30.0);
                      model.move(i, ms, value, dragging: true);
                    };
                    gesture.onEnd = (_) => editor!.endDrag();
                    gesture.onCancel = editor!.endDrag;
                  },
                ),
        },
        child: CustomPaint(size: size, painter: painter),
      );
    },
  );
}

class _ProfilePainter extends CustomPainter {
  _ProfilePainter(
    this.profile,
    this.colors,
    this.active,
    this.selected,
    this.textStyle,
    this.number,
  );
  final TextStyle textStyle;
  final NumberFormat number;
  final ExtractionProfile profile;
  final ColorScheme colors;
  final String? active;
  final int? selected;
  double maximum(String key) =>
      (key == 'flow' ? profile.flow : profile.pressure).fold(
        key == 'flow' ? 6.0 : 12.0,
        (m, p) => math.max(m, p.value),
      );
  Offset location(GuidePoint p, String key, Size size) => Offset(
    34 + p.elapsedMs / profile.durationMs * (size.width - 68),
    size.height - 28 - p.value / maximum(key) * (size.height - 52),
  );
  void label(Canvas canvas, String text, Offset offset, Color color) {
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: textStyle.copyWith(fontSize: 10, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(canvas, offset);
    p.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = colors.outlineVariant;
    for (var i = 0; i <= 4; i++) {
      final y = 24 + (size.height - 52) * i / 4;
      canvas.drawLine(Offset(34, y), Offset(size.width - 34, y), grid);
      if (profile.flow.isNotEmpty) {
        label(
          canvas,
          number.format(maximum('flow') * (1 - i / 4)),
          Offset(0, y - 5),
          colors.primary,
        );
      }
      if (profile.pressure.isNotEmpty) {
        label(
          canvas,
          number.format(maximum('pressure') * (1 - i / 4)),
          Offset(size.width - 28, y - 5),
          colors.tertiary,
        );
      }
    }
    if (profile.flow.isNotEmpty) {
      label(canvas, 'g/s', Offset.zero, colors.primary);
    }
    if (profile.pressure.isNotEmpty) {
      label(canvas, 'bar', Offset(size.width - 28, 0), colors.tertiary);
    }
    for (var i = 0; i <= 4; i++) {
      label(
        canvas,
        '${number.format(profile.durationMs / 1000 * i / 4)} s',
        Offset(24 + (size.width - 68) * i / 4, size.height - 19),
        colors.onSurfaceVariant,
      );
    }
    for (final entry in {
      'flow': profile.flow,
      'pressure': profile.pressure,
    }.entries) {
      final color = entry.key == 'flow' ? colors.primary : colors.tertiary;
      final path = Path();
      for (var i = 0; i < entry.value.length; i++) {
        final p = entry.value[i];
        final pos = location(p, entry.key, size);
        if (i == 0 || p.breakBefore) {
          path.moveTo(pos.dx, pos.dy);
        } else {
          path.lineTo(pos.dx, pos.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke,
      );
      if (active == entry.key) {
        for (var i = 0; i < entry.value.length; i++) {
          canvas.drawCircle(
            location(entry.value[i], entry.key, size),
            selected == i ? 7 : 4,
            Paint()..color = color,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ProfilePainter oldDelegate) =>
      oldDelegate.profile != profile ||
      oldDelegate.active != active ||
      oldDelegate.selected != selected ||
      oldDelegate.colors != colors ||
      oldDelegate.number.locale != number.locale ||
      oldDelegate.textStyle != textStyle;
}
