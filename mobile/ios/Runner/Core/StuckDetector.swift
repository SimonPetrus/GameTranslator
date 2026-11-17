// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Okuyucunun takılıp takılmadığını anlar: zaman damgaları girer, karar çıkar (saf; saat, iş parçacığı ve Vision yok).
/// Çağıran, kare gelişini ve okumanın başlayıp bitişini bildirir; [check] takılma nedenini ya da nil verir.
struct StuckDetector {
  enum Reason: Equatable {
    /// Okuma bayrağı (busy) çok uzun süredir açık.
    case busyTooLong
    /// Kareler geliyor ama uzun süredir hiçbir okuma tamamlanmadı.
    case noResult
  }

  /// Okuma bayrağı bu kadar ms açık kalırsa takılmıştır (normal okuma yüzlerce ms sürer).
  static let BUSY_MAX_MS: Int64 = 8000
  /// Kareler gelirken bu kadar ms hiçbir okuma bitmezse takılmıştır.
  static let NO_RESULT_MS: Int64 = 10000
  /// Son kare bundan eskiyse akış canlı sayılmaz (kareler durduysa takılma değil, bağlantı sorunudur).
  static let FRAME_LIVE_MS: Int64 = 2000
  /// Bir kurtarmadan sonra en az bu kadar ms yeni kurtarma yapılmaz.
  static let COOLDOWN_MS: Int64 = 30000

  private var busySince: Int64?
  private var lastFrameAt: Int64?
  private var resultBaseline: Int64?
  private var framesSinceResult = 0
  private var lastRecoveryAt: Int64?

  /// Yeni kare geldi.
  mutating func frame(at time: Int64) {
    // Kare akışında uzun boşluk (yeniden bağlanma, duraklatma) takılma değildir; sayaç yeniden başlar.
    if let last = lastFrameAt, time - last > StuckDetector.FRAME_LIVE_MS {
      resultBaseline = time
      framesSinceResult = 0
    }
    lastFrameAt = time
    if resultBaseline == nil { resultBaseline = time }
    framesSinceResult += 1
  }

  mutating func readStarted(at time: Int64) { busySince = time }

  /// Okuma bitti (sonuç ya da hata fark etmez; takılmadı).
  mutating func readFinished(at time: Int64) {
    busySince = nil
    resultBaseline = time
    framesSinceResult = 0
  }

  /// Takılma varsa nedeni verir ve kendini sıfırlar; kurtarma bekleme süresinde ise nil.
  mutating func check(at time: Int64) -> Reason? {
    if let last = lastRecoveryAt, time - last < StuckDetector.COOLDOWN_MS { return nil }
    var reason: Reason?
    if let since = busySince, time - since >= StuckDetector.BUSY_MAX_MS {
      reason = .busyTooLong
    } else if let last = lastFrameAt, time - last <= StuckDetector.FRAME_LIVE_MS,
              let base = resultBaseline, framesSinceResult > 0, time - base >= StuckDetector.NO_RESULT_MS {
      reason = .noResult
    }
    guard let found = reason else { return nil }
    reset(at: time)
    lastRecoveryAt = time
    return found
  }

  /// Kurtarma ya da ayar değişimi sonrası izlenen durum temizlenir (bekleme süresi korunur).
  mutating func reset(at time: Int64) {
    busySince = nil
    resultBaseline = time
    framesSinceResult = 0
  }
}
