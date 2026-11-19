// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Yazı tanımanın bulduğu bir satır parçası; konum bölge piksellerinde, sol üstten.
struct TextObservation: Equatable {
  let text: String
  let confidence: Double
  let left: Int, top: Int, right: Int, bottom: Int
  /// Yazı satırının eğimi (derece; Vision'ın dörtgeninin üst kenarından). Bilinmiyorsa nil ("Yalnız altyazıyı çevir"
  /// süzgeci eğik dünya içi yazıyı ayırmak için kullanır; başka hiçbir kural bakmaz).
  var angle: Double? = nil

  var height: Int { bottom - top }
  var width: Int { right - left }
  var centerX: Double { Double(left + right) / 2 }
  var centerY: Double { Double(top + bottom) / 2 }
}

/// Bölgeden okunan parçalardan altyazıyı seçen saf kurallar (Vision'dan bağımsız, birim sınanır).
enum ReadingSelector {
  /// Bu güvenin altındaki parçalar yok sayılır.
  static let MIN_CONFIDENCE = 0.35
  /// En iyi parçanın güveni bunun altındaysa (ya da hiç parça yoksa) yakınlaştırılmış yeniden okuma denenir.
  static let RETRY_BELOW_CONFIDENCE = 0.5
  /// Yeniden okumada bölgenin yatay/dikey kenarlarından kırpılan oran ve büyütme katı.
  static let RETRY_INSET_X = 0.08
  static let RETRY_INSET_Y = 0.10
  static let RETRY_SCALE = 2.0
  /// Büyütülmüş görüntünün en çok genişliği (piksel); bant zaten bu kadar genişse büyütme küçülür ya da atlanır.
  static let RETRY_MAX_WIDTH = 2000
  /// Büyütme katı bundan küçük kalacaksa yeniden okuma atlanır (fayda yok, maliyet var).
  static let RETRY_MIN_SCALE = 1.25
  /// İlk okuma hiçbir şey bulmadıysa yeniden okuma yalnız son altyazıdan bu kadar ms içinde denenir.
  static let RETRY_RECENT_MS: Int64 = 3000
  /// Yeniden okumalar arasında en az bu kadar ms geçer (işlemci yükünü sınırlar).
  static let RETRY_MIN_INTERVAL_MS: Int64 = 2000
  /// Bölge kenarına bu orandan yakın dokunan parça kesik sayılır (en az 2 piksel).
  static let EDGE_MARGIN_RATIO = 0.004
  /// Aynı bloktaki iki satır arasındaki boşluk, ortanca satır yüksekliğinin bu katını aşarsa ayrı bloktur.
  static let BLOCK_GAP_LINES = 1.5

  // Blok puanı ağırlıkları.
  static let WEIGHT_CENTER = 0.35
  static let WEIGHT_BOTTOM = 0.25
  static let WEIGHT_HEIGHT = 0.20
  static let WEIGHT_WORDS = 0.10
  static let WEIGHT_CONFIDENCE = 0.10
  /// Sözcük puanı bu sözcük sayısında doyar.
  static let WORDS_FULL = 4

  /// Güveni düşük parçaları eler.
  static func filterConfidence(_ input: [TextObservation], minimum: Double = MIN_CONFIDENCE) -> [TextObservation] {
    input.filter { $0.confidence >= minimum && !$0.text.isEmpty }
  }

  /// Bölgenin yalnız bir kenarına dokunan (kesik görünen, başka arayüzden taşan) parçaları eler.
  /// İki kenara birden dokunan çok geniş parça korunur (gerçek bir uzun satır olabilir).
  static func dropEdgeCut(_ input: [TextObservation], width: Int) -> [TextObservation] {
    let margin = max(2, Int((Double(width) * EDGE_MARGIN_RATIO).rounded()))
    let kept = input.filter { o in
      let touchesLeft = o.left <= margin
      let touchesRight = o.right >= width - margin
      return touchesLeft == touchesRight
    }
    // Hepsi kesik görünüyorsa (dar bölge) tek gerçek satır yitirilmesin.
    return kept.isEmpty ? input : kept
  }

  /// Parçaları dikey yakınlığa göre bloklara ayırır (üstten alta).
  static func blocks(_ input: [TextObservation]) -> [[TextObservation]] {
    let sorted = input.sorted { $0.top < $1.top }
    guard !sorted.isEmpty else { return [] }
    let heights = sorted.map(\.height).sorted()
    let median = max(heights[heights.count / 2], 1)
    let maxGap = Double(median) * BLOCK_GAP_LINES
    var result: [[TextObservation]] = [[sorted[0]]]
    var reach = sorted[0].bottom
    for o in sorted.dropFirst() {
      if Double(o.top - reach) <= maxGap {
        result[result.count - 1].append(o)
        reach = max(reach, o.bottom)
      } else {
        result.append([o])
        reach = o.bottom
      }
    }
    return result
  }

