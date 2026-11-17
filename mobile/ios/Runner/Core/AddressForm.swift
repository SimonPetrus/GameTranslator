// SPDX-License-Identifier: AGPL-3.0-only
// Yalnız iOS'ta (henüz): Kotlin karşılığı yok. Android ve Windows'a da taşınırsa kurallar aynı tutulmalı.
import Foundation

/// sen/siz tutarlılığı: motorlar aynı konuşmacıya bir satırda "sen", ötekinde "siz" diyebilir ("Seni gördüm, bekleyin.").
/// Satırda "sen" biçimi var ve "siz" belirtisi yoksa, çoğul/saygılı emir kipleri ("bekleyin") tekile ("bekle") çevrilir.
/// Yalnız emir konumunda (sözcükten sonra noktalama ya da satır sonu) ve yalnız listedeki fiillerde. "alın", "yazın",
/// "kazın", "kesin", "koyun" gibi başka anlamı olan sözcükler listede yoktur. Emin değilsek dokunulmaz.
enum AddressForm {
  struct Evidence: Equatable {
    var sen = false
    /// "Siz" biçimi ya da birden çok kişiye seslenme belirtisi: varsa hiçbir şey çevrilmez.
    var siz = false
  }

  // MARK: - Belirtiler

  private static let singularCues: Set<String> = [
    "sen", "seni", "sana", "senin", "sende", "senden", "seninle", "senle", "sensiz", "kendin",
  ]
  private static let pluralCues: Set<String> = [
    "siz", "sizi", "size", "sizin", "sizde", "sizden", "sizinle", "sizle", "sizler", "sizleri", "sizlere",
    "sizlerin", "sizlerle", "hepiniz", "hepinizi", "hepinize", "hepinizin", "ikiniz", "ikinizi", "ikinize",
    "hanginiz", "kendiniz", "kendinizi", "kendinize",
    // Çoğul seslenme: tekil emir bu kişilere söylenmez.
    "beyler", "çocuklar", "arkadaşlar", "millet", "adamlar", "askerler", "hanımlar", "efendiler", "dostlar",
  ]
  private static let sizEndings = ["sınız", "siniz", "sunuz", "sünüz"]

  static func evidence(_ text: String) -> Evidence {
    var result = Evidence()
    for token in tokens(text) {
      let word = token.lower
      if singularCues.contains(word) { result.sen = true }
      if pluralCues.contains(word) { result.siz = true }
      if word.count >= 7 && sizEndings.contains(where: { word.hasSuffix($0) }) { result.siz = true }
    }
    return result
  }

  // MARK: - Emir kipleri

  /// "çoğul:tekil" çiftleri (emir kipi, olumlu). Olumsuzları aşağıda üretilir.
  private static let pairs: [(String, String)] = [
    ("bekleyin", "bekle"), ("durun", "dur"), ("gelin", "gel"), ("koşun", "koş"), ("bakın", "bak"),
    ("dinleyin", "dinle"), ("gidin", "git"), ("kaçın", "kaç"), ("girin", "gir"),
    ("geçin", "geç"), ("bırakın", "bırak"), ("söyleyin", "söyle"), ("gösterin", "göster"), 
    ("getirin", "getir"), ("götürün", "götür"), ("edin", "et"), ("olun", "ol"),
    ("kalkın", "kalk"), ("oturun", "otur"), ("susun", "sus"), ("atlayın", "atla"), ("tırmanın", "tırman"),
    ("saklanın", "saklan"), ("çekilin", "çekil"), ("toplanın", "toplan"), ("hazırlanın", "hazırlan"),
    ("saldırın", "saldır"), ("vurun", "vur"), ("öldürün", "öldür"), ("ateşleyin", "ateşle"),
    ("kurtarın", "kurtar"), ("koruyun", "koru"), ("savunun", "savun"), ("yakalayın", "yakala"),
    ("durdurun", "durdur"), ("kapatın", "kapat"), ("kaldırın", "kaldır"), ("toplayın", "topla"),
    ("taşıyın", "taşı"), ("çağırın", "çağır"), ("arayın", "ara"), ("bulun", "bul"), ("anlatın", "anlat"),
    ("açıklayın", "açıkla"), ("izleyin", "izle"), ("yürüyün", "yürü"), ("dönün", "dön"), ("inanın", "inan"),
    ("uyanın", "uyan"), ("uyuyun", "uyu"), ("yükleyin", "yükle"), 
    ("başlayın", "başla"), ("ilerleyin", "ilerle"), ("yaklaşın", "yaklaş"),
    ("uzaklaşın", "uzaklaş"), ("dağılın", "dağıl"), ("birleşin", "birleş"), ("hızlanın", "hızlan"),
    ("yavaşlayın", "yavaşla"), ("deneyin", "dene"), ("düşünün", "düşün"), ("hatırlayın", "hatırla"),
    ("unutun", "unut"), ("çalışın", "çalış"), ("kullanın", "kullan"), ("seçin", "seç"), ("bitirin", "bitir"),
    ("bağlayın", "bağla"), ("çözün", "çöz"), ("dokunun", "dokun"),
  ]

