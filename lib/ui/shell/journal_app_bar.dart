import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';

/// Titles and actions for the journal tabs; navigation stays with the shell.
class JournalAppBar extends StatelessWidget implements PreferredSizeWidget {
  const JournalAppBar({
    super.key,
    required this.tab,
    required this.showArchivedEquipment,
    required this.onStats,
    this.onCafes,
    required this.onRoasters,
    required this.onToggleArchivedEquipment,
    required this.onSettings,
  });

  final int tab;
  final bool showArchivedEquipment;
  final VoidCallback onStats;
  final VoidCallback? onCafes;
  final VoidCallback onRoasters;
  final VoidCallback onToggleArchivedEquipment;
  final VoidCallback onSettings;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AppBar(
      title: Text(switch (tab) {
        1 => s.beansTitle,
        2 => s.historyTitle,
        3 => s.equipment,
        _ => s.appTitle,
      }),
      actions: [
        if ((tab == 0 || tab == 2) && onCafes != null)
          IconButton(
            key: const ValueKey('cafes-button'),
            tooltip: s.cafeTitle,
            icon: const Icon(Icons.local_cafe_outlined),
            onPressed: onCafes,
          ),
        if (tab == 0 || tab == 2)
          IconButton(
            key: tab == 2 ? const ValueKey('history-stats-button') : null,
            tooltip: s.statsTitle,
            icon: const Icon(Icons.bar_chart_outlined),
            onPressed: onStats,
          ),
        if (tab == 1)
          IconButton(
            key: const ValueKey('roasters-button'),
            tooltip: s.roasterProfilesTitle,
            icon: const Icon(Icons.storefront_outlined),
            onPressed: onRoasters,
          ),
        if (tab == 3)
          IconButton(
            key: const ValueKey('equipment-show-archived'),
            tooltip: showArchivedEquipment
                ? s.hideArchivedEquipment
                : s.showArchivedEquipment,
            isSelected: showArchivedEquipment,
            icon: const Icon(Icons.archive_outlined),
            selectedIcon: const Icon(Icons.archive),
            onPressed: onToggleArchivedEquipment,
          ),
        IconButton(
          key: const ValueKey('settings-button'),
          tooltip: s.settings,
          icon: const Icon(Icons.settings_outlined),
          onPressed: onSettings,
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
