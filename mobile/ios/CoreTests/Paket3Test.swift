// SPDX-License-Identifier: AGPL-3.0-only
// Paket 3 saf parçalarının testleri: altyazı geçmişi, çökme kaydı biçimi, demo satırları, ek okuma alanı, kare hızı
// ölçümü ve çeviri hattının "kim çevirdi" bilgisi (Kotlin karşılığı yok).
import Foundation

enum SubtitleHistoryTest {
  private static func entry(_ text: String, at: Int = 1, source: String = "src", engine: String = "google") -> HistoryEntry {
    HistoryEntry(at: at, source: source, text: text, engine: engine)
  }

  static func run() {
    TestRun.test("SubtitleHistoryTest.ringDropsOldestAndSkipsConsecutiveDuplicates") {
      var ring = HistoryRing(capacity: 3)
      assertTrue(ring.add(entry("a")))
      assertTrue(ring.add(entry("b")))
      assertFalse(ring.add(entry("b", at: 2)), "art arda aynı çeviri eklenmez")
      assertTrue(ring.add(entry("c")))
      assertTrue(ring.add(entry("d")))
      assertEquals(3, ring.count)
      assertEquals(["d", "c", "b"], ring.newestFirst.map { $0.text })
    }
    TestRun.test("SubtitleHistoryTest.duplicateOnlyCountsWhenConsecutive") {
      var ring = HistoryRing(capacity: 10)
      ring.add(entry("a"))
      ring.add(entry("b"))
      assertTrue(ring.add(entry("a")))
      assertEquals(3, ring.count)
    }
    TestRun.test("SubtitleHistoryTest.defaultCapacityIs200") {
      var ring = HistoryRing()
      for i in 0..<250 { ring.add(entry("line \(i)")) }
      assertEquals(200, ring.count)
      assertEquals("line 249", ring.newestFirst.first?.text ?? "")
      assertEquals("line 50", ring.newestFirst.last?.text ?? "")
    }
    TestRun.test("SubtitleHistoryTest.codecRoundTripAndCorruptFile") {
      let entries = [entry("Merhaba", at: 5, source: "Hello", engine: "pack"), entry("Elveda", at: 6, source: "Bye", engine: "")]
      let data = HistoryCodec.encode(entries)
      assertNotNull(data)
      assertEquals(entries, HistoryCodec.decode(data))
      assertEquals([HistoryEntry](), HistoryCodec.decode(nil))
      assertEquals([HistoryEntry](), HistoryCodec.decode(Data("not json".utf8)))
      assertEquals([HistoryEntry](), HistoryCodec.decode(Data("{\"version\":99,\"entries\":[]}".utf8)))
      assertEquals([HistoryEntry](), HistoryCodec.decode(Data("[1,2]".utf8)))
      // Bozuk satırlar atlanır, sağlam olanlar kalır.
      let mixed = Data("{\"version\":1,\"entries\":[7,{\"text\":\"\"},{\"at\":3,\"source\":\"s\",\"text\":\"ok\",\"engine\":\"x\"}]}".utf8)
      assertEquals([entry("ok", at: 3, source: "s", engine: "x")], HistoryCodec.decode(mixed))
    }
    TestRun.test("SubtitleHistoryTest.logPersistsReloadsAndClears") {
      let storage = MemoryCacheStorage()
      let log = SubtitleHistoryLog(storage: storage, capacity: 5, saveDelay: 3600, now: { 1000 })
      log.record(source: "Hello", text: "Merhaba", engine: "pack")
      log.record(source: "World", text: "Dünya", engine: "google")
      log.record(source: "World", text: "Dünya", engine: "google")
      log.record(source: "x", text: "   ", engine: "google")
      assertEquals(2, log.count)
      log.flush()
      assertEquals(1, storage.writes)

      let reloaded = SubtitleHistoryLog(storage: storage, capacity: 5, saveDelay: 3600, now: { 2000 })
      let list = reloaded.list()
      assertEquals(2, list.count)
      assertEquals("Dünya", list[0]["text"] as? String ?? "")
      assertEquals("google", list[0]["engine"] as? String ?? "")
      assertEquals("Merhaba", list[1]["text"] as? String ?? "")
      assertEquals(1000, list[1]["at"] as? Int ?? 0)
      reloaded.record(source: "Next", text: "Sonraki", engine: "gemini")
      assertEquals("Sonraki", reloaded.list()[0]["text"] as? String ?? "")
      assertEquals(2000, reloaded.list()[0]["at"] as? Int ?? 0)

      reloaded.clear()
      assertEquals(0, reloaded.list().count)
      assertEquals(0, SubtitleHistoryLog(storage: storage, saveDelay: 3600).count)
    }
    TestRun.test("SubtitleHistoryTest.corruptStorageStartsEmpty") {
      let storage = MemoryCacheStorage()
      storage.data = Data("{{{".utf8)
      let log = SubtitleHistoryLog(storage: storage, saveDelay: 3600)
      assertEquals(0, log.count)
      log.record(source: "a", text: "b", engine: "")
      assertEquals(1, log.list().count)
    }
    TestRun.test("SubtitleHistoryTest.loadKeepsNewestWithinCapacity") {
      let storage = MemoryCacheStorage()
      storage.data = HistoryCodec.encode((0..<10).map { entry("t\($0)", at: $0) })
      let log = SubtitleHistoryLog(storage: storage, capacity: 4, saveDelay: 3600)
      let texts = log.list().map { $0["text"] as? String ?? "" }
      assertEquals(["t9", "t8", "t7", "t6"], texts)
    }
    TestRun.test("SubtitleHistoryTest.veryLongTextIsTrimmed") {
      let storage = MemoryCacheStorage()
      let log = SubtitleHistoryLog(storage: storage, saveDelay: 3600)
      log.record(source: String(repeating: "s", count: 5000), text: String(repeating: "t", count: 5000), engine: "")
      let row = log.list()[0]
      assertEquals(SubtitleHistoryLog.maxTextLength, (row["text"] as? String ?? "").count)
      assertEquals(SubtitleHistoryLog.maxTextLength, (row["source"] as? String ?? "").count)
    }
  }
}

