import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/brew_stats.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_share_text.dart';
import 'package:holybeans/ui/brews/share_sheet.dart';
import 'package:holybeans/ui/core/error_report.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:share_plus/share_plus.dart';

/// Shares [brew] as text or an image. The fields chosen in the sheet become
/// the shared parameters, as in Settings → Brew parameters.
Future<void> shareBrewFlow(
  BuildContext context, {
  required JournalRepository repository,
  PhotoStore? photos,
  required BrewParameterSettings settings,
  required ShareTemplateSettings templateSettings,
  required Brew brew,
  required Coffee coffee,
  required List<CoffeeComponent> components,
  required BrewMethod? method,
  required void Function(String text) message,
}) async {
  final s = AppLocalizations.of(context)!;
  try {
    final lots = await repository.watchLots().first;
    final lot = lots.where((lot) => lot.id == brew.lotId).firstOrNull;
    final cost = brewCost(brew, pricePerKgByCoffee([coffee], lots));
    Uint8List? initialPhoto;
    if (photos != null) {
      final names = [
        ...await repository.brewPhotos(brew.id),
        ...await repository.coffeePhotos(coffee.id),
      ];
      for (final name in names) {
        try {
          initialPhoto = await photos.file(name).readAsBytes();
          break;
        } catch (error, stack) {
          reportError(error, stack);
        }
      }
    }
    final initial = await settings.loadShared();
    final config = await templateSettings.load();
    final recording = await repository.brewCurve(brew.id);
    final catalog = await repository.toolCatalog();
    final toolNames = [
      for (final id in await repository.brewToolIds(brew.id))
        if (catalog.byId[id] case final tool?) tool.name,
    ];
    if (!context.mounted) return;
    final result = await showFormSheet<ShareBrewResult>(
      context,
      ShareBrewSheet(
        initialPhoto: initialPhoto,
        cost: cost,
        lot: lot,
        coffee: coffee,
        brew: brew,
        components: components,
        method: method,
        toolNames: toolNames,
        initialFields: initial,
        recording: recording,
        templateSettings: templateSettings,
        configuration: config,
      ),
    );
    if (result == null || !context.mounted) return;
    if (result.rememberFields) await settings.saveShared(result.fields);
    if (result.image case final image?) {
      await SharePlus.instance.share(
        ShareParams(
          text: result.text,
          files: [XFile.fromData(image, mimeType: 'image/png')],
          fileNameOverrides: ['holybeans-${brew.id.substring(0, 8)}.png'],
        ),
      );
      return;
    }
    final source =
        result.text ??
        BrewShareText.build(
          strings: s,
          cost: cost,
          coffee: coffee,
          components: components,
          brew: brew,
          method: method,
          toolNames: toolNames,
          fields: result.fields,
          dateLocaleName: regionalLocale.toString(),
        );
    if (source.isEmpty) {
      message(s.noShareFields);
      return;
    }
    await SharePlus.instance.share(ShareParams(text: source));
  } catch (error, stack) {
    reportError(error, stack);
    message(s.shareFailed);
  }
}
