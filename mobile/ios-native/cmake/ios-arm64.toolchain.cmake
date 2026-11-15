# SPDX-License-Identifier: AGPL-3.0-only
# iOS cihaz hedefi (arm64, iphoneos SDK) için CMake araç zinciri. CMake'in yerleşik iOS desteğini kullanır;
# "Unix Makefiles" üreteciyle imzalama gerekmez. Simülatör bu dosyanın kapsamında değil.
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_SYSROOT iphoneos CACHE STRING "iOS SDK")
set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "iOS mimarisi")

if(NOT DEFINED GT_IOS_DEPLOYMENT_TARGET)
	set(GT_IOS_DEPLOYMENT_TARGET "$ENV{GT_IOS_DEPLOYMENT_TARGET}")
endif()
if(NOT GT_IOS_DEPLOYMENT_TARGET)
	set(GT_IOS_DEPLOYMENT_TARGET "13.0")
endif()
set(CMAKE_OSX_DEPLOYMENT_TARGET "${GT_IOS_DEPLOYMENT_TARGET}" CACHE STRING "En düşük iOS sürümü")

# Araç zinciri, try_compile alt projelerine de aynı ayarları taşısın.
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES GT_IOS_DEPLOYMENT_TARGET)

# Mac'teki Homebrew kütüphaneleri (libevent, libidn2, openssl@3 ...) macOS içindir; iOS hedefine asla bağlanmamalı.
set(CMAKE_IGNORE_PREFIX_PATH "/opt/homebrew;/usr/local")
