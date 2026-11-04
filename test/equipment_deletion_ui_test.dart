import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/cupping.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/equipment/equipment_page.dart';

void main() {
  late AppDatabase database;
  late JournalRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = JournalRepository(database);
  });
  tearDown(() => database.close());

  Widget app(
    EquipmentSection section, {
    bool archived = false,
    String locale = 'en',
  }) => MaterialApp(
    locale: Locale(locale),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: EquipmentPage(
        repository: repository,
        section: section,
        onSectionChanged: (_) {},
        showArchived: archived,
      ),
    ),
  );

  Future<void> openDelete(
    WidgetTester tester,
    String label, {
    String actions = 'Actions',
  }) async {
    await tester.tap(find.byTooltip(actions).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  for (final section in [EquipmentSection.methods, EquipmentSection.water]) {
    final method = section == EquipmentSection.methods;
    final label = method ? 'Delete method' : 'Delete water profile';
    for (final archived in [false, true]) {
      testWidgets(
        '$section deletion cancels then confirms (archived: $archived)',
        (tester) async {
          if (method) {
            final id = await repository.createMethod(name: 'Trial');
            await repository.setMethodArchived(id, archived: archived);
          } else {
            final id = await repository.createWaterProfile(name: 'Trial');
            await repository.setWaterProfileArchived(id, archived: archived);
          }
          await tester.pumpWidget(app(section, archived: archived));
          await tester.pumpAndSettle();
          await openDelete(tester, label);
          expect(find.text('Delete “Trial”?'), findsOneWidget);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(find.text('Trial'), findsOneWidget);

          await openDelete(tester, label);
          await tester.tap(
            find.byKey(const ValueKey('delete-equipment-confirm')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Trial'), findsNothing);
          expect(find.text('“Trial” deleted.'), findsOneWidget);
          expect(await database.select(database.brewMethods).get(), isEmpty);
          expect(await database.select(database.waterProfiles).get(), isEmpty);
          expect(tester.takeException(), isNull);
          await disposeApp(tester);
        },
      );
    }
  }

  testWidgets('method with accessories explains the block and still archives', (
    tester,
  ) async {
    final method = await repository.createMethod(name: 'V60');
    await repository.createTool(name: 'Filter', methodIds: [method]);
    await tester.pumpWidget(app(EquipmentSection.methods));
    await tester.pumpAndSettle();
    await openDelete(tester, 'Delete method');
    expect(
      find.byKey(const ValueKey('equipment-in-use-dialog')),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'It has linked accessories, including archived or imported ones.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('delete-equipment-confirm')),
      findsNothing,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive method'));
    await tester.pumpAndSettle();
    expect(find.text('V60'), findsNothing);
    expect(
      (await database.select(database.brewMethods).get()).single.archivedAtMs,
      isNotNull,
    );
    await disposeApp(tester);
  });

  testWidgets('water draft block is readable in Spanish on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final water = await repository.createWaterProfile(name: 'Agua de prueba');
    await repository.createCuppingSession(
      CuppingDraft()..waterProfileId = water,
    );
    await tester.pumpWidget(app(EquipmentSection.water, locale: 'es'));
    await tester.pumpAndSettle();
    await openDelete(tester, 'Eliminar agua', actions: 'Acciones');
    expect(find.text('No se puede eliminar «Agua de prueba»'), findsOneWidget);
    expect(
      find.textContaining('Está seleccionado en una cata'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('delete-equipment-confirm')),
      findsNothing,
    );
    expect(await database.select(database.waterProfiles).get(), hasLength(1));
    expect(tester.takeException(), isNull);
    await disposeApp(tester);
  });

  testWidgets('new relation while confirmation is open prevents deletion', (
    tester,
  ) async {
    final water = await repository.createWaterProfile(name: 'Trial');
    await tester.pumpWidget(app(EquipmentSection.water));
    await tester.pumpAndSettle();
    await openDelete(tester, 'Delete water profile');
    await repository.createCuppingSession(
      CuppingDraft()..waterProfileId = water,
    );
    await tester.tap(find.byKey(const ValueKey('delete-equipment-confirm')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('equipment-in-use-dialog')),
      findsOneWidget,
    );
    expect(
      find.textContaining('It is selected in a cupping session'),
      findsOneWidget,
    );
    expect(await database.select(database.waterProfiles).get(), hasLength(1));
    expect(tester.takeException(), isNull);
    await disposeApp(tester);
  });
}
