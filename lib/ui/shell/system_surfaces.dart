import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/services/brew_live_notice.dart';
import 'package:holybeans/data/services/device_feedback.dart';
import 'package:holybeans/data/services/incoming_shares.dart';
import 'package:holybeans/domain/app_shortcut.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/bean_import.dart';
import 'package:holybeans/ui/shell/journal_actions.dart';
import 'package:holybeans/ui/shell/journal_view_model.dart';

/// What HolyBeans shows outside its own screens: the ongoing notice of a
/// brew, which it clears when the app starts, the home screen widget,
/// which follows the last brew, and the labels of both and of the launcher
/// shortcuts, in the app's language. Owned by the shell, started once.
class SystemSurfaces {
  SystemSurfaces({
    required this.journal,
    required this.describe,
    this.feedback = const DeviceFeedback(),
    this.notice = const BrewLiveNotice(),
  });

  final JournalViewModel journal;

  /// The widget's coffee name and recipe for [Brew], in the app's language.
  final (String?, String?) Function(Brew brew) describe;
  final DeviceFeedback feedback;
  final BrewLiveNotice notice;

  /// What the widget shows, to send it only when it changes.
  (String?, String?)? _shown;

  /// The labels last sent, to send them only when the language changes.
  Map<String, String>? _labels;

  void start() {
    // A brew left running when the app last died would keep its notice,
    // and its clock, until something cleared it.
    unawaited(notice.clear());
    journal.addListener(_syncWidget);
    _syncWidget();
  }

  void dispose() => journal.removeListener(_syncWidget);

  /// Sends [labels] (see [surfaceLabels]) when they change. After a change
  /// of language the widget's recipe, worded in it too, goes again.
  void relabel(Map<String, String> labels) {
    if (mapEquals(labels, _labels)) return;
    final changed = _labels != null;
    _labels = labels;
    unawaited(feedback.setSurfaceLabels(labels));
    if (changed) {
      _shown = null;
      _syncWidget();
    }
  }

  /// Keeps the home screen widget on the last brew, as Repeat would start.
  void _syncWidget() {
    if (journal.loading || journal.hasError) return;
    final brew = journal.latestUsableBrew;
    final shown = brew == null ? (null, null) : describe(brew);
    if (shown == _shown) return;
    _shown = shown;
    unawaited(feedback.updateWidget(title: shown.$1, recipe: shown.$2));
  }
}

/// The labels Android shows for HolyBeans outside the app, by the names
/// MainActivity reads (`SurfaceLabels.kt`).
Map<String, String> surfaceLabels(AppLocalizations s) => {
  'shortcutBrew': s.shortcutBrew,
  'shortcutBrewLong': s.shortcutBrewLong,
  'shortcutRepeat': s.shortcutRepeat,
  'shortcutRepeatLong': s.shortcutRepeatLong,
  'shortcutScan': s.shortcutScan,
  'shortcutScanLong': s.shortcutScanLong,
  'widgetLabel': s.widgetLabel,
  'widgetEmpty': s.widgetEmpty,
  'liveUpdateChannel': s.liveUpdateChannel,
};

/// Runs what a launcher shortcut, or the widget, asked for.
Future<void> runAppShortcut(
  BuildContext context,
  AppShortcut shortcut, {
  required JournalActions actions,
  required JournalViewModel journal,
  IncomingShares? incoming,
}) async {
  final last = journal.latestUsableBrew;
  switch (shortcut) {
    case AppShortcut.brew:
      await actions.navigation.openBrewForm(journal.coffees, seed: last);
    case AppShortcut.repeat:
      await actions.navigation.openBrewForm(
        journal.coffees,
        seed: last,
        repeat: last != null,
      );
    case AppShortcut.scanBean:
      if (incoming == null) break;
      final text = await scanBeanQr(
        actions,
        AppLocalizations.of(context)!,
        incoming,
      );
      if (text != null && context.mounted) {
        await importBeansFromText(context, actions, journal.coffees, text);
      }
    case AppShortcut.open:
      break;
  }
}
