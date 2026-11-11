import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/share_markdown.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/ui/brews/share_sheet.dart';
import 'package:holybeans/ui/brews/share_template_editor.dart';
import 'package:holybeans/ui/core/share_image.dart';
import 'package:holybeans/ui/core/share_markdown_text.dart';

import 'helpers/ui_test_support.dart';

String plain(String source) =>
    ShareMarkdown.parse(source).map((r) => r.text).join();

void main() {
  test('basic formatting and nested styles', () {
    final runs = ShareMarkdown.parse('**bold _both_** *italic* ~~old~~ `code`');
    expect(runs.where((r) => r.text == 'both').single.bold, isTrue);
    expect(runs.where((r) => r.text == 'both').single.italic, isTrue);
    expect(runs.where((r) => r.text == 'old').single.strike, isTrue);
    expect(runs.where((r) => r.text == 'code').single.code, isTrue);
    expect(plain('***both*** __bold__ _italic_'), 'both bold italic');
    expect(plain('**bold *both*** *italic **both***'), 'bold both italic both');
  });
  test('line breaks, empty lines, bullets and quotes survive', () {
    expect(
      plain('- **one**\n+ two\n\n> *quote*\n1. three\n'),
      '• one\n• two\n\n│ quote\n1. three\n',
    );
  });
  test(
    'unmatched delimiters, escapes and intraword underscores stay literal',
    () {
      expect(
        plain(r'\*literal\* **unfinished a_b_c café_molido_fino'),
        '*literal* **unfinished a_b_c café_molido_fino',
      );
      expect(plain('`**literal**`'), '**literal**');
      final escapedEnd = ShareMarkdown.parse(
        TemplateEngine.renderMarkdown('**<coffee>**', {
          'coffee': 'Coffee_*literal*',
        }),
      );
      expect(escapedEnd.single.text, 'Coffee_*literal*');
      expect(escapedEnd.single.bold, isTrue);
    },
  );
  test('substituted values cannot inject formatting or template tags', () {
    const body = '**<coffee>**\n<notes>\n`<grind_setting>`';
    const values = {
      'coffee': 'A_*B*_<time>',
      'notes': '> not a quote\n- not a list\n**not bold**',
      'grind_setting': '1_2`3',
    };
    final rendered = TemplateEngine.renderMarkdown(body, values);
    expect(
      plain(rendered),
      'A_*B*_<time>\n> not a quote\n- not a list\n**not bold**\n1_2`3',
    );
    expect(
      ShareMarkdown.parse(rendered).where((r) => r.bold).single.text,
      values['coffee'],
    );
    expect(
      TemplateEngine.render(body, values),
      '**A_*B*_<time>**\n> not a quote\n- not a list\n**not bold**\n`1_2`3`',
    );
  });
  for (final language in ['es', 'en']) {
    testWidgets('template editor formats while typing ($language)', (
      tester,
    ) async {
      await tester.pumpWidget(
        localizedApp(
          locale: Locale(language),
          home: Scaffold(
            body: ShareTemplateEditor(
              style: ShareTemplateStyle.espresso,
              values: const {'coffee': 'Coffee_*literal*'},
              onSave: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('template-body')),
        '**<coffee>**',
      );
      await tester.pump();
      final preview = tester.widget<SelectableText>(
        find.byKey(const ValueKey('template-preview')),
      );
      expect(preview.textSpan!.toPlainText(), 'Coffee_*literal*');
      expect(
        (preview.textSpan!.children!.single as TextSpan).style!.fontWeight,
        FontWeight.w700,
      );
      expect(tester.takeException(), isNull);
    });
    testWidgets('formatted brew card exports a PNG ($language)', (
      tester,
    ) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        localizedApp(
          locale: Locale(language),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundary,
                child: const BrewShareCard(
                  title: 'Coffee',
                  sections: [],
                  customText:
                      '**Coffee**\n*Roaster*\n- ~~old~~ `18 g`\n> Good cup',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Coffee\nRoaster\n• old 18 g\n│ Good cup',
          findRichText: true,
        ),
        findsOneWidget,
      );
      final bytes = await tester.runAsync(
        () => renderShareImage(boundary.currentContext!, boundary),
      );
      expect(bytes, isNotNull);
      expect(bytes!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('image text and selectable preview use the same styled content', (
    tester,
  ) async {
    const source = '**Coffee**\n*Roaster* ~~old~~ `18 g`';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              shareMarkdownText(source, key: const Key('image')),
              shareMarkdownText(
                source,
                key: const Key('preview'),
                selectable: true,
              ),
            ],
          ),
        ),
      ),
    );
    final image = tester.widget<Text>(find.byKey(const Key('image'))).textSpan!;
    final preview = tester
        .widget<SelectableText>(find.byKey(const Key('preview')))
        .textSpan!;
    expect(image.toPlainText(), 'Coffee\nRoaster old 18 g');
    expect(preview.toPlainText(), image.toPlainText());
    final spans = (image as TextSpan).children!.cast<TextSpan>();
    expect(spans.first.style!.fontWeight, FontWeight.w700);
    expect(
      spans.singleWhere((s) => s.text == 'Roaster').style!.fontStyle,
      FontStyle.italic,
    );
    expect(tester.takeException(), isNull);
  });
}
