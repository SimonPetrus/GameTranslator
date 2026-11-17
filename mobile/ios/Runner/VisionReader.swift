// SPDX-License-Identifier: AGPL-3.0-only
import CoreGraphics
import Foundation
import Vision

/// Karelerde altyazı bölgesini okuyan ve çeviri hattına veren [FrameReader] (Android'deki Engine.readFrame,
/// rows ve buildPipeline'ın karşılığı). Yazı tanıma ML Kit yerine Apple'ın Vision çatısıyla, cihaz üstünde.
final class VisionReader: FrameReader {
  private unowned let engine: Engine
  /// Okuma kuyruğu; okuyucu takılırsa yenisiyle değiştirilir (busyLock altında okunur/yazılır).
  private var queue = DispatchQueue(label: "gt.reader")
  private let translating = DispatchQueue(label: "gt.translate")
  private let busyLock = NSLock()
  private var busy = false
  /// Takılma kurtarmasında artar; eski (takılmış) okumanın bitişi yeni durumu bozmasın diye.
  private var generation = 0
  private var stuck = StuckDetector()
  private var retryLimiter = RetryLimiter()
  /// Son altyazının görüldüğü an (yalnız okuma kuyruğunda); boş ekranda gereksiz yeniden okumayı önler.
  private var lastSubtitleAt: Int64?
  private let scheduler = ReadScheduler()
  private var pipeline: SubtitlePipeline?
  private var region = Region()
  private var language = "en"
  /// Vision'a verilecek tanıma dili; nil: Vision kendi seçsin (kaynak dil bu iOS sürümünde desteklenmiyor).
  private var ocrLanguage: String? = "en-US"
  private var hideButtonHints = true
  private var lastLines: [String] = []
  private var lastBox: TextBox?
  private var ocrTimes: [Int] = []
  private let sink: ServerSink

  init(engine: Engine) {
    self.engine = engine
    sink = ServerSink(server: engine.server)
  }

  // MARK: - FrameReader

  private func currentQueue() -> DispatchQueue {
    busyLock.lock(); defer { busyLock.unlock() }
    return queue
  }

