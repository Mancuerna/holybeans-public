import 'package:flutter/material.dart';
import 'package:holybeans/core/decimal_format.dart';
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
      final s = AppLocalizations.of(context);
      final grams = scale.connected ? scale.reading?.grams : null;
      return IconButton(
        tooltip: grams == null
            ? s.scaleUseWeightOff
            : s.scaleUseWeight(
                formatDecimal(
                  grams,
                  pattern: '0.0',
                  locale: regionalLocale.toString(),
                ),
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
    this.footerIcon,
    this.resetAction,
    this.extraAction,
    this.busy = false,
  });

  final Scale scale;
  final String? footer;
  final IconData? footerIcon;
  final Widget? resetAction;
  final Widget? extraAction;
  final bool busy;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: scale,
    builder: (context, _) {
      final s = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final reading = scale.connected ? scale.reading : null;
      final grams = NumberFormat('0.0', regionalLocale.toString());
      final tare = reading == null
          ? null
          : OutlinedButton(
              key: const ValueKey('scale-tare'),
              style: OutlinedButton.styleFrom(
                backgroundColor: colors.surfaceContainerLowest,
              ),
              onPressed: busy ? null : () => scale.send(ScaleCommand.tare),
              child: Text(s.scaleTare),
            );
      final content = Column(
        key: const ValueKey('scale-readout'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (reading != null)
            Row(
              children: [
                Icon(Icons.scale_outlined, size: 22, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${grams.format(reading.grams)} g',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (reading.batteryPercent case final battery?)
                        Text(
                          s.scaleBattery(battery),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                ?resetAction,
              ],
            )
          else
            DeviceStatusRow(
              icon: Icons.scale_outlined,
              active: false,
              text: scale.name ?? '',
              status: scaleStatusLabel(s, scale.status),
              action: scale.status == DeviceStatus.connecting
                  ? _connecting(s.scaleConnect)
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
            ),
          if (tare != null || extraAction != null) ...[
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final action = extraAction;
                if (tare == null) return action!;
                if (action == null) return tare;
                if (constraints.maxWidth < 300 ||
                    MediaQuery.textScalerOf(context).scale(14) > 18) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [tare, const SizedBox(height: 10), action],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: tare),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: action),
                  ],
                );
              },
            ),
          ],
          if (footer case final note?) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (footerIcon case final icon?) ...[
                  Icon(icon, size: 16, color: colors.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    note,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      );
      if (reading == null) return content;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: content,
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
      final s = AppLocalizations.of(context);
      final bar = sensor.connected ? sensor.bar : null;
      return DeviceStatusRow(
        key: const ValueKey('pressure-readout'),
        icon: Icons.speed_rounded,
        active: bar != null,
        text: bar == null
            ? sensor.name ?? ''
            : s.sensorBar(
                formatDecimal(
                  bar,
                  pattern: '0.0',
                  locale: regionalLocale.toString(),
                ),
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
