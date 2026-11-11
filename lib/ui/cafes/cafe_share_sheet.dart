import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/cafes/cafe_share_card.dart';
import 'package:holybeans/ui/cafes/cafe_share_text.dart';
import 'package:holybeans/ui/core/share_image.dart';

class CafeShareResult {
  const CafeShareResult({this.text, this.image});

  final String? text;
  final Uint8List? image;
}

class CafeShareSheet extends StatefulWidget {
  const CafeShareSheet({super.key, required this.rows, this.initialPhoto});

  final List<CafeShareRow> rows;
  final Uint8List? initialPhoto;

  @override
  State<CafeShareSheet> createState() => _CafeShareSheetState();
}

class _CafeShareSheetState extends State<CafeShareSheet> {
  late final selected = {
    for (final row in widget.rows)
      if (!row.personal) row.id,
  };
  final cardKey = GlobalKey();
  bool asImage = false;
  bool includePhoto = false;
  bool busy = false;

  Future<void> _share(String source) async {
    if (busy || source.isEmpty) return;
    setState(() => busy = true);
    final s = AppLocalizations.of(context);
    try {
      final photo = includePhoto ? widget.initialPhoto : null;
      final bytes = asImage
          ? await renderShareImage(context, cardKey, photo: photo)
          : null;
      if (!mounted) return;
      Navigator.pop(
        context,
        CafeShareResult(text: asImage ? null : source, image: bytes),
      );
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.shareFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final source = cafeShareText(widget.rows, selected);
    final photo = includePhoto ? widget.initialPhoto : null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.cafeShareTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              key: const ValueKey('cafe-share-format'),
              segments: [
                ButtonSegment(value: false, label: Text(s.shareFormatText)),
                ButtonSegment(value: true, label: Text(s.shareFormatImage)),
              ],
              selected: {asImage},
              onSelectionChanged: busy
                  ? null
                  : (value) => setState(() => asImage = value.single),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (asImage) ...[
                      if (widget.initialPhoto != null)
                        SwitchListTile.adaptive(
                          key: const ValueKey('cafe-share-include-photo'),
                          title: Text(s.cafeShareIncludePhoto),
                          value: includePhoto,
                          onChanged: busy
                              ? null
                              : (value) => setState(() => includePhoto = value),
                        ),
                      RepaintBoundary(
                        key: cardKey,
                        child: CafeShareCard(
                          rows: widget.rows,
                          selected: selected,
                          photo: photo,
                        ),
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            source,
                            key: const ValueKey('cafe-share-preview'),
                          ),
                        ),
                      ),
                    _Fields(
                      rows: widget.rows,
                      selected: selected,
                      enabled: !busy,
                      onChanged: (id, value) => setState(() {
                        if (value) {
                          selected.add(id);
                        } else {
                          selected.remove(id);
                        }
                      }),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: Text(s.cancel),
                ),
                FilledButton(
                  key: const ValueKey('cafe-share-confirm'),
                  onPressed: busy || source.isEmpty
                      ? null
                      : () => _share(source),
                  child: Text(s.share),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Fields extends StatelessWidget {
  const _Fields({
    required this.rows,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final List<CafeShareRow> rows;
  final Set<String> selected;
  final bool enabled;
  final void Function(String, bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return ExpansionTile(
      title: Text(s.shareFields),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(s.cafeShareFieldsHint),
        ),
        for (final row in rows)
          CheckboxListTile(
            key: ValueKey('cafe-share-field-${row.id}'),
            title: Text(row.label),
            subtitle: Text(row.value),
            value: selected.contains(row.id),
            onChanged: enabled ? (value) => onChanged(row.id, value!) : null,
          ),
      ],
    );
  }
}
