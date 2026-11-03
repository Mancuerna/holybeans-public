class ManualStopwatch implements Stopwatch {
  @override
  Duration elapsed = Duration.zero;
  @override
  bool isRunning = false;
  @override
  void start() => isRunning = true;
  @override
  void stop() => isRunning = false;
  @override
  void reset() => elapsed = Duration.zero;
  @override
  int get elapsedMilliseconds => elapsed.inMilliseconds;
  @override
  int get elapsedMicroseconds => elapsed.inMicroseconds;
  @override
  int get elapsedTicks => elapsed.inMicroseconds;
  @override
  int get frequency => 1000000;
}
