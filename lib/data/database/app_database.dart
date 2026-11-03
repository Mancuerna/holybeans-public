import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:holybeans/data/database/schema_steps.g.dart' as schemas;
import 'package:holybeans/data/services/journal_write_gate.dart';
import 'package:holybeans/domain/beanconqueror/bq_values.dart';
import 'package:holybeans/domain/favorite_brews.dart';
import 'package:holybeans/domain/roaster_profile.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

part 'app_database.g.dart';
part 'cafe_tables.dart';
part 'cupping_tables.dart';
part 'recipient_migration.dart';
part 'roaster_registry.dart';
part 'stock_tables.dart';
part 'piston_tables.dart';

class Coffees extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get roaster => text().withLength(max: 200)();
  TextColumn get notes => text().nullable()();
  IntColumn get paidPriceCents => integer().nullable()();
  RealColumn get rating => real().nullable()();
  TextColumn get roastLevel => text().nullable()();

  /// Comma-separated tasting notes, e.g. "Nectarine, jasmine".
  TextColumn get flavorProfile => text().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isDecaf => boolean().withDefault(const Constant(false))();

  /// Web page of the coffee in the roaster's shop.
  TextColumn get shopUrl => text().nullable()();

  /// Rest the roaster recommends before brewing, in days after roasting.
  IntColumn get restDays => integer().nullable()();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();
  IntColumn get archivedAtMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class CoffeeComponents extends Table {
  TextColumn get id => text()();
  TextColumn get coffeeId =>
      text().references(Coffees, #id, onDelete: KeyAction.restrict)();
  IntColumn get position => integer()();
  TextColumn get country => text().nullable()();
  TextColumn get region => text().nullable()();
  TextColumn get farm => text().nullable()();
  TextColumn get producer => text().nullable()();
  TextColumn get variety => text().nullable()();
  TextColumn get process => text().nullable()();
  IntColumn get altitudeMeters => integer().nullable()();
  IntColumn get altitudeMaxMeters => integer().nullable()();

  /// When the cherries were picked, as written, e.g. "2025" or "Jan 2025".
  TextColumn get harvest => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {coffeeId, position},
  ];
}

