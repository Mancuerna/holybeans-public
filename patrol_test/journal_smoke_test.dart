import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/main.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:patrol/patrol.dart';

import 'steps/architecture_steps.dart';
import 'steps/archive_stock_steps.dart';
import 'steps/backup_steps.dart';
import 'steps/bean_paste_steps.dart';
import 'steps/bean_share_steps.dart';
import 'steps/beta_fix_steps.dart';
import 'steps/blind_cupping_steps.dart';
import 'steps/bq_folder_steps.dart';
import 'steps/brew_pours_steps.dart';
import 'steps/cafe_share_steps.dart';
import 'steps/cafe_steps.dart';
import 'steps/coffee_delete_steps.dart';
import 'steps/cupping_steps.dart';
import 'steps/difluid_scale_steps.dart';
import 'steps/espresso_comparison_steps.dart';
import 'steps/favorite_steps.dart';
import 'steps/filter_scale_steps.dart';
import 'steps/first_brew_steps.dart';
import 'steps/flavor_notes_steps.dart';
import 'steps/frozen_brew_steps.dart';
import 'steps/guard_compare_steps.dart';
import 'steps/interface_review_steps.dart';
import 'steps/interface_ux_fixes_steps.dart';
import 'steps/journal_steps.dart';
import 'steps/loffee_steps.dart';
import 'steps/multi_scale_steps.dart';
import 'steps/parameters_steps.dart';
import 'steps/photo_benchmark_steps.dart';
import 'steps/pour_assistant_steps.dart';
import 'steps/pours_curve_steps.dart';
import 'steps/pre_migration_steps.dart';
import 'steps/pressure_assistant_steps.dart';
import 'steps/pressure_chart_steps.dart';
import 'steps/pressure_sensor_steps.dart';
import 'steps/recipient_steps.dart';
import 'steps/roaster_steps.dart';
import 'steps/share_chart_steps.dart';
import 'steps/share_image_steps.dart';
import 'steps/share_template_steps.dart';
import 'steps/shared_tools_steps.dart';
import 'steps/stock_adjustments_steps.dart';
import 'steps/template_exchange_steps.dart';
import 'steps/usability_steps.dart';
import 'steps/water_calculator_steps.dart';
import 'steps/water_card_steps.dart';
import 'steps/year_review_steps.dart';
import 'support/smoke_support.dart';

