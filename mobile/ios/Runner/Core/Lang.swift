// SPDX-License-Identifier: AGPL-3.0-only
// Yerel (Swift) tarafın kullanıcıya görünen metinleri için Türkçe/İngilizce seçimi. Destek günlükleri her zaman Türkçe kalır;
// bu yardımcı yalnız Flutter arayüzüne giden metinlerde kullanılır. Saf mantık (yalnız Foundation); dil kaynağı değiştirilebilir.
import Foundation

enum Lang {
  /// Ayardaki "uiLanguage" değerleri.
  static let auto = "auto", turkish = "tr", english = "en"

  /// Geçerli arayüz dilini verir: "tr" ya da "en". Çalışma anında okunur (ayar değişince yeniden başlatma gerekmez).
  /// Varsayılan Türkçe; uygulama açılışta ayardan okuyan bir işlev atar (testler değiştirmedikçe Türkçe kalır).
  nonisolated(unsafe) static var provider: () -> String = { Lang.turkish }

  /// Türkçe ya da İngilizce metin; dil [provider]'dan okunur.
  static func t(_ tr: String, _ en: String) -> String { provider() == english ? en : tr }

  /// Ayar değerini ("auto" | "tr" | "en"; bozuksa "auto") normalleştirir.
  static func normalize(_ setting: String) -> String {
    let value = setting.trimmingCharacters(in: .whitespaces).lowercased()
    return value == turkish || value == english ? value : auto
  }

  /// Etkin dil: "tr"/"en" ayarı olduğu gibi; "auto" için cihazın birinci tercih edilen dili Türkçeyse Türkçe, değilse İngilizce.
  /// [preferred]: Locale.preferredLanguages biçiminde ("tr-TR", "en-GB"); boşsa İngilizce.
  static func effective(setting: String, preferred: [String]) -> String {
    switch normalize(setting) {
    case turkish: return turkish
    case english: return english
    default:
      guard let first = preferred.first?.lowercased() else { return english }
      return first == "tr" || first.hasPrefix("tr-") || first.hasPrefix("tr_") ? turkish : english
    }
  }
}
