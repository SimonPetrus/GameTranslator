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

/// Core/ReadingSelector.swift'teki LineHeight ve LineHeightTracker (TV'ye giden tek satır yüksekliği). Kare 1000 piksel
/// yüksek varsayılır: 40 piksel = 0,04.
enum LineHeightTest {
  static func run() {
    func obs(_ text: String, _ l: Int, _ t: Int, _ r: Int, _ b: Int) -> TextObservation {
      TextObservation(text: text, confidence: 0.9, left: l, top: t, right: r, bottom: b)
    }
    func near(_ expected: Double, _ actual: Double?, _ message: String = "", file: String = #fileID, line: Int = #line) {
      guard let actual else { return TestRun.fail("\(message) \(expected) bekleniyordu, nil geldi", file, line) }
      if abs(expected - actual) > 1e-9 { TestRun.fail("\(message) \(expected) bekleniyordu, \(actual) geldi", file, line) }
    }
    // 26 karakter, 400 piksel: karakter başına ~15,4 piksel, 40 piksel yükseklikte oran 2,6 (tek satır).
    let line1 = "We need to leave right now"

    TestRun.test("LineHeightTest.singleAndSeparateLines") {
      near(0.04, LineHeight.estimate([obs(line1, 300, 900, 700, 940)], frameHeight: 1000))
      near(0.04, LineHeight.estimate([obs(line1, 300, 850, 700, 890), obs(line1, 300, 900, 700, 940)], frameHeight: 1000))
    }
    TestRun.test("LineHeightTest.twoLinesInOneObservationAreHalved") {
      // 51 karakter tek satır genişliğinde (400 px), 85 px yükseklik: oran 85 / (400/51) = 10,84; √(10,84/2,6) ≈ 2,04 → 2 satır.
      near(0.0425, LineHeight.estimate([obs("We need to leave right now before they find us here", 300, 860, 700, 945)], frameHeight: 1000))
      // Kısa metinli iki satırlık parça (karakter oranı ölçülmez): komşularının ortancasının 2 katı → ikiye bölünür.
      // Eski kural (ortanca yerine üstteki değer) burada 80 px (0,08) gönderiyordu.
      near(0.04, LineHeight.estimate([obs("Hey", 450, 820, 550, 860), obs("Hey you", 430, 870, 570, 950)], frameHeight: 1000))
    }
    TestRun.test("LineHeightTest.mixedHeightsAndOutliers") {
      // Büyük/küçük harf ve alt çıkıntı farkı: 38, 40, 42 → ortanca 40.
      near(0.04, LineHeight.estimate([obs(line1, 300, 800, 700, 838), obs(line1, 300, 850, 700, 890), obs(line1, 300, 900, 700, 942)],
                                     frameHeight: 1000))
      // Kısa dev parça (120 px) uzun satırlar varken hiç sayılmaz.
      near(0.04, LineHeight.estimate([obs(line1, 300, 800, 700, 840), obs(line1, 300, 850, 700, 890), obs("OK", 480, 700, 520, 820)],
                                     frameHeight: 1000))
      // İki uzun satır, biri alt çıkıntılı (40 ve 44 px): büyüğe yakın olan, satırın gerçek kutu yüksekliği.
      near(0.044, LineHeight.estimate([obs(line1, 300, 850, 700, 890), obs(line1, 300, 900, 700, 944)], frameHeight: 1000))
      // Uzun satırda komşusunun 1,7 katından uzun parça (84 px) yine satır sayısına bölünür: 84 / 2 = 42.
      near(0.042, LineHeight.estimate([obs(line1, 300, 800, 700, 840), obs(line1, 300, 860, 700, 944)], frameHeight: 1000))
    }
    TestRun.test("LineHeightTest.shortPiecesDoNotShrinkAFullLine") {
      // Tam satır (44 px) + kısa küçük harfli "me" (13 px): yalnız uzun satıra bakılır.
      near(0.044, LineHeight.estimate([obs(line1, 300, 900, 700, 944), obs("me", 490, 950, 510, 963)], frameHeight: 1000))
      // Tam satır + alt çıkıntısız kısa satır (34 px).
      near(0.044, LineHeight.estimate([obs(line1, 300, 900, 700, 944), obs("Go now", 460, 950, 540, 984)], frameHeight: 1000))
    }
    TestRun.test("LineHeightTest.unreliableEstimateIsNotSent") {
      assertNull(LineHeight.estimate([], frameHeight: 1000))
      assertNull(LineHeight.estimate([obs("OK", 450, 700, 550, 900)], frameHeight: 1000), "0,2: sınırın üstünde")
      assertNull(LineHeight.estimate([obs("OK", 450, 900, 550, 905)], frameHeight: 1000), "0,005: sınırın altında")
      assertNull(LineHeight.estimate([obs(line1, 300, 900, 700, 940)], frameHeight: 0))
    }
    TestRun.test("LineHeightTest.trackerKeepsTheSizeSteady") {
      var tracker = LineHeightTracker(capacity: 3)
      assertNull(tracker.add(nil))
      near(0.04, tracker.add(0.04))
      near(0.04, tracker.add(nil), "ölçüm yoksa son değerler")
      near(0.04, tracker.add(0.08), "tek büyük ölçüm boyu büyütmez")
      near(0.05, tracker.add(0.05))
      near(0.05, tracker.add(0.03), "en eski (0,04) düşer: 0,03 0,05 0,08")
      tracker.reset()
      assertNull(tracker.add(nil))
    }
    TestRun.test("LineHeightTest.sentOnlyWhenMatchingTheGameSize") {
      near(0.04, LineHeight.toSend(0.04, matchGameTextSize: true))
      assertNull(LineHeight.toSend(0.04, matchGameTextSize: false))
      assertNull(LineHeight.toSend(nil, matchGameTextSize: true))
    }
  }
}
