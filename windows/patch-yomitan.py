"""Fork: makes the stock Yomitan (Chrome build) run inside Electron.

Electron has no chrome.permissions API, so Yomitan's background stops at
start-up (getAll of undefined). Each permissions function gets a guard that
answers as if every permission in the manifest is granted, only when the API
is missing; in a real browser nothing changes. The same workaround is used by
YomiNinja and GSM's overlay. Yomitan stays a separate program (GPL-3); this
script is the whole change.

Usage: python3 patch-yomitan.py <yomitan folder>
"""
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
manifest = json.loads((root / 'manifest.json').read_text(encoding='utf-8'))
granted = {
    'origins': manifest.get('host_permissions', []) + ['file:///*'],
    'permissions': manifest.get('permissions', []) + manifest.get('optional_permissions', []),
}
granted_js = json.dumps(granted)

path = root / 'js' / 'data' / 'permissions-util.js'
text = path.read_text(encoding='utf-8')

guards = {
    'export function hasPermissions(permissions) {':
        "    if (typeof chrome.permissions === 'undefined') { return Promise.resolve(true); } // Memento overlay: Electron",
    'export function setPermissionsGranted(permissions, shouldHave) {':
        "    if (typeof chrome.permissions === 'undefined') { return Promise.resolve(shouldHave); } // Memento overlay: Electron",
    'export function getAllPermissions() {':
        f"    if (typeof chrome.permissions === 'undefined') {{ return Promise.resolve({granted_js}); }} // Memento overlay: Electron",
}

for head, guard in guards.items():
    if head not in text:
        sys.exit(f'patch-yomitan: "{head}" not found, Yomitan changed')
    if guard in text:
        continue
    text = text.replace(head, head + '\n' + guard, 1)

path.write_text(text, encoding='utf-8')
print('Yomitan patched for Electron (permissions)')
