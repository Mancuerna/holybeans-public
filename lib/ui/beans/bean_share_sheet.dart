import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/bean_share_card.dart';
import 'package:holybeans/ui/beans/bean_share_text.dart';
import 'package:holybeans/ui/core/share_image.dart';
import 'package:holybeans/ui/core/share_image_appearance.dart';
import 'package:holybeans/ui/core/share_photo_card.dart';

class BeanShareResult {
  const BeanShareResult({this.text, this.image, this.transfer = false});
  final String? text;
  final Uint8List? image;
  final bool transfer;
}

class BeanShareSheet extends StatefulWidget {
  const BeanShareSheet({super.key, required this.rows, this.initialPhoto});
  final List<BeanShareRow> rows;
  final Uint8List? initialPhoto;

  @override
  State<BeanShareSheet> createState() => _BeanShareSheetState();
}

class _BeanShareSheetState extends State<BeanShareSheet> {
  late final selected = {
    for (final row in widget.rows)
      if (!row.personal) row.id,
  };
  late Uint8List? photo = widget.initialPhoto;
  final cardKey = GlobalKey();
  bool asImage = false;
  bool transparent = false;
  bool lightText = true;
  bool photoCaption = false;
  bool busy = false;

  void _failure(Object error, StackTrace stack, String message) {
    reportError(error, stack);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _pickPhoto() async {
    if (busy) return;
    setState(() => busy = true);
    final s = AppLocalizations.of(context)!;
    try {
      final bytes = await pickSharePhoto(context);
      if (mounted && bytes != null) setState(() => photo = bytes);
    } catch (error, stack) {
      _failure(error, stack, s.photoFailed);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _share(String source) async {
    if (busy || source.isEmpty) return;
    setState(() => busy = true);
    final s = AppLocalizations.of(context)!;
    try {
      final bytes = asImage
          ? await renderShareImage(context, cardKey, photo: photo)
          : null;
      if (!mounted) return;
      Navigator.pop(
        context,
        BeanShareResult(
          text: !asImage || photoCaption ? source : null,
          image: bytes,
        ),
      );
    } catch (error, stack) {
      _failure(error, stack, s.shareFailed);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final source = beanShareText(widget.rows, selected);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.shareBeanCard,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              key: const ValueKey('bean-share-format'),
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
                      ShareImageOptions(
                        transparent: transparent,
                        lightText: lightText,
                        enabled: !busy,
                        onTransparentChanged: (value) =>
                            setState(() => transparent = value),
                        onLightTextChanged: (value) =>
                            setState(() => lightText = value),
                      ),
                      SwitchListTile.adaptive(
                        key: const ValueKey('bean-share-photo-caption'),
                        title: Text(s.sharePhotoCaption),
                        value: photoCaption,
                        onChanged: busy
                            ? null
                            : (value) => setState(() => photoCaption = value),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(s.sharePhotoCaptionHint),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            key: const ValueKey('bean-share-choose-photo'),
                            onPressed: busy ? null : _pickPhoto,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: Text(
                              photo == null ? s.addPhoto : s.changePhoto,
                            ),
                          ),
                          if (photo != null)
                            TextButton.icon(
                              key: const ValueKey('bean-share-remove-photo'),
                              onPressed: busy
                                  ? null
                                  : () => setState(() => photo = null),
                              icon: const Icon(Icons.close),
                              label: Text(s.removePhoto),
                            ),
                        ],
                      ),
                      if (photoCaption && photo == null)
                        Text(s.beanSharePhotoRequired),
                      ShareImagePreview(
                        captureKey: cardKey,
                        transparent: transparent,
                        lightText: lightText,
                        child: photoCaption
                            ? SharePhotoCard(
                                photo: photo,
                                title: '',
                                charts: const SizedBox.shrink(),
                              )
                            : BeanShareCard(
                                rows: widget.rows,
                                selected: selected,
                                photo: photo,
                              ),
                      ),
                    ],
                    if (!asImage || photoCaption)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            source,
                            key: const ValueKey('bean-share-preview'),
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
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const ValueKey('bean-share-transfer'),
                      onPressed: busy
                          ? null
                          : () => Navigator.pop(
                              context,
                              const BeanShareResult(transfer: true),
                            ),
                      icon: const Icon(Icons.qr_code_2),
                      label: Text(s.beanShareTransfer),
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
                  key: const ValueKey('bean-share-confirm'),
                  onPressed:
                      busy ||
                          source.isEmpty ||
                          (asImage && photoCaption && photo == null)
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
  final List<BeanShareRow> rows;
  final Set<String> selected;
  final bool enabled;
  final void Function(String, bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return ExpansionTile(
      title: Text(s.shareFields),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(s.beanShareFieldsHint),
        ),
        for (final row in rows)
          CheckboxListTile(
            key: ValueKey('bean-share-field-${row.id}'),
            title: Text(row.label),
            subtitle: Text(row.value),
            value: selected.contains(row.id),
            onChanged: enabled ? (value) => onChanged(row.id, value!) : null,
          ),
      ],
    );
  }
}
