// SPDX-License-Identifier: AGPL-3.0-only
// Doğal Türkçe adımlarının (deyim, hazır cevap, son düzeltme, sen/siz, bağlam, ad koruması) testleri; Kotlin karşılığı yok.
import Foundation

enum IdiomNormalizerTest {
  static func run() {
    TestRun.test("IdiomNormalizerTest.listIsBigEnough") {
      assertTrue(IdiomNormalizer.count >= 100, "kural sayısı \(IdiomNormalizer.count)")
    }
    TestRun.test("IdiomNormalizerTest.idiomsAreReplacedKeepingCaseAndPunctuation") {
      assertEquals("I will protect you.", IdiomNormalizer.apply("I've got your six."))
      assertEquals("Hostiles are approaching!", IdiomNormalizer.apply("We've got company!"))
      assertEquals("Hostiles are approaching!", IdiomNormalizer.apply("We’ve got company!"))
      assertEquals("Withdraw!", IdiomNormalizer.apply("Fall back!"))
      assertEquals("STAY FOCUSED!", IdiomNormalizer.apply("STAY FROSTY!"))
      assertEquals("Stay focused, rookie.", IdiomNormalizer.apply("Stay frosty, rookie."))
      assertEquals("Guard me!", IdiomNormalizer.apply("Cover me!"))
      assertEquals("They are defenseless targets.", IdiomNormalizer.apply("They are sitting ducks."))
      assertEquals("That took you a while.", IdiomNormalizer.apply("Took you long enough."))
      assertEquals("At last!", IdiomNormalizer.apply("About time!"))
      assertEquals("Okay, withdraw!", IdiomNormalizer.apply("Okay, fall back!"))
      assertEquals("Wait for it. At my signal.", IdiomNormalizer.apply("Wait for it. On my mark."))
      assertEquals("We are being shot at!", IdiomNormalizer.apply("We're taking fire!"))
    }
    TestRun.test("IdiomNormalizerTest.ordinaryTextIsLeftAlone") {
      for line in ["Where are you going?", "I will fall back on my training.", "He will fall back asleep.",
                   "We have company tonight.", "Cover me with a blanket.", "It is about time to leave.",
                   "Stay frostbitten.", "Okay, fall back to the bridge.", "Hold the line, please.",
                   "The heads up display is broken.", "Get down from there.",
                   "We are taking fire from the left.", "The coast is clear today.", "He hit the road early.",
                   "Let them have it back."] {
        assertEquals(line, IdiomNormalizer.apply(line), line)
      }
    }
  }
}

enum StockLinesTest {
  static func run() {
    TestRun.test("StockLinesTest.tableIsBigEnough") {
      assertTrue(StockLines.count >= 60, "satır sayısı \(StockLines.count)")
    }
    TestRun.test("StockLinesTest.stockLinesGetFixedTurkish") {
      assertEquals("Temiz!", StockLines.lookup("Clear!"))
      assertEquals("Anlaşıldı.", StockLines.lookup("Copy that."))
      assertEquals("Anlaşıldı.", StockLines.lookup("Roger."))
      assertEquals("Yürü!", StockLines.lookup("Move!"))
      assertEquals("Şarjör değiştir!", StockLines.lookup("Reload!"))
      assertEquals("Teşekkürler.", StockLines.lookup("Thanks."))
      assertEquals("Merhaba?", StockLines.lookup("Hello?"))
      assertEquals("Temiz", StockLines.lookup("clear"))
      assertEquals("Temiz!!", StockLines.lookup("CLEAR!!"))
      assertEquals("Kımıldama!", StockLines.lookup("Don't move!"))
      assertEquals("Kımıldama!", StockLines.lookup("Don’t move!"))
      assertEquals("- Temiz!", StockLines.lookup("- Clear!"))
      assertEquals("ENZO: Anlaşıldı.", StockLines.lookup("ENZO: Copy that."))
      assertEquals("Bekle…", StockLines.lookup("Wait…"))
    }
    TestRun.test("StockLinesTest.otherLinesGoToTheEngine") {
      for line in ["Where are you going?", "Clear the room!", "Clear?", "Sure.", "Fine.", "Left.", "Move! Now!",
                   "Clear, please.", "\"Clear!\"", "Roger that, sir.", "Wait?", "Sorry?", "",
                   // Bağlama göre değişen tek sözcükler tabloda yok.
                   "Go!", "Help!", "Medic!", "Man down!", "Fire!", "Cover!", "Incoming!", "On your left!"] {
        assertNull(StockLines.lookup(line), line)
      }
    }
  }
}

