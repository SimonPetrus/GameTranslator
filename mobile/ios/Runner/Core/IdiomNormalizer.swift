// SPDX-License-Identifier: AGPL-3.0-only
// Yalnız iOS'ta (henüz): Kotlin karşılığı yok. Android ve Windows'a da taşınırsa kurallar aynı tutulmalı.
import Foundation

/// Oyun deyimlerini çeviri motoruna gitmeden önce aynı anlamdaki düz İngilizceyle değiştirir: motorlar "got your six"
/// gibi deyimleri sözcüğü sözcüğüne çevirir ("altın altı"). Yalnız İngilizce→Türkçe ve Gemini dışı motorlarda kullanılır
/// (Gemini bağlamı kendisi anlar). Eşleşme tam sözcük sınırında ve büyük/küçük harfe bakmadan olur; baştaki büyük harf
/// ve tümü büyük yazım korunur, noktalama dokunulmaz kalır.
/// Tablodaki "^" önekli girdiler yalnız tek başına bir cümlecik olduğunda değişir (başında cümle başı/noktalama,
/// sonunda noktalama ya da satır sonu): "Fall back!" değişir, "he will fall back asleep" değişmez.
enum IdiomNormalizer {
  /// (deyim, yerine konacak düz İngilizce). Sıra önemsizdir; uzun deyim önce denenir.
  static let entries: [(String, String)] = [
    // Arkayı kollamak
    ("got your six", "got your back"), ("have your six", "have your back"), ("watch your six", "watch your back"),
    ("check your six", "look behind you"), ("on your six", "behind you"), ("on my six", "behind me"),
    ("i've got your six", "I've got your back"),
    // Düşman geliyor
    ("^we've got company", "enemies are coming"), ("^we have company", "enemies are coming"),
    ("^we got company", "enemies are coming"), ("^we've got incoming", "an attack is coming"),
    ("^incoming", "an attack is coming"), ("^heads up", "watch out"), ("fire in the hole", "an explosion is coming"),
    ("^danger close", "the danger is very close to us"), ("taking fire", "under attack"),
    ("we're pinned down", "we cannot move because of enemy fire"), ("we are pinned down", "we cannot move because of enemy fire"),
    ("^contact left", "enemy on the left"), ("^contact right", "enemy on the right"),
    ("^contact front", "enemy in front"), ("^contact rear", "enemy behind us"),
    // Uyanık kalmak
    ("stay frosty", "stay alert"), ("stay sharp", "stay alert"), ("keep your eyes peeled", "watch carefully"),
    ("^look sharp", "be alert"), ("^look alive", "be alert"), ("^eyes up", "look carefully"),
    ("keep your head down", "stay low and hidden"),
    // Emir ve hareket
    ("on my mark", "when I say so"), ("on my go", "when I say go"), ("^fall back", "retreat"),
    ("^break contact", "retreat"), ("^cover me", "protect me"), ("lock and load", "get ready to fight"),
    ("locked and loaded", "ready to fight"), ("^move out", "go"), ("^move it", "hurry up"),
    ("^bug out", "leave quickly"), ("^run for it", "run away"), ("make a run for it", "try to run away"),
    ("make a break for it", "try to escape"), ("cut and run", "run away"), ("turn tail", "run away"),
    ("on the double", "quickly"), ("^double time", "run quickly"), ("hit the deck", "lie down on the ground"),
    ("hit the dirt", "lie down on the ground"), ("get to the choppers", "go to the helicopters"),
    ("get to the chopper", "go to the helicopter"), ("^stand down", "stop, do not attack"),
    ("^stand by", "wait"), ("^standing by", "waiting"), ("stand your ground", "do not retreat"),
    ("hold your position", "stay where you are"), ("^hold position", "stay where you are"),
    ("hold your fire", "do not shoot"), ("^cease fire", "stop shooting"), ("^open fire", "start shooting"),
    ("weapons free", "you may fire at will"), ("weapons hot", "weapons are ready to fire"),
    ("^at ease", "relax"), ("^as you were", "continue what you were doing"), ("^carry on", "continue"),
    ("^dismissed", "you may go"), ("all hands on deck", "everyone help now"),
    ("batten down the hatches", "prepare for trouble"),
    // Telsiz dili
    ("^say again", "repeat that"), ("do you copy", "can you hear me"), ("do you read me", "can you hear me"),
    ("^loud and clear", "I hear you well"), ("^wilco", "I will do it"), ("^over and out", "end of message"),
    ("oscar mike", "we are moving"), ("charlie mike", "continue the mission"), 
    ("^ten-four", "understood"), ("^all clear", "no danger now"), ("the coast is clear", "no enemy is near"),
    ("^affirmative", "yes"), ("that's a negative", "no"), ("that is a negative", "no"),
    ("^aye aye", "yes, understood"), ("^tango down", "the enemy is dead"), ("^target down", "the enemy is dead"),
    ("^hostile down", "the enemy is dead"), ("^man down", "a soldier is hurt"), ("^officer down", "an officer is hurt"),
    ("cleared hot", "allowed to attack"), ("cleared to engage", "allowed to attack"), ("bingo fuel", "fuel is low"),
    // Gündelik konuşma
    ("took you long enough", "you took a long time"), ("^about time", "finally"), ("sitting ducks", "easy targets"),
    ("sitting duck", "easy target"), ("piece of cake", "very easy"), ("walk in the park", "very easy"),
    ("easy peasy", "very easy"), ("^no sweat", "no problem"), ("^hang tight", "wait here"),
    ("^sit tight", "wait here"), ("hang in there", "do not give up"), ("you've got this", "you can do it"),
    ("you got this", "you can do it"), ("let's roll", "let's go"), ("^cut it out", "stop it"),
    ("^knock it off", "stop it"), ("^beat it", "go away"), ("^scram", "go away"), ("^get lost", "go away"),
    ("^buzz off", "go away"), ("^bite me", "leave me alone"), ("for crying out loud", "for heaven's sake"),
    ("holy smokes", "wow"), ("holy cow", "wow"), ("holy moly", "wow"), ("good grief", "oh dear"),
    ("what the hell is going on", "what is going on"), ("hold your horses", "wait a moment"),
    ("^easy now", "be careful"), ("^steady now", "stay calm"), ("mark my words", "remember what I say"),
    ("so help me god", "I swear to God"), ("cross my heart", "I promise"), ("by all that's holy", "I swear"),
    ("^good hunting", "good luck"), ("^happy hunting", "good luck"), ("^godspeed", "good luck"),
    ("^safe travels", "have a safe journey"), ("^break a leg", "good luck"), ("rise and shine", "wake up"),
    ("hit the road", "leave"), ("hit the sack", "go to sleep"), ("call it a night", "stop for tonight"),
    ("call it a day", "stop for today"),
    // Ölüm ve yenilgi
    ("kick the bucket", "die"), ("bite the dust", "die"), ("bought the farm", "died"), ("buy the farm", "die"),
    ("pushing up daisies", "dead"), ("meet your maker", "die"), ("dead as a doornail", "completely dead"),
    ("six feet under", "dead and buried"), ("we're toast", "we are finished"), ("you're toast", "you are finished"),
    ("we're done for", "we are lost"), ("we're screwed", "we are in big trouble"),
    // Saldırı ve savaş
    ("bring it on", "come and fight me"), ("come get some", "come and fight me"),
    ("give them hell", "fight hard against them"), ("give 'em hell", "fight hard against them"),
    ("let them have it", "attack them with full force"), ("eat lead", "get shot"),
    // Korsan ve macera
    ("shiver me timbers", "oh my goodness"), ("^avast", "stop"), ("^ahoy", "hello there"),
    ("me hearties", "my friends"), ("scallywag", "rascal"),
  ]

