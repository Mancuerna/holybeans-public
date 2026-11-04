import 'package:flutter/material.dart';
import 'package:holybeans/data/services/device_feedback.dart';
import 'package:holybeans/data/services/pressure_sensor.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/scale/scale_readout.dart';
import 'package:holybeans/ui/settings/pressure_sensor_section.dart';
import 'package:intl/intl.dart';

/// A small button inside a weight field that writes the scale's current
/// weight into it; disabled while the scale is not connected.
class ScaleFillButton extends StatelessWidget {
  const ScaleFillButton({super.key, required this.scale, required this.onUse});

  final Scale scale;
  final ValueChanged<double> onUse;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: scale,
    builder: (context, _) {
      final s = AppLocalizations.of(context)!;
      final grams = scale.connected ? scale.reading?.grams : null;
      return IconButton(
        tooltip: grams == null
            ? s.scaleUseWeightOff
            : s.scaleUseWeight(
                NumberFormat('0.0', regionalLocale.toString()).format(grams),
              ),
        icon: const Icon(Icons.scale_outlined),
        onPressed: grams == null ? null : () => onUse(grams),
      );
    },
  );
}

/// One thin line for a Bluetooth device in the brew form: its icon, name and
/// live value, or its name with its state underneath ("Turn Bluetooth on"),
/// an action at the end and an optional note below, such as "Recording the
/// weight".
class DeviceStatusRow extends StatelessWidget {
  const DeviceStatusRow({
    super.key,
    required this.icon,
    required this.active,
    required this.text,
    this.status,
    this.detail,
    this.action,
    this.footer,
  });

  final IconData icon;

  /// Connected and reading: the icon takes the primary colour.
  final bool active;
  final String text;

  /// Why the device is not reading, also available in full in a tooltip.
  final String? status;

  /// A secondary note after the value, such as the battery.
  final String? detail;
  final Widget? action;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              (active
                                      ? theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        )
                                      : theme.textTheme.bodyMedium)
                                  ?.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                        ),
                      ),
                      if (detail case final note?) ...[
                        const SizedBox(width: 8),
                        Text(
                          note,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (status case final state?)
                    Tooltip(
                      message: state,
                      excludeFromSemantics: true,
                      child: Text(
                        state,
                        key: const ValueKey('device-status'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ?action,
          ],
        ),
        if (footer case final note?)
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              note,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
      ],
    );
  }
}

Widget _connecting(String label) => TextButton(
  onPressed: null,
  child: Stack(
    alignment: Alignment.center,
    children: [
      // Keep the reconnect button's footprint, including enlarged text.
      Visibility(
        visible: false,
        maintainSize: true,
        maintainState: true,
        maintainAnimation: true,
        child: Text(label),
      ),
      const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ],
  ),
);

/// The paired scale in the brew form: name, live weight and battery, with
/// "Tare" when connected and "Connect" when not.
class ScaleStatusRow extends StatelessWidget {
  const ScaleStatusRow({
    super.key,
    required this.scale,
    this.footer,
    this.resetAction,
    this.busy = false,
  });

  final Scale scale;
  final String? footer;
  final Widget? resetAction;
  final bool busy;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: scale,
    builder: (context, _) {
      final s = AppLocalizations.of(context)!;
      final reading = scale.connected ? scale.reading : null;
      final grams = NumberFormat('0.0', regionalLocale.toString());
      return DeviceStatusRow(
        key: const ValueKey('scale-readout'),
        icon: Icons.scale_outlined,
        active: reading != null,
        // Connected, the weight is what matters: the name (with its serial
        // number) only shows while the scale is away.
        text: reading == null
            ? scale.name ?? ''
            : '${grams.format(reading.grams)} g',
        status: reading == null ? scaleStatusLabel(s, scale.status) : null,
        detail: switch (reading?.batteryPercent) {
          final battery? => s.scaleBattery(battery),
          null => null,
        },
        footer: footer,
        action: reading != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    key: const ValueKey('scale-tare'),
                    onPressed: busy
                        ? null
                        : () => scale.send(ScaleCommand.tare),
                    child: Text(s.scaleTare),
                  ),
                  ?resetAction,
                ],
              )
            : scale.status == DeviceStatus.connecting
            ? _connecting(s.scaleConnect)
            // With Bluetooth off, Connect cannot work: open the switch.
            : scale.status == DeviceStatus.bluetoothOff
            ? TextButton(
                key: const ValueKey('scale-bluetooth-on'),
                onPressed: const DeviceFeedback().openBluetoothSettings,
                child: Text(s.scaleTurnOnBluetooth),
              )
            : TextButton(
                key: const ValueKey('scale-connect'),
                onPressed: scale.connect,
                child: Text(s.scaleConnect),
              ),
      );
    },
  );
}

/// The paired pressure sensor in the brew form: name and live pressure,
/// with "Connect" when it is not connected.
class PressureStatusRow extends StatelessWidget {
  const PressureStatusRow({super.key, required this.sensor, this.footer});

  final PressureSensor sensor;
  final String? footer;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sensor,
    builder: (context, _) {
      final s = AppLocalizations.of(context)!;
      final bar = sensor.connected ? sensor.bar : null;
      return DeviceStatusRow(
        key: const ValueKey('pressure-readout'),
        icon: Icons.speed_rounded,
        active: bar != null,
        text: bar == null
            ? sensor.name ?? ''
            : s.sensorBar(
                NumberFormat('0.0', regionalLocale.toString()).format(bar),
              ),
        status: bar == null
            ? pressureSensorStatusLabel(s, sensor.status)
            : null,
        footer: footer,
        action: sensor.connected
            ? null
            : sensor.status == DeviceStatus.connecting
            ? _connecting(s.scaleConnect)
            : TextButton(
                key: const ValueKey('pressure-connect'),
                onPressed: sensor.connect,
                child: Text(s.scaleConnect),
              ),
      );
    },
  );
}
