// SPDX-License-Identifier: AGPL-3.0-only
// Paket 4 saf parçalarının testleri: JSON sayı/mantıksal ayrımı, arayüz dili yardımcısı, geçmişte düzeltilen satırın yerine
// geçmesi ve otomatik altyazı alanı bulucusu (Kotlin karşılığı yok).
import Foundation

enum JsonNumberTest {
  private static func parse(_ json: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
  }

  static func run() {
    TestRun.test("JsonNumberTest.zeroAndOneAreNumbersNotBooleans") {
      let map = parse("{\"a\":0,\"b\":1,\"c\":0.0,\"d\":1.0,\"e\":true,\"f\":false,\"g\":0.5}")
      for key in ["a", "b", "c", "d", "g"] {
        assertFalse(JsonNumber.isBoolean(map[key]), key)
        assertNotNull(JsonNumber.number(map[key]), key)
      }
      for key in ["e", "f"] {
        assertTrue(JsonNumber.isBoolean(map[key]), key)
        assertNull(JsonNumber.number(map[key]), key)
      }
      assertEquals(0.0, JsonNumber.double(map["a"], 9), accuracy: 0.0001)
      assertEquals(1.0, JsonNumber.double(map["b"], 9), accuracy: 0.0001)
      assertEquals(0.0, JsonNumber.double(map["c"], 9), accuracy: 0.0001)
      assertEquals(1.0, JsonNumber.double(map["d"], 9), accuracy: 0.0001)
      assertEquals(0.5, JsonNumber.double(map["g"], 9), accuracy: 0.0001)
      assertEquals(9.0, JsonNumber.double(map["e"], 9), accuracy: 0.0001, "true sayı değildir")
      assertEquals(9.0, JsonNumber.double(map["f"], 9), accuracy: 0.0001, "false sayı değildir")
      assertEquals(0, JsonNumber.int(map["a"], 7))
      assertEquals(1, JsonNumber.int(map["b"], 7))
      assertEquals(0, JsonNumber.int(map["c"], 7))
      assertEquals(1, JsonNumber.int(map["d"], 7))
      assertEquals(7, JsonNumber.int(map["e"], 7))
      assertEquals(7, JsonNumber.int(map["f"], 7))
    }
    TestRun.test("JsonNumberTest.swiftValuesAndStringsAndJunk") {
      assertTrue(JsonNumber.isBoolean(true as Any))
      assertTrue(JsonNumber.isBoolean(false as Any))
      assertFalse(JsonNumber.isBoolean(0 as Any))
      assertFalse(JsonNumber.isBoolean(1 as Any))
      assertFalse(JsonNumber.isBoolean(1.0 as Any))
      assertFalse(JsonNumber.isBoolean("true" as Any))
      assertFalse(JsonNumber.isBoolean(nil))
      assertEquals(1.0, JsonNumber.double(1 as Any, 9), accuracy: 0.0001)
      assertEquals(0, JsonNumber.int(0 as Any, 7))
      assertEquals(9.0, JsonNumber.double(true as Any, 9), accuracy: 0.0001)
      assertEquals(2.5, JsonNumber.double("2.5" as Any, 9), accuracy: 0.0001)
      assertEquals(3, JsonNumber.int("3.7" as Any, 7))
      assertEquals(7, JsonNumber.int("abc" as Any, 7))
      assertEquals(7, JsonNumber.int("1e300" as Any, 7))
      assertEquals(9.0, JsonNumber.double(nil, 9), accuracy: 0.0001)
      assertEquals(9.0, JsonNumber.double("nan" as Any, 9), accuracy: 0.0001)
    }
    TestRun.test("JsonNumberTest.extraRegionKeepsZeroAndOne") {
      let map = parse("{\"top\":0,\"bottom\":1,\"left\":0,\"right\":1,\"name\":\"Tam\"}")
      let region = ExtraRegion.parse(map, number: 1)
      assertNotNull(region)
      assertEquals(0.0, region?.top ?? 9, accuracy: 0.0001, "top 0 varsayılana düşmemeli")
      assertEquals(0.0, region?.left ?? 9, accuracy: 0.0001, "left 0 varsayılana düşmemeli")
      assertEquals(1.0, region?.bottom ?? 9, accuracy: 0.0001)
      assertEquals(1.0, region?.right ?? 9, accuracy: 0.0001)
      let flags = ExtraRegion.parse(parse("{\"top\":true,\"left\":false}"), number: 1)
      assertEquals(ExtraRegion().top, flags?.top ?? 9, accuracy: 0.0001, "mantıksal değer sayı sayılmaz")
      assertEquals(ExtraRegion().left, flags?.left ?? 9, accuracy: 0.0001)
    }
  }
}

