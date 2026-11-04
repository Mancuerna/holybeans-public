import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/cupping.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/cupping/cupping_model.dart';
import 'package:holybeans/ui/cupping/cupping_page.dart';

import 'helpers/blind_cupping_fixture.dart';

void main() {
  late AppDatabase db;
  late JournalRepository r;
  late String coffee;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    r = JournalRepository(db);
    coffee = await r.createCoffee(
      name: 'Secret Kenya',
      roaster: 'R',
      initialGrams: 100,
    );
  });
  tearDown(() => db.close());

  Widget app(CuppingSession session, String language) => MaterialApp(
    locale: Locale(language),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(1.3)),
      child: child!,
    ),
    home: CuppingPage(repository: r, session: session),
  );

  CuppingModel model(WidgetTester tester) =>
      tester
              .widget<ListenableBuilder>(
                find
                    .descendant(
                      of: find.byType(CuppingPage),
                      matching: find.byType(ListenableBuilder),
                    )
                    .first,
              )
              .listenable
          as CuppingModel;

  Future<void> scroll(WidgetTester tester, Finder finder, {bool up = false}) =>
      tester.scrollUntilVisible(
        finder.hitTestable(),
        up ? -160 : 160,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );

  for (final language in ['es', 'en']) {
    testWidgets(
      'blind setup offers six letters and no coffee selectors ($language)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final id = await r.createCuppingSession(CuppingDraft());
        await tester.pumpWidget(app((await r.cuppingSession(id))!, language));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('cupping-blind')));
        await tester.pumpAndSettle();
        for (var i = 2; i < 6; i++) {
          final add = find.byKey(const ValueKey('cupping-add-cup'));
          await scroll(tester, add);
          await tester.tap(add);
          await tester.pumpAndSettle();
        }
        expect(find.byKey(const ValueKey('cupping-add-cup')), findsNothing);
        expect(
          find.text(language == 'es' ? 'Taza F' : 'Cup F'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('cupping-coffee-0')), findsNothing);
        expect(find.textContaining('Secret Kenya'), findsNothing);
        expect(model(tester).draft.cups, hasLength(6));
        expect(tester.takeException(), null);
        await tester.tap(find.byKey(const ValueKey('cupping-pour')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('cupping-countdown')), findsOneWidget);
        expect(find.textContaining('Secret Kenya'), findsNothing);
        final editTime = find.byKey(const ValueKey('cupping-edit-target'));
        await scroll(tester, editTime);
        await tester.tap(editTime);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('cupping-target-input')),
          '05:30',
        );
        await tester.tap(find.byKey(const ValueKey('cupping-save-target')));
        await tester.pumpAndSettle();
        expect(model(tester).draft.crustSeconds, 330);
        final pause = find.byKey(const ValueKey('cupping-pause'));
        await scroll(tester, pause, up: true);
        await tester.tap(pause);
        await tester.pumpAndSettle();
        expect(model(tester).clockPaused, true);
        final reset = find.byKey(const ValueKey('cupping-reset-clock'));
        await scroll(tester, reset);
        await tester.tap(reset);
        await tester.pumpAndSettle();
        expect(model(tester).clockPaused, false);
        expect(model(tester).elapsed, 0);
        await model(tester).flush();
        expect(await r.allBrews(), isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'anonymous scores, reveal confirmation, resumed mapping and fixed review ($language)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final d = blindTasting()..cups.last.scores[4] = null;
        final id = await r.createCuppingSession(d);
        await tester.pumpWidget(app((await r.cuppingSession(id))!, language));
        await tester.pumpAndSettle();
        expect(find.textContaining('Secret Kenya'), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('cupping-identify')),
              )
              .onPressed,
          null,
        );
        await tester.tap(find.byKey(const ValueKey('cupping-view')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Secret Kenya'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('cupping-view')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('cupping-tab-1')));
        await tester.pumpAndSettle();
        final missing = find.byKey(const ValueKey('cupping-score-1-4-null'));
        await scroll(tester, missing);
        await tester.tap(missing);
        await tester.pumpAndSettle();
        await tester.tap(find.text('5').last);
        await tester.pumpAndSettle();
        final scored = find.byKey(const ValueKey('cupping-score-1-4-5.0'));
        await tester.tap(scored);
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(language == 'es' ? 'Sin responder' : 'Unanswered').last,
        );
        await tester.pumpAndSettle();
        expect(model(tester).draft.canReveal, false);
        await tester.tap(missing);
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(language == 'es' ? 'No evaluado' : 'Not evaluated').last,
        );
        await tester.pumpAndSettle();
        expect(model(tester).draft.cups.last.notEvaluated[5], true);
        expect(model(tester).draft.cups.last.scores[4], null);
        final identify = find.byKey(const ValueKey('cupping-identify'));
        await tester.tap(identify);
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(language == 'es' ? 'Cancelar' : 'Cancel').last,
        );
        await tester.pumpAndSettle();
        expect(model(tester).draft.revealed, false);
        expect(find.byKey(const ValueKey('cupping-coffee-0')), findsNothing);
        await tester.tap(identify);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('cupping-confirm-reveal')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('cupping-identification')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('cupping-identification-notes-0')),
          findsOneWidget,
        );
        final first = find.byKey(const ValueKey('cupping-coffee-0'));
        await scroll(tester, first);
        await tester.tap(first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Secret Kenya').last);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('cupping-finish')),
              )
              .onPressed,
          null,
        );
        await model(tester).flush();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(app((await r.cuppingSession(id))!, language));
        await tester.pumpAndSettle();
        expect(model(tester).draft.cups.first.coffeeId, coffee);
        expect(model(tester).draft.cups.last.coffeeId, null);
        final second = find.byKey(const ValueKey('cupping-coffee-1'));
        await scroll(tester, second);
        await tester.tap(second);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Secret Kenya').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('cupping-review-scores')));
        await tester.pumpAndSettle();
        for (final field in tester.widgetList<DropdownButtonFormField<double>>(
          find.byType(DropdownButtonFormField<double>),
        )) {
          expect(field.onChanged, null);
        }
        final notes = find.byKey(const ValueKey('cupping-notes-0'));
        await scroll(tester, notes);
        expect(
          tester
              .widget<EditableText>(
                find.descendant(of: notes, matching: find.byType(EditableText)),
              )
              .readOnly,
          true,
        );
        expect(model(tester).draft.cups.first.rating, 0);
        await tester.tap(find.byKey(const ValueKey('cupping-review-scores')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('cupping-finish')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('cupping-finish')), findsNothing);
        expect(await r.allBrews(), hasLength(2));
        expect((await r.allBrews()).last.aftertaste, null);
        expect(
          (await r.allBrews()).map((b) => b.notes),
          containsAll(['Cup A notes', 'Cup B notes']),
        );
        await tester.tap(find.byKey(const ValueKey('cupping-share')));
        await tester.pumpAndSettle();
        expect(
          find.text(language == 'es' ? 'Cata a ciegas' : 'Blind cupping'),
          findsOneWidget,
        );
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
