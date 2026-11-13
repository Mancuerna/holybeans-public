import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/extraction_profile.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/profiles/profile_editor_page.dart';
import 'package:holybeans/ui/profiles/profile_plot.dart';

import 'helpers/ui_test_support.dart';

Finder field(String label) => find.ancestor(
  of: find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  ),
  matching: find.byType(TextFormField),
);

void main() {
  for (final locale in ['es', 'en']) {
    for (final channel in ['flow', 'pressure']) {
      testWidgets('$locale $channel point inputs are compact and spaced', (
        tester,
      ) async {
        final points = [
          (elapsedMs: 0, value: 0.0, breakBefore: false),
          (elapsedMs: 20383, value: 3.132889308286489, breakBefore: false),
          (elapsedMs: 20384, value: 0.0, breakBefore: false),
        ];
        final profile = ExtractionProfile.example('p', 'Example').copyWith(
          primary: channel,
          flow: channel == 'flow' ? points : null,
          pressure: channel == 'pressure' ? points : null,
        );
        await tester.pumpWidget(
          localizedApp(
            theme: AppTheme.light(),
            locale: Locale(locale),
            home: ProfileEditorPage(profile: profile, onSave: (_) async {}),
          ),
        );
        await tester.pumpAndSettle();
        final model = tester
            .widget<ProfilePlot>(find.byType(ProfilePlot))
            .editor!;
        final row = find.widgetWithText(ListTile, '2');
        await tester.scrollUntilVisible(
          row,
          250,
          scrollable: verticalScrollable(find.byType(ProfileEditorPage)),
        );
        await Scrollable.ensureVisible(tester.element(row), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();
        final time = field(locale == 'es' ? 'Tiempo (s)' : 'Time (s)');
        final value = field(channel == 'flow' ? 'g/s' : 'bar');
        expect(
          tester.widget<TextFormField>(time).controller!.text,
          locale == 'es' ? '20,38' : '20.38',
        );
        expect(
          tester.widget<TextFormField>(value).controller!.text,
          locale == 'es' ? '3,13' : '3.13',
        );
        expect(
          tester.getTopLeft(value).dy - tester.getBottomLeft(time).dy,
          greaterThanOrEqualTo(16),
        );
        final savePoint = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        );
        await tester.tap(savePoint);
        await tester.pumpAndSettle();
        expect(model.points[1], points[1]);
        expect(model.canUndo, isFalse);
        // Editing only the value must preserve the original millisecond time.
        await Scrollable.ensureVisible(tester.element(row), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();
        await tester.enterText(value, locale == 'es' ? '4,25' : '4.25');
        await tester.tap(savePoint);
        await tester.pumpAndSettle();
        expect(model.points[1].elapsedMs, 20383);
        expect(model.points[1].value, 4.25);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final (size, scale, sameRow) in [
    (const Size(360, 800), 1.0, true),
    (const Size(320, 800), 1.0, false),
    (const Size(360, 800), 2.0, false),
  ]) {
    testWidgets('duration adapts to $size with text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        localizedApp(
          theme: AppTheme.light(),
          locale: const Locale('es'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: ProfileEditorPage(
            profile: ExtractionProfile.example('p', 'Example'),
            onSave: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dose = tester.getRect(field('Dosis (g)'));
      final temperature = tester.getRect(field('Temperatura (°C)'));
      final duration = tester.getRect(field('Duración (s)'));
      if (sameRow) {
        expect(dose.top, temperature.top);
        expect(dose.top, duration.top);
        expect(duration.left - temperature.right, greaterThanOrEqualTo(12));
      } else {
        expect(duration.top, greaterThan(dose.bottom));
      }
      expect(duration.right, lessThanOrEqualTo(size.width - 16));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'duration scales both curves, supports undo, and saves pending input',
    (tester) async {
      final original = ExtractionProfile.example('p', 'Example');
      ExtractionProfile? saved;
      await tester.pumpWidget(
        localizedApp(
          theme: AppTheme.light(),
          locale: const Locale('es'),
          home: ProfileEditorPage(
            profile: original,
            onSave: (p) async => saved = p,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final duration = field('Duración (s)');
      await tester.enterText(duration, '45,5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final model = tester
          .widget<ProfilePlot>(find.byType(ProfilePlot))
          .editor!;
      expect(model.profile.durationMs, 45500);
      for (final (before, after) in [
        (original.flow, model.profile.flow),
        (original.pressure, model.profile.pressure),
      ]) {
        for (var i = 0; i < before.length; i++) {
          expect(
            after[i].elapsedMs,
            (before[i].elapsedMs * 45500 / 30000).round(),
          );
          expect(after[i].value, before[i].value);
        }
      }
      final undo = find.byIcon(Icons.undo);
      await tester.scrollUntilVisible(
        undo,
        200,
        scrollable: verticalScrollable(find.byType(ProfileEditorPage)),
      );
      await tester.tap(undo);
      await tester.pumpAndSettle();
      expect(model.profile.durationMs, 30000);
      await tester.tap(find.byIcon(Icons.redo));
      await tester.pumpAndSettle();
      expect(model.profile.durationMs, 45500);
      await tester.scrollUntilVisible(
        duration,
        -200,
        scrollable: verticalScrollable(find.byType(ProfileEditorPage)),
      );
      expect(tester.widget<TextFormField>(duration).controller!.text, '45,5');
      await tester.enterText(duration, '60');
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();
      expect(saved?.durationMs, 60000);
      expect(saved?.flow.last.elapsedMs, 60000);
      expect(saved?.pressure.last.elapsedMs, 60000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid duration and colliding point times cannot be saved', (
    tester,
  ) async {
    ExtractionProfile? saved;
    final original = ExtractionProfile.example('p', 'Example').copyWith(
      flow: [
        (elapsedMs: 0, value: 0.0, breakBefore: false),
        (elapsedMs: 1, value: 1.0, breakBefore: false),
        (elapsedMs: 30000, value: 0.0, breakBefore: false),
      ],
    );
    await tester.pumpWidget(
      localizedApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        home: ProfileEditorPage(
          profile: original,
          onSave: (p) async => saved = p,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final duration = field('Duration (s)');
    for (final invalid in ['', '0', '601', 'NaN', '1']) {
      await tester.enterText(duration, invalid);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(
        tester.widget<ProfilePlot>(find.byType(ProfilePlot)).profile.durationMs,
        30000,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.enterText(duration, '60');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(saved?.durationMs, 60000);
  });
}
