import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';

/// Cancel and share, under the scrolling preview.
class ShareSheetActions extends StatelessWidget {
  const ShareSheetActions({
    super.key,
    required this.onShare,
    required this.onCopy,
    required this.copyLabel,
    required this.busy,
    this.message,
  });

  /// Null while there is nothing to share or the picture is rendering.
  final VoidCallback? onShare;
  final VoidCallback? onCopy;
  final String copyLabel;
  final String? message;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: Text(s.cancel),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.outlined(
                key: const ValueKey('share-copy'),
                onPressed: onCopy,
                tooltip: copyLabel,
                icon: const Icon(Icons.content_copy_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('share-confirm'),
                  onPressed: onShare,
                  child: Text(s.share),
                ),
              ),
            ],
          ),
          if (message case final text?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(text, key: const ValueKey('share-copy-message')),
              ),
            ),
        ],
      ),
    );
  }
}

class ShareSheetHeader extends StatelessWidget {
  const ShareSheetHeader({
    super.key,
    required this.asImage,
    required this.onChanged,
  });
  final bool asImage;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            s.share,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          SegmentedButton<bool>(
            key: const ValueKey('share-format'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.notes_rounded),
                tooltip: s.shareFormatText,
                label: Text(s.shareFormatText),
              ),
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.image_outlined),
                tooltip: s.shareFormatImage,
                label: Text(s.shareFormatImage),
              ),
            ],
            selected: {asImage},
            onSelectionChanged: onChanged == null
                ? null
                : (value) => onChanged!(value.single),
          ),
        ],
      ),
    );
  }
}
