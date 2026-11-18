// SPDX-License-Identifier: AGPL-3.0-only
// Tanı kaydının (Ayarlar › Tanı kaydı) saf parçaları: olay JSON'u, gizli alan süzme, sınırlar ve yarım kayıt okuma.
// Yalnız iOS'ta; Kotlin karşılığı yok. Yalnız Foundation.
import Foundation

/// Tanı kaydındaki bir JSON değeri. Nesne alanlarının sırası korunur (çıktı kararlı ve okunur).
enum DiagValue {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([DiagValue])
  case object(DiagFields)

  /// Bu uzunluğu (UTF-8 bayt) aşan metin kısaltılır: tek bir dev günlük satırı dosyayı şişirmesin.
  static let maxStringBytes = 8192

  /// Kutu: [sol, üst, sağ, alt] (0–1, dört basamak); yoksa null.
  static func box(_ b: TextBox?) -> DiagValue {
    guard let b else { return .null }
    return .array([.double(b.left), .double(b.top), .double(b.right), .double(b.bottom)])
  }

  static func strings(_ list: [String]) -> DiagValue { .array(list.map { .string($0) }) }

  static func doubles(_ list: [Double]) -> DiagValue { .array(list.map { .double($0) }) }

  static func optional(_ value: Double?) -> DiagValue { value.map { .double($0) } ?? .null }

  static func optional(_ value: String?) -> DiagValue { value.map { .string($0) } ?? .null }

  /// JSON metni.
  var json: String {
    var out = ""
    write(to: &out)
    return out
  }

  func write(to out: inout String) {
    switch self {
    case .null: out += "null"
    case .bool(let value): out += value ? "true" : "false"
    case .int(let value): out += String(value)
    case .double(let value): out += DiagValue.number(value)
    case .string(let value): out += SubtitleWire.jsonString(DiagValue.clip(value))
    case .array(let items):
      out += "["
      for (index, item) in items.enumerated() {
        if index > 0 { out += "," }
        item.write(to: &out)
      }
      out += "]"
    case .object(let fields): fields.write(to: &out)
    }
  }

  /// Dört basamağa yuvarlanmış sayı, sondaki sıfırlar atılır; sonlu değilse null (JSON'da NaN yok).
  static func number(_ value: Double) -> String {
    guard value.isFinite else { return "null" }
    var text = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    if text.contains(".") {
      while text.hasSuffix("0") { text.removeLast() }
      if text.hasSuffix(".") { text.removeLast() }
    }
    return text == "-0" ? "0" : text
  }

  static func clip(_ text: String) -> String {
    guard text.utf8.count > maxStringBytes else { return text }
    var kept = ""
    var bytes = 0
    for character in text {
      bytes += String(character).utf8.count
      if bytes > maxStringBytes - 16 { break }
      kept.append(character)
    }
    return kept + "…[kısaltıldı]"
  }
}

/// Sıralı nesne alanları. `["what": .string("send"), "count": .int(2)]` biçiminde yazılır.
struct DiagFields: ExpressibleByDictionaryLiteral {
  private(set) var items: [(key: String, value: DiagValue)] = []

  init() {}

  init(dictionaryLiteral elements: (String, DiagValue)...) {
    items = elements.map { (key: $0.0, value: $0.1) }
  }

  var isEmpty: Bool { items.isEmpty }

  /// Alan ekler; aynı ad varsa değeri değiştirir.
  subscript(key: String) -> DiagValue? {
    get { items.first(where: { $0.key == key })?.value }
    set {
      if let index = items.firstIndex(where: { $0.key == key }) {
        if let newValue { items[index].value = newValue } else { items.remove(at: index) }
      } else if let newValue {
        items.append((key: key, value: newValue))
      }
    }
  }

  func write(to out: inout String) {
    out += "{"
    for (index, item) in items.enumerated() {
      if index > 0 { out += "," }
      out += SubtitleWire.jsonString(item.key)
      out += ":"
      item.value.write(to: &out)
    }
    out += "}"
  }

  var json: String {
    var out = ""
    write(to: &out)
    return out
  }
}

