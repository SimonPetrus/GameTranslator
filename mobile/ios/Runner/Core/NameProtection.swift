// SPDX-License-Identifier: AGPL-3.0-only
// Yalnız iOS'ta (henüz): Kotlin karşılığı yok. Android ve Windows'a da taşınırsa kurallar aynı tutulmalı.
import Foundation

/// Ad tutarlılığı: motorlar aynı özel adı satırdan satıra farklı çevirebilir. En basit güvenli sürüm: cümle ortasında
/// büyük harfle yazılmış, özel ada benzeyen sözcükler çevrilmez, olduğu gibi kalır. Mevcut sözlük düzeneği kullanılır:
/// ad geçici bir yer tutucuyla değiştirilir, çeviriden sonra ad geri konur ve Türkçe eki ada göre yeniden kurulur;
/// yer tutucu kaybolursa çeviri korumasız yapılır (GlossaryTranslator).
/// Aşırı korumayı önleyen kurallar: hitap, rütbe, akrabalık ve unvan sözcükleri korunmaz; başlık biçimli satırlarda
/// (sözcüklerin en az yarısı büyük harfli) hiçbir şey korunmaz; virgülden sonra tek başına cümle sonunda duran büyük
/// harfli sözcük hitap sayılır ve oturumda başka yerde adın büyük harfle geçtiği görülmedikçe korunmaz.
/// Kullanıcının sözlüğündeki terimlere dokunulmaz.
enum NameProtection {
  /// Satır başına en çok bu kadar ad korunur (yer tutucu sayısı sınırlı).
  static let maxNames = 6

