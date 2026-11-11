import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';

/// Owns tool selections and ignores loads superseded by a method or user edit.
class BrewToolsModel extends ChangeNotifier {
  BrewToolsModel({
    required this.repository,
    required this.methodId,
    required this.existing,
    required this.selectedBrew,
  });
  final JournalRepository repository;
  final String? Function() methodId;
  final Brew? existing;
  final Brew? selectedBrew;
  final Set<String> _selectedIds = {};
  List<MethodTool> _tools = const [];
  Map<String, int> _useCounts = const {};
  bool _loading = false;
  bool _savedLoaded = false;
  bool _touched = false;

  late final _selectionView = UnmodifiableSetView(_selectedIds);
  Set<String> get selectedIds => _selectionView;
  List<MethodTool> get tools => _tools;
  Map<String, int> get useCounts => _useCounts;
  bool get loading => _loading;
  bool get savedLoaded => _savedLoaded;
  bool get touched => _touched;
  int _edit = 0;
  int _request = 0;
  bool _disposed = false;
  final _errors = <String>{};
  bool get hasError => _errors.isNotEmpty;

  // The form publishes its composite selection change after these resets.
  void cancelPending() {
    ++_request;
    _loading = false;
  }

  void resetForMethod() {
    ++_request;
    _touched = false;
    _tools = const [];
    _selectedIds.clear();
  }

  void toggle(String id, bool selected) {
    ++_edit;
    _touched = true;
    selected ? _selectedIds.add(id) : _selectedIds.remove(id);
    _notify();
  }

  void publish() => _notify();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> loadSaved() async {
    final selectedBrew = this.selectedBrew;
    if (selectedBrew == null) {
      _savedLoaded = true;
      return;
    }
    final edit = _edit;
    final selectedMethod = methodId();
    List<String> ids;
    try {
      ids = await repository.brewToolIds(selectedBrew.id);
    } catch (error, stack) {
      reportError(error, stack);
      if (!_disposed) {
        _errors.add('savedTools');
        _notify();
      }
      return;
    }
    if (_disposed) return;
    _savedLoaded = true;
    _errors.remove('savedTools');
    if (edit == _edit && selectedMethod == methodId() && !_touched) {
      _selectedIds
        ..clear()
        ..addAll(ids);
      if (methodId() case final method?) {
        unawaited(load(method, preferredIds: ids.toSet()));
      }
    }
    _notify();
  }

  Future<void> load(
    String selectedMethodId, {
    Iterable<String> preferredIds = const [],
  }) async {
    final request = ++_request;
    _errors.remove('_tools');
    final toolsEdit = _edit;
    _loading = true;
    _notify();
    try {
      final catalog = await repository.toolCatalog();
      final retained = existing?.methodId == selectedMethodId
          ? await repository.brewToolIds(existing!.id)
          : const <String>[];
      final rows = catalog.forMethod(selectedMethodId, retainedIds: retained);
      if (_disposed || request != _request) return;
      final availableIds = rows.map((tool) => tool.id).toSet();
      _tools = rows;
      _useCounts = catalog.useCounts;
      _selectedIds
        ..removeWhere((id) => !availableIds.contains(id))
        ..addAll(
          toolsEdit == _edit
              ? preferredIds.where(availableIds.contains)
              : const <String>[],
        );
    } catch (error, stack) {
      reportError(error, stack);
      if (_disposed || request != _request) return;
      _errors.add('_tools');
    }
    _loading = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
