// SPDX-License-Identifier: AGPL-3.0-only
// Android'deki core/SubtitlePipeline.kt'nin Swift portu; onunla birebir aynı tutulmalıdır.
import Foundation

/// Metni çevirir; bloklar. Çevrilemezse null.
/// (Kotlin'de çevirmenin fırlattığı istisna hatta null sayılır; Swift'te çevirmen hata fırlatmaz, hatayı null'a çevirir.)
protocol TextTranslator {
  func translate(_ text: String) -> String?
}

/// Kotlin'deki `fun interface` lambdası: kapanışı çevirmen olarak kullanır.
struct FunctionTranslator: TextTranslator {
  private let body: (String) -> String?

  init(_ body: @escaping (String) -> String?) { self.body = body }

  func translate(_ text: String) -> String? { body(text) }
}

/// Çevirinin gittiği yer (TV sunucusu ve telefondaki ekran).
protocol SubtitleSink {
  func show(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool)
  func clear()
}

/// Oyun paketinden bulunan satır (Android'deki GamePacks.kt: `data class PackMatch(val text: String, val packId: String? = null)`).
/// Paketler: GamePacks.swift (GamePackLibrary), arama: PackTranslation.match.
struct PackMatch: Equatable, Sendable {
  let text: String
  let packId: String?

  init(text: String, packId: String? = nil) {
    self.text = text
    self.packId = packId
  }
}

/// Kotlin'deki `java.util.concurrent.Executor` karşılığı: verilen işi (şimdi ya da sonra) çalıştırır.
typealias TranslateExecutor = (@escaping @Sendable () -> Void) -> Void

/// Hattın ayarlara bağlı seçenekleri (testte varsayılan: hepsi kapalı).
struct PipelineOptions {
  /// Hedef dil Türkçeyse ve satır zaten Türkçeyse motora gidilmez.
  var skipTurkishSource = false
  /// Diskteki kalıcı önbellek (yoksa yalnız bellek önbelleği).
  var cache: DiskTranslationCache?
  var engineId = ""
  var model = ""
  var sourceLanguage = ""
  var targetLanguage = ""
  var rulesVersion = ""
  /// Kullanıcının terim sözlüğü (ad koruması bu terimlere dokunmaz); uygulama kurar.
  var glossary: Glossary = Glossary.EMPTY

  func cacheKey(_ text: String) -> String {
    DiskTranslationCache.key(engine: engineId, model: model, source: sourceLanguage, target: targetLanguage,
                                   rules: rulesVersion, text: text)
  }
}

/// Okunan altyazıyı çevirip gönderen hat: gürültü temizliği → kararlılık → önbellek → oyun paketi/çeviri → TV.
/// Windows'taki SubtitlePipeline.cs'in çekirdeği (bekletme ve dublaj yok).
/// [onRead] tek bir iş parçacığından çağrılır; çeviri [translateExecutor]'da yapılır, sonuçlar kilit altında işlenir.
final class SubtitlePipeline: @unchecked Sendable {
  /// Satır ekranda durdukça çeviri de durur; kalkınca TV'den silinir.
  static let ON_SCREEN_MS = 15000
  private static let CACHE_SIZE = 300
  /// Yeni hatların seçeneklerini ayarlardan kuran kanca (uygulama kurar; testte nil).
  nonisolated(unsafe) static var optionsProvider: (() -> PipelineOptions)?

  /// Çevirisi geldiğinde ekrandan kalkmış satırın TV'de kalacağı süre.
  static func readingTime(_ text: String) -> Int { min(8000, max(2000, 1200 + 60 * text.utf16.count)) }

  private let translator: TextTranslator
  private let sink: SubtitleSink
  private let translateExecutor: TranslateExecutor
  private let stabilizer: SubtitleStabilizer

  // Kotlin'deki `synchronized` yeniden girilebilir; doğrudan çalıştıran yürütücüyle (testler) kilitlenmesin diye
  // NSRecursiveLock kullanılır.
  private let lock = NSRecursiveLock()
  private let cache = LruCache(capacity: SubtitlePipeline.CACHE_SIZE)
  private var latest = 0
  /// Ekranda duran satırın numarası; satır kalktıysa -1.
  private var onScreen = -1
  private var lastShownSource: String?
  /// [lastShownSource]'un gösterildiği an ([contextClock] saniyesi); kısa satırın bağlamı yeterince yeni mi bakılır.
  private var lastShownAt: Double?
  /// Doğal Türkçe adımlarının (sen/siz belleği) oturum durumu; oyun/paket değişince ve [reset]te sıfırlanır.
  private let address: AddressMemory
  private let nameMemory = NameMemory()
  private var lastPackId: String?
  /// Kısa satır bağlamının zaman ölçüsü (saniye); testte sahte saat verilir.
  var contextClock: () -> Double = { ProcessInfo.processInfo.systemUptime }
  /// Seçili motor Gemini iken Gemini zincirde beklemedeyse true: satırı büyük olasılıkla başka motor (DeepL/Google) çevireceği için
  /// deyim sadeleştirme, ad koruması ve kısa satır bağlamı uygulanır. Varsayılan: hiçbir zaman (bugünkü davranış).
  var geminiBypassed: () -> Bool = { false }

