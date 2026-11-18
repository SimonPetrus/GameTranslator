// SPDX-License-Identifier: AGPL-3.0-only
// Kota dolunca motor değiştirme: seçili motor → anahtarı dolu diğer motor → Google. Yalnız Foundation; saat dışarıdan verilir.
import Foundation

/// Bir motorun bekleme nedeni (sistem durumunda gösterilir).
enum EnginePauseReason: String {
  /// Kota (aylık ya da günlük) doldu.
  case quota
  /// Anahtar reddedildi.
  case key
  /// Kısa süreli "çok istek".
  case busy
  /// Art arda ağ hatası/zaman aşımı (bağlantı sorunu).
  case connection
}

struct EnginePause: Equatable {
  var seconds: Double
  var reason: EnginePauseReason
}

/// Bir çeviri denemesinin sonucu. `failed`: boş/okunamayan cevap, destek yok vb.; motor beklemeye alınmaz, yalnız o satır
/// sonraki motora düşer. `unreachable`: ağ hatası ya da zaman aşımı; tek başına bekleme yaratmaz ama art arda
/// [EngineCooldowns.connectionFailureLimit] kez olursa motor kısa süre beklemeye alınır. `pause`: motor bu süre hiç denenmez.
enum ChainOutcome: Equatable {
  case translated(String)
  case failed
  case unreachable
  case pause(EnginePause)

  var text: String? {
    if case .translated(let value) = self { return value }
    return nil
  }
}

/// Zincirdeki bir motor.
protocol ChainMember {
  var id: String { get }
  func attempt(_ text: String) -> ChainOutcome
}

/// Durum bilgisi vermeyen çevirmeni (Google) zincire sokar: cevap yoksa `failed`.
struct PlainChainMember: ChainMember {
  let id: String
  let translator: TextTranslator

  func attempt(_ text: String) -> ChainOutcome {
    translator.translate(text).map { .translated($0) } ?? .failed
  }
}

/// Durum kodundan bekleme süresi.
enum EnginePauseRule {
  static let longPause: Double = 30 * 60
  static let shortPause: Double = 60
  static let geminiKeyPause: Double = 300

  /// DeepL: 456 aylık kota dolu, 403 anahtar reddedildi (ikisi 30 dk), 429 çok istek (60 sn). Başka kod: bekleme yok.
  static func deepL(status: Int) -> EnginePause? {
    switch status {
    case 456: return EnginePause(seconds: longPause, reason: .quota)
    case 403: return EnginePause(seconds: longPause, reason: .key)
    case 429: return EnginePause(seconds: shortPause, reason: .busy)
    default: return nil
    }
  }

  /// Gemini 429: GeminiRateLimit'in verdiği süre; günlük hak bittiyse 30 dk.
  static func gemini(_ decision: GeminiRateLimit.Decision) -> EnginePause {
    decision.daily ? EnginePause(seconds: longPause, reason: .quota) : EnginePause(seconds: decision.seconds, reason: .busy)
  }

  /// Gemini 400/401/403: anahtar kabul edilmedi.
  static var geminiKeyRejected: EnginePause { EnginePause(seconds: geminiKeyPause, reason: .key) }
}

/// Zincir sırası.
enum FailoverOrder {
  /// Google'dan önce gelen anahtarlı motorlar. Boş dönerse zincir kurulmaz (bugünkü davranış). Seçili motorun kendi anahtarı
  /// boşsa (fiilen Google çalışır) ya da seçili motor deepl/gemini değilse boştur; böylece önbellek anahtarındaki motor
  /// kimliği (Engine.effectiveEngine) her zaman zincirin ilk motoruyla aynı kalır.
  /// Gemini yalnız hedef Türkçe iken kullanılır (istemi Türkçe çeviri içindir).
  static func keyed(engine: String, deepLKey: Bool, geminiKey: Bool, targetIsTurkish: Bool, failover: Bool) -> [String] {
    guard failover else { return [] }
    let geminiUsable = geminiKey && targetIsTurkish
    switch engine {
    case "deepl": return deepLKey ? (geminiUsable ? ["deepl", "gemini"] : ["deepl"]) : []
    case "gemini": return geminiUsable ? (deepLKey ? ["gemini", "deepl"] : ["gemini"]) : []
    default: return []
    }
  }
}

/// Motor başına bellekteki bekleme tablosu ve sistem durumu için son cevap veren motor. Kilitle korunur.
final class EngineCooldowns: @unchecked Sendable {
  struct Paused: Equatable {
    var engine: String
    var seconds: Int
    var reason: EnginePauseReason
  }

