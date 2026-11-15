# SPDX-License-Identifier: AGPL-3.0-only
# chiaki-ng'nin lib/CMakeLists.txt dosyası Android ve Switch dışındaki her hedefte libevent ister
# (remote/holepunch.c, PSN üzerinden bağlantı) ve onu find_package(libevent) ile arar. iOS'ta sistem
# libevent'i yok; bu modül, aynı derlemede FetchContent ile kaynaktan derlenen statik event_core'u
# chiaki-ng'nin beklediği değişkenlerle (LIBEVENT_INCLUDE_DIRS, LIBEVENT_LIBRARIES) bildirir.
if(NOT TARGET event_core_static)
	set(libevent_FOUND FALSE)
	if(libevent_FIND_REQUIRED)
		message(FATAL_ERROR "libevent: event_core_static hedefi yok; mobile/ios-native/CMakeLists.txt libevent'i chiaki-lib'den önce eklemeli")
	endif()
	return()
endif()

set(libevent_FOUND TRUE)
set(LIBEVENT_FOUND TRUE)
set(LIBEVENT_INCLUDE_DIRS "${libevent_SOURCE_DIR}/include" "${libevent_BINARY_DIR}/include")
set(LIBEVENT_LIBRARIES event_core_static)
