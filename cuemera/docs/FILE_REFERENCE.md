# File & Function Reference

Organized by folder, in dependency order (leaf constants first). "Notes" only called out where non-trivial; purely presentational files with no logic get a short entry. **A fourth session found and fixed a severe correctness bug spanning two files: `SubjectProfile.copyWith` silently swallowed explicit nulls (so callers intending to clear a stale value never actually did), and `TrackingEngine.smoothSubject` separately dropped 4 of 9 `SubjectProfile` fields entirely when rebuilding its output. Combined, this meant `ReferenceComparisonEngine`'s face-pitch, face-roll, mouth-open, and eye-open coaching evaluators never fired in production — see `LIMITATIONS_AND_ROADMAP.md` for the full account.** Entries below reflect current state; superseded notes from earlier sessions have been removed rather than kept as history.

## core/constants

#### `app_colors.dart`
`AppColors extends ThemeExtension<AppColors>` — 8-color palette (`background, surface, text, textMuted, accent, targetZone, success, warning`), `dark`/`light` static instances, standard `copyWith`/`lerp`. Clean, no issues. `targetZone` is used by `TargetZoneOverlay`; `warning` is now also used by the ML Kit unavailability banner in `camera_screen.dart`.

#### `app_spacing.dart`
Static `double` scale (`xs`4 … `xxl`48). No logic, no issues.

#### `app_strings.dart`
10 static string constants, all with real call sites. No changes this session.

#### `app_typography.dart`
`AppTypography` — private `TextStyle` constants + color-aware accessors (`heading1/2, body, bodyMuted, caption, score`) + `buildTextTheme`. Unchanged.

#### ~~`debug_flags.dart`~~
**Deleted.** `kDebugPerfOverlay` was never read anywhere; `camera_screen.dart` gates its debug overlay on Flutter's own `kDebugMode` instead.

## core/di

#### ~~`service_locator.dart`~~
**Deleted.** `get_it` is no longer a dependency. The Riverpod providers are now the only DI path in the app.

## core/services

#### `camera_service.dart`
`CameraService` — wraps the `camera` plugin. Two separate `CameraController`s are maintained: `_controller` (medium-res, live ML-analysis stream) and `_previewController` (high-res, on-screen preview). `capture()` stops the live stream, spins up a **third**, temporary `ResolutionPreset.max` controller just for the single photo, then disposes it — this per-capture controller lifecycle is unchanged architecturally, but now **instrumented**: `lastCaptureControllerSetupLatency`/`lastCaptureShutterLatency`/`lastCaptureControllerTeardownLatency` (each a `Duration?`) are measured via `Stopwatch` and logged via `debugPrint` on every capture, giving real numbers before any decision to redesign it. Gallery-save outcome is now tracked via `lastGallerySaveSucceeded` (`bool?` — `null` before any capture, `false` on denied permission or a thrown `Gal` exception, which is also reported through `ErrorReportingService`) instead of being silently discarded. `switchLens()`, `startImageStream`/`stopImageStream`, `dispose()` unchanged.

#### `memory_service.dart`
`MemoryService` — thin wrapper over two Hive `Box`es (`shooting_habits`, `album_state`) with generic get/set. `memoryServiceProvider` is a `FutureProvider<MemoryService>` that awaits `init()` before resolving. Unchanged this session; schema versioning for the data it stores lives in the consumer (`album_providers.dart`), not in this generic service.

#### `ml_kit_service.dart`
`MlKitService` — owns the live-frame `PoseDetector`, `FaceDetector`, `SelfieSegmenter`, converts a `CameraImage` to ML Kit's `InputImage`, runs all three detectors sequentially per frame behind a `_busy` guard, broadcasting `MlKitAnalysisResult` on `analysisStream`. The live `FaceDetectorOptions` has `enableClassification: true`. **New this session:** `processImage` now wraps the three detector calls in a `try`/`catch` — a failure is reported via `ErrorReportingService` and counted; after 5 consecutive failures (`_maxConsecutiveFailuresBeforeFlagging`, typically a failed on-device model download/initialization) the service emits `true` on the new `unavailableStream`, and emits `false` again the next time a frame succeeds. Previously an exception here had no app-level fallback at all — see `scene_providers.dart`/`camera_screen.dart` for how the UI now surfaces this.

