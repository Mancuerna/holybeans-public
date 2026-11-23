import 'package:flutter/material.dart';
import 'package:holybeans/data/services/portal_sensor.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/settings/device_pairing_section.dart';
import 'package:holybeans/ui/settings/pressure_sensor_section.dart';

class PortalReadout extends StatelessWidget {
  const PortalReadout({super.key, required this.sensor});
  final BlePortalSensor sensor;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sensor,
    builder: (context, _) {
      final s = AppLocalizations.of(context);
      final reading = sensor.latest;
      return ListTile(
        title: Text(sensor.name ?? 'Belka Portal'),
        subtitle: Text(
          sensor.connected && reading != null
              ? 'EC ${reading.ec.toStringAsFixed(2)} · ${reading.outlet.toStringAsFixed(1)} °C'
              : pressureSensorStatusLabel(s, sensor.status),
        ),
        trailing: sensor.connected
            ? null
            : TextButton(
                onPressed: sensor.connect,
                child: Text(s.scaleConnect),
              ),
      );
    },
  );
}

class PortalSection extends StatelessWidget {
  const PortalSection({super.key, required this.sensor});
  final BlePortalSensor sensor;

  Future<void> _graph(BuildContext context, bool visible) async {
    try {
      await sensor.displayGraph(visible);
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).portalCommandFailed),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return DevicePairingSection(
      device: sensor,
      keyPrefix: 'portal',
      texts: (
        hint: s.portalHint,
        find: s.sensorFind,
        searching: s.sensorSearching,
        noneFound: s.sensorNoneFound,
        failed: s.sensorFailed,
        connect: s.scaleConnect,
        disconnect: s.scaleDisconnect,
        forget: s.sensorForget,
      ),
      statusLabel: (status) => pressureSensorStatusLabel(s, status),
      foundIcon: Icons.sensors,
      readout: ListenableBuilder(
        listenable: sensor,
        builder: (context, _) => Column(
          children: [
            PortalReadout(sensor: sensor),
            if (sensor.connected)
              Wrap(
                children: [
                  TextButton(
                    onPressed: () => _graph(context, true),
                    child: Text(s.portalShowGraph),
                  ),
                  TextButton(
                    onPressed: () => _graph(context, false),
                    child: Text(s.portalHideGraph),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
