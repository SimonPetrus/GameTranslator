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
  /// [rows]: birden çok konuşmalı satırda her satırın (konuşmanın) oyundaki kutusu, sırası ve sayısı metnin
  /// satırlarıyla aynı ([TurnRows]); yoksa nil. Varsayılanı rows'u yok sayar.
  func show(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool, rows: [TextBox]?)
  func clear()
}

extension SubtitleSink {
  func show(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool, rows: [TextBox]?) {
    show(text, durationMs: durationMs, box: box, replaces: replaces)
  }
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
  /// Yakın geçmişte satır başında görülen konuşmacı adları (küçük harfli, en yenisi sonda; kilit altında):
  /// satır ortasındaki "…mine. Devin: No." ancak bu adlardansa ayrı konuşma sayılır ([SpeakerTurns.split]).
  private var recentSpeakers: [String] = []
  private static let RECENT_SPEAKERS = 32
  private var lastPackId: String?
  /// TV'ye hattın en son gönderdiği satır (numarası, çevirisi, kutusu, satır kutuları, süresi, gönderildiği an); kalkınca ya da sıfırlanınca nil.
  private var displayed: (number: Int, text: String, box: TextBox?, rows: [TextBox]?, durationMs: Int, at: Double)?
  /// TV'deki gösterim her değiştiğinde (satır, temizleme, ek gösterim, sıfırlama) artar.
  private var screenMark = 0
  private var resets = 0
  /// Kısa satır bağlamının ve ekrandaki satırın kalan süresinin zaman ölçüsü (saniye); testte sahte saat verilir.
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
  func onRead(_ lines: [String], _ box: TextBox?) { onRead(lines, box, lineBoxes: nil) }

  /// [lineBoxes]: her satırın ekrandaki yeri ([lines] ile aynı sıra ve sayıda; tutmuyorsa yok sayılır). Birden çok
  /// konuşmalı satırda TV'ye her konuşmanın kutusu gider ([TurnRows]).
  func onRead(_ lines: [String], _ box: TextBox?, lineBoxes: [TextBox]?) {
    let aligned = box != nil && lineBoxes?.count == lines.count
    var kept: [String] = []
    var keptBoxes: [TextBox] = []
    for (index, line) in lines.enumerated() {
      let cleaned = OcrNoise.clean(line)
      if cleaned.isEmpty { continue }
      kept.append(cleaned)
      if aligned, let lineBoxes { keptBoxes.append(lineBoxes[index]) }
    }
    let text = kept.joined(separator: "\n")
    let layout = aligned ? ReadLayout(lines: kept, boxes: keptBoxes) : nil
    onReadText?(text)
    lock.lock()
    defer { lock.unlock() }
    let action = stabilizer.feed(text)
    if Diag.on { diagStabilize(text, action) }
    switch action.kind {
    case .none:
      break
    case .clear:
      onScreen = -1
      displayed = nil
      screenMark += 1
      sink.clear()
    case .restore:
      guard let source = action.text else { return }
      latest += 1
      let number = latest
      onScreen = number
      if let cached = cache.get(key(source)) {
        Diag.emit("pipeline") { ["what": .string("path"), "number": .int(number), "path": .string("memory"), "source": .string(source)] }
        show(number, source, cached, box, layout, SubtitlePipeline.ON_SCREEN_MS, replaces: revises(source), origin: "cache")
      } else {
        request(number, source, box, layout)
      }
    case .translate:
      guard let source = action.text else { return }
      latest += 1
      let number = latest
      onScreen = number
      if let cached = cache.get(key(source)) {
        Diag.emit("pipeline") { ["what": .string("path"), "number": .int(number), "path": .string("memory"), "source": .string(source)] }
        deliver(number, source, cached, box, layout, origin: "cache")
      } else {
        request(number, source, box, layout)
      }
    }
  }

  /// Tanı kaydı: son yazılan kararlılık kararı (kilit altında); aynı karar her karede yeniden yazılmaz.
  private var diagLastDecision = ""

