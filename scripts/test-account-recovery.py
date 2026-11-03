#!/usr/bin/env python3
"""Run production refresh/routing bodies with memory fakes; no live app or auth.

Compile libraries first with scripts/test-claude-account-lifecycle.py. This uses
its direct Swift compiler output, without package resolution or host stores.
"""
from pathlib import Path
import os
import subprocess
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/claude-lifecycle-verification'
source = (ROOT / 'AIQuota/ViewModels/QuotaViewModel.swift').read_text()
fixture = (ROOT / 'scripts/tests/AccountRecoveryFixture.swift').read_text()
for marker, signature, offset in [
    ('CODEX', '    func refreshCodex() async {', 0),
    ('CLAUDE', '    func refreshClaude() async {', 0),
    ('ADDITIONAL', '    func refresh(userInitiated: Bool = false) async {', source.index('final class AdditionalAccountSession')),
    ('ROUTE', '    func reconnect(_ account: ConnectedAccount) async {', 0),
    ('SIGNOUT_ACCOUNT', '    func signOutAccount(id: String) async {', 0),
]:
    start = source.index(signature, offset)
    end = source.index('\n    }', start) + len('\n    }')
    fixture = fixture.replace('    // SOURCE_' + marker, source[start:end])
path = OUT / 'AccountRecoveryFixture.swift'
path.write_text(fixture)
command = ['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '6', '-module-cache-path', str(OUT / 'module-cache'),
           '-I', str(OUT), '-L', str(OUT), '-lAIQuotaKit', '-lMobileAccessCore', '-Xlinker', '-rpath', '-Xlinker', str(OUT),
           str(path), '-o', str(OUT / 'account-recovery-checks')]
env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
subprocess.run(command, cwd=ROOT, env=env, check=True)
subprocess.run([str(OUT / 'account-recovery-checks')], cwd=ROOT, env=env, check=True, timeout=30)