  /// Başka anlamı olduğu için yalnız cümlecik başında (ya da "hadi/hemen/şimdi/çabuk/lütfen"den sonra) çevrilenler:
  /// "gelin" gelin (evli kadın) de demektir.
  private static let clauseStartOnly: Set<String> = ["gelin"]
  private static let leadWords: Set<String> = ["hadi", "hemen", "şimdi", "çabuk", "lütfen"]

  private static let backVowels = Set("aıou")

  private static let table: [String: String] = {
    var map: [String: String] = [:]
    for (plural, singular) in pairs where map[plural] == nil {
      map[plural] = singular
      // Olumsuz: bekleyin → beklemeyin; tekili bekleme. "-ma/-me" ünlü uyumuna göre, çoğulu hep "-mayın/-meyin".
      let back = singular.last(where: { "aeıioöuü".contains($0) }).map { backVowels.contains($0) } ?? false
      map[singular + (back ? "mayın" : "meyin")] = singular + (back ? "ma" : "me")
    }
    return map
  }()

  /// Çevrilebilen sözcük sayısı (olumlu + olumsuz).
  static var count: Int { table.count }

  private struct Token {
    let range: NSRange
    let text: String
    let lower: String
  }

  private static let wordPattern = KotlinText.regex("\\p{L}+")

  private static func tokens(_ text: String) -> [Token] {
    let ns = text as NSString
    return wordPattern.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)).map { (match: NSTextCheckingResult) -> Token in
      let word = ns.substring(with: match.range)
      return Token(range: match.range, text: word, lower: KotlinText.lowercaseTurkish(word))
    }
  }

  private static let afterChars = Set(".,!?…;:)\"”’'")
  private static let beforeBreaks = Set(".!?,;:…\"“-–—(")

  /// Emir konumundaki çoğul emirleri tekile çevirir ([text] içinde "siz" belirtisi olmadığı çağıranca bilinir).
  static func singularize(_ text: String) -> String {
    let ns = text as NSString
    var out = ""
    var last = 0
    let all = tokens(text)
    for (index, token) in all.enumerated() {
      guard let singular = table[token.lower] else { continue }
      let end = token.range.location + token.range.length
      // Emir konumu: sonrası satır sonu ya da noktalama.
      if end < ns.length {
        guard let nextScalar = Unicode.Scalar(ns.character(at: end)), afterChars.contains(Character(nextScalar)) else { continue }
      }
      if clauseStartOnly.contains(token.lower) && !startsClause(ns, token.range, previous: index > 0 ? all[index - 1] : nil) {
        continue
      }
      out += ns.substring(with: NSRange(location: last, length: token.range.location - last))
      out += matchCase(singular, like: token.text)
      last = end
    }
    if last == 0 { return text }
    out += ns.substring(from: last)
    return out
  }

  private static func startsClause(_ ns: NSString, _ range: NSRange, previous: Token?) -> Bool {
    var i = range.location - 1
    while i >= 0 {
      let c = ns.character(at: i)
      if c == 0x20 || c == 0x09 { i -= 1; continue }
      if let scalar = Unicode.Scalar(c), beforeBreaks.contains(Character(scalar)) { return true }
      // Aralarında yalnız boşluk olan önceki sözcük "hadi gelin" gibi bir giriş sözcüğü mü?
      if let previous, previous.range.location + previous.range.length == i + 1 { return leadWords.contains(previous.lower) }
      return false
    }
    return true
  }

  private static func matchCase(_ singular: String, like original: String) -> String {
    let letters = original.filter { $0.isLetter }
    if letters.count >= 2 && letters.allSatisfy({ $0.isUppercase }) { return KotlinText.uppercaseTurkish(singular) }
    if let first = original.first, first.isUppercase, let head = singular.first {
      return KotlinText.uppercaseTurkish(String(head)) + String(singular.dropFirst())
    }
    return singular
  }

  /// Satır içi tutarlılık: "sen" biçimi var, "siz" belirtisi yok → emirler tekile.
  static func harmonizeLine(_ text: String) -> String {
    let e = evidence(text)
    return e.sen && !e.siz ? singularize(text) : text
  }
}

