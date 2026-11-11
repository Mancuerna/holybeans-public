import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/bean_exchange.dart';
import 'package:holybeans/domain/brew_pours.dart';

/// Journal writes used by cards and sheets, without exposing the full facade.
class JournalMutations {
  JournalMutations(this._repository);
  final JournalRepository _repository;
  Future<void> setCoffeeFavorite(String id, {required bool favorite}) =>
      _repository.setCoffeeFavorite(id, favorite: favorite);
  Future<void> setCoffeeArchived(
    String id, {
    required bool archived,
    double? rating,
  }) => _repository.setCoffeeArchived(id, archived: archived, rating: rating);
  Future<List<String>> deleteUnusedCoffee(String id) =>
      _repository.deleteUnusedCoffee(id);
  Future<String> createCoffeeFromCard(SharedBean bean) =>
      _repository.createCoffeeFromCard(bean);
  Future<void> setBrewPours(String brewId, BrewPours pours) =>
      _repository.setBrewPours(brewId, pours);
  Future<List<String>> deleteBrew(String id) => _repository.deleteBrew(id);
  Future<void> resolveBrewStockReview(String id, {required bool deduct}) =>
      _repository.resolveBrewStockReview(id, deduct: deduct);
  Future<Brew?> brew(String id) => _repository.brew(id);
}