  struct Snapshot: Equatable {
    var active: Bool
    /// Son cevap veren motor; henüz yoksa sıradaki ilk bekleyen olmayan motor.
    var current: String
    var paused: [Paused]
  }

  static let shared = EngineCooldowns()

  private let lock = NSLock()
  private var until: [String: Date] = [:]
  private var reasons: [String: EnginePauseReason] = [:]
  private var order: [String] = []
  private var lastAnswered = ""
  private var failures: [String: Int] = [:]

  /// Art arda bu kadar ağ hatası/zaman aşımında motor beklemeye alınır; bekleme süresi (sn).
  static let connectionFailureLimit = 2
  static let connectionPause: Double = 15

  /// Yeni zincir kurulurken çağrılır: tablo sıfırlanır. Boş sıra: zincir yok.
  func configure(order: [String]) {
    lock.lock(); defer { lock.unlock() }
    self.order = order
    until = [:]
    reasons = [:]
    failures = [:]
    lastAnswered = ""
  }

  func isPaused(_ engine: String, now: Date) -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard let end = until[engine] else { return false }
    return now < end
  }

  /// Bekleme yalnız uzar, kısalmaz (kısa bir yerel bekleme uzun bir kota beklemesini silmesin).
  func pause(_ engine: String, _ pause: EnginePause, now: Date) {
    lock.lock(); defer { lock.unlock() }
    let end = now.addingTimeInterval(max(0, pause.seconds))
    if let old = until[engine], old > end, old > now { return }
    until[engine] = end
    reasons[engine] = pause.reason
  }

  /// Başarılı cevap: art arda hata sayacı sıfırlanır.
  func noteAnswer(_ engine: String) {
    lock.lock(); defer { lock.unlock() }
    lastAnswered = engine
    failures[engine] = 0
  }

  /// Ağ hatası/zaman aşımı: ikincisi art arda gelirse motor kısa süre beklemeye alınır (sayaç sıfırlanır). Bekleme alındıysa true.
  @discardableResult
  func noteUnreachable(_ engine: String, now: Date) -> Bool {
    lock.lock(); defer { lock.unlock() }
    let count = (failures[engine] ?? 0) + 1
    guard count >= Self.connectionFailureLimit else {
      failures[engine] = count
      return false
    }
    failures[engine] = 0
    let end = now.addingTimeInterval(Self.connectionPause)
    if let old = until[engine], old > end { return true }
    until[engine] = end
    reasons[engine] = .connection
    return true
  }

  func snapshot(now: Date) -> Snapshot {
    lock.lock(); defer { lock.unlock() }
    guard !order.isEmpty else { return Snapshot(active: false, current: "", paused: []) }
    var paused: [Paused] = []
    for engine in order {
      if let end = until[engine], end > now {
        paused.append(Paused(engine: engine, seconds: Int(end.timeIntervalSince(now).rounded(.up)), reason: reasons[engine] ?? .busy))
      }
    }
    let current = !lastAnswered.isEmpty ? lastAnswered : (order.first { engine in !paused.contains { $0.engine == engine } } ?? "google")
    return Snapshot(active: true, current: current, paused: paused)
  }
}

/// Üyeleri sırayla dener; beklemedeki üye atlanır (istek bile atılmaz). Cevap veren üyenin kimliği [FallbackSignal]'e yazılır;
/// ilk üyeden sonrakiler cevap verirse "yedek cevap verdi" işaretlenir (önbellek zehirlenmesin: yalnız ilk üyenin çevirisi
/// seçili motorun anahtarıyla saklanır, diğerleri hiç saklanmaz).
final class FailoverTranslator: TextTranslator {
  private let members: [ChainMember]
  private let cooldowns: EngineCooldowns
  private let clock: () -> Date

  init(members: [ChainMember], cooldowns: EngineCooldowns, clock: @escaping () -> Date = { Date() }) {
    self.members = members
    self.cooldowns = cooldowns
    self.clock = clock
  }

  func translate(_ text: String) -> String? {
    for (index, member) in members.enumerated() {
      if cooldowns.isPaused(member.id, now: clock()) { continue }
      switch member.attempt(text) {
      case .translated(let result):
        cooldowns.noteAnswer(member.id)
        FallbackSignal.answered(by: member.id)
        if index > 0 { FallbackSignal.mark() }
        return result
      case .pause(let pause):
        cooldowns.pause(member.id, pause, now: clock())
      case .unreachable:
        // Son üye (Google) beklemeye alınmaz: başka seçenek kalmaz.
        if index < members.count - 1 { cooldowns.noteUnreachable(member.id, now: clock()) }
      case .failed:
        continue
      }
    }
    return nil
  }
}
