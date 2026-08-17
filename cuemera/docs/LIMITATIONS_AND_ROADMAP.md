# Known Limitations & Upgrade Roadmap

**Status:** P0/P1 hygiene resolved. Track 2 (Gemma 3 270M coaching phrases) and the `sherpa_onnx` TTS path are both code-complete and confirmed working end-to-end on a real device. The architecture audit's 11-step migration plan is implemented through step 10 (step 11 intentionally deferred — see §5). Full session-by-session history lives in `README.md`. Everything below is either a code fix still awaiting device verification, or work not yet started.

## 1. Needs physical-device testing

- **Re-confirm the tenth-session fixes** (`_pickWorst` tie-break, circular-deviation, inverted tolerance sliders, AI-coaching timeout lockout, reference-photo likelihood gate — `README.md` §11): diagnosed from debug logs and applied by inspection, never run through a full live session.
- **`pose_analyzer.dart`'s likelihood gate** (eleventh session): confirm a real low-confidence live shoulder detection now correctly yields `null` instead of a bogus angle.
- **Device-verify the twelfth session's crop-redetect reconciliation rewrite** (`reference_photo_crop_redetect.dart`) and the corrected painter fix (`reference_picker_sheet.dart`) — reasoned through against real log evidence, not re-run since. Phase 2's trigger threshold (⅓ of tracked extremities untrusted) is still an untuned first guess.
- **Investigate possible non-determinism in `ReferenceImageAnalyzer.analyze()`** — same source photo, picked twice, once produced "no pose detected," once a partial skeleton. Not yet reproduced under controlled conditions; `kDebugMode` logging exists to help next time it happens.
- **`ModelLifecycleManager.ensureReady()`'s stall-based install timeout** (fifteenth session) — reasoned through against one real slow-but-successful download, never tested against a genuinely hung one.
- **AI-coaching-unavailable warning + Retry in `settings_screen.dart`** (thirteenth session): confirm it actually appears after a real 3-timeout streak, and that Retry actually restores AI phrases.
- **Re-confirm the front/back camera rotation fix** (`MlKitService.rotationFor()`) on a real device with the front camera; also test with the phone rotated, since device orientation now affects the computed rotation.
- **Test the Impeller-disable mitigation on more devices** — one device (model "7 ZS67") showed worse frame pacing with Impeller than Skia. Confirm the `AndroidManifest.xml` meta-data fix is actually applied, and whether it helps on other devices too.
- **`CameraService.capture()`'s merged single-controller redesign** — needs confirmation that continuous autofocus now behaves correctly (original symptom: visibly softer preview/capture + non-continuous AF on a device reporting `LIMITED` Camera2 hardware level), that the ML Kit overlay/coaching resumes after a capture, that `switchLens()` still works, and that `ResolutionPreset.high` doesn't slow ML Kit frame processing unacceptably.
- **Measure `ReferenceImageAnalyzer.analyze()`'s `Future.wait` concurrency** and **`MlKitService.processImage()`'s concurrent pose/face/segmentation calls** for real wall-clock latency wins — ML Kit's native platform-channel bindings may serialize these regardless of Dart-level concurrency either way.
- **Verify all four `*IsMirrored` direction flags** in `reference_comparison_engine.dart` (`_faceRollDirectionIsMirrored`, `_shoulderBalanceDirectionIsMirrored`, `_bodyYawDirectionIsMirrored`, `_faceYawDirectionIsMirrored`) — the single oldest open item in this doc. `camera_screen.dart`'s `mirror_check:` debug log exists to support this: compare raw signs between front/back camera for the same physical pose; a flag that flips sign needs to become a function of `lensDirection`.
- **Confirm a real subject can satisfy all `AutoCaptureService` gates within `minTrackingProgressForCapture`**, now against the fifteenth-session circular-deviation fixes plus the since-added `shoulderBalanceRatio`/`shoulderSpanRatio` scoring/gating (both still device-unverified).
- **Confirm `ReferenceComparisonEngine.evaluate()`'s tier selection** actually surfaces composition/lighting coaching in rotation (not just pose/face repeating), and that a torso-rotation-or-lean cluster gets voiced as one collapsed correction instead of four separate ones.
- **Confirm `light_analyzer.dart`'s mask-index scale fix** (ninth session) changes `backgroundClutterCount` sanely on-device; re-tune `DetectionThresholds.defaultBackgroundClutterThreshold` if auto-capture behaves differently than before.
- **Confirm the ninth-session provider/rebuild-scope changes** (`targetSubjectProfileProvider`, `currentScoreProvider`'s `Consumer` scoping) didn't silently change UI behavior.
- **New this session — device-test the auto-capture 3-shot session cap** (`capture_providers.dart`'s `autoCaptureCountProvider`/`maxAutoCaptureShots`). Goal is to also resolve the "Hold still. loops forever / coaching sentences feel cut off" symptom — a full pipeline review (TTS queue, camera capture) found no code that actually interrupts audio, so this cap is the best available theory, not a confirmed root cause.
- **New this session — device-test the "Accurate Detection" toggle** (`live_detection_settings_provider.dart` → `MlKitService.setAccurateMode()`): confirm switching `PoseDetectionModel`/`FaceDetectorMode` mid-session doesn't glitch tracking, and measure the real per-frame cost increase against `camera_screen.dart`'s 80ms `_throttleInterval` on a lower-end device.

## 2. Needs test coverage / code audit

- **`reference_image_analyzer.dart`'s `analyze()` orchestration is untested** — constructs real ML Kit detectors internally, no injection seam. `PoseLandmarkGate`/`sampleMaskTrust`/`_verifyLandmark` are pure functions and could be unit-tested independently of that seam question — not yet done.
- **No unit tests for `_evaluateShoulderBalance`/`_evaluateShoulderSpan`/`_evaluateBodyYaw`/`_evaluateFaceYaw`** — should mirror the existing `_evaluateShoulderAngle`/`_evaluateFaceRoll` coverage (null-skip case, threshold boundary, tier boundaries, direction on both sides).
- **`tracking_engine.dart`'s `trackingProgress()` and `auto_capture_service.dart` have no regression test** for the circular-deviation fixes — a wrap-boundary case (e.g. current=-178°, reference=170°) would be the highest-value addition, given this bug class has recurred 4-5 times across the project.

## 3. Needs a product decision

- **Gate debug logging behind `kDebugMode`** — `ai_gate:`/`coaching_phrase_generation:` (`voice_providers.dart`), `pick_worst:` (`reference_comparison_engine.dart`), and `LANDMARK_VERIFY`/the crop-redetect summary (`reference_photo_crop_redetect.dart`) are all still ungated. `camera_screen.dart`'s `mirror_check:`/`auto_capture_check:` loggers are correctly gated already — use as the reference pattern.
- **Wire `ErrorReportingService` to a real remote sink** — currently only retains the last 200 reports in memory; needs a service chosen (Crashlytics/Sentry/custom) and credentials.
- **`enableClassification: false` on the live `FaceDetectorOptions` contradicts older docs** that assumed it was enabled downstream of Track 1's flag. `eyesOpen`/`expression` are `null` for two independent reasons now (detector config + `FaceAnalyzer.enableEyeAndExpressionSignals = false`) — decide whether to re-enable classification or drop the now-redundant flag.
- **`CoachingPhraseModelService._buildPrompt()`'s length guard is a character count, not a real tokenizer count** — conservative but blunt; not device-confirmed to trigger correctly on an actually-over-budget prompt.
- **Type `voice_providers.dart`'s `emphasisFor(severityBand)` parameter properly** instead of leaving it untyped — was written before `coaching_decision.dart`'s real enum was available to confirm against.
- **`pubspec.yaml`'s `environment.sdk: ^3.8.1` doesn't match the `^3.12.0`** the Toolchain section elsewhere says was bumped to for Track 2 — resolve which is actually true on the dev machine.
- **Fold the expression classifier (`expression_classifier.dart`) into the eventual model-driven effort**, instead of hand-tuning its probability thresholds (currently gated off entirely by Track 1's signal-disable flag).
- **Scope a Quality Engine** (aesthetic scoring beyond `ComparisonMath`'s geometric comparison) — needs a labeled dataset before any model work starts; realistic path is a NIMA-style small CNN fine-tuned and exported to LiteRT.

## 4. Model-driven upgrade — the core "complete product" gap

Track 2 is code-complete and device-confirmed running end-to-end (`README.md` §16). Remaining, in order:

1. **Capture a full Phase 3 latency dataset** — only 1 of 5 sample decisions' latency was ever logged (`hue`/strong: 2200ms). Need all 5, plus real-shoot usage, to judge whether `gemma-3-270m-it-q8`'s size/quantization and phrasing are actually right.
2. **Document the Hugging Face gated-model access gotcha** in onboarding docs — a valid `HF_TOKEN` alone isn't enough; the account must separately accept the Gemma license on huggingface.co, or every download 401s. Also note: a ~304MB download over HF's Xet CDN can appear to stall for a long stretch while still genuinely downloading.
3. Once (1)–(2) are done and the app's seen real use: judge phrase-quality/naturalness, and revisit the ~304MB download size vs. a smaller quantization if one becomes available.

## 5. Audit migration — what's still open

Steps 1–10 of the architecture audit's 11-step plan are implemented; step 11 (flip the v2 coaching flag, delete the old listener) is intentionally not attempted — both gaps that used to block it (LLM validation, eligibility-context stubs) are closed, but it's correctly sequenced behind real device soak time, which no session has done yet.

- **LLM output validation** (`llm_output_validator.dart`) is wired on both listeners, but only the pass-through path (a valid phrase, spoken) has real device evidence — never confirmed that a real generated phrase has actually failed validation and correctly fallen back.
- **`voiceDirectorListenerV2Provider`'s `EligibilityContext` is real but presence-level, not geometric-level** — `subjectFullyInFrame`/`detectorsAgree` check raw per-frame detector presence, not true geometric framing/agreement (the mask signal is deliberately never sampled on the live path, for per-frame cost). **Still correctly recommend not enabling "Coaching v2 (experimental)" for real users** until real device soak time exists.
- **No tests for any of the audit migration work** — explicit, repeated choice across multiple sessions, not an oversight. `reference_comparison_engine_test.dart` needs updating for `confidence`/`controllability`, root-cause collapsing, and `_evaluateFaceYaw`.
- **Step 11 intentionally still not attempted** — see above.