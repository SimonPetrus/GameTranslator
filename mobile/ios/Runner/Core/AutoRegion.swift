// SPDX-License-Identifier: AGPL-3.0-only
// Otomatik altyazı alanı (yalnız iOS'ta, ayarlardan açılır): tam karede aralıklı okunan satırlardan altyazının hangi yatay
// şeritte durduğunu öğrenir. Saf mantık (zaman damgası girer, karar çıkar; Vision, saat ve iş parçacığı yok).
// Fikir: altyazı metni birkaç saniyede bir değişir ama aynı şeritte, yaklaşık ortada durur ve cümle gibidir;
// sabit yazı (HUD, menü, skor), düğme ipuçları, çok küçük/büyük yazı ve köşelerdeki yazı altyazı sayılmaz.
import Foundation

/// Tam karede okunan bir satır; konum ekrana oranla (0–1), sol üstten.
struct AutoRegionLine: Equatable {
  var text: String
  var left: Double
  var top: Double
  var right: Double
  var bottom: Double
  var confidence: Double = 1

  var height: Double { bottom - top }
  var width: Double { right - left }
  var centerX: Double { (left + right) / 2 }
  var centerY: Double { (top + bottom) / 2 }
}

/// Okunacak şerit, ekrana oranla (0–1): Region ile aynı anlam.
struct AutoRegionBand: Equatable {
  var top: Double
  var bottom: Double
  var left: Double
  var right: Double
}

enum AutoRegionEvent: Equatable {
  case none
  /// Şerit ilk kez bulundu.
  case locked(AutoRegionBand)
  /// Kilitli şerit belirgin biçimde genişledi ya da kaydı.
  case adjusted(AutoRegionBand)
  /// Uzun süre okuma olmadı; kilit düştü, yeniden aranır.
  case unlocked
}

struct AutoRegionFinder {
  // MARK: - Sabitler

  /// Şerit aranırken ve kilitliyken tam kare taramaları arasında en az bu kadar ms.
  static let SCAN_SEARCH_MS: Int64 = 2000
  static let SCAN_LOCKED_MS: Int64 = 15000
  /// Taranan görüntünün uzun kenarı en çok bu kadar piksel.
  static let SCAN_MAX_SIDE = 960
  /// Kilit için aynı şeritte görülmesi gereken farklı altyazı sayısı ve bunların sayıldığı pencere.
  static let LOCK_HITS = 3
  static let HIT_WINDOW_MS: Int64 = 90_000
  /// Aynı metin aynı yerde bu süreden uzun kalırsa sabit yazıdır (HUD, menü).
  static let STATIC_MS: Int64 = 20_000
  /// Kilitli şeritte bu süre okuma olmazsa kilit düşer.
  static let UNLOCK_QUIET_MS: Int64 = 20_000
  /// Bir iz bu kadar süre görülmezse unutulur; en çok bu kadar iz tutulur.
  static let TRACK_TTL_MS: Int64 = 120_000
  static let MAX_TRACKS = 12
  /// İz taramada görünmediğinde "şu anki metin" bu süreden sonra unutulur (tek tarama kaçırması sabitliği bozmasın).
  static let GAP_MS: Int64 = 6000

  // Satır ve blok süzgeçleri (ekrana oranla).
  static let MIN_CONFIDENCE = 0.3
  static let MIN_LINE_HEIGHT = 0.015
  static let MAX_LINE_HEIGHT = 0.09
  static let MAX_BLOCK_HEIGHT = 0.25
  static let MAX_CENTER_OFFSET = 0.22
  static let EDGE_CENTER = 0.12
  static let CORNER_X = 0.25
  static let CORNER_Y = 0.10
  /// Ekranın dikey ortasındaki bu aralıktaki yazı altyazı sayılmaz (üstte ve altta olabilir).
  static let MIDDLE_FROM = 0.32
  static let MIDDLE_TO = 0.5
  static let MIN_WORDS = 3
  static let MIN_LETTERS = 10
  static let MIN_LOWER_RATIO = 0.4
  /// İki metin bu sözcük benzerliğinden (Jaccard) fazlaysa aynı sayılır.
  static let SAME_TEXT = 0.6
  /// Bir iz (aynı şeritteki yazılar) en çok bu kadar yüksek olabilir.
  static let MAX_TRACK_HEIGHT = 0.30

