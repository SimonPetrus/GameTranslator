// SPDX-License-Identifier: AGPL-3.0-only
// Arayüzün sunduğu 27 dil kodunun çeviri motorlarına göre eşlemesi.
import Foundation

enum LanguageCodes {
  /// Arayüzdeki hedef dil kodları.
  static let supported = ["tr", "en", "de", "fr", "es", "it", "pt", "ru", "ar", "ja", "zh", "ko", "pl", "nl", "id", "hi",
                          "fa", "uk", "el", "hu", "ro", "cs", "sv", "th", "vi", "he", "az"]

  /// Google gtx: Çince ve İbranice için özel kodlar ("iw" eski ama her uçta çalışan İbranice kodu).
  static func google(_ code: String) -> String {
    switch code.lowercased() {
    case "zh": return "zh-CN"
    case "he": return "iw"
    default: return code.lowercased()
    }
  }

  /// DeepL hedef dilleri (arayüzdeki 27'den desteklenen alt küme). Desteklenmeyen: nil (Google'a düşülür).
  static func deepLTarget(_ code: String) -> String? {
    switch code.lowercased() {
    case "en": return "EN-US"
    case "pt": return "PT-BR"
    case "zh": return "ZH-HANS"
    case "tr", "de", "fr", "es", "it", "ru", "ar", "ja", "ko", "pl", "nl", "id", "uk", "el", "hu", "ro", "cs", "sv":
      return code.uppercased()
    default: return nil // hi, fa, th, vi, he, az
    }
  }

  /// DeepL kaynak dilleri (varyantsız kodlar).
  static func deepLSource(_ code: String) -> String? {
    switch code.lowercased() {
    case "tr", "en", "de", "fr", "es", "it", "pt", "ru", "ar", "ja", "zh", "ko", "pl", "nl", "id", "uk", "el", "hu", "ro", "cs", "sv":
      return code.uppercased()
    default: return nil
    }
  }

  /// Vision (VNRecognizeTextRequest) için aday tanımlayıcılar, öncelik sırasıyla. Vision "en-US" gibi bölgeli kimlikler
  /// bildirir; hangi sürümde hangisinin olduğu çalışma anında `supportedRecognitionLanguages()` ile sorulur.
  static func visionCandidates(_ code: String) -> [String] {
    switch code.lowercased() {
    case "en": return ["en-US"]
    case "ja": return ["ja-JP"]
    case "zh": return ["zh-Hans"]
    case "ko": return ["ko-KR"]
    case "de": return ["de-DE"]
    case "fr": return ["fr-FR"]
    case "es": return ["es-ES"]
    case "it": return ["it-IT"]
    case "pt": return ["pt-BR", "pt-PT"]
    case "ru": return ["ru-RU"]
    case "uk": return ["uk-UA"]
    case "ar": return ["ar-SA"]
    case "th": return ["th-TH"]
    case "vi": return ["vi-VT", "vi-VN"]
    case "tr": return ["tr-TR"]
    default: return [code]
    }
  }

  /// [supported] listesindeki Vision kimliği (listedeki yazımıyla); dil desteklenmiyorsa nil.
  /// Önce adaylar, sonra aynı ana dil koduyla başlayan ilk kimlik ("vi-VT" gibi beklenmedik bölgeler) aranır.
  static func visionLanguage(_ code: String, supported: [String]) -> String? {
    for candidate in visionCandidates(code) {
      if let hit = supported.first(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) { return hit }
    }
    let base = code.lowercased()
    return supported.first { $0.lowercased() == base || $0.lowercased().hasPrefix(base + "-") }
  }

  /// Apple Translation (Locale.Language kimliği).
  static func apple(_ code: String) -> String {
    switch code.lowercased() {
    case "zh": return "zh-Hans"
    case "he": return "he"
    default: return code.lowercased()
    }
  }
}
