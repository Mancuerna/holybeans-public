import 'package:flutter/material.dart';
import 'package:holybeans/domain/meticulous/piston_analysis.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/regional_dates.dart';

String pistonServiceLabel(AppLocalizations s, String kind) => switch (kind) {
  'grease' => s.pistonGrease,
  'descale' => s.pistonDescale,
  _ => s.pistonClean,
};

Future<PistonService?> editPistonService(
  BuildContext context,
  PistonService? existing,
) => showDialog<PistonService>(
  context: context,
  builder: (_) => _ServiceForm(existing),
);

class _ServiceForm extends StatefulWidget {
  const _ServiceForm(this.existing);
  final PistonService? existing;
  @override
  State<_ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends State<_ServiceForm> {
  late DateTime date = widget.existing == null
      ? DateTime.now()
      : DateTime.fromMillisecondsSinceEpoch(widget.existing!.timeMs);
  late String kind = widget.existing?.kind ?? 'grease';
  late final notes = TextEditingController(text: widget.existing?.notes);
  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(s.pistonMaintenance),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: kind,
              isExpanded: true,
              decoration: InputDecoration(labelText: s.pistonServiceType),
              items: [
                for (final k in PistonService.kinds)
                  DropdownMenuItem(
                    value: k,
                    child: Text(pistonServiceLabel(s, k)),
                  ),
              ],
              onChanged: (v) => setState(() => kind = v!),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_outlined),
              label: Text(formatRegionalDateTime(date, regionalLocale)),
              onPressed: () async {
                final selected = await showDatePicker(
                  context: context,
                  locale: regionalLocale,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (selected == null || !context.mounted) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(date),
                );
                if (time == null || !mounted) return;
                final candidate = DateTime(
                  selected.year,
                  selected.month,
                  selected.day,
                  time.hour,
                  time.minute,
                );
                setState(
                  () => date = candidate.isAfter(DateTime.now())
                      ? DateTime.now()
                      : candidate,
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('piston-service-notes'),
              controller: notes,
              maxLength: 2000,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: s.pistonNotes),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        FilledButton(
          key: const ValueKey('piston-service-save'),
          onPressed: () => Navigator.pop(
            context,
            PistonService(
              id: widget.existing?.id ?? '',
              timeMs: date.millisecondsSinceEpoch,
              kind: kind,
              notes: notes.text,
            ),
          ),
          child: Text(s.save),
        ),
      ],
    );
  }
}
