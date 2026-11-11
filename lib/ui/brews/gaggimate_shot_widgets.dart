import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/services/gaggimate_client.dart';
import 'package:holybeans/domain/gaggimate/shot.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/extraction_chart.dart';
import 'package:holybeans/ui/core/regional_dates.dart';

String gaggimateError(AppLocalizations s, GaggimateFailure failure) =>
    switch (failure) {
      GaggimateFailure.connection => s.gaggimateConnectionFailed,
      GaggimateFailure.unavailable => s.gaggimateHistoryUnavailable,
      GaggimateFailure.invalidData => s.gaggimateInvalidData,
    };

Future<GaggimateShot?> pickGaggimateShot(
  BuildContext context, {
  required String address,
  required Set<String> imported,
}) => showModalBottomSheet<GaggimateShot>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => _Picker(address: address, imported: imported),
);

class _Picker extends StatefulWidget {
  const _Picker({required this.address, required this.imported});
  final String address;
  final Set<String> imported;
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  GaggimateSource? source;
  List<GaggimateHistoryEntry>? entries;
  GaggimateFailure? failure;
  bool invalidAddress = false;
  bool loading = false;
  String? picking;
  int limit = 20;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    source?.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (loading || picking != null) return;
    setState(() {
      loading = true;
      failure = null;
      invalidAddress = false;
    });
    try {
      source ??= connectGaggimate(widget.address);
      final list = await source!.history();
      if (mounted) setState(() => entries = list);
    } on FormatException {
      if (mounted) setState(() => invalidAddress = true);
    } on GaggimateException catch (e, stack) {
      reportError(e, stack);
      if (mounted) setState(() => failure = e.failure);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _pick(GaggimateHistoryEntry entry) async {
    if (picking != null || loading) return;
    setState(() {
      picking = entry.id;
      failure = null;
    });
    try {
      final shot = await source!.shot(entry);
      if (mounted) Navigator.pop(context, shot);
    } on GaggimateException catch (e, stack) {
      reportError(e, stack);
      if (mounted) setState(() => failure = e.failure);
    } finally {
      if (mounted) setState(() => picking = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      child: ListView(
        shrinkWrap: true,
        key: const ValueKey('gaggimate-shot-list'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(s.gaggimateName, style: Theme.of(context).textTheme.titleLarge),
          Text(s.gaggimateImportHint),
          const SizedBox(height: 12),
          if (invalidAddress || failure != null) ...[
            Text(
              invalidAddress
                  ? s.meticulousInvalidAddress
                  : gaggimateError(s, failure!),
              key: const ValueKey('gaggimate-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: loading || picking != null ? null : _load,
              child: Text(s.retry),
            ),
          ],
          if (loading) const Center(child: CircularProgressIndicator()),
          if (entries?.isEmpty ?? false) Text(s.meticulousNoShots),
          for (final entry in (entries ?? const <GaggimateHistoryEntry>[]).take(
            limit,
          ))
            Card(
              child: ListTile(
                key: ValueKey('gaggimate-shot-${entry.id}'),
                enabled: picking == null && !loading,
                title: Text(entry.profileName),
                subtitle: Text(
                  '${formatRegionalDate(entry.brewedAt, regionalLocale)} '
                  '${regionalTimeFormat(regionalLocale.toString()).format(entry.brewedAt)}',
                ),
                trailing: picking == entry.id
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : widget.imported.contains(
                        gaggimateExternalId(
                          source!.machineAddress,
                          entry.id,
                          entry.brewedAt,
                        ),
                      )
                    ? Text(s.meticulousImported)
                    : const Icon(Icons.chevron_right_rounded),
                onTap: () => _pick(entry),
              ),
            ),
          if ((entries?.length ?? 0) > limit)
            TextButton(
              onPressed: () => setState(() => limit += 20),
              child: Text(s.loadMore),
            ),
        ],
      ),
    );
  }
}

class GaggimateShotCard extends StatelessWidget {
  const GaggimateShotCard({
    super.key,
    required this.shot,
    required this.onImport,
    required this.onRemove,
  });
  final GaggimateShot? shot;
  final VoidCallback onImport;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final picked = shot;
    return Card(
      key: const ValueKey('brew-gaggimate'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.wifi_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.gaggimateName,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (picked != null)
                  IconButton(
                    onPressed: onRemove,
                    tooltip: s.removeImportedShot,
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            if (picked != null) ...[
              Text(picked.profileName),
              if (picked.yieldGrams == null) Text(s.gaggimateNoScaleWeight),
              if (picked.curve case final curve?)
                ExtractionChart(curve: curve, compact: true, flowUnit: 'g/s'),
            ],
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('brew-import-gaggimate'),
                onPressed: onImport,
                icon: const Icon(Icons.cloud_download_outlined),
                label: Text(picked == null ? s.importShot : s.changeShot),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
