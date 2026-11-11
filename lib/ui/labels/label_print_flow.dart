import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/label_output_preferences.dart';
import 'package:holybeans/data/services/label_printer.dart';
import 'package:holybeans/data/services/label_printer_cleanup.dart';
import 'package:holybeans/data/services/marklife_printer.dart';
import 'package:holybeans/data/services/paired_device_file.dart';
import 'package:holybeans/domain/label_printer_profile.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/labels/label_print_page.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';

Future<void> showCoffeeLabelPage(
  BuildContext context,
  JournalActions actions,
  Coffee coffee,
) async {
  final printers = <LabelPrinter>[];
  final s = AppLocalizations.of(context);
  try {
    final repository = actions.read.queries;
    final settings = actions.commands.templateSettings;
    final components = await repository.coffeeComponents(coffee.id);
    final lots = await repository.coffeeLots(coffee.id);
    final configuration = await settings.load();
    final outputPreferences = await LabelOutputPreferences.open();
    final lotIds = lots.map((l) => l.id).toSet();
    final portions = actions.read.portions
        .where(
          (p) =>
              lotIds.contains(p.lotId) &&
              p.thawedAtMs == null &&
              p.remainingGrams > 0,
        )
        .toList();
    for (final model in LabelPrinterModel.values) {
      if (model == LabelPrinterModel.marklifeP12) {
        final printer = MarklifePrinter(
          await PairedDeviceFile.open('marklife_p12.json'),
        );
        printers.add(printer);
        await printer.load();
        continue;
      }
      final printer = NiimbotLabelPrinter(
        await PairedDeviceFile.open('niimbot_${model.name}.json'),
        model: model,
      );
      printers.add(printer);
      await printer.load();
    }
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LabelPrintPage(
          coffee: coffee,
          components: components,
          lots: lots,
          portions: portions,
          templates: configuration.labelTemplates,
          settings: settings,
          outputPreferences: outputPreferences,
          printer: printers.first,
          otherPrinters: printers.skip(1).toList(),
        ),
      ),
    );
  } catch (error, stack) {
    reportError(error, stack);
    actions.navigation.message(s.labelOpenFailed);
  } finally {
    await closeLabelPrinters(printers);
  }
}