  // Şerit payları.
  static let PAD_LINES = 1.0
  static let PAD_X = 0.10
  static let MIN_WIDTH = 0.60
  static let MIN_HEIGHT = 0.12
  /// Kilitli şerit yalnız bu kadardan çok değişirse güncellenir; içe (daralma) doğru adımın bu oranı atılır.
  static let ADJUST_DEADBAND = 0.03
  static let OUTWARD_DEADBAND = 0.01
  static let SHRINK_STEP = 0.25

  // MARK: - Satır süzgeci

  enum Verdict: Equatable {
    case accepted, lowConfidence, tooSmall, tooLarge, corner, prompt, garbled, empty
  }

  /// Tek satır altyazı adayı olabilir mi? Kabulde temizlenmiş metin de döner.
  static func screenLine(_ line: AutoRegionLine) -> (verdict: Verdict, text: String) {
    if line.confidence < MIN_CONFIDENCE { return (.lowConfidence, "") }
    if line.height < MIN_LINE_HEIGHT { return (.tooSmall, "") }
    if line.height > MAX_LINE_HEIGHT { return (.tooLarge, "") }
    let cx = line.centerX, cy = line.centerY
    if cx < EDGE_CENTER || cx > 1 - EDGE_CENTER { return (.corner, "") }
    if (cx < CORNER_X || cx > 1 - CORNER_X) && (cy < CORNER_Y || cy > 1 - CORNER_Y) { return (.corner, "") }
    let cleaned = OcrNoise.clean(line.text).trimmingCharacters(in: .whitespacesAndNewlines)
    if cleaned.isEmpty { return (.empty, "") }
    let stripped = ButtonHints.strip(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
    if stripped.isEmpty { return (.prompt, "") }
    if OcrNoise.looksGarbled(stripped) { return (.garbled, "") }
    return (.accepted, stripped)
  }

  /// Cümle gibi mi: birkaç sözcük, yeterince harf, küçük harf ağırlığı ya da cümle sonu işareti.
  static func isSentenceLike(_ text: String) -> Bool {
    let words = text.split(whereSeparator: { (c: Character) in c == " " || c == "\n" || c == "\t" })
      .filter { (word: Substring) in word.contains(where: { (c: Character) in c.isLetter }) }
    if words.count < MIN_WORDS { return false }
    var letters = 0, lower = 0, visible = 0
    for ch in text where !ch.isWhitespace {
      visible += 1
      if ch.isLetter {
        letters += 1
        if ch.isLowercase { lower += 1 }
      }
    }
    if letters < MIN_LETTERS || Double(letters) < 0.6 * Double(visible) { return false }
    let endsLikeSentence = text.last.map { ".!?…\"”'’".contains($0) } ?? false
    return Double(lower) / Double(letters) >= MIN_LOWER_RATIO || endsLikeSentence
  }

  // MARK: - Bloklar

  /// Alt alta duran satırlardan oluşan altyazı bloğu.
  struct Block: Equatable {
    var text: String
    var left: Double
    var top: Double
    var right: Double
    var bottom: Double
    /// Satırların ortanca yüksekliği.
    var lineHeight: Double

    var centerX: Double { (left + right) / 2 }
    var centerY: Double { (top + bottom) / 2 }
  }

  /// Süzgeçten geçen satırları yakınlığa göre bloklara ayırır; yalnız altyazı gibi görünen bloklar döner (yukarıdan aşağı).
  static func blocks(from lines: [AutoRegionLine]) -> [Block] {
    var accepted: [(line: AutoRegionLine, text: String)] = []
    for line in lines {
      let screened = screenLine(line)
      if screened.verdict == .accepted { accepted.append((line, screened.text)) }
    }
    accepted.sort { $0.line.top < $1.line.top }
    var groups: [[(line: AutoRegionLine, text: String)]] = []
    for item in accepted {
      var joined = false
      for index in groups.indices {
        guard let reach = groups[index].map({ $0.line.bottom }).max(),
              let tallest = groups[index].map({ $0.line.height }).max() else { continue }
        let gap = item.line.top - reach
        let near = gap <= max(tallest, item.line.height)
        let overlaps = groups[index].contains { member in
          min(member.line.right, item.line.right) > max(member.line.left, item.line.left)
        }
        if near && overlaps && gap > -3 * max(tallest, item.line.height) {
          groups[index].append(item)
          joined = true
          break
        }
      }
      if !joined { groups.append([item]) }
    }
    var result: [Block] = []
    for group in groups {
      let block = makeBlock(group)
      if isEligible(block) { result.append(block) }
    }
    return result.sorted { $0.top < $1.top }
  }

  /// Aynı satırdaki parçalar soldan sağa, satırlar yukarıdan aşağı birleşir.
  private static func makeBlock(_ group: [(line: AutoRegionLine, text: String)]) -> Block {
    let sorted = group.sorted { $0.line.centerY < $1.line.centerY }
    var rows: [[(line: AutoRegionLine, text: String)]] = []
    for item in sorted {
      if let first = rows.last?.first, abs(item.line.centerY - first.line.centerY) < max(first.line.height, item.line.height) / 2 {
        rows[rows.count - 1].append(item)
      } else {
        rows.append([item])
      }
    }
    let text = rows.map { row in row.sorted { $0.line.left < $1.line.left }.map { $0.text }.joined(separator: " ") }
      .joined(separator: "\n")
    let heights = group.map { $0.line.height }.sorted()
    return Block(text: text,
                 left: group.map { $0.line.left }.min() ?? 0, top: group.map { $0.line.top }.min() ?? 0,
                 right: group.map { $0.line.right }.max() ?? 0, bottom: group.map { $0.line.bottom }.max() ?? 0,
                 lineHeight: heights[heights.count / 2])
  }

  /// Blok altyazı olabilir mi: yaklaşık ortalı, cümle gibi, ekranın dikey ortasında değil, çok yüksek değil.
  static func isEligible(_ block: Block) -> Bool {
    if abs(block.centerX - 0.5) > MAX_CENTER_OFFSET { return false }
    if block.bottom - block.top > MAX_BLOCK_HEIGHT { return false }
    if block.centerY > MIDDLE_FROM && block.centerY < MIDDLE_TO { return false }
    return isSentenceLike(block.text)
  }

  // MARK: - Metin benzerliği

  /// Harf ve rakamlardan oluşan küçük harfli sözcük kümesi.
  static func wordSet(_ text: String) -> Set<String> {
    var words = Set<String>()
    var current = ""
    for ch in text.lowercased() {
      if ch.isLetter || ch.isNumber {
        current.append(ch)
      } else if !current.isEmpty {
        words.insert(current)
        current = ""
      }
    }
    if !current.isEmpty { words.insert(current) }
    return words
  }

  /// İki metin aynı altyazının (küçük okuma farkları, harf harf beliren yazı) iki hâli mi?
  static func isSameText(_ a: String, _ b: String) -> Bool {
    let x = wordSet(a), y = wordSet(b)
    if x.isEmpty || y.isEmpty { return false }
    let shared = x.intersection(y).count
    let union = x.count + y.count - shared
    if Double(shared) / Double(union) >= SAME_TEXT { return true }
    // Biri ötekinin içinde kalıyorsa (kelime kelime beliren altyazı) aynıdır.
    return min(x.count, y.count) >= 2 && Double(shared) / Double(min(x.count, y.count)) >= 0.9
  }

  // MARK: - Şerit hesabı

  /// İzin kapladığı alandan okunacak şerit: üst ve altta ~1 satır pay, yanlarda geniş pay, en az genişlik ve yükseklik;
  /// hepsi 0–1 içinde.
  static func makeBand(top: Double, bottom: Double, left: Double, right: Double, lineHeight: Double) -> AutoRegionBand {
    let line = max(lineHeight, 0.02)
    var t = top - PAD_LINES * line, b = bottom + PAD_LINES * line
    var l = left - PAD_X, r = right + PAD_X
    (t, b) = fit(t, b, minimum: MIN_HEIGHT)
    (l, r) = fit(l, r, minimum: MIN_WIDTH)
    return AutoRegionBand(top: t, bottom: b, left: l, right: r)
  }

  /// [low, high] aralığını en az [minimum] uzunlukta yapar (ortası korunarak) ve 0–1'e sığdırır (kaydırarak).
  private static func fit(_ low: Double, _ high: Double, minimum: Double) -> (Double, Double) {
    var l = low, h = high
    if h - l < minimum {
      let c = (l + h) / 2
      l = c - minimum / 2
      h = c + minimum / 2
    }
    if l < 0 { h -= l; l = 0 }
    if h > 1 { l -= h - 1; h = 1 }
    return (max(0, l), min(1, h))
  }

  /// Kilitli şerit yeni hedefe doğru kayar: dışa doğru (genişleme) hemen, içe doğru (daralma) yavaş adımlarla;
  /// küçük oynamalar yok sayılır. Değişiklik yoksa nil.
  static func blend(_ current: AutoRegionBand, toward target: AutoRegionBand) -> AutoRegionBand? {
    func edge(_ now: Double, _ goal: Double, outwardIsLower: Bool) -> Double {
      let outward = outwardIsLower ? now - goal : goal - now
      if outward > OUTWARD_DEADBAND { return goal }
      let inward = -outward
      if inward > ADJUST_DEADBAND { return now + (goal - now) * SHRINK_STEP }
      return now
    }
    let next = AutoRegionBand(top: edge(current.top, target.top, outwardIsLower: true),
                              bottom: edge(current.bottom, target.bottom, outwardIsLower: false),
                              left: edge(current.left, target.left, outwardIsLower: true),
                              right: edge(current.right, target.right, outwardIsLower: false))
    return next == current ? nil : next
  }

  /// Tarama görüntüsünün boyutu: uzun kenar [SCAN_MAX_SIDE]'ı geçmez; küçük kare büyütülmez.
  static func scanSize(width: Int, height: Int) -> (width: Int, height: Int) {
    let longest = max(width, height)
    guard longest > SCAN_MAX_SIDE, width > 0, height > 0 else { return (width, height) }
    let scale = Double(SCAN_MAX_SIDE) / Double(longest)
    return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
  }

  // MARK: - Durum

  /// Aynı şeritte duran yazıların izi.
  private struct Seen {
    var text: String
    var at: Int64
  }

  private struct Track {
    var top: Double
    var bottom: Double
    var left: Double
    var right: Double
    var lineHeight: Double
    var lastSeen: Int64
    var current: String
    var currentSince: Int64
    var seen: [Seen]
    var hits: [Int64]
    var isStatic = false

    var centerX: Double { (left + right) / 2 }
    var centerY: Double { (top + bottom) / 2 }

    func activeHits(at now: Int64) -> Int { hits.filter { now - $0 <= AutoRegionFinder.HIT_WINDOW_MS }.count }
  }

  /// Kilitli şerit; yoksa aranıyor.
  private(set) var band: AutoRegionBand?
  var isLocked: Bool { band != nil }

  private var tracks: [Track] = []
  private var lastScanAt: Int64?
  private var lastActivityAt: Int64 = 0

  /// Tam kare taraması şimdi yapılabilir mi (aranırken ~2 sn, kilitliyken ~15 sn aralıkla)?
  func scanDue(at now: Int64) -> Bool {
    guard let last = lastScanAt else { return true }
    return now - last >= (isLocked ? AutoRegionFinder.SCAN_LOCKED_MS : AutoRegionFinder.SCAN_SEARCH_MS)
  }

  /// Tarama başladı (okuma başarısız olsa da bir sonraki tarama aralığa uyar).
  mutating func markScan(at now: Int64) { lastScanAt = now }

  /// Kilitli şeritte gerçek bir okuma oldu (normal okumanın boş olmayan sonucu).
  mutating func noteReading(at now: Int64) {
    if isLocked { lastActivityAt = now }
  }

  /// Her şey unutulur (akış ya da ayar değişti).
  mutating func reset() {
    band = nil
    tracks.removeAll()
    lastScanAt = nil
    lastActivityAt = 0
  }

  /// Kilitliyken şeritte uzun süredir okuma yoksa kilidi düşürür ve aramaya başlar (izler silinir; eski kanıtla hemen yeniden
  /// kilitlenip titremesin).
  mutating func checkIdle(at now: Int64) -> AutoRegionEvent {
    guard isLocked, now - lastActivityAt >= AutoRegionFinder.UNLOCK_QUIET_MS else { return .none }
    band = nil
    tracks.removeAll()
    return .unlocked
  }

  /// Tam karede okunan satırlar girer. Kilit kurulur, şerit genişler/kayar ya da (sessizlikte) düşer.
  mutating func ingest(_ lines: [AutoRegionLine], at now: Int64) -> AutoRegionEvent {
    let idle = checkIdle(at: now)
    prune(at: now)
    var touched = Set<Int>()
    var inBand = false
    for block in AutoRegionFinder.blocks(from: lines) {
      let index = update(with: block, at: now)
      touched.insert(index)
      if let current = band, !tracks[index].isStatic, tracks[index].centerY >= current.top, tracks[index].centerY <= current.bottom {
        inBand = true
      }
    }
    for index in tracks.indices where !touched.contains(index) && now - tracks[index].lastSeen > AutoRegionFinder.GAP_MS {
      tracks[index].current = ""
    }
    // Çok iz birikirse en eski görülenler atılır (indeksler artık kullanılmıyor).
    while tracks.count > AutoRegionFinder.MAX_TRACKS {
      guard let oldest = tracks.indices.min(by: { tracks[$0].lastSeen < tracks[$1].lastSeen }) else { break }
      tracks.remove(at: oldest)
    }
    if let current = band {
      if inBand { lastActivityAt = now }
      guard let best = bestTrack(at: now, minimumHits: 1, inside: current), let moved = AutoRegionFinder.blend(current, toward: Self.bandFor(best)) else {
        return idle
      }
      band = moved
      return .adjusted(moved)
    }
    guard let winner = bestTrack(at: now, minimumHits: AutoRegionFinder.LOCK_HITS, inside: nil) else { return idle }
    let found = Self.bandFor(winner)
    band = found
    lastActivityAt = now
    return .locked(found)
  }

  private static func bandFor(_ track: Track) -> AutoRegionBand {
    makeBand(top: track.top, bottom: track.bottom, left: track.left, right: track.right, lineHeight: track.lineHeight)
  }

  /// Sabit olmayan, yeterince kanıtlı en iyi iz: farklı altyazı sayısı, alt yarıya ve ortaya yakınlık puanı artırır.
  private func bestTrack(at now: Int64, minimumHits: Int, inside region: AutoRegionBand?) -> Track? {
    var best: (track: Track, score: Double)?
    for track in tracks where !track.isStatic && track.activeHits(at: now) >= minimumHits {
      if let region, track.centerY < region.top || track.centerY > region.bottom { continue }
      let score = Double(track.activeHits(at: now)) + (track.centerY > 0.5 ? 1.0 : 0.0) + (1 - abs(track.centerX - 0.5) * 2) * 0.5
      if best == nil || score > best!.score { best = (track, score) }
    }
    return best?.track
  }

  /// Bloğu en uygun ize işler (yoksa yeni iz açar); iz sırasını döner.
  private mutating func update(with block: Block, at now: Int64) -> Int {
    var matched: Int?
    var overlapBest = 0.0
    for index in tracks.indices {
      let t = tracks[index]
      let overlap = min(t.bottom, block.bottom) - max(t.top, block.top)
      let smaller = min(t.bottom - t.top, block.bottom - block.top)
      guard smaller > 0, overlap / smaller >= 0.4 else { continue }
      let height = max(t.bottom, block.bottom) - min(t.top, block.top)
      if height > AutoRegionFinder.MAX_TRACK_HEIGHT { continue }
      if overlap > overlapBest { overlapBest = overlap; matched = index }
    }
    guard let index = matched else {
      tracks.append(Track(top: block.top, bottom: block.bottom, left: block.left, right: block.right, lineHeight: block.lineHeight,
                          lastSeen: now, current: block.text, currentSince: now,
                          seen: [Seen(text: block.text, at: now)], hits: [now]))
      return tracks.count - 1
    }
    tracks[index].top = min(tracks[index].top, block.top)
    tracks[index].bottom = max(tracks[index].bottom, block.bottom)
    tracks[index].left = min(tracks[index].left, block.left)
    tracks[index].right = max(tracks[index].right, block.right)
    tracks[index].lineHeight = block.lineHeight
    tracks[index].lastSeen = now
    if AutoRegionFinder.isSameText(tracks[index].current, block.text) {
      tracks[index].current = block.text
      if now - tracks[index].currentSince > AutoRegionFinder.STATIC_MS { tracks[index].isStatic = true }
    } else {
      tracks[index].current = block.text
      tracks[index].currentSince = now
      // Sabit sayılan yerde yazı değişti: sabitlik o metne aitti; kanıt yeniden başlar (aynı yerdeki altyazı kilitlenebilsin).
      if tracks[index].isStatic {
        tracks[index].isStatic = false
        tracks[index].seen.removeAll()
        tracks[index].hits.removeAll()
      }
      let known = tracks[index].seen.contains { now - $0.at <= AutoRegionFinder.HIT_WINDOW_MS && AutoRegionFinder.isSameText($0.text, block.text) }
      if !known {
        tracks[index].seen.append(Seen(text: block.text, at: now))
        tracks[index].hits.append(now)
      }
    }
    return index
  }

  /// Eski kanıtlar ve görülmeyen izler atılır.
  private mutating func prune(at now: Int64) {
    tracks.removeAll { now - $0.lastSeen > AutoRegionFinder.TRACK_TTL_MS }
    for index in tracks.indices {
      tracks[index].hits.removeAll { now - $0 > AutoRegionFinder.HIT_WINDOW_MS }
      tracks[index].seen.removeAll { now - $0.at > AutoRegionFinder.HIT_WINDOW_MS }
    }
  }
}
