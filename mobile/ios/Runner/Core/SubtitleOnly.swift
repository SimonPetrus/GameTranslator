// SPDX-License-Identifier: AGPL-3.0-only
// "Yalnız altyazıyı çevir" (yalnız iOS'ta; Kotlin karşılığı yok): okunan bölgedeki altyazı olmayan yazıları (tabela,
// gösterge, görev metni, menü) blok seçiminden önce ayıklar. Saf mantık: zaman damgası girer, karar çıkar (Vision, saat
// ve iş parçacığı yok). İlke: ŞÜPHEDE ÇEVİR — gerçek altyazıyı kaçırmak fazladan bir tabelayı çevirmekten kötüdür.
// Altyazı bandı, TV'ye gönderilen altyazıların okunduğu yerden zamanla öğrenilir. Bant öğrenilene kadar yalnız kesin
// kurallar çalışır: menü/sayfa bloğu, ekrana dağılmış çok parça, ekran kenarına dayalı yazı, uzun süre değişmeyen yazı.
// Ek okuma alanı (kullanıcının bilerek seçtiği alan) ve otomatik alan taraması bu süzgece girmez.
import Foundation

/// Öğrenilmiş altyazı bandı; tam kareye oranla (0–1), sol üstten.
struct SubtitleBand: Equatable {
  enum Layout: Equatable {
    /// Altyazı ekranın ortasına hizalı (çoğu oyun).
    case centered
    /// Altyazı sola yaslı: satırlar aynı sol kenardan başlar ([SubtitleBand.leftEdge]).
    case left
    /// Kararsız: yatay konum kuralı uygulanmaz.
    case mixed
  }

  var top: Double
  var bottom: Double
  /// Altyazının tipik tek satır yüksekliği (tam kare yüksekliğine oranla).
  var lineHeight: Double
  var layout: Layout
  /// Sola yaslı altyazının sol kenarı (yalnız [layout] sola yaslıyken anlamlı).
  var leftEdge: Double
  /// Bandın dayandığı altyazı sayısı.
  var samples: Int

  func contains(_ y: Double) -> Bool { y >= top && y <= bottom }
}

/// Süzgecin bir karede attığı parça ve nedeni.
struct SubtitleOnlyDrop: Equatable {
  let observation: TextObservation
  let reason: SubtitleOnlyReason
}

enum SubtitleOnlyReason: Equatable {
  /// Çok satırlı, sola hizalı, kısa satırlı blok (duraklatma menüsü, envanter, ayarlar): o karede çeviri yok.
  case menu
  /// Ekranın büyük kısmına yayılmış çok sayıda parça (harita, sayfa): o karede çeviri yok.
  case scattered
  /// Ekranın sol/sağ kenarına dayalı yazı (görev metni, ipucu, harita adı).
  case edge
  /// Konumu ve metni uzun süre değişmeyen yazı (gösterge, görev metni).
  case unchanging
  /// Bant öğrenildikten sonra: bantta ama altyazının yatay hizasında değil.
  case offCenter
  /// Bant öğrenildikten sonra: satır yüksekliği altyazınınkinden çok farklı (dev tabela, başlık, minik rakam).
  case lineHeight
  /// Bant öğrenildikten sonra: bandın dışında kısa, eğik/güvensiz ya da tek sözcük BÜYÜK HARF yazı (dünya içi tabela).
  case sign
  /// Bant öğrenildikten sonra: bandın tamamen dışında ve ortalı konuşma/cümle değil.
  case outsideBand

  var code: String {
    switch self {
    case .menu: return "menu"
    case .scattered: return "scattered"
    case .edge: return "edge"
    case .unchanging: return "static"
    case .offCenter: return "off-center"
    case .lineHeight: return "line-height"
    case .sign: return "world-sign"
    case .outsideBand: return "outside-band"
    }
  }
}

/// Bir karenin süzgeç sonucu.
struct SubtitleOnlyOutcome {
  /// Kalan parçalar (girdideki sırayla; güveni düşük parçalar dokunulmadan geçer, seçim onları kendisi eler).
  var kept: [TextObservation] = []
  var drops: [SubtitleOnlyDrop] = []
  /// Kare bütünüyle menü/sayfa sayıldı.
  var wholeFrame = false
}

/// Okuma alanının tam karedeki yeri: parça pikseli (alan içinde, sol üstten) → tam kareye oran.
struct SubtitleOnlyFrame: Equatable {
  var cropX: Int
  var cropY: Int
  var width: Int
  var height: Int

  func x(_ px: Double) -> Double { (Double(cropX) + px) / Double(max(width, 1)) }
  func y(_ px: Double) -> Double { (Double(cropY) + px) / Double(max(height, 1)) }

