// SPDX-License-Identifier: AGPL-3.0-only
// Doğal Türkçe adımlarının (deyim, hazır cevap, son düzeltme, sen/siz, bağlam, ad koruması) testleri; Kotlin karşılığı yok.
import Foundation

enum IdiomNormalizerTest {
  static func run() {
    TestRun.test("IdiomNormalizerTest.listIsBigEnough") {
      assertTrue(IdiomNormalizer.count >= 100, "kural sayısı \(IdiomNormalizer.count)")
    }
    TestRun.test("IdiomNormalizerTest.idiomsAreReplacedKeepingCaseAndPunctuation") {
      assertEquals("I've got your back.", IdiomNormalizer.apply("I've got your six."))
      assertEquals("Enemies are coming!", IdiomNormalizer.apply("We've got company!"))
      assertEquals("Enemies are coming!", IdiomNormalizer.apply("We’ve got company!"))
      assertEquals("Retreat!", IdiomNormalizer.apply("Fall back!"))
      assertEquals("STAY ALERT!", IdiomNormalizer.apply("STAY FROSTY!"))
      assertEquals("Stay alert, rookie.", IdiomNormalizer.apply("Stay frosty, rookie."))
      assertEquals("Protect me!", IdiomNormalizer.apply("Cover me!"))
      assertEquals("They are easy targets.", IdiomNormalizer.apply("They are sitting ducks."))
      assertEquals("You took a long time.", IdiomNormalizer.apply("Took you long enough."))
      assertEquals("Finally!", IdiomNormalizer.apply("About time!"))
      assertEquals("Okay, retreat!", IdiomNormalizer.apply("Okay, fall back!"))
      assertEquals("Wait for it. When I say so.", IdiomNormalizer.apply("Wait for it. On my mark."))
    }
    TestRun.test("IdiomNormalizerTest.ordinaryTextIsLeftAlone") {
      for line in ["Where are you going?", "I will fall back on my training.", "He will fall back asleep.",
                   "We have company tonight.", "Cover me with a blanket.", "It is about time to leave.",
                   "Stay frostbitten.", "Okay, fall back to the bridge.", "Hold the line, please.",
                   "The heads up display is broken.", "Get down from there."] {
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
                   "Clear, please.", "\"Clear!\"", "Roger that, sir.", "Wait?", "Sorry?", ""] {
        assertNull(StockLines.lookup(line), line)
      }
    }
  }
}

