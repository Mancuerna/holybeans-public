import 'package:flutter/material.dart';
import 'package:holybeans/core/error_report.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class PistonCredits extends StatelessWidget {
  const PistonCredits({super.key});

  Future<void> _open(BuildContext context, String project) async {
    try {
      final opened = await launchUrl(
        Uri.https('github.com', '/cjborchert/$project'),
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (error, stack) {
      reportError(error, stack);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).pistonProjectUnavailable),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.pistonCredits, style: Theme.of(context).textTheme.bodySmall),
        Wrap(
          spacing: 8,
          children: [
            for (final project in ['ha-meticulous-cards', 'ha-meticulous'])
              TextButton.icon(
                key: ValueKey('piston-credit-$project'),
                onPressed: () => _open(context, project),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(project),
              ),
          ],
        ),
      ],
    );
  }
}
