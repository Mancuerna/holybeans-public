import 'package:flutter/material.dart';
import 'package:holybeans/data/services/loffee_key_store.dart';
import 'package:holybeans/l10n/app_localizations.dart';

Future<String?> configureLoffeeKey(
  BuildContext context,
  LoffeeKeyStore store,
) => showDialog<String>(
  context: context,
  builder: (_) => _LoffeeKeyDialog(store: store),
);

class _LoffeeKeyDialog extends StatefulWidget {
  const _LoffeeKeyDialog({required this.store});
  final LoffeeKeyStore store;
  @override
  State<_LoffeeKeyDialog> createState() => _LoffeeKeyDialogState();
}

class _LoffeeKeyDialogState extends State<_LoffeeKeyDialog> {
  final _key = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = true;
  bool _stored = false;
  bool _show = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.store.read();
      if (!mounted) return;
      setState(() {
        _stored = value != null;
        _busy = false;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _failed = true;
          _busy = false;
        });
      }
    }
  }

  Future<void> _save({bool delete = false}) async {
    if (!delete && !(_form.currentState?.validate() ?? false)) return;
    final value = _key.text.trim();
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      if (delete) {
        await widget.store.delete();
      } else {
        await widget.store.save(value);
      }
      if (mounted) Navigator.pop(context, delete ? '' : value);
    } on Object {
      // Credential errors are deliberately not logged with platform details.
      if (mounted) {
        setState(() {
          _failed = true;
          _busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _key.clear();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        key: const ValueKey('loffee-key-dialog'),
        title: Text(s.loffeeKeyTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.loffeeKeyHint),
              if (_stored) ...[
                const SizedBox(height: 12),
                Text(s.loffeeKeyStored),
              ],
              const SizedBox(height: 16),
              Form(
                key: _form,
                child: TextFormField(
                  key: const ValueKey('loffee-key-input'),
                  controller: _key,
                  enabled: !_busy,
                  obscureText: !_show,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    labelText: s.loffeeKeyLabel,
                    suffixIcon: IconButton(
                      tooltip: _show ? s.loffeeHideKey : s.loffeeShowKey,
                      onPressed: () => setState(() => _show = !_show),
                      icon: Icon(
                        _show
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    return text.isEmpty ||
                            text.length > 512 ||
                            RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(text)
                        ? s.loffeeKeyInvalid
                        : null;
                  },
                ),
              ),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(s.loffeeKeyFailed),
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
        actions: [
          if (_stored)
            TextButton(
              key: const ValueKey('loffee-key-delete'),
              onPressed: _busy ? null : () => _save(delete: true),
              child: Text(s.loffeeForgetKey),
            ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(s.cancel),
          ),
          FilledButton(
            key: const ValueKey('loffee-key-save'),
            onPressed: _busy ? null : _save,
            child: Text(s.save),
          ),
        ],
      ),
    );
  }
}
