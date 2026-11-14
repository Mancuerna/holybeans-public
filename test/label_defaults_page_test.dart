import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/label_output_preferences.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/domain/label_template.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/labels/label_output_settings.dart';
import 'package:holybeans/ui/labels/label_print_page.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/fake_label_printer.dart';
import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

const _coffeeTemplate = LabelTemplate(
  id: 'coffee-template',
  name: 'My bag',
  kind: LabelKind.coffee,
  body: '<coffee>',
  imageOptions: LabelImageOptions(size: 0.7, offsetX: 0.3),
);
const _frozenTemplate = LabelTemplate(
  id: 'frozen-template',
  name: 'My portion',
  kind: LabelKind.frozen,
  body: '<coffee> <portion_weight>',
);

void main() {
  setUpAll(initializeDateFormatting);
  late AppDatabase db;
  late ShareTemplateSettings settings;
  late _Printer printer;
  setUp(() {
    db = memoryDatabase();
    settings = ShareTemplateSettings(db);
    printer = _Printer();
  });
  tearDown(() async {
    printer.dispose();
    await db.close();
  });

  Future<void> mount(
    WidgetTester tester, {
    List<_Printer> others = const [],
    LabelOutputPreferences? outputPreferences,
    String language = 'en',
  }) async {
    final configuration = await settings.load();
    await tester.pumpWidget(
      localizedApp(
        locale: Locale(language),
        home: LabelPrintPage(
          coffee: const Coffee(
            id: 'c',
            name: 'Coffee',
            roaster: 'Roaster',
            isFavorite: false,
            isDecaf: false,
            createdAtMs: 0,
            updatedAtMs: 0,
          ),
          components: const [],
          lots: const [],
          portions: const [],
          templates: configuration.labelTemplates,
          defaults: configuration.labelDefaults,
          settings: settings,
          printer: printer,
          otherPrinters: others,
          outputPreferences: outputPreferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    final scrollable = find.byType(Scrollable).first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 180, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> chooseTemplate(WidgetTester tester, String name) async {
    await tap(tester, find.byType(DropdownButtonFormField<String>).first);
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  String body(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('label-body')))
      .controller!
      .text;

  final defaultButton = find.byKey(const ValueKey('label-template-default'));

  testWidgets(
    'explicit default survives reopening and choosing another template',
    (tester) async {
      await settings.saveLabelTemplate(_coffeeTemplate);
      await mount(tester);
      await chooseTemplate(tester, _coffeeTemplate.name);
      await tap(tester, defaultButton);
      expect(
        (await settings.load()).selectedLabel(LabelKind.coffee)?.id,
        _coffeeTemplate.id,
      );
      await chooseTemplate(tester, 'Basic template');
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester);
      expect(body(tester), _coffeeTemplate.body);
      expect(
        tester
            .widget<LabelGraphicControls>(find.byType(LabelGraphicControls))
            .options
            .offsetX,
        0.3,
      );
      expect(tester.widget<TextButton>(defaultButton).onPressed, isNull);
      expect(find.text('Default for this label type'), findsOneWidget);
      expect(printer.jobs, 0);
    },
  );

  testWidgets(
    'each label kind opens its own default and keeps the discard guard',
    (tester) async {
      await settings.saveLabelTemplate(_coffeeTemplate);
      await settings.saveLabelTemplate(_frozenTemplate);
      await settings.selectLabel(LabelKind.coffee, _coffeeTemplate.id);
      await settings.selectLabel(LabelKind.frozen, _frozenTemplate.id);
      await mount(tester);
      await tap(tester, find.byType(DropdownButtonFormField<LabelKind>));
      await tester.tap(find.text('Frozen portion').last);
      await tester.pumpAndSettle();
      expect(body(tester), _frozenTemplate.body);
      final field = find.byKey(const ValueKey('label-body'));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Unsaved draft');
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(defaultButton).onPressed, isNull);
      await tap(tester, find.byType(DropdownButtonFormField<LabelKind>));
      await tester.tap(find.text('Coffee').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(body(tester), 'Unsaved draft');
      await tap(tester, find.byType(DropdownButtonFormField<LabelKind>));
      await tester.tap(find.text('Coffee').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(body(tester), _coffeeTemplate.body);
    },
  );

  testWidgets(
    'basic template can replace a default and deleting it falls back',
    (tester) async {
      await settings.saveLabelTemplate(_coffeeTemplate);
      await settings.selectLabel(LabelKind.coffee, _coffeeTemplate.id);
      await mount(tester);
      await chooseTemplate(tester, 'Basic template');
      await tap(tester, defaultButton);
      expect((await settings.load()).labelDefaults, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester);
      final basicBody = body(tester);
      expect(
        basicBody,
        lookupAppLocalizations(const Locale('en')).labelCoffeeBody,
      );
      await chooseTemplate(tester, _coffeeTemplate.name);
      await tap(tester, defaultButton);
      await tap(tester, find.text('Delete template'));
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(body(tester), basicBody);
      expect((await settings.load()).labelDefaults, isEmpty);
      expect((await settings.load()).labelTemplates, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Spanish default control fits a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await settings.saveLabelTemplate(_coffeeTemplate);
    await settings.selectLabel(LabelKind.coffee, _coffeeTemplate.id);
    await mount(tester, language: 'es');
    await tester.scrollUntilVisible(
      defaultButton,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Predeterminada para este tipo de etiqueta'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'only the remembered selected model connects and never prints automatically',
    (tester) async {
      printer.name = 'D110';
      final other = _Printer(model: LabelPrinterModel.b1)..name = 'B1';
      addTearDown(other.dispose);
      final preferences = LabelOutputPreferences(File('unused'))
        ..model = other.model;
      await mount(tester, others: [other], outputPreferences: preferences);
      expect(printer.attempts, isEmpty);
      expect(other.attempts, [true]);
      expect(other.connected, isTrue);
      expect(other.jobs, 0);
      expect(printer.jobs, 0);
      await tap(tester, find.byKey(const ValueKey('label-printer-disconnect')));
      await tester.pumpAndSettle();
      expect(other.connected, isFalse);
      expect(other.attempts, [true]);
      await tap(tester, find.byKey(const ValueKey('label-printer-reconnect')));
      expect(other.attempts, [true, false]);
      expect(other.connected, isTrue);
    },
  );

  testWidgets(
    'unpaired and already connected printers do not start a connection',
    (tester) async {
      await mount(tester);
      expect(printer.attempts, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      printer.name = 'D110';
      printer.status = DeviceStatus.connected;
      await mount(tester);
      expect(printer.attempts, isEmpty);
    },
  );

  for (final failure in [
    DeviceStatus.failed,
    DeviceStatus.bluetoothOff,
    DeviceStatus.denied,
  ]) {
    testWidgets('automatic $failure leaves manual retry available', (
      tester,
    ) async {
      printer.name = 'D110';
      printer.failure = failure;
      await mount(tester);
      expect(printer.attempts, [true]);
      expect(printer.status, failure);
      expect(printer.jobs, 0);
      printer.failure = null;
      await tap(tester, find.byKey(const ValueKey('label-printer-reconnect')));
      expect(printer.attempts, [true, false]);
      expect(printer.connected, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'switching to another paired model attempts an automatic connection',
    (tester) async {
      final other = _Printer(model: LabelPrinterModel.b1)..name = 'B1';
      addTearDown(other.dispose);
      await mount(tester, others: [other]);
      await tap(tester, find.byKey(const ValueKey(LabelPrinterModel.d110)));
      await tester.tap(find.text('Niimbot B1').last);
      await tester.pumpAndSettle();
      expect(other.attempts, [true]);
      expect(other.connected, isTrue);
      expect(other.jobs, 0);
    },
  );
}

class _Printer extends FakeLabelPrinter {
  _Printer({super.model});
  final attempts = <bool>[];
  DeviceStatus? failure;

  @override
  Future<void> connect({bool automatic = false}) async {
    attempts.add(automatic);
    status = failure ?? DeviceStatus.connected;
    notifyListeners();
  }
}
