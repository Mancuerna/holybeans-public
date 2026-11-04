import copy
import json
import tempfile
import unittest
from pathlib import Path

from tool.performance import compare, records, snapshot


class PerformanceTests(unittest.TestCase):
    def setUp(self):
        self.rows = [{'environment': 'Android profile', 'os': 'test-device-build',
                      'harnessVersion': 6, 'run': 'test', 'operation': 'live_chart',
                      'initialPoints': 10000, 'elapsedMs': 5000,
                      'build': {'p95Ms': 10}}]

    def test_budget_detects_regression_but_allows_small_noise(self):
        before = snapshot(self.rows)
        after = copy.deepcopy(before)
        after['records'][0]['metrics']['build.p95Ms'] = 13
        self.assertEqual(compare(before, after), [])
        after['records'][0]['metrics']['build.p95Ms'] = 15
        self.assertEqual(len(compare(before, after)), 1)

    def test_missing_scenarios_and_metrics_fail(self):
        before = snapshot(self.rows)
        after = copy.deepcopy(before)
        after['records'][0]['metrics'].clear()
        self.assertEqual(len(compare(before, after)), 2)
        after['records'].clear()
        self.assertEqual(len(compare(before, after)), 1)

    def test_different_context_duplicates_and_invalid_numbers_fail(self):
        before = snapshot(self.rows)
        after = copy.deepcopy(before)
        after['os'] = 'different phone'
        with self.assertRaises(ValueError):
            compare(before, after)
        with self.assertRaises(ValueError):
            snapshot(self.rows * 2)
        self.rows[0]['elapsedMs'] = float('nan')
        with self.assertRaises(ValueError):
            snapshot(self.rows)

    def test_incomplete_or_mixed_audit_cannot_be_a_baseline(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'audit.jsonl'
            path.write_text(json.dumps(self.rows[0]) + '\n')
            with self.assertRaises(ValueError):
                records(path)
            complete = {**self.rows[0], 'operation': 'audit_complete', 'passed': True}
            path.write_text('\n'.join(map(json.dumps, [*self.rows, complete])))
            self.assertEqual(len(records(path)), 2)
            complete['run'] = 'other'
            path.write_text('\n'.join(map(json.dumps, [*self.rows, complete])))
            with self.assertRaises(ValueError):
                records(path)
