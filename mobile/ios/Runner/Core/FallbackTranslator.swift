// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// "Yedek motor cevap verdi" işareti. Çeviri aynı iş parçacığında eşzamanlı yapıldığından işaret iş parçacığına bağlıdır:
/// hat çeviriden önce sıfırlar, sonra okur; sarmalayıcı çevirmenler (sözlük, konuşmacı adı) araya girse de bozulmaz.
enum FallbackSignal {
  private static let key = "gt.fallbackAnswered"

  static func reset() { Thread.current.threadDictionary[key] = false }

  static func mark() { Thread.current.threadDictionary[key] = true }

  static var marked: Bool { (Thread.current.threadDictionary[key] as? Bool) ?? false }
}

/// Önce [primary]; başarısız olursa [fallback]. Yedek cevap verirse [FallbackSignal] işaretlenir
/// (yedeğin çevirisi asıl motorun önbellek anahtarıyla saklanmasın diye).
final class FallbackTranslator: TextTranslator {
  private let primary: TextTranslator
  private let fallback: TextTranslator

  init(_ primary: TextTranslator, _ fallback: TextTranslator) {
    self.primary = primary
    self.fallback = fallback
  }

  func translate(_ text: String) -> String? {
    if let result = primary.translate(text) { return result }
    guard let result = fallback.translate(text) else { return nil }
    FallbackSignal.mark()
    return result
  }
}
