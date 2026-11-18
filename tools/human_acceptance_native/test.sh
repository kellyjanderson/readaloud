#!/bin/bash
set -euo pipefail

source_dir="$(cd "$(dirname "$0")" && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

xcrun swiftc -swift-version 5 -target arm64-apple-macosx12.0 -parse-as-library \
    "$source_dir/Session.swift" "$source_dir/RunnerTests.swift" -o "$temporary/RunnerTests"
"$temporary/RunnerTests"
