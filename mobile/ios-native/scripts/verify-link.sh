#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Bağlama kanıtını doğrular ve <çıktı>/LINK_REPORT.md olarak yazar:
#  1) gt_ios_linktest dylib + çalıştırılabilir: Mach-O arm64, platform iOS, libchiaki/curl/... sembolü çözülmemiş kalmamış.
#  2) Bağlayıcı haritası: discovery/regist/session/holepunch nesneleri ve bağımlılık arşivleri gerçekten bağlanmış.
#  3) Yalnız çıktı klasöründeki birleşik arşiv + başlıklarla, CMake dışında, aynı dosya yeniden bağlanır
#     (Xcode'a taşınacak şeyin kendi başına yettiğinin kanıtı).
# Kullanım: verify-link.sh <derleme-klasörü> <çıktı-klasörü>
set -euo pipefail

BUILD="${1:?derleme klasörü}"
OUT="${2:?çıktı klasörü}"
IOS_MIN="${GT_IOS_DEPLOYMENT_TARGET:-13.0}"
DYLIB="$BUILD/libgt_ios_linktest.dylib"
EXE="$BUILD/gt_ios_linktest_exe"
MAP="$BUILD/gt_ios_linktest.map"
REPORT="$OUT/LINK_REPORT.md"
mkdir -p "$OUT"
: > "$REPORT"

say() { printf '%s\n' "$*" | tee -a "$REPORT"; }
fail() { say "HATA: $*"; exit 1; }

say "# iOS bağlama kanıtı"
say ""
say "- Tarih (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
say "- Xcode: $(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
say "- SDK: $(xcrun --sdk iphoneos --show-sdk-version) ($(xcrun --sdk iphoneos --show-sdk-path))"
say "- En düşük iOS: $IOS_MIN"
say ""

check_binary() {
	local f="$1"
	[[ -f "$f" ]] || fail "yok: $f"
	say "## $(basename "$f")"
	say '```'
	say "$(file "$f")"
	local archs
	archs="$(xcrun lipo -archs "$f")"
	[[ "$archs" == "arm64" ]] || fail "$f mimarisi arm64 değil: $archs"
	local build
	build="$(xcrun vtool -show-build "$f" 2>/dev/null || otool -l "$f")"
	say "$(printf '%s\n' "$build" | grep -E '^[[:space:]]*(platform|minos|sdk) ' | head -3)"
	printf '%s\n' "$build" | grep -Eq '^[[:space:]]*platform (2|IOS)[[:space:]]*$' || fail "$f platformu iOS değil"
	local unresolved
	unresolved="$(xcrun nm -u "$f" | grep -E '^_(chiaki_|curl_|Curl_|event_|evutil_|json_|upnp|UPNP_|strupnp|OPENSSL_|EVP_|SSL_|BIO_|pb_|jerasure_|galois_|gf_|reed_sol_)' || true)"
	[[ -z "$unresolved" ]] || fail "$f içinde çözülmemiş kütüphane sembolü: $unresolved"
	say "çözülmemiş (sistemden gelecek) sembol sayısı: $(xcrun nm -u "$f" | wc -l | tr -d ' ')"
	say "bağlı sistem kütüphaneleri:"
	say "$(otool -L "$f" | tail -n +2)"
	say '```'
}

check_binary "$DYLIB"
xcrun nm -gU "$DYLIB" | grep -q ' _gt_ios_linktest_probe$' || fail "dylib gt_ios_linktest_probe dışa açmıyor"
check_binary "$EXE"

# --- Bağlayıcı haritası ---
[[ -f "$MAP" ]] || fail "bağlayıcı haritası yok: $MAP"
say "## Bağlayıcı haritası (dylib): arşiv başına bağlanan nesne sayısı"
say '```'
say "örnek satırlar:"
say "$(grep -m3 -E 'libchiaki\.a' "$MAP" || true)"
missing=0
for lib in libchiaki.a libjerasure.a libgf_complete.a libprotobuf-nanopb.a libcurl.a libjson-c.a libminiupnpc.a libevent_core.a libssl.a libcrypto.a; do
	# ld64: ".../libx.a(y.o)", yeni bağlayıcı (ld-prime): ".../libx.a[N](y.o)"
	n="$(grep -cE "/${lib//./\\.}(\[[0-9]+\])?\(" "$MAP" || true)"
	say "$(printf '%-22s %s' "$lib" "$n")"
	case "$lib" in
		libchiaki.a|libcurl.a|libjson-c.a|libminiupnpc.a|libevent_core.a|libcrypto.a|libjerasure.a|libprotobuf-nanopb.a)
			[[ "$n" -gt 0 ]] || missing=1 ;;
	esac
done
for obj in discovery regist session holepunch takion streamconnection; do
	grep -qE "/libchiaki\.a(\[[0-9]+\])?\($obj\.c\.o\)" "$MAP" || fail "libchiaki.a($obj.c.o) bağlanmamış"
done
say "libchiaki.a içinden: discovery, regist, session, holepunch, takion, streamconnection bağlandı"
say '```'
[[ "$missing" -eq 0 ]] || fail "beklenen bir bağımlılık arşivinden hiç nesne bağlanmamış"

# --- Bağımsız bağlama: yalnız çıktı klasörüyle ---
[[ -f "$OUT/lib/libgtchiaki_ios.a" ]] || fail "birleşik arşiv yok"
sys_flags=()
while read -r dep; do
	case "$dep" in
		*/libSystem.B.dylib) ;;
		*.framework/*) name="${dep%%.framework/*}"; sys_flags+=(-framework "${name##*/}") ;;
		/usr/lib/lib*.dylib) name="${dep##*/lib}"; sys_flags+=("-l${name%%.*}") ;;
	esac
done < <(otool -L "$DYLIB" | tail -n +2 | awk '{print $1}')
STANDALONE="$BUILD/standalone/libgt_standalone.dylib"
mkdir -p "$(dirname "$STANDALONE")"
xcrun -sdk iphoneos clang -arch arm64 "-mios-version-min=$IOS_MIN" -dynamiclib \
	-install_name @rpath/libgt_standalone.dylib \
	-I"$OUT/include" "$OUT/gt_ios_linktest.c" "$OUT/lib/libgtchiaki_ios.a" \
	${sys_flags[@]+"${sys_flags[@]}"} -Wl,-undefined,error -o "$STANDALONE"
say "## Bağımsız bağlama (yalnız out/include + out/lib/libgtchiaki_ios.a)"
say '```'
say "ek bağlayıcı bayrakları: ${sys_flags[*]:-(yok)}"
say "$(file "$STANDALONE")"
say '```'
check_binary "$STANDALONE"

say "## Çıktılar"
say '```'
say "$(cd "$OUT" && ls -l lib)"
say "$(cd "$OUT" && find include -name '*.h' | wc -l | tr -d ' ') başlık dosyası (include/)"
say '```'
say ""
say "SONUÇ: BAŞARILI — libchiaki ve bağımlılıkları iOS arm64 (iphoneos) için derlendi ve bağlandı."
