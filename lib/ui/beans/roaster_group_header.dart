import 'package:flutter/material.dart';
import 'package:holybeans/domain/bean_roaster_groups.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/freshness_widgets.dart';
import 'package:holybeans/ui/core/detail_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';

class RoasterGroupHeader extends StatelessWidget {
  const RoasterGroupHeader({
    super.key,
    required this.group,
    required this.expanded,
    required this.onTap,
    required this.showStock,
  });

  final BeanRoasterGroup group;
  final bool expanded;
  final VoidCallback? onTap;
  final bool showStock;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final weight = formatGrams(group.knownGrams, regionalLocale.toString());
    return Card(
      child: ListTile(
        key: ValueKey('roaster-group-${group.key}'),
        onTap: onTap,
        title: Text(group.name.isEmpty ? s.beansNoRoaster : group.name),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  s.beansGroupCount(group.beans.length),
                  if (showStock)
                    group.hasUnknownStock
                        ? (group.knownGrams > 0
                              ? s.beansGroupPartialStock(weight)
                              : s.unknownStock)
                        : weight,
                ].join(' · '),
              ),
              if (group.phases.isNotEmpty)
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  children: [
                    for (final phase in group.phases.entries)
                      Text(
                        '${phase.value} ${freshnessPhaseLabel(s, phase.key)}',
                        style: TextStyle(
                          color: freshnessPhaseColor(context, phase.key),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        trailing: onTap == null
            ? null
            : Icon(expanded ? Icons.expand_less : Icons.expand_more),
      ),
    );
  }
}
