part of '../journal_repository.dart';

extension PhotoOperations on JournalRepository {
  static const maxPhotos = PhotoRepository.maxPhotos;
  Stream<List<String>> watchCoffeePhotos(String coffeeId) =>
      photoRecords.watchCoffeePhotos(coffeeId);
  Future<List<String>> coffeePhotos(String coffeeId) =>
      photoRecords.coffeePhotos(coffeeId);
  Stream<List<String>> watchBrewPhotos(String brewId) =>
      photoRecords.watchBrewPhotos(brewId);
  Future<List<String>> brewPhotos(String brewId) =>
      photoRecords.brewPhotos(brewId);
  Future<List<String>> _unreferencedPhotos(List<String> files) =>
      photoRecords.unreferencedPhotos(files);

  /// The cover photo of every coffee that has one, by coffee ID.
  Stream<Map<String, String>> watchCoffeeCovers() =>
      photoRecords.watchCoffeeCovers();

  /// Replaces the photos of a coffee with [files], in that order.
  Future<void> setCoffeePhotos(String coffeeId, List<String> files) =>
      photoRecords.setCoffeePhotos(coffeeId, files);

  /// Replaces the photos of a brew with [files], in that order.
  Future<void> setBrewPhotos(String brewId, List<String> files) =>
      photoRecords.setBrewPhotos(brewId, files);
}
