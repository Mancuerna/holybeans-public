import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/flavor_descriptors.dart';
import 'package:holybeans/domain/text_suggestions.dart';

void main() {
  test('recognition is exact, bilingual and accent/case insensitive', () {
    for (final name in ['peach', ' MELOCOTÓN ', 'durazno', 'melocoton']) {
      expect(recognizeFlavorNote(name), FlavorDescriptor.peach);
    }
    expect(recognizeFlavorNote('JAZMI\u0301N'), FlavorDescriptor.jasmine);
    expect(
      recognizeFlavorNote('dark chocolate'),
      FlavorDescriptor.darkChocolate,
    );
    expect(recognizeFlavorNote('chocolate'), FlavorDescriptor.chocolate);
    expect(recognizeFlavorNote('nueces'), FlavorDescriptor.walnut);
    expect(recognizeFlavorNote('frutos secos'), FlavorDescriptor.nutty);
    expect(recognizeFlavorNote('lemon cake'), isNull);
    expect(recognizeFlavorNote('chocolate y naranja'), isNull);
    expect(recognizeFlavorNote('un recuerdo de mi infancia'), isNull);
  });

  test('aliases cannot collide with another descriptor', () {
    final owner = <String, FlavorDescriptor>{};
    for (final descriptor in FlavorDescriptor.values) {
      for (final alias in descriptor.aliases) {
        final folded = foldSuggestion(alias);
        expect(owner[folded] ?? descriptor, descriptor, reason: alias);
        owner[folded] = descriptor;
      }
    }
  });

  test('new aliases deduplicate without rewriting imported notes', () {
    const existing = ['Peach', 'JASMINE', 'tarta de la abuela'];
    expect(appendFlavorNote(existing, 'melocotón'), existing);
    expect(appendFlavorNote(existing, 'Jazmín'), existing);
    expect(appendFlavorNote(existing, ' TARTA DE LA ABUELA '), existing);
    expect(appendFlavorNote(existing, '  cacao '), [...existing, 'cacao']);
    expect(appendFlavorNote(existing, ''), existing);
    expect(existing, ['Peach', 'JASMINE', 'tarta de la abuela']);
  });

  test('suggestions accept either language and skip selected aliases', () {
    expect(suggestFlavorNotes('dur', []), [FlavorDescriptor.peach]);
    expect(suggestFlavorNotes(' MELOCO ', []), [FlavorDescriptor.peach]);
    expect(suggestFlavorNotes('dur', ['peach']), isEmpty);
    expect(suggestFlavorNotes('', []), isEmpty);
    expect(suggestFlavorNotes('lemon cake', []), isEmpty);
    expect(
      suggestFlavorNotes('chocolate', []),
      contains(FlavorDescriptor.chocolate),
    );
    expect(
      suggestFlavorNotes('chocolate', []),
      contains(FlavorDescriptor.darkChocolate),
    );
  });

  test('individual flowers and fruits have distinct visual families', () {
    expect(FlavorDescriptor.peach.tone, FlavorDescriptor.apricot.tone);
    expect(FlavorDescriptor.jasmine.tone, FlavorTone.cream);
    expect(FlavorDescriptor.rose.tone, FlavorTone.pink);
    expect(FlavorDescriptor.lavender.tone, FlavorTone.purple);
    expect(FlavorDescriptor.blueberry.tone, FlavorTone.blue);
  });

  test('free-text notes take the colour of a descriptor they name', () {
    expect(flavorNoteTone('peach'), FlavorTone.orange);
    expect(flavorNoteTone('Cherry jam'), FlavorTone.red);
    expect(flavorNoteTone('flowers'), FlavorDescriptor.floral.tone);
    expect(flavorNoteTone('Stewed strawberries'), FlavorTone.red);
    expect(flavorNoteTone('brown sugar notes'), FlavorTone.brown);
    expect(flavorNoteTone('tea-like'), isNull);
    // Identity stays exact: the colour does not make it a descriptor.
    expect(recognizeFlavorNote('Cherry jam'), isNull);
  });
}
