#!/usr/bin/env python3
"""Compare advanced AIs against a frozen Git revision at equal node budgets."""

import argparse
import json
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', default='ede5e79')
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--game', choices=['all', 'gomoku', 'draughts'], default='all')
    parser.add_argument('--pairs', type=int, default=3)
    parser.add_argument('--nodes', type=int, default=1500)
    parser.add_argument('--plies', type=int, default=120)
    parser.add_argument('--product-budgets', action='store_true')
    parser.add_argument('--output', default='/tmp/easyplay-advanced-benchmark.json')
    args = parser.parse_args()
    if min(args.pairs, args.nodes, args.plies) < 1:
        parser.error('pairs, nodes and plies must be positive')
    revision = subprocess.check_output(
        ['git', 'rev-parse', '--verify', args.baseline + '^{commit}'], cwd=ROOT,
        text=True,
    ).strip()

    def source(relative):
        return subprocess.check_output(
            ['git', 'show', f'{revision}:{relative}'], cwd=ROOT, text=True,
        )

    output = ROOT / '.dart_tool/advanced_ai_baseline'
    output.mkdir(parents=True, exist_ok=True)
    metadata = {'revision': revision}
    for game in ('gomoku', 'draughts'):
        relative = f'lib/{game}/{game}_ai.dart'
        original = source(relative)
        directory = (ROOT / relative).parent

        def absolute(match):
            if ':' in match[2]:
                return match[0]
            return match[1] + " '" + (directory / match[2]).resolve().as_uri() + "'"

        original = re.sub(r"(import|export) '([^']+)'", absolute, original)
        (output / f'{game}_ai.dart').write_text(original)
        profile = re.search(
            r"advanced\('高级',\s*(\d+),\s*(\d+),\s*(\d+)\)",
            source(f'lib/{game}/{game}_ai_level.dart'),
        )
        if profile is None:
            raise ValueError(f'Cannot read {game} baseline search profile')
        metadata[game] = dict(zip(('depth', 'nodes', 'milliseconds'), map(int, profile.groups())))
    (output / 'gomoku_ai_position.dart').write_text(source('lib/gomoku/gomoku_ai_position.dart'))
    (output / 'metadata.json').write_text(json.dumps(metadata))
    template = (ROOT / 'tools/benchmark_advanced_ai.dart.template').read_text()

    def template_import(match):
        target = (ROOT / 'tools' / match[1]).resolve()
        return "import '" + target.as_uri() + "'"

    entrypoint = output / 'main.dart'
    entrypoint.write_text(re.sub(r"import '([^']+)'", lambda match:
        match[0] if ':' in match[1] else template_import(match), template))
    executable = output / 'benchmark'
    subprocess.run(
        [args.dart, 'compile', 'exe', str(entrypoint), '-o', str(executable)],
        cwd=ROOT, check=True,
    )
    command = [
        str(executable), '--game', args.game, '--pairs', str(args.pairs),
        '--nodes', str(args.nodes), '--plies', str(args.plies), '--output', args.output,
    ]
    if args.product_budgets:
        command.append('--product-budgets')
    subprocess.run(command, cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
