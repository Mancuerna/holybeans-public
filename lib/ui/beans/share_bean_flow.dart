import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/stock.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/bean_share_sheet.dart';
import 'package:holybeans/ui/beans/bean_share_text.dart';
import 'package:holybeans/ui/beans/share_bean_sheet.dart';
import 'package:holybeans/ui/core/error_report.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:share_plus/share_plus.dart';

Future<void> showShareBeanSheet(
  BuildContext context,
  JournalActions actions,
  Coffee coffee,
) async {
  final s = AppLocalizations.of(context)!;
  try {
    final repository = actions.repository;
    final components = await repository.coffeeComponents(coffee.id);
    final lots = await repository.coffeeLots(coffee.id);
    Uint8List? photo;
    if (actions.photos case final store?) {
      for (final name in await repository.coffeePhotos(coffee.id)) {
        try {
          photo = await store.file(name).readAsBytes();
          break;
        } catch (error, stack) {
          reportError(error, stack);
        }
      }
    }
    if (!context.mounted) return;
    final result = await showFormSheet<BeanShareResult>(
      context,
      BeanShareSheet(
        rows: beanShareRows(
          s,
          coffee,
          components,
          CoffeeStock(
            lots: lots.where((lot) => lot.archivedAtMs == null).toList(),
            portions: actions.portions,
          ),
        ),
        initialPhoto: photo,
      ),
    );
    if (result == null || !context.mounted) return;
    if (result.transfer) {
      await showBeanTransferSheet(context, actions, coffee);
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        text: result.text,
        files: result.image == null
            ? null
            : [XFile.fromData(result.image!, mimeType: 'image/png')],
        fileNameOverrides: result.image == null
            ? null
            : ['holybeans-coffee.png'],
      ),
    );
  } catch (error, stack) {
    reportError(error, stack);
    actions.message(s.shareFailed);
  }
}
