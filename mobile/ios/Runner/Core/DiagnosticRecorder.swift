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

/// events.jsonl'in yazıldığı yer (uygulamada POSIX dosyası; testte yazılamayan sahte hedef verilebilir).
protocol DiagnosticOutput: AnyObject {
  /// Yazıldıysa true.
  func write(_ data: Data) -> Bool
  func sync()
  func close()
}

/// Kare kodlayıcısı: çağrıldığında JPEG verir (kare kuyruğunda çalışır).
typealias DiagnosticFrameEncoder = () -> Data?
/// O anki karenin kodlayıcısını veren işlev; kare yoksa nil.
typealias DiagnosticFrameGrabber = () -> DiagnosticFrameEncoder?

/// Satır satır eklenen dosya (POSIX; hata istisna değil).
private final class AppendFile: DiagnosticOutput {
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
  private var grabber: DiagnosticFrameGrabber?

  // yalnız kuyrukta
  private final class OpenSession {
    let id: String
    let folder: URL
    let frames: URL
    let file: DiagnosticOutput
    let token: Int
    let startUptime: Double
    let startedAt: Date
    let version: String
    var budget: DiagnosticBudget
    var seq = 0
    var lastSync: Double
    var lastPulse: Double
    var dirty = false

    init(id: String, folder: URL, file: DiagnosticOutput, token: Int, startUptime: Double, startedAt: Date, version: String,
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
  /// Mühürlenip özeti diske yazılamayan kayıtlar (yalnız kuyrukta): her yoklamada dosya yeniden okunmasın.
  private var sealedInMemory: [String: DiagnosticSummary] = [:]
  private let openOutput: (URL) -> DiagnosticOutput?

  /// Kayıt sürerken [DiagnosticLimits.pulseSeconds]'de bir, yardımcı kuyrukta çağrılır (uygulama durum özeti ve kare yazar).
  var onPulse: (() -> Void)?
  /// Kayıt başlayınca ya da durunca (kuyrukta) çağrılır.
  var onChange: (() -> Void)?

  init(root: URL, limits: DiagnosticLimits = DiagnosticLimits(),
       clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
       wallClock: @escaping () -> Date = { Date() },
       freeSpace: ((URL) -> Int64?)? = nil,
       openOutput: ((URL) -> DiagnosticOutput?)? = nil) {
    self.root = root
    self.limits = limits
    self.clock = clock
    self.wallClock = wallClock
    // Varsayılanlar gövdede verilir (varsayılan argümanda kendi tipine başvuru yok).
    if let freeSpace {
      self.freeSpace = freeSpace
    } else {
      self.freeSpace = { (url: URL) -> Int64? in DiagnosticRecorder.availableCapacity(url) }
    }
    if let openOutput {
      self.openOutput = openOutput
    } else {
      self.openOutput = { (url: URL) -> DiagnosticOutput? in AppendFile(url: url) }
    }
  }

  /// O anki karenin kodlayıcısını veren işlev: kare yoksa nil; varsa çağrıldığında JPEG üreten kapanış (kare kuyruğunda
  /// çalışır). Kilit altında çağrılır; hızlı olmalı, kodlama yapmamalı.
  var frameGrabber: DiagnosticFrameGrabber? {
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
        while existing.count >= limits.maxSessions {
          let oldest: String = existing.removeFirst()
          sealedInMemory[oldest] = nil
          try? manager.removeItem(at: folderURL(oldest))
        }
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
      guard let file = openOutput(folder.appendingPathComponent("events.jsonl")) else {
        try? manager.removeItem(at: folder)
        return .failed("events.jsonl açılamadı")
      }
      nextToken += 1
      let now = clock()
      let opened = OpenSession(id: id, folder: folder, file: file, token: nextToken, startUptime: now, startedAt: startedAt,
                               version: version, limits: limits)
      var head: DiagFields = ["format": DiagValue.int(Self.formatVersion), "id": DiagValue.string(id),
                              "version": DiagValue.string(version)]
      head["startedAt"] = DiagValue.int(Int(startedAt.timeIntervalSince1970 * 1000))
      let limitFields: DiagFields = ["seconds": DiagValue.double(limits.maxSeconds), "bytes": DiagValue.int(limits.maxBytes),
                                     "frames": DiagValue.int(limits.maxFrames), "pulseSeconds": DiagValue.double(limits.pulseSeconds)]
      head["limits"] = DiagValue.object(limitFields)
      for item in fields.items { head[item.key] = item.value }
      // Oturum satırı yazılamazsa kayıt hiç açılmaz: oturum yayımlanmaz, bayrak açılmaz, klasör silinir.
      // (append, oturum henüz [session] olmadığı için hata durumunda finish çağırmaz.)
      guard append(opened, type: "session", fields: head, at: now) else {
        opened.file.close()
        try? manager.removeItem(at: folder)
        return .failed("events.jsonl yazılamadı")
      }
      opened.file.sync()
      session = opened
      lock.lock()
      liveToken = opened.token
      liveStart = now
      pending = 0
      reservedFrames = 0
      let previous = published
      published = Status(recording: true, id: id, events: opened.budget.events, bytes: opened.budget.bytes,
                         lastStop: previous.lastStop, lastStopId: previous.lastStopId, stops: previous.stops)
      lock.unlock()
      if Diag.recorder === self { Diag.on = true }
      startTimer()
      onChange?()
      return .started(id)
    }
  }

