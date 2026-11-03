import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

Map<String, dynamic> config(String uuid, DateTime at) => {
  'uuid': uuid,
  'unix_timestamp': at.millisecondsSinceEpoch ~/ 1000,
};

/// A small BeanConqueror export: an espresso machine with tools, a dripper,
/// a grinder, a finished bean, a frozen one still in the freezer and three
/// brews, with BeanConqueror's 0-to-5 ratings.
Map<String, dynamic> exportJson() => {
  'SETTINGS': [
    {'brew_rating': 5, 'bean_rating': 5},
  ],
  'VERSION': [
    {'alreadyDisplayedVersions': <String>[]},
  ],
  'PREPARATION': [
    {
      'name': 'Lelit Bianca',
      'type': 'PORTAFILTER',
      'style_type': 'ESPRESSO',
      'config': config('prep-espresso', DateTime(2025)),
      'connectedPreparationDevice': {
        'type': 'METICULOUS',
        'url': 'http://192.0.2.90',
      },
      'tools': [
        {
          'name': 'VST 18',
          'config': config('tool-basket', DateTime(2025)),
          'archived': false,
        },
      ],
    },
    {
      'name': 'V60',
      'type': 'V60',
      'style_type': 'POUR OVER',
      'config': config('prep-v60', DateTime(2025)),
      'tools': <Object>[],
    },
  ],
  'MILL': [
    {'name': 'Lagom 01', 'config': config('mill-lagom', DateTime(2025))},
  ],
  'BEANS': [
    {
      'name': 'Finca Finished',
      'roaster': 'Roast Club ',
      'config': config('bean-finished', DateTime(2025, 1, 2)),
      'roast': 'CITY_ROAST',
      'roastingDate': '2025-01-01T10:00:00.000Z',
      'weight': 250,
      'cost': 13.5,
      'finished': true,
      'rating': 4,
      'aromatics': 'Miel, fruta de hueso',
      'decaffeinated': false,
      'url': 'https://example.com/finca',
      'bean_information': [
        {
          'country': 'Ethiopia ',
          'farmer': 'Khalid',
          'variety': 'Heirloom',
          'processing': 'Washed',
          'elevation': '1.900 msnm',
          'harvest_time': '2024',
        },
      ],
      'frozenDate': null,
      'attachments': ['/photo_abc.jpg'],
    },
    {
      'name': 'Frozen Gesha',
      'roaster': 'Nomad',
      'config': config('bean-frozen', DateTime(2025, 2)),
      'roast': 'UNKNOWN',
      'weight': 100,
      'finished': false,
      'rating': 0,
      'frozenDate': '2025-02-05T09:00:00.000Z',
      'frozenId': 'eb2a8c',
      'frozenStorageType': 'TUBE',
      'bean_information': <Object>[],
    },
  ],
  'BREWS': [
    {
      'config': config('brew-espresso', DateTime(2025, 1, 5, 8)),
      'bean': 'bean-finished',
      'method_of_preparation': 'prep-espresso',
      'method_of_preparation_tools': ['tool-basket'],
      'mill': 'mill-lagom',
      'grind_size': '12',
      'grind_weight': 18,
      'brew_quantity': 0,
      'brew_quantity_type': 'GR',
      'brew_beverage_quantity': 36.4,
      'brew_beverage_quantity_type': 'GR',
      'brew_time': 28,
      'brew_temperature': 93,
      'coffee_blooming_time': 6,
      'coffee_first_drip_time': 9,
      'rating': 3.5,
      'tds': 9.1,
      'note': 'Sweet',
    },
  ],
};

/// Brews kept in the second chunk file.
List<Map<String, dynamic>> chunkBrews() => [
  {
    'config': config('brew-v60', DateTime(2025, 2, 10, 9)),
    'bean': 'bean-frozen',
    'method_of_preparation': 'prep-v60',
    'mill': 'mill-lagom',
    'grind_size': '30',
    'grind_weight': 15,
    'brew_quantity': 250,
    'brew_quantity_type': 'GR',
    'brew_beverage_quantity': 0,
    'brew_beverage_quantity_type': 'GR',
    'brew_time': 180,
    'coffee_blooming_time': 40,
    'flow_profile': 'brews/brew-v60_flow_profile.json',
    'rating': 0,
  },
  {
    'config': config('brew-lost', DateTime(2025, 2, 11)),
    'bean': 'bean-that-is-not-there',
    'method_of_preparation': 'prep-v60',
  },
];

Uint8List zip() {
  final archive = Archive()
    ..add(
      ArchiveFile.bytes(
        'Beanconqueror.json',
        utf8.encode(jsonEncode(exportJson())),
      ),
    )
    ..add(
      ArchiveFile.bytes(
        'Beanconqueror_Brews_1.json',
        utf8.encode(jsonEncode(chunkBrews())),
      ),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// A ZIP of the whole export folder, as a phone's file manager makes it:
/// the export's own ZIP, the `brews` folder of flow profiles and a photo.
Uint8List folderZip() {
  final archive = Archive()
    ..add(ArchiveFile.bytes('Beanconqueror/Beanconqueror.zip', zip()))
    ..add(
      ArchiveFile.bytes(
        'Beanconqueror/brews/brew-v60_flow_profile.json',
        utf8.encode(jsonEncode(v60FlowProfile())),
      ),
    )
    ..add(
      ArchiveFile.bytes('Beanconqueror/brews/unrelated_flow_profile.json', [
        ...utf8.encode('not json'),
      ]),
    )
    ..add(ArchiveFile.bytes('Beanconqueror/photo_abc.jpg', [0xFF, 0xD8, 0xFF]));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// The flow profile of the V60 brew, as BeanConqueror stores it.
Map<String, dynamic> v60FlowProfile() => {
  'weight': [
    for (final (time, grams) in [
      ('09:00:00.000', 0.0),
      ('09:00:00.500', 3.0),
      ('09:00:01.000', 9.0),
    ])
      {'timestamp': time, 'brew_time': '', 'actual_weight': grams},
  ],
  'realtimeFlow': <Object>[],
  'pressureFlow': <Object>[],
};
