// SPDX-License-Identifier: AGPL-3.0-only
// Tanı kaydını paylaşmak için sıkıştırmasız ("stored") ZIP yazıcı: iOS'ta zip için sistem kitaplığı yok, kareler zaten
// JPEG (sıkışık). Windows'ta çift tıkla açılır. 4 GB ve 65535 dosya altı (ZIP64 yok). Yalnız Foundation; dosyalar parça
// parça okunur, bellekte bütünüyle tutulmaz.
import Darwin
import Foundation

/// ZIP'in CRC-32'si: GamePacks.swift'teki CRC32 (gzip ile aynı, IEEE 802.3) kullanılır.
enum ZipChecksum {
  static func of(_ data: Data) -> UInt32 {
    data.withUnsafeBytes { CRC32.checksum($0.bindMemory(to: UInt8.self)) }
  }

  /// Parça parça okunan veri için süren hesap.
  static func add(_ crc: inout CRC32, _ data: Data) {
    data.withUnsafeBytes { raw in
      for byte in raw { crc.update(byte) }
    }
  }
}

enum ZipError: Error, Equatable {
  case tooLarge
  case tooManyEntries
  case read(String)
  case write(String)
  case changed(String)
}

/// ZIP baytlarının gittiği yer.
protocol ZipSink: AnyObject {
  func write(_ data: Data) throws
}

/// Bellekte biriktirir (testler).
final class DataZipSink: ZipSink {
  private(set) var data = Data()
  func write(_ chunk: Data) throws { data.append(chunk) }
}

/// Dosyaya yazar (POSIX; hata istisna değil, ZipError.write).
final class FileZipSink: ZipSink {
  private var fd: Int32

  init(url: URL) throws {
    fd = url.path.withCString { open($0, O_WRONLY | O_CREAT | O_TRUNC, 0o644) }
    if fd < 0 { throw ZipError.write("open \(errno)") }
  }

  deinit { close() }

  func write(_ chunk: Data) throws {
    try chunk.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      guard var base = raw.baseAddress else { return }
      var left = raw.count
      while left > 0 {
        let written = Darwin.write(fd, base, left)
        if written < 0 {
          if errno == EINTR { continue }
          throw ZipError.write("write \(errno)")
        }
        left -= written
        base = base.advanced(by: written)
      }
    }
  }

  func close() {
    if fd >= 0 {
      _ = Darwin.close(fd)
      fd = -1
    }
  }
}

/// Sıkıştırmasız ZIP yazıcı: her dosya için yerel başlık + veri, sonda merkezî dizin ve dizin sonu kaydı.
/// CRC ve boy veriden önce bilindiği için veri tanımlayıcısı (bayrak 3) kullanılmaz; her açıcı okur.
final class StoredZipWriter {
  private struct Entry {
    let name: [UInt8]
    let crc: UInt32
    let size: UInt32
    let offset: UInt32
    let time: UInt16
    let date: UInt16
  }

  static let chunkSize = 256 * 1024
  private let sink: ZipSink
  private var entries: [Entry] = []
  private var offset: UInt64 = 0
  private var finished = false

  init(sink: ZipSink) { self.sink = sink }

  /// Bellekteki veriyi ekler. [name]: "klasör/dosya" (eğik çizgiyle).
  func add(name: String, data: Data, modified: Date) throws {
    let crc = ZipChecksum.of(data)
    try header(name: name, crc: crc, size: data.count, modified: modified)
    try emit(data)
  }

  /// Dosyayı iki geçişte ekler: önce CRC ve boy, sonra parça parça kopya (bellekte bütünüyle tutulmaz).
  func add(name: String, file: URL, modified: Date) throws {
    var first = CRC32()
    var size = 0
    try Self.readChunks(file) { chunk in
      ZipChecksum.add(&first, chunk)
      size += chunk.count
    }
    try header(name: name, crc: first.value, size: size, modified: modified)
    var copied = 0
    var check = CRC32()
    try Self.readChunks(file) { chunk in
      ZipChecksum.add(&check, chunk)
      copied += chunk.count
      try emit(chunk)
    }
    // Dosya iki geçiş arasında değiştiyse ZIP bozuk olur.
    if copied != size || check.value != first.value { throw ZipError.changed(file.lastPathComponent) }
  }