  func box(_ list: [TextObservation]) -> TextBox {
    var left = Int.max, top = Int.max, right = Int.min, bottom = Int.min
    for o in list {
      left = min(left, o.left)
      top = min(top, o.top)
      right = max(right, o.right)
      bottom = max(bottom, o.bottom)
    }
    if list.isEmpty { return TextBox(left: 0, top: 0, right: 0, bottom: 0) }
    return TextBox(left: x(Double(left)), top: y(Double(top)), right: x(Double(right)), bottom: y(Double(bottom)))
  }
}

/// [SubtitleOnlyFilter.noteShown]'un sonucu (tanı kaydı ve TV kutusu için).
struct SubtitleOnlyShown: Equatable {
  enum Learning: Equatable {
    /// Gösterilen satırın okuması bulunamadı (demo, çok eski okuma): öğrenmeye katılmadı.
    case unmatched
    /// Örnek eklendi; bant değişmedi ya da henüz öğrenilmedi.
    case sample
    /// Bant ilk kez öğrenildi.
    case learned
    /// Bant kaydı (oyun ya da altyazı yeri değişti): yeniden öğrenildi.
    case relearned
    /// Örnek bandın dışındaydı; kayma kanıtı birikiyor.
    case outside
  }

  var learning: Learning
  var sample: TextBox?
  var lineHeight: Double?
  var outsideRun: Int
  var bandChanged: Bool
}

struct SubtitleOnlyFilter {
  // MARK: - Sabitler (gerçek cihaz kaydına göre ayarlanacak)

  /// Bandın öğrenilmesi için gereken, birbirine yakın gönderilmiş altyazı sayısı.
  static let LEARN_MIN = 3
  /// En çok bu kadar örnek tutulur (en yenileri).
  static let MAX_SAMPLES = 12
  /// Örneklerin dikey ortası ortanca örneğinkinden en çok bu kadar uzaksa aynı bantta sayılır.
  static let CLUSTER_SPAN = 0.12
  /// Band, örneklerin üstüne ve altına bu kadar tipik satır payı alır.
  static let BAND_PAD_LINES = 1.0
  /// Yerleşim kararı (ortalı / sola yaslı) için örneklerin en az bu oranı uymalı.
  static let LAYOUT_SHARE = 2.0 / 3.0
  /// Satırın yatay ortası ekran ortasından en çok bu kadar uzaksa ortalı sayılır.
  static let CENTER_TOLERANCE = 0.12
  /// Yatay ortası bundan kenara yakın yazı ekran kenarına dayalıdır (AutoRegionFinder ile aynı eşik).
  static let EDGE_CENTER = AutoRegionFinder.EDGE_CENTER
  /// Sola yaslı bantta satırın sol kenarı öğrenilen kenara en çok bu kadar uzak olabilir.
  static let LEFT_EDGE_TOLERANCE = 0.04
  /// Sola yaslı yerleşim kararı: örneklerin sol kenarları ortancaya bu kadar yakın olmalı.
  static let LEFT_SAMPLE_SPREAD = 0.03
  /// Parçanın tek satır yüksekliği tipik altyazınınkinin bu aralığının dışındaysa altyazı değildir.
  static let MIN_HEIGHT_FACTOR = 0.6
  static let MAX_HEIGHT_FACTOR = 1.7
  /// Tabela: en çok bu kadar sözcük; güveni bunun altında ya da eğimi bundan fazla (derece) ya da tek sözcük BÜYÜK HARF.
  static let SIGN_MAX_WORDS = 2
  static let SIGN_LOW_CONFIDENCE = 0.5
  static let SIGN_TILT_DEGREES = 6.0
  /// Menü bloğu: en az bu kadar satır, satır başları bu kadar (karenin genişliğine oranla) aynı x'te, satır başına
  /// ortanca sözcük sayısı en çok bu kadar.
  static let MENU_MIN_ROWS = 4
  static let MENU_LEFT_SPREAD = 0.012
  static let MENU_MAX_ROW_WORDS = 4
  /// Dağınık sayfa: en az bu kadar parça, bu kadar blok; parçalar karenin en az bu genişliğine ve yüksekliğine yayılmış.
  static let SCATTER_MIN_PIECES = 10
  static let SCATTER_MIN_BLOCKS = 4
  static let SCATTER_MIN_WIDTH = 0.5
  static let SCATTER_MIN_HEIGHT = 0.3
  /// Aynı satırdaki iki parça arasındaki boşluk satır yüksekliğinin bu katından büyükse ayrı yazıdır (yan yana gösterge).
  static let SEGMENT_GAP_LINES = 2.5
  /// Metni ve yeri bu kadar ms değişmeyen yazı sabittir (gösterge/görev metni).
  static let STATIC_MS: Int64 = 9000
  /// Yazı bu kadar ms görünmezse kalkmış sayılır; yeniden belirmesi yeni görünümdür.
  static let STATIC_GAP_MS: Int64 = 4000
  /// Sabit yazı bu kadar ms hatırlanır (sonraki görünümlerinde çevrilmesin).
  static let STATIC_MEMORY_MS: Int64 = 600_000
  static let MAX_FIXTURES = 32
  /// Aynı yazı sayılmak için yatay ve dikey ortalar arasındaki en büyük fark.
  static let SAME_PLACE = 0.03
  /// Bandın dışında art arda bu kadar altyazı gönderilirse bant yeniden öğrenilir; uzun sessizlikten sonra daha az.
  static let RELEARN_RUN = 3
  static let RELEARN_RUN_AFTER_QUIET = 2
  static let RELEARN_QUIET_MS: Int64 = 120_000
  /// Gösterilen satırın okuması bu kadar son okumada ve bu kadar ms içinde aranır.
  static let MAX_READS = 8
  static let READ_MATCH_MS: Int64 = 10_000
  /// Gösterilen satır, en çok bu kadar ms önce görülmüş yazıyla eşleştirilir (sabitlik muafiyeti).
  static let SHOWN_MATCH_MS: Int64 = 3000

