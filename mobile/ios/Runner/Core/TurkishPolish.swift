// SPDX-License-Identifier: AGPL-3.0-only
// Yalnız iOS'ta (henüz): Kotlin karşılığı yok. Android ve Windows'a da taşınırsa kurallar aynı tutulmalı.
import Foundation

/// Motorun Türkçe çıktısını okunur hâle getirir (İngilizce→Türkçe, tüm motorlar). İlke: emin değilsen dokunma.
///  - noktalamanın önündeki boşluk ve art arda boşluklar temizlenir;
///  - kaynak cümle !, ? ya da … ile bitiyorsa ve motor bunu düz noktaya çevirmiş ya da bırakmışsa kaynağın işareti konur;
///  - tırnak ve kesme işareti kaynağın yazımına (düz ya da kıvrık) uydurulur;
///  - ilk harf büyük olur; kaynak küçük harfle başlıyorsa (cümlenin devamı) dokunulmaz.
enum TurkishPolish {
  static func apply(_ translated: String, source: String) -> String {
    var text = KotlinText.trim(translated)
    if text.isEmpty { return text }
    text = squeezeSpaces(text)
    text = tightenPunctuation(text)
    text = matchQuoteStyle(text, source: source)
    text = matchClosingMark(text, source: source)
    text = raiseInitial(text, source: source)
    return text
  }

  // MARK: - Boşluklar

  private static let spaceRuns = KotlinText.regex("[ \\t]{2,}")
  private static let spaceBeforeMark = KotlinText.regex("[ \\t]+([,.;:!?…])")

  static func squeezeSpaces(_ text: String) -> String {
    let ns = text as NSString
    return spaceRuns.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length),
                                              withTemplate: " ")
  }

  static func tightenPunctuation(_ text: String) -> String {
    let ns = text as NSString
    return spaceBeforeMark.stringByReplacingMatches(in: text, options: [],
                                                    range: NSRange(location: 0, length: ns.length), withTemplate: "$1")
  }

  // MARK: - Tırnak ve kesme işareti

  /// Kaynak düz çift tırnak kullanıyorsa çıktıdaki kıvrıklar düze, kaynak kıvrıksa çıktıdaki düzler (çift sayıdaysa)
  /// sırayla açan/kapayan kıvrığa çevrilir. Kesme işareti de aynı biçimde kaynağı izler.
  static func matchQuoteStyle(_ text: String, source: String) -> String {
    let sourceCurly = source.contains("“") || source.contains("”")
    let sourceStraight = source.contains("\"")
    var out = text
    if sourceStraight && !sourceCurly {
      out = out.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
    } else if sourceCurly && !sourceStraight && out.contains("\"") && out.filter({ $0 == "\"" }).count % 2 == 0 {
      var opening = true
      var rebuilt = ""
      for ch in out {
        if ch == "\"" {
          rebuilt.append(opening ? "“" : "”")
          opening.toggle()
        } else {
          rebuilt.append(ch)
        }
      }
      out = rebuilt
    }
    let sourceCurlyApostrophe = source.contains("’")
    let sourceStraightApostrophe = source.contains("'")
    if sourceStraightApostrophe && !sourceCurlyApostrophe {
      out = out.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
    } else if sourceCurlyApostrophe && !sourceStraightApostrophe {
      out = out.replacingOccurrences(of: "'", with: "’")
    }
    return out
  }

  // MARK: - Bitiş işareti

  private static let closingQuotes = Set("\"”’')»".unicodeScalars)
  private static let markScalars = Set(".!?…".unicodeScalars)

  /// Metni (gövde, bitiş işareti dizisi, kapanış tırnak/parantezleri) olarak ayırır: `Atla!"` → (`Atla`, `!`, `"`).
  static func peelEnding(_ text: String) -> (body: String, marks: String, closers: String) {
    var scalars = Array(KotlinText.trim(text).unicodeScalars)
    var closers: [Unicode.Scalar] = []
    while let last = scalars.last, closingQuotes.contains(last) {
      closers.insert(last, at: 0)
      scalars.removeLast()
    }
    var marks: [Unicode.Scalar] = []
    while let last = scalars.last, markScalars.contains(last) {
      marks.insert(last, at: 0)
      scalars.removeLast()
    }
    return (stringOf(scalars), stringOf(marks), stringOf(closers))
  }

  private static func stringOf(_ scalars: [Unicode.Scalar]) -> String {
    var s = ""
    s.unicodeScalars.append(contentsOf: scalars)
    return s
  }

  /// Kaynak güçlü bir işaretle (!, ?, …, ?!, ...) bitiyorsa ve çevirinin bitişi yoksa ya da tek noktaysa, çevirinin
  /// sonuna kaynağın işareti konur. Çeviri başka bir işaretle bitiyorsa (kaynak "!" çeviri "?") motorun seçimine dokunulmaz.
  static func matchClosingMark(_ text: String, source: String) -> String {
    let sourceMarks = peelEnding(source).marks
    let strong = sourceMarks.contains("!") || sourceMarks.contains("?") || sourceMarks.contains("…") || sourceMarks.count >= 2
    if !strong { return text }
    let (body, marks, closers) = peelEnding(text)
    if body.isEmpty { return text }
    if marks.isEmpty {
      // İşaretsiz çeviri yalnız harf ya da rakamla bitiyorsa tamamlanır; virgül, iki nokta gibi sonlar bırakılır.
      guard let last = body.unicodeScalars.last,
            last.properties.isAlphabetic || CharacterSet.decimalDigits.contains(last) else { return text }
    } else if marks != "." {
      return text
    }
    return body + sourceMarks + closers
  }

  // MARK: - İlk harf

  /// İlk harf küçükse büyütür. Konuşmacı işareti ("- ") ve adı ("MARA: ") atlanır; rakamla başlayan metne dokunulmaz.
  static func raiseInitial(_ text: String, source: String) -> String {
    let (prefix, afterPrefix) = SpeakerPrefix.split(text)
    let (name, rest) = SpeakerName.split(afterPrefix)
    guard let raised = raiseLeadingLetter(rest) else { return text }
    let (_, sourceAfterPrefix) = SpeakerPrefix.split(source)
    let (_, sourceRest) = SpeakerName.split(sourceAfterPrefix)
    if let first = leadingLetter(sourceRest), first.properties.isLowercase { return text }
    return prefix + name + raised
  }

  private static func leadingLetter(_ text: String) -> Unicode.Scalar? {
    for scalar in text.unicodeScalars {
      if scalar.properties.isAlphabetic { return scalar }
      if CharacterSet.decimalDigits.contains(scalar) { return nil }
    }
    return nil
  }

  /// İlk harf küçük harfse büyütülmüş metin; değişecek bir şey yoksa nil.
  private static func raiseLeadingLetter(_ text: String) -> String? {
    var index = text.startIndex
    while index < text.endIndex {
      let ch = text[index]
      if ch.isLetter {
        guard ch.isLowercase else { return nil }
        return String(text[text.startIndex..<index]) + KotlinText.uppercaseTurkish(String(ch))
          + String(text[text.index(after: index)...])
      }
      if ch.isNumber { return nil }
      index = text.index(after: index)
    }
    return nil
  }
}
