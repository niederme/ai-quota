#!/usr/bin/env python3
"""Bounded dummy-only checks, without SwiftPM manifests, app launch or host stores.

Builds the local production libraries directly (no dependency fetch or signing).
The runner injects memory persistence and an intercept-all URLProtocol. The primary
app method is copied verbatim into memory-only adapters; --primary-source-ref can
reproduce that method's prior behavior without executing the old app.

This is NOT an OS-enforced runtime sandbox. Never use it for unreviewed code or
real identities. It does not test live WebKit, Keychain, entitlements or UI.
"""
import argparse
import json
from pathlib import Path
import resource
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--primary-source-ref', '--app-source-ref', help='Read primary refresh and additional sign-in bodies from a Git ref; run their 8 checks alone')
parser.add_argument('--skip-build', action='store_true', help='Reuse libraries already compiled from this working tree')
args = parser.parse_args()
OUT = ROOT / 'output' / 'claude-lifecycle-verification'
OUT.mkdir(parents=True, exist_ok=True)
CACHE = OUT / 'module-cache'
CACHE.mkdir(exist_ok=True)
DEVELOPER = Path('/Applications/Xcode.app/Contents/Developer')
SWIFTC = DEVELOPER / 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
SDK = DEVELOPER / 'Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
ENV = {'PATH': '/usr/bin:/bin', 'TMPDIR': str(OUT), 'CLANG_MODULE_CACHE_PATH': str(CACHE)}

def limits():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    resource.setrlimit(resource.RLIMIT_CPU, (180, 180))
    resource.setrlimit(resource.RLIMIT_FSIZE, (256 * 1024 * 1024, 256 * 1024 * 1024))

def run(label, command, timeout=180):
    result = subprocess.run(list(map(str, command)), cwd=ROOT, env=ENV,
                            capture_output=True, text=True, timeout=timeout, preexec_fn=limits)
    (OUT / f'{label}.log').write_text(result.stdout + result.stderr)
    (OUT / f'{label}-command.json').write_text(json.dumps(list(map(str, command)), indent=2) + '\n')
    print(f'{label}: exit {result.returncode}', flush=True)
    if result.returncode:
        print((result.stdout + result.stderr)[-6000:])
    return result

base = [SWIFTC, '-parse-as-library', '-enable-testing', '-swift-version', '6',
        '-target', 'arm64-apple-macosx15.0', '-sdk', SDK, '-module-cache-path', CACHE,
        '-I', OUT, '-L', OUT]
for name in ([] if args.skip_build else ['MobileAccessCore', 'AIQuotaKit']):
    sources = sorted((ROOT / f'Packages/{name}/Sources/{name}').rglob('*.swift'))
    command = base + ['-emit-library', '-emit-module', '-module-name', name,
                      '-emit-module-path', OUT / f'{name}.swiftmodule', '-o', OUT / f'lib{name}.dylib']
    if name == 'AIQuotaKit': command += ['-lMobileAccessCore']
    if run(f'{name}-library', command + sources).returncode: sys.exit(1)

path = 'AIQuota/ViewModels/QuotaViewModel.swift'
source = (ROOT / path).read_text() if not args.primary_source_ref else subprocess.check_output(
    ['git', 'show', f'{args.primary_source_ref}:{path}'], cwd=ROOT, text=True)
start = source.index('    func refreshClaude() async {')
end = source.index('\n    }', start) + len('\n    }')
body = source[start:end]
fixtures = ROOT / 'Packages/AIQuotaKit/Tests/Standalone'
adapters = (fixtures / 'PrimaryClaudeRefreshAdapters.swift').read_text()
assert adapters.count('// SOURCE_REFRESH_CLAUDE') == 1
adapters = adapters.replace('    // SOURCE_REFRESH_CLAUDE', body)
(OUT / 'PrimaryClaudeAdapters.swift').write_text(adapters)
additional = (fixtures / 'AdditionalClaudeReconnectAdapters.swift').read_text()
start = source.index('    func signIn() async {', source.index('final class AdditionalAccountSession'))
end = source.index('\n    }', start) + len('\n    }')
assert additional.count('// SOURCE_ADDITIONAL_SIGNIN') == 1
additional = additional.replace('    // SOURCE_ADDITIONAL_SIGNIN', source[start:end])
(OUT / 'AdditionalClaudeAdapters.swift').write_text(additional)
checks = (fixtures / 'ClaudeLifecycleDummyChecks.swift').read_text()
if args.primary_source_ref:
    # Common definitions contain only memory types and injected constructors.
    checks = checks[:checks.index('@main enum ClaudeLifecycleDummyChecks')]
    checks += '''\n@main enum PrimaryBaselineChecks {
    static func main() async {
        var failed = false
        do { try await runPrimaryRefreshChecks() } catch { print(error); failed = true }
        do { try await runAdditionalReconnectChecks() } catch { print(error); failed = true }
        if failed { exit(1) }
    }
}\n'''
(OUT / 'DummyChecks.swift').write_text(checks)
executable = OUT / ('primary-baseline-checks' if args.primary_source_ref else 'dummy-checks')
command = base + ['-lAIQuotaKit', '-lMobileAccessCore', '-Xlinker', '-rpath', '-Xlinker', OUT,
                  OUT / 'DummyChecks.swift', OUT / 'PrimaryClaudeAdapters.swift', OUT / 'AdditionalClaudeAdapters.swift', '-o', executable]
if run('dummy-compile', command).returncode: sys.exit(1)
result = run('primary-baseline-run' if args.primary_source_ref else 'dummy-run', [executable], timeout=30)
print(result.stdout, end='')
manifest = {
    'source_ref': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
    'primary_body_ref': args.primary_source_ref or 'working tree',
    'os_enforced_sandbox': False,
    'environment_allowlist': ENV,
    'runtime_bound_seconds': 30,
    'persistence': 'in-memory injected only; no live Keychain/defaults/WebKit',
    'network': 'intercept-all in-process URLProtocol; no live provider requests',
    'primary_coverage': 'verbatim refreshClaude method body, memory app/UI adapters',
    'additional_card_coverage': 'verbatim signIn method body, real injected coordinator and memory registry/refresh adapters',
    'package_coverage': 'actual compiled ClaudeAuthCoordinator and WidgetRefreshService',
    'exit_code': result.returncode,
}
(OUT / ('primary-baseline-evidence.json' if args.primary_source_ref else 'dummy-evidence.json')).write_text(json.dumps(manifest, indent=2) + '\n')
sys.exit(result.returncode)
