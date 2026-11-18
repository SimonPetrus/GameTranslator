// SPDX-License-Identifier: AGPL-3.0-only
// Yalnız iOS'ta (henüz): Kotlin karşılığı yok. TV protokolü tv/webos/app.js'in başındaki yorumdadır.
import Foundation

/// Bir okumanın satırları ve her satırın oyundaki kutusu (yukarıdan aşağı, aynı sayıda). Hat bunu okunan metinle
/// birlikte taşır; birden çok konuşmalı altyazıda her konuşmanın kutusu buradan çıkar ([TurnRows]).
struct ReadLayout: Equatable {
  let lines: [String]
  let boxes: [TextBox]

  /// Satır yoksa ya da satır ve kutu sayısı tutmuyorsa nil.
  init?(lines: [String], boxes: [TextBox]) {
    guard !lines.isEmpty, lines.count == boxes.count else { return nil }
    self.lines = lines
    self.boxes = boxes
  }
}

/// Altyazı olayındaki `rows` öğesi: bir satırın (konuşmanın) oyundaki yeri ve isteğe bağlı satır yüksekliği.
struct SubtitleRow: Equatable {
  var box: TextBox
  var line: Double?
}

/// Birden çok konuşmalı altyazıda ([SpeakerTurns]) her konuşmanın oyundaki kutusu: konuşmayı oluşturan okuma
/// satırlarının birleşik kutusu (sarılmış iki satır → ikisinin birleşimi). TV örtme yerleşiminde her satırı kendi
/// kutusuna koyar. Kutular konuşmalara ayrılamıyorsa (satır içi konuşmacı değişimi) nil: TV birleşik kutuyu kullanır.
enum TurnRows {
  /// [source]: hattın çevirdiği metin; [layout] onun okumasıdır (satırları aynı olmalı, yoksa nil). Tek konuşmada nil.
  static func boxes(source: String, layout: ReadLayout, known: Set<String> = []) -> [TextBox]? {
    let lines = layout.lines.map { KotlinText.trim($0) }
    guard lines.count >= 2, !lines.contains(where: { $0.isEmpty }) else { return nil }
    // Çevrilen metin bu okumanın satırlarından oluşmalı (geri gelen eski okuma ya da başka satır değil).
    let sourceLines = KotlinText.split(SubtitleSegmenter.replacingCRLF(KotlinText.units(source)), 0x0A)
      .map { KotlinText.string(KotlinText.trim($0)) }
    guard sourceLines.count == lines.count, zip(sourceLines, lines).allSatisfy({ KotlinText.same($0.0, $0.1) }) else { return nil }
    let turns = SpeakerTurns.split(source, known: known)
    guard turns.count >= 2 else { return nil }
    // Her satırın konuşması: etiketli ya da tireli satır yeni konuşma başlatır (SubtitleSegmenter.split'in kuralı);
    // satırın yeni konuşma açıp açmadığı, ilk satırlara eklenince konuşma bloğu sayısının artmasından anlaşılır.
    var groups: [[Int]] = []
    var blocks = 0
    for index in lines.indices {
      let count = blockCount(Array(lines[...index]))
      if count > blocks || groups.isEmpty { groups.append([index]) } else { groups[groups.count - 1].append(index) }
      blocks = count
    }
    // Satır içi konuşmacı değişimi (bir bloktan iki konuşma) ya da boş konuşma: kutular konuşmalara ayrılamaz.
    guard groups.count == turns.count else { return nil }
    for (turn, group) in zip(turns, groups) {
      let block = group.map { lines[$0] }.joined(separator: " ")
      guard withoutWhitespace(turn) == withoutWhitespace(block) else { return nil }
    }
    return groups.map { group in union(group.map { layout.boxes[$0] }) }
  }

  /// [boxes] ve çevirinin satır sayısı (TV'nin `text.split("\n")`'i, boş satırlar dahil) tutarsa kutular; yoksa nil.
  static func rows(source: String, layout: ReadLayout, translated: String, known: Set<String> = []) -> [TextBox]? {
    guard let boxes = boxes(source: source, layout: layout, known: known) else { return nil }
    let parts = KotlinText.split(KotlinText.units(translated), 0x0A)
    guard parts.count == boxes.count, !parts.contains(where: { KotlinText.isBlank(KotlinText.string($0)) }) else { return nil }
    return boxes
  }

