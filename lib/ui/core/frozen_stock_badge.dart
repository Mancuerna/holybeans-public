import 'package:flutter/material.dart';
import 'package:holybeans/domain/frozen_stock_state.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/semantic_colors.dart';

export 'package:holybeans/domain/frozen_stock_state.dart';

class FrozenStockBadge extends StatelessWidget {
  const FrozenStockBadge({super.key, required this.state, this.weight});

  final FrozenStockState state;

  final String? weight;

  @override
  Widget build(BuildContext context) {
    if (state == FrozenStockState.none) return const SizedBox.shrink();
    final s = AppLocalizations.of(context);
    final all = state == FrozenStockState.all;
    final status = all ? s.frozenAllHint : s.frozenSomeHint;
    final hint = weight == null ? status : '${s.frozen}: $weight. $status';
    final color = frozenColor(context);
    return Tooltip(
      message: hint,
      excludeFromSemantics: true,
      child: Semantics(
        label: hint,
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.ac_unit_rounded, size: 15, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                weight ?? (all ? s.frozenAllShort : s.frozenSomeShort),
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