  /// Kaydı durdurur (sürmüyorsa bir şey yapmaz); bekleyen olaylar önce yazılır.
  func stop(_ reason: DiagnosticStop = .manual) {
    queue.sync { () -> Void in finish(reason) }
  }

  // MARK: - Olaylar

  /// Bir olay (Diag.emit üzerinden). [frameReason] verildiyse o anki kare de istenir.
  func record(_ type: String, _ fields: DiagFields, frameReason: String?) {
    let t: Double = clock()
    var fields: DiagFields = fields
    lock.lock()
    guard let token: Int = liveToken else {
      lock.unlock()
      return
    }
    if pending >= Self.maxPending {
      published.dropped += 1
      lock.unlock()
      return
    }
    pending += 1
    // Kare adı kilit altında ayrılır; kodlama olay sıraya girdikten SONRA kare kuyruğuna verilir. Böylece karenin yazımı
    // (kare kuyruğundan sonra aynı seri kuyruğa girer) olaydan hiç önce olamaz: kare sınırını dolduran kare kaydı
    // durdurduğunda onu isteyen olay çoktan yazılmıştır.
    let frame: (name: String, encode: DiagnosticFrameEncoder)? = frameReason == nil ? nil : reserveFrameLocked()
    lock.unlock()
    if let frame { fields["frame"] = DiagValue.string(frame.name) }
    let event: DiagFields = fields
    queue.async { [self] in
      lock.lock()
      pending -= 1
      lock.unlock()
      guard let s = session, s.token == token else { return }
      _ = append(s, type: type, fields: event, at: t)
      if let stop = s.budget.exceeded(now: clock()) { finish(stop) }
    }
    if let frame, let reason = frameReason { encodeFrame(frame.name, frame.encode, reason: reason, token: token) }
  }

  /// Kilit altında: kare kotası ve kuyruğu uygunsa kare adı ayırır (kodlama henüz başlamaz); değilse nil (olay karesiz
  /// yazılır). Kodlayıcı da burada alınır: olayın anındaki kare.
  private func reserveFrameLocked() -> (name: String, encode: DiagnosticFrameEncoder)? {
    guard let grab: DiagnosticFrameGrabber = grabber, framesInFlight < Self.maxFramesInFlight,
          reservedFrames < limits.maxFrames, let encode: DiagnosticFrameEncoder = grab() else { return nil }
    reservedFrames += 1
    framesInFlight += 1
    let name: String = String(format: "%04ld.jpg", reservedFrames)
    return (name: name, encode: encode)
  }

  /// Kareyi kare kuyruğunda kodlar, sonucu seri kuyrukta yazar.
  private func encodeFrame(_ name: String, _ encode: @escaping DiagnosticFrameEncoder, reason: String, token: Int) {
    frameQueue.async { [self] in
      let started: Double = clock()
      let data: Data? = encode()
      let ms: Int = Int(((clock() - started) * 1000).rounded())
      queue.async { [self] in
        lock.lock()
        framesInFlight -= 1
        lock.unlock()
        writeFrame(name, data, reason: reason, encodeMs: ms, token: token)
      }
    }
  }

