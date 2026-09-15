#!/usr/bin/env python3
"""Archive/upload AIQuota iOS from this checkout; retain resumable release records."""
import argparse
import base64
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]
MOBILE = ROOT / 'iOS'
IOS_TARGETS = {'AIQuota-iOS', 'AIQuotaWidget-iOS', 'AIQuota-iOSTests'}
BUNDLE = 'com.niederme.AIQuota'
TEAM = '289GY9L343'
XCODE = '/Applications/Xcode.app/Contents/Developer'
RUNS = Path.home() / 'Library/Logs/AIQuota/TestFlight'


def credentials():
    values = {}
    path = Path(os.environ.get('ASC_ENV_FILE', str(Path.home() / '.appstoreconnect/sendmoi.env')))
    if path.exists():
        for line in path.read_text().splitlines():
            words = shlex.split(line, comments=True)
            if words and words[0] == 'export':
                words = words[1:]
            if len(words) == 1 and '=' in words[0]:
                key, value = words[0].split('=', 1)
                values[key] = value
    values.update(os.environ)
    key_id, issuer = values.get('ASC_KEY_ID'), values.get('ASC_ISSUER_ID')
    if not key_id or not issuer:
        raise RuntimeError('Set ASC_KEY_ID and ASC_ISSUER_ID, or ASC_ENV_FILE.')
    key_path = Path(values.get('ASC_KEY_PATH', str(Path.home() / f'.appstoreconnect/private_keys/AuthKey_{key_id}.p8')))
    if not key_path.is_file():
        raise RuntimeError('App Store Connect private key file is missing.')
    return key_id, issuer, key_path


class ASC:
    def __init__(self, creds):
        self.creds = creds

    def get(self, resource, **params):
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec, utils
        kid, issuer, path = self.creds
        enc = lambda b: base64.urlsafe_b64encode(b).rstrip(b'=')
        now = int(time.time())
        token = enc(json.dumps({'alg': 'ES256', 'kid': kid, 'typ': 'JWT'}).encode()) + b'.' + enc(json.dumps({'iss': issuer, 'iat': now, 'exp': now + 600, 'aud': 'appstoreconnect-v1'}).encode())
        key = serialization.load_pem_private_key(path.read_bytes(), password=None)
        r, s = utils.decode_dss_signature(key.sign(token, ec.ECDSA(hashes.SHA256())))
        token += b'.' + enc(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))
        url = resource if resource.startswith('https://') else 'https://api.appstoreconnect.apple.com/v1/' + resource
        if not url.startswith('https://api.appstoreconnect.apple.com/'):
            raise RuntimeError('Unexpected App Store Connect pagination host.')
        if params:
            url += '?' + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + token.decode()})
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            raise RuntimeError(f'App Store Connect HTTP {error.code}; check credentials and permissions.') from None

    def builds(self, version):
        apps = self.get('apps', **{'filter[bundleId]': BUNDLE})['data']
        if len(apps) != 1:
            raise RuntimeError('Could not uniquely identify AIQuota in App Store Connect.')
        page = self.get('builds', **{'filter[app]': apps[0]['id'], 'include': 'preReleaseVersion', 'limit': 200})
        result = []
        while True:
            versions = {v['id']: v['attributes'] for v in page.get('included', []) if v['type'] == 'preReleaseVersions'}
            for build in page['data']:
                relation = build['relationships']['preReleaseVersion']['data']
                attrs = versions.get(relation['id'])
                if attrs is None:
                    attrs = self.get('preReleaseVersions/' + relation['id'])['data']['attributes']
                if attrs['platform'] == 'IOS' and attrs['version'] == version:
                    result.append(build)
            nxt = page.get('links', {}).get('next')
            if not nxt:
                return result
            page = self.get(nxt)


def ios_build_settings():
    project = ROOT / 'AIQuota.xcodeproj/project.pbxproj'
    objects = json.loads(subprocess.check_output(
        ['/usr/bin/plutil', '-convert', 'json', '-o', '-', str(project)], text=True))['objects']
    targets = {obj['name']: obj for obj in objects.values()
               if obj.get('isa') == 'PBXNativeTarget' and obj.get('name') in IOS_TARGETS}
    if set(targets) != IOS_TARGETS:
        raise RuntimeError('Expected iOS targets are missing from the shared project.')
    return [objects[config]['buildSettings']
            for target in targets.values()
            for config in objects[target['buildConfigurationList']]['buildConfigurations']]


