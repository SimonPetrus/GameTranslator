// SPDX-License-Identifier: AGPL-3.0-only
// Gemini "429 çok istek" yanıtının çözümü (Google RetryInfo/QuotaFailure biçimi) ve model listesi.
import Foundation

/// Seçilebilir Gemini modelleri (windows/src/GameTranslator.Core/Resources/ai-models.json ile aynı kimlikler).
enum GeminiModels {
  static let defaultId = "gemini-3.5-flash-lite"
  static let all = ["gemini-3.5-flash-lite", "gemini-3.6-flash"]

  /// Bilinmeyen ya da boş değer varsayılana döner.
  static func resolve(_ id: String?) -> String {
    let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return all.contains(trimmed) ? trimmed : defaultId
  }
}

enum GeminiRateLimit {
  struct Decision: Equatable {
    /// Gemini'nin bu süre kullanılmaması önerilir (sn).
    var seconds: Double
    /// Günlük hak bitti mi.
    var daily: Bool
    /// Yanıttaki RetryInfo.retryDelay (sn), yoksa nil.
    var retryDelay: Double?
  }

  static let defaultPause: Double = 60
  static let minPause: Double = 5
  static let maxPause: Double = 300
  static let margin: Double = 2
  static let dailyPause: Double = 3600

  /// 429 yanıt gövdesinden bekleme kararı. Gövde okunamazsa 60 sn (eski davranış).
  static func decide(_ body: Data?) -> Decision {
    var retry: Double?
    var daily = false
    if let body, let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
       let error = root["error"] as? [String: Any] {
      if let message = (error["message"] as? String)?.lowercased(), message.contains("per day") || message.contains("daily") {
        daily = true
      }
      for detail in (error["details"] as? [[String: Any]]) ?? [] {
        let type = detail["@type"] as? String ?? ""
        if type.hasSuffix("RetryInfo"), let text = detail["retryDelay"] as? String { retry = parseDuration(text) }
        if type.hasSuffix("QuotaFailure") {
          for violation in (detail["violations"] as? [[String: Any]]) ?? [] {
            let id = ((violation["quotaId"] as? String) ?? "").lowercased()
            let metric = ((violation["quotaMetric"] as? String) ?? "").lowercased()
            if id.contains("perday") || id.contains("per_day") || metric.contains("per_day") || metric.contains("perday") { daily = true }
          }
        }
      }
    }
    if daily { return Decision(seconds: dailyPause, daily: true, retryDelay: retry) }
    let seconds = min(max((retry ?? defaultPause) + (retry == nil ? 0 : margin), minPause), maxPause)
    return Decision(seconds: seconds, daily: false, retryDelay: retry)
  }

  /// "37s", "0.847655010s", "1m30s", "500ms" ya da düz sayı (sn).
  static func parseDuration(_ text: String) -> Double? {
    let t = text.trimmingCharacters(in: .whitespaces).lowercased()
    if t.isEmpty { return nil }
    if let plain = Double(t) { return plain.isFinite && plain >= 0 ? plain : nil }
    var total = 0.0
    var number = ""
    var unit = ""
    var matched = false
    func flush() -> Bool {
      guard let value = Double(number) else { return false }
      switch unit {
      case "h": total += value * 3600
      case "m": total += value * 60
      case "s": total += value
      case "ms": total += value / 1000
      default: return false
      }
      number = ""; unit = ""; matched = true
      return true
    }
    for ch in t {
      if ch.isNumber || ch == "." {
        if !unit.isEmpty { if !flush() { return nil } }
        number.append(ch)
      } else if ch.isLetter {
        unit.append(ch)
      } else { return nil }
    }
    if !number.isEmpty || !unit.isEmpty { if !flush() { return nil } }
    return matched && total.isFinite ? total : nil
  }
}
