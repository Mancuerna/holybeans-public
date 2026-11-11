import 'package:flutter/material.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/domain/scale_recording.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

/// What [status] means for the user.
String scaleStatusLabel(AppLocalizations s, DeviceStatus status) =>
    switch (status) {
      DeviceStatus.connected => s.scaleConnected,
      DeviceStatus.connecting => s.scaleConnecting,
      DeviceStatus.searching => s.scaleSearching,
      DeviceStatus.idle => s.scaleDisconnected,
      DeviceStatus.failed => s.scaleFailed,
      DeviceStatus.bluetoothOff => s.scaleBluetoothOff,
      DeviceStatus.denied => s.scaleDenied,
    };

/// A button under the weight that hands it to a field, such as the dose.
typedef ScaleUse = ({Key key, String label, ValueChanged<double> onUse});

/// The paired scale: its live weight, battery and a tare button when
/// connected, or its state and a connect button when not. [uses] hand the
/// weight to the form.
class ScaleReadout extends StatelessWidget {
  const ScaleReadout({
    super.key,
    required this.scale,
    this.uses = const [],
    this.footer,
  });

  final Scale scale;
  final List<ScaleUse> uses;

  /// A line under the weight, such as whether it is being recorded.
  final String? footer;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: scale,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final reading = scale.reading;
    final connected = scale.connected && reading != null;
    final grams = NumberFormat('0.0', regionalLocale.toString());
    final battery = reading?.batteryPercent;
    return Card(
      key: const ValueKey('scale-readout'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.scale_outlined,
                  color: connected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: connected
                      ? Semantics(
                          liveRegion: false,
                          label:
                              '${scale.name}: ${grams.format(reading.grams)} g',
                          excludeSemantics: true,
                          child: Text(
                            '${grams.format(reading.grams)} g',
                            key: const ValueKey('scale-weight'),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        )
                      : Text(
                          '${scale.name}\n${scaleStatusLabel(s, scale.status)}',
                          style: theme.textTheme.bodyMedium,
                        ),
                ),
                if (connected && battery != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      s.scaleBattery(battery),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (connected)
                  TextButton(
                    key: const ValueKey('scale-tare'),
                    onPressed: () => scale.send(ScaleCommand.tare),
                    child: Text(s.scaleTare),
                  )
                else if (scale.status != DeviceStatus.connecting)
                  TextButton(
                    key: const ValueKey('scale-connect'),
                    onPressed: scale.connect,
                    child: Text(s.scaleConnect),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
            if (footer case final text?)
              Padding(
                padding: const EdgeInsets.only(left: 36, top: 2),
                child: Text(
                  text,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            if (connected && uses.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final use in uses)
                      ActionChip(
                        key: use.key,
                        avatar: const Icon(Icons.south_rounded, size: 18),
                        label: Text(use.label),
                        onPressed: () => use.onUse(reading.grams),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