  // MARK: - Durum

  /// Okunan alandaki bir yazının (bloğun) izi: sabitlik için.
  private struct Fixture {
    var text: String
    var centerX: Double
    var centerY: Double
    var appearedAt: Int64
    var lastSeen: Int64
    /// Bir görünümünde [STATIC_MS] boyunca değişmedi: sabit yazı.
    var unchanging: Bool
    /// Bu görünümünde TV'ye gönderildi: görünüm sürdükçe sabitlikten muaf (gerçek uzun altyazı erken silinmesin).
    var shownNow: Bool
    var inLastRead: Bool
  }

  /// Bir okumanın seçilen bloğu (gösterilince örnek olur).
  private struct Sample {
    var key: String
    var top: Double
    var bottom: Double
    var left: Double
    var right: Double
    var lineHeight: Double
    var at: Int64

    var centerX: Double { (left + right) / 2 }
    var centerY: Double { (top + bottom) / 2 }
  }

  private var fixtures: [Fixture] = []
  private var reads: [Sample] = []
  private var samples: [Sample] = []
  private var outsideRun: [Sample] = []
  private var runAfterQuiet = false
  private var lastSampleAt: Int64?
  /// Öğrenilmiş altyazı bandı; yoksa yalnız kesin kurallar çalışır.
  private(set) var band: SubtitleBand?

  init() {}

  /// Her şey unutulur (akış durdu/başladı, bölge ya da ayar değişti).
  mutating func reset() {
    fixtures.removeAll()
    reads.removeAll()
    samples.removeAll()
    outsideRun.removeAll()
    runAfterQuiet = false
    lastSampleAt = nil
    band = nil
  }

  // MARK: - Süzme

  /// Bir karenin parçalarını süzer. [track]: sabitlik izleri güncellenir (asıl okuma); yeniden okumada false.
  mutating func apply(_ input: [TextObservation], frame: SubtitleOnlyFrame, at now: Int64, track: Bool) -> SubtitleOnlyOutcome {
    var outcome = SubtitleOnlyOutcome()
    let confident: [TextObservation] = ReadingSelector.filterConfidence(input)
    let firstBlocks: [[TextObservation]] = ReadingSelector.blocks(confident)
    if track { markSeen(firstBlocks, frame: frame, at: now) }
    if let reason = SubtitleOnlyFilter.frameReason(confident, blocks: firstBlocks, frame: frame) {
      outcome.wholeFrame = true
      for o in input { outcome.drops.append(SubtitleOnlyDrop(observation: o, reason: reason)) }
      return outcome
    }
    var dropped: [SubtitleOnlyDrop] = []
    var remaining: [TextObservation] = []
    // Sabitlik yazı başına (satırın büyük boşlukla ayrılmış parçası): altyazının yanındaki gösterge kendi başına izlenir.
    for block in firstBlocks {
      for segment in SubtitleOnlyFilter.segments(block) {
        if isUnchanging(segment, frame: frame) {
          for o in segment { dropped.append(SubtitleOnlyDrop(observation: o, reason: SubtitleOnlyReason.unchanging)) }
          continue
        }
        for o in segment {
          if let current = band, let reason = SubtitleOnlyFilter.pieceReason(o, band: current, frame: frame) {
            dropped.append(SubtitleOnlyDrop(observation: o, reason: reason))
          } else {
            remaining.append(o)
          }
        }
      }
    }
    for block in ReadingSelector.blocks(remaining) {
      dropped.append(contentsOf: blockDrops(block, frame: frame))
    }
    outcome.drops = dropped
    var kept: [TextObservation] = []
    for o in input where !dropped.contains(where: { (d: SubtitleOnlyDrop) -> Bool in d.observation == o }) { kept.append(o) }
    outcome.kept = kept
    return outcome
  }

