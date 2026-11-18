// SPDX-License-Identifier: AGPL-3.0-only
// Tanı kaydı: zaman damgalı olaylar tek bir events.jsonl'e satır satır, kareler frames/NNNN.jpg olarak yazılır. Bütün
// yazımlar tek seri kuyrukta; her olay ayrı satır olduğu için uygulama öldürülse de dosya okunur kalır (yarım son satır
// açılışta kesilir). Yalnız iOS'ta; Kotlin karşılığı yok. Yalnız Foundation (kare kodlayıcı uygulamadan verilir).
import Darwin
import Foundation

/// Hattın her yerinden çağrılan hızlı yol. Kayıt kapalıyken maliyet tek bir bool denetimidir: alanları kuran kapanış
/// hiç çalışmaz, dizge ya da JSON üretilmez.
enum Diag {
  /// Kayıt sürüyor mu (yalnız kaydedici yazar; her iş parçacığından okunur).
  nonisolated(unsafe) static var on = false
  /// Uygulamanın tek kaydedicisi (açılışta bir kez atanır; testler kendi kaydedicisini atar).
  nonisolated(unsafe) static var recorder: DiagnosticRecorder?

  @inline(__always)
  static func emit(_ type: String, _ build: () -> DiagFields) {
    guard on, let recorder = recorder else { return }
    recorder.record(type, build(), frameReason: nil)
  }

  /// Olayla birlikte o anki oyun karesi de (kuyruk boşsa) küçültülüp kaydedilir; olaya `frame` alanı eklenir.
  @inline(__always)
  static func emit(_ type: String, frame reason: String, _ build: () -> DiagFields) {
    guard on, let recorder = recorder else { return }
    recorder.record(type, build(), frameReason: reason)
  }
}

/// Bitmiş (ya da yarım kalıp mühürlenmiş) bir kaydın özeti: summary.json.
struct DiagnosticSummary: Equatable {
  var id: String
  var version: String
  /// Başlangıç, 1970'ten ms.
  var startedAt: Int64
  var seconds: Double
  var events: Int
  var frames: Int
  /// Klasörün diskteki boyu.
  var bytes: Int
  /// DiagnosticStop adı ya da "interrupted".
  var reason: String
  var interrupted: Bool

  func toJson() -> [String: Any] {
    ["id": id, "version": version, "startedAt": startedAt, "seconds": seconds, "events": events, "frames": frames,
     "bytes": bytes, "reason": reason, "interrupted": interrupted]
  }

  static func fromJson(_ json: [String: Any]?) -> DiagnosticSummary? {
    guard let json, let id = json["id"] as? String, DiagnosticNames.isValidId(id) else { return nil }
    return DiagnosticSummary(
      id: id, version: json["version"] as? String ?? "",
      startedAt: Int64(JsonNumber.double(json["startedAt"], 0)), seconds: JsonNumber.double(json["seconds"], 0),
      events: JsonNumber.int(json["events"], 0), frames: JsonNumber.int(json["frames"], 0),
      bytes: JsonNumber.int(json["bytes"], 0), reason: json["reason"] as? String ?? "",
      interrupted: json["interrupted"] as? Bool ?? false)
  }
}

/// Satır satır eklenen dosya (POSIX; hata istisna değil).
private final class AppendFile {
  private var fd: Int32

  init?(url: URL) {
    fd = url.path.withCString { open($0, O_WRONLY | O_CREAT | O_APPEND, 0o644) }
    if fd < 0 { return nil }
  }

  deinit { close() }

  func write(_ data: Data) -> Bool {
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
      guard var base = raw.baseAddress else { return true }
      var left = raw.count
      while left > 0 {
        let written = Darwin.write(fd, base, left)
        if written < 0 {
          if errno == EINTR { continue }
          return false
        }
        left -= written
        base = base.advanced(by: written)
      }
      return true
    }
  }

  func sync() { if fd >= 0 { _ = fsync(fd) } }

  func close() {
    if fd >= 0 {
      _ = Darwin.close(fd)
      fd = -1
    }
  }
}

