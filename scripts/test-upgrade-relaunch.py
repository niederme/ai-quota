#!/usr/bin/env python3
"""Memory-only account/coordinator relaunch simulation; no actual OS upgrade.

Compile the production libraries first with test-claude-account-lifecycle.py.
Uses only fake auth inputs and memory writers, no live account credentials.
"""
from pathlib import Path
import os
import subprocess
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/claude-lifecycle-verification'
command = ['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '6', '-module-cache-path', str(OUT / 'module-cache'),
           '-I', str(OUT), '-L', str(OUT), '-lAIQuotaKit', '-lMobileAccessCore', '-Xlinker', '-rpath', '-Xlinker', str(OUT),
           str(ROOT / 'Packages/AIQuotaKit/Tests/Standalone/UpgradeRelaunchChecks.swift'), '-o', str(OUT / 'upgrade-relaunch-checks')]
env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
subprocess.run(command, cwd=ROOT, env=env, check=True)
subprocess.run([str(OUT / 'upgrade-relaunch-checks')], cwd=ROOT, env=env, check=True, timeout=30)
