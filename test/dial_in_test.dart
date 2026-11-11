import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/brews/brew_form.dart';
import 'package:holybeans/ui/brews/dial_in_card.dart';

import 'helpers/test_database.dart';
import 'helpers/ui_test_support.dart';

const _longNote =
    'Bright and juicy but a little thin at the end; try a slower second '
    'pour, a hotter kettle and a finer grind before changing the dose, and '
    'keep the bloom at forty seconds.';

/// Opens a new brew of Kenya with the V60 from the coffee's sheet: a rated
/// Kenya brew two days ago, an unrated one later and one of another coffee
/// yesterday; with [favorite], a favourite Kenya recipe three days ago.
/// Returns the form's scrollable.
Future<Finder> _openKenyaV60(
  WidgetTester tester, {
  bool favorite = false,
}) async {
  final database = memoryDatabase();
  addTearDown(database.close);
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repository = JournalRepository(database);
  final methodId = await repository.createMethod(
    name: 'V60',
    category: 'pourover',
  );
  final kenya = await repository.createCoffee(name: 'Kenya', roaster: 'R');
  final other = await repository.createCoffee(name: 'Other', roaster: 'R');
  final kenyaBrew = await repository.createBrew(
    coffeeId: kenya,
    methodId: methodId,
    methodName: 'V60',
    grindSetting: '22 clicks',
    doseGrams: 18,
    waterGrams: 288,
    timeSeconds: 180,
    brewedAt: DateTime.now().subtract(const Duration(days: 2)),
  );
  await repository.rateBrew(
    kenyaBrew,
    rating: 7,
    notes: _longNote,
    tasting: const BrewTasting(balance: -1, strength: 0),
  );
  // A later unrated Kenya brew, and a later one of another coffee.
  await repository.createBrew(
    coffeeId: kenya,
    methodId: methodId,
    methodName: 'V60',
    grindSetting: '23 clicks',
    doseGrams: 18,
    notes: 'Go finer',
    brewedAt: DateTime.now().subtract(const Duration(hours: 30)),
  );
  await repository.createBrew(
    coffeeId: other,
    methodId: methodId,
    methodName: 'V60',
    grindSetting: '30 clicks',
    doseGrams: 15,
    brewedAt: DateTime.now().subtract(const Duration(days: 1)),
  );

  if (favorite) {
    final best = await repository.createBrew(
      coffeeId: kenya,
      methodId: methodId,
      methodName: 'V60',
      grindSetting: '20 clicks',
      doseGrams: 16,
      waterGrams: 256,
      brewedAt: DateTime.now().subtract(const Duration(days: 3)),
    );
    await repository.rateBrew(
      best,
      rating: 9,
      notes: null,
      tasting: const BrewTasting(balance: 0, strength: 0),
    );
    await repository.setBrewFavorite(best, favorite: true);
  }
  await tester.pumpWidget(
    HolyBeansApp(database: database, initialLocale: const Locale('en')),
  );
  await tester.pumpAndSettle();
  final bounds = tester.getRect(find.byType(NavigationBar));
  await tester.tapAt(
    Offset(bounds.left + bounds.width * 1.5 / 4, bounds.center.dy),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Kenya'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Brew with this bean'));
  await tester.pumpAndSettle();

  final form = find.byType(BrewForm);
  final scrollable = find
      .descendant(of: form, matching: find.byType(Scrollable))
      .first;
  final selector = find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == 'Choose a method',
  );
  await tester.scrollUntilVisible(selector, 200, scrollable: scrollable);
  await tester.pumpAndSettle();
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(find.text('V60').last);
  await tester.pumpAndSettle();

  return scrollable;
}

