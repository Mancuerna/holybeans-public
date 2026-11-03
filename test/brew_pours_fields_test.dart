import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_pours_draft.dart';
import 'package:holybeans/ui/brews/brew_pours_fields.dart';

void main() {
  testWidgets(
    'counts are optional, bounded and independent of folded measurements',
    (tester) async {
      final draft = BrewPoursDraft();
      addTearDown(draft.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('es'),
          home: Scaffold(
            body: ListView(children: [BrewPoursFields(draft: draft)]),
          ),
        ),
      );
      expect(find.text('Sin registrar'), findsNWidgets(2));
      expect(find.text('Detalles de blooms y vertidos'), findsNothing);
      Finder dropdown(String label) => find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<int> &&
            w.decoration.labelText == label,
      );
      await tester.tap(dropdown('Blooms'));
      await tester.pumpAndSettle();
      final field = tester.widget<DropdownButton<int>>(
        find.descendant(
          of: dropdown('Blooms'),
          matching: find.byType(DropdownButton<int>),
        ),
      );
      expect(field.items!.map((v) => v.value), [-1, 0, 1, 2, 3]);
      await tester.ensureVisible(find.text('2').last);
      await tester.tap(find.text('2').last);
      await tester.pumpAndSettle();
      await tester.tap(dropdown('Vertidos'));
      await tester.pumpAndSettle();
      final pours = tester.widget<DropdownButton<int>>(
        find.descendant(
          of: dropdown('Vertidos'),
          matching: find.byType(DropdownButton<int>),
        ),
      );
      expect(pours.items!.map((v) => v.value), [
        -1,
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
      ]);
      await tester.ensureVisible(find.text('1').last);
      await tester.tap(find.text('1').last);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextFormField, 'Agua añadida (g)'),
        findsNothing,
      );
      await tester.tap(find.text('Detalles de blooms y vertidos'));
      await tester.pumpAndSettle();
      final durationBounds = tester.getRect(
        find.byKey(const ValueKey('bloom-1-duration')),
      );
      final restBounds = tester.getRect(
        find.byKey(const ValueKey('bloom-1-rest')),
      );
      expect(restBounds.top, greaterThan(durationBounds.bottom));
      final water =
          find
              .descendant(
                of: find.byKey(const ValueKey('bloom-1-water')),
                matching: find.byType(TextFormField),
              )
              .evaluate()
              .isEmpty
          ? find.byKey(const ValueKey('bloom-1-water'))
          : find.descendant(
              of: find.byKey(const ValueKey('bloom-1-water')),
              matching: find.byType(TextFormField),
            );
      await tester.enterText(water, '36,5');
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('bloom-1-duration')),
          matching: find.byType(TextFormField),
        ),
        '8',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('bloom-1-rest')),
          matching: find.byType(TextFormField),
        ),
        '30',
      );
      final phase = draft.value.phases.single;
      expect(phase.waterGrams, 36.5);
      expect(phase.durationSeconds, 8);
      expect(phase.restSeconds, 30);
      await tester.ensureVisible(find.text('Detalles de blooms y vertidos'));
      await tester.tap(find.text('Detalles de blooms y vertidos'));
      await tester.pumpAndSettle();
      expect(draft.value.phases.single.restSeconds, 30);
      await tester.ensureVisible(dropdown('Blooms'));
      await tester.tap(dropdown('Blooms'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0').last);
      await tester.pumpAndSettle();
      expect(draft.value.bloomCount, 0);
      expect(draft.value.phases, isEmpty);
      expect(draft.value.pourCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('old bloom time stays editable inside folded details', (
    tester,
  ) async {
    final draft = BrewPoursDraft();
    final bloom = TextEditingController(text: '45');
    addTearDown(draft.dispose);
    addTearDown(bloom.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('es'),
        home: Scaffold(
          body: ListView(
            children: [BrewPoursFields(draft: draft, bloomTime: bloom)],
          ),
        ),
      ),
    );
    expect(find.text('Tiempo total de bloom (s)'), findsNothing);
    expect(bloom.text, '45');
    await tester.tap(find.text('Detalles de blooms y vertidos'));
    await tester.pumpAndSettle();
    final total = find.widgetWithText(
      TextFormField,
      'Tiempo total de bloom (s)',
    );
    expect(tester.widget<TextFormField>(total).controller!.text, '45');
    expect(draft.bloomCount, isNull);
    expect(draft.value.phases, isEmpty);
    await tester.enterText(total, '40');
    await tester.tap(find.text('Detalles de blooms y vertidos'));
    await tester.pumpAndSettle();
    expect(bloom.text, '40');
    draft.setCount(BrewPourKind.bloom, 0);
    await tester.pumpAndSettle();
    expect(find.text('Detalles de blooms y vertidos'), findsNothing);
    draft.setCount(BrewPourKind.bloom, 1);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detalles de blooms y vertidos'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(total).controller!.text, '40');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('each phase shows its flow as it is typed, and in details', (
    tester,
  ) async {
    final draft = BrewPoursDraft()..setCount(BrewPourKind.pour, 1);
    addTearDown(draft.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('es'),
        home: Scaffold(
          body: ListView(children: [BrewPoursFields(draft: draft)]),
        ),
      ),
    );
    await tester.tap(find.text('Detalles de blooms y vertidos'));
    await tester.pumpAndSettle();
    final flow = find.byKey(const ValueKey('pour-1-flow'));
    expect(flow, findsNothing);
    await tester.enterText(find.byKey(const ValueKey('pour-1-water')), '100');
    await tester.pump();
    expect(flow, findsNothing, reason: 'no time yet');
    await tester.enterText(find.byKey(const ValueKey('pour-1-duration')), '12');
    await tester.pump();
    expect(tester.widget<Text>(flow).data, 'Caudal: 8.3 g/s');

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('es'),
        home: Scaffold(body: BrewPourDetails(pours: draft.value)),
      ),
    );
    await tester.tap(find.text('Detalles de blooms y vertidos'));
    await tester.pumpAndSettle();
    expect(find.text('100 g, Vertido: 12 s, 8.3 g/s'), findsOneWidget);
  });

  testWidgets('count controls fit large text', (tester) async {
    final draft = BrewPoursDraft()
      ..setCount(BrewPourKind.bloom, 2)
      ..setCount(BrewPourKind.pour, 10);
    addTearDown(draft.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SizedBox(
              width: 320,
              child: ListView(children: [BrewPoursFields(draft: draft)]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bloom and pour details'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('bloom-1-rest')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