#### `theme_preference_service.dart`
`ThemePreferenceService extends StateNotifier<ThemeMode>` — persists dark/light via `shared_preferences`. Unchanged.

#### `tracking_engine.dart`
`TrackingEngine` — constructed with a `DetectionThresholds thresholds` (default `DetectionThresholds.defaultValues`). **Bug found and fixed in an earlier session:** `smoothSubject` rebuilt `SubjectProfile` via its plain constructor and only forwarded 5 of 9 fields (`bodyRatio`, `faceAngleDegrees`, `shoulderAngleDegrees`, `eyesOpen`, `expression`) — `faceAngleXDegrees`, `faceAngleZDegrees`, `mouthOpenRatio`, and `eyeOpenRatio` were always `null` on the published `subjectProfileProvider` state regardless of what `PoseAnalyzer`/`FaceAnalyzer` had just computed. Fixed by adding EMA smoothing + missing-streak debounce for all 4 previously-dropped fields, following the exact pattern already used for the other 5. `smoothScene` unchanged. **Confirmed, not changed, this session (Signal Disable Track 1):** `trackingProgress()` already guards both `eyesOpen` and `expression` on *both sides non-null* before adding them to the weighted average (see `evaluate — trackingProgress` group in the test file) — so now that `face_analyzer.dart` makes both permanently `null`, they cleanly drop out of the average instead of counting as an always-failing match. No code change was needed here; a test was added instead to lock in that this already-safe behavior covers the new permanent case, not just a transient one.

#### `tts_service.dart`
`TtsService` — wraps `flutter_tts`; `speak()` guards on `_ready` (set by `init()`) so calls before initialization silently no-op rather than throwing. **Bug found and fixed this session:** `init()` was never called anywhere in the codebase — `ttsServiceProvider` only constructed `TtsService()` and returned it, so `_ready` stayed `false` forever and every `speak()` call was silently dropped. This was the root cause of "no voice coaching at all." Fixed by calling `service.init()` (fire-and-forget) inside `ttsServiceProvider`.

#### `expression_classifier.dart`
`classifyExpression({smilingProbability, leftEyeOpenProbability, rightEyeOpenProbability}) → String?` — the single shared expression classifier used by both `face_analyzer.dart` and `reference_image_analyzer.dart`. Unchanged — per the Signal Disable plan's non-goals, this file is gated off from the live path by `face_analyzer.dart`'s flag, not edited or deleted.

#### `error_reporting_service.dart` *(new)*
`ErrorReportingService` (singleton via `ErrorReportingService.instance`) — centralized error/crash capture. `report(error, stackTrace, {context})` records an `ErrorReport` (capped at the 200 most recent, in memory only) and `debugPrint`s it; `reportFlutterError(FlutterErrorDetails)` adapts framework errors to the same call. Wired from `main.dart` (`FlutterError.onError`, `PlatformDispatcher.instance.onError`, `runZonedGuarded`) and called directly from every previously-silent `catch` in `reference_image_analyzer.dart`, `album_providers.dart`, `camera_service.dart` (gallery save), and `ml_kit_service.dart` (per-frame processing failures). **Local-only** — a `TODO(remote-sink)` marks the intended extension point for a real service (Crashlytics/Sentry/custom backend) once one is chosen; reports do not currently survive app restart or leave the device.

## core/theme

#### `app_theme.dart`
`AppTheme.darkTheme`/`lightTheme` build a Material 3 `ThemeData` from `AppColors`. Unchanged.

## features/album

#### `album_providers.dart`
`AlbumNotifier extends StateNotifier<AlbumState>` — takes a `Ref`; on construction, asynchronously restores shots from `MemoryService`. **New this session — schema versioning:** a `schemaVersion` key (stored alongside `'shots'` in the album Hive box) is read on restore; if it's below `_currentShotsSchemaVersion` (currently `2`, bumped when `referenceImagePath`/`toleranceSettings` were added to `Shot`), `_migrateShots()` runs and the version is rewritten, giving future schema changes a documented, single place to add a migration step instead of relying on `Shot.fromMap`'s null-safe defaults alone. `_persist()` always writes the current schema version alongside the data. All three previously-silent `catch` blocks (restore, persist, shot-file delete) now report through `ErrorReportingService` instead of swallowing silently.

