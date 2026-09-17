#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo '此脚本需要装有苹果开发工具的电脑；纯配置测试可单独运行 swift test。' >&2
  exit 1
fi
swift test
xcodebuild -project BetweenUsPhysicsDemo.xcodeproj -scheme BetweenUsPhysicsDemo \
  -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/BetweenUsPhysicsDemoDerived CODE_SIGNING_ALLOWED=NO build
if [[ -n "${SIMULATOR_ID:-}" ]]; then
  xcodebuild -project BetweenUsPhysicsDemo.xcodeproj -scheme BetweenUsPhysicsDemo \
    -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -derivedDataPath /tmp/BetweenUsPhysicsDemoDerived CODE_SIGNING_ALLOWED=NO test
else
  echo '编译结束；指定 SIMULATOR_ID 后重跑，可执行附带的苹果框架装配测试。'
fi
