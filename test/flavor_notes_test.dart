import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/flavor_notes.dart';

void main() {
  test('flavor notes are trimmed, deduplicated and joined', () {
    expect(normalizeFlavorNotes(null), isNull);
    expect(normalizeFlavorNotes(' , ,'), isNull);
    expect(
      normalizeFlavorNotes(' Cherry,jasmine , cherry,, Cacao '),
      'Cherry, jasmine, Cacao',
    );
  });
}
