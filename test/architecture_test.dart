import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'helpers/import_graph.dart';

void main() {
  test('dependency checker distinguishes a diamond from a cycle', () {
    expect(
      importCycles({
        'a': {'b', 'c'},
        'b': {'d'},
        'c': {'d'},
        'd': {},
      }),
      isEmpty,
    );
    expect(
      importCycles({
        'a': {'b'},
        'b': {'a'},
      }),
      ['a -> b -> a'],
    );
    expect(
      importCycles({
        'a': {'a'},
      }),
      ['a -> a'],
    );
  });

  test('own test files stay within the same size limit', () {
    final oversized = <String>[];
    for (final root in ['test', 'patrol_test']) {
      for (final file in Directory(
        root,
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart') ||
            file.path.contains('generated_migrations') ||
            file.path.endsWith('test_bundle.dart')) {
          continue;
        }
        if (file.readAsLinesSync().length > 800) oversized.add(file.path);
      }
    }
    expect(oversized, isEmpty);
  });

  test('new dependency cycles cannot enter the app', () {
    final graph = <String, Set<String>>{};
    final imports = RegExp(r"(?:import|export)\s+'package:holybeans/([^']+)'");
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') ||
          file.path.endsWith('.g.dart') ||
          file.path.contains('l10n')) {
        continue;
      }
      graph[path.posix.joinAll(path.split(file.path))] = {
        for (final match in imports.allMatches(file.readAsStringSync()))
          'lib/${match[1]}',
      };
    }
    expect(importCycles(graph), isEmpty);
  });

  test('application files stay small and data/domain do not depend on presentation', () {
    final violations = <String>[];
    // Existing domain adapters use the immutable generated journal rows.
    // This documented exception does not permit new database dependencies.
    const journalRowAdapters = {
      'brew_stats.dart',
      'stats_insights.dart',
      'stock.dart',
      'tool_catalog.dart',
    };
    final imports = RegExp(r'''(?:import|export)\s+['"]([^'"]+)['"]''');
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (path.extension(file.path) != '.dart' ||
          file.path.endsWith('.g.dart') ||
          path.split(file.path).contains('l10n')) {
        continue;
      }
      final source = file.readAsStringSync();
      final segments = path.split(file.path);
      final layer = segments[1];
      if (layer == 'domain' && source.contains('DateTime.now(')) {
        violations.add('${file.path}: pass the current time into domain logic');
      }
      if (source.split('\n').length - 1 > 800) {
        violations.add('${file.path}: over 800 lines');
      }
      for (final match in imports.allMatches(source)) {
        final uri = match.group(1)!;
        if (!uri.startsWith('dart:') && !uri.startsWith('package:')) {
          violations.add('${file.path}: use a package import for $uri');
        }
        if (layer == 'ui' && uri.startsWith('package:drift/')) {
          violations.add('${file.path}: SQL access belongs in data');
        }
        if (layer == 'data' || layer == 'domain') {
          if (uri.contains('/ui/') ||
              uri.contains('/l10n/') ||
              uri == 'package:holybeans/main.dart') {
            violations.add('${file.path}: presentation dependency $uri');
          }
        }
        if (layer == 'domain') {
          if (uri.startsWith('package:flutter/') || uri == 'dart:ui') {
            violations.add('${file.path}: Flutter dependency');
          }
          if (uri == 'dart:io') {
            violations.add('${file.path}: platform I/O belongs in data');
          }
          if (uri.contains('/data/') &&
              !(uri.endsWith('/data/database/app_database.dart') &&
                  journalRowAdapters.contains(path.basename(file.path)))) {
            violations.add('${file.path}: undocumented data dependency $uri');
          }
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