/// Tanı kaydedicisi. Olaylar her iş parçacığından [record] ile gelir; kodlama, gizli değer silme ve disk yazımı tek seri
/// kuyrukta yapılır. Kareler ayrı, düşük öncelikli kuyrukta kodlanır (hat beklemez); kuyruk doluysa kare atlanır.
final class DiagnosticRecorder: @unchecked Sendable {
  struct Status: Equatable {
    var recording = false
    var id = ""
    var seconds = 0.0
    var events = 0
    var bytes = 0
    var frames = 0
    /// Kuyruk taştığı için yazılamayan olay sayısı.
    var dropped = 0
    /// Son duruşun nedeni ve kaydı; [stops] her duruşta artar (arayüz bildirimi için).
    var lastStop: DiagnosticStop?
    var lastStopId = ""
    var stops = 0
  }

  enum StartResult: Equatable {
    case started(String)
    case busy
    case full(oldest: String)
    case lowDisk(Int64)
    case failed(String)
  }

  static let formatVersion = 1
  static let maxPending = 4000
  static let maxFramesInFlight = 2
  /// Diske zorla yazma (fsync) aralığı, sn. Uygulama öldürülse de yazılmış satırlar kaybolmaz; bu yalnız güç kesintisi için.
  static let syncSeconds = 5.0

  let root: URL
  let limits: DiagnosticLimits
  private let clock: () -> Double
  private let wallClock: () -> Date
  private let freeSpace: (URL) -> Int64?

  private let queue = DispatchQueue(label: "gt.diag")
  private let frameQueue = DispatchQueue(label: "gt.diag.frames", qos: .utility)

  // lock altında
  private let lock = NSLock()
  private var liveToken: Int?
  private var liveStart = 0.0
  private var pending = 0
  private var reservedFrames = 0
  private var framesInFlight = 0
  private var published = Status()
  private var secretValues: [String] = []
  private var grabber: (() -> (() -> Data?)?)?

  // yalnız kuyrukta
  private final class OpenSession {
    let id: String
    let folder: URL
    let frames: URL
    let file: AppendFile
    let token: Int
    let startUptime: Double
    let startedAt: Date
    let version: String
    var budget: DiagnosticBudget
    var seq = 0
    var lastSync: Double
    var lastPulse: Double
    var dirty = false

    init(id: String, folder: URL, file: AppendFile, token: Int, startUptime: Double, startedAt: Date, version: String,
         limits: DiagnosticLimits) {
      self.id = id
      self.folder = folder
      frames = folder.appendingPathComponent("frames", isDirectory: true)
      self.file = file
      self.token = token
      self.startUptime = startUptime
      self.startedAt = startedAt
      self.version = version
      budget = DiagnosticBudget(limits: limits, startedAt: startUptime)
      lastSync = startUptime
      lastPulse = startUptime
    }
  }

  private var session: OpenSession?
  private var nextToken = 0
  private var timer: DispatchSourceTimer?

  /// Kayıt sürerken [DiagnosticLimits.pulseSeconds]'de bir, yardımcı kuyrukta çağrılır (uygulama durum özeti ve kare yazar).
  var onPulse: (() -> Void)?
  /// Kayıt başlayınca ya da durunca (kuyrukta) çağrılır.
  var onChange: (() -> Void)?

  init(root: URL, limits: DiagnosticLimits = DiagnosticLimits(),
       clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
       wallClock: @escaping () -> Date = { Date() },
       freeSpace: @escaping (URL) -> Int64? = DiagnosticRecorder.availableCapacity) {
    self.root = root
    self.limits = limits
    self.clock = clock
    self.wallClock = wallClock
    self.freeSpace = freeSpace
  }

  /// O anki karenin kodlayıcısını veren işlev: kare yoksa nil; varsa çağrıldığında JPEG üreten kapanış (kare kuyruğunda
  /// çalışır). Kilit altında çağrılır; hızlı olmalı, kodlama yapmamalı.
  var frameGrabber: (() -> (() -> Data?)?)? {
    get { lock.lock(); defer { lock.unlock() }; return grabber }
    set { lock.lock(); grabber = newValue; lock.unlock() }
  }

