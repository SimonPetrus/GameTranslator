// SPDX-License-Identifier: AGPL-3.0-only
// Core/SubtitleRows.swift testleri: konuşma ↔ okuma satırı kutuları (TurnRows), TV çerçevesi ve /hello (SubtitleWire),
// hattın rows'u taşıması (Kotlin karşılığı yok).
import Foundation

enum SubtitleRowsTest {
  static let b1 = TextBox(left: 0.30, top: 0.80, right: 0.70, bottom: 0.84)
  static let b2 = TextBox(left: 0.32, top: 0.85, right: 0.68, bottom: 0.89)
  static let b3 = TextBox(left: 0.35, top: 0.90, right: 0.65, bottom: 0.94)

  private static func layout(_ lines: [String], _ boxes: [TextBox]) -> ReadLayout {
    ReadLayout(lines: lines, boxes: boxes)!
  }

  private static func boxes(_ lines: [String], _ boxes: [TextBox], known: Set<String> = []) -> [TextBox]? {
    TurnRows.boxes(source: lines.joined(separator: "\n"), layout: layout(lines, boxes), known: known)
  }

  static func run() {
    TestRun.test("TurnRowsTest.twoSpeakersOnTwoLines") {
      assertEquals([b1, b2], boxes(["ENZO: Get down!", "MARIA: Who is that?"], [b1, b2]))
      assertEquals([b1, b2], boxes(["- Run!", "- Where?"], [b1, b2]))
      // Tireden sonra boşluk yok: konuşma "- Run!" olur, kutusu yine o satırınki.
      assertEquals([b1, b2], boxes(["-Run!", "-Where?"], [b1, b2]))
    }
    TestRun.test("TurnRowsTest.continuationThenTwoSpeakersOnThreeLines") {
      assertEquals([b1, b2, b3], boxes(["It's your rec time, not mine.", "Devin: No, bitch.", "Connie: Oh, damn."], [b1, b2, b3]))
    }
    TestRun.test("TurnRowsTest.wrappedTurnGetsTheUnionOfItsLines") {
      // Shayna'nın iki satıra sarılmış cümlesi tek konuşma: kutusu iki satırın birleşimi (0.30, 0.80, 0.70, 0.89).
      let wrapped = TextBox(left: 0.30, top: 0.80, right: 0.70, bottom: 0.89)
      assertEquals([wrapped, b3],
                   boxes(["Shayna: We booked him on a traffic", "violation, so he stays here.", "Guard: Move it."], [b1, b2, b3]))
      assertEquals(wrapped, TurnRows.union([b1, b2]))
    }
    TestRun.test("TurnRowsTest.speakerChangeInsideALineHasNoRows") {
      // İki etiket: satır ortasındaki "Devin:" ayrı konuşma; iki satır üç konuşmaya ayrılamaz.
      assertNull(boxes(["It's your rec time, not mine. Devin: No, bitch.", "Connie: Oh, damn."], [b1, b2]))
      // Tek etiket: yalnız ad yakın geçmişteyse bölünür.
      assertNull(boxes(["It's your rec time, not mine. Devin: No, bitch.", "- Fine."], [b1, b2], known: ["devin"]))
      assertEquals([b1, b2], boxes(["It's your rec time, not mine. Devin: No, bitch.", "- Fine."], [b1, b2]))
    }
    TestRun.test("TurnRowsTest.countMismatchHasNoRows") {
      assertNull(ReadLayout(lines: ["ENZO: Get down!", "MARIA: Who is that?"], boxes: [b1]))
      assertNull(ReadLayout(lines: [], boxes: []))
      let source = "ENZO: Get down!\nMARIA: Who is that?"
      let read = layout(["ENZO: Get down!", "MARIA: Who is that?"], [b1, b2])
      assertEquals([b1, b2], TurnRows.rows(source: source, layout: read, translated: "ENZO: Yere yat!\nMARIA: O da kim?"))
      // Çeviri tek satıra aktı, araya boş satır girdi ya da bir satır boş: TV'nin satırlarıyla tutmaz.
      assertNull(TurnRows.rows(source: source, layout: read, translated: "ENZO: Yere yat! MARIA: O da kim?"))
      assertNull(TurnRows.rows(source: source, layout: read, translated: "ENZO: Yere yat!\n\nMARIA: O da kim?"))
      assertNull(TurnRows.rows(source: source, layout: read, translated: "ENZO: Yere yat!\n "))
      assertNull(TurnRows.rows(source: source, layout: read, translated: "A\nB\nC"))
    }
    TestRun.test("TurnRowsTest.singleTurnHasNoRows") {
      assertNull(boxes(["Shayna: We booked him on a traffic", "violation, so he stays here."], [b1, b2]))
      assertNull(boxes(["ENZO: Get down!"], [b1]))
      assertNull(boxes(["The ferry leaves at", "10:30 sharp."], [b1, b2]))
    }
    TestRun.test("TurnRowsTest.otherReadingHasNoRows") {
      // Çevrilen metin bu okumanın satırları değil (kararlılığın geri getirdiği eski okuma): kutular ona ait değil.
      let read = layout(["ENZO: Get down!", "MARIA: Who is th"], [b1, b2])
      assertNull(TurnRows.boxes(source: "ENZO: Get down!\nMARIA: Who is that?", layout: read))
      assertNull(TurnRows.boxes(source: "ENZO: Get down! MARIA: Who is th", layout: read))
    }

    TestRun.test("SubtitleWireTest.helloReportsActive") {
      assertEquals("{\"active\":true,\"app\":\"gametranslator\"}", SubtitleWire.helloBody(active: true))
      assertEquals("{\"active\":false,\"app\":\"gametranslator\"}", SubtitleWire.helloBody(active: false))
      // TV 1.0.7+ yalnız bu deseni arar; eski TV yalnız "gametranslator" geçmesine bakar.
      assertTrue(SubtitleWire.helloBody(active: true).range(of: "\"active\":true") != nil)
      assertTrue(SubtitleWire.helloBody(active: false).contains("gametranslator"))
    }
    TestRun.test("SubtitleWireTest.frameWithoutRowsIsUnchanged") {
      let box = TextBox(left: 0.2, top: 0.8, right: 0.8, bottom: 0.9)
      // 1.8.4'teki (ve Android'deki) çerçeveyle bayt bayt aynı.
      let old = "event: subtitle\ndata: {\"at\":5,\"box\":{\"bottom\":0.9,\"left\":0.2,\"right\":0.8,\"top\":0.8},\"duration\":15000,\"replace\":true,\"text\":\"Çok \\\"iyi\\\"\\nşey\"}\n\n"
      assertEquals(old, SubtitleWire.subtitleFrame("Çok \"iyi\"\nşey", durationMs: 15000, box: box, replaces: true, at: 5))
      assertEquals(old, SubtitleWire.subtitleFrame("Çok \"iyi\"\nşey", durationMs: 15000, box: box, replaces: true, at: 5, rows: nil))
      assertEquals(old, SubtitleWire.subtitleFrame("Çok \"iyi\"\nşey", durationMs: 15000, box: box, replaces: true, at: 5, rows: []))
      let source = TextBox(left: 0.1, top: 0.8, right: 0.9, bottom: 0.9)
      assertEquals("event: subtitle\ndata: {\"at\":7,\"box\":{\"bottom\":0.9,\"left\":0.2,\"right\":0.8,\"top\":0.8},\"duration\":8000,\"line\":0.034,\"source\":{\"bottom\":0.9,\"left\":0.1,\"right\":0.9,\"top\":0.8},\"text\":\"Merhaba\"}\n\n",
                   SubtitleWire.subtitleFrame("Merhaba", durationMs: 8000, box: box, replaces: false, at: 7, source: source, line: 0.034))
      // Üst düzey kutu yoksa rows yazılmaz (TV onsuz kullanmaz).
      assertEquals("event: subtitle\ndata: {\"at\":1,\"duration\":1000,\"text\":\"A\\nB\"}\n\n",
                   SubtitleWire.subtitleFrame("A\nB", durationMs: 1000, box: nil, replaces: false, at: 1,
                                              rows: [SubtitleRow(box: b1, line: nil), SubtitleRow(box: b2, line: nil)]))
      assertEquals("0.875", SubtitleWire.number(0.8750))
      assertEquals("1", SubtitleWire.number(1.4))
      assertEquals("0", SubtitleWire.number(-0.2))
    }
    TestRun.test("SubtitleWireTest.rowsAreWrittenBetweenReplaceAndSource") {
      let box = TextBox(left: 0.3, top: 0.8, right: 0.7, bottom: 0.89)
      let source = TextBox(left: 0.25, top: 0.8, right: 0.75, bottom: 0.89)
      let frame = SubtitleWire.subtitleFrame("ENZO: Yere yat!\nMARIA: O da kim?", durationMs: 15000, box: box, replaces: true, at: 1,
                                             source: source, line: 0.0342,
                                             rows: [SubtitleRow(box: b1, line: 0.0342), SubtitleRow(box: b2, line: 0.0342)])
      let json = #"{"at":1,"box":{"bottom":0.89,"left":0.3,"right":0.7,"top":0.8},"duration":15000,"line":0.0342,"replace":true,"rows":[{"box":{"bottom":0.84,"left":0.3,"right":0.7,"top":0.8},"line":0.0342},{"box":{"bottom":0.89,"left":0.32,"right":0.68,"top":0.85},"line":0.0342}],"source":{"bottom":0.89,"left":0.25,"right":0.75,"top":0.8},"text":"ENZO: Yere yat!\nMARIA: O da kim?"}"#
      assertEquals("event: subtitle\ndata: " + json + "\n\n", frame)
      // Geçerli JSON; rows sayısı TV'nin text.split("\n") sayısıyla aynı.
      let parsed = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
      let rows = parsed?["rows"] as? [[String: Any]]
      let text = parsed?["text"] as? String ?? ""
      assertEquals(2, rows?.count ?? -1)
      assertEquals(text.components(separatedBy: "\n").count, rows?.count ?? -1)
      // Satır yüksekliği yoksa yalnız kutu yazılır.
      assertEquals(#"[{"box":{"bottom":0.84,"left":0.3,"right":0.7,"top":0.8}},{"box":{"bottom":0.89,"left":0.32,"right":0.68,"top":0.85}}]"#,
                   SubtitleWire.rowsJson([SubtitleRow(box: b1, line: nil), SubtitleRow(box: b2, line: 0)]))
    }

    TestRun.test("PipelineRowsTest.twoSpeakersSendTheirBoxes") {
      let f = RowsFixture()
      f.p.onRead(["ENZO: Get down!", "MARIA: Who is that?"], whole, lineBoxes: [b1, b2])
      assertEquals(["ENZO: Yere yat!\nMARIA: O da kim?"], f.sink.texts)
      assertEquals([b1, b2], f.sink.lastRows)
    }
    TestRun.test("PipelineRowsTest.noRowsWithoutLineBoxesBoxOrMatchingCount") {
      let f = RowsFixture()
      f.p.onRead(["ENZO: Get down!", "MARIA: Who is that?"], whole)
      assertEquals(["ENZO: Yere yat!\nMARIA: O da kim?"], f.sink.texts)
      assertNull(f.sink.lastRows, "satır kutusu verilmedi (1.8.4 çağrısı)")
      let g = RowsFixture()
      g.p.onRead(["ENZO: Get down!", "MARIA: Who is that?"], nil, lineBoxes: [b1, b2])
      assertEquals(1, g.sink.texts.count)
      assertNull(g.sink.lastRows, "üst düzey kutu yok")
      let h = RowsFixture()
      h.p.onRead(["ENZO: Get down!", "MARIA: Who is that?"], whole, lineBoxes: [b1])
      assertEquals(1, h.sink.texts.count)
      assertNull(h.sink.lastRows, "kutu sayısı satır sayısını tutmuyor")
    }
    TestRun.test("PipelineRowsTest.wrappedSingleSpeakerHasNoRows") {
      let f = RowsFixture()
      f.p.onRead(["Shayna: We booked him on a traffic", "violation, so he stays here."], whole, lineBoxes: [b1, b2])
      assertEquals(["Shayna: Onu trafik ihlalinden aldık, burada kalıyor."], f.sink.texts)
      assertNull(f.sink.lastRows)
    }
    TestRun.test("PipelineRowsTest.restoredLineFromCacheKeepsRows") {
      let f = RowsFixture()
      f.p.onRead(["ENZO: Get down!", "MARIA: Who is that?"], whole, lineBoxes: [b1, b2])
      f.clock.now = 100
      f.p.onRead([], nil)
      f.clock.now = 1100
      f.p.onRead([], nil)
      assertEquals(1, f.sink.clears)
      // Satır 400 ms sonra geri geldi: önbellekten gösterilir, kutular bu okumanınkiler.
      f.clock.now = 1500
      f.p.onRead(["ENZO: Get down!", "MARIA: Who is that?"], whole, lineBoxes: [b1, b2])
      assertEquals(1, f.calls)
      assertEquals(2, f.sink.texts.count)
      assertEquals([b1, b2], f.sink.lastRows)
    }
    TestRun.test("PipelineRowsTest.lineResentAfterAsideKeepsRows") {
      let f = RowsFixture()
      f.p.onRead(["ENZO: Get down!", "MARIA: Who is that?"], whole, lineBoxes: [b1, b2])
      f.clock.now = 5000
      let mark = f.p.showAside("Görev: anahtarı bul.", durationMs: 8000, unlessResetSince: f.p.resetCount)
      assertNull(f.sink.lastRows, "ek gösterimde rows yok")
      f.clock.now = 13000
      assertTrue(f.p.resumeAfterAside(mark ?? -1))
      assertEquals("ENZO: Yere yat!\nMARIA: O da kim?|2000", f.sink.log.last ?? "")
      assertEquals([b1, b2], f.sink.lastRows)
    }
    TestRun.test("PipelineRowsTest.revisedReadingSendsItsOwnBoxes") {
      let f = RowsFixture()
      let wider = TextBox(left: 0.28, top: 0.80, right: 0.72, bottom: 0.84)
      f.p.onRead(["ENZO: We can go to the city now.", "MARIA: Who is that?"], whole, lineBoxes: [b1, b2])
      f.clock.now = 200
      f.p.onRead(["ENZO: We can not go to the city now.", "MARIA: Who is that?"], whole, lineBoxes: [wider, b2])
      assertEquals(["ENZO: Şehre şimdi gidebiliriz.\nMARIA: O da kim?", "ENZO: Şehre şimdi gidemeyiz.\nMARIA: O da kim?"], f.sink.texts)
      assertEquals([false, true], f.sink.replaces)
      assertEquals([wider, b2], f.sink.lastRows)
    }
  }

