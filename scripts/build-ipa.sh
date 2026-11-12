#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate_project.py
xcodebuild -project ios/QingJi.xcodeproj -scheme QingJi -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
mkdir -p build/ipa/Payload
ditto build/DerivedData/Build/Products/Release-iphoneos/QingJi.app build/ipa/Payload/QingJi.app
SOURCE_REVISION=$(git rev-parse HEAD)
/usr/libexec/PlistBuddy -c "Add :QingJiSourceRevision string $SOURCE_REVISION" build/ipa/Payload/QingJi.app/Info.plist
IPA_NAME="QingJi-v0.10.0-build12-unsigned.ipa"
cd build/ipa
ditto -c -k --keepParent Payload "../$IPA_NAME"
cd ../..
python3 scripts/verify_ipa.py "build/$IPA_NAME" --version 0.10.0 --build 12 --display-name '轻记新版' --revision "$SOURCE_REVISION"
shasum -a 256 "build/$IPA_NAME" > "build/$IPA_NAME.sha256"
