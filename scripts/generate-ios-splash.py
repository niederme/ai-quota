#!/usr/bin/env python3
"""Compose static, enclosure-free launch assets from the Icon Composer source.

The source geometry and colors are retained; SVG edge highlights are a static
launch treatment, not live Liquid Glass. The app icon itself is unchanged.
"""
import copy
import json
import subprocess
import shutil
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'iOS/App/Assets.xcassets'
ICON = ROOT / 'AIQuota/AppIcon.icon'
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)

def color(name, dark):
    values = json.loads((ASSETS / f'{name}.colorset/Contents.json').read_text())['colors']
    value = next((v for v in values if bool(v.get('appearances')) == dark), values[0])
    components = value['color']['components']
    return '#' + ''.join(f'{round(float(components[k])*255):02x}' for k in ('red','green','blue'))

def save(name, documents):
    folder = ASSETS / f'{name}.imageset'
    folder.mkdir(exist_ok=True)
    converter = shutil.which('rsvg-convert')
    if converter is None:
        raise SystemExit('Install librsvg (brew install librsvg) to regenerate launch PNGs.')
    images = []
    for appearance, document in documents.items():
        scales = (1,2,3) if name == 'LaunchArtwork' else (1,)
        for scale in scales:
            filename = f'{appearance}@{scale}x.png'
            image = {'filename':filename,'idiom':'universal'}
            args = [converter, '--output', str(folder/filename)]
            if name == 'LaunchArtwork':
                args += ['--width',str(144*scale),'--height',str(144*scale)]
                image['scale'] = f'{scale}x'
            subprocess.run(args,input=document.encode(),check=True)
            if appearance == 'dark':
                image['appearances'] = [{'appearance':'luminosity','value':'dark'}]
            images.append(image)
    (folder/'Contents.json').write_text(json.dumps({'images':images,'info':{'author':'xcode','version':1}},indent=2)+'\n')

def artwork(dark):
    result = ET.Element(f'{{{NS}}}svg', {'width':'144','height':'144','viewBox':'0 0 1024 1024'})
    defs = ET.SubElement(result, f'{{{NS}}}defs')
    gradient = ET.SubElement(defs, f'{{{NS}}}linearGradient', {'id':'edge','x1':'0','y1':'0','x2':'0','y2':'1'})
    for offset,opacity in [('0','0.85'),('0.5','0.12'),('1','0.4')]:
        ET.SubElement(gradient, f'{{{NS}}}stop', {'offset':offset,'stop-color':'#FFFFFF','stop-opacity':opacity})
    document = json.loads((ICON/'icon.json').read_text())
    for group in reversed(document['groups']):
        if group.get('hidden'): continue
        for layer in reversed(group['layers']):
            if layer.get('hidden'): continue
            for original in ET.parse(ICON/'Assets'/layer['image-name']).getroot():
                shape = copy.deepcopy(original)
                if 'Track' in layer['name'] and not dark:
                    shape.set('fill-opacity','0.55')
                if layer['name'] == 'Spark' and not dark:
                    shape.set('fill', color('OverviewAccent',False))
                result.append(shape)
                if layer.get('glass'):
                    edge = copy.deepcopy(shape)
                    edge.set('fill','none')
                    edge.attrib.pop('fill-opacity',None)
                    edge.set('stroke','url(#edge)')
                    edge.set('stroke-width','4')
                    result.append(edge)
    return ET.tostring(result, encoding='unicode')

def background(dark):
    base, accent = color('OverviewBase',dark), color('OverviewAccent',dark)
    top,middle,glow = (0.72,0.12,0.35) if dark else (0.18,0.05,0.12)
    return f'''<svg xmlns="{NS}" width="1000" height="2000" viewBox="0 0 1000 2000">
<defs>
<linearGradient id="wash" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="#661F8F" stop-opacity="{top}"/>
<stop offset="0.4" stop-color="{accent}" stop-opacity="{middle}"/>
<stop offset="0.7" stop-color="{accent}" stop-opacity="0"/>
</linearGradient>
<radialGradient id="glow" gradientUnits="userSpaceOnUse" cx="1000" cy="0" r="850">
<stop offset="0" stop-color="{accent}" stop-opacity="{glow}"/>
<stop offset="1" stop-color="{accent}" stop-opacity="0"/>
</radialGradient>
</defs>
<path d="M0 0H1000V2000H0Z" fill="{base}"/>
<path d="M0 0H1000V2000H0Z" fill="url(#wash)"/>
<path d="M0 0H1000V2000H0Z" fill="url(#glow)"/>
</svg>'''

if __name__ == '__main__':
    save('LaunchArtwork', {'light':artwork(False),'dark':artwork(True)})
    save('LaunchBackground', {'light':background(False),'dark':background(True)})
