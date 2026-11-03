import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/domain/share_template_exchange.dart';

void main() {
  for (final style in ShareTemplateStyle.values) {
    test('round trip $style exports only unresolved portable fields', () {
      final original = ShareTemplate(
        id: 'private-id',
        name: '☕ Mi receta',
        style: style,
        body: '<country_flag> <country>: Mi <coffee> salió en <time>\nRatio <ratio>',
      );
      final source = encodeShareTemplate(original);
      expect(isShareTemplateFile(source), isTrue);
      expect((jsonDecode(source) as Map).keys.toSet(), {
        'format',
        'version',
        'name',
        'style',
        'body',
      });
      expect(source, isNot(contains('private-id')));
      final copy = decodeShareTemplate(source, newId: 'fresh-id');
      expect(copy.toJson(), {...original.toJson(), 'id': 'fresh-id'});
    });
  }
  test(
    'rejects wrong format version style invalid fields and unknown tags',
    () {
      final valid = jsonDecode(
        encodeShareTemplate(
          const ShareTemplate(
            id: 'a',
            name: 'A',
            style: ShareTemplateStyle.filter,
            body: '<time>',
          ),
        ),
      ) as Map<String, dynamic>;
      for (final patch in [
        {'format': 'holybeans-beans'},
        {'version': 2},
        {'style': 'tea'},
        {'name': ''},
        {'body': '<secret>'},
        {'body': 3},
        {'name': 'a' * 81},
        {'body': 'a' * 8001},
      ]) {
        expect(
          () => decodeShareTemplate(
            jsonEncode({...valid, ...patch}),
            newId: 'new',
          ),
          throwsFormatException,
        );
      }
      for (final source in [
        'null',
        '[]',
        'broken',
        ' ' * (maxShareTemplateBytes + 1),
      ]) {
        expect(
          () => decodeShareTemplate(source, newId: 'new'),
          throwsFormatException,
        );
      }
      expect(isShareTemplateFile('{"format":"holybeans-beans"}'), isFalse);
      expect(isShareTemplateFile('broken'), isFalse);
    },
  );
  test('foreign IDs and defaults cannot overwrite local state', () {
    final source = jsonEncode({
      'format': shareTemplateFormat,
      'version': 1,
      'name': 'Imported',
      'style': 'espresso',
      'body': '<time>',
      'id': 'existing',
      'defaults': {'espresso': 'existing'},
      'fields': <String>[],
    });
    expect(decodeShareTemplate(source, newId: 'new').id, 'new');
  });
}