  func rebuild(settings s: Settings) {
    currentQueue().async {
      self.pipeline?.reset()
      self.region = s.region
      self.language = s.sourceLanguage
      self.ocrLanguage = self.resolveOcrLanguage(s.sourceLanguage)
      self.hideButtonHints = s.hideButtonHints
      // Cihaz üstü çeviri (Apple) arka planda hazırlanır: internet koptuğunda yedek olur (Android'deki ML Kit gibi).
      let local = AppleTranslator(source: s.sourceLanguage, target: s.targetLanguage) { level, text in self.engine.log(level, text) }
      self.translating.async { _ = local.prepare() }
      let online: TextTranslator?
      switch s.engine {
      case "deepl":
        online = s.deepLKey.trimmingCharacters(in: .whitespaces).isEmpty
          ? GoogleGtxTranslator(source: s.sourceLanguage, target: s.targetLanguage)
          : FallbackTranslator(DeepLTranslator(key: s.deepLKey, source: s.sourceLanguage, target: s.targetLanguage),
                               GoogleGtxTranslator(source: s.sourceLanguage, target: s.targetLanguage))
      case "gemini":
        let google = GoogleGtxTranslator(source: s.sourceLanguage, target: s.targetLanguage)
        online = s.geminiKey.trimmingCharacters(in: .whitespaces).isEmpty || s.targetLanguage != "tr"
          ? google
          : FallbackTranslator(GeminiTranslator(key: s.geminiKey) { level, text in self.engine.log(level, text) }, google)
      case "mlkit":
        online = nil
      default:
        online = GoogleGtxTranslator(source: s.sourceLanguage, target: s.targetLanguage)
      }
      let engineTranslator: TextTranslator = online.map { FallbackTranslator($0, local) } ?? local
      // Sözlüğün ek kuralları Türkçeye göredir; bilgisayarda da yalnız İngilizce→Türkçe için çalışır.
      let glossary = s.sourceLanguage == "en" && s.targetLanguage == "tr" ? s.parsedGlossary() : Glossary.EMPTY
      if !glossary.isEmpty { self.engine.log(2, "terim sözlüğü: \(glossary.count) terim") }
      let withGlossary: TextTranslator = glossary.isEmpty ? engineTranslator : GlossaryTranslator(glossary, engineTranslator)
      // Baştaki konuşmacı işareti ("- ", ">>") motorlara gönderilmez; hangi motor çevirirse çevirsin korunur.
      // Konuşmacı adı ("ENZO: ", "MINE GUARD: ") çevrilmez: satırdan satıra tutarsız çıkıyordu.
      let translator = PrefixTranslator(SpeakerNameTranslator(withGlossary))
      let engine = self.engine
      let built = SubtitlePipeline(translator: translator, sink: self.sink, translateQueue: self.translating)
      built.onPair = { source, translation in
        engine.lastSource = source
        engine.lastTranslation = translation
        engine.translatedCount += 1
        engine.log(2, "çeviri: \"\(source.replacingOccurrences(of: "\n", with: " "))\" → \"\(translation)\"")
        engine.notifyChanged()
      }
      built.onTranslateFailed = { source in
        engine.log(1, "çevrilemedi: \"\(source.replacingOccurrences(of: "\n", with: " "))\"")
      }
      // Oyun paketi: satır paketteyse motora gidilmez. Bulanık arama yalnız son tam eşleşmenin paketinde (oynanan oyun).
      if s.packsEnabled && PackTranslation.applies(s.sourceLanguage, s.targetLanguage) {
        let library = Packs.shared.library
        library.setPinned(s.packChoice.isEmpty ? nil : s.packChoice)
        // Paketler çeviri kuyruğunda ilk istekten önce açılır (~1 sn; okuma beklemez).
        self.translating.async {
          let started = DispatchTime.now().uptimeNanoseconds
          let infos = library.infos
          engine.log(2, "oyun paketleri: \(infos.count) paket, \(infos.reduce(0) { $0 + $1.entries }) satır (\((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000) ms)")
        }
        built.packLookup = { text in PackTranslation.match(library, text) }
        built.onPackHit = { source, match in
          engine.packHits += 1
          engine.packGame = library.scopeTitle ?? match.packId ?? ""
          engine.log(2, "paket (\(match.packId ?? "?")): \"\(source.replacingOccurrences(of: "\n", with: " "))\"")
        }
      }
      built.onReadText = { text in
        if text != engine.lastRead {
          engine.lastRead = text
          engine.notifyChanged()
        }
      }
      self.scheduler.reset()
      self.lastLines = []
      self.lastBox = nil
      self.pipeline = built
    }
  }

  func reset() {
    currentQueue().async {
      self.region = Store.shared.settings.region
      self.scheduler.reset()
      self.retryLimiter.reset()
      self.pipeline?.reset()
    }
  }

  func offer(_ frame: Frame) {
    let now = SubtitleStabilizer.monotonicMillis()
    busyLock.lock()
    stuck.frame(at: now)
    var recovered: StuckDetector.Reason?
    if let reason = stuck.check(at: now) {
      // Takılan okuma bırakılır: yeni kuyruk, boş durum; eski okuma dönerse yeni durumu bozmaz (generation).
      generation += 1
      busy = false
      queue = DispatchQueue(label: "gt.reader.\(generation)")
      recovered = reason
    }
    // Önceki kare hâlâ okunuyorsa bu kare atlanır; okuma kareleri biriktirmez.
    if busy { busyLock.unlock(); reportRecovery(recovered); return }
    busy = true
    stuck.readStarted(at: now)
    let token = generation
    let target = queue
    busyLock.unlock()
    reportRecovery(recovered)
    if recovered != nil {
      // Takılan kuyruğa atılmış ayar yeniden kurulumu hiç çalışmayabilir: güncel ayarlarla yeni kuyrukta yeniden kurulur
      // (bölge, dil, hat). Ardından oku işi aynı seri kuyrukta sıraya girer.
      rebuild(settings: Store.shared.settings)
      target.async {
        self.retryLimiter.reset()
        self.lastSubtitleAt = nil
      }
    }
    target.async {
      defer {
        self.busyLock.lock()
        if token == self.generation {
          self.busy = false
          self.stuck.readFinished(at: SubtitleStabilizer.monotonicMillis())
        }
        self.busyLock.unlock()
      }
      self.read(frame, token: token)
    }
  }

