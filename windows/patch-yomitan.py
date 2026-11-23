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
manifest = json.loads((root / 'manifest.json').read_text(encoding='utf-8-sig'))

# A fixed public key gives Yomitan the same extension ID (ijackakicchpihljanchkfbindleipce)
# wherever Memento is installed; the ID decides where Yomitan's dictionaries
# and settings are stored, so without it every install folder started empty.
# Only the public half exists; nothing is signed with it.
manifest['key'] = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEArUYottgvT8e3viTy5h1yOtmmgTG39HeCHgAdRzbP/+2jVkcxQGwJpUKfdQx4c8sLnWVa3gwKmM34hleQzVYsSN+pYtn+Er8b5eRgOVwlzTOdqAoInz4jMNIItw/h1PEO5YwQljh5FYh+ghrKOuM3DN+7cw85QuImpTbPWWlNuXPKY34OATfox+yAqk1ZJIYrSLvqX6qU+yrn3W6rZsVJHS21sqajywjhPaEtB4N+aEjKLu/KT7pdDldsxGH0+F9u8oK584T/vqO/sQrh7Y91YuCjGuSsY0ALLa6W5V57CZLTtQyFPNEtlIES/04X8kDR4u6veMh5HxMjeOprcgUIuwIDAQAB'
(root / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=4), encoding='utf-8')
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

# The popup sits in a closed shadow root, which the overlay page can't look
# into to tell whether the popup is open. Inside Electron (no
# chrome.permissions) make it an open one; browsers keep 'closed'.
path = root / 'js' / 'app' / 'popup.js'
text = path.read_text(encoding='utf-8')
old = "container.attachShadow({mode: 'closed', delegatesFocus: true});"
new = "container.attachShadow({mode: (typeof chrome.permissions === 'undefined' ? 'open' : 'closed'), delegatesFocus: true}); // Memento overlay: Electron"
if new not in text:
    if old not in text:
        sys.exit('patch-yomitan: popup shadow root not found, Yomitan changed')
    text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')
print('Yomitan patched for Electron (permissions, popup shadow root)')
