// SPDX-License-Identifier: AGPL-3.0-only
// Core/ReadingSelector.swift testleri (Kotlin karşılığı yok). Bölge 1000x200 piksel varsayılır.
import Foundation

enum ReadingSelectorTest {
  static func run() {
    func obs(_ text: String, _ conf: Double, _ l: Int, _ t: Int, _ r: Int, _ b: Int) -> TextObservation {
      TextObservation(text: text, confidence: conf, left: l, top: t, right: r, bottom: b)
    }
    let w = 1000, h = 200

    TestRun.test("ReadingSelectorTest.lowConfidenceIsDropped") {
      let list = [obs("good text here", 0.9, 300, 150, 700, 180), obs("noise", 0.2, 300, 10, 400, 30), obs("edge", 0.35, 300, 60, 500, 80)]
      let kept = ReadingSelector.filterConfidence(list)
      assertEquals(2, kept.count)
      assertEquals("good text here", kept[0].text)
      assertEquals("edge", kept[1].text)
    }
    TestRun.test("ReadingSelectorTest.edgeCutTextIsDropped") {
      let list = [
        obs("cut off on the left", 0.9, 0, 150, 300, 180),
        obs("cut off on the right", 0.9, 700, 100, 1000, 130),
        obs("proper subtitle line", 0.9, 250, 150, 750, 180),
        obs("a very very wide line", 0.9, 0, 40, 1000, 70),
      ]
      let kept = ReadingSelector.dropEdgeCut(list, width: w).map(\.text)
      assertEquals(["proper subtitle line", "a very very wide line"], kept)
    }
    TestRun.test("ReadingSelectorTest.edgeCutKeepsOriginalsWhenNothingElseSurvives") {
      let only = [obs("narrow region subtitle", 0.9, 0, 150, 1000, 180)]
      let left = [obs("touches left only", 0.9, 0, 150, 600, 180)]
      assertEquals(1, ReadingSelector.dropEdgeCut(only, width: w).count)
      assertEquals(1, ReadingSelector.dropEdgeCut(left, width: w).count, "tek parça kesik görünse de korunur")
      let mixed = left + [obs("fine line here", 0.9, 250, 100, 750, 130)]
      assertEquals(["fine line here"], ReadingSelector.dropEdgeCut(mixed, width: w).map(\.text))
    }
    TestRun.test("ReadingSelectorTest.blocksSplitOnLargeGap") {
      let list = [obs("one", 0.9, 300, 140, 700, 165), obs("two", 0.9, 300, 168, 700, 193), obs("far", 0.9, 300, 10, 400, 35)]
      let blocks = ReadingSelector.blocks(list)
      assertEquals(2, blocks.count)
      assertEquals(["far"], blocks[0].map(\.text))
      assertEquals(["one", "two"], blocks[1].map(\.text))
      assertEquals(0, ReadingSelector.blocks([]).count)
    }
    TestRun.test("ReadingSelectorTest.subtitleBlockBeatsCornerUi") {
      let list = [
        obs("Where do you think you are going", 0.95, 250, 140, 750, 168),
        obs("with that thing?", 0.95, 350, 170, 650, 198),
        obs("SKIP", 0.9, 850, 20, 950, 60),
        obs("Chapter 3", 0.9, 20, 20, 200, 50),
      ]
      let selected = ReadingSelector.select(list, width: w, height: h)
      assertEquals(["Where do you think you are going", "with that thing?"], selected.map(\.text))
    }
    TestRun.test("ReadingSelectorTest.singleBlockIsKeptWhole") {
      let list = [obs("first line of text", 0.9, 300, 120, 700, 148), obs("second line of text", 0.9, 300, 152, 700, 180)]
      assertEquals(2, ReadingSelector.select(list, width: w, height: h).count)
    }
    TestRun.test("ReadingSelectorTest.scoreFavoursCentredBottomMultiWord") {
      let good = [obs("this is a subtitle", 0.9, 300, 150, 700, 180)]
      let corner = [obs("HUD", 0.9, 0, 5, 80, 30)]
      assertTrue(ReadingSelector.score(good, width: w, height: h) > ReadingSelector.score(corner, width: w, height: h))
      assertEquals(0.0, ReadingSelector.score([], width: w, height: h), accuracy: 0.0001)
    }
    TestRun.test("ReadingSelectorTest.retryDecision") {
      assertTrue(ReadingSelector.needsRetry([]))
      assertTrue(ReadingSelector.needsRetry([obs("weak", 0.4, 300, 150, 700, 180)]))
      assertFalse(ReadingSelector.needsRetry([obs("fine", 0.8, 300, 150, 700, 180)]))
      let weak = [obs("weak", 0.4, 300, 150, 700, 180)]
      let strong = [obs("strong", 0.8, 300, 150, 700, 180)]
      assertTrue(ReadingSelector.isBetter(strong, than: weak))
      assertTrue(ReadingSelector.isBetter(weak, than: []))
      assertFalse(ReadingSelector.isBetter([], than: weak))
      assertFalse(ReadingSelector.isBetter(weak, than: strong))
    }
    TestRun.test("ReadingSelectorTest.emptyScreenDoesNotRetryUnlessSubtitleWasJustSeen") {
      let weak = [obs("weak", 0.4, 300, 150, 700, 180)]
      assertFalse(ReadingSelector.shouldRetry(rawCount: 0, selected: [], lastSubtitleAt: nil, now: 10_000))
      assertFalse(ReadingSelector.shouldRetry(rawCount: 0, selected: [], lastSubtitleAt: 1000, now: 10_000))
      assertTrue(ReadingSelector.shouldRetry(rawCount: 0, selected: [], lastSubtitleAt: 8000, now: 10_000))
      assertTrue(ReadingSelector.shouldRetry(rawCount: 0, selected: [], lastSubtitleAt: 7000, now: 10_000))
      assertFalse(ReadingSelector.shouldRetry(rawCount: 0, selected: [], lastSubtitleAt: 6999, now: 10_000))
      // Parçalar var ama güvensiz ya da süzülüp boşalmış: eskisi gibi yeniden okunur.
      assertTrue(ReadingSelector.shouldRetry(rawCount: 2, selected: weak, lastSubtitleAt: nil, now: 10_000))
      assertTrue(ReadingSelector.shouldRetry(rawCount: 2, selected: [], lastSubtitleAt: nil, now: 10_000))
      assertFalse(ReadingSelector.shouldRetry(rawCount: 1, selected: [obs("ok", 0.9, 300, 150, 700, 180)], lastSubtitleAt: nil, now: 10_000))
    }
    TestRun.test("ReadingSelectorTest.retryScaleIsCapped") {
      assertEquals(2.0, ReadingSelector.retryScale(bandWidth: 800)!, accuracy: 0.0001)
      assertEquals(2000.0 / 1161.0, ReadingSelector.retryScale(bandWidth: 1161)!, accuracy: 0.0001)
      assertNull(ReadingSelector.retryScale(bandWidth: 1800))
      assertNull(ReadingSelector.retryScale(bandWidth: 0))
    }
    TestRun.test("ReadingSelectorTest.retryBandIsCentredInsideRegion") {
      let band = ReadingSelector.retryBand(width: 1000, height: 200)
      assertEquals(80, band.x)
      assertEquals(20, band.y)
      assertEquals(840, band.width)
      assertEquals(180, band.height)
    }
    TestRun.test("ReadingSelectorTest.pixelConversion") {
      // Vision: sol alttan 0–1. Büyütmesiz: x 0.1–0.5, y(alttan) 0.0–0.25 → üstten 150–200.
      let p = ReadingSelector.pixels(minX: 0.1, minY: 0.0, maxX: 0.5, maxY: 0.25, imageWidth: 1000, imageHeight: 200)
      assertEquals(100, p.left); assertEquals(500, p.right); assertEquals(150, p.top); assertEquals(200, p.bottom)
      // 2x büyütülmüş, bölgede (80,20) konumundaki bant: 1680x360 görüntü.
      let q = ReadingSelector.pixels(minX: 0.5, minY: 0.0, maxX: 1.0, maxY: 0.5, imageWidth: 1680, imageHeight: 360,
                                     offsetX: 80, offsetY: 20, scale: 2)
      assertEquals(500, q.left); assertEquals(920, q.right); assertEquals(110, q.top); assertEquals(200, q.bottom)
    }
    TestRun.test("ReadingSelectorTest.retryLimiterRateLimits") {
      var limiter = RetryLimiter(minInterval: 2000)
      assertTrue(limiter.allow(at: 1000))
      assertFalse(limiter.allow(at: 2000))
      assertFalse(limiter.allow(at: 2999))
      assertTrue(limiter.allow(at: 3000))
      limiter.reset()
      assertTrue(limiter.allow(at: 3001))
    }
  }
}
