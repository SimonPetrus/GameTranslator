// SPDX-License-Identifier: AGPL-3.0-only
// TV'deki altyazı görünümü: stil alanları, `style` çerçevesi, konuşmacı renk paleti ve altyazı yazı tipi (yalnız
// Foundation). Protokol: TV 1.0.10 (tv/webos/app.js'in başındaki yorum). Yeni alanlar (speakerColors, fontFamily,
// fontUrl) yalnız ilgili ayar açıkken yazılır; kapalıyken çerçeve 1.8.5 ile bayt bayt aynıdır.
import Foundation

/// TV'de altyazının görünümü (Android'deki SubtitleStyle ve Windows'taki SubtitleStyle ile aynı alanlar).
struct SubtitleStyle: Equatable {
  var fontSize = 46
  var bottomPercent = 7
  /// cover, above, below, fixed
  var placement = "cover"
  var background = 72
  var bold = false
  /// white, yellow, cyan, green, orange
  var textColor = "white"
  /// inApp, overlay (yalnız Android TV uygulaması kullanır)
  var displayMode = "inApp"
  var stackPrevious = true
  /// Konuşmacı adı ("ENZO:") renkli; bilgisayar sürümündeki "Konuşmacı adı renkli" (yalnız iPhone ayarlarında).
  var speakerColor = false
  /// Konuşmacı adı renkliyken her konuşmacıya ayrı renk (TV paleti; yalnız iPhone ayarlarında, varsayılan açık).
  var speakerColorsEnabled = true
  /// Altyazı yazı tipi: "default" (TV'nin standart yazı tipi) ya da [SubtitleFonts]'taki bir kimlik (yalnız iPhone).
  var subtitleFont = SubtitleFonts.defaultId
}

/// Pakette gelen, TV'ye /font/ yolundan verilen bir yazı tipi.
struct SubtitleFont: Equatable {
  /// Ayardaki kimlik ("quicksand").
  let id: String
  /// TV'ye giden `fontFamily`.
  let family: String
  /// Sunucudaki dosya adı (yalnız [A-Za-z0-9._-]); `fontUrl` = "/font/" + bu.
  let file: String
  /// Uygulama paketindeki kaynak adı ve uzantısı.
  let resource: String
  let ext: String

  var url: String { "/font/" + file }
}

/// Paketlenmiş altyazı yazı tipleri. Yalnız açık lisanslı yazı tipi: Quicksand (SIL Open Font License 1.1; dosya ve
/// lisansı Runner/Fonts/ altında, Google Fonts deposundan).
enum SubtitleFonts {
  static let defaultId = "default"
  static let quicksand = SubtitleFont(id: "quicksand", family: "Quicksand", file: "Quicksand.ttf", resource: "Quicksand", ext: "ttf")
  /// Sunucunun verdiği dosyaların tamamı (sabit izin listesi).
  static let all: [SubtitleFont] = [quicksand]
  /// TV için yazı tipi biçimi: ttf (eski TV motorları woff/woff2'yi tanımayabilir).
  static let contentType = "font/ttf"

  /// Kimliğin yazı tipi; "default" ya da bilinmeyen kimlikte nil.
  static func font(for id: String) -> SubtitleFont? {
    for font in all where font.id == id { return font }
    return nil
  }

  /// Bilinmeyen kimlik "default" olur.
  static func normalize(_ id: String) -> String { font(for: id) == nil ? defaultId : id }

  /// /font/ isteğinin yolu (sorgu kısmı atılmış): yalnız izin listesindeki dosyanın tam yolu eşleşir; başka her şey
  /// (alt klasör, "..", kodlanmış karakter, büyük/küçük harf farkı) nil.
  static func served(path: String) -> SubtitleFont? {
    for font in all where path == font.url { return font }
    return nil
  }

  /// TV 1.0.10'un kabul ettiği dosya adı: boş değil, yalnız A-Z a-z 0-9 . _ - ve ".." içermiyor.
  static func isSafeFileName(_ name: String) -> Bool {
    guard !name.isEmpty, !name.contains("..") else { return false }
    for scalar in name.unicodeScalars {
      let v: UInt32 = scalar.value
      let digit: Bool = v >= 48 && v <= 57
      let upper: Bool = v >= 65 && v <= 90
      let lower: Bool = v >= 97 && v <= 122
      if !(digit || upper || lower || v == 46 || v == 95 || v == 45) { return false }
    }
    return true
  }
}

