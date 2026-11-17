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
    // Koruma ve arka
    ("i've got your six", "I will protect you"), ("i got your six", "I will protect you"),
    ("we've got your six", "we will protect you"), ("we got your six", "we will protect you"),
    ("i'll have your six", "I will protect you"), ("^got your six", "I will protect you"),
    ("watch your six", "look behind you"), ("check your six", "look behind you"),
    ("on your six", "right behind you"), ("on my six", "right behind me"),
    // Tehlike yaklaşıyor
    ("^we've got company", "hostiles are approaching"), ("^we have company", "hostiles are approaching"),
    ("^we got company", "hostiles are approaching"), ("^got company", "hostiles are approaching"),
    ("^incoming", "danger is approaching"), ("^heads up", "pay attention"),
    ("fire in the hole", "an explosion is about to happen"), ("^danger close", "the blast will be right next to us"),
    ("^we're taking fire", "we are being shot at"), ("^we are taking fire", "we are being shot at"),
    ("^i'm taking fire", "I am being shot at"), ("^taking fire", "we are being shot at"),
    ("we're pinned down", "enemy fire keeps us from moving"), ("we are pinned down", "enemy fire keeps us from moving"),
    ("^contact left", "enemy on the left"), ("^contact right", "enemy on the right"),
    ("^contact front", "enemy in front"), ("^contact rear", "enemy behind us"),
    // Dikkatli olmak
    ("stay frosty", "stay focused"), ("stay sharp", "stay focused"), ("keep your eyes peeled", "keep watching closely"),
    ("^look sharp", "pay attention"), ("^look alive", "wake up and pay attention"), ("^eyes up", "pay attention"),
    ("keep your head down", "stay low"),
    // Emir ve hareket
    ("on my mark", "at my signal"), ("on my go", "at my word"), ("^fall back", "withdraw"),
    ("^break contact", "withdraw from the fight"), ("^cover me", "guard me"), ("lock and load", "get your weapons ready"),
    ("locked and loaded", "weapons ready"), ("^move out", "start moving"), ("^move it", "hurry"),
    ("^bug out", "leave at once"), ("^run for it", "run away now"), ("make a run for it", "try to flee"),
    ("make a break for it", "try to flee"), ("cut and run", "flee"), ("turn tail", "flee"),
    ("on the double", "right now"), ("^double time", "go faster"), ("hit the deck", "throw yourself to the ground"),
    ("get to the choppers", "go to the helicopters"), ("get to the chopper", "go to the helicopter"),
    ("^stand down", "stop fighting"), ("^stand by", "be ready and wait"), ("^standing by", "ready and waiting"),
    ("stand your ground", "do not give way"), ("hold your position", "do not leave your spot"),
    ("^hold position", "do not leave your spot"), ("hold your fire", "do not shoot"), ("^cease fire", "stop shooting"),
    ("^open fire", "begin shooting"), ("weapons free", "you may shoot freely"),
    ("weapons hot", "weapons loaded and ready"), ("^at ease", "relax"),
    ("^as you were", "go back to what you were doing"), ("^carry on", "go on"), ("^dismissed", "you are free to go"),
    // Telsiz dili
    ("^say again", "repeat that"), ("do you copy", "can you hear me"), ("do you read me", "can you hear me"),
    ("^loud and clear", "I can hear you well"), ("^wilco", "I will comply"), ("^over and out", "end of transmission"),
    ("oscar mike", "we are on the move"), ("charlie mike", "keep going with the mission"),
    ("^ten-four", "message received"), ("^all clear", "there is no danger"), ("^affirmative", "yes"),
    ("that's a negative", "no"), ("that is a negative", "no"), ("^aye aye", "yes, I understand"),
    ("^tango down", "the enemy has fallen"), ("^target down", "the enemy has fallen"),
    ("^hostile down", "the enemy has fallen"), ("^man down", "a comrade is wounded"),
    ("^officer down", "an officer is wounded"), ("cleared hot", "you may attack"),
    ("cleared to engage", "you may attack"), ("bingo fuel", "we are low on fuel"),
    // Gündelik konuşma
    ("took you long enough", "that took you a while"), ("^about time", "at last"),
    ("sitting ducks", "defenseless targets"), ("sitting duck", "defenseless target"), ("^no sweat", "no trouble at all"),
    ("^hang tight", "stay where you are"), ("^sit tight", "stay where you are"),
    ("hang in there", "keep going, do not quit"), ("you've got this", "you are able to do this"),
    ("you got this", "you are able to do this"), ("let's roll", "let's get started"), ("^cut it out", "stop that"),
    ("^knock it off", "stop that"), ("^beat it", "go away"), ("^scram", "go away"), ("^get lost", "go away"),
    ("^buzz off", "go away"), ("^bite me", "leave me alone"), ("for crying out loud", "for goodness' sake"),
    ("holy smokes", "good heavens"), ("holy cow", "good heavens"), ("holy moly", "good heavens"),
    ("good grief", "good heavens"), ("what the hell is going on", "what on earth is happening"),
    ("hold your horses", "slow down a moment"), ("^easy now", "calm down"), ("^steady now", "stay calm"),
    ("mark my words", "listen carefully to what I say"), ("so help me god", "I swear to God"),
    ("cross my heart", "I promise sincerely"), ("by all that's holy", "I solemnly swear"),
    ("^good hunting", "best of luck"), ("^happy hunting", "best of luck"), ("^godspeed", "best of luck"),
    ("^safe travels", "have a safe trip"), ("^break a leg", "best of luck"), ("rise and shine", "get up"),
    ("hit the sack", "go to bed"), ("call it a night", "end the night here"), ("call it a day", "end the day here"),
    ("wet behind the ears", "inexperienced"), ("in the nick of time", "just in time"),
    ("cat's out of the bag", "the secret is out"), ("let sleeping dogs lie", "leave the matter alone"),
    ("a blessing in disguise", "a hidden benefit"), ("once in a blue moon", "very rarely"),
    ("cost an arm and a leg", "cost a fortune"),
    // Ölüm ve yenilgi
    ("kick the bucket", "pass away"), ("bite the dust", "fall dead"), ("meet your maker", "die"),
    ("dead as a doornail", "absolutely dead"), ("you're toast", "you are finished"), ("we're toast", "we are finished"),
    ("we're done for", "we have lost"), ("we're screwed", "we are in serious trouble"),
    // Saldırı
    ("bring it on", "come and try me"), ("come get some", "come and fight me"), ("give them hell", "hit them hard"),
    ("give 'em hell", "hit them hard"),
    // Korsan
    ("shiver me timbers", "good heavens"), ("^avast", "halt"), ("^ahoy", "hello"), ("me hearties", "my friends"),
    ("scallywag", "rascal"),
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