enum LangTest {
  static func run() {
    TestRun.test("LangTest.defaultIsTurkishAndProviderIsRead") {
      let saved = Lang.provider
      defer { Lang.provider = saved }
      assertEquals("merhaba", Lang.t("merhaba", "hello"))
      Lang.provider = { "en" }
      assertEquals("hello", Lang.t("merhaba", "hello"))
      Lang.provider = { "tr" }
      assertEquals("merhaba", Lang.t("merhaba", "hello"))
      // Dil çağrı anında okunur: kaynak değişince sonuç da değişir.
      var current = "tr"
      Lang.provider = { current }
      assertEquals("merhaba", Lang.t("merhaba", "hello"))
      current = "en"
      assertEquals("hello", Lang.t("merhaba", "hello"))
    }
    TestRun.test("LangTest.effectiveLanguage") {
      assertEquals("tr", Lang.effective(setting: "auto", preferred: ["tr-TR", "en-US"]))
      assertEquals("tr", Lang.effective(setting: "auto", preferred: ["tr"]))
      assertEquals("tr", Lang.effective(setting: "auto", preferred: ["tr_TR"]))
      assertEquals("en", Lang.effective(setting: "auto", preferred: ["en-US", "tr-TR"]))
      assertEquals("en", Lang.effective(setting: "auto", preferred: ["de-DE"]))
      assertEquals("en", Lang.effective(setting: "auto", preferred: ["trk-XX"]))
      assertEquals("en", Lang.effective(setting: "auto", preferred: []))
      assertEquals("tr", Lang.effective(setting: "tr", preferred: ["en-US"]))
      assertEquals("en", Lang.effective(setting: "en", preferred: ["tr-TR"]))
      assertEquals("tr", Lang.effective(setting: "bozuk", preferred: ["tr-TR"]))
      assertEquals("en", Lang.effective(setting: "", preferred: ["fr-FR"]))
    }
    TestRun.test("LangTest.normalize") {
      assertEquals("auto", Lang.normalize("auto"))
      assertEquals("tr", Lang.normalize("tr"))
      assertEquals("en", Lang.normalize(" EN "))
      assertEquals("auto", Lang.normalize("de"))
      assertEquals("auto", Lang.normalize(""))
    }
  }
}

enum HistoryReplaceTest {
  private static func entry(_ text: String, at: Int = 1, source: String = "src") -> HistoryEntry {
    HistoryEntry(at: at, source: source, text: text, engine: "google")
  }

