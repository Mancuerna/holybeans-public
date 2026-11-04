import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/repositories/coffee_freshness.dart';
import 'package:holybeans/data/repositories/journal_data.dart';
import 'package:holybeans/domain/coffee_freshness.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/beans/freshness_widgets.dart';

typedef FreshnessRequest = ({
  Coffee coffee,
  List<CoffeeLot> lots,
  List<CoffeeLot> allLots,
  List<Coffee> coffees,
  List<Brew> brews,
  List<CoffeeComponent> components,
  List<BrewMethod> methods,
  int? frozenAge,
});
CoffeeFreshness? _prepare(FreshnessRequest request) => coffeeFreshness(
  coffee: request.coffee,
  lots: request.lots,
  coffees: request.coffees,
  brews: request.brews,
  allLots: request.allLots,
  components: request.components,
  methods: request.methods,
  frozenOnlyAge: request.frozenAge,
);

/// Rated history is requested only for this detail, without notes or pours.
class LiveFreshnessSection extends StatefulWidget {
  const LiveFreshnessSection({
    super.key,
    required this.data,
    required this.coffee,
    required this.lots,
    required this.allLots,
    required this.methods,
    required this.frozenAge,
  });
  final JournalData data;
  final Coffee coffee;
  final List<CoffeeLot> lots;
  final List<CoffeeLot> allLots;
  final List<BrewMethod> methods;
  final int? frozenAge;
  @override
  State<LiveFreshnessSection> createState() => _LiveFreshnessSectionState();
}

class _LiveFreshnessSectionState extends State<LiveFreshnessSection> {
  late final stream = widget.data.reads?.watchAnalytics(ratedOnly: true);
  @override
  Widget build(BuildContext context) => StreamBuilder<List<Brew>>(
    stream: stream,
    initialData: stream == null ? widget.data.brews : null,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Text(AppLocalizations.of(context)!.dataError);
      }
      if (!snapshot.hasData) return const LinearProgressIndicator();
      return _CalculatedFreshness(
        request: (
          coffee: widget.coffee,
          lots: widget.lots,
          allLots: widget.allLots,
          coffees: widget.data.coffees,
          brews: snapshot.data!,
          components: widget.data.components,
          methods: widget.methods,
          frozenAge: widget.frozenAge,
        ),
      );
    },
  );
}

class _CalculatedFreshness extends StatefulWidget {
  const _CalculatedFreshness({required this.request});
  final FreshnessRequest request;
  @override
  State<_CalculatedFreshness> createState() => _CalculatedFreshnessState();
}

class _CalculatedFreshnessState extends State<_CalculatedFreshness> {
  Future<CoffeeFreshness?>? future;
  CoffeeFreshness? value;
  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(_CalculatedFreshness oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.request != oldWidget.request) _update();
  }

  void _update() {
    if (widget.request.brews.length <= 200) {
      value = _prepare(widget.request);
      future = null;
    } else {
      value = null;
      future = compute(
        _prepare,
        widget.request,
        debugLabel: 'coffee-freshness',
      );
    }
  }

  Widget _section(CoffeeFreshness? freshness) => freshness == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 20),
          child: FreshnessSection(freshness: freshness),
        );
  @override
  Widget build(BuildContext context) => future == null
      ? _section(value)
      : FutureBuilder<CoffeeFreshness?>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(AppLocalizations.of(context)!.dataError);
            }
            return snapshot.connectionState == ConnectionState.done
                ? _section(snapshot.data)
                : const LinearProgressIndicator();
          },
        );
}