  /// Her satırdan silinecek gizli değerler (API anahtarları, hesap kimliği...). Kayıt başlarken ve ayar değişince verilir.
  var secrets: [String] {
    get { lock.lock(); defer { lock.unlock() }; return secretValues }
    set { lock.lock(); secretValues = newValue; lock.unlock() }
  }

  var status: Status {
    lock.lock(); defer { lock.unlock() }
    var out = published
    if liveToken != nil { out.seconds = max(0, clock() - liveStart) }
    return out
  }

  var isRecording: Bool {
    lock.lock(); defer { lock.unlock() }
    return liveToken != nil
  }

  // MARK: - Başlat / durdur

  /// Yeni kayıt açar. Kayıt sürüyorsa .busy; [DiagnosticLimits.maxSessions] kayıt varsa ve [replaceOldest] değilse
  /// .full (en eskinin kimliğiyle); boş alan azsa .lowDisk. [fields] oturum olayına eklenir.
  func start(version: String, replaceOldest: Bool = false, fields: DiagFields = DiagFields()) -> StartResult {
    queue.sync { () -> StartResult in
      if session != nil { return .busy }
      let manager = FileManager.default
      do {
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
      } catch {
        return .failed("klasör: \(error.localizedDescription)")
      }
      Self.excludeFromBackup(root)
      var existing = listIds()
      if existing.count >= limits.maxSessions {
        guard replaceOldest else { return .full(oldest: existing[0]) }
        while existing.count >= limits.maxSessions { try? manager.removeItem(at: folderURL(existing.removeFirst())) }
      }
      if let free = freeSpace(root), free < limits.minFreeBytes { return .lowDisk(free) }
      let startedAt = wallClock()
      var id = DiagnosticNames.sessionId(startedAt)
      var suffix = 2
      while manager.fileExists(atPath: folderURL(id).path) {
        id = DiagnosticNames.sessionId(startedAt) + "-\(suffix)"
        suffix += 1
      }
      let folder = folderURL(id)
      do {
        try manager.createDirectory(at: folder.appendingPathComponent("frames", isDirectory: true), withIntermediateDirectories: true)
      } catch {
        return .failed("klasör: \(error.localizedDescription)")
      }
      Self.excludeFromBackup(folder)
      guard let file = AppendFile(url: folder.appendingPathComponent("events.jsonl")) else {
        try? manager.removeItem(at: folder)
        return .failed("events.jsonl açılamadı")
      }
      nextToken += 1
      let now = clock()
      let opened = OpenSession(id: id, folder: folder, file: file, token: nextToken, startUptime: now, startedAt: startedAt,
                               version: version, limits: limits)
      session = opened
      lock.lock()
      liveToken = opened.token
      liveStart = now
      pending = 0
      reservedFrames = 0
      let previous = published
      published = Status(recording: true, id: id, lastStop: previous.lastStop, lastStopId: previous.lastStopId, stops: previous.stops)
      lock.unlock()
      var head: DiagFields = ["format": .int(Self.formatVersion), "id": .string(id), "version": .string(version),
                              "startedAt": .int(Int(startedAt.timeIntervalSince1970 * 1000))]
      head["limits"] = .object(["seconds": .double(limits.maxSeconds), "bytes": .int(limits.maxBytes),
                                "frames": .int(limits.maxFrames), "pulseSeconds": .double(limits.pulseSeconds)])
      for item in fields.items { head[item.key] = item.value }
      _ = append(opened, type: "session", fields: head, at: now)
      opened.file.sync()
      if Diag.recorder === self { Diag.on = true }
      startTimer()
      onChange?()
      return .started(id)
    }
  }

  /// Kaydı durdurur (sürmüyorsa bir şey yapmaz); bekleyen olaylar önce yazılır.
  func stop(_ reason: DiagnosticStop = .manual) {
    queue.sync { finish(reason) }
  }

  // MARK: - Olaylar

