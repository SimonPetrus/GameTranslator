// SPDX-License-Identifier: AGPL-3.0-only
// Örtme (cover) yerleşiminde TV'ye giden kutu (box), örtülen alan (source), satır yüksekliği (line) ve satır kutularını
// (rows) kareden kareye oynatmadan tutar (yalnız iOS'ta; Kotlin karşılığı yok). Saf mantık: zaman damgası girer.
// Neden: 1.8.5'te aynı altyazının düzeltilmiş okuması, ek alan gösteriminden dönüş ve okuma kutusunun pikselce oynaması
// TV'deki kutuyu ve yazı boyunu değiştiriyordu; satır yüksekliği izleyicisi kısa sürede tabela gibi büyük yazıyla
// dolabiliyor, ölçüm kaybolunca da TV ayardaki (çoğu zaman daha büyük) boya dönüyordu ("ani büyüme").
import Foundation

/// TV'ye gidecek bir satırın ham değerleri (ServerSink verir).
struct CoverRequest {
  var text: String
  var box: TextBox
  /// LineHeight.toSend'den geçmiş değer (bilinmiyorsa ya da "oyunun yazı boyuna uy" kapalıysa nil).
  var line: Double?
  var matchGameTextSize: Bool
  /// Çevirinin okunan metne uzunluk oranı; bilinmiyorsa nil (alan genişletilmez, 1.8.5'teki gibi).
  var widenRatio: Double?
  /// Hattın konuşma kutuları; en az iki ise gider (1.8.5'teki kural).
  var rows: [TextBox]?
  var replaces: Bool
}

/// Kararın gerekçeleri (tanı kaydı).
enum CoverNote: Equatable {
  /// Aynı okuma ve aynı metin yeniden gönderildi (ek alan gösteriminden dönüş): önceki çerçevenin aynısı.
  case repeated
  /// Aynı altyazının düzeltilmiş okuması, kutu anlamlı değişmedi: sabitlenmiş kutu.
  case pinned
  /// Aynı altyazının okuması kutunun dışına taştı: kutu birleşimle büyüdü (küçülmez).
  case grown
  /// Aynı altyazı başka yere geçti: yeni kutu.
  case moved
  /// Yeni satır, kutusu öncekiyle pikselce aynı yerde: önceki kutu (titreme yok).
  case steady
  /// Aynı altyazı: satır yüksekliği sabit.
  case linePinned
  /// Ölçüm yok: son gönderilen satır yüksekliği (TV ayardaki boya sıçramasın).
  case lineKept
  /// Satır yüksekliği bir öncekinin [LineHeight.GROWTH_STEP] katıyla sınırlandı.
  case lineLimited
  /// Satır yüksekliği üst sınıra indirildi ([LineHeight.sendCap]).
  case lineCapped
  /// Kutu [CoverKeeper.MAX_BOX_HEIGHT]'tan yüksekti: kırpıldı, line ve rows gönderilmedi.
  case boxCapped

  var code: String {
    switch self {
    case .repeated: return "repeated"
    case .pinned: return "pinned"
    case .grown: return "grown"
    case .moved: return "moved"
    case .steady: return "steady"
    case .linePinned: return "line-pinned"
    case .lineKept: return "line-kept"
    case .lineLimited: return "line-limited"
    case .lineCapped: return "line-capped"
    case .boxCapped: return "box-capped"
    }
  }
}

/// TV'ye gidecek kararlı değerler.
struct CoverPlacement: Equatable {
  var box: TextBox
  var source: TextBox
  var line: Double?
  var rows: [SubtitleRow]?
  var notes: [CoverNote]
}

struct CoverKeeper {
  /// Kenarları bu kadar (ekrana oranla) oynayan kutu aynı sayılır.
  static let PIN_TOLERANCE = 0.015
  /// Yeni satır öncekinden en çok bu kadar ms sonra geliyorsa aynı yerdeki kutusu öncekine sabitlenir.
  static let CONTINUE_MS: Int64 = 4000
  /// Birleşik kutunun en büyük yüksekliği (tam kareye oranla); aşılırsa kırpılır, line gönderilmez.
  static let MAX_BOX_HEIGHT = 0.20

