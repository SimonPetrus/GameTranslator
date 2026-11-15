# SPDX-License-Identifier: AGPL-3.0-only
# libchiaki (chiaki-ng) + bağımlılıkları, iOS cihaz hedefi (arm64, iphoneos) için statik kütüphane olarak.
# Android'deki mobile/android/app/src/main/cpp/CMakeLists.txt ile aynı yaklaşım: chiaki-ng'nin kök
# CMakeLists'i yerine yalnız third-party + lib eklenir. Farklar: CHIAKI_ENABLE_ANDROID kapalı (bu yüzden
# holepunch.c libevent ister; libevent de kaynaktan derlenir), OpenSSL dışarıdan (GT_OPENSSL_ROOT) gelir,
# MediaCodec/log/android yok. Bağlama kanıtı için linktest/ altındaki dosya dylib ve çalıştırılabilir
# olarak bağlanır. Kullanım: mobile/ios-native/build.sh (README.md).
cmake_minimum_required(VERSION 3.24)
project(gtios C)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
	message(FATAL_ERROR "Bu proje yalnız iOS içindir: -DCMAKE_TOOLCHAIN_FILE=mobile/ios-native/cmake/ios-arm64.toolchain.cmake")
endif()

set(CHIAKI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../third-party/chiaki-ng" CACHE PATH "chiaki-ng kaynakları")
get_filename_component(CHIAKI_DIR "${CHIAKI_DIR}" ABSOLUTE)
if(NOT EXISTS "${CHIAKI_DIR}/lib/CMakeLists.txt")
	message(FATAL_ERROR "chiaki-ng bulunamadı: ${CHIAKI_DIR} (mobile/ios-native/build.sh sabitlenmiş sürümü indirir)")
endif()

set(GT_OPENSSL_ROOT "" CACHE PATH "iOS arm64 için derlenmiş OpenSSL (include/ ve lib/libcrypto.a, lib/libssl.a)")
if(NOT EXISTS "${GT_OPENSSL_ROOT}/lib/libcrypto.a")
	message(FATAL_ERROR "OpenSSL bulunamadı: GT_OPENSSL_ROOT=${GT_OPENSSL_ROOT} (scripts/build-openssl.sh)")
endif()

set(GT_IOS_OUT_DIR "${CMAKE_BINARY_DIR}/out" CACHE PATH "Statik kütüphanelerin ve başlıkların toplandığı klasör")

# --- Bağımlılık yalıtımı ---
# Mac'teki pkg-config, Homebrew'un macOS kütüphanelerini (libevent, libidn2 ...) bulup iOS hedefine
# bağlatabilir. Boş bir arama yolu verilerek hiçbir .pc dosyası görünmez hale getirilir.
set(GT_EMPTY_PKGCONFIG_DIR "${CMAKE_BINARY_DIR}/empty-pkgconfig")
file(MAKE_DIRECTORY "${GT_EMPTY_PKGCONFIG_DIR}")
set(ENV{PKG_CONFIG_LIBDIR} "${GT_EMPTY_PKGCONFIG_DIR}")
set(ENV{PKG_CONFIG_PATH} "")
set(CURL_USE_PKGCONFIG OFF CACHE BOOL "" FORCE)

# --- chiaki-ng seçenekleri: yalnız bağlantı, kayıt ve görüntü akışı (Android ile aynı) ---
set(CHIAKI_ENABLE_ANDROID OFF)
set(CHIAKI_IS_SWITCH OFF)
set(CHIAKI_ENABLE_TESTS OFF)
set(CHIAKI_ENABLE_FFMPEG_DECODER OFF)
set(CHIAKI_ENABLE_PI_DECODER OFF)
set(CHIAKI_ENABLE_STEAM_SHORTCUT OFF)
set(CHIAKI_LIB_ENABLE_OPUS OFF)
set(CHIAKI_LIB_ENABLE_MBEDTLS OFF)
set(CHIAKI_LIB_OPENSSL_EXTERNAL_PROJECT OFF)
set(CHIAKI_USE_SYSTEM_JERASURE OFF)
set(CHIAKI_USE_SYSTEM_NANOPB OFF)
set(CHIAKI_USE_SYSTEM_CURL OFF)
set(CHIAKI_LIB_JSONC_EXTERNAL_PROJECT ON)
set(CHIAKI_LIB_MINIUPNPC_EXTERNAL_PROJECT ON)
set(CHIAKI_VERSION_MAJOR 1)
set(CHIAKI_VERSION_MINOR 10)
set(CHIAKI_VERSION_PATCH 1)
set(CHIAKI_VERSION ${CHIAKI_VERSION_MAJOR}.${CHIAKI_VERSION_MINOR}.${CHIAKI_VERSION_PATCH})

# Bizim modüllerimiz (Findlibevent) chiaki-ng'ninkilerden önce aranır.
list(PREPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
list(APPEND CMAKE_MODULE_PATH "${CHIAKI_DIR}/cmake")
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)

# --- Python (nanopb üreteci; protobuf + grpcio-tools paketleriyle) ---
# chiaki-ng'nin kök dosyası eski FindPythonInterp'i kullanır; burada Python3 modülü bulunur ve chiaki'nin
# beklediği PYTHON_EXECUTABLE ondan doldurulur.
if(PYTHON_EXECUTABLE)
	set(Python_EXECUTABLE "${PYTHON_EXECUTABLE}" CACHE FILEPATH "" FORCE)
	set(Python3_EXECUTABLE "${PYTHON_EXECUTABLE}" CACHE FILEPATH "" FORCE)
endif()
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(PYTHON_EXECUTABLE "${Python3_EXECUTABLE}" CACHE FILEPATH "" FORCE)
# protoc: nanopb'nin grpcio-tools kullanan sarmalayıcısı (ayrı protoc kurmak gerekmez).
if(NOT PROTOC)
	set(PROTOC "${CHIAKI_DIR}/third-party/nanopb/generator/protoc" CACHE FILEPATH "" FORCE)
endif()
if(NOT nanopb_PROTOC_PATH)
	set(nanopb_PROTOC_PATH "${PROTOC}" CACHE FILEPATH "" FORCE)
endif()

# --- OpenSSL (statik, iOS arm64) ---
set(OPENSSL_USE_STATIC_LIBS TRUE)
set(OPENSSL_ROOT_DIR "${GT_OPENSSL_ROOT}")
set(OPENSSL_INCLUDE_DIR "${GT_OPENSSL_ROOT}/include" CACHE PATH "" FORCE)
set(OPENSSL_CRYPTO_LIBRARY "${GT_OPENSSL_ROOT}/lib/libcrypto.a" CACHE FILEPATH "" FORCE)
set(OPENSSL_SSL_LIBRARY "${GT_OPENSSL_ROOT}/lib/libssl.a" CACHE FILEPATH "" FORCE)
find_package(OpenSSL REQUIRED)

# --- Ortak alt proje ayarları ---
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_STATIC_LIBS ON CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)

