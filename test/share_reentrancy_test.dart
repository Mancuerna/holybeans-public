import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/share_sheet.dart';

class _Pops extends NavigatorObserver {
  int pops = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
  }
}

void main() {
  testWidgets('two text share callbacks close only the share sheet', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = JournalRepository(db);
    final coffeeId = await repository.createCoffee(
      name: 'Coffee',
      roaster: 'R',
    );
    final brewId = await repository.createBrew(
      coffeeId: coffeeId,
      methodName: 'V60',
    );
    final coffee = (await repository.coffee(coffeeId))!;
    final brew = (await repository.brew(brewId))!;
    final observer = _Pops();
    ShareBrewResult? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: [observer],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (context) => Scaffold(
                    appBar: AppBar(title: const Text('Parent screen')),
                    body: TextButton(
                      onPressed: () async {
                        result = await showModalBottomSheet<ShareBrewResult>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => ShareBrewSheet(
                            coffee: coffee,
                            brew: brew,
                            components: const [],
                            initialFields: const {BrewParameter.coffee},
                          ),
                        );
                      },
                      child: const Text('Open share'),
                    ),
                  ),
                ),
              ),
              child: const Text('Open parent'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open parent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open share'));
    await tester.pumpAndSettle();
    final confirm = tester
        .widget<FilledButton>(find.byKey(const ValueKey('share-confirm')))
        .onPressed!;
    confirm();
    confirm();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(observer.pops, 1);
    expect(find.text('Parent screen'), findsOneWidget);
    expect(result?.text, contains('Coffee'));
  });
}
