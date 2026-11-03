import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/home_coffees.dart';

typedef _Brew = ({String id, bool favorite, int at});

HomeCoffeeFacts _coffee(
  String id,
  FreshnessPhase? phase, {
  int? daysLeft,
  int? lastBrew,
  int created = 0,
}) => (
  id: id,
  phase: phase,
  daysLeft: daysLeft,
  lastBrewedAtMs: lastBrew,
  createdAtMs: created,
);

void main() {
  test('coffees to use soon go by urgency, ready ones by use', () {
    final home = homeCoffees([
      _coffee('aging-9', FreshnessPhase.aging, daysLeft: 9, lastBrew: 50),
      _coffee('stale', FreshnessPhase.stale, lastBrew: 10),
      _coffee('aging-2', FreshnessPhase.aging, daysLeft: 2, lastBrew: 5),
      _coffee(
        'aging-2-recent',
        FreshnessPhase.aging,
        daysLeft: 2,
        lastBrew: 90,
      ),
      _coffee('good-old', FreshnessPhase.good, daysLeft: 3, lastBrew: 20),
      _coffee('prime-new', FreshnessPhase.prime, daysLeft: 8, created: 7),
      _coffee('good-recent', FreshnessPhase.good, daysLeft: 1, lastBrew: 80),
      _coffee('resting-8', FreshnessPhase.degassing, daysLeft: 8),
      _coffee('resting-28', FreshnessPhase.degassing, daysLeft: 28),
      _coffee('undated', null),
    ]);
    expect(home.spendSoon, ['stale', 'aging-2-recent', 'aging-2']);
    expect(home.spendSoonCount, 4, reason: 'the fourth is left for Beans');
    expect(home.ready, ['good-recent', 'good-old', 'prime-new']);
    expect(home.readyCount, 3);
    expect(home.restingCount, 2);
    expect(home.resting, isEmpty, reason: 'neither was brewed');
    expect(home.waitingCount, 2);
    expect(home.firstReadyInDays, 8);
    expect(home.undatedCount, 1);
    expect(home.undated, isEmpty, reason: 'six already shown');
    expect(home.isEmpty, isFalse);
  });

  test('coffees without a roast date fill the room the others leave', () {
    final home = homeCoffees([
      _coffee('aging', FreshnessPhase.aging, daysLeft: 4),
      _coffee('undated-old', null, lastBrew: 10),
      _coffee('undated-new', null, created: 9),
      _coffee('undated-recent', null, lastBrew: 40),
      _coffee('undated-other', null, lastBrew: 20),
    ]);
    expect(home.spendSoon, ['aging']);
    expect(home.undated, ['undated-recent', 'undated-other', 'undated-old']);
    expect(home.undatedCount, 4);
  });

  test('a resting coffee already brewed can still be repeated', () {
    final home = homeCoffees([
      _coffee('brewed', FreshnessPhase.degassing, daysLeft: 3, lastBrew: 9),
      _coffee('waiting', FreshnessPhase.degassing, daysLeft: 12),
      _coffee('undated', null, lastBrew: 5),
    ]);
    expect(home.resting, ['brewed']);
    expect(home.restingCount, 2);
    expect(home.waitingCount, 1);
    expect(home.firstReadyInDays, 12, reason: 'of those not shown');
    expect(home.undated, ['undated']);
  });

  test('an empty pantry has no groups', () {
    final home = homeCoffees(const []);
    expect(home.isEmpty, isTrue);
    expect(home.firstReadyInDays, isNull);
  });

  test('Repeat starts from the favourite recipe, else the newest brew', () {
    _Brew? seed(List<_Brew> brews) => repeatSeed(
      brews,
      isFavorite: (b) => b.favorite,
      brewedAtMs: (b) => b.at,
    );
    expect(
      seed([
        (id: 'new', favorite: false, at: 30),
        (id: 'fav-old', favorite: true, at: 10),
        (id: 'fav-espresso', favorite: true, at: 20),
      ])?.id,
      'fav-espresso',
    );
    expect(
      seed([
        (id: 'old', favorite: false, at: 10),
        (id: 'new', favorite: false, at: 30),
      ])?.id,
      'new',
    );
    expect(seed(const []), isNull);
  });
}
