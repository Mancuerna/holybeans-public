import 'package:integration_test/integration_test_driver.dart';

/// Writes each performance summary the test reports to `build/<key>.json`.
Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    for (final MapEntry(:key, :value) in (data ?? const {}).entries) {
      await writeResponseData(
        value as Map<String, dynamic>,
        testOutputFilename: key,
      );
    }
  },
);
