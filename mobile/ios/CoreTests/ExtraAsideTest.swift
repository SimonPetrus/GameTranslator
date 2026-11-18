// SPDX-License-Identifier: AGPL-3.0-only
// Ek okuma alanı gösterimi: bitince hattın ekrandaki satırı geri gelir; geçmişte ek alan kaydı ezilmez (Kotlin karşılığı yok).
import Foundation

enum ExtraAsideTest {
  private static func translate(_ text: String) -> String? {
    text.hasPrefix("Where") ? "Nereye gidiyorsun?" : "Arabaya bin."
  }

  /// Hat saniye saatini sahte saatten okur (kalan süre hesabı).
  private static func fixture() -> PipelineFixture {
    let f = PipelineFixture(.direct, translate)
    let clock = f.clock
    f.p.contextClock = { Double(clock.now) / 1000 }
    return f
  }

  /// Çeviriyi hemen yapmayan yürütücü: işler sırayla elle çalıştırılır.
  private final class Pending {
    var jobs: [() -> Void] = []
    func runAll() {
      let current = jobs
      jobs.removeAll()
      for job in current { job() }
    }
  }

  static func run() {
    let box = TextBox(left: 0.2, top: 0.8, right: 0.8, bottom: 0.9)
    TestRun.test("ExtraAsideTest.currentLineComesBackWithRemainingTime") {
      let f = fixture()
      f.onRead(["Where are you going?"], box)
      assertEquals(["Nereye gidiyorsun?|15000|false"], f.shown)
      f.clock.now = 5000
      let mark = f.p.showAside("Görev: anahtarı bul.", durationMs: 8000, unlessResetSince: f.p.resetCount)
      assertNotNull(mark)
      assertEquals("Görev: anahtarı bul.|8000|false", f.shown.last ?? "")
      // Oyundaki satır ekranda kalır: hat yeni bir şey göndermez.
      f.clock.now = 9000
      f.onRead(["Where are you going?"], box)
      assertEquals(2, f.shown.count)
      // Ek gösterim bitti (13 sn): satırın 15 sn'sinden kalan 2 sn ile geri gelir.
      f.clock.now = 13000
      assertTrue(f.p.resumeAfterAside(mark ?? -1))
      assertEquals("Nereye gidiyorsun?|2000|false", f.shown.last ?? "")
      // Aynı işaret ikinci kez bir şey göndermez.
      assertFalse(f.p.resumeAfterAside(mark ?? -1))
      assertEquals(3, f.shown.count)
    }
    TestRun.test("ExtraAsideTest.newLineMeanwhileIsNotOverwritten") {
      let f = fixture()
      f.onRead(["Where are you going?"], box)
      f.clock.now = 1000
      let mark = f.p.showAside("Görev notu.", durationMs: 8000, unlessResetSince: f.p.resetCount)
      f.clock.now = 2000
      f.onRead(["Get in the car."], box)
      assertEquals("Arabaya bin.|15000|false", f.shown.last ?? "")
      f.clock.now = 9000
      assertFalse(f.p.resumeAfterAside(mark ?? -1), "hattın yeni satırı ezilmez")
      assertEquals(3, f.shown.count)
    }
    TestRun.test("ExtraAsideTest.lineGoneMeanwhileIsNotBroughtBack") {
      let f = fixture()
      f.onRead(["Where are you going?"], box)
      f.clock.now = 1000
      let mark = f.p.showAside("Görev notu.", durationMs: 8000, unlessResetSince: f.p.resetCount)
      // Bölge boşaldı: 1 sn sonra hat temizler.
      f.clock.now = 1100
      f.onRead([], nil)
      f.clock.now = 2100
      f.onRead([], nil)
      assertEquals(1, f.clears)
      f.clock.now = 9000
      assertFalse(f.p.resumeAfterAside(mark ?? -1))
      // Satır zaten kalkmışken başlayan ek gösterimden sonra da geri gelmez.
      let later = f.p.showAside("Başka not.", durationMs: 8000, unlessResetSince: f.p.resetCount)
      f.clock.now = 10000
      assertFalse(f.p.resumeAfterAside(later ?? -1))
      assertEquals(3, f.shown.count)
    }
    TestRun.test("ExtraAsideTest.resetCancelsAsideAndResume") {
      let f = fixture()
      f.onRead(["Where are you going?"], box)
      let before = f.p.resetCount
      f.p.reset()
      assertEquals(1, f.clears)
      assertNull(f.p.showAside("Görev notu.", durationMs: 8000, unlessResetSince: before), "durdurmadan sonra gösterilmez")
      assertEquals(1, f.shown.count)
      let g = fixture()
      g.onRead(["Where are you going?"], box)
      g.clock.now = 1000
      let mark = g.p.showAside("Görev notu.", durationMs: 8000, unlessResetSince: g.p.resetCount)
      g.p.reset()
      g.clock.now = 9000
      assertFalse(g.p.resumeAfterAside(mark ?? -1), "durdurmadan sonra satır geri gelmez")
      assertEquals(2, g.shown.count)
    }
    TestRun.test("ExtraAsideTest.expiredLineIsNotResent") {
      let f = fixture()
      f.onRead(["Where are you going?"], box)
      f.clock.now = 7000
      let mark = f.p.showAside("Görev notu.", durationMs: 8000, unlessResetSince: f.p.resetCount)
      // 14,5 sn: 15 sn'den kalan 500 ms, en kısa süreden (1 sn) az.
      f.clock.now = 14500
      assertFalse(f.p.resumeAfterAside(mark ?? -1))
      assertEquals(2, f.shown.count)
    }
    TestRun.test("ExtraAsideTest.lateTranslationOfLeftLineIsNotResent") {
      let clock = FakeClock()
      let sink = RecordingSink()
      let pending = Pending()
      let p = SubtitlePipeline(translator: FunctionTranslator(translate), sink: sink,
                               translateExecutor: { job in pending.jobs.append(job) },
                               stabilizer: SubtitleStabilizer(clock: { clock.now }))
      p.contextClock = { Double(clock.now) / 1000 }
      p.onRead(["Where are you going?"], box)
      clock.now = 100
      p.onRead([], nil)
      clock.now = 1100
      p.onRead([], nil)
      assertEquals(1, sink.clears)
      // Çeviri satır kalktıktan sonra geldi: okuma süresiyle gösterilir (1200 + 60 × 18 = 2280 ms).
      pending.runAll()
      assertEquals(["Nereye gidiyorsun?|2280|false"], sink.shown)
      let mark = p.showAside("Görev notu.", durationMs: 8000, unlessResetSince: p.resetCount)
      clock.now = 1500
      assertFalse(p.resumeAfterAside(mark ?? -1), "oyunda kalkmış satır geri getirilmez")
      assertEquals(2, sink.shown.count)
    }
  }
}

