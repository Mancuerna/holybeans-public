import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/core/error_report.dart';

void main() {
  late List<String> messages;
  late List<FlutterErrorDetails> presented;

  setUp(() {
    final print = debugPrint;
    final flutter = FlutterError.onError;
    final present = FlutterError.presentError;
    final platform = PlatformDispatcher.instance.onError;
    addTearDown(() {
      debugPrint = print;
      FlutterError.onError = flutter;
      FlutterError.presentError = present;
      PlatformDispatcher.instance.onError = platform;
    });
    messages = [];
    presented = [];
    debugPrint = (message, {wrapWidth}) => messages.add(message ?? '');
    FlutterError.presentError = presented.add;
    FlutterError.onError = (_) {};
    PlatformDispatcher.instance.onError = (_, _) => false;
    installErrorReporting();
  });

  test('framework failures retain diagnostics and reach the app log', () {
    final details = FlutterErrorDetails(
      exception: StateError('framework failure'),
      stack: StackTrace.fromString('frame one\nframe two'),
    );
    FlutterError.reportError(details);
    expect(presented, [details]);
    expect(messages.single, contains('framework failure (frame one)'));
    expect(messages.single, isNot(contains('frame two')));
  });

  test('framework failures without a stack still reach the app log', () {
    FlutterError.reportError(
      FlutterErrorDetails(exception: StateError('missing stack')),
    );
    expect(messages.single, contains('missing stack'));
    expect(presented, hasLength(1));
  });

  test('unhandled platform failures are reported and marked handled', () {
    expect(
      PlatformDispatcher.instance.onError!(
        StateError('async failure'),
        StackTrace.fromString('async frame'),
      ),
      isTrue,
    );
    expect(messages.single, contains('async failure (async frame)'));
  });
}