  /// Bir olay (Diag.emit üzerinden). [frameReason] verildiyse o anki kare de istenir.
  func record(_ type: String, _ fields: DiagFields, frameReason: String?) {
    let t = clock()
    var fields = fields
    if let reason = frameReason, let name = reserveFrame(reason: reason) { fields["frame"] = .string(name) }
    lock.lock()
    guard let token = liveToken else {
      lock.unlock()
      return
    }
    if pending >= Self.maxPending {
      published.dropped += 1
      lock.unlock()
      return
    }
    pending += 1
    lock.unlock()
    queue.async { [self] in
      lock.lock()
      pending -= 1
      lock.unlock()
      guard let s = session, s.token == token else { return }
      _ = append(s, type: type, fields: fields, at: t)
      if let stop = s.budget.exceeded(now: clock()) { finish(stop) }
    }
  }

  /// Kare kotası ve kuyruğu uygunsa kare adı ayırır ve kodlamayı kare kuyruğuna verir; değilse nil (olay karesiz yazılır).
  private func reserveFrame(reason: String) -> String? {
    lock.lock()
    guard let token = liveToken, let grab = grabber, framesInFlight < Self.maxFramesInFlight,
          reservedFrames < limits.maxFrames, let encode = grab() else {
      lock.unlock()
      return nil
    }
    reservedFrames += 1
    framesInFlight += 1
    let name = String(format: "%04ld.jpg", reservedFrames)
    lock.unlock()
    frameQueue.async { [self] in
      let started = clock()
      let data = encode()
      let ms = Int(((clock() - started) * 1000).rounded())
      queue.async { [self] in
        lock.lock()
        framesInFlight -= 1
        lock.unlock()
        writeFrame(name, data, reason: reason, encodeMs: ms, token: token)
      }
    }
    return name
  }

  /// Kuyrukta.
  private func writeFrame(_ name: String, _ data: Data?, reason: String, encodeMs: Int, token: Int) {
    guard let s = session, s.token == token else { return }
    var fields: DiagFields = ["name": .string(name), "reason": .string(reason), "encodeMs": .int(encodeMs)]
    guard let data, !data.isEmpty else {
      fields["ok"] = .bool(false)
      fields["error"] = .string("kodlanamadı")
      _ = append(s, type: "frame", fields: fields, at: clock())
      return
    }
    guard s.budget.fitsFrame(bytes: data.count) else {
      fields["ok"] = .bool(false)
      fields["error"] = .string("boyut sınırı")
      _ = append(s, type: "frame", fields: fields, at: clock())
      finish(.size)
      return
    }
    do {
      try data.write(to: s.frames.appendingPathComponent(name))
    } catch {
      fields["ok"] = .bool(false)
      fields["error"] = .string(error.localizedDescription)
      _ = append(s, type: "frame", fields: fields, at: clock())
      return
    }
    s.budget.addFrame(bytes: data.count)
    fields["ok"] = .bool(true)
    fields["bytes"] = .int(data.count)
    _ = append(s, type: "frame", fields: fields, at: clock())
    if let stop = s.budget.exceeded(now: clock()) { finish(stop) }
  }

  /// Kuyrukta: satırı kodlar, gizli değerleri siler ve ekler. Yazılamazsa kayıt durur.
  @discardableResult
  private func append(_ s: OpenSession, type: String, fields: DiagFields, at t: Double) -> Bool {
    s.seq += 1
    let ms = max(0, Int(((t - s.startUptime) * 1000).rounded()))
    let line = DiagnosticLine.encode(seq: s.seq, t: ms, type: type, fields: fields)
    let data = Data(DiagnosticPrivacy.scrub(line, secrets: secrets).utf8)
    guard s.file.write(data) else {
      if session === s { finish(.failed, writable: false) }
      return false
    }
    s.budget.addEvent(bytes: data.count)
    s.dirty = true
    lock.lock()
    published.events = s.budget.events
    published.bytes = s.budget.bytes
    published.frames = s.budget.frames
    lock.unlock()
    return true
  }

