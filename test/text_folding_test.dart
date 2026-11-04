import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/text_suggestions.dart';

String original(String text) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final buffer = StringBuffer();
  for (final char in text.trim().toLowerCase().split('')) {
    final index = from.indexOf(char);
    buffer.write(index < 0 ? char : to[index]);
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
}

void main() {
  test('fast folding preserves every UTF-16 code unit and whitespace boundary', () {
    for (var i = 0; i <= 0xffff; i++) {
      final text =
          ' \u0301${String.fromCharCode(i)}\t Z${String.fromCharCode(i)}\u0301 ';
      expect(
        foldSuggestion(text),
        original(text),
        reason: 'U+${i.toRadixString(16)}',
      );
    }
  });
  test(
    'mixed Unicode, repeated whitespace and long text keep old matching',
    () {
      final random = Random(42);
      const alphabet = [
        'CAFÉ',
        'İ',
        '🙂',
        '漢字',
        '\u0301',
        '\u036f',
        '\n',
        '\t',
        '\u0085',
        '\ufeff',
        ' ',
      ];
      for (var i = 0; i < 1000; i++) {
        final text = List.generate(
          50,
          (_) => alphabet[random.nextInt(alphabet.length)],
        ).join();
        final folded = original(text);
        expect(foldSuggestion(text), folded);
        for (final query in [
          '',
          'cafe',
          'aaaaab',
          'z nowhere',
          folded,
          folded.substring(0, folded.length ~/ 2),
        ]) {
          expect(
            FoldedTextMatcher(query).matches(text),
            folded.contains(query),
          );
        }
      }
    },
  );
  test(
    'substring fallback handles overlaps, whitespace and matches late in notes',
    () {
      for (final (text, query) in [
        ('aaaaaaaab', 'aaaab'),
        ('ababababac', 'ababac'),
        ('CAFÉ \t\n JAZMÍN', 'cafe jazmin'),
        ('a' * 10000, 'aaaab'),
        ('a' * 10000 + ' Fin', 'fin'),
        ('🙂' * 1000 + 'É', '🙂e'),
      ]) {
        expect(
          FoldedTextMatcher(query).matches(text),
          original(text).contains(query),
        );
      }
    },
  );
}
