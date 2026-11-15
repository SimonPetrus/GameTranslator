// SPDX-License-Identifier: AGPL-3.0-only
// Core testlerinin giriş noktası (run.sh).
import Foundation

TextMatchTest.run()
OcrNoiseTest.run()
SubtitleStabilizerTest.run()
SubtitlePipelineTest.run()
ReadSchedulerTest.run()
GlossaryTest.run()
TurkishSuffixTest.run()
TermProtectionTest.run()
SpeakerPrefixTest.run()
TestRun.finish()