  private func reportRecovery(_ reason: StuckDetector.Reason?) {
    guard let reason else { return }
    let text: String
    switch reason {
    case .busyTooLong: text = "okuyucu takıldı (okuma çok uzun sürdü); sıfırlandı"
    case .noResult: text = "okuyucu takıldı (karelere sonuç gelmiyor); sıfırlandı"
    }
    engine.log(1, text)
  }

  /// Kaynak dil kodunu Vision'ın desteklediği bir kimliğe çevirir. Desteklenmiyorsa tek bir uyarı yazılır ve
  /// İngilizceye (o da yoksa Vision'ın kendi seçimine) dönülür; her karede hata verilmez.
  private func resolveOcrLanguage(_ code: String) -> String? {
    let probe = VNRecognizeTextRequest()
    probe.recognitionLevel = .accurate
    let supported = (try? probe.supportedRecognitionLanguages()) ?? []
    if supported.isEmpty { return LanguageCodes.visionCandidates(code).first }
    if let chosen = LanguageCodes.visionLanguage(code, supported: supported) { return chosen }
    let fallback = LanguageCodes.visionLanguage("en", supported: supported)
    engine.log(1, "yazı tanıma bu iOS sürümünde \"\(code)\" dilini desteklemiyor; \(fallback ?? "otomatik dil") kullanılıyor")
    return fallback
  }

  // MARK: - Okuma

  /// Takılma kurtarmasından sonra eski bir okumanın sonucu atılır (kilit altında kontrol edilir).
  private func isCurrent(_ token: Int) -> Bool {
    busyLock.lock(); defer { busyLock.unlock() }
    return token == generation
  }

  private func read(_ frame: Frame, token: Int) {
    guard isCurrent(token) else { return }
    guard let pipeline, let image = frame.cgImage() else { return }
    let r = region
    let fullWidth = frame.width, fullHeight = frame.height
    let cropX = min(max(Int(r.left * Double(fullWidth)), 0), fullWidth - 2)
    let cropY = min(max(Int(r.top * Double(fullHeight)), 0), fullHeight - 2)
    let w = min(max(Int((r.right - r.left) * Double(fullWidth)), 1), fullWidth - cropX)
    let h = min(max(Int((r.bottom - r.top) * Double(fullHeight)), 1), fullHeight - cropY)
    guard let crop = image.cropping(to: CGRect(x: cropX, y: cropY, width: w, height: h)) else { return }

    if let signature = Self.signature(crop), scheduler.canReuse(signature) {
      if isCurrent(token) { pipeline.onRead(lastLines, lastBox) }
      return
    }

    // İlk okuma tüm bölgede; sonuç yoksa ya da güvensizse sınırlı sıklıkta, ortalanmış bandı büyüterek bir kez daha.
    guard let first = recognize(crop, offsetX: 0, offsetY: 0, scale: 1, timed: true) else { return }
    guard isCurrent(token) else { return }
    var selected = ReadingSelector.select(first, width: w, height: h)
    let clock = SubtitleStabilizer.monotonicMillis()
    let band = ReadingSelector.retryBand(width: w, height: h)
    // Boş ekranda yeniden okuma yok; büyütme genişliği sınırlı (çok geniş bölgede küçülür ya da atlanır).
    if ReadingSelector.shouldRetry(rawCount: first.count, selected: selected, lastSubtitleAt: lastSubtitleAt, now: clock),
       let scale = ReadingSelector.retryScale(bandWidth: band.width),
       retryLimiter.allow(at: clock) {
      if let part = image.cropping(to: CGRect(x: cropX + band.x, y: cropY + band.y, width: band.width, height: band.height)),
         let big = Self.upscaled(part, factor: scale),
         let again = recognize(big, offsetX: band.x, offsetY: band.y, scale: scale, timed: false) {
        guard isCurrent(token) else { return }
        let retried = ReadingSelector.select(again, width: w, height: h)
        if ReadingSelector.isBetter(retried, than: selected) { selected = retried }
      }
    }
    let pieces: [Piece] = selected.map { Piece(text: $0.text, left: $0.left, top: $0.top, right: $0.right, bottom: $0.bottom) }
    var (lines, box) = Self.rows(pieces, cropX: cropX, cropY: cropY, fullWidth: fullWidth, fullHeight: fullHeight)
    if hideButtonHints {
      // Oyun düğmesi yazıları ("RESUME BA", "SKIP") çeviriye karışmasın.
      lines = lines.map(ButtonHints.strip).filter { !$0.isEmpty }
      if lines.isEmpty { box = nil }
    }
    if let box, !pieces.isEmpty {
      // Satır yüksekliği: okunan satırların ortanca yüksekliği, ekran yüksekliğine oranla.
      let heights = pieces.map { $0.bottom - $0.top }.sorted()
      sink.remember(box, line: Double(heights[heights.count / 2]) / Double(fullHeight),
                    characters: lines.reduce(0) { $0 + $1.count })
    }
    // Kurtarmadan önce başlamış eski okumanın bayat satırları hatta ve ortak duruma gitmez.
    guard isCurrent(token) else { return }
    if !lines.isEmpty { lastSubtitleAt = clock }
    lastLines = lines
    lastBox = box
    pipeline.onRead(lines, box)
  }

