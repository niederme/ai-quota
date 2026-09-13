import importlib.util
from pathlib import Path
import plistlib
import tempfile
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

    def test_sync_all_overrides_and_detect_drift(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'AIQuota-iOS.xcodeproj').mkdir()
            (root / 'project.yml').write_text('MARKETING_VERSION: "0.1.0"\nCURRENT_PROJECT_VERSION: "11"\n')
            pbx = root / 'AIQuota-iOS.xcodeproj/project.pbxproj'
            pbx.write_text('CURRENT_PROJECT_VERSION = 11;\n' * 4)
            with patch.object(m, 'MOBILE', root):
                m.sync_build(12)
                self.assertEqual(m.project_numbers(), ('0.1.0', 12))
                self.assertEqual(pbx.read_text().count('= 12;'), 4)
                pbx.write_text('CURRENT_PROJECT_VERSION = 13;')
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
