// SPDX-License-Identifier: AGPL-3.0-only
// Core/TurkishDetect.swift testleri.
import Foundation

enum TurkishDetectTest {
  static func run() {
    TestRun.test("TurkishDetectTest.turkishLines") {
      for line in ["Tamam, hadi gidelim.", "Bunu daha önce hiç görmemiştim ve çok şaşırdım.", "Nereye gidiyorsun?",
                   "NEREDE ŞİMDİ?", "Hoş geldin", "Lütfen kapıyı aç, çünkü acele etmemiz lazım."] {
        assertTrue(TurkishDetect.isTurkish(line), line)
      }
    }
    TestRun.test("TurkishDetectTest.englishLinesAreNotTurkish") {
      for line in ["Where are you going?", "I know. Let's go.", "Press X to continue", "We need to get out of here before they find us.",
                   "Dr. Müller, please come here.", "I told Müller to meet Çelik tomorrow.",
                   "Ali, Işık and Güneş went home.", "The cafe is closed.", "Ben and Tom are here."] {
        assertFalse(TurkishDetect.isTurkish(line), line)
      }
    }
    TestRun.test("TurkishDetectTest.mixedAndEmpty") {
      assertFalse(TurkishDetect.isTurkish("Hoşgeldin, the boss is waiting for you."))
      assertFalse(TurkishDetect.isTurkish(""))
      // Yalnız Türkçe harfli kısa satırlar (özel adlar) Türkçe sayılmaz.
      for name in ["Çağlar!", "Şahin Aksoy", "Şahin Aksoy Çağlar", "Işık", "Güneş Öztürk"] {
        assertFalse(TurkishDetect.isTurkish(name), name)
      }
      assertFalse(TurkishDetect.isTurkish("... !?"))
      assertFalse(TurkishDetect.isTurkish("12:30"))
    }
    TestRun.test("TurkishDetectTest.consoleWordsAndOneLetterDamage") {
      // Konsol/sistem sözcükleri.
      for line in ["Güncelleme yükleniyor", "Lütfen bekleyin", "Oturum açılıyor, lütfen bekleyin", "Ayarlar kaydediliyor",
                   "İptal", "Devam"] {
        assertTrue(TurkishDetect.isTurkish(line), line)
      }
      // Yazı tanımanın bir harfi bozduğu (değişmiş, düşmüş, eklenmiş) 6+ harfli sözcükler.
      for line in ["Yükleniyar", "Güncellme", "Baglantı", "Bekleyln", "Güncelleeme"] {
        assertTrue(TurkishDetect.isTurkish(line), line)
      }
      // İki harf bozulmuş ya da 5 harfli sözcük bulanık sayılmaz.
      assertFalse(TurkishDetect.isTurkish("Yükleniyxx"))
      assertFalse(TurkishDetect.isTurkish("Iptxl"))
      // İngilizce satırlar (özel adlar ve İngilizce sistem metinleri) Türkçe sayılmaz.
      for line in ["Update complete, please wait.", "Connection lost.", "Loading game data", "Saving settings, do not turn off",
                   "Mr. Bekley and Ms. Oturn arrived", "The Güncel brothers are here."] {
        assertFalse(TurkishDetect.isTurkish(line), line)
      }
    }
    TestRun.test("TurkishDetectTest.oneEditApart") {
      func edit(_ a: String, _ b: String) -> Bool { TurkishDetect.oneEditApart(Array(a), Array(b)) }
      assertTrue(edit("bekleyin", "bekleyln"))
      assertTrue(edit("bekleyin", "bekleyi"))
      assertTrue(edit("bekleyin", "bekleyinn"))
      assertTrue(edit("bekleyin", "ekleyin"))
      assertFalse(edit("bekleyin", "bekleyin"))
      assertFalse(edit("bekleyin", "bekleyxx"))
      assertFalse(edit("bekleyin", "bekley"))
      assertFalse(edit("", ""))
    }
    TestRun.test("TurkishDetectTest.pipelineSkipsTurkishSource") {
      var calls: [String] = []
      let f = PipelineFixture(.direct) { text in calls.append(text); return "çeviri" }
      var options = PipelineOptions()
      options.skipTurkishSource = true
      f.p.options = options
      f.onRead(["Tamam, hadi gidelim."], nil)
      assertEquals([], calls)
      assertEquals(0, f.shown.count)
      assertEquals(1, f.p.skippedAsTarget)
      // İngilizce satır aynı seçenekle yine motora gider.
      var englishCalls: [String] = []
      let g = PipelineFixture(.direct) { text in englishCalls.append(text); return "Nereye gidiyorsun?" }
      g.p.options = options
      g.onRead(["Where are you going?"], nil)
      assertEquals(["Where are you going?"], englishCalls)
      assertEquals(1, g.shown.count)
    }
    TestRun.test("TurkishDetectTest.pipelineWithoutOptionStillCallsEngine") {
      var calls: [String] = []
      let f = PipelineFixture(.direct) { text in calls.append(text); return "çeviri" }
      f.onRead(["Tamam, hadi gidelim."], nil)
      assertEquals(["Tamam, hadi gidelim."], calls)
    }
  }
}
