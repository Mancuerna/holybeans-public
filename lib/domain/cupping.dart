import 'dart:convert';

enum CuppingPhase { setup, infusion, cooling, tasting, review }

/// A cup's choices, including explicit overrides of the shared equipment.
class CuppingCupDraft {
  factory CuppingCupDraft.fromMap(Map<String, dynamic> map) {
    final rawScores = map['scores'];
    if (rawScores is! List || rawScores.length != 5) {
      throw const FormatException('Invalid cupping scores');
    }
    final cup =
        CuppingCupDraft(
            coffeeId: _id(map['coffeeId']),
            lotId: _id(map['lotId']),
            frozenPortionId: _id(map['frozenPortionId']),
          )
          ..commonGrinder = _bool(map['commonGrinder'])
          ..grinderId = _id(map['grinderId'])
          ..grindSetting = _text(map['grindSetting'])
          ..commonWater = _bool(map['commonWater'])
          ..waterProfileId = _id(map['waterProfileId'])
          ..rating = map['rating'] == null ? null : _number(map['rating'])
          ..scores = [
            for (final value in rawScores)
              if (value == null)
                null
              else if (value is int && value >= 1 && value <= 5)
                value
              else
                throw const FormatException('Invalid cupping score'),
          ]
          ..notEvaluated = _notEvaluated(map['notEvaluated'])
          ..notes = _text(map['notes']);
    for (var i = 0; i < 6; i++) {
      if (cup.notEvaluated[i] &&
          (i == 0 ? cup.rating != null : cup.scores[i - 1] != null)) {
        throw const FormatException('Evaluated and skipped cupping score');
      }
    }
    final rating = cup.rating;
    if (rating != null &&
        (rating < 0 || rating > 10 || rating * 2 != (rating * 2).round())) {
      throw const FormatException('Invalid cupping rating');
    }
    return cup;
  }
  CuppingCupDraft({this.coffeeId, this.lotId, this.frozenPortionId});

  String? coffeeId;
  String? lotId;
  String? frozenPortionId;
  bool commonGrinder = true;
  String? grinderId;
  String grindSetting = '';
  bool commonWater = true;
  String? waterProfileId;
  double? rating;
  List<int?> scores = List.filled(5, null);
  List<bool> notEvaluated = List.filled(6, false);
  String notes = '';

  bool get complete =>
      (rating != null || notEvaluated[0]) &&
      List.generate(
        5,
        (i) => scores[i] != null || notEvaluated[i + 1],
      ).every((done) => done);

  Map<String, Object?> toMap() => {
    'coffeeId': coffeeId,
    'lotId': lotId,
    'frozenPortionId': frozenPortionId,
    'commonGrinder': commonGrinder,
    'grinderId': grinderId,
    'grindSetting': grindSetting,
    'commonWater': commonWater,
    'waterProfileId': waterProfileId,
    'rating': rating,
    'scores': scores,
    'notEvaluated': notEvaluated,
    'notes': notes,
  };
}

