import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:holybeans/data/preferences/coffee_maze_settings.dart';
import 'package:holybeans/domain/coffee_maze.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/coffee_maze/coffee_maze_painter.dart';

class CoffeeMazePage extends StatefulWidget {
  const CoffeeMazePage({super.key, this.settings});

  final Future<CoffeeMazeSettings> Function()? settings;

  @override
  State<CoffeeMazePage> createState() => _CoffeeMazePageState();
}

class _CoffeeMazePageState extends State<CoffeeMazePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _game = CoffeeMaze();
  final _frames = ValueNotifier(0);
  late final Ticker _ticker;
  late final Future<CoffeeMazeSettings?> _settings;
  Duration? _lastTick;
  double _lastSave = 0;
  int _best = 0;
  int _requestedBest = 0;
  bool _recordAvailable = true;
  Offset _drag = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_tick);
    _settings = _loadSettings();
  }

  Future<CoffeeMazeSettings?> _loadSettings() async {
    try {
      final settings = await (widget.settings ?? CoffeeMazeSettings.open)();
      final best = await settings.readBest();
      if (mounted) setState(() => _best = math.max(_best, best));
      return settings;
    } on Exception {
      if (mounted) setState(() => _recordAvailable = false);
      return null;
    }
  }

  Future<void> _saveBest() async {
    final score = math.max(_best, _game.score);
    if (score <= _requestedBest) return;
    _requestedBest = score;
    try {
      final settings = await _settings;
      await settings?.saveBest(score);
    } on Exception {
      _requestedBest = 0;
      if (mounted) setState(() => _recordAvailable = false);
    }
  }

  void _tick(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    if (previous == null) return;
    final before = (_game.score, _game.phase, _game.caffeine.ceil());
    _game.advance((elapsed - previous).inMicroseconds / 1000000);
    _best = math.max(_best, _game.score);
    _frames.value++;
    if (before != (_game.score, _game.phase, _game.caffeine.ceil())) {
      setState(() {});
    }
    if (_game.elapsed - _lastSave >= 2 || _game.phase != MazePhase.playing) {
      _lastSave = _game.elapsed;
      unawaited(_saveBest());
    }
    if (_game.phase != MazePhase.playing) _ticker.stop();
  }

  void _start() {
    unawaited(_saveBest());
    setState(_game.start);
    _lastTick = null;
    _lastSave = _game.elapsed;
    if (!_ticker.isActive) _ticker.start();
    _frames.value++;
  }

  void _pause() {
    if (_game.phase != MazePhase.playing) return;
    setState(_game.pause);
    _ticker.stop();
    _lastTick = null;
    unawaited(_saveBest());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause();
  }

  @override
  void dispose() {
    unawaited(_saveBest());
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _frames.dispose();
    super.dispose();
  }

  void _steer(MazeDirection direction) {
    if (_game.phase == MazePhase.playing) _game.steer(direction);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.keyW => MazeDirection.up,
      LogicalKeyboardKey.arrowDown ||
      LogicalKeyboardKey.keyS => MazeDirection.down,
      LogicalKeyboardKey.arrowLeft ||
      LogicalKeyboardKey.keyA => MazeDirection.left,
      LogicalKeyboardKey.arrowRight ||
      LogicalKeyboardKey.keyD => MazeDirection.right,
      _ => null,
    };
    if (direction != null) {
      _steer(direction);
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
      _game.phase == MazePhase.playing ? _pause() : _start();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    const cream = CoffeeMazePainter.cream;
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: CoffeeMazePainter.caramel,
          brightness: Brightness.dark,
        ),
      ),
      child: Focus(
        autofocus: true,
        onKeyEvent: _key,
        child: Scaffold(
          backgroundColor: CoffeeMazePainter.background,
          appBar: AppBar(
            title: Text(s.mazeTitle, style: const TextStyle(color: cream)),
            backgroundColor: CoffeeMazePainter.background,
            foregroundColor: cream,
            actions: [
              IconButton(
                key: const ValueKey('maze-pause'),
                tooltip: _game.phase == MazePhase.paused
                    ? s.mazeResume
                    : s.mazePause,
                onPressed: _game.phase == MazePhase.playing
                    ? _pause
                    : _game.phase == MazePhase.paused
                    ? _start
                    : null,
                icon: Icon(
                  _game.phase == MazePhase.paused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final sideways =
                    constraints.maxWidth >= 600 &&
                    constraints.maxWidth > constraints.maxHeight;
                final dashboard = _dashboard(s);
                final controls = _controls(s);
                if (sideways) {
                  return Row(
                    children: [
                      Expanded(child: _board(s)),
                      SizedBox(
                        width: 250,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              dashboard,
                              const SizedBox(height: 16),
                              controls,
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }
                final minimumHeight =
                    340 + MediaQuery.textScalerOf(context).scale(120);
                if (constraints.maxHeight < minimumHeight) {
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        dashboard,
                        SizedBox(
                          height:
                              constraints.maxWidth *
                                  CoffeeMaze.rows /
                                  CoffeeMaze.columns +
                              8,
                          child: _board(s),
                        ),
                        controls,
                      ],
                    ),
                  );
                }
                return Column(
                  children: [
                    dashboard,
                    Expanded(child: _board(s)),
                    controls,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _dashboard(AppLocalizations s) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 24,
          runSpacing: 4,
          children: [
            _stat(s.mazeScore, '${_game.score}'.padLeft(4, '0')),
            _stat(s.mazeBest, '$_best'.padLeft(4, '0')),
            _stat(s.mazeRound, '${_game.level}'),
          ],
        ),
        const SizedBox(height: 6),
        Semantics(
          label: s.mazeLives(_game.lives),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(
                    Icons.coffee_rounded,
                    size: 18,
                    color: i < _game.lives
                        ? CoffeeMazePainter.cream
                        : const Color(0xFF675045),
                  ),
                ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  _game.caffeine > 0
                      ? s.mazeRush(_game.caffeine.ceil())
                      : s.mazeCoffeeBreak,
                  style: const TextStyle(
                    color: CoffeeMazePainter.caramel,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!_recordAvailable)
          Text(
            s.mazeRecordUnavailable,
            style: const TextStyle(
              color: CoffeeMazePainter.cream,
              fontSize: 12,
            ),
          ),
      ],
    ),
  );

  Widget _stat(String label, String value) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: CoffeeMazePainter.caramel,
          fontSize: 11,
          letterSpacing: 1,
        ),
      ),
      Text(
        value,
        style: const TextStyle(
          color: CoffeeMazePainter.cream,
          fontFamily: 'PlexCondensed',
          fontSize: 24,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );

  Widget _board(AppLocalizations s) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Center(
      child: AspectRatio(
        aspectRatio: CoffeeMaze.columns / CoffeeMaze.rows,
        child: GestureDetector(
          key: const ValueKey('maze-board'),
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => _drag = Offset.zero,
          onPanUpdate: (details) {
            _drag += details.delta;
            if (_drag.distance < 12) return;
            _steer(
              _drag.dx.abs() > _drag.dy.abs()
                  ? (_drag.dx > 0 ? MazeDirection.right : MazeDirection.left)
                  : (_drag.dy > 0 ? MazeDirection.down : MazeDirection.up),
            );
            _drag = Offset.zero;
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  painter: CoffeeMazePainter(_game, repaint: _frames),
                ),
              ),
              if (_game.phase != MazePhase.playing) _overlay(s),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _overlay(AppLocalizations s) {
    final title = switch (_game.phase) {
      MazePhase.ready => s.mazeTitle,
      MazePhase.paused => s.mazePaused,
      MazePhase.caught => s.mazeCaught,
      MazePhase.cleared => s.mazeCleared,
      MazePhase.over => s.mazeGameOver,
      MazePhase.playing => '',
    };
    final action = switch (_game.phase) {
      MazePhase.ready => s.mazePlay,
      MazePhase.over => s.mazeAgain,
      MazePhase.cleared => s.mazeNext,
      _ => s.mazeResume,
    };
    return ColoredBox(
      color: CoffeeMazePainter.background.withValues(alpha: .86),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.coffee_rounded,
                size: 38,
                color: CoffeeMazePainter.caramel,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: CoffeeMazePainter.cream,
                  fontFamily: 'PlexCondensed',
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _game.phase == MazePhase.ready
                    ? s.mazeInstructions
                    : _game.phase == MazePhase.cleared
                    ? s.mazeBonus
                    : s.mazeScoreValue(_game.score),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: CoffeeMazePainter.cream,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const ValueKey('maze-start'),
                style: FilledButton.styleFrom(
                  backgroundColor: CoffeeMazePainter.cream,
                  foregroundColor: CoffeeMazePainter.background,
                ),
                onPressed: _start,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(action),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls(AppLocalizations s) {
    Widget button(MazeDirection direction, IconData icon, String label) =>
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            key: ValueKey('maze-${direction.name}'),
            tooltip: label,
            onPressed: () => _steer(direction),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF493128),
              foregroundColor: CoffeeMazePainter.cream,
              padding: EdgeInsets.zero,
            ),
            icon: Icon(icon, size: 26),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(MazeDirection.up, Icons.keyboard_arrow_up_rounded, s.mazeUp),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              button(
                MazeDirection.left,
                Icons.keyboard_arrow_left_rounded,
                s.mazeLeft,
              ),
              const SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  Icons.coffee_outlined,
                  size: 19,
                  color: CoffeeMazePainter.caramel,
                ),
              ),
              button(
                MazeDirection.right,
                Icons.keyboard_arrow_right_rounded,
                s.mazeRight,
              ),
            ],
          ),
          button(
            MazeDirection.down,
            Icons.keyboard_arrow_down_rounded,
            s.mazeDown,
          ),
        ],
      ),
    );
  }
}
