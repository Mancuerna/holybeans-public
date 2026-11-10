import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/pre_migration_copies.dart';
import 'package:holybeans/domain/pre_migration.dart';
import 'package:holybeans/ui/startup/startup_recovery.dart';

class ReadyCopies extends PreMigrationCopies {
  ReadyCopies({this.empty = false}) : super(Directory('unused'));
  final bool empty;
  final copy = PreMigrationCopy.parse(
    PreMigrationCopy.nameFor(37, DateTime.utc(2026, 10)),
  )!;
  final original = File('saved-journal.sqlite');
  @override
  Future<List<PreMigrationCopy>> list() async => empty ? [] : [copy];
  @override
  Future<List<File>> recoveryFiles(PreMigrationCopy copy) async => [original];
}

void main() {
  for (final locale in ['en', 'es']) {
    testWidgets('recovery is localized in $locale and shares a retained copy', (
      tester,
    ) async {
      final copies = ReadyCopies();
      List<File>? shared;
      await tester.pumpWidget(
        StartupRecoveryApp(
          error: StateError('cannot open journal'),
          locale: Locale(locale),
          openCopies: () async => copies,
          shareFiles: (files) async => shared = files,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          locale == 'en'
              ? 'Could not open your journal'
              : 'No se pudo abrir tu diario',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(find.text('Bad state: cannot open journal'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.share_outlined));
      await tester.pumpAndSettle();
      expect(shared, [copies.original]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an empty recovery folder is explained', (tester) async {
    await tester.pumpWidget(
      StartupRecoveryApp(
        error: StateError('database'),
        locale: const Locale('en'),
        openCopies: () async => ReadyCopies(empty: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No copies saved before an update were found.'),
      findsOneWidget,
    );
  });

  testWidgets('inaccessible copies do not hide the startup failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      StartupRecoveryApp(
        error: StateError('database'),
        locale: const Locale('en'),
        openCopies: () async => throw const FileSystemException('unavailable'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not open your journal'), findsOneWidget);
    expect(find.text('Could not read the saved copies.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed share can be attempted again', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      StartupRecoveryApp(
        error: StateError('database'),
        locale: const Locale('en'),
        openCopies: () async => ReadyCopies(),
        shareFiles: (_) async {
          if (++attempts == 1) throw StateError('share failed');
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.share_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Could not share'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.share_outlined));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Could not share'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
