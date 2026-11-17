// SPDX-License-Identifier: AGPL-3.0-only
// Core/StuckDetector.swift testleri (Kotlin karşılığı yok).
import Foundation

enum StuckDetectorTest {
  static func run() {
    TestRun.test("StuckDetectorTest.healthyReadingNeverTriggers") {
      var d = StuckDetector()
      var t: Int64 = 0
      while t < 60_000 {
        d.frame(at: t, hash: Int(t))
        d.readStarted(at: t)
        d.readFinished(at: t + 300)
        assertNull(d.check(at: t + 300))
        t += 500
      }
    }
    TestRun.test("StuckDetectorTest.busyTooLong") {
      var d = StuckDetector()
      d.frame(at: 0, hash: 1)
      d.readStarted(at: 0)
      d.frame(at: 5000, hash: 2)
      assertNull(d.check(at: 5000))
      d.frame(at: StuckDetector.BUSY_MAX_MS, hash: 3)
      assertEquals(StuckDetector.Reason.busyTooLong, d.check(at: StuckDetector.BUSY_MAX_MS))
    }
    TestRun.test("StuckDetectorTest.noResultWhileFramesKeepComing") {
      var d = StuckDetector()
      var t: Int64 = 0
      d.frame(at: 0, hash: 0)
      while t < StuckDetector.NO_RESULT_MS - 500 {
        t += 400
        d.frame(at: t, hash: Int(t))
        assertNull(d.check(at: t))
      }
      t += 600
      d.frame(at: t, hash: Int(t))
      assertEquals(StuckDetector.Reason.noResult, d.check(at: t))
    }
    TestRun.test("StuckDetectorTest.noFramesIsNotStuck") {
      var d = StuckDetector()
      d.frame(at: 0, hash: 0)
      assertNull(d.check(at: 60_000), "kareler durduysa takılma değil")
    }
    TestRun.test("StuckDetectorTest.frozenFrameNeedsTimeAndCount") {
      var d = StuckDetector()
      var t: Int64 = 0
      // Sonuçlar akıyor (okuma biter) ama aynı özet tekrarlıyor.
      var reason: StuckDetector.Reason?
      while t <= StuckDetector.SAME_FRAME_MS + 1000 && reason == nil {
        d.frame(at: t, hash: 42)
        d.readStarted(at: t)
        d.readFinished(at: t)
        reason = d.check(at: t)
        t += 250
      }
      assertEquals(StuckDetector.Reason.frozenFrame, reason)
      // Az kare: süre dolsa da sayı yetmez.
      var e = StuckDetector()
      e.frame(at: 0, hash: 7)
      e.readFinished(at: 0)
      e.frame(at: 25_000, hash: 7)
      e.readFinished(at: 25_000)
      assertNull(e.check(at: 25_000))
    }
    TestRun.test("StuckDetectorTest.changingHashResetsFrozenCount") {
      var d = StuckDetector()
      var t: Int64 = 0
      while t < 40_000 {
        d.frame(at: t, hash: t % 2000 == 0 ? 1 : 2)
        d.readStarted(at: t)
        d.readFinished(at: t)
        assertNull(d.check(at: t))
        t += 250
      }
    }
    TestRun.test("StuckDetectorTest.cooldownAfterRecovery") {
      var d = StuckDetector()
      d.frame(at: 0, hash: 1)
      d.readStarted(at: 0)
      assertEquals(StuckDetector.Reason.busyTooLong, d.check(at: 9000))
      d.frame(at: 9500, hash: 2)
      d.readStarted(at: 9500)
      assertNull(d.check(at: 20_000), "bekleme süresinde yeni kurtarma yok")
      assertEquals(StuckDetector.Reason.busyTooLong, d.check(at: 9000 + StuckDetector.COOLDOWN_MS))
    }
    TestRun.test("StuckDetectorTest.hashOfBytes") {
      let a = [UInt8](repeating: 1, count: 10_000)
      var b = a
      b[5000] = 9
      let ha = a.withUnsafeBytes { StuckDetector.hash(of: $0, samples: 10_000) }
      let hb = b.withUnsafeBytes { StuckDetector.hash(of: $0, samples: 10_000) }
      let ha2 = a.withUnsafeBytes { StuckDetector.hash(of: $0, samples: 10_000) }
      assertNotNull(ha)
      assertEquals(ha, ha2)
      assertNotEquals(ha, hb)
      assertNull([UInt8]().withUnsafeBytes { StuckDetector.hash(of: $0) })
    }
  }
}
