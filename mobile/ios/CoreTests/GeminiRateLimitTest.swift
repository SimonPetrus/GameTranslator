// SPDX-License-Identifier: AGPL-3.0-only
// Core/GeminiRateLimit.swift (429 çözümü, model listesi) ve Core/LanguageCodes.swift testleri.
import Foundation

enum GeminiRateLimitTest {
  private static func body(_ json: String) -> Data { Data(json.utf8) }

  static func run() {
    TestRun.test("GeminiRateLimitTest.perMinuteUsesRetryDelay") {
      let d = GeminiRateLimit.decide(body("""
      {"error":{"code":429,"message":"Quota exceeded","status":"RESOURCE_EXHAUSTED","details":[
        {"@type":"type.googleapis.com/google.rpc.QuotaFailure","violations":[
          {"quotaMetric":"generativelanguage.googleapis.com/generate_content_free_tier_requests",
           "quotaId":"GenerateRequestsPerMinutePerProjectPerModel-FreeTier","quotaValue":"15"}]},
        {"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"37s"}]}}
      """))
      assertFalse(d.daily)
      assertEquals(37.0, d.retryDelay ?? -1)
      assertEquals(39.0, d.seconds)
    }
    TestRun.test("GeminiRateLimitTest.dailyQuotaPausesAnHour") {
      let d = GeminiRateLimit.decide(body("""
      {"error":{"code":429,"message":"You exceeded your current quota","details":[
        {"@type":"type.googleapis.com/google.rpc.QuotaFailure","violations":[
          {"quotaId":"GenerateRequestsPerDayPerProjectPerModel-FreeTier","quotaValue":"20"}]},
        {"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"12.5s"}]}}
      """))
      assertTrue(d.daily)
      assertEquals(3600.0, d.seconds)
    }
    TestRun.test("GeminiRateLimitTest.clampsAndDefaults") {
      let short = GeminiRateLimit.decide(body(#"{"error":{"details":[{"@type":"x.RetryInfo","retryDelay":"0.4s"}]}}"#))
      assertEquals(5.0, short.seconds)
      let long = GeminiRateLimit.decide(body(#"{"error":{"details":[{"@type":"x.RetryInfo","retryDelay":"900s"}]}}"#))
      assertEquals(300.0, long.seconds)
      assertEquals(60.0, GeminiRateLimit.decide(nil).seconds)
      assertEquals(60.0, GeminiRateLimit.decide(body("not json")).seconds)
      assertEquals(60.0, GeminiRateLimit.decide(body(#"{"error":{"message":"busy"}}"#)).seconds)
    }
    TestRun.test("GeminiRateLimitTest.durationParsing") {
      assertEquals(37.0, GeminiRateLimit.parseDuration("37s") ?? -1)
      assertEquals(0.5, GeminiRateLimit.parseDuration("0.5s") ?? -1)
      assertEquals(90.0, GeminiRateLimit.parseDuration("1m30s") ?? -1)
      assertEquals(0.25, GeminiRateLimit.parseDuration("250ms") ?? -1)
      assertEquals(12.0, GeminiRateLimit.parseDuration("12") ?? -1)
      assertNull(GeminiRateLimit.parseDuration("abc"))
      assertNull(GeminiRateLimit.parseDuration(""))
    }
    TestRun.test("GeminiRateLimitTest.modelWhitelist") {
      assertEquals("gemini-3.6-flash", GeminiModels.resolve("gemini-3.6-flash"))
      assertEquals(GeminiModels.defaultId, GeminiModels.resolve("gemini-1.0-ultra"))
      assertEquals(GeminiModels.defaultId, GeminiModels.resolve(nil))
      assertEquals(GeminiModels.defaultId, GeminiModels.resolve(""))
    }
    TestRun.test("LanguageCodesTest.googleCodes") {
      assertEquals("zh-CN", LanguageCodes.google("zh"))
      assertEquals("iw", LanguageCodes.google("he"))
      for code in LanguageCodes.supported where code != "zh" && code != "he" { assertEquals(code, LanguageCodes.google(code)) }
    }
    TestRun.test("LanguageCodesTest.deepLCodes") {
      assertEquals(27, LanguageCodes.supported.count)
      assertEquals("EN-US", LanguageCodes.deepLTarget("en") ?? "")
      assertEquals("PT-BR", LanguageCodes.deepLTarget("pt") ?? "")
      assertEquals("ZH-HANS", LanguageCodes.deepLTarget("zh") ?? "")
      assertEquals("TR", LanguageCodes.deepLTarget("tr") ?? "")
      assertEquals("EN", LanguageCodes.deepLSource("en") ?? "")
      for code in ["hi", "fa", "th", "vi", "he", "az"] { assertNull(LanguageCodes.deepLTarget(code), code) }
      for code in LanguageCodes.supported where !["hi", "fa", "th", "vi", "he", "az"].contains(code) {
        assertNotNull(LanguageCodes.deepLTarget(code), code)
      }
    }
    TestRun.test("LanguageCodesTest.visionMapping") {
      let ios16 = ["en-US", "fr-FR", "it-IT", "de-DE", "es-ES", "pt-BR", "zh-Hans", "zh-Hant", "yue-Hans", "yue-Hant",
                   "ko-KR", "ja-JP", "ru-RU", "uk-UA"]
      assertEquals("en-US", LanguageCodes.visionLanguage("en", supported: ios16) ?? "")
      assertEquals("zh-Hans", LanguageCodes.visionLanguage("zh", supported: ios16) ?? "")
      assertEquals("ja-JP", LanguageCodes.visionLanguage("ja", supported: ios16) ?? "")
      assertEquals("pt-BR", LanguageCodes.visionLanguage("pt", supported: ios16) ?? "")
      assertNull(LanguageCodes.visionLanguage("th", supported: ios16))
      assertNull(LanguageCodes.visionLanguage("ar", supported: ios16))
      assertEquals("vi-VT", LanguageCodes.visionLanguage("vi", supported: ["en-US", "vi-VT"]) ?? "")
      assertEquals("pt-PT", LanguageCodes.visionLanguage("pt", supported: ["pt-PT"]) ?? "")
      assertEquals("en", LanguageCodes.visionLanguage("en", supported: ["en"]) ?? "")
      assertEquals("tr-TR", LanguageCodes.visionLanguage("TR", supported: ["tr-TR"]) ?? "")
      assertNull(LanguageCodes.visionLanguage("ja", supported: []))
    }
    TestRun.test("LanguageCodesTest.appleCodes") {
      assertEquals("zh-Hans", LanguageCodes.apple("zh"))
      assertEquals("tr", LanguageCodes.apple("tr"))
    }
  }
}
