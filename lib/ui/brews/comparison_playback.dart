import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';

mixin ComparisonPlayback<T extends StatefulWidget> on State<T>, TickerProvider {
  double get playbackPosition;
  void updatePlaybackPosition(double value);

  late final AnimationController _replay = AnimationController(vsync: this)
    ..addListener(() {
      updatePlaybackPosition(_start + _replay.value * (_end - _start));
    })
    ..addStatusListener((_) {
      if (mounted) setState(() {});
    });
  late final AppLifecycleListener _lifecycle;
  double _start = 0;
  double _end = 0;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed) pausePlayback();
      },
    );
  }

  void pausePlayback() {
    if (!_replay.isAnimating) return;
    _replay.stop();
    setState(() {});
  }

  void _togglePlayback(double min, double max) {
    if (_replay.isAnimating) {
      pausePlayback();
      return;
    }
    _start = playbackPosition >= max ? min : playbackPosition.clamp(min, max);
    _end = max;
    _replay.duration = Duration(microseconds: ((_end - _start) * 1000).round());
    _replay.forward(from: 0);
  }

  Widget playbackButton({required double min, required double max}) {
    final s = AppLocalizations.of(context)!;
    return IconButton.filledTonal(
      key: const ValueKey('comparison-playback'),
      tooltip: _replay.isAnimating ? s.comparisonPause : s.comparisonPlay,
      onPressed: max > min ? () => _togglePlayback(min, max) : null,
      icon: Icon(
        _replay.isAnimating ? Icons.pause_rounded : Icons.play_arrow_rounded,
      ),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _replay.dispose();
    super.dispose();
  }
}
