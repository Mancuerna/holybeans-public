import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/services/niimbot_connection_log.dart';
import 'package:holybeans/domain/label_printer_profile.dart';

void main() {
  test(
    'includes scan outcome and redacted failures without device details',
    () {
      final log = NiimbotConnectionLog(LabelPrinterModel.d110M);
      log.record('scan.start', {'name': 'private'});
      log.record('scan.stop', {'supportedDevices': 0, 'name': 'private'});
      log.record('scan.error', {'error': 'Failed AA:BB:CC:DD:EE:FF'});
      expect(log.report, contains('scan.start {}'));
      expect(log.report, contains('scan.stop {"supportedDevices":0}'));
      expect(log.report, contains('scan.error {"error":"Failed [address]"}'));
      expect(log.report, isNot(contains('private')));
      expect(log.report, isNot(contains('AA:BB')));
    },
  );

  test('keeps connection evidence without label rows or device addresses', () {
    final log = NiimbotConnectionLog(LabelPrinterModel.b1Pro);
    expect(log.report, isEmpty);
    log.record('connect.start', {'id': 'AA:BB:CC:DD:EE:FF', 'name': 'private'});
    log.record('notification.raw', {'bytes': 'private label bytes'});
    log.record('niimbot.receive', {
      'bytes': 20,
      'decoded': 0,
      'buffered': 20,
      'invalidFrames': 0,
      'expected': 181,
      'raw': 'private bytes',
    });
    log.record('niimbot.mtu.result', {'mtu': 247, 'id': 'private'});
    log.record('niimbot.response', {
      'command': 0x48,
      'payload': [16, 1],
    });
    log.record('connect.error', {'error': 'Timeout AA:BB:CC:DD:EE:FF'});
    expect(log.report, contains('B1 Pro'));
    expect(log.report, contains('[16,1]'));
    expect(log.report, contains('"buffered":20'));
    expect(log.report, contains('"mtu":247'));
    expect(log.report, contains('Timeout [address]'));
    expect(log.report, isNot(contains('private')));
    expect(log.report, isNot(contains('AA:BB')));
  });

  test('bounds repeated attempts and native error length', () {
    final log = NiimbotConnectionLog(LabelPrinterModel.b1Pro);
    for (var i = 0; i < 500; i++) {
      log.record('connect.error', {'error': 'e' * 4000});
    }
    expect(log.report.split('\n'), hasLength(122));
    expect(log.report.length, lessThan(70000));
  });
}