  /// Öğrenilmiş altyazı bandı (dikey) ve tipik satır yüksekliği: "Yalnız altyazıyı çevir" açıkken okuyucu verir; yoksa nil.
  var bandTop: Double?
  var bandBottom: Double?
  var typicalLine: Double?

  private var lastText: String?
  private var lastInputBox: TextBox?
  /// Son seçilen kutu ve örtülen alan (kırpmadan önce).
  private var lastChosen: TextBox?
  private var lastSource: TextBox?
  private var lastOutput: CoverPlacement?
  private var lastAt: Int64?
  /// Son gönderilen satır yüksekliği (temizlemelerde kalır; ardışık satırlar arası yumuşatma için).
  private var lastLine: Double?

  init() {}

  /// Akış ya da ayar değişti: her şey unutulur.
  mutating func reset() {
    lastText = nil
    lastInputBox = nil
    lastChosen = nil
    lastSource = nil
    lastOutput = nil
    lastAt = nil
    lastLine = nil
  }

  mutating func place(_ r: CoverRequest, at now: Int64) -> CoverPlacement {
    if let output = lastOutput, let box = lastInputBox, let text = lastText, box == r.box, KotlinText.same(text, r.text) {
      var again: CoverPlacement = output
      again.notes = [CoverNote.repeated]
      lastAt = now
      return again
    }
    var notes: [CoverNote] = []
    var recent = false
    if let at = lastAt { recent = now >= at && now - at <= CoverKeeper.CONTINUE_MS }
    let sameSubtitle: Bool = lastChosen != nil && (r.replaces || lastInputBox == r.box)
    var box: TextBox = r.box
    var keptPlace = false
    if let pinned = lastChosen {
      if sameSubtitle {
        if CoverKeeper.contains(CoverKeeper.expanded(pinned, by: CoverKeeper.PIN_TOLERANCE), r.box) {
          box = pinned
          keptPlace = true
          notes.append(CoverNote.pinned)
        } else if CoverKeeper.overlapsVertically(pinned, r.box) {
          box = CoverKeeper.union(pinned, r.box)
          keptPlace = true
          notes.append(CoverNote.grown)
        } else {
          notes.append(CoverNote.moved)
        }
      } else if recent && CoverKeeper.near(pinned, r.box, CoverKeeper.PIN_TOLERANCE) {
        box = pinned
        notes.append(CoverNote.steady)
      }
    }
    var source: TextBox = box
    if let ratio = r.widenRatio { source = CoverKeeper.widened(box, ratio: ratio) }
    if keptPlace, let previous = lastSource {
      // Aynı altyazının örtülen alanı küçülmez (oyunun yazısı açıkta kalmasın), pikselce oynamaz.
      source = CoverKeeper.contains(CoverKeeper.expanded(previous, by: CoverKeeper.PIN_TOLERANCE), source)
        ? previous : CoverKeeper.union(previous, source)
    }
    var line: Double? = nil
    if r.matchGameTextSize {
      line = r.line
      if keptPlace, let previous = lastOutput?.line {
        line = previous
        notes.append(CoverNote.linePinned)
      } else {
        if line == nil, let previous = lastLine {
          line = previous
          notes.append(CoverNote.lineKept)
        }
        if let value = line, let previous = lastLine, value > previous * LineHeight.GROWTH_STEP {
          line = previous * LineHeight.GROWTH_STEP
          notes.append(CoverNote.lineLimited)
        }
      }
      let cap: Double = LineHeight.sendCap(typical: typicalLine)
      if let value = line, value > cap {
        line = cap
        notes.append(CoverNote.lineCapped)
      }
    }
    var outBox: TextBox = box
    var outSource: TextBox = source
    var rows: [SubtitleRow]? = nil
    if box.bottom - box.top > CoverKeeper.MAX_BOX_HEIGHT {
      notes.append(CoverNote.boxCapped)
      line = nil
      outBox = clipped(box)
      outSource = TextBox(left: source.left, top: outBox.top, right: source.right, bottom: outBox.bottom)
    } else if let list = r.rows, list.count >= 2 {
      var built: [SubtitleRow] = []
      for b in list { built.append(SubtitleRow(box: b, line: line)) }
      rows = built
    }
    let placed = CoverPlacement(box: outBox, source: outSource, line: line, rows: rows, notes: notes)
    lastText = r.text
    lastInputBox = r.box
    lastChosen = box
    lastSource = source
    lastOutput = placed
    lastAt = now
    if let line { lastLine = line }
    return placed
  }