enum TurkishPolishTest {
  static func run() {
    TestRun.test("TurkishPolishTest.spacesAndPunctuation") {
      assertEquals("Eşyaları topla!", TurkishPolish.apply("Eşyaları topla !", source: "Gather the supplies!"))
      assertEquals("Burada kal.", TurkishPolish.apply("Burada   kal  .", source: "Stay in this room."))
      assertEquals("Işığı söndür…", TurkishPolish.apply("Işığı söndür …", source: "Turn off the light…"))
      assertEquals("Hayır, olmaz.", TurkishPolish.apply("Hayır , olmaz .", source: "No, never."))
    }
    TestRun.test("TurkishPolishTest.sourceEndMarkIsKept") {
      assertEquals("Saklan!", TurkishPolish.apply("Saklan.", source: "Hide!"))
      assertEquals("Emin misin?", TurkishPolish.apply("Emin misin.", source: "Are you sure?"))
      assertEquals("Ne yaptın?!", TurkishPolish.apply("Ne yaptın.", source: "What have you done?!"))
      assertEquals("Hala buradayım...", TurkishPolish.apply("Hala buradayım.", source: "I am still here..."))
      assertEquals("Anahtarı ver!", TurkishPolish.apply("Anahtarı ver", source: "Hand over the key!"))
      assertEquals("\"Atla!\"", TurkishPolish.apply("\"Atla.\"", source: "\"Jump!\""))
      assertEquals("Kapıyı kapat. Hemen aç!",
                   TurkishPolish.apply("Kapıyı kapat. Hemen aç.", source: "Close the door. Open it now!"))
    }
    TestRun.test("TurkishPolishTest.endMarkIsNotForced") {
      // Kaynak düz noktaysa ya da çeviri başka güçlü işaretle bitiyorsa dokunulmaz.
      assertEquals("Atla!", TurkishPolish.apply("Atla!", source: "Jump."))
      assertEquals("Gerçek mi?", TurkishPolish.apply("Gerçek mi?", source: "It is real!"))
      assertEquals("Sakin ol", TurkishPolish.apply("Sakin ol", source: "Calm down"))
      assertEquals("Dönme,", TurkishPolish.apply("Dönme,", source: "Don't turn!"))
      assertEquals("Anahtar nerede?", TurkishPolish.apply("Anahtar nerede?", source: "Where is the key?"))
    }
    TestRun.test("TurkishPolishTest.quotesFollowTheSource") {
      assertEquals("“Atla!”", TurkishPolish.apply("\"Atla!\"", source: "“Jump!”"))
      assertEquals("\"Atla!\"", TurkishPolish.apply("“Atla!”", source: "\"Jump!\""))
      assertEquals("Ayşe'nin evi.", TurkishPolish.apply("Ayşe’nin evi.", source: "Ayse's house."))
      assertEquals("Ayşe’nin evi.", TurkishPolish.apply("Ayşe'nin evi.", source: "Ayse’s house."))
      // Tek (eşleşmeyen) düz tırnak kıvrığa çevrilmez.
      assertEquals("Dedi ki \"atla.", TurkishPolish.apply("Dedi ki \"atla.", source: "He said “jump."))
    }
    TestRun.test("TurkishPolishTest.capitalization") {
      assertEquals("Atla!", TurkishPolish.apply("atla!", source: "Jump!"))
      assertEquals("Işığı söndür.", TurkishPolish.apply("ışığı söndür.", source: "Turn off the light."))
      assertEquals("- Kapıyı aç.", TurkishPolish.apply("- kapıyı aç.", source: "- Open the door."))
      assertEquals("MARA: Sakin ol.", TurkishPolish.apply("MARA: sakin ol.", source: "MARA: Calm down."))
      // Kaynak küçük harfle başlıyorsa cümlenin devamıdır; rakamla başlayan metne dokunulmaz.
      assertEquals("ve sonra", TurkishPolish.apply("ve sonra", source: "and later"))
      assertEquals("2 kişi vardı.", TurkishPolish.apply("2 kişi vardı.", source: "Two people were there."))
    }
    TestRun.test("TurkishPolishTest.emptyAndPlainTextAreStable") {
      assertEquals("", TurkishPolish.apply("   ", source: "Jump!"))
      assertEquals("Merhaba.", TurkishPolish.apply("Merhaba.", source: "Hello."))
    }
  }
}

