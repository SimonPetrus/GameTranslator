// SPDX-License-Identifier: AGPL-3.0-only
// DeepL anahtar kontrolü sonuç mantığının testleri (Kotlin karşılığı yok).
import Foundation

enum DeepLCheckTest {
  private static func body(_ json: String) -> Data { Data(json.utf8) }

  static func run() {
    TestRun.test("DeepLCheckTest.okWithQuota") {
      let (ok, text) = DeepLCheck.outcome(status: 200, body: body("{\"character_count\":12345,\"character_limit\":500000}"))
      assertTrue(ok)
      assertEquals("Anahtar çalışıyor. Bu ay 12.345 / 500.000 karakter kullanıldı.", text)
    }
    TestRun.test("DeepLCheckTest.okWithoutQuota") {
      for json in ["{}", "{\"character_count\":5}", "{\"character_count\":5,\"character_limit\":0}"] {
        let (ok, text) = DeepLCheck.outcome(status: 200, body: body(json))
        assertTrue(ok, json)
        assertEquals("Anahtar çalışıyor.", text, json)
      }
    }
    TestRun.test("DeepLCheckTest.okWithBrokenBody") {
      for data in [body("not json"), body("[1,2]"), Data()] {
        let (ok, text) = DeepLCheck.outcome(status: 200, body: data)
        assertTrue(ok)
        assertEquals("Anahtar çalışıyor.", text)
      }
      let (ok, _) = DeepLCheck.outcome(status: 200, body: nil)
      assertTrue(ok)
    }
    TestRun.test("DeepLCheckTest.invalidKey") {
      let (ok, text) = DeepLCheck.outcome(status: 403, body: nil)
      assertFalse(ok)
      assertTrue(text.contains("kabul edilmedi"))
    }
    TestRun.test("DeepLCheckTest.quotaExceeded") {
      let (ok, text) = DeepLCheck.outcome(status: 456, body: body("{\"message\":\"Quota exceeded\"}"))
      assertFalse(ok)
      assertTrue(text.contains("geçerli"), "anahtarın geçerli olduğu söylenmeli")
      assertTrue(text.contains("kota"))
    }
    TestRun.test("DeepLCheckTest.tooManyRequests") {
      let (ok, text) = DeepLCheck.outcome(status: 429, body: nil)
      assertFalse(ok)
      assertTrue(text.contains("Biraz sonra"))
    }
    TestRun.test("DeepLCheckTest.unexpectedCode") {
      let (ok, text) = DeepLCheck.outcome(status: 503, body: nil)
      assertFalse(ok)
      assertTrue(text.contains("503"))
    }
    TestRun.test("DeepLCheckTest.emptyKeyAndUnreachable") {
      assertFalse(DeepLCheck.emptyKey.0)
      assertFalse(DeepLCheck.unreachable.0)
      assertTrue(DeepLCheck.unreachable.1.contains("İnternet"))
    }
    TestRun.test("DeepLCheckTest.groupedNumbers") {
      assertEquals("0", DeepLCheck.grouped(0))
      assertEquals("999", DeepLCheck.grouped(999))
      assertEquals("1.000", DeepLCheck.grouped(1000))
      assertEquals("500.000", DeepLCheck.grouped(500000))
      assertEquals("1.234.567", DeepLCheck.grouped(1234567))
    }
  }
}
