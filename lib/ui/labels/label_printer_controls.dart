import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:holybeans/data/services/label_printer.dart';
import 'package:holybeans/data/services/paired_device.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/settings/device_pairing_section.dart';

class LabelPrinterControls extends StatelessWidget {
  const LabelPrinterControls({super.key, required this.printer});
  final LabelPrinter printer;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    String statusLabel(DeviceStatus status) => switch (status) {
      DeviceStatus.idle => s.labelDisconnected,
      DeviceStatus.searching => s.labelSearching,
      DeviceStatus.connecting => s.labelConnecting,
      DeviceStatus.connected => s.labelConnected,
      DeviceStatus.failed => s.labelConnectionFailed,
      DeviceStatus.bluetoothOff => s.labelBluetoothOff,
      DeviceStatus.denied => s.labelBluetoothDenied,
    };
    return Column(
      children: [
        DevicePairingSection(
          device: printer,
          keyPrefix: 'label-printer',
          texts: (
            hint: s.labelPrinterHint,
            find: s.labelFindPrinter(printer.model.label),
            searching: s.labelSearching,
            noneFound: s.labelNoneFound(printer.model.label),
            failed: s.labelConnectionFailed,
            connect: s.labelConnect,
            disconnect: s.labelDisconnect,
            forget: s.labelForget,
          ),
          statusLabel: statusLabel,
          foundIcon: Icons.print_outlined,
          readout: ListenableBuilder(
            listenable: printer,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(printer.name ?? 'Niimbot ${printer.model.label}'),
                Text(statusLabel(printer.status)),
                if (!printer.connected &&
                    printer.status != DeviceStatus.connecting)
                  TextButton(
                    key: const ValueKey('label-printer-reconnect'),
                    onPressed: printer.connect,
                    child: Text(s.labelConnect),
                  ),
              ],
            ),
          ),
        ),
        ListenableBuilder(
          listenable: printer,
          builder: (context, _) => printer.diagnosticReport.isEmpty
              ? const SizedBox.shrink()
              : TextButton.icon(
                  key: const ValueKey('label-printer-copy-diagnostics'),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: printer.diagnosticReport),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.labelDiagnosticsCopied)),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(s.labelCopyDiagnostics),
                ),
        ),
      ],
    );
  }
}

class LabelTemplateNameDialog extends StatefulWidget {
  const LabelTemplateNameDialog({super.key, required this.initial});
  final String initial;
  @override
  State<LabelTemplateNameDialog> createState() =>
      _LabelTemplateNameDialogState();
}

class _LabelTemplateNameDialogState extends State<LabelTemplateNameDialog> {
  late final name = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(s.labelTemplateSave),
      content: TextField(
        key: const ValueKey('label-template-name'),
        controller: name,
        autofocus: true,
        maxLength: 80,
        decoration: InputDecoration(labelText: s.labelTemplateName),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, name.text.trim()),
          child: Text(s.save),
        ),
      ],
    );
  }
}
