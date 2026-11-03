import 'package:flutter/material.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/scale/scale_readout.dart';
import 'package:holybeans/ui/settings/device_pairing_section.dart';

/// Settings for the Bluetooth scale: find and pair one, then see its
/// weight, disconnect or forget it.
class ScaleSection extends StatelessWidget {
  const ScaleSection({super.key, required this.scale});

  final Scale scale;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: scale,
      builder: (context, _) => Column(
        children: [
          DevicePairingSection(
            device: scale,
            keyPrefix: 'scale',
            texts: (
              hint: s.scaleHint,
              find: s.scaleFind,
              searching: s.scaleSearching,
              noneFound: s.scaleNoneFound,
              failed: s.scaleFailed,
              connect: s.scaleConnect,
              disconnect: s.scaleDisconnect,
              forget: s.scaleForget,
            ),
            statusLabel: (status) => scaleStatusLabel(s, status),
            foundIcon: Icons.scale_outlined,
            readout: ScaleReadout(scale: scale),
            allowAdditionalDevices: true,
            showForget: false,
          ),
          for (final saved in scale.rememberedScales)
            ListTile(
              key: ValueKey('scale-saved-${saved.id}'),
              leading: Icon(
                scale.activeScaleId == saved.id
                    ? Icons.bluetooth_connected
                    : Icons.scale_outlined,
              ),
              title: Text(saved.name),
              subtitle: Text(
                scale.activeScaleId == saved.id
                    ? s.scaleConnected
                    : s.scaleRemembered,
              ),
              trailing: Wrap(
                children: [
                  if (scale.activeScaleId != saved.id)
                    IconButton(
                      tooltip: s.scaleConnect,
                      onPressed:
                          scale.status == DeviceStatus.connecting ||
                              scale.status == DeviceStatus.searching
                          ? null
                          : () => scale.pair(saved),
                      icon: const Icon(Icons.bluetooth),
                    ),
                  IconButton(
                    key: ValueKey('scale-forget-${saved.id}'),
                    tooltip: s.scaleForget,
                    onPressed: () => scale.forgetScale(saved.id),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