enum AddressFormTest {
  /// Saniye cinsinden elle ilerletilen saat.
  final class TestClock { var now = 1000.0 }

  static func run() {
    TestRun.test("AddressFormTest.verbListIsBigEnough") {
      assertTrue(AddressForm.count >= 120, "çevrilen sözcük sayısı \(AddressForm.count)")
    }
    TestRun.test("AddressFormTest.evidence") {
      assertTrue(AddressForm.evidence("Seni gördüm.").sen)
      assertFalse(AddressForm.evidence("Seni gördüm.").siz)
      assertTrue(AddressForm.evidence("Sizi gördüm.").siz)
      assertTrue(AddressForm.evidence("Beyler, bekleyin.").siz)
      assertTrue(AddressForm.evidence("Nerede çalışıyorsunuz?").siz)
      assertFalse(AddressForm.evidence("Bekleyin.").sen)
      assertFalse(AddressForm.evidence("Bekleyin.").siz)
    }
    TestRun.test("AddressFormTest.imperativesBecomeSingularWhenSenIsUsed") {
      assertEquals("Seni görüyorum, bekle.", AddressForm.harmonizeLine("Seni görüyorum, bekleyin."))
      assertEquals("Sana söylüyorum. Dur!", AddressForm.harmonizeLine("Sana söylüyorum. Durun!"))
      assertEquals("Senin için buradayım, koş!", AddressForm.harmonizeLine("Senin için buradayım, koşun!"))
      assertEquals("SEN BEKLE!", AddressForm.harmonizeLine("SEN BEKLEYİN!"))
      assertEquals("Seni duydum, gitme.", AddressForm.harmonizeLine("Seni duydum, gitmeyin."))
      assertEquals("Sana güveniyorum, bakma.", AddressForm.harmonizeLine("Sana güveniyorum, bakmayın."))
      assertEquals("Sana söylüyorum, dikkat et!", AddressForm.harmonizeLine("Sana söylüyorum, dikkat edin!"))
      assertEquals("Sana söylüyorum, hadi gel!", AddressForm.harmonizeLine("Sana söylüyorum, hadi gelin!"))
      assertEquals("Senin yolun uzun. Gel.", AddressForm.harmonizeLine("Senin yolun uzun. Gelin."))
    }
    TestRun.test("AddressFormTest.ambiguousOrUnsureTextIsLeftAlone") {
      // Siz belirtisi, çoğul seslenme, belirtisiz satır: dokunulmaz.
      for line in ["Sen ve siz bekleyin.", "Beyler, sana söylüyorum, bekleyin.", "Bekleyin.", "Sizi gördüm, bekleyin.",
                   // Başka anlamı olan sözcükler listede yok.
                   "Sana bir şey söyleyeceğim. Alın.", "Sana yazın.", "Seni kazın.", "Sen kesin.", "Sana koyun.",
                   "Sana verin.", "Seni bilin.", "Senin için yapın.", "Sana çekin.", "Seni çıkın.",
                   // Emir konumunda değil: sözcükten sonra noktalama yok.
                   "Sen bekleyin burada.",
                   // "gelin" cümlecik başında değil: gelin (evli kadın) olabilir.
                   "Sana güveniyorum çünkü gelin.",
                   // Normal cümle.
                   "Seni gördüm.", "Nereye gidiyorsun?"] {
        assertEquals(line, AddressForm.harmonizeLine(line), line)
      }
    }
    TestRun.test("AddressFormTest.speakerOfLine") {
      assertEquals("ENZO", AddressMemory.speaker(of: "ENZO: Hi there."))
      assertEquals("ENZO", AddressMemory.speaker(of: "- ENZO: Hi there."))
      assertNull(AddressMemory.speaker(of: "Hello there."))
      assertNull(AddressMemory.speaker(of: "Note: this is not a name"))
    }
    TestRun.test("AddressFormTest.speakerMemory") {
      let clock = TestClock()
      let memory = AddressMemory(clock: { clock.now })
      // Tek "sen" gözlemi yetmez.
      assertEquals("Seni gördüm.", memory.apply("Seni gördüm.", speaker: "ENZO"))
      assertEquals("Bekleyin.", memory.apply("Bekleyin.", speaker: "ENZO"))
      // İkinci ardışık "sen" gözlemi: belirtisiz satır tekile çevrilir.
      assertEquals("Sana söyledim.", memory.apply("Sana söyledim.", speaker: "ENZO"))
      assertEquals("Bekle.", memory.apply("Bekleyin.", speaker: "ENZO"))
      // Başka konuşmacı ve konuşmacısız satır etkilenmez.
      assertEquals("Bekleyin.", memory.apply("Bekleyin.", speaker: "MARIA"))
      assertEquals("Bekleyin.", memory.apply("Bekleyin.", speaker: nil))
      // "Siz" gözlemi seriyi bozar.
      assertEquals("Sizi gördüm.", memory.apply("Sizi gördüm.", speaker: "ENZO"))
      assertEquals("Bekleyin.", memory.apply("Bekleyin.", speaker: "ENZO"))
      // Yeniden iki "sen", sonra zaman aşımı.
      _ = memory.apply("Seni gördüm.", speaker: "ENZO")
      _ = memory.apply("Sana söyledim.", speaker: "ENZO")
      assertEquals("Bekle.", memory.apply("Bekleyin.", speaker: "ENZO"))
      clock.now += AddressMemory.maxAgeSeconds + 1
      assertEquals("Bekleyin.", memory.apply("Bekleyin.", speaker: "ENZO"))
      // Sıfırlama.
      clock.now += 1
      _ = memory.apply("Seni gördüm.", speaker: "ENZO")
      _ = memory.apply("Sana söyledim.", speaker: "ENZO")
      memory.reset()
      assertEquals("Bekleyin.", memory.apply("Bekleyin.", speaker: "ENZO"))
    }
  }
}

