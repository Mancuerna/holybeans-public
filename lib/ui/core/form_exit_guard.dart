import 'dart:async';

import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';

// Bottom-sheet drag and barrier dismissals use Navigator.pop directly, so
// guarding only maybePop/PopScope would still discard the form on those paths.
class FormSheetRoute<T> extends ModalBottomSheetRoute<T> {
  FormSheetRoute({
    required super.builder,
    required super.capturedThemes,
    required super.barrierLabel,
    required super.barrierOnTapHint,
    required super.modalBarrierColor,
    required super.useSafeArea,
  }) : super(isScrollControlled: true, showDragHandle: true);

  Future<bool> Function()? confirmExit;
  bool _allowed = false;
  bool _checking = false;

  void complete(T? result) {
    _allowed = true;
    navigator?.pop<T>(result);
  }

  @override
  bool didPop(T? result) {
    final check = confirmExit;
    if (_allowed || check == null) return super.didPop(result);
    // A drag may already have reversed the sheet animation. Bring it back
    // while the user decides, including when they choose to keep editing.
    controller?.forward();
    if (!_checking) {
      _checking = true;
      scheduleMicrotask(() async {
        try {
          final accepted = await check();
          if (accepted && isActive && isCurrent) complete(result);
        } finally {
          _checking = false;
        }
      });
    }
    return false;
  }
}

class FormExitGuard extends StatefulWidget {
  const FormExitGuard({
    super.key,
    required this.hasChanges,
    required this.busy,
    required this.child,
  });

  final bool Function() hasChanges;
  final bool Function() busy;
  final Widget child;

  static void complete<T>(BuildContext context, [T? result]) {
    final route = ModalRoute.of(context);
    if (route is FormSheetRoute<Object?>) {
      route.complete(result);
    } else {
      context.findAncestorStateOfType<_FormExitGuardState>()?._allowed = true;
      Navigator.of(context).pop<T>(result);
    }
  }

  static void cancel(BuildContext context) {
    final guard = context.findAncestorStateOfType<_FormExitGuardState>();
    if (guard == null || ModalRoute.of(context) is FormSheetRoute<Object?>) {
      Navigator.of(context).pop();
    } else {
      unawaited(guard._close());
    }
  }

  @override
  State<FormExitGuard> createState() => _FormExitGuardState();
}

class _FormExitGuardState extends State<FormExitGuard> {
  FormSheetRoute<Object?>? _route;
  bool _allowed = false;
  bool _checking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is FormSheetRoute<Object?> && _route != route) {
      _route?.confirmExit = null;
      _route = route;
      route.confirmExit = _confirm;
    }
  }

  Future<bool> _confirm() async {
    if (!mounted || widget.busy()) return false;
    if (_allowed || !widget.hasChanges()) return true;
    final s = AppLocalizations.of(context)!;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.discardChangesTitle),
        content: Text(s.discardChangesMessage),
        actions: [
          TextButton(
            key: const ValueKey('keep-editing'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.keepEditing),
          ),
          FilledButton(
            key: const ValueKey('discard-changes'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.discardChanges),
          ),
        ],
      ),
    );
    return mounted && discard == true && !widget.busy();
  }

  Future<void> _close() async {
    if (_checking) return;
    _checking = true;
    try {
      if (await _confirm() && mounted) {
        setState(() => _allowed = true);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.of(context).pop();
      }
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _route?.confirmExit = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _route != null
      ? widget.child
      : PopScope<Object?>(
          canPop: _allowed,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_close());
          },
          child: widget.child,
        );
}
