import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/data/services/beanconqueror_archive.dart';
import 'package:holybeans/data/services/beanconqueror_sources.dart';
import 'package:holybeans/data/services/export_folder.dart';
import 'package:holybeans/data/services/photo_resizer.dart';
import 'package:holybeans/data/services/photo_store.dart';
import 'package:holybeans/domain/beanconqueror/bq_flow_profile.dart';
import 'package:holybeans/domain/beanconqueror/bq_import_plan.dart';
import 'package:holybeans/domain/beanconqueror/bq_values.dart';
import 'package:holybeans/domain/shot_curve.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/form_widgets.dart';

/// What an import brought, in one line.
String bqSummaryMessage(AppLocalizations s, BqImportSummary summary) {
  final added = summary.coffees + summary.brews > 0
      ? s.bqImported(summary.coffees, summary.brews)
      : null;
  final photos = summary.photos > 0 ? s.bqPhotosAdded(summary.photos) : null;
  final curves = summary.curves > 0 ? s.bqCurvesAdded(summary.curves) : null;
  final updated = summary.updated > 0
      ? s.bqUpdatedCount(summary.updated)
      : null;
  final parts = [?added, ?updated, ?photos, ?curves];
  return parts.isEmpty ? s.bqNothingNew : parts.join(', ');
}

/// Where an export is read from.
enum _BqSource { folder, file }

/// Lets the user pick a BeanConqueror export, shows what importing it
/// adds and imports it. With [folder] (Android), the export folder itself
/// can be picked, curves and photos included; otherwise, or by choice, a
/// file. Returns what was added, or null.
Future<BqImportSummary?> importFromBeanconqueror(
  BuildContext context, {
  required JournalRepository repository,
  PhotoStore? photos,
  ExportFolder? folder,
}) async {
  final s = AppLocalizations.of(context)!;
  final source = folder == null
      ? _BqSource.file
      : await showModalBottomSheet<_BqSource>(
          context: context,
          showDragHandle: true,
          builder: (context) => const _SourceSheet(),
        );
  if (source == null || !context.mounted) return null;
  BqImportPlan? plan;
  BqExtraFiles? extra;
  try {
    if (source == _BqSource.folder) {
      final uri = await folder!.pick();
      if (uri == null || !context.mounted) return null;
      plan = await _whileReading(context, () async {
        final files = await folder.list(uri);
        final export = await FolderExtraFiles.exportOf(folder, files);
        if (export == null) return null;
        extra = FolderExtraFiles(folder, files);
        return _plan(export, repository);
      });
      if (plan == null) {
        if (context.mounted) showMessage(context, s.bqFolderNoExport);
        return null;
      }
    } else {
      const types = XTypeGroup(
        label: 'BeanConqueror',
        extensions: ['zip', 'json'],
      );
      final file = await openFile(acceptedTypeGroups: [types]);
      if (file == null || !context.mounted) return null;
      plan = await _whileReading(context, () async {
        final bytes = await file.readAsBytes();
        // A ZIP of the whole export folder brings its curves and photos.
        extra = await ZipExtraFiles.of(bytes);
        return _plan(bytes, repository);
      });
    }
  } on BqArchiveException {
    if (context.mounted) showMessage(context, s.bqNotAnExport);
    return null;
  } on Object catch (error, stack) {
    reportError(error, stack);
    if (context.mounted) showOperationError(context, error, s.bqImportFailed);
    return null;
  }
  final ready = plan;
  if (!context.mounted || ready == null) return null;
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => BeanconquerorImportPage(
        plan: ready,
        repository: repository,
        photos: photos,
        extra: extra,
      ),
    ),
  );
}

/// What [bytes] of an export would add to the journal. Large exports take
/// a moment to unzip and decode, so that happens off the UI thread; a
/// static function, so nothing else travels to the other isolate.
Future<BqImportPlan> _plan(
  Uint8List bytes,
  JournalRepository repository,
) async {
  final export = await compute(BeanconquerorArchive.read, bytes);
  return planBeanconquerorImport(
    export,
    await repository.beanconquerorJournal(),
    now: DateTime.now(),
  );
}