enum ShortLineContextTest {
  static func run() {
    TestRun.test("ShortLineContextTest.shortLines") {
      assertTrue(ShortLineContext.isShort("Which one?"))
      assertTrue(ShortLineContext.isShort("Over there."))
      assertTrue(ShortLineContext.isShort("It was her."))
      assertTrue(ShortLineContext.isShort("MARA: Which one?"))
      assertFalse(ShortLineContext.isShort("Where did it happen?"))
      assertFalse(ShortLineContext.isShort("..."))
      assertFalse(ShortLineContext.isShort(""))
    }
    TestRun.test("ShortLineContextTest.contextSelection") {
      assertEquals("Someone saw Tomas near the pier.",
                   ShortLineContext.context(for: "Which one?", previous: "Someone saw Tomas near the pier."))
      assertEquals("Where is the boat?", ShortLineContext.context(for: "Over there.", previous: "MARA: Where is the boat?"))
      // Uzun satırın bağlamı yok, önceki satır yok, aynı satır bağlam değil.
      assertNull(ShortLineContext.context(for: "Where did it happen?", previous: "Someone saw Tomas near the pier."))
      assertNull(ShortLineContext.context(for: "Which one?", previous: nil))
      assertNull(ShortLineContext.context(for: "Which one?", previous: "  "))
      assertNull(ShortLineContext.context(for: "Which one?", previous: "Which one!"))
      let long = String(repeating: "word ", count: 80)
      let cut = ShortLineContext.context(for: "Which one?", previous: long)
      assertNotNull(cut)
      assertTrue((cut ?? "").utf16.count <= ShortLineContext.maxContextLength)
    }
    TestRun.test("ShortLineContextTest.threadContext") {
      assertNull(TranslationContext.current)
      TranslationContext.set("abc")
      assertEquals("abc", TranslationContext.current)
      TranslationContext.set(nil)
      assertNull(TranslationContext.current)
    }
    TestRun.test("ShortLineContextTest.separatorProtocol") {
      assertEquals("Someone saw Tomas near the pier. ### Which one?",
                   ContextSplit.combine(context: "Someone saw Tomas near the pier.", text: "Which one?"))
      assertEquals("Hold. ### Why?", ContextSplit.combine(context: "Hold", text: "Why?"))
      assertEquals("Hangisi?", ContextSplit.extract("Biri iskelede gördü. ### Hangisi?", original: "Which one?"))
      assertNull(ContextSplit.extract("Biri iskelede gördü. Hangisi?", original: "Which one?"))
      assertNull(ContextSplit.extract("A ### B ### C", original: "Which one?"))
      assertNull(ContextSplit.extract("Biri iskelede gördü. ###", original: "Which one?"))
      assertNull(ContextSplit.extract("### Hangisi?", original: "Which one?"))
      assertNull(ContextSplit.extract("Önceki. ### " + String(repeating: "a ", count: 12), original: "Which one?"))
    }
    TestRun.test("ShortLineContextTest.splitTranslate") {
      var calls: [String] = []
      // Ayraç korunur: kısa satırın çevirisi alınır.
      let ok = ContextSplit.translate("Why?", context: "A.") { text in
        calls.append(text)
        return text == "A. ### Why?" ? "Bir. ### Neden?" : nil
      }
      assertEquals("Neden?", ok)
      assertEquals(["A. ### Why?"], calls)
      // Ayraç kayıp: kısa satır tek başına çevrilir.
      calls = []
      let lost = ContextSplit.translate("Why?", context: "A.") { text in
        calls.append(text)
        return text == "Why?" ? "Neden?" : "Bir neden"
      }
      assertEquals("Neden?", lost)
      assertEquals(["A. ### Why?", "Why?"], calls)
      // Ağ yok: tek istek, ikinci deneme yok.
      calls = []
      assertNull(ContextSplit.translate("Why?", context: "A.") { text in calls.append(text); return nil })
      assertEquals(1, calls.count)
      // Bağlam yok ya da metinde ayraç var: doğrudan.
      calls = []
      assertEquals("x", ContextSplit.translate("Why?", context: nil) { text in calls.append(text); return "x" })
      assertEquals(["Why?"], calls)
      calls = []
      _ = ContextSplit.translate("a ### b", context: "A.") { text in calls.append(text); return "x" }
      assertEquals(["a ### b"], calls)
    }
  }
}