  /// Seçenekler (Türkçe satırı atlama, kalıcı önbellek); varsayılanı [optionsProvider]'dan gelir.
  var options: PipelineOptions {
    get { lock.lock(); defer { lock.unlock() }; return _options }
    set { lock.lock(); defer { lock.unlock() }; _options = newValue }
  }
  private var _options = PipelineOptions()
  /// Zaten hedef dilde olduğu için motora gönderilmeyen satır sayısı.
  var skippedAsTarget: Int { lock.lock(); defer { lock.unlock() }; return _skipped }
  private var _skipped = 0

  /// Çeviri gösterildiğinde (kaynak, çeviri).
  var onPair: ((String, String) -> Void)?
  /// Çeviri başarısız olduğunda kaynak satır.
  var onTranslateFailed: ((String) -> Void)?
  /// Okunan ve temizlenen ham metin (boş olabilir); tanılama için.
  var onReadText: ((String) -> Void)?
  /// Oyun paketi: kararlı satırın hazır Türkçesi (yoksa null). Çeviri motorundan önce, çeviri iş parçacığında bakılır;
  /// bulunursa motora gidilmez ve paketteki metin olduğu gibi gösterilir (sözlük de uygulanmaz).
  var packLookup: ((String) throws -> PackMatch?)? {
    get { lock.lock(); defer { lock.unlock() }; return _packLookup }
    set { lock.lock(); defer { lock.unlock() }; _packLookup = newValue }
  }
  private var _packLookup: ((String) throws -> PackMatch?)?
  /// Paketten gösterilen satır (kaynak, paket).
  var onPackHit: ((String, PackMatch) -> Void)?
  /// Bir satır gösterildiğinde (kaynak, çeviri, çeviriyi yapan: "pack", "stock", "cache", "google", "deepl",
  /// "gemini", "apple" ya da bilinmiyorsa "", önceki satırın düzeltilmiş hâli mi); altyazı geçmişi içindir.
  var onShown: ((String, String, String, Bool) -> Void)?
  /// Paketten gösterilen satır sayısı.
  var packHits: Int { lock.lock(); defer { lock.unlock() }; return _packHits }
  private var _packHits = 0

  /// [translateQueue] seri bir kuyruk olmalıdır (Android'deki tek iş parçacıklı çeviri yürütücüsü).
  convenience init(
    translator: TextTranslator, sink: SubtitleSink, translateQueue: DispatchQueue,
    stabilizer: SubtitleStabilizer = SubtitleStabilizer()
  ) {
    self.init(translator: translator, sink: sink, translateExecutor: { translateQueue.async(execute: $0) },
              stabilizer: stabilizer)
  }

  init(
    translator: TextTranslator, sink: SubtitleSink, translateExecutor: @escaping TranslateExecutor,
    stabilizer: SubtitleStabilizer = SubtitleStabilizer()
  ) {
    self.translator = translator
    self.sink = sink
    self.translateExecutor = translateExecutor
    self.stabilizer = stabilizer
    self.address = AddressMemory()
    _options = SubtitlePipeline.optionsProvider?() ?? PipelineOptions()
  }

  /// Bir karenin okuması: [lines] yukarıdan aşağı satırlar, [box] yazının ekrandaki yeri.
  func onRead(_ lines: [String], _ box: TextBox?) {
    let text = lines.map { OcrNoise.clean($0) }.filter { !$0.isEmpty }.joined(separator: "\n")
    onReadText?(text)
    lock.lock()
    defer { lock.unlock() }
    let action = stabilizer.feed(text)
    switch action.kind {
    case .none:
      break
    case .clear:
      onScreen = -1
      sink.clear()
    case .restore:
      guard let source = action.text else { return }
      latest += 1
      let number = latest
      onScreen = number
      if let cached = cache.get(key(source)) {
        show(source, cached, box, SubtitlePipeline.ON_SCREEN_MS, replaces: revises(source), origin: "cache")
      } else {
        request(number, source, box)
      }
    case .translate:
      guard let source = action.text else { return }
      latest += 1
      let number = latest
      onScreen = number
      if let cached = cache.get(key(source)) { deliver(number, source, cached, box, origin: "cache") } else { request(number, source, box) }
    }
  }

