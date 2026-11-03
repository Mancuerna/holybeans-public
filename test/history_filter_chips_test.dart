import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/history_filter_chips.dart';
import 'package:holybeans/ui/brews/history_filters.dart';

void main() {
  testWidgets('an active filter shows as a chip whose cross clears it', (
    tester,
  ) async {
    final filters = HistoryFilters()
      ..methodId = 'method-id'
      ..methodName = 'V60'
      ..minimumRating = 8;
    addTearDown(filters.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: filters,
            builder: (context, _) =>
                HistoryFilterChips(filters: filters, coffees: const []),
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

    await tester.tap(find.text('Clear filters'));
    await tester.pump();
    expect(filters.activeCount, 0);
  });
}
