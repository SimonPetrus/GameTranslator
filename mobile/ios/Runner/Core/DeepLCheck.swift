// SPDX-License-Identifier: AGPL-3.0-only
// Ayarlardaki DeepL "Kaydet ve dene" sonucunun saf mantığı (yalnız Foundation): `GET /v2/usage` yanıtının durum kodu ve
// gövdesinden (başarılı mı, gösterilecek metin) üretilir. Ağ çağrısı Runner tarafındadır; anahtar hiçbir metne girmez.
import Foundation

enum DeepLCheck {
  static var emptyKey: (Bool, String) { (false, Lang.t("Önce anahtarı yapıştır.", "Paste the key first.")) }

  static var unreachable: (Bool, String) {
    (false, Lang.t("DeepL'e ulaşılamadı. İnternet bağlantını kontrol et.", "Could not reach DeepL. Check your internet connection."))
  }

  /// [status]: HTTP durum kodu; [body]: yanıt gövdesi (yoksa nil).
  static func outcome(status: Int, body: Data?) -> (Bool, String) {
    switch status {
    case 200:
      if let usage = usage(body) {
        let used = grouped(usage.used), limit = grouped(usage.limit)
        return (true, Lang.t("Anahtar çalışıyor. Bu ay \(used) / \(limit) karakter kullanıldı.",
                             "The key works. \(used) / \(limit) characters used this month."))
      }
      return (true, Lang.t("Anahtar çalışıyor.", "The key works."))
    case 403:
      return (false, Lang.t("Anahtar kabul edilmedi. Anahtarı eksiksiz kopyaladığından emin ol.",
                            "The key was not accepted. Make sure you copied the whole key."))
    case 456:
      return (false, Lang.t("Anahtar geçerli ama bu ayki karakter kotası dolmuş; kota yenilenene kadar DeepL çeviri yapmaz.",
                            "The key is valid but this month's character quota is used up; DeepL will not translate until it renews."))
    case 429:
      return (false, Lang.t("DeepL çok fazla istek aldı. Biraz sonra yeniden dene.", "DeepL received too many requests. Try again shortly."))
    default:
      return (false, Lang.t("DeepL hata verdi (HTTP \(status)). Biraz sonra yeniden dene.", "DeepL returned an error (HTTP \(status)). Try again shortly."))
    }
  }

  /// Gövdedeki `character_count` ve `character_limit`; biri yoksa ya da JSON bozuksa nil.
  private static func usage(_ body: Data?) -> (used: Int, limit: Int)? {
    guard let body, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
          let used = (json["character_count"] as? NSNumber)?.intValue,
          let limit = (json["character_limit"] as? NSNumber)?.intValue, limit > 0, used >= 0 else { return nil }
    return (used, limit)
  }

  /// Binlik ayraçlı sayı: Türkçede "12.345", İngilizcede "12,345" (yerel ayardan bağımsız).
  static func grouped(_ number: Int) -> String {
    let separator = Lang.t(".", ",")
    let digits = Array(String(number))
    var out = ""
    for (index, digit) in digits.enumerated() {
      if index > 0 && (digits.count - index) % 3 == 0 { out += separator }
      out.append(digit)
    }
    return out
  }
}