  /// Kuyrukta: son satırı yazar, dosyayı kapatır, summary.json'u yazar.
  private func finish(_ reason: DiagnosticStop, writable: Bool = true) {
    guard let s = session else { return }
    session = nil
    if Diag.recorder === self { Diag.on = false }
    timer?.cancel()
    timer = nil
    lock.lock()
    liveToken = nil
    let dropped = published.dropped
    lock.unlock()
    let seconds = max(0, clock() - s.startUptime)
    if writable {
      let fields: DiagFields = ["reason": .string(reason.rawValue), "seconds": .double(seconds), "events": .int(s.budget.events + 1),
                                "frames": .int(s.budget.frames), "bytes": .int(s.budget.bytes), "dropped": .int(dropped)]
      _ = appendClosing(s, fields: fields)
    }
    s.file.sync()
    s.file.close()
    let summary = DiagnosticSummary(id: s.id, version: s.version, startedAt: Int64(s.startedAt.timeIntervalSince1970 * 1000),
                                    seconds: seconds, events: s.budget.events, frames: s.budget.frames,
                                    bytes: Self.folderSize(s.folder), reason: reason.rawValue, interrupted: false)
    Self.writeSummary(summary, in: s.folder)
    lock.lock()
    published.recording = false
    published.seconds = seconds
    published.events = s.budget.events
    published.bytes = s.budget.bytes
    published.frames = s.budget.frames
    published.lastStop = reason
    published.lastStopId = s.id
    published.stops += 1
    lock.unlock()
    onChange?()
  }

  /// Kapanış satırı (oturum artık [session] değil; yazım hatası yeniden finish çağırmaz).
  private func appendClosing(_ s: OpenSession, fields: DiagFields) -> Bool {
    s.seq += 1
    let line = DiagnosticLine.encode(seq: s.seq, t: max(0, Int(((clock() - s.startUptime) * 1000).rounded())), type: "stop",
                                     fields: fields)
    let data = Data(DiagnosticPrivacy.scrub(line, secrets: secrets).utf8)
    guard s.file.write(data) else { return false }
    s.budget.addEvent(bytes: data.count)
    return true
  }

  // MARK: - Zamanlayıcı

  private func startTimer() {
    timer?.cancel()
    let created = DispatchSource.makeTimerSource(queue: queue)
    created.schedule(deadline: .now() + 1, repeating: 1)
    created.setEventHandler { [weak self] in self?.tickLocked() }
    created.resume()
    timer = created
  }

  /// Kuyrukta, saniyede bir: süre sınırı, fsync, durum ve nabız.
  private func tickLocked() {
    guard let s = session else { return }
    let now = clock()
    if let stop = s.budget.exceeded(now: now) { return finish(stop) }
    if s.dirty && now - s.lastSync >= Self.syncSeconds {
      s.file.sync()
      s.dirty = false
      s.lastSync = now
    }
    if now - s.lastPulse >= limits.pulseSeconds {
      s.lastPulse = now
      if let pulse = onPulse { DispatchQueue.global(qos: .utility).async(execute: pulse) }
    }
  }

  /// Testler: zamanlayıcıyı beklemeden bir tık.
  func tick() { queue.sync { tickLocked() } }

  /// Testler: bekleyen kare kodlamaları ve yazımlar biter.
  func waitIdle() {
    for _ in 0..<3 {
      frameQueue.sync {}
      queue.sync {}
    }
  }

  // MARK: - Kayıtlar

  /// Bitmiş kayıtlar, yeniden eskiye. Yarım kalanlar (uygulama kapanmış) önce mühürlenir.
  func sessions() -> [DiagnosticSummary] {
    queue.sync {
      listIds().reversed().compactMap { id -> DiagnosticSummary? in
        if session?.id == id { return nil }
        return summaryLocked(id)
      }
    }
  }

  /// Yarım kalan kayıtları mühürler (açılışta).
  func sealInterrupted() {
    queue.sync {
      for id in listIds() where session?.id != id { _ = summaryLocked(id) }
    }
  }

  /// Bitmiş kaydın klasörü (paylaşım için); kayıt sürüyorsa ya da yoksa nil.
  func folder(for id: String) -> URL? {
    queue.sync { () -> URL? in
      guard DiagnosticNames.isValidId(id), session?.id != id else { return nil }
      let url = folderURL(id)
      guard FileManager.default.fileExists(atPath: url.path) else { return nil }
      _ = summaryLocked(id)
      return url
    }
  }

  func summary(for id: String) -> DiagnosticSummary? {
    queue.sync { () -> DiagnosticSummary? in
      guard DiagnosticNames.isValidId(id), session?.id != id else { return nil }
      return summaryLocked(id)
    }
  }

