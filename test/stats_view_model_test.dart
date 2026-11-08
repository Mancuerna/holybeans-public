import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/ui/stats/stats_view_model.dart';

void main() {
  test(
    'large statistics run off-thread and publish the latest complete request',
    () async {
      final model = StatsViewModel();
      addTearDown(model.dispose);
      StatsRequest request(int count) => (
        brews: [
          for (var i = 0; i < count; i++)
            Brew(
              recipientIsPortafilter: false,
              id: 'b$i',
              coffeeId: 'coffee',
              methodName: 'V60',
              isFavorite: false,
              isPreGround: false,
              brewedAtMs: i * 86400000,
              createdAtMs: i,
              updatedAtMs: i,
              doseGrams: 18,
              rating: 8,
            ),
        ],
        coffees: const [],
        components: const [],
        methods: const [],
        lots: const [],
        prices: const {},
        range: StatsRange.all,
        now: DateTime(2026),
        language: 'en',
        remaining: 100,
        frozen: 50,
      );
      final done = Completer<void>();
      model.addListener(() {
        if ((model.value != null || model.error != null) && !done.isCompleted) {
          done.complete();
        }
      });
      model.update(request(300));
      expect(model.value, isNull);
      model.update(request(450));
      await done.future.timeout(const Duration(seconds: 30));
      expect(model.error, isNull);
      expect(model.value!.stats.count, 450);
      expect(model.value!.stats.groundGrams, 8100);
      expect(model.value!.allBrews, hasLength(450));
      expect(
        model.value!.activity.values.fold<int>(0, (sum, count) => sum + count),
        450,
      );
      expect(model.value!.consumption.single.brewCount, 450);
    },
  );
}