class CoffeeLots extends Table {
  TextColumn get id => text()();
  TextColumn get coffeeId =>
      text().references(Coffees, #id, onDelete: KeyAction.restrict)();
  TextColumn get roastDate => text().nullable()();
  TextColumn get purchaseDate => text().nullable()();
  TextColumn get openedDate => text().nullable()();
  RealColumn get initialGrams => real().nullable()();
  RealColumn get remainingGrams => real().nullable()();
  RealColumn get overdrawGrams => real().nullable()();

  /// Days the unfrozen coffee spent in the freezer, subtracted from its age
  /// after roasting. Set when a portion is thawed into an empty lot.
  IntColumn get frozenPauseDays => integer().nullable()();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();
  IntColumn get archivedAtMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Coffee taken out of a lot and kept in the freezer. The lot's
/// `remainingGrams` counts only unfrozen coffee; freezing moves grams here and
/// thawing moves them back, so brews keep drawing from the fresh balance.
class FrozenPortions extends Table {
  TextColumn get id => text()();
  TextColumn get lotId =>
      text().references(CoffeeLots, #id, onDelete: KeyAction.restrict)();

  /// Short code to write on the container, unique across portions.
  TextColumn get label => text().withLength(min: 1, max: 12)();
  TextColumn get container => text().nullable()();

  /// Local calendar date (ISO `yyyy-MM-dd`) when the coffee was frozen.
  TextColumn get frozenDate => text()();
  RealColumn get initialGrams => real()();
  RealColumn get remainingGrams => real()();
  TextColumn get notes => text().nullable()();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();

  /// Set when the last grams are thawed.
  IntColumn get thawedAtMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {label},
  ];
}

class Recipients extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  RealColumn get emptyGrams => real()();
  IntColumn get archivedAtMs => integer().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class BrewMethods extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get category => text().nullable()();
  TextColumn get templateType => text().nullable()();
  TextColumn get notes => text().nullable()();

  /// Connected machine behind the method, e.g. "meticulous"; null for
  /// manual methods.
  TextColumn get machine => text().nullable()();

  /// Network address of [machine], e.g. "192.168.1.50".
  TextColumn get machineAddress => text().nullable()();

  /// Filter and immersion methods: the jug the coffee is weighed in, whose
  /// empty weight is taken off the full one to get the beverage.
  TextColumn get vesselName => text().nullable()();
  RealColumn get vesselGrams => real().nullable()();

  TextColumn get defaultRecipientId => text().nullable().references(
    Recipients,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// The guided pour recipe last used with this method (PourPlan.toJson).
  TextColumn get pourPlanJson => text().nullable()();
  IntColumn get archivedAtMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class WaterProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  RealColumn get ghPpmAsCaCO3 => real().named('gh_ppm_as_caco3').nullable()();
  RealColumn get khPpmAsCaCO3 => real().named('kh_ppm_as_caco3').nullable()();
  RealColumn get tdsPpm => real().nullable()();
  RealColumn get ph => real().nullable()();

  /// Dissolved minerals in ppm (mg/l) of the ion itself.
  RealColumn get calciumPpm => real().nullable()();
  RealColumn get magnesiumPpm => real().nullable()();
  RealColumn get sodiumPpm => real().nullable()();
  RealColumn get potassiumPpm => real().nullable()();
  RealColumn get chloridePpm => real().nullable()();
  RealColumn get sulfatePpm => real().nullable()();
  RealColumn get bicarbonatePpm => real().nullable()();
  TextColumn get recipeJson => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get archivedAtMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Grinders extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get notes => text().nullable()();

  /// Whether the grinder's motor speed can be set, so brews record RPM.
  BoolColumn get hasAdjustableFeederRpm =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get hasAdjustableRpm =>
      boolean().withDefault(const Constant(false))();
  IntColumn get archivedAtMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class MethodTools extends Table {
  TextColumn get id => text()();
  // Original owner, retained for old backups and import provenance. Current
  // compatibility is represented by ToolMethodLinks, not this column.
  TextColumn get methodId => text().nullable().references(
    BrewMethods,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  IntColumn get archivedAtMs => integer().nullable()();
  // An explicitly merged tool keeps its identity and historical references.
  TextColumn get mergedIntoId => text().nullable().references(
    MethodTools,
    #id,
    onDelete: KeyAction.restrict,
  )();

  @override
  Set<Column> get primaryKey => {id};
}

class ToolMethodLinks extends Table {
  TextColumn get toolId =>
      text().references(MethodTools, #id, onDelete: KeyAction.restrict)();
  TextColumn get methodId =>
      text().references(BrewMethods, #id, onDelete: KeyAction.restrict)();

  @override
  Set<Column> get primaryKey => {toolId, methodId};
}

class Brews extends Table {
  TextColumn get id => text()();
  TextColumn get coffeeId =>
      text().references(Coffees, #id, onDelete: KeyAction.restrict)();
  TextColumn get lotId => text().nullable().references(
    CoffeeLots,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get methodId => text().nullable().references(
    BrewMethods,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get grinderId => text().nullable().references(
    Grinders,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get waterProfileId => text().nullable().references(
    WaterProfiles,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get waterProfileName => text().nullable()();
  BoolColumn get isPreGround => boolean().withDefault(const Constant(false))();
  TextColumn get methodName => text().withLength(min: 1, max: 120)();
  TextColumn get grinderName => text().nullable()();
  TextColumn get grindSetting => text().nullable()();
  RealColumn get doseGrams => real().nullable()();

  /// The original frozen portion, when the app recorded the thaw for this brew.
  TextColumn get frozenPortionId => text().nullable().references(
    FrozenPortions,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Part of the dose taken from that portion; the rest used available coffee.
  RealColumn get frozenDoseGrams => real().nullable()();
  RealColumn get waterGrams => real().nullable()();
  RealColumn get beverageGrams => real().nullable()();
  TextColumn get recipientId => text().nullable().references(
    Recipients,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get recipientName => text().nullable()();
  RealColumn get recipientGrams => real().nullable()();
  IntColumn get timeSeconds => integer().nullable()();
  RealColumn get temperatureC => real().nullable()();
  RealColumn get brix => real().nullable()();
  RealColumn get brixFactor => real().nullable()();
  IntColumn get feederRpm => integer().nullable()();
  RealColumn get tdsPercent => real().nullable()();

  /// Grinder speed; only kept when the grinder has adjustable RPM.
  IntColumn get grindRpm => integer().nullable()();

  /// Peak espresso extraction pressure in bar.
  RealColumn get pressureBar => real().nullable()();

  /// Espresso pre-infusion or filter bloom length.
  IntColumn get preinfusionSeconds => integer().nullable()();
  IntColumn get bloomSeconds => integer().nullable()();

  /// Recorded filter pours; null means unrecorded, unlike an explicit zero.
  IntColumn get bloomCount => integer().nullable()();
  IntColumn get pourCount => integer().nullable()();
  TextColumn get pourPhasesJson => text().nullable()();

  /// Espresso: seconds until the first drop reaches the cup.
  IntColumn get firstDripSeconds => integer().nullable()();

  /// Extraction compass: -1 sour, 0 balanced, 1 bitter.
  IntColumn get tasteBalance => integer().nullable()();

  /// Extraction compass: -1 weak, 0 balanced, 1 strong.
  IntColumn get tasteStrength => integer().nullable()();

  /// Flavour scores from 0 to 5.
  IntColumn get acidity => integer().nullable()();
  IntColumn get sweetness => integer().nullable()();
  IntColumn get bitterness => integer().nullable()();
  IntColumn get body => integer().nullable()();
  IntColumn get aftertaste => integer().nullable()();

  /// Machine profile or recipe name, e.g. a Meticulous profile.
  TextColumn get profileName => text().nullable()();
  RealColumn get rating => real().nullable()();

  /// The recipe a new brew of the same coffee and method starts from; at
  /// most one per coffee and method.
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
  IntColumn get brewedAtMs => integer()();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();
  IntColumn get archivedAtMs => integer().nullable()();
  BoolColumn get archivedByCoffee => boolean().nullable()();
  BoolColumn get stockReviewPending => boolean().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Pressure, flow and weight over time recorded by a connected machine.
class BrewCurves extends Table {
  TextColumn get brewId =>
      text().references(Brews, #id, onDelete: KeyAction.cascade)();

  /// Where the curve came from, e.g. "meticulous".
  TextColumn get source => text()();

  /// The samples as written by ShotCurve.toJson.
  TextColumn get samplesJson => text()();

  @override
  Set<Column> get primaryKey => {brewId};
}

/// Photos of a coffee, in order; the first is its cover.
class CoffeePhotos extends Table {
  TextColumn get coffeeId =>
      text().references(Coffees, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();

  /// File name inside the app's photo folder.
  TextColumn get fileName => text()();

  @override
  Set<Column> get primaryKey => {coffeeId, position};
}

/// Photos of a brew, in order.
class BrewPhotos extends Table {
  TextColumn get brewId =>
      text().references(Brews, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();

  /// File name inside the app's photo folder.
  TextColumn get fileName => text()();

  @override
  Set<Column> get primaryKey => {brewId, position};
}

class BrewToolSelections extends Table {
  TextColumn get brewId =>
      text().references(Brews, #id, onDelete: KeyAction.cascade)();
  TextColumn get toolId =>
      text().references(MethodTools, #id, onDelete: KeyAction.restrict)();

  @override
  Set<Column> get primaryKey => {brewId, toolId};
}

class ImportRecords extends Table {
  TextColumn get id => text()();
  TextColumn get source => text()();
  TextColumn get kind => text()();
  TextColumn get externalId => text()();
  TextColumn get fingerprint => text()();
  TextColumn get localEntity => text().nullable()();
  TextColumn get localId => text().nullable()();
  IntColumn get importedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {source, kind, externalId},
  ];
}

class LegacyPayloads extends Table {
  TextColumn get importRecordId =>
      text().references(ImportRecords, #id, onDelete: KeyAction.cascade)();
  TextColumn get rawJson => text()();

  @override
  Set<Column> get primaryKey => {importRecordId};
}

class AppPreferences extends Table {
  IntColumn get id => integer()();
  TextColumn get shareFieldsJson => text()();

  /// Optional brew form fields the user chose to hide, as a JSON name list.
  TextColumn get hiddenBrewFieldsJson => text().nullable()();

  /// Minutes after saving an unrated brew to remind the user to rate it;
  /// null turns the reminder off.
  IntColumn get rateReminderMinutes => integer().nullable()();

  /// Language chosen in Settings (e.g. "es"); null follows the device.
  TextColumn get localeCode => text().nullable()();

  /// When the journal was last saved or shared as a backup.
  IntColumn get lastBackupAtMs => integer().nullable()();

  /// Bluetooth scale the app connects to: its device ID (the address on
  /// Android) and advertised name.
  TextColumn get scaleDeviceId => text().nullable()();
  TextColumn get scaleName => text().nullable()();

  /// Paired scales in most recently used order; null reads the legacy pair.
  TextColumn get scalesJson => text().nullable()();

  /// Sort and display options of the Beans and Brews lists, as JSON.
  TextColumn get listOptionsJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    PistonMachines,
    PistonMethodLinks,
    PistonMeasurements,
    PistonMaintenances,
    Roasters,
    CoffeeRoasterLinks,
    Cafes,
    CafeDrinks,
    CafeDrinkPhotos,
    Coffees,
    CoffeeComponents,
    CoffeeLots,
    FrozenPortions,
    Recipients,
    BrewMethods,
    Grinders,
    WaterProfiles,
    MethodTools,
    ToolMethodLinks,
    Brews,
    BrewCurves,
    CoffeePhotos,
    BrewPhotos,
    BrewToolSelections,
    ImportRecords,
    LegacyPayloads,
    AppPreferences,
    StockAdjustments,
    CuppingSessions,
    CuppingSessionCups,
  ],
)
class AppDatabase extends _$AppDatabase {
  factory AppDatabase.forTesting(QueryExecutor executor) =>
      AppDatabase._(executor);

  /// Another journal file, such as a copy being brought up to date.
  factory AppDatabase.at(File file) => AppDatabase._(NativeDatabase(file));
  factory AppDatabase._(QueryExecutor executor) =>
      AppDatabase._gated(executor, JournalWriteGate());

  AppDatabase._gated(QueryExecutor executor, this.writeGate)
    : super(executor.interceptWith(writeGate));

  final JournalWriteGate writeGate;

  /// The schema this version of the app writes.
  static const currentSchema = 37;

  /// Where the journal lives.
  static Future<File> file() async {
    final directory = await getApplicationSupportDirectory();
    return File(path.join(directory.path, 'holybeans.sqlite'));
  }

  static Future<AppDatabase> open() async =>
      AppDatabase._(NativeDatabase.createInBackground(await file()));

  @override
  int get schemaVersion => currentSchema;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    // Keep every published migration, including updates that skip versions.
    onUpgrade: (migrator, from, to) async {
      if (from < 19 || from >= to || to != schemaVersion) {
        throw UnsupportedError('Unsupported schema upgrade $from -> $to');
      }
      // Rebuilding method_tools only relaxes its old owner constraint. Copy
      // every old column and keep brew/import IDs unchanged, atomically.
      await customStatement('PRAGMA foreign_keys = OFF');
      await transaction(() async {
        await migrator.runMigrationSteps(
          from: from,
          to: to,
          steps: schemas.migrationSteps(
            from19To20: (m, schema) async {
              await m.addColumn(
                schema.appPreferences,
                schema.appPreferences.scaleDeviceId,
              );
              await m.addColumn(
                schema.appPreferences,
                schema.appPreferences.scaleName,
              );
            },
            from20To21: (m, schema) async {
              await m.addColumn(schema.brews, schema.brews.bloomCount);
              await m.addColumn(schema.brews, schema.brews.pourCount);
              await m.addColumn(schema.brews, schema.brews.pourPhasesJson);
            },
            from21To22: (m, schema) async {
              await m.alterTable(
                TableMigration(
                  schema.methodTools,
                  newColumns: [schema.methodTools.mergedIntoId],
                ),
              );
              await m.createTable(schema.toolMethodLinks);
              await customStatement('''
          INSERT INTO tool_method_links (tool_id, method_id)
          SELECT id, method_id FROM method_tools WHERE method_id IS NOT NULL
        ''');
            },
            from22To23: (m, schema) async {
              await m.addColumn(schema.brews, schema.brews.isFavorite);
              await _favoritesFromBeanconqueror();
            },
            from23To24: (m, schema) async {
              await m.addColumn(
                schema.appPreferences,
                schema.appPreferences.listOptionsJson,
              );
            },
            from24To25: (m, schema) async {
              await m.addColumn(schema.brews, schema.brews.frozenPortionId);
              await m.addColumn(schema.brews, schema.brews.frozenDoseGrams);
            },
            from25To26: (m, schema) async {
              await m.addColumn(
                schema.coffeeComponents,
                schema.coffeeComponents.altitudeMaxMeters,
              );
            },
            from26To27: (m, schema) async {
              await m.addColumn(
                schema.waterProfiles,
                schema.waterProfiles.bicarbonatePpm,
              );
              await m.addColumn(
                schema.waterProfiles,
                schema.waterProfiles.recipeJson,
              );
            },
            from36To37: (m, schema) async {
              await m.createTable(schema.pistonMachines);
              await m.createTable(schema.pistonMethodLinks);
              await m.createTable(schema.pistonMeasurements);
              await m.createTable(schema.pistonMaintenances);
            },
            from35To36: (m, schema) async {
              await m.addColumn(
                schema.grinders,
                schema.grinders.hasAdjustableFeederRpm,
              );
              await m.addColumn(schema.brews, schema.brews.feederRpm);
              await m.addColumn(schema.brews, schema.brews.brix);
              await m.addColumn(schema.brews, schema.brews.brixFactor);
            },
            from34To35: (m, schema) async {
              await m.createTable(schema.roasters);
              await m.createTable(schema.coffeeRoasterLinks);
              await m.createTable(schema.cafes);
              await m.createTable(schema.cafeDrinks);
              await m.createTable(schema.cafeDrinkPhotos);
              await RoasterRegistry(this).backfill();
            },
            from33To34: (m, schema) => m.addColumn(
              schema.appPreferences,
              schema.appPreferences.scalesJson,
            ),
            from32To33: (m, schema) => restoreLegacyBrewRecipients(),
            from31To32: (m, schema) => mergeMigratedRecipients(),
            from30To31: (m, schema) async {
              await m.createTable(schema.recipients);
              await m.addColumn(
                schema.brewMethods,
                schema.brewMethods.defaultRecipientId,
              );
              await m.addColumn(schema.brews, schema.brews.recipientId);
              await m.addColumn(schema.brews, schema.brews.recipientName);
              await m.addColumn(schema.brews, schema.brews.recipientGrams);
              await customStatement(
                'INSERT INTO recipients (id, name, empty_grams) '
                "SELECT 'method-recipient:' || id, "
                "CASE WHEN vessel_name IS NULL OR trim(vessel_name) = '' THEN name ELSE vessel_name END, "
                'vessel_grams FROM brew_methods WHERE vessel_grams IS NOT NULL',
              );
              await customStatement(
                "UPDATE brew_methods SET default_recipient_id = 'method-recipient:' || id "
                'WHERE vessel_grams IS NOT NULL',
              );
            },
            from29To30: (m, schema) async {
              await m.createTable(schema.stockAdjustments);
            },
            from28To29: (m, schema) async {
              await m.addColumn(schema.brews, schema.brews.stockReviewPending);
              await customStatement(
                'UPDATE brews SET stock_review_pending = 1 '
                'WHERE archived_at_ms IS NOT NULL AND '
                '(archived_by_coffee IS NULL OR archived_by_coffee = 0)',
              );
            },
            from27To28: (m, schema) async {
              await m.createTable(schema.cuppingSessions);
              await m.createTable(schema.cuppingSessionCups);
            },
          ),
        );
        final violations = await customSelect('PRAGMA foreign_key_check').get();
        if (violations.isNotEmpty) {
          throw StateError('Migration left invalid foreign keys');
        }
      });
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Brews marked as favourite or best brew in BeanConqueror before
  /// favourites existed here, kept in their imported JSON.
  Future<void> _favoritesFromBeanconqueror() async {
    final rows = await customSelect('''
      SELECT b.id, b.coffee_id, b.method_id, b.rating, b.brewed_at_ms,
          p.raw_json
        FROM brews b
        JOIN import_records r
          ON r.local_id = b.id AND r.source = 'beanconqueror' AND r.kind = 'brew'
        JOIN legacy_payloads p ON p.import_record_id = r.id
        WHERE b.method_id IS NOT NULL
    ''').get();
    final candidates = <FavoriteCandidate>[];
    for (final row in rows) {
      final Object? json;
      try {
        json = jsonDecode(row.read<String>('raw_json'));
      } on FormatException {
        continue;
      }
      if (json is! Map) continue;
      final best = json['best_brew'] == true;
      if (!best && json['favourite'] != true) continue;
      candidates.add((
        id: row.read<String>('id'),
        coffeeId: row.read<String>('coffee_id'),
        methodId: row.read<String>('method_id'),
        best: best,
        rating: row.readNullable<double>('rating'),
        brewedAtMs: row.read<int>('brewed_at_ms'),
      ));
    }
    for (final id in pickFavorites(candidates)) {
      await customUpdate(
        'UPDATE brews SET is_favorite = 1 WHERE id = ?',
        variables: [Variable.withString(id)],
        updates: {brews},
      );
    }
  }
}