#### `album_state.dart`
`AlbumState` — immutable list of `Shot` + public `shotTypes`. `diversityScore()`/`suggestNextShotType()` unchanged this session. Now covered by `test/album/domain/album_state_test.dart`.

#### `shot.dart`
`Shot` — immutable record. **New this session:** two additional optional fields, `referenceImagePath` (the reference photo's path at capture time) and `toleranceSettings` (the `ToleranceSettings` in effect at capture time), so a saved shot can be re-explained or re-scored later — closing the gap flagged in earlier Limitations notes. `toMap()`/`fromMap()` updated to round-trip both (via `ToleranceSettings.toMap()`/`fromMap()`); both are nullable so shots persisted before this change still deserialize fine with `null` for the new fields.

#### `album_screen.dart`
`AlbumScreen` + `ShotDetailScreen` + `_confirmDeleteDialog`. Unchanged this session.

## features/camera_session

#### `camera_screen.dart`
The largest file in the app; hosts the live camera session. Updated this session:
- `_performCapture()`: after `cameraService.capture()`, checks `cameraService.lastGallerySaveSucceeded == false` and sets `gallerySaveWarningProvider` if the gallery save failed (mirroring the same check added to `capture_providers.dart`'s auto-capture path).
- `build()`: watches `mlKitAvailabilityListenerProvider` and reads `mlKitUnavailableProvider`; when `true`, a persistent banner is shown at the top of the `Stack`. `ref.listen`s `gallerySaveWarningProvider` and shows a one-shot `SnackBar`, deferred via `WidgetsBinding.instance.addPostFrameCallback` — calling `ScaffoldMessenger`/resetting provider state synchronously inside this listener caused a `markNeedsBuild`-during-build crash when it fired in the same flush cycle as the pre-existing `capturedShotProvider` listener's `setState()`; deferring to a post-frame callback fixed it.
- **`TargetZoneOverlay` removed from the `Stack`** at the user's explicit request — it was read as implying the subject had to physically fit inside the drawn rectangle, when in fact the underlying comparison (`ComparisonMath`/`trackingProgress`) always used the full frame's landmark/scene data regardless of the box. Purely a UI removal; `trackingProgress` and the unused import were removed along with it. `TargetZoneOverlay` itself (`shared/widgets/target_zone_overlay.dart`) is unchanged and dead again, same as before it was wired in.
- **Bug found and fixed — wrong rotation on the front camera:** `_onFrame`'s `InputImageRotation` for ML Kit was computed from `sensorOrientation` alone, using the same formula for front and back cameras. Front-facing sensors are mounted mirrored relative to back-facing ones and need a different compensation formula (`(360 - sensorOrientation) % 360` instead of `sensorOrientation` directly, per ML Kit's official guidance) — without it, live pose/face landmarks were computed in the wrong orientation specifically on the front (selfie) camera. This was the root cause of shoulder-angle coaching (and by extension `trackingProgress`/auto-capture) appearing persistently wrong even when correctly posed, on front camera only — the reference-photo pipeline (a static file, no camera/rotation involved) was never affected, matching the reported symptom.

#### ~~`album_button.dart`~~
**Deleted** (prior session — never instantiated).

#### `camera_preview_layer.dart`
Unchanged.

#### `camera_top_nav_bar.dart`
Unchanged.

#### `debug_perf_overlay.dart`
`DebugPerfOverlay` — FPS counter + `AutoCaptureService.debugConditionBreakdown()` dump, reading `detectionThresholdsProvider`. Unchanged this session.

#### `focus_ring.dart`, `phrase_chip.dart`
Presentational, unchanged.

#### `shot_builder.dart`
`buildShotFromCapture(...)` — **updated this session** to pass `referenceImagePath: reference.imagePath` and `toleranceSettings: tolerance` into the `Shot` it builds, populating the two new `Shot` fields. `reference`/`tolerance` were already parameters here — this data simply wasn't being stored before.

#### `capture_providers.dart`
`selectedShotTypeProvider` unchanged. **New this session:** `gallerySaveWarningProvider` (`StateProvider<String?>`) and the public `gallerySaveFailedMessage` constant — set by `autoCaptureProvider` (and by `camera_screen._performCapture` for the manual path) whenever `cameraService.lastGallerySaveSucceeded == false`; `camera_screen.dart` listens to it and shows a snackbar. `shouldCaptureProvider`/`autoCaptureProvider` otherwise unchanged from the prior session (thresholds-aware `shouldCapture`, stream-resume after capture).

#### `auto_capture_service.dart`
`AutoCaptureService.shouldCapture(...)` — **Signal Disable Track 1.** Removed the `subject.eyesOpen != true` hard gate: once `eyesOpen` went permanently `null` (see `face_analyzer.dart`), this gate would have silently blocked every capture forever. `debugConditionBreakdown()`'s `'eyesOpen'` key was dropped to match — it's no longer part of the decision, so reporting it (either value) would be misleading debug output. Every other gate (shoulder/face angle, pitch, roll, background clutter, brightness, tracking progress, cooldown) unchanged. Covered by `test/capture/services/auto_capture_service_test.dart`, including a test that specifically demonstrates the reference-aware background gate rejecting a case the old fixed `<=5` literal would have allowed, and (this session) a rewritten case confirming `eyesOpen` has no effect on the outcome either way, replacing the old `'fails when eyes are not open'` test that asserted the now-removed gate.

## features/editorial_score

#### `score_calculator.dart`
`calculateReferenceScore(...) → EditorialScore` — **the P0 story-score fix** (earlier session): `story` no longer reads a flat constant; `_storyScore(scene)` returns `(depthEstimate.clamp(0.0, 1.0) * 100).round()` when populated, falling back to a neutral `50` when `null`. **Signal Disable Track 1, this session:** `_expressionScore` had a tested fallback for the *reference* having no expression, but no explicit handling for the *subject* having no expression while the reference does — which becomes the permanent case now that `face_analyzer.dart` always produces `null`. Without a fix, `subject.expression == referenceValue` would silently evaluate to `false` on every single frame (`null` never equals a string), scoring it as a maximal, unintentional mismatch. Added an explicit early return of the same neutral `60` used for the "no signal at all" case, with a comment explaining why. Covered by a new test in `test/editorial_score/domain/score_calculator_test.dart` asserting the value `60` directly, not just "doesn't crash."

#### `score_providers.dart`
Unchanged.

## features/home

#### `home_screen.dart`, `home_menu_card.dart`
Unchanged this session.

## features/reference_photo

#### `comparison_math.dart`
Unchanged. Now covered by `test/reference_photo/domain/comparison_math_test.dart`.

#### `reference_profile.dart`
Unchanged.

#### `tolerance_settings.dart`
`ToleranceSettings` — 4 `double` sliders, `defaultBalanced`, `copyWith`. **New this session:** `toMap()`/`fromMap()`, so a `Shot`'s `toleranceSettings` field can round-trip through Hive.

#### `detection_thresholds.dart`, `detection_thresholds_provider.dart`
Unchanged.

#### `reference_providers.dart`
Unchanged.

#### `reference_image_analyzer.dart`
`ReferenceImageAnalyzer.analyze(imagePath) → ReferenceProfile` — **two fixes this session:** (1) `bodyRatio` now requires `nose`/`leftHip`/`leftAnkle` to each pass the same `_minLandmarkLikelihood` confidence filter already applied to `poseLandmarkPoints`, instead of using raw landmark positions; a half-body reference photo with an out-of-frame ankle now yields `bodyRatio: null` instead of a silently-wrong ratio. (2) The five independent analysis steps (pose detection, face detection, segmentation, image decode, palette generation) — previously sequential despite no step depending on another's result — now run concurrently via a single `Future.wait`, refactored into five private methods (`_analyzePose`, `_analyzeFace`, `_runSegmentation`, `_decodeImageFile`, `_analyzePalette`) each returning a small result class; mask-dependent scores (`negativeSpaceScore`, `symmetryScore`, `backgroundClutterCount`) still compute after the wait since they need both `mask` and `decoded`. The five `catch` blocks still report through `ErrorReportingService.instance.report(e, st, context: ...)` as before.

## features/scene_analysis

#### `scene_providers.dart`
`subjectProfileProvider`, `sceneProfileProvider`, `onFrameCallbackProvider`, `trackingEngineProvider`, `targetSceneProfileProvider`, `trackingProgressProvider`, `sceneAnalysisListenerProvider`, `mlKitUnavailableProvider`, `mlKitAvailabilityListenerProvider` unchanged this session. **Bug found and fixed:** `targetSubjectProfileProvider`'s no-reference-loaded fallback set `bodyRatio: current.bodyRatio` — the live subject's own current body ratio was used as its own tracking target, guaranteeing a permanent zero-deviation reading on that attribute by construction, unlike every other field in that fallback which used a neutral default. Fixed to `bodyRatio: null`, consistent with how a missing signal is treated everywhere else in the comparison layer.

#### `face_analyzer.dart`
`FaceAnalyzer.analyzeFace(...)` — **Signal Disable Track 1.** `eyesOpen` (bool gate) and `expression` (classified label) were flipping constantly frame-to-frame with no hysteresis against ML Kit's raw probability noise. Added `static const bool enableEyeAndExpressionSignals = false`, checked once right before the two values are written to the returned `SubjectProfile` — both are now permanently `null` while the flag is off. `classifyExpression` is still called internally (not deleted), so flipping the flag back to `true` is a one-line revert, not a restore from git history. `faceAngleXDegrees`/`faceAngleZDegrees`/`mouthOpenRatio`/`eyeOpenRatio` are completely unaffected. Now covered by `test/scene_analysis/services/face_analyzer_test.dart`'s updated `eyesOpen`/`expression` groups, which assert `null` even when the underlying probabilities would clearly indicate open/closed or a smile — confirming the flag actually suppresses the value in both directions, not just coincidentally.

#### `light_analyzer.dart`
`LightAnalyzer.analyzeLight(...)` — **updated this session**: `_atan`/`_atan2` (the hand-rolled 7th-order Taylor-series approximation with no domain reduction) have been removed. `_atan2Degrees` now calls `dart:math`'s `atan2` directly, matching the pattern `pose_analyzer.dart` already used. No other behavior change — same call sites (`_estimateLightDirection`, `_estimateColorTone`), same signature. The `planes[1]=U, planes[2]=V` assumption in `_estimateColorTone` remains unverified (needs physical-device testing, out of scope for a code-only session).

#### `pose_analyzer.dart`
Unchanged.

#### `scene_profile.dart`
Unchanged.

#### `subject_profile.dart`
`SubjectProfile` — immutable, 9 nullable fields + `timestamp`. **Bug found and fixed this session:** `copyWith` used `value ?? this.value` for every parameter, so a caller passing an explicit `null` to clear a stale field (`face_analyzer.dart` on no-face-detected, `pose_analyzer.dart` on low-confidence landmarks) had that `null` silently discarded — the field kept its last non-null value indefinitely. Fixed with a sentinel-object default (`static const Object _unset`) per parameter and an `identical(param, _unset)` check, so an explicit `null` is now distinguishable from an omitted argument and actually clears the field. Call sites are source-compatible; no signature changes needed at `pose_analyzer.dart`/`face_analyzer.dart`.

## features/settings

#### `settings_screen.dart`
Unchanged.

## features/splash

#### `splash_screen.dart`
Unchanged this session (mic permission drop, `get_it` removal, `HomeScreen` routing, and awaiting `memoryServiceProvider.future` were all done in the prior session).

## features/voice_director

#### `priority_engine.dart`
`PriorityAction` — **AI Integration Track 2, Phase 0.** Gained a required `decision` field (`CoachingDecision`, from the new `models/coaching_decision.dart`) alongside the existing `phrase`/`severity`/`sourceLayer`. Decouples the coaching decision from the phrase text so a future phrase-generation step (Phase 2) can vary the spoken wording without needing a new action shape.

#### `reference_comparison_engine.dart`
`ReferenceComparisonEngine.evaluate(...)` — substantially rebuilt in an earlier session: 3-tier priority fallthrough (Pose & Face → Composition → Lighting/Color), severity-tiered phrases via `_tieredPhrase`, new directional evaluators (`_evaluateFaceRoll` left/right gated behind `_faceRollDirectionIsMirrored`; `_evaluateMouthOpen`/`_evaluateEyeOpen` gained direction), `_evaluateExpression` naming the actual target label. `_evaluateBodyRatio`/`_evaluateSymmetry`/`_evaluateHue` remain single-direction by design. Every `_evaluate*` method also builds a `CoachingDecision` (`attribute`/`direction`/`tier`/`normalizedSeverity`/`fallbackPhrase`/`targetExpression`) alongside the phrase — zero behavior change, byte-for-byte identical phrase output. `_AttributeEvaluation` no longer stores `severity`/`phrase` directly; both are getters derived from `decision`. The severity-band ceilings (`_mildSeverityCeiling`/`_moderateSeverityCeiling`) are aliases of the single source of truth on `CoachingDecision` itself. Direction mapping: `bodyRatio`/`symmetry`/`hue` → `CoachingDirection.none`; `faceRoll` → `left`/`right`; `expression` → `none` with `targetExpression` set; everything else → `increase`/`decrease`. Covered by `reference_comparison_engine_test.dart`'s `CoachingDecision fields` group plus the original phrase-based tests (unchanged, still pass).

**Import-path incident:** this file was once re-uploaded still on its pre-`CoachingDecision` version (no import of `models/coaching_decision.dart`, no `decision` field anywhere) while `priority_engine.dart` had already moved to requiring `decision` as a parameter — caused a "required named parameter" compile error. Fixed by re-applying the `CoachingDecision` wiring to that exact uploaded file, preserving its actual phrase wording verbatim (it had drifted slightly from earlier notes in this doc — e.g. the `bodyRatio` "strong" phrase). Worth a diff against git history if anything here looks unexpectedly out of sync again.

#### `voice_providers.dart`
`voiceDirectorListenerProvider` — Dedupe keyed on `next.decision.dedupeKey`/`lastDedupeKey` (Phase 0). **Phase 2 wiring:** calls `CoachingPhraseModelService.generate(action.decision)` (3s timeout) per debounced decision, falling back to `decision.fallbackPhrase` on timeout/`null`/not-ready/thrown. `coachingAiUnavailableProvider` (mirrors `mlKitUnavailableProvider`) trips after 3 consecutive failures, skipping generation for the rest of the session. `generationEpoch` drops a stale generation result if a newer decision is committed while an older one's `generate()` call is still in flight. **Phase 3 instrumentation:** every attempt is logged via `debugPrint` (latency, attribute, success/fail — mirrors `CameraService.capture()`'s existing pattern), plus module-level `lastPhraseGenerationLatencyMs`/`lastPhraseGenerationSucceeded` for a future debug UI. **Currently inert in practice:** nothing in the app calls `ensureInstalled()` yet, so `phraseModel.isReady` is always `false` and every decision still resolves to `decision.fallbackPhrase` — identical to pre-Phase-2 behavior. No UI banner built for `coachingAiUnavailableProvider`. `nextActionProvider`/`referenceComparisonEngineProvider` unchanged.