  /// Kuyrukta.
  private func writeFrame(_ name: String, _ data: Data?, reason: String, encodeMs: Int, token: Int) {
    guard let s = session, s.token == token else { return }
    var fields = DiagFields()
    fields["name"] = DiagValue.string(name)
    fields["reason"] = DiagValue.string(reason)
    fields["encodeMs"] = DiagValue.int(encodeMs)
    guard let data, !data.isEmpty else {
      fields["ok"] = DiagValue.bool(false)
      fields["error"] = DiagValue.string("kodlanamadı")
      _ = append(s, type: "frame", fields: fields, at: clock())
      return
    }
    guard s.budget.fitsFrame(bytes: data.count) else {
      fields["ok"] = DiagValue.bool(false)
      fields["error"] = DiagValue.string("boyut sınırı")
      _ = append(s, type: "frame", fields: fields, at: clock())
      finish(.size)
      return
    }
    do {
      try data.write(to: s.frames.appendingPathComponent(name))
    } catch {
      fields["ok"] = DiagValue.bool(false)
      fields["error"] = DiagValue.string(error.localizedDescription)
      _ = append(s, type: "frame", fields: fields, at: clock())
      return
    }
    s.budget.addFrame(bytes: data.count)
    fields["ok"] = DiagValue.bool(true)
    fields["bytes"] = DiagValue.int(data.count)
    _ = append(s, type: "frame", fields: fields, at: clock())
    if let stop = s.budget.exceeded(now: clock()) { finish(stop) }
  }

  /// Kuyrukta: satırı kodlar, gizli değerleri siler ve ekler. Yazılamazsa kayıt durur.
  @discardableResult
  private func append(_ s: OpenSession, type: String, fields: DiagFields, at t: Double) -> Bool {
    s.seq += 1
    let ms = max(0, Int(((t - s.startUptime) * 1000).rounded()))
    // Gizli değerler yalnız dizge değerlerinden silinir (alan adları, sayılar ve JSON yapısı korunur).
    let clean: DiagFields = DiagnosticPrivacy.scrub(fields: fields, secrets: secrets)
    let line: String = DiagnosticLine.encode(seq: s.seq, t: ms, type: type, fields: clean)
    let data = Data(line.utf8)
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
      var fields = DiagFields()
      fields["reason"] = DiagValue.string(reason.rawValue)
      fields["seconds"] = DiagValue.double(seconds)
      fields["events"] = DiagValue.int(s.budget.events + 1)
      fields["frames"] = DiagValue.int(s.budget.frames)
      fields["bytes"] = DiagValue.int(s.budget.bytes)
      fields["dropped"] = DiagValue.int(dropped)
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
    let data = Data(line.utf8)
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
  func tick() { queue.sync { () -> Void in tickLocked() } }

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
    queue.sync { () -> [DiagnosticSummary] in
      var out: [DiagnosticSummary] = []
      for id in listIds().reversed() where session?.id != id {
        if let summary = summaryLocked(id) { out.append(summary) }
      }
      return out
    }
  }

  /// Yarım kalan kayıtları mühürler (açılışta).
  func sealInterrupted() {
    queue.sync { () -> Void in
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
      sealedInMemory[id] = nil
      return (try? FileManager.default.removeItem(at: url)) != nil
    }
  }

  private func folderURL(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }

  /// Kayıt klasörleri, eskiden yeniye (adlar zaman damgası).
  private func listIds() -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
    var ids: [String] = []
    for name in names where DiagnosticNames.isValidId(name) { ids.append(name) }
    return ids.sorted()
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
    // Özet diske yazılamadıysa (ör. disk dolu) mühür bir kez yapılır; sonraki yoklamalar bellekteki özeti kullanır,
    // dosya yeniden okunmaz ve ikinci bir "recovered" satırı eklenmez.
    if let known = sealedInMemory[id] { return known }
    let sealed = Self.seal(folder: folder, id: id)
    if let sealed { sealedInMemory[id] = sealed }
    return sealed
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
    var frames = 0
    for name in frameNames where name.hasSuffix(".jpg") { frames += 1 }
    var added = 0
    if FileManager.default.fileExists(atPath: events.path), let file = AppendFile(url: events) {
      var note = DiagFields()
      note["reason"] = DiagValue.string("interrupted")
      note["droppedTailBytes"] = DiagValue.int(data.count - complete)
      note["note"] = DiagValue.string("uygulama kayıt sürerken kapandı; kayıt bir sonraki açılışta mühürlendi")
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
