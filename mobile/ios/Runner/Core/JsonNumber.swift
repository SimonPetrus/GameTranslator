// SPDX-License-Identifier: AGPL-3.0-only
// Ayar JSON'unda sayı okuma: JSONSerialization 0 ve 1 sayılarını da NSNumber verir ve Swift'te bunlar `is Bool` sayılır;
// bu yüzden gerçek true/false, tür kimliğine bakılarak ayırt edilir (yalnız Foundation).
import Foundation

enum JsonNumber {
  /// Değer gerçek bir JSON mantıksal değeri mi (true/false)? Sayı 0 ve 1 değildir.
  static func isBoolean(_ value: Any?) -> Bool {
    guard let value = value else { return false }
    // Swift'in kendi Bool'u (ayarlardan değil, kodla kurulmuş sözlükler).
    if type(of: value) == Bool.self { return true }
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID()
  }

  /// Değer sayıysa NSNumber; mantıksal değerler ve sayı olmayanlar için nil.
  static func number(_ value: Any?) -> NSNumber? {
    guard let value = value, !isBoolean(value), let number = value as? NSNumber else { return nil }
    return number
  }

  /// Sayı ya da sayı gibi yazılmış metin; sonlu değilse ya da okunamıyorsa [fallback].
  static func double(_ value: Any?, _ fallback: Double) -> Double {
    if let n = number(value) {
      let v = n.doubleValue
      return v.isFinite ? v : fallback
    }
    if let t = value as? String, let v = Double(t), v.isFinite { return v }
    return fallback
  }

  static func int(_ value: Any?, _ fallback: Int) -> Int {
    if let n = number(value) { return n.intValue }
    if let t = value as? String, let v = Double(t), v.isFinite, abs(v) < 1e15 { return Int(v) }
    return fallback
  }
}

/// Kayıtlı ayar JSON'unun bozulmasına karşı seçim: asıl kayıt okunamıyorsa yedeğe dönülür (saf mantık; içerik asla
/// günlüğe yazılmaz çünkü API anahtarları içerir).
enum SettingsRecovery {
  enum Source: Equatable { case primary, backup, none }

  /// Metin geçerli bir JSON nesnesi mi (sözlük)?
  static func isValidObject(_ text: String?) -> Bool {
    guard let text = text, !text.isEmpty,
          let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { return false }
    return object is [String: Any]
  }

  /// Kullanılacak kayıt: geçerli asıl kayıt, yoksa geçerli yedek, yoksa .none (varsayılanlar).
  /// [broken] asıl kayıt var ama bozuksa (boş değil) tanı için saklanacak metindir.
  static func choose(primary: String?, backup: String?) -> (text: String?, source: Source, broken: String?) {
    if isValidObject(primary) { return (primary, .primary, nil) }
    let broken: String? = (primary?.isEmpty == false) ? primary : nil
    if isValidObject(backup) { return (backup, .backup, broken) }
    return (nil, .none, broken)
  }
}
