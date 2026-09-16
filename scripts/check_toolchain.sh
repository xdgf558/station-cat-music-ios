#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
expected=$(cat .xcode-version)
actual=$(xcodebuild -version | sed -n '1s/^Xcode //p')
if [[ "$actual" != "$expected" ]]; then
  if [[ "${M1_ALLOW_LOCAL_TOOLCHAIN:-0}" != 1 || "${CI:-false}" == true ]]; then
    echo "Expected Xcode $expected; got $actual. Local experiments may set M1_ALLOW_LOCAL_TOOLCHAIN=1; CI must stay pinned." >&2
    exit 1
  fi
  echo "LOCAL TOOLCHAIN OVERRIDE: $actual; this is not stable-CI acceptance."
fi
xcodebuild -version
