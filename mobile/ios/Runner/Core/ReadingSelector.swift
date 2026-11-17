// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Yazı tanımanın bulduğu bir satır parçası; konum bölge piksellerinde, sol üstten.
struct TextObservation: Equatable {
  let text: String
  let confidence: Double
  let left: Int, top: Int, right: Int, bottom: Int

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
