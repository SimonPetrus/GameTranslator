// SPDX-License-Identifier: AGPL-3.0-only
import Darwin
import Foundation

/// Çökme günlüğü. Açılışta (1) önceki çalıştırmadan kalan canlı çökme dosyası okunur, kayıt "son çökme" olarak saklanıp
/// uygulama günlüğüne Türkçe bir satır yazılır; (2) yeni canlı dosya açılır ve içinin yazılacağı dosya tanıtıcısı
/// önceden tutulur; (3) yakalanmamış NSException ve ölümcül sinyaller (SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP)
/// için işleyiciler kurulur. Sinyal yolunda yalnız eşzamansız-sinyal-güvenli çağrılar kullanılır (write, time, signal,
/// raise): bellek ayırma, Swift String ve kilit yok. Önceki işleyiciler (başka kütüphanelerin) zincirlenir.
/// Sınır: bellek yetersizliği (jetsam) ve bekçi köpeği (watchdog) ölümleri sinyal almaz, kaydedilemez; yığın taşması
/// da (ayrı sinyal yığını kurulmadığı için) kaydedilemeyebilir.
enum CrashLog {
  private static let lock = NSLock()
  private static var started = false
  private static var saved: CrashRecord?
  private static var savedURL: URL?

  /// Açılışta bir kez, mümkün olduğunca erken çağrılır.
  static func start() {
    lock.lock()
    if started { lock.unlock(); return }
    started = true
    lock.unlock()

    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    var folder = support.appendingPathComponent("Crash", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var excluded = URLResourceValues()
    excluded.isExcludedFromBackup = true
    try? folder.setResourceValues(excluded)
    let live = folder.appendingPathComponent("crash-live.log")
    let last = folder.appendingPathComponent("last-crash.json")

    // Önceki çalıştırmanın çökme kaydı: son çökme olarak saklanır (kullanıcı silene dek kalır).
    var record: CrashRecord?
    if let data = try? Data(contentsOf: last), let object = try? JSONSerialization.jsonObject(with: data) {
      record = CrashRecord.fromJson(object)
    }
    if let data = try? Data(contentsOf: live), !data.isEmpty,
       let fresh = CrashFormat.parse(String(decoding: data, as: UTF8.self)) {
      record = fresh
      if let json = try? JSONSerialization.data(withJSONObject: fresh.toJson()) { try? json.write(to: last, options: .atomic) }
      Engine.shared.log(1, CrashFormat.message(fresh))
    }
    lock.lock()
    saved = record
    savedURL = last
    lock.unlock()

    // Canlı dosya boşaltılıp açılır; tanıtıcı işleyicilerde kullanılmak üzere saklanır.
    let fd = live.path.withCString { open($0, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0o644) }
    CrashState.fd = fd
    guard fd >= 0 else {
      Engine.shared.log(1, "çökme günlüğü açılamadı; çökmeler kaydedilmeyecek")
      return
    }
    CrashState.prepare()
    installExceptionHandler()
    installSignalHandlers()
  }

  /// Son kaydedilen çökme: {"at": ms, "kind": "signal"|"exception", "name", "detail"}; yoksa nil.
  static func last() -> [String: Any]? {
    lock.lock(); defer { lock.unlock() }
    return saved?.toJson()
  }

  static func clear() {
    lock.lock()
    saved = nil
    let url = savedURL
    lock.unlock()
    if let url { try? FileManager.default.removeItem(at: url) }
  }

  private static func installExceptionHandler() {
    CrashState.previousException = NSGetUncaughtExceptionHandler()
    NSSetUncaughtExceptionHandler(gtUncaughtExceptionHandler)
  }

  private static func installSignalHandlers() {
    for number in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
      let old = signal(number, gtCrashSignalHandler)
      // Eski işleyici gerçek bir işlev ise (SIG_DFL=0, SIG_IGN=1 ve SIG_ERR=-1 değilse) zincirlenir.
      if let old = old, unsafeBitCast(old, to: Int.self) > 1 {
        CrashState.previousSignal[Int(number)] = old
      }
    }
  }
}

