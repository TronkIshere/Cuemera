# Known Limitations & Upgrade Roadmap

All P0 and P1 items are resolved. What remains is grouped below by what it needs to move forward.

## 1. Needs physical-device testing

- **`CameraService.capture()`'s per-photo controller lifecycle needs a redesign decision.** It currently spins up a brand-new `ResolutionPreset.max` `CameraController` for every single photo (on top of the two already-running controllers), then disposes it. Latency is instrumented (`lastCaptureControllerSetupLatency`/`lastCaptureShutterLatency`/`lastCaptureControllerTeardownLatency`, logged via `debugPrint` on every capture) — pull real numbers from a device, then decide whether reusing an existing controller (trading off capture resolution) is worth it.
- **Measure the real wall-clock impact of `ReferenceImageAnalyzer.analyze()`'s concurrency.** Its five independent steps (pose, face, segmentation, decode, palette) now run via `Future.wait` instead of sequentially. Confirm on a physical device that this actually cuts latency — ML Kit's native platform-channel bindings may serialize these calls internally regardless of Dart-level concurrency, in which case the real-world win could be smaller than assumed.
- **Verify `_evaluateFaceRoll`'s left/right direction in `reference_comparison_engine.dart`.** The phrase direction is derived from ML Kit's documented `headEulerAngleZ` sign convention, gated behind a `_faceRollDirectionIsMirrored` flag (currently `false`). This hasn't been confirmed on a physical device — tilt your head to a known side and check which phrase fires; flip the flag if it's backward. Now that the `subject_profile.dart`/`tracking_engine.dart` fix means this evaluator actually runs in production, getting the direction right matters more than when it was previously dead code.

## 2. Needs a product decision

- **Wire `ErrorReportingService` to a real remote sink.** It currently only retains the last 200 reports in memory (`FlutterError.onError`, `PlatformDispatcher.instance.onError`, `runZonedGuarded`, and every previously-silent `catch` all route through it) — reports don't survive app restart and never leave the device. A `TODO(remote-sink)` marks the extension point; needs a service chosen (Firebase Crashlytics, Sentry, custom backend) and an account/API keys before this can be wired up.

## 3. Model-driven upgrade — the core "complete product" gap

**In progress — see `SIGNAL_DISABLE_AND_AI_INTEGRATION_PLAN.md` for current status.**
The direction below (on-device GenAI generating the coaching phrase, rule-based
`ComparisonMath` attribute/severity selection kept underneath, phrase bank
retained as the fallback) was chosen — the specific route settled on is
Gemma 3 270M via `flutter_gemma`, not the Gemini Nano/Foundation Models path
this section originally sketched. Phase 0 (decouple decision from phrase)
and Phase 1 (isolated model integration) are done; Phase 1's device smoke
test, Phase 2 (wire into the live path), and Phase 3 (measure and tune)
are still open — full detail in the plan doc rather than duplicated here.

Two items from this section remain untouched and still open:
- **Fold the unified expression classifier (`expression_classifier.dart`) into that same modeling effort**, rather than continuing to hand-tune its probability thresholds. (Currently gated off the live path entirely by Track 1's signal-disable flag, which further reduces urgency here for now.)
- **Scope a Quality Engine** — aesthetic scoring beyond `ComparisonMath`'s geometric comparison. No ready-made on-device model exists for this; the realistic path is a NIMA-style small CNN (MobileNet/Inception backbone) fine-tuned and exported to LiteRT. Needs a labeled dataset first — bootstrap from a public aesthetic-scoring dataset, then fine-tune on real app data — before any model work starts.