// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Okuyucunun takılıp takılmadığını anlar: zaman damgaları girer, karar çıkar (saf; saat, iş parçacığı ve Vision yok).
/// Çağıran, kare gelişini, okumanın başlayıp bitişini ve karenin özetini bildirir; [check] takılma nedenini ya da nil verir.
struct StuckDetector {
  enum Reason: Equatable {
    /// Okuma bayrağı (busy) çok uzun süredir açık.
    case busyTooLong
    /// Kareler geliyor ama uzun süredir hiçbir okuma tamamlanmadı.
    case noResult
    /// Akış canlı görünürken aynı kare özeti durmadan tekrarlanıyor.
    case frozenFrame
  }

  /// Okuma bayrağı bu kadar ms açık kalırsa takılmıştır (normal okuma yüzlerce ms sürer).
  static let BUSY_MAX_MS: Int64 = 8000
  /// Kareler gelirken bu kadar ms hiçbir okuma bitmezse takılmıştır.
  static let NO_RESULT_MS: Int64 = 10000
  /// Aynı kare özeti en az bu kadar ms ve [SAME_FRAME_MIN_COUNT] kare boyunca tekrarlanırsa akış donmuştur.
  static let SAME_FRAME_MS: Int64 = 20000
  static let SAME_FRAME_MIN_COUNT = 60
  /// Son kare bundan eskiyse akış canlı sayılmaz (kareler durduysa takılma değil, bağlantı sorunudur).
  static let FRAME_LIVE_MS: Int64 = 2000
  /// Bir kurtarmadan sonra en az bu kadar ms yeni kurtarma yapılmaz.
  static let COOLDOWN_MS: Int64 = 30000

  private var busySince: Int64?
  private var lastFrameAt: Int64?
  private var resultBaseline: Int64?
  private var framesSinceResult = 0
  private var lastHash: Int?
  private var sameSince: Int64 = 0
  private var sameCount = 0
  private var lastRecoveryAt: Int64?

  /// Yeni kare geldi; [hash] karenin özeti (alınamadıysa nil).
  mutating func frame(at time: Int64, hash: Int?) {
    lastFrameAt = time
    if resultBaseline == nil { resultBaseline = time }
    framesSinceResult += 1
    if let hash {
      if hash == lastHash {
        sameCount += 1
      } else {
        lastHash = hash
        sameSince = time
        sameCount = 1
      }
    }
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
    } else if let last = lastFrameAt, time - last <= StuckDetector.FRAME_LIVE_MS {
      if let base = resultBaseline, framesSinceResult > 0, time - base >= StuckDetector.NO_RESULT_MS {
        reason = .noResult
      } else if sameCount >= StuckDetector.SAME_FRAME_MIN_COUNT, time - sameSince >= StuckDetector.SAME_FRAME_MS {
        reason = .frozenFrame
      }
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
    lastHash = nil
    sameCount = 0
    sameSince = time
  }

  /// Kare baytlarından ucuz bir özet: dağılmış ~[samples] baytın FNV-1a'sı.
  static func hash(of bytes: UnsafeRawBufferPointer, samples: Int = 2048) -> Int? {
    let count = bytes.count
    guard count > 0, samples > 0 else { return nil }
    let step = max(count / samples, 1)
    var value: UInt64 = 0xcbf29ce484222325
    var index = 0
    while index < count {
      value = (value ^ UInt64(bytes[index])) &* 0x100000001b3
      index += step
    }
    return Int(truncatingIfNeeded: value)
  }
}
