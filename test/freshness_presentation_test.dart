import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/coffee_freshness.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/freshness_widgets.dart';
import 'package:holybeans/ui/core/app_theme.dart';

void main() {
  for (final locale in ['es', 'en']) {
    for (final dark in [false, true]) {
      testWidgets(
        'roaster rest is explicit at large text: $locale, dark=$dark',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: FreshnessSection(
                    freshness: CoffeeFreshness(
                      day: 55,
                      pausedDays: 0,
                      restDays: 60,
                      windows: {
                        for (final style in BrewStyle.values)
                          style: freshnessWindow(
                            roastLevel: 'light',
                            style: style,
                            restDays: 60,
                          ),
                      },
                      sweetSpots: const {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(
              locale == 'es'
                  ? 'Reposo del tostador: 60 días'
                  : 'Roaster’s recommended rest: 60 days',
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              locale == 'es'
                  ? 'Aplicado a filtro · Espresso estimado por la app'
                  : 'Applied to Filter · Espresso estimated by the app',
            ),
            findsOneWidget,
          );
          final rest = find.byKey(const ValueKey('freshness-roaster-rest'));
          final espresso = find.byKey(const ValueKey('freshness-espresso'));
          expect(
            tester.getBottomLeft(rest).dy,
            lessThanOrEqualTo(tester.getTopLeft(espresso).dy),
          );
          for (final (style, days) in [
            (BrewStyle.filter, 5),
            (BrewStyle.espresso, 19),
          ]) {
            final row = find.byKey(ValueKey('freshness-${style.name}'));
            expect(
              find.descendant(
                of: row,
                matching: find.text(
                  locale == 'es'
                      ? 'En su punto dentro de $days días'
                      : 'In its prime in $days days',
                ),
              ),
              findsOneWidget,
            );
          }
          expect(find.byType(FreshnessBar), findsNWidgets(2));
          expect(find.text(locale == 'es' ? 'Hoy' : 'Today'), findsNWidgets(2));
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('countdowns explain phase boundaries in $locale', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final s = AppLocalizations.of(context)!;
      const window = FreshnessWindow(
        primeStart: 10,
        primeEnd: 20,
        goodUntil: 25,
        agingUntil: 30,
      );
      final expected = locale == 'es'
          ? [
              'En su punto dentro de 1 día',
              '11 días restantes en su punto',
              '1 día restante en su punto',
              '5 días restantes en buen estado',
              '1 día restante en buen estado',
              '5 días hasta «Pasado»',
              '1 día hasta «Pasado»',
              null,
            ]
          : [
              'In its prime in 1 day',
              '11 days left in its prime',
              '1 day left in its prime',
              '5 days left in good condition',
              '1 day left in good condition',
              '5 days until stale',
              '1 day until stale',
              null,
            ];
      expect([
        for (final day in [9, 10, 20, 21, 25, 26, 30, 31])
          freshnessTimeLabel(s, window, day),
      ], expected);
    });
  }

  for (final dark in [false, true]) {
    testWidgets('phase labels have readable contrast, dark=$dark', (
      tester,
    ) async {
      final theme = dark ? AppTheme.dark() : AppTheme.light();
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      for (final phase in FreshnessPhase.values) {
        final color = freshnessPhaseColor(context, phase);
        for (final surface in [
          theme.colorScheme.surface,
          theme.colorScheme.surfaceContainerLowest,
          theme.colorScheme.surfaceContainerLow,
        ]) {
          final background = Color.alphaBlend(
            color.withValues(alpha: 0.15),
            surface,
          );
          expect(
            _contrast(color, background),
            greaterThanOrEqualTo(4.5),
            reason: '$phase label on $surface',
          );
          expect(
            _contrast(color, surface),
            greaterThanOrEqualTo(3),
            reason: '$phase bar on $surface',
          );
        }
      }
    });
  }
}

double _contrast(Color first, Color second) {
  final values = [first.computeLuminance(), second.computeLuminance()]..sort();
  return (values.last + 0.05) / (values.first + 0.05);
}
