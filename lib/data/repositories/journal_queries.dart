import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/repositories/tool_catalog.dart';
import 'package:holybeans/domain/frozen_brew.dart';
import 'package:holybeans/domain/shot_curve.dart';

/// Read-only journal access for presentation; never exposes its repository.
class JournalQueries {
  JournalQueries(this._repository);
  final JournalRepository _repository;
  Future<Brew?> brew(String id) => _repository.brew(id);
  Future<({ShotCurve curve, String source})?> brewCurve(String brewId) =>
      _repository.brewCurve(brewId);
  Future<List<CoffeeLot>> coffeeLots(String coffeeId) =>
      _repository.coffeeLots(coffeeId);
  Future<CoffeeLot?> coffeeLot(String lotId) => _repository.coffeeLot(lotId);
  Future<List<CoffeeComponent>> coffeeComponents(String coffeeId) =>
      _repository.coffeeComponents(coffeeId);
  Future<List<String>> coffeePhotos(String coffeeId) =>
      _repository.coffeePhotos(coffeeId);
  Future<List<String>> brewPhotos(String brewId) =>
      _repository.brewPhotos(brewId);
  Stream<List<String>> watchCoffeePhotos(String coffeeId) =>
      _repository.watchCoffeePhotos(coffeeId);
  Stream<List<String>> watchBrewPhotos(String brewId) =>
      _repository.watchBrewPhotos(brewId);
  Stream<List<StockAdjustment>> watchStockAdjustments({
    String? coffeeId,
    bool activeOnly = false,
  }) => _repository.watchStockAdjustments(
    coffeeId: coffeeId,
    activeOnly: activeOnly,
  );
  Stream<List<Coffee>> watchCoffees({bool includeArchived = false}) =>
      _repository.watchCoffees(includeArchived: includeArchived);
  Stream<List<CoffeeLot>> watchLots() => _repository.watchLots();
  Future<ToolCatalog> toolCatalog() => _repository.toolCatalog();
  Future<List<String>> brewToolIds(String brewId) =>
      _repository.brewToolIds(brewId);
  Future<BrewStockReturn> brewStockReturn(Brew brew) =>
      _repository.brewStockReturn(brew);
  Stream<List<FrozenPortion>> watchFrozenPortions() =>
      _repository.watchFrozenPortions();
  Stream<List<Brew>> watchAnalytics() => _repository.reads.watchAnalytics();
}
