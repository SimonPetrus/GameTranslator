// SPDX-License-Identifier: AGPL-3.0-only
// Ek okuma alanları: ana altyazı bölgesinin dışında, istek üzerine bir kez okunan ekran alanları (görev, eşya adı vb.).
import Foundation

struct ExtraRegion: Equatable {
  /// Ayarlarda tutulan en çok alan sayısı.
  static let maxCount = 3
  static let maxNameLength = 24

  var top = 0.1
  var bottom = 0.3
  var left = 0.1
  var right = 0.5
  var name = ""

  func toJson() -> [String: Any] {
    ["top": top, "bottom": bottom, "left": left, "right": right, "name": name]
  }

  /// Ayar JSON'undaki "extraRegions" dizisi: en çok 3 alan; sayılar sınırlanır, bozuk girdiler atlanır.
  static func parseList(_ value: Any?) -> [ExtraRegion] {
    guard let rows = value as? [Any] else { return [] }
    var out: [ExtraRegion] = []
    for row in rows {
      if out.count >= maxCount { break }
      if let region = parse(row, number: out.count + 1) { out.append(region) }
    }
    return out
  }

  /// [number]: adı boş alana verilecek sıra ("Alan 2").
  static func parse(_ value: Any?, number: Int) -> ExtraRegion? {
    guard let map = value as? [String: Any] else { return nil }
    let d = ExtraRegion()
    let top = clamp(double(map["top"], d.top), 0, 0.95)
    let left = clamp(double(map["left"], d.left), 0, 0.95)
    let bottom = clamp(double(map["bottom"], d.bottom), top + 0.05, 1)
    let right = clamp(double(map["right"], d.right), left + 0.05, 1)
    var name = String((map["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
    if name.isEmpty { name = "Alan \(number)" }
    return ExtraRegion(top: top, bottom: bottom, left: left, right: right, name: name)
  }

  /// Okunan satırları tek cümle olarak birleştirir: boşlar atılır, satır sonundaki tire ("exam-" + "ple") birleşir,
  /// diğer satırlar tek boşlukla eklenir.
  static func joinLines(_ lines: [String]) -> String {
    var out = ""
    for raw in lines {
      let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.isEmpty { continue }
      if out.isEmpty {
        out = line
      } else if out.hasSuffix("-"), out.count >= 2, let before = out.dropLast().last, before.isLetter,
                let first = line.first, first.isLowercase {
        out.removeLast()
        out += line
      } else {
        out += " " + line
      }
    }
    return out
  }

  private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double { min(max(value, low), high) }

  private static func double(_ value: Any?, _ fallback: Double) -> Double { JsonNumber.double(value, fallback) }
}