## features/voice_director/models

#### `coaching_decision.dart` *(new)*
`CoachingDecision` — lives at `features/voice_director/models/coaching_decision.dart` (no `domain/` in the path — a mismatched assumption about this caused a real compile error once already, see the callout in `reference_comparison_engine.dart`'s entry below; check for the same mistake if any other file imports `domain/models/coaching_decision.dart`). Immutable model: `attribute` (`CoachingAttribute` enum, one per `_evaluate*` method), `direction` (`CoachingDirection`: `increase`/`decrease`/`left`/`right`/`none`), `tier` (`CoachingTier`: `poseAndFace`/`composition`/`lighting`), `normalizedSeverity` (double), `fallbackPhrase` (the hand-authored string — used verbatim now, and again whenever model generation fails/is slow/is unavailable), and nullable `targetExpression` (only set for the `expression` attribute). Exposes `severityBand` (mild/moderate/strong, via the ceiling constants that live here as the single source of truth) and `dedupeKey` (identity for de-duplicating repeated coaching prompts).

## features/voice_director/services

#### `coaching_phrase_model_service.dart` *(new)*
`CoachingPhraseModelService` — wraps Gemma 3 270M via `flutter_gemma`/`flutter_gemma_mediapipe` (the `gemma3-270m-it-q8.task` mobile build, `litert-community/gemma-3-270m-it` on Hugging Face — gated, needs a token). `ensureInstalled({onProgress})` downloads on first use (flutter_gemma caches after) and registers `MediaPipeEngine` via a guarded one-time `FlutterGemma.initialize(...)` call; throws the plugin's typed `DownloadException` on failure (401/403/etc.). `generate(CoachingDecision) → Future<String?>` builds a short-phrase prompt from the decision's fields and **never throws** — any failure or not-yet-installed state returns `null`. **Deliberately isolated from the live coaching path** at the time it was written — Phase 2 has since wired it into `voiceDirectorListenerProvider` with fallback behavior (see that entry). Import corrected to `../models/coaching_decision.dart` (was briefly `../domain/models/...`, wrong path).

## features/voice_director/providers

#### `coaching_phrase_model_providers.dart` *(new)*
`coachingPhraseModelServiceProvider` — sources the Hugging Face token via build-time `--dart-define=HF_TOKEN=...` (simplest of the options considered; swappable for a backend-fetched token or self-hosted mirror later without touching anything else). Consumed by `voice_providers.dart`'s Phase 2 wiring.

## features/capture/presentation/widgets

#### `shot_type_picker_sheet.dart`
Unchanged this session.

## features/reference_photo/presentation/widgets

#### `reference_picker_sheet.dart`
`ReferenceAnalysisPainter` — **bug found and fixed this session**: when a reference photo was framed to cut off before the knee/wrist (e.g. a half-body shot), ML Kit's pose detector sometimes still reported a landmark there with enough confidence to pass `ReferenceImageAnalyzer`'s filter, but at a wildly extrapolated position (the joint isn't actually visible), drawing an implausible skeleton line. Fixed with `_findSuspectExtremities`/`_torsoScale`: any skeleton segment longer than 4x the shoulder/hip-width reference scale has its extremity endpoint (wrist/ankle) hidden entirely instead of drawn. Presentational-only fix — doesn't touch `reference_image_analyzer.dart`'s scoring pipeline. **Related but not fixed:** `bodyRatio` in `reference_image_analyzer.dart` computes directly from raw `nose`/`leftHip`/`leftAnkle` landmarks, bypassing this same confidence filter — the same bad-ankle-position issue could still be silently skewing `bodyRatio` (and therefore scoring/tracking) for partial-body reference photos, not just this preview. Flagged, not addressed, since the reported symptom was scoped to the preview only.

#### `adjustments_sheet.dart`
Unchanged this session.

## shared/widgets

#### `app_background.dart`, `primary_button.dart`, `score_badge.dart`
Unchanged.

#### `target_zone_overlay.dart`
`TargetZoneOverlay` — animated, theme-aware alignment-box overlay with corner brackets. **Unmounted again this session**: removed from `camera_screen.dart`'s `Stack` at the user's request (it visually implied the subject had to fit inside the drawn box, which was never actually true of the underlying comparison logic). The widget itself is unchanged and once again dead code, same status as before it was originally wired in.

## Root

#### `pubspec.yaml`
**AI Integration Track 2, Phase 1, updated this session.** Added `flutter_gemma: ^1.5.2` and `flutter_gemma_mediapipe: ^1.0.0` (the `.task`/MediaPipe engine — flutter_gemma's core package registers no engine by itself as of its 1.0 modular restructuring, so this is required, not optional) and `integration_test` under `dev_dependencies` (needed to run `coaching_phrase_model_smoke_test.dart`). **Bumped `environment.sdk` from `^3.8.1` to `^3.12.0`** — `flutter_gemma >=1.0.0` requires Dart `>=3.12.0` (ships with Flutter 3.44+); this needs an actual `flutter upgrade`, not just the pubspec edit. `hive`/`hive_flutter` (unmaintained — `hive_flutter`'s last release predates this by years) are the one existing dependency worth watching after this bump; not confirmed broken, but `hive_ce` is the community-maintained successor if a conflict surfaces.

#### `main.dart`
**Updated this session:** `main()` now wires `FlutterError.onError` to `ErrorReportingService.instance.reportFlutterError`, sets `PlatformDispatcher.instance.onError` to report platform-level errors, and wraps `WidgetsFlutterBinding.ensureInitialized()`/`runApp(...)` in `runZonedGuarded` to catch uncaught async errors — all three previously had no handler at all. `MyApp` unchanged.

## test/

Originally 5 files covering the pure-Dart logic layer; now 7, all passing (150 tests as of this session's `flutter test` run):
- `test/reference_photo/domain/comparison_math_test.dart` — unchanged.
- `test/editorial_score/domain/score_calculator_test.dart` — story-score P0 fix, persistence round-trip, plus (this session) the subject-side-missing-expression fallback case for Signal Disable Track 1.
- `test/core/services/tracking_engine_test.dart` — EMA/debounce smoothing, `trackingProgress`, plus (this session) a case confirming `trackingProgress` isn't suppressed when `eyesOpen`/`expression` are permanently `null` on both sides.
- `test/album/domain/album_state_test.dart` — unchanged.
- `test/capture/services/auto_capture_service_test.dart` — gate chain, cooldown, reference-aware background-clutter gate, plus (this session) the `eyesOpen`-has-no-effect case replacing the removed hard-gate test.
- `test/scene_analysis/services/face_analyzer_test.dart` *(added a prior session, updated this session)* — full coverage of `face_analyzer.dart`; `eyesOpen`/`expression` groups updated this session to assert `null` under the disabled-signal flag.
- `test/voice_director/domain/reference_comparison_engine_test.dart` *(added this session)* — previously had zero coverage; now covers the 3-tier priority logic, severity tiering, all 13 `_evaluate*` methods' phrase output, and (Track 2 Phase 0) a new `CoachingDecision fields` group asserting `attribute`/`direction`/`tier`/`severityBand`/`targetExpression`/`dedupeKey` directly.

Not covered: `reference_image_analyzer.dart`'s `analyze()` orchestration (needs a physical device/platform channel — no fake-able seam for its internal `PoseDetector`/`FaceDetector`/`SelfieSegmenter` construction) and `expression_classifier.dart` (currently gated off the live path entirely, see `face_analyzer.dart`). `coaching_phrase_model_service.dart` (Track 2 Phase 1) similarly can't be a pure-Dart unit test — see `integration_test/coaching_phrase_model_smoke_test.dart` below.

## integration_test/ *(new)*

#### `coaching_phrase_model_smoke_test.dart` *(new)*
**AI Integration Track 2, Phase 1, added this session — not yet run.** Must live at the top-level `integration_test/` directory (sibling of `lib/`/`test/`) — it was initially placed at `test/integration_test/...` instead, which the `integration_test` plugin doesn't detect (runs as a plain widget test with no real device/platform channel, silently invalidating the result); moved. Run via `flutter test integration_test/coaching_phrase_model_smoke_test.dart --dart-define=HF_TOKEN=... -d <device-id>` — the `-d` device target is required too, or it still runs in the host harness. Drives real native Gemma 3 270M inference through `CoachingPhraseModelService`; needs network access and a Hugging Face token with the Gemma license accepted. Installs the model, then generates a phrase for 5 hand-picked `CoachingDecision`s spanning different attributes/directions/severity bands, printing each phrase plus install/generation latency for Phase 3's use. Not a strict content assertion — the point is human review of real output, not pinned wording; only asserts `generate()`'s contract (never throws, non-empty text once ready).