def project_numbers():
    yaml = (MOBILE / 'project.yml').read_text()
    version = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', yaml).group(1)
    builds = re.findall(r'CURRENT_PROJECT_VERSION:\s*"(\d+)"', yaml)
    settings = ios_build_settings()
    builds += [str(setting.get('CURRENT_PROJECT_VERSION', '')) for setting in settings]
    if not builds or len(set(builds)) != 1 or not builds[0].isdigit():
        raise RuntimeError('Project and YAML build numbers are out of sync.')
    if any(setting.get('MARKETING_VERSION') != version for setting in settings):
        raise RuntimeError('Project and YAML marketing versions are out of sync.')
    return version, int(builds[0])


def next_build(local, builds):
    numbers = [b['attributes']['version'] for b in builds]
    if any(not n.isdigit() for n in numbers):
        raise RuntimeError('Non-integer remote build number requires manual review.')
    return max([local] + [int(n) for n in numbers]) + 1


def sync_build(number):
    path = MOBILE / 'project.yml'
    content, count = re.subn(r'CURRENT_PROJECT_VERSION:\s*"\d+"',
                             f'CURRENT_PROJECT_VERSION: "{number}"', path.read_text())
    if count != 1:
        raise RuntimeError('Expected one iOS build number in the iOS distribution template.')
    path.write_text(content)
    subprocess.run(['xcodegen', 'generate', '--spec', str(ROOT / 'project.yml')],
                   cwd=ROOT, check=True)
    if project_numbers()[1] != number:
        raise RuntimeError('Regenerated iOS build number does not match the release.')


def save(run, state):
    tmp = run / 'state.tmp'
    tmp.write_text(json.dumps(state, indent=2) + '\n')
    tmp.replace(run / 'state.json')


def execute(run, stage, args, creds):
    kid, issuer, path = creds
    env = dict(os.environ, DEVELOPER_DIR=XCODE, PATH='/usr/bin:/bin:/usr/sbin:/sbin')
    log = run / f'{stage}.log'
    print(f'{stage.capitalize()} running. Log: {log}', flush=True)
    with log.open('w') as output:
        proc = subprocess.run(['/usr/bin/xcodebuild'] + args + ['-allowProvisioningUpdates', '-authenticationKeyPath', str(path), '-authenticationKeyID', kid, '-authenticationKeyIssuerID', issuer], cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT)
    if proc.returncode:
        raise RuntimeError(f'{stage.capitalize()} failed. Inspect {log}')


def verify_archive(state):
    archive = Path(state['archive'])
    apps = list((archive / 'Products/Applications').glob('*.app'))
    if len(apps) != 1:
        raise RuntimeError('Archive must contain exactly one iOS app.')
    app = apps[0]
    extensions = list((app / 'PlugIns').glob('*.appex'))
    if len(extensions) != 1:
        raise RuntimeError('Expected one widget extension.')
    for item, bundle in [(app, BUNDLE), (extensions[0], BUNDLE + '.mobilewidget')]:
        with (item / 'Info.plist').open('rb') as source:
            info = plistlib.load(source)
        expected = {'CFBundleIdentifier': bundle, 'CFBundleShortVersionString': state['version'], 'CFBundleVersion': str(state['build']), 'DTPlatformName': 'iphoneos'}
        if any(info.get(k) != v for k, v in expected.items()):
            raise RuntimeError('Archive identity, platform, or build does not match this release.')


