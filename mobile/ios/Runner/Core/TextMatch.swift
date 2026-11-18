// SPDX-License-Identifier: AGPL-3.0-only
// Android'deki core/TextMatch.kt'nin Swift portu; onunla birebir aynı tutulmalıdır.
import Foundation

/// OCR çıktılarını karşılaştırmak için sadeleştirme ve gürültüye dayanıklı benzerlik.
/// Windows'taki GameTranslator.Core/TextMatch.cs ile aynı kurallar.
enum TextMatch {
  private static let SPACE: UInt16 = 0x20
  private static let NEWLINE: UInt16 = 0x0A

  /// Küçük harf, yalnız harf/rakam, tek boşluk.
  static func normalize(_ s: String) -> String { KotlinText.string(normalize(KotlinText.units(s))) }

  static func normalize(_ s: UTF16Text) -> UTF16Text {
    var builder = UTF16Text()
    builder.reserveCapacity(s.count)
    for c in KotlinText.lowercaseRoot(KotlinText.string(s)).utf16 { builder.append(isAlphanumeric(c) ? c : SPACE) }
    return KotlinText.join(KotlinText.split(builder, SPACE).filter { !$0.isEmpty }, [SPACE])
  }

  /// Levenshtein oranı [threshold] ve üstündeyse benzer sayılır. Boş metin hiçbir metne benzemez.
  static func isSimilar(_ a: String, _ b: String, _ threshold: Double = 0.85) -> Bool {
    isSimilar(KotlinText.units(a), KotlinText.units(b), threshold)
  }

