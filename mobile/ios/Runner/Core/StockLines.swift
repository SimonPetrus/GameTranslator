// SPDX-License-Identifier: AGPL-3.0-only
// Yalnız iOS'ta (henüz): Kotlin karşılığı yok. Android ve Windows'a da taşınırsa kurallar aynı tutulmalı.
import Foundation

/// Çok kısa kalıp satırların hazır Türkçesi ("Clear!" → "Temiz!"): motora gidilmez, gecikme ve hata payı sıfırdır.
/// Eşleşme büyük/küçük harf, sondaki noktalama ve konuşmacı işareti/adı dışında tam olmalıdır; kaynağın sondaki
/// noktalaması (! ? … .) olduğu gibi korunur. Yalnız belirsiz olmayan satırlar vardır: "Sure", "Fine", "Left" gibi
/// bağlama göre değişenler yoktur. Komutlar tekil (sen) biçimindedir.
/// Yalnız İngilizce→Türkçe için kullanılır; diske yazılmaz.
enum StockLines {
  /// Soru işaretiyle de aynı anlama gelenler ("Hello?" → "Merhaba?").
  private static let neutral: [(String, String)] = [
    ("hello", "Merhaba"), ("hi", "Selam"), ("hey", "Hey"), ("goodbye", "Hoşça kal"), ("bye", "Hoşça kal"),
    ("good morning", "Günaydın"), ("good evening", "İyi akşamlar"), ("good night", "İyi geceler"),
    ("good luck", "İyi şanslar"), ("thanks", "Teşekkürler"), ("thank you", "Teşekkür ederim"),
    ("please", "Lütfen"), ("yes", "Evet"), ("no", "Hayır"), ("okay", "Tamam"), ("ok", "Tamam"),
    ("alright", "Tamam"), ("yeah", "Evet"), ("yep", "Evet"), ("nope", "Hayır"), ("what", "Ne"),
    ("why", "Neden"), ("who", "Kim"), ("where", "Nerede"), ("huh", "Ha"), ("wow", "Vay canına"),
    ("oh no", "Olamaz"),
    ("excellent", "Mükemmel"), ("perfect", "Mükemmel"), ("amazing", "İnanılmaz"), ("incredible", "İnanılmaz"),
    ("great", "Harika"), ("nice", "Güzel"),
  ]

