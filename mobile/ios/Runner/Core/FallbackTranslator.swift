// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// "Yedek motor cevap verdi" işareti ve cevap veren motorun kimliği. Çeviri aynı iş parçacığında eşzamanlı yapıldığından
/// işaret iş parçacığına bağlıdır: hat çeviriden önce sıfırlar, sonra okur; sarmalayıcı çevirmenler (sözlük, konuşmacı adı)
/// araya girse de bozulmaz.
enum FallbackSignal {
  private static let key = "gt.fallbackAnswered"
  private static let answeredKey = "gt.answeredBy"

  static func reset() {
    Thread.current.threadDictionary[key] = false
    Thread.current.threadDictionary[answeredKey] = nil
  }

  static func mark() { Thread.current.threadDictionary[key] = true }

  static var marked: Bool { (Thread.current.threadDictionary[key] as? Bool) ?? false }

  /// Zincir ya da yedek, cevabı veren motorun kimliğini ("deepl", "gemini", "google", "apple") bildirir.
  static func answered(by id: String) { Thread.current.threadDictionary[answeredKey] = id }

  static var answeredBy: String? { Thread.current.threadDictionary[answeredKey] as? String }
}

/// Önce [primary]; başarısız olursa [fallback]. Yedek cevap verirse [FallbackSignal] işaretlenir
/// (yedeğin çevirisi asıl motorun önbellek anahtarıyla saklanmasın diye). [fallbackId] verilirse cevap veren kimlik de yazılır.
final class FallbackTranslator: TextTranslator {
  private let primary: TextTranslator
  private let fallback: TextTranslator
  private let fallbackId: String?

  init(_ primary: TextTranslator, _ fallback: TextTranslator, fallbackId: String? = nil) {
    self.primary = primary
    self.fallback = fallback
    self.fallbackId = fallbackId
  }

  func translate(_ text: String) -> String? {
    if let result = primary.translate(text) { return result }
    guard let result = fallback.translate(text) else { return nil }
    FallbackSignal.mark()
    if let fallbackId { FallbackSignal.answered(by: fallbackId) }
    return result
  }
}
