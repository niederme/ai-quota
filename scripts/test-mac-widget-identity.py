#!/usr/bin/env python3
"""Verify real Mac widget naming/error views with synthetic, read-only fixtures.

Compiles the production widget sources against the current native package build.
Never writes account defaults, credentials or histories, or calls provider APIs.
"""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/mac-widget-identity'
OUT.mkdir(parents=True, exist_ok=True)
env = dict(os.environ)
env.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
env['CLANG_MODULE_CACHE_PATH'] = str(OUT / 'cache')
env['SWIFTPM_MODULECACHE_OVERRIDE'] = str(OUT / 'cache')
package = ['swift', 'build', '--disable-sandbox', '--build-system', 'native',
           '--cache-path', str(OUT / 'spm-cache'), '--config-path', str(OUT / 'spm-config'),
           '--security-path', str(OUT / 'spm-security'), '--package-path',
           str(ROOT / 'Packages/AIQuotaKit')]
subprocess.run(package, cwd=ROOT, env=env, check=True)
binary = Path(subprocess.check_output(package + ['--show-bin-path'], cwd=ROOT, env=env, text=True).strip())
command = ['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(OUT / 'cache'),
           '-I', str(binary / 'Modules')]
for module in ['AIQuotaKit', 'MobileAccessCore']:
    objects = sorted((binary / f'{module}.build').glob('*.swift.o'))
    assert objects, f'No native build objects for {module}'
    command += list(map(str, objects))
command += [str(ROOT / path) for path in [
    'AIQuotaWidget/WidgetIntent.swift',
    'AIQuotaWidget/Provider/QuotaTimelineProvider.swift',
    'AIQuotaWidget/Views/WidgetGaugeView.swift',
    'AIQuotaWidget/Views/WidgetSmallView.swift',
    'AIQuotaWidget/Views/WidgetMediumView.swift',
    'scripts/tests/MacWidgetIdentityFixture.swift']]
executable = OUT / 'MacWidgetIdentityFixture'
subprocess.run(command + ['-o', str(executable)], cwd=ROOT, env=env, check=True)
subprocess.run([str(executable), str(OUT)], cwd=ROOT, env=env, check=True, timeout=120)
