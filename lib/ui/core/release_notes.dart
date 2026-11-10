import 'dart:async';

import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/preferences/current_release.g.dart';
import 'package:holybeans/data/preferences/release_notes_settings.dart';
import 'package:holybeans/l10n/app_localizations.dart';

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
        final language = Localizations.localeOf(context).languageCode;
        return AlertDialog(
          key: const ValueKey('release-notes'),
          title: Text(s.releaseNotesTitle),
          scrollable: true,
          content: _ReleaseNotesBody(
            currentReleaseNotes[language] ?? currentReleaseNotes['en']!,
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

class _ReleaseNotesBody extends StatelessWidget {
  const _ReleaseNotesBody(this.notes);

  final String notes;

  @override
  Widget build(BuildContext context) {
    final lines = notes
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        for (final line in lines)
          if (line.startsWith('- '))
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ExcludeSemantics(child: Text('•')),
                const SizedBox(width: 8),
                Expanded(child: Text(line.substring(2))),
              ],
            )
          else
            Text(line),
      ],
    );
  }
}