  /// Merkezî dizini ve dizin sonu kaydını yazar.
  func finish() throws {
    guard !finished else { return }
    finished = true
    let directoryStart = offset
    for entry in entries {
      var b = Data()
      Self.u32(&b, 0x0201_4B50)
      Self.u16(&b, 20)  // yapan sürüm (2.0, MS-DOS)
      Self.u16(&b, 20)  // gereken sürüm
      Self.u16(&b, 0x0800)  // genel bayrak: adlar UTF-8
      Self.u16(&b, 0)  // yöntem: stored
      Self.u16(&b, entry.time)
      Self.u16(&b, entry.date)
      Self.u32(&b, entry.crc)
      Self.u32(&b, entry.size)
      Self.u32(&b, entry.size)
      Self.u16(&b, UInt16(entry.name.count))
      Self.u16(&b, 0)  // ek alan
      Self.u16(&b, 0)  // açıklama
      Self.u16(&b, 0)  // disk
      Self.u16(&b, 0)  // iç öznitelik
      Self.u32(&b, 0)  // dış öznitelik
      Self.u32(&b, entry.offset)
      b.append(contentsOf: entry.name)
      try emit(b)
    }
    let directorySize = offset - directoryStart
    guard offset <= UInt64(UInt32.max) else { throw ZipError.tooLarge }
    var end = Data()
    Self.u32(&end, 0x0605_4B50)
    Self.u16(&end, 0)
    Self.u16(&end, 0)
    Self.u16(&end, UInt16(entries.count))
    Self.u16(&end, UInt16(entries.count))
    Self.u32(&end, UInt32(directorySize))
    Self.u32(&end, UInt32(directoryStart))
    Self.u16(&end, 0)
    try emit(end)
  }

  // MARK: - İç

  private func header(name: String, crc: UInt32, size: Int, modified: Date) throws {
    guard entries.count < 0xFFFF else { throw ZipError.tooManyEntries }
    guard offset + UInt64(size) + 30 + UInt64(name.utf8.count) < UInt64(UInt32.max), size < Int(UInt32.max) else {
      throw ZipError.tooLarge
    }
    let bytes = Array(name.utf8)
    let (time, date) = Self.dosTime(modified)
    let entry = Entry(name: bytes, crc: crc, size: UInt32(size), offset: UInt32(offset), time: time, date: date)
    var b = Data()
    Self.u32(&b, 0x0403_4B50)
    Self.u16(&b, 20)
    Self.u16(&b, 0x0800)
    Self.u16(&b, 0)
    Self.u16(&b, time)
    Self.u16(&b, date)
    Self.u32(&b, crc)
    Self.u32(&b, UInt32(size))
    Self.u32(&b, UInt32(size))
    Self.u16(&b, UInt16(bytes.count))
    Self.u16(&b, 0)
    b.append(contentsOf: bytes)
    try emit(b)
    entries.append(entry)
  }

  private func emit(_ data: Data) throws {
    try sink.write(data)
    offset += UInt64(data.count)
  }

  /// MS-DOS saat ve tarihi (yerel saat; iki saniye çözünürlük; 1980 öncesi 1980).
  static func dosTime(_ date: Date, timeZone: TimeZone = .current) -> (time: UInt16, date: UInt16) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    let year = min(max((c.year ?? 1980) - 1980, 0), 127)
    let time = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
    let day = UInt16(year << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
    return (time, day)
  }

  static func u16(_ data: inout Data, _ value: UInt16) {
    data.append(UInt8(value & 0xFF))
    data.append(UInt8(value >> 8))
  }

  static func u32(_ data: inout Data, _ value: UInt32) {
    for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8((value >> UInt32(shift)) & 0xFF)) }
  }

  /// Dosyayı [chunkSize] parçalarla okur (POSIX; istisna yok).
  static func readChunks(_ url: URL, _ body: (Data) throws -> Void) throws {
    let fd = url.path.withCString { open($0, O_RDONLY) }
    if fd < 0 { throw ZipError.read("\(url.lastPathComponent): open \(errno)") }
    defer { _ = Darwin.close(fd) }
    var buffer = [UInt8](repeating: 0, count: chunkSize)
    while true {
      let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, chunkSize) }
      if count < 0 {
        if errno == EINTR { continue }
        throw ZipError.read("\(url.lastPathComponent): read \(errno)")
      }
      if count == 0 { break }
      try body(Data(buffer[0..<count]))
    }
  }
}

/// Bir tanı kaydı klasörünü tek ZIP'e yazar: <kök>/events.jsonl, <kök>/summary.json, <kök>/frames/NNNN.jpg (sıralı).
/// Klasörün dışındaki ve gizli dosyalar alınmaz.
enum DiagnosticExport {
  /// ZIP'e girecek dosyalar: (ZIP içindeki ad, dosya). Sıra kararlıdır.
  static func files(in folder: URL, root: String) -> [(name: String, url: URL)] {
    let manager = FileManager.default
    var out: [(name: String, url: URL)] = []
    for name in ["events.jsonl", "summary.json"] {
      let url = folder.appendingPathComponent(name)
      if manager.fileExists(atPath: url.path) { out.append((name: root + "/" + name, url: url)) }
    }
    let frames = folder.appendingPathComponent("frames", isDirectory: true)
    let names = ((try? manager.contentsOfDirectory(atPath: frames.path)) ?? [])
      .filter { $0.hasSuffix(".jpg") && !$0.hasPrefix(".") && !$0.contains("/") }
      .sorted()
    for name in names { out.append((name: root + "/frames/" + name, url: frames.appendingPathComponent(name))) }
    return out
  }

  static func write(folder: URL, root: String, to sink: ZipSink, modified: Date = Date()) throws {
    let writer = StoredZipWriter(sink: sink)
    for file in files(in: folder, root: root) {
      let date = ((try? file.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? modified
      try writer.add(name: file.name, file: file.url, modified: date)
    }
    try writer.finish()
  }
}