/// events.jsonl'deki bir satır: `{"seq":12,"t":3400,"type":"read",...}` ve satır sonu. [t]: kaydın başından ms.
enum DiagnosticLine {
  static let reserved: Set<String> = ["seq", "t", "type"]

  static func encode(seq: Int, t: Int, type: String, fields: DiagFields) -> String {
    var out = "{\"seq\":\(seq),\"t\":\(t),\"type\":" + SubtitleWire.jsonString(type)
    for item in fields.items where !reserved.contains(item.key) {
      out += ","
      out += SubtitleWire.jsonString(item.key)
      out += ":"
      item.value.write(to: &out)
    }
    out += "}\n"
    return out
  }
}

/// Hat adımlarının tanı izi (kayıt açıkken kurulur; kapalıyken hiç oluşmaz).
final class DiagTrace {
  var steps: [String] = []
  var calls = 0
  var raw: String?
  var names: [String] = []
}

/// Gizli bilgilerin kayda girmemesi: ayarlardaki anahtarlar yalnız "dolu/boş" olarak, sözlük yalnız sayılarla yazılır;
/// bilinen gizli değerler ve URL'deki anahtar parametreleri her satırdan silinir.
enum DiagnosticPrivacy {
  static let secretFields: Set<String> = ["deepLKey", "geminiKey"]
  /// Adında bunlardan biri geçen alan da gizli sayılır (ileride eklenecek alanlara karşı).
  static let secretWords = ["key", "token", "secret", "password", "passwd", "account", "regist", "morning", "credential",
                            "auth", "cookie"]
  static let masked = "[gizli]"

  static func isSecretField(_ name: String) -> Bool {
    if secretFields.contains(name) { return true }
    let lower = name.lowercased()
    return secretWords.contains { lower.contains($0) }
  }

  /// Ayar JSON'u (Settings.toJson) gizli alanlar süzülmüş olarak; alanlar alfabetik.
  static func settings(_ json: [String: Any]) -> DiagValue { .object(redactedObject(json)) }

  /// Değişen ayar yolları ("engine", "style.fontSize"); alfabetik. Değerler karşılaştırılır, yazılmaz.
  static func changes(before: [String: Any], after: [String: Any]) -> [String] {
    var old: [String: String] = [:]
    var new: [String: String] = [:]
    for (path, value) in flatten(before, prefix: "") { old[path] = convert(value).json }
    for (path, value) in flatten(after, prefix: "") { new[path] = convert(value).json }
    return Set(old.keys).union(new.keys).filter { old[$0] != new[$0] }.sorted()
  }

  /// [paths] yollarındaki yeni değerler, gizliler süzülmüş (ayar değişikliği olayı için).
  static func values(_ json: [String: Any], paths: [String]) -> DiagFields {
    let flat = Dictionary(flatten(json, prefix: ""), uniquingKeysWith: { first, _ in first })
    var out = DiagFields()
    for path in paths {
      let leaf = path.split(separator: ".").last.map(String.init) ?? path
      guard let value = flat[path] else {
        out[path] = .null
        continue
      }
      out[path] = redacted(leaf, value)
    }
    return out
  }

