import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/list_options_settings.dart';
import 'package:holybeans/data/repositories/journal_data.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/list_options.dart';
import 'package:holybeans/ui/shell/journal_view_model.dart';

void main() {
  test('journal snapshots own their collections', () {
    final coffees = <Coffee>[];
    final covers = <String, String>{};
    final data = JournalData(
      coffees: coffees,
      brews: [],
      lots: [],
      components: [],
      covers: covers,
    );
    covers['later'] = 'photo.jpg';
    expect(data.covers, isEmpty);
    expect(() => data.covers['x'] = 'other.jpg', throwsUnsupportedError);
    expect(data.coffees.clear, throwsUnsupportedError);
  });

  late AppDatabase database;
  late JournalRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = JournalRepository(database);
  });
  tearDown(() => database.close());

  JournalViewModel open() => JournalViewModel(
    repository: repository,
    parameterSettings: BrewParameterSettings(database),
    listOptionsSettings: ListOptionsSettings(database),
  );

  /// Waits until the view model has every list, or [test] holds.
  Future<void> settle(JournalViewModel journal, [bool Function()? test]) =>
      pumpEventQueue().then((_) async {
        for (var i = 0; i < 50; i++) {
          if (!journal.loading && (test?.call() ?? true)) return;
          await pumpEventQueue();
        }
        fail('the journal did not load');
      });

  test('loads the journal and follows its changes', () async {
    final journal = open();
    addTearDown(journal.dispose);
    var notified = 0;
    journal.addListener(() => notified++);
    expect(journal.loading, isTrue);

    await settle(journal);
    expect(journal.hasError, isFalse);
    expect(journal.data.coffees, isEmpty);
    expect(journal.everyCoffeeArchived, isTrue, reason: 'no coffee yet');

    final kenya = await repository.createCoffee(
      name: 'Kenya',
      roaster: 'North',
    );
    await settle(journal, () => journal.coffees.isNotEmpty);
    expect(journal.data.coffees.single.name, 'Kenya');
    expect(journal.everyCoffeeArchived, isFalse);
    expect(notified, greaterThan(0));

    final lot = (await repository.coffeeLots(kenya)).single.id;
    await repository.createBrew(
      coffeeId: kenya,
      lotId: lot,
      methodName: 'V60',
      brewedAt: DateTime(2026, 10, 6, 9),
    );
    await settle(journal, () => journal.data.brews.isNotEmpty);
    expect(journal.latestUsableBrew?.methodName, 'V60');

    // A brew of an archived coffee is not one to start from.
    await repository.setCoffeeArchived(kenya, archived: true);
    await settle(journal, () => journal.everyCoffeeArchived);
    expect(journal.latestUsableBrew, isNull);
  });

  test('reuses snapshots until journal rows change', () async {
    final journal = open();
    addTearDown(journal.dispose);
    await settle(journal);
    final before = journal.data;
    expect(journal.data, same(before));
    journal.changeListOptions(const ListOptions(brewsCompact: true));
    expect(journal.data, same(before));
    await repository.createCoffee(name: 'New', roaster: 'Test');
    await settle(journal, () => journal.coffees.isNotEmpty);
    expect(journal.data, isNot(same(before)));
    expect(before.coffees, isEmpty);
    expect(journal.data, same(journal.data));
  });

  test('keeps the list options for the next launch', () async {
    final journal = open();
    addTearDown(journal.dispose);
    expect(await journal.loadListOptions(), isA<ListOptions>());
    journal.changeListOptions(const ListOptions(brewsCompact: true));
    expect(journal.listOptions.brewsCompact, isTrue);
    await pumpEventQueue();

    final next = open();
    addTearDown(next.dispose);
    expect((await next.loadListOptions()).brewsCompact, isTrue);
    expect(next.listOptions.brewsCompact, isTrue);
  });

  test('a late settings load cannot undo a new list choice', () async {
    final settings = _DelayedListOptions(database);
    final journal = JournalViewModel(
      repository: repository,
      parameterSettings: BrewParameterSettings(database),
      listOptionsSettings: settings,
    );
    addTearDown(journal.dispose);
    final loading = journal.loadListOptions();
    const chosen = ListOptions(brewsCompact: true, showArchivedBrews: true);
    journal.changeListOptions(chosen);
    settings.pending.complete(const ListOptions());
    final loaded = await loading;
    expect(journal.listOptions, same(chosen));
    // The shell also uses the returned options for the history filters.
    expect(loaded, same(chosen));
    expect(settings.writes, [chosen]);
  });

  test(
    'list setting failures are contained and a later save still works',
    () async {
      final settings = _DelayedListOptions(database)..failSaves = true;
      final journal = JournalViewModel(
        repository: repository,
        parameterSettings: BrewParameterSettings(database),
        listOptionsSettings: settings,
      );
      addTearDown(journal.dispose);
      final loading = journal.loadListOptions();
      settings.pending.completeError(StateError('Read failed'));
      expect((await loading).brewsCompact, isFalse);
      journal.changeListOptions(const ListOptions(brewsCompact: true));
      await pumpEventQueue();
      settings.failSaves = false;
      const next = ListOptions(beansCompact: true);
      journal.changeListOptions(next);
      await pumpEventQueue();
      expect(settings.writes, [next]);
    },
  );

  test('stops notifying once disposed', () async {
    final journal = open()..dispose();
    // Rows arriving after disposal must not reach a disposed notifier.
    await repository.createCoffee(name: 'Late', roaster: 'Nobody');
    await pumpEventQueue();
    expect(journal.coffees, isEmpty);
  });
}

class _DelayedListOptions extends ListOptionsSettings {
  _DelayedListOptions(super.database);
  final pending = Completer<ListOptions>();
  final writes = <ListOptions>[];
  bool failSaves = false;

  @override
  Future<ListOptions> load() => pending.future;

  @override
  Future<void> save(ListOptions options) async {
    if (failSaves) throw StateError('Write failed');
    writes.add(options);
  }
}
