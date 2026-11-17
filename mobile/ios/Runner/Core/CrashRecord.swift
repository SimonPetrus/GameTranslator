// SPDX-License-Identifier: AGPL-3.0-only
// Çökme kaydının biçimi ve okunması (saf; dosya, sinyal ve iş parçacığı yok). Yazan taraf: Runner/CrashLog.swift.
import Foundation

/// Önceki çalıştırmanın çöktüğünü anlatan kayıt.
struct CrashRecord: Equatable {
  var at: Int
  /// "signal" ya da "exception"
  var kind: String
  var name: String
  var detail: String

  func toJson() -> [String: Any] {
    ["at": at, "kind": kind, "name": name, "detail": detail]
  }

  static func fromJson(_ value: Any?) -> CrashRecord? {
    guard let map = value as? [String: Any], let kind = map["kind"] as? String, let name = map["name"] as? String,
          kind == "signal" || kind == "exception" else { return nil }
    let at = (map["at"] as? NSNumber)?.intValue ?? 0
    return CrashRecord(at: at, kind: kind, name: name, detail: map["detail"] as? String ?? "")
  }
}

/// Canlı çökme dosyasındaki satır biçimi (alanlar "|" ile ayrılır, satır sonu "\n"):
///   sinyal:   GTCRASH1|S|<saniye>|<sinyal numarası>
///   istisna:  GTCRASH1|E|<saniye>|<ad>|<ayrıntı>
/// Sinyal satırı, sinyal işleyicisinde yalnız tam sayı yazımıyla üretilebilsin diye bilerek sabit ve kısadır.
enum CrashFormat {
  static let tag = "GTCRASH1"
  /// Sinyal satırının sabit başı; işleyici bunu önceden hazırlanmış arabelleğe koyar.
  static let signalPrefix = tag + "|S|"
  static let maxNameLength = 80
  static let maxDetailLength = 700
  /// Bir istisna çöküşünden hemen sonra gelen SIGABRT'in aynı çöküş sayılacağı en uzun süre (ms).
  static let abortFollowMs = 30_000

  static let signals: [Int: String] = [4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 8: "SIGFPE", 10: "SIGBUS", 11: "SIGSEGV"]

  static func signalName(_ number: Int) -> String { signals[number] ?? "SIG\(number)" }

  static func signalLine(at seconds: Int, signal: Int) -> String {
    signalPrefix + "\(seconds)|\(signal)\n"
  }

  static func exceptionLine(at seconds: Int, name: String, reason: String, stack: String) -> String {
    var detail = sanitize(reason, limit: 300)
    let frames = sanitize(stack, limit: 400)
    if !frames.isEmpty { detail += (detail.isEmpty ? "" : " @ ") + frames }
    return tag + "|E|\(seconds)|" + sanitize(name, limit: maxNameLength) + "|" + String(detail.prefix(maxDetailLength)) + "\n"
  }

  /// Ayraç ve satır sonu karakterleri temizlenir, uzunluk sınırlanır.
  static func sanitize(_ text: String, limit: Int) -> String {
    let flat = text.replacingOccurrences(of: "|", with: "/")
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespaces)
    return String(flat.prefix(limit))
  }

  /// Dosyadaki son çöküşü verir; satır yoksa ya da hepsi bozuksa nil. İstisna çöküşünün ardından gelen SIGABRT
  /// (uygulama istisnadan sonra kendini durdurur) ayrı çöküş sayılmaz: istisna kaydı verilir.
  static func parse(_ text: String) -> CrashRecord? {
    var records: [CrashRecord] = []
    for line in text.split(whereSeparator: { $0.isNewline }) {
      if let record = parseLine(String(line)) { records.append(record) }
    }
    guard let last = records.last else { return nil }
    if last.kind == "signal", last.name == "SIGABRT",
       let exception = records.last(where: { $0.kind == "exception" }), last.at - exception.at <= abortFollowMs, last.at >= exception.at {
      return exception
    }
    return last
  }

  private static func parseLine(_ line: String) -> CrashRecord? {
    let fields = line.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
    guard fields.count >= 4, fields[0] == tag, let seconds = Int(fields[2]) else { return nil }
    switch fields[1] {
    case "S":
      guard let number = Int(fields[3]) else { return nil }
      return CrashRecord(at: seconds * 1000, kind: "signal", name: signalName(number), detail: "Sinyal \(number)")
    case "E":
      return CrashRecord(at: seconds * 1000, kind: "exception", name: fields[3], detail: fields.count > 4 ? fields[4] : "")
    default:
      return nil
    }
  }

  /// Uygulama günlüğüne yazılan Türkçe satır.
  static func message(_ record: CrashRecord) -> String {
    if record.kind == "signal" { return "Önceki çalıştırma çöktü: \(record.name) (\(record.detail))" }
    let detail = record.detail.isEmpty ? "" : ": " + String(record.detail.prefix(200))
    return "Önceki çalıştırma çöktü: \(record.name)\(detail)"
  }
}
