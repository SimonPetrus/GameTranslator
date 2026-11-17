// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Parlak ya da gürültülü arka planda ekrandaki altyazı aynı kaldığı halde yazı tanıma titrer: bir sözcüğü atar,
/// birkaç harfi yanlış okur ya da kısa süre hiçbir şey okumaz. Bu yardımcı, böyle okumaları "satır değişmedi" saymak
/// ve titreme yaşanırken satırı biraz daha ekranda tutmak için kararı verir. Saf mantıktır; saat dışarıdan gelir.
struct FlickerHold {
  /// Yeni okuma gösterilen satıra bu oranda ya da daha çok benziyorsa aynı satırdır.
  static let SIMILAR_RATIO = 0.92
  /// Eksik okunmuş sayılması için yeni okumada en az bu kadar sözcük olmalı.
  static let MIN_WORDS = 3
  /// Gösterilen satırdan en çok bu kadar sözcük düşmüş okuma titreme sayılır.
  static let MAX_DROPPED_WORDS = 2
  /// Titreme sayılan olayların hatırlandığı süre.
  static let WINDOW_MS = 4000
  /// Pencerede bu kadar olay olduysa arka plan gürültülü sayılır.
  static let MIN_EVENTS = 2
  /// Gürültülü arka planda boş okuma satırı en çok bu kadar ekranda tutar.
  static let EXTENDED_CLEAR_MS = 4000
  /// Aynı kısalmış okuma bu kadar ms boyunca kararlı kalırsa titreme değil, yeni (daha kısa) satırdır.
  static let STABLE_SHORTER_MS = 1500
  private static let MAX_EVENTS = 16

  private var events: [Int64] = []
  private var shorterText = ""
  private var shorterSince: Int64 = 0

  /// Titreme sayılan [reading] hâlâ tutulmalı mı. Aynı okuma [STABLE_SHORTER_MS] boyunca kesintisiz sürerse
  /// false verir: gerçekten yeni bir satırdır ve geçmesine izin verilir.
  mutating func holdsFlicker(_ reading: String, at time: Int64) -> Bool {
    if shorterText.isEmpty || !TextMatch.isSimilar(reading, shorterText, 0.9) {
      shorterText = reading
      shorterSince = time
      return true
    }
    return time - shorterSince < Int64(FlickerHold.STABLE_SHORTER_MS)
  }

  /// Gösterilen satır tam okundu ya da yeni satır geldi: kısalmış okuma sayacı sıfırlanır.
  mutating func clearShorter() {
    shorterText = ""
    shorterSince = 0
  }

  /// [reading] (sadeleştirilmiş), gösterilen [shown] (sadeleştirilmiş) satırın titremiş okuması mı.
  /// Satırdan uzun (büyüyen) okuma hiçbir zaman titreme değildir; yeni satır olabilir.
  static func isFlicker(_ reading: String, _ shown: String) -> Bool {
    if reading.isEmpty || shown.isEmpty { return false }
    let x = reading.split(separator: " ").map(String.init)
    let y = shown.split(separator: " ").map(String.init)
    if x.count > y.count { return false }
    if TextMatch.isSimilar(reading, shown, SIMILAR_RATIO) { return true }
    guard x.count >= MIN_WORDS, y.count - x.count >= 1, y.count - x.count <= MAX_DROPPED_WORDS else { return false }
    return isSubsequence(x, of: y)
  }

  /// [part] sözcükleri, [whole] içinde sırayla (aralarda atlama olabilir) geçiyor mu.
  static func isSubsequence(_ part: [String], of whole: [String]) -> Bool {
    var index = 0
    for word in whole where index < part.count && word == part[index] { index += 1 }
    return index == part.count
  }

  /// Bir titreme olayı (benzer okuma ya da kısa boşluktan sonra aynı satırın dönüşü) kaydedilir.
  mutating func note(_ time: Int64) {
    events.append(time)
    if events.count > FlickerHold.MAX_EVENTS { events.removeFirst(events.count - FlickerHold.MAX_EVENTS) }
  }

  /// Son pencerede yeterince titreme yaşandı mı.
  func isNoisy(_ time: Int64) -> Bool {
    events.filter { time - $0 <= Int64(FlickerHold.WINDOW_MS) && time >= $0 }.count >= FlickerHold.MIN_EVENTS
  }

  /// Boş okumada satırı kaldırmadan önce beklenecek süre; gürültülü değilse [base] aynen döner.
  func clearDelay(base: Int, at time: Int64) -> Int {
    isNoisy(time) ? max(base, FlickerHold.EXTENDED_CLEAR_MS) : base
  }

  mutating func reset() {
    events.removeAll()
    clearShorter()
  }
}
