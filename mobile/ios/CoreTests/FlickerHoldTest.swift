// SPDX-License-Identifier: AGPL-3.0-only
// Core/FlickerHold.swift ve kararlayıcıdaki titreme tutma kuralları (Kotlin karşılığı yok).
import Foundation

enum FlickerHoldTest {
  static func run() {
    func stabilizer(_ clock: FakeClock) -> SubtitleStabilizer { SubtitleStabilizer(clock: { clock.now }) }

    TestRun.test("FlickerHoldTest.similarOrDroppedWordIsFlicker") {
      assertTrue(FlickerHold.isFlicker("we need to leave the city now", "we need to leave the city nov"))
      assertTrue(FlickerHold.isFlicker("we need to leave city now", "we need to leave the city now"))
      assertTrue(FlickerHold.isFlicker("we need leave city now", "we need to leave the city now"))
    }
    TestRun.test("FlickerHoldTest.differentOrLongerLineIsNotFlicker") {
      assertFalse(FlickerHold.isFlicker("get in the car", "we need to leave the city now"))
      // Büyüyen satır (daktilo) yeni satırdır.
      assertFalse(FlickerHold.isFlicker("we need to leave the city now please", "we need to leave the city now"))
      // Çok sözcük düşmüşse titreme değil.
      assertFalse(FlickerHold.isFlicker("we need to", "we need to leave the city now"))
      assertFalse(FlickerHold.isFlicker("", "abc def ghi"))
      assertFalse(FlickerHold.isFlicker("abc def ghi", ""))
    }
    TestRun.test("FlickerHoldTest.noisyOnlyAfterEnoughEventsInWindow") {
      var h = FlickerHold()
      assertFalse(h.isNoisy(0))
      h.note(0)
      assertFalse(h.isNoisy(100))
      h.note(500)
      assertTrue(h.isNoisy(1000))
      assertFalse(h.isNoisy(10_000))
      assertEquals(800, h.clearDelay(base: 800, at: 10_000))
      assertEquals(FlickerHold.EXTENDED_CLEAR_MS, h.clearDelay(base: 800, at: 1000))
      h.reset()
      assertFalse(h.isNoisy(1000))
    }
    TestRun.test("FlickerHoldTest.droppedWordKeepsCurrentLine") {
      let c = FakeClock()
      let s = stabilizer(c)
      assertEquals(StabilizerAction.translate("We need to leave the city now."), s.feed("We need to leave the city now."))
      c.now += 200
      assertEquals(StabilizerAction.None, s.feed("We need to leave city now."))
      c.now += 200
      assertEquals(StabilizerAction.None, s.feed("We need to leave city now."))
    }
    TestRun.test("FlickerHoldTest.noisyBackgroundHoldsLineDuringEmptyReads") {
      let c = FakeClock()
      let s = stabilizer(c)
      _ = s.feed("We need to leave the city now.")
      // İki titreme (boşluktan dönüş + düşen sözcük) arka planı gürültülü yapar.
      c.now += 200; _ = s.feed("")
      c.now += 200; assertEquals(StabilizerAction.None, s.feed("We need to leave the city now."))
      c.now += 200; assertEquals(StabilizerAction.None, s.feed("We need to leave city now."))
      c.now += 200; assertEquals(StabilizerAction.None, s.feed(""))
      c.now += 1500
      assertEquals(StabilizerAction.None, s.feed(""), "800 ms sonra kalkmamalı")
      c.now += 2500
      assertEquals(StabilizerAction.Clear, s.feed(""), "tutma süresi bitince kalkmalı")
    }
    TestRun.test("FlickerHoldTest.quietBackgroundStillClearsAfterNormalDelay") {
      let c = FakeClock()
      let s = stabilizer(c)
      _ = s.feed("We need to leave the city now.")
      c.now += 300; assertEquals(StabilizerAction.None, s.feed(""))
      c.now += 900; assertEquals(StabilizerAction.Clear, s.feed(""))
    }
    TestRun.test("FlickerHoldTest.newLineIsNotDelayed") {
      let c = FakeClock()
      let s = stabilizer(c)
      _ = s.feed("We need to leave the city now.")
      c.now += 200; _ = s.feed("")
      c.now += 200; _ = s.feed("We need to leave the city now.")
      c.now += 200; _ = s.feed("We need to leave city now.")
      c.now += 200
      assertEquals(StabilizerAction.translate("Get in the car."), s.feed("Get in the car."))
    }
  }
}
