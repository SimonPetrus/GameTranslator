#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# libchiaki + bağımlılıklarını iOS cihaz hedefi (arm64, iphoneos) için derler, bağlama kanıtını üretir
# ve doğrular. macOS + Xcode gerekir. GitHub Actions (.github/workflows/ios-native.yml) bunu çağırır;
# Mac'te depo kökünden: ./mobile/ios-native/build.sh
#
# Ortam değişkenleri (hepsi isteğe bağlı):
#   GT_WORK_DIR               geçici ve çıktı klasörü (varsayılan: <depo>/work/ios-native)
#   CHIAKI_DIR                chiaki-ng kaynakları (varsayılan: <depo>/third-party/chiaki-ng; yoksa indirilir)
#   GT_OPENSSL_ROOT           hazır iOS OpenSSL (varsayılan: kaynaktan derlenir)
#   GT_IOS_DEPLOYMENT_TARGET  en düşük iOS sürümü (varsayılan: 13.0)
#   PYTHON                    Python 3 yorumlayıcısı (varsayılan: python3)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

# chiaki-ng sabit sürüm: v1.10.1 (Android'deki CHIAKI_VERSION ile aynı).
CHIAKI_REF="v1.10.1"
CHIAKI_COMMIT="f30da0aaeb96fc0026cc03683153f682352e7d7c"
CHIAKI_SUBMODULES=(third-party/curl third-party/gf-complete third-party/jerasure third-party/nanopb)
PIP_PACKAGES=(protobuf==5.29.5 grpcio==1.71.0 grpcio-tools==1.71.0)

WORK="${GT_WORK_DIR:-$REPO/work/ios-native}"
CHIAKI_DIR="${CHIAKI_DIR:-$REPO/third-party/chiaki-ng}"
export GT_IOS_DEPLOYMENT_TARGET="${GT_IOS_DEPLOYMENT_TARGET:-13.0}"
OPENSSL_PREFIX="${GT_OPENSSL_ROOT:-$WORK/deps/openssl-ios-arm64-$GT_IOS_DEPLOYMENT_TARGET}"
BUILD="$WORK/build"
OUT="$WORK/out"
VENV="$WORK/venv"
PY="${PYTHON:-python3}"

log() { printf '\n==> %s\n' "$*"; }

[[ "$(uname -s)" == "Darwin" ]] || { echo "Bu betik macOS + Xcode ister." >&2; exit 1; }
mkdir -p "$WORK"

# --- 1. chiaki-ng ---
if [[ ! -f "$CHIAKI_DIR/lib/CMakeLists.txt" ]]; then
	log "chiaki-ng $CHIAKI_REF indiriliyor"
	git clone --quiet --depth 1 --branch "$CHIAKI_REF" https://github.com/streetpea/chiaki-ng "$CHIAKI_DIR"
	git -C "$CHIAKI_DIR" submodule update --init --depth 1 "${CHIAKI_SUBMODULES[@]}"
fi
HEAD_COMMIT="$(git -C "$CHIAKI_DIR" rev-parse HEAD)"
if [[ "$HEAD_COMMIT" != "$CHIAKI_COMMIT" ]]; then
	echo "chiaki-ng beklenen sürümde değil: $HEAD_COMMIT (beklenen $CHIAKI_REF = $CHIAKI_COMMIT)" >&2
	[[ "${GT_ALLOW_CHIAKI_MISMATCH:-0}" == "1" ]] || exit 1
fi
for sub in "${CHIAKI_SUBMODULES[@]}"; do
	[[ -n "$(ls -A "$CHIAKI_DIR/$sub" 2>/dev/null)" ]] || git -C "$CHIAKI_DIR" submodule update --init --depth 1 "$sub"
done

# Yamalar (varsa): kaynak değiştirilmez, yalnız mobile/ios-native/patches/*.patch uygulanır.
shopt -s nullglob
for patch in "$HERE"/patches/*.patch; do
	if git -C "$CHIAKI_DIR" apply --check "$patch" 2>/dev/null; then
		log "yama: $(basename "$patch")"
		git -C "$CHIAKI_DIR" apply "$patch"
	elif git -C "$CHIAKI_DIR" apply --reverse --check "$patch" 2>/dev/null; then
		echo "yama zaten uygulanmış: $(basename "$patch")"
	else
		echo "yama uygulanamadı: $patch" >&2
		exit 1
	fi
done
shopt -u nullglob

# --- 2. Python (nanopb üreteci) ---
if [[ ! -x "$VENV/bin/python" ]]; then
	log "Python sanal ortamı"
	"$PY" -m venv "$VENV"
fi
"$VENV/bin/python" -m pip install --quiet --disable-pip-version-check "${PIP_PACKAGES[@]}"
export PATH="$VENV/bin:$PATH" # nanopb'nin protoc sarmalayıcısı "python3" arar

# --- 3. OpenSSL ---
log "OpenSSL (iOS arm64, iOS $GT_IOS_DEPLOYMENT_TARGET+)"
bash "$HERE/scripts/build-openssl.sh" "$OPENSSL_PREFIX" "$WORK/dl"

# --- 4. CMake ---
log "CMake yapılandırma"
cmake -S "$HERE" -B "$BUILD" \
	-DCMAKE_TOOLCHAIN_FILE="$HERE/cmake/ios-arm64.toolchain.cmake" \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
	-DGT_IOS_DEPLOYMENT_TARGET="$GT_IOS_DEPLOYMENT_TARGET" \
	-DCHIAKI_DIR="$CHIAKI_DIR" \
	-DGT_OPENSSL_ROOT="$OPENSSL_PREFIX" \
	-DGT_IOS_OUT_DIR="$OUT" \
	-DPYTHON_EXECUTABLE="$VENV/bin/python"

log "Derleme"
cmake --build "$BUILD" --parallel "$(sysctl -n hw.ncpu)"

# --- 5. Doğrulama ---
bash "$HERE/scripts/verify-link.sh" "$BUILD" "$OUT"