  /// Görüntüyü okur; her çağrıda taze bir istek kurulur. Parçalar bölge pikselinde (sol üstten) döner;
  /// [offsetX]/[offsetY]/[scale] büyütülmüş bir alt bandın bölgedeki yerini belirtir. Okuma hatasında nil.
  private func recognize(_ image: CGImage, offsetX: Int, offsetY: Int, scale: Double, timed: Bool) -> [TextObservation]? {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if let ocrLanguage { request.recognitionLanguages = [ocrLanguage] }
    do {
      let started = DispatchTime.now().uptimeNanoseconds
      try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
      if timed {
        ocrTimes.append(Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000))
        if ocrTimes.count >= 100 {
          let sorted = ocrTimes.sorted()
          engine.log(2, "ölçüm: yazı tanıma \(image.width)x\(image.height) ortanca \(sorted[sorted.count / 2]) ms, en çok \(sorted.last!) ms")
          ocrTimes.removeAll()
        }
      }
    } catch {
      engine.log(1, "yazı tanıma başarısız: \(error.localizedDescription)")
      return nil
    }
    return (request.results ?? []).compactMap { (observation) -> TextObservation? in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      let text = candidate.string.trimmingCharacters(in: .whitespaces)
      if text.isEmpty { return nil }
      // Vision kutusu 0–1 ve sol alttan; piksel ve sol üstten koordinata çevrilir.
      let b = observation.boundingBox
      let p = ReadingSelector.pixels(minX: Double(b.minX), minY: Double(b.minY), maxX: Double(b.maxX), maxY: Double(b.maxY),
                                     imageWidth: image.width, imageHeight: image.height,
                                     offsetX: offsetX, offsetY: offsetY, scale: scale)
      return TextObservation(text: text, confidence: Double(candidate.confidence),
                             left: p.left, top: p.top, right: p.right, bottom: p.bottom)
    }
  }

  /// Görüntüyü [factor] kat büyütür (küçük yazı için yeniden okuma).
  static func upscaled(_ image: CGImage, factor: Double) -> CGImage? {
    let width = Int((Double(image.width) * factor).rounded()), height = Int((Double(image.height) * factor).rounded())
    guard width > 0, height > 0 else { return nil }
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }

  struct Piece {
    let text: String
    let left: Int, top: Int, right: Int, bottom: Int
  }

  /// Tanınan satırları yukarıdan aşağı sıralar, aynı hizadakileri birleştirir; yazının tüm ekrandaki yerini verir
  /// (Android'deki Engine.rows ile aynı kural).
  static func rows(_ input: [Piece], cropX: Int, cropY: Int, fullWidth: Int, fullHeight: Int) -> ([String], TextBox?) {
    let pieces = input.sorted { $0.top < $1.top }
    guard !pieces.isEmpty else { return ([], nil) }
    var grouped: [[Piece]] = []
    for piece in pieces {
      if let reference = grouped.last?.first,
         abs((piece.top + piece.bottom) / 2 - (reference.top + reference.bottom) / 2)
           < max(reference.bottom - reference.top, piece.bottom - piece.top) / 2 {
        grouped[grouped.count - 1].append(piece)
      } else {
        grouped.append([piece])
      }
    }
    let lines = grouped.map { row in row.sorted { $0.left < $1.left }.map(\.text).joined(separator: " ") }
    let left = pieces.map(\.left).min()!, top = pieces.map(\.top).min()!
    let right = pieces.map(\.right).max()!, bottom = pieces.map(\.bottom).max()!
    let box = TextBox(left: Double(cropX + left) / Double(fullWidth), top: Double(cropY + top) / Double(fullHeight),
                      right: Double(cropX + right) / Double(fullWidth), bottom: Double(cropY + bottom) / Double(fullHeight))
    return (lines, box)
  }

  /// Bölgenin 32×8 küçültülmüş parlaklık özeti; iki karenin aynı olup olmadığını anlamak için.
  static func signature(_ image: CGImage) -> [UInt8]? {
    let width = 32, height = 8
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
      guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
      context.interpolationQuality = .medium
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return nil }
    return (0..<(width * height)).map { i in
      let r = Int(pixels[i * 4]), g = Int(pixels[i * 4 + 1]), b = Int(pixels[i * 4 + 2])
      return UInt8((r * 3 + g * 6 + b) / 10)
    }
  }
}

