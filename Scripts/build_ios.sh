#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 Scripts/generate_project.py
xcodebuild -project Hearth.xcodeproj -scheme Hearth -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO clean build
mkdir -p build/package/Payload
cp -R build/Build/Products/Release-iphoneos/Hearth.app build/package/Payload/
(cd build/package && /usr/bin/ditto -c -k --keepParent Payload ../Hearth-unsigned.ipa)
shasum -a 256 build/Hearth-unsigned.ipa > build/SHA256SUMS.txt
printf '%s\n' 'Unsigned IPA created. Install using your own Apple account via AltStore Classic; not directly installable from Safari.'