enum TurkishPostEditTest {
  static func run() {
    TestRun.test("TurkishPostEditTest.spacesAndPunctuation") {
      assertEquals("Dur!", TurkishPostEdit.apply("Dur !", source: "Stop!"))
      assertEquals("Gel buraya.", TurkishPostEdit.apply("Gel   buraya  .", source: "Come here."))
      assertEquals("Bekle…", TurkishPostEdit.apply("Bekle …", source: "Wait…"))
      assertEquals("Evet, tamam.", TurkishPostEdit.apply("Evet , tamam .", source: "Yes, okay."))
    }
    TestRun.test("TurkishPostEditTest.sourceEndMarkIsKept") {
      assertEquals("Koş!", TurkishPostEdit.apply("Koş.", source: "Run!"))
      assertEquals("Gerçekten?", TurkishPostEdit.apply("Gerçekten.", source: "Really?"))
      assertEquals("Neden?!", TurkishPostEdit.apply("Neden.", source: "Why?!"))
      assertEquals("Bekle...", TurkishPostEdit.apply("Bekle.", source: "Wait..."))
      assertEquals("Bekle!", TurkishPostEdit.apply("Bekle", source: "Wait!"))
      assertEquals("\"Koş!\"", TurkishPostEdit.apply("\"Koş.\"", source: "\"Run!\""))
      assertEquals("Şimdi. Koş!", TurkishPostEdit.apply("Şimdi. Koş.", source: "Now. Run!"))
    }
    TestRun.test("TurkishPostEditTest.endMarkIsNotForced") {
      // Kaynak düz noktaysa ya da çeviri başka güçlü işaretle bitiyorsa dokunulmaz.
      assertEquals("Koş!", TurkishPostEdit.apply("Koş!", source: "Run."))
      assertEquals("Gerçekten?", TurkishPostEdit.apply("Gerçekten?", source: "Really!"))
      assertEquals("Koş", TurkishPostEdit.apply("Koş", source: "Run"))
      assertEquals("Dur,", TurkishPostEdit.apply("Dur,", source: "Stop!"))
      assertEquals("Nereye gidiyorsun?", TurkishPostEdit.apply("Nereye gidiyorsun?", source: "Where are you going?"))
    }
    TestRun.test("TurkishPostEditTest.quotesFollowTheSource") {
      assertEquals("“Koş!”", TurkishPostEdit.apply("\"Koş!\"", source: "“Run!”"))
      assertEquals("\"Koş!\"", TurkishPostEdit.apply("“Koş!”", source: "\"Run!\""))
      assertEquals("Kratos'u gör.", TurkishPostEdit.apply("Kratos’u gör.", source: "See Kratos's axe."))
      assertEquals("Kratos’u gör.", TurkishPostEdit.apply("Kratos'u gör.", source: "See Kratos’s axe."))
      // Tek (eşleşmeyen) düz tırnak kıvrığa çevrilmez.
      assertEquals("Dedi ki \"koş.", TurkishPostEdit.apply("Dedi ki \"koş.", source: "He said “run."))
    }
    TestRun.test("TurkishPostEditTest.capitalization") {
      assertEquals("Koş!", TurkishPostEdit.apply("koş!", source: "Run!"))
      assertEquals("İyi misin?", TurkishPostEdit.apply("iyi misin?", source: "Are you okay?"))
      assertEquals("- Gel buraya.", TurkishPostEdit.apply("- gel buraya.", source: "- Come here."))
      assertEquals("ENZO: Gel.", TurkishPostEdit.apply("ENZO: gel.", source: "ENZO: Come."))
      // Kaynak küçük harfle başlıyorsa cümlenin devamıdır; rakamla başlayan metne dokunulmaz.
      assertEquals("ve sonra", TurkishPostEdit.apply("ve sonra", source: "and then"))
      assertEquals("3 adam geldi.", TurkishPostEdit.apply("3 adam geldi.", source: "Three men came."))
    }
    TestRun.test("TurkishPostEditTest.emptyAndPlainTextAreStable") {
      assertEquals("", TurkishPostEdit.apply("   ", source: "Run!"))
      assertEquals("Merhaba.", TurkishPostEdit.apply("Merhaba.", source: "Hello."))
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
      assertTrue(ShortLineContext.isShort("Not you."))
      assertTrue(ShortLineContext.isShort("Do it."))
      assertTrue(ShortLineContext.isShort("Him?"))
      assertTrue(ShortLineContext.isShort("ENZO: Him?"))
      assertTrue(ShortLineContext.isShort("It is him."))
      assertFalse(ShortLineContext.isShort("Where are you going?"))
      assertFalse(ShortLineContext.isShort("..."))
      assertFalse(ShortLineContext.isShort(""))
    }
    TestRun.test("ShortLineContextTest.contextSelection") {
      assertEquals("I think Marcus took it.", ShortLineContext.context(for: "Not you.", previous: "I think Marcus took it."))
      assertEquals("Who took it?", ShortLineContext.context(for: "Him?", previous: "ENZO: Who took it?"))
      // Uzun satırın bağlamı yok, önceki satır yok, aynı/uzamış satır bağlam değil.
      assertNull(ShortLineContext.context(for: "Where are you going?", previous: "I think Marcus took it."))
      assertNull(ShortLineContext.context(for: "Not you.", previous: nil))
      assertNull(ShortLineContext.context(for: "Not you.", previous: "  "))
      assertNull(ShortLineContext.context(for: "Not you.", previous: "Not you!"))
      assertNull(ShortLineContext.context(for: "Not you at all.", previous: "Not you."))
      let long = String(repeating: "word ", count: 80)
      let cut = ShortLineContext.context(for: "Not you.", previous: long)
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
      assertEquals("I think Marcus took it. ### Not you.", ContextSplit.combine(context: "I think Marcus took it.", text: "Not you."))
      assertEquals("Wait. ### Hey?", ContextSplit.combine(context: "Wait", text: "Hey?"))
      assertEquals("Sen değil.", ContextSplit.extract("Sanırım Marcus aldı. ### Sen değil.", original: "Not you."))
      assertNull(ContextSplit.extract("Sanırım Marcus aldı. Sen değil.", original: "Not you."))
      assertNull(ContextSplit.extract("A ### B ### C", original: "Not you."))
      assertNull(ContextSplit.extract("Sanırım Marcus aldı. ###", original: "Not you."))
      assertNull(ContextSplit.extract("### Sen değil.", original: "Not you."))
      assertNull(ContextSplit.extract("Önceki. ### " + String(repeating: "a ", count: 12), original: "Not you."))
    }
    TestRun.test("ShortLineContextTest.splitTranslate") {
      var calls: [String] = []
      // Ayraç korunur: kısa satırın çevirisi alınır.
      let ok = ContextSplit.translate("Hi", context: "A.") { text in
        calls.append(text)
        return text == "A. ### Hi" ? "Bir. ### Selam" : nil
      }
      assertEquals("Selam", ok)
      assertEquals(["A. ### Hi"], calls)
      // Ayraç kayıp: kısa satır tek başına çevrilir.
      calls = []
      let lost = ContextSplit.translate("Hi", context: "A.") { text in
        calls.append(text)
        return text == "Hi" ? "Selam" : "Bir selam"
      }
      assertEquals("Selam", lost)
      assertEquals(["A. ### Hi", "Hi"], calls)
      // Ağ yok: tek istek, ikinci deneme yok.
      calls = []
      assertNull(ContextSplit.translate("Hi", context: "A.") { text in calls.append(text); return nil })
      assertEquals(1, calls.count)
      // Bağlam yok ya da metinde ayraç var: doğrudan.
      calls = []
      assertEquals("x", ContextSplit.translate("Hi", context: nil) { text in calls.append(text); return "x" })
      assertEquals(["Hi"], calls)
      calls = []
      _ = ContextSplit.translate("a ### b", context: "A.") { text in calls.append(text); return "x" }
      assertEquals(["a ### b"], calls)
    }
  }
}

