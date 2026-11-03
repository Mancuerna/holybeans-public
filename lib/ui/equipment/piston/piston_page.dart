import 'package:flutter/material.dart';
import 'package:holybeans/data/repositories/piston_repository.dart';
import 'package:holybeans/domain/meticulous/piston_analysis.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/equipment/piston/piston_chart.dart';
import 'package:holybeans/ui/equipment/piston/piston_credits.dart';
import 'package:holybeans/ui/equipment/piston/piston_model.dart';
import 'package:holybeans/ui/equipment/piston/piston_service_form.dart';
import 'package:intl/intl.dart';

class PistonPage extends StatefulWidget {
  const PistonPage({
    super.key,
    required this.repository,
    required this.methodId,
    required this.address,
    required this.name,
  });
  final PistonRepository repository;
  final String methodId;
  final String address;
  final String name;
  @override
  State<PistonPage> createState() => _PistonPageState();
}

class _PistonPageState extends State<PistonPage> {
  late final model = PistonModel(
    widget.repository,
    widget.methodId,
    widget.address,
  )..open();
  int days = 90;
  bool speed = false;
  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  Future<void> edit([PistonService? existing]) async {
    final result = await editPistonService(context, existing);
    if (result == null || !mounted) return;
    final ok = await model.save(result);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.pistonSaveError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final s = AppLocalizations.of(context)!;
      final locale = regionalLocale.toString();
      final number = NumberFormat('0.00', locale);
      final percent = NumberFormat('+0.0;-0.0', locale);
      String date(int ms) => formatRegionalDateTime(
        DateTime.fromMillisecondsSinceEpoch(ms),
        regionalLocale,
      );
      final data = model.data;
      final all = pistonSeries(data.readings, data.services, speed: speed);
      final since = days == 0
          ? 0
          : DateTime.now()
                .subtract(Duration(days: days))
                .millisecondsSinceEpoch;
      final points = all.where((p) => p.timeMs >= since).toList();
      final stats = pistonTrend(data.readings, data.services);
      final last = data.readings.where((r) => r.usable).lastOrNull;
      return Scaffold(
        appBar: AppBar(title: Text(s.pistonTitle)),
        body: SafeArea(
          child: model.loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      widget.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      data.checkedAtMs == null
                          ? s.pistonNeverUpdated
                          : '${s.pistonUpdated}: ${date(data.checkedAtMs!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          key: const ValueKey('piston-refresh'),
                          onPressed: model.busy ? null : model.refresh,
                          icon: const Icon(Icons.sync),
                          label: Text(s.pistonRefresh),
                        ),
                        if (model.busy)
                          TextButton(
                            onPressed: model.cancel,
                            child: Text(s.cancel),
                          ),
                      ],
                    ),
                    if (model.busy) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Text('${s.pistonProgress}: ${model.processed}'),
                    ],
                    if (model.failed || model.loadFailed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          model.loadFailed ? s.dataError : s.pistonOffline,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (!data.complete && data.serial != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(s.pistonPartial),
                      ),
                    const SizedBox(height: 16),
                    if (data.readings.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(s.pistonStart),
                        ),
                      )
                    else ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.pistonEffort,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                children: [
                                  ChoiceChip(
                                    label: Text(s.pistonCurrent),
                                    selected: !speed,
                                    onSelected: (_) =>
                                        setState(() => speed = false),
                                  ),
                                  ChoiceChip(
                                    label: Text(s.pistonSpeed),
                                    selected: speed,
                                    onSelected: (_) =>
                                        setState(() => speed = true),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  for (final d in [30, 90, 365, 0])
                                    ChoiceChip(
                                      label: Text(
                                        d == 0
                                            ? s.pistonAll
                                            : d == 365
                                            ? s.pistonYear
                                            : '$d ${s.pistonDays}',
                                      ),
                                      selected: days == d,
                                      onSelected: (_) =>
                                          setState(() => days = d),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              PistonChart(
                                points: points,
                                services: data.services,
                                speed: speed,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 24,
                        runSpacing: 16,
                        children: [
                          _Stat(
                            s.pistonRecent,
                            stats.level == null
                                ? '—'
                                : '${number.format(stats.level)} A',
                          ),
                          _Stat(
                            s.pistonChange,
                            stats.change == null
                                ? '—'
                                : '${percent.format(stats.change)} %',
                          ),
                          _Stat(
                            s.pistonTrend,
                            stats.monthly == null
                                ? '—'
                                : '${percent.format(stats.monthly)} %',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        data.services.isEmpty
                            ? s.pistonReference60
                            : s.pistonReferenceService,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (last != null)
                        Text(
                          '${s.pistonLastReading}: ${date(last.timeMs)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 12),
                      Text(
                        '${s.pistonUsable}: ${data.readings.where((r) => r.usable).length} / ${data.readings.length}',
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      s.pistonExplanation,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      key: const ValueKey('piston-add-service'),
                      onPressed: data.serial == null || model.busy
                          ? null
                          : edit,
                      icon: const Icon(Icons.build_outlined),
                      label: Text(s.pistonRecordService),
                    ),
                    for (final service in data.services.reversed)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(pistonServiceLabel(s, service.kind)),
                        subtitle: Text(
                          '${date(service.timeMs)}${service.notes.isEmpty ? '' : '\n${service.notes}'}',
                        ),
                        onTap: model.busy ? null : () => edit(service),
                        trailing: IconButton(
                          tooltip: s.pistonDeleteService,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: model.busy
                              ? null
                              : () async {
                                  final yes = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text(s.pistonDeleteService),
                                      content: Text(s.pistonDeleteConfirm),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: Text(s.cancel),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: Text(s.pistonDeleteService),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (yes != true || !mounted) return;
                                  final ok = await model.delete(service);
                                  if (!ok && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(s.pistonSaveError),
                                      ),
                                    );
                                  }
                                },
                        ),
                      ),
                    const SizedBox(height: 24),
                    const PistonCredits(),
                  ],
                ),
        ),
      );
    },
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      Text(value, style: Theme.of(context).textTheme.headlineSmall),
    ],
  );
}
