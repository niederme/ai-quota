#!/usr/bin/env python3
"""Exercise production Mac cards with synthetic accounts and an offscreen host.

No live app, credentials, account persistence, or provider requests. Outputs
geometry/accessibility evidence under output/mac-refresh-layout. Use
--source-ref eedcef4 to reproduce the former conditional warning-row regression.
Requires Xcode selected and SwiftPM's native package build (object files).
"""
import argparse
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source-ref', help='Read only the card source from this Git revision')
parser.add_argument('--skip-build', action='store_true', help='Reuse the current package build')
args = parser.parse_args()
OUT = ROOT / 'output/mac-refresh-layout'
OUT.mkdir(parents=True, exist_ok=True)
env = dict(os.environ)
env.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
package = ['swift', 'build', '--build-system', 'native', '--package-path',
           str(ROOT / 'Packages/AIQuotaKit'), '--scratch-path', str(OUT / 'package')]
if not args.skip_build:
    subprocess.run(package, cwd=ROOT, env=env, check=True)
binary = Path(subprocess.check_output(package + ['--show-bin-path'], cwd=ROOT, env=env, text=True).strip())
source_path = 'AIQuota/Views/MacAccountOverviewItem.swift'
source = (subprocess.check_output(['git', 'show', f'{args.source_ref}:{source_path}'], cwd=ROOT, text=True)
          if args.source_ref else (ROOT / source_path).read_text())
# Observe the real heatmap position without replacing its implementation.
needle = '                        .padding(.top, 8)'
assert source.count(needle) == 1, 'Update the heatmap geometry observation point'
source = source.replace(needle, needle + '''
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("fixture")) }
                        action: { FixtureMeasurements.graphs[account.id] = $0 }
''')
mode = 'baseline' if args.source_ref else 'current'
card = OUT / f'MacAccountCard-{mode}.swift'
card.write_text(source)
executable = OUT / f'MacRefreshLayout-{mode}'
command = ['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(OUT / 'cache'),
           '-I', str(binary / 'Modules')]
for module in ['AIQuotaKit', 'MobileAccessCore']:
    objects = sorted((binary / f'{module}.build').glob('*.swift.o'))
    assert objects, f'No native build objects for {module}; rerun without --skip-build'
    command += list(map(str, objects))
command += [str(ROOT / 'AIQuota/Views' / name) for name in
            ['AdaptiveColors.swift', 'CodexTokenHistoryView.swift', 'MacAccountDial.swift']]
command += [str(card), str(ROOT / 'scripts/tests/MacRefreshLayoutFixture.swift'), '-o', str(executable)]
subprocess.run(command, cwd=ROOT, env=env, check=True)
subprocess.run([str(executable), str(OUT / mode)], cwd=ROOT, env=env, check=True, timeout=180)
