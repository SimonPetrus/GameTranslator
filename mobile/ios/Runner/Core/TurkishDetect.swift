// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Satırın zaten Türkçe olup olmadığını motora gitmeden anlar (hedef dil Türkçeyken motor çağrısı boşa gitmesin).
/// Belirleyici ve çevrimdışı: Türkçeye özgü harfler (ğ ı ş İ güçlü; ç ö ü zayıf, çünkü Almanca/Fransızca/Portekizce'de de var)
/// ve yaygın Türkçe sözcükler sayılır. İngilizce satırdaki özel adlar ("Müller", "Işık") yanlış alarm vermesin diye
/// İngilizce işlev sözcükleri varsa çok daha yüksek yoğunluk istenir.
enum TurkishDetect {
  private static let strongChars: Set<Character> = ["ğ", "Ğ", "ı", "İ", "ş", "Ş"]
  private static let weakChars: Set<Character> = ["ç", "Ç", "ö", "Ö", "ü", "Ü"]

  /// Belirsiz olmayan yaygın Türkçe sözcükler (özel ad ya da İngilizce sözcük olabilenler yok: ben, sen, var, ama ...).
  private static let common: Set<String> = [
    "ve", "bir", "için", "değil", "çok", "evet", "hayır", "gibi", "daha", "şimdi", "nasıl", "neden", "tamam", "lütfen",
    "merhaba", "teşekkürler", "teşekkür", "hadi", "gidelim", "burada", "orada", "yapma", "bilmiyorum", "biliyorum",
    "olmaz", "bunu", "şunu", "bana", "sana", "onu", "beni", "seni", "bizi", "kadar", "sonra", "önce", "belki", "çünkü",
    "artık", "yine", "bile", "sadece", "tekrar", "hepsi", "nerede", "nereye", "nedir", "değilim", "değilsin", "misin",
    "musun", "mısın", "bugün", "yarın", "dün", "yok", "tamamdır", "sağol", "hoş", "geldin", "hoşgeldin", "peki", "işte", "zaten",
    "olarak", "üzerinde", "bunlar", "şunlar", "onlar", "buraya", "oraya", "biraz", "herkes", "hiçbir", "bütün",
    // Konsol ve sistem metinleri.
    "güncelleme", "bekleyin", "oturum", "bağlantı", "ayarlar", "kaydediliyor", "yükleniyor", "devam", "iptal",
    "kaydedildi", "tamamlandı",
  ]

  /// En az 6 harfli bilinen sözcükler: yazı tanıma bir harfi bozmuş (değişmiş, düşmüş ya da eklenmiş) olsa da sayılır.
  private static let fuzzyKnown: [[Character]] = common.filter { $0.count >= 6 }.map { Array($0) }

  /// [a] ile [b] tam olarak bir harf farkla (değiştirme, ekleme ya da silme) ayrılıyor mu.
  static func oneEditApart(_ a: [Character], _ b: [Character]) -> Bool {
    if abs(a.count - b.count) > 1 { return false }
    var i = 0
    while i < a.count && i < b.count && a[i] == b[i] { i += 1 }
    if i == a.count && i == b.count { return false }
    if a.count == b.count { return a[(i + 1)...] == b[(i + 1)...] }
    if a.count > b.count { return a[(i + 1)...] == b[i...] }
    return a[i...] == b[(i + 1)...]
  }

  private static func isKnown(_ word: String) -> Bool {
    if common.contains(word) { return true }
    let letters = Array(word)
    if letters.count < 5 { return false }
    return fuzzyKnown.contains { oneEditApart(letters, $0) }
  }

  /// İngilizce işlev sözcükleri (Türkçede anlamlı karşılığı olmayanlar).
  private static let english: Set<String> = [
    "the", "and", "you", "to", "of", "is", "are", "this", "that", "with", "for", "what", "we", "not", "have", "your",
    "it", "he", "she", "they", "was", "my", "from", "will", "can", "get", "just", "there", "here", "all",
  ]

  static func isTurkish(_ text: String) -> Bool {
    // "İ" küçültülünce birleşik noktalı "i̇" olur; sözcük karşılaştırması için önce düz "i" yapılır.
    let hasDottedCapital = text.contains("İ")
    let folded = text.replacingOccurrences(of: "İ", with: "i").lowercased()
    var words: [String] = []
    var current = ""
    for ch in folded {
      if ch.isLetter { current.append(ch) } else if !current.isEmpty { words.append(current); current = "" }
    }
    if !current.isEmpty { words.append(current) }
    let n = words.count
    if n == 0 { return false }

    var score = 0
    var englishHits = 0
    var commonHits = 0
    for word in words {
      if english.contains(word) { englishHits += 1 }
      if isKnown(word) { score += 2; commonHits += 1; continue }
      if word.contains(where: { strongChars.contains($0) }) {
        score += 2
      } else if word.contains(where: { weakChars.contains($0) }) {
        score += 1
      }
    }
    // Büyük "İ" katlamada düz "i" olmuştu; güçlü harf sayılsın.
    if hasDottedCapital { score += 2 }

    if englishHits > 0 { return score >= 2 * n && score >= 4 }
    // Kısa satırda ("Çağlar!", "Şahin Aksoy") yalnız Türkçe harf özel ad olabilir: bilinen bir Türkçe sözcük şart.
    if n <= 3 { return commonHits >= 1 && score >= 2 }
    return score >= 4 && score * 4 >= n * 3
  }
}