/// Runs [work] behind a dialog that says the export is being read, so the
/// screen does not sit still while a large export is listed and decoded.
Future<T> _whileReading<T>(
  BuildContext context,
  Future<T> Function() work,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final text = AppLocalizations.of(context)!.bqReadingExport;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          key: const ValueKey('bq-reading-export'),
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 24),
              Expanded(child: Text(text)),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    return await work();
  } finally {
    navigator.pop();
  }
}

/// The export folder, recommended, or a file.
class _SourceSheet extends StatelessWidget {
  const _SourceSheet();

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('bq-source-folder'),
            leading: const Icon(Icons.folder_open_rounded),
            title: Text(s.bqSourceFolder),
            subtitle: Text(s.bqSourceFolderHint),
            onTap: () => Navigator.pop(context, _BqSource.folder),
          ),
          ListTile(
            key: const ValueKey('bq-source-file'),
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(s.bqSourceFile),
            subtitle: Text(s.bqSourceFileHint),
            onTap: () => Navigator.pop(context, _BqSource.file),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// What an import will add, with the photos to bring along, and the button
/// that imports it.
class BeanconquerorImportPage extends StatefulWidget {
  const BeanconquerorImportPage({
    super.key,
    required this.plan,
    required this.repository,
    this.photos,
    this.extra,
    this.pickFiles = _pickFiles,
  });

  final BqImportPlan plan;
  final JournalRepository repository;

  /// Curves and photos that came with the export: its folder, or a ZIP of
  /// it.
  final BqExtraFiles? extra;

  /// Photo folder; without it photos are not offered.
  final PhotoStore? photos;

  /// Opens the file picker for photos and flow profiles; tests pass their
  /// own.
  final Future<List<XFile>> Function() pickFiles;

  static Future<List<XFile>> _pickFiles() => openFiles(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'BeanConqueror',
        extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'json', 'zip'],
      ),
    ],
  );

  @override
  State<BeanconquerorImportPage> createState() =>
      _BeanconquerorImportPageState();
}

class _BeanconquerorImportPageState extends State<BeanconquerorImportPage> {
  /// Picked files by the BeanConqueror file name they stand for.
  final picked = <String, XFile>{};

  /// Where curves and photos come from: the export's own and any ZIP
  /// picked.
  late final bundles = <BqExtraFiles>[?widget.extra];
  bool importing = false;

  /// What the import is busy with and, when it can tell, how much of it is
  /// done out of how much.
  (_BqStage, int?, int?)? progress;

  void _show(_BqStage stage, [int? done, int? total]) {
    if (mounted) setState(() => progress = (stage, done, total));
  }

  BqImportPlan get plan => widget.plan;

  bool _available(String name) =>
      picked.containsKey(name) ||
      bundles.any((bundle) => bundle.names.contains(name));

  /// Adds picked files that the import refers to; the photos and the
  /// curves (in the export's `brews` folder) can be picked in turns, one
  /// by one or zipped. Hundreds of loose files are too much for the
  /// system picker, which reads them all at once; a ZIP is read lazily.
  Future<void> _pickFiles() async {
    final wanted = {
      if (widget.photos != null) ...plan.photoNames,
      ...plan.curveNames,
    };
    final files = await widget.pickFiles();
    final zips = <BqExtraFiles>[];
    for (final file in files) {
      final name = file.name.isEmpty ? file.path : file.name;
      if (!name.toLowerCase().endsWith('.zip')) continue;
      try {
        final zip = await ZipExtraFiles.of(await file.readAsBytes());
        if (zip != null && zip.names.any(wanted.contains)) zips.add(zip);
      } on Object catch (error, stack) {
        reportError(error, stack);
        // Not a ZIP after all; nothing in it is used.
      }
    }
    if (!mounted) return;
    setState(() {
      bundles.addAll(zips);
      for (final file in files) {
        final name = bqFileName(file.name.isEmpty ? file.path : file.name);
        if (wanted.contains(name)) picked[name] = file;
      }
    });
  }