  /// Yalnızca bildirim ya da emir olanlar; "?" ile biterse motora gidilir (anlam değişebilir).
  private static let statements: [(String, String)] = [
    ("hold on", "Bir saniye"), ("wait", "Bekle"), ("sorry", "Üzgünüm"),
    ("i'm sorry", "Üzgünüm"), ("not now", "Şimdi değil"), ("not yet", "Henüz değil"), ("come on", "Hadi"),
    ("quick", "Çabuk"), ("quickly", "Çabuk"), ("good job", "İyi iş"), ("well done", "Aferin"),
    ("nice shot", "Güzel atış"),
    ("clear", "Temiz"), ("all clear", "Her yer temiz"), ("copy", "Anlaşıldı"), ("copy that", "Anlaşıldı"),
    ("roger", "Anlaşıldı"), ("roger that", "Anlaşıldı"), ("understood", "Anlaşıldı"), ("got it", "Anlaşıldı"),
    ("affirmative", "Olumlu"), ("negative", "Olumsuz"), ("will do", "Olur"), ("on it", "Hallediyorum"),
    ("i'm on it", "Hallediyorum"), ("no problem", "Sorun değil"), ("don't worry", "Merak etme"),
    ("go go go", "Hadi hadi hadi"), ("let's go", "Hadi gidelim"),
    ("let's move", "Hadi gidelim"), ("move out", "Harekete geç"),
    ("follow me", "Beni takip et"), ("stay here", "Burada kal"), ("wait here", "Burada bekle"),
    ("stop", "Dur"), ("don't move", "Kımıldama"), ("run", "Koş"),
    ("hurry", "Acele et"), ("hurry up", "Acele et"), ("reload", "Şarjör değiştir"),
    ("reloading", "Şarjör değiştiriyorum"), ("cover me", "Beni koru"), 
    ("grenade", "El bombası"), 
    ("i'm hit", "Vuruldum"), ("i'm hurt", "Yaralandım"),
    ("i'm ready", "Hazırım"), ("i'm here", "Buradayım"), 
    ("almost there", "Neredeyse geldik"), ("fall back", "Geri çekil"), 
    ("hold your fire", "Ateş etme"), ("don't shoot", "Ateş etme"), ("cease fire", "Ateşi kes"),
    ("open fire", "Ateş et"), ("watch out", "Dikkat et"), ("look out", "Dikkat et"),
    ("careful", "Dikkat"), ("be careful", "Dikkatli ol"), ("watch your back", "Arkanı kolla"),
    ("behind you", "Arkanda"), 
    ("over here", "Buraya"), ("this way", "Bu taraftan"), ("that way", "O taraftan"),
    ("target acquired", "Hedef kilitlendi"),
    ("enemy spotted", "Düşman görüldü"), ("take cover", "Siper al"), ("get to cover", "Siper al"),
    ("kill him", "Öldür onu"), ("kill them", "Onları öldür"), 
    ("hands up", "Eller yukarı"), ("drop it", "Bırak onu"),
     ("let go", "Bırak"), ("shut up", "Kapa çeneni"), ("be quiet", "Sessiz ol"),
    ("quiet", "Sessiz"), ("listen", "Dinle"), ("look", "Bak"), ("stay down", "Yerde kal"),
    ("stay close", "Yakın dur"), ("stay behind me", "Arkamda kal"), ("stay with me", "Benimle kal"),
    ("keep going", "Devam et"), ("keep moving", "Hareket etmeye devam et"), ("i see him", "Onu görüyorum"),
    ("damn", "Lanet olsun"), ("damn it", "Lanet olsun"),
    ("dammit", "Lanet olsun"), ("shit", "Kahretsin"), ("help me", "Bana yardım et"),
    ("ready", "Hazır"),
  ]

  private struct Entry {
    let turkish: String
    let neutral: Bool
  }

  private static let table: [String: Entry] = {
    var map: [String: Entry] = [:]
    // Tekrarlayan anahtarda ilk girdi kalır (çökmez).
    for (key, turkish) in neutral where map[key] == nil { map[key] = Entry(turkish: turkish, neutral: true) }
    for (key, turkish) in statements where map[key] == nil { map[key] = Entry(turkish: turkish, neutral: false) }
    return map
  }()

  /// Tablodaki satır sayısı.
  static var count: Int { table.count }

  private static let markChars = Set(".!?…".unicodeScalars)

  /// Hazır Türkçe; satır tabloda değilse nil. Baştaki konuşmacı işareti ve adı korunur.
  static func lookup(_ source: String) -> String? {
    let (prefix, afterPrefix) = SpeakerPrefix.split(source)
    let (name, body) = SpeakerName.split(afterPrefix)
    let trimmed = KotlinText.trim(body)
    if trimmed.isEmpty { return nil }
    // Sondaki noktalama dizisini ayır.
    var scalars = Array(trimmed.unicodeScalars)
    var marks: [Unicode.Scalar] = []
    while let last = scalars.last, markChars.contains(last) {
      marks.insert(last, at: 0)
      scalars.removeLast()
    }
    var core = ""
    core.unicodeScalars.append(contentsOf: scalars)
    // Tırnak, iç noktalama ya da rakam içeren satır kalıp değildir.
    if core.contains(where: { !($0.isLetter || $0 == " " || $0 == "'" || $0 == "’") }) { return nil }
    var key = KotlinText.lowercaseRoot(core).replacingOccurrences(of: "’", with: "'")
    key = KotlinText.string(KotlinText.join(
      KotlinText.splitJavaWhitespace(KotlinText.units(key)).filter { !$0.isEmpty }, [0x20]))
    guard let entry = table[key] else { return nil }
    let markText = String(String.UnicodeScalarView(marks))
    if !entry.neutral && markText.contains("?") { return nil }
    return prefix + name + entry.turkish + markText
  }
}
