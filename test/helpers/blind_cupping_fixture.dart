import 'package:holybeans/domain/cupping.dart';

CuppingDraft blindTasting({int count = 2}) =>
    CuppingDraft(
        cups: [
          for (var i = 0; i < count; i++)
            CuppingCupDraft()
              ..rating = i == 0 ? 0 : 8.5
              ..scores = [1, 2, 3, 4, 5]
              ..notes = 'Cup ${String.fromCharCode(65 + i)} notes',
        ],
      )
      ..blind = true
      ..sound = false
      ..startedAtMs = 1000
      ..brokenAtMs = 241000
      ..tastingAtMs = 721000
      ..phase = CuppingPhase.tasting;
