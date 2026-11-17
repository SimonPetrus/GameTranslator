// SPDX-License-Identifier: AGPL-3.0-only
// Yeniden bağlanma bekleme süresi: üstel artış (saf, testlenebilir).
import Foundation

/// Bağlantı koptukça bekleme 2, 4, 8, 16, 30 sn (üst sınır 30) diye artar; akış 60 sn kesintisiz sürmüşse ya da
/// kullanıcı elle bağlanırsa başa döner. Saf bir tür: saat dışarıdan verilir (testlenebilir).
struct ReconnectPolicy: Equatable {
  /// Bekleme basamakları (sn); son basamak üst sınırdır.
  static let steps: [Double] = [2, 4, 8, 16, 30]
  /// "Konsol başka cihazda kullanımda" için en kısa bekleme.
  static let inUseMinimum: Double = 8
  /// Akış bu kadar sn kesintisiz sürdüyse sayaç sıfırlanır.
  static let stableAfter: Double = 60

  enum Reason: Equatable {
    case generic
    /// PS5 Remote Play'in başka cihazda kullanıldığını söyledi.
    case inUse
  }

  /// Şu ana kadarki ardışık başarısız deneme sayısı.
  private(set) var attempt = 0
  /// Akışın başladığı an (sn); akış yoksa nil.
  private var streamingSince: Double?

  init() {}

  /// Akış kuruldu ([now]: saniye cinsinden tek yönlü saat).
  mutating func streamStarted(at now: Double) { streamingSince = now }

  /// Elle bağlanma ya da yeni başlatma: sayaç sıfırlanır.
  mutating func reset() {
    attempt = 0
    streamingSince = nil
  }

  /// Sıradaki yeniden deneme beklemesi (sn). Akış yeterince uzun sürdüyse önce sayaç sıfırlanır.
  mutating func nextDelay(_ reason: Reason = .generic, at now: Double) -> Double {
    if let since = streamingSince {
      if now - since >= Self.stableAfter { attempt = 0 }
      streamingSince = nil
    }
    let base = Self.steps[min(attempt, Self.steps.count - 1)]
    attempt += 1
    return reason == .inUse ? max(base, Self.inUseMinimum) : base
  }
}
