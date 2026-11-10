import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/repositories/piston_repository.dart';
import 'package:holybeans/data/services/loffee_api.dart';
import 'package:holybeans/data/services/piston_history_client.dart';
import 'package:holybeans/data/services/pre_migration_copies.dart';
import 'package:holybeans/domain/loffee_bean.dart';
import 'package:holybeans/domain/meticulous/piston_analysis.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/loffee_search_page.dart';
import 'package:holybeans/ui/equipment/piston/piston_model.dart';

import 'helpers/fake_loffee.dart';
import 'helpers/piston_fake.dart';

void main() {
  late List<String> messages;
  Future<void> recordErrors(Future<void> Function() action) async {
    messages = [];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => messages.add(message ?? '');
    try {
      await action();
    } finally {
      debugPrint = original;
    }
  }

  for (final failure in ['open', 'sync', 'reload', 'save', 'delete']) {
    test(
      'piston $failure failure is reported while recovery is retained',
      () => recordErrors(() async {
        final source = FakePistonSource([]);
        final original = connectPistonHistory;
        connectPistonHistory = (_) => source;
        addTearDown(() => connectPistonHistory = original);
        final model = PistonModel(_PistonRepository(failure), 'method', 'test')
          ..data = const PistonSnapshot(serial: 'machine');
        addTearDown(model.dispose);
        const service = PistonService(id: 'service', timeMs: 0, kind: 'clean');
        switch (failure) {
          case 'open':
            await model.open();
            expect(model.loadFailed, isTrue);
            expect(model.loading, isFalse);
          case 'sync' || 'reload':
            await model.refresh();
            expect(source.closed, isTrue);
            expect(failure == 'sync' ? model.failed : model.loadFailed, isTrue);
          case 'save':
            expect(await model.save(service), isFalse);
          case 'delete':
            expect(await model.delete(service), isFalse);
        }
        expect(model.busy, isFalse);
        expect(messages.single, contains('$failure failure'));
      }),
    );
  }

  test(
    'pre-migration copy failure is reported without blocking startup',
    () => recordErrors(() async {
      final copies = PreMigrationCopies(Directory('unused-copy-test'));
      expect(
        await copies.keepIfUpgrading(_UnreadableJournal(), currentSchema: 38),
        isNull,
      );
      expect(messages.single, contains('Cannot read journal'));
    }),
  );

  for (final keyFailure in [true, false]) {
    testWidgets(
      'unexpected Loffee failure is reported, key=$keyFailure',
      (tester) => recordErrors(() async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LoffeeSearchPage(
              services: LoffeeServices(
                api: _FailingSearch(),
                keys: MemoryLoffeeKeys('test-only-key')..fail = keyFailure,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (!keyFailure) {
          await tester.enterText(
            find.byKey(const ValueKey('loffee-query')),
            'coffee',
          );
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('loffee-search')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('loffee-error')), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        expect(
          messages.single,
          contains(keyFailure ? 'credential failure' : 'Search failure'),
        );
      }),
    );
  }
}

class _PistonRepository extends Fake implements PistonRepository {
  _PistonRepository(this.failure);
  final String failure;
  @override
  Future<PistonSnapshot> load(String methodId) async {
    if (failure == 'open' || failure == 'reload') {
      throw StateError('$failure failure');
    }
    return const PistonSnapshot();
  }

  @override
  Future<void> sync(
    String methodId,
    PistonHistorySource source, {
    required bool Function() cancelled,
    required void Function(int) onProgress,
  }) async {
    if (failure == 'sync') throw StateError('sync failure');
  }

  @override
  Future<void> saveService(String serial, PistonService service) async =>
      throw StateError('save failure');
  @override
  Future<void> deleteService(String serial, String id) async =>
      throw StateError('delete failure');
}

class _UnreadableJournal extends Fake implements File {
  @override
  bool existsSync() => true;
  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      Stream.error(const FileSystemException('Cannot read journal'));
}

class _FailingSearch extends FakeLoffeeApi {
  @override
  Future<LoffeePage> search({
    required String key,
    required String query,
    int page = 1,
  }) async => throw StateError('Search failure');
}