  /// Bloğun altyazıya benzerlik puanı (0–1): ortalı, bölgenin altına yakın, satır yükseklikleri tutarlı,
  /// çok sözcüklü, güvenli.
  static func score(_ block: [TextObservation], width: Int, height: Int) -> Double {
    guard !block.isEmpty, width > 0, height > 0 else { return 0 }
    let left = Double(block.map(\.left).min()!), right = Double(block.map(\.right).max()!)
    let bottom = Double(block.map(\.bottom).max()!)
    let center = 1 - min(abs((left + right) / 2 - Double(width) / 2) / (Double(width) / 2), 1)
    let near = min(max(bottom / Double(height), 0), 1)
    let heights = block.map { Double($0.height) }
    let mean = heights.reduce(0, +) / Double(heights.count)
    var consistency = 1.0
    if mean > 0, heights.count > 1 {
      let variance = heights.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(heights.count)
      consistency = max(0, 1 - variance.squareRoot() / mean)
    }
    let words = block.reduce(0) { $0 + $1.text.split(separator: " ").count }
    let wordScore = min(Double(words) / Double(WORDS_FULL), 1)
    let confidence = block.map(\.confidence).reduce(0, +) / Double(block.count)
    return WEIGHT_CENTER * center + WEIGHT_BOTTOM * near + WEIGHT_HEIGHT * consistency
      + WEIGHT_WORDS * wordScore + WEIGHT_CONFIDENCE * confidence
  }

  /// Birden çok blok varsa altyazıya en çok benzeyeni seçer; tek blok olduğu gibi döner.
  static func pickBlock(_ input: [TextObservation], width: Int, height: Int) -> [TextObservation] {
    let found = blocks(input)
    if found.count <= 1 { return found.first ?? [] }
    var best = found[0]
    var bestScore = score(best, width: width, height: height)
    for block in found.dropFirst() {
      let s = score(block, width: width, height: height)
      if s > bestScore { best = block; bestScore = s }
    }
    return best
  }

  /// Tam seçim hattı: düşük güven elenir, kesik kenar parçaları atılır, altyazı bloğu seçilir.
  static func select(_ input: [TextObservation], width: Int, height: Int) -> [TextObservation] {
    pickBlock(dropEdgeCut(filterConfidence(input), width: width), width: width, height: height)
  }

  /// Seçim boşsa ya da en iyi parça güvensizse yeniden okuma gerekir.
  static func needsRetry(_ selected: [TextObservation]) -> Bool {
    guard let best = selected.map(\.confidence).max() else { return true }
    return best < RETRY_BELOW_CONFIDENCE
  }

  /// Yeniden okuma yapılsın mı. [rawCount]: ilk okumanın (süzmeden önceki) parça sayısı; [lastSubtitleAt]: son
  /// altyazı görülen an. Hiçbir şey bulunmadıysa yalnız altyazı az önce görülmüşse denenir (boş ekranda sürekli değil).
  static func shouldRetry(rawCount: Int, selected: [TextObservation], lastSubtitleAt: Int64?, now: Int64) -> Bool {
    if rawCount == 0 {
      guard let last = lastSubtitleAt, now >= last else { return false }
      return now - last <= RETRY_RECENT_MS
    }
    return needsRetry(selected)
  }

  /// Bant için büyütme katı: [RETRY_SCALE], ama büyütülmüş genişlik [RETRY_MAX_WIDTH]'i aşmasın.
  /// Kat [RETRY_MIN_SCALE]'in altında kalacaksa nil (yeniden okuma atlanır).
  static func retryScale(bandWidth: Int) -> Double? {
    guard bandWidth > 0 else { return nil }
    let scale = min(RETRY_SCALE, Double(RETRY_MAX_WIDTH) / Double(bandWidth))
    return scale >= RETRY_MIN_SCALE ? scale : nil
  }

  /// Yeniden okuma sonucu ilkinden daha iyiyse (ilk boşsa ya da ortalama güveni daha yüksekse) onu kullan.
  static func isBetter(_ retry: [TextObservation], than first: [TextObservation]) -> Bool {
    if retry.isEmpty { return false }
    if first.isEmpty { return true }
    return averageConfidence(retry) > averageConfidence(first)
  }

