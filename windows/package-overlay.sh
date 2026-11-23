#!/bin/bash

# Fork: bundles the Yomitan overlay into ./overlay of the current directory
# (the portable/installer folder): the Electron runtime renamed to
# memento-overlay.exe, the overlay app (overlay/app in this repo) and the
# stock, unmodified Yomitan for Chrome. Yomitan is its own program (GPL-3);
# Memento only talks to the overlay over a local connection.
#
# Usage: package-overlay.sh <path to the repo root>

set -euo pipefail

ELECTRON_VERSION=42.3.2
YOMITAN_VERSION=26.11.10.0

repo="$1"
dest="overlay"

rm -rf "$dest"
mkdir -p "$dest"

curl -fL --retry 3 \
    "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/electron-v${ELECTRON_VERSION}-win32-x64.zip" \
    -o electron.zip
python3 -m zipfile -e electron.zip "$dest"
rm electron.zip
mv "$dest/electron.exe" "$dest/memento-overlay.exe"
rm -f "$dest/resources/default_app.asar"

mkdir -p "$dest/resources/app"
cp "$repo"/overlay/app/*.js "$repo"/overlay/app/*.html "$repo"/overlay/app/package.json \
    "$dest/resources/app/"

curl -fL --retry 3 \
    "https://github.com/yomidevs/yomitan/releases/download/${YOMITAN_VERSION}/yomitan-chrome.zip" \
    -o yomitan.zip
mkdir -p "$dest/resources/yomitan"
python3 -m zipfile -e yomitan.zip "$dest/resources/yomitan"
rm yomitan.zip

for required in \
    "$dest/memento-overlay.exe" \
    "$dest/resources/app/main.js" \
    "$dest/resources/yomitan/manifest.json"
do
    if [[ ! -f "$required" ]]
    then
        echo "Overlay packaging failed: missing $required" >&2
        exit 1
    fi
done
echo "Overlay bundled (Electron ${ELECTRON_VERSION}, Yomitan ${YOMITAN_VERSION})"
