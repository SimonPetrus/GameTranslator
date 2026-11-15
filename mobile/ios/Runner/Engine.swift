// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Uygulamanın çekirdeği (Android'deki Engine.kt'nin iOS karşılığı). Şimdilik altyazı sunucusu, durum ve ayarlar;
/// PS5 Remote Play oturumu, yazı okuma ve çeviri sonraki aşamada (libchiaki bağlanınca) eklenecek.
final class Engine {
  static let shared = Engine()

  private static let logLimit = 300

  /// idle, starting, waking, connecting, streaming, reconnecting, stopping, failed
  private(set) var phase = "idle"
  private(set) var message = ""
  private(set) var running = false
  private(set) var lastSource = ""
  private(set) var lastTranslation = ""
  private(set) var lastRead = ""
  private(set) var frameCount = 0
  private(set) var frameWidth = 0
  private(set) var frameHeight = 0
  private(set) var translatedCount = 0
  private(set) var packHits = 0
  private(set) var packGame = ""

  let server = SubtitleServer()

  /// Durum değişince ana iş parçacığında çağrılır.
  var onChanged: (([String: Any?]) -> Void)?

  /// Durum değişkenleri ve sunucu işleri bu kuyrukta sıralanır (Android'deki gt-control iş parçacığı).
  private let control = DispatchQueue(label: "gt.control")
  private let logLock = NSLock()
  private var logs: [String] = []
  private var notifyPending = false
  private var settings = Settings()

  private init() {
    server.onChanged = { [weak self] in self?.notifyChanged() }
    server.onLog = { [weak self] level, text in self?.log(level, text) }
    if let url = Bundle.main.url(forResource: "obs-overlay", withExtension: "html") {
      server.overlayPage = try? Data(contentsOf: url)
    }
  }

  // MARK: - Durum

  func state() -> [String: Any?] {
    [
      "phase": phase,
      "message": message,
      "running": running,
      "tvClients": server.connectedClients,
      "serverPort": server.boundPort,
      "localAddress": Network.localAddress(),
      "lastSource": lastSource,
      "lastTranslation": lastTranslation,
      "lastRead": lastRead,
      "frames": frameCount,
      "frameWidth": frameWidth,
      "frameHeight": frameHeight,
      "translated": translatedCount,
      "packHits": packHits,
      "packGame": packGame,
      // Arayüz "bu telefon desteklenmiyor" uyarısını göstermesin; başlatınca neyin eksik olduğu ayrıca söylenir.
      "nativeAvailable": true,
    ]
  }

  func logLines() -> [String] {
    logLock.lock(); defer { logLock.unlock() }
    return logs
  }

  func log(_ level: Int, _ text: String) {
    let line = "\(level == 0 ? "E" : level == 1 ? "W" : "I") \(text)"
    NSLog("GameTranslator %@", line)
    logLock.lock()
    logs.append(line)
    if logs.count > Self.logLimit { logs.removeFirst(logs.count - Self.logLimit) }
    logLock.unlock()
  }

  private func setPhase(_ value: String, _ text: String = "") {
    phase = value
    message = text
    log(value == "failed" ? 0 : 2, "durum: \(value) \(text)".trimmingCharacters(in: .whitespaces))
    notifyChanged()
  }

  /// Arayüze en çok ~10 Hz bildirim.
  private func notifyChanged() {
    DispatchQueue.main.async {
      if self.notifyPending { return }
      self.notifyPending = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        self.notifyPending = false
        self.onChanged?(self.state())
      }
    }
  }

  // MARK: - Başlat / durdur

  func start() {
    control.async {
      if self.running { return }
      let store = Store.shared
      self.settings = store.settings
      if store.accountId == nil || store.console == nil {
        return self.setPhase("failed", "Önce PSN girişi ve PS5 eşleştirmesi gerekli")
      }
      self.setPhase("failed", "PS5 bağlantısı iPhone sürümünde henüz hazır değil")
    }
  }

  func stop() {
    control.async {
      self.running = false
      self.server.clear()
      self.server.stop()
      self.setPhase("idle")
    }
  }

  /// Ayarlar değişti: görünüm hemen TV'ye gider.
  func applySettings() {
    control.async {
      let before = self.settings
      let now = Store.shared.settings
      self.settings = now
      if now.style != before.style, self.server.isStarted { self.server.sendStyle(now.style) }
    }
  }

  /// TV'de deneme altyazısı; sunucu kapalıysa açılır (TV telefonu bulsun diye açık kalır).
  func sendTestSubtitle() {
    control.async {
      self.settings = Store.shared.settings
      let wasStarted = self.server.isStarted
      if !wasStarted {
        self.server.start()
        self.log(2, "altyazı sunucusu: \(Network.localAddress() ?? "?"):\(SubtitleServer.defaultPort)")
      }
      self.server.sendStyle(self.settings.style)
      let r = self.settings.region
      self.server.sendSubtitle("Bu bir deneme altyazısıdır. Oyunun üstünde görüyor musunuz?", durationMs: 8000,
                               box: TextBox(left: 0.3, top: r.bottom - 0.1, right: 0.7, bottom: r.bottom - 0.03))
    }
  }

  // MARK: - PS5 (libchiaki bağlanınca)

  func discover(hosts: [String], timeoutMs: Int) -> [[String: Any]] { [] }

  func register(host: String, pin: Int) -> [String: Any] {
    if Store.shared.accountId == nil { return ["ok": false, "detail": "Önce PSN girişi gerekli"] }
    return ["ok": false, "detail": "PS5 eşleştirmesi iPhone sürümünde henüz hazır değil."]
  }

  func snapshot(width: Int) -> Data? { nil }
}

/// Ağ yardımcıları.
enum Network {
  /// Telefonun yerel ağdaki IPv4 adresi (Wi-Fi, yani en0, öncelikli).
  static func localAddress() -> String? {
    var fallback: String?
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0, let first = list else { return nil }
    defer { freeifaddrs(list) }
    for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let entry = pointer.pointee
      let flags = Int32(entry.ifa_flags)
      guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
            flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
      else { continue }
      let text = String(cString: host)
      let name = String(cString: entry.ifa_name)
      if name == "en0" { return text }
      // Hücresel (pdp_ip) adresi TV'ye ulaşmaz; yalnız başka yerel arayüz yoksa yedek.
      if fallback == nil, !name.hasPrefix("pdp_ip"), !name.hasPrefix("utun"), !name.hasPrefix("ipsec") { fallback = text }
    }
    return fallback
  }
}
