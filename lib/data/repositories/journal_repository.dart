import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/beanconqueror_repository.dart';
import 'package:holybeans/data/repositories/brew_recipe_context.dart';
import 'package:holybeans/data/repositories/brew_recipe_queries.dart';
import 'package:holybeans/data/repositories/brew_repository.dart';
import 'package:holybeans/data/repositories/brew_stock_ledger.dart';
import 'package:holybeans/data/repositories/brew_writer.dart';
import 'package:holybeans/data/repositories/cafe_repository.dart';
import 'package:holybeans/data/repositories/coffee_profile_writer.dart';
import 'package:holybeans/data/repositories/coffee_repository.dart';
import 'package:holybeans/data/repositories/cupping_repository.dart';
import 'package:holybeans/data/repositories/cupping_share.dart';
import 'package:holybeans/data/repositories/equipment_repository.dart';
import 'package:holybeans/data/repositories/extraction_profile_repository.dart';
import 'package:holybeans/data/repositories/freezer_repository.dart';
import 'package:holybeans/data/repositories/journal_inputs.dart';
import 'package:holybeans/data/repositories/journal_read_queries.dart';
import 'package:holybeans/data/repositories/journal_record_queries.dart';
import 'package:holybeans/data/repositories/photos_repository.dart';
import 'package:holybeans/data/repositories/piston_repository.dart';
import 'package:holybeans/data/repositories/recipients_repository.dart';
import 'package:holybeans/data/repositories/recordings_repository.dart';
import 'package:holybeans/data/repositories/stock.dart';
import 'package:holybeans/data/repositories/stock_adjustment_repository.dart';
import 'package:holybeans/data/repositories/tool_catalog.dart';
import 'package:holybeans/data/repositories/tools_repository.dart';
import 'package:holybeans/data/services/meticulous_client.dart';
import 'package:holybeans/data/services/meticulous_free_pour.dart';
import 'package:holybeans/domain/bean_exchange.dart';
import 'package:holybeans/domain/beanconqueror/bq_import_plan.dart';
import 'package:holybeans/domain/brew_input.dart';
import 'package:holybeans/domain/brew_pours.dart';
import 'package:holybeans/domain/coffee_suggestions.dart';
import 'package:holybeans/domain/cupping.dart';
import 'package:holybeans/domain/flow_guide.dart';
import 'package:holybeans/domain/frozen_brew.dart';
import 'package:holybeans/domain/gaggimate/shot.dart';
import 'package:holybeans/domain/pour_plan.dart';
import 'package:holybeans/domain/pressure_guide.dart';
import 'package:holybeans/domain/profile_suggestions.dart';
import 'package:holybeans/domain/shot_curve.dart';

export 'package:holybeans/data/repositories/beanconqueror_repository.dart'
    show BqImportSummary;
export 'package:holybeans/data/repositories/catalog_validation.dart'
    show connectedMachines;
export 'package:holybeans/data/repositories/cupping_repository.dart'
    show CuppingStockException;
export 'package:holybeans/data/repositories/equipment_repository.dart'
    show EquipmentDeletionBlocker, EquipmentInUseException, WaterMinerals;
export 'package:holybeans/data/repositories/journal_inputs.dart';
export 'package:holybeans/data/repositories/stock_adjustment_repository.dart'
    show StockAdjustmentException;

part 'journal_repository/beanconqueror.dart';
part 'journal_repository/brews.dart';
part 'journal_repository/coffee_cards.dart';
part 'journal_repository/coffees.dart';
part 'journal_repository/cupping.dart';
part 'journal_repository/equipment.dart';
part 'journal_repository/equipment_deletion.dart';
part 'journal_repository/freezer.dart';
part 'journal_repository/frozen_brews.dart';
part 'journal_repository/imports.dart';
part 'journal_repository/photos.dart';
part 'journal_repository/recipients.dart';
part 'journal_repository/stock_adjustments.dart';
part 'journal_repository/stock_review.dart';
part 'journal_repository/tools.dart';

/// Composes journal aggregates and preserves the existing caller API.
class JournalRepository {
  JournalRepository(this.database);

