// SPDX-License-Identifier: AGPL-3.0-only
// Core/SubtitleLook.swift testleri: `style` çerçevesi (1.8.5 ile bayt bayt aynılık), konuşmacı renk paleti, altyazı yazı
// tipi ve /font/ yolu (TV 1.0.10 protokolü; Kotlin karşılığı yok).
import Foundation

enum SubtitleLookTest {
  /// 1.8.5'teki SubtitleServer.styleFrame'in birebir kopyası (karşılaştırma için).
  static func legacyStyleFrame(_ s: SubtitleStyle) -> String {
    func jsonString(_ text: String) -> String { SubtitleWire.jsonString(text) }
    func colorHex(_ name: String) -> String {
      switch name {
      case "yellow": return "#FFE600"
      case "cyan": return "#38BDF8"
      case "green": return "#10B981"
      case "orange": return "#FF9F0A"
      default: return "#FFFFFF"
      }
    }
    func speakerColorValue(_ s: SubtitleStyle) -> String {
      guard s.speakerColor else { return "" }
      return s.textColor == "yellow" ? "#64D2FF" : "#FFD60A"
    }
    return SubtitleWire.frame("style",
          "{\"background\":\(min(100, max(0, s.background))),\"bold\":\(s.bold),\"bottomPercent\":\(s.bottomPercent),\"color\":\(jsonString(colorHex(s.textColor))),"
            + "\"displayMode\":\(jsonString(s.displayMode)),\"fontSize\":\(s.fontSize),\"placement\":\(jsonString(s.placement)),"
            + "\"speakerColor\":\(jsonString(speakerColorValue(s))),"
            + "\"stackPrevious\":\(s.stackPrevious),\"textColor\":\(jsonString(s.textColor))}")
  }

  static func style(color: String = "white", speaker: Bool = false, colors: Bool = true, font: String = "default") -> SubtitleStyle {
    var s = SubtitleStyle()
    s.textColor = color
    s.speakerColor = speaker
    s.speakerColorsEnabled = colors
    s.subtitleFont = font
    return s
  }

