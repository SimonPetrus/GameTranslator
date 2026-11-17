// SPDX-License-Identifier: AGPL-3.0-only
// Oturumlar arasında kalan, sınırlı boyutlu satır çevirisi deposu.
import Foundation

/// Önbelleğin kalıcı deposu (testte bellekte, uygulamada dosyada).
protocol TranslationCacheStorage: AnyObject {
  func read() -> Data?
  func write(_ data: Data)
}

final class FileCacheStorage: TranslationCacheStorage {
  let url: URL

  init(url: URL) { self.url = url }

  func read() -> Data? { try? Data(contentsOf: url) }

  func write(_ data: Data) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
  }
}

/// Satır çevirilerini oturumlar arasında saklar: anahtar = motor + model + kaynak dil + hedef dil + kural sürümü + metin.
/// En fazla [capacity] kayıt; dolunca en uzun süredir kullanılmayan kayıtlar atılır, 30 günden eski kayıtlar yüklemede silinir.
/// Dosya ilk kullanımda (tembel) okunur; bozuksa boş başlanır. Kayıt gecikmeli ve çeviri iş parçacığı dışında yapılır.
final class DiskTranslationCache: @unchecked Sendable {
  static let defaultCapacity = 5000
  static let maxAge: Double = 30 * 86400
  private static let fileVersion = 1

  private struct Row: Codable {
    var k: String
    var v: String
    var s: Int
    var t: Double
  }

  private struct FileBody: Codable {
    var version: Int
    var rows: [Row]
  }

  private struct Entry {
    var value: String
    var seq: Int
    var time: Double
  }

  private let storage: TranslationCacheStorage
  private let capacity: Int
  private let saveDelay: TimeInterval
  private let now: () -> Double
  private let queue: DispatchQueue
  private let lock = NSLock()
  private let writeLock = NSLock()
  private var entries: [String: Entry] = [:]
  private var loaded = false
  private var dirty = false
  private var saveScheduled = false
  private var nextSeq = 0

  init(storage: TranslationCacheStorage, capacity: Int = DiskTranslationCache.defaultCapacity,
       saveDelay: TimeInterval = 3, now: @escaping () -> Double = { Date().timeIntervalSince1970 },
       queue: DispatchQueue = DispatchQueue(label: "gt.translation-cache", qos: .utility)) {
    self.storage = storage
    self.capacity = max(1, capacity)
    self.saveDelay = saveDelay
    self.now = now
    self.queue = queue
  }

  /// Anahtar: alanlar birim ayracıyla (U+001F) birleştirilir; metin sonda olduğu için karışma olmaz.
  static func key(engine: String, model: String, source: String, target: String, rules: String, text: String) -> String {
    [engine, model, source, target, rules, text].joined(separator: "\u{1F}")
  }

  /// Sözlük gibi uzun kural girdileri için kararlı kısa özet (FNV-1a 64; Swift'in hashValue'su her açılışta değişir).
  static func stableHash(_ text: String) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
    return String(hash, radix: 16)
  }

  var count: Int {
    lock.lock(); defer { lock.unlock() }
    loadIfNeeded()
    return entries.count
  }

  func get(_ key: String) -> String? {
    lock.lock()
    loadIfNeeded()
    guard var entry = entries[key] else { lock.unlock(); return nil }
    entry.seq = nextSeq
    nextSeq += 1
    entry.time = now()
    entries[key] = entry
    dirty = true
    let schedule = takeSaveSlot()
    lock.unlock()
    if schedule { scheduleSave() }
    return entry.value
  }

  func set(_ key: String, _ value: String) {
    if value.isEmpty { return }
    lock.lock()
    loadIfNeeded()
    entries[key] = Entry(value: value, seq: nextSeq, time: now())
    nextSeq += 1
    dirty = true
    if entries.count > capacity { evict() }
    let schedule = takeSaveSlot()
    lock.unlock()
    if schedule { scheduleSave() }
  }

  /// Kilit altında: kayıt zamanlanmamışsa yer ayırır (true dönerse çağıran zamanlamalı). Yazma sırasında gelen
  /// değişiklik de böylece yeni bir kayıt turu alır.
  private func takeSaveSlot() -> Bool {
    if saveScheduled { return false }
    saveScheduled = true
    return true
  }

  private func scheduleSave() { queue.asyncAfter(deadline: .now() + saveDelay) { [self] in flush() } }

  /// Bekleyen değişiklikleri hemen yazar (uygulama durunca ve testlerde).
  func flush() {
    writeLock.lock(); defer { writeLock.unlock() }
    lock.lock()
    saveScheduled = false
    guard loaded, dirty else { lock.unlock(); return }
    dirty = false
    let rows = entries.map { Row(k: $0.key, v: $0.value.value, s: $0.value.seq, t: $0.value.time) }
    lock.unlock()
    if let data = try? JSONEncoder().encode(FileBody(version: Self.fileVersion, rows: rows)) { storage.write(data) }
  }

  // MARK: - İç

  /// Kilit altında çağrılır.
  private func loadIfNeeded() {
    if loaded { return }
    loaded = true
    guard let data = storage.read(),
          let body = try? JSONDecoder().decode(FileBody.self, from: data), body.version == Self.fileVersion else { return }
    let limit = now() - Self.maxAge
    for row in body.rows where row.t >= limit && !row.v.isEmpty {
      entries[row.k] = Entry(value: row.v, seq: row.s, time: row.t)
      nextSeq = max(nextSeq, row.s + 1)
    }
    if entries.count > capacity { evict() }
  }

  /// Kilit altında çağrılır: sınırın %90'ına inene dek en eski kullanılanlar atılır.
  private func evict() {
    let target = max(1, capacity * 9 / 10)
    let removeCount = entries.count - target
    if removeCount <= 0 { return }
    for (key, _) in entries.sorted(by: { $0.value.seq < $1.value.seq }).prefix(removeCount) { entries[key] = nil }
  }
}
