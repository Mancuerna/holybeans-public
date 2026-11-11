import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_scale_session.dart';
import 'package:holybeans/ui/brews/brew_timer.dart';

class BrewScaleResetButton extends StatefulWidget {
  const BrewScaleResetButton({
    super.key,
    required this.session,
    required this.timer,
  });

  final BrewScaleSession session;
  final BrewTimer timer;

  @override
  State<BrewScaleResetButton> createState() => _BrewScaleResetButtonState();
}

class _BrewScaleResetButtonState extends State<BrewScaleResetButton> {
  bool _busy = false;

  Future<void> _reset() async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = AppLocalizations.of(context)!;
    try {
      if (widget.timer.running) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(s.scaleReset),
            content: Text(s.scaleResetConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(s.cancel),
              ),
              FilledButton(
                key: const ValueKey('scale-reset-confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(s.scaleResetAction),
              ),
            ],
          ),
        );
        if (!mounted || confirmed != true) return;
      }
      final success = await widget.session.resetWeightAndTimer(
        widget.timer.reset,
      );
      if (mounted && !success) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.scaleResetFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) => IconButton(
      key: const ValueKey('scale-reset'),
      tooltip: AppLocalizations.of(context)!.scaleReset,
      icon: const Icon(Icons.restart_alt_rounded, size: 20),
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      onPressed:
          _busy || widget.session.resetting || !widget.session.scale.connected
          ? null
          : _reset,
    ),
  );
}
