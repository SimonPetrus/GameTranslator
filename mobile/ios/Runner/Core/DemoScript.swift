// SPDX-License-Identifier: AGPL-3.0-only
// Konsolsuz deneme (demo): gerçek çeviri hattından geçirilen örnek İngilizce altyazılar.
import Foundation

struct DemoScript {
  /// Satırlar arası bekleme (sn).
  static let intervalSeconds = 3.5

  /// Uydurma örnek satırlar; bazıları konuşmacı adıyla başlar (adlar çevrilmez, hat bunu işler).
  static let lines: [String] = [
    "The bridge is out. We have to find another way across.",
    "MIRA: Stay close and keep your voice down.",
    "I can hear something moving in the tunnel.",
    "KAEL: Do you remember what the old man told us?",
    "Check the lantern. We are running out of oil.",
    "MIRA: There is a light on the far side of the river.",
    "Nobody has come through here in years.",
    "KAEL: Then why are the doors still warm?",
    "Take this key and open the gate on the left.",
    "We should rest before the storm reaches the valley.",
    "MIRA: I never thought we would make it this far.",
    "Wait here. I will be back before sunrise.",
  ]

  private(set) var index = 0

  /// Sıradaki satır; sona gelince başa döner.
  mutating func next() -> String {
    let line = DemoScript.lines[index % DemoScript.lines.count]
    index += 1
    return line
  }
}

/// Son birkaç saniyedeki olay hızı (kare/sn): zaman damgaları girer, hız çıkar (saf; saat dışarıdan verilir).
struct RateMeter {
  let window: Double
  private var stamps: [Double] = []

  init(window: Double = 5) {
    self.window = max(1, window)
  }

  mutating func record(at time: Double) {
    stamps.append(time)
    trim(time)
  }

  /// [now] anındaki hız; pencereden eski olaylar sayılmaz. İlk saniyeden kısa süre geçtiyse 1 sn'ye bölünür.
  mutating func rate(at now: Double) -> Double {
    trim(now)
    guard let first = stamps.first else { return 0 }
    let span = max(1, min(window, now - first))
    return Double(stamps.count) / span
  }

  mutating func reset() { stamps.removeAll() }

  private mutating func trim(_ now: Double) {
    let limit = now - window
    if let drop = stamps.firstIndex(where: { $0 >= limit }) {
      if drop > 0 { stamps.removeFirst(drop) }
    } else {
      stamps.removeAll()
    }
  }
}