  private func request(_ number: Int, _ source: String, _ box: TextBox?) {
    // Kısa satırın bağlamı: bu an gösterilmiş olan satır ve ne zaman gösterildiği (kilit altında okunur).
    let previous = lastShownSource
    let previousAt = lastShownAt
    translateExecutor { [self] in
      let options = self.options
      // Satır zaten Türkçeyse motora gidilmez; sonuç kaynağıyla aynı olduğundan eskiden olduğu gibi gösterilmez.
      if options.skipTurkishSource && TurkishDetect.isTurkish(source) {
        lock.lock()
        defer { lock.unlock() }
        _skipped += 1
        deliver(number, source, source, box, origin: "")
        return
      }
      let packed: PackMatch? = (try? packLookup?(source)).flatMap { KotlinText.isBlank($0.text) ? nil : $0 }
      // İki satırlık altyazı tek cümledir; çevirmene tek satır olarak gider.
      let oneLine = KotlinText.string(source.utf16.map { $0 == 0x0A ? 0x20 : $0 })
      // Doğal Türkçe adımları yalnız İngilizce→Türkçe; Gemini bağlamı kendisi anlar (deyim, bağlam, ad adımları yok).
      let natural = packed == nil && options.sourceLanguage == "en" && options.targetLanguage == "tr"
      let gemini = options.engineId == "gemini" && !geminiBypassed()
      let stock: String? = natural ? StockLines.lookup(oneLine) : nil
      var context: String? = nil
      if natural && !gemini && stock == nil, let previousAt {
        let age = contextClock() - previousAt
        if age >= 0 && age <= ShortLineContext.maxAgeSeconds { context = ShortLineContext.context(for: oneLine, previous: previous) }
      }
      // Hazır cevap diske yazılmaz; bağlamla çevrilen satır da yazılmaz (aynı satır başka bağlamda başka çıkar).
      let cacheable = stock == nil && context == nil
      let diskKey = cacheable && options.cache != nil ? options.cacheKey(oneLine) : nil
      let stored: String? = packed == nil ? diskKey.flatMap { options.cache?.get($0) } : nil
      FallbackSignal.reset()
      var translated: String?
      var memoryStep = false
      var origin = ""
      if let packed {
        translated = KotlinText.trim(packed.text)
        origin = "pack"
      } else if let stock {
        translated = stock
        origin = "stock"
      } else if let stored {
        translated = stored
        memoryStep = natural
        origin = "cache"
      } else {
        translated = translateEngine(oneLine, natural: natural, gemini: gemini, context: context, options: options)
        memoryStep = natural
        origin = SubtitlePipeline.engineOrigin(options.engineId, fallbackAnswered: FallbackSignal.marked,
                                               answeredBy: FallbackSignal.answeredBy)
      }
      // Yedek motorun çevirisi gösterilir ama asıl motorun anahtarıyla diske yazılmaz.
      if packed == nil, stored == nil, !FallbackSignal.marked, let diskKey, let translated, !translated.isEmpty {
        options.cache?.set(diskKey, translated)
      }
      // Konuşmacı belleği diske yazılan metne değil gösterilene uygulanır (oturuma bağlı olduğu için önbelleğe girmez).
      if memoryStep, let current = translated, !current.isEmpty {
        translated = address.apply(current, speaker: AddressMemory.speaker(of: oneLine))
      }
      lock.lock()
      defer { lock.unlock() }
      if let packed = packed {
        _packHits += 1
        // Oyun/paket değişti: konuşmacıların sen/siz belleği geçerli değil.
        if let id = packed.packId, id != lastPackId {
          address.reset()
          nameMemory.reset()
          lastPackId = id
        }
        onPackHit?(source, packed)
      }
      guard let translated = translated, !translated.isEmpty else {
        if number == onScreen { stabilizer.forgetSent() }
        onTranslateFailed?(source)
        return
      }
      if context == nil { cache.set(key(source), translated) }
      deliver(number, source, translated, box, origin: origin)
    }
  }