  static func run() {
    TestRun.test("HistoryReplaceTest.ringReplacesLastWhenRevision") {
      var ring = HistoryRing(capacity: 5)
      assertTrue(ring.add(entry("a")))
      assertTrue(ring.add(entry("b ham", at: 2)))
      assertTrue(ring.add(entry("b düzeltilmiş", at: 3), replacingLast: true))
      assertEquals(2, ring.count)
      assertEquals(["b düzeltilmiş", "a"], ring.newestFirst.map { $0.text })
      assertEquals(3, ring.newestFirst.first?.at ?? 0)
      // Aynı çeviri yine değişiklik sayılmaz.
      assertFalse(ring.add(entry("b düzeltilmiş", at: 4), replacingLast: true))
      assertEquals(3, ring.newestFirst.first?.at ?? 0)
      // Düzeltme isteği olmayan yeni satır eklenir.
      assertTrue(ring.add(entry("c")))
      assertEquals(3, ring.count)
    }
    TestRun.test("HistoryReplaceTest.replaceOnEmptyRingAppends") {
      var ring = HistoryRing(capacity: 5)
      assertTrue(ring.add(entry("a"), replacingLast: true))
      assertEquals(1, ring.count)
    }
    TestRun.test("HistoryReplaceTest.logUpdatesLastEntryAndPersists") {
      let storage = MemoryCacheStorage()
      let log = SubtitleHistoryLog(storage: storage, capacity: 5, saveDelay: 3600, now: { 1000 })
      log.record(source: "Hello th", text: "Merhab", engine: "google")
      log.record(source: "Hello there", text: "Merhaba", engine: "google", replacesLast: true)
      assertEquals(1, log.count)
      log.record(source: "Next", text: "Sonraki", engine: "google")
      assertEquals(2, log.count)
      log.flush()
      let reloaded = SubtitleHistoryLog(storage: storage, capacity: 5, saveDelay: 3600)
      let texts = reloaded.list().map { $0["text"] as? String ?? "" }
      assertEquals(["Sonraki", "Merhaba"], texts)
      assertEquals("Hello there", reloaded.list()[1]["source"] as? String ?? "")
    }
    TestRun.test("HistoryReplaceTest.pipelineReportsRevisionFlag") {
      let clock = FakeClock()
      let sink = PackPipelineTest.TextSink()
      let p = SubtitlePipeline(translator: FunctionTranslator { _ in "Çeviri" }, sink: sink,
                               translateExecutor: { $0() }, stabilizer: SubtitleStabilizer(clock: { clock.now }))
      var flags: [Bool] = []
      p.onShown = { _, _, _, replaces in flags.append(replaces) }
      p.onRead(["Get in the car."], nil)
      assertEquals([false], flags, "ilk satır düzeltme değildir")
    }
  }
}

enum AutoRegionTest {
  private static let subs = [
    "The bridge is out. We have to find another way across.",
    "Check the lantern. We are running out of oil.",
    "Nobody has come through here in years.",
    "Take this key and open the gate on the left.",
    "We should rest before the storm reaches the valley.",
  ]

  private static func line(_ text: String, y: Double, h: Double = 0.04, left: Double = 0.3, right: Double = 0.7,
                           confidence: Double = 0.9) -> AutoRegionLine {
    AutoRegionLine(text: text, left: left, top: y, right: right, bottom: y + h, confidence: confidence)
  }

  /// Her altyazıyı iki taramada (2 sn aralıkla) gösterir; olayları (an, olay) olarak toplar.
  private static func play(_ finder: inout AutoRegionFinder, _ texts: [String], y: Double, from start: Int64,
                           extra: [AutoRegionLine] = []) -> [(Int64, AutoRegionEvent)] {
    var events: [(Int64, AutoRegionEvent)] = []
    var t = start
    for text in texts {
      for _ in 0..<2 {
        let event = finder.ingest([line(text, y: y)] + extra, at: t)
        if event != AutoRegionEvent.none { events.append((t, event)) }
        t += 2000
      }
    }
    return events
  }

