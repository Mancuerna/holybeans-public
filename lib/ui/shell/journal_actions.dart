import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_data.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/bean_exchange.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/domain/freshness.dart';
import 'package:holybeans/domain/frozen_brew.dart';
import 'package:holybeans/ui/backup/backup_center.dart';

export 'package:holybeans/data/repositories/journal_data.dart';

/// What tabs, cards and sheets can ask the shell to do, and the services and
/// shared data they need. The shell implements it, so screens stay unaware
/// of navigation details and of each other.
abstract interface class JournalActions {
  JournalRepository get repository;

  /// Photo folder; null hides photo controls (e.g. in tests).
  PhotoStore? get photos;

  List<BrewMethod> get methods;

  /// Parameters hidden in Settings: not shown in forms, details or lists.
  Set<BrewParameter> get hiddenParameters;
  List<FrozenPortion> get portions;

  /// Latest lots, for sheets opened outside the shell's builder.
  List<CoffeeLot> get latestLots;

  /// The phase [coffee] is in today for [style], or for the style last
  /// brewed with it (see `freshnessToday`), worked out once per change of
  /// the journal.
  FreshnessToday? freshnessToday(Coffee coffee, {BrewStyle? style});

  void message(String text);

  /// Backups shared by Home and Settings: reminders, automatic copies and
  /// the daily copy folder.
  BackupCenter get backupCenter;

  Future<void> exportBackup();

  /// Saves today's copy to the chosen folder.
  Future<void> saveBackupToFolder();

  /// Picks the folder for daily copies and saves the first one.
  Future<void> chooseBackupFolder();

  /// Adds a coffee, or edits [existing].
  Future<void> addCoffee([Coffee? existing]);

  /// Adds a new coffee filled in from a shared [card].
  Future<void> addCoffeeFromCard(SharedBean card);

  /// Opens the details of the coffee with [id], when it exists.
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

    /// Opens a repeat on the values that usually change, with − and +.
    bool adjust = false,
  });

  Future<void> rateBrew(Brew brew, Coffee? coffee);
  Future<void> archiveBrew(Brew brew);

  /// Makes [brew] the favourite recipe of its coffee and method (replacing
  /// the one before), or unmarks it; false when it could not be saved.
  /// With [announce], a message says what changed.
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

  /// Asks to archive [coffee] with an optional final rating; true when done.
  Future<bool> confirmCoffeeArchive(
    Coffee coffee, {
    bool afterOverdraw = false,
  });

  void showCoffeeDetails(Coffee coffee, JournalData data);
  void showBrewDetails(Brew brew, Coffee? coffee, JournalData data);
  Future<void> compareBrew(Brew brew, JournalData data);

  /// Switches to the Beans tab showing the available ones.
  void showAllBeans();

  /// Switches to the history filtered to every brew of [coffee].
  void showBrewsOfCoffee(Coffee coffee);
}