  /// Bölge yeniden okunmadan önceki okuma kullanıldı (kare değişmedi): son okumada görülen yazılar hâlâ ekranda.
  mutating func touch(at now: Int64) {
    for index in fixtures.indices where fixtures[index].inLastRead {
      fixtures[index].lastSeen = now
      if now - fixtures[index].appearedAt >= SubtitleOnlyFilter.STATIC_MS { fixtures[index].unchanging = true }
    }
  }

  // MARK: - Kurallar

  /// Kare bütünüyle menü ya da dağınık sayfa mı.
  static func frameReason(_ pieces: [TextObservation], blocks: [[TextObservation]], frame: SubtitleOnlyFrame) -> SubtitleOnlyReason? {
    for block in blocks where isMenuBlock(block, frame: frame) { return SubtitleOnlyReason.menu }
    if pieces.count >= SCATTER_MIN_PIECES && blocks.count >= SCATTER_MIN_BLOCKS {
      let area: TextBox = frame.box(pieces)
      if area.right - area.left >= SCATTER_MIN_WIDTH && area.bottom - area.top >= SCATTER_MIN_HEIGHT {
        return SubtitleOnlyReason.scattered
      }
    }
    return nil
  }

  /// Menü bloğu: en az [MENU_MIN_ROWS] satır, satır başları aynı x'te, satırlar kısa, konuşmacı etiketi yok.
  static func isMenuBlock(_ block: [TextObservation], frame: SubtitleOnlyFrame) -> Bool {
    let rows: [[TextObservation]] = ReadingSelector.rows(block)
    guard rows.count >= MENU_MIN_ROWS else { return false }
    var lefts: [Double] = []
    var words: [Double] = []
    for row in rows {
      guard let first = row.first else { continue }
      lefts.append(frame.x(Double(first.left)))
      var count = 0
      for o in row { count += wordCount(o.text) }
      words.append(Double(count))
    }
    guard let low = lefts.min(), let high = lefts.max(), high - low <= MENU_LEFT_SPREAD else { return false }
    if LineHeight.upperMedian(words) > Double(MENU_MAX_ROW_WORDS) { return false }
    return !hasLabel(text(of: block))
  }

  /// Parça kuralları (yalnız bant öğrenildikten sonra): satır yüksekliği uyumu ve dünya içi tabela.
  static func pieceReason(_ o: TextObservation, band: SubtitleBand, frame: SubtitleOnlyFrame) -> SubtitleOnlyReason? {
    let centerY: Double = frame.y(o.centerY)
    let inBand: Bool = band.contains(centerY)
    if band.lineHeight > 0 {
      let height: Double = LineHeight.perLine(o) / Double(max(frame.height, 1))
      let ratio: Double = height / band.lineHeight
      let mismatch: Bool = ratio < MIN_HEIGHT_FACTOR || ratio > MAX_HEIGHT_FACTOR
      // Bantta cümle gibi duran parça yüksekliği tutmasa da altyazıdır (şüphede çevir).
      if mismatch && !(inBand && AutoRegionFinder.isSentenceLike(o.text)) { return SubtitleOnlyReason.lineHeight }
    }
    if !inBand && isSignLike(o) { return SubtitleOnlyReason.sign }
    return nil
  }

  /// Kısa (en çok [SIGN_MAX_WORDS] sözcük), konuşmacı etiketi olmayan ve eğik / güvensiz / tek sözcük BÜYÜK HARF yazı.
  /// Eğim yalnız Vision verdiyse kullanılır.
  static func isSignLike(_ o: TextObservation) -> Bool {
    let words: Int = wordCount(o.text)
    guard words >= 1, words <= SIGN_MAX_WORDS else { return false }
    if hasLabel(o.text) { return false }
    if let angle = o.angle, abs(angle) >= SIGN_TILT_DEGREES { return true }
    if o.confidence < SIGN_LOW_CONFIDENCE { return true }
    return words == 1 && isAllCaps(o.text)
  }

