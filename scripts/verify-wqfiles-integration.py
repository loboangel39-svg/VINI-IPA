"""Verify full upstream inventory and compiled target membership."""
from pathlib import Path
import hashlib, json, re
root = Path(__file__).resolve().parents[1]
vendor = root/'Vendor/WQFiles'
manifest = json.loads((vendor/'UPSTREAM.json').read_text())
adapted = {'main.m', 'WQLocalization.m'}
for name, expected in manifest['sha256'].items():
    path = vendor/name
    assert path.is_file(), f'missing upstream dependency: {name}'
    if name not in adapted:
        assert hashlib.sha256(path.read_bytes().replace(b'\r\n', b'\n')).hexdigest() == expected, f'upstream changed: {name}'
project = (root/'ThreeOneOSFive.xcodeproj/project.pbxproj').read_text()
for path in vendor.glob('WQ*.m'):
    assert f'{path.name} in Sources' in project, f'not built: {path.name}'
assert '#include "main.m"' in (vendor/'WQEmbedded.m').read_text()
assert '#define main WQStandaloneMain' in (vendor/'WQEmbedded.m').read_text()
assert 'WQIntegratedInitialize()' in (root/'ThreeOneOSFive/App.swift').read_text()
assert 'WQIntegratedMakeViewController()' in (root/'ThreeOneOSFive/views/SettingsView.swift').read_text()
ids = re.findall(r'^\s*([A-F0-9]{24})\s*(?:/\*.*?\*/\s*)?=\s*\{', project, re.M)
assert len(ids) == len(set(ids)), 'duplicate Xcode object identifiers'
print(f'PASS: {len(manifest["sha256"])} upstream files preserved; all implementations in target')
