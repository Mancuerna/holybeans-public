import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/extraction_profile_repository.dart';
import 'package:holybeans/domain/extraction_profile.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/profiles/profile_editor_page.dart';
import 'package:holybeans/ui/profiles/profile_numbers.dart';
import 'package:holybeans/ui/profiles/profile_plot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

class ProfileLibraryPage extends StatefulWidget {
  const ProfileLibraryPage({super.key, required this.repository, this.onUse});
  final ExtractionProfileRepository repository;
  final Future<void> Function(ExtractionProfile)? onUse;
  @override
  State<ProfileLibraryPage> createState() => _ProfileLibraryPageState();
}

class _ProfileLibraryPageState extends State<ProfileLibraryPage> {
  late final rows = widget.repository.watch();
  String search = '';
  bool busy = false;
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).profileError)),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(ExtractionProfile profile) async {
    await Navigator.of(context).push<ExtractionProfile>(
      MaterialPageRoute(
        builder: (_) =>
            ProfileEditorPage(profile: profile, onSave: widget.repository.save),
      ),
    );
  }

  Future<void> import() async {
    final file = await openFile();
    if (file == null) return;
    if (await file.length() > 512 * 1024) {
      throw const FormatException('Profile too large');
    }
    final profile = ExtractionProfile.decode(await file.readAsString())
        .copyWith(id: const Uuid().v4());
    if (mounted) await edit(profile);
  }

  Future<void> share(ExtractionProfile profile) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            utf8.encode(profile.encode()),
            mimeType: 'application/json',
          ),
        ],
        fileNameOverrides: ['holybeans-profile.json'],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> delete(ExtractionProfile profile) async {
    final s = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.profileDelete),
        content: Text(s.profileDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (yes == true) await widget.repository.delete(profile.id);
  }

  @override
  Widget build(BuildContext context) {
    final n = profileNumber(context);
    final s = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.profilesTitle),
        actions: [
          IconButton(
            onPressed: busy ? null : () => run(import),
            tooltip: s.profileImport,
            icon: const Icon(Icons.file_open_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy
            ? null
            : () => edit(
                ExtractionProfile.example(const Uuid().v4(), s.profileExample),
              ),
        icon: const Icon(Icons.add),
        label: Text(s.profileNew),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                labelText: s.profileSearch,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => search = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ExtractionProfileRow>>(
              stream: rows,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text(s.profileError));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final profiles =
                    <({ExtractionProfile profile, bool favorite})>[];
                try {
                  for (final row in snapshot.data!) {
                    final profile = ExtractionProfile.decode(row.dataJson);
                    if ('${profile.name} ${profile.notes}'
                        .toLowerCase()
                        .contains(search)) {
                      profiles.add((
                        profile: profile,
                        favorite: row.isFavorite,
                      ));
                    }
                  }
                } on FormatException {
                  return Center(child: Text(s.profileError));
                }
                if (profiles.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(s.profileEmpty),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: profiles.length,
                  itemBuilder: (context, i) {
                    final p = profiles[i].profile;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    p.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ),
                                IconButton(
                                  tooltip: s.profileFavorite,
                                  onPressed: busy
                                      ? null
                                      : () => run(
                                          () => widget.repository.favorite(
                                            p.id,
                                            !profiles[i].favorite,
                                          ),
                                        ),
                                  icon: Icon(
                                    profiles[i].favorite
                                        ? Icons.star
                                        : Icons.star_border,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  enabled: !busy,
                                  onSelected: (v) => run(() async {
                                    switch (v) {
                                      case 'edit':
                                        await edit(p);
                                      case 'copy':
                                        await edit(
                                          p.copyWith(
                                            id: const Uuid().v4(),
                                            name:
                                                '${p.name.length > 65 ? p.name.substring(0, 65) : p.name} (${s.profileDuplicate})',
                                          ),
                                        );
                                      case 'share':
                                        await share(p);
                                      case 'delete':
                                        await delete(p);
                                    }
                                  }),
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text(s.profileEditor),
                                    ),
                                    PopupMenuItem(
                                      value: 'copy',
                                      child: Text(s.profileDuplicate),
                                    ),
                                    PopupMenuItem(
                                      value: 'share',
                                      child: Text(s.profileShare),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(s.profileDelete),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Text(
                              '${p.flow.isNotEmpty && p.pressure.isNotEmpty
                                  ? s.profileBoth
                                  : p.flow.isNotEmpty
                                  ? s.curveFlow
                                  : s.curvePressure} · ${n.format(p.durationMs / 1000)} s · ${n.format(p.doseGrams)} g · ${n.format(p.temperatureC)} °C',
                            ),
                            ProfilePlot(profile: p, height: 130),
                            if (p.predictedGrams ?? p.targetGrams
                                case final grams?)
                              Text(
                                '${s.profilePredicted}: ${n.format(grams)} g',
                              ),
                            if (p.notes.isNotEmpty)
                              Text(
                                p.notes,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (widget.onUse != null)
                              FilledButton.tonalIcon(
                                onPressed: busy
                                    ? null
                                    : () => run(() async {
                                        await widget.repository.used(p.id);
                                        if (mounted) await widget.onUse!(p);
                                      }),
                                icon: const Icon(Icons.play_arrow),
                                label: Text(s.profileUse),
                              )
                            else
                              TextButton(
                                onPressed: busy ? null : () => edit(p),
                                child: Text(s.profileEditor),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