  /// Blok ve parça grubu kuralları: kenar (her zaman), bant dışı ve yatay hiza (bant öğrenildikten sonra).
  private func blockDrops(_ block: [TextObservation], frame: SubtitleOnlyFrame) -> [SubtitleOnlyDrop] {
    let blockText: String = SubtitleOnlyFilter.text(of: block)
    let positive: Bool = SubtitleOnlyFilter.hasLabel(blockText) || AutoRegionFinder.isSentenceLike(blockText)
    let whole: TextBox = frame.box(block)
    var outside = false
    if let current = band { outside = whole.bottom < current.top || whole.top > current.bottom }
    var drops: [SubtitleOnlyDrop] = []
    for segment in SubtitleOnlyFilter.segments(block) {
      let shape: TextBox = frame.box(segment)
      if let reason = segmentReason(shape, positive: positive, outside: outside) {
        for o in segment { drops.append(SubtitleOnlyDrop(observation: o, reason: reason)) }
      }
    }
    return drops
  }

  private func segmentReason(_ shape: TextBox, positive: Bool, outside: Bool) -> SubtitleOnlyReason? {
    let centerX: Double = (shape.left + shape.right) / 2
    let centered: Bool = abs(centerX - 0.5) <= SubtitleOnlyFilter.CENTER_TOLERANCE
    var aligned = false
    if let current = band, current.layout == SubtitleBand.Layout.left {
      aligned = abs(shape.left - current.leftEdge) <= SubtitleOnlyFilter.LEFT_EDGE_TOLERANCE
    }
    let atEdge: Bool = centerX < SubtitleOnlyFilter.EDGE_CENTER || centerX > 1 - SubtitleOnlyFilter.EDGE_CENTER
    if atEdge && !aligned { return SubtitleOnlyReason.edge }
    guard let current = band else { return nil }
    // Bandın dışında: yalnız ortalı (ya da sola yaslı bantta hizalı) konuşma/cümle kabul.
    if outside { return (centered || aligned) && positive ? nil : SubtitleOnlyReason.outsideBand }
    switch current.layout {
    case SubtitleBand.Layout.centered:
      return centered ? nil : SubtitleOnlyReason.offCenter
    case SubtitleBand.Layout.left:
      return centered || aligned ? nil : SubtitleOnlyReason.offCenter
    case SubtitleBand.Layout.mixed:
      return nil
    }
  }

  /// Bloğun satırları, her satır aralarında büyük boşluk olan parçalarda bölünerek (yan yana duran gösterge ayrı yazıdır).
  static func segments(_ block: [TextObservation]) -> [[TextObservation]] {
    var out: [[TextObservation]] = []
    for row in ReadingSelector.rows(block) {
      var current: [TextObservation] = []
      var reach = 0
      for o in row {
        if let last = current.last {
          let gap: Double = Double(o.left - reach)
          let height: Double = Double(max(max(last.height, o.height), 1))
          if gap > SEGMENT_GAP_LINES * height {
            out.append(current)
            current = []
          }
        }
        reach = current.isEmpty ? o.right : max(reach, o.right)
        current.append(o)
      }
      if !current.isEmpty { out.append(current) }
    }
    return out
  }

  // MARK: - Sabit yazı

  private func fixtureIndex(text: String, centerX: Double, centerY: Double) -> Int? {
    let normalized: String = TextMatch.normalize(text)
    var best: Int?
    var bestDistance = Double.infinity
    for index in fixtures.indices {
      let f = fixtures[index]
      let dx: Double = abs(f.centerX - centerX)
      let dy: Double = abs(f.centerY - centerY)
      guard dx <= SubtitleOnlyFilter.SAME_PLACE, dy <= SubtitleOnlyFilter.SAME_PLACE else { continue }
      let same: Bool = KotlinText.same(TextMatch.normalize(f.text), normalized) || AutoRegionFinder.isSameText(f.text, text)
      guard same else { continue }
      if dx + dy < bestDistance {
        bestDistance = dx + dy
        best = index
      }
    }
    return best
  }