  /// Kutuların birleşimi (en soldaki sol kenar, en üstteki üst kenar...). Boş dizi verilmez.
  static func union(_ boxes: [TextBox]) -> TextBox {
    TextBox(left: boxes.map(\.left).min() ?? 0, top: boxes.map(\.top).min() ?? 0,
            right: boxes.map(\.right).max() ?? 0, bottom: boxes.map(\.bottom).max() ?? 0)
  }

  /// Metnin konuşma bloğu sayısı: SubtitleSegmenter.split'teki satır sonu ayraçları + 1 (boş metinde 0).
  private static func blockCount(_ lines: [String]) -> Int {
    let pieces = SubtitleSegmenter.split(lines.joined(separator: "\n"))
    if pieces.isEmpty { return 0 }
    return pieces.filter { !$0.translate && $0.text == "\n" }.count + 1
  }

  private static func withoutWhitespace(_ text: String) -> UTF16Text {
    KotlinText.units(text).filter { !KotlinText.isWhitespace($0) }
  }
}

/// TV'ye giden çerçevelerin ve /hello yanıtının metni (Android'deki SubtitleServer.kt ile bayt bayt aynı; yeni alanlar
/// yalnız verildiğinde yazılır). Saf: sunucu (SubtitleServer) yalnız gönderir.
enum SubtitleWire {
  /// /hello yanıtı. TV küçük harfle "gametranslator" arar; "active":true çeviri çalışırken (TV 1.0.7+ boştaki
  /// sunucuyu bırakıp çeviri yapanı arar). Alanlar alfabetik.
  static func helloBody(active: Bool) -> String { "{\"active\":\(active),\"app\":\"gametranslator\"}" }

  static func jsonString(_ text: String) -> String {
    var out = "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      default:
        if scalar.value < 0x20 {
          out += String(format: "\\u%04x", scalar.value)
        } else {
          out.unicodeScalars.append(scalar)
        }
      }
    }
    return out + "\""
  }

  /// Dört basamağa yuvarlanır, sondaki sıfırlar atılır (0.8750 → 0.875).
  static func number(_ value: Double) -> String {
    var text = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), min(1.0, max(0.0, value)))
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text.isEmpty ? "0" : text
  }

  static func boxJson(_ b: TextBox) -> String {
    "{\"bottom\":\(number(b.bottom)),\"left\":\(number(b.left)),\"right\":\(number(b.right)),\"top\":\(number(b.top))}"
  }

  /// `[{"box":{...},"line":0.034}, ...]`; line yalnız verildiyse ve sıfırdan büyükse yazılır.
  static func rowsJson(_ rows: [SubtitleRow]) -> String {
    "[" + rows.map { row -> String in
      var item = "{\"box\":" + boxJson(row.box)
      if let line = row.line, line > 0 { item += ",\"line\":" + number(line) }
      return item + "}"
    }.joined(separator: ",") + "]"
  }

  static func frame(_ name: String, _ json: String) -> String { "event: \(name)\ndata: \(json)\n\n" }

  /// Alanlar alfabetik sırada (Windows'taki SortedDictionary gibi); source, line ve rows yalnız verildiyse yazılır.
  /// rows yalnız üst düzey box varken yazılır (TV onsuz kullanmaz).
  static func subtitleFrame(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool, at: Int64,
                            source: TextBox? = nil, line: Double? = nil, rows: [SubtitleRow]? = nil) -> String {
    var json = "{\"at\":\(at)"
    if let box { json += ",\"box\":" + boxJson(box) }
    json += ",\"duration\":\(durationMs)"
    if let line, line > 0 { json += ",\"line\":" + number(line) }
    if replaces { json += ",\"replace\":true" }
    if box != nil, let rows, !rows.isEmpty { json += ",\"rows\":" + rowsJson(rows) }
    if let source { json += ",\"source\":" + boxJson(source) }
    json += ",\"text\":" + jsonString(text) + "}"
    return frame("subtitle", json)
  }
}
