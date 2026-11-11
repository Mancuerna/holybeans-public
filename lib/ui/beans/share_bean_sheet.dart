import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/bean_exchange.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';

/// Shares [coffee]'s card: a QR code on screen, and as a `.holybeans` file
/// or a picture of the QR for whoever would rather not download files.
Future<void> showBeanTransferSheet(
  BuildContext context,
  JournalRead actions,
  Coffee coffee,
) async {
  final repository = actions.queries;
  final s = AppLocalizations.of(context);
  final SharedBean card;
  try {
    card = sharedBeanFromCoffee(
      coffee,
      await repository.coffeeComponents(coffee.id),
      await repository.coffeeLots(coffee.id),
    );
  } catch (error, stack) {
    reportError(error, stack);
    if (context.mounted) showOperationError(context, error, s.shareFailed);
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => SafeArea(top: false, child: _ShareBeanSheet(card: card)),
  );
}

class _ShareBeanSheet extends StatelessWidget {
  const _ShareBeanSheet({required this.card});

  final SharedBean card;

  /// A file name from the coffee's name, safe on any system.
  String get _fileName {
    final base = card.name
        .replaceAll(RegExp(r'[^\w\s-]', unicode: true), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    return '${base.isEmpty ? 'coffee' : base}.$beanFileExtension';
  }

  Future<void> _sendFile(BuildContext context) async {
    final s = AppLocalizations.of(context);
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              utf8.encode(encodeBeans([card])),
              mimeType: beanFileMimeType,
            ),
          ],
          fileNameOverrides: [_fileName],
        ),
      );
    } catch (error, stack) {
      reportError(error, stack);
      if (context.mounted) showOperationError(context, error, s.saveFailed);
    }
  }

  Future<void> _sendQrImage(BuildContext context) async {
    final s = AppLocalizations.of(context);
    try {
      final png = await _qrPng(
        beanQrText(card),
        title: card.name,
        caption: s.shareBeanQrCaption,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(png, mimeType: 'image/png')],
          fileNameOverrides: ['${_fileName.split('.').first}.png'],
        ),
      );
    } catch (error, stack) {
      reportError(error, stack);
      if (context.mounted) showOperationError(context, error, s.saveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.shareBeanTitle(card.name),
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            s.shareBeanHint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Semantics(
              image: true,
              label: s.shareBeanQrCaption,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CustomPaint(
                    key: const ValueKey('share-bean-qr'),
                    painter: _QrPainter(beanQrText(card)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const ValueKey('share-bean-file'),
            onPressed: () => _sendFile(context),
            icon: const Icon(Icons.ios_share_rounded),
            label: Text(s.shareBeanFile),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('share-bean-qr-image'),
            onPressed: () => _sendQrImage(context),
            icon: const Icon(Icons.qr_code_2_rounded),
            label: Text(s.shareBeanQrImage),
          ),
        ],
      ),
    );
  }
}

/// The modules of [text]'s QR code, with medium error correction (the
/// default), enough for a photo of a screen.
QrImage _qrOf(String text) =>
    QrImage(QrCode(payload: QrPayload.fromString(text)));

/// Draws a QR code in black on white, with the quiet zone scanners need.
class _QrPainter extends CustomPainter {
  _QrPainter(String text) : _image = _qrOf(text);

  final QrImage _image;

  @override
  void paint(Canvas canvas, Size size) => _paintQr(canvas, size.width, _image);

  @override
  bool shouldRepaint(_QrPainter old) => false;
}

void _paintQr(Canvas canvas, double side, QrImage image) {
  // Four modules of white around the code, as the standard asks.
  final count = image.moduleCount + 8;
  final module = side / count;
  canvas.drawRect(
    Rect.fromLTWH(0, 0, side, side),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final dark = Paint()..color = const Color(0xFF000000);
  for (var x = 0; x < image.moduleCount; x++) {
    for (var y = 0; y < image.moduleCount; y++) {
      if (image.isDark(y, x)) {
        canvas.drawRect(
          Rect.fromLTWH((x + 4) * module, (y + 4) * module, module, module),
          dark,
        );
      }
    }
  }
}

/// A PNG of [text]'s QR code with [title] and [caption] under it, to send
/// as a picture.
Future<Uint8List> _qrPng(
  String text, {
  required String title,
  required String caption,
}) async {
  const side = 900.0;
  const margin = 40.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  TextPainter label(String value, double size, FontWeight weight) =>
      TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            color: const Color(0xFF221E1B),
            fontSize: size,
            fontWeight: weight,
            fontFamily: 'Plex',
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: side - 2 * margin);
  final titleText = label(title, 44, FontWeight.w600);
  final captionText = label(caption, 32, FontWeight.w400);
  final height = side + titleText.height + captionText.height + margin * 2;
  canvas.drawRect(
    Rect.fromLTWH(0, 0, side, height),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  _paintQr(canvas, side, _qrOf(text));
  titleText.paint(canvas, Offset((side - titleText.width) / 2, side));
  captionText.paint(
    canvas,
    Offset((side - captionText.width) / 2, side + titleText.height + 16),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(side.toInt(), height.ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return bytes!.buffer.asUint8List();
}