enum HistoryAsideTest {
  private static func entry(_ text: String) -> HistoryEntry {
    HistoryEntry(at: 1, source: "src", text: text, engine: "google")
  }

  static func run() {
    TestRun.test("HistoryAsideTest.revisionAfterAsideEntryAppends") {
      var ring = HistoryRing(capacity: 5)
      assertTrue(ring.add(entry("a")))
      assertTrue(ring.add(entry("x"), aside: true))
      assertTrue(ring.add(entry("a düzeltilmiş"), replacingLast: true))
      assertEquals(["a düzeltilmiş", "x", "a"], ring.newestFirst.map { $0.text })
      // Son kayıt yine hattın satırı: sonraki düzeltme onun yerine geçer.
      assertTrue(ring.add(entry("a son"), replacingLast: true))
      assertEquals(["a son", "x", "a"], ring.newestFirst.map { $0.text })
    }
    TestRun.test("HistoryAsideTest.skippedAsideKeepsLastReplaceable") {
      var ring = HistoryRing(capacity: 5)
      assertTrue(ring.add(entry("a")))
      // Son satırla aynı çeviri eklenmez; son kayıt hattın satırı kalır.
      assertFalse(ring.add(entry("a"), aside: true))
      assertTrue(ring.add(entry("a2"), replacingLast: true))
      assertEquals(["a2"], ring.newestFirst.map { $0.text })
      ring.clear()
      assertTrue(ring.add(entry("x"), aside: true))
      ring.clear()
      assertTrue(ring.add(entry("b")))
      assertTrue(ring.add(entry("b2"), replacingLast: true))
      assertEquals(["b2"], ring.newestFirst.map { $0.text }, "temizlik ek alan işaretini de siler")
    }
    TestRun.test("HistoryAsideTest.logKeepsAsideEntry") {
      let log = SubtitleHistoryLog(storage: MemoryCacheStorage(), capacity: 5, saveDelay: 3600, now: { 1000 })
      log.record(source: "Hello th", text: "Merhab", engine: "google")
      log.record(source: "Quest", text: "Görev", engine: "google", aside: true)
      log.record(source: "Hello there", text: "Merhaba", engine: "google", replacesLast: true)
      assertEquals(["Merhaba", "Görev", "Merhab"], log.list().map { $0["text"] as? String ?? "" })
    }
  }
}
