import 'package:flutter/material.dart';
import 'package:holybeans/data/services/meticulous_client.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/extraction_chart.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

/// Lets the user pick one of the latest shots of the Meticulous at
/// [address], each with its curve; shots in [imported] are marked. Only
/// reads the machine's history.
Future<MeticulousShot?> pickMeticulousShot(
  BuildContext context, {
  required String address,
  required Set<String> imported,
}) => showModalBottomSheet<MeticulousShot>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => _ShotPicker(address: address, imported: imported),
);

class _ShotPicker extends StatefulWidget {
  const _ShotPicker({required this.address, required this.imported});

  final String address;
  final Set<String> imported;

  @override
  State<_ShotPicker> createState() => _ShotPickerState();
}

class _ShotPickerState extends State<_ShotPicker> {
  static const _page = 10;
  int limit = _page;
  List<MeticulousShot>? shots;
  String? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    MeticulousSource? source;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      source = connectMeticulous(widget.address);
      final recent = await source.recentShots(limit: limit, withCurves: true);
      if (mounted) setState(() => shots = recent);
    } on FormatException {
      if (!mounted) return;
      final s = AppLocalizations.of(context);
      setState(() => error = s.meticulousInvalidAddress);
    } on MeticulousException catch (failure) {
      if (!mounted) return;
      final s = AppLocalizations.of(context);
      setState(() => error = s.meticulousConnectFailed(failure.message));
    } finally {
      source?.close();
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final deviceLocale = regionalLocale;
    final number = NumberFormat('0.#', regionalLocale.toString());
    final list = shots;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      child: ListView(
        key: const ValueKey('meticulous-shot-list'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        shrinkWrap: true,
        children: [
          Text(s.importShot, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            s.importShotHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (error case final message?) ...[
            Text(
              message,
              key: const ValueKey('meticulous-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(onPressed: _load, child: Text(s.retry)),
            ),
          ],
          if (list == null && loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (list != null && list.isEmpty) Text(s.meticulousNoShots),
          for (final shot in list ?? const <MeticulousShot>[])
            Card(
              key: ValueKey('meticulous-shot-${shot.id}'),
              margin: const EdgeInsets.only(bottom: 10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.pop(context, shot),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              shot.profileName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (widget.imported.contains(shot.id))
                            Text(
                              s.meticulousImported,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                      Text(
                        [
                          [
                            formatRegionalDate(shot.brewedAt, deviceLocale),
                            regionalTimeFormat(deviceLocale.toString())
                                .format(shot.brewedAt),
                          ].join(' '),
                          if (shot.timeSeconds != null) '${shot.timeSeconds} s',
                          if (shot.yieldGrams != null)
                            '${number.format(shot.yieldGrams)} g',
                          if (shot.peakPressureBar != null)
                            '${number.format(shot.peakPressureBar)} bar',
                        ].join(', '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (shot.curve case final curve?) ...[
                        const SizedBox(height: 8),
                        ExtractionChart(curve: curve, compact: true),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          if (list != null && list.length >= limit)
            Center(
              child: TextButton(
                key: const ValueKey('meticulous-load-more'),
                onPressed: loading
                    ? null
                    : () {
                        limit += _page;
                        _load();
                      },
                child: loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(s.loadMore),
              ),
            ),
        ],
      ),
    );
  }
}

/// Import from the method's Meticulous, or the shot already picked with
/// its curve.
class MeticulousShotCard extends StatelessWidget {
  const MeticulousShotCard({
    super.key,
    required this.shot,
    required this.onImport,
    required this.onRemove,
  });

  final MeticulousShot? shot;
  final VoidCallback onImport;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final picked = shot;
    return Card(
      key: const ValueKey('brew-meticulous'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.wifi_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    picked == null ? 'Meticulous' : s.importedShot,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (picked != null)
                  IconButton(
                    tooltip: s.removeImportedShot,
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            if (picked case final picked?) ...[
              Text(picked.profileName),
              if (picked.curve case final curve?) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ExtractionChart(curve: curve, compact: true),
                ),
              ],
            ],
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('brew-import-shot'),
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