enum NameProtectionTest {
  static func run() {
    TestRun.test("NameProtectionTest.midSentenceNamesAreFound") {
      assertEquals(["Marcus", "Black", "Gate"],
                   NameProtection.candidates("Where is Marcus going with the Black Gate key?"))
      assertEquals(["Marcus"], NameProtection.candidates("I told Marcus. Then Marcus left."))
      assertEquals(["Marcus"], NameProtection.candidates("I'm Marcus's friend."))
      assertEquals(["Marcus"], NameProtection.candidates("Wait, Marcus!"))
    }
    TestRun.test("NameProtectionTest.ordinaryCapitalsAreIgnored") {
      for line in ["Marcus is here.", "Yes, Captain.", "THEY KILLED MARCUS!", "He lives in Spring, not in spring.",
                   "See you on Monday.", "Why, Doesn't it work?", "She said, \"Run.\" Then she left.",
                   "He spoke English.", "Hello there.", "Look: Marcus", "- Marcus"] {
        assertEquals([], NameProtection.candidates(line), line)
      }
    }
    TestRun.test("NameProtectionTest.userGlossaryTermsAreSkipped") {
      let glossary = Glossary.of(["Kratos": "Kratos"])
      assertEquals([], NameProtection.candidates("Call Kratos now.", glossary: glossary))
      assertEquals(["Marcus"], NameProtection.candidates("Call Marcus and Kratos now.", glossary: glossary))
    }
    TestRun.test("NameProtectionTest.nameRoundTripKeepsNameAndSuffix") {
      var seen: [String] = []
      let translator = GlossaryTranslator(NameProtection.glossary(for: ["Marcus"]), FunctionTranslator { text in
        seen.append(text)
        return "Sanırım Zarmon'u gördü."
      })
      assertEquals("Sanırım Marcus'u gördü.", translator.translate("I think Marcus saw him."))
      assertEquals(["I think Zarmon saw him."], seen)
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
    TestRun.test("NaturalPipelineTest.idiomIsNormalizedBeforeTheEngineAndResultIsPostEdited" + suffix) {
      var calls: [String] = []
      let f = fixture(mode, options()) { text in calls.append(text); return "düşmanlar geliyor !" }
      f.onRead(["We've got company!"], nil)
      assertEquals(["Enemies are coming!"], calls)
      assertEquals(["Düşmanlar geliyor!"], texts(f))
    }
    TestRun.test("NaturalPipelineTest.geminiKeepsItsOwnInputButIsPostEdited" + suffix) {
      var calls: [String] = []
      let f = fixture(mode, options(engine: "gemini")) { text in calls.append(text); return "düşmanlar geliyor !" }
      f.onRead(["We've got company!"], nil)
      assertEquals(["We've got company!"], calls)
      assertEquals(["Düşmanlar geliyor!"], texts(f))
    }
    TestRun.test("NaturalPipelineTest.engineEndMarkIsRestored" + suffix) {
      let f = fixture(mode, options()) { _ in "Koş." }
      f.onRead(["Run for the exit!"], nil)
      assertEquals(["Koş!"], texts(f))
    }
    TestRun.test("NaturalPipelineTest.shortLineGetsContextAndNamesStayStable" + suffix) {
      var calls: [String] = []
      var contexts: [String?] = []
      let f = fixture(mode, options()) { text in
        calls.append(text)
        contexts.append(TranslationContext.current)
        if text.contains("Zarmon") { return "Sanırım Zarmon aldı." }
        return text == "Not you." ? "Sen değil ." : "Nereye gidiyorsun?"
      }
      f.onRead(["I think Marcus took it."], nil)
      // Ad yer tutucuyla gitti, geri konuldu; ilk satırın bağlamı yok.
      assertEquals(["I think Zarmon took it."], calls)
      assertEquals("Sanırım Marcus aldı.", texts(f).last)
      assertNil(contexts[0])
      // Kısa satır: önceki gösterilen satır bağlam; çeviri son düzeltilir.
      read(f, "Not you.")
      assertEquals("Not you.", calls[1])
      assertEquals("I think Marcus took it.", contexts[1])
      assertEquals("Sen değil.", texts(f).last)
      assertNil(TranslationContext.current, "bağlam iş parçacığında kalmamalı")
      // Bağlamla çevrilen satır önbelleğe girmez: aynı satır başka bağlamla yeniden çevrilir.
      read(f, "Where are you going?")
      read(f, "Not you.")
      assertEquals(4, calls.count)
      assertEquals("Where are you going?", contexts[3])
    }
    TestRun.test("NaturalPipelineTest.oldOrGeminiOrLongLineGetsNoContext" + suffix) {
      var contexts: [String?] = []
      let f = fixture(mode, options()) { _ in contexts.append(TranslationContext.current); return "Tamam." }
      f.onRead(["I think Marcus took it."], nil)
      read(f, "Not you.", after: 20_000)
      assertNil(contexts[1], "önceki satır 15 sn'den eski")
      read(f, "Not me.")
      assertEquals("Not you.", contexts[2])
      read(f, "Where are you going with that?")
      assertNil(contexts[3], "uzun satır")

      var geminiContexts: [String?] = []
      let g = fixture(mode, options(engine: "gemini")) { _ in geminiContexts.append(TranslationContext.current); return "Tamam." }
      g.onRead(["I think Marcus took it."], nil)
      read(g, "Not you.")
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
