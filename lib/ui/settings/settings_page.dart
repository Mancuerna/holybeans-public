import 'dart:async';

import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/preferences/rate_reminder_settings.dart';
import 'package:holybeans/data/services/device_feedback.dart';
import 'package:holybeans/data/services/pressure_sensor.dart';
import 'package:holybeans/data/services/refractometer.dart';
import 'package:holybeans/data/services/scale.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/share_templates_page.dart';
import 'package:holybeans/ui/coffee_maze/coffee_maze_page.dart';
import 'package:holybeans/ui/core/app_services.dart';
import 'package:holybeans/ui/scale/scale_readout.dart';
import 'package:holybeans/ui/settings/brew_parameters_page.dart';
import 'package:holybeans/ui/settings/pressure_sensor_section.dart';
import 'package:holybeans/ui/settings/refractometer_section.dart';
import 'package:holybeans/ui/settings/scale_section.dart';

/// App-wide preferences and data tools that do not belong to a single tab.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    this.services,
    super.key,
    required this.locale,
    required this.onLocaleChanged,
    required this.onExportBackup,
    required this.onExportCsv,
    required this.onImportBackup,
    this.backupTiles,
    this.onImportBeanconqueror,
    this.onConfigureLoffee,
    this.onFillPoursFromCurves,
  });

  final AppServices? services;

  /// The explicitly chosen app locale, or null when following the system.
  final Locale? locale;
  final ValueChanged<Locale?> onLocaleChanged;
  final Future<void> Function() onExportBackup;

  /// Shares every brew as CSV for spreadsheets.
  final VoidCallback onExportCsv;
  final Future<void> Function() onImportBackup;

  /// Automatic copies and the daily copy folder, below the manual backup.
  final Widget? backupTiles;

  /// Imports a BeanConqueror export; hidden without it.
  final VoidCallback? onImportBeanconqueror;

  /// Changes the device credential for Loffee Labs.
  final VoidCallback? onConfigureLoffee;

  /// Fills blooms and pours of saved filter brews from their curves.
  final VoidCallback? onFillPoursFromCurves;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final services = widget.services ?? AppServicesScope.read(context);
  late final _version = const DeviceFeedback().appVersion();
  Timer? _versionTapTimer;
  int _versionTaps = 0;
  bool _gameOpen = false;
  bool _backupBusy = false;

  Future<void> _runBackup(
    Future<void> Function() work,
    String failureMessage,
  ) async {
    if (_backupBusy) return;
    setState(() => _backupBusy = true);
    final navigator = Navigator.of(context, rootNavigator: true);
    final text = AppLocalizations.of(context).backupWorking;
    final progress = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          key: const ValueKey('backup-progress'),
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 24),
              Expanded(child: Text(text)),
            ],
          ),
        ),
      ),
    );
    navigator.push(progress);
    try {
      await work();
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failureMessage)));
      }
    } finally {
      // A restore confirmation may be above this route; never pop that instead.
      if (navigator.mounted && progress.isActive) {
        navigator.removeRoute(progress);
      }
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  void _tapVersion() {
    if (_gameOpen) return;
    _versionTapTimer?.cancel();
    _versionTaps++;
    if (_versionTaps < 5) {
      _versionTapTimer = Timer(
        const Duration(milliseconds: 900),
        () => _versionTaps = 0,
      );
      return;
    }
    _versionTaps = 0;
    _gameOpen = true;
    unawaited(
      Navigator.of(context)
          .push<void>(MaterialPageRoute(builder: (_) => const CoffeeMazePage()))
          .whenComplete(() => _gameOpen = false),
    );
  }

  @override
  void dispose() {
    _versionTapTimer?.cancel();
    super.dispose();
  }

  late String? languageCode = widget.locale?.languageCode;
  late final Stream<int?>? reminderMinutes = services.reminderSettings
      .watchMinutes();

  Future<void> _setReminder(int? minutes) async {
    final s = AppLocalizations.of(context);
    if (minutes != null && !(await services.reminders!.requestPermission())) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.notificationsDenied)));
      }
      return;
    }
    await services.reminderSettings.saveMinutes(minutes);
  }

  void _selectLanguage(String? code) {
    setState(() => languageCode = code);
    widget.onLocaleChanged(code == null ? null : Locale(code));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    Widget languageOption(String? code, String label) => ListTile(
      key: ValueKey('language-${code ?? 'system'}'),
      title: Text(label),
      selected: languageCode == code,
      trailing: languageCode == code ? const Icon(Icons.check_rounded) : null,
      onTap: () => _selectLanguage(code),
    );
    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _SettingsHeader(s.settingsPreparation),
          ListTile(
            key: const ValueKey('brew-parameters'),
            leading: const Icon(Icons.tune_rounded),
            title: Text(s.brewParameters),
            subtitle: Text(s.brewParametersHint),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    BrewParametersPage(settings: services.parameterSettings),
              ),
            ),
          ),
          if (services.reminders != null && reminderMinutes != null) ...[
            const Divider(height: 24),
            _ReminderOptions(stream: reminderMinutes!, onChanged: _setReminder),
          ],
          ListTile(
            key: const ValueKey('share-templates'),
            leading: const Icon(Icons.edit_note_rounded),
            title: Text(s.shareTemplates),
            subtitle: Text(s.shareTemplatesHint),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ShareTemplatesPage(settings: services.templateSettings),
              ),
            ),
          ),
          if (services.scale != null ||
              services.pressureSensor != null ||
              services.refractometer != null)
            _SettingsHeader(s.settingsDevices),
          if (services.scale case final scale?)
            _deviceTile(
              'settings-scale',
              s.scaleSection,
              Icons.scale_outlined,
              ScaleSection(scale: scale),
              device: scale,
              status: scaleStatusLabel,
            ),
          if (services.pressureSensor case final sensor?)
            _deviceTile(
              'settings-pressure',
              s.sensorSection,
              Icons.speed_rounded,
              PressureSensorSection(sensor: sensor),
              device: sensor,
              status: pressureSensorStatusLabel,
            ),
          if (services.refractometer case final refractometer?)
            _deviceTile(
              'settings-refractometer',
              s.refractometerSection,
              Icons.science_outlined,
              RefractometerSection(refractometer: refractometer),
              device: refractometer,
              status: refractometerStatusLabel,
            ),
          const Divider(height: 24),
          _SettingsHeader(s.backup),
          ListTile(
            leading: const Icon(Icons.ios_share_rounded),
            title: Text(s.exportBackup),
            enabled: !_backupBusy,
            onTap: () => _runBackup(widget.onExportBackup, s.backupFailed),
          ),
          ListTile(
            leading: const Icon(Icons.restore_rounded),
            title: Text(s.importBackup),
            enabled: !_backupBusy,
            onTap: () => _runBackup(widget.onImportBackup, s.restoreFailed),
          ),
          ?widget.backupTiles,
          _SettingsHeader(s.settingsTransfers),
          if (widget.onConfigureLoffee case final onConfigure?)
            ListTile(
              key: const ValueKey('loffee-key-settings'),
              leading: const Icon(Icons.key_outlined),
              title: Text(s.loffeeKeyTitle),
              subtitle: Text(s.loffeeKeySettingsHint),
              onTap: onConfigure,
            ),
          if (widget.onImportBeanconqueror case final onImport?)
            ListTile(
              key: const ValueKey('import-beanconqueror'),
              leading: const Icon(Icons.move_to_inbox_outlined),
              title: Text(s.bqImport),
              subtitle: Text(s.bqHowTo),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onImport,
            ),
          ListTile(
            key: const ValueKey('export-brews-csv'),
            leading: const Icon(Icons.table_chart_outlined),
            title: Text(s.exportBrewsCsv),
            subtitle: Text(s.exportBrewsCsvHint),
            onTap: widget.onExportCsv,
          ),
          if (widget.onFillPoursFromCurves != null)
            _SettingsHeader(s.settingsMaintenance),
          if (widget.onFillPoursFromCurves case final onFill?)
            ListTile(
              key: const ValueKey('pours-from-curves'),
              leading: const Icon(Icons.auto_graph_rounded),
              title: Text(s.poursFromCurvesTitle),
              subtitle: Text(s.poursFromCurvesHint),
              onTap: onFill,
            ),
          _SettingsHeader(s.settingsGeneral),
          languageOption(null, s.systemLanguage),
          languageOption('es', 'Español'),
          languageOption('en', 'English'),
          _SettingsHeader(s.settingsAbout),
          FutureBuilder<String?>(
            future: _version,
            builder: (context, snapshot) => switch (snapshot.data) {
              final version? => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    key: const ValueKey('app-version'),
                    leading: const Icon(Icons.info_outline_rounded),
                    title: Text(s.appVersionLabel),
                    subtitle: Text(version),
                    onTap: _tapVersion,
                  ),
                ],
              ),
              null => const SizedBox.shrink(),
            },
          ),
        ],
      ),
    );
  }

  /// A device's entry, with the one paired and its state underneath so it
  /// is known before opening it.
  Widget _deviceTile(
    String key,
    String title,
    IconData icon,
    Widget section, {
    required PairedDevice device,
    required String Function(AppLocalizations, DeviceStatus) status,
  }) => ListenableBuilder(
    listenable: device,
    builder: (context, _) {
      final s = AppLocalizations.of(context);
      return ListTile(
        key: ValueKey(key),
        leading: Icon(icon),
        title: Text(title),
        subtitle: switch (device.name) {
          final name? when name.trim().isNotEmpty => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name),
              Tooltip(
                message: status(s, device.status),
                excludeFromSemantics: true,
                child: Text(
                  status(s, device.status),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          _ => Text(s.deviceNotPaired),
        },
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: Text(title)),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [section],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
    child: Semantics(
      header: true,
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _ReminderOptions extends StatelessWidget {
  const _ReminderOptions({required this.stream, required this.onChanged});
  final Stream<int?> stream;
  final ValueChanged<int?> onChanged;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return StreamBuilder<int?>(
      stream: stream,
      builder: (context, snapshot) {
        final minutes = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile.adaptive(
              key: const ValueKey('rate-reminder-toggle'),
              secondary: const Icon(Icons.notifications_outlined),
              title: Text(s.rateReminder),
              subtitle: Text(s.rateReminderHint),
              value: minutes != null,
              onChanged: snapshot.connectionState == ConnectionState.waiting
                  ? null
                  : (on) => onChanged(
                      on ? RateReminderSettings.defaultMinutes : null,
                    ),
            ),
            if (minutes != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final delay in RateReminderSettings.delays)
                      ChoiceChip(
                        label: Text(s.minutesShort(delay)),
                        selected: minutes == delay,
                        onSelected: (_) => onChanged(delay),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
