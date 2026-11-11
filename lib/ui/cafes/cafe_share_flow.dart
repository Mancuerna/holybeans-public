import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/cafe_repository.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/cafes/cafe_share_sheet.dart';
import 'package:holybeans/ui/cafes/cafe_share_text.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareCafeDrinkFlow(
  BuildContext context, {
  required CafeJournalData data,
  required CafeDrink drink,
  PhotoStore? photos,
}) async {
  final s = AppLocalizations.of(context);
  try {
    Uint8List? photo;
    if (photos != null) {
      for (final name in data.photosOf(drink.id)) {
        try {
          photo = await photos.file(name).readAsBytes();
          break;
        } catch (error, stack) {
          reportError(error, stack);
        }
      }
    }
    if (!context.mounted) return;
    final rows = cafeShareRows(
      context,
      data.cafeOf(drink),
      drink,
      data.roasterOf(drink),
    );
    final result = await showFormSheet<CafeShareResult>(
      context,
      CafeShareSheet(rows: rows, initialPhoto: photo),
    );
    if (result == null || !context.mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        text: result.text,
        files: result.image == null
            ? null
            : [XFile.fromData(result.image!, mimeType: 'image/png')],
        fileNameOverrides: result.image == null
            ? null
            : ['holybeans-cafe-drink.png'],
      ),
    );
  } catch (error, stack) {
    reportError(error, stack);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.shareFailed)));
    }
  }
}