  private mutating func markSeen(_ blocks: [[TextObservation]], frame: SubtitleOnlyFrame, at now: Int64) {
    for index in fixtures.indices { fixtures[index].inLastRead = false }
    var segments: [[TextObservation]] = []
    for block in blocks { segments.append(contentsOf: SubtitleOnlyFilter.segments(block)) }
    for segment in segments {
      let text: String = SubtitleOnlyFilter.text(of: segment)
      let shape: TextBox = frame.box(segment)
      let centerX: Double = (shape.left + shape.right) / 2
      let centerY: Double = (shape.top + shape.bottom) / 2
      if let index = fixtureIndex(text: text, centerX: centerX, centerY: centerY) {
        let gap: Int64 = now - fixtures[index].lastSeen
        if gap > SubtitleOnlyFilter.STATIC_GAP_MS || gap < 0 {
          // Kalkıp yeniden belirdi: yeni görünüm (sabitlik bilgisi kalır, gösterilme bilgisi sıfırlanır).
          fixtures[index].appearedAt = now
          fixtures[index].shownNow = false
        }
        fixtures[index].text = text
        fixtures[index].centerX = centerX
        fixtures[index].centerY = centerY
        fixtures[index].lastSeen = now
        fixtures[index].inLastRead = true
        if now - fixtures[index].appearedAt >= SubtitleOnlyFilter.STATIC_MS { fixtures[index].unchanging = true }
      } else {
        fixtures.append(Fixture(text: text, centerX: centerX, centerY: centerY, appearedAt: now, lastSeen: now,
                                unchanging: false, shownNow: false, inLastRead: true))
      }
    }
    fixtures.removeAll { (f: Fixture) -> Bool in now - f.lastSeen > SubtitleOnlyFilter.STATIC_MEMORY_MS }
    while fixtures.count > SubtitleOnlyFilter.MAX_FIXTURES {
      var oldest = 0
      for index in fixtures.indices where fixtures[index].lastSeen < fixtures[oldest].lastSeen { oldest = index }
      fixtures.remove(at: oldest)
    }
  }

  private func isUnchanging(_ block: [TextObservation], frame: SubtitleOnlyFrame) -> Bool {
    let shape: TextBox = frame.box(block)
    guard let index = fixtureIndex(text: SubtitleOnlyFilter.text(of: block), centerX: (shape.left + shape.right) / 2,
                                   centerY: (shape.top + shape.bottom) / 2) else { return false }
    return fixtures[index].unchanging && !fixtures[index].shownNow
  }

  // MARK: - Bant öğrenme

  /// Okumanın sonunda (asıl okuma): seçilen blok ve TV'ye gidecek satırlar; satır gösterilirse örnek olur.
  mutating func rememberRead(lines: [String], selected: [TextObservation], frame: SubtitleOnlyFrame, at now: Int64) {
    guard !selected.isEmpty else { return }
    var cleaned: [String] = []
    for line in lines {
      let text: String = OcrNoise.clean(line)
      if !text.isEmpty { cleaned.append(text) }
    }
    let key: String = cleaned.joined(separator: "\n")
    if key.isEmpty { return }
    if let last = reads.last, KotlinText.same(last.key, key) {
      reads[reads.count - 1].at = now
      return
    }
    let shape: TextBox = frame.box(selected)
    var heights: [Double] = []
    for o in selected { heights.append(LineHeight.perLine(o) / Double(max(frame.height, 1))) }
    reads.append(Sample(key: key, top: shape.top, bottom: shape.bottom, left: shape.left, right: shape.right,
                        lineHeight: LineHeight.upperMedian(heights), at: now))
    if reads.count > SubtitleOnlyFilter.MAX_READS { reads.removeFirst(reads.count - SubtitleOnlyFilter.MAX_READS) }
  }

