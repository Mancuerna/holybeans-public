import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holybeans/data/preferences/current_release.g.dart';
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
    'fresh install is silent; updates show once, skipped versions work',
    () async {
      settings = ReleaseNotesSettings(file, version: '1.0.0');
      expect(await settings.pending(existingInstallation: false), isFalse);
      expect(await settings.pending(existingInstallation: true), isFalse);
      final update = ReleaseNotesSettings(file, version: '1.2.0');
      expect(await update.pending(existingInstallation: true), isTrue);
      await update.markSeen();
      expect(await update.pending(existingInstallation: true), isFalse);
      expect(await settings.pending(existingInstallation: true), isFalse);
      expect(
        await ReleaseNotesSettings(
          file,
          version: '1.2.0',
        ).pending(existingInstallation: true),
        isFalse,
      );
    },
  );

  test(
    'version ordering is numeric across patches, minors and majors',
    () async {
      for (final versions in [
        ('1.4.9', '1.4.10'),
        ('1.9.9', '1.10.0'),
        ('1.99.99', '2.0.0'),
      ]) {
        final older = ReleaseNotesSettings(file, version: versions.$1);
        final newer = ReleaseNotesSettings(file, version: versions.$2);
        await older.markSeen();
        expect(await newer.pending(existingInstallation: true), isTrue);
        await newer.markSeen();
        expect(await older.pending(existingInstallation: true), isFalse);
      }
    },
  );

  test('legacy and malformed acknowledgements migrate once', () async {
    for (final saved in [
      {'seen': 14},
      {'seenVersion': 'broken'},
      {'seenVersion': 14},
    ]) {
      await file.writeAsString(jsonEncode(saved));
      expect(await settings.pending(existingInstallation: true), isTrue);
      await settings.markSeen();
      expect(await settings.pending(existingInstallation: true), isFalse);
      expect(jsonDecode(await file.readAsString()), {
        'seenVersion': currentReleaseVersion,
      });
    }
  });

  test('generated notes match the current version and publication text', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version: (\d+\.\d+\.\d+)\+',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;
    expect(currentReleaseVersion, version);
    final source = File('docs/releases/$version.md').readAsStringSync();
    for (final locale in {'es': 'es-ES', 'en': 'en-GB'}.entries) {
      final expected = RegExp(
        '<${locale.value}>\\s*(.*?)\\s*</${locale.value}>',
        dotAll: true,
      ).firstMatch(source)!.group(1)!.trim();
      expect(currentReleaseNotes[locale.key], expected);
    }
    expect(currentReleaseNotes.keys, unorderedEquals(['es', 'en']));
  });

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
        final improvements = currentReleaseNotes[language]!
            .split('\n')
            .where((line) => line.startsWith('- '))
            .map((line) => line.substring(2))
            .toList();
        expect(improvements, isNotEmpty);
        for (final improvement in improvements) {
          expect(find.text(improvement), findsOneWidget);
        }
        for (var i = 1; i < improvements.length; i++) {
          final previous = tester.getRect(find.text(improvements[i - 1]));
          final current = tester.getRect(find.text(improvements[i]));
          expect(current.top - previous.bottom, greaterThanOrEqualTo(12));
          expect(current.left, previous.left);
        }
        await tester.ensureVisible(find.text(improvements.last));
        await tester.pumpAndSettle();
        expect(find.text(improvements.last).hitTestable(), findsOneWidget);
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
