import 'package:flutter/material.dart';
import 'package:holybeans/data/services/refractometer.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/settings/device_pairing_section.dart';
import 'package:intl/intl.dart';

/// Short status of the refractometer connection.
String refractometerStatusLabel(AppLocalizations s, DeviceStatus status) =>
    switch (status) {
      DeviceStatus.connected => s.sensorConnected,
      DeviceStatus.connecting => s.sensorConnecting,
      DeviceStatus.searching => s.refractometerSearching,
      DeviceStatus.failed => s.sensorFailed,
      DeviceStatus.bluetoothOff => s.refractometerBluetoothOff,
      DeviceStatus.denied => s.refractometerDenied,
      DeviceStatus.idle => s.sensorDisconnected,
    };

/// The paired refractometer's name, status and last TDS, with a button to
/// connect when it is not.
class RefractometerReadout extends StatelessWidget {
  const RefractometerReadout({super.key, required this.refractometer});

  final Refractometer refractometer;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: refractometer,
    builder: (context, _) {
      final s = AppLocalizations.of(context)!;
      final theme = Theme.of(context);
      final tds = refractometer.tdsPercent;
      final busy =
          refractometer.status == DeviceStatus.connecting ||
          refractometer.status == DeviceStatus.searching;
      return Card(
        key: const ValueKey('refractometer-readout'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              const Icon(Icons.colorize_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${refractometer.name ?? ''}\n'
                      '${refractometerStatusLabel(s, refractometer.status)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (tds != null)
                      Text(
                        s.refractometerTds(
                          NumberFormat(
                            '0.00',
                            regionalLocale.toString(),
                          ).format(tds),
                        ),
                        key: const ValueKey('refractometer-value'),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (!refractometer.connected)
                TextButton(
                  key: const ValueKey('refractometer-connect'),
                  onPressed: refractometer.connect,
                  child: Text(s.scaleConnect),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Settings for the Bluetooth refractometer: find and pair one, then see
/// its last TDS, disconnect or forget it.
class RefractometerSection extends StatelessWidget {
  const RefractometerSection({super.key, required this.refractometer});

  final Refractometer refractometer;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return DevicePairingSection(
      device: refractometer,
      keyPrefix: 'refractometer',
      texts: (
        hint: s.refractometerHint,
        find: s.refractometerFind,
        searching: s.refractometerSearching,
        noneFound: s.sensorNoneFound,
        failed: s.sensorFailed,
        connect: s.scaleConnect,
        disconnect: s.scaleDisconnect,
        forget: s.refractometerForget,
      ),
      statusLabel: (status) => refractometerStatusLabel(s, status),
      foundIcon: Icons.colorize_outlined,
      readout: RefractometerReadout(refractometer: refractometer),
    );
  }
}
