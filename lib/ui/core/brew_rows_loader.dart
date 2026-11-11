import 'package:flutter/material.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/l10n/app_localizations.dart';

/// Loads an analytics projection only for the screen that needs it.
class BrewRowsLoader extends StatefulWidget {
  const BrewRowsLoader({super.key, required this.load, required this.builder});
  final Future<List<Brew>> Function() load;
  final Widget Function(List<Brew>) builder;
  @override
  State<BrewRowsLoader> createState() => _BrewRowsLoaderState();
}

class _BrewRowsLoaderState extends State<BrewRowsLoader> {
  late Future<List<Brew>> rows = widget.load();
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Brew>>(
    future: rows,
    builder: (context, snapshot) {
      if (snapshot.hasData) return widget.builder(snapshot.data!);
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: snapshot.hasError
              ? TextButton(
                  onPressed: () => setState(() => rows = widget.load()),
                  child: Text(AppLocalizations.of(context).dataError),
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}
