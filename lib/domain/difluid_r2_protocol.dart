/// The Bluetooth protocol of the DiFluid R2 refractometer, as its maker
/// publishes it (github.com/DiFluid/difluid-sdk-demo, docs/protocolR2.md)
/// and BeanConqueror reads it (`src/classes/devices/difluidR2Refractometer.ts`,
/// GPL-3.0). Frames travel both ways on characteristic AA01 of service
/// 00FF: `DF DF`, function, command, data length, data, and a checksum
/// that is the sum of all the previous bytes, modulo 256.
///
/// HolyBeans only asks it to measure, as AGENTS.md allows: an average of
/// the number of tests the R2 is set to, which it first reads with the
/// documented query, so that the average (which takes that number and
/// stores it) leaves the setting as it was; a single test when the number
/// is unknown. BeanConqueror also sets the temperature unit, the automatic
/// test and the number of tests; those settings are deliberately left out,
/// as are brightness and calibration.
library;

import 'package:holybeans/domain/difluid_frame.dart';

export 'package:holybeans/domain/difluid_frame.dart' show difluidFrame;

/// Full 128-bit UUIDs of the refractometer's service and characteristic.
abstract final class DifluidR2Uuids {
  static const service = '000000ff-0000-1000-8000-00805f9b34fb';
  static const characteristic = '0000aa01-0000-1000-8000-00805f9b34fb';
}

/// Whether a device advertising [name] is a DiFluid R2.
bool isDifluidR2Name(String? name) =>
    name != null && name.toUpperCase().contains('R2');

const _deviceSettings = 1;
const _numberOfTests = 3;
const _deviceAction = 3;
const _singleTest = 0;
const _averageTest = 1;
const _error = 254;

/// "Single Test": measure the sample once (`DF DF 03 00 00 C1`).
final difluidSingleTest = difluidFrame(_deviceAction, _singleTest);

/// "Get Number of Tests": how many tests the device's own button averages
/// (`DF DF 01 03 00 C2`). Only reads the setting.
final difluidGetNumberOfTests = difluidFrame(_deviceSettings, _numberOfTests);

/// "Average Test" of [count] tests (1 to 10). The device stores [count] as
/// its number of tests, so it must be the one it already has.
List<int> difluidAverageTest(int count) =>
    difluidFrame(_deviceAction, _averageTest, [count.clamp(1, 10)]);

/// What the refractometer reports about a measurement.
sealed class R2Message {
  const R2Message();
}

/// How many tests the device averages, as it answered the query.
class R2TestCount extends R2Message {
  const R2TestCount(this.count);

  final int count;
}

/// A measurement started, from the app or the device's own button.
class R2Measuring extends R2Message {
  const R2Measuring();
}

/// The total dissolved solids measured, in percent. Below zero for water,
/// an empty prism or a device that needs zeroing.
class R2Result extends R2Message {
  const R2Result(this.tdsPercent);

  final double tdsPercent;
}

/// The measurement failed; [noLiquid] when there was no sample on the
/// prism.
class R2Failed extends R2Message {
  const R2Failed({this.noLiquid = false});

  final bool noLiquid;
}

/// Reads one notification: the number of tests, a measurement starting,
/// its result or an error. Null for anything else (temperatures, other
/// settings, device details) and for a frame that does not check out.
R2Message? parseR2Message(List<int> packet) {
  final frame = parseDifluidFrame(packet);
  if (frame == null) return null;
  final command = frame.command;
  final data = frame.data;
  if (frame.function == _deviceSettings) {
    return command == _numberOfTests && data.isNotEmpty
        ? R2TestCount(data[0])
        : null;
  }
  if (frame.function != _deviceAction) return null;
  if (command == _error) {
    // General errors (class 2) number 3 when no liquid is detected.
    return R2Failed(noLiquid: data.length >= 3 && data[1] == 2 && data[2] == 3);
  }
  if (command != _singleTest && command != _averageTest || data.isEmpty) {
    return null;
  }
  return switch (data[0]) {
    // Test status: a test (11) or an average test started (4) or going on
    // (5, 10).
    0 when data.length >= 2 && const {4, 5, 10, 11}.contains(data[1]) =>
      const R2Measuring(),
    // The result of a single test (2), or the mean of an average test (3),
    // not the readings taken on the way: TDS × 100.
    2 when command == _singleTest && data.length >= 3 => _result(data),
    3 when command == _averageTest && data.length >= 3 => _result(data),
    _ => null,
  };
}

/// A signed 16-bit TDS × 100: `FF F9` is −0.07 %.
R2Result _result(List<int> data) {
  var value = (data[1] << 8) | data[2];
  if (value >= 0x8000) value -= 0x10000;
  return R2Result(value / 100);
}