/// Versioned session draft. No inventory is consumed until it is completed.
class CuppingDraft {
  factory CuppingDraft.fromJson(String source) {
    try {
      final raw = jsonDecode(source);
      if (raw is! Map<String, dynamic> ||
          raw['version'] != 1 ||
          raw['cups'] is! List) {
        throw const FormatException('Invalid cupping draft');
      }
      final draft =
          CuppingDraft(
              cups: [
                for (final map in raw['cups'] as List)
                  CuppingCupDraft.fromMap(map as Map<String, dynamic>),
              ],
            )
            ..name = _text(raw['name'])
            ..dose = _number(raw['dose'])
            ..water = _number(raw['water'])
            ..temperature = _number(raw['temperature'])
            ..waterEdited = _bool(raw['waterEdited'])
            ..grinderId = _id(raw['grinderId'])
            ..grindSetting = _text(raw['grindSetting'])
            ..waterProfileId = _id(raw['waterProfileId'])
            ..crustSeconds = _integer(raw['crustSeconds'])!
            ..tastingSeconds = _integer(raw['tastingSeconds'])!
            ..startedAtMs = _integer(raw['startedAtMs'])
            ..brokenAtMs = _integer(raw['brokenAtMs'])
            ..tastingAtMs = _integer(raw['tastingAtMs'])
            ..timerStartedAtMs = _integer(raw['timerStartedAtMs'])
            ..pausedAtMs = _integer(raw['pausedAtMs'])
            ..pausedTotalMs = _integer(raw['pausedTotalMs']) ?? 0
            ..sound = _bool(raw['sound'])
            ..blind = raw.containsKey('blind') && _bool(raw['blind'])
            ..revealed = raw.containsKey('revealed') && _bool(raw['revealed'])
            ..crustAlerted = _bool(raw['crustAlerted'])
            ..tastingAlerted = _bool(raw['tastingAlerted'])
            ..phase = CuppingPhase.values.byName(raw['phase'] as String);
      if (draft.cups.length < 2 ||
          draft.cups.length > 6 ||
          !draft.recipeValid ||
          (!draft.blind && draft.revealed) ||
          (draft.blind &&
              !draft.revealed &&
              (draft.phase == CuppingPhase.review ||
                  draft.cups.any(
                    (c) =>
                        c.coffeeId != null ||
                        c.lotId != null ||
                        c.frozenPortionId != null,
                  ))) ||
          (draft.revealed &&
              (draft.phase != CuppingPhase.review || !draft.scoringComplete)) ||
          draft.name.length > 120 ||
          draft.crustSeconds < 60 ||
          draft.crustSeconds > 600 ||
          draft.tastingSeconds <= draft.crustSeconds ||
          draft.tastingSeconds > 3600 ||
          draft.pausedTotalMs < 0 ||
          (draft.timerStartedAtMs != null && draft.startedAtMs == null) ||
          (draft.pausedAtMs != null &&
              (draft.timerStartedAtMs == null ||
                  draft.pausedAtMs! < draft.timerStartedAtMs!)) ||
          !switch (draft.phase) {
            CuppingPhase.setup =>
              draft.startedAtMs == null &&
                  draft.brokenAtMs == null &&
                  draft.tastingAtMs == null,
            CuppingPhase.infusion =>
              draft.startedAtMs != null &&
                  draft.brokenAtMs == null &&
                  draft.tastingAtMs == null,
            CuppingPhase.cooling =>
              draft.startedAtMs != null &&
                  draft.brokenAtMs != null &&
                  draft.tastingAtMs == null,
            CuppingPhase.tasting || CuppingPhase.review =>
              draft.startedAtMs != null &&
                  draft.brokenAtMs != null &&
                  draft.tastingAtMs != null,
          } ||
          (draft.brokenAtMs != null &&
              (draft.startedAtMs == null ||
                  draft.brokenAtMs! < draft.startedAtMs!)) ||
          (draft.tastingAtMs != null &&
              (draft.brokenAtMs == null ||
                  draft.tastingAtMs! < draft.brokenAtMs!))) {
        throw const FormatException('Invalid cupping session state');
      }
      return draft;
    } on Object {
      throw const FormatException('Invalid cupping draft');
    }
  }
  CuppingDraft({List<CuppingCupDraft>? cups})
    : cups = cups ?? [CuppingCupDraft(), CuppingCupDraft()];

  List<CuppingCupDraft> cups;
  String name = '';
  double dose = 11;
  double water = 200;
  double temperature = 93;
  bool waterEdited = false;
  String? grinderId;
  String grindSetting = '';
  String? waterProfileId;
  int crustSeconds = 300;
  int tastingSeconds = 600;
  int? startedAtMs;
  int? brokenAtMs;
  int? tastingAtMs;
  int? timerStartedAtMs;
  int? pausedAtMs;
  int pausedTotalMs = 0;
  bool sound = true;
  bool blind = false;
  bool revealed = false;
  bool crustAlerted = false;
  bool tastingAlerted = false;
  CuppingPhase phase = CuppingPhase.setup;

  double get suggestedCapacity => dose * 150 / 8.25;
  bool get recipeValid =>
      dose.isFinite &&
      dose > 0 &&
      dose <= 1000 &&
      water.isFinite &&
      water > 0 &&
      water <= 10000 &&
      temperature.isFinite &&
      temperature > 0 &&
      temperature <= 100;
  bool get ready =>
      cups.length >= 2 &&
      cups.length <= 6 &&
      recipeValid &&
      (!blind || revealed) &&
      cups.every((c) => c.coffeeId != null && c.complete);
  bool get scoringComplete =>
      cups.length >= 2 && cups.length <= 6 && cups.every((c) => c.complete);
  bool get canReveal =>
      blind && !revealed && phase == CuppingPhase.tasting && scoringComplete;

