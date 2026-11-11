import 'package:flutter/material.dart';
import 'package:holybeans/data/services/device_feedback.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/l10n/app_localizations.dart';

/// What a [DevicePairingSection] says, in the device's own words.
typedef DevicePairingTexts = ({
  String hint,
  String find,
  String searching,
  String noneFound,
  String failed,
  String connect,
  String disconnect,
  String forget,
});

/// Settings for a Bluetooth device: find and pair one, then see its
/// [readout], disconnect or forget it. Keys start with [keyPrefix].
class DevicePairingSection extends StatelessWidget {
  const DevicePairingSection({
    super.key,
    required this.device,
    required this.keyPrefix,
    required this.texts,
    required this.statusLabel,
    required this.foundIcon,
    required this.readout,
    this.allowAdditionalDevices = false,
    this.showForget = true,
  });

  final PairedDevice device;
  final String keyPrefix;
  final DevicePairingTexts texts;
  final String Function(DeviceStatus status) statusLabel;
  final IconData foundIcon;
  final Widget readout;
  final bool allowAdditionalDevices;
  final bool showForget;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: device,
    builder: (context, _) {
      final theme = Theme.of(context);
      final muted = theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );
      final status = device.status;
      final searching = status == DeviceStatus.searching;
      final paired = device.name != null;
      // A paired device's readout already says what is wrong.
      final problem = paired && !searching
          ? null
          : switch (status) {
              DeviceStatus.bluetoothOff ||
              DeviceStatus.denied => statusLabel(status),
              DeviceStatus.failed => texts.failed,
              _ => null,
            };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(texts.hint, style: muted),
          ),
          if (paired && !searching) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: readout,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                spacing: 4,
                children: [
                  if (device.connected || status == DeviceStatus.connecting)
                    TextButton.icon(
                      key: ValueKey('$keyPrefix-disconnect'),
                      onPressed: device.disconnect,
                      icon: const Icon(Icons.bluetooth_disabled_rounded),
                      label: Text(texts.disconnect),
                    ),
                  if (showForget)
                    TextButton.icon(
                      key: ValueKey('$keyPrefix-forget'),
                      onPressed: device.forget,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text(texts.forget),
                    ),
                ],
              ),
            ),
          ],
          if (!paired || searching || allowAdditionalDevices) ...[
            ListTile(
              key: ValueKey('$keyPrefix-find'),
              leading: searching
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bluetooth_searching_rounded),
              title: Text(searching ? texts.searching : texts.find),
              onTap: status == DeviceStatus.connecting
                  ? null
                  : searching
                  ? device.stopSearch
                  : device.search,
            ),
            for (final found in device.found)
              ListTile(
                key: ValueKey('$keyPrefix-found-${found.id}'),
                leading: Icon(foundIcon),
                title: Text(found.name),
                trailing: FilledButton.tonal(
                  onPressed: status == DeviceStatus.connecting
                      ? null
                      : () => device.pair(found),
                  child: Text(texts.connect),
                ),
              ),
            if (!searching &&
                device.found.isEmpty &&
                status == DeviceStatus.idle &&
                device.hasSearched)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(texts.noneFound, style: muted),
              ),
          ],
          if (problem != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                problem,
                style: muted?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          // Bluetooth off has one fix, a tap away.
          if (status == DeviceStatus.bluetoothOff)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextButton.icon(
                  key: ValueKey('$keyPrefix-bluetooth-settings'),
                  onPressed: const DeviceFeedback().openBluetoothSettings,
                  icon: const Icon(Icons.settings_bluetooth_rounded),
                  label: Text(
                    AppLocalizations.of(context).openBluetoothSettings,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
