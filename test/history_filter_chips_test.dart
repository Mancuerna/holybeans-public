import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/ui/brews/history_filter_chips.dart';
import 'package:holybeans/ui/brews/history_filters.dart';

import 'helpers/ui_test_support.dart';

void main() {
  testWidgets('an active filter shows as a chip whose cross clears it', (
    tester,
  ) async {
    final filters = HistoryFilters()
      ..methodId = 'method-id'
      ..methodName = 'V60'
      ..toolIds = ['paper']
      ..showArchived = true
      ..minimumRating = 8;
    addTearDown(filters.dispose);
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('en'),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: filters,
            builder: (context, _) => HistoryFilterChips(
              filters: filters,
              coffees: const [],
              tools: const [MethodTool(id: 'paper', name: 'Cafec abacá')],
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('history-active-method')), findsOneWidget);
    expect(find.text('8+ ★'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear filter: V60'));
    await tester.pump();
    expect(filters.methodId, isNull);
    expect(filters.methodName, isNull);
    expect(find.byKey(const ValueKey('history-active-method')), findsNothing);
    expect(filters.minimumRating, 8);
    expect(filters.toolIds, ['paper']);
    expect(find.byTooltip('Clear filter: Cafec abacá'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pump();
    expect(filters.activeCount, 0);
    expect(filters.toolIds, isEmpty);
    expect(filters.showArchived, isTrue);
  });

  test(
    'method navigation clears accessory filters and keeps archive visibility',
    () {
      final filters = HistoryFilters()
        ..toolIds = ['paper', 'basket']
        ..showArchived = true;
      addTearDown(filters.dispose);
      expect(filters.activeCount, 2);
      filters.resetForNavigation();
      expect(filters.toolIds, isEmpty);
      expect(filters.activeCount, 0);
      expect(filters.showArchived, isTrue);
      expect(filters.navigationRevision, 1);
    },
  );
}
