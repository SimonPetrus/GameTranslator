// SPDX-License-Identifier: AGPL-3.0-only
// Yalnız iOS'ta (henüz): Kotlin karşılığı yok. Android ve Windows'a da taşınırsa kurallar aynı tutulmalı.
import Foundation

/// Altyazı bölgesine giren oyun düğmesi yazıları: "...who does. RESUME BA", "SKIP RESUME BA", "Hold ⓧ to skip".
/// Bunlar çeviriye karışıyordu ("BA'yı DEVAM ET"). Kurallar temkinlidir; gerçek diyalog silinmez:
/// 1) Satır sonu: büyük harfli düğme sözcükleri (RESUME, SKIP, ...) ve yanlarındaki tuş işaretleri (1–2 karakter: "A",
///    "BA", "R1"; simgeler; L1–R3) silinir. Kuyrukta en az bir düğme sözcüğü bulunmalı ve kuyruk ya satırın tamamı olmalı
///    ya da cümle sonu işaretinden (. ! ? … ") sonra gelmeli.
/// 2) Satır ortası: düğme sözcüğü ile kumanda simgesi (✕ ○ △ □ ⓧ, L1–R3, parantezli "(13)") yan yana ise o dizi silinir.
///    Cümle başındaki baş harfi büyük fiil de ("Hold ⓧ") sayılır; küçük harfli sözcük hiçbir zaman sayılmaz.
///    "<fiil> <simge> to ..." talimatı satırın tamamıysa satır boş olur; diyalogdan sonra gelirse yalnız diyalog kalır.
/// 3) Kuyrukta yalnız simge varsa noktalama aranmaz; yalnız simgelerden oluşan satır boş olur.
enum ButtonHints {
  static let words: Set<String> = [
    "RESUME", "SKIP", "CONTINUE", "BACK", "SELECT", "CLOSE", "CONFIRM", "CANCEL", "NEXT", "EXIT", "HOLD", "PRESS",
    "OPTIONS", "MENU", "ACCEPT", "DECLINE", "RETURN", "PAUSE", "LOG", "JOURNAL", "PROCEED",
  ]

  /// Parçanın satırdaki rolü.
  private enum Role { case hint, icon, trigger, short, text }

  /// Kumanda yüzü simgeleri; çarpı işareti "×" ve oklar bilerek yok (diyalogda geçebilir).
  private static let iconScalars = Set("✕✖✗✘⊗⊠○◯△▵□▢◻▦✜".unicodeScalars)
  private static let circledLetters: ClosedRange<UInt32> = 0x24B6...0x24E9
  private static let bracketChars = CharacterSet(charactersIn: "()[]{}<>|")
  private static let triggerNames: Set<String> = ["L1", "L2", "L3", "R1", "R2", "R3"]
  private static let sentenceEnds = Set(".!?…\"”'’")

  /// Satırdaki düğme yazıları atılmış hali; satır yalnız düğme yazısıysa boş metin.
  static func strip(_ line: String) -> String {
    let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    if parts.isEmpty { return line }
    let roles = assignRoles(parts)
    if let cut = promptCut(parts, roles) { return parts[..<cut].joined(separator: " ") }

    // Aşama 1: ortadaki diziler.
    var items: [(text: String, role: Role)] = []
    var changed = false
    var start = 0
    while start < parts.count {
      if roles[start] == .text {
        items.append((parts[start], .text)); start += 1; continue
      }
      var end = start
      while end < parts.count && roles[end] != .text { end += 1 }
      let slice = roles[start..<end]
      if slice.contains(.hint) && (slice.contains(.icon) || slice.contains(.trigger)) {
        var k = start
        while k < end && roles[k] == .short { items.append((parts[k], .short)); k += 1 }
        changed = true
      } else {
        for k in start..<end { items.append((parts[k], roles[k])) }
      }
      start = end
    }
    if items.isEmpty { return "" }

    // Aşama 2: satır sonu.
    var keep = items.count
    var hintSeen = false, iconSeen = false
    scan: while keep > 0 {
      switch items[keep - 1].role {
      case .hint: hintSeen = true
      case .icon: iconSeen = true
      case .trigger, .short: break
      case .text: break scan
      }
      keep -= 1
    }
    if (hintSeen || iconSeen) && keep < items.count {
      if keep == 0 { return "" }
      let head = items[..<keep].map(\.text).joined(separator: " ")
      if iconSeen || head.last.map({ sentenceEnds.contains($0) }) == true { return head }
    }
    return changed ? items.map(\.text).joined(separator: " ") : line
  }

  /// Simgenin hemen önünde duran ve cümle başında "Hold ⓧ" gibi baş harfi büyük yazılan komut fiilleri.
  private static let promptVerbs: Set<String> = words.union(["TAP", "USE", "TOGGLE", "RELEASE", "CLICK"])

  private static func assignRoles(_ parts: [String]) -> [Role] {
    var roles: [Role] = parts.map { part in
      let inner = unbracketed(part)
      if isIcon(inner) { return .icon }
      if words.contains(part) { return .hint }
      if isTrigger(part, inner) { return .trigger }
      if isShort(part) { return .short }
      return .text
    }
    // Baş harfi büyük ("Hold", "Tap") komut fiili: yalnız cümle başında ve hemen ardından simge geliyorsa.
    for i in 0..<(parts.count - 1) where roles[i] == .text && isTitleCase(parts[i]) && promptVerbs.contains(parts[i].uppercased()) {
      guard roles[i + 1] == .icon || roles[i + 1] == .trigger else { continue }
      if i == 0 || parts[i - 1].last.map({ sentenceEnds.contains($0) }) == true { roles[i] = .hint }
    }
    return roles
  }

  private static func isTitleCase(_ s: String) -> Bool {
    guard let first = s.first, first.isUppercase else { return false }
    return s.dropFirst().allSatisfy { $0.isLetter && $0.isLowercase }
  }

  /// "<komut fiili> <simge> to ..." biçimindeki talimat: bütün satırsa boş, diyalogdan sonra gelirse yalnız diyalog kalır.
  /// Nil: bu biçim yok.
  private static func promptCut(_ parts: [String], _ roles: [Role]) -> Int? {
    guard parts.count >= 3 else { return nil }
    for s in 0..<(parts.count - 2) where roles[s] == .hint && (roles[s + 1] == .icon || roles[s + 1] == .trigger)
      && parts[s + 2].lowercased() == "to" {
      if s == 0 { return 0 }
      if parts[s - 1].last.map({ sentenceEnds.contains($0) }) == true { return s }
    }
    return nil
  }

  private static func unbracketed(_ s: String) -> String { s.trimmingCharacters(in: bracketChars) }

  private static func isIcon(_ s: String) -> Bool {
    !s.isEmpty && s.unicodeScalars.allSatisfy { iconScalars.contains($0) || circledLetters.contains($0.value) }
  }

  /// "L2", "R1" gibi tetik adı; parantez içinde ilk karakter 1/I/l/| okunmuş L'dir ("(13)", "I2)").
  private static func isTrigger(_ part: String, _ inner: String) -> Bool {
    if triggerNames.contains(inner) { return true }
    guard inner != part, inner.count == 2, let lead = inner.first, let digit = inner.last else { return false }
    return "1Il|".contains(lead) && "123".contains(digit)
  }

  /// Tuş işareti gibi okunan kısa parça: 1–2 büyük harf ya da rakam ("A", "BA", "R1", "L2", "X").
  private static func isShort(_ part: String) -> Bool {
    (1...2).contains(part.count) && part.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
  }
}
