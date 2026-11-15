#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# OpenSSL'i iOS cihaz hedefi (arm64, iphoneos) için kaynaktan, yalnız statik kütüphane olarak derler.
# Kullanım: build-openssl.sh <kurulum-klasörü> <çalışma-klasörü>
# Sürüm ve SHA-256 aşağıda sabitlidir; indirilen arşiv doğrulanmadan derlenmez.
set -euo pipefail

OPENSSL_VERSION="${OPENSSL_VERSION:-3.5.9}"
OPENSSL_SHA256="${OPENSSL_SHA256:-603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a}"
IOS_MIN="${GT_IOS_DEPLOYMENT_TARGET:-13.0}"

PREFIX="${1:?kurulum klasörü gerekli}"
WORK="${2:?çalışma klasörü gerekli}"

if [[ -f "$PREFIX/lib/libcrypto.a" && -f "$PREFIX/lib/libssl.a" && -f "$PREFIX/.gt-openssl-$OPENSSL_VERSION-ios$IOS_MIN" ]]; then
	echo "OpenSSL $OPENSSL_VERSION (iOS $IOS_MIN) zaten hazır: $PREFIX"
	exit 0
fi

mkdir -p "$WORK"
cd "$WORK"
ARCHIVE="openssl-$OPENSSL_VERSION.tar.gz"
if [[ ! -f "$ARCHIVE" ]]; then
	curl -fsSL --retry 3 -o "$ARCHIVE.part" \
		"https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/$ARCHIVE"
	mv "$ARCHIVE.part" "$ARCHIVE"
fi
echo "$OPENSSL_SHA256  $ARCHIVE" | shasum -a 256 -c -

rm -rf "openssl-$OPENSSL_VERSION"
tar -xzf "$ARCHIVE"
cd "openssl-$OPENSSL_VERSION"

# ios64-xcrun: "xcrun -sdk iphoneos cc -arch arm64". async iOS'ta zaten kapalı.
./Configure ios64-xcrun \
	--prefix="$PREFIX" --openssldir="$PREFIX/ssl" --libdir=lib \
	no-shared no-apps no-docs no-tests no-module no-engine \
	"-mios-version-min=$IOS_MIN"

JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
make -j"$JOBS" build_libs >/dev/null
make install_dev >/dev/null
touch "$PREFIX/.gt-openssl-$OPENSSL_VERSION-ios$IOS_MIN"

cd "$WORK"
rm -rf "openssl-$OPENSSL_VERSION"

echo "OpenSSL $OPENSSL_VERSION kuruldu: $PREFIX"
xcrun lipo -info "$PREFIX/lib/libcrypto.a" "$PREFIX/lib/libssl.a"
