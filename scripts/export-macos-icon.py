#!/usr/bin/env python3
"""Export macOS compatibility/UI artwork from the shared Icon Composer source.

Run after editing AIQuota/AppIcon.icon. Requires Xcode with Icon Composer.
The layered document remains the app icon on macOS 26 and later.
"""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEVELOPER = Path(os.environ.get('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer'))
ICTOOL = DEVELOPER.parent / 'Applications/Icon Composer.app/Contents/Executables/ictool'
ASSETS = ROOT / 'AIQuota/Resources/Assets.xcassets'


def render(output, size, rendition='Default'):
    subprocess.run([
        str(ICTOOL), str(ROOT / 'AIQuota/AppIcon.icon'), '--export-image',
        '--output-file', str(output), '--platform', 'macOS', '--rendition', rendition,
        '--width', str(size), '--height', str(size), '--scale', '1',
        '--design-generation', '26',
    ], check=True)


if __name__ == '__main__':
    for size in (16, 32, 64, 128, 256, 512, 1024):
        render(ASSETS / f'AppIcon.appiconset/icon_{size}.png', size)
    ui = ASSETS / 'AppBrandIcon.imageset'
    ui.mkdir(exist_ok=True)
    images = []
    for rendition in ('Default', 'Dark'):
        for scale, size in ((1, 128), (2, 256)):
            filename = f'icon-{rendition.lower()}@{scale}x.png'
            render(ui / filename, size, rendition)
            item = {'idiom': 'mac', 'filename': filename, 'scale': f'{scale}x'}
            if rendition == 'Dark':
                item['appearances'] = [{'appearance': 'luminosity', 'value': 'dark'}]
            images.append(item)
    (ui / 'Contents.json').write_text(json.dumps({
        'images': images, 'info': {'author': 'xcode', 'version': 1}
    }, indent=2) + '\n')