  /// Hat bir satırı TV'ye gönderdi ([source]: hattın çevirdiği metin): o anki yazı sabitlikten muaf olur, okuması
  /// bulunursa bant örneği olur.
  mutating func noteShown(_ source: String, at now: Int64) -> SubtitleOnlyShown {
    let flat: String = source.replacingOccurrences(of: "\n", with: " ")
    let shown: String = TextMatch.normalize(flat)
    for index in fixtures.indices where fixtures[index].inLastRead || now - fixtures[index].lastSeen <= SubtitleOnlyFilter.SHOWN_MATCH_MS {
      let text: String = TextMatch.normalize(fixtures[index].text)
      // Gösterilen metnin bir satırı (yazı) da gösterilmiş sayılır.
      let same: Bool = KotlinText.same(text, shown) || (text.count >= 2 && shown.contains(text))
        || AutoRegionFinder.isSameText(fixtures[index].text, flat)
      if same { fixtures[index].shownNow = true }
    }
    var note = SubtitleOnlyShown(learning: SubtitleOnlyShown.Learning.unmatched, sample: nil, lineHeight: nil,
                                 outsideRun: outsideRun.count, bandChanged: false)
    guard let sample = readSample(for: source, at: now) else { return note }
    note.sample = TextBox(left: sample.left, top: sample.top, right: sample.right, bottom: sample.bottom)
    note.lineHeight = sample.lineHeight
    let before: SubtitleBand? = band
    if let current = band {
      if current.contains(sample.centerY) {
        outsideRun.removeAll()
        addSample(sample)
        band = SubtitleOnlyFilter.makeBand(samples, minimum: SubtitleOnlyFilter.LEARN_MIN) ?? current
        note.learning = SubtitleOnlyShown.Learning.sample
      } else {
        if outsideRun.isEmpty {
          runAfterQuiet = lastSampleAt.map { (at: Int64) -> Bool in now - at >= SubtitleOnlyFilter.RELEARN_QUIET_MS } ?? true
        }
        if let last = outsideRun.last, SubtitleOnlyFilter.sameKey(last.key, sample.key) {
          outsideRun[outsideRun.count - 1] = sample
        } else {
          outsideRun.append(sample)
        }
        let needed: Int = runAfterQuiet ? SubtitleOnlyFilter.RELEARN_RUN_AFTER_QUIET : SubtitleOnlyFilter.RELEARN_RUN
        note.learning = SubtitleOnlyShown.Learning.outside
        if outsideRun.count >= needed {
          if let moved = SubtitleOnlyFilter.makeBand(outsideRun, minimum: needed) {
            samples = outsideRun
            outsideRun.removeAll()
            band = moved
            note.learning = SubtitleOnlyShown.Learning.relearned
          } else {
            // Bant dışındakiler kendi aralarında da dağınık: kanıt kayar (en eskisi atılır).
            outsideRun.removeFirst()
          }
        }
      }
    } else {
      addSample(sample)
      if let learned = SubtitleOnlyFilter.makeBand(samples, minimum: SubtitleOnlyFilter.LEARN_MIN) {
        band = learned
        note.learning = SubtitleOnlyShown.Learning.learned
      } else {
        note.learning = SubtitleOnlyShown.Learning.sample
      }
    }
    lastSampleAt = now
    note.outsideRun = outsideRun.count
    note.bandChanged = before != band
    return note
  }

  private func readSample(for source: String, at now: Int64) -> Sample? {
    for read in reads.reversed() where KotlinText.same(read.key, source) { return read }
    for read in reads.reversed() where now - read.at <= SubtitleOnlyFilter.READ_MATCH_MS && now >= read.at {
      if SubtitleOnlyFilter.sameKey(read.key, source) { return read }
    }
    return nil
  }

  /// Aynı satırın düzeltilmiş okuması yeni örnek açmaz, öncekinin yerine geçer.
  private mutating func addSample(_ sample: Sample) {
    if let last = samples.last, SubtitleOnlyFilter.sameKey(last.key, sample.key) {
      samples[samples.count - 1] = sample
    } else {
      samples.append(sample)
    }
    if samples.count > SubtitleOnlyFilter.MAX_SAMPLES { samples.removeFirst(samples.count - SubtitleOnlyFilter.MAX_SAMPLES) }
  }

  private static func sameKey(_ a: String, _ b: String) -> Bool {
    KotlinText.same(a, b) || AutoRegionFinder.isSameText(a.replacingOccurrences(of: "\n", with: " "),
                                                        b.replacingOccurrences(of: "\n", with: " "))
  }

  /// Örneklerin en kalabalık dikey kümesinden bant: ortanca örneğe [CLUSTER_SPAN] içindeki örnekler en az [minimum]
  /// tane olmalı. Yerleşim: sol kenarlar ortalardan daha tutarlıysa ve örneklerin çoğu hizalıysa sola yaslı; çoğu
  /// ortalıysa ortalı; yoksa kararsız.
  private static func makeBand(_ list: [Sample], minimum: Int) -> SubtitleBand? {
    guard minimum > 0, list.count >= minimum else { return nil }
    var centers: [Double] = []
    for s in list { centers.append(s.centerY) }
    let median: Double = LineHeight.upperMedian(centers)
    var cluster: [Sample] = []
    for s in list where abs(s.centerY - median) <= CLUSTER_SPAN { cluster.append(s) }
    guard cluster.count >= minimum else { return nil }
    var heights: [Double] = []
    var tops: [Double] = []
    var bottoms: [Double] = []
    var lefts: [Double] = []
    var middles: [Double] = []
    for s in cluster {
      heights.append(s.lineHeight)
      tops.append(s.top)
      bottoms.append(s.bottom)
      lefts.append(s.left)
      middles.append(s.centerX)
    }
    let typical: Double = LineHeight.upperMedian(heights)
    let pad: Double = BAND_PAD_LINES * typical
    let top: Double = max(0, (tops.min() ?? 0) - pad)
    let bottom: Double = min(1, (bottoms.max() ?? 1) + pad)
    let medianLeft: Double = LineHeight.upperMedian(lefts)
    let medianMiddle: Double = LineHeight.upperMedian(middles)
    var aligned = 0
    var centered = 0
    var leftDeviation = 0.0
    var middleDeviation = 0.0
    for s in cluster {
      if abs(s.left - medianLeft) <= LEFT_SAMPLE_SPREAD { aligned += 1 }
      if abs(s.centerX - 0.5) <= CENTER_TOLERANCE { centered += 1 }
      leftDeviation += abs(s.left - medianLeft)
      middleDeviation += abs(s.centerX - medianMiddle)
    }
    let needed: Double = LAYOUT_SHARE * Double(cluster.count)
    let layout: SubtitleBand.Layout
    if Double(aligned) >= needed && leftDeviation < middleDeviation {
      layout = SubtitleBand.Layout.left
    } else if Double(centered) >= needed {
      layout = SubtitleBand.Layout.centered
    } else {
      layout = SubtitleBand.Layout.mixed
    }
    return SubtitleBand(top: top, bottom: bottom, lineHeight: typical, layout: layout, leftEdge: medianLeft,
                        samples: cluster.count)
  }

