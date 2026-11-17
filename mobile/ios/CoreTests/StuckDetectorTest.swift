// SPDX-License-Identifier: AGPL-3.0-only
// Core/StuckDetector.swift testleri (Kotlin karşılığı yok).
import Foundation

enum StuckDetectorTest {
  static func run() {
    TestRun.test("StuckDetectorTest.healthyReadingNeverTriggers") {
      var d = StuckDetector()
      var t: Int64 = 0
      while t < 60_000 {
        d.frame(at: t)
        d.readStarted(at: t)
        d.readFinished(at: t + 300)
        assertNull(d.check(at: t + 300))
        t += 500
      }
    }
    TestRun.test("StuckDetectorTest.busyTooLong") {
      var d = StuckDetector()
      d.frame(at: 0)
      d.readStarted(at: 0)
      d.frame(at: 5000)
      assertNull(d.check(at: 5000))
      d.frame(at: StuckDetector.BUSY_MAX_MS)
      assertEquals(StuckDetector.Reason.busyTooLong, d.check(at: StuckDetector.BUSY_MAX_MS))
    }
    TestRun.test("StuckDetectorTest.noResultWhileFramesKeepComing") {
      var d = StuckDetector()
      var t: Int64 = 0
      d.frame(at: 0)
      while t < StuckDetector.NO_RESULT_MS - 500 {
        t += 400
        d.frame(at: t)
        assertNull(d.check(at: t))
      }
      t += 600
      d.frame(at: t)
      assertEquals(StuckDetector.Reason.noResult, d.check(at: t))
    }
    TestRun.test("StuckDetectorTest.noFramesIsNotStuck") {
      var d = StuckDetector()
      d.frame(at: 0)
      assertNull(d.check(at: 60_000), "kareler durduysa takılma değil")
    }
    TestRun.test("StuckDetectorTest.gapInFramesIsNotStuck") {
      var d = StuckDetector()
      d.frame(at: 0)
      d.frame(at: 60_000)
      assertNull(d.check(at: 60_000), "uzun boşluktan sonra ilk kare takılma sayılmaz")
      d.frame(at: 60_400)
      assertNull(d.check(at: 60_400))
    }
    TestRun.test("StuckDetectorTest.identicalFramesWithResultsNeverTrigger") {
      // Duraklatılmış oyun: kareler aynı olsa da okuma bitiyor; kurtarma yok.
      var d = StuckDetector()
      var t: Int64 = 0
      while t < 120_000 {
        d.frame(at: t)
        d.readStarted(at: t)
        d.readFinished(at: t)
        assertNull(d.check(at: t))
        t += 250
      }
    }
    TestRun.test("StuckDetectorTest.cooldownAfterRecovery") {
      var d = StuckDetector()
      d.frame(at: 0)
      d.readStarted(at: 0)
      assertEquals(StuckDetector.Reason.busyTooLong, d.check(at: 9000))
      d.frame(at: 9500)
      d.readStarted(at: 9500)
      assertNull(d.check(at: 20_000), "bekleme süresinde yeni kurtarma yok")
      assertEquals(StuckDetector.Reason.busyTooLong, d.check(at: 9000 + StuckDetector.COOLDOWN_MS))
    }
  }
}