  static func averageConfidence(_ list: [TextObservation]) -> Double {
    list.isEmpty ? 0 : list.map(\.confidence).reduce(0, +) / Double(list.count)
  }

  /// Parçaları satırlara ayırır: yukarıdan aşağı, aynı hizadakiler (dikey ortası satırın ilk parçasına iki yükseklikten
  /// büyüğünün yarısından yakın) aynı satırda, soldan sağa (VisionReader.rows ile aynı kural).
  static func rows(_ input: [TextObservation]) -> [[TextObservation]] {
    var grouped: [[TextObservation]] = []
    for o in input.sorted(by: { $0.top < $1.top }) {
      if let reference = grouped.last?.first,
         abs((o.top + o.bottom) / 2 - (reference.top + reference.bottom) / 2) < max(reference.height, o.height) / 2 {
        grouped[grouped.count - 1].append(o)
      } else {
        grouped.append([o])
      }
    }
    return grouped.map { $0.sorted { $0.left < $1.left } }
  }

  /// Yeniden okunacak ortalanmış bant (bölge pikselinde): x, y, genişlik, yükseklik.
  static func retryBand(width: Int, height: Int) -> (x: Int, y: Int, width: Int, height: Int) {
    let x = Int((Double(width) * RETRY_INSET_X).rounded())
    let y = Int((Double(height) * RETRY_INSET_Y).rounded())
    return (x, y, max(width - 2 * x, 1), max(height - y, 1))
  }

  /// Vision'ın 0–1 (sol alttan) kutusunu, [imageWidth]×[imageHeight] görüntü içinde piksele (sol üstten) çevirir;
  /// [offsetX]/[offsetY]/[scale] görüntünün bölgedeki yeri ve büyütme katıdır (yeniden okuma için).
  static func pixels(minX: Double, minY: Double, maxX: Double, maxY: Double,
                     imageWidth: Int, imageHeight: Int, offsetX: Int = 0, offsetY: Int = 0, scale: Double = 1)
    -> (left: Int, top: Int, right: Int, bottom: Int) {
    let s = max(scale, 1)
    let left = Int((minX * Double(imageWidth) / s).rounded()) + offsetX
    let right = Int((maxX * Double(imageWidth) / s).rounded()) + offsetX
    let top = Int(((1 - maxY) * Double(imageHeight) / s).rounded()) + offsetY
    let bottom = Int(((1 - minY) * Double(imageHeight) / s).rounded()) + offsetY
    return (left, top, right, bottom)
  }
}

/// Oyun altyazısının tek satır yüksekliği (ekran yüksekliğine oranla). TV "örterek" yerleşiminde yazı boyunun üst
/// sınırını bundan alır; fazla büyük ölçüm yazıyı ayardaki boyun 1,6 katına kadar büyütüyordu. Tahmin güvenilmezse nil
/// (TV ayardaki boyu kullanır).
enum LineHeight {
  /// Bu aralığın dışındaki tahmin güvenilmez sayılır (1080p'de ~13–86 piksel).
  static let MIN_RATIO = 0.012
  static let MAX_RATIO = 0.08
  /// Yazı kutusu yüksekliğinin ortalama karakter genişliğine oranı tek satırda ~2,2–3,2'dir. k satırı kapsayan parçada
  /// yükseklik k, karakter sayısı da k katına çıktığı için oran ~k² katıdır: satır sayısı √(oran / 2,6)'dan bulunur.
  /// Oran yalnız bu kadar karakterden uzun parçada ölçülür.
  static let SINGLE_LINE_RATIO = 2.6
  static let MIN_CHARACTERS = 8
  /// Komşularının ortancasının bu katından uzun parça birden çok satır sayılır.
  static let TALL_FACTOR = 1.7