  static func isSimilar(_ a: UTF16Text, _ b: UTF16Text, _ threshold: Double = 0.85) -> Bool {
    if a == b { return !a.isEmpty }
    if a.isEmpty || b.isEmpty { return false }
    var previous = Array(0...b.count)
    var row = [Int](repeating: 0, count: b.count + 1)
    for i in 1...a.count {
      row[0] = i
      for j in 1...b.count {
        row[j] = min(min(previous[j] + 1, row[j - 1] + 1), previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
      }
      swap(&previous, &row)
    }
    return 1 - Double(previous[b.count]) / Double(max(a.count, b.count)) >= threshold
  }

  /// Satırları ayrı ayrı sadeleştirip alt alta birleştirir; [isSameSubtitle] kaçırılan satırı bundan anlar.
  static func normalizeRows(_ s: String) -> String {
    let unified = s.replacingOccurrences(of: "\r\n", with: "\n", options: .literal)
    let rows = KotlinText.split(KotlinText.units(unified), NEWLINE).map { normalize($0) }.filter { !$0.isEmpty }
    return KotlinText.string(KotlinText.join(rows, [NEWLINE]))
  }

  /// Yeni okuma, gönderilmiş altyazının yeniden okuması mı. Başına ya da sonuna sözcük eklenmiş metin yenidir;
  /// sondan kısalmış metin ise ancak tam bir satırı eksikse aynı altyazıdır.
  static func isSameSubtitle(_ reread: String, _ sent: String, checkMeaning: Bool = true) -> Bool {
    // Olumsuzluk ya da sayı eklenen okuma anlamı değiştirir: aynı altyazı değildir, yeniden çevrilir.
    if checkMeaning && addsMeaning(old: sent, new: reread) { return false }
    let rereadUnits = KotlinText.units(reread)
    let rows = KotlinText.split(KotlinText.units(sent), NEWLINE)
    let flat = KotlinText.join(rows, [SPACE])
    let x = cleanWords(rereadUnits)
    let y = cleanWords(flat)
    if !y.isEmpty && x.count > y.count && (startsWith(x, y) || endsWith(x, y)) { return false }
    if isSimilar(rereadUnits, flat) { return true }
    if !x.isEmpty && x.count < y.count && (startsWith(y, x) || endsWith(y, x)) {
      return isWholeRows(x.count, rows, startsWith(y, x))
    }
    var remaining = y
    let sentCount = remaining.count
    var shared = 0
    for word in x { if removeFirst(&remaining, word) { shared += 1 } }
    if x.count >= 4 && x.count <= sentCount && Double(shared) >= Double(x.count) * 0.85 { return true }
    let longer = max(x.count, sentCount)
    let shorter = min(x.count, sentCount)
    if shorter < 6 || Double(shorter) / Double(longer) < 0.75 { return false }
    return Double(shared) / Double(longer) >= 0.75
  }

  /// Yeni satır, az önce gösterilen satırın uzamış ya da düzelmiş okuması mı; TV onu öncekinin yerine koyar.
  static func isRevision(_ newText: String, _ oldText: String) -> Bool {
    let x = normalize(KotlinText.units(newText))
    let y = normalize(KotlinText.units(oldText))
    if x.isEmpty || y.isEmpty { return false }
    if isGrowth(newText, oldText) || isGrowth(oldText, newText) { return true }
    if isSimilar(x, y, 0.8) { return true }
    let a = cleanWords(x)
    var b = cleanWords(y)
    let shorter = min(a.count, b.count)
    let longer = max(a.count, b.count)
    if shorter < 5 { return false }
    if similarity(a, b) >= 0.65 { return true }
    var shared = 0
    for word in a { if removeFirst(&b, word) { shared += 1 } }
    return Double(shared) / Double(longer) >= 0.7
  }

  /// Okuma, gönderilmiş satırın aynı cümleyi bozuk okuyan ve ondan daha iyi olmayan bir yeniden okuması mı.
  static func isWorseReread(_ reread: String, _ sent: String, checkMeaning: Bool = true) -> Bool {
    let a = normalize(KotlinText.units(reread))
    let b = normalize(KotlinText.units(sent))
    let x = cleanWords(a)
    let y = cleanWords(b)
    if x.count < 5 || y.isEmpty || isGrowth(reread, sent) || isGrowth(sent, reread) { return false }
    if checkMeaning && addsMeaning(old: sent, new: reread) { return false }
    let reads = similarity(x, y) >= 0.65 || isSimilar(a, b, 0.75)
    return reads && OcrNoise.score(reread) < OcrNoise.score(sent) + 4
  }

  private static let negations: Set<String> = [
    "not", "no", "never", "none", "nothing", "nobody", "neither", "nor", "without", "cannot", "nowhere",
    // Kesme işareti okunmamış kısaltmalar ("dont", "cant").
    "dont", "doesnt", "didnt", "cant", "couldnt", "wont", "wouldnt", "isnt", "arent", "wasnt", "werent", "havent",
    "hasnt", "hadnt", "shouldnt", "aint",
  ]

  private static let numberWords: [String: String] = [
    "zero": "0", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8",
    "nine": "9", "ten": "10", "eleven": "11", "twelve": "12", "thirteen": "13", "fourteen": "14", "fifteen": "15",
    "sixteen": "16", "seventeen": "17", "eighteen": "18", "nineteen": "19", "twenty": "20", "thirty": "30",
    "forty": "40", "fifty": "50", "sixty": "60", "seventy": "70", "eighty": "80", "ninety": "90",
    "hundred": "100", "thousand": "1000", "million": "1000000",
  ]

  /// Küçük harf, harf/rakam öbekleri (kesme işareti ayırır: "don't" -> "don", "t").
  private static func meaningTokens(_ text: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    for ch in text.lowercased() {
      if ch.isLetter || ch.isNumber { current.append(ch) } else if !current.isEmpty { tokens.append(current); current = "" }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
  }

  private static func negationCount(_ tokens: [String]) -> Int {
    var count = 0
    for (index, token) in tokens.enumerated() {
      if negations.contains(token) || (token == "t" && index > 0 && tokens[index - 1].hasSuffix("n")) { count += 1 }
    }
    return count
  }

  private static func numberTokens(_ tokens: [String]) -> [String] {
    tokens.compactMap { token -> String? in
      if let word = numberWords[token] { return word }
      return token.allSatisfy({ $0.isNumber }) ? token : nil
    }
  }

  /// Okumanın anlam imzası: sıralı sayılar ve olumsuzluk sayısı. Aynı imza, aynı anlamdır ([MeaningMemory]).
  static func meaningSignature(_ text: String) -> String {
    let tokens = meaningTokens(text)
    return numberTokens(tokens).sorted().joined(separator: ",") + "|" + String(negationCount(tokens))
  }

  /// Yeni okuma, eskisinde olmayan bir olumsuzluk (not, n't, no, never ...) ya da sayı ekliyor ya da değiştiriyor mu.
  /// Böyle okuma "aynı altyazı" ya da titreme değildir: anlam değiştiği için yeniden çevrilir. Eskide olan bir
  /// olumsuzluğun ya da sayının okunmaması (düşmesi) anlam eklemez.
  static func addsMeaning(old: String, new: String) -> Bool {
    let oldTokens = meaningTokens(old)
    let newTokens = meaningTokens(new)
    if negationCount(newTokens) > negationCount(oldTokens) { return true }
    var remaining = numberTokens(oldTokens)
    for number in numberTokens(newTokens) {
      if let index = remaining.firstIndex(of: number) { remaining.remove(at: index) } else { return true }
    }
    return false
  }

  /// Levenshtein oranı (sözcük dizileri için).
  private static func similarity(_ x: [UTF16Text], _ y: [UTF16Text]) -> Double {
    if x.isEmpty || y.isEmpty { return x.isEmpty && y.isEmpty ? 1.0 : 0.0 }
    var previous = Array(0...y.count)
    var row = [Int](repeating: 0, count: y.count + 1)
    for i in 1...x.count {
      row[0] = i
      for j in 1...y.count {
        row[j] = min(min(previous[j] + 1, row[j - 1] + 1), previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
      }
      swap(&previous, &row)
    }
    return 1 - Double(previous[y.count]) / Double(max(x.count, y.count))
  }

  /// [newText], [oldText]'in sonuna (ya da başına) sözcük eklenmiş hali mi (daktilo efekti).
  static func isGrowth(_ newText: String, _ oldText: String) -> Bool {
    let x = KotlinText.split(normalize(KotlinText.units(newText)), SPACE).filter { !$0.isEmpty }
    let y = KotlinText.split(normalize(KotlinText.units(oldText)), SPACE).filter { !$0.isEmpty }
    if y.isEmpty || x.count <= y.count { return false }
    return startsWith(x, y) || (y.count >= 2 && endsWith(x, y))
  }

  private static func startsWith(_ words: [UTF16Text], _ part: [UTF16Text]) -> Bool {
    Array(words.prefix(part.count)) == part
  }

  private static func endsWith(_ words: [UTF16Text], _ part: [UTF16Text]) -> Bool {
    Array(words.dropFirst(max(0, words.count - part.count))) == part
  }

  /// Kotlin MutableList.remove(element): ilk eşit öğeyi siler.
  private static func removeFirst(_ list: inout [UTF16Text], _ word: UTF16Text) -> Bool {
    guard let index = list.firstIndex(of: word) else { return false }
    list.remove(at: index)
    return true
  }

  /// Baştan (ya da sondan) [count] sözcük tam satırlara denk geliyor mu.
  private static func isWholeRows(_ count: Int, _ rows: [UTF16Text], _ fromStart: Bool) -> Bool {
    var total = 0
    for row in fromStart ? rows : rows.reversed() {
      total += cleanWords(row).count
      if total == count { return true }
      if total > count { return false }
    }
    return false
  }

  // Tek harfler ("a", "I" ya da OCR'ın uydurduğu "O") karşılaştırmaya bir şey katmaz.
  private static func cleanWords(_ normalized: UTF16Text) -> [UTF16Text] {
    KotlinText.split(normalized, SPACE).filter { w in w.count > 1 && !w.contains { OcrNoise.isNumber($0) } }
  }

  private static func isAlphanumeric(_ c: UInt16) -> Bool {
    switch KotlinText.category(c) {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
      .nonspacingMark, .spacingMark, .enclosingMark,
      .decimalNumber, .letterNumber, .otherNumber:
      return true
    default: return false
    }
  }
}

/// Ekrandaki tek satır için, daha önce teslim edilen okumaların anlam imzalarını ve anlam yüzünden yapılan yeniden
/// çeviri sayısını tutar. OCR bir rakamı ileri geri okuyunca (3 ↔ 8 ↔ 3) her dönüş yeniden çeviri sayılmasın:
/// önceden teslim edilmiş imzaya dönüş yeni anlam değildir; satır başına en çok [MAX_RETRANSLATIONS] anlam yeniden çevirisi.
struct MeaningMemory {
  static let MAX_RETRANSLATIONS = 2

  private var seen: [String] = []
  private var retranslations = 0

  /// [text] okuması için "anlam eklendi" kuralı hâlâ geçerli mi (imza yeni ve üst sınıra varılmadı).
  func permits(_ text: String) -> Bool {
    retranslations < MeaningMemory.MAX_RETRANSLATIONS && !seen.contains(TextMatch.meaningSignature(text))
  }

  /// Gerçekten başka bir satır gösterildi: bellek bu satırın okumasıyla yeniden başlar.
  mutating func start(_ text: String) {
    seen = [TextMatch.meaningSignature(text)]
    retranslations = 0
  }

  /// Aynı satırın düzeltilmiş okuması teslim edildi; [byMeaning] anlam eklendiği için mi çevrildi.
  mutating func record(_ text: String, byMeaning: Bool) {
    let signature = TextMatch.meaningSignature(text)
    if !seen.contains(signature) { seen.append(signature) }
    if byMeaning { retranslations += 1 }
  }

  mutating func reset() {
    seen = []
    retranslations = 0
  }
}