  /// Yüksek kutu öğrenilmiş bantla kırpılır; bant yoksa (ya da kutu bandın dışındaysa) alt kenarı korunarak
  /// [MAX_BOX_HEIGHT]'a indirilir (altyazı çoğunlukla altta, son satır en alttadır).
  func clipped(_ box: TextBox) -> TextBox {
    var top: Double = box.top
    var bottom: Double = box.bottom
    if let bandTop, let bandBottom, bandBottom > bandTop {
      let t: Double = max(top, bandTop)
      let b: Double = min(bottom, bandBottom)
      if b > t {
        top = t
        bottom = b
      }
    }
    if bottom - top > CoverKeeper.MAX_BOX_HEIGHT { top = bottom - CoverKeeper.MAX_BOX_HEIGHT }
    return TextBox(left: box.left, top: max(0, top), right: box.right, bottom: bottom)
  }

  /// Türkçe çoğu zaman İngilizceden uzundur: TV çeviriyi oyunun altyazısının genişliğine sığdıramayınca iki satıra
  /// bölüp küçültüyordu. Alan, çevirinin uzunluk oranında (%8 payla) iki yana genişletilir; ekranın %90'ını ve
  /// kenarları (%5) aşmaz. Çeviri daha kısaysa alan küçültülmez (oyunun altyazısı tamamen örtülsün).
  /// (1.8.5'te ServerSink.widened; aynı hesap.)
  static func widened(_ box: TextBox, ratio: Double) -> TextBox {
    let width: Double = box.right - box.left
    guard width > 0, ratio.isFinite else { return box }
    let target: Double = min(0.9, width * ratio * 1.08)
    guard target > width else { return box }
    let center: Double = (box.left + box.right) / 2
    var left: Double = center - target / 2
    var right: Double = center + target / 2
    // Bir kenara dayanırsa öbür yana kaydırılır.
    if left < 0.05 { right += 0.05 - left; left = 0.05 }
    if right > 0.95 { left -= right - 0.95; right = 0.95 }
    return TextBox(left: max(0.05, left), top: box.top, right: min(0.95, right), bottom: box.bottom)
  }

  static func union(_ a: TextBox, _ b: TextBox) -> TextBox {
    TextBox(left: min(a.left, b.left), top: min(a.top, b.top), right: max(a.right, b.right), bottom: max(a.bottom, b.bottom))
  }

  static func expanded(_ box: TextBox, by margin: Double) -> TextBox {
    TextBox(left: box.left - margin, top: box.top - margin, right: box.right + margin, bottom: box.bottom + margin)
  }

  /// [inner], [outer]'ın içinde mi.
  static func contains(_ outer: TextBox, _ inner: TextBox) -> Bool {
    inner.left >= outer.left && inner.top >= outer.top && inner.right <= outer.right && inner.bottom <= outer.bottom
  }

  /// Her kenar en çok [tolerance] kadar farklı.
  static func near(_ a: TextBox, _ b: TextBox, _ tolerance: Double) -> Bool {
    abs(a.left - b.left) <= tolerance && abs(a.top - b.top) <= tolerance && abs(a.right - b.right) <= tolerance
      && abs(a.bottom - b.bottom) <= tolerance
  }

  static func overlapsVertically(_ a: TextBox, _ b: TextBox) -> Bool {
    min(a.bottom, b.bottom) > max(a.top, b.top)
  }
}

/// Örtme kararının tanı biçimi (yalnız kayıt açıkken).
enum CoverDiag {
  static func fields(_ request: CoverRequest, _ placed: CoverPlacement) -> DiagValue {
    var codes: [String] = []
    for note in placed.notes { codes.append(note.code) }
    var fields = DiagFields()
    fields["notes"] = DiagValue.strings(codes)
    fields["boxIn"] = DiagValue.box(request.box)
    fields["lineIn"] = DiagValue.optional(request.line)
    fields["replaces"] = DiagValue.bool(request.replaces)
    fields["widenRatio"] = DiagValue.optional(request.widenRatio)
    return DiagValue.object(fields)
  }
}