enum NameProtectionTest {
  static func run() {
    TestRun.test("NameProtectionTest.midSentenceNamesAreFound") {
      assertEquals(["Tomas"], NameProtection.candidates("Where is Tomas going with the key?"))
      assertEquals(["Tomas"], NameProtection.candidates("She told Tomas that Tomas left early."))
      assertEquals(["Tomas"], NameProtection.candidates("I'm Tomas's friend."))
      assertEquals(["Elsa"], NameProtection.candidates("Tell Elsa to wait, Elsa."))
    }
    TestRun.test("NameProtectionTest.ordinaryCapitalsAreIgnored") {
      for line in ["Tomas is here.", "Yes, Captain.", "THEY SAW TOMAS!", "He lives in Spring, not in spring.",
                   "See you on Monday.", "Why, Doesn't it work?", "She said, \"Run.\" Then she left.",
                   "He spoke English.", "Hello there.", "Look: Tomas", "- Tomas"] {
        assertEquals([], NameProtection.candidates(line), line)
      }
    }
    TestRun.test("NameProtectionTest.vocativesAndTitlesAreNotProtected") {
      for line in ["Run, Boy!", "Easy, Kid.", "Thank you, Mother.", "Yes, Sir.", "Careful, Rookie!", "Go on, Doc.",
                   "Move it, Sarge.", "As you wish, Majesty."] {
        assertEquals([], NameProtection.candidates(line), line)
      }
      // Virgülden sonra cümle sonundaki ad: oturumda görülmediyse korunmaz, görüldüyse korunur.
      assertEquals([], NameProtection.candidates("Keep going, Elsa."))
      assertEquals(["Elsa"], NameProtection.candidates("Keep going, Elsa.", known: ["elsa"]))
      assertEquals([], NameProtection.candidates("Elsa saw it. Keep going, Elsa."))
      // Aynı satırda hitap olmayan konumda da geçiyorsa korunur.
      assertEquals(["Elsa"], NameProtection.candidates("Tell Elsa to wait, Elsa."))
    }
    TestRun.test("NameProtectionTest.titleCaseLinesAreNotProtected") {
      assertTrue(NameProtection.isTitleCase("Welcome To The Black Gate"))
      assertEquals([], NameProtection.candidates("Welcome To The Black Gate"))
      assertEquals([], NameProtection.candidates("Chapter One The Old Harbor Town"))
      assertFalse(NameProtection.isTitleCase("Where is Tomas going with the key?"))
      assertFalse(NameProtection.isTitleCase("Hello"))
    }
    TestRun.test("NameProtectionTest.nameMemory") {
      let memory = NameMemory()
      assertTrue(memory.snapshot.isEmpty)
      memory.remember(["Elsa", "Tomas"])
      assertTrue(memory.snapshot.contains("elsa"))
      assertTrue(memory.snapshot.contains("tomas"))
      memory.reset()
      assertTrue(memory.snapshot.isEmpty)
    }
    TestRun.test("NameProtectionTest.userGlossaryTermsAreSkipped") {
      let glossary = Glossary.of(["Kratos": "Kratos"])
      assertEquals([], NameProtection.candidates("Call Kratos now.", glossary: glossary))
      assertEquals(["Tomas"], NameProtection.candidates("Call Tomas and Kratos now.", glossary: glossary))
    }
    TestRun.test("NameProtectionTest.nameRoundTripKeepsNameAndSuffix") {
      var seen: [String] = []
      let translator = GlossaryTranslator(NameProtection.glossary(for: ["Tomas"]), FunctionTranslator { text in
        seen.append(text)
        return "Biri Zarmon'u gördü."
      })
      assertEquals("Biri Tomas'ı gördü.", translator.translate("Someone saw Tomas near the pier."))
      assertEquals(["Someone saw Zarmon near the pier."], seen)
    }
  }
}