/// Çevirinin gittiği yer: TV sunucusu. Okunan yazının yeri ve satır yüksekliği de gider: TV "cover" yerleşiminde
/// çeviriyi oyunun altyazısının alanına, onun boyunda sığdırır ve alanı opak bantla örter.
private final class ServerSink: SubtitleSink {
  private let server: SubtitleServer
  private let lock = NSLock()
  /// Son okumaların kutusu → (satır yüksekliği, okunan İngilizce metnin karakter sayısı); hat aynı kutuyu çeviriyle
  /// birlikte geri verir.
  private var lines: [(box: TextBox, line: Double, characters: Int)] = []

  init(server: SubtitleServer) { self.server = server }

  func remember(_ box: TextBox, line: Double, characters: Int) {
    lock.lock(); defer { lock.unlock() }
    if let last = lines.last, last.box == box { return }
    lines.append((box, line, characters))
    if lines.count > 32 { lines.removeFirst(lines.count - 32) }
  }

  func show(_ text: String, durationMs: Int, box: TextBox?, replaces: Bool) {
    var line: Double?
    var source = box
    if let box {
      lock.lock()
      let known = lines.last(where: { $0.box == box })
      lock.unlock()
      line = known?.line
      if let known, known.characters > 0 {
        source = Self.widened(box, ratio: Double(text.count) / Double(known.characters))
      }
    }
    server.sendSubtitle(text, durationMs: durationMs, box: box, replaces: replaces, source: source, line: line)
  }

  /// Türkçe çoğu zaman İngilizceden uzundur: TV çeviriyi oyunun altyazısının genişliğine sığdıramayınca iki satıra
  /// bölüp küçültüyordu. Alan, çevirinin uzunluk oranında (%8 payla) iki yana genişletilir; ekranın %90'ını ve
  /// kenarları (%5) aşmaz. Çeviri daha kısaysa alan küçültülmez (oyunun altyazısı tamamen örtülsün).
  static func widened(_ box: TextBox, ratio: Double) -> TextBox {
    let width = box.right - box.left
    guard width > 0, ratio.isFinite else { return box }
    let target = min(0.9, width * ratio * 1.08)
    guard target > width else { return box }
    let center = (box.left + box.right) / 2
    var left = center - target / 2
    var right = center + target / 2
    // Bir kenara dayanırsa öbür yana kaydırılır.
    if left < 0.05 { right += 0.05 - left; left = 0.05 }
    if right > 0.95 { left -= right - 0.95; right = 0.95 }
    return TextBox(left: max(0.05, left), top: box.top, right: min(0.95, right), bottom: box.bottom)
  }

  func clear() { server.clear() }
}
