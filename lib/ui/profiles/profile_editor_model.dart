import 'package:flutter/foundation.dart';
import 'package:holybeans/domain/extraction_profile.dart';
import 'package:holybeans/domain/flow_guide.dart';

class ProfileEditorModel extends ChangeNotifier {
  ProfileEditorModel(this.profile);
  ExtractionProfile profile;
  String active = 'flow';
  int selected = 0;
  bool dirty = false;
  final _past = <ExtractionProfile>[];
  final _future = <ExtractionProfile>[];
  ExtractionProfile? _gesture;
  bool get dragging => _gesture != null;
  List<GuidePoint> get points =>
      active == 'flow' ? profile.flow : profile.pressure;
  bool get canUndo => _past.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;

  void change(ExtractionProfile next) {
    if (next.encode() == profile.encode()) return;
    _past.add(profile);
    if (_past.length > 70) _past.removeAt(0);
    _future.clear();
    profile = next;
    dirty = true;
    _normalize();
  }

  void _normalize() {
    if ((active == 'flow' ? profile.flow : profile.pressure).isEmpty) {
      active = profile.primary;
    }
    selected = selected.clamp(0, points.length - 1);
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    _future.add(profile);
    profile = _past.removeLast();
    dirty = true;
    _normalize();
  }

  void redo() {
    if (!canRedo) return;
    _past.add(profile);
    profile = _future.removeLast();
    dirty = true;
    _normalize();
  }

  void select(String channel, [int index = 0]) {
    active = channel;
    selected = index;
    _normalize();
  }

  void setChannels(Set<String> channels) {
    if (channels.isEmpty) return;
    final example = ExtractionProfile.example(profile.id, profile.name);
    List<GuidePoint> channel(
      String key,
      List<GuidePoint> old,
      List<GuidePoint> defaults,
    ) => !channels.contains(key)
        ? []
        : old.isNotEmpty
        ? old
        : [
            for (final p in defaults)
              (
                elapsedMs:
                    (p.elapsedMs * profile.durationMs / example.durationMs)
                        .round(),
                value: p.value,
                breakBefore: p.breakBefore,
              ),
          ];
    change(
      profile.copyWith(
        flow: channel('flow', profile.flow, example.flow),
        pressure: channel('pressure', profile.pressure, example.pressure),
        primary: channels.contains(profile.primary)
            ? profile.primary
            : channels.first,
      ),
    );
  }

  void scaleDuration(int ms) {
    List<GuidePoint> scale(List<GuidePoint> points) => [
      for (final p in points)
        (
          elapsedMs: (p.elapsedMs * ms / profile.durationMs).round(),
          value: p.value,
          breakBefore: p.breakBefore,
        ),
    ];
    change(
      profile.copyWith(
        durationMs: ms,
        flow: scale(profile.flow),
        pressure: scale(profile.pressure),
      ),
    );
  }

  ExtractionProfile _withPoints(List<GuidePoint> next) => active == 'flow'
      ? profile.copyWith(flow: next)
      : profile.copyWith(pressure: next);
  void move(int i, int ms, double value, {bool dragging = false}) {
    final next = [...points];
    next[i] = (elapsedMs: ms, value: value, breakBefore: points[i].breakBefore);
    final updated = _withPoints(next);
    if (dragging) {
      profile = updated;
      dirty = true;
      notifyListeners();
    } else {
      change(updated);
    }
  }

  void beginDrag() {
    _gesture = profile;
  }

  void endDrag() {
    if (_gesture case final before? when before.encode() != profile.encode()) {
      _past.add(before);
      _future.clear();
    }
    _gesture = null;
    notifyListeners();
  }

  void add() {
    if (points.length >= 2000) return;
    final i = selected.clamp(0, points.length - 2);
    final a = points[i];
    final b = points[i + 1];
    if (b.elapsedMs - a.elapsedMs < 2) return;
    final next = [...points]
      ..insert(i + 1, (
        elapsedMs: (a.elapsedMs + b.elapsedMs) ~/ 2,
        value: (a.value + b.value) / 2,
        breakBefore: b.breakBefore,
      ));
    change(_withPoints(next));
    selected = i + 1;
    notifyListeners();
  }

  void remove(int i) {
    if (points.length <= 2 || i == 0 || i == points.length - 1) return;
    final next = [...points];
    if (next[i].breakBefore) {
      final following = next[i + 1];
      next[i + 1] = (
        elapsedMs: following.elapsedMs,
        value: following.value,
        breakBefore: true,
      );
    }
    next.removeAt(i);
    change(_withPoints(next));
  }
}
