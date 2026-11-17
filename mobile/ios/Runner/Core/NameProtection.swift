// SPDX-License-Identifier: AGPL-3.0-only
// Yalnız iOS'ta (henüz): Kotlin karşılığı yok. Android ve Windows'a da taşınırsa kurallar aynı tutulmalı.
import Foundation

/// Ad tutarlılığı: motorlar aynı özel adı satırdan satıra farklı çevirebilir ("Black Gate" → "Kara Kapı" / "Siyah Geçit").
/// En basit güvenli sürüm: cümle ortasında büyük harfle yazılmış, özel ada benzeyen sözcükler çevrilmez, olduğu gibi
/// kalır. Mevcut sözlük düzeneği kullanılır: ad geçici bir yer tutucuyla değiştirilir, çeviriden sonra ad geri konur
/// ve Türkçe eki ("Kratos'u") ada göre yeniden kurulur; yer tutucu kaybolursa çeviri korumasız yapılır
/// (GlossaryTranslator). Bellek tutulmaz: ad ilk görüldüğü satırdan itibaren korunur (ilk satırda farklı, sonrakilerde
/// aynı çıkmasın diye). Kullanıcının sözlüğündeki terimlere dokunulmaz, onların çevirisi kullanıcıdadır.
enum NameProtection {
  /// Satır başına en çok bu kadar ad korunur (yer tutucu sayısı sınırlı).
  static let maxNames = 6

  /// Özel ad sayılmayan büyük harfli sözcükler: unvanlar, gün/ay adları, uyruklar, sık geçen cins adlar.
  private static let stopWords: Set<String> = [
    // Unvan ve hitap: çevrilmesi doğru olanlar
    "sir", "lord", "lady", "captain", "sergeant", "major", "general", "colonel", "commander", "doctor", "professor",
    "king", "queen", "prince", "princess", "master", "father", "mother", "brother", "sister", "uncle", "aunt",
    "mister", "miss", "madam", "officer", "agent", "detective", "lieutenant", "private", "corporal", "admiral",
    "boss", "chief", "sheriff", "mayor", "judge", "saint", "mom", "dad", "grandma", "grandpa", "mrs", "madame",
    "gentlemen", "ladies", "sire", "milord", "milady", "commissioner", "inspector", "warden", "guard", "soldier",
    // Gün, ay, bayram
    "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "january", "february", "march",
    "april", "june", "july", "august", "september", "october", "november", "december", "christmas", "halloween",
    "easter", "thanksgiving",
    // Uyruk ve dil
    "english", "american", "british", "german", "french", "russian", "japanese", "chinese", "spanish", "italian",
    "irish", "scottish", "turkish", "korean", "indian", "mexican", "canadian", "european", "african", "asian",
    "arabic", "greek", "roman",
    // Sık büyük harfle yazılan genel sözcükler
    "god", "gods", "heaven", "hell", "earth", "internet", "okay", "yes", "the", "and", "but", "you", "your",
    "what", "when", "where", "who", "why", "how", "this", "that", "they", "them", "then", "there", "here", "now",
    "well", "wait", "stop", "come", "look", "let", "just", "not", "all", "get", "got", "one", "two", "three",
  ]

  private static let candidatePattern = KotlinText.regex(
    "(?<![\\p{L}\\p{N}'’])(\\p{Lu}\\p{Ll}{2,})(?![\\p{L}\\p{N}]|['’](?:t|ll|re|ve|d|m)(?![\\p{L}]))")

  /// Tümü büyük harf satır (bağırma, başlık) özel ad ipucu vermez.
  private static func isMostlyUppercase(_ text: String) -> Bool {
    let letters = text.filter { $0.isLetter }
    if letters.count < 4 { return false }
    return Double(letters.filter { $0.isUppercase }.count) / Double(letters.count) >= 0.8
  }

  /// [text] içinde korunacak adlar (ilk görülme sırasıyla, tekrarsız). [glossary] kullanıcı sözlüğüdür: örtüşen
  /// adlar atlanır.
  static func candidates(_ text: String, glossary: Glossary = Glossary.EMPTY) -> [String] {
    if isMostlyUppercase(text) { return [] }
    let ns = text as NSString
    let userTerms = glossary.find(text)
    var result: [String] = []
    var seen = Set<String>()
    for match in candidatePattern.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
      let range = match.range(at: 1)
      let word = ns.substring(with: range)
      let lower = KotlinText.lowercaseRoot(word)
      if stopWords.contains(lower) || seen.contains(lower) { continue }
      if !isMidClause(ns, range.location) { continue }
      if userTerms.contains(where: { range.location < $0.start + $0.length && $0.start < range.location + range.length }) { continue }
      // Aynı sözcük aynı satırda küçük harfle de geçiyorsa cins addır ("Spring ... spring").
      if hasLowercaseForm(text, lower) { continue }
      seen.insert(lower)
      result.append(word)
      if result.count >= maxNames { break }
    }
    return result
  }

  /// Cümle ortası: önceki boşluk dışı karakter harf, rakam, virgül ya da noktalı virgül olmalı. Satır başı, cümle sonu
  /// (. ! ?), tırnak, tire ve iki nokta sonrası cümle başı sayılır.
  private static func isMidClause(_ ns: NSString, _ location: Int) -> Bool {
    var i = location - 1
    while i >= 0 {
      let c = ns.character(at: i)
      if c == 0x20 || c == 0x09 { i -= 1; continue }
      guard let scalar = Unicode.Scalar(c) else { return false }
      let ch = Character(scalar)
      return ch.isLetter || ch.isNumber || ch == "," || ch == ";"
    }
    return false
  }

  private static func hasLowercaseForm(_ text: String, _ lower: String) -> Bool {
    let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: lower) + "(?![\\p{L}\\p{N}])"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
    return regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) != nil
  }

  /// Adları olduğu gibi bırakan sözlük (yalnız `keep`).
  static func glossary(for names: [String]) -> Glossary { Glossary.of(pairs: [], keep: names) }
}