enum CrashFormatTest {
  static func run() {
    TestRun.test("CrashFormatTest.signalLineParses") {
      let record = CrashFormat.parse(CrashFormat.signalLine(at: 1_700_000_000, signal: 11))
      assertEquals(CrashRecord(at: 1_700_000_000_000, kind: "signal", name: "SIGSEGV", detail: "Sinyal 11"), record ?? CrashRecord(at: 0, kind: "", name: "", detail: ""))
      assertEquals("SIGABRT", CrashFormat.signalName(6))
      assertEquals("SIGTRAP", CrashFormat.signalName(5))
      assertEquals("SIG31", CrashFormat.signalName(31))
      assertTrue(CrashFormat.signalLine(at: 1, signal: 2).hasPrefix(CrashFormat.signalPrefix))
      assertEquals("GTCRASH1|S|12|6\n", CrashFormat.signalLine(at: 12, signal: 6))
    }
    TestRun.test("CrashFormatTest.exceptionLineParsesAndIsSanitized") {
      let line = CrashFormat.exceptionLine(at: 100, name: "NSInvalidArgumentException", reason: "bad | thing\nnext", stack: "a; b")
      assertEquals(1, line.filter { $0 == "\n" }.count)
      let record = CrashFormat.parse(line)
      assertNotNull(record)
      assertEquals("exception", record?.kind ?? "")
      assertEquals("NSInvalidArgumentException", record?.name ?? "")
      assertEquals("bad / thing next @ a; b", record?.detail ?? "")
      assertEquals(100_000, record?.at ?? 0)
    }
    TestRun.test("CrashFormatTest.abortRightAfterExceptionReportsTheException") {
      let text = CrashFormat.exceptionLine(at: 100, name: "NSRangeException", reason: "r", stack: "") + CrashFormat.signalLine(at: 101, signal: 6)
      assertEquals("exception", CrashFormat.parse(text)?.kind ?? "")
      assertEquals("NSRangeException", CrashFormat.parse(text)?.name ?? "")
      // Lone abort, or an abort long after an old exception, is its own crash.
      assertEquals("signal", CrashFormat.parse(CrashFormat.signalLine(at: 101, signal: 6))?.kind ?? "")
      let late = CrashFormat.exceptionLine(at: 100, name: "NSRangeException", reason: "r", stack: "") + CrashFormat.signalLine(at: 500, signal: 6)
      assertEquals("signal", CrashFormat.parse(late)?.kind ?? "")
      // A different signal after an exception is reported as is.
      let other = CrashFormat.exceptionLine(at: 100, name: "NSRangeException", reason: "r", stack: "") + CrashFormat.signalLine(at: 101, signal: 11)
      assertEquals("SIGSEGV", CrashFormat.parse(other)?.name ?? "")
    }
    TestRun.test("CrashFormatTest.garbageAndPartialLinesAreIgnored") {
      assertNull(CrashFormat.parse(""))
      assertNull(CrashFormat.parse("hello\nGTCRASH1|S|12\nGTCRASH1|S|x|11\nGTCRASH1|Q|1|2\n"))
      let text = "junk\nGTCRASH1|S|50|8\nGTCRASH1|S|9"
      assertEquals("SIGFPE", CrashFormat.parse(text)?.name ?? "")
    }
    TestRun.test("CrashFormatTest.sanitizeLimitsLength") {
      assertEquals("a/b c", CrashFormat.sanitize("a|b\nc", limit: 10))
      assertEquals(5, CrashFormat.sanitize(String(repeating: "x", count: 100), limit: 5).count)
    }
    TestRun.test("CrashFormatTest.messageIsTurkish") {
      let signal = CrashRecord(at: 1, kind: "signal", name: "SIGSEGV", detail: "Sinyal 11")
      assertEquals("Önceki çalıştırma çöktü: SIGSEGV (Sinyal 11)", CrashFormat.message(signal))
      let exception = CrashRecord(at: 1, kind: "exception", name: "NSRangeException", detail: "index 5")
      assertEquals("Önceki çalıştırma çöktü: NSRangeException: index 5", CrashFormat.message(exception))
      let bare = CrashRecord(at: 1, kind: "exception", name: "X", detail: "")
      assertEquals("Önceki çalıştırma çöktü: X", CrashFormat.message(bare))
    }
    TestRun.test("CrashFormatTest.jsonRoundTrip") {
      let record = CrashRecord(at: 42, kind: "exception", name: "N", detail: "d")
      assertEquals(record, CrashRecord.fromJson(record.toJson()) ?? CrashRecord(at: 0, kind: "", name: "", detail: ""))
      assertNull(CrashRecord.fromJson(["kind": "other", "name": "x"]))
      assertNull(CrashRecord.fromJson("text"))
      assertNull(CrashRecord.fromJson(nil))
    }
  }
}

