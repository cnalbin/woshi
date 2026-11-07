#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate_project.py
SIMULATOR_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; ds=[d for v in json.load(sys.stdin)["devices"].values() for d in v if d["name"].startswith("iPhone") and d["isAvailable"]]; print(ds[0]["udid"])')
xcrun simctl boot "$SIMULATOR_ID"
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcodebuild -project ios/QingJi.xcodeproj -scheme QingJi -configuration Debug \
  -sdk iphonesimulator -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath build/Simulator -resultBundlePath build/UITests.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