void main() {
  for (final language in ['en', 'es']) {
    for (final newestRated in [false, true]) {
      testWidgets(
        'reference label distinguishes last rated from newest in $language ($newestRated)',
        (tester) async {
          final date = DateTime.now().millisecondsSinceEpoch;
          Brew row(String id, double rating) => Brew(
            recipientIsPortafilter: false,
            id: id,
            coffeeId: 'coffee',
            methodName: 'V60',
            isPreGround: false,
            isFavorite: id == 'favorite',
            brewedAtMs: date,
            createdAtMs: date,
            updatedAtMs: date,
            rating: rating,
          );
          final rated = row('rated', 7);
          await tester.pumpWidget(
            localizedApp(
              locale: Locale(language),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: DialInCard(
                    brew: row('favorite', 8),
                    rated: true,
                    favorite: true,
                    latest: rated,
                    newest: newestRated ? rated : row('newest', 0),
                  ),
                ),
              ),
            ),
          );
          final strings = AppLocalizations.of(
            tester.element(find.byType(DialInCard)),
          )!;
          final label = tester
              .widget<Text>(find.byKey(const ValueKey('brew-dial-in-latest')))
              .data;
          expect(
            label,
            newestRated
                ? strings.dialInLatestNote('★ 7')
                : strings.dialInLatestRatedNote('★ 7'),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('the brew form recalls the same coffee and suggests a change', (
    tester,
  ) async {
    final scrollable = await _openKenyaV60(tester);
    final card = find.byKey(const ValueKey('brew-dial-in'));
    await tester.scrollUntilVisible(card, 100, scrollable: scrollable);
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('Last rated with this coffee'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.text('22 clicks, 18 g → 288 g, 3:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('★ 7, Too sour')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('brew-dial-in-advice')))
          .data,
      startsWith('Extract more'),
    );
    // The notes of the rated brew and of the newer one, written for the
    // next brew; the long one in two lines until "Show more".
    final note = find.byKey(const ValueKey('brew-dial-in-note'));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('brew-dial-in-newest-note')),
        matching: find.textContaining("Last time's note: Go finer"),
      ),
      findsOneWidget,
    );
    final collapsed = tester.getSize(note).height;
    final more = find.descendant(
      of: note,
      matching: find.byKey(const ValueKey('brew-dial-in-note-more')),
    );
    expect(
      find.descendant(of: more, matching: find.text('Show more')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('brew-dial-in-newest-note')),
        matching: find.byKey(const ValueKey('brew-dial-in-note-more')),
      ),
      findsNothing,
      reason: 'a short note needs no button',
    );
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(tester.getSize(note).height, greaterThan(collapsed));
    expect(
      find.descendant(of: more, matching: find.text('Show less')),
      findsOneWidget,
    );

    // The recipe comes from the latest brew of the same coffee, not from the
    // latest V60 brew of any coffee.
    final grind = find.widgetWithText(TextFormField, 'Grind setting');
    await tester.scrollUntilVisible(grind, 200, scrollable: scrollable);
    expect(tester.widget<TextFormField>(grind).controller!.text, '23 clicks');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('a favourite recipe is where a new brew starts', (tester) async {
    final scrollable = await _openKenyaV60(tester, favorite: true);
    final card = find.byKey(const ValueKey('brew-dial-in'));
    await tester.scrollUntilVisible(card, 100, scrollable: scrollable);
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('Your favourite recipe with this coffee'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('20 clicks, 16 g → 256 g')),
      findsOneWidget,
    );
    // The last rated brew is only a note, and a favourite needs no advice.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('brew-dial-in-latest')))
          .data,
      'Last rated brew: ★ 7, Too sour',
    );
    expect(find.byKey(const ValueKey('brew-dial-in-advice')), findsNothing);
    final grind = find.widgetWithText(TextFormField, 'Grind setting');
    await tester.scrollUntilVisible(grind, 200, scrollable: scrollable);
    expect(tester.widget<TextFormField>(grind).controller!.text, '20 clicks');
    final hint = find.byKey(const ValueKey('method-memory-hint'));
    await tester.scrollUntilVisible(hint, 200, scrollable: scrollable);
    expect(
      find.descendant(
        of: hint,
        matching: find.text('Values from your favourite V60 recipe'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('notes of the brew being edited stay in the form only', (
    tester,
  ) async {
    Brew brew(String id, String? notes) => Brew(
      recipientIsPortafilter: false,
      id: id,
      coffeeId: 'c',
      methodName: 'V60',
      brewedAtMs: DateTime(2026, 10, 2).millisecondsSinceEpoch,
      createdAtMs: 0,
      updatedAtMs: 0,
      notes: notes,
      isPreGround: false,
      isFavorite: false,
    );
    await tester.pumpWidget(
      localizedApp(
        locale: const Locale('es'),
        home: Scaffold(
          body: DialInCard(
            brew: brew('a', 'Más fino'),
            rated: true,
            newest: brew('b', 'Bajar a 92 °C'),
            editingId: 'b',
          ),
        ),
      ),
    );
    expect(find.textContaining('Nota: Más fino'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('brew-dial-in-newest-note')),
      findsNothing,
    );
  });
}
