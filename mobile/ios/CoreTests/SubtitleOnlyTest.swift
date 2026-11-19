// SPDX-License-Identifier: AGPL-3.0-only
// Core/SubtitleOnly.swift ("Yalnız altyazıyı çevir" süzgeci) ve Core/CoverKeeper.swift (kararlı örtme kutusu) testleri
// (Kotlin karşılığı yok). Kare 1000x1000 piksel, okuma alanı bütün kare: piksel / 1000 = ekrana oran.
import Foundation

enum SubtitleOnlyTest {
  static let frame = SubtitleOnlyFrame(cropX: 0, cropY: 0, width: 1000, height: 1000)

  static func obs(_ text: String, _ l: Int, _ t: Int, _ r: Int, _ b: Int, conf: Double = 0.9,
                  angle: Double? = nil) -> TextObservation {
    TextObservation(text: text, confidence: conf, left: l, top: t, right: r, bottom: b, angle: angle)
  }

  /// Altyazı satırları: 300–700 x, 900–940 y (40 px = 0,04; karakter oranıyla tek satır), ortası 0,5 / 0,92.
  static let lineA = "We need to leave right now"
  static let lineB = "Where is the money hidden"
  static let lineC = "Get on the horse and ride"

  static func texts(_ list: [TextObservation]) -> [String] { list.map(\.text) }

  static func reasons(_ outcome: SubtitleOnlyOutcome) -> [String] { outcome.drops.map { $0.observation.text + "=" + $0.reason.code } }

  /// Bir altyazıyı okunmuş ve TV'ye gönderilmiş gibi işler (süzme → okuma kaydı → gösterim).
  @discardableResult
  static func showLine(_ filter: inout SubtitleOnlyFilter, _ piece: TextObservation, at t: Int64) -> SubtitleOnlyShown {
    let outcome = filter.apply([piece], frame: frame, at: t, track: true)
    filter.rememberRead(lines: outcome.kept.map(\.text), selected: outcome.kept, frame: frame, at: t)
    return filter.noteShown(piece.text, at: t + 300)
  }

  /// Alt bantta (0,86–0,98) ortalı, tipik satırı 0,04 olan bant öğrenilmiş süzgeç.
  static func learnedBottom() -> SubtitleOnlyFilter {
    var filter = SubtitleOnlyFilter()
    showLine(&filter, obs(lineA, 300, 900, 700, 940), at: 0)
    showLine(&filter, obs(lineB, 300, 900, 700, 940), at: 1000)
    showLine(&filter, obs(lineC, 300, 900, 700, 940), at: 2000)
    return filter
  }

  /// Birbirine benzemeyen (sözcük kümeleri örtüşmeyen) cümle biçimli altyazı satırları; ilki [lineA].
  static let talk: [String] = [lineA, "Where is the money hidden", "Get on the horse and ride", "They are coming for us",
                               "I will hold them off here", "Stay down and keep quiet", "Nobody move or I shoot",
                               "Check the barn for supplies", "Your brother owes me money", "Watch your back out there",
                               "Bring the wagon around back", "This town has gone mad"]

  /// Yükleme ipuçlarından (ortalı, 480–510 px, satır 30 px) öğrenilmiş yanlış bant: 0,45–0,54, tipik 0,03.
  static func tipsBand() -> SubtitleOnlyFilter {
    var filter = SubtitleOnlyFilter()
    showLine(&filter, obs("Press the button to start", 300, 480, 700, 510), at: 0)
    showLine(&filter, obs("Hold the trigger to aim now", 300, 480, 700, 510), at: 1000)
    showLine(&filter, obs("Visit the shop for new gear", 300, 480, 700, 510), at: 2000)
    return filter
  }

