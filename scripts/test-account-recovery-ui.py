#!/usr/bin/env python3
"""Render production card/detail controls using memory models, never live auth.

Compile libraries with test-claude-account-lifecycle.py first. Identity lookup is
replaced only in copied UI sources to avoid the production registry/cache stores.
Unrelated insights and history charts are empty fixture subviews.
"""
from pathlib import Path
import os
import subprocess
ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'output/claude-lifecycle-verification'
OUT = ROOT / 'output/account-recovery-ui'
OUT.mkdir(parents=True, exist_ok=True)
source = (ROOT / 'scripts/tests/MacRefreshLayoutFixture.swift').read_text().split('@MainActor enum FixtureMeasurements')[0]
source = source.replace('var issue: String?', '''var issue: String?
    var issueError: NetworkError?
    var recoveryAction: AccountRecoveryAction { .resolve(authenticated: isAuthenticated, error: issueError, hasIssue: issue != nil) }
    var codexUsageHistory: CodexUsageHistory?
    var usageHistoryFailed = false
    var isUsageHistoryLoading = false
    func refreshUsageHistory(force: Bool = false) {}''')
source = source.replace('func refresh() async {}', 'func refresh(userInitiated: Bool = false) async {}')
source = source.replace('NSError?', 'NetworkError?').replace('import QuartzCore', 'import QuartzCore\nimport MobileAccessCore').replace(': CodexTokenHistory?', ': AIQuotaKit.CodexTokenHistory?').replace('= CodexTokenHistory(', '= AIQuotaKit.CodexTokenHistory(').replace('CodexTokenHistory.dateFormatter()', 'AIQuotaKit.CodexTokenHistory.dateFormatter()')
source = source.replace('error: nil, hasIssue: session.issue != nil', 'error: session.issueError, hasIssue: session.issue != nil')
source = source.replace('error: nil, hasIssue: (account.provider == .codex ? codexError : claudeError) != nil', 'error: account.provider == .codex ? codexError : claudeError')
(OUT / 'Models.swift').write_text(source)
views = []
for name in ['MacAccountOverviewItem.swift', 'MacAdditionalAccountDetailView.swift']:
    copied = OUT / name
    copied.write_text((ROOT / 'AIQuota/Views' / name).read_text().replace('.presentation(', '.fixturePresentation('))
    views.append(copied)
command = ['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(LIB / 'module-cache'),
           '-I', str(LIB), '-L', str(LIB), '-lAIQuotaKit', '-lMobileAccessCore', '-Xlinker', '-rpath', '-Xlinker', str(LIB)]
command += [str(ROOT / 'AIQuota/Views' / n) for n in ['AdaptiveColors.swift', 'CodexTokenHistoryView.swift', 'MacAccountDial.swift']]
command += list(map(str, views + [OUT / 'Models.swift', ROOT / 'scripts/tests/AccountRecoveryUIFixture.swift']))
command += ['-o', str(OUT / 'recovery-ui')]
env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
subprocess.run(command, cwd=ROOT, env=env, check=True)
subprocess.run([str(OUT / 'recovery-ui'), str(OUT)], cwd=ROOT, env=env, check=True, timeout=60)