  late final JournalRecordQueries records = JournalRecordQueries(database);
  late final StockAdjustmentRepository stockEdits = StockAdjustmentRepository(
    database,
    coffeeProfiles,
    records,
  );
  late final BrewStockLedger stock = BrewStockLedger(
    database,
    freezer,
    records,
  );
  late final FreezerRepository freezer = FreezerRepository(database);
  late final CoffeeRepository coffees = CoffeeRepository(
    database,
    freezer,
    photoRecords,
    coffeeProfiles,
    records,
  );
  late final BrewRepository brews = BrewRepository(
    database,
    photoRecords,
    recipients,
    records,
    stock,
    brewWriter,
  );
  late final CoffeeProfileWriter coffeeProfiles = CoffeeProfileWriter(
    database,
    stock,
  );
  late final CuppingRepository cupping = CuppingRepository(
    database,
    brews,
    equipment,
    freezer,
    records,
  );
  late final BrewWriter brewWriter = BrewWriter(
    database,
    equipment,
    photoRecords,
    recordings,
    records,
    tools,
  );

  late final PhotoRepository photoRecords = PhotoRepository(database);
  late final RecipientRepository recipients = RecipientRepository(database);
  late final EquipmentRepository equipment = EquipmentRepository(
    database,
    recipients,
  );
  late final ToolRepository tools = ToolRepository(database, equipment);
  late final RecordingRepository recordings = RecordingRepository(database);
  late final BeanconquerorRepository beanconqueror = BeanconquerorRepository(
    database,
    photoRecords,
    recordings,
  );

  late final CafeRepository cafes = CafeRepository(database);

  final AppDatabase database;
  late final extractionProfiles = ExtractionProfileRepository(database);
  late final PistonRepository piston = PistonRepository(database);
  late final _recipeQueries = BrewRecipeQueries(
    database,
    readToolIds: brewToolIds,
  );

  Future<Brew?> latestBrewFor({
    required String coffeeId,
    required String methodId,
    bool rated = false,
  }) => _recipeQueries.latestBrewFor(
    coffeeId: coffeeId,
    methodId: methodId,
    rated: rated,
  );

  Future<Brew?> favoriteBrewFor({
    required String coffeeId,
    required String methodId,
  }) => _recipeQueries.favoriteBrewFor(coffeeId: coffeeId, methodId: methodId);

  Future<Brew?> latestBrewForMethod(String methodId) =>
      _recipeQueries.latestBrewForMethod(methodId);

  Future<BrewReferences> dialInFor({
    required String coffeeId,
    required String methodId,
  }) => _recipeQueries.dialInFor(coffeeId: coffeeId, methodId: methodId);

  Future<BrewRecipeMemory?> methodMemory({
    required String? coffeeId,
    required String methodId,
  }) => _recipeQueries.methodMemory(coffeeId: coffeeId, methodId: methodId);

  late final reads = JournalReadQueries(database);

  Stream<List<Coffee>> watchCoffees({bool includeArchived = false}) =>
      records.watchCoffees(includeArchived: includeArchived);

  /// Everything the journal holds, archived records included, read once
  /// (for exports).
  Future<List<Coffee>> allCoffees() => records.allCoffees();

  Future<List<Brew>> allBrews() => records.allBrews();

  Future<ProfileSuggestions> profileSuggestions() => brews.profileSuggestions();

  Future<List<BrewMethod>> allMethods() => records.allMethods();

  Future<List<CoffeeLot>> allLots() => records.allLots();

  /// Fresh stock and dose history after saving; reads do not depend on streams
  /// having delivered the transaction yet.
  Future<StockArchiveSuggestion?> archiveSuggestionForBrew(String brewId) =>
      stock.archiveSuggestionForBrew(brewId);

  /// Reads suggestions once for a bean form, including archived coffees.
  Future<CoffeeSuggestions> coffeeSuggestions() => coffees.coffeeSuggestions();

  /// Every inventory record, archived ones included.
  Stream<List<CoffeeLot>> watchLots() => records.watchLots();

  /// Every coffee's origins, in their order.
  Stream<List<CoffeeComponent>> watchComponents() => records.watchComponents();

  Stream<List<BrewMethod>> watchMethods({bool includeArchived = false}) =>
      records.watchMethods(includeArchived: includeArchived);

  Stream<List<Grinder>> watchGrinders({bool includeArchived = false}) =>
      records.watchGrinders(includeArchived: includeArchived);

  Stream<List<WaterProfile>> watchWaterProfiles({
    bool includeArchived = false,
  }) => records.watchWaterProfiles(includeArchived: includeArchived);

  /// Container kinds offered when freezing coffee.
  static final frozenContainers = allowedFrozenContainers;
}
