import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:holybeans/data/preferences/share_template_settings.dart';
import 'package:holybeans/domain/share_template.dart';
import 'package:holybeans/domain/share_template_exchange.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/share_template_editor.dart';
import 'package:holybeans/ui/core/error_report.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

Future<void> exportShareTemplate(
  BuildContext context,
  ShareTemplate template,
) async {
  final s = AppLocalizations.of(context)!;
  final box = context.findRenderObject() as RenderBox?;
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            utf8.encode(encodeShareTemplate(template)),
            mimeType: 'application/x-holybeans',
          ),
        ],
        fileNameOverrides: ['holybeans-template.holybeans'],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  } catch (error, stack) {
    reportError(error, stack);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.shareTemplateExportFailed)));
    }
  }
}

Future<ShareTemplate?> importShareTemplate(
  BuildContext context,
  ShareTemplateSettings settings, {
  String? source,
}) async {
  final s = AppLocalizations.of(context)!;
  try {
    if (source == null) {
      final file = await openFile();
      if (file == null) return null;
      if (await file.length() > maxShareTemplateBytes) {
        throw const FormatException('Share template too large');
      }
      source = utf8.decode(await file.readAsBytes());
    }
    final template = decodeShareTemplate(source, newId: const Uuid().v4());
    if (!context.mounted) return null;
    return await showFormSheet<ShareTemplate>(
      context,
      ShareTemplateEditor(
        style: template.style,
        existing: template,
        importing: true,
        onSave: settings.saveTemplate,
      ),
    );
  } catch (error, stack) {
    reportError(error, stack);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.shareTemplateImportFailed)));
    }
    return null;
  }
}
