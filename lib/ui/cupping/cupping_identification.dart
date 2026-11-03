import 'package:flutter/material.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/cupping/cupping_model.dart';
import 'package:holybeans/ui/cupping/cupping_setup.dart';

class CuppingIdentification extends StatelessWidget {
  const CuppingIdentification({super.key, required this.model});
  final CuppingModel model;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return ListView(
      key: const ValueKey('cupping-identification'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          s.cuppingIdentify,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(s.cuppingIdentifyHint),
        const SizedBox(height: 12),
        for (var i = 0; i < model.draft.cups.length; i++)
          CuppingCupSetup(model: model, index: i, identifying: true),
        const SizedBox(height: 24),
      ],
    );
  }
}