# --- curl (chiaki-ng alt modülü): yalnız HTTP + WebSocket, OpenSSL ile; isteğe bağlı bağımlılıklar kapalı ---
set(CURL_ZLIB OFF CACHE STRING "" FORCE)
set(CURL_BROTLI OFF CACHE STRING "" FORCE)
set(CURL_ZSTD OFF CACHE STRING "" FORCE)
set(USE_NGHTTP2 OFF CACHE BOOL "" FORCE)
set(USE_LIBIDN2 OFF CACHE BOOL "" FORCE)
set(CURL_USE_LIBPSL OFF CACHE BOOL "" FORCE)
set(CURL_USE_LIBSSH2 OFF CACHE BOOL "" FORCE)
set(CURL_USE_GSSAPI OFF CACHE BOOL "" FORCE)
set(CURL_USE_OPENSSL ON CACHE BOOL "" FORCE)
set(BUILD_LIBCURL_DOCS OFF CACHE BOOL "" FORCE)
set(BUILD_MISC_DOCS OFF CACHE BOOL "" FORCE)
set(ENABLE_CURL_MANUAL OFF CACHE BOOL "" FORCE)

add_subdirectory("${CHIAKI_DIR}/third-party" chiaki-third-party EXCLUDE_FROM_ALL)

add_definitions(-DCHIAKI_VERSION_MAJOR=${CHIAKI_VERSION_MAJOR} -DCHIAKI_VERSION_MINOR=${CHIAKI_VERSION_MINOR}
		-DCHIAKI_VERSION_PATCH=${CHIAKI_VERSION_PATCH} -DCHIAKI_VERSION=\"${CHIAKI_VERSION}\")

include(FetchContent)

# --- json-c (başlıklar Android'deki gibi kopyalanır) ---
set(BUILD_APPS OFF CACHE BOOL "" FORCE)
set(DISABLE_EXTRA_LIBS ON CACHE BOOL "" FORCE)
set(DISABLE_BSON_OUTPUT ON CACHE BOOL "" FORCE)
set(DISABLE_WERROR ON CACHE BOOL "" FORCE)
FetchContent_Declare(json-c
	URL https://github.com/json-c/json-c/archive/refs/tags/json-c-0.17-20230812.tar.gz
	URL_HASH SHA256=024d302a3aadcbf9f78735320a6d5aedf8b77876c8ac8bbb95081ca55054c7eb
	DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(json-c)
set(JSONC_PREFIX_INCLUDE_DIR "${CMAKE_BINARY_DIR}/_deps/json-c-prefix-include")
file(GLOB GT_JSONC_HEADERS "${json-c_SOURCE_DIR}/*.h")
file(COPY ${GT_JSONC_HEADERS} DESTINATION "${JSONC_PREFIX_INCLUDE_DIR}/json-c")

# --- miniupnpc ---
set(UPNPC_BUILD_STATIC ON CACHE BOOL "" FORCE)
set(UPNPC_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(UPNPC_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(UPNPC_BUILD_SAMPLE OFF CACHE BOOL "" FORCE)
set(UPNPC_NO_INSTALL ON CACHE BOOL "" FORCE)
FetchContent_Declare(miniupnpc
	URL https://github.com/miniupnp/miniupnp/archive/refs/tags/miniupnpc_2_2_8.tar.gz
	URL_HASH SHA256=3d0d49f761f09c1321ceb663d1b008825361d7bd242640c60ae467e82642502a
	DOWNLOAD_EXTRACT_TIMESTAMP TRUE
	SOURCE_SUBDIR miniupnpc
)
FetchContent_MakeAvailable(miniupnpc)
set(MINIUPNPC_PREFIX_INCLUDE_DIR "${CMAKE_BINARY_DIR}/_deps/miniupnpc-prefix-include")
file(GLOB GT_UPNPC_HEADERS "${miniupnpc_SOURCE_DIR}/miniupnpc/include/*.h")
file(COPY ${GT_UPNPC_HEADERS} DESTINATION "${MINIUPNPC_PREFIX_INCLUDE_DIR}/miniupnpc")

# --- libevent (yalnız iOS'ta gerekli: holepunch.c Android dışında event2 kullanır) ---
set(EVENT__LIBRARY_TYPE STATIC CACHE STRING "" FORCE)
set(EVENT__DISABLE_OPENSSL ON CACHE BOOL "" FORCE)
set(EVENT__DISABLE_BENCHMARK ON CACHE BOOL "" FORCE)
set(EVENT__DISABLE_TESTS ON CACHE BOOL "" FORCE)
set(EVENT__DISABLE_REGRESS ON CACHE BOOL "" FORCE)
set(EVENT__DISABLE_SAMPLES ON CACHE BOOL "" FORCE)
set(EVENT__DISABLE_DEBUG_MODE ON CACHE BOOL "" FORCE)
FetchContent_Declare(libevent
	URL https://github.com/libevent/libevent/releases/download/release-2.1.12-stable/libevent-2.1.12-stable.tar.gz
	URL_HASH SHA256=92e6de1be9ec176428fd2367677e61ceffc2ee1cb119035037a27d346b0403bb
	DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(libevent)

add_subdirectory("${CHIAKI_DIR}/lib" chiaki-lib EXCLUDE_FROM_ALL)

# --- Bağlama kanıtı ---
# 1) dylib: -undefined error (ld64 varsayılanı) ile her sembol çözülmeli.
add_library(gt_ios_linktest SHARED linktest/gt_ios_linktest.c)
target_compile_options(gt_ios_linktest PRIVATE -Wall)
target_link_libraries(gt_ios_linktest PRIVATE chiaki-lib)
target_link_options(gt_ios_linktest PRIVATE
	"LINKER:-undefined,error"
	"LINKER:-map,${CMAKE_BINARY_DIR}/gt_ios_linktest.map")
# 2) çalıştırılabilir (main'li); çalıştırılmaz, yalnız bağlanır.
add_executable(gt_ios_linktest_exe linktest/gt_ios_linktest.c)
target_compile_definitions(gt_ios_linktest_exe PRIVATE GT_LINKTEST_MAIN)
target_link_libraries(gt_ios_linktest_exe PRIVATE chiaki-lib)

# --- Çıktılar: tek tek statik kütüphaneler + hepsini içeren birleşik arşiv + başlıklar ---
set(GT_BUNDLE_TARGETS chiaki-lib jerasure gf_complete protobuf-nanopb-static CURL::libcurl json-c libminiupnpc-static event_core_static)
set(GT_BUNDLE_FILES)
foreach(t IN LISTS GT_BUNDLE_TARGETS)
	list(APPEND GT_BUNDLE_FILES "$<TARGET_FILE:${t}>")
endforeach()
list(APPEND GT_BUNDLE_FILES "${OPENSSL_SSL_LIBRARY}" "${OPENSSL_CRYPTO_LIBRARY}")
# Apple libtool (Homebrew'un GNU libtool'u ile karışmasın diye xcrun üzerinden).
add_custom_target(gt_ios_bundle ALL
	COMMAND "${CMAKE_COMMAND}" -E rm -rf "${GT_IOS_OUT_DIR}"
	COMMAND "${CMAKE_COMMAND}" -E make_directory "${GT_IOS_OUT_DIR}/lib" "${GT_IOS_OUT_DIR}/include/chiaki"
	COMMAND "${CMAKE_COMMAND}" -E copy ${GT_BUNDLE_FILES} "${GT_IOS_OUT_DIR}/lib/"
	COMMAND xcrun libtool -static -no_warning_for_no_symbols -o "${GT_IOS_OUT_DIR}/lib/libgtchiaki_ios.a" ${GT_BUNDLE_FILES}
	COMMAND "${CMAKE_COMMAND}" -E copy_directory "${CHIAKI_DIR}/lib/include" "${GT_IOS_OUT_DIR}/include"
	COMMAND "${CMAKE_COMMAND}" -E copy "${CMAKE_BINARY_DIR}/chiaki-lib/include/chiaki/config.h" "${GT_IOS_OUT_DIR}/include/chiaki/config.h"
	COMMAND "${CMAKE_COMMAND}" -E copy "${CMAKE_CURRENT_SOURCE_DIR}/linktest/gt_ios_linktest.c" "${GT_IOS_OUT_DIR}/"
	COMMAND_EXPAND_LISTS
	VERBATIM
)
add_dependencies(gt_ios_bundle gt_ios_linktest gt_ios_linktest_exe)
