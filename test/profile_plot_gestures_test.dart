import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/extraction_profile.dart';
import 'package:holybeans/ui/profiles/profile_editor_model.dart';
import 'package:holybeans/ui/profiles/profile_plot.dart';

import 'helpers/ui_test_support.dart';

void main() {
  for (final channel in ['flow', 'pressure']) {
    testWidgets('$channel point owns vertical drags and one undo restores it', (
      tester,
    ) async {
      final original = ExtractionProfile.example('p', 'Example');
      final model = ProfileEditorModel(original)..select(channel, 2);
      final scroll = ScrollController();
      addTearDown(model.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        localizedApp(
          home: Scaffold(
            body: ListView(
              controller: scroll,
              children: [
                const SizedBox(height: 80),
                ListenableBuilder(
                  listenable: model,
                  builder: (_, _) =>
                      ProfilePlot(profile: model.profile, editor: model),
                ),
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      );
      final box = tester.getRect(find.byType(ProfilePlot));
      final point = model.points[2];
      final start =
          box.topLeft +
          Offset(
            34 + point.elapsedMs / original.durationMs * (box.width - 68),
            230 - 28 - point.value / (channel == 'flow' ? 6 : 12) * (230 - 52),
          );
      final gesture = await tester.startGesture(start);
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, -4));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(model.points[2].value, greaterThan(point.value));
      expect(model.points[2].elapsedMs, point.elapsedMs);
      model.undo();
      expect(model.profile.encode(), original.encode());
      expect(model.canUndo, isFalse);
      model.redo();
      expect(model.points[2].value, greaterThan(point.value));
      // Empty chart space continues to scroll the surrounding page.
      await tester.dragFrom(
        box.topLeft + const Offset(150, 40),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(model.dragging, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