  /// Satırdaki bilinen gizli değerleri ve URL/üst bilgi anahtarlarını [masked] ile değiştirir. 4 karakterden kısa
  /// "gizli" değer yok sayılır (her yerde geçen kısa dizgeler silinmesin).
  static func scrub(_ line: String, secrets: [String]) -> String {
    var out = line
    for secret in secrets {
      let value = secret.trimmingCharacters(in: .whitespacesAndNewlines)
      guard value.count >= 4 else { continue }
      out = out.replacingOccurrences(of: value, with: masked)
      // JSON'a kaçışlı yazılmış hali de (ör. "/" ya da "\"" içeren anahtar).
      let escaped = String(SubtitleWire.jsonString(value).dropFirst().dropLast())
      if escaped != value { out = out.replacingOccurrences(of: escaped, with: masked) }
    }
    for pattern in patterns {
      let range = NSRange(out.startIndex..., in: out)
      out = pattern.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: "$1" + masked)
    }
    return out
  }

  /// `?key=...`, `&key=...`, `DeepL-Auth-Key ...`, `x-goog-api-key: ...`, `Bearer ...`.
  private static let patterns: [NSRegularExpression] = [
    "(?i)([?&](?:key|api_key|apikey|auth_key|token)=)[^&\\s\"\\\\]+",
    "(?i)(DeepL-Auth-Key\\s+)[^\\s\"\\\\]+",
    "(?i)(x-goog-api-key\\s*[:=]\\s*)[^\\s\"\\\\]+",
    "(?i)(Bearer\\s+)[^\\s\"\\\\]+",
  ].compactMap { try? NSRegularExpression(pattern: $0) }

  // MARK: - Dönüştürme

  private static func redactedObject(_ json: [String: Any]) -> DiagFields {
    var out = DiagFields()
    for key in json.keys.sorted() { out[key] = redacted(key, json[key] as Any) }
    return out
  }

  private static func redacted(_ key: String, _ value: Any) -> DiagValue {
    if key == "glossary" { return glossarySummary(value as? String ?? "") }
    if isSecretField(key) {
      let filled = !((value as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      return .object(["set": .bool(filled)])
    }
    if let map = value as? [String: Any] { return .object(redactedObject(map)) }
    if let list = value as? [Any] {
      return .array(list.map { item -> DiagValue in
        if let map = item as? [String: Any] { return .object(redactedObject(map)) }
        return convert(item)
      })
    }
    return convert(value)
  }

  /// Sözlüğün içeriği değil yalnız büyüklüğü: satır, terim ve korunan terim sayısı.
  static func glossarySummary(_ text: String) -> DiagValue {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var fields: DiagFields = ["set": .bool(!trimmed.isEmpty)]
    fields["lines"] = .int(trimmed.isEmpty ? 0 : trimmed.split(separator: "\n", omittingEmptySubsequences: true).count)
    if let data = trimmed.data(using: .utf8), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      fields["terms"] = .int((root["terms"] as? [String: Any])?.count ?? 0)
      fields["keep"] = .int((root["keep"] as? [Any])?.count ?? 0)
    } else if !trimmed.isEmpty {
      fields["valid"] = .bool(false)
    }
    return .object(fields)
  }

  /// Gizli alan süzmesi olmadan düz dönüşüm (yalnız karşılaştırma ve gizli olmayan değerler için).
  static func convert(_ value: Any) -> DiagValue {
    if JsonNumber.isBoolean(value), let flag = value as? Bool { return .bool(flag) }
    if let text = value as? String { return .string(text) }
    if type(of: value) == Int.self, let number = value as? Int { return .int(number) }
    if type(of: value) == Double.self, let number = value as? Double { return .double(number) }
    if let number = value as? NSNumber {
      return CFNumberIsFloatType(number as CFNumber) ? .double(number.doubleValue) : .int(number.intValue)
    }
    if let map = value as? [String: Any] {
      var out = DiagFields()
      for key in map.keys.sorted() { out[key] = convert(map[key] as Any) }
      return .object(out)
    }
    if let list = value as? [Any] { return .array(list.map(convert)) }
    return .null
  }

  private static func flatten(_ json: [String: Any], prefix: String) -> [(String, Any)] {
    var out: [(String, Any)] = []
    for key in json.keys.sorted() {
      let path = prefix.isEmpty ? key : prefix + "." + key
      if let map = json[key] as? [String: Any] {
        out.append(contentsOf: flatten(map, prefix: path))
      } else {
        out.append((path, json[key] as Any))
      }
    }
    return out
  }
}

/// Kaydın sınırları: biri dolunca kayıt kendiliğinden durur.
struct DiagnosticLimits: Equatable {
  var maxSeconds: Double = 15 * 60
  var maxBytes = 40 * 1024 * 1024
  var maxFrames = 600
  /// Boş alan bunun altındaysa kayıt başlamaz (kayıt + paylaşılacak zip kopyası + pay).
  var minFreeBytes: Int64 = 200 * 1024 * 1024
  /// Telefonda en çok bu kadar kayıt durur; yenisi için eskisi silinmeli.
  var maxSessions = 3
  /// Nabız (durum özeti ve kare) aralığı, sn.
  var pulseSeconds: Double = 10
}

/// Kaydın neden durduğu.
enum DiagnosticStop: String {
  case manual, duration, size, frames, failed, terminated
}

