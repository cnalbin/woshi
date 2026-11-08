#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate_project.py
xcodebuild -project ios/QingJi.xcodeproj -scheme QingJi -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
mkdir -p build/ipa/Payload
ditto build/DerivedData/Build/Products/Release-iphoneos/QingJi.app build/ipa/Payload/QingJi.app
cd build/ipa
ditto -c -k --keepParent Payload ../QingJi-unsigned.ipa
cd ../..
python3 scripts/verify_ipa.py build/QingJi-unsigned.ipa
shasum -a 256 build/QingJi-unsigned.ipa > build/QingJi-unsigned.ipa.sha256