  static let whole = TextBox(left: 0.28, top: 0.80, right: 0.72, bottom: 0.94)
}

/// rows'u da kaydeden alıcı (4 parametreli show: ek gösterim).
final class RowsSink: SubtitleSink {
  var texts: [String] = []
  var log: [String] = []
  var replaces: [Bool] = []
  var rows: [[TextBox]?] = []
  var clears = 0

  var lastRows: [TextBox]? { rows.last ?? nil }

  func show(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool) {
    show(text, durationMs: durationMs, box: box, replaces: replaces, rows: nil)
  }

  func show(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool, rows: [TextBox]?) {
    texts.append(text)
    log.append("\(text)|\(durationMs)")
    self.replaces.append(replaces)
    self.rows.append(rows)
  }

  func clear() { clears += 1 }
}

/// Doğrudan çalışan hat, sahte saat (kararlılık ve kalan süre) ve satır satır sözlük çevirmeni.
final class RowsFixture {
  let clock = FakeClock()
  let sink = RowsSink()
  var calls = 0
  var p: SubtitlePipeline!

  private static let tr: [String: String] = [
    "Get down!": "Yere yat!",
    "Who is that?": "O da kim?",
    "We can go to the city now.": "Şehre şimdi gidebiliriz.",
    "We can not go to the city now.": "Şehre şimdi gidemeyiz.",
    "Shayna: We booked him on a traffic violation, so he stays here.": "Shayna: Onu trafik ihlalinden aldık, burada kalıyor.",
  ]

  init() {
    let clock = self.clock
    p = SubtitlePipeline(translator: FunctionTranslator { [unowned self] text in
      self.calls += 1
      return text.split(separator: "\n").map { RowsFixture.tr[String($0)] ?? "?" }.joined(separator: "\n")
    }, sink: sink, translateExecutor: { $0() }, stabilizer: SubtitleStabilizer(clock: { clock.now }))
    p.contextClock = { Double(clock.now) / 1000 }
  }
}