/// Hat içinde uçtan uca: deyim, hazır cevap, son düzeltme, bağlam, ad koruması, sen/siz belleği.
enum NaturalPipelineTest {
  private static func options(engine: String = "google", source: String = "en", target: String = "tr") -> PipelineOptions {
    var options = PipelineOptions()
    options.engineId = engine
    options.sourceLanguage = source
    options.targetLanguage = target
    return options
  }

  /// Satır kalkıp yenisi okunur (önceki satır gösterilmiş olur).
  private static func read(_ f: PipelineFixture, _ line: String, after extra: Int64 = 0) {
    f.clock.now += 100 + extra
    f.onRead([], nil)
    f.clock.now += 2000
    f.onRead([], nil)
    f.onRead([line], nil)
  }

  private static func texts(_ f: PipelineFixture) -> [String] {
    f.shown.map { String($0.split(separator: "|", omittingEmptySubsequences: false).first ?? "") }
  }

  private static func fixture(_ mode: ExecutorMode, _ options: PipelineOptions,
                              _ translator: @escaping (String) -> String?) -> PipelineFixture {
    let f = PipelineFixture(mode, translator)
    f.p.options = options
    let clock = f.clock
    f.p.contextClock = { Double(clock.now) / 1000 }
    return f
  }

  static func run() {
    for mode in ExecutorMode.allCases { run(mode) }
    TestRun.test("NaturalPipelineTest.otherLanguagePairsAreUntouched") {
      var calls: [String] = []
      let f = fixture(.direct, options(target: "de")) { text in calls.append(text); return "gehen !" }
      f.onRead(["We've got company!"], nil)
      assertEquals(["We've got company!"], calls)
      assertEquals(["gehen !"], texts(f))
      let g = PipelineFixture(.direct) { text in calls.append(text); return "koş !" }
      g.onRead(["Clear!"], nil)
      assertEquals("koş !", texts(g).last)
    }
  }

