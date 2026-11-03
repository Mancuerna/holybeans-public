import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/journal_repository.dart';
import 'package:holybeans/domain/pressure_guide.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/brews/pressure_assistant/pressure_guide_page.dart';
import 'package:holybeans/ui/core/error_report.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:intl/intl.dart';

class PressureAssistantButton extends StatelessWidget {
  const PressureAssistantButton({super.key, required this.model});
  final BrewFormModel model;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const ValueKey('pressure-assistant'),
    onPressed: model.timer.running
        ? null
        : () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => PressureReferencePage(model: model),
            ),
          ),
    icon: const Icon(Icons.show_chart),
    label: Text(AppLocalizations.of(context)!.pressureAssistant),
  );
}

class PressureReferencePage extends StatefulWidget {
  const PressureReferencePage({super.key, required this.model});
  final BrewFormModel model;

  @override
  State<PressureReferencePage> createState() => _PressureReferencePageState();
}

class _PressureReferencePageState extends State<PressureReferencePage> {
  late Future<List<({Brew brew, PressureGuide guide})>> _references = _load();
  String _search = '';

  Future<List<({Brew brew, PressureGuide guide})>> _load() async {
    try {
      final result = await widget.model.repository.pressureReferences();
      int priority(Brew brew) => brew.id == widget.model.seed?.id
          ? 0
          : brew.coffeeId == widget.model.coffeeId
          ? (brew.isFavorite ? 1 : 2)
          : 3;
      result.sort((a, b) {
        final order = priority(a.brew).compareTo(priority(b.brew));
        return order != 0
            ? order
            : b.brew.brewedAtMs.compareTo(a.brew.brewedAtMs);
      });
      return result;
    } catch (error, stack) {
      reportError(error, stack);
      rethrow;
    }
  }

  String _name(Brew brew) =>
      widget.model.coffees
          .where((coffee) => coffee.id == brew.coffeeId)
          .firstOrNull
          ?.name ??
      brew.methodName;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    return Scaffold(
      appBar: AppBar(title: Text(s.pressureGuideChoose)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  labelText: s.search,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) =>
                    setState(() => _search = value.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: FutureBuilder(
                future: _references,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s.pressureGuideLoadError),
                          TextButton(
                            onPressed: () =>
                                setState(() => _references = _load()),
                            child: Text(s.retry),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final references = snapshot.data!
                      .where(
                        (item) => '${_name(item.brew)} ${item.brew.methodName}'
                            .toLowerCase()
                            .contains(_search),
                      )
                      .toList();
                  if (references.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(s.pressureGuideEmpty),
                    );
                  }
                  return ListView.builder(
                    itemCount: references.length,
                    itemBuilder: (context, index) {
                      final item = references[index];
                      final date = formatRegionalDateTime(
                        DateTime.fromMillisecondsSinceEpoch(
                          item.brew.brewedAtMs,
                        ),
                        regionalLocale,
                      );
                      final title = '${_name(item.brew)} · $date';
                      return ListTile(
                        key: ValueKey('pressure-reference-${item.brew.id}'),
                        leading: Icon(
                          item.brew.isFavorite
                              ? Icons.favorite
                              : Icons.show_chart,
                        ),
                        title: Text(_name(item.brew)),
                        subtitle: Text(
                          '$date · ${item.brew.methodName}\n'
                          '${NumberFormat('0.#', locale).format(item.guide.endMs / 1000)} s',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => PressureGuidePage(
                                guide: item.guide,
                                title: title,
                                timer: widget.model.timer,
                                session: widget.model.pressureSession,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
