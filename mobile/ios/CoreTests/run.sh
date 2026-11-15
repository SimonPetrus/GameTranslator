#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Runner/Core/*.swift'i testlerle birlikte swiftc ile derleyip çalıştırır (XCTest gerekmez).
# Kullanım: CoreTests/run.sh [derleme klasörü]   (varsayılan: $TMPDIR altında geçici klasör; depoya yazılmaz)
# SWIFT_VERSION=6 ile Swift 6 dil kipinde derlenir (varsayılan 5).
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
RUNNER="$HERE/../Runner"

if [ $# -ge 1 ]; then
  BUILD="$1"
  mkdir -p "$BUILD"
else
  BUILD="$(mktemp -d "${TMPDIR:-/tmp}/gt-coretests.XXXXXX")"
  trap 'rm -rf "$BUILD"' EXIT
fi

# TextBox tek kaynaktan gelir: SubtitleServer.swift'teki tanım çıkarılır (dosyanın geri kalanı Network/uygulama ister).
awk '/^struct TextBox[: {]/ { on = 1 } on { print } on && /^}/ { exit }' "$RUNNER/SubtitleServer.swift" > "$BUILD/TextBox.swift"
if ! grep -q 'struct TextBox' "$BUILD/TextBox.swift"; then
  echo "TextBox tanımı $RUNNER/SubtitleServer.swift içinde bulunamadı" >&2
  exit 1
fi

xcrun swiftc -swift-version "${SWIFT_VERSION:-5}" -O \
  -module-name CoreTests \
  -module-cache-path "$BUILD/module-cache" \
  "$RUNNER"/Core/*.swift "$BUILD/TextBox.swift" \
  "$HERE/Harness.swift" "$HERE/CoreTest.swift" "$HERE/GlossaryTest.swift" "$HERE/SpeakerNameTest.swift" "$HERE/main.swift" \
  -o "$BUILD/coretests"

"$BUILD/coretests"
