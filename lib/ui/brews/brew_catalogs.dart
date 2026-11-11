import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/profile_suggestions.dart';

/// Catalog snapshots and loading state, with subscriptions owned by the form.
class BrewCatalogs extends ChangeNotifier {
  BrewCatalogs({
    required this.repository,
    required this.onMethods,
    required this.onMethodsReady,
    required this.onGrinders,
    required this.onWaterProfiles,
    required this.onRecipients,
    required this.onLots,
  });
  final JournalRepository repository;
  final void Function(List<BrewMethod>) onMethods;
  final VoidCallback onMethodsReady;
  final void Function(List<Grinder>) onGrinders;
  final void Function(List<WaterProfile>) onWaterProfiles;
  final void Function(List<Recipient>) onRecipients;
  final void Function(List<CoffeeLot>, String?) onLots;
  List<BrewMethod> _methods = const [];
  List<Grinder> _grinders = const [];
  List<WaterProfile> _waterProfiles = const [];
  List<Recipient> _recipients = [];
  List<CoffeeLot> _lots = const [];
  bool _loadingMethods = true;
  bool _loadingGrinders = true;
  bool _loadingWaterProfiles = true;
  bool _loadingRecipients = true;
  bool _loadingLots = true;
  ProfileSuggestions? _profiles;
  List<BrewMethod> get methods => _methods;
  List<Grinder> get grinders => _grinders;
  List<WaterProfile> get waterProfiles => _waterProfiles;
  List<Recipient> get recipients => _recipients;
  List<CoffeeLot> get lots => _lots;
  bool get loadingMethods => _loadingMethods;
  bool get loadingGrinders => _loadingGrinders;
  bool get loadingWaterProfiles => _loadingWaterProfiles;
  bool get loadingRecipients => _loadingRecipients;
  bool get loadingLots => _loadingLots;
  ProfileSuggestions? get profiles => _profiles;
  void prepareLots({bool clear = false, bool loading = true}) {
    if (clear) _lots = const [];
    _loadingLots = loading;
  }

  final _subscriptions = <StreamSubscription<Object?>>[];
  final _errors = <String>{};
  bool get hasError => _errors.isNotEmpty;
  bool get lotsFailed => _errors.contains('lots');
  bool _disposed = false;
  int _lotRequest = 0;

  void watch() {
    _watch('recipients', repository.watchRecipients(includeArchived: true), (
      rows,
    ) {
      _recipients = rows;
      _loadingRecipients = false;
      onRecipients(rows);
    }, onError: () => _loadingRecipients = false);
    _watch(
      'methods',
      repository.watchMethods(includeArchived: true),
      (rows) {
        _methods = rows;
        _loadingMethods = false;
        onMethods(rows);
      },
      onError: () => _loadingMethods = false,
      after: onMethodsReady,
    );
    _watch('grinders', repository.watchGrinders(includeArchived: true), (rows) {
      _grinders = rows;
      _loadingGrinders = false;
      onGrinders(rows);
    }, onError: () => _loadingGrinders = false);
    _watch('water', repository.watchWaterProfiles(includeArchived: true), (
      rows,
    ) {
      _waterProfiles = rows;
      _loadingWaterProfiles = false;
      onWaterProfiles(rows);
    }, onError: () => _loadingWaterProfiles = false);
  }

  void _watch<T>(
    String key,
    Stream<T> stream,
    void Function(T) onData, {
    required VoidCallback onError,
    VoidCallback? after,
  }) {
    _subscriptions.add(
      stream.listen(
        (rows) {
          if (_disposed) return;
          _errors.remove(key);
          onData(rows);
          _notify();
          after?.call();
        },
        onError: (Object error, StackTrace stack) {
          reportError(error, stack);
          if (_disposed) return;
          _errors.add(key);
          onError();
          _notify();
        },
      ),
    );
  }

  Future<void> restart() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    if (_disposed) return;
    _loadingMethods = _loadingGrinders = _loadingWaterProfiles =
        _loadingRecipients = true;
    watch();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadProfileSuggestions() async {
    try {
      final loaded = await repository.profileSuggestions();
      if (_disposed) return;
      _profiles = loaded;
      _notify();
    } catch (error, stack) {
      // Suggestions are optional: a failed read must not block free text/save.
      reportError(error, stack);
    }
  }

  Future<void> loadLots(String selectedCoffeeId, {String? preferred}) async {
    final request = ++_lotRequest;
    _errors.remove('lots');
    List<CoffeeLot> rows;
    try {
      rows = await repository.coffeeLots(selectedCoffeeId);
    } catch (error, stack) {
      reportError(error, stack);
      if (_disposed || request != _lotRequest) return;
      _errors.add('lots');
      _loadingLots = false;
      _notify();
      return;
    }
    if (_disposed || request != _lotRequest) return;
    _lots = rows;
    onLots(rows, preferred);
    _loadingLots = false;
    _notify();
  }

  List<T> _inserted<T>(
    List<T> rows,
    T row,
    String Function(T) id,
    String Function(T) name,
  ) =>
      [...rows.where((other) => id(other) != id(row)), row]
        ..sort((a, b) => name(a).compareTo(name(b)));
  void insertMethod(BrewMethod value) {
    _methods = _inserted(_methods, value, (r) => r.id, (r) => r.name);
  }

  void insertGrinder(Grinder value) {
    _grinders = _inserted(_grinders, value, (r) => r.id, (r) => r.name);
  }

  void insertWaterProfile(WaterProfile value) {
    _waterProfiles = _inserted(
      _waterProfiles,
      value,
      (r) => r.id,
      (r) => r.name,
    );
  }

  void publish() => _notify();
  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}
