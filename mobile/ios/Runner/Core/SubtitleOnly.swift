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
  /// Karede menü satırları ya da dağınık sayfa bulundu (yalnız ilgili bloklar atıldı; kare çapında veto yok).
  var pageFound = false
  /// Emniyet supabı bu karede bandı unuttu (tanı kaydı: filter/band-dropped).
  var bandDropped = false
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
    /// Gösterilen satır konuşma/cümle biçimli değil (menü öğesi, başlık): bant öğretmez.
    case notSpeech
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
  static let LAYOUT_SHARE: Double = 2.0 / 3.0
  /// Satırın yatay ortası ekran ortasından en çok bu kadar uzaksa ortalı sayılır.
  static let CENTER_TOLERANCE: Double = 0.12
  /// Yatay ortası bundan kenara yakın yazı ekran kenarına dayalıdır (AutoRegionFinder ile aynı eşik).
  static let EDGE_CENTER: Double = AutoRegionFinder.EDGE_CENTER
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
  static let SEGMENT_GAP_LINES: Double = 2.5
  /// Bir satır, blok çapasının ortası, sol ya da sağ kenarıyla bu kadar içinde hizalıysa aynı altyazının satırıdır.
  static let ALIGN_TOLERANCE: Double = 0.03
  /// Yan parça bu payla çekirdeğin yatay kapsamının içindeyse çekirdeğe katılır.
  static let SIDE_MARGIN: Double = 0.02
  /// Emniyet supabı: bant kuralları bu kadar ms konuşma/cümle biçimli yazı atıp bu arada hiçbir satır gösterilmezse
  /// bant unutulur.
  static let SAFETY_MS: Int64 = 20_000
  /// Şüpheli atmalar arasındaki en uzun ara: daha uzun ara şüpheyi bitirir.
  static let SUSPECT_GAP_MS: Int64 = 4000
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
  /// Bant kurallarının konuşma/cümle biçimli yazı atmaya başladığı an (son gösterimden beri); yoksa nil.
  private var suspectSince: Int64?
  /// Son şüpheli atmanın anı: aradan [SUSPECT_GAP_MS]'den fazla geçerse şüphe biter (supap yalnız kesintisiz şüphede açılır).
  private var lastSuspectAt: Int64?
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
    suspectSince = nil
    lastSuspectAt = nil
    band = nil
  }

  // MARK: - Süzme

  /// Bir karenin parçalarını süzer. [track]: sabitlik izleri güncellenir (asıl okuma); yeniden okumada false.
  mutating func apply(_ input: [TextObservation], frame: SubtitleOnlyFrame, at now: Int64, track: Bool) -> SubtitleOnlyOutcome {
    var outcome = SubtitleOnlyOutcome()
    // Emniyet supabı: bant kuralları bir süredir konuşma/cümle biçimli yazı atıyor ve bu arada hiçbir satır gösterilmedi:
    // bant yanlış ya da eskimiş; unutulur, kesin kurallara dönülür ve yeniden öğrenilir.
    if track, band != nil, let since = suspectSince, let last = lastSuspectAt, now >= since, now >= last,
       now - last <= SubtitleOnlyFilter.SUSPECT_GAP_MS, now - since >= SubtitleOnlyFilter.SAFETY_MS {
      forgetBand(at: now)
      outcome.bandDropped = true
    }
    let confident: [TextObservation] = ReadingSelector.filterConfidence(input)
    let firstBlocks: [[TextObservation]] = ReadingSelector.blocks(confident)
    if track { markSeen(firstBlocks, frame: frame, at: now) }
    let scattered: Bool = SubtitleOnlyFilter.isScattered(confident, blocks: firstBlocks, frame: frame)
    if scattered { outcome.pageFound = true }
    var dropped: [SubtitleOnlyDrop] = []
    var remaining: [TextObservation] = []
    for block in firstBlocks {
      // Menü: blok içinde art arda en az dört sola hizalı kısa satır; yalnız o satırlar atılır (karenin geri kalanı değil).
      let split: (menu: [TextObservation], rest: [TextObservation]) = SubtitleOnlyFilter.menuRows(block, frame: frame)
      if !split.menu.isEmpty {
        outcome.pageFound = true
        for o in split.menu { dropped.append(SubtitleOnlyDrop(observation: o, reason: SubtitleOnlyReason.menu)) }
      }
      let rest: [TextObservation] = split.rest
      if rest.isEmpty { continue }
      // Dağınık sayfa: bant varsa yalnız bandın dışındaki blok, bant yoksa ortalı konuşma/cümle olmayan blok atılır.
      if scattered && scatterDrops(rest, frame: frame) {
        for o in rest { dropped.append(SubtitleOnlyDrop(observation: o, reason: SubtitleOnlyReason.scattered)) }
        continue
      }
      let restText: String = SubtitleOnlyFilter.text(of: rest)
      let speech: Bool = SubtitleOnlyFilter.isSpeech(restText)
      let standalone: Bool = ReadingSelector.rows(rest).count == 1
      // Sabitlik yazı başına (satırın büyük boşlukla ayrılmış parçası): altyazının yanındaki gösterge kendi başına izlenir.
      for segment in SubtitleOnlyFilter.segments(rest) {
        if isUnchanging(segment, frame: frame) {
          for o in segment { dropped.append(SubtitleOnlyDrop(observation: o, reason: SubtitleOnlyReason.unchanging)) }
          continue
        }
        for o in segment {
          if let current = band,
             let reason = SubtitleOnlyFilter.pieceReason(o, band: current, frame: frame, blockSpeech: speech, standalone: standalone) {
            dropped.append(SubtitleOnlyDrop(observation: o, reason: reason))
          } else {
            remaining.append(o)
          }
        }
      }
    }
    var suspicious = false
    for block in ReadingSelector.blocks(remaining) {
      let result: (drops: [SubtitleOnlyDrop], suspicious: Bool) = blockDrops(block, frame: frame)
      dropped.append(contentsOf: result.drops)
      if result.suspicious { suspicious = true }
    }
    if track && band != nil {
      // Şüphe yalnız kesintisiz sürerse sayılır: son şüpheli atmadan [SUSPECT_GAP_MS]'den fazla geçtiyse sayaç sıfırlanır.
      var expired = false
      if let last = lastSuspectAt { expired = now < last || now - last > SubtitleOnlyFilter.SUSPECT_GAP_MS }
      if suspicious {
        if expired || suspectSince == nil { suspectSince = now }
        lastSuspectAt = now
      } else if expired {
        suspectSince = nil
        lastSuspectAt = nil
      }
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
      // Bu görünümünde TV'ye gönderilmiş yazı (altyazı) sabit yazı hafızasına hiç girmez.
      if !fixtures[index].shownNow && now - fixtures[index].appearedAt >= SubtitleOnlyFilter.STATIC_MS {
        fixtures[index].unchanging = true
      }
    }
  }

  /// Bant ve öğrenme kanıtı unutulur. Sabit yazı sayımı sıfırdan başlar: bant kuralıyla uzun süre atılmış gerçek altyazı
  /// sabit yazı sayılmış olabilir (gösterilmediği için); supaptan sonra o yüzden düşmesin.
  private mutating func forgetBand(at now: Int64) {
    for index in fixtures.indices {
      fixtures[index].unchanging = false
      fixtures[index].appearedAt = now
    }
    band = nil
    samples.removeAll()
    outsideRun.removeAll()
    runAfterQuiet = false
    lastSampleAt = nil
    suspectSince = nil
    lastSuspectAt = nil
  }

  // MARK: - Kurallar

  /// Karede ekrana yayılmış çok sayıda parça var mı (harita, envanter, kalabalık gösterge). Kare çapında veto değildir:
  /// hangi blokların atılacağına [scatterDrops] karar verir.
  static func isScattered(_ pieces: [TextObservation], blocks: [[TextObservation]], frame: SubtitleOnlyFrame) -> Bool {
    guard pieces.count >= SCATTER_MIN_PIECES && blocks.count >= SCATTER_MIN_BLOCKS else { return false }
    let area: TextBox = frame.box(pieces)
    return area.right - area.left >= SCATTER_MIN_WIDTH && area.bottom - area.top >= SCATTER_MIN_HEIGHT
  }

  /// Dağınık sayfada blok atılsın mı: bant öğrenilmişse yalnız bandın tamamen dışındaki blok; bant yoksa ortalı ve
  /// konuşma/cümle biçimli blok korunur, gerisi atılır.
  private func scatterDrops(_ block: [TextObservation], frame: SubtitleOnlyFrame) -> Bool {
    let shape: TextBox = frame.box(block)
    if let current = band { return shape.bottom < current.top || shape.top > current.bottom }
    let centerX: Double = (shape.left + shape.right) / 2
    let centered: Bool = abs(centerX - 0.5) <= SubtitleOnlyFilter.CENTER_TOLERANCE
    return !(centered && SubtitleOnlyFilter.isSpeech(SubtitleOnlyFilter.text(of: block)))
  }

  /// Bloğun menü satırları ve geri kalanı. Menü: art arda en az [MENU_MIN_ROWS] satır, satır başları ilk satırınkine
  /// [MENU_LEFT_SPREAD] içinde, satır başına ortanca sözcük en çok [MENU_MAX_ROW_WORDS], konuşmacı etiketi yok. Menünün
  /// altındaki/üstündeki altyazı satırları geri kalandadır.
  static func menuRows(_ block: [TextObservation], frame: SubtitleOnlyFrame) -> (menu: [TextObservation], rest: [TextObservation]) {
    let rows: [[TextObservation]] = ReadingSelector.rows(block)
    guard rows.count >= MENU_MIN_ROWS else { return ([], block) }
    var lefts: [Double] = []
    for row in rows { lefts.append(frame.x(Double(row.first?.left ?? 0))) }
    var isMenu: [Bool] = Array(repeating: false, count: rows.count)
    var start = 0
    while start < rows.count {
      var end = start
      while end + 1 < rows.count && abs(lefts[end + 1] - lefts[start]) <= MENU_LEFT_SPREAD { end += 1 }
      if end - start + 1 >= MENU_MIN_ROWS {
        var words: [Double] = []
        var lines: [String] = []
        for index in start...end {
          var count = 0
          var parts: [String] = []
          for o in rows[index] {
            count += wordCount(o.text)
            parts.append(o.text)
          }
          words.append(Double(count))
          lines.append(parts.joined(separator: " "))
        }
        if LineHeight.upperMedian(words) <= Double(MENU_MAX_ROW_WORDS) && !hasLabel(lines.joined(separator: "\n")) {
          for index in start...end { isMenu[index] = true }
        }
      }
      start = end + 1
    }
    var menu: [TextObservation] = []
    var rest: [TextObservation] = []
    for (index, row) in rows.enumerated() {
      if isMenu[index] { menu.append(contentsOf: row) } else { rest.append(contentsOf: row) }
    }
    return (menu, rest)
  }

  /// Blok menü satırlarından mı oluşuyor (tanı ve test için).
  static func isMenuBlock(_ block: [TextObservation], frame: SubtitleOnlyFrame) -> Bool {
    !menuRows(block, frame: frame).menu.isEmpty
  }

  /// Konuşma ya da cümle biçimi: konuşmacı etiketi ya da cümle gibi metin (altyazının olumlu kanıtı).
  /// Etiketten sonraki gövde harf içermiyorsa ("Cash: $500", "HP: 100") gösterge sayılır, konuşma değil.
  static func isSpeech(_ text: String) -> Bool {
    if AutoRegionFinder.isSentenceLike(text) { return true }
    guard hasLabel(text) else { return false }
    let lines: [Substring] = text.split(separator: "\n")
    for line in lines {
      var body: Substring = line
      if let mark = line.range(of: ": ") { body = line[mark.upperBound...] }
      if body.contains(where: { (c: Character) -> Bool in c.isLetter }) { return true }
    }
    return false
  }

  /// Tireyle başlayan konuşma ("- Yes.").
  static func startsWithDash(_ text: String) -> Bool {
    guard let first = text.trimmingCharacters(in: .whitespaces).first else { return false }
    return first == "-" || first == "–" || first == "—"
  }

  /// Parça kuralları (yalnız bant öğrenildikten sonra): satır yüksekliği uyumu ve dünya içi tabela.
  /// Konuşma/cümle biçimli parça yükseklikten hiç atılmaz (bant içinde de dışında da). Alt sınır (kısa sarma satırı
  /// "me.", "with" küçük ölçülür) bant içinde ve konuşma/cümle biçimli blokta uygulanmaz. Tabela kuralı yalnız tek
  /// satırlık bloklara (yalnız duran yazı) uygulanır: altyazı bloğunun içinden satır atılmaz.
  static func pieceReason(_ o: TextObservation, band: SubtitleBand, frame: SubtitleOnlyFrame, blockSpeech: Bool,
                          standalone: Bool) -> SubtitleOnlyReason? {
    let centerY: Double = frame.y(o.centerY)
    let inBand: Bool = band.contains(centerY)
    if band.lineHeight > 0 && !isSpeech(o.text) {
      let height: Double = LineHeight.perLine(o) / Double(max(frame.height, 1))
      let ratio: Double = height / band.lineHeight
      let tooSmall: Bool = ratio < MIN_HEIGHT_FACTOR && !inBand && !blockSpeech
      let tooBig: Bool = ratio > MAX_HEIGHT_FACTOR
      if tooSmall || tooBig { return SubtitleOnlyReason.lineHeight }
    }
    if standalone && !inBand && isSignLike(o) { return SubtitleOnlyReason.sign }
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

  /// Blok kuralları. İlke: altyazı bloğu ya bütün kalır ya bütün gider; bloğun içinden yalnız açıkça ayrık yazı atılır.
  /// Bloğun çekirdeği: her satırın ana yazısı (satırdaki en geniş parça grubu) içinde en geniş olanla (çapa) hizalı
  /// satırlar — ortaları, sol ya da sağ kenarları çapanınkine yakın ya da çapanın yatay kapsamının içinde. Çekirdek
  /// TEK BİRİM olarak değerlendirilir (ortalı bloğun sola yaslı kısa satırı atılmaz). Çapaya hizasız satır ve satırdaki
  /// yan parça (yatay boşlukla ayrılmış, çekirdeğin kapsamı dışına taşan gösterge) ayrı birimdir. [suspicious]: bant
  /// kuralı konuşma/cümle biçimli bir birimi attı (emniyet supabı için).
  private func blockDrops(_ block: [TextObservation], frame: SubtitleOnlyFrame) -> (drops: [SubtitleOnlyDrop], suspicious: Bool) {
    var mains: [[TextObservation]] = []
    var sides: [[TextObservation]] = []
    for row in ReadingSelector.rows(block) {
      let groups: [[TextObservation]] = SubtitleOnlyFilter.segments(row)
      // Aynı satırda geniş boşlukla ayrılmış iki konuşma ("- Yes.    - No."): birleşik kapsamı ortalıysa ve hepsi
      // konuşma/tireli ise tek yazıdır.
      if groups.count >= 2 {
        let whole: TextBox = frame.box(row)
        let centered: Bool = abs((whole.left + whole.right) / 2 - 0.5) <= SubtitleOnlyFilter.CENTER_TOLERANCE
        var talk = true
        for group in groups {
          let text: String = SubtitleOnlyFilter.text(of: group)
          if !(SubtitleOnlyFilter.startsWithDash(text) || SubtitleOnlyFilter.isSpeech(text)) { talk = false }
        }
        if centered && talk {
          mains.append(row)
          continue
        }
      }
      var widest = 0
      var widestWidth = -1.0
      for (index, group) in groups.enumerated() {
        let shape: TextBox = frame.box(group)
        if shape.right - shape.left > widestWidth {
          widestWidth = shape.right - shape.left
          widest = index
        }
      }
      for (index, group) in groups.enumerated() {
        if index == widest { mains.append(group) } else { sides.append(group) }
      }
    }
    var anchor: TextBox?
    for main in mains {
      let shape: TextBox = frame.box(main)
      if anchor == nil || shape.right - shape.left > anchor!.right - anchor!.left { anchor = shape }
    }
    guard let anchorBox = anchor else { return ([], false) }
    var core: [TextObservation] = []
    var units: [[TextObservation]] = []
    for main in mains {
      if SubtitleOnlyFilter.alignedRows(frame.box(main), anchorBox) { core.append(contentsOf: main) } else { units.append(main) }
    }
    let coreBox: TextBox = frame.box(core)
    for side in sides {
      let shape: TextBox = frame.box(side)
      let inside: Bool = shape.left >= coreBox.left - SubtitleOnlyFilter.SIDE_MARGIN
        && shape.right <= coreBox.right + SubtitleOnlyFilter.SIDE_MARGIN
      if inside { core.append(contentsOf: side) } else { units.append(side) }
    }
    units.insert(core, at: 0)
    let whole: TextBox = frame.box(block)
    var outside = false
    if let current = band { outside = whole.bottom < current.top || whole.top > current.bottom }
    var drops: [SubtitleOnlyDrop] = []
    var suspicious = false
    for unit in units where !unit.isEmpty {
      let speech: Bool = SubtitleOnlyFilter.isSpeech(SubtitleOnlyFilter.text(of: unit))
      guard let reason = unitReason(frame.box(unit), speech: speech, outside: outside) else { continue }
      for o in unit { drops.append(SubtitleOnlyDrop(observation: o, reason: reason)) }
      if speech && (reason == SubtitleOnlyReason.outsideBand || reason == SubtitleOnlyReason.offCenter) { suspicious = true }
    }
    return (drops, suspicious)
  }

  /// İki satır aynı altyazı bloğunun satırları gibi hizalı mı: ortaları, sol ya da sağ kenarları [ALIGN_TOLERANCE]
  /// içinde ya da satır öbürünün yatay kapsamının içinde.
  static func alignedRows(_ row: TextBox, _ anchor: TextBox) -> Bool {
    let centers: Double = abs((row.left + row.right) / 2 - (anchor.left + anchor.right) / 2)
    if centers <= ALIGN_TOLERANCE { return true }
    if abs(row.left - anchor.left) <= ALIGN_TOLERANCE || abs(row.right - anchor.right) <= ALIGN_TOLERANCE { return true }
    return row.left >= anchor.left - SIDE_MARGIN && row.right <= anchor.right + SIDE_MARGIN
  }

  private func unitReason(_ shape: TextBox, speech: Bool, outside: Bool) -> SubtitleOnlyReason? {
    let centerX: Double = (shape.left + shape.right) / 2
    let centerY: Double = (shape.top + shape.bottom) / 2
    let centered: Bool = abs(centerX - 0.5) <= SubtitleOnlyFilter.CENTER_TOLERANCE
    var aligned = false
    if let current = band, current.layout == SubtitleBand.Layout.left {
      aligned = abs(shape.left - current.leftEdge) <= SubtitleOnlyFilter.LEFT_EDGE_TOLERANCE
    }
    let atEdge: Bool = centerX < SubtitleOnlyFilter.EDGE_CENTER || centerX > 1 - SubtitleOnlyFilter.EDGE_CENTER
    if atEdge && !aligned { return SubtitleOnlyReason.edge }
    guard let current = band else { return nil }
    if outside {
      // Bandın dışında: ortalı (ya da sola yaslı bantta hizalı) konuşma/cümle kabul. Altyazı yeri değişmiş olabilir:
      // son kabul edilen bant dışı altyazıyla aynı yükseklikteki ortalı kısa satır da kabul (yeniden öğrenilirken).
      if (centered || aligned) && speech { return nil }
      if centered, let last = outsideRun.last, abs(centerY - last.centerY) <= SubtitleOnlyFilter.CLUSTER_SPAN { return nil }
      return SubtitleOnlyReason.outsideBand
    }
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
        // Bu görünümünde TV'ye gönderilmiş yazı (altyazı) sabit yazı hafızasına hiç girmez.
        if !fixtures[index].shownNow && now - fixtures[index].appearedAt >= SubtitleOnlyFilter.STATIC_MS {
          fixtures[index].unchanging = true
        }
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
      if same {
        fixtures[index].shownNow = true
        fixtures[index].unchanging = false
      }
    }
    // Bir satır gösterildi: bant işini görüyor (emniyet supabı sayacı sıfırlanır).
    suspectSince = nil
    lastSuspectAt = nil
    var note = SubtitleOnlyShown(learning: SubtitleOnlyShown.Learning.unmatched, sample: nil, lineHeight: nil,
                                 outsideRun: outsideRun.count, bandChanged: false)
    // Yalnız konuşma/cümle biçimli gösterim bant öğretir (menü öğesi, başlık, kısa etiketsiz yazı öğretmez).
    guard SubtitleOnlyFilter.isSpeech(source) else {
      note.learning = SubtitleOnlyShown.Learning.notSpeech
      return note
    }
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
    case SubtitleOnlyShown.Learning.notSpeech: return "not-speech"
    }
  }
}