void main() {
  patrolTest(
    'records a cafe drink without changing home inventory',
    tags: ['android', 'cafe-journal'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkCafeJournal($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'cafe drinks share text and a branded image without changing the diary',
    tags: ['android', 'cafe-share'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkCafeShare($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'follows a previous pressure shot without changing the reference',
    tags: ['android', 'pressure-assistant'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkPressureAssistant($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'pairs two scales, reconnects to the available one and forgets only one',
    tags: ['android', 'multi-scale'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkMultiScale($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'beans share text, card and photo without changing the diary',
    tags: ['android', 'bean-share'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkBeanShare($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'usability: validation, search, detail actions and quick periods',
    tags: ['android', 'usability'],
    ($) async {
      final db = await openTestDatabase();
      try {
        await clearTestData(db);
        await checkUsability($, db);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await db.close();
      }
    },
  );
  patrolTest(
    'escaped AI card survives clipboard preview and import',
    tags: ['android', 'bean-paste'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkBeanPaste($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'photo benchmark: Dart decoder against the platform one',
    tags: ['android', 'photo-benchmark'],
    ($) async => runPhotoBenchmark(),
    timeout: const Timeout(Duration(minutes: 20)),
  );
  patrolTest(
    'recipients: create, select, save and preserve historical tare',
    tags: ['android', 'recipients'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkRecipients($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'roasters: search, archived coffee, navigation and unchanged diary',
    tags: ['android', 'roasters'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkRoasters($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'year review: calendar, stories, PNG and unchanged diary',
    tags: ['android', 'year-review'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkYearReview($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'stock adjustments: gift, correction, undo and restore',
    tags: ['android', 'stock-adjustments'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkStockAdjustments($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'interface review: Up next, adjust, ongoing timer notice, chips, swipe',
    tags: ['android', 'interface-review'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkInterfaceReview($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'archiving keeps consumption; old stock review is explicit',
    tags: ['android', 'archive-stock'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkArchiveStock($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'assistant without a scale saves recipe counts without measured phases',
    tags: ['android', 'pour-assistant'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkPourAssistant($, database, withScale: false);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'vertical pour bars follow weight and return measured brew fields',
    tags: ['android', 'pour-assistant'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkPourAssistant($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'template files preview before importing without replacing defaults',
    tags: ['android', 'template-exchange'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkTemplateExchange($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'water cards align minerals and preserve original precision',
    tags: ['android', 'water-cards'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkWaterCards($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'image sharing exports pressure and the correct espresso or filter map',
    tags: ['android', 'share-charts'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkShareCharts($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'frozen badges settings and saved templates preserve field sharing',
    tags: ['android', 'share-templates'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkShareTemplates($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'photo selection blocks saving and archive restoration keeps its photos',
    tags: ['android', 'architecture'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkArchitectureFlows($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'two espresso shots share a cursor and preserve the saved journal',
    tags: ['android', 'espresso-compare'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkEspressoComparison($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'flavor note chips save pending text and preserve imported profiles',
    tags: ['android', 'flavor-notes'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkFlavorNotes($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'BOOKOO peak survives scale sampling and Stop allows later manual correction',
    tags: ['android', 'pressure-chart'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkPressureChart($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'blind cupping rates letters before identifying existing coffees',
    tags: ['android', 'blind-cupping'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkBlindCupping($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'cupping drafts, reminders, comparison and atomic inventory',
    tags: ['android', 'cupping'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkCupping($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'unsaved coffee and brew drafts are protected and comparison is read only',
    tags: ['android', 'guard-compare'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkGuardAndComparison($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'shared brew PNG preserves every bloom, pour and multiline note',
    tags: ['android', 'share-image'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkShareImage($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'direct water recipes, mineral bottles and water chart survive save and reopen',
    tags: ['android', 'water-calculator'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkWaterCalculator($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'DiFluid pairs, tares and records filter water through the shared scale flow',
    tags: ['android', 'difluid-scale'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkDifluidScale($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'filter scale progress preserves the target and Stop saves measured water',
    tags: ['android', 'filter-scale'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkFilterScale($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'bean speed dial and Loffee review preserve inventory and device credentials',
    tags: ['android', 'loffee'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkLoffeeImport($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'shared tools preserve identity, archived usages, merges and historical selections',
    tags: ['android', 'shared-tools'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkSharedTools($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'adds a bean, brews it twice, and keeps the focused name field visible',
    tags: ['android', 'brew-repeat'],
    ($) async {
      var database = await openTestDatabase();
      var databaseClosed = false;
      try {
        await clearTestData(database);
        await $.pumpWidgetAndSettle(
          HolyBeansApp(
            services: AppServices(database: database),
            initialLocale: const Locale('en'),
          ),
        );
        await addFirstBean($, database);
        await brewFirstCup($, database);
        await checkHomeAndBrewDetails($, database);
        await rateFirstBrew($, database);
        await repeatPreGround($, database);

        // Everything survives closing and reopening the database.
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
        databaseClosed = true;
        database = await openTestDatabase();
        databaseClosed = false;
        final coffees = await database.select(database.coffees).get();
        final brews = await database.select(database.brews).get();
        final lots = await database.select(database.coffeeLots).get();
        expect(coffees.single.name, 'Patrol Kenya');
        expect(brews, hasLength(2));
        expect(
          brews.singleWhere((brew) => brew.isPreGround).grindSetting,
          isNull,
        );
        expect(lots.single.remainingGrams, 214);
        await $.pumpWidgetAndSettle(
          HolyBeansApp(
            services: AppServices(database: database),
            initialLocale: const Locale('en'),
          ),
        );
        await $.waitUntilVisible(find.text('Patrol Kenya'));

        await checkHistory($);
        await addSecondBeanAndFreeze($, database);
        await archiveAndRestoreMethod($);
        await editFirstBean($, database);
        await overdrawAndArchive($, database);
        await checkStats($);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        if (!databaseClosed) await database.close();
      }
    },
  );
  patrolTest(
    'beta fixes preserve timer, suggestions, sorting and first drip',
    tags: ['android'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkBetaFixes($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'unused coffee deletion protects active and archived history',
    tags: ['android', 'coffee-delete'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkCoffeeDeletion($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'filter pours preserve counts, folded measurements and repeat semantics',
    tags: ['android', 'filter-pours'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkBrewPours($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'automatic copies, a real backup folder and restoring a copy',
    tags: ['android', 'backups'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkBackups($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'blooms and pours come from the scale curve of saved brews',
    tags: ['android', 'pours-curve'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkPoursFromCurves($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'a BeanConqueror export folder imports every curve',
    tags: ['android', 'bq-folder'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkBeanconquerorFolder($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'the journal kept before an update comes back up to date',
    tags: ['android', 'backups', 'pre-migration'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkPreMigrationCopy($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'a favourite recipe is where a new brew of its coffee and method starts',
    tags: ['android', 'favorites'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkFavoriteRecipe($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'brew parameters hide values everywhere but keep them',
    tags: ['android', 'parameters'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkBrewParameters($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'deleting a frozen brew restores its portion and cancellation keeps it frozen',
    tags: ['android', 'frozen-brew'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkFrozenBrewDeletion($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'interface fixes: reveal errors, reject invalid time and keep custom ratio',
    tags: ['android', 'interface-ux-fixes'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkInterfaceUxForm($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  patrolTest(
    'interface fixes: method navigation resets filters and uses stable ids',
    tags: ['android', 'interface-ux-fixes'],
    ($) async {
      final database = await openTestDatabase();
      try {
        await clearTestData(database);
        await checkInterfaceUxHistory($, database);
      } finally {
        await $.pumpWidgetAndSettle(const SizedBox.shrink());
        await database.close();
      }
    },
  );
  // The BLE library has no platform reset; keep its simulated peripheral last.
  patrolTest(
    'BOOKOO pressure pairs, reads a protocol frame and forgets the monitor',
    tags: ['android', 'pressure-sensor'],
    checkBookooPressure,
  );
}
