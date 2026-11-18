// SPDX-License-Identifier: AGPL-3.0-only
// Kota dolunca motor değiştirme: sıra, bekleme süreleri, bekleme tablosu, atlama, geri dönüş ve cevap veren motor kimliği.
import Foundation

private final class Clock {
  var now = Date(timeIntervalSince1970: 1_000_000)
  func advance(_ seconds: Double) { now = now.addingTimeInterval(seconds) }
}

private final class ScriptedMember: ChainMember {
  let id: String
  var outcome: ChainOutcome
  private(set) var calls = 0

  init(_ id: String, _ outcome: ChainOutcome) {
    self.id = id
    self.outcome = outcome
  }

  func attempt(_ text: String) -> ChainOutcome {
    calls += 1
    return outcome
  }
}

enum FailoverChainTest {
  private static func quota(_ seconds: Double = 1800) -> ChainOutcome { .pause(EnginePause(seconds: seconds, reason: .quota)) }

  private static func order(_ engine: String, deepL: Bool = true, gemini: Bool = true, tr: Bool = true, on: Bool = true) -> [String] {
    FailoverOrder.keyed(engine: engine, deepLKey: deepL, geminiKey: gemini, targetIsTurkish: tr, failover: on)
  }

  static func run() {
    TestRun.test("FailoverChainTest.orderDeepLSelected") {
      assertEquals(["deepl", "gemini"], order("deepl"))
      assertEquals(["deepl"], order("deepl", gemini: false))
      assertEquals(["deepl"], order("deepl", tr: false), "Gemini yalnız Türkçe hedefte")
    }
    TestRun.test("FailoverChainTest.orderGeminiSelected") {
      assertEquals(["gemini", "deepl"], order("gemini"))
      assertEquals(["gemini"], order("gemini", deepL: false))
      assertEquals([], order("gemini", tr: false), "hedef Türkçe değilse Gemini fiilen Google; zincir yok")
    }
    TestRun.test("FailoverChainTest.orderEmptyWhenSwitchOffOrSelectedKeyMissingOrOtherEngine") {
      assertEquals([], order("deepl", on: false))
      assertEquals([], order("gemini", on: false))
      assertEquals([], order("deepl", deepL: false), "seçili motorun anahtarı boşsa zincir yok (önbellek kimliği Google)")
      assertEquals([], order("google"))
      assertEquals([], order("mlkit"))
    }
    TestRun.test("FailoverChainTest.pauseRulesFromStatus") {
      assertEquals(EnginePause(seconds: 1800, reason: .quota), EnginePauseRule.deepL(status: 456) ?? EnginePause(seconds: 0, reason: .busy))
      assertEquals(EnginePause(seconds: 1800, reason: .key), EnginePauseRule.deepL(status: 403) ?? EnginePause(seconds: 0, reason: .busy))
      assertEquals(EnginePause(seconds: 60, reason: .busy), EnginePauseRule.deepL(status: 429) ?? EnginePause(seconds: 0, reason: .quota))
      for status in [200, 500, 503, 0, 400] { assertNull(EnginePauseRule.deepL(status: status), "durum \(status)") }
    }
    TestRun.test("FailoverChainTest.geminiPauseFollowsRateLimitDecision") {
      let minute = GeminiRateLimit.Decision(seconds: 37, daily: false, retryDelay: 35)
      assertEquals(EnginePause(seconds: 37, reason: .busy), EnginePauseRule.gemini(minute))
      let daily = GeminiRateLimit.Decision(seconds: 3600, daily: true, retryDelay: nil)
      assertEquals(EnginePause(seconds: 1800, reason: .quota), EnginePauseRule.gemini(daily))
    }
    TestRun.test("FailoverChainTest.firstMemberAnswersWithoutMark") {
      let clock = Clock()
      let a = ScriptedMember("deepl", .translated("bir"))
      let b = ScriptedMember("gemini", .translated("iki"))
      let chain = FailoverTranslator(members: [a, b], cooldowns: EngineCooldowns(), clock: { clock.now })
      FallbackSignal.reset()
      assertEquals("bir", chain.translate("x") ?? "")
      assertEquals("deepl", FallbackSignal.answeredBy ?? "")
      assertFalse(FallbackSignal.marked, "asıl motor cevapladı: önbelleğe yazılabilir")
      assertEquals(0, b.calls)
    }
    TestRun.test("FailoverChainTest.quotaMovesToNextAndSkipsPausedWithoutRequest") {
      let clock = Clock()
      let cooldowns = EngineCooldowns()
      cooldowns.configure(order: ["deepl", "gemini"])
      let deepL = ScriptedMember("deepl", quota())
      let gemini = ScriptedMember("gemini", .translated("Gemini çevirisi"))
      let google = ScriptedMember("google", .translated("Google çevirisi"))
      let chain = FailoverTranslator(members: [deepL, gemini, google], cooldowns: cooldowns, clock: { clock.now })
      FallbackSignal.reset()
      assertEquals("Gemini çevirisi", chain.translate("a") ?? "")
      assertEquals("gemini", FallbackSignal.answeredBy ?? "")
      assertTrue(FallbackSignal.marked, "ikinci motor cevabı seçili motorun önbellek anahtarıyla saklanmaz")
      assertEquals(1, deepL.calls)
      for _ in 0..<5 { _ = chain.translate("b") }
      assertEquals(1, deepL.calls, "beklemedeki motora istek atılmaz")
      assertEquals(6, gemini.calls)
      assertEquals(0, google.calls)
    }
    TestRun.test("FailoverChainTest.emptyReplyDoesNotPauseEngine") {
      let clock = Clock()
      let cooldowns = EngineCooldowns()
      cooldowns.configure(order: ["deepl"])
      let deepL = ScriptedMember("deepl", .failed)
      let google = ScriptedMember("google", .translated("G"))
      let chain = FailoverTranslator(members: [deepL, google], cooldowns: cooldowns, clock: { clock.now })
      FallbackSignal.reset()
      assertEquals("G", chain.translate("a") ?? "")
      assertEquals("google", FallbackSignal.answeredBy ?? "")
      assertFalse(cooldowns.isPaused("deepl", now: clock.now))
      deepL.outcome = .translated("D")
      FallbackSignal.reset()
      assertEquals("D", chain.translate("b") ?? "", "bir sonraki satırda yine asıl motor denenir")
      assertEquals(2, deepL.calls)
      assertFalse(FallbackSignal.marked)
    }
    TestRun.test("FailoverChainTest.returnsToPrimaryWhenCooldownExpires") {
      let clock = Clock()
      let cooldowns = EngineCooldowns()
      cooldowns.configure(order: ["deepl", "gemini"])
      let deepL = ScriptedMember("deepl", quota(1800))
      let gemini = ScriptedMember("gemini", .translated("G"))
      let chain = FailoverTranslator(members: [deepL, gemini], cooldowns: cooldowns, clock: { clock.now })
      _ = chain.translate("a")
      assertTrue(cooldowns.isPaused("deepl", now: clock.now))
      clock.advance(1799)
      assertTrue(cooldowns.isPaused("deepl", now: clock.now))
      clock.advance(2)
      assertFalse(cooldowns.isPaused("deepl", now: clock.now))
      deepL.outcome = .translated("D")
      FallbackSignal.reset()
      assertEquals("D", chain.translate("b") ?? "")
      assertEquals(2, deepL.calls, "süre dolunca gerçek istekle yeniden denenir")
      assertEquals("deepl", FallbackSignal.answeredBy ?? "")
      assertFalse(FallbackSignal.marked)
    }
    TestRun.test("FailoverChainTest.allPausedOrFailedReturnsNil") {
      let clock = Clock()
      let cooldowns = EngineCooldowns()
      let a = ScriptedMember("deepl", quota())
      let b = ScriptedMember("gemini", .pause(EnginePause(seconds: 60, reason: .busy)))
      let c = ScriptedMember("google", .failed)
      let chain = FailoverTranslator(members: [a, b, c], cooldowns: cooldowns, clock: { clock.now })
      assertNull(chain.translate("a"))
      assertNull(chain.translate("b"))
      assertEquals(1, a.calls)
      assertEquals(1, b.calls)
      assertEquals(2, c.calls, "Google beklemeye alınmaz")
    }
    TestRun.test("FailoverChainTest.longerPauseIsNotShortened") {
      let cooldowns = EngineCooldowns()
      let now = Date(timeIntervalSince1970: 5000)
      cooldowns.pause("gemini", EnginePause(seconds: 1800, reason: .quota), now: now)
      cooldowns.pause("gemini", EnginePause(seconds: 30, reason: .busy), now: now)
      assertTrue(cooldowns.isPaused("gemini", now: now.addingTimeInterval(1000)))
      cooldowns.configure(order: ["gemini"])
      assertFalse(cooldowns.isPaused("gemini", now: now), "yeni zincir kurulunca bekleme sıfırlanır")
    }
    TestRun.test("FailoverChainTest.snapshotShowsPausedAndCurrent") {
      let cooldowns = EngineCooldowns()
      let now = Date(timeIntervalSince1970: 9000)
      assertFalse(cooldowns.snapshot(now: now).active)
      cooldowns.configure(order: ["deepl", "gemini"])
      assertEquals("deepl", cooldowns.snapshot(now: now).current)
      cooldowns.pause("deepl", EnginePause(seconds: 1620, reason: .quota), now: now)
      let snap = cooldowns.snapshot(now: now)
      assertTrue(snap.active)
      assertEquals("gemini", snap.current)
      assertEquals([EngineCooldowns.Paused(engine: "deepl", seconds: 1620, reason: .quota)], snap.paused)
      cooldowns.noteAnswer("gemini")
      assertEquals("gemini", cooldowns.snapshot(now: now).current)
      assertEquals([], cooldowns.snapshot(now: now.addingTimeInterval(1700)).paused)
    }
    TestRun.test("FailoverChainTest.singleUnreachableDoesNotPause") {
      let clock = Clock()
      let cooldowns = EngineCooldowns()
      cooldowns.configure(order: ["deepl"])
      let deepL = ScriptedMember("deepl", .unreachable)
      let google = ScriptedMember("google", .translated("G"))
      let chain = FailoverTranslator(members: [deepL, google], cooldowns: cooldowns, clock: { clock.now })
      _ = chain.translate("a")
      assertFalse(cooldowns.isPaused("deepl", now: clock.now))
      assertEquals(1, deepL.calls)
    }
    TestRun.test("FailoverChainTest.twoConsecutiveUnreachablePauseFifteenSecondsThenReturn") {
      let clock = Clock()
      let cooldowns = EngineCooldowns()
      cooldowns.configure(order: ["deepl"])
      let deepL = ScriptedMember("deepl", .unreachable)
      let google = ScriptedMember("google", .translated("G"))
      let chain = FailoverTranslator(members: [deepL, google], cooldowns: cooldowns, clock: { clock.now })
      _ = chain.translate("a")
      _ = chain.translate("b")
      assertTrue(cooldowns.isPaused("deepl", now: clock.now))
      assertEquals(EngineCooldowns.Paused(engine: "deepl", seconds: 15, reason: .connection), cooldowns.snapshot(now: clock.now).paused.first
        ?? EngineCooldowns.Paused(engine: "", seconds: 0, reason: .busy))
      _ = chain.translate("c")
      assertEquals(2, deepL.calls, "beklemede istek atılmaz")
      clock.advance(16)
      assertFalse(cooldowns.isPaused("deepl", now: clock.now))
      _ = chain.translate("d")
      assertEquals(3, deepL.calls, "süre dolunca yeniden denenir")
    }
    TestRun.test("FailoverChainTest.successBetweenFailuresResetsCounter") {
      // unreachable(1) → cevap(0) → unreachable(1): bekleme yok.
      let clock = Clock()
      let cooldowns = EngineCooldowns()
      cooldowns.configure(order: ["deepl"])
      let deepL = ScriptedMember("deepl", .unreachable)
      let google = ScriptedMember("google", .translated("G"))
      let chain = FailoverTranslator(members: [deepL, google], cooldowns: cooldowns, clock: { clock.now })
      _ = chain.translate("a")
      deepL.outcome = .translated("D")
      _ = chain.translate("b")
      deepL.outcome = .unreachable
      _ = chain.translate("c")
      assertFalse(cooldowns.isPaused("deepl", now: clock.now))
      _ = chain.translate("d")
      assertTrue(cooldowns.isPaused("deepl", now: clock.now), "sıfırlandıktan sonra art arda 2 hata yine bekletir")
    }
    TestRun.test("FailoverChainTest.emptyReplyNeitherCountsNorResets") {
      // unreachable(1) → boş cevap (1 kalır) → unreachable(2): bekleme.
      let clock = Clock()
      let cooldowns = EngineCooldowns()
      cooldowns.configure(order: ["deepl"])
      let deepL = ScriptedMember("deepl", .unreachable)
      let google = ScriptedMember("google", .translated("G"))
      let chain = FailoverTranslator(members: [deepL, google], cooldowns: cooldowns, clock: { clock.now })
      _ = chain.translate("a")
      deepL.outcome = .failed
      _ = chain.translate("b")
      assertFalse(cooldowns.isPaused("deepl", now: clock.now))
      deepL.outcome = .unreachable
      _ = chain.translate("c")
      assertTrue(cooldowns.isPaused("deepl", now: clock.now), "boş cevap sayacı sıfırlamaz")
      // Yalnız boş cevaplar sayacı artırmaz: failed, failed, unreachable(1) → bekleme yok.
      let other = EngineCooldowns()
      other.configure(order: ["deepl"])
      let e = ScriptedMember("deepl", .failed)
      let chain2 = FailoverTranslator(members: [e, google], cooldowns: other, clock: { clock.now })
      _ = chain2.translate("a")
      _ = chain2.translate("b")
      e.outcome = .unreachable
      _ = chain2.translate("c")
      assertFalse(other.isPaused("deepl", now: clock.now), "boş cevaplar sayaca girmez")
    }
    TestRun.test("FailoverChainTest.lastMemberNeverPausedByUnreachable") {
      let clock = Clock()
      let cooldowns = EngineCooldowns()
      let google = ScriptedMember("google", .unreachable)
      let chain = FailoverTranslator(members: [google], cooldowns: cooldowns, clock: { clock.now })
      for _ in 0..<4 { _ = chain.translate("a") }
      assertFalse(cooldowns.isPaused("google", now: clock.now))
      assertEquals(4, google.calls)
    }
    TestRun.test("FailoverChainTest.geminiModeFollowsBypassProvider") {
      // Her satır yeni bir hatla okunur: ilk okuma hemen çeviriye gider, bellek önbelleği ve kararlılık karışmaz.
      // Satırlar StockLines'ta yok ("we've got company", "hold your horses"); deyim kuralları IdiomNormalizer'da var.
      func sent(_ line: String, bypassed: Bool?) -> [String] {
        var seen: [String] = []
        let clock = FakeClock()
        let p = SubtitlePipeline(translator: FunctionTranslator { text in seen.append(text); return "Çeviri" },
                                 sink: PackPipelineTest.TextSink(), translateExecutor: { $0() },
                                 stabilizer: SubtitleStabilizer(clock: { clock.now }))
        var options = PipelineOptions()
        options.engineId = "gemini"
        options.sourceLanguage = "en"
        options.targetLanguage = "tr"
        p.options = options
        if let bypassed { p.geminiBypassed = { bypassed } }
        p.onRead([line], nil)
        return seen
      }
      // "We've got company!": "^we've got company" → "hostiles are approaching" (büyük harf başı korunur).
      assertEquals(["We've got company!"], sent("We've got company!", bypassed: nil), "varsayılan: Gemini kipi")
      assertEquals(["We've got company!"], sent("We've got company!", bypassed: false), "Gemini beklemede değil: Gemini kipi")
      assertEquals(["Hostiles are approaching!"], sent("We've got company!", bypassed: true), "Gemini beklemede: normal kip")
      // "Hold your horses!": "hold your horses" → "slow down a moment" (başı büyük: "Slow …").
      assertEquals(["Hold your horses!"], sent("Hold your horses!", bypassed: false))
      assertEquals(["Slow down a moment!"], sent("Hold your horses!", bypassed: true))
    }
    TestRun.test("FailoverChainTest.fallbackIdReportsLocalAnswer") {
      let outer = FallbackTranslator(FunctionTranslator { _ in nil }, FunctionTranslator { _ in "Yerel" }, fallbackId: "apple")
      FallbackSignal.reset()
      assertEquals("Yerel", outer.translate("a") ?? "")
      assertTrue(FallbackSignal.marked)
      assertEquals("apple", FallbackSignal.answeredBy ?? "")
      FallbackSignal.reset()
      assertNull(FallbackSignal.answeredBy)
    }
    TestRun.test("FailoverChainTest.originUsesAnsweringEngine") {
      assertEquals("gemini", SubtitlePipeline.engineOrigin("deepl", fallbackAnswered: true, answeredBy: "gemini"))
      assertEquals("deepl", SubtitlePipeline.engineOrigin("gemini", fallbackAnswered: true, answeredBy: "deepl"))
      assertEquals("google", SubtitlePipeline.engineOrigin("deepl", fallbackAnswered: true, answeredBy: "google"))
      assertEquals("deepl", SubtitlePipeline.engineOrigin("deepl", fallbackAnswered: false, answeredBy: "deepl"))
      assertEquals("google", SubtitlePipeline.engineOrigin("deepl", fallbackAnswered: true, answeredBy: nil), "kimlik yoksa eski tahmin")
      assertEquals("apple", SubtitlePipeline.engineOrigin("deepl", fallbackAnswered: true, answeredBy: "apple"))
    }
  }
}
