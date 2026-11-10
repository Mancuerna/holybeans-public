import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/cupping.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/cupping/cupping_page.dart';
import 'package:holybeans/ui/sync/journal_write_feedback.dart';

class CuppingEntry extends StatelessWidget {
  const CuppingEntry({super.key, required this.repository});
  final JournalRepository repository;

  /// Cupping is an activity of its own, not a brew method: one tinted row
  /// above the methods, opening its sessions, with Start beside it.
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.secondaryContainer,
      child: ListTile(
        key: const ValueKey('cupping-sessions'),
        contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 8),
        leading: const Icon(Icons.local_cafe_outlined),
        title: Text(s.cuppingTitle),
        subtitle: Text(s.cuppingEntryHint),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => CuppingSessionsPage(repository: repository),
          ),
        ),
        trailing: FilledButton.tonal(
          key: const ValueKey('start-cupping'),
          onPressed: () => openCupping(context, repository),
          child: Text(s.cuppingStartShort),
        ),
      ),
    );
  }
}

class CuppingSessionsPage extends StatefulWidget {
  const CuppingSessionsPage({super.key, required this.repository});
  final JournalRepository repository;
  @override
  State<CuppingSessionsPage> createState() => _CuppingSessionsPageState();
}

class _CuppingSessionsPageState extends State<CuppingSessionsPage> {
  late final sessions = widget.repository.watchCuppingSessions();
  Future<void> _discard(CuppingSession session) async {
    final s = AppLocalizations.of(context)!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.cuppingDiscard),
        content: Text(s.cuppingDiscardHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.cuppingDiscard),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await widget.repository.discardCuppingDraft(session.id);
    } catch (e, stack) {
      reportError(e, stack);
      if (mounted) {
        showOperationError(context, e, s.saveFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(s.cuppingSessions)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openCupping(context, widget.repository),
        icon: const Icon(Icons.add),
        label: Text(s.cuppingStart),
      ),
      body: StreamBuilder<List<CuppingSession>>(
        stream: sessions,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text(s.dataError));
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          if (rows.isEmpty) return Center(child: Text(s.cuppingEmpty));
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              final draft = CuppingDraft.fromJson(row.draftJson);
              return Card(
                child: ListTile(
                  title: Text(row.name.isEmpty ? s.cuppingTitle : row.name),
                  subtitle: Text(
                    [
                      formatRegionalDateTime(
                        DateTime.fromMillisecondsSinceEpoch(row.createdAtMs),
                        regionalLocale,
                      ),
                      if (row.completedAtMs == null) s.cuppingDraft,
                      [
                        s.cuppingCoffeeCount(draft.cups.length),
                        if (draft.blind) s.cuppingBlindShort,
                      ].join(', '),
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                  onTap: () =>
                      openCupping(context, widget.repository, session: row),
                  trailing: row.completedAtMs != null
                      ? const Icon(Icons.chevron_right)
                      : IconButton(
                          tooltip: s.cuppingDiscard,
                          onPressed: () => _discard(row),
                          icon: const Icon(Icons.delete_outline),
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
