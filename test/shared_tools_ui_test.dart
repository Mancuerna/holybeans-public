import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form_fields.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/equipment/method_tools_sheet.dart';
import 'package:holybeans/ui/equipment/tool_form.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

void main() {
  late AppDatabase db;
  late JournalRepository repo;
  setUp(() {
    db = memoryDatabase();
    repo = JournalRepository(db);
  });
  tearDown(() => db.close());

  Widget frame(Widget Function(BuildContext) body) => localizedApp(
    locale: const Locale('en'),
    home: Scaffold(body: Builder(builder: body)),
  );

  testWidgets(
    'method autocomplete reuses identity and preserves other associations',
    (tester) async {
      final v60 = await repo.createMethod(name: 'V60');
      final origami = await repo.createMethod(name: 'Origami');
      final tool = await repo.createTool(name: 'Cafec Abaca', methodIds: [v60]);
      final method = (await db.select(db.brewMethods).get()).singleWhere(
        (row) => row.id == origami,
      );
      await tester.pumpWidget(
        frame(
          (context) => TextButton(
            onPressed: () => showMethodTools(context, repo, method),
            child: const Text('Manage'),
          ),
        ),
      );
      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add accessory'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tool-name')));
      await tester.enterText(find.byKey(const ValueKey('tool-name')), 'Cafe');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('tool-suggestion-$tool')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(ValueKey('tool-method-$v60')))
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(ValueKey('tool-method-$origami')),
            )
            .value,
        isTrue,
      );
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      final catalog = await repo.toolCatalog();
      expect(catalog.visible().single.id, tool);
      expect(catalog.methodsByTool[tool], {v60, origami});
      expect(find.text('Cafec Abaca'), findsOneWidget);
      expect(find.text('0 brews'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'equipment tool tab edits shared methods and offers explicit merge',
    (tester) async {
      final v60 = await repo.createMethod(name: 'V60');
      final origami = await repo.createMethod(name: 'Origami');
      final source = await repo.createTool(name: 'Old paper', methodIds: [v60]);
      final target = await repo.createTool(name: 'Paper', methodIds: [origami]);
      await tester.pumpWidget(
        HolyBeansApp(
          services: AppServices(database: db),
          initialLocale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Equipment'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accessories').first);
      await tester.pumpAndSettle();
      expect(find.text('Add accessory'), findsOneWidget);
      final card = find.byKey(ValueKey('tool-card-$source'));
      await tester.tap(
        find.descendant(of: card, matching: find.byTooltip('Actions')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merge accessories'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('merge-tool-target')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paper, Origami').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Merge accessories'));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('tool-card-$source')), findsNothing);
      expect(find.byKey(ValueKey('tool-card-$target')), findsOneWidget);
      expect((await repo.toolCatalog()).methodsByTool[target], {v60, origami});
      await tester.tap(find.text('Paper').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('tool-name')),
        'Cafec Abaca',
      );
      await tester.tap(find.byKey(ValueKey('tool-method-$v60')));
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      final catalog = await repo.toolCatalog();
      expect(catalog.byId[target]!.name, 'Cafec Abaca');
      expect(catalog.methodsByTool[target], {origami});
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'long tool chips keep counts and names readable at large text size',
    (tester) async {
      final tool = MethodTool(
        id: 'tool',
        name: List.filled(8, 'Cafec Abaca').join(' '),
      );
      await tester.pumpWidget(
        frame(
          (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: SizedBox(
              width: 360,
              child: MethodToolChips(
                tools: [tool],
                selected: const {},
                useCounts: const {'tool': 2097},
                onToggle: (_, _) {},
                onManage: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('2097'), findsOneWidget);
      expect(find.text(tool.name), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('unassigned tool can be saved from its catalog form', (
    tester,
  ) async {
    await tester.pumpWidget(
      frame(
        (context) => TextButton(
          onPressed: () => showToolForm(context, repo),
          child: const Text('New'),
        ),
      ),
    );
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('tool-name')), 'Brush');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final catalog = await repo.toolCatalog();
    expect(catalog.visible().single.name, 'Brush');
    expect(catalog.methodsByTool, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
