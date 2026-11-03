import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/release_notes_settings.dart';
import 'package:holybeans/l10n/app_localizations.dart';
import 'package:holybeans/ui/core/release_notes.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory directory;
  late File file;
  late ReleaseNotesSettings settings;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('release-notes-');
    file = File(path.join(directory.path, 'notes.json'));
    settings = ReleaseNotesSettings(file);
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'fresh install is silent; updates show once, skipped revisions work',
    () async {
      expect(await settings.pending(existingInstallation: false), isFalse);
      expect(await settings.pending(existingInstallation: true), isFalse);
      final update = ReleaseNotesSettings(
        file,
        revision: ReleaseNotesSettings.currentRevision + 1,
      );
      expect(await update.pending(existingInstallation: true), isTrue);
      await update.markSeen();
      expect(await update.pending(existingInstallation: true), isFalse);
      expect(await settings.pending(existingInstallation: true), isFalse);
    },
  );

  test(
    'first introduction and damaged preference on existing app show notes',
    () async {
      expect(await settings.pending(existingInstallation: true), isTrue);
      await file.writeAsString('{broken');
      expect(await settings.pending(existingInstallation: true), isTrue);
      await settings.markSeen();
      expect(await settings.pending(existingInstallation: true), isFalse);
    },
  );

  for (final language in ['es', 'en']) {
    testWidgets(
      'localized notes fit large text and acknowledge once: $language',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final memory = _MemorySettings(file);
        final observer = ReleaseNotesObserver(memory);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            navigatorObservers: [observer],
            builder: (_, child) => MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: const Scaffold(body: Text('Diary')),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('release-notes')), findsOneWidget);
        final s = lookupAppLocalizations(Locale(language));
        expect(find.text(s.releaseNotesTransparentSharing), findsOneWidget);
        expect(find.text(s.releaseNotesD11Printers), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(language == 'es' ? 'Entendido' : 'Got it'));
        await tester.pumpAndSettle();
        expect(memory.acknowledgements, 1);
        expect(find.byKey(const ValueKey('release-notes')), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('launch route takes priority, notes wait until returning home', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final memory = _MemorySettings(file);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: [ReleaseNotesObserver(memory)],
        home: _LaunchRoute(navigator),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rate from reminder'), findsOneWidget);
    expect(find.byKey(const ValueKey('release-notes')), findsNothing);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('release-notes')), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(memory.acknowledgements, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _LaunchRoute extends StatefulWidget {
  const _LaunchRoute(this.navigator);
  final GlobalKey<NavigatorState> navigator;
  @override
  State<_LaunchRoute> createState() => _LaunchRouteState();
}

class _LaunchRouteState extends State<_LaunchRoute> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Rate from reminder')),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('Diary'));
}

class _MemorySettings extends ReleaseNotesSettings {
  _MemorySettings(super.file);
  int acknowledgements = 0;
  @override
  Future<void> markSeen() async {
    acknowledgements++;
  }
}
