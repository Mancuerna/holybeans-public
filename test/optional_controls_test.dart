import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/core/optional_rating_slider.dart';
import 'package:holybeans/ui/core/page_layout.dart';

void main() {
  for (final language in ['es', 'en']) {
    for (final dark in [false, true]) {
      testWidgets(
        'optional controls remain explicit and usable $language dark=$dark',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final query = TextEditingController(text: 'Coffee');
          double? rating;
          final semantics = tester.ensureSemantics();
          try {
            await tester.pumpWidget(
              MaterialApp(
                locale: Locale(language),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: dark ? AppTheme.dark() : AppTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
                home: Scaffold(
                  body: StatefulBuilder(
                    builder: (context, setState) => Column(
                      children: [
                        ValueListenableBuilder(
                          valueListenable: query,
                          builder: (_, _, _) =>
                              SearchField(label: 'Search', controller: query),
                        ),
                        OptionalRatingSlider(
                          value: rating,
                          onChanged: (value) => setState(() => rating = value),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            final s = AppLocalizations.of(
              tester.element(find.byType(OptionalRatingSlider)),
            )!;
            expect(_sliderValues(tester), [s.noRating]);
            expect(rating, isNull);
            final clear = find.byTooltip(s.clearSearch);
            expect(clear, findsOneWidget);
            await tester.tap(clear);
            await tester.pumpAndSettle();
            expect(query.text, isEmpty);
            expect(find.byTooltip(s.clearSearch), findsNothing);
            await tester.tap(find.byType(Slider));
            await tester.pumpAndSettle();
            expect(rating, 5);
            await tester.tap(find.byTooltip(s.clearRating));
            await tester.pumpAndSettle();
            expect(rating, isNull);
            expect(_sliderValues(tester), [s.noRating]);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            semantics.dispose();
            query.dispose();
          }
        },
      );
    }
  }
}

List<String> _sliderValues(WidgetTester tester) {
  final values = <String>[];
  tester.getSemantics(find.byType(Slider)).visitChildren((node) {
    values.add(node.getSemanticsData().value);
    return true;
  });
  return values;
}