/// Kayıt sürerken sayaçlar ve sınır denetimi (saf; saat dışarıdan).
struct DiagnosticBudget {
  let limits: DiagnosticLimits
  let startedAt: Double
  private(set) var bytes = 0
  private(set) var frames = 0
  private(set) var events = 0

  init(limits: DiagnosticLimits, startedAt: Double) {
    self.limits = limits
    self.startedAt = startedAt
  }

  mutating func addEvent(bytes count: Int) {
    events += 1
    bytes += count
  }

  mutating func addFrame(bytes count: Int) {
    frames += 1
    bytes += count
  }

  /// Bu boyda bir kare boyut sınırını aşmadan yazılabilir mi.
  func fitsFrame(bytes count: Int) -> Bool { bytes + count <= limits.maxBytes }

  /// Kare kotası dolmadı mı.
  func acceptsFrame(reserved: Int) -> Bool { reserved < limits.maxFrames }

  /// Dolan ilk sınır; yoksa nil.
  func exceeded(now: Double) -> DiagnosticStop? {
    if now - startedAt >= limits.maxSeconds { return .duration }
    if bytes >= limits.maxBytes { return .size }
    if frames >= limits.maxFrames { return .frames }
    return nil
  }
}

/// events.jsonl okuma: yalnız satır sonuyla biten ve çözülebilen satırlar sayılır; yarım kalan son satır yok sayılır.
enum DiagnosticReader {
  static func events(_ data: Data) -> (events: [[String: Any]], skipped: Int) {
    var events: [[String: Any]] = []
    var skipped = 0
    var start = data.startIndex
    while start < data.endIndex {
      guard let end = data[start...].firstIndex(of: 0x0A) else {
        skipped += 1  // satır sonu yok: uygulama yazarken kapandı
        break
      }
      let line = data[start..<end]
      if !line.isEmpty {
        if let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
          events.append(object)
        } else {
          skipped += 1
        }
      }
      start = data.index(after: end)
    }
    return (events, skipped)
  }

  /// Dosyanın sağlam kısmının uzunluğu: son satır sonuna kadar (yarım son satır atılınca kalacak bayt).
  static func completeLength(_ data: Data) -> Int {
    guard let last = data.lastIndex(of: 0x0A) else { return 0 }
    return data.distance(from: data.startIndex, to: last) + 1
  }

  /// Tam satır sayısı (satır sonları).
  static func lineCount(_ data: Data) -> Int { data.reduce(0) { $0 + ($1 == 0x0A ? 1 : 0) } }

  /// Son tam satır (çözülebiliyorsa).
  static func lastEvent(_ data: Data) -> [String: Any]? {
    let length = completeLength(data)
    guard length > 0 else { return nil }
    let body = data.prefix(length - 1)
    let start = body.lastIndex(of: 0x0A).map { body.index(after: $0) } ?? body.startIndex
    return try? JSONSerialization.jsonObject(with: Data(body[start...])) as? [String: Any]
  }

  /// İlk satır (oturum bilgisi).
  static func firstEvent(_ data: Data) -> [String: Any]? {
    guard let end = data.firstIndex(of: 0x0A) else { return nil }
    return try? JSONSerialization.jsonObject(with: Data(data[data.startIndex..<end])) as? [String: Any]
  }
}

/// Okuma adımlarının tanı biçimi (VisionReader'ın kullandığı saf yapılar).
enum DiagRead {
  /// Vision gözlemi: metin, güven, kutu (tüm karede 0–1: sol, üst, sağ, alt) ve okunan alandaki piksel boyu.
  /// [cropX]/[cropY]: alanın karedeki yeri (piksel).
  static func observation(_ o: TextObservation, cropX: Int, cropY: Int, frameWidth: Int, frameHeight: Int) -> DiagValue {
    let w = Double(max(frameWidth, 1)), h = Double(max(frameHeight, 1))
    let box = TextBox(left: Double(cropX + o.left) / w, top: Double(cropY + o.top) / h,
                      right: Double(cropX + o.right) / w, bottom: Double(cropY + o.bottom) / h)
    return .object(["text": .string(o.text), "conf": .double(o.confidence), "box": DiagValue.box(box),
                    "px": .array([.int(o.left), .int(o.top), .int(o.right), .int(o.bottom)]), "h": .int(o.height)])
  }