  /// Kilit altında, yalnız kayıt açıkken: kararlılık kararı (bekletildi / aynı satır / boş / çevir / geri geldi / temizle).
  private func diagStabilize(_ read: String, _ action: StabilizerAction) {
    let kind: String
    switch action.kind {
    case .none: kind = read.isEmpty ? "empty" : (read == lastShownSource ? "same" : "hold")
    case .translate: kind = "translate"
    case .clear: kind = "clear"
    case .restore: kind = "restore"
    }
    let key = kind + "\u{1F}" + read
    if action.kind == .none && key == diagLastDecision { return }
    diagLastDecision = key
    let opens = action.kind == .translate || action.kind == .restore
    let number = opens ? latest + 1 : latest
    Diag.emit("pipeline") {
      ["what": .string("stabilize"), "action": .string(kind), "read": .string(read), "source": DiagValue.optional(action.text),
       "number": .int(number)]
    }
  }

  private func request(_ number: Int, _ source: String, _ box: TextBox?, _ layout: ReadLayout?) {
    // Kısa satırın bağlamı: bu an gösterilmiş olan satır ve ne zaman gösterildiği (kilit altında okunur).
    let previous = lastShownSource
    let previousAt = lastShownAt
    let known = Set(recentSpeakers)
    translateExecutor { [self] in
      let options = self.options
      // Tanı kaydı açıksa izlenen adımlar (kapalıyken nil; hiçbir şey kurulmaz).
      let trace: DiagTrace? = Diag.on ? DiagTrace() : nil
      let started = trace == nil ? 0 : DispatchTime.now().uptimeNanoseconds
      // Satır zaten Türkçeyse motora gidilmez; sonuç kaynağıyla aynı olduğundan eskiden olduğu gibi gösterilmez.
      if options.skipTurkishSource && TurkishDetect.isTurkish(source) {
        Diag.emit("pipeline") { ["what": .string("path"), "number": .int(number), "path": .string("turkish-source"), "source": .string(source)] }
        lock.lock()
        defer { lock.unlock() }
        _skipped += 1
        deliver(number, source, source, box, layout, origin: "")
        return
      }
      let packed: PackMatch? = (try? packLookup?(source)).flatMap { KotlinText.isBlank($0.text) ? nil : $0 }
      rememberSpeakers(SpeakerTurns.speakers(in: source))
      // Birden çok konuşma (etiketli satırlar): her konuşma TV'de kendi satırında; tek satıra düzleştirilmez.
      let turns = packed == nil ? SpeakerTurns.split(source, known: known) : []
      if turns.count > 1 {
        let result = translateTurns(turns, options: options, remember: true, trace: trace)
        if let trace {
          Diag.emit("pipeline") {
            SubtitlePipeline.diagPath(number: number, source: source, path: result.origin == "cache" ? "disk" : "engine",
                                      origin: result.origin, options: options, trace: trace, started: started,
                                      translated: result.text, turns: turns)
          }
        }
        lock.lock()
        defer { lock.unlock() }
        guard let translated = result.text, !translated.isEmpty else {
          Diag.emit("pipeline") { ["what": .string("failed"), "number": .int(number), "source": .string(source), "onScreen": .bool(number == onScreen)] }
          if number == onScreen { stabilizer.forgetSent() }
          onTranslateFailed?(source)
          return
        }
        cache.set(key(source), translated)
        deliver(number, source, translated, box, layout, origin: result.origin)
        return
      }
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
        translated = translateEngine(oneLine, natural: natural, gemini: gemini, context: context, options: options, trace: trace)
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
        if let trace, translated != current { trace.steps.append("address-memory") }
      }
      if let trace {
        if context != nil { trace.steps.append("context") }
        let path = packed != nil ? "pack" : stock != nil ? "stock" : stored != nil ? "disk" : "engine"
        let fallback = FallbackSignal.marked
        let answered = FallbackSignal.answeredBy
        let finalText = translated
        Diag.emit("pipeline") {
          var fields = SubtitlePipeline.diagPath(number: number, source: source, path: path, origin: origin, options: options,
                                                 trace: trace, started: started, translated: finalText, turns: [])
          fields["packId"] = DiagValue.optional(packed?.packId)
          fields["context"] = DiagValue.optional(context)
          fields["fallbackAnswered"] = DiagValue.bool(path == "engine" && fallback)
          fields["answeredBy"] = path == "engine" ? DiagValue.optional(answered) : DiagValue.null
          fields["gemini"] = DiagValue.bool(gemini)
          fields["natural"] = DiagValue.bool(natural)
          return fields
        }
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
        Diag.emit("pipeline") { ["what": .string("failed"), "number": .int(number), "source": .string(source), "onScreen": .bool(number == onScreen)] }
        if number == onScreen { stabilizer.forgetSent() }
        onTranslateFailed?(source)
        return
      }
      if context == nil { cache.set(key(source), translated) }
      deliver(number, source, translated, box, layout, origin: origin)
    }
  }

  /// Tanı kaydı: çevirinin hangi yoldan geldiği (paket, hazır cevap, disk önbelleği, motor), motor, istek sayısı, süre,
  /// uygulanan adımlar, motorun ham cevabı ve son metin.
  static func diagPath(number: Int, source: String, path: String, origin: String, options: PipelineOptions, trace: DiagTrace,
                       started: UInt64, translated: String?, turns: [String]) -> DiagFields {
    let ms = Int((DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000)
    var fields: DiagFields = ["what": .string("translate"), "number": .int(number), "source": .string(source), "path": .string(path)]
    if !turns.isEmpty { fields["turns"] = DiagValue.strings(turns) }
    fields["origin"] = DiagValue.string(origin)
    fields["engine"] = DiagValue.string(options.engineId)
    fields["model"] = DiagValue.string(options.model)
    fields["requests"] = DiagValue.int(trace.calls)
    fields["ms"] = DiagValue.int(ms)
    fields["steps"] = DiagValue.strings(trace.steps)
    if !trace.names.isEmpty { fields["protectedNames"] = DiagValue.strings(trace.names) }
    fields["raw"] = DiagValue.optional(trace.raw)
    fields["text"] = DiagValue.optional(translated)
    return fields
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
      let trace: DiagTrace? = Diag.on ? DiagTrace() : nil
      let started = trace == nil ? 0 : DispatchTime.now().uptimeNanoseconds
      let value = performOnce(source, trace: trace)
      box.value = value
      if let trace {
        let options = self.options
        Diag.emit("extra") {
          var fields = SubtitlePipeline.diagPath(number: -1, source: source, path: value.origin.isEmpty ? "none" : value.origin,
                                                 origin: value.origin, options: options, trace: trace, started: started,
                                                 translated: value.text, turns: [])
          fields["what"] = DiagValue.string("translate-once")
          return fields
        }
      }
      semaphore.signal()
    }
    if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
      Diag.emit("extra") { ["what": .string("translate-timeout"), "seconds": .double(timeoutSeconds), "source": .string(source)] }
      return (nil, "")
    }
    return box.value
  }

  private func performOnce(_ source: String, trace: DiagTrace? = nil) -> (text: String?, origin: String) {
    let options = self.options
    if options.skipTurkishSource && TurkishDetect.isTurkish(source) { return (source, "") }
    let packed: PackMatch? = (try? packLookup?(source)).flatMap { KotlinText.isBlank($0.text) ? nil : $0 }
    if let packed { return (KotlinText.trim(packed.text), "pack") }
    lock.lock()
    let known = Set(recentSpeakers)
    lock.unlock()
    let turns = SpeakerTurns.split(source, known: known)
    if turns.count > 1 { return translateTurns(turns, options: options, remember: false, trace: trace) }
    let oneLine = KotlinText.string(source.utf16.map { $0 == 0x0A ? 0x20 : $0 })
    let natural = options.sourceLanguage == "en" && options.targetLanguage == "tr"
    if natural, let stock = StockLines.lookup(oneLine) { return (stock, "stock") }
    let diskKey: String? = options.cache != nil ? options.cacheKey(oneLine) : nil
    if let diskKey, let stored = options.cache?.get(diskKey) { return (stored, "cache") }
    FallbackSignal.reset()
    let gemini = options.engineId == "gemini" && !geminiBypassed()
    guard let translated = translateEngine(oneLine, natural: natural, gemini: gemini, context: nil, options: options, trace: trace),
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
                               options: PipelineOptions, trace: DiagTrace? = nil) -> String? {
    if !natural {
      trace?.calls += 1
      let plain = translator.translate(line).map { KotlinText.trim($0) }
      trace?.raw = plain
      return plain
    }
    var input = line
    var engine: TextTranslator = translator
    if !gemini {
      input = IdiomNormalizer.apply(input)
      if let trace, input != line { trace.steps.append("idiom") }
      let names = NameProtection.candidates(input, glossary: options.glossary, known: nameMemory.snapshot)
      nameMemory.remember(names)
      if !names.isEmpty { engine = GlossaryTranslator(NameProtection.glossary(for: names), translator) }
      if let trace, !names.isEmpty {
        trace.steps.append("names")
        trace.names.append(contentsOf: names)
      }
    }
    TranslationContext.set(context)
    defer { TranslationContext.set(nil) }
    trace?.calls += 1
    guard let raw = engine.translate(input).map({ KotlinText.trim($0) }), !raw.isEmpty else { return nil }
    trace?.raw = raw
    let edited = TurkishPolish.apply(raw, source: line)
    let harmonized = AddressForm.harmonizeLine(edited)
    if let trace {
      if edited != raw { trace.steps.append("polish") }
      if harmonized != edited { trace.steps.append("address-form") }
    }
    return harmonized
  }

  /// Birden çok konuşmalı altyazı ([SpeakerTurns]): her konuşma kendi satırında çevrilir, satırlar "\n" ile birleşir
  /// (TV satır sonunu gösterir). Disk önbelleğinin anahtarı satır sonlu metindir: tek satıra düzleştirilmiş eski birleşik
  /// çeviriler geri gelmez. Hazır cevap ve kısa satır bağlamı bu yolda yoktur. [remember]: konuşmacı belleği uygulanır
  /// (ana hat). Çevrilemezse metin nil.
  private func translateTurns(_ turns: [String], options: PipelineOptions, remember: Bool,
                              trace: DiagTrace? = nil) -> (text: String?, origin: String) {
    let natural = options.sourceLanguage == "en" && options.targetLanguage == "tr"
    let gemini = options.engineId == "gemini" && !geminiBypassed()
    let diskKey: String? = options.cache != nil ? options.cacheKey(turns.joined(separator: "\n")) : nil
    var parts: [String]?
    var origin = ""
    if let diskKey, let stored = options.cache?.get(diskKey) {
      let lines = SpeakerTurns.lines(stored)
      if lines.count == turns.count {
        parts = lines
        origin = "cache"
      }
    }
    if parts == nil {
      FallbackSignal.reset()
      parts = translateTurnsEngine(turns, natural: natural, gemini: gemini, options: options, trace: trace)
      origin = SubtitlePipeline.engineOrigin(options.engineId, fallbackAnswered: FallbackSignal.marked,
                                             answeredBy: FallbackSignal.answeredBy)
      // Yedek motorun çevirisi asıl motorun anahtarıyla diske yazılmaz.
      if let done = parts, !FallbackSignal.marked, let diskKey { options.cache?.set(diskKey, done.joined(separator: "\n")) }
    }
    guard var result = parts, result.count == turns.count else { return (nil, "") }
    if remember && natural {
      for i in result.indices { result[i] = address.apply(result[i], speaker: AddressMemory.speaker(of: turns[i])) }
    }
    return (result.joined(separator: "\n"), origin)
  }

  /// Konuşmaların motor çevirisi. Baştaki tire/">>" ve büyük harfli ad ([SpeakerPrefix], [SpeakerName]) ayrılıp olduğu
  /// gibi geri konur; gövdeler tek istekte, satır satır ("\n") gider. Motor satır sayısını korumazsa (satır sonlarını
  /// yuttuysa) her gövde ayrı istekle çevrilir. İngilizce→Türkçe adımları ([translateEngine] ile aynı) gövde başına
  /// uygulanır. Çevrilemezse nil; dönen dizi [turns] ile aynı boydadır.
  private func translateTurnsEngine(_ turns: [String], natural: Bool, gemini: Bool, options: PipelineOptions,
                                    trace: DiagTrace? = nil) -> [String]? {
    var heads: [String] = []
    var bodies: [String] = []
    for turn in turns {
      let (prefix, afterPrefix) = SpeakerPrefix.split(turn)
      let (name, body) = SpeakerName.split(afterPrefix)
      heads.append(prefix + name)
      bodies.append(body)
    }
    let wanted = bodies.indices.filter { !KotlinText.isBlank(bodies[$0]) }
    var inputs = wanted.map { bodies[$0] }
    var engine: TextTranslator = translator
    if natural && !gemini {
      inputs = inputs.map { IdiomNormalizer.apply($0) }
      let known = nameMemory.snapshot
      var names: [String] = []
      for input in inputs {
        for name in NameProtection.candidates(input, glossary: options.glossary, known: known) where !names.contains(name) {
          names.append(name)
        }
      }
      nameMemory.remember(names)
      if !names.isEmpty { engine = GlossaryTranslator(NameProtection.glossary(for: names), translator) }
      if let trace, !names.isEmpty {
        trace.steps.append("names")
        trace.names.append(contentsOf: names)
      }
    }
    TranslationContext.set(nil)
    var outputs: [String] = []
    if inputs.count > 1 {
      // Motor hiç çeviremediyse gövde gövde yeniden denenmez (boşa istek).
      trace?.calls += 1
      guard let raw = engine.translate(inputs.joined(separator: "\n")) else { return nil }
      trace?.raw = raw
      let lines = SpeakerTurns.lines(raw)
      if lines.count == inputs.count { outputs = lines } else { trace?.steps.append("turn-lines-mismatch") }
    }
    if outputs.isEmpty {
      for input in inputs {
        trace?.calls += 1
        guard let raw = engine.translate(input).map({ KotlinText.trim($0) }), !raw.isEmpty else { return nil }
        outputs.append(raw)
      }
    }
    // Yalnız işaretten oluşan konuşma ("-") olduğu gibi kalır.
    var result = heads.map { KotlinText.trim($0) }
    for (k, index) in wanted.enumerated() {
      var text = outputs[k]
      if natural { text = AddressForm.harmonizeLine(TurkishPolish.apply(text, source: bodies[index])) }
      result[index] = heads[index] + text
    }
    return result
  }

  /// Kilit altında çağrılır. Yerine yenisi gelmiş satırın geç kalan çevirisi gösterilmez.
  private func deliver(_ number: Int, _ source: String, _ translated: String, _ box: TextBox?, _ layout: ReadLayout?,
                       origin: String) {
    if number != latest {
      Diag.emit("pipeline") { ["what": .string("deliver"), "result": .string("stale"), "number": .int(number), "latest": .int(latest)] }
      return
    }
    // Çeviri kaynağıyla neredeyse aynıysa metin zaten hedef dildedir.
    if !stabilizer.shouldSend(source, translated) {
      Diag.emit("pipeline") {
        ["what": .string("deliver"), "result": .string("same-as-source"), "number": .int(number), "text": .string(translated)]
      }
      return
    }
    let duration = number == onScreen ? SubtitlePipeline.ON_SCREEN_MS : SubtitlePipeline.readingTime(translated)
    show(number, source, translated, box, layout, duration, replaces: revises(source), origin: origin)
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

  /// Kilit altında çağrılır. [layout] [source]'un okumasıysa ve satırlar konuşmalara ayrılabiliyorsa her satırın kutusu
  /// da gider (önbellekten, paketten ya da motordan gelen çeviride aynı kural; satır sayısı tutmazsa gitmez).
  private func show(_ number: Int, _ source: String, _ translated: String, _ box: TextBox?, _ layout: ReadLayout?,
                    _ duration: Int, replaces: Bool, origin: String) {
    lastShownSource = source
    let now = contextClock()
    lastShownAt = now
    let rows: [TextBox]? = box == nil ? nil : layout.flatMap {
      TurnRows.rows(source: source, layout: $0, translated: translated, known: Set(recentSpeakers))
    }
    displayed = (number: number, text: translated, box: box, rows: rows, durationMs: duration, at: now)
    screenMark += 1
    Diag.emit("pipeline") {
      var fields: DiagFields = ["what": .string("show"), "number": .int(number), "source": .string(source), "text": .string(translated)]
      fields["origin"] = DiagValue.string(origin)
      fields["durationMs"] = DiagValue.int(duration)
      fields["replaces"] = DiagValue.bool(replaces)
      fields["box"] = DiagValue.box(box)
      fields["layoutLines"] = layout.map { DiagValue.strings($0.lines) } ?? DiagValue.null
      fields["rows"] = rows.map { DiagRead.boxes($0) } ?? DiagValue.null
      return fields
    }
    sink.show(translated, durationMs: duration, box: box, replaces: replaces, rows: rows)
    onPair?(source, translated)
    onShown?(source, translated, origin, replaces)
  }

  /// Kilit altında çağrılır. Bellek önbelleği anahtarı: sadeleştirilmiş metin; birden çok konuşmalı okumada konuşma sayısı
  /// da eklenir (aynı sözcüklerin tek paragraf çevirisi satırlı okumaya dönmesin). Tek konuşmada anahtar değişmez.
  private func key(_ source: String) -> UTF16Text {
    let base = KotlinText.units(TextMatch.normalize(source))
    let turns = SpeakerTurns.split(source, known: Set(recentSpeakers)).count
    return turns > 1 ? base + KotlinText.units("\u{1F}\(turns)") : base
  }

  /// Satır başında görülen konuşmacı adlarını yakın geçmişe yazar (kilidi kendisi alır).
  private func rememberSpeakers(_ names: [String]) {
    if names.isEmpty { return }
    lock.lock()
    defer { lock.unlock() }
    for name in names {
      recentSpeakers.removeAll { $0 == name }
      recentSpeakers.append(name)
    }
    if recentSpeakers.count > SubtitlePipeline.RECENT_SPEAKERS {
      recentSpeakers.removeFirst(recentSpeakers.count - SubtitlePipeline.RECENT_SPEAKERS)
    }
  }

  /// Hattın kaç kez sıfırlandığı (durdurma, bölge ya da ayar değişimi).
  var resetCount: Int { lock.lock(); defer { lock.unlock() }; return resets }

  /// Hattın dışından kısa bir gösterim (ek okuma alanı): TV'ye gider, hattın ekrandaki satırı unutulmaz.
  /// Hat [resetCount] okunduktan sonra sıfırlandıysa (durdurma) gösterilmez ve nil döner; yoksa dönen işaret,
  /// gösterim bitince [resumeAfterAside]'a verilir.
  func showAside(_ text: String, durationMs: Int, unlessResetSince resetsBefore: Int) -> Int? {
    lock.lock()
    defer { lock.unlock() }
    guard resets == resetsBefore else {
      Diag.emit("extra") {
        ["what": .string("aside"), "shown": .bool(false), "reason": .string("pipeline-reset"), "resets": .int(resets),
         "resetsBefore": .int(resetsBefore)]
      }
      return nil
    }
    screenMark += 1
    Diag.emit("extra") {
      ["what": .string("aside"), "shown": .bool(true), "text": .string(text), "durationMs": .int(durationMs), "mark": .int(screenMark)]
    }
    sink.show(text, durationMs: durationMs, box: nil, replaces: false)
    return screenMark
  }

  /// Ek gösterim bitti: o arada TV'de başka bir şey gösterilmediyse (yeni satır, temizleme, sıfırlama, başka ek gösterim)
  /// ve hattın son gösterdiği satır oyunda hâlâ ekrandaysa, o satır kendi süresinden kalanla yeniden gönderilir.
  /// Kalan süre [RESUME_MIN_MS]'den azsa gönderilmez (satırın TV'deki süresi zaten dolmuştu). Gönderildiyse true.
  @discardableResult
  func resumeAfterAside(_ mark: Int) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard mark == screenMark, let current = displayed, current.number == onScreen, current.number == latest else {
      Diag.emit("extra") {
        let reason = mark != screenMark ? "screen-changed" : displayed == nil ? "nothing-displayed" : "line-gone"
        return ["what": .string("resume"), "resumed": .bool(false), "reason": .string(reason)]
      }
      return false
    }
    let elapsed = Int(((contextClock() - current.at) * 1000).rounded())
    let remaining = current.durationMs - max(0, elapsed)
    guard remaining >= SubtitlePipeline.RESUME_MIN_MS else {
      Diag.emit("extra") { ["what": .string("resume"), "resumed": .bool(false), "reason": .string("expired"), "remainingMs": .int(remaining)] }
      return false
    }
    Diag.emit("extra") { ["what": .string("resume"), "resumed": .bool(true), "text": .string(current.text), "remainingMs": .int(remaining)] }
    screenMark += 1
    sink.show(current.text, durationMs: remaining, box: current.box, replaces: false, rows: current.rows)
    return true
  }

  /// Ek gösterimden sonra geri gelen satırın en kısa kalan süresi (TV de 1 sn'den kısa gösterim yapmaz).
  static let RESUME_MIN_MS = 1000

  func reset() {
    lock.lock()
    defer { lock.unlock() }
    latest += 1
    resets += 1
    Diag.emit("pipeline") { ["what": .string("reset"), "resets": .int(resets)] }
    diagLastDecision = ""
    onScreen = -1
    displayed = nil
    screenMark += 1
    lastShownSource = nil
    lastShownAt = nil
    lastPackId = nil
    recentSpeakers.removeAll()
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
