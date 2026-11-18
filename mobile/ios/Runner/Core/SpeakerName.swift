// SPDX-License-Identifier: AGPL-3.0-only
// Yalnız iOS'ta (henüz): Kotlin karşılığı yok. Android ve Windows'a da taşınırsa kurallar aynı tutulmalı.
import Foundation

/// Altyazının başındaki konuşmacı adı: "ENZO: ...", "MINE GUARD: ...". Ad her satırda ayrı çevrilince tutarsız
/// çıkıyordu ("MAYIN KORUYUCU", "MADEN KORUYUCU", "MAYIN KORUCU"); ad çevrilmez, olduğu gibi kalır.
/// Ad yalnız büyük harf, rakam, boşluk ve . ' ’ - & işaretlerinden oluşur, en az iki harf içerir, en çok 30
/// karakterdir; ardından iki nokta ve boşluk gelir. Küçük harf içeren "Note: ..." gibi satırlar ad sayılmaz.
enum SpeakerName {
  private static let pattern = try! NSRegularExpression(pattern: "^([A-Z0-9][A-Z0-9 .'’&-]{0,29}):[ \\t]+(\\S.*)$",
                                                        options: [.dotMatchesLineSeparators])

  /// (ad ve ardındaki ": ", geri kalan metin). Ad yoksa ilk değer boştur.
  static func split(_ text: String) -> (String, String) {
    let range = NSRange(text.startIndex..., in: text)
    guard let match = pattern.firstMatch(in: text, range: range),
          let nameRange = Range(match.range(at: 1), in: text),
          let restRange = Range(match.range(at: 2), in: text) else { return ("", text) }
    let name = text[nameRange].trimmingCharacters(in: .whitespaces)
    guard name.unicodeScalars.filter({ CharacterSet.uppercaseLetters.contains($0) }).count >= 2 else { return ("", text) }
    return (name + ": ", String(text[restRange]))
  }
}

/// Altyazıdaki konuşmalar: konuşmacı etiketiyle ("Devin:", "PRISON GUARD:") ya da diyalog tiresiyle başlayan her satır
/// yeni bir konuşmadır, diğer satırlar öncekinin sarmasıdır (kural SubtitleSegmenter.split'inkidir). Birden çok konuşma
/// tek satıra düzleştirilip çevrilince TV'de tek paragrafa akıyordu; hat her konuşmayı kendi satırında gösterir.
enum SpeakerTurns {
  /// Konuşmalar yukarıdan aşağı, her biri tek satır (sarma satırlar boşlukla birleşir). Etiketsiz ilk satır (önceki
  /// konuşmanın devamı) kendi konuşmasıdır. Tek konuşmalı altyazıda tek öğe döner.
  /// Satır ortasında, cümle sonundan (. ! ? …) sonra gelen etiket ("…not mine. Devin: No.") da yeni konuşmadır; ama
  /// yalnız metinde en az iki etiket varsa ya da ad [known] içindeyse (yakın geçmişte satır başında konuşmacı olarak
  /// görülmüş, küçük harfli). Tek başına "He said. Captain: go." bölünmez; "10:30", "In Spanish:" etiket değildir.
  static func split(_ text: String, known: Set<String> = []) -> [String] {
    var blocks: [[SubtitleSegmenter.Piece]] = [[]]
    for piece in SubtitleSegmenter.split(text) {
      if !piece.translate && piece.text == "\n" { blocks.append([]) } else { blocks[blocks.count - 1].append(piece) }
    }
    let labels = blocks.reduce(0) { sum, block in sum + block.filter { SubtitleSegmenter.labelName($0) != nil }.count }
    var turns: [String] = []
    func flush(_ text: String) { if !KotlinText.isBlank(text) { turns.append(KotlinText.trim(text)) } }
    for block in blocks {
      var current = ""
      for (index, piece) in block.enumerated() {
        // Cümle arası ayracından (" ") sonraki etiket: satır ortasında konuşmacı değişimi.
        if index > 0, block[index - 1].text == " ", !block[index - 1].translate, let name = SubtitleSegmenter.labelName(piece),
           labels >= 2 || known.contains(KotlinText.lowercaseRoot(name)) {
          flush(current)
          current = ""
        }
        current += piece.text
      }
      flush(current)
    }
    return turns
  }

  /// Satır başındaki konuşmacı etiketlerinin adları (küçük harfli): hattın yakın geçmiş belleği ([split]'in known'u).
  static func speakers(in text: String) -> [String] {
    var names: [String] = []
    var atLineStart = true
    for piece in SubtitleSegmenter.split(text) {
      if !piece.translate && piece.text == "\n" {
        atLineStart = true
        continue
      }
      if atLineStart, let name = SubtitleSegmenter.labelName(piece) { names.append(KotlinText.lowercaseRoot(name)) }
      // Satır başındaki diyalog tiresi ("- ") etiketi satır başından düşürmez.
      if piece.translate || !piece.text.hasPrefix("-") && !piece.text.hasPrefix("–") && !piece.text.hasPrefix("—") {
        atLineStart = false
      }
    }
    return names
  }

  /// Motorun çok satırlı yanıtı satırlara: boş satırlar atlanır, her satır kırpılır.
  static func lines(_ text: String) -> [String] {
    text.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" })
      .map { KotlinText.trim(String($0)) }
      .filter { !$0.isEmpty }
  }
}

/// Çevirmeni sarar: konuşmacı adı çevirmene gönderilmez, çevirinin başına olduğu gibi konur.
final class SpeakerNameTranslator: TextTranslator {
  private let inner: TextTranslator

  init(_ inner: TextTranslator) { self.inner = inner }

  func translate(_ text: String) -> String? {
    let (name, rest) = SpeakerName.split(text)
    if name.isEmpty { return inner.translate(text) }
    guard let translated = inner.translate(rest)?.trimmingCharacters(in: .whitespacesAndNewlines), !translated.isEmpty else { return nil }
    return name + translated
  }
}
