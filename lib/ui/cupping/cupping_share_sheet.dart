import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/repositories/cupping_share.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/cupping/cupping_share_card.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareCuppingFlow(
  BuildContext context,
  JournalRepository repository,
  String sessionId,
) async {
  final s = AppLocalizations.of(context)!;
  try {
    final data = await repository.cuppingShareData(sessionId);
    if (!context.mounted) return;
    final image = await showFormSheet<Uint8List>(
      context,
      CuppingShareSheet(data: data),
    );
    if (image == null || !context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(image, mimeType: 'image/png')],
        fileNameOverrides: ['holybeans-cupping-$sessionId.png'],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  } catch (e, stack) {
    reportError(e, stack);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.shareFailed)));
    }
  }
}

class CuppingShareSheet extends StatefulWidget {
  const CuppingShareSheet({super.key, required this.data});
  final CuppingShareData data;
  @override
  State<CuppingShareSheet> createState() => _CuppingShareSheetState();
}

class _CuppingShareSheetState extends State<CuppingShareSheet> {
  final cardKey = GlobalKey();
  bool includeNotes = false;
  bool dark = false;
  bool rendering = false;

  Future<void> _export() async {
    if (rendering) return;
    setState(() => rendering = true);
    try {
      // Finish painting any option change before capturing the whole card.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final size = boundary.size;
      // Very long notes still fit the image/texture limits without truncation.
      final ratio = math.min(
        1.5,
        math.min(
          16384 / math.max(size.width, size.height),
          math.sqrt(20000000 / (size.width * size.height)),
        ),
      );
      final image = await boundary.toImage(pixelRatio: ratio);
      ByteData? bytes;
      try {
        bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      } finally {
        image.dispose();
      }
      if (bytes == null) throw StateError('PNG encoding failed');
      if (mounted) Navigator.of(context).pop(bytes.buffer.asUint8List());
    } catch (e, stack) {
      reportError(e, stack);
      if (mounted) {
        setState(() => rendering = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.shareFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  s.cuppingShare,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  CheckboxListTile(
                    key: const ValueKey('cupping-share-notes'),
                    title: Text(s.cuppingShareNotes),
                    dense: true,
                    value: includeNotes,
                    onChanged: rendering
                        ? null
                        : (v) => setState(() => includeNotes = v!),
                  ),
                  CheckboxListTile(
                    key: const ValueKey('cupping-share-dark'),
                    title: Text(s.cuppingShareDark),
                    dense: true,
                    value: dark,
                    onChanged: rendering
                        ? null
                        : (v) => setState(() => dark = v!),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('cupping-share-preview'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    key: const ValueKey('cupping-share-preview-horizontal'),
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: RepaintBoundary(
                          key: cardKey,
                          child: CuppingShareCard(
                            data: widget.data,
                            includeNotes: includeNotes,
                            dark: dark,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: rendering
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(s.cancel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('cupping-share-confirm'),
                      onPressed: rendering ? null : _export,
                      icon: rendering
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.share_outlined),
                      label: Text(s.share),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