typealias GTSignalHandler = @convention(c) (Int32) -> Void

/// İşleyicilerin okuduğu, önceden hazırlanmış durum. Kilit yok: açılışta bir kez yazılır, işleyicilerde yalnız okunur.
private enum CrashState {
  /// [0]: dosya tanıtıcısı, [1]: sabit başın uzunluğu. İşaretçi kullanılır: global değişkenlere erişimdeki çalışma anı
  /// çakışma denetimi sinyal yolunda çağrılmasın.
  static let slots: UnsafeMutablePointer<Int> = {
    let pointer = UnsafeMutablePointer<Int>.allocate(capacity: 2)
    pointer.initialize(repeating: -1, count: 2)
    return pointer
  }()
  static var fd: Int32 {
    get { Int32(truncatingIfNeeded: slots[0]) }
    set { slots[0] = Int(newValue) }
  }
  static var prefixLength: Int {
    get { slots[1] }
    set { slots[1] = newValue }
  }
  static var previousException: NSUncaughtExceptionHandler?
  /// Sinyal numarasına göre önceki işleyiciler (numaralar 32'nin altındadır).
  static let previousSignal: UnsafeMutablePointer<GTSignalHandler?> = {
    let pointer = UnsafeMutablePointer<GTSignalHandler?>.allocate(capacity: 32)
    pointer.initialize(repeating: nil, count: 32)
    return pointer
  }()
  /// Sinyal satırı arabelleği: sabit baş (GTCRASH1|S|) önceden yazılır; işleyici yalnız sayıları ekler.
  static let buffer: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)

  /// Tembel başlatmalar işleyicide ilk kez tetiklenmesin diye açılışta zorlanır.
  static func prepare() {
    var n = 0
    for byte in CrashFormat.signalPrefix.utf8 {
      buffer[n] = byte
      n += 1
    }
    prefixLength = n
    _ = previousSignal
  }
}

/// [value] ondalık yazılıp [start] konumundan başlayarak arabelleğe konur; sonraki boş konumu döner. Bellek ayırmaz.
private func gtAppendNumber(_ value: Int, _ start: Int) -> Int {
  var v = value < 0 ? 0 : value
  var digits = 1
  var probe = v / 10
  while probe > 0 {
    digits += 1
    probe /= 10
  }
  var index = start + digits - 1
  repeat {
    CrashState.buffer[index] = UInt8(48 + v % 10)
    v /= 10
    index -= 1
  } while v > 0
  return start + digits
}

/// Ölümcül sinyal işleyicisi: eşzamansız-sinyal-güvenli çağrılarla bir satır yazar, önceki işleyiciyi çağırır, varsayılan
/// davranışa dönüp sinyali yeniden yükseltir.
private func gtCrashSignalHandler(_ number: Int32) {
  let fd = CrashState.fd
  if fd >= 0 {
    var n = CrashState.prefixLength
    n = gtAppendNumber(Int(time(nil)), n)
    CrashState.buffer[n] = 124 // "|"
    n += 1
    n = gtAppendNumber(Int(number), n)
    CrashState.buffer[n] = 10 // "\n"
    n += 1
    _ = write(fd, CrashState.buffer, n)
  }
  let index = Int(number)
  let previous: GTSignalHandler? = index >= 0 && index < 32 ? CrashState.previousSignal[index] : nil
  _ = signal(number, SIG_DFL)
  if let previous = previous { previous(number) }
  raise(number)
}

/// Yakalanmamış NSException: normal (sinyal dışı) bağlamdır; ad, neden ve ilk yığın satırları yazılır.
private func gtUncaughtExceptionHandler(_ exception: NSException) {
  let fd = CrashState.fd
  if fd >= 0 {
    let stack = exception.callStackSymbols.prefix(6).joined(separator: "; ")
    let line = CrashFormat.exceptionLine(at: Int(Date().timeIntervalSince1970), name: exception.name.rawValue,
                                         reason: exception.reason ?? "", stack: stack)
    let bytes = Array(line.utf8)
    _ = bytes.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
  }
  CrashState.previousException?(exception)
}