  /// Parçaların (aynı bloktaki satırlar, bölge pikselinde) tek satır yüksekliği / [frameHeight]; güvenilmezse nil.
  /// Hedef satırın gerçek kutu yüksekliğidir (TV yazı boyunu bunun 1,05 katıyla sınırlar). Uzun parça (en az
  /// [MIN_CHARACTERS] karakter) varsa yalnız uzun parçalara bakılır: "me", "so" gibi kısa ya da yalnız küçük harfli parça
  /// yazının gerçek boyundan alçaktır. Komşularının [TALL_FACTOR] katından uzun parça satır sayısına bölünür; kalanlardan
  /// üstteki ortanca alınır (alt çıkıntılı satır çıkıntısızdan biraz yüksektir; gerçek boy büyüğe yakındır).
  static func estimate(_ pieces: [TextObservation], frameHeight: Int) -> Double? {
    // Sıcak yol (her okumada): ara değer dizisi kurulmaz. [explain] aynı hesabı ara değerleriyle yapar; ikisinin aynı
    // sonucu verdiği CoreTests'te (DiagnosticFormatTest.lineHeightTraceMatchesEstimate) denetlenir.
    guard frameHeight > 0 else { return nil }
    let measured = pieces.filter { $0.height > 0 }
    let long = measured.filter { $0.text.count >= MIN_CHARACTERS && $0.width > 0 }
    let used = long.isEmpty ? measured : long
    let heights = used.map { piece -> Double in
      let h = Double(piece.height)
      guard piece.text.count >= MIN_CHARACTERS, piece.width > 0 else { return h }
      let ratio = h / (Double(piece.width) / Double(piece.text.count))
      let lines = (ratio / SINGLE_LINE_RATIO).squareRoot().rounded()
      return lines >= 2 ? h / lines : h
    }
    guard !heights.isEmpty else { return nil }
    let typical = lowerMedian(heights)
    // Komşularından belirgin uzun parça kaç satırsa ona bölünür.
    let single = heights.map { h -> Double in
      guard typical > 0, h >= typical * TALL_FACTOR else { return h }
      return h / (h / typical).rounded()
    }
    let ratio = upperMedian(single) / Double(frameHeight)
    return ratio >= MIN_RATIO && ratio <= MAX_RATIO ? ratio : nil
  }

  /// [estimate]'in bütün ara değerleri (yalnız tanı kaydı açıkken): aynı hesap, sonuç [Trace.result].
  struct Trace {
    struct Piece {
      let text: String
      let characters: Int
      let heightPx: Int
      let widthPx: Int
      /// Yükseklik / ortalama karakter genişliği; kısa parçada nil.
      let ratio: Double?
      /// Oran'dan bulunan satır sayısı (√(oran / 2,6) yuvarlanmış); kısa parçada nil.
      let linesGuess: Double?
      /// Bu parçanın tek satır yüksekliği (piksel; satır sayısına bölünmüş).
      let perLine: Double
    }

    var frameHeight = 0
    /// Uzun parça (≥ MIN_CHARACTERS) vardı ve yalnız onlar kullanıldı.
    var onlyLong = false
    var pieces: [Piece] = []
    /// Parça tek satır yüksekliklerinin küçük ortancası.
    var typical = 0.0
    /// Komşularının TALL_FACTOR katından uzun olanlar bölündükten sonraki değerler.
    var single: [Double] = []
    var upper = 0.0
    var ratio = 0.0
    /// Kabul aralığında mı (MIN_RATIO…MAX_RATIO).
    var inRange = false
    var result: Double?
  }

  static func explain(_ pieces: [TextObservation], frameHeight: Int) -> Trace {
    var trace = Trace()
    trace.frameHeight = frameHeight
    guard frameHeight > 0 else { return trace }
    let measured = pieces.filter { $0.height > 0 }
    let long = measured.filter { $0.text.count >= MIN_CHARACTERS && $0.width > 0 }
    let used = long.isEmpty ? measured : long
    trace.onlyLong = !long.isEmpty
    trace.pieces = used.map { piece -> Trace.Piece in
      let h = Double(piece.height)
      let characters = piece.text.count
      guard characters >= MIN_CHARACTERS, piece.width > 0 else {
        return Trace.Piece(text: piece.text, characters: characters, heightPx: piece.height, widthPx: piece.width,
                           ratio: nil, linesGuess: nil, perLine: h)
      }
      let ratio = h / (Double(piece.width) / Double(characters))
      let lines = (ratio / SINGLE_LINE_RATIO).squareRoot().rounded()
      return Trace.Piece(text: piece.text, characters: characters, heightPx: piece.height, widthPx: piece.width,
                         ratio: ratio, linesGuess: lines, perLine: lines >= 2 ? h / lines : h)
    }
    let heights = trace.pieces.map(\.perLine)
    guard !heights.isEmpty else { return trace }
    let typical = lowerMedian(heights)
    trace.typical = typical
    // Komşularından belirgin uzun parça kaç satırsa ona bölünür.
    let single = heights.map { h -> Double in
      guard typical > 0, h >= typical * TALL_FACTOR else { return h }
      return h / (h / typical).rounded()
    }
    trace.single = single
    trace.upper = upperMedian(single)
    let ratio = trace.upper / Double(frameHeight)
    trace.ratio = ratio
    trace.inRange = ratio >= MIN_RATIO && ratio <= MAX_RATIO
    trace.result = trace.inRange ? ratio : nil
    return trace
  }

