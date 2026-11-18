// SPDX-License-Identifier: AGPL-3.0-only
// Core/ButtonHints.swift testleri (Kotlin karşılığı yok).
import Foundation

enum ButtonHintsTest {
  static func run() {
    TestRun.test("ButtonHintsTest.trailingPromptsAreRemoved") {
      assertEquals("IL MERLO: then clear the way for someone who does.", ButtonHints.strip("IL MERLO: then clear the way for someone who does. RESUME BA"))
      assertEquals("MINER: Nobody's working down there until it's checked out.", ButtonHints.strip("MINER: Nobody's working down there until it's checked out. SKIP RESUME BA"))
      assertEquals("Let's go!", ButtonHints.strip("Let's go! SKIP X"))
      assertEquals("", ButtonHints.strip("SKIP RESUME BA"))
      assertEquals("", ButtonHints.strip("A CONTINUE"))
    }
    TestRun.test("ButtonHintsTest.dialogueIsLeftAlone") {
      assertEquals("I said go back", ButtonHints.strip("I said go back"))
      assertEquals("WE NEED TO GO BACK", ButtonHints.strip("WE NEED TO GO BACK"))
      assertEquals("Don't skip it. OK", ButtonHints.strip("Don't skip it. OK"))
      assertEquals("He said: SKIP", ButtonHints.strip("He said: SKIP"))
      assertEquals("PS5", ButtonHints.strip("PS5"))
      assertEquals("", ButtonHints.strip(""))
    }
    TestRun.test("ButtonHintsTest.middleOfLineHintIsRemoved") {
      assertEquals("then run", ButtonHints.strip("Hold ⓧ then run"))
      assertEquals("We must leave now.", ButtonHints.strip("We must PRESS L2 leave now."))
      assertEquals("Open the gate", ButtonHints.strip("Open SKIP △ the gate"))
    }
    TestRun.test("ButtonHintsTest.promptPhrasesAreDropped") {
      assertEquals("", ButtonHints.strip("Tap △ to climb the ladder"))
      assertEquals("", ButtonHints.strip("Hold ⓧ to skip"))
      assertEquals("Let's go.", ButtonHints.strip("Let's go. Hold ⓧ to skip"))
      assertEquals("Please come back", ButtonHints.strip("Please come back ✕"))
      assertEquals("Please come Back to me", ButtonHints.strip("Please come Back to me"))
      assertEquals("Tap the rail to climb", ButtonHints.strip("Tap the rail to climb"))
      assertEquals("Hold on to the ladder", ButtonHints.strip("Hold on to the ladder"))
    }
    TestRun.test("ButtonHintsTest.iconGlyphNoiseIsRemoved") {
      assertEquals("", ButtonHints.strip("✕"))
      assertEquals("", ButtonHints.strip("○ △"))
      assertEquals("Wait here", ButtonHints.strip("Wait here ✕"))
      assertEquals("Run away", ButtonHints.strip("Run away ⓧ"))
      assertEquals("Let's go!", ButtonHints.strip("Let's go! SKIP ✕"))
    }
    TestRun.test("ButtonHintsTest.shoulderButtonOcrForms") {
      assertEquals("Take cover.", ButtonHints.strip("Take cover. HOLD L2"))
      assertEquals("Take cover.", ButtonHints.strip("Take cover. HOLD (13)"))
      assertEquals("Fire!", ButtonHints.strip("Fire! PRESS R1"))
      assertEquals("Quiet now", ButtonHints.strip("Quiet PRESS I3) now"))
    }
    TestRun.test("ButtonHintsTest.moreDialogueIsLeftAlone") {
      assertEquals("Press the button", ButtonHints.strip("Press the button"))
      assertEquals("I can hold on", ButtonHints.strip("I can hold on"))
      assertEquals("Take the L2 route", ButtonHints.strip("Take the L2 route"))
      assertEquals("He is (13) years old", ButtonHints.strip("He is (13) years old"))
      assertEquals("A", ButtonHints.strip("A"))
      assertEquals("X", ButtonHints.strip("X"))
      assertEquals("I", ButtonHints.strip("I"))
      assertEquals("3 × 4 = 12", ButtonHints.strip("3 × 4 = 12"))
      assertEquals("GO BACK, I SAID", ButtonHints.strip("GO BACK, I SAID"))
      assertEquals("Press START to begin", ButtonHints.strip("Press START to begin"))
    }
    // Her grupta önce ipucu, sonra ona benzeyen diyalog.
    TestRun.test("ButtonHintsTest.triggerPrompts") {
      for line in ["Hold L2 to aim", "Hold [2 to aim", "Hold L2to aim", "Hold 12 to aim", "Hold (L2) to aim", "Press R1 to shoot",
                   "Double tap R1 to dodge", "Press L3 to sprint", "HOLD R2 TO FIRE", "Hold LZ to aim", "Hold 02 to aim"] {
        assertTrue(ButtonHints.isPrompt(line), line)
      }
      assertFalse(ButtonHints.isPrompt("Hold on, I'm coming!"))
      assertFalse(ButtonHints.isPrompt("Hold on to this."))
      assertFalse(ButtonHints.isPrompt("I need to hold on to this."))
    }
    TestRun.test("ButtonHintsTest.shapeButtonPrompts") {
      for line in ["Press ✕ to continue", "Press X to continue", "Press x to continue", "Press square to reload",
                   "Hold △ to interact", "Press [] to reload", "Press ○ to cancel"] {
        assertTrue(ButtonHints.isPrompt(line), line)
      }
      assertFalse(ButtonHints.isPrompt("Use the cross to ward him off."))
      assertFalse(ButtonHints.isPrompt("Press charges against him."))
    }
    TestRun.test("ButtonHintsTest.directionAndSystemButtonPrompts") {
      for line in ["Press up on the D-pad to heal", "Press ↑ to heal", "Press OPTIONS to pause", "Hold PS to open the menu",
                   "Press Create to take a screenshot", "Swipe touchpad to open the map", "Press touchpad"] {
        assertTrue(ButtonHints.isPrompt(line), line)
      }
      assertFalse(ButtonHints.isPrompt("Hold up to ten people."))
      assertFalse(ButtonHints.isPrompt("Move up to the roof."))
    }
    TestRun.test("ButtonHintsTest.stickAndTriggerPressurePrompts") {
      for line in ["Move L stick to walk", "Tilt R stick to look around", "Push the left stick to sprint", "Rotate the right stick to aim",
                   "Move the analog stick to steer",
                   "Squeeze R2 to fire", "Half-press L2 to focus", "Flick R3 to switch targets"] {
        assertTrue(ButtonHints.isPrompt(line), line)
      }
      assertFalse(ButtonHints.isPrompt("Push to the limit!"))
      assertFalse(ButtonHints.isPrompt("Move to the left."))
      assertFalse(ButtonHints.isPrompt("Squeeze me in, please."))
    }
    TestRun.test("ButtonHintsTest.comboAndRepeatPrompts") {
      for line in ["Hold L2 + R2 to aim", "Press L1 and R1 to switch", "Hold L2 + R2", "Press and hold ✕ to sprint",
                   "Tap ✕ repeatedly to break free", "Tap ✕ repeatedly", "Mash ○ to escape", "Press ✕"] {
        assertTrue(ButtonHints.isPrompt(line), line)
      }
      assertFalse(ButtonHints.isPrompt("Lucia: Hold him down!"))
      assertFalse(ButtonHints.isPrompt("Tap the glass to wake him."))
      assertFalse(ButtonHints.isPrompt("Hold it."))
    }
    TestRun.test("ButtonHintsTest.promptsWithoutTheIcon") {
      for line in ["Hold to aim", "Press to skip", "Tap repeatedly to break free", "Mash to break free", "Release to throw"] {
        assertTrue(ButtonHints.isPrompt(line), line)
      }
      assertFalse(ButtonHints.isPrompt("Release him to me."))
      assertFalse(ButtonHints.isPrompt("Hold to that, son."))
      assertFalse(ButtonHints.isPrompt("Use your head to think."))
      assertFalse(ButtonHints.isPrompt("Pull to shore!"))
    }
    TestRun.test("ButtonHintsTest.dialogueThatLooksLikeAPromptIsKept") {
      // Genel fiil simgesiz ipucu değildir (sarılmış diyalogun ilk satırı).
      assertFalse(ButtonHints.isPrompt("Move to cover on three"))
      // Tek büyük harf düğme değildir; L/R yalnız çubukla.
      assertFalse(ButtonHints.isPrompt("Use V to distract them."))
      assertFalse(ButtonHints.isPrompt("Move L to walk"))
      // "the stick" tek başına çubuk tuşu değildir.
      assertFalse(ButtonHints.isPrompt("Use the stick to hit him."))
      // Noktalı satırda düğme adı yetmez, açık tuş gerekir.
      assertFalse(ButtonHints.isPrompt("Press square to reload."))
      assertTrue(ButtonHints.isPrompt("Press ✕ to continue."))
      // Altındaki satır küçük harfle sürüyorsa simgesiz kalıp ipucu değildir; açık tuşlu ipucu yine ipucudur.
      assertFalse(ButtonHints.isPrompt("Hold to aim", continues: true))
      assertTrue(ButtonHints.isPrompt("Hold L2 to aim", continues: true))
    }
    TestRun.test("ButtonHintsTest.hintRowsLeaveTextAndBox") {
      func obs(_ text: String, _ l: Int, _ t: Int, _ r: Int, _ b: Int) -> TextObservation {
        TextObservation(text: text, confidence: 0.9, left: l, top: t, right: r, bottom: b)
      }
      let subtitle = obs("Lucia: You! Cash on the counter right now!", 300, 100, 700, 130)
      // Vision ipucunu simgenin iki yanında iki parça okur; üstünde sayfa göstergesi.
      let frame = [subtitle, obs("● ○ ○", 480, 140, 520, 150), obs("Hold", 440, 160, 480, 185), obs("to aim", 520, 160, 580, 185)]
      assertEquals([subtitle], ButtonHints.dropHintRows(frame, english: true))
      // Yalnız ipucu: hiçbir şey kalmaz (kutu da yok).
      assertEquals([], ButtonHints.dropHintRows([obs("Hold L2 to aim", 420, 160, 600, 185)], english: true))
      // İngilizce değilse fiil kalıbına bakılmaz; harfsiz gösterge yine atılır.
      assertEquals(3, ButtonHints.dropHintRows(frame, english: false).count)
      // Kutu yalnız altyazıyı kapsar.
      let kept = ButtonHints.dropHintRows(frame, english: true)
      assertEquals(130, kept.map(\.bottom).max() ?? 0)
      // Sarılmış diyalog: "Hold to aim" satırı küçük harfle sürüyor, atılmaz.
      let wrapped = [obs("Hold to aim", 300, 100, 600, 130), obs("when I give the signal.", 300, 135, 650, 165)]
      assertEquals(2, ButtonHints.dropHintRows(wrapped, english: true).count)
    }
  }
}
