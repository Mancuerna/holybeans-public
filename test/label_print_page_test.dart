import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/label_output_preferences.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/domain/label_template.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/labels/label_print_page.dart';
import 'package:holybeans/ui/labels/label_renderer.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/fake_label_printer.dart';

const coffee = Coffee(
  id: 'c',
  name: 'Café Sidama',
  roaster: 'Roaster',
  isFavorite: false,
  isDecaf: false,
  createdAtMs: 0,
  updatedAtMs: 0,
);
const lot = CoffeeLot(
  id: 'l',
  coffeeId: 'c',
  roastDate: '2026-10-20',
  createdAtMs: 0,
  updatedAtMs: 0,
);

void main() {
  setUpAll(initializeDateFormatting);
  late AppDatabase db;
  late FakeLabelPrinter printer;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    printer = FakeLabelPrinter();
  });
  tearDown(() async {
    printer.dispose();
    await db.close();
  });

  Future<void> mount(
    WidgetTester tester, {
    bool multiple = false,
    List<FrozenPortion> portions = const [],
    String locale = 'en',
    List<FakeLabelPrinter> others = const [],
    List<LabelTemplate> templates = const [],
    LabelOutputPreferences? outputPreferences,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LabelPrintPage(
          coffee: coffee,
          components: const [],
          lots: [
            lot,
            if (multiple)
              const CoffeeLot(
                id: 'l2',
                coffeeId: 'c',
                roastDate: '2026-10-21',
                createdAtMs: 0,
                updatedAtMs: 0,
              ),
          ],
          portions: portions,
          templates: templates,
          settings: ShareTemplateSettings(db),
          printer: printer,
          outputPreferences: outputPreferences,
          otherPrinters: others,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, String key) async {
    await tester.scrollUntilVisible(
      find.byKey(ValueKey(key)),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  for (final model in LabelPrinterModel.values.where(
    (m) => m != LabelPrinterModel.d110,
  )) {
    testWidgets(
      'switching to ${model.label} replaces paper, preview and print target',
      (tester) async {
        final b1 = FakeLabelPrinter(model: model);
        addTearDown(b1.dispose);
        await printer.connect();
        await mount(tester, others: [b1]);
        expect(
          tester
              .widget<DropdownButton<LabelPaper>>(
                find.descendant(
                  of: find.byKey(const ValueKey('label-paper-d110')),
                  matching: find.byType(DropdownButton<LabelPaper>),
                ),
              )
              .items!
              .every((item) => item.value!.model == LabelPrinterModel.d110),
          isTrue,
        );
        await tester.tap(find.byKey(const ValueKey(LabelPrinterModel.d110)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Niimbot ${model.label}').last);
        await tester.pumpAndSettle();
        expect(printer.connected, isFalse);
        final b1Paper = tester.widget<DropdownButtonFormField<LabelPaper>>(
          find.byKey(ValueKey('label-paper-${model.name}')),
        );
        expect(b1Paper.initialValue, model.defaultPaper);
        expect(
          tester
              .widget<DropdownButton<LabelPaper>>(
                find.descendant(
                  of: find.byKey(ValueKey('label-paper-${model.name}')),
                  matching: find.byType(DropdownButton<LabelPaper>),
                ),
              )
              .items!
              .every((item) => item.value!.model == model),
          isTrue,
        );
        await reveal(tester, 'label-preview');
        expect(
          tester
              .widget<LabelPreview>(find.byKey(const ValueKey('label-preview')))
              .layout
              .paper,
          model.defaultPaper,
        );
        await reveal(tester, 'label-print');
        expect(
          tester
              .widget<FilledButton>(find.byKey(const ValueKey('label-print')))
              .onPressed,
          isNull,
        );
        expect(b1.jobs, 0);
        b1.completion = Completer<void>();
        await b1.connect();
        await tester.pumpAndSettle();
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('label-print')))
            .onPressed!();
        // Preview and output now share a raster future started during build.
        // Let engine image IO finish and pump its continuations in the test zone.
        for (var n = 0; n < 100 && b1.jobs == 0; n++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pump();
        expect(find.text('Printing…'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const ValueKey('label-print')))
              .onPressed,
          isNull,
        );
        b1.completion!.complete();
        await tester.pumpAndSettle();
        expect(b1.jobs, 1);
        expect(b1.lastPaper, model.defaultPaper);
        expect(
          b1.lastPixels!.length,
          model.defaultPaper.printableWidth *
              model.defaultPaper.printableHeight,
        );
        expect(printer.jobs, 0);
      },
    );
  }

  testWidgets('remembers model and each paper across switching and reopening', (
    tester,
  ) async {
    final preferences = _MemoryOutputPreferences();
    final b1 = FakeLabelPrinter(model: LabelPrinterModel.b1);
    addTearDown(b1.dispose);
    await mount(tester, others: [b1], outputPreferences: preferences);
    Future<void> chooseModel(LabelPrinterModel current, String next) async {
      await tester.tap(find.byKey(ValueKey(current)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Niimbot $next').last);
      await tester.pumpAndSettle();
    }

    await chooseModel(LabelPrinterModel.d110, 'B1');
    await tester.tap(find.byKey(const ValueKey('label-paper-b1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('40 × 40 mm').last);
    await tester.pumpAndSettle();
    await chooseModel(LabelPrinterModel.b1, 'D110');
    expect(preferences.model, LabelPrinterModel.d110);
    await chooseModel(LabelPrinterModel.d110, 'B1');
    expect(preferences.paperFor(LabelPrinterModel.b1), LabelPaper.mm40x40);
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(tester, others: [b1], outputPreferences: preferences);
    expect(find.byKey(const ValueKey(LabelPrinterModel.b1)), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<LabelPaper>>(
            find.byKey(const ValueKey('label-paper-b1')),
          )
          .initialValue,
      LabelPaper.mm40x40,
    );
    await reveal(tester, 'label-preview');
    expect(
      tester.widget<LabelPreview>(find.byType(LabelPreview)).layout.paper,
      LabelPaper.mm40x40,
    );
    expect(b1.jobs, 0);
    expect(b1.connected, isFalse);
  });

  testWidgets('unavailable remembered model falls back to available printer', (
    tester,
  ) async {
    final preferences = _MemoryOutputPreferences();
    await preferences.remember(LabelPaper.mm40x40);
    await mount(tester, outputPreferences: preferences);
    expect(find.byKey(const ValueKey(LabelPrinterModel.d110)), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<LabelPaper>>(
            find.byKey(const ValueKey('label-paper-d110')),
          )
          .initialValue,
      LabelPaper.mm15x30,
    );
  });

  for (final (region, roast, frozen) in [
    (const Locale('en', 'GB'), '20/10/2026', '25/10/2026'),
    (const Locale('en', 'US'), '10/20/2026', '10/25/2026'),
  ]) {
    testWidgets('label source dates follow $region without printing', (
      tester,
    ) async {
      tester.platformDispatcher.localeTestValue = region;
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      await mount(
        tester,
        multiple: true,
        locale: 'es',
        portions: const [
          FrozenPortion(
            id: 'f',
            lotId: 'l',
            label: 'F123',
            frozenDate: '2026-10-25',
            initialGrams: 18,
            remainingGrams: 18,
            createdAtMs: 0,
            updatedAtMs: 0,
          ),
        ],
      );
      final lots = find.byKey(const ValueKey('label-lot-coffee'));
      await Scrollable.ensureVisible(tester.element(lots), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(lots);
      await tester.pumpAndSettle();
      expect(find.text('1 · $roast'), findsWidgets);
      expect(find.textContaining('2026-10-20'), findsNothing);
      await tester.tap(find.text('1 · $roast').last);
      await tester.pumpAndSettle();
      final kind = find.byType(DropdownButtonFormField<LabelKind>);
      await Scrollable.ensureVisible(tester.element(kind), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(kind);
      await tester.pumpAndSettle();
      final s = lookupAppLocalizations(const Locale('es'));
      await tester.tap(find.text(s.labelFrozen).last);
      await tester.pumpAndSettle();
      final portions = find.byKey(const ValueKey('label-portion'));
      await Scrollable.ensureVisible(tester.element(portions), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(portions);
      await tester.pumpAndSettle();
      expect(find.text('F123 · $frozen'), findsWidgets);
      expect(find.textContaining('2026-10-25'), findsNothing);
      expect(printer.jobs, 0);
    });
  }

  testWidgets('requires a lot when ambiguous and a connected printer', (
    tester,
  ) async {
    await mount(tester, multiple: true);
    await reveal(tester, 'label-export');
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('label-export')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('label-print')))
          .onPressed,
      isNull,
    );
    expect(printer.jobs, 0);
  });

  testWidgets('unknown fields and overflowing labels disable export', (
    tester,
  ) async {
    await mount(tester);
    await reveal(tester, 'label-body');
    await tester.enterText(find.byKey(const ValueKey('label-body')), '<dose>');
    await tester.pumpAndSettle();
    expect(find.textContaining('dose'), findsWidgets);
    await reveal(tester, 'label-export');
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('label-export')))
          .onPressed,
      isNull,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('label-body')),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('label-body')),
      List.filled(20, 'coffee').join('\n'),
    );
    await tester.pumpAndSettle();
    await reveal(tester, 'label-export');
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('label-export')))
          .onPressed,
      isNull,
    );
    expect(printer.jobs, 0);
  });

  testWidgets('saving a custom template persists content without printing', (
    tester,
  ) async {
    await mount(tester);
    await reveal(tester, 'label-body');
    await tester.enterText(
      find.byKey(const ValueKey('label-body')),
      '**<coffee>**\n<roast_date>',
    );
    await reveal(tester, 'label-template-save');
    await tester.tap(find.byKey(const ValueKey('label-template-save')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('label-template-name')),
      'My bag',
    );
    await tester.pump();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final saved = (await ShareTemplateSettings(
      db,
    ).load()).labelTemplates.single;
    expect(saved.name, 'My bag');
    expect(saved.body, '**<coffee>**\n<roast_date>');
    expect(printer.jobs, 0);
  });

  testWidgets('Spanish page scrolls at large text on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final pro = FakeLabelPrinter(model: LabelPrinterModel.b2Pro);
    addTearDown(pro.dispose);
    await mount(tester, locale: 'es', others: [pro]);
    await tester.tap(find.byKey(const ValueKey(LabelPrinterModel.d110)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Niimbot B2 Pro').last);
    await tester.pumpAndSettle();
    await reveal(tester, 'label-export');
    expect(tester.takeException(), isNull);
  });
}

class _MemoryOutputPreferences extends LabelOutputPreferences {
  _MemoryOutputPreferences() : super(File('unused'));
  final papers = <LabelPrinterModel, LabelPaper>{};
  @override
  LabelPaper paperFor(LabelPrinterModel model) =>
      papers[model] ?? model.defaultPaper;
  @override
  Future<void> remember(LabelPaper paper) async {
    model = paper.model;
    papers[paper.model] = paper;
  }
}
