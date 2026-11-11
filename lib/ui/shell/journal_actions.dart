import 'dart:typed_data';

import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/freezer_repository.dart';
import 'package:holybeans/data/repositories/journal_data.dart';
import 'package:holybeans/data/repositories/journal_mutations.dart';
import 'package:holybeans/data/repositories/journal_queries.dart';
import 'package:holybeans/data/repositories/stock_adjustment_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/bean_exchange.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/frozen_brew.dart';
import 'package:holybeans/ui/backup/backup_center.dart';

export 'package:holybeans/data/repositories/journal_data.dart';

/// A route's dependencies grouped by purpose; leaf widgets take only their role.
class JournalActions {
  const JournalActions({
    required this.read,
    required this.navigation,
    required this.commands,
  });
  final JournalRead read;
  final JournalNavigation navigation;
  final JournalCommands commands;
}

/// Shared snapshots and queries, with no journal write API.
abstract interface class JournalRead {
  JournalQueries get queries;
  PhotoStore? get photos;
  List<BrewMethod> get methods;
  Set<BrewParameter> get hiddenParameters;
  List<FrozenPortion> get portions;
  List<CoffeeLot> get latestLots;
  FreshnessToday? freshnessToday(Coffee coffee, {BrewStyle? style});
}

/// Opens routes and sheets and presents messages for their callers.
abstract interface class JournalNavigation {
  void message(String text);
  Future<void> addCoffee([Coffee? existing]);
  Future<void> addCoffeeFromCard(
    SharedBean card, {
    String? initialNotes,
    String? roastLevelHint,
    Future<Uint8List> Function()? importPhoto,
  });
  void showCoffeeDetailsById(String id);
  void showRoasters({String? roaster});
  Future<void> openBrewForm(
    List<Coffee> coffees, {
    Brew? existing,
    Brew? seed,
    String? initialCoffeeId,
    String? initialLotId,
    double? initialDoseGrams,
    FrozenBrewSource? initialFrozenSource,
    String? initialMethodId,
    bool repeat = false,
    bool adjust = false,
  });
  void showCoffeeDetails(Coffee coffee, JournalData data);
  void showBrewDetails(Brew brew, Coffee? coffee, JournalData data);
  Future<void> compareBrew(Brew brew, JournalData data);
  void showAllBeans();
  void showBrewsOfCoffee(Coffee coffee);
}

/// Explicit edits and backup/share operations available to action controls.
abstract interface class JournalCommands {
  JournalMutations get mutations;
  FreezerRepository get freezer;
  StockAdjustmentRepository get stockEdits;
  ShareTemplateSettings get templateSettings;
  BackupCenter get backupCenter;
  Future<void> exportBackup();
  Future<void> saveBackupToFolder();
  Future<void> chooseBackupFolder();
  Future<void> rateBrew(Brew brew, Coffee? coffee);
  Future<void> archiveBrew(Brew brew);
  Future<bool> setBrewFavorite(
    Brew brew, {
    required bool favorite,
    bool announce = true,
  });
  Future<void> shareBrew(
    Brew brew,
    Coffee coffee,
    List<CoffeeComponent> components,
  );
  Future<bool> confirmCoffeeArchive(
    Coffee coffee, {
    bool afterOverdraw = false,
  });
}