enum DemoScriptTest {
  static func run() {
    TestRun.test("DemoScriptTest.linesAreUsableEnglishSubtitles") {
      assertEquals(12, DemoScript.lines.count)
      assertEquals(12, Set(DemoScript.lines).count, "satırlar farklı olmalı")
      var speakers = 0
      for line in DemoScript.lines {
        assertTrue(line.count >= 10, line)
        assertFalse(TurkishDetect.isTurkish(line), line)
        assertFalse(OcrNoise.looksGarbled(line), line)
        assertEquals(line, OcrNoise.clean(line), "OcrNoise satırı değiştirmemeli")
        if line.range(of: "^[A-Z]{2,}: ", options: .regularExpression) != nil { speakers += 1 }
      }
      assertTrue(speakers >= 3, "konuşmacı önekli satır sayısı \(speakers)")
    }
    TestRun.test("DemoScriptTest.cyclesThroughTheLines") {
      var script = DemoScript()
      var seen: [String] = []
      for _ in 0..<13 { seen.append(script.next()) }
      assertEquals(Array(DemoScript.lines), Array(seen.prefix(12)))
      assertEquals(DemoScript.lines[0], seen[12])
      assertEquals(13, script.index)
      assertEquals(3.5, DemoScript.intervalSeconds, accuracy: 0.0001)
    }
  }
}

