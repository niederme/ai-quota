#!/usr/bin/env python3
"""Actual separate-process relaunch checks with synthetic native Keychain sessions.

This exercises the production coordinator and KeychainStore with a fresh test
namespace across seven process launches. It does not install a TestFlight update.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/codex-process-relaunch'
OUT.mkdir(parents=True, exist_ok=True)
command = ['swift', 'test', '--disable-sandbox', '--package-path', 'Packages/AIQuotaKit',
           '--scratch-path', 'output/recovery-kit', '--filter', 'crossProcessSavedSession', '--no-parallel']
env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer',
           CLANG_MODULE_CACHE_PATH=str(ROOT/'output/module-cache'),
           SWIFTPM_MODULECACHE_OVERRIDE=str(ROOT/'output/module-cache'))
with tempfile.TemporaryDirectory(prefix='synthetic-codex-relaunch-', dir=OUT) as directory:
    env['AIQUOTA_RELAUNCH_FIXTURE'] = directory
    env['AIQUOTA_TEST_STORE_ID'] = str(uuid.uuid4())
    records = []
    for i, phase in enumerate(['seed', 'restore', 'offline', 'restore', 'expired', 'wrong', 'restore', 'cleanup']):
        env['AIQUOTA_RELAUNCH_PHASE'] = phase
        run = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=180)
        (OUT/f'{i}-{phase}.log').write_text(run.stdout + run.stderr)
        records.append({'phase':phase, 'exit_code':run.returncode,
                        'result':[line for line in run.stdout.splitlines() if 'PROCESS_RELAUNCH' in line]})
        print(records[-1], flush=True)
        if run.returncode:
            raise SystemExit('Fixture phase failed; see its log')
        if '--skip-build' not in command: command.insert(2, '--skip-build')
    (OUT/'results.json').write_text(json.dumps({'processes':records, 'account_cases':14,
        'persistence':'native KeychainStore with a fresh UUID test service; synthetic session values',
        'test_namespace':env['AIQUOTA_TEST_STORE_ID'], 'fixture_credentials_removed':True,
        'live_provider_or_os_upgrade_test':False}, indent=2)+'\n')
