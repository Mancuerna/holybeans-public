"""Small device baselines and explicit regression budgets for profile audits."""
import argparse
import json
import math
from pathlib import Path

# Relative allowances absorb ordinary device noise; absolute allowances avoid
# failing on changes of microseconds. These are regression limits, not SLAs.
LIMITS = {
    'elapsedMs': (1.25, 5),
    'medianMs': (1.25, 2),
    'build.p95Ms': (1.20, 2),
    'raster.p95Ms': (1.20, 2),
    'processCpuTicks': (1.25, 10),
    'rssBytes': (1.20, 16 * 1024 * 1024),
    'mainIsolateAfterGc.heapUsage': (1.20, 4 * 1024 * 1024),
}
CONTEXT = ('environment', 'os', 'harnessVersion')
IDENTITY = ('operation', 'fixture', 'initialPoints')


def value(row, path):
    result = row
    for key in path.split('.'):
        if not isinstance(result, dict) or key not in result:
            return None
        result = result[key]
    return result


def identity(row):
    return tuple(row.get(key) for key in IDENTITY)


def records(path):
    rows = [json.loads(line) for line in Path(path).read_text().splitlines() if line.strip()]
    if not any(row.get('operation') == 'audit_complete' and row.get('passed') is True for row in rows):
        raise ValueError('Incomplete or failed audit')
    runs = {row.get('run') for row in rows}
    if len(runs) != 1:
        raise ValueError('Mixed audit runs')
    contexts = {tuple(row.get(key) for key in CONTEXT) for row in rows}
    if len(contexts) != 1 or None in next(iter(contexts)):
        raise ValueError('Missing or inconsistent device/build context')
    return rows


def snapshot(rows):
    context = {key: rows[0][key] for key in CONTEXT}
    selected = []
    seen = set()
    for row in rows:
        metrics = {key: value(row, key) for key in LIMITS if value(row, key) is not None}
        if not metrics:
            continue
        key = identity(row)
        if key in seen:
            raise ValueError(f'Duplicate measurement: {key}')
        if any(not isinstance(v, (int, float)) or not math.isfinite(v) or v < 0 for v in metrics.values()):
            raise ValueError(f'Invalid measurement: {key}')
        seen.add(key)
        selected.append({**{key: row[key] for key in IDENTITY if key in row}, 'metrics': metrics})
    if not selected:
        raise ValueError('No performance measurements')
    return {**context, 'records': selected}


def compare(baseline, current):
    if any(baseline.get(key) != current.get(key) for key in CONTEXT):
        raise ValueError('Compare the same device OS, build mode and harness version')
    actual = {identity(row): row for row in current['records']}
    failures = []
    for previous in baseline['records']:
        key = identity(previous)
        row = actual.get(key)
        if row is None:
            failures.append(f'Missing scenario: {key}')
            continue
        for metric, before in previous['metrics'].items():
            after = row['metrics'].get(metric)
            factor, slack = LIMITS[metric]
            maximum = before * factor + slack
            if after is None or after > maximum:
                failures.append(f'{key} {metric}: {after}; limit {maximum:.3f} (baseline {before})')
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['snapshot', 'compare'])
    parser.add_argument('audit', type=Path)
    parser.add_argument('baseline', type=Path)
    args = parser.parse_args()
    current = snapshot(records(args.audit))
    if args.action == 'snapshot':
        args.baseline.write_text(json.dumps(current, indent=2) + '\n')
    else:
        failures = compare(json.loads(args.baseline.read_text()), current)
        for failure in failures:
            print(failure)
        print(f'{len(failures)} regression(s) across {len(current["records"])} measurements')
        raise SystemExit(bool(failures))


if __name__ == '__main__':
    main()