/// Konuşmacı başına renk paleti (TV ad → renk eşlemesini kendisi yapar: ilk görülme sırası, palet bitince en uzun
/// süredir konuşmayanın rengi). Telefon yalnız paleti gönderir; palet akış boyunca değişmez (değişirse TV eşlemeyi
/// sıfırlar): yalnız yazı rengine ve ayara bağlıdır.
enum SpeakerPalette {
  static let base: [String] = ["#FFD60A", "#64D2FF", "#FF9F0A", "#30D158", "#FF7AB6", "#C49BFF"]

  /// Yazı rengiyle karışacak palet rengi: sarı yazıda sarı (masaüstü sürümdeki kural), turuncu yazıda turuncu, yeşil
  /// yazıda yeşil, camgöbeği yazıda açık mavi. Beyaz yazıda yok.
  static func clashing(_ textColor: String) -> String? {
    switch textColor {
    case "yellow": return "#FFD60A"
    case "orange": return "#FF9F0A"
    case "green": return "#30D158"
    case "cyan": return "#64D2FF"
    default: return nil
    }
  }

  /// Yazı renginin palet karşılığı çıkarılmış palet (sıra korunur).
  static func colors(textColor: String) -> [String] {
    let clash: String? = clashing(textColor)
    var out: [String] = []
    for color in base where color != clash { out.append(color) }
    return out
  }

  static func json(_ colors: [String]) -> String {
    var parts: [String] = []
    for color in colors { parts.append(SubtitleWire.jsonString(color)) }
    return "[" + parts.joined(separator: ",") + "]"
  }
}

extension SubtitleWire {
  /// Yazı rengi adının CSS karşılığı (TV uygulamaları `color` alanını okur); bilinmeyen ad beyazdır.
  static func colorHex(_ name: String) -> String {
    switch name {
    case "yellow": return "#FFE600"
    case "cyan": return "#38BDF8"
    case "green": return "#10B981"
    case "orange": return "#FF9F0A"
    default: return "#FFFFFF"
    }
  }

  /// Bilgisayar sürümüyle aynı: kapalıysa "", yazı sarıysa ad açık mavi, değilse sarı.
  static func speakerColorValue(_ s: SubtitleStyle) -> String {
    guard s.speakerColor else { return "" }
    return s.textColor == "yellow" ? "#64D2FF" : "#FFD60A"
  }

  /// Gönderilecek palet: konuşmacı adı renkli VE her konuşmacıya ayrı renk açıksa; değilse nil (alan yazılmaz).
  static func speakerColors(_ s: SubtitleStyle) -> [String]? {
    guard s.speakerColor, s.speakerColorsEnabled else { return nil }
    return SpeakerPalette.colors(textColor: s.textColor)
  }

  /// `style` olayı; alanlar alfabetik sırada (Android'deki SubtitleServer.kt ile aynı biçim). fontFamily/fontUrl yalnız
  /// yazı tipi seçiliyken, speakerColors yalnız [speakerColors] verdiyse yazılır. [clearFont]: bu oturumda TV'ye yazı tipi
  /// gönderilmiş ve şimdi standart seçili: TV'nin standarda dönmesi için `"fontFamily":""` yazılır (TV alan yoksa yazı
  /// tipini değiştirmez).
  static func styleFrame(_ s: SubtitleStyle, clearFont: Bool = false) -> String {
    let font: SubtitleFont? = SubtitleFonts.font(for: s.subtitleFont)
    var json = "{\"background\":\(min(100, max(0, s.background))),\"bold\":\(s.bold),\"bottomPercent\":\(s.bottomPercent)"
    json += ",\"color\":" + jsonString(colorHex(s.textColor))
    json += ",\"displayMode\":" + jsonString(s.displayMode)
    if let font {
      json += ",\"fontFamily\":" + jsonString(font.family)
    } else if clearFont {
      json += ",\"fontFamily\":\"\""
    }
    json += ",\"fontSize\":\(s.fontSize)"
    if let font { json += ",\"fontUrl\":" + jsonString(font.url) }
    json += ",\"placement\":" + jsonString(s.placement)
    json += ",\"speakerColor\":" + jsonString(speakerColorValue(s))
    if let palette = speakerColors(s) { json += ",\"speakerColors\":" + SpeakerPalette.json(palette) }
    json += ",\"stackPrevious\":\(s.stackPrevious),\"textColor\":" + jsonString(s.textColor) + "}"
    return frame("style", json)
  }

  /// /font/ yanıtının başlıkları: TV sayfası başka kökenden yüklediği için CORS başlığı zorunlu.
  static func fontResponseHead(length: Int) -> String {
    "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: \(SubtitleFonts.contentType)\r\n"
      + "Cache-Control: max-age=86400\r\nContent-Length: \(length)\r\nConnection: close\r\n\r\n"
  }
}
