import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:patrol/patrol.dart';

import '../benchmark/support/audit_metrics.dart';
import '../benchmark/support/chart_audit.dart';
import '../benchmark/support/journal_audit.dart';
import '../benchmark/support/journal_fixture.dart';
import '../benchmark/support/journal_ui_audit.dart';
import '../benchmark/support/media_audit.dart';
import '../benchmark/support/startup_audit.dart';

void main() {
  patrolTest('synthetic journal performance audit', ($) async {
    expect(kProfileMode, isTrue, reason: 'run patrol test --profile');
    const section = String.fromEnvironment(
      'AUDIT_SECTION',
      defaultValue: 'all',
    );
    const fixtureName = String.fromEnvironment('AUDIT_FIXTURE');
    const uiFixtureName = String.fromEnvironment('AUDIT_UI_FIXTURE');
    const run = String.fromEnvironment('AUDIT_RUN', defaultValue: 'baseline');
    const prototypes = bool.fromEnvironment(
      'AUDIT_PROTOTYPES',
      defaultValue: true,
    );
    final sections = section.split(',').toSet();
    expect(
      sections,
      everyElement(isIn(['all', 'data', 'ui', 'media', 'startup', 'charts'])),
    );
    bool includes(String value) =>
        sections.contains('all') || sections.contains(value);
    if (fixtureName.isNotEmpty) {
      expect(
        auditFixtures.map((fixture) => fixture.name),
        contains(fixtureName),
      );
    }
    if (uiFixtureName.isNotEmpty) {
      expect(['100x2048', '5000x2048', '10000x2048'], contains(uiFixtureName));
    }
    final directory = (await getExternalStorageDirectory())!;
    final output = File(path.join(directory.path, 'performance-audit.jsonl'));
    await output.writeAsString('');
    void record(Map<String, Object?> value) {
      final line = jsonEncode({
        'environment': 'Android profile; file-backed background SQLite',
        'os': Platform.operatingSystemVersion,
        'harnessVersion': 4,
        'run': run,
        ...value,
      });
      output.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
      debugPrint('JOURNAL_AUDIT $line', wrapWidth: 100000);
    }

    final memory = await AuditMemory.connect();
    record({'operation': 'environment', 'vmServiceAvailable': memory != null});
    try {
      if (includes('data')) {
        for (final fixture in auditFixtures) {
          if (fixtureName.isNotEmpty && fixture.name != fixtureName) continue;
          await runJournalAudit(
            fixture,
            record,
            memory: memory,
            // Device builds can override the compile-time default.
            // ignore: avoid_redundant_argument_values
            prototypes: prototypes,
          );
        }
      }
      if (includes('ui')) {
        for (final count in [100, 5000, 10000]) {
          final fixture = JournalFixture(count, 2048);
          if (uiFixtureName.isNotEmpty && fixture.name != uiFixtureName) {
            continue;
          }
          await runJournalUiAudit(
            $.tester,
            fixture,
            record,
            memory: memory,
            enterText: (finder, text) => $.enterText(
              finder,
              text,
              hideKeyboard: false,
              enablePatrolLog: false,
            ),
          );
        }
      }
      if (includes('media')) {
        await runMediaAudit(record, memory: memory);
      }
      if (includes('startup')) {
        await runStartupAudit($.tester, record);
      }
      if (includes('charts')) {
        await runChartAudit($.tester, record, memory: memory);
      }
      record({'operation': 'audit_complete', 'passed': true});
      // Let the host collect the artifact before the orchestrator clears data.
      await Future<void>.delayed(const Duration(seconds: 20));
    } finally {
      await memory?.close();
    }
  }, timeout: const Timeout(Duration(minutes: 60)));
}