  /// Bitmiş kaydı siler; süren kayıt silinmez.
  @discardableResult
  func delete(_ id: String) -> Bool {
    queue.sync { () -> Bool in
      guard DiagnosticNames.isValidId(id), session?.id != id else { return false }
      let url = folderURL(id)
      guard FileManager.default.fileExists(atPath: url.path) else { return false }
      return (try? FileManager.default.removeItem(at: url)) != nil
    }
  }

  private func folderURL(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }

  /// Kayıt klasörleri, eskiden yeniye (adlar zaman damgası).
  private func listIds() -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
    return names.filter { DiagnosticNames.isValidId($0) }.sorted()
  }

  /// Kuyrukta: summary.json varsa onu okur; yoksa kayıt yarım kalmıştır: yarım son satır kesilir, bir "recovered" satırı
  /// eklenir ve özet "interrupted" olarak yazılır.
  private func summaryLocked(_ id: String) -> DiagnosticSummary? {
    let folder = folderURL(id)
    let summaryURL = folder.appendingPathComponent("summary.json")
    if let data = try? Data(contentsOf: summaryURL),
       let summary = DiagnosticSummary.fromJson(try? JSONSerialization.jsonObject(with: data) as? [String: Any]) {
      return summary
    }
    return Self.seal(folder: folder, id: id)
  }

  /// Yarım kalmış kaydı onarır ve özetini yazar (saf dosya işi; test edilir).
  static func seal(folder: URL, id: String) -> DiagnosticSummary? {
    let events = folder.appendingPathComponent("events.jsonl")
    let data = (try? Data(contentsOf: events)) ?? Data()
    let complete = DiagnosticReader.completeLength(data)
    if complete < data.count {
      _ = events.path.withCString { truncate($0, off_t(complete)) }
    }
    let kept = data.prefix(complete)
    let first = DiagnosticReader.firstEvent(kept)
    let last = DiagnosticReader.lastEvent(kept)
    let lines = DiagnosticReader.lineCount(kept)
    let lastT = JsonNumber.int(last?["t"], 0)
    let lastSeq = JsonNumber.int(last?["seq"], lines)
    let frameNames = (try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("frames").path)) ?? []
    let frames = frameNames.filter { $0.hasSuffix(".jpg") }.count
    var added = 0
    if FileManager.default.fileExists(atPath: events.path), let file = AppendFile(url: events) {
      let note: DiagFields = ["reason": .string("interrupted"), "droppedTailBytes": .int(data.count - complete),
                              "note": .string("uygulama kayıt sürerken kapandı; kayıt bir sonraki açılışta mühürlendi")]
      if file.write(Data(DiagnosticLine.encode(seq: lastSeq + 1, t: lastT, type: "recovered", fields: note).utf8)) { added = 1 }
      file.sync()
      file.close()
    }
    let summary = DiagnosticSummary(
      id: id, version: first?["version"] as? String ?? "",
      startedAt: Int64(JsonNumber.double(first?["startedAt"], 0)), seconds: Double(lastT) / 1000,
      events: lines + added, frames: frames, bytes: folderSize(folder), reason: "interrupted", interrupted: true)
    writeSummary(summary, in: folder)
    return summary
  }

  private static func writeSummary(_ summary: DiagnosticSummary, in folder: URL) {
    guard let data = try? JSONSerialization.data(withJSONObject: summary.toJson()) else { return }
    try? data.write(to: folder.appendingPathComponent("summary.json"), options: .atomic)
  }

  static func folderSize(_ folder: URL) -> Int {
    guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
    var total = 0
    for case let url as URL in walker {
      total += (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }
    return total
  }

  static func excludeFromBackup(_ url: URL) {
    var target = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? target.setResourceValues(values)
  }

  /// Birimdeki boş alan ("önemli kullanım" için); okunamazsa nil.
  static func availableCapacity(_ url: URL) -> Int64? {
    if #available(macOS 10.13, iOS 11.0, *) {
      let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      if let free = values?.volumeAvailableCapacityForImportantUsage { return free }
    }
    let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
    return values?.volumeAvailableCapacity.map { Int64($0) }
  }
}