  /// Çeviriyi hangi kaynağın verdiği (en iyi tahmin): yedek motor cevap verdiyse Gemini/DeepL'in yerine Google,
  /// Google'ın yerine cihaz üstü (Apple) yazılır; ayrımı yapılamayan durumda tahmin edilir.
  /// [answeredBy] (zincir ya da yedek cevap verenin kimliğini bildirdiyse) tahminin yerine geçer.
  static func engineOrigin(_ engineId: String, fallbackAnswered: Bool, answeredBy: String? = nil) -> String {
    if let answeredBy, !answeredBy.isEmpty { return answeredBy }
    switch engineId {
    case "mlkit": return "apple"
    case "gemini", "deepl": return fallbackAnswered ? "google" : engineId
    case "google": return fallbackAnswered ? "apple" : "google"
    default: return engineId
    }
  }

  /// Tek seferlik çeviri (ek okuma alanı): kararlılık, ekran sırası, TV'ye gönderim ve konuşmacı belleği yok; oyun paketi,
  /// hazır cevap, önbellek ve motor ana hatla aynı yoldan gider. Çeviri iş parçacığında çalışır; çağıran bloklanır.
  /// Çevrilemezse ya da süre dolarsa metin nil.
  func translateOnce(_ source: String, timeoutSeconds: Double = 15) -> (text: String?, origin: String) {
    let semaphore = DispatchSemaphore(value: 0)
    let box = OnceResult()
    translateExecutor { [self] in
      box.value = performOnce(source)
      semaphore.signal()
    }
    if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut { return (nil, "") }
    return box.value
  }

  private func performOnce(_ source: String) -> (text: String?, origin: String) {
    let options = self.options
    if options.skipTurkishSource && TurkishDetect.isTurkish(source) { return (source, "") }
    let packed: PackMatch? = (try? packLookup?(source)).flatMap { KotlinText.isBlank($0.text) ? nil : $0 }
    if let packed { return (KotlinText.trim(packed.text), "pack") }
    let oneLine = KotlinText.string(source.utf16.map { $0 == 0x0A ? 0x20 : $0 })
    let natural = options.sourceLanguage == "en" && options.targetLanguage == "tr"
    if natural, let stock = StockLines.lookup(oneLine) { return (stock, "stock") }
    let diskKey: String? = options.cache != nil ? options.cacheKey(oneLine) : nil
    if let diskKey, let stored = options.cache?.get(diskKey) { return (stored, "cache") }
    FallbackSignal.reset()
    let gemini = options.engineId == "gemini" && !geminiBypassed()
    guard let translated = translateEngine(oneLine, natural: natural, gemini: gemini, context: nil, options: options),
          !translated.isEmpty else { return (nil, "") }
    let fallback = FallbackSignal.marked
    if !fallback, let diskKey { options.cache?.set(diskKey, translated) }
    return (translated, SubtitlePipeline.engineOrigin(options.engineId, fallbackAnswered: fallback,
                                                      answeredBy: FallbackSignal.answeredBy))
  }

  /// Motor çağrısı ve (İngilizce→Türkçe ise) çevrilmeden önce/sonra adımlar: deyim sadeleştirme, ad koruması, kısa satır
  /// bağlamı, Türkçe son düzeltme, satır içi sen/siz tutarlılığı. Çevrilemezse nil.
  // [gemini]: PipelineOptions.engineId zaten etkin motordur (Engine: anahtarsız ya da hedef Türkçe değilse "google"); tek kaynak.
  private func translateEngine(_ line: String, natural: Bool, gemini: Bool, context: String?,
                               options: PipelineOptions) -> String? {
    if !natural {
      return translator.translate(line).map { KotlinText.trim($0) }
    }
    var input = line
    var engine: TextTranslator = translator
    if !gemini {
      input = IdiomNormalizer.apply(input)
      let names = NameProtection.candidates(input, glossary: options.glossary, known: nameMemory.snapshot)
      nameMemory.remember(names)
      if !names.isEmpty { engine = GlossaryTranslator(NameProtection.glossary(for: names), translator) }
    }
    TranslationContext.set(context)
    defer { TranslationContext.set(nil) }
    guard let raw = engine.translate(input).map({ KotlinText.trim($0) }), !raw.isEmpty else { return nil }
    let edited = TurkishPolish.apply(raw, source: line)
    return AddressForm.harmonizeLine(edited)
  }

  /// Kilit altında çağrılır. Yerine yenisi gelmiş satırın geç kalan çevirisi gösterilmez.
  private func deliver(_ number: Int, _ source: String, _ translated: String, _ box: TextBox?, origin: String) {
    if number != latest { return }
    // Çeviri kaynağıyla neredeyse aynıysa metin zaten hedef dildedir.
    if !stabilizer.shouldSend(source, translated) { return }
    let duration = number == onScreen ? SubtitlePipeline.ON_SCREEN_MS : SubtitlePipeline.readingTime(translated)
    show(source, translated, box, duration, replaces: revises(source), origin: origin)
  }

