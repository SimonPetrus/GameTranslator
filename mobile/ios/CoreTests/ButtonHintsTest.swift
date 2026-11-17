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
  }
}
