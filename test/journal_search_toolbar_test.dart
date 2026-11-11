import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/core/journal_search_toolbar.dart';

import 'helpers/ui_test_support.dart';

void main() {
  for (final language in ['en', 'es']) {
    for (final (width, scale) in [(360.0, 1.0), (320.0, 2.0), (800.0, 2.0)]) {
      testWidgets('search and actions fit $width at ${scale}x ($language)', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        var taps = 0;
        await tester.pumpWidget(
          localizedApp(
            theme: AppTheme.light(),
            locale: Locale(language),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => JournalSearchToolbar(
                    controller: controller,
                    actions: [
                      for (var i = 0; i < 3; i++)
                        IconButton(
                          key: ValueKey(i),
                          tooltip: 'Action $i',
                          onPressed: () => taps++,
                          icon: const Icon(Icons.sort),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final search = find.byType(TextField);
        final searchBounds = tester.getRect(search);
        for (var i = 0; i < 3; i++) {
          final button = find.byKey(ValueKey(i));
          final bounds = tester.getRect(button);
          expect(bounds.width, greaterThanOrEqualTo(48));
          expect(bounds.height, greaterThanOrEqualTo(48));
          expect(bounds.right, lessThanOrEqualTo(width - 20));
          if (width == 320) {
            expect(bounds.top, greaterThanOrEqualTo(searchBounds.bottom));
          } else {
            expect(bounds.center.dy, closeTo(searchBounds.center.dy, 1));
          }
          await tester.tap(button);
        }
        expect(taps, 3);
        await tester.enterText(search, 'Ethiopia');
        await tester.pump();
        final strings = AppLocalizations.of(tester.element(search))!;
        await tester.tap(find.byTooltip(strings.clearSearch));
        await tester.pump();
        expect(controller.text, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