  /// Kilit altında çağrılır. [source], az önce gösterilen satırın uzamış ya da düzelmiş okuması mı (TV öncekinin
  /// yerine koyar). Konuşmacı işareti/adı atılıp tek satır olarak da bakılır: ad bozuk okunmuş olabilir.
  /// Önbellekten, hazır cevaptan, paketten ve geri gelen satırlardan gelen çeviriler de aynı yoldan geçer.
  private func revises(_ source: String) -> Bool {
    guard let previous = lastShownSource else { return false }
    if TextMatch.isRevision(source, previous) { return true }
    let a = SubtitlePipeline.bareText(source)
    let b = SubtitlePipeline.bareText(previous)
    return !a.isEmpty && !b.isEmpty && TextMatch.isSimilar(a, b, 0.8)
  }

  /// Konuşmacı işareti ve adı atılmış, tek satır, sadeleştirilmiş metin.
  private static func bareText(_ text: String) -> String {
    let oneLine = KotlinText.string(text.utf16.map { $0 == 0x0A ? 0x20 : $0 })
    let (_, afterPrefix) = SpeakerPrefix.split(oneLine)
    let (_, afterName) = SpeakerName.split(afterPrefix)
    return TextMatch.normalize(afterName)
  }

  private func show(_ source: String, _ translated: String, _ box: TextBox?, _ duration: Int, replaces: Bool, origin: String) {
    lastShownSource = source
    lastShownAt = contextClock()
    sink.show(translated, durationMs: duration, box: box, replaces: replaces)
    onPair?(source, translated)
    onShown?(source, translated, origin, replaces)
  }

  private func key(_ source: String) -> UTF16Text { KotlinText.units(TextMatch.normalize(source)) }

  func reset() {
    lock.lock()
    defer { lock.unlock() }
    latest += 1
    onScreen = -1
    lastShownSource = nil
    lastShownAt = nil
    lastPackId = nil
    address.reset()
    nameMemory.reset()
    if stabilizer.reset().kind == .clear { sink.clear() }
  }
}

/// [SubtitlePipeline.translateOnce] sonucunu çeviri kuyruğundan çağırana taşır.
private final class OnceResult: @unchecked Sendable {
  var value: (text: String?, origin: String) = (nil, "")
}

/// Kotlin'deki erişim sıralı `LinkedHashMap` + `removeEldestEntry`: en uzun süredir dokunulmayan kayıt atılır.
/// Anahtarlar UTF-16 birimleridir (Kotlin String eşitliği; Swift String'in kanonik eşdeğerliği değil).
private final class LruCache {
  private let capacity: Int
  private var values: [UTF16Text: String] = [:]
  /// En eskiden en yeniye erişim sırası.
  private var order: [UTF16Text] = []

  init(capacity: Int) { self.capacity = capacity }

  func get(_ key: UTF16Text) -> String? {
    guard let value = values[key] else { return nil }
    touch(key)
    return value
  }

  func set(_ key: UTF16Text, _ value: String) {
    if values.updateValue(value, forKey: key) != nil { touch(key) } else { order.append(key) }
    if values.count > capacity {
      let eldest = order.removeFirst()
      values[eldest] = nil
    }
  }

  private func touch(_ key: UTF16Text) {
    if let index = order.firstIndex(of: key) { order.remove(at: index) }
    order.append(key)
  }
}

/// Hangi karede yazı tanıma yapılacağını seçer: bölge değişmediyse son okuma yeniden kullanılır.
/// Oyun süresinin çoğunda bölge boştur ya da değişmez; telefonda bu pil ve ısı demektir (Windows'taki ReadScheduler).
final class ReadScheduler {
  private let changeThreshold: Int
  private let maxReuse: Int
  private var previous: [UInt8]?
  private var reused = 0

  init(changeThreshold: Int = 16, maxReuse: Int = 20) {
    self.changeThreshold = changeThreshold
    self.maxReuse = maxReuse
  }

  /// true ise bölge değişmedi; son okuma geçerli.
  func canReuse(_ signature: [UInt8]) -> Bool {
    let before = previous
    previous = signature
    if let before = before, reused < maxReuse, !changed(before, signature) {
      reused += 1
      return true
    }
    reused = 0
    return false
  }

  func reset() {
    previous = nil
    reused = 0
  }

  private func changed(_ a: [UInt8], _ b: [UInt8]) -> Bool {
    if a.count != b.count { return true }
    for i in a.indices where abs(Int(a[i]) - Int(b[i])) > changeThreshold { return true }
    return false
  }
}
