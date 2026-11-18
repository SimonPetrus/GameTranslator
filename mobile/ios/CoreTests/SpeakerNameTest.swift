// SPDX-License-Identifier: AGPL-3.0-only
// Core/SpeakerName.swift testleri (Kotlin karşılığı yok).
import Foundation

enum SpeakerNameTest {
  static func run() {
    TestRun.test("SpeakerNameTest.namesAreSplitOff") {
      assertEquals("ENZO: ", SpeakerName.split("ENZO: Come on, Gaetano, where are you...").0)
      assertEquals("MINE GUARD: ", SpeakerName.split("MINE GUARD: It wasn't me!").0)
      assertEquals("It wasn't me!", SpeakerName.split("MINE GUARD: It wasn't me!").1)
      assertEquals("DR. O'NEIL-SMITH: ", SpeakerName.split("DR. O'NEIL-SMITH: Hold still.").0)
      assertEquals("BB-8: ", SpeakerName.split("BB-8: Beep.").0)
    }
    TestRun.test("SpeakerNameTest.ordinaryTextIsLeftAlone") {
      assertEquals("", SpeakerName.split("Note: this is not a name").0)
      assertEquals("", SpeakerName.split("We need to go: now.").0)
      assertEquals("", SpeakerName.split("A: one letter").0)
      assertEquals("", SpeakerName.split("10:30 tomorrow").0)
      assertEquals("", SpeakerName.split("ENZO:").0)
      assertEquals("", SpeakerName.split("A VERY LONG NAME THAT IS NOT A NAME AT ALL: hi").0)
    }
    TestRun.test("SpeakerNameTest.translatorKeepsTheName") {
      var seen: [String] = []
      let translator = SpeakerNameTranslator(FunctionTranslator { text in seen.append(text); return "[\(text)]" })
      assertEquals("MINE GUARD: [It wasn't me!]", translator.translate("MINE GUARD: It wasn't me!"))
      assertEquals(["It wasn't me!"], seen)
      assertEquals("[Hello there]", translator.translate("Hello there"))
      let failing = SpeakerNameTranslator(FunctionTranslator { _ in nil })
      assertNull(failing.translate("ENZO: Hi."))
      // Konuşmacı işaretiyle birlikte: önce tire, sonra ad ayrılır.
      let both = PrefixTranslator(SpeakerNameTranslator(FunctionTranslator { "[\($0)]" }))
      assertEquals("- ENZO: [Go.]", both.translate("- ENZO: Go."))
    }
    TestRun.test("SpeakerNameTest.onlyTheFirstColonIsTheName") {
      assertEquals("TELLER: ", SpeakerName.split("TELLER: In Spanish: My God.").0)
      assertEquals("In Spanish: My God.", SpeakerName.split("TELLER: In Spanish: My God.").1)
    }
  }
}

/// Core/SpeakerName.swift'teki SpeakerTurns ve hattın çok konuşmalı yolu (etiketli satırlar TV'de ayrı satır).
enum SpeakerTurnsTest {
  private static let tr: [String: String] = [
    "It's your rec time, not mine.": "Bu senin dinlenme zamanın, benim değil.",
    "Devin: No, bitch.": "Devin: Hayır, kaltak.",
    "Connie: Oh, damn.": "Connie: Oh, lanet olsun.",
    "Prison Guard: Melendez, you're holding up the show.": "Hapishane Gardiyanı: Melendez, gösteriyi geciktiriyorsun.",
    "Shayna: We booked him on a traffic violation.": "Shayna: Onu trafik ihlalinden gözaltına aldık.",
    "Get down!": "Yere yat!",
    "Who is that?": "O da kim?",
    "Guard: Move it.": "Gardiyan: Kımılda.",
    "Devin: Make me.": "Devin: Beni zorla.",
    "It's your rec time, not mine. Devin: No, bitch.": "Bu senin dinlenme zamanın, benim değil. Devin: Hayır, kaltak.",
  ]

  /// Satır sonlarını koruyan motor: her satır ayrı çevrilir, "\n" ile birleşir.
  private static func keepsLines(_ text: String) -> String {
    text.split(separator: "\n").map { tr[String($0)] ?? "?" }.joined(separator: "\n")
  }

