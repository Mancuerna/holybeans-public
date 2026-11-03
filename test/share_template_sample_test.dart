import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/share_template_editor.dart';
import 'package:holybeans/ui/brews/share_template_values.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(initializeDateFormatting);

  // Fields a brew of the other style does not record.
  const filterOnly = {
    'water',
    'bloom_count',
    'bloom',
    'pour_count',
    'pour_details',
  };
  const espressoOnly = {'preinfusion', 'first_drip', 'pressure', 'profile'};

  for (final locale in ['es', 'en']) {
    for (final style in ShareTemplateStyle.values) {
      test('the $locale ${style.name} sample fills every tag of its style', () {
        final values = sampleShareTemplateValues(
          lookupAppLocalizations(Locale(locale)),
          style,
        );
        final skipped = style == ShareTemplateStyle.espresso
            ? filterOnly
            : espressoOnly;
        for (final tag in shareTemplateTags.keys) {
          expect(
            values[tag]?.trim().isNotEmpty,
            !skipped.contains(tag),
            reason: tag,
          );
        }
      });
    }
  }

  testWidgets('the preview sits under the text and follows it', (tester) async {
    // Tall enough for the whole form, help included, to be laid out.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ShareTemplateEditor(
            style: ShareTemplateStyle.filter,
            onSave: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final body = find.byKey(const ValueKey('template-body'));
    final card = find.byKey(const ValueKey('template-preview-card'));
    final help = find.textContaining('Tap a tag to insert it');
    expect(tester.getRect(card).top, greaterThan(tester.getRect(body).bottom));
    expect(tester.getRect(card).bottom, lessThan(tester.getRect(help).top));

    await tester.enterText(body, '<method> · <pour_details> · <preinfusion>');
    await tester.pump();
    final preview = tester
        .widget<SelectableText>(find.byKey(const ValueKey('template-preview')))
        .data!;
    expect(preview, startsWith('V60 · Bloom 1 · 50 g'));
    expect(preview, endsWith(' · —'));
    expect(
      find.textContaining('The sample has no <preinfusion>'),
      findsOneWidget,
    );
  });
}
