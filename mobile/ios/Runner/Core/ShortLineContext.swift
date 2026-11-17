// SPDX-License-Identifier: AGPL-3.0-only
// Yalnız iOS'ta (henüz): Kotlin karşılığı yok. Android ve Windows'a da taşınırsa kurallar aynı tutulmalı.
import Foundation

/// Çeviri iş parçacığına bağlı bağlam: hat, kısa bir satırı çevirmeden önce önceki satırı buraya koyar; yaprak çevirmenler
/// (DeepL, Google, Apple) okur. Sarmalayıcı çevirmenler (sözlük, konuşmacı adı) araya girse de bozulmaz
/// (FallbackSignal ile aynı yöntem). Gemini'ye uygulanmaz: o bağlamı kendisi alır.
enum TranslationContext {
  private static let key = "gt.translationContext"

  static func set(_ context: String?) {
    if let context { Thread.current.threadDictionary[key] = context } else { Thread.current.threadDictionary.removeObject(forKey: key) }
  }

  static var current: String? { Thread.current.threadDictionary[key] as? String }
}

/// Üç sözcüğe kadar satır ("Which one?", "Over there.") tek başına belirsizdir; önceki gösterilen satır bağlam olur.
enum ShortLineContext {
  /// En çok bu kadar sözcüklü satırlar kısa sayılır.
  static let maxWords = 3
  /// Önceki satır bu süreden eski gösterildiyse bağlam olmaz (saniye).
  static let maxAgeSeconds = 15.0
  /// Bağlam metninin en çok uzunluğu (karakter).
  static let maxContextLength = 200

  /// Konuşmacı işareti/adı atılmış gövde.
  static func body(_ line: String) -> String {
    let (_, afterPrefix) = SpeakerPrefix.split(line)
    let (_, rest) = SpeakerName.split(afterPrefix)
    return KotlinText.trim(rest)
  }

  static func wordCount(_ line: String) -> Int {
    KotlinText.splitJavaWhitespace(KotlinText.units(body(line))).filter { part in
      part.contains(where: { KotlinText.isLetterOrDigit($0) })
    }.count
  }

  static func isShort(_ line: String) -> Bool {
    let count = wordCount(line)
    return count >= 1 && count <= maxWords
  }

  /// [line] kısaysa ve [previous] ondan farklı, gerçek bir önceki satırsa bağlam metni; yoksa nil.
  static func context(for line: String, previous: String?) -> String? {
    guard let previous, isShort(line) else { return nil }
    var text = body(previous).replacingOccurrences(of: "\n", with: " ")
    text = KotlinText.trim(text)
    if text.isEmpty || wordCount(text) == 0 { return nil }
    if TextMatch.normalize(text) == TextMatch.normalize(body(line)) { return nil }
    // Aynı satırın OCR düzeltmesi ya da uzamışı bağlam değildir.
    if TextMatch.isRevision(line, previous) || TextMatch.isGrowth(line, previous) || TextMatch.isGrowth(previous, line) { return nil }
    if text.utf16.count > maxContextLength {
      // Sondaki cümlelere bakılır; baştaki yarım sözcük atılır.
      let tail = String(text.suffix(maxContextLength))
      text = KotlinText.trim(String(tail.drop(while: { !$0.isWhitespace })))
      if text.isEmpty { return nil }
    }
    return text
  }
}

/// Bağlam özelliği olmayan motorlar (Google, Apple) için: "<önceki cümle> ### <kısa satır>" birlikte çevrilir, ayraçtan
/// sonrası alınır. Ayraç çıktıda tam bir kez yoksa ya da bölünme şüpheliyse kısa satır tek başına çevrilir.
enum ContextSplit {
  static let separator = "###"

  static func combine(context: String, text: String) -> String {
    var before = KotlinText.trim(context)
    if let last = before.last, !".!?…:;".contains(last) { before += "." }
    return before + " " + separator + " " + text
  }

  /// Çeviriden kısa satırın karşılığı; güvenilmezse nil.
  static func extract(_ translated: String, original text: String) -> String? {
    let parts = translated.components(separatedBy: separator)
    guard parts.count == 2 else { return nil }
    let before = KotlinText.trim(parts[0])
    let after = KotlinText.trim(parts[1])
    if before.isEmpty || after.isEmpty { return nil }
    // Kısa satırın çevirisi kısa olmalı: ayraç kayıp gitmiş ya da cümleler karışmışsa uzun çıkar.
    let originalWords = max(1, KotlinText.splitJavaWhitespace(KotlinText.units(text)).count)
    let afterWords = KotlinText.splitJavaWhitespace(KotlinText.units(after)).filter { !$0.isEmpty }.count
    if afterWords > originalWords * 4 + 2 { return nil }
    return after
  }

  /// [call] metni çevirir. Bağlam varsa birleşik metin denenir; olmazsa ya da bozuksa metin tek başına çevrilir.
  static func translate(_ text: String, context: String?, call: (String) -> String?) -> String? {
    guard let context, !KotlinText.isBlank(context), !text.contains(separator) else { return call(text) }
    // Birleşik istek hiç yanıt almadıysa (ağ yok) tek başına denemenin anlamı yok; zaman aşımı ikiye katlanmasın.
    guard let combined = call(combine(context: context, text: text)) else { return nil }
    if let part = extract(combined, original: text) { return part }
    return call(text)
  }
}
