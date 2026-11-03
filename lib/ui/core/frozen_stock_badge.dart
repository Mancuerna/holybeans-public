import 'package:flutter/material.dart';
import 'package:holybeans/domain/frozen_stock_state.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/semantic_colors.dart';

export 'package:holybeans/domain/frozen_stock_state.dart';

class FrozenStockBadge extends StatelessWidget {
  const FrozenStockBadge({super.key, required this.state});

  final FrozenStockState state;

  @override
  Widget build(BuildContext context) {
    if (state == FrozenStockState.none) return const SizedBox.shrink();
    final s = AppLocalizations.of(context)!;
    final all = state == FrozenStockState.all;
    final hint = all ? s.frozenAllHint : s.frozenSomeHint;
    final color = frozenColor(context);
    return Tooltip(
      message: hint,
      child: Semantics(
        label: hint,
        excludeSemantics: true,
        child: Container(
          margin: const EdgeInsetsDirectional.only(end: 6),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: BoxDecoration(
            color: all ? color.withValues(alpha: .12) : null,
            border: Border.all(color: color.withValues(alpha: .45)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.ac_unit_rounded, size: 15, color: color),
              const SizedBox(width: 3),
              Text(
                all ? s.frozenAllShort : s.frozenSomeShort,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
