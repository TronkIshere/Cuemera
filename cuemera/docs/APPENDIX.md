# Known Limitations & Upgrade Roadmap

All P0 and P1 items are resolved. What remains is grouped below by what it needs to move forward.

## 1. Needs physical-device testing

- **Measure the real wall-clock impact of `ReferenceImageAnalyzer.analyze()`'s concurrency.** Its five independent steps (pose, face, segmentation, decode, palette) now run via `Future.wait` instead of sequentially. Confirm on a physical device that this actually cuts latency — ML Kit's native platform-channel bindings may serialize these calls internally regardless of Dart-level concurrency, in which case the real-world win could be smaller than assumed.
- **Verify `_evaluateFaceRoll`'s left/right direction in `reference_comparison_engine.dart`.** The phrase direction is derived from ML Kit's documented `headEulerAngleZ` sign convention, gated behind a `_faceRollDirectionIsMirrored` flag (currently `false`). This hasn't been confirmed on a physical device — tilt your head to a known side and check which phrase fires; flip the flag if it's backward. Now that the `subject_profile.dart`/`tracking_engine.dart` fix means this evaluator actually runs in production, getting the direction right matters more than when it was previously dead code.

## 2. Needs test coverage / code audit

- **`reference_image_analyzer.dart`'s `analyze()` orchestration is still untested.** It constructs real `PoseDetector`/`FaceDetector`/`SelfieSegmenter` instances internally and calls their native `processImage()` directly — there's no seam to inject a fake, so exercising `analyze()` itself needs a physical device/platform channel, not a pure-Dart test. `face_analyzer_test.dart` now covers `face_analyzer.dart` fully (`Face`'s public constructor makes it directly testable), and `reference_image_analyzer_test.dart` covers the four pure pixel/mask helpers (`estimateNegativeSpace`/`estimateSymmetry`/`estimateBackgroundClutter`/`estimateBrightness`, made public + `@visibleForTesting` for exactly this purpose) — but the pose/face detection calls and the `bodyRatio`/`poseLandmarkPoints` landmark logic inside `_analyzePose`/`_analyzeFace` remain uncovered. If `analyze()` itself needs to be under test, it likely needs a constructor-injected detector seam first.

## 3. Needs a product decision

- **Wire `ErrorReportingService` to a real remote sink.** It currently only retains the last 200 reports in memory (`FlutterError.onError`, `PlatformDispatcher.instance.onError`, `runZonedGuarded`, and every previously-silent `catch` all route through it) — reports don't survive app restart and never leave the device. A `TODO(remote-sink)` marks the extension point; needs a service chosen (Firebase Crashlytics, Sentry, custom backend) and an account/API keys before this can be wired up.

## 4. Model-driven upgrade — the core "complete product" gap

**In progress.** The direction below (on-device GenAI generating the
coaching phrase, rule-based `ComparisonMath` attribute/severity selection
kept underneath, phrase bank retained as the fallback) was chosen — the
specific route settled on is Gemma 3 270M via `flutter_gemma`, not the
Gemini Nano/Foundation Models path this section originally sketched.

Decoupling the decision from the phrase text (`CoachingDecision`) and
wiring the model into the live coaching path (`voiceDirectorListenerProvider`,
with a 3-second timeout and fallback to `decision.fallbackPhrase` on
failure) are both code-complete. **None of it is active yet** — nothing
in the app calls `CoachingPhraseModelService.ensureInstalled()`, so
`phraseModel.isReady` is always `false` and every decision still
resolves to `decision.fallbackPhrase`, byte-for-byte identical to before
this work started. `voice_providers.dart` logs every generation attempt
via `debugPrint` (latency, attribute, success/fail — mirrors
`CameraService.capture()`'s existing instrumentation), but there's no
real data yet since nothing has triggered a real attempt.

**Model/bundling decisions already made:** `litert-community/gemma-3-270m-it`'s
`gemma3-270m-it-q8.task` mobile build (int8, ~304MB, gated on Hugging
Face), downloaded on-demand (`.fromNetwork`) rather than bundled in app
assets, token sourced via build-time `--dart-define=HF_TOKEN=...`. Files:
`coaching_decision.dart`, `coaching_phrase_model_service.dart`,
`coaching_phrase_model_providers.dart`,
`integration_test/coaching_phrase_model_smoke_test.dart`. `pubspec.yaml`
updated (`flutter_gemma`, `flutter_gemma_mediapipe`, `integration_test`,
`environment.sdk` bumped to `^3.12.0` — needs an actual `flutter upgrade`,
not just the pubspec edit).

**Open items, in the order they unblock each other:**
1. Run the smoke test on a physical device with network access and an
   HF token that's accepted the Gemma license:
   ```
   flutter test integration_test/coaching_phrase_model_smoke_test.dart \
     --dart-define=HF_TOKEN=<token> -d <device-id>
   ```
2. Decide where `ensureInstalled()` gets triggered from (a settings
   toggle, automatic on first reference-photo pick, etc.) and build it —
   this is what actually turns the model on.
3. Once both of the above are done and the app's been used for real:
   latency against the existing 80ms/frame throttle budget, a
   phrase-quality/naturalness pass, and whether `gemma-3-270m-it-q8` is
   the right size/quantization — all from real numbers, not assumption.

Two items from this section remain untouched and still open:
- **Fold the unified expression classifier (`expression_classifier.dart`) into that same modeling effort**, rather than continuing to hand-tune its probability thresholds. (Currently gated off the live path entirely by Track 1's signal-disable flag, which further reduces urgency here for now.)
- **Scope a Quality Engine** — aesthetic scoring beyond `ComparisonMath`'s geometric comparison. No ready-made on-device model exists for this; the realistic path is a NIMA-style small CNN (MobileNet/Inception backbone) fine-tuned and exported to LiteRT. Needs a labeled dataset first — bootstrap from a public aesthetic-scoring dataset, then fine-tune on real app data — before any model work starts.