  static func payload(_ frame: String) -> [String: Any]? {
    guard let range = frame.range(of: "data: ") else { return nil }
    let json = frame[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
  }

  static func run() {
    TestRun.test("SubtitleLookTest.offIsByteIdenticalTo185") {
      // Varsayılanlar (konuşmacı adı renkli kapalı, standart yazı tipi), palet kapalı, çeşitli görünümler.
      var odd = SubtitleStyle()
      odd.fontSize = 72
      odd.bold = true
      odd.background = 140
      odd.placement = "fixed"
      odd.stackPrevious = false
      let cases: [SubtitleStyle] = [SubtitleStyle(), style(color: "yellow"), style(speaker: true, colors: false),
                                    style(color: "yellow", speaker: true, colors: false), style(color: "orange", colors: true), odd]
      for s in cases { assertEquals(legacyStyleFrame(s), SubtitleWire.styleFrame(s), "\(s)") }
    }
    TestRun.test("SubtitleLookTest.paletteIsSentWithTheSpeakerColor") {
      let frame = SubtitleWire.styleFrame(style(speaker: true))
      assertEquals("event: style\ndata: {\"background\":72,\"bold\":false,\"bottomPercent\":7,\"color\":\"#FFFFFF\",\"displayMode\":\"inApp\","
                   + "\"fontSize\":46,\"placement\":\"cover\",\"speakerColor\":\"#FFD60A\","
                   + "\"speakerColors\":[\"#FFD60A\",\"#64D2FF\",\"#FF9F0A\",\"#30D158\",\"#FF7AB6\",\"#C49BFF\"],"
                   + "\"stackPrevious\":true,\"textColor\":\"white\"}\n\n", frame)
      assertEquals(6, (payload(frame)?["speakerColors"] as? [String])?.count ?? 0, "geçerli JSON dizisi")
      // Aynı ayarla her çerçevede aynı palet (TV eşlemeyi yalnız palet değişince sıfırlar).
      assertEquals(frame, SubtitleWire.styleFrame(style(speaker: true)))
      // Konuşmacı adı renkli kapalıyken palet gitmez (TV paleti zaten yalnız speakerColor doluyken kullanır).
      assertNull(SubtitleWire.speakerColors(style(speaker: false)))
    }
    TestRun.test("SubtitleLookTest.paletteAvoidsTheTextColor") {
      assertEquals(["#64D2FF", "#FF9F0A", "#30D158", "#FF7AB6", "#C49BFF"], SpeakerPalette.colors(textColor: "yellow"))
      assertEquals(["#FFD60A", "#64D2FF", "#30D158", "#FF7AB6", "#C49BFF"], SpeakerPalette.colors(textColor: "orange"))
      assertEquals(["#FFD60A", "#64D2FF", "#FF9F0A", "#FF7AB6", "#C49BFF"], SpeakerPalette.colors(textColor: "green"))
      assertEquals(["#FFD60A", "#FF9F0A", "#30D158", "#FF7AB6", "#C49BFF"], SpeakerPalette.colors(textColor: "cyan"))
      assertEquals(SpeakerPalette.base, SpeakerPalette.colors(textColor: "white"))
      // Sarı yazıda tek renk açık mavi, palet de onunla başlar.
      let yellow = payload(SubtitleWire.styleFrame(style(color: "yellow", speaker: true)))
      assertEquals("#64D2FF", yellow?["speakerColor"] as? String ?? "")
      assertEquals("#64D2FF", (yellow?["speakerColors"] as? [String])?.first ?? "")
    }
    TestRun.test("SubtitleLookTest.fontFields") {
      let frame = SubtitleWire.styleFrame(style(font: "quicksand"))
      assertEquals("event: style\ndata: {\"background\":72,\"bold\":false,\"bottomPercent\":7,\"color\":\"#FFFFFF\",\"displayMode\":\"inApp\","
                   + "\"fontFamily\":\"Quicksand\",\"fontSize\":46,\"fontUrl\":\"/font/Quicksand.ttf\",\"placement\":\"cover\","
                   + "\"speakerColor\":\"\",\"stackPrevious\":true,\"textColor\":\"white\"}\n\n", frame)
      // Kullanıcı bir kez yazı tipi seçmişti (kalıcı bayrak), şimdi standart: yalnız boş fontFamily eklenir (TV standarda
      // döner; telefon yeniden başlasa da). Hiç seçmediyse alan yok (1.8.5 ile aynı; offIsByteIdenticalTo185).
      var used = SubtitleStyle()
      used.subtitleFontUsed = true
      assertEquals("event: style\ndata: {\"background\":72,\"bold\":false,\"bottomPercent\":7,\"color\":\"#FFFFFF\",\"displayMode\":\"inApp\","
                   + "\"fontFamily\":\"\",\"fontSize\":46,\"placement\":\"cover\",\"speakerColor\":\"\",\"stackPrevious\":true,"
                   + "\"textColor\":\"white\"}\n\n", SubtitleWire.styleFrame(used))
      var chosen = style(font: "quicksand")
      chosen.subtitleFontUsed = true
      assertEquals(frame, SubtitleWire.styleFrame(chosen))
      // Palet ve yazı tipi birlikte.
      let both = payload(SubtitleWire.styleFrame(style(speaker: true, font: "quicksand")))
      assertEquals("Quicksand", both?["fontFamily"] as? String ?? "")
      assertEquals(6, (both?["speakerColors"] as? [String])?.count ?? 0)
    }
    TestRun.test("SubtitleLookTest.fontUsedFlagSurvivesAStaleCopy") {
      // N1: Dart ayarların eski kopyasını (bayrak false) geri yazar; bayrak saklı ayardan ya da yazı tipinden gelir.
      var quicksand = style(font: "quicksand")
      quicksand.subtitleFontUsed = false
      var usedDefault = SubtitleStyle()
      usedDefault.subtitleFontUsed = true
      let plain = SubtitleStyle()
      assertTrue(SubtitleFonts.usedFlag(incoming: plain, stored: quicksand), "Quicksand → Standart (aynı oturum)")
      assertTrue(SubtitleFonts.usedFlag(incoming: plain, stored: usedDefault), "daha önce seçilmişti")
      assertFalse(SubtitleFonts.usedFlag(incoming: plain, stored: plain), "hiç seçilmedi")
      assertTrue(SubtitleFonts.usedFlag(incoming: quicksand, stored: plain), "Quicksand seçili")
      // Akış: Quicksand seçildi, kaydedildi; sonra Dart eski kopyayla Standart gönderdi → çerçeve TV'yi standarda döndürür.
      var saved = quicksand
      saved.subtitleFontUsed = SubtitleFonts.usedFlag(incoming: quicksand, stored: plain)
      var next = plain
      next.subtitleFontUsed = SubtitleFonts.usedFlag(incoming: plain, stored: saved)
      assertTrue(SubtitleWire.styleFrame(next).contains("\"fontFamily\":\"\""))
    }
    TestRun.test("SubtitleLookTest.fontIds") {
      assertEquals("quicksand", SubtitleFonts.normalize("quicksand"))
      assertEquals("default", SubtitleFonts.normalize("default"))
      assertEquals("default", SubtitleFonts.normalize("Comic Sans"))
      assertEquals("default", SubtitleFonts.normalize(""))
      assertNull(SubtitleFonts.font(for: "default"))
      for font in SubtitleFonts.all {
        assertTrue(SubtitleFonts.isSafeFileName(font.file), font.file)
        assertTrue(font.url.hasPrefix("/font/"), font.url)
      }
      assertFalse(SubtitleFonts.isSafeFileName("Quick sand.ttf"))
      assertFalse(SubtitleFonts.isSafeFileName("..ttf"))
      assertFalse(SubtitleFonts.isSafeFileName("Çiçek.ttf"))
      assertFalse(SubtitleFonts.isSafeFileName(""))
    }
    TestRun.test("SubtitleLookTest.fontPathAllowList") {
      assertEquals(SubtitleFonts.quicksand, SubtitleFonts.served(path: "/font/Quicksand.ttf"))
      for path in ["/font/quicksand.ttf", "/font/../Store.swift", "/font/Quicksand.ttf/", "/font/", "/font/%51uicksand.ttf",
                   "/fonts/Quicksand.ttf", "/font//Quicksand.ttf", "/font/Fonts/Quicksand.ttf", "/font/OFL.txt"] {
        assertNull(SubtitleFonts.served(path: path), path)
      }
    }
    TestRun.test("SubtitleLookTest.fontResponseHeaders") {
      assertEquals("HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: font/ttf\r\nCache-Control: max-age=86400\r\n"
                   + "Content-Length: 124824\r\nConnection: close\r\n\r\n", SubtitleWire.fontResponseHead(length: 124824))
    }
    TestRun.test("SubtitleLookTest.fontIsPackaged") {
      guard let dir = ProcessInfo.processInfo.environment["GT_RUNNER_DIR"] else {
        return TestRun.fail("GT_RUNNER_DIR ayarlı değil (run.sh ayarlar)", #fileID, #line)
      }
      let runner = URL(fileURLWithPath: dir)
      let font = (try? Data(contentsOf: runner.appendingPathComponent("Fonts/Quicksand.ttf"))) ?? Data()
      assertTrue(font.count > 10_000, "\(font.count) bayt")
      assertEquals([0, 1, 0, 0], Array(font.prefix(4)), "TrueType imzası")
      let license = (try? String(contentsOf: runner.appendingPathComponent("Fonts/OFL.txt"), encoding: .utf8)) ?? ""
      assertTrue(license.contains("SIL Open Font License, Version 1.1"), "lisans metni")
      let project = (try? String(contentsOf: runner.appendingPathComponent("../Runner.xcodeproj/project.pbxproj"), encoding: .utf8)) ?? ""
      assertTrue(project.contains("Quicksand.ttf in Resources */,"), "yazı tipi pakete giriyor")
      assertTrue(project.contains("OFL.txt in Resources */,"), "lisans pakete giriyor")
    }
  }
}
