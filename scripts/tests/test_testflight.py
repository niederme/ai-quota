import importlib.util
from pathlib import Path
import plistlib
import tempfile
import subprocess
import json
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release', Path(__file__).parents[1] / 'testflight.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class ReleaseTests(unittest.TestCase):
    def test_number_never_reuses_local_or_remote(self):
        self.assertEqual(m.next_build(11, [{'attributes': {'version': '14'}}]), 15)
        self.assertEqual(m.next_build(17, []), 18)
        with self.assertRaises(RuntimeError):
            m.next_build(11, [{'attributes': {'version': '1.2'}}])

    def test_platform_and_version_filter(self):
        api = m.ASC(None)
        def get(resource, **params):
            if resource == 'apps':
                return {'data': [{'id': 'app'}]}
            return {'data': [
                {'attributes': {'version': '900'}, 'relationships': {'preReleaseVersion': {'data': {'id': 'mac'}}}},
                {'attributes': {'version': '12'}, 'relationships': {'preReleaseVersion': {'data': {'id': 'ios'}}}},
                {'attributes': {'version': '99'}, 'relationships': {'preReleaseVersion': {'data': {'id': 'old'}}}},
            ], 'included': [
                {'type': 'preReleaseVersions', 'id': 'mac', 'attributes': {'platform': 'MAC_OS', 'version': '0.1.0'}},
                {'type': 'preReleaseVersions', 'id': 'ios', 'attributes': {'platform': 'IOS', 'version': '0.1.0'}},
                {'type': 'preReleaseVersions', 'id': 'old', 'attributes': {'platform': 'IOS', 'version': '0.0.9'}},
            ]}
        api.get = get
        self.assertEqual([b['attributes']['version'] for b in api.builds('0.1.0')], ['12'])

    def test_sync_ios_without_changing_mac_and_detect_drift(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            mobile = root / 'iOS'
            mobile.mkdir()
            (root / 'project.yml').write_text(
                'name: AIQuota\ninclude: [iOS/project.yml]\n'
                'settings:\n  base:\n    CURRENT_PROJECT_VERSION: "387"\n'
                '    MARKETING_VERSION: "1.9.27"\n'
                'targets:\n  Mac:\n    type: application\n    platform: macOS\n')
            (mobile / 'project.yml').write_text(
                'targetTemplates:\n  iOSDistribution:\n    settings:\n      base:\n'
                '        MARKETING_VERSION: "0.1.0"\n        CURRENT_PROJECT_VERSION: "11"\n'
                'targets:\n' + ''.join(
                    f'  {name}:\n    type: application\n    platform: iOS\n'
                    '    templates: [iOSDistribution]\n' for name in sorted(m.IOS_TARGETS)))
            with patch.object(m, 'ROOT', root), patch.object(m, 'MOBILE', mobile):
                m.sync_build(12)
                self.assertEqual(m.project_numbers(), ('0.1.0', 12))
                pbx = root / 'AIQuota.xcodeproj/project.pbxproj'
                objects = json.loads(subprocess.check_output(
                    ['plutil', '-convert', 'json', '-o', '-', str(pbx)], text=True))['objects']
                mac = next(o for o in objects.values() if o.get('isa') == 'PBXProject')
                for config in objects[mac['buildConfigurationList']]['buildConfigurations']:
                    settings = objects[config]['buildSettings']
                    self.assertEqual(str(settings['CURRENT_PROJECT_VERSION']), '387')
                    self.assertEqual(settings['MARKETING_VERSION'], '1.9.27')
                pbx.write_text(pbx.read_text().replace('CURRENT_PROJECT_VERSION = 12;',
                                                      'CURRENT_PROJECT_VERSION = 13;', 1))
                with self.assertRaises(RuntimeError):
                    m.project_numbers()

    def test_processing_is_not_testflight_availability(self):
        api = m.ASC(None)
        api.builds = lambda version: [{'id': 'build-id', 'attributes': {'version': '12', 'processingState': 'VALID'}}]
        with tempfile.TemporaryDirectory() as tmp:
            state = dict(version='0.1.0', build=12, phase='uploaded')
            api.get = lambda path: {'data': {'attributes': {'internalBuildState': 'READY_FOR_BETA_TESTING'}}}
            self.assertFalse(m.status(api, Path(tmp), state))
            api.get = lambda path: {'data': {'attributes': {'internalBuildState': 'IN_BETA_TESTING'}}}
            self.assertTrue(m.status(api, Path(tmp), state))
            self.assertEqual(state['phase'], 'available')

    def test_archive_rejects_widget_mismatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = Path(tmp) / 'Products/Applications/App.app'
            widget = app / 'PlugIns/Widget.appex'
            widget.mkdir(parents=True)
            for path, bundle in [(app, m.BUNDLE), (widget, m.BUNDLE + '.mobilewidget')]:
                with (path / 'Info.plist').open('wb') as f:
                    plistlib.dump(dict(CFBundleIdentifier=bundle, CFBundleVersion='12', CFBundleShortVersionString='0.1.0', DTPlatformName='iphoneos'), f)
            state = dict(archive=tmp, build=12, version='0.1.0')
            m.verify_archive(state)
            with (widget / 'Info.plist').open('wb') as f:
                plistlib.dump(dict(CFBundleVersion='11'), f)
            with self.assertRaises(RuntimeError):
                m.verify_archive(state)

if __name__ == '__main__':
    unittest.main()