  Future<void> _import() async {
    final s = AppLocalizations.of(context)!;
    setState(() => importing = true);
    final stored = <String, String>{};
    try {
      if (widget.photos case final store?) await _storePhotos(store, stored);
      final curves = <String, ShotCurve>{};
      if (plan.curveNames.any(picked.containsKey)) _show(_BqStage.curves);
      for (final name in plan.curveNames) {
        final file = picked[name];
        if (file == null) continue;
        try {
          final curve = bqFlowCurve(jsonDecode(await file.readAsString()));
          if (curve != null) curves[name] = curve;
        } on FormatException {
          // A profile that does not read is left out, like a missing one.
        }
      }
      // Curves from a folder or ZIP are read a few at a time and decoded
      // off the UI thread.
      for (final bundle in bundles) {
        final wanted = _fromBundle(bundle, plan.curveNames, curves.keys);
        if (wanted.isEmpty) continue;
        _show(_BqStage.curves);
        curves.addAll(
          await bundle.curves(
            wanted,
            onProgress: (done, total) => _show(_BqStage.curves, done, total),
          ),
        );
      }
      _show(_BqStage.saving);
      final summary = await widget.repository.importBeanconqueror(
        plan,
        photos: stored,
        curves: curves,
      );
      if (mounted) Navigator.pop(context, summary);
    } on Object catch (error, stack) {
      reportError(error, stack);
      // The journal is untouched; drop the photos copied for it.
      for (final name in stored.values) {
        try {
          await widget.photos?.delete(name);
        } catch (cleanupError, cleanupStack) {
          reportError(cleanupError, cleanupStack);
        }
      }
      if (mounted) {
        setState(() {
          importing = false;
          progress = null;
        });
        showOperationError(context, error, s.bqImportFailed);
      }
    }
  }

  /// Photos read per trip to a folder or ZIP, so only a few full-size ones
  /// are in memory at once.
  static const _photoBatch = 12;

  /// Shrinks and stores the photos the import refers to, from the files
  /// picked and then from each folder or ZIP, noting where each went in
  /// [stored].
  Future<void> _storePhotos(
    PhotoStore store,
    Map<String, String> stored,
  ) async {
    final total = plan.photoNames.where(_available).length;
    if (total == 0) return;
    var done = 0;
    void report() => _show(_BqStage.photos, done, total);

    Future<void> keep(Iterable<MapEntry<String, Uint8List>> photos) =>
        shrinkEach(photos, (name, bytes) async {
          stored[name] = await store.add(bytes);
          done++;
          report();
        });

    report();
    final loose = [
      for (final MapEntry(key: name, value: file) in picked.entries)
        if (plan.photoNames.contains(name)) (name, file),
    ];
    for (var start = 0; start < loose.length; start += _photoBatch) {
      await keep([
        for (final (name, file) in loose.skip(start).take(_photoBatch))
          MapEntry(name, await file.readAsBytes()),
      ]);
    }
    for (final bundle in bundles) {
      final wanted = _fromBundle(bundle, plan.photoNames, stored.keys).toList()
        ..sort();
      for (var start = 0; start < wanted.length; start += _photoBatch) {
        final files = await bundle.files(
          wanted.skip(start).take(_photoBatch).toSet(),
        );
        await keep(files.entries);
      }
    }
  }

