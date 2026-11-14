import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_scale_session.dart';

class BrewScaleWaitButton extends StatelessWidget {
  const BrewScaleWaitButton({super.key, required this.session});

  final BrewScaleSession session;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    if (session.waitingForDrip) {
      return OutlinedButton.icon(
        key: const ValueKey('scale-wait-drip-cancel'),
        onPressed: session.cancelWaitForDrip,
        icon: const Icon(Icons.close_rounded, size: 18),
        label: Text(s.scaleCancelWaitDrip),
      );
    }
    return Tooltip(
      message: s.scaleWaitDripHint,
      child: FilledButton.icon(
        key: const ValueKey('scale-wait-drip'),
        style: FilledButton.styleFrom(
          backgroundColor: colors.primaryContainer,
          foregroundColor: colors.onPrimaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: session.scale.connected && !session.resetting
            ? session.waitForDrip
            : null,
        icon: const Icon(Icons.water_drop_outlined, size: 18),
        label: Text(s.scaleWaitDrip),
      ),
    );
  }
}