  static func run() {
    TestRun.test("AutoRegionTest.screenLineVerdicts") {
      let ok = AutoRegionFinder.screenLine(line("Wait here. I will be back before sunrise.", y: 0.8))
      assertTrue(ok.verdict == .accepted)
      assertEquals("Wait here. I will be back before sunrise.", ok.text)
      assertTrue(AutoRegionFinder.screenLine(line("Wait here. I will be back.", y: 0.8, confidence: 0.1)).verdict == .lowConfidence)
      assertTrue(AutoRegionFinder.screenLine(line("Wait here. I will be back.", y: 0.8, h: 0.008)).verdict == .tooSmall)
      assertTrue(AutoRegionFinder.screenLine(line("Wait here. I will be back.", y: 0.4, h: 0.12)).verdict == .tooLarge)
      assertTrue(AutoRegionFinder.screenLine(line("Wait here. I will be back.", y: 0.8, left: 0.0, right: 0.15)).verdict == .corner)
      assertTrue(AutoRegionFinder.screenLine(line("Wait here. I will be back.", y: 0.8, left: 0.85, right: 1.0)).verdict == .corner)
      // Köşe göstergesi: yatayda kenara yakın, dikeyde en altta.
      assertTrue(AutoRegionFinder.screenLine(line("Wait here. I will be back.", y: 0.93, left: 0.05, right: 0.4)).verdict == .corner)
      // Düğme ipucu altyazı adayı olamaz.
      let hint = AutoRegionFinder.screenLine(line("RESUME BA", y: 0.8))
      assertTrue(hint.verdict == .prompt || hint.verdict == .empty, "düğme ipucu kabul edilmemeli")
    }
    TestRun.test("AutoRegionTest.sentenceLikeRules") {
      assertTrue(AutoRegionFinder.isSentenceLike("Take this key and open the gate on the left."))
      assertTrue(AutoRegionFinder.isSentenceLike("We should rest before the storm.\nThe valley is close."))
      assertFalse(AutoRegionFinder.isSentenceLike("SCORE 12000"))
      assertFalse(AutoRegionFinder.isSentenceLike("Press START"))
      assertFalse(AutoRegionFinder.isSentenceLike("HEALTH"))
      assertFalse(AutoRegionFinder.isSentenceLike("OBJECTIVE FIND THE KEY AND OPEN THE DOOR"))
      assertFalse(AutoRegionFinder.isSentenceLike("00:12:45  1200  3400  9999"))
      assertFalse(AutoRegionFinder.isSentenceLike(""))
      // Büyük harfli ama cümle işaretli altyazı kabul edilir.
      assertTrue(AutoRegionFinder.isSentenceLike("WE HAVE TO LEAVE NOW!"))
    }
    TestRun.test("AutoRegionTest.sameTextToleratesOcrNoiseAndGrowingText") {
      assertTrue(AutoRegionFinder.isSameText("We should rest before the storm", "we should rest before the storm."))
      assertTrue(AutoRegionFinder.isSameText("Take this key and open the gate on the left.", "Take this key and open the gate on the lett."))
      assertTrue(AutoRegionFinder.isSameText("We should rest", "We should rest before the storm reaches the valley."))
      assertFalse(AutoRegionFinder.isSameText("Take this key and open the gate", "Nobody has come through here in years"))
      assertFalse(AutoRegionFinder.isSameText("", "We should rest"))
    }
    TestRun.test("AutoRegionTest.twoLineSubtitleBecomesOneBlock") {
      let lines = [
        line("Take this key and open", y: 0.84),
        line("the gate on the left.", y: 0.885, left: 0.35, right: 0.65),
        // Köşedeki gösterge ve ekranın ortasındaki yazı blok olmaz.
        line("Wait here. I will be back before sunrise.", y: 0.02, left: 0.0, right: 0.12),
        line("Nobody has come through here in years.", y: 0.40),
      ]
      let blocks = AutoRegionFinder.blocks(from: lines)
      assertEquals(1, blocks.count)
      assertTrue(blocks[0].text.contains("Take this key"))
      assertTrue(blocks[0].text.contains("gate on the left"))
      assertTrue(blocks[0].text.contains("\n"))
      assertEquals(0.84, blocks[0].top, accuracy: 0.0001)
      assertEquals(0.925, blocks[0].bottom, accuracy: 0.0001)
    }
    TestRun.test("AutoRegionTest.bandPaddingAndClamping") {
      let normal = AutoRegionFinder.makeBand(top: 0.80, bottom: 0.86, left: 0.30, right: 0.70, lineHeight: 0.04)
      assertEquals(0.76, normal.top, accuracy: 0.0001)
      assertEquals(0.90, normal.bottom, accuracy: 0.0001)
      assertEquals(0.20, normal.left, accuracy: 0.0001)
      assertEquals(0.80, normal.right, accuracy: 0.0001)
      // Ekranın en altı ve tüm genişlik: 0–1 içinde kalır.
      let edge = AutoRegionFinder.makeBand(top: 0.93, bottom: 0.99, left: 0.02, right: 0.98, lineHeight: 0.05)
      assertEquals(0.84, edge.top, accuracy: 0.0001)
      assertEquals(1.0, edge.bottom, accuracy: 0.0001)
      assertEquals(0.0, edge.left, accuracy: 0.0001)
      assertEquals(1.0, edge.right, accuracy: 0.0001)
      // Dar ve alçak iz: en az genişlik ve yükseklik, ortası korunur.
      let tiny = AutoRegionFinder.makeBand(top: 0.50, bottom: 0.52, left: 0.45, right: 0.55, lineHeight: 0)
      assertEquals(0.45, tiny.top, accuracy: 0.0001)
      assertEquals(0.57, tiny.bottom, accuracy: 0.0001)
      assertEquals(0.20, tiny.left, accuracy: 0.0001)
      assertEquals(0.80, tiny.right, accuracy: 0.0001)
      // Üstte altyazı: üst kenar 0'ın altına inmez.
      let top = AutoRegionFinder.makeBand(top: 0.02, bottom: 0.06, left: 0.3, right: 0.7, lineHeight: 0.04)
      assertTrue(top.top >= 0 && top.bottom - top.top >= AutoRegionFinder.MIN_HEIGHT - 0.0001)
    }
    TestRun.test("AutoRegionTest.blendWidensAtOnceAndShrinksSlowly") {
      let current = AutoRegionBand(top: 0.70, bottom: 0.95, left: 0.20, right: 0.80)
      let target = AutoRegionBand(top: 0.65, bottom: 0.90, left: 0.21, right: 0.80)
      let next = AutoRegionFinder.blend(current, toward: target)
      assertNotNull(next)
      assertEquals(0.65, next?.top ?? 0, accuracy: 0.0001, "dışa doğru hemen")
      assertEquals(0.9375, next?.bottom ?? 0, accuracy: 0.0001, "içe doğru adım adım")
      assertEquals(0.20, next?.left ?? 0, accuracy: 0.0001, "küçük oynama yok sayılır")
      assertEquals(0.80, next?.right ?? 0, accuracy: 0.0001)
      assertNull(AutoRegionFinder.blend(current, toward: current))
      assertNull(AutoRegionFinder.blend(current, toward: AutoRegionBand(top: 0.705, bottom: 0.945, left: 0.205, right: 0.795)))
    }
    TestRun.test("AutoRegionTest.scanSizeKeepsLongSideWithinLimit") {
      let a = AutoRegionFinder.scanSize(width: 1920, height: 1080)
      assertEquals(960, a.width)
      assertEquals(540, a.height)
      let b = AutoRegionFinder.scanSize(width: 1080, height: 1920)
      assertEquals(540, b.width)
      assertEquals(960, b.height)
      let c = AutoRegionFinder.scanSize(width: 3840, height: 2160)
      assertEquals(960, c.width)
      assertEquals(540, c.height)
      let d = AutoRegionFinder.scanSize(width: 640, height: 360)
      assertEquals(640, d.width)
      assertEquals(360, d.height)
    }
    TestRun.test("AutoRegionTest.locksAfterThreeDistinctSubtitlesInOneBand") {
      var finder = AutoRegionFinder()
      assertTrue(finder.scanDue(at: 0))
      let two = play(&finder, Array(subs.prefix(2)), y: 0.84, from: 0)
      assertTrue(two.isEmpty, "iki altyazı yetmez")
      assertFalse(finder.isLocked)
      let third = play(&finder, [subs[2]], y: 0.84, from: 8000)
      assertEquals(1, third.count)
      assertEquals(8000, third[0].0, "üçüncü farklı altyazıyla kilitlenir")
      guard case .locked(let band) = third[0].1 else { TestRun.fail("kilit olayı bekleniyordu", #fileID, #line); return }
      assertEquals(0.80, band.top, accuracy: 0.0001)
      assertEquals(0.92, band.bottom, accuracy: 0.0001)
      assertEquals(0.20, band.left, accuracy: 0.0001)
      assertEquals(0.80, band.right, accuracy: 0.0001)
      assertTrue(finder.band == band)
      // Aynı karelerin tekrarı yeni olay üretmez.
      let again = play(&finder, [subs[2]], y: 0.84, from: 12000)
      assertTrue(again.isEmpty)
    }
    TestRun.test("AutoRegionTest.topSubtitlesCanLockToo") {
      var finder = AutoRegionFinder()
      let events = play(&finder, Array(subs.prefix(3)), y: 0.06, from: 0)
      assertEquals(1, events.count)
      guard case .locked(let band) = events[0].1 else { TestRun.fail("kilit olayı bekleniyordu", #fileID, #line); return }
      assertTrue(band.top < 0.1 && band.bottom < 0.25, "üst altyazı bandı üstte")
    }
    TestRun.test("AutoRegionTest.staticHudNeverLocksAndSubtitlesWin") {
      var finder = AutoRegionFinder()
      let hud = line("Objective: reach the lighthouse before dark.", y: 0.06)
      var t: Int64 = 0
      while t <= 40_000 {
        assertTrue(finder.ingest([hud], at: t) == AutoRegionEvent.none, "sabit yazı kilit üretmemeli")
        t += 2000
      }
      assertFalse(finder.isLocked)
      // Sabit yazı varken altyazılar altta kilitlenir; kilit sabit yazıya değil altyazıya olur.
      let events = play(&finder, Array(subs.prefix(3)), y: 0.84, from: 42_000, extra: [hud])
      assertEquals(1, events.count)
      guard case .locked(let band) = events[0].1 else { TestRun.fail("kilit olayı bekleniyordu", #fileID, #line); return }
      assertTrue(band.top > 0.5, "alt bant seçilmeli")
    }
    TestRun.test("AutoRegionTest.staticTextInSameBandDoesNotBlockLaterSubtitles") {
      var finder = AutoRegionFinder()
      let bar = line("Objective: reach the lighthouse before dark.", y: 0.84)
      var t: Int64 = 0
      while t <= 40_000 {
        _ = finder.ingest([bar], at: t)
        t += 2000
      }
      assertFalse(finder.isLocked)
      let events = play(&finder, Array(subs.prefix(3)), y: 0.84, from: 42_000)
      assertEquals(1, events.count, "sabit yazı gidince aynı yerdeki altyazı kilitlenir")
      assertEquals(50_000, events[0].0)
    }
    TestRun.test("AutoRegionTest.alternatingOrFlickeringTextDoesNotLock") {
      var finder = AutoRegionFinder()
      let a = "Take this key and open the gate on the left."
      let b = "Nobody has come through here in years."
      var t: Int64 = 0
      for i in 0..<40 {
        let event = finder.ingest([line(i % 2 == 0 ? a : b, y: 0.84)], at: t)
        assertTrue(event == AutoRegionEvent.none, "iki metnin gidip gelmesi kilit üretmemeli")
        t += 2000
      }
      // Okuma gürültüsü: aynı satırın küçük farklı okumaları tek altyazıdır.
      var noisy = AutoRegionFinder()
      let variants = [a, "Take this key and open the gate on the lett.", "Take this key and open the gate on the left,"]
      for i in 0..<30 {
        assertTrue(noisy.ingest([line(variants[i % 3], y: 0.84)], at: Int64(i) * 2000) == AutoRegionEvent.none)
      }
      assertFalse(noisy.isLocked)
    }
    TestRun.test("AutoRegionTest.middleOfScreenAndCornersDoNotLock") {
      var finder = AutoRegionFinder()
      assertTrue(play(&finder, Array(subs.prefix(4)), y: 0.40, from: 0).isEmpty, "ekranın ortası altyazı değildir")
      var corner = AutoRegionFinder()
      var t: Int64 = 0
      for text in subs.prefix(4) {
        let e = corner.ingest([line(text, y: 0.9, left: 0.02, right: 0.25)], at: t)
        assertTrue(e == AutoRegionEvent.none)
        t += 4000
      }
    }
    TestRun.test("AutoRegionTest.widensWhenSubtitleGrowsTaller") {
      var finder = AutoRegionFinder()
      _ = play(&finder, Array(subs.prefix(3)), y: 0.84, from: 0)
      assertTrue(finder.isLocked)
      let tall = [line("Take this key and open", y: 0.84), line("the gate on the left.", y: 0.885, left: 0.35, right: 0.65)]
      let event = finder.ingest(tall, at: 14_000)
      guard case .adjusted(let band) = event else { TestRun.fail("genişleme bekleniyordu: \(event)", #fileID, #line); return }
      assertEquals(0.965, band.bottom, accuracy: 0.0001)
      assertEquals(0.80, band.top, accuracy: 0.0001)
    }
    TestRun.test("AutoRegionTest.unlocksAfterQuietAndNeedsFreshEvidence") {
      var finder = AutoRegionFinder()
      _ = play(&finder, Array(subs.prefix(3)), y: 0.84, from: 0)
      assertTrue(finder.isLocked)
      assertTrue(finder.checkIdle(at: 10_000 + 19_999) == AutoRegionEvent.none)
      assertTrue(finder.isLocked)
      assertTrue(finder.checkIdle(at: 10_000 + 20_000) == AutoRegionEvent.unlocked)
      assertFalse(finder.isLocked)
      assertNull(finder.band)
      // Eski kanıtla hemen yeniden kilitlenmez.
      let one = play(&finder, [subs[3]], y: 0.84, from: 40_000)
      assertTrue(one.isEmpty)
      assertFalse(finder.isLocked)
    }
    TestRun.test("AutoRegionTest.readingInBandKeepsTheLock") {
      var finder = AutoRegionFinder()
      _ = play(&finder, Array(subs.prefix(3)), y: 0.84, from: 0)
      finder.noteReading(at: 20_000)
      assertTrue(finder.checkIdle(at: 39_999) == AutoRegionEvent.none)
      assertTrue(finder.checkIdle(at: 40_000) == AutoRegionEvent.unlocked)
      // Kilitli değilken okuma bir şey değiştirmez.
      finder.noteReading(at: 50_000)
      assertFalse(finder.isLocked)
    }
    TestRun.test("AutoRegionTest.subtitleOnScreenInBandKeepsTheLock") {
      var finder = AutoRegionFinder()
      _ = play(&finder, Array(subs.prefix(3)), y: 0.84, from: 0)
      // 15 sn aralıkla taramalar: her seferinde band içinde altyazı var.
      var t: Int64 = 23_000
      for text in subs.suffix(2) {
        _ = finder.ingest([line(text, y: 0.84)], at: t)
        t += 15_000
      }
      assertTrue(finder.isLocked)
      assertTrue(finder.checkIdle(at: t - 15_000 + 19_999) == AutoRegionEvent.none)
    }
    TestRun.test("AutoRegionTest.scanCadence") {
      var finder = AutoRegionFinder()
      assertTrue(finder.scanDue(at: 5))
      finder.markScan(at: 0)
      assertFalse(finder.scanDue(at: AutoRegionFinder.SCAN_SEARCH_MS - 1))
      assertTrue(finder.scanDue(at: AutoRegionFinder.SCAN_SEARCH_MS))
      _ = play(&finder, Array(subs.prefix(3)), y: 0.84, from: 0)
      assertTrue(finder.isLocked)
      finder.markScan(at: 10_000)
      assertFalse(finder.scanDue(at: 10_000 + AutoRegionFinder.SCAN_LOCKED_MS - 1))
      assertTrue(finder.scanDue(at: 10_000 + AutoRegionFinder.SCAN_LOCKED_MS))
      finder.reset()
      assertFalse(finder.isLocked)
      assertTrue(finder.scanDue(at: 1))
    }
    TestRun.test("AutoRegionTest.constantsAreSane") {
      assertEquals(2000, AutoRegionFinder.SCAN_SEARCH_MS)
      assertEquals(15_000, AutoRegionFinder.SCAN_LOCKED_MS)
      assertEquals(960, AutoRegionFinder.SCAN_MAX_SIDE)
      assertEquals(20_000, AutoRegionFinder.UNLOCK_QUIET_MS)
      assertTrue(AutoRegionFinder.LOCK_HITS >= 2)
    }
  }
}