  /// Which of [names] to take from [bundle]: those it has and that were
  /// not taken already.
  static Set<String> _fromBundle(
    BqExtraFiles bundle,
    Set<String> names,
    Iterable<String> taken,
  ) => names.where(bundle.names.contains).toSet().difference(taken.toSet());

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    int count<T>(List<T> rows, bool Function(T) test) =>
        rows.where(test).length;
    final added = [
      (Icons.coffee_outlined, plan.coffees.length, s.bqCoffees),
      (Icons.history_rounded, plan.brews.length, s.bqBrews),
      (
        Icons.coffee_maker_outlined,
        count(plan.methods, (row) => row.reuseId == null),
        s.bqMethods,
      ),
      (
        Icons.blender_outlined,
        count(plan.grinders, (row) => row.reuseId == null),
        s.bqGrinders,
      ),
      (
        Icons.water_drop_outlined,
        count(plan.waters, (row) => row.reuseId == null),
        s.bqWaters,
      ),
    ];
    final reused =
        count(plan.methods, (row) => row.reuseId != null) +
        count(plan.grinders, (row) => row.reuseId != null) +
        count(plan.waters, (row) => row.reuseId != null);
    final frozen = count(plan.coffees, (row) => row.portion != null);
    final archived = count(plan.coffees, (row) => row.archivedAtMs != null);
    final skipped = plan.skipped.values.fold(0, (sum, n) => sum + n);
    final notes = [
      if (reused > 0) s.bqReused(reused),
      if (frozen > 0) s.bqFrozen(frozen),
      if (archived > 0) s.bqArchived(archived),
      if (skipped > 0) s.bqSkipped(skipped),
      if (plan.changedCoffees.length + plan.changedBrews.length
          case final changed when changed > 0)
        s.bqChanged(changed),
      if (plan.conflicts > 0) s.bqConflicts(plan.conflicts),
      if (plan.updates.isNotEmpty) s.bqUpdates(plan.updates.length),
      if (plan.warnings[BqWarning.brewWithoutBean] case final n?) s.bqNoBean(n),
      if (plan.warnings[BqWarning.missingDate] case final n?) s.bqNoDate(n),
    ];
    final photoNames = widget.photos == null
        ? const <String>{}
        : plan.photoNames;
    final curveNames = plan.curveNames;
    int found(Set<String> names) => names.where(_available).length;
    final complete =
        found(photoNames) == photoNames.length &&
        found(curveNames) == curveNames.length;

    final page = Scaffold(
      appBar: AppBar(title: Text(s.bqImport)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (plan.isEmpty)
              Text(s.bqNothingNew, key: const ValueKey('bq-nothing-new'))
            else ...[
              Text(s.bqIntro, style: muted),
              const SizedBox(height: 12),
              for (final (icon, number, label) in added)
                if (number > 0)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(icon),
                    title: Text(label(number)),
                  ),
            ],
            for (final note in notes)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(note, style: muted),
              ),
            if (photoNames.isNotEmpty || curveNames.isNotEmpty) ...[
              const Divider(height: 32),
              if (photoNames.isNotEmpty)
                Text(
                  s.bqPhotos(found(photoNames), photoNames.length),
                  key: const ValueKey('bq-photo-count'),
                  style: theme.textTheme.titleMedium,
                ),
              if (curveNames.isNotEmpty)
                Text(
                  s.bqCurves(found(curveNames), curveNames.length),
                  key: const ValueKey('bq-curve-count'),
                  style: theme.textTheme.titleMedium,
                ),
              const SizedBox(height: 4),
              Text(
                complete
                    ? s.bqFilesIncluded
                    : curveNames.isEmpty
                    ? s.bqPhotosHint
                    : s.bqFilesHint,
                key: const ValueKey('bq-files-hint'),
                style: muted,
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('bq-pick-files'),
                  onPressed: importing ? null : _pickFiles,
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text(s.bqPickFiles),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey('bq-import'),
              onPressed: plan.isEmpty || importing ? null : _import,
              icon: importing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(importing ? s.bqImporting : s.bqImportAction),
            ),
            if (progress case (final stage, final done, final total))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                      value: done == null || total == null || total == 0
                          ? null
                          : done / total,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      switch ((stage, done, total)) {
                        (_BqStage.photos, final done?, final total?) =>
                          s.bqPreparingPhotos(done, total),
                        (_BqStage.curves, final done?, final total?) =>
                          s.bqReadingCurves(done, total),
                        (_BqStage.photos, _, _) => s.bqImporting,
                        (_BqStage.curves, _, _) => s.bqReadingAllCurves,
                        (_BqStage.saving, _, _) => s.bqSavingImport,
                      },
                      key: ValueKey('bq-progress-${stage.name}'),
                      style: muted,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    return PopScope(canPop: !importing, child: page);
  }
}

/// What an import is busy with while it shows its progress.
enum _BqStage { photos, curves, saving }
