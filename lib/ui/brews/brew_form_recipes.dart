import 'package:holybeans/data/repositories/brew_recipe_context.dart';
import 'package:holybeans/ui/core/error_report.dart';

/// Only the newest recipe request can apply or end the loading state.
class BrewFormRecipes {
  BrewFormRecipes({
    required this._loadMemory,
    required this._loadReferences,
    required this.notify,
  });

  final LoadBrewMemory _loadMemory;
  final LoadBrewReferences _loadReferences;
  BrewRecipeMemory? _memory;
  BrewReferences? _references;
  BrewRecipeMemory? get memory => _memory;
  BrewReferences? get references => _references;
  int _referenceRequest = 0;
  final void Function() notify;
  int _request = 0;
  bool _loading = false;
  bool get loading => _loading;
  bool _disposed = false;

  Future<void> load({
    required String? coffeeId,
    required String methodId,
    required Future<void> Function(BrewRecipeMemory? memory) apply,
  }) async {
    final request = ++_request;
    _loading = true;
    notify();
    try {
      BrewRecipeMemory? memory;
      try {
        memory = await _loadMemory(coffeeId: coffeeId, methodId: methodId);
      } catch (error, stack) {
        reportError(error, stack);
      }
      if (_disposed || request != _request) return;
      _memory = memory;
      await apply(memory);
    } finally {
      if (!_disposed && request == _request) {
        _loading = false;
        notify();
      }
    }
  }

  /// Advice and notes do not block saving and have their own request sequence.
  Future<void> loadReferences({String? coffeeId, String? methodId}) async {
    final request = ++_referenceRequest;
    BrewReferences? found;
    if (coffeeId != null && methodId != null) {
      try {
        found = await _loadReferences(coffeeId: coffeeId, methodId: methodId);
      } catch (error, stack) {
        reportError(error, stack);
      }
    }
    if (_disposed || request != _referenceRequest) return;
    _references = found;
    notify();
  }

  void dispose() => _disposed = true;
}
