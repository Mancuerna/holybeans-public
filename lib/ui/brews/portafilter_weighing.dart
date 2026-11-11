import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/brews/brew_form_model.dart';
import 'package:holybeans/ui/core/form_widgets.dart';
import 'package:holybeans/ui/core/regional_dates.dart';
import 'package:holybeans/ui/equipment/recipients_page.dart';
import 'package:holybeans/ui/scale/scale_compact.dart';
import 'package:intl/intl.dart';

class PortafilterWeighButton extends StatelessWidget {
  const PortafilterWeighButton({super.key, required this.model});

  final BrewFormModel model;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('weigh-portafilter'),
        icon: const Icon(Icons.scale_outlined),
        label: Text(s.weighPortafilter),
        onPressed:
            model.timer.running || (model.scaleSession?.resetting ?? false)
            ? null
            : () async {
                final session = model.scaleSession;
                session?.beginDoseWeighing();
                try {
                  final result =
                      await showDialog<({Recipient recipient, double dose})>(
                        context: context,
                        builder: (_) => _PortafilterWeighing(model: model),
                      );
                  if (result != null && context.mounted) {
                    model.selectRecipient(result.recipient);
                    model.draft.fillWeight(model.draft.dose, result.dose);
                  }
                } finally {
                  session?.endDoseWeighing();
                }
              },
      ),
    );
  }
}

class _PortafilterWeighing extends StatefulWidget {
  const _PortafilterWeighing({required this.model});
  final BrewFormModel model;

  @override
  State<_PortafilterWeighing> createState() => _PortafilterWeighingState();
}

class _PortafilterWeighingState extends State<_PortafilterWeighing> {
  final total = TextEditingController();
  late Recipient? recipient = widget.model.recipient?.isPortafilter == true
      ? widget.model.recipient
      : null;

  double? get dose {
    final gross = parseNumber(total.text);
    final tare = recipient?.emptyGrams;
    if (gross == null || !gross.isFinite || tare == null || gross <= tare) {
      return null;
    }
    // Use the same precision as the dose field and scale readout.
    final net = ((gross - tare) * 10).round() / 10;
    return net > 0 ? net : null;
  }

  @override
  void initState() {
    super.initState();
    total.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    total.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final number = NumberFormat('0.#', regionalLocale.toString());
    final net = dose;
    final gross = parseNumber(total.text);
    return AlertDialog(
      title: Text(s.weighPortafilter),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            RecipientPicker(
              repository: widget.model.repository,
              value: recipient?.id,
              snapshot: recipient,
              isPortafilter: true,
              onChanged: (value) => setState(() => recipient = value),
            ),
            Text(s.portafilterWeighHint),
            TextField(
              key: const ValueKey('portafilter-total'),
              controller: total,
              inputFormatters: [decimalInputFormatter],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: s.portafilterTotal,
                errorText: gross != null && recipient != null && net == null
                    ? s.recipientTooHeavy
                    : null,
                suffixIcon: widget.model.scaleSession != null
                    ? ScaleFillButton(
                        key: const ValueKey('scale-to-portafilter'),
                        scale: widget.model.scaleSession!.scale,
                        onUse: (grams) =>
                            total.text = fieldNumber(grams, decimals: 1),
                      )
                    : null,
              ),
            ),
            if (net != null)
              Text(
                '${number.format(gross)} g − ${number.format(recipient!.emptyGrams)} g = ${number.format(net)} g',
                key: const ValueKey('portafilter-net-dose'),
                style: Theme.of(context).textTheme.titleMedium,
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
          key: const ValueKey('use-portafilter-dose'),
          onPressed: net == null
              ? null
              : () =>
                    Navigator.pop(context, (recipient: recipient!, dose: net)),
          child: Text(s.useAsDose),
        ),
      ],
    );
  }
}
