// SPDX-License-Identifier: AGPL-3.0-only
// Gösterilen altyazıların geçmişi: son N satır bellekte ve diskte (yalnız Foundation; testlerde bellek deposuyla).
import Foundation

/// Geçmişte bir satır: gösterildiği an (ms), okunan metin, çeviri ve çeviriyi yapan kaynak.
struct HistoryEntry: Equatable {
  var at: Int
  var source: String
  var text: String
  /// "pack", "stock", "cache", "google", "deepl", "gemini", "apple" ya da bilinmiyorsa "".
  var engine: String

  func toJson() -> [String: Any] {
    ["at": at, "source": source, "text": text, "engine": engine]
  }

  static func fromJson(_ value: Any?) -> HistoryEntry? {
    guard let map = value as? [String: Any], let text = map["text"] as? String, !text.isEmpty else { return nil }
    let at = (map["at"] as? NSNumber)?.intValue ?? 0
    return HistoryEntry(at: at, source: map["source"] as? String ?? "", text: text, engine: map["engine"] as? String ?? "")
  }
}

/// Sabit boyutlu halka: dolunca en eski satır atılır; art arda aynı çeviri bir kez tutulur.
struct HistoryRing {
  static let defaultCapacity = 200

  let capacity: Int
  private(set) var oldestFirst: [HistoryEntry] = []

  init(capacity: Int = HistoryRing.defaultCapacity) {
    self.capacity = max(1, capacity)
  }

  var count: Int { oldestFirst.count }

  /// Eklendiyse true; son satırla aynı çeviri ise eklenmez.
  @discardableResult
  mutating func add(_ entry: HistoryEntry) -> Bool {
    if let last = oldestFirst.last, last.text == entry.text { return false }
    oldestFirst.append(entry)
    if oldestFirst.count > capacity { oldestFirst.removeFirst(oldestFirst.count - capacity) }
    return true
  }

  /// Diskten okunan satırları yükler (en eskiden en yeniye); fazlası baştan atılır.
  mutating func load(_ entries: [HistoryEntry]) {
    oldestFirst = Array(entries.suffix(capacity))
  }

  mutating func clear() { oldestFirst.removeAll() }

  var newestFirst: [HistoryEntry] { Array(oldestFirst.reversed()) }
}

/// Dosya biçimi: {"version":1,"entries":[...]} (en eskiden en yeniye). Bozuk dosya boş geçmiş sayılır.
enum HistoryCodec {
  static let version = 1

  static func encode(_ entries: [HistoryEntry]) -> Data? {
    let root: [String: Any] = ["version": version, "entries": entries.map { $0.toJson() }]
    return try? JSONSerialization.data(withJSONObject: root)
  }

  static func decode(_ data: Data?) -> [HistoryEntry] {
    guard let data = data,
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          (root["version"] as? NSNumber)?.intValue == version,
          let rows = root["entries"] as? [Any] else { return [] }
    return rows.compactMap { HistoryEntry.fromJson($0) }
  }
}

/// Kalıcı altyazı geçmişi: bellekteki halka + gecikmeli (debounce) disk yazımı. Dosya ilk kullanımda okunur.
final class SubtitleHistoryLog: @unchecked Sendable {
  /// Bir satırın tutulacağı en uzun uzunluk (karakter); dosya şişmesin.
  static let maxTextLength = 1000

  private let storage: TranslationCacheStorage
  private let saveDelay: TimeInterval
  private let now: () -> Int
  private let queue: DispatchQueue
  private let lock = NSLock()
  private let writeLock = NSLock()
  private var ring: HistoryRing
  private var loaded = false
  private var dirty = false
  private var saveScheduled = false

  init(storage: TranslationCacheStorage, capacity: Int = HistoryRing.defaultCapacity, saveDelay: TimeInterval = 2,
       now: @escaping () -> Int = { Int(Date().timeIntervalSince1970 * 1000) },
       queue: DispatchQueue = DispatchQueue(label: "gt.history", qos: .utility)) {
    self.storage = storage
    self.ring = HistoryRing(capacity: capacity)
    self.saveDelay = saveDelay
    self.now = now
    self.queue = queue
  }

  var count: Int {
    lock.lock(); defer { lock.unlock() }
    loadIfNeeded()
    return ring.count
  }

  /// Gösterilen bir satırı kaydeder (boş çeviri ve art arda aynı çeviri atlanır).
  func record(source: String, text: String, engine: String) {
    let clean = String(text.prefix(Self.maxTextLength))
    if clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
    lock.lock()
    loadIfNeeded()
    let added = ring.add(HistoryEntry(at: now(), source: String(source.prefix(Self.maxTextLength)), text: clean, engine: engine))
    if added { dirty = true }
    let schedule = added && takeSaveSlot()
    lock.unlock()
    if schedule { scheduleSave() }
  }

  /// En yeniden en eskiye, kanal üzerinden gönderilebilir biçimde.
  func list() -> [[String: Any]] {
    lock.lock(); defer { lock.unlock() }
    loadIfNeeded()
    return ring.newestFirst.map { $0.toJson() }
  }

  /// Geçmişi siler; boş dosya hemen yazılır.
  func clear() {
    lock.lock()
    loadIfNeeded()
    ring.clear()
    dirty = true
    lock.unlock()
    flush()
  }

  /// Bekleyen değişiklikleri hemen yazar (uygulama arka plana giderken ve testlerde).
  func flush() {
    writeLock.lock(); defer { writeLock.unlock() }
    lock.lock()
    saveScheduled = false
    guard loaded, dirty else { lock.unlock(); return }
    dirty = false
    let entries = ring.oldestFirst
    lock.unlock()
    if let data = HistoryCodec.encode(entries) { storage.write(data) }
  }

  // MARK: - İç

  private func takeSaveSlot() -> Bool {
    if saveScheduled { return false }
    saveScheduled = true
    return true
  }

  private func scheduleSave() { queue.asyncAfter(deadline: .now() + saveDelay) { [self] in flush() } }

  /// Kilit altında çağrılır.
  private func loadIfNeeded() {
    if loaded { return }
    loaded = true
    ring.load(HistoryCodec.decode(storage.read()))
  }
}
