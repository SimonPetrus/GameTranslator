// SPDX-License-Identifier: AGPL-3.0-only
// Yalnız iOS'ta (henüz): Kotlin karşılığı yok. Android ve Windows'a da taşınırsa kurallar aynı tutulmalı.
import Foundation

/// Çeviri motorunun Türkçe çıktısını düzeltir (tüm motorlar, yalnız İngilizce→Türkçe). Kural: emin değilsen dokunma.
///  - noktalamadan önceki boşluk silinir ("Dur !" → "Dur!"), art arda boşluklar teke iner;
///  - motor kaynağın bitiş işaretini değiştirdiyse geri konur ("Run!" → "Koş." değil "Koş!"; ?, ?!, … aynı);
///  - tırnak ve kesme işareti kaynaktaki yazımı izler (düz ya da kıvrık);
///  - ilk harf büyütülür (kaynak küçük harfle başlıyorsa, yani cümlenin devamıysa dokunulmaz).
enum TurkishPostEdit {
  static func apply(_ translated: String, source: String) -> String {
    var text = KotlinText.trim(translated)
    if text.isEmpty { return text }
    text = collapseSpaces(text)
    text = removeSpaceBeforePunctuation(text)
    text = followQuotes(text, source: source)
    text = followEndMark(text, source: source)
    text = capitalizeFirst(text, source: source)
    return text
  }

  // MARK: - Boşluklar

  private static let spaceRuns = KotlinText.regex("[ \\t]{2,}")
  private static let spaceBeforeMark = KotlinText.regex("[ \\t]+([,.;:!?…])")

  static func collapseSpaces(_ text: String) -> String {
    let ns = text as NSString
    return spaceRuns.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length),
                                              withTemplate: " ")
  }

  static func removeSpaceBeforePunctuation(_ text: String) -> String {
    let ns = text as NSString
    return spaceBeforeMark.stringByReplacingMatches(in: text, options: [],
                                                    range: NSRange(location: 0, length: ns.length), withTemplate: "$1")
  }

  // MARK: - Tırnaklar

  private static let straightDouble = "\""
  private static let curlyDouble = "“”"

  /// Kaynak düz tırnak kullanıyorsa çıktıdaki kıvrıklar düze, kaynak kıvrıksa düzler kıvrığa çevrilir.
  static func followQuotes(_ text: String, source: String) -> String {
    let srcCurly = source.contains("“") || source.contains("”")
    let srcStraight = source.contains(straightDouble)
    let srcApostropheCurly = source.contains("’")
    let srcApostropheStraight = source.contains("'")
    var out = text
    if srcStraight && !srcCurly {
      out = out.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
    } else if srcCurly && !srcStraight && out.filter({ $0 == "\"" }).count % 2 == 0 && out.contains("\"") {
      var open = true
      var rebuilt = ""
      for ch in out {
        if ch == "\"" {
          rebuilt.append(open ? "“" : "”")
          open.toggle()
        } else {
          rebuilt.append(ch)
        }
      }
      out = rebuilt
    }
    if srcApostropheStraight && !srcApostropheCurly {
      out = out.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
    } else if srcApostropheCurly && !srcApostropheStraight {
      out = out.replacingOccurrences(of: "'", with: "’")
    }
    return out
  }

  // MARK: - Bitiş işareti

  private static let closers = Set("\"”’')»".unicodeScalars)
  private static let markScalars = Set(".!?…".unicodeScalars)

  /// (gövde, işaret dizisi, kapanış tırnakları/parantez): "Koş!\"" → ("Koş", "!", "\"").
  static func splitEnd(_ text: String) -> (String, String, String) {
    var scalars = Array(KotlinText.trim(text).unicodeScalars)
    var tail: [Unicode.Scalar] = []
    while let last = scalars.last, closers.contains(last) {
      tail.insert(last, at: 0)
      scalars.removeLast()
    }
    var marks: [Unicode.Scalar] = []
    while let last = scalars.last, markScalars.contains(last) {
      marks.insert(last, at: 0)
      scalars.removeLast()
    }
    return (join(scalars), join(marks), join(tail))
  }

  private static func join(_ scalars: [Unicode.Scalar]) -> String {
    var s = ""
    s.unicodeScalars.append(contentsOf: scalars)
    return s
  }

  /// Kaynak ünlem, soru ya da üç nokta ile bitiyor, çeviri bitişi yok ya da düz noktaysa çevirinin bitişi kaynağınki olur.
  /// Çevirinin bitişi başka bir güçlü işaretse (ör. kaynak "!" çeviri "?") motorun kararına dokunulmaz.
  static func followEndMark(_ text: String, source: String) -> String {
    let (_, srcMarks, _) = splitEnd(source)
    let strong = srcMarks.contains("!") || srcMarks.contains("?") || srcMarks.contains("…") || srcMarks.count >= 2
    if !strong { return text }
    let (body, marks, closing) = splitEnd(text)
    if body.isEmpty { return text }
    if marks.isEmpty {
      // İşaretsiz çeviri yalnız harf/rakamla bitiyorsa tamamlanır ("Koş" → "Koş!"); virgül, iki nokta vb. bırakılır.
      guard let last = body.unicodeScalars.last, last.properties.isAlphabetic || CharacterSet.decimalDigits.contains(last) else {
        return text
      }
    } else if marks != "." {
      return text
    }
    // Kaynağın "..." yazımı korunur; tek "…" ise tek karakter.
    return body + srcMarks + closing
  }

  // MARK: - Büyük harf

  /// İlk harf küçükse büyütülür. Konuşmacı işareti ("- ") ve adı ("ENZO: ") atlanır. Rakamla başlayan metne dokunulmaz.
  static func capitalizeFirst(_ text: String, source: String) -> String {
    let (prefix, afterPrefix) = SpeakerPrefix.split(text)
    let (name, rest) = SpeakerName.split(afterPrefix)
    guard let capitalized = capitalizeLeading(rest) else { return text }
    // Kaynağın ilk harfi küçükse cümlenin devamıdır: büyütme.
    let (_, srcAfterPrefix) = SpeakerPrefix.split(source)
    let (_, srcRest) = SpeakerName.split(srcAfterPrefix)
    if let first = firstLetter(srcRest), first.properties.isLowercase { return text }
    return prefix + name + capitalized
  }

  private static func firstLetter(_ text: String) -> Unicode.Scalar? {
    for scalar in text.unicodeScalars {
      if scalar.properties.isAlphabetic { return scalar }
      if CharacterSet.decimalDigits.contains(scalar) { return nil }
    }
    return nil
  }

  /// Baştaki ilk harf küçükse büyütülmüş metin; değişecek bir şey yoksa nil.
  private static func capitalizeLeading(_ text: String) -> String? {
    var index = text.startIndex
    while index < text.endIndex {
      let ch = text[index]
      if ch.isLetter {
        guard ch.isLowercase else { return nil }
        let upper = KotlinText.uppercaseTurkish(String(ch))
        return String(text[text.startIndex..<index]) + upper + String(text[text.index(after: index)...])
      }
      if ch.isNumber { return nil }
      index = text.index(after: index)
    }
    return nil
  }
}
