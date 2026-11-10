import 'dart:io';

import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/services/pre_migration_copies.dart';
import 'package:holybeans/domain/pre_migration.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/app_theme.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:share_plus/share_plus.dart';

class StartupRecoveryApp extends StatefulWidget {
  const StartupRecoveryApp({
    super.key,
    required this.error,
    this.locale,
    this.openCopies = PreMigrationCopies.open,
    this.shareFiles = _shareFiles,
  });

  final Object error;
  final Locale? locale;
  final Future<PreMigrationCopies> Function() openCopies;
  final Future<void> Function(List<File>) shareFiles;

  static Future<void> _shareFiles(List<File> files) async {
    await SharePlus.instance.share(
      ShareParams(files: [for (final file in files) XFile(file.path)]),
    );
  }

  @override
  State<StartupRecoveryApp> createState() => _StartupRecoveryAppState();
}

class _StartupRecoveryAppState extends State<StartupRecoveryApp> {
  late PreMigrationCopies _store;
  late final _copies = _load();
  bool _busy = false;
  bool _shareFailed = false;

  Future<List<PreMigrationCopy>> _load() async {
    try {
      _store = await widget.openCopies();
      return await _store.list();
    } catch (error, stack) {
      reportError(error, stack);
      rethrow;
    }
  }

  Future<void> _share(PreMigrationCopy copy) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _shareFailed = false;
    });
    try {
      await widget.shareFiles(await _store.recoveryFiles(copy));
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) setState(() => _shareFailed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: widget.locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    home: Builder(builder: _page),
  );

  Widget _page(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(s.appTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              s.startupFailedTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(s.startupFailedHint),
            ExpansionTile(
              title: Text(s.startupErrorDetails),
              children: [SelectableText(widget.error.toString())],
            ),
            const SizedBox(height: 24),
            Text(
              s.preMigrationTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(s.startupCopiesHint),
            FutureBuilder<List<PreMigrationCopy>>(
              future: _copies,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text(s.startupCopiesUnavailable);
                final copies = snapshot.data;
                if (copies == null) return const LinearProgressIndicator();
                if (copies.isEmpty) return Text(s.startupCopiesEmpty);
                return Column(
                  children: [
                    for (final copy in copies)
                      ListTile(
                        title: Text(
                          formatRegionalDateTime(
                            copy.savedAt.toLocal(),
                            regionalLocale,
                          ),
                        ),
                        trailing: const Icon(Icons.share_outlined),
                        subtitle: Text(s.share),
                        onTap: _busy ? null : () => _share(copy),
                      ),
                  ],
                );
              },
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_shareFailed) Text(s.shareFailed),
          ],
        ),
      ),
    );
  }
}
