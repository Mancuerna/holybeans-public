import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/share_image_appearance.dart';

class SharePhotoCard extends StatelessWidget {
  const SharePhotoCard({
    super.key,
    required this.photo,
    required this.title,
    required this.charts,
  });

  final Uint8List? photo;
  final String title;
  final Widget charts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transparent = ShareImageAppearance.isTransparent(context);
    return Container(
      key: const ValueKey('share-photo-card'),
      width: 340,
      padding: const EdgeInsets.all(12),
      decoration: transparent
          ? null
          : BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (photo case final bytes?)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                errorBuilder: (_, error, stack) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(AppLocalizations.of(context)!.photoFailed),
                ),
              ),
            )
          else if (title.isNotEmpty)
            Text(title, style: theme.textTheme.titleLarge),
          charts,
        ],
      ),
    );
  }
}