  /// Once identities can be chosen, preserve the anonymous tasting results.
  bool preservesBlindResults(CuppingDraft previous) {
    if (previous.phase != CuppingPhase.setup && blind != previous.blind) {
      return false;
    }
    if (!previous.blind || !previous.revealed) return true;
    if (!blind || !revealed || cups.length != previous.cups.length) {
      return false;
    }
    for (var i = 0; i < cups.length; i++) {
      final a = cups[i];
      final b = previous.cups[i];
      if (a.rating != b.rating || a.notes != b.notes) return false;
      for (var j = 0; j < 6; j++) {
        if (a.notEvaluated[j] != b.notEvaluated[j]) return false;
      }
      for (var j = 0; j < 5; j++) {
        if (a.scores[j] != b.scores[j]) return false;
      }
    }
    return true;
  }

  int get scoredCount => cups.fold(
    0,
    (n, cup) =>
        n +
        (cup.rating != null || cup.notEvaluated[0] ? 1 : 0) +
        List.generate(
          5,
          (i) => cup.scores[i] != null || cup.notEvaluated[i + 1],
        ).where((done) => done).length,
  );
  int elapsedAt(int nowMs) => startedAtMs == null
      ? 0
      : ((nowMs -
                    (timerStartedAtMs ?? startedAtMs!) -
                    pausedTotalMs -
                    (pausedAtMs == null
                        ? 0
                        : (nowMs - pausedAtMs!).clamp(0, nowMs))) ~/
                1000)
            .clamp(0, 1 << 30);
  String? grinderFor(CuppingCupDraft cup) =>
      cup.commonGrinder ? grinderId : cup.grinderId;
  String settingFor(CuppingCupDraft cup) =>
      cup.commonGrinder ? grindSetting : cup.grindSetting;
  String? waterFor(CuppingCupDraft cup) =>
      cup.commonWater ? waterProfileId : cup.waterProfileId;

  void updateDose(double value) {
    dose = value;
    if (!waterEdited) water = suggestedCapacity;
  }

  String toJson() => jsonEncode({
    'version': 1,
    'name': name,
    'cups': cups.map((cup) => cup.toMap()).toList(),
    'dose': dose,
    'water': water,
    'temperature': temperature,
    'waterEdited': waterEdited,
    'grinderId': grinderId,
    'grindSetting': grindSetting,
    'waterProfileId': waterProfileId,
    'crustSeconds': crustSeconds,
    'tastingSeconds': tastingSeconds,
    'startedAtMs': startedAtMs,
    'brokenAtMs': brokenAtMs,
    'tastingAtMs': tastingAtMs,
    'timerStartedAtMs': timerStartedAtMs,
    'pausedAtMs': pausedAtMs,
    'pausedTotalMs': pausedTotalMs,
    'sound': sound,
    'blind': blind,
    'revealed': revealed,
    'crustAlerted': crustAlerted,
    'tastingAlerted': tastingAlerted,
    'phase': phase.name,
  });
}

String? _id(Object? value) => value == null
    ? null
    : switch (value) {
        final String s when s.isNotEmpty && s.length <= 120 => s,
        _ => throw const FormatException('Invalid cupping reference'),
      };
String _text(Object? value) => switch (value) {
  final String s when s.length <= 10000 => s,
  _ => throw const FormatException('Invalid cupping text'),
};
bool _bool(Object? value) =>
    value is bool ? value : throw const FormatException('Invalid cupping flag');
double _number(Object? value) => value is num && value.isFinite
    ? value.toDouble()
    : throw const FormatException('Invalid cupping number');
int? _integer(Object? value) => value == null
    ? null
    : switch (value) {
        final int n when n >= 0 && n <= 8640000000000000 => n,
        _ => throw const FormatException('Invalid cupping time'),
      };

List<bool> _notEvaluated(Object? value) {
  if (value == null) return List.filled(6, false);
  if (value is! List || value.length != 6 || value.any((v) => v is! bool)) {
    throw const FormatException('Invalid skipped cupping scores');
  }
  return value.cast<bool>().toList();
}

String formatCuppingDuration(int seconds) =>
    '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

int? parseCuppingDuration(String text) {
  final parts = text.trim().split(':');
  if (parts.length != 2 || parts[1].length != 2) return null;
  final minutes = int.tryParse(parts[0]);
  final seconds = int.tryParse(parts[1]);
  if (minutes == null ||
      seconds == null ||
      minutes < 0 ||
      seconds < 0 ||
      seconds > 59) {
    return null;
  }
  return minutes * 60 + seconds;
}
