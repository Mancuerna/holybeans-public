import 'package:flutter/material.dart';
import 'package:holybeans/ui/core/motion.dart';

Future<bool> validateAndReveal(FormState form) async {
  final errors = form.validateGranularly();
  if (errors.isEmpty) return true;
  // Lay out error labels before locating the first invalid field.
  await WidgetsBinding.instance.endOfFrame;
  if (!form.mounted) return false;
  final ordered = errors.where((field) => field.mounted).toList()
    ..sort((a, b) {
      double top(FormFieldState<Object?> field) {
        final box = field.context.findRenderObject() as RenderBox;
        return box.localToGlobal(Offset.zero).dy;
      }

      return top(a).compareTo(top(b));
    });
  if (ordered.isEmpty) return false;
  final field = ordered.first;
  await Scrollable.ensureVisible(
    field.context,
    alignment: 0.2,
    duration: motionDuration(field.context, const Duration(milliseconds: 200)),
  );
  if (!field.mounted) return false;
  void focusInput(Element element) {
    if (element.widget case EditableText(:final focusNode)) {
      focusNode.requestFocus();
    } else {
      element.visitChildren(focusInput);
    }
  }

  (field.context as Element).visitChildren(focusInput);
  return false;
}
