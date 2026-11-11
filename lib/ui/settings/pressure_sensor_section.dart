import 'package:flutter/material.dart';
import 'package:holybeans/core/decimal_format.dart';
import 'package:holybeans/data/services/pressure_sensor.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/settings/device_pairing_section.dart';

/// Short status of the pressure sensor connection.
String pressureSensorStatusLabel(AppLocalizations s, DeviceStatus status) =>
    switch (status) {
      DeviceStatus.connected => s.sensorConnected,
      DeviceStatus.connecting => s.sensorConnecting,
      DeviceStatus.searching => s.sensorSearching,
      DeviceStatus.failed => s.sensorFailed,
      DeviceStatus.bluetoothOff => s.sensorBluetoothOff,
      DeviceStatus.denied => s.sensorDenied,
      DeviceStatus.idle => s.sensorDisconnected,
    };

/// The paired sensor's name, status and live pressure, with a button to
/// connect when it is not.
class PressureReadout extends StatelessWidget {
  const PressureReadout({super.key, required this.sensor, this.footer});

  final PressureSensor sensor;

  /// Extra line, such as "Recording the pressure".
  final String? footer;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sensor,
    builder: (context, _) {
      final s = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final bar = sensor.bar;
      final busy =
          sensor.status == DeviceStatus.connecting ||
          sensor.status == DeviceStatus.searching;
      return Card(
        key: const ValueKey('pressure-readout'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              const Icon(Icons.speed_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${sensor.name ?? ''}\n'
                      '${pressureSensorStatusLabel(s, sensor.status)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (sensor.connected && bar != null)
                      Text(
                        s.sensorBar(
                          formatDecimal(
                            bar,
                            pattern: '0.0',
                            locale: regionalLocale.toString(),
                          ),
                        ),
                        key: const ValueKey('pressure-value'),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    if (footer case final text?)
                      Text(text, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (busy)
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (!sensor.connected)
                TextButton(
                  key: const ValueKey('pressure-connect'),
                  onPressed: sensor.connect,
                  child: Text(s.scaleConnect),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Settings for the Bluetooth pressure sensor: find and pair one, then see
/// its pressure, disconnect or forget it.
class PressureSensorSection extends StatelessWidget {
  const PressureSensorSection({super.key, required this.sensor});

  final PressureSensor sensor;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return DevicePairingSection(
      device: sensor,
      keyPrefix: 'sensor',
      texts: (
        hint: s.sensorHint,
        find: s.sensorFind,
        searching: s.sensorSearching,
        noneFound: s.sensorNoneFound,
        failed: s.sensorFailed,
        connect: s.scaleConnect,
        disconnect: s.scaleDisconnect,
        forget: s.sensorForget,
      ),
      statusLabel: (status) => pressureSensorStatusLabel(s, status),
      foundIcon: Icons.speed_rounded,
      readout: PressureReadout(sensor: sensor),
    );
  }
}
