import 'package:flutter/material.dart';
import 'package:holybeans/data/services/meticulous_client.dart';
import 'package:holybeans/data/services/meticulous_free_pour.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/extraction_chart.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

/// Shows the latest free pour on the scale of the Meticulous at [address]
/// to pick it, marked when its id is in [imported]. Only the latest can be
/// read from outside the machine. Only reads its history.
Future<MeticulousFreePour?> pickMeticulousFreePour(
  BuildContext context, {
  required String address,
  required Set<String> imported,
}) => showModalBottomSheet<MeticulousFreePour>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => _FreePourPicker(address: address, imported: imported),
);

class _FreePourPicker extends StatefulWidget {
  const _FreePourPicker({required this.address, required this.imported});

  final String address;
  final Set<String> imported;

  @override
  State<_FreePourPicker> createState() => _FreePourPickerState();
}

class _FreePourPickerState extends State<_FreePourPicker> {
  MeticulousFreePour? pour;
  bool loaded = false;
  bool loading = false;
  String? error;

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
      final last = await source.lastFreePour();
      if (mounted) {
        setState(() {
          pour = last;
          loaded = true;
        });
      }
    } on FormatException {
      if (!mounted) return;
      final s = AppLocalizations.of(context)!;
      setState(() => error = s.meticulousInvalidAddress);
    } on MeticulousException catch (failure) {
      if (!mounted) return;
      final s = AppLocalizations.of(context)!;
      setState(() => error = s.meticulousConnectFailed(failure.message));
    } finally {
      source?.close();
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final found = pour;
    return ListView(
      key: const ValueKey('meticulous-free-pour-sheet'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      shrinkWrap: true,
      children: [
        Text(s.importFreePour, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          s.importFreePourHint,
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
        if (loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (loaded && found == null)
          Text(s.meticulousNoFreePour, key: const ValueKey('no-free-pour')),
        if (found != null)
          Card(
            key: ValueKey('meticulous-free-pour-${found.id}'),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.pop(context, found),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _when(found),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (widget.imported.contains(found.id))
                          Text(
                            s.meticulousImported,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                    Text(
                      freePourSummary(found, s),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (found.curve case final curve?) ...[
                      const SizedBox(height: 8),
                      ExtractionChart(
                        curve: curve,
                        compact: true,
                        flowUnit: 'g/s',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// When [pour] was made, in the device's format.
String _when(MeticulousFreePour pour) {
  final locale = regionalLocale;
  return [
    formatRegionalDate(pour.brewedAt, locale),
    regionalTimeFormat(locale.toString()).format(pour.brewedAt),
  ].join(' ');
}

/// "19 g · Water 299.1 g · Beverage 248.5 g · 4:28" for what [pour] has.
String freePourSummary(MeticulousFreePour pour, AppLocalizations s) {
  final number = NumberFormat('0.#', regionalLocale.toString());
  return [
    if (pour.doseGrams case final grams?) '${number.format(grams)} g',
    if (pour.waterGrams case final grams?)
      '${s.water} ${number.format(grams)} g',
    if (pour.beverageGrams case final grams?)
      '${s.brewOutput} ${number.format(grams)} g',
    if (pour.timeSeconds case final seconds?)
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
  ].join(', ');
}

/// Import the latest free pour from the Meticulous's scale, or the one
/// already picked with its curve.
class MeticulousFreePourCard extends StatelessWidget {
  const MeticulousFreePourCard({
    super.key,
    required this.pour,
    required this.onImport,
    required this.onRemove,
  });

  final MeticulousFreePour? pour;
  final VoidCallback onImport;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final picked = pour;
    return Card(
      key: const ValueKey('brew-meticulous-free-pour'),
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
                    picked == null ? 'Meticulous' : s.importedFreePour,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (picked != null)
                  IconButton(
                    tooltip: s.removeImportedFreePour,
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            if (picked case final picked?) ...[
              Text(freePourSummary(picked, s)),
              if (picked.curve case final curve?) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ExtractionChart(
                    curve: curve,
                    compact: true,
                    flowUnit: 'g/s',
                  ),
                ),
              ],
            ],
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('brew-import-free-pour'),
                onPressed: onImport,
                icon: const Icon(Icons.cloud_download_outlined),
                label: Text(s.importFreePour),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