  static func observations(_ list: [TextObservation], cropX: Int, cropY: Int, frameWidth: Int, frameHeight: Int) -> DiagValue {
    .array(list.map { observation($0, cropX: cropX, cropY: cropY, frameWidth: frameWidth, frameHeight: frameHeight) })
  }

  /// Seçim adımları: güven elemesi, kesik kenar elemesi, bloklar ve puanları, seçilen bloğun sırası (ReadingSelector.select
  /// ile aynı hesap).
  static func selection(_ input: [TextObservation], width: Int, height: Int) -> DiagValue {
    let confident = ReadingSelector.filterConfidence(input)
    let uncut = ReadingSelector.dropEdgeCut(confident, width: width)
    let blocks = ReadingSelector.blocks(uncut)
    var best = -1
    var bestScore = -Double.infinity
    var list: [DiagValue] = []
    for (index, block) in blocks.enumerated() {
      let score = ReadingSelector.score(block, width: width, height: height)
      // pickBlock: tek blok puansız seçilir; birden çokta ilk en yüksek puan.
      if blocks.count == 1 || score > bestScore { best = index; bestScore = score }
      list.append(.object(["texts": DiagValue.strings(block.map(\.text)), "score": .double(score)]))
    }
    var fields: DiagFields = ["lowConfidence": DiagValue.strings(input.filter { !confident.contains($0) }.map(\.text))]
    fields["edgeCut"] = DiagValue.strings(confident.filter { !uncut.contains($0) }.map(\.text))
    fields["blocks"] = .array(list)
    fields["chosenBlock"] = .int(best)
    return .object(fields)
  }

  /// Satır yüksekliği hesabının ara değerleri.
  static func lineHeight(_ t: LineHeight.Trace) -> DiagValue {
    var fields: DiagFields = ["frameHeight": .int(t.frameHeight), "onlyLong": .bool(t.onlyLong)]
    fields["pieces"] = .array(t.pieces.map { p -> DiagValue in
      .object(["text": .string(p.text), "chars": .int(p.characters), "hPx": .int(p.heightPx), "wPx": .int(p.widthPx),
               "ratio": DiagValue.optional(p.ratio), "lines": DiagValue.optional(p.linesGuess), "perLine": .double(p.perLine)])
    })
    fields["typical"] = .double(t.typical)
    fields["single"] = DiagValue.doubles(t.single)
    fields["upperMedianPx"] = .double(t.upper)
    fields["ratio"] = .double(t.ratio)
    fields["inRange"] = .bool(t.inRange)
    fields["min"] = .double(LineHeight.MIN_RATIO)
    fields["max"] = .double(LineHeight.MAX_RATIO)
    fields["estimate"] = DiagValue.optional(t.result)
    return .object(fields)
  }

  static func boxes(_ list: [TextBox]) -> DiagValue { .array(list.map { DiagValue.box($0) }) }
}

/// Kayıt ve paylaşım dosyası adları.
enum DiagnosticNames {
  /// Kayıt klasörü: yyyyMMdd-HHmmss (yerel saat).
  static func sessionId(_ date: Date, timeZone: TimeZone = .current) -> String {
    stamp(date, "yyyyMMdd-HHmmss", timeZone)
  }

  /// gametranslator-tani-<sürüm>-<yyyyMMdd-HHmm>; sürümdeki dosya adına uygun olmayan karakterler atılır.
  static func exportBase(version: String, sessionId: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
    let cleanVersion = String(version.unicodeScalars.filter { allowed.contains($0) && $0.isASCII })
    let minute = sessionId.count >= 13 ? String(sessionId.prefix(13)) : sessionId
    return "gametranslator-tani-\(cleanVersion.isEmpty ? "0" : cleanVersion)-\(minute)"
  }

  /// Kayıt kimliği yalnız rakam ve tireden oluşmalı (klasör dışına çıkılmasın).
  static func isValidId(_ id: String) -> Bool {
    !id.isEmpty && id.count <= 32 && id.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || $0 == "-" }
  }

  private static func stamp(_ date: Date, _ format: String, _ timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = format
    return formatter.string(from: date)
  }
}
