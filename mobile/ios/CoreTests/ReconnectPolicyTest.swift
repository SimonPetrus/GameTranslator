// SPDX-License-Identifier: AGPL-3.0-only
// Core/ReconnectPolicy.swift testleri.
import Foundation

enum ReconnectPolicyTest {
  static func run() {
    TestRun.test("ReconnectPolicyTest.delaysGrowAndCap") {
      var p = ReconnectPolicy()
      let delays = (0..<7).map { _ in p.nextDelay(at: 0) }
      assertEquals([2, 4, 8, 16, 30, 30, 30], delays)
    }
    TestRun.test("ReconnectPolicyTest.inUseWaitsAtLeastEightSeconds") {
      var p = ReconnectPolicy()
      assertEquals(8.0, p.nextDelay(.inUse, at: 0))   // 2 -> 8
      assertEquals(8.0, p.nextDelay(.inUse, at: 0))   // 4 -> 8
      assertEquals(8.0, p.nextDelay(.inUse, at: 0))   // 8
      assertEquals(16.0, p.nextDelay(.inUse, at: 0))  // 16
    }
    TestRun.test("ReconnectPolicyTest.stableStreamResetsCounter") {
      var p = ReconnectPolicy()
      _ = p.nextDelay(at: 0); _ = p.nextDelay(at: 0); _ = p.nextDelay(at: 0)
      p.streamStarted(at: 100)
      assertEquals(2.0, p.nextDelay(at: 161), "60 sn+ kararlı akıştan sonra başa dönmeli")
      assertEquals(4.0, p.nextDelay(at: 170))
    }
    TestRun.test("ReconnectPolicyTest.shortStreamKeepsCounter") {
      var p = ReconnectPolicy()
      _ = p.nextDelay(at: 0)  // 2
      _ = p.nextDelay(at: 0)  // 4
      p.streamStarted(at: 100)
      assertEquals(8.0, p.nextDelay(at: 150), "60 sn'den kısa akış sayacı sıfırlamamalı")
    }
    TestRun.test("ReconnectPolicyTest.manualResetStartsOver") {
      var p = ReconnectPolicy()
      for _ in 0..<4 { _ = p.nextDelay(at: 0) }
      p.reset()
      assertEquals(0, p.attempt)
      assertEquals(2.0, p.nextDelay(at: 0))
    }
  }
}
