import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/share_image_appearance.dart';
import 'package:holybeans/ui/core/share_markdown_text.dart';

class JournalShareCard extends StatelessWidget {
  const JournalShareCard({
    super.key,
    required this.title,
    required this.sections,
    this.customText,
    this.charts,
    this.photo,
  });

  final String? title;
  final List<List<(String, String)>> sections;
  final String? customText;
  final Widget? charts;
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transparent = ShareImageAppearance.isTransparent(context);
    final colors = theme.colorScheme;
    return Container(
      width: 340,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: transparent
          ? null
          : BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colors.outlineVariant),
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.coffee_rounded, size: 18, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context).appTitle,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (customText != null)
            shareMarkdownText(
              customText!,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.onSurface,
              ),
            )
          else if (title != null)
            Text(
              title!,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
          if (photo case final bytes?) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                errorBuilder: (_, error, stack) =>
                    Text(AppLocalizations.of(context).photoFailed),
              ),
            ),
          ],
          if (customText == null)
            for (final (index, rows) in sections.indexed)
              if (rows.isNotEmpty) ...[
                if (index > 0)
                  Divider(height: 24, color: colors.outlineVariant)
                else
                  const SizedBox(height: 12),
                for (final (label, value) in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            value,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
          ?charts,
        ],
      ),
    );
  }
}
