import 'dart:async';

import 'package:holybeans/data/services/brew_live_notice.dart';

/// Keeps the ongoing notification of a brew in step with its timer, so it
/// can be read from the lock screen while the hands are busy: shown when it
/// starts (counting from where it starts), gone when it stops or resets.
/// The coffee and method are read at that moment, as they may have changed
/// since the form opened.
class BrewTimerNotice {
  BrewTimerNotice({
    required this.describe,
    this.notice = const BrewLiveNotice(),
  });

  final ({String title, String text}) Function() describe;
  final BrewLiveNotice notice;

  void started(int fromSeconds) {
    final labels = describe();
    unawaited(
      notice.showTimer(
        title: labels.title,
        text: labels.text,
        startedAt: DateTime.now().subtract(Duration(seconds: fromSeconds)),
      ),
    );
  }

  void ended() => unawaited(notice.clear());
}