/// Konuşmacı başına oturum belleği: bir konuşmacı art arda satırlarda "sen" diyorsa, ardından gelen ve kendi başına
/// belirti taşımayan satırındaki çoğul emirler de tekile çevrilir. Belirti: en az 2 ardışık "sen" gözlemi ve
/// arada "siz" gözlemi olmaması; gözlem [maxAgeSeconds] saniyeden eskiyse unutulur. Oyun/paket değişince [reset].
final class AddressMemory: @unchecked Sendable {
  static let minStreak = 2
  static let maxAgeSeconds = 60.0
  private static let maxSpeakers = 32

  private struct Entry {
    var streak = 0
    var at = 0.0
  }

  private let clock: () -> Double
  private let lock = NSLock()
  private var entries: [String: Entry] = [:]

  init(clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) { self.clock = clock }

  func reset() {
    lock.lock(); defer { lock.unlock() }
    entries = [:]
  }

  /// Satırdaki konuşmacı adı (SpeakerName biçimi, ": " olmadan); yoksa nil. Önceki tire/">>" işareti atlanır.
  static func speaker(of source: String) -> String? {
    let (_, afterPrefix) = SpeakerPrefix.split(source)
    let (name, _) = SpeakerName.split(afterPrefix)
    let trimmed = name.hasSuffix(": ") ? String(name.dropLast(2)) : name
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Çevrilmiş satırı konuşmacı belleğine göre işler: belirtiyi kaydeder, belirtisiz satırda bellek açıkça "sen"
  /// diyorsa çoğul emirleri tekile çevirir. Konuşmacı yoksa metin aynen döner.
  func apply(_ text: String, speaker: String?) -> String {
    guard let speaker else { return text }
    let e = AddressForm.evidence(text)
    let now = clock()
    lock.lock()
    defer { lock.unlock() }
    var entry = entries[speaker] ?? Entry()
    if e.siz {
      entry.streak = 0
      entry.at = now
      store(speaker, entry)
      return text
    }
    if e.sen {
      entry.streak = (now - entry.at <= AddressMemory.maxAgeSeconds ? entry.streak : 0) + 1
      entry.at = now
      store(speaker, entry)
      return text
    }
    if entry.streak >= AddressMemory.minStreak && now - entry.at <= AddressMemory.maxAgeSeconds {
      return AddressForm.singularize(text)
    }
    return text
  }

  private func store(_ speaker: String, _ entry: Entry) {
    if entries[speaker] == nil && entries.count >= AddressMemory.maxSpeakers { entries.removeAll() }
    entries[speaker] = entry
  }
}
