import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';

/// The four main tabs: Home, Beans, Brews and Equipment.
class JournalNavigationBar extends StatelessWidget {
  const JournalNavigationBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return NavigationBar(
      selectedIndex: selected,
      onDestinationSelected: onSelected,
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home_rounded),
          label: s.navHome,
        ),
        NavigationDestination(
          icon: const Icon(Icons.coffee_outlined),
          selectedIcon: const Icon(Icons.coffee_rounded),
          label: s.navBeans,
        ),
        NavigationDestination(
          icon: const Icon(Icons.history_rounded),
          label: s.navHistory,
        ),
        NavigationDestination(
          icon: const Icon(Icons.coffee_maker_outlined),
          selectedIcon: const Icon(Icons.coffee_maker_rounded),
          label: s.equipment,
        ),
      ],
    );
  }
}
