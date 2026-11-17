// SPDX-License-Identifier: AGPL-3.0-only
// Core/TranslationCache.swift testleri (bellek deposu + dosya gidiş-dönüşü) ve hattın kalıcı önbellek kullanımı.
import Foundation

final class MemoryCacheStorage: TranslationCacheStorage {
  var data: Data?
  var writes = 0
  var onWrite: (() -> Void)?
  func read() -> Data? { data }
  func write(_ data: Data) {
    self.data = data
    writes += 1
    let hook = onWrite
    onWrite = nil
    hook?()
  }
}

enum TranslationCacheTest {
  private static func cache(_ storage: TranslationCacheStorage, capacity: Int = 100,
                            now: @escaping () -> Double = { 1_000_000 }) -> DiskTranslationCache {
    DiskTranslationCache(storage: storage, capacity: capacity, saveDelay: 3600, now: now)
  }

  static func run() {
    TestRun.test("TranslationCacheTest.roundTripThroughStorage") {
      let storage = MemoryCacheStorage()
      let a = cache(storage)
      a.set("k1", "Merhaba")
      a.set("k2", "Elveda")
      a.flush()
      assertEquals(1, storage.writes)
      let b = cache(storage)
      assertEquals(2, b.count)
      assertEquals("Merhaba", b.get("k1") ?? "")
      assertNull(b.get("yok"))
    }
    TestRun.test("TranslationCacheTest.keyDiffersByEngineModelLanguagesRules") {
      let base = DiskTranslationCache.key(engine: "gemini", model: "m1", source: "en", target: "tr", rules: "r1", text: "Hi")
      for other in [
        DiskTranslationCache.key(engine: "google", model: "m1", source: "en", target: "tr", rules: "r1", text: "Hi"),
        DiskTranslationCache.key(engine: "gemini", model: "m2", source: "en", target: "tr", rules: "r1", text: "Hi"),
        DiskTranslationCache.key(engine: "gemini", model: "m1", source: "de", target: "tr", rules: "r1", text: "Hi"),
        DiskTranslationCache.key(engine: "gemini", model: "m1", source: "en", target: "fr", rules: "r1", text: "Hi"),
        DiskTranslationCache.key(engine: "gemini", model: "m1", source: "en", target: "tr", rules: "r2", text: "Hi"),
        DiskTranslationCache.key(engine: "gemini", model: "m1", source: "en", target: "tr", rules: "r1", text: "Hi!"),
      ] { assertNotEquals(base, other) }
      assertEquals(DiskTranslationCache.stableHash("a"), DiskTranslationCache.stableHash("a"))
      assertNotEquals(DiskTranslationCache.stableHash("a"), DiskTranslationCache.stableHash("b"))
    }
    TestRun.test("TranslationCacheTest.evictsLeastRecentlyUsed") {
      let c = cache(MemoryCacheStorage(), capacity: 10)
      for i in 0..<10 { c.set("k\(i)", "v\(i)") }
      assertEquals("v0", c.get("k0") ?? "")   // k0 yeniden kullanıldı
      c.set("k10", "v10")                      // sınır aşıldı: %90'a inilir (9 kayıt)
      assertEquals(9, c.count)
      assertEquals("v0", c.get("k0") ?? "", "kullanılan kayıt atılmamalı")
      assertNull(c.get("k1"), "en eski kullanılan atılmalı")
      assertEquals("v10", c.get("k10") ?? "")
    }
    TestRun.test("TranslationCacheTest.corruptFileStartsEmpty") {
      let storage = MemoryCacheStorage()
      storage.data = Data("{ bozuk".utf8)
      let c = cache(storage)
      assertEquals(0, c.count)
      c.set("k", "v")
      c.flush()
      assertEquals("v", cache(storage).get("k") ?? "")
      let wrongVersion = MemoryCacheStorage()
      wrongVersion.data = Data(#"{"version":99,"rows":[{"k":"a","v":"b","s":1,"t":1000000}]}"#.utf8)
      assertEquals(0, cache(wrongVersion).count)
    }
    TestRun.test("TranslationCacheTest.oldEntriesDropAtLoad") {
      let storage = MemoryCacheStorage()
      nonisolated(unsafe) var clock = 1_000_000.0
      let a = cache(storage, now: { clock })
      a.set("eski", "x")
      clock += 10 * 86400
      a.set("yeni", "y")
      a.flush()
      clock += 25 * 86400   // eski 35 gün, yeni 25 gün
      let b = cache(storage, now: { clock })
      assertNull(b.get("eski"))
      assertEquals("y", b.get("yeni") ?? "")
    }
    TestRun.test("TranslationCacheTest.emptyValuesAreNotStored") {
      let c = cache(MemoryCacheStorage())
      c.set("k", "")
      assertEquals(0, c.count)
    }
    TestRun.test("TranslationCacheTest.fileRoundTrip") {
      let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gt-cache-test-\(UUID().uuidString)", isDirectory: true)
      defer { try? FileManager.default.removeItem(at: dir) }
      let url = dir.appendingPathComponent("alt/translation-cache.json")
      let a = cache(FileCacheStorage(url: url))
      a.set("k", "Çeviri: ğüşiöç")
      a.flush()
      assertTrue(FileManager.default.fileExists(atPath: url.path))
      assertEquals("Çeviri: ğüşiöç", cache(FileCacheStorage(url: url)).get("k") ?? "")
      // Bozuk dosya: boş başlar.
      try? Data("###".utf8).write(to: url)
      assertEquals(0, cache(FileCacheStorage(url: url)).count)
    }
    TestRun.test("TranslationCacheTest.pipelineUsesDiskCache") {
      let shared = cache(MemoryCacheStorage())
      var options = PipelineOptions()
      options.cache = shared
      options.engineId = "google"
      options.sourceLanguage = "en"
      options.targetLanguage = "tr"
      options.rulesVersion = "r1"
      var first: [String] = []
      let f1 = PipelineFixture(.direct) { text in first.append(text); return "Nereye gidiyorsun?" }
      f1.p.options = options
      f1.onRead(["Where are you going?"], nil)
      assertEquals(["Where are you going?"], first)
      assertEquals(1, shared.count)
      // Yeni hat (uygulama yeniden açılmış gibi): motora gidilmez, önbellekten gösterilir.
      var second: [String] = []
      let f2 = PipelineFixture(.direct) { text in second.append(text); return "başka" }
      f2.p.options = options
      f2.onRead(["Where are you going?"], nil)
      assertEquals([], second)
      assertEquals(["Nereye gidiyorsun?|15000|false"], f2.shown)
      // Farklı model: önbellek kaçırılır.
      var third: [String] = []
      let f3 = PipelineFixture(.direct) { text in third.append(text); return "başka" }
      var other = options
      other.model = "gemini-3.6-flash"
      f3.p.options = other
      f3.onRead(["Where are you going?"], nil)
      assertEquals(["Where are you going?"], third)
    }
    TestRun.test("TranslationCacheTest.fallbackAnswerIsShownButNotCached") {
      let shared = cache(MemoryCacheStorage())
      var options = PipelineOptions()
      options.cache = shared
      options.engineId = "gemini"
      options.targetLanguage = "tr"
      let primary = FunctionTranslator { _ in nil }
      let backup = FunctionTranslator { _ in "Yedek çeviri" }
      let f = PipelineFixture(.direct) { text in FallbackTranslator(primary, backup).translate(text) }
      f.p.options = options
      f.onRead(["Where are you going?"], nil)
      assertEquals(["Yedek çeviri|15000|false"], f.shown)
      assertEquals(0, shared.count, "yedek motorun çevirisi asıl motor anahtarıyla saklanmamalı")
      // Asıl motor cevap verirse saklanır.
      let g = PipelineFixture(.direct) { text in FallbackTranslator(FunctionTranslator { _ in "Asıl çeviri" }, backup).translate(text) }
      g.p.options = options
      g.onRead(["Where are you going?"], nil)
      assertEquals(1, shared.count)
    }
    TestRun.test("TranslationCacheTest.readDuringFlushSchedulesAnotherSave") {
      let storage = MemoryCacheStorage()
      let q = DispatchQueue(label: "CoreTests.cache-save")
      let c = DiskTranslationCache(storage: storage, capacity: 10, saveDelay: 0, now: { 1_000_000 }, queue: q)
      storage.onWrite = { _ = c.get("k") }   // yazma sürerken okuma: kayıt yeniden dirty olur
      c.set("k", "v")
      // Zamanlanan kayıtlar kuyrukta zamanlayıcıyla çalışır; en çok 3 sn beklenir.
      var waited = 0
      while storage.writes < 2 && waited < 300 { usleep(10_000); waited += 1 }
      q.sync {}
      assertEquals(2, storage.writes, "yazma sırasında kirlenen kayıt yeniden zamanlanmalı")
    }
    TestRun.test("TranslationCacheTest.packTranslationsAreNotCached") {
      let shared = cache(MemoryCacheStorage())
      var options = PipelineOptions()
      options.cache = shared
      let f = PipelineFixture(.direct) { _ in "motor" }
      f.p.options = options
      f.p.packLookup = { _ in PackMatch(text: "Paket çevirisi", packId: "p") }
      f.onRead(["Where are you going?"], nil)
      assertEquals(0, shared.count)
    }
  }
}