  static func run() {
    TestRun.test("SubtitleOnlyTest.perLineMatchesEstimate") {
      // 26 karakter / 400 px / 40 px: oran 2,6 → tek satır; 51 karakterlik 85 px parça iki satır → 42,5.
      assertEquals(40.0, LineHeight.perLine(obs(lineA, 300, 900, 700, 940)), accuracy: 1e-9)
      assertEquals(42.5, LineHeight.perLine(obs("We need to leave right now before they find us here", 300, 860, 700, 945)),
                   accuracy: 1e-9)
      assertEquals(100.0, LineHeight.perLine(obs("SALOON", 450, 860, 550, 960)), accuracy: 1e-9, "kısa parça bölünmez")
    }
    TestRun.test("SubtitleOnlyTest.beforeLearningOnlyCertainRules") {
      var filter = SubtitleOnlyFilter()
      // Sol üst görev metni: yatay ortası 0,11 < 0,12 → kenar. Ortadan kaçık (0,3) ama kenarda olmayan yazı ve
      // bandın dışındaki BÜYÜK HARF tabela bant öğrenilmeden atılmaz (şüphede çevir).
      let list = [obs("Find the horse", 20, 100, 200, 130), obs("Objective: reach the camp", 150, 500, 450, 540),
                  obs("SALOON", 450, 300, 550, 340), obs(lineA, 300, 900, 700, 940)]
      let outcome = filter.apply(list, frame: frame, at: 0, track: true)
      assertEquals(["Find the horse=edge"], reasons(outcome))
      assertEquals(["Objective: reach the camp", "SALOON", lineA], texts(outcome.kept))
      assertNull(filter.band)
    }
    TestRun.test("SubtitleOnlyTest.edgeNeighbourOnTheSubtitleRowIsSplitOff") {
      var filter = SubtitleOnlyFilter()
      // Altyazıyla aynı satırda sağ kenardaki gösterge (900–990: ortası 0,945): ayrı yazı (boşluk 200 px > 2,5 × 40).
      let list = [obs(lineA, 300, 900, 700, 940), obs("x12", 900, 905, 990, 935)]
      let outcome = filter.apply(list, frame: frame, at: 0, track: true)
      assertEquals(["x12=edge"], reasons(outcome))
      assertEquals([lineA], texts(outcome.kept))
    }
    TestRun.test("SubtitleOnlyTest.menuBlockIsDroppedAlone") {
      var filter = SubtitleOnlyFilter()
      // Dört satır, satır başları aynı x'te (0,1), satır başına ortanca 1 sözcük: duraklatma menüsü.
      let menu = [obs("Resume", 100, 300, 250, 330), obs("Settings", 100, 350, 260, 380), obs("Load Game", 100, 400, 300, 430),
                  obs("Quit", 100, 450, 180, 480)]
      let outcome = filter.apply(menu + [obs(lineA, 300, 900, 700, 940), obs("noise", 400, 600, 500, 620, conf: 0.2)],
                                 frame: frame, at: 0, track: true)
      // Yalnız menü bloğu atılır; karenin geri kalanı (altyazı, güveni düşük parça) değerlendirilmeye devam eder.
      assertTrue(outcome.pageFound)
      assertEquals([lineA, "noise"], texts(outcome.kept))
      assertEquals(["Resume=menu", "Settings=menu", "Load Game=menu", "Quit=menu"], reasons(outcome))
    }
    TestRun.test("SubtitleOnlyTest.notAMenu") {
      var filter = SubtitleOnlyFilter()
      // Üç satır yetmez; dört ortalı satırın başları farklı x'te (yayılma 0,04 > 0,012); uzun satırlı sola yaslı blok
      // (ortanca 5 sözcük > 4) da menü değildir.
      let three = [obs("Resume", 100, 300, 250, 330), obs("Settings", 100, 350, 260, 380), obs("Quit", 100, 400, 180, 430)]
      assertFalse(filter.apply(three, frame: frame, at: 0, track: true).pageFound)
      let centered = [obs("one two", 300, 300, 700, 330), obs("three four", 320, 350, 680, 380), obs("five six", 280, 400, 720, 430),
                      obs("seven", 310, 450, 690, 480)]
      assertFalse(filter.apply(centered, frame: frame, at: 0, track: true).pageFound)
      let prose = [obs("I told you we would be late again", 100, 300, 700, 330), obs("and now look at what happened here", 100, 350, 700, 380),
                   obs("you never listen to a single word", 100, 400, 700, 430), obs("so do not blame me for this one", 100, 450, 700, 480)]
      assertFalse(filter.apply(prose, frame: frame, at: 0, track: true).pageFound)
      assertFalse(SubtitleOnlyFilter.isMenuBlock(prose, frame: frame))
    }
    TestRun.test("SubtitleOnlyTest.scatteredPageDropsTheWholeFrame") {
      var filter = SubtitleOnlyFilter()
      // 12 parça, 4 blok (satırlar arası boşluk 170 px > 1,5 × 30), 0,1–0,9 genişlik (0,8 ≥ 0,5), 0,1–0,73 yükseklik (≥ 0,3).
      var list: [TextObservation] = []
      for y in [100, 300, 500, 700] {
        for x in [100, 450, 800] { list.append(obs("AMMO", x, y, x + 100, y + 30)) }
      }
      // Bant yok: ortalı konuşma/cümle olmayan bloklar ("AMMO AMMO AMMO" cümle değil) atılır.
      let outcome = filter.apply(list, frame: frame, at: 0, track: true)
      assertTrue(outcome.pageFound)
      assertEquals(12, outcome.drops.count)
      assertEquals("scattered", outcome.drops[0].reason.code)
      // 9 parça (bir satır eksik): sınırın altında.
      var fewer = SubtitleOnlyFilter()
      assertFalse(fewer.apply(Array(list.prefix(9)), frame: frame, at: 0, track: true).pageFound)
    }
    TestRun.test("SubtitleOnlyTest.unchangingTextIsDroppedAfterNineSeconds") {
      var filter = SubtitleOnlyFilter()
      let hud = obs("Reach the old mill", 400, 100, 600, 130)
      var t: Int64 = 0
      while t <= 8000 {
        assertEquals(1, filter.apply([hud], frame: frame, at: t, track: true).kept.count, "t=\(t)")
        t += 1000
      }
      // 9000 - 0 ≥ STATIC_MS: hiç gösterilmemiş sabit yazı atılır.
      assertEquals(["Reach the old mill=static"], reasons(filter.apply([hud], frame: frame, at: 9000, track: true)))
      // Kalkıp (11 sn) yeniden belirdi: sonraki görünümünde hemen atılır.
      assertEquals(["Reach the old mill=static"], reasons(filter.apply([hud], frame: frame, at: 20000, track: true)))
      // Metin değişti: yeniden değerlendirilir.
      let changed = obs("Talk to the sheriff", 400, 100, 600, 130)
      assertEquals(1, filter.apply([changed], frame: frame, at: 21000, track: true).kept.count)
      // Aynı metin başka yerde (0,3 aşağıda): yeni yazı.
      assertEquals(1, filter.apply([obs("Reach the old mill", 400, 400, 600, 430)], frame: frame, at: 22000, track: true).kept.count)
    }
    TestRun.test("SubtitleOnlyTest.shownLongSubtitleIsNotCutShort") {
      var filter = SubtitleOnlyFilter()
      let line = obs(lineA, 300, 900, 700, 940)
      _ = filter.apply([line], frame: frame, at: 0, track: true)
      filter.rememberRead(lines: [lineA], selected: [line], frame: frame, at: 0)
      _ = filter.noteShown(lineA, at: 500)
      // 12 sn ekranda kalan gerçek altyazı (bir kez çevrildi): görünüm sürdükçe atılmaz.
      var t: Int64 = 1000
      while t <= 12000 {
        assertEquals(1, filter.apply([line], frame: frame, at: t, track: true).kept.count, "t=\(t)")
        t += 1000
      }
      // Kalktı ve aynı metin aynı yerde yeniden belirdi (tuşla ilerleyen diyalog, ölüm sonrası yinelenen satır): gösterilmiş
      // altyazı sabit yazı hafızasına hiç girmediği için yine çevrilir.
      assertEquals(1, filter.apply([line], frame: frame, at: 30000, track: true).kept.count)
    }
    TestRun.test("SubtitleOnlyTest.reusedFramesKeepTheClockRunning") {
      var filter = SubtitleOnlyFilter()
      let hud = obs("Reach the old mill", 400, 100, 600, 130)
      _ = filter.apply([hud], frame: frame, at: 0, track: true)
      // Kare değişmediği için okunmadı (yeniden kullanıldı): yazı hâlâ ekranda sayılır, 5 sn'lik boşluk yeni görünüm olmaz.
      filter.touch(at: 4000)
      filter.touch(at: 8000)
      assertEquals(["Reach the old mill=static"], reasons(filter.apply([hud], frame: frame, at: 9500, track: true)))
      // touch olmadan 5 sn boşluk (> 4 sn) yeni görünümdür: 9 sn dolmaz.
      var other = SubtitleOnlyFilter()
      _ = other.apply([hud], frame: frame, at: 0, track: true)
      _ = other.apply([hud], frame: frame, at: 5000, track: true)
      assertEquals(1, other.apply([hud], frame: frame, at: 9500, track: true).kept.count)
    }
    TestRun.test("SubtitleOnlyTest.retryReadDoesNotCountTowardsStatic") {
      var filter = SubtitleOnlyFilter()
      let hud = obs("Reach the old mill", 400, 100, 600, 130)
      _ = filter.apply([hud], frame: frame, at: 0, track: false)
      // İz açılmadı: 9 sn sonra ilk izli okuma yeni yazıdır.
      assertEquals(1, filter.apply([hud], frame: frame, at: 9000, track: true).kept.count)
    }
    TestRun.test("SubtitleOnlyTest.bandIsLearnedFromShownSubtitles") {
      var filter = SubtitleOnlyFilter()
      assertEquals(SubtitleOnlyShown.Learning.sample, showLine(&filter, obs(lineA, 300, 900, 700, 940), at: 0).learning)
      // Aynı satırın yeniden gösterilmesi (düzeltilmiş okuma) yeni örnek değildir.
      assertEquals(SubtitleOnlyShown.Learning.sample, showLine(&filter, obs(lineA, 300, 900, 700, 940), at: 500).learning)
      assertEquals(SubtitleOnlyShown.Learning.sample, showLine(&filter, obs(lineB, 300, 900, 700, 940), at: 1000).learning)
      assertNull(filter.band, "iki farklı altyazı yetmez")
      let third = showLine(&filter, obs(lineC, 300, 900, 700, 940), at: 2000)
      assertEquals(SubtitleOnlyShown.Learning.learned, third.learning)
      assertTrue(third.bandChanged)
      guard let band = filter.band else { return TestRun.fail("bant öğrenilmedi", #fileID, #line) }
      // Örnekler 0,90–0,94, tipik satır 0,04, bir satır pay: 0,86–0,98; hepsi ortalı.
      assertEquals(0.86, band.top, accuracy: 1e-9)
      assertEquals(0.98, band.bottom, accuracy: 1e-9)
      assertEquals(0.04, band.lineHeight, accuracy: 1e-9)
      assertEquals(SubtitleBand.Layout.centered, band.layout)
      assertEquals(3, band.samples)
      // Okuması olmayan gösterim (demo) öğrenmeye katılmaz.
      var demo = SubtitleOnlyFilter()
      assertEquals(SubtitleOnlyShown.Learning.unmatched, demo.noteShown("Nothing was read here", at: 0).learning)
    }
    TestRun.test("SubtitleOnlyTest.afterLearningOffCenterAndHeightMismatch") {
      var filter = learnedBottom()
      let list = [obs("Objective: reach the camp", 150, 860, 450, 900),  // bantta, ortası 0,3: hizasız
                  obs(lineA, 300, 900, 700, 940),
                  obs("SALOON", 450, 860, 550, 960),                      // 100 px: tipikin 2,5 katı
                  obs("12", 490, 945, 510, 955)]                          // 10 px: 0,25 katı
      let outcome = filter.apply(list, frame: frame, at: 5000, track: true)
      // "12" bantta: alt sınır bantta uygulanmaz; altyazının ortasında olduğu için çekirdeğe katılır.
      assertEquals(["SALOON=line-height", "Objective: reach the camp=off-center"], reasons(outcome))
      assertEquals([lineA, "12"], texts(outcome.kept))
    }
    TestRun.test("SubtitleOnlyTest.inBandSentenceKeepsDespiteHeight") {
      var filter = learnedBottom()
      // 80 px (2 kat) ama bantta ve cümle gibi: şüphede çevir.
      let tall = obs("Get on the horse and ride now", 300, 880, 700, 960)
      assertEquals(1, filter.apply([tall], frame: frame, at: 5000, track: true).kept.count)
    }
    TestRun.test("SubtitleOnlyTest.worldSignsOutsideTheBand") {
      var filter = learnedBottom()
      // Ayrı bloklar (aralar 110 px > 1,5 × 40); hepsi bandın (0,86–0,98) dışında, yüksekliği tipik (40 px).
      let list = [obs("SALOON", 450, 200, 550, 240),                       // tek sözcük BÜYÜK HARF
                  obs("Saloon", 450, 350, 550, 390, conf: 0.4),           // güvensiz
                  obs("Gun shop", 450, 500, 550, 540, angle: 12),         // eğik
                  obs("Gun shop", 450, 650, 550, 690, angle: 2)]          // düz: tabela değil ama bant dışı ve cümle değil
      let outcome = filter.apply(list, frame: frame, at: 5000, track: true)
      assertEquals(["SALOON=world-sign", "Saloon=world-sign", "Gun shop=world-sign", "Gun shop=outside-band"], reasons(outcome))
      // Aynı tabela bantta: tabela kuralı yok (yüksekliği tutuyor, ortalı).
      assertEquals(1, filter.apply([obs("SALOON", 450, 900, 550, 940)], frame: frame, at: 6000, track: true).kept.count)
    }
    TestRun.test("SubtitleOnlyTest.positiveEvidenceOutsideTheBand") {
      var filter = learnedBottom()
      // Bandın dışında ama ortalı konuşma (etiket) ya da cümle: kabul. Ortalı değilse, ya da cümle/etiket yoksa: atılır.
      assertEquals(1, filter.apply([obs("ENZO: Get down now!", 300, 300, 700, 340)], frame: frame, at: 5000, track: true).kept.count)
      assertEquals(1, filter.apply([obs("They are coming for us", 300, 400, 700, 440)], frame: frame, at: 5100, track: true).kept.count)
      assertEquals(["ENZO: Get down now!=outside-band"],
                   reasons(filter.apply([obs("ENZO: Get down now!", 50, 500, 450, 540)], frame: frame, at: 5200, track: true)))
      assertEquals(["Valentine 3=outside-band"],
                   reasons(filter.apply([obs("Valentine 3", 400, 600, 600, 640)], frame: frame, at: 5300, track: true)))
    }
    TestRun.test("SubtitleOnlyTest.leftAlignedGameIsLearned") {
      var filter = SubtitleOnlyFilter()
      // Sola yaslı altyazı (sol kenar 0,05, ortalar 0,25 / 0,35 / 0,2): sola yaslı bant.
      showLine(&filter, obs(lineA, 50, 900, 450, 940), at: 0)
      showLine(&filter, obs("Where is the money hidden, tell me now", 50, 900, 650, 940), at: 1000)
      showLine(&filter, obs("Get on the horse", 50, 900, 350, 940), at: 2000)
      guard let band = filter.band else { return TestRun.fail("bant öğrenilmedi", #fileID, #line) }
      assertEquals(SubtitleBand.Layout.left, band.layout)
      assertEquals(0.05, band.leftEdge, accuracy: 1e-9)
      // Kısa satır (ortası 0,07: kenar) sol kenara hizalı olduğu için kalır; sağdaki ipucu hizasız.
      let outcome = filter.apply([obs("No.", 50, 900, 90, 940), obs("Hold to skip", 700, 860, 950, 895)], frame: frame, at: 5000,
                                 track: true)
      assertEquals(["No."], texts(outcome.kept))
      assertEquals(["Hold to skip=off-center"], reasons(outcome))
    }
    TestRun.test("SubtitleOnlyTest.bandShiftIsRelearned") {
      var filter = learnedBottom()
      // Üstte (0,10–0,14) ortalı cümleler: bandın dışında, olumlu kanıtla gösterildi. Üçüncüsünde bant taşınır.
      assertEquals(SubtitleOnlyShown.Learning.outside, showLine(&filter, obs("They are coming for us", 300, 100, 700, 140), at: 3000).learning)
      assertEquals(SubtitleOnlyShown.Learning.outside, showLine(&filter, obs("Get to the boat right now", 300, 100, 700, 140), at: 4000).learning)
      assertEquals(SubtitleOnlyShown.Learning.relearned, showLine(&filter, obs("I will hold them off here", 300, 100, 700, 140), at: 5000).learning)
      guard let band = filter.band else { return TestRun.fail("bant yok", #fileID, #line) }
      assertEquals(0.06, band.top, accuracy: 1e-9)
      assertEquals(0.18, band.bottom, accuracy: 1e-9)
      // Araya bant içi altyazı girerse kanıt sıfırlanır.
      var other = learnedBottom()
      showLine(&other, obs("They are coming for us", 300, 100, 700, 140), at: 3000)
      showLine(&other, obs("Get to the boat right now", 300, 100, 700, 140), at: 4000)
      showLine(&other, obs("Stay down and keep quiet", 300, 900, 700, 940), at: 5000)
      assertEquals(SubtitleOnlyShown.Learning.outside, showLine(&other, obs("I will hold them off here", 300, 100, 700, 140), at: 6000).learning)
      assertEquals(0.86, other.band?.top ?? 0, accuracy: 1e-9)
    }
    TestRun.test("SubtitleOnlyTest.longQuietThenShiftNeedsFewerSamples") {
      var filter = learnedBottom()
      // Son örnek 2000 ms'de; 2 dk'dan uzun sessizlik (oyun değişmiş olabilir): iki örnek yeter.
      assertEquals(SubtitleOnlyShown.Learning.outside, showLine(&filter, obs("They are coming for us", 300, 100, 700, 140), at: 200_000).learning)
      assertEquals(SubtitleOnlyShown.Learning.relearned, showLine(&filter, obs("Get to the boat right now", 300, 100, 700, 140), at: 201_000).learning)
      assertEquals(2, filter.band?.samples ?? 0)
    }
    TestRun.test("SubtitleOnlyTest.resetForgetsEverything") {
      var filter = learnedBottom()
      let hud = obs("Reach the old mill", 400, 100, 600, 130)
      for t in [10000, 13000, 16000] as [Int64] { _ = filter.apply([hud], frame: frame, at: t, track: true) }
      assertEquals(["Reach the old mill=static"], reasons(filter.apply([hud], frame: frame, at: 19000, track: true)))
      assertNotNull(filter.band)
      filter.reset()
      assertNull(filter.band)
      // Bant ve sabit yazı izleri gitti: bant dışı yazı ve aynı gösterge yeniden adaydır.
      assertEquals(1, filter.apply([hud], frame: frame, at: 20000, track: true).kept.count)
    }
    TestRun.test("SubtitleOnlyTest.nothingToDropKeepsTheSelection") {
      var filter = SubtitleOnlyFilter()
      // Sıradan altyazı + güveni düşük gürültü: girdi olduğu gibi döner, seçim aynı (ayar kapalıykenki sonuç).
      let list = [obs(lineA, 300, 900, 700, 940), obs("with that thing?", 350, 945, 650, 985), obs("~", 480, 600, 500, 620, conf: 0.2)]
      let outcome = filter.apply(list, frame: frame, at: 0, track: true)
      assertEquals(list, outcome.kept)
      assertEquals(ReadingSelector.select(list, width: 1000, height: 1000), ReadingSelector.select(outcome.kept, width: 1000, height: 1000))
    }
    // MARK: İnceleme bulguları (Y1, Y2, O1–O5)

    TestRun.test("SubtitleOnlyTest.menuItemsDoNotTeachTheBand") {
      // Y1c: akış oyun menüsünde başladı; çevrilen menü öğeleri konuşma/cümle değil, bant öğretmez.
      var filter = SubtitleOnlyFilter()
      var t: Int64 = 0
      for item in ["Continue", "Load Game", "Settings", "Quit Game"] {
        assertEquals(SubtitleOnlyShown.Learning.notSpeech, showLine(&filter, obs(item, 400, 500, 600, 530), at: t).learning, item)
        t += 1000
      }
      assertNull(filter.band)
    }
    TestRun.test("SubtitleOnlyTest.wrongBandStillLetsSpeechThrough") {
      // Y1a: bant yükleme ipuçlarından öğrenildi (ortalı, 0,48–0,51, satır 30 px → bant 0,45–0,54, tipik 0,03). Oyunun
      // altyazısı bandın dışında (0,88–0,94) ve iki kat boyda (60 px): cümle biçimli olduğu için yükseklikten atılmaz,
      // bant dışında ama ortalı cümle olduğu için kabul edilir.
      var filter = tipsBand()
      guard let band = filter.band else { return TestRun.fail("bant öğrenilmedi", #fileID, #line) }
      assertEquals(0.45, band.top, accuracy: 1e-9)
      assertEquals(0.54, band.bottom, accuracy: 1e-9)
      assertEquals(0.03, band.lineHeight, accuracy: 1e-9)
      let outcome = filter.apply([obs(lineA, 300, 880, 700, 940)], frame: frame, at: 10000, track: true)
      assertEquals([lineA], texts(outcome.kept))
      assertEquals([], reasons(outcome))
    }
    TestRun.test("SubtitleOnlyTest.safetyValveDropsAWrongBand") {
      // Y1b/N2: aynı yanlış bant; oyunun altyazıları sola yaslı (0,05–0,45; ortası 0,25) ve bant dışında: cümle oldukları
      // halde atılır. Okumalar 2 sn arayla (≤ 4 sn: şüphe kesintisiz), her okumada başka satır. Şüphe 10000'de başlar;
      // 28000'de 18 sn, 30000'de 20 sn: bant unutulur, o kare kesin kurallarla geçer.
      var filter = tipsBand()
      for i in 0..<10 {
        let t: Int64 = 10000 + Int64(i) * 2000
        let outcome = filter.apply([obs(talk[i], 50, 880, 450, 940)], frame: frame, at: t, track: true)
        assertEquals(["\(talk[i])=outside-band"], reasons(outcome), "t=\(t)")
        assertFalse(outcome.bandDropped, "t=\(t)")
      }
      let after = filter.apply([obs(talk[10], 50, 880, 450, 940)], frame: frame, at: 30000, track: true)
      assertTrue(after.bandDropped)
      assertNull(filter.band)
      assertEquals([talk[10]], texts(after.kept))
      // Arada bir satır gösterildiyse bant işini görüyor: sayaç gösterimde sıfırlanır, 26000'deki şüpheli atmayla yeniden
      // başlar; 44000'de 18 sn, 46000'de 20 sn.
      var shown = tipsBand()
      for i in 0..<8 { _ = shown.apply([obs(talk[i], 50, 880, 450, 940)], frame: frame, at: 10000 + Int64(i) * 2000, track: true) }
      _ = shown.noteShown("Somebody else said something here", at: 25000)
      var t: Int64 = 26000
      var index = 8
      while t <= 44000 {
        assertFalse(shown.apply([obs(talk[index % talk.count], 50, 880, 450, 940)], frame: frame, at: t, track: true).bandDropped,
                    "t=\(t)")
        assertNotNull(shown.band)
        t += 2000
        index += 1
      }
      assertTrue(shown.apply([obs(talk[index % talk.count], 50, 880, 450, 940)], frame: frame, at: 46000, track: true).bandDropped)
    }
    TestRun.test("SubtitleOnlyTest.singleSuspectFrameDoesNotDropTheBand") {
      // N2: tek karede atılan cümle biçimli yazı (10000), ardından yazısız okumalar ya da hiç okuma yok: şüphe 4 sn'de
      // biter; 25 sn sessizlikten sonra da bant durur.
      var filter = tipsBand()
      _ = filter.apply([obs(lineA, 50, 880, 450, 940)], frame: frame, at: 10000, track: true)
      var t: Int64 = 13000
      while t <= 34000 {
        assertFalse(filter.apply([], frame: frame, at: t, track: true).bandDropped, "t=\(t)")
        t += 3000
      }
      assertNotNull(filter.band)
      var silent = tipsBand()
      _ = silent.apply([obs(lineA, 50, 880, 450, 940)], frame: frame, at: 10000, track: true)
      let later = silent.apply([obs(lineB, 50, 880, 450, 940)], frame: frame, at: 35000, track: true)
      assertFalse(later.bandDropped, "25 sn sonra: son şüpheli atma 4 sn'den eski")
      assertNotNull(silent.band)
    }
    TestRun.test("SubtitleOnlyTest.staticCountRestartsWhenTheBandIsDropped") {
      // N3: yanlış bant; uzun bir altyazı satırı (lineA, 0,88–0,94) 10000'den beri bant kuralıyla atılıyor, 20000'de
      // 10 sn'yi aşınca sabit yazı olur (gösterilmedi). Altındaki/üstündeki değişen satırlar (0,70–0,76) şüpheyi kesintisiz
      // sürdürür. 30000'de supap açılır: sabit yazı sayımı sıfırdan başlar, lineA da çevrilir.
      var filter = tipsBand()
      let long = obs(lineA, 50, 880, 450, 940)
      for i in 0..<10 {
        let t: Int64 = 10000 + Int64(i) * 2000
        let outcome = filter.apply([long, obs(talk[i + 1], 50, 700, 450, 760)], frame: frame, at: t, track: true)
        let expected: String = t >= 20000 ? "\(lineA)=static" : "\(lineA)=outside-band"
        assertTrue(reasons(outcome).contains(expected), "t=\(t) \(reasons(outcome))")
      }
      let after = filter.apply([long, obs(talk[11], 50, 700, 450, 760)], frame: frame, at: 30000, track: true)
      assertTrue(after.bandDropped)
      assertEquals([lineA, talk[11]], texts(after.kept))
    }
    TestRun.test("SubtitleOnlyTest.dashPairOnOneRowIsOneUnit") {
      // DÜŞÜK: "- Yes." (0,30–0,38) ve "- No." (0,62–0,70) aynı satırda 240 px boşlukla (> 2,5 × 40): birleşik kapsam
      // 0,30–0,70 ortalı, ikisi de tireli → tek yazı, ortalı bantta ikisi de kalır.
      var filter = learnedBottom()
      let outcome = filter.apply([obs("- Yes.", 300, 900, 380, 940), obs("- No.", 620, 900, 700, 940)], frame: frame, at: 5000,
                                 track: true)
      assertEquals(["- Yes.", "- No."], texts(outcome.kept))
    }
    TestRun.test("SubtitleOnlyTest.labelWithoutWordsIsNotSpeech") {
      // DÜŞÜK: "Cash: $500" etiket gibi ama gövdesinde harf yok: gösterge. Bant dışında ortalı olsa da atılır.
      assertFalse(SubtitleOnlyFilter.isSpeech("Cash: $500"))
      assertFalse(SubtitleOnlyFilter.isSpeech("HP: 100/100"))
      assertTrue(SubtitleOnlyFilter.isSpeech("Lucia: Yes."))
      assertTrue(SubtitleOnlyFilter.isSpeech("ENZO: Get down now!"))
      var filter = learnedBottom()
      assertEquals(["Cash: $500=outside-band"], reasons(filter.apply([obs("Cash: $500", 400, 300, 600, 340)], frame: frame, at: 5000,
                                                                        track: true)))
    }
    TestRun.test("SubtitleOnlyTest.leftAlignedLinesOfACenteredBlockStay") {
      // Y2: ortalı bant; blok ekranda ortalı (0,3–0,7) ama satırları sola yaslı, ikinci satır kısa (0,3–0,42; ortası
      // 0,36: tek başına ortadan 0,14 uzak). Sol kenarı birinci satırınkiyle aynı: aynı blok, iki satır da kalır.
      var filter = learnedBottom()
      let list = [obs(lineA, 300, 900, 700, 940), obs("with you.", 300, 945, 420, 985)]
      let outcome = filter.apply(list, frame: frame, at: 5000, track: true)
      assertEquals([lineA, "with you."], texts(outcome.kept))
      assertEquals([], reasons(outcome))
    }
    TestRun.test("SubtitleOnlyTest.shortWrapLinesAndLabelsStay") {
      // O1: bantta tipik yüksekliğin yarısı ölçülen kısa sarma satırı ("me.", "with": 20 px / 40 px = 0,5 < 0,6) ve
      // etiketli kısa satır ("Lucia: Yes.") kalır; bant dışında iki kat boyda etiketli satır da (ortalı) kalır.
      var filter = learnedBottom()
      let me = filter.apply([obs(lineB, 300, 900, 700, 940), obs("me.", 485, 945, 515, 965)], frame: frame, at: 5000, track: true)
      assertEquals([lineB, "me."], texts(me.kept))
      let wrap = filter.apply([obs(lineC, 300, 900, 700, 940), obs("with", 470, 945, 530, 965)], frame: frame, at: 6000, track: true)
      assertEquals([lineC, "with"], texts(wrap.kept))
      assertEquals(1, filter.apply([obs("Lucia: Yes.", 400, 900, 600, 920)], frame: frame, at: 7000, track: true).kept.count)
      assertEquals(1, filter.apply([obs("Lucia: Yes.", 400, 300, 600, 380)], frame: frame, at: 8000, track: true).kept.count)
    }
    TestRun.test("SubtitleOnlyTest.crowdedHudDoesNotVetoTheSubtitle") {
      // O3: 12 "AMMO" parçası 4 satırda (0,1–0,58) + bantta altyazı: dağınık sayfa, ama yalnız bant dışı bloklar atılır.
      var hud: [TextObservation] = []
      for y in [100, 250, 400, 550] {
        for x in [100, 450, 800] { hud.append(obs("AMMO", x, y, x + 100, y + 30)) }
      }
      var filter = learnedBottom()
      let outcome = filter.apply(hud + [obs(lineA, 300, 900, 700, 940)], frame: frame, at: 5000, track: true)
      assertTrue(outcome.pageFound)
      assertEquals([lineA], texts(outcome.kept))
      assertEquals(12, outcome.drops.filter { $0.reason == SubtitleOnlyReason.scattered }.count)
      // Bant yokken: ortalı cümle biçimli blok korunur, gerisi atılır.
      var fresh = SubtitleOnlyFilter()
      let early = fresh.apply(hud + [obs(lineA, 300, 900, 700, 940)], frame: frame, at: 0, track: true)
      assertEquals([lineA], texts(early.kept))
    }
    TestRun.test("SubtitleOnlyTest.dialogueChoicesDropOnlyTheList") {
      // O4: 4 seçenekli liste (sol kenar 0,1, satır başına ortanca 1 sözcük) + ortalı NPC altyazısı: liste atılır, altyazı kalır.
      let choices = [obs("1. Yes", 100, 300, 200, 330), obs("2. No", 100, 340, 190, 370), obs("3. Tell me more", 100, 380, 330, 410),
                     obs("4. Leave", 100, 420, 220, 450)]
      var filter = SubtitleOnlyFilter()
      let apart = filter.apply(choices + [obs(lineA, 300, 900, 700, 940)], frame: frame, at: 0, track: true)
      assertEquals([lineA], texts(apart.kept))
      assertEquals(4, apart.drops.filter { $0.reason == SubtitleOnlyReason.menu }.count)
      // Liste altyazının hemen üstünde (aynı dikey blok): yalnız liste satırları atılır.
      let near = [obs("1. Yes", 100, 700, 200, 730), obs("2. No", 100, 740, 190, 770), obs("3. Tell me more", 100, 780, 330, 810),
                  obs("4. Leave", 100, 820, 220, 850), obs(lineA, 300, 860, 700, 900)]
      var other = SubtitleOnlyFilter()
      let together = other.apply(near, frame: frame, at: 0, track: true)
      assertEquals([lineA], texts(together.kept))
      assertEquals(["1. Yes=menu", "2. No=menu", "3. Tell me more=menu", "4. Leave=menu"], reasons(together))
    }
    TestRun.test("SubtitleOnlyTest.shortLineAtTheNewSubtitlePlace") {
      // O5: altyazı yeri değişti (üstte, 0,10–0,14); bir bant dışı cümle gösterildi. Aynı yükseklikteki ortalı kısa satır
      // ("Yes.", cümle değil) yeniden öğrenilirken de kabul edilir; böyle bir kanıt yokken atılır.
      var filter = learnedBottom()
      showLine(&filter, obs("They are coming for us", 300, 100, 700, 140), at: 3000)
      assertEquals(["Yes."], texts(filter.apply([obs("Yes.", 450, 100, 550, 140)], frame: frame, at: 4000, track: true).kept))
      var plain = learnedBottom()
      assertEquals(["Yes.=outside-band"], reasons(plain.apply([obs("Yes.", 450, 100, 550, 140)], frame: frame, at: 4000, track: true)))
    }
    TestRun.test("SubtitleOnlyTest.extraAreaIsNotFiltered") {
      // Ek okuma alanı (kullanıcının bilerek seçtiği alan) süzgece girmez: VisionReader.extraLines süzgeci çağırmaz.
      guard let dir = ProcessInfo.processInfo.environment["GT_RUNNER_DIR"] else {
        return TestRun.fail("GT_RUNNER_DIR ayarlı değil (run.sh ayarlar)", #fileID, #line)
      }
      let source = (try? String(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent("VisionReader.swift"), encoding: .utf8)) ?? ""
      guard let start = source.range(of: "private func extraLines("),
            let end = source.range(of: "// MARK: - Okuma", range: start.upperBound..<source.endIndex) else {
        return TestRun.fail("VisionReader.extraLines bulunamadı", #fileID, #line)
      }
      let body = String(source[start.upperBound..<end.lowerBound])
      assertFalse(body.contains("onlyFilter"), "ek alan süzülmemeli")
      assertTrue(source.contains("if subtitleOnly {"), "asıl okuma ayara bağlı süzülür")
    }
  }
}

enum CoverKeeperTest {
  static let b = TextBox(left: 0.3, top: 0.85, right: 0.7, bottom: 0.95)
  static let far = TextBox(left: 0.3, top: 0.70, right: 0.7, bottom: 0.80)

  static func request(_ text: String, _ box: TextBox, line: Double?, ratio: Double? = nil, rows: [TextBox]? = nil,
                      replaces: Bool = false, match: Bool = true) -> CoverRequest {
    CoverRequest(text: text, box: box, line: line, matchGameTextSize: match, widenRatio: ratio, rows: rows, replaces: replaces)
  }

  static func codes(_ p: CoverPlacement) -> [String] { p.notes.map(\.code) }

  static func assertBox(_ expected: TextBox, _ actual: TextBox, file: String = #fileID, line: Int = #line) {
    let edges: [Double] = [expected.left - actual.left, expected.top - actual.top, expected.right - actual.right,
                           expected.bottom - actual.bottom]
    if edges.contains(where: { (d: Double) -> Bool in abs(d) > 1e-9 }) {
      TestRun.fail("beklenen <\(expected)>, gelen <\(actual)>", file, line)
    }
  }

  static func run() {
    TestRun.test("CoverKeeperTest.firstLineIsUnchanged") {
      var keeper = CoverKeeper()
      let placed = keeper.place(request("Hadi gidelim", b, line: 0.04, ratio: 1.5), at: 0)
      assertEquals(b, placed.box)
      // 1.8.5'teki genişletme: 0,4 × 1,5 × 1,08 = 0,648 → 0,176–0,824.
      assertEquals(0.176, placed.source.left, accuracy: 1e-9)
      assertEquals(0.824, placed.source.right, accuracy: 1e-9)
      assertEquals(CoverKeeper.widened(b, ratio: 1.5), placed.source)
      assertEquals(0.04, placed.line ?? 0, accuracy: 1e-12)
      assertEquals([], codes(placed))
      // TV çerçevesi ham değerlerle kurulanla bayt bayt aynı.
      let raw = SubtitleWire.subtitleFrame("Hadi gidelim", durationMs: 15000, box: b, replaces: false, at: 1,
                                           source: CoverKeeper.widened(b, ratio: 1.5), line: 0.04, rows: nil)
      let kept = SubtitleWire.subtitleFrame("Hadi gidelim", durationMs: 15000, box: placed.box, replaces: false, at: 1,
                                            source: placed.source, line: placed.line, rows: placed.rows)
      assertEquals(raw, kept)
    }
    TestRun.test("CoverKeeperTest.lineGrowsAtMostAQuarterPerLine") {
      var keeper = CoverKeeper()
      _ = keeper.place(request("bir", b, line: 0.03), at: 0)
      // 0,05 istendi: 0,03 × 1,25 = 0,0375; sonra 0,0375 × 1,25 = 0,046875; sonra 0,05 (sınırın altında).
      let second = keeper.place(request("iki", far, line: 0.05), at: 5000)
      assertEquals(0.0375, second.line ?? 0, accuracy: 1e-12)
      assertEquals(["line-limited"], codes(second))
      assertEquals(0.046875, keeper.place(request("üç", b, line: 0.05), at: 10000).line ?? 0, accuracy: 1e-12)
      assertEquals(0.05, keeper.place(request("dört", far, line: 0.05), at: 15000).line ?? 0, accuracy: 1e-12)
      // Küçülme serbest.
      assertEquals(0.03, keeper.place(request("beş", b, line: 0.03), at: 20000).line ?? 0, accuracy: 1e-12)
    }
    TestRun.test("CoverKeeperTest.lineCap") {
      var keeper = CoverKeeper()
      // Tipik bilinmiyor: 1.8.5'teki sınır (0,08); 0,075 olduğu gibi gider, 0,09 (olağan ölçümde gelmez) 0,08'e iner.
      assertEquals(0.075, keeper.place(request("bir", b, line: 0.075), at: 0).line ?? 0, accuracy: 1e-12)
      var high = CoverKeeper()
      let capped = high.place(request("bir", b, line: 0.09), at: 0)
      assertEquals(0.08, capped.line ?? 0, accuracy: 1e-12, "tipik bilinmiyor: %8")
      assertEquals(["line-capped"], codes(capped))
      var typical = CoverKeeper()
      typical.typicalLine = 0.03
      assertEquals(0.045, typical.place(request("bir", b, line: 0.05), at: 0).line ?? 0, accuracy: 1e-12, "1,5 × 0,03")
      assertEquals(0.08, LineHeight.sendCap(typical: 0.07), accuracy: 1e-12, "en çok MAX_RATIO")
      assertEquals(0.08, LineHeight.sendCap(typical: nil), accuracy: 1e-12)
    }
    TestRun.test("CoverKeeperTest.revisionIsPinned") {
      var keeper = CoverKeeper()
      _ = keeper.place(request("Hadi", b, line: 0.04), at: 0)
      // Düzeltilmiş okuma, kutu 0,005 oynadı: kutu ve satır yüksekliği aynı kalır.
      let jitter = TextBox(left: 0.305, top: 0.852, right: 0.698, bottom: 0.948)
      let pinned = keeper.place(request("Hadi gidelim", jitter, line: 0.05, replaces: true), at: 300)
      assertEquals(b, pinned.box)
      assertEquals(b, pinned.source)
      assertEquals(0.04, pinned.line ?? 0, accuracy: 1e-12)
      assertEquals(["pinned", "line-pinned"], codes(pinned))
      // Okuma kutunun dışına taştı (0,25–0,75): kutu birleşimle büyür, küçülmez; satır yüksekliği yine sabit.
      let wider = TextBox(left: 0.25, top: 0.85, right: 0.75, bottom: 0.95)
      let grown = keeper.place(request("Hadi gidelim artık", wider, line: 0.05, replaces: true), at: 600)
      assertEquals(wider, grown.box)
      assertEquals(["grown", "line-pinned"], codes(grown))
      // Sonraki düzeltme yine dar okundu: büyümüş kutu korunur.
      assertEquals(wider, keeper.place(request("Hadi gidelim artık!", b, line: 0.04, replaces: true), at: 900).box)
      // Başka yere geçti (dikey örtüşme yok): yeni kutu.
      let moved = keeper.place(request("Hadi gidelim artık!!", far, line: 0.04, replaces: true), at: 1200)
      assertEquals(far, moved.box)
      assertEquals(["moved"], codes(moved))
    }
    TestRun.test("CoverKeeperTest.repeatAfterAsideIsIdentical") {
      var keeper = CoverKeeper()
      let first = keeper.place(request("Hadi gidelim", b, line: 0.04, ratio: 1.5), at: 0)
      // Ek alan gösteriminden dönüş: aynı okuma kutusu ve metin; okuma belleğinden düştüğü için line ve oran yok.
      // 1.8.5'te line gitmiyor (TV ayardaki boya büyüyordu) ve alan daralıyordu.
      let again = keeper.place(request("Hadi gidelim", b, line: nil, ratio: nil), at: 8000)
      assertEquals(first.box, again.box)
      assertEquals(first.source, again.source)
      assertEquals(0.04, again.line ?? 0, accuracy: 1e-12)
      assertEquals(["repeated"], codes(again))
    }
    TestRun.test("CoverKeeperTest.missingMeasurementKeepsTheLastLine") {
      var keeper = CoverKeeper()
      _ = keeper.place(request("bir", b, line: 0.04), at: 0)
      let next = keeper.place(request("iki", far, line: nil), at: 5000)
      assertEquals(0.04, next.line ?? 0, accuracy: 1e-12)
      assertEquals(["line-kept"], codes(next))
      // "Oyunun yazı boyuna uy" kapalı: line hiç gitmez.
      var off = CoverKeeper()
      _ = off.place(request("bir", b, line: nil, match: false), at: 0)
      assertNull(off.place(request("iki", far, line: nil, match: false), at: 1000).line)
    }
    TestRun.test("CoverKeeperTest.steadyBoxForTheNextLine") {
      var keeper = CoverKeeper()
      _ = keeper.place(request("bir", b, line: 0.04), at: 0)
      let near = TextBox(left: 0.31, top: 0.851, right: 0.69, bottom: 0.949)
      let steady = keeper.place(request("iki", near, line: 0.04), at: 3000)
      assertEquals(b, steady.box)
      assertEquals(["steady"], codes(steady))
      // Son gösterimden 5 sn sonra (8000 - 3000 > 4000) başka bir okuma kutusu: yeni kutu.
      let later = TextBox(left: 0.312, top: 0.852, right: 0.688, bottom: 0.948)
      assertEquals(later, keeper.place(request("üç", later, line: 0.04), at: 8000).box)
    }
    TestRun.test("CoverKeeperTest.tallBoxIsClipped") {
      var keeper = CoverKeeper()
      let tall = TextBox(left: 0.3, top: 0.6, right: 0.7, bottom: 0.95)
      let rows = [TextBox(left: 0.3, top: 0.6, right: 0.7, bottom: 0.65), TextBox(left: 0.3, top: 0.9, right: 0.7, bottom: 0.95)]
      let clipped = keeper.place(request("bir\niki", tall, line: 0.04, rows: rows), at: 0)
      // 0,35 > 0,20; bant yok: alt kenar korunur → 0,75–0,95. line yine gider (TV ayardaki boya dönmesin); üst satır
      // kutusu (0,60–0,65) kırpılmış kutunun dışında kaldığı için rows gitmez.
      assertBox(TextBox(left: 0.3, top: 0.75, right: 0.7, bottom: 0.95), clipped.box)
      assertBox(TextBox(left: 0.3, top: 0.75, right: 0.7, bottom: 0.95), clipped.source)
      assertEquals(0.04, clipped.line ?? 0, accuracy: 1e-12)
      assertNull(clipped.rows)
      assertEquals(["box-capped"], codes(clipped))
      // Satır kutuları kırpılmış kutunun içindeyse gider (line ile).
      var inside = CoverKeeper()
      let fitting = [TextBox(left: 0.3, top: 0.76, right: 0.7, bottom: 0.8), TextBox(left: 0.3, top: 0.9, right: 0.7, bottom: 0.95)]
      let sent = inside.place(request("bir\niki", tall, line: 0.04, rows: fitting), at: 0).rows ?? []
      assertEquals(2, sent.count)
      assertEquals(0.04, sent.first?.line ?? 0, accuracy: 1e-12)
      // Öğrenilmiş bant 0,80–0,97: bantla kırpılır (0,80–0,95).
      var banded = CoverKeeper()
      banded.bandTop = 0.80
      banded.bandBottom = 0.97
      assertEquals(TextBox(left: 0.3, top: 0.8, right: 0.7, bottom: 0.95), banded.place(request("bir", tall, line: 0.04), at: 0).box)
      // Kutu bandın tamamen dışında: alt kenar korunur.
      var outside = CoverKeeper()
      outside.bandTop = 0.1
      outside.bandBottom = 0.2
      assertBox(TextBox(left: 0.3, top: 0.75, right: 0.7, bottom: 0.95), outside.place(request("bir", tall, line: 0.04), at: 0).box)
    }
    TestRun.test("CoverKeeperTest.rowsCarryTheKeptLine") {
      var keeper = CoverKeeper()
      _ = keeper.place(request("bir", far, line: 0.03), at: 0)
      let rows = [TextBox(left: 0.3, top: 0.85, right: 0.7, bottom: 0.89), TextBox(left: 0.32, top: 0.9, right: 0.68, bottom: 0.94)]
      let placed = keeper.place(request("ENZO: Yat!\nMARIA: Kim?", b, line: 0.05, rows: rows), at: 5000)
      let sent: [SubtitleRow] = placed.rows ?? []
      assertEquals(2, sent.count)
      for (index, row) in sent.enumerated() {
        assertEquals(rows[index], row.box)
        assertEquals(0.0375, row.line ?? 0, accuracy: 1e-12, "satır \(index)")
      }
      // Tek satır kutusu gitmez (1.8.5'teki kural).
      assertNull(keeper.place(request("tek", far, line: 0.03, rows: [rows[0]]), at: 10000).rows)
    }
    TestRun.test("CoverKeeperTest.resetForgetsTheHistory") {
      var keeper = CoverKeeper()
      _ = keeper.place(request("bir", b, line: 0.03), at: 0)
      keeper.reset()
      let fresh = keeper.place(request("iki", far, line: 0.05), at: 1000)
      assertEquals(0.05, fresh.line ?? 0, accuracy: 1e-12)
      assertEquals([], codes(fresh))
    }
  }
}
