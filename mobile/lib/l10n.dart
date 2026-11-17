// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Arayüz dili (Türkçe / İngilizce). Metinler çağrı yerinde `L.t('Türkçe', 'English')` ile seçilir.
class L {
  /// 'tr' or 'en' (effective language).
  static final ValueNotifier<String> language = ValueNotifier<String>('tr');

  static bool get en => language.value == 'en';

  /// Returns the Turkish or English text for the current language.
  static String t(String tr, String en) => L.en ? en : tr;

  /// Applies the setting ('auto' | 'tr' | 'en'); 'auto' → Turkish if the device language is Turkish, else English.
  /// İngilizce arayüz yalnız iOS'ta var: Android'de ayar saklanmadığı için arayüz her zaman Türkçedir.
  static void apply(String setting) {
    final String effective;
    if (!Platform.isIOS) {
      effective = 'tr';
    } else if (setting == 'tr' || setting == 'en') {
      effective = setting;
    } else {
      effective = ui.PlatformDispatcher.instance.locale.languageCode == 'tr' ? 'tr' : 'en';
    }
    if (language.value != effective) language.value = effective;
  }
}