def status(api, run, state):
    matches = [b for b in api.builds(state['version']) if b['attributes']['version'] == str(state['build'])]
    if not matches:
        print(f"Build {state['build']}: not yet visible in App Store Connect.", flush=True)
        return False
    build = matches[0]
    processing = build['attributes']['processingState']
    beta = api.get('builds/' + build['id'] + '/buildBetaDetail')['data']['attributes'].get('internalBuildState')
    state.update(asc_build_id=build['id'], processing=processing, internal_beta=beta)
    if processing == 'VALID' and beta == 'IN_BETA_TESTING':
        state['phase'] = 'available'
    save(run, state)
    print(f"Build {state['build']}: {processing}; internal TestFlight: {beta}", flush=True)
    if processing in ('FAILED', 'INVALID'):
        raise RuntimeError('Apple processing failed. Review this build in App Store Connect.')
    return state['phase'] == 'available'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['preflight', 'release', 'archive', 'upload', 'status'])
    parser.add_argument('--run', type=Path, help='Existing release directory (required for upload/status).')
    parser.add_argument('--wait', type=int, default=600, help='Maximum processing wait seconds; 0 checks once.')
    args = parser.parse_args()
    if args.wait < 0:
        parser.error('--wait must be nonnegative')
    creds = credentials()
    api = ASC(creds)
    if not Path(XCODE).is_dir():
        raise RuntimeError('Expected Xcode installation is missing.')
    common = Path(subprocess.check_output(['git', 'rev-parse', '--git-common-dir'], cwd=ROOT, text=True).strip())
    if not common.is_absolute():
        common = ROOT / common
    with (common / 'aiquota-testflight.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Another release command is running.') from None
        if args.command in ('preflight', 'release', 'archive'):
            if args.run:
                parser.error('--run applies only to upload/status')
            version, local = project_numbers()
            builds = api.builds(version)
            number = next_build(local, builds)
            print(f'Worktree: {ROOT}\nVersion: {version}; project build: {local}; next build: {number}', flush=True)
            if args.command == 'preflight':
                return
            stamp = dt.datetime.now().strftime('%Y-%m-%d-%H%M%S') + '-' + uuid.uuid4().hex[:6]
            run = RUNS / stamp
            run.mkdir(parents=True, mode=0o700)
            archive = Path.home() / 'Library/Developer/Xcode/Archives' / dt.date.today().isoformat() / f'AIQuota-iOS-{stamp}.xcarchive'
            state = dict(worktree=str(ROOT), version=version, build=number, archive=str(archive), phase='archiving')
            save(run, state)
            print(f'Release record: {run}', flush=True)
            sync_build(number)
            workspace = ROOT / 'AIQuota.xcworkspace'
            container = ['-workspace', str(workspace)] if workspace.exists() else ['-project', str(ROOT / 'AIQuota.xcodeproj')]
            execute(run, 'archive', container + ['-scheme', 'AIQuota-iOS', '-configuration', 'Release', '-destination', 'generic/platform=iOS', '-archivePath', str(archive), 'archive'], creds)
            verify_archive(state)
            state['phase'] = 'archived'
            save(run, state)
            if args.command == 'archive':
                return
        else:
            if not args.run:
                parser.error('--run is required for upload/status')
            run = args.run.expanduser().resolve()
            state = json.loads((run / 'state.json').read_text())
            if state['worktree'] != str(ROOT):
                raise RuntimeError('Run this command from the release record’s original worktree.')
        if args.command in ('release', 'upload'):
            if state['phase'] != 'archived':
                raise RuntimeError('Upload already attempted or archive incomplete. Use status; do not submit a duplicate.')
            if any(b['attributes']['version'] == str(state['build']) for b in api.builds(state['version'])):
                raise RuntimeError('This build already exists in App Store Connect. Use status.')
            verify_archive(state)
            options = run / 'ExportOptions.plist'
            with options.open('wb') as output:
                plistlib.dump(dict(destination='upload', method='app-store-connect', signingStyle='automatic', teamID=TEAM, manageAppVersionAndBuildNumber=False), output)
            state['phase'] = 'uploading'
            save(run, state)
            execute(run, 'upload', ['-exportArchive', '-archivePath', state['archive'], '-exportPath', str(run / 'export'), '-exportOptionsPlist', str(options)], creds)
            state['phase'] = 'uploaded'
            save(run, state)
        deadline = time.monotonic() + args.wait
        while not status(api, run, state):
            if time.monotonic() >= deadline:
                print(f'Processing/distribution still pending. Check again: python3 scripts/testflight.py status --run {shlex.quote(str(run))} --wait 0')
                return
            time.sleep(min(30, max(0, deadline - time.monotonic())))


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError, ImportError, subprocess.CalledProcessError) as error:
        print(f'Error: {error}', file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print('Stopped. Release record preserved; use status before any further upload.', file=sys.stderr)
        sys.exit(130)
