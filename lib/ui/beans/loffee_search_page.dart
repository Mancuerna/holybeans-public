import 'package:flutter/material.dart';
import 'package:holybeans/data/services/loffee_api.dart';
import 'package:holybeans/domain/loffee_bean.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/loffee_key_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

class LoffeeSearchPage extends StatefulWidget {
  const LoffeeSearchPage({super.key, required this.services});
  final LoffeeServices services;
  @override
  State<LoffeeSearchPage> createState() => _LoffeeSearchPageState();
}

class _LoffeeSearchPageState extends State<LoffeeSearchPage> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  String? _key;
  bool _loadingKey = true;
  bool _keyFailed = false;
  bool _busy = false;
  LoffeeFailure? _failure;
  LoffeePage? _result;
  int _page = 1;
  String _searched = '';

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  Future<void> _loadKey() async {
    try {
      final key = await widget.services.keys.read();
      if (mounted) {
        setState(() {
          _key = key;
          _loadingKey = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _keyFailed = true;
          _loadingKey = false;
        });
      }
    }
  }

  Future<void> _configure() async {
    final key = await configureLoffeeKey(context, widget.services.keys);
    if (!mounted || key == null) return;
    setState(() {
      _key = key.isEmpty ? null : key;
      _keyFailed = false;
      _result = null;
      _failure = null;
      _page = 1;
    });
  }

  Future<void> _search({int page = 1, String? query}) async {
    final key = _key;
    final text = (query ?? _query.text).trim();
    if (_busy || key == null || text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _failure = null;
      if (page == 1) _result = null;
    });
    try {
      final result = await widget.services.api.search(
        key: key,
        query: text,
        page: page,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _page = page;
        _searched = text;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } on LoffeeException catch (error) {
      if (mounted) setState(() => _failure = error.failure);
    } on Object {
      if (mounted) setState(() => _failure = LoffeeFailure.unavailable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    _key = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.loffeeSearchTitle),
        actions: [
          IconButton(
            key: const ValueKey('loffee-configure'),
            tooltip: s.loffeeKeyTitle,
            onPressed: _busy || _loadingKey ? null : _configure,
            icon: const Icon(Icons.key_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          key: const ValueKey('loffee-results'),
          controller: _scroll,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(s.loffeeSearchHint),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('loffee-query'),
                      controller: _query,
                      enabled: !_busy && _key != null,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        labelText: s.loffeeQueryHint,
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListenableBuilder(
                      listenable: _query,
                      builder: (_, _) => FilledButton(
                        key: const ValueKey('loffee-search'),
                        onPressed:
                            _busy || _key == null || _query.text.trim().isEmpty
                            ? null
                            : _search,
                        child: Text(s.search),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_busy || _loadingKey)
              const SliverToBoxAdapter(child: LinearProgressIndicator()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList.list(children: _results(s)),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _results(AppLocalizations s) => [
    if (_keyFailed) Text(s.loffeeKeyFailed),
    if (!_loadingKey && _key == null) ...[
      Text(s.loffeeNeedsKey),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const ValueKey('loffee-add-key'),
        onPressed: _configure,
        icon: const Icon(Icons.key_outlined),
        label: Text(s.loffeeKeyTitle),
      ),
    ],
    if (_failure case final failure?) ...[
      Text(switch (failure) {
        LoffeeFailure.authentication => s.loffeeAuthenticationFailed,
        LoffeeFailure.rateLimit => s.loffeeRateLimited,
        LoffeeFailure.network => s.loffeeNetworkFailed,
        LoffeeFailure.response => s.loffeeResponseFailed,
        LoffeeFailure.unavailable => s.loffeeUnavailable,
      }, key: const ValueKey('loffee-error')),
      const SizedBox(height: 12),
    ],
    if (_result case final result?) ...[
      if (result.beans.isEmpty) Text(s.loffeeNoResults),
      for (final bean in result.beans) _BeanResult(bean: bean, enabled: !_busy),
      if (_page > 1 || result.hasMore)
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          children: [
            if (_page > 1)
              OutlinedButton(
                key: const ValueKey('loffee-previous'),
                onPressed: _busy
                    ? null
                    : () => _search(page: _page - 1, query: _searched),
                child: Text(s.loffeePrevious),
              ),
            if (result.hasMore)
              OutlinedButton(
                key: const ValueKey('loffee-next'),
                onPressed: _busy
                    ? null
                    : () => _search(page: _page + 1, query: _searched),
                child: Text(s.loffeeNext),
              ),
          ],
        ),
    ],
    const SizedBox(height: 16),
    Text(s.loffeeCatalogHint),
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton(
        onPressed: () async {
          try {
            await launchUrl(
              Uri.https('www.loffeelabs.com', '/developers'),
              mode: LaunchMode.externalApplication,
            );
          } on Object {
            /* Search remains usable without an external browser. */
          }
        },
        child: Text(s.loffeeAttribution),
      ),
    ),
  ];
}

class _BeanResult extends StatelessWidget {
  const _BeanResult({required this.bean, required this.enabled});
  final LoffeeBean bean;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final origin = bean.card.origins.firstOrNull;
    final details = [
      bean.card.roaster,
      if (origin != null)
        [
          origin.country,
          origin.region,
          origin.variety,
          origin.process,
        ].whereType<String>().join(', '),
      [
        bean.roastType,
        bean.roastDegree,
        bean.elevation,
      ].whereType<String>().join(', '),
      bean.card.flavorNotes.join(', '),
    ].where((text) => text.isNotEmpty).join('\n');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              bean.card.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(details),
            if (bean.description case final description?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  description,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: ValueKey('loffee-select-${bean.id}'),
                onPressed: enabled ? () => Navigator.pop(context, bean) : null,
                icon: const Icon(Icons.add_rounded),
                label: Text(s.loffeeReview),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