  /// Tek parçanın tek satır yüksekliği (piksel): [estimate]'in parça kuralı (uzun parçada satır sayısına bölünür).
  /// "Yalnız altyazıyı çevir" süzgeci parçaları altyazının tipik satır yüksekliğiyle bununla karşılaştırır.
  static func perLine(_ piece: TextObservation) -> Double {
    let h: Double = Double(piece.height)
    let characters: Int = piece.text.count
    guard characters >= MIN_CHARACTERS, piece.width > 0 else { return h }
    let ratio: Double = h / (Double(piece.width) / Double(characters))
    let lines: Double = (ratio / SINGLE_LINE_RATIO).squareRoot().rounded()
    return lines >= 2 ? h / lines : h
  }

  // Örtme (cover) yerleşiminde TV'ye giden satır yüksekliğinin sınırları (CoverKeeper bunları kullanır; tek yer).
  /// Altyazının tipik satır yüksekliği bilinmiyorsa gönderilen en büyük değer (tam kare yüksekliğine oranla): 1.8.5'teki
  /// kabul sınırı ([MAX_RATIO]); büyüme adım sınırı ani sıçramayı zaten önler.
  static let MAX_SENT_RATIO: Double = 0.08
  /// Tipik satır yüksekliği biliniyorsa gönderilen en büyük değer onun bu katıdır (yine en çok [MAX_RATIO]).
  static let TYPICAL_CAP_FACTOR: Double = 1.5
  /// Ardışık iki altyazı arasında satır yüksekliği en çok bu katına çıkar (küçülme serbest).
  static let GROWTH_STEP: Double = 1.25

  /// Gönderilecek satır yüksekliğinin üst sınırı: tipik değer biliniyorsa onun [TYPICAL_CAP_FACTOR] katı (en çok
  /// [MAX_RATIO]), bilinmiyorsa [MAX_SENT_RATIO].
  static func sendCap(typical: Double?) -> Double {
    guard let typical, typical > 0 else { return MAX_SENT_RATIO }
    return min(MAX_RATIO, typical * TYPICAL_CAP_FACTOR)
  }

  /// Büyük olan ortanca (çift sayıda değerde üstteki).
  static func upperMedian(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
  }

  /// TV'ye gidecek satır yüksekliği: "Oyunun yazı boyuna uy" kapalıysa hiç gönderilmez (TV ayardaki boyu kullanır).
  static func toSend(_ tracked: Double?, matchGameTextSize: Bool) -> Double? {
    guard matchGameTextSize, let tracked, tracked > 0 else { return nil }
    return tracked
  }

  /// Küçük olan ortanca (çift sayıda değerde alttaki): büyük ölçüme kaymaz.
  static func lowerMedian(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted.isEmpty ? 0 : sorted[(sorted.count - 1) / 2]
  }
}

/// Satır yüksekliği tahminlerini kararlı tutar: son [capacity] güvenilir tahminin ortancası. Oyunun yazı boyu değişmez;
/// tek bir hatalı ölçüm yazıyı büyütüp küçültmesin, aynı altyazının okumaları arasında boy oynamasın.
struct LineHeightTracker {
  let capacity: Int
  private var recent: [Double] = []

  init(capacity: Int = 7) { self.capacity = max(1, capacity) }

  /// Yeni tahmini (nil: bu okumada güvenilir ölçüm yok) ekler; kullanılacak değeri döner (henüz yoksa nil).
  mutating func add(_ estimate: Double?) -> Double? {
    if let estimate, estimate > 0 {
      recent.append(estimate)
      if recent.count > capacity { recent.removeFirst(recent.count - capacity) }
    }
    return recent.isEmpty ? nil : LineHeight.lowerMedian(recent)
  }

  mutating func reset() { recent.removeAll() }

  /// Ortancası alınan son tahminler, eskiden yeniye (tanı kaydı).
  var window: [Double] { recent }
}

/// Yeniden okuma sıklığını sınırlar (saf; saat dışarıdan).
struct RetryLimiter {
  private var lastAt: Int64?
  let minInterval: Int64

  init(minInterval: Int64 = ReadingSelector.RETRY_MIN_INTERVAL_MS) { self.minInterval = minInterval }

  /// İzin varsa true verir ve anı kaydeder.
  mutating func allow(at time: Int64) -> Bool {
    if let last = lastAt, time - last < minInterval, time >= last { return false }
    lastAt = time
    return true
  }

  mutating func reset() { lastAt = nil }
}