  // MARK: - Metin yardımcıları

  /// Bloğun metni: satırlar yukarıdan aşağı, parçalar soldan sağa.
  static func text(of block: [TextObservation]) -> String {
    var lines: [String] = []
    for row in ReadingSelector.rows(block) {
      var parts: [String] = []
      for o in row { parts.append(o.text) }
      lines.append(parts.joined(separator: " "))
    }
    return lines.joined(separator: "\n")
  }

  /// Harf içeren sözcük sayısı.
  static func wordCount(_ text: String) -> Int {
    var count = 0
    let parts: [Substring] = text.split(whereSeparator: { (c: Character) -> Bool in c == " " || c == "\n" || c == "\t" })
    for part in parts where part.contains(where: { (c: Character) -> Bool in c.isLetter }) { count += 1 }
    return count
  }

  /// En az iki harf, hepsi büyük.
  static func isAllCaps(_ text: String) -> Bool {
    var letters = 0
    for c in text where c.isLetter {
      if c.isLowercase { return false }
      letters += 1
    }
    return letters >= 2
  }

  /// Satır başında konuşmacı etiketi ("Devin:", "MINE GUARD:") var mı (SpeakerTurns'ün kuralı).
  static func hasLabel(_ text: String) -> Bool { !SpeakerTurns.speakers(in: text).isEmpty }
}

/// Süzgecin tanı kaydı biçimi (yalnız kayıt açıkken çağrılır).
enum SubtitleOnlyDiag {
  static func band(_ band: SubtitleBand?) -> DiagValue {
    guard let band else { return DiagValue.null }
    var fields = DiagFields()
    fields["top"] = DiagValue.double(band.top)
    fields["bottom"] = DiagValue.double(band.bottom)
    fields["lineHeight"] = DiagValue.double(band.lineHeight)
    let layout: String
    switch band.layout {
    case SubtitleBand.Layout.centered: layout = "centered"
    case SubtitleBand.Layout.left: layout = "left"
    case SubtitleBand.Layout.mixed: layout = "mixed"
    }
    fields["layout"] = DiagValue.string(layout)
    if band.layout == SubtitleBand.Layout.left { fields["leftEdge"] = DiagValue.double(band.leftEdge) }
    fields["samples"] = DiagValue.int(band.samples)
    return DiagValue.object(fields)
  }

  static func drops(_ list: [SubtitleOnlyDrop], frame: SubtitleOnlyFrame) -> DiagValue {
    var items: [DiagValue] = []
    for drop in list {
      var fields = DiagFields()
      fields["text"] = DiagValue.string(drop.observation.text)
      fields["reason"] = DiagValue.string(drop.reason.code)
      fields["conf"] = DiagValue.double(drop.observation.confidence)
      fields["box"] = DiagValue.box(frame.box([drop.observation]))
      fields["h"] = DiagValue.int(drop.observation.height)
      if let angle = drop.observation.angle { fields["angle"] = DiagValue.double(angle) }
      items.append(DiagValue.object(fields))
    }
    return DiagValue.array(items)
  }

  static func learning(_ value: SubtitleOnlyShown.Learning) -> String {
    switch value {
    case SubtitleOnlyShown.Learning.unmatched: return "unmatched"
    case SubtitleOnlyShown.Learning.sample: return "sample"
    case SubtitleOnlyShown.Learning.learned: return "learned"
    case SubtitleOnlyShown.Learning.relearned: return "relearned"
    case SubtitleOnlyShown.Learning.outside: return "outside"
    }
  }
}