enum ExtraRegionTest {
  static func run() {
    TestRun.test("ExtraRegionTest.parseListClampsLimitsAndNames") {
      let rows: [Any] = [
        ["top": 0.2, "bottom": 0.4, "left": 0.1, "right": 0.6, "name": "  Görev  "] as [String: Any],
        ["name": ""] as [String: Any],
        "junk",
        ["top": 5.0, "bottom": 0.0, "left": -2.0, "right": 9.0] as [String: Any],
        ["top": 0.5] as [String: Any],
      ]
      let list = ExtraRegion.parseList(rows)
      assertEquals(3, list.count)
      assertEquals("Görev", list[0].name)
      assertEquals(0.2, list[0].top, accuracy: 0.0001)
      assertEquals(0.6, list[0].right, accuracy: 0.0001)
      assertEquals("Alan 2", list[1].name)
      assertEquals(ExtraRegion().top, list[1].top, accuracy: 0.0001)
      assertEquals(0.95, list[2].top, accuracy: 0.0001)
      assertEquals(1.0, list[2].bottom, accuracy: 0.0001)
      assertEquals(0.0, list[2].left, accuracy: 0.0001)
      assertEquals(1.0, list[2].right, accuracy: 0.0001)
      assertEquals("Alan 3", list[2].name)
    }
    TestRun.test("ExtraRegionTest.bottomStaysBelowTopAndRightRightOfLeft") {
      let r = ExtraRegion.parse(["top": 0.5, "bottom": 0.1, "left": 0.7, "right": 0.2] as [String: Any], number: 1)
      assertNotNull(r)
      assertTrue((r?.bottom ?? 0) >= (r?.top ?? 1) + 0.05 - 0.0001)
      assertTrue((r?.right ?? 0) >= (r?.left ?? 1) + 0.05 - 0.0001)
    }
    TestRun.test("ExtraRegionTest.badInputGivesEmptyList") {
      assertEquals(0, ExtraRegion.parseList(nil).count)
      assertEquals(0, ExtraRegion.parseList("x").count)
      assertEquals(0, ExtraRegion.parseList([Any]()).count)
      assertEquals(0, ExtraRegion.parseList([1, 2, "z"] as [Any]).count)
    }
    TestRun.test("ExtraRegionTest.longNameIsCut") {
      let r = ExtraRegion.parse(["name": String(repeating: "n", count: 60)] as [String: Any], number: 1)
      assertEquals(ExtraRegion.maxNameLength, r?.name.count ?? 0)
    }
    TestRun.test("ExtraRegionTest.jsonRoundTrip") {
      let region = ExtraRegion(top: 0.25, bottom: 0.5, left: 0.125, right: 0.75, name: "Harita")
      assertEquals(region, ExtraRegion.parse(region.toJson(), number: 1) ?? ExtraRegion())
    }
    TestRun.test("ExtraRegionTest.joinLines") {
      assertEquals("Find the old well.", ExtraRegion.joinLines(["Find the", "  old well. ", ""]))
      assertEquals("example text", ExtraRegion.joinLines(["exam-", "ple text"]))
      assertEquals("well- Known", ExtraRegion.joinLines(["well-", "Known"]))
      assertEquals("- Hello - Hi", ExtraRegion.joinLines(["- Hello", "- Hi"]))
      assertEquals("", ExtraRegion.joinLines(["  ", ""]))
      assertEquals("", ExtraRegion.joinLines([]))
    }
  }
}

