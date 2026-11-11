import 'dart:async';

import 'package:flutter/material.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/motion.dart';

/// The kinds of Bluetooth device the app pairs, to name them in a notice.
enum DeviceKind { scale, pressureSensor, refractometer }

/// Tells when a device becomes connected or stops being so, from the
/// statuses it goes through. Failed attempts to reconnect to a device that
/// is off are not changes.
class DeviceLinkWatch {
  bool _connected = false;

  /// True when [status] connects it, false when it disconnects it, null
  /// otherwise.
  bool? add(DeviceStatus status) {
    final connected = status == DeviceStatus.connected;
    if (connected == _connected) return null;
    _connected = connected;
    return connected;
  }
}

/// Over every screen, including sheets, a short notice that goes away by
/// itself when a paired device connects or disconnects.
class DeviceToasts extends StatefulWidget {
  const DeviceToasts({super.key, required this.devices, required this.child});

  final Map<DeviceKind, PairedDevice> devices;
  final Widget child;

  /// How long a notice stays.
  static const shownFor = Duration(seconds: 3);

  @override
  State<DeviceToasts> createState() => _DeviceToastsState();
}

class _DeviceToastsState extends State<DeviceToasts> {
  final _watches = <DeviceKind, DeviceLinkWatch>{};
  final _listeners = <DeviceKind, VoidCallback>{};
  ({DeviceKind kind, bool connected})? _notice;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(DeviceToasts oldWidget) {
    super.didUpdateWidget(oldWidget);
    _unlisten(oldWidget.devices);
    _listen();
  }

  void _listen() {
    for (final MapEntry(key: kind, value: device) in widget.devices.entries) {
      final watch = _watches.putIfAbsent(kind, DeviceLinkWatch.new)
        ..add(device.status);
      void listener() {
        if (watch.add(device.status) case final connected?) {
          _show(kind, connected);
        }
      }

      _listeners[kind] = listener;
      device.addListener(listener);
    }
  }

  void _unlisten(Map<DeviceKind, PairedDevice> devices) {
    for (final MapEntry(key: kind, value: device) in devices.entries) {
      if (_listeners.remove(kind) case final listener?) {
        device.removeListener(listener);
      }
    }
  }

  void _show(DeviceKind kind, bool connected) {
    _hide?.cancel();
    _hide = Timer(DeviceToasts.shownFor, () {
      if (mounted) setState(() => _notice = null);
    });
    setState(() => _notice = (kind: kind, connected: connected));
  }

  @override
  void dispose() {
    _hide?.cancel();
    _unlisten(widget.devices);
    super.dispose();
  }

  String _text(AppLocalizations s, DeviceKind kind, bool connected) =>
      switch ((kind, connected)) {
        (DeviceKind.scale, true) => s.toastScaleConnected,
        (DeviceKind.scale, false) => s.toastScaleDisconnected,
        (DeviceKind.pressureSensor, true) => s.toastSensorConnected,
        (DeviceKind.pressureSensor, false) => s.toastSensorDisconnected,
        (DeviceKind.refractometer, true) => s.toastRefractometerConnected,
        (DeviceKind.refractometer, false) => s.toastRefractometerDisconnected,
      };

  @override
  Widget build(BuildContext context) {
    final notice = _notice;
    final s = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final theme = Theme.of(context);
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 16,
          right: 16,
          // A notice never stands in the way of a tap.
          child: IgnorePointer(
            child: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: motionDuration(
                    context,
                    const Duration(milliseconds: 200),
                  ),
                  child: notice == null || s == null
                      ? const SizedBox.shrink()
                      : Semantics(
                          key: ValueKey(notice),
                          liveRegion: true,
                          child: Material(
                            key: const ValueKey('device-toast'),
                            elevation: 4,
                            color: theme.colorScheme.inverseSurface,
                            shape: const StadiumBorder(),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    notice.connected
                                        ? Icons.bluetooth_connected_rounded
                                        : Icons.bluetooth_disabled_rounded,
                                    size: 18,
                                    color: theme.colorScheme.onInverseSurface,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      _text(s, notice.kind, notice.connected),
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onInverseSurface,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
