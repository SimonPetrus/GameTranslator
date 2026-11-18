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

  // MARK: - Tuş ipucu satırı ("Hold L2 to aim")

  /// İpucunun başındaki eylem fiilleri (PS5 kumandası: tuşlar, tetikler, çubuklar, dokunmatik yüzey; "Double tap" ve
  /// "Press and hold" ayrıca bakılır).
  private static let actionVerbs: Set<String> = [
    "hold", "press", "tap", "release", "use", "push", "pull", "click", "toggle", "move", "tilt", "rotate", "flick",
    "squeeze", "half-press", "mash", "swipe",
  ]
  /// Simge okunmadığında da ipucu sayılan basış fiilleri ("Hold to aim"). "Move", "Use", "Push" gibi genel fiiller
  /// ancak açık bir düğme ya da çubukla ipucudur ("Move to cover on three" diyalogdur).
  private static let pressVerbs: Set<String> = ["hold", "press", "tap", "double", "release", "squeeze", "mash", "half-press", "click"]
  /// "to"dan sonra gelince ipucu değil diyalog olan sözcükler ("Push to the limit!", "Move to the left.").
  private static let notActions: Set<String> = [
    "the", "a", "an", "my", "your", "his", "her", "its", "our", "their", "me", "him", "them", "us", "it", "this", "that",
    "these", "those", "you", "be", "do", "go",
  ]
  /// Simge yerine okunabilen düğme adları: şekil tuşları, yön tuşu, Options/Share/Create, PS, dokunmatik yüzey.
  /// Çubuk ("stick") yalnız yanıyla düğmedir: "left stick", "R stick", "analog stick" ([stickSides]).
  private static let buttonNames: Set<String> = [
    "options", "share", "create", "touchpad", "d-pad", "dpad", "ps", "triangle", "circle", "cross", "square",
  ]
  private static let stickWords: Set<String> = ["stick", "sticks"]
  private static let stickSides: Set<String> = ["left", "right", "l", "r", "analog", "both"]
  /// Düğmenin yanında durabilen sözcükler ("L2 + R2", "L1 and R1", "✕ repeatedly", "up on the D-pad").
  private static let buttonFillers: Set<String> = [
    "+", "&", "/", "and", "or", "both", "left", "right", "up", "down", "on", "repeatedly", "quickly", "button", "buttons",
    "trigger", "triggers",
  ]
  /// "the" yalnız bu sözcüklerden biriyle düğme dizisinde durabilir ("the left stick", "the D-pad"); "Use the cross" diyalogdur.
  private static let theAllowedWith: Set<String> = ["stick", "sticks", "d-pad", "dpad", "touchpad", "button", "buttons", "trigger", "triggers"]
  /// Simge okunmadığında fiille "to" arasında kalabilen sözcükler ("Tap repeatedly to break free").
  private static let repeatWords: Set<String> = ["repeatedly", "quickly"]
  /// Yön tuşu okları; diyalogda geçmez.
  private static let arrowScalars = Set("←↑→↓⬅⬆➡⬇".unicodeScalars)
  /// OCR'ın şekil tuşları için okuduğu biçimler (✕ → x, ○ → o/0, △ → ^, □ → [] ya da 口).
  private static let shapeMisreads: Set<String> = ["x", "o", "0", "^", "[]", "()", "口"]
  private static let tokenEdges = CharacterSet(charactersIn: "()[]{}<>|.,!?:;…")

  /// Tek başına oyunun tuş ipucu satırı mı (İngilizce kalıp): "<eylem fiili> <düğmeler> to <fiil>" — "Hold L2 to aim",
  /// "Press ✕ to continue", "Double tap R1 to dodge", "Hold L2 + R2 to aim", "Move the left stick to walk", OCR'ın
  /// bozduğu "Hold [2 to aim", "Hold L2to aim", "Hold LZ to aim"; "to"suz yalnız düğmeli "Press ✕", "Tap ✕ repeatedly";
  /// simgesi hiç okunmamış "Hold to aim", "Tap repeatedly to break free".
  /// Koşullar: satır büyük harfli fiille başlar (konuşmacı etiketi yok), en çok 8 sözcük, virgül yok; "to"dan sonra 1–4
  /// sözcük gelir ve ilki zamir/tanımlık değildir. Sonda cümle noktalaması varsa (oyun ipuçları çoğunlukla noktasızdır)
  /// yalnız simge, ok ya da L1–R3 gibi açık bir tuşla ipucudur. Simge okunmadıysa daha sıkı: yalnız basış fiilleri
  /// ([pressVerbs]), en çok 5 sözcük, "to"dan sonra en çok 3 sözcük, noktalama yok ve satır bir sonraki satıra küçük
  /// harfle sürmüyor ([continues]: sarılmış diyalogun ilk satırı). "Hold on to this.", "Press charges against him.",
  /// "Use the cross to ward him off.", "Use V to distract them.", "Use the stick to hit him." ipucu değildir.
  static func isPrompt(_ line: String, continues: Bool = false) -> Bool {
    var tokens: [String] = []
    for part in line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init) {
      // Düğme adına yapışmış "to" ("L2to") ayrılır.
      if part.count > 2, part.lowercased().hasSuffix("to"), isButtonToken(String(part.dropLast(2))) {
        tokens.append(String(part.dropLast(2)))
        tokens.append("to")
      } else {
        tokens.append(part)
      }
    }
    guard tokens.count >= 2, tokens.count <= 8, !line.contains(","), let initial = tokens[0].first, initial.isUppercase,
          let last = line.trimmingCharacters(in: .whitespaces).last else {
      return false
    }
    let punctuated = ".!?…".contains(last)
    var start = 1
    let verb = tokens[0].lowercased()
    if verb == "double" {
      guard tokens[1].lowercased() == "tap" else { return false }
      start = 2
    } else if !actionVerbs.contains(verb) {
      return false
    }
    // "Press and hold ✕ to ...": ikinci fiil atlanır.
    if start + 1 < tokens.count, tokens[start].lowercased() == "and", actionVerbs.contains(tokens[start + 1].lowercased()) {
      start += 2
    }
    guard start < tokens.count else { return false }
    guard let to = tokens[start...].firstIndex(where: { $0.lowercased() == "to" }) else {
      // "to"suz ipucu yalnız düğmelerden oluşur: "Press ✕", "Hold L2 + R2", "Tap ✕ repeatedly".
      return tokens.count <= 6 && isButtonGroup(tokens[start...], punctuated: punctuated)
    }
    let middle = tokens[start..<to]
    let rest = tokens[(to + 1)...]
    guard !rest.isEmpty, rest.count <= 4 else { return false }
    let next = rest.first!.lowercased().filter { $0.isLetter }
    guard !next.isEmpty, !notActions.contains(next) else { return false }
    if middle.allSatisfy({ repeatWords.contains($0.lowercased()) }) {
      // Simge okunmadı.
      return pressVerbs.contains(verb) && tokens.count <= 5 && rest.count <= 3 && !punctuated && !continues
    }
    return isButtonGroup(middle, punctuated: punctuated)
  }

  /// Düğme dizisi: en az bir düğme, geri kalanı düğme yanı sözcükleri, en çok 5 parça. [punctuated]: satır cümle
  /// noktalamasıyla bitiyor; o zaman dizide açık bir tuş ([isStrongButton]) bulunmalı.
  private static func isButtonGroup(_ parts: ArraySlice<String>, punctuated: Bool) -> Bool {
    guard !parts.isEmpty, parts.count <= 5 else { return false }
    let items = Array(parts)
    let lowered = items.map { $0.lowercased().trimmingCharacters(in: tokenEdges) }
    var button = items.map { isButtonToken($0) }
    // Çubuk yalnız yanıyla: "left stick", "R stick", "analog stick".
    for i in lowered.indices.dropFirst() where stickWords.contains(lowered[i]) && stickSides.contains(lowered[i - 1]) {
      button[i] = true
      button[i - 1] = true
    }
    guard button.contains(true) else { return false }
    if punctuated && !items.contains(where: { isStrongButton($0) }) { return false }
    let allowsThe = lowered.contains { theAllowedWith.contains($0) }
    for i in items.indices where !button[i] {
      if buttonFillers.contains(lowered[i]) || (allowsThe && lowered[i] == "the") { continue }
      return false
    }
    return true
  }

  /// Açık tuş: kumanda simgesi, ok ya da L1–R3 (küçük harfli ya da bozuk okunmuş: "l2", "12", "[2", "(L2)", "LZ",
  /// "02"). Diyalogda bu biçimler geçmez.
  private static func isStrongButton(_ part: String) -> Bool {
    let inner = part.trimmingCharacters(in: tokenEdges)
    if inner.isEmpty { return false }
    if isIcon(inner) || inner.unicodeScalars.allSatisfy({ arrowScalars.contains($0) }) || triggerNames.contains(inner.uppercased()) {
      return true
    }
    let scalars = Array(inner.unicodeScalars)
    guard scalars.count <= 2, let second = scalars.last else { return false }
    if "123".unicodeScalars.contains(second) {
      return scalars.count == 1 || "LlRrIi1|0Oo".unicodeScalars.contains(scalars[0])
    }
    // "L2"/"R2"deki 2'nin Z okunuşu.
    return scalars.count == 2 && "LR".unicodeScalars.contains(scalars[0]) && "Zz".unicodeScalars.contains(second)
  }

  /// Düğme yerine okunan parça: açık tuş ([isStrongButton]), düğme adı (OPTIONS, Touchpad, D-pad, Triangle) ya da
  /// şekil tuşunun bozuk okunuşu ("X", "x", "o", "[]"). Başka tek büyük harf ("V", tek başına "L") düğme sayılmaz.
  private static func isButtonToken(_ part: String) -> Bool {
    if shapeMisreads.contains(part.lowercased()) { return true }
    let inner = part.trimmingCharacters(in: tokenEdges)
    if inner.isEmpty { return false }
    return shapeMisreads.contains(inner.lowercased()) || buttonNames.contains(inner.lowercased()) || isStrongButton(inner)
  }

  /// Altyazı olmayan satırları parçalarıyla birlikte atar (yazı da kutu da onları içermesin): tamamı düğme yazısı olan
  /// satır ([strip] boş döner), İngilizcede tuş ipucu satırı ([isPrompt]) ve harf ya da rakam içermeyen satır ("● ○ ○").
  /// Satırlar [ReadingSelector.rows] ile kurulur; Vision ipucunu simgenin iki yanında iki parça okusa da satır tek bakılır.
  /// Hemen altındaki satır küçük harfle başlıyorsa satır sarılmış bir cümlenin başıdır (simgesiz kalıpta ipucu sayılmaz).
  static func dropHintRows(_ input: [TextObservation], english: Bool) -> [TextObservation] {
    let rows = ReadingSelector.rows(input)
    var kept: [TextObservation] = []
    for (index, row) in rows.enumerated() {
      let text = row.map(\.text).joined(separator: " ")
      if !text.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) { continue }
      if strip(text).isEmpty { continue }
      if english {
        let continues = index + 1 < rows.count && continuesInto(row, rows[index + 1])
        if isPrompt(text, continues: continues) { continue }
      }
      kept.append(contentsOf: row)
    }
    return kept
  }

  /// [next] satırı [row]'un hemen altında (aradaki boşluk bir satır yüksekliğini aşmıyor) ve küçük harfle başlıyor mu.
  private static func continuesInto(_ row: [TextObservation], _ next: [TextObservation]) -> Bool {
    guard let bottom = row.map(\.bottom).max(), let height = row.map(\.height).max(), let top = next.map(\.top).min(),
          let first = next.map(\.text).joined(separator: " ").first(where: { $0.isLetter }) else { return false }
    return top - bottom <= height && first.isLowercase
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