  /// Satır sonlarını yutan motor: satırların çevirisi tek satırda, boşlukla.
  private static func swallowsLines(_ text: String) -> String {
    text.split(separator: "\n").map { tr[String($0)] ?? "?" }.joined(separator: " ")
  }

  static func run() {
    TestRun.test("SpeakerTurnsTest.labelledLinesAreSeparateTurns") {
      assertEquals(["Prison Guard: Melendez, you're holding up the show.", "Shayna: We booked him on a traffic violation."],
                   SpeakerTurns.split("Prison Guard: Melendez, you're holding up the show.\nShayna: We booked him on a traffic violation."))
      assertEquals(["It's your rec time, not mine.", "Devin: No, bitch.", "Connie: Oh, damn."],
                   SpeakerTurns.split("It's your rec time, not mine.\nDevin: No, bitch.\nConnie: Oh, damn."))
      assertEquals(["ENZO: Get down!", "MARIA: Who is that?"], SpeakerTurns.split("ENZO: Get down!\nMARIA: Who is that?"))
      assertEquals(["- Run!", "- Where?"], SpeakerTurns.split("- Run!\n- Where?"))
    }
    TestRun.test("SpeakerTurnsTest.wrappedAndLabelLikeLinesStayTogether") {
      // Aynı konuşmacının iki satıra sarılmış cümlesi tek konuşmadır.
      assertEquals(["Shayna: We booked him on a traffic violation, so he stays here."],
                   SpeakerTurns.split("Shayna: We booked him on a traffic\nviolation, so he stays here."))
      // Ad olmayan başlık ve saat yeni konuşma değildir.
      assertEquals(["We meet at the docks. Note: bring the key."], SpeakerTurns.split("We meet at the docks.\nNote: bring the key."))
      assertEquals(["The ferry leaves at 10:30 sharp."], SpeakerTurns.split("The ferry leaves at\n10:30 sharp."))
      // Yalnız ilk "Ad:" etikettir; satır içindeki "In Spanish:" konuşmayı bölmez.
      assertEquals(["Teller: In Spanish: My God, goddamn."], SpeakerTurns.split("Teller: In Spanish: My God, goddamn."))
      assertEquals(["Lucia: You! Cash on the counter right now!", "Teller: In Spanish: My God, goddamn."],
                   SpeakerTurns.split("Lucia: You! Cash on the counter right now!\nTeller: In Spanish: My God, goddamn."))
      assertEquals([], SpeakerTurns.split(""))
      assertEquals(["A", "B", "C"], SpeakerTurns.lines("A\n\n B \r\nC\n"))
    }
    TestRun.test("SpeakerTurnsTest.twoSpeakersShowOnTwoLines") {
      var calls: [String] = []
      let f = PipelineFixture(.direct) { text in calls.append(text); return keepsLines(text) }
      f.onRead(["Prison Guard: Melendez, you're holding up the show.", "Shayna: We booked him on a traffic violation."], nil)
      assertEquals(["Prison Guard: Melendez, you're holding up the show.\nShayna: We booked him on a traffic violation."], calls,
                   "tek istek")
      assertEquals(["Hapishane Gardiyanı: Melendez, gösteriyi geciktiriyorsun.\nShayna: Onu trafik ihlalinden gözaltına aldık.|15000|false"],
                   f.shown)
    }
    TestRun.test("SpeakerTurnsTest.continuationThenTwoSpeakersShowOnThreeLines") {
      var calls: [String] = []
      let f = PipelineFixture(.direct) { text in calls.append(text); return keepsLines(text) }
      f.onRead(["It's your rec time, not mine.", "Devin: No, bitch.", "Connie: Oh, damn."], nil)
      assertEquals(1, calls.count, "tek istek")
      assertEquals(["Bu senin dinlenme zamanın, benim değil.\nDevin: Hayır, kaltak.\nConnie: Oh, lanet olsun.|15000|false"], f.shown)
    }
    TestRun.test("SpeakerTurnsTest.wrappedSentenceOfOneSpeakerStaysOneLine") {
      var calls: [String] = []
      let f = PipelineFixture(.direct) { text in calls.append(text); return "Shayna: Onu trafik ihlalinden aldık, burada kalıyor." }
      f.onRead(["Shayna: We booked him on a traffic", "violation, so he stays here."], nil)
      assertEquals(["Shayna: We booked him on a traffic violation, so he stays here."], calls)
      assertEquals(["Shayna: Onu trafik ihlalinden aldık, burada kalıyor.|15000|false"], f.shown)
    }
    TestRun.test("SpeakerTurnsTest.engineThatSwallowsLineBreaksIsAskedPerTurn") {
      var calls: [String] = []
      let f = PipelineFixture(.direct) { text in calls.append(text); return swallowsLines(text) }
      f.onRead(["It's your rec time, not mine.", "Devin: No, bitch.", "Connie: Oh, damn."], nil)
      assertEquals(["It's your rec time, not mine.\nDevin: No, bitch.\nConnie: Oh, damn.",
                    "It's your rec time, not mine.", "Devin: No, bitch.", "Connie: Oh, damn."], calls)
      assertEquals(["Bu senin dinlenme zamanın, benim değil.\nDevin: Hayır, kaltak.\nConnie: Oh, lanet olsun.|15000|false"], f.shown)
    }
    TestRun.test("SpeakerTurnsTest.translatedOrBrokenLabelsAreHandled") {
      // Motor etiketi çevirdi: satır yapısı korunur.
      let f = PipelineFixture(.direct) { keepsLines($0) }
      f.onRead(["Guard: Move it.", "Devin: Make me."], nil)
      assertEquals(["Gardiyan: Kımılda.\nDevin: Beni zorla.|15000|false"], f.shown)
      // Motor fazladan satır döndürdü: konuşmalar tek tek çevrilir, sonuç yine iki satır.
      var calls = 0
      let g = PipelineFixture(.direct) { text in
        calls += 1
        return text.contains("\n") ? "Kımılda.\nBeni\nzorla." : (tr[text] ?? "?")
      }
      g.onRead(["Guard: Move it.", "Devin: Make me."], nil)
      assertEquals(3, calls)
      assertEquals(["Gardiyan: Kımılda.\nDevin: Beni zorla.|15000|false"], g.shown)
      // Motor hiç çeviremedi: gösterilmez, konuşma konuşma yeniden denenmez.
      var failed = 0
      let h = PipelineFixture(.direct) { _ in failed += 1; return nil }
      h.onRead(["Guard: Move it.", "Devin: Make me."], nil)
      assertEquals(1, failed)
      assertEquals([], h.shown)
    }
    TestRun.test("SpeakerTurnsTest.capitalNamesAreKeptAndNotSentToTheEngine") {
      var calls: [String] = []
      let f = PipelineFixture(.direct) { text in calls.append(text); return keepsLines(text) }
      f.onRead(["ENZO: Get down!", "MARIA: Who is that?"], nil)
      assertEquals(["Get down!\nWho is that?"], calls)
      assertEquals(["ENZO: Yere yat!\nMARIA: O da kim?|15000|false"], f.shown)
      // Ek okuma alanının tek seferlik çevirisi de aynı yoldan gider.
      assertEquals("ENZO: Yere yat!\nMARIA: O da kim?", f.p.translateOnce("ENZO: Get down!\nMARIA: Who is that?").text)
    }
    TestRun.test("SpeakerTurnsTest.speakerChangeInsideALine") {
      // Satır ortasında cümle sonundan sonraki etiket: ad yakın geçmişte satır başında görüldüyse ya da metinde iki etiket varsa.
      assertEquals(["It's your rec time, not mine.", "Devin: No, bitch."],
                   SpeakerTurns.split("It's your rec time, not mine. Devin: No, bitch.", known: ["devin"]))
      assertEquals(["It's your rec time, not mine. Devin: No, bitch."], SpeakerTurns.split("It's your rec time, not mine. Devin: No, bitch."))
      assertEquals(["Lucia: You!", "Teller: Hi there."], SpeakerTurns.split("Lucia: You! Teller: Hi there."))
      // Tek etiket, ad olmayan başlık, saat ve satır içi ikinci iki nokta bölünmez.
      assertEquals(["He said so. Captain: Move out."], SpeakerTurns.split("He said so. Captain: Move out."))
      assertEquals(["I told him. Listen: we go now."], SpeakerTurns.split("I told him. Listen: we go now.", known: ["listen"]))
      assertEquals(["Meet at 10:30. Be ready."], SpeakerTurns.split("Meet at 10:30. Be ready."))
      assertEquals(["Teller: In Spanish: My God."], SpeakerTurns.split("Teller: In Spanish: My God.", known: ["teller", "in spanish"]))
      // Satır başı etiketleri hattın yakın geçmişine yazılır (tireden sonra da).
      assertEquals(["devin", "connie"], SpeakerTurns.speakers(in: "It's your rec time.\nDevin: No.\n- Connie: Oh."))
    }
    TestRun.test("SpeakerTurnsTest.recentSpeakerSplitsALaterLine") {
      var calls: [String] = []
      let f = PipelineFixture(.direct) { text in calls.append(text); return keepsLines(text) }
      f.onRead(["Devin: Make me."], nil)
      f.clock.now += 100
      f.onRead([], nil)
      f.clock.now += 5000
      f.onRead([], nil)
      f.clock.now += 5000
      f.onRead(["It's your rec time, not mine. Devin: No, bitch."], nil)
      assertEquals(["Devin: Make me.", "It's your rec time, not mine.\nDevin: No, bitch."], calls)
      assertEquals(2, f.shown.count)
      assertTrue(f.shown.last?.hasPrefix("Bu senin dinlenme zamanın, benim değil.\nDevin: Hayır, kaltak.|") == true, "\(f.shown)")
    }
    TestRun.test("SpeakerTurnsTest.memoryCacheKeepsTheLineStructure") {
      // Aynı sözcükler önce tek satır (tek konuşma) çevrildi; sonraki satırlı okuma düz paragrafı önbellekten almaz.
      var calls: [String] = []
      let f = PipelineFixture(.direct) { text in calls.append(text); return keepsLines(text) }
      f.onRead(["It's your rec time, not mine. Devin: No, bitch."], nil)
      f.clock.now += 100
      f.onRead([], nil)
      f.clock.now += 5000
      f.onRead([], nil)
      f.clock.now += 5000
      f.onRead(["It's your rec time, not mine.", "Devin: No, bitch."], nil)
      assertEquals(["It's your rec time, not mine. Devin: No, bitch.", "It's your rec time, not mine.\nDevin: No, bitch."], calls)
      assertEquals("Bu senin dinlenme zamanın, benim değil. Devin: Hayır, kaltak.|15000|false", f.shown.first)
      assertTrue(f.shown.last?.hasPrefix("Bu senin dinlenme zamanın, benim değil.\nDevin: Hayır, kaltak.|") == true, "\(f.shown)")
    }
    TestRun.test("SpeakerTurnsTest.oldFlattenedCacheEntryIsNotUsed") {
      let shared = DiskTranslationCache(storage: MemoryCacheStorage(), capacity: 100, saveDelay: 3600, now: { 1_000_000 })
      var options = PipelineOptions()
      options.cache = shared
      options.engineId = "google"
      // Eski sürümün tek satıra düzleştirip sakladığı birleşik çeviri.
      shared.set(options.cacheKey("It's your rec time, not mine. Devin: No, bitch."), "Bu senin dinlenme zamanın, benim değil. Devin: Hayır.")
      var calls = 0
      let f = PipelineFixture(.direct) { text in calls += 1; return keepsLines(text) }
      f.p.options = options
      f.onRead(["It's your rec time, not mine.", "Devin: No, bitch."], nil)
      assertEquals(1, calls)
      assertEquals(["Bu senin dinlenme zamanın, benim değil.\nDevin: Hayır, kaltak.|15000|false"], f.shown)
      assertEquals(2, shared.count)
      // Yeni hat: satır sonlu kayıt önbellekten gelir, motora gidilmez.
      var again = 0
      let g = PipelineFixture(.direct) { _ in again += 1; return nil }
      g.p.options = options
      g.onRead(["It's your rec time, not mine.", "Devin: No, bitch."], nil)
      assertEquals(0, again)
      assertEquals(["Bu senin dinlenme zamanın, benim değil.\nDevin: Hayır, kaltak.|15000|false"], g.shown)
    }
  }
}
