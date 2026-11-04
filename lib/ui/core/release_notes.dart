import 'dart:async';

import 'package:flutter/material.dart';
import 'package:holybeans/data/preferences/release_notes_settings.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/error_report.dart';

class ReleaseNotesObserver extends NavigatorObserver {
  ReleaseNotesObserver(this.settings);
  final ReleaseNotesSettings settings;
  bool _shown = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _schedule(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _schedule(previousRoute);

  void _schedule(Route<dynamic>? route) {
    if (_shown || route == null || !route.isFirst) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (_shown || !route.isCurrent) return;
        final context = navigator?.overlay?.context;
        if (context == null || !context.mounted) return;
        _shown = true;
        unawaited(_show(context));
      });
    });
  }

  Future<void> _show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final s = AppLocalizations.of(context)!;
        return AlertDialog(
          key: const ValueKey('release-notes'),
          title: Text(s.releaseNotesTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.releaseNotesPerformance),
                const SizedBox(height: 16),
                Text(s.releaseNotesEquipmentDeletion),
                const SizedBox(height: 16),
                Text(s.releaseNotesFlowGuide),
                const SizedBox(height: 16),
                Text(s.releaseNotesFilterFinish),
                const SizedBox(height: 16),
                Text(s.releaseNotesClipboard),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.releaseNotesDone),
            ),
          ],
        );
      },
    );
    try {
      await settings.markSeen();
    } catch (error, stack) {
      reportError(error, stack);
    }
  }
}