  private struct Rule {
    let regex: NSRegularExpression
    let replacement: String
    let clauseOnly: Bool
  }

  /// Etkin kural sayısı (tekrarsız).
  static var count: Int { rules.count }

  private static let rules: [Rule] = {
    var seen = Set<String>()
    var built: [(Int, Rule)] = []
    for (raw, replacement) in entries {
      let clauseOnly = raw.hasPrefix("^")
      let phrase = KotlinText.lowercaseRoot(clauseOnly ? String(raw.dropFirst()) : raw)
      if !seen.insert((clauseOnly ? "^" : "") + phrase).inserted { continue }
      var body = ""
      for ch in phrase {
        if ch == " " { body += "[ \\t]+" }
        else if ch == "'" || ch == "’" { body += "['’]" }
        else { body += NSRegularExpression.escapedPattern(for: String(ch)) }
      }
      let pattern = "(?<![\\p{L}\\p{N}'’])" + body + "(?![\\p{L}\\p{N}])"
      guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
      built.append((phrase.count, Rule(regex: regex, replacement: replacement, clauseOnly: clauseOnly)))
    }
    // Uzun deyim önce: "i've got your six", "got your six"tan önce eşleşir.
    return built.sorted { $0.0 > $1.0 }.map { $0.1 }
  }()

  /// Metindeki deyimleri değiştirir; deyim yoksa metin aynen döner.
  static func apply(_ text: String) -> String {
    var current = text
    for rule in rules {
      let ns = current as NSString
      let matches = rule.regex.matches(in: current, options: [], range: NSRange(location: 0, length: ns.length))
      if matches.isEmpty { continue }
      var out = ""
      var last = 0
      var changed = false
      for match in matches {
        if rule.clauseOnly && !isWholeClause(ns, match.range) { continue }
        out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
        out += cased(rule.replacement, like: ns.substring(with: match.range))
        last = match.range.location + match.range.length
        changed = true
      }
      if changed {
        out += ns.substring(from: last)
        current = out
      }
    }
    return current
  }

  private static let openers = "\"“”'‘’(-–—>"
  private static let breaks = ".!?,;:…"
  private static let closers = "\"”’')"

  /// Eşleşme tek başına bir cümlecik mi: öncesi metin başı ya da noktalama, sonrası noktalama ya da metin sonu.
  private static func isWholeClause(_ ns: NSString, _ range: NSRange) -> Bool {
    var i = range.location - 1
    while i >= 0 {
      let c = ns.character(at: i)
      if c == 0x20 || c == 0x09 || openers.utf16.contains(c) { i -= 1; continue }
      if !breaks.utf16.contains(c) { return false }
      break
    }
    var j = range.location + range.length
    while j < ns.length {
      let c = ns.character(at: j)
      if c == 0x20 || c == 0x09 || closers.utf16.contains(c) { j += 1; continue }
      return breaks.utf16.contains(c)
    }
    return true
  }

  /// Eşleşen yazımın büyük/küçük harf düzenini yerine konana uygular: "Fall back" → "Retreat", "FALL BACK" → "RETREAT".
  private static func cased(_ replacement: String, like matched: String) -> String {
    let letters = matched.filter { $0.isLetter }
    if letters.count >= 2 && letters.allSatisfy({ $0.isUppercase }) { return replacement.uppercased() }
    guard let first = matched.first(where: { $0.isLetter }), first.isUppercase, let head = replacement.first else {
      return replacement
    }
    // "I've" gibi zaten büyük başlayan karşılıklar aynen kalır.
    return String(head).uppercased() + String(replacement.dropFirst())
  }
}