enum RateMeterTest {
  static func run() {
    TestRun.test("RateMeterTest.steadyStreamReportsItsRate") {
      var meter = RateMeter(window: 5)
      for i in 0..<50 { meter.record(at: Double(i) / 10) }
      assertEquals(10, meter.rate(at: 5.0), accuracy: 0.6)
    }
    TestRun.test("RateMeterTest.startsLowThenStopsAtZero") {
      var meter = RateMeter(window: 5)
      for i in 0..<3 { meter.record(at: Double(i) / 10) }
      assertEquals(3, meter.rate(at: 0.3), accuracy: 0.0001)
      assertEquals(0, meter.rate(at: 20), accuracy: 0.0001)
      var empty = RateMeter()
      assertEquals(0, empty.rate(at: 1), accuracy: 0.0001)
    }
    TestRun.test("RateMeterTest.resetForgetsOldEvents") {
      var meter = RateMeter(window: 5)
      meter.record(at: 1)
      meter.record(at: 1.5)
      meter.reset()
      assertEquals(0, meter.rate(at: 2), accuracy: 0.0001)
    }
  }
}

enum PipelineOriginTest {
  static func run() {
    TestRun.test("PipelineOriginTest.engineOriginMapping") {
      assertEquals("gemini", SubtitlePipeline.engineOrigin("gemini", fallbackAnswered: false))
      assertEquals("google", SubtitlePipeline.engineOrigin("gemini", fallbackAnswered: true))
      assertEquals("deepl", SubtitlePipeline.engineOrigin("deepl", fallbackAnswered: false))
      assertEquals("google", SubtitlePipeline.engineOrigin("deepl", fallbackAnswered: true))
      assertEquals("google", SubtitlePipeline.engineOrigin("google", fallbackAnswered: false))
      assertEquals("apple", SubtitlePipeline.engineOrigin("google", fallbackAnswered: true))
      assertEquals("apple", SubtitlePipeline.engineOrigin("mlkit", fallbackAnswered: false))
      assertEquals("", SubtitlePipeline.engineOrigin("", fallbackAnswered: false))
    }
    TestRun.test("PipelineOriginTest.shownReportsWhoTranslated") {
      let clock = FakeClock()
      let sink = PackPipelineTest.TextSink()
      let p = SubtitlePipeline(translator: FunctionTranslator { _ in "Arabaya bin." }, sink: sink,
                               translateExecutor: { $0() }, stabilizer: SubtitleStabilizer(clock: { clock.now }))
      var options = PipelineOptions()
      options.engineId = "gemini"
      p.options = options
      var shown: [[String]] = []
      p.onShown = { source, text, origin in shown.append([source, text, origin]) }
      p.onRead(["Get in the car."], nil)
      assertEquals([["Get in the car.", "Arabaya bin.", "gemini"]], shown)

      clock.now += 100
      p.onRead([], nil)
      clock.now += 2000
      p.onRead([], nil)
      p.packLookup = { text in PackTranslation.match(text, PackPipelineTest.lookup) }
      p.onRead(["Get down!"], nil)
      assertEquals(["Get down!", "Yere yat!", "pack"], shown.last ?? [])
    }
    TestRun.test("PipelineOriginTest.translateOnceUsesPackThenEngine") {
      let clock = FakeClock()
      let sink = PackPipelineTest.TextSink()
      let p = SubtitlePipeline(translator: FunctionTranslator { _ in "Arabaya bin." }, sink: sink,
                               translateExecutor: { $0() }, stabilizer: SubtitleStabilizer(clock: { clock.now }))
      var options = PipelineOptions()
      options.engineId = "google"
      p.options = options
      p.packLookup = { text in PackTranslation.match(text, PackPipelineTest.lookup) }
      let fromPack = p.translateOnce("Get down!")
      assertEquals("Yere yat!", fromPack.text ?? "")
      assertEquals("pack", fromPack.origin)
      let fromEngine = p.translateOnce("Open the north door\nnow.")
      assertEquals("Arabaya bin.", fromEngine.text ?? "")
      assertEquals("google", fromEngine.origin)
      assertTrue(sink.shown.isEmpty, "tek seferlik çeviri TV'ye gitmez")

      let broken = SubtitlePipeline(translator: FunctionTranslator { _ in nil }, sink: sink,
                                    translateExecutor: { $0() }, stabilizer: SubtitleStabilizer(clock: { clock.now }))
      assertNull(broken.translateOnce("Anything at all.").text)
    }
  }
}
