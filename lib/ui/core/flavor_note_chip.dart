import 'package:flutter/material.dart';
import 'package:holybeans/domain/flavor_descriptors.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/core/flavor_note_labels.dart';

/// Shared appearance for saved notes and removable notes in the editor.
class FlavorNoteChip extends StatelessWidget {
  const FlavorNoteChip({super.key, required this.note, this.onDeleted});

  final String note;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppLocalizations.of(context);
    final label = flavorNoteLabel(note, s);
    final seed = flavorNoteColor(flavorNoteTone(note));
    // A note without a known family is outlined on the sheet: a grey fill
    // read as one more colour family.
    final background = seed == null
        ? theme.colorScheme.surfaceContainerLowest
        : Color.alphaBlend(
            seed.withValues(
              alpha: theme.brightness == Brightness.dark ? .25 : .14,
            ),
            theme.colorScheme.surface,
          );
    final style = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    final border = BorderSide(
      color: seed?.withValues(alpha: .35) ?? theme.colorScheme.outlineVariant,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      side: border,
    );
    if (onDeleted != null) {
      return InputChip(
        label: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
        labelStyle: style,
        backgroundColor: background,
        shape: shape,
        side: border,
        onDeleted: onDeleted,
        deleteButtonTooltipMessage: s.flavorNoteRemove(label),
        materialTapTargetSize: MaterialTapTargetSize.padded,
      );
    }
    return DecoratedBox(
      decoration: ShapeDecoration(color: background, shape: shape),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(label, style: style),
      ),
    );
  }
}

Color? flavorNoteColor(FlavorTone? tone) => switch (tone) {
  FlavorTone.red => const Color(0xffbd3852),
  FlavorTone.pink => const Color(0xffc55e91),
  FlavorTone.purple => const Color(0xff8d64ae),
  FlavorTone.blue => const Color(0xff4d78b8),
  FlavorTone.orange => const Color(0xffdf8742),
  FlavorTone.yellow => const Color(0xffbca13c),
  FlavorTone.green => const Color(0xff6f9554),
  FlavorTone.cream => const Color(0xffc5b38b),
  FlavorTone.brown => const Color(0xff96735b),
  null => null,
};