  /// Özel ad sayılmayan büyük harfli sözcükler.
  private static let stopWords: Set<String> = [
    // Hitap
    "boy", "kid", "son", "girl", "lad", "lass", "rookie", "buddy", "pal", "mate", "friend", "stranger", "traveler",
    "traveller", "partner", "champ", "kiddo", "darling", "honey", "sweetheart", "dear", "fellas", "folks", "bro",
    "sis", "comrade", "citizen", "soldier", "hunter", "newbie", "genius", "idiot", "fool", "kitten", "boys", "girls",
    // Rütbe ve meslek
    "sir", "madam", "miss", "mister", "mrs", "madame", "captain", "sergeant", "sarge", "major", "general", "colonel",
    "commander", "lieutenant", "private", "corporal", "admiral", "officer", "agent", "detective", "inspector",
    "commissioner", "warden", "guard", "deputy", "marshal", "ranger", "knight", "sheriff", "mayor", "judge", "chief",
    "boss", "doc", "doctor", "nurse", "professor", "teacher", "priest", "pastor", "father", "master", "mistress",
    // Unvan ve akrabalık
    "lord", "lady", "king", "queen", "prince", "princess", "majesty", "highness", "excellency", "sire", "milord",
    "milady", "saint", "mother", "brother", "sister", "uncle", "aunt", "mom", "dad", "mama", "papa", "grandma",
    "grandpa", "grandmother", "grandfather", "gentlemen", "ladies",
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
  private static let wordPattern = KotlinText.regex("[\\p{L}][\\p{L}'’]*")

  /// Tümü büyük harf satır (bağırma, başlık) özel ad ipucu vermez.
  private static func isMostlyUppercase(_ text: String) -> Bool {
    let letters = text.filter { $0.isLetter }
    if letters.count < 4 { return false }
    return Double(letters.filter { $0.isUppercase }.count) / Double(letters.count) >= 0.8
  }

  /// Başlık biçimli satır: ilk sözcük dışında, içerik sözcüklerinin (4+ harfli ya da büyük harfli) en az yarısı büyük
  /// harfle başlıyor ve en az 4 içerik sözcüğü var ("Welcome To The Black Gate").
  static func isTitleCase(_ text: String) -> Bool {
    let ns = text as NSString
    let words = wordPattern.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
      .map { ns.substring(with: $0.range) }
    if words.count < 2 { return false }
    var content = 0
    var capitalized = 0
    for word in words.dropFirst() {
      let isCapital = word.first?.isUppercase ?? false
      if word.count >= 4 || isCapital {
        content += 1
        if isCapital { capitalized += 1 }
      }
    }
    return content >= 4 && Double(capitalized) / Double(content) >= 0.5
  }

  /// [text] içinde korunacak adlar (ilk görülme sırasıyla, tekrarsız). [glossary] kullanıcı sözlüğüdür: örtüşen adlar
  /// atlanır. [known] bu oturumda daha önce cümle ortasında büyük harfle görülmüş adların küçük harfli biçimidir;
  /// hitap konumundaki bir sözcük ancak bunlardan biriyse ya da aynı satırda hitap olmayan konumda da geçiyorsa korunur.
  static func candidates(_ text: String, glossary: Glossary = Glossary.EMPTY, known: Set<String> = []) -> [String] {
    if isMostlyUppercase(text) || isTitleCase(text) { return [] }
    let ns = text as NSString
    let userTerms = glossary.find(text)
    let matches = candidatePattern.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
    // Hitap olmayan konumda geçen sözcükler.
    var firm = Set<String>()
    for match in matches {
      let range = match.range(at: 1)
      if isMidClause(ns, range.location) && !isVocative(ns, range) {
        firm.insert(KotlinText.lowercaseRoot(ns.substring(with: range)))
      }
    }
    var result: [String] = []
    var seen = Set<String>()
    for match in matches {
      let range = match.range(at: 1)
      let word = ns.substring(with: range)
      let lower = KotlinText.lowercaseRoot(word)
      if stopWords.contains(lower) || seen.contains(lower) { continue }
      if !isMidClause(ns, range.location) { continue }
      if isVocative(ns, range) && !firm.contains(lower) && !known.contains(lower) { continue }
      if userTerms.contains(where: { range.location < $0.start + $0.length && $0.start < range.location + range.length }) { continue }
      // Aynı sözcük aynı satırda küçük harfle de geçiyorsa cins addır ("Spring ... spring").
      if hasLowercaseForm(text, lower) { continue }
      seen.insert(lower)
      result.append(word)
      if result.count >= maxNames { break }
    }
    return result
  }

  /// Cümle ortası: önceki boşluk dışı karakter harf, rakam, virgül ya da noktalı virgül olmalı.
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

  /// Hitap: öncesinde virgül, sonrasında cümle sonu (. ! ? … ya da metin sonu; kapanış tırnağı atlanır).
  private static func isVocative(_ ns: NSString, _ range: NSRange) -> Bool {
    var i = range.location - 1
    while i >= 0, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i -= 1 }
    guard i >= 0, ns.character(at: i) == 0x2C else { return false }
    var j = range.location + range.length
    while j < ns.length {
      let c = ns.character(at: j)
      if c == 0x20 || c == 0x09 || c == 0x22 || c == 0x201D || c == 0x2019 { j += 1; continue }
      return c == 0x2E || c == 0x21 || c == 0x3F || c == 0x2026
    }
    return true
  }

  private static func hasLowercaseForm(_ text: String, _ lower: String) -> Bool {
    let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: lower) + "(?![\\p{L}\\p{N}])"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
    return regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) != nil
  }

  /// Adları olduğu gibi bırakan sözlük (yalnız `keep`).
  static func glossary(for names: [String]) -> Glossary { Glossary.of(pairs: [], keep: names) }
}

/// Bu oturumda cümle ortasında büyük harfle görülmüş adların belleği (küçük harfli). Oyun/paket değişince sıfırlanır.
final class NameMemory: @unchecked Sendable {
  private static let maxNames = 300
  private let lock = NSLock()
  private var names = Set<String>()

  var snapshot: Set<String> { lock.lock(); defer { lock.unlock() }; return names }

  func remember(_ found: [String]) {
    lock.lock(); defer { lock.unlock() }
    for name in found {
      if names.count >= NameMemory.maxNames { names.removeAll() }
      names.insert(KotlinText.lowercaseRoot(name))
    }
  }

  func reset() {
    lock.lock(); defer { lock.unlock() }
    names.removeAll()
  }
}
