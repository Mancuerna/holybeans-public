import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/database/app_database.dart';
import 'package:holybeans/data/preferences/brew_parameter_settings.dart';
import 'package:holybeans/domain/brew_parameters.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/settings/brew_parameters_page.dart';

void main() {
  testWidgets('rebuilds keep subscriptions; replacing settings releases them', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final first = _Settings(db);
    final second = _Settings(db);
    addTearDown(() async {
      await first.close();
      await second.close();
      await db.close();
    });

    Widget app(_Settings settings, {bool dark = false}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      home: BrewParametersPage(settings: settings),
    );

    await tester.pumpWidget(app(first));
    first.hidden.add({});
    first.shared.add({...defaultSharedParameters});
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect((first.hiddenListens, first.sharedListens), (1, 1));

    await tester.pumpWidget(app(first, dark: true));
    await tester.pumpAndSettle();
    first.hidden.add({BrewParameter.tools});
    await tester.pumpAndSettle();
    expect((first.hiddenListens, first.sharedListens), (1, 1));
    expect((first.hiddenCancels, first.sharedCancels), (0, 0));

    await tester.pumpWidget(app(second));
    second.hidden.add({});
    second.shared.add({...defaultSharedParameters});
    await tester.pumpAndSettle();
    expect((first.hiddenCancels, first.sharedCancels), (1, 1));
    expect((second.hiddenListens, second.sharedListens), (1, 1));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    expect((second.hiddenCancels, second.sharedCancels), (1, 1));
  });
}

class _Settings extends BrewParameterSettings {
  _Settings(super.database);

  int hiddenListens = 0;
  int sharedListens = 0;
  int hiddenCancels = 0;
  int sharedCancels = 0;
  final hidden = StreamController<Set<BrewParameter>>.broadcast();
  final shared = StreamController<Set<BrewParameter>>.broadcast();

  @override
  Stream<Set<BrewParameter>> watchHidden() => Stream.multi((controller) {
    hiddenListens++;
    final subscription = hidden.stream.listen(controller.add);
    controller.onCancel = () async {
      hiddenCancels++;
      await subscription.cancel();
    };
  });

  @override
  Stream<Set<BrewParameter>> watchShared() => Stream.multi((controller) {
    sharedListens++;
    final subscription = shared.stream.listen(controller.add);
    controller.onCancel = () async {
      sharedCancels++;
      await subscription.cancel();
    };
  });

  Future<void> close() async {
    await hidden.close();
    await shared.close();
  }
}