  static func run(_ mode: ExecutorMode) {
    let suffix = " [\(mode.rawValue)]"
    TestRun.test("NaturalPipelineTest.stockLineSkipsTheEngine" + suffix) {
      var calls: [String] = []
      let f = fixture(mode, options()) { text in calls.append(text); return "motor" }
      f.onRead(["Clear!"], nil)
      assertEquals([], calls)
      assertEquals(["Temiz!"], texts(f))
    }
    TestRun.test("NaturalPipelineTest.idiomIsNormalizedBeforeTheEngineAndResultIsPolished" + suffix) {
      var calls: [String] = []
      let f = fixture(mode, options()) { text in calls.append(text); return "düşmanlar yaklaşıyor !" }
      f.onRead(["We've got company!"], nil)
      assertEquals(["Hostiles are approaching!"], calls)
      assertEquals(["Düşmanlar yaklaşıyor!"], texts(f))
    }
    TestRun.test("NaturalPipelineTest.geminiKeepsItsOwnInputButIsPolished" + suffix) {
      var calls: [String] = []
      let f = fixture(mode, options(engine: "gemini")) { text in calls.append(text); return "düşmanlar yaklaşıyor !" }
      f.onRead(["We've got company!"], nil)
      assertEquals(["We've got company!"], calls)
      assertEquals(["Düşmanlar yaklaşıyor!"], texts(f))
    }
    TestRun.test("NaturalPipelineTest.engineEndMarkIsRestored" + suffix) {
      let f = fixture(mode, options()) { _ in "Tekneye acele et." }
      f.onRead(["Hurry to the boat!"], nil)
      assertEquals(["Tekneye acele et!"], texts(f))
    }
    TestRun.test("NaturalPipelineTest.shortLineGetsContextAndNamesStayStable" + suffix) {
      var calls: [String] = []
      var contexts: [String?] = []
      let f = fixture(mode, options()) { text in
        calls.append(text)
        contexts.append(TranslationContext.current)
        if text.contains("Zarmon") { return "Biri Zarmon'u iskelenin yanında gördü." }
        return text == "Which one?" ? "Hangisi ?" : "Nerede oldu?"
      }
      f.onRead(["Someone saw Tomas near the pier."], nil)
      // Ad yer tutucuyla gitti, geri konuldu (ek ada göre kuruldu); ilk satırın bağlamı yok.
      assertEquals(["Someone saw Zarmon near the pier."], calls)
      assertEquals("Biri Tomas'ı iskelenin yanında gördü.", texts(f).last)
      assertNil(contexts[0])
      // Kısa satır: önceki gösterilen satır bağlam; çeviri son düzeltilir.
      read(f, "Which one?")
      assertEquals("Which one?", calls[1])
      assertEquals("Someone saw Tomas near the pier.", contexts[1])
      assertEquals("Hangisi?", texts(f).last)
      assertNil(TranslationContext.current, "bağlam iş parçacığında kalmamalı")
      // Bağlamla çevrilen satır önbelleğe girmez: aynı satır başka bağlamla yeniden çevrilir.
      read(f, "Where did it happen?")
      read(f, "Which one?")
      assertEquals(4, calls.count)
      assertEquals("Where did it happen?", contexts[3])
    }
    TestRun.test("NaturalPipelineTest.oldOrGeminiOrLongLineGetsNoContext" + suffix) {
      var contexts: [String?] = []
      let f = fixture(mode, options()) { _ in contexts.append(TranslationContext.current); return "Tamam." }
      f.onRead(["Someone saw Tomas near the pier."], nil)
      read(f, "Which one?", after: 20_000)
      assertNil(contexts[1], "önceki satır 15 sn'den eski")
      read(f, "That one.")
      assertEquals("Which one?", contexts[2])
      read(f, "Where did it happen near the old pier?")
      assertNil(contexts[3], "uzun satır")

      var geminiContexts: [String?] = []
      let g = fixture(mode, options(engine: "gemini")) { _ in geminiContexts.append(TranslationContext.current); return "Tamam." }
      g.onRead(["Someone saw Tomas near the pier."], nil)
      read(g, "Which one?")
      assertNil(geminiContexts[1], "Gemini kendi bağlamını alır")
    }
    TestRun.test("NaturalPipelineTest.speakerSenMemoryAcrossLines" + suffix) {
      let answers = [
        "ENZO: I saw you.": "ENZO: Seni gördüm.",
        "ENZO: I told you so.": "ENZO: Sana söylemiştim.",
        "ENZO: Stay behind the crates.": "ENZO: Siperin arkasında bekleyin.",
        "ENZO: Where are all of you?": "ENZO: Hepiniz nerdesiniz?",
        "ENZO: Stay behind the barrels.": "ENZO: Varillerin arkasında bekleyin.",
      ]
      let f = fixture(mode, options()) { answers[$0] }
      f.onRead(["ENZO: I saw you."], nil)
      read(f, "ENZO: I told you so.")
      read(f, "ENZO: Stay behind the crates.")
      assertEquals("ENZO: Siperin arkasında bekle.", texts(f).last)
      // "Siz" gözlemi seriyi bozar.
      read(f, "ENZO: Where are all of you?")
      read(f, "ENZO: Stay behind the barrels.")
      assertEquals("ENZO: Varillerin arkasında bekleyin.", texts(f).last)
    }
    TestRun.test("NaturalPipelineTest.packChangeResetsSpeakerMemory" + suffix) {
      let answers = [
        "ENZO: I saw you.": "ENZO: Seni gördüm.",
        "ENZO: I told you so.": "ENZO: Sana söylemiştim.",
        "ENZO: Stay behind the crates.": "ENZO: Siperin arkasında bekleyin.",
      ]
      let f = fixture(mode, options()) { answers[$0] }
      f.p.packLookup = { text in text == "Get down!" ? PackMatch(text: "Yere yat!", packId: "gta-v") : nil }
      f.onRead(["ENZO: I saw you."], nil)
      read(f, "ENZO: I told you so.")
      read(f, "Get down!")
      assertEquals("Yere yat!", texts(f).last)
      read(f, "ENZO: Stay behind the crates.")
      assertEquals("ENZO: Siperin arkasında bekleyin.", texts(f).last)
    }
    TestRun.test("NaturalPipelineTest.inLineSenSizIsAlsoStoredConsistently" + suffix) {
      let f = fixture(mode, options()) { _ in "Seni gördüm, bekleyin." }
      f.onRead(["I saw you, wait here until I come back."], nil)
      assertEquals(["Seni gördüm, bekle."], texts(f))
    }
  }

  private static func assertNil(_ value: String?, _ message: String = "", file: String = #fileID, line: Int = #line) {
    assertNull(value, message, file: file, line: line)
  }
}
