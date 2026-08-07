# File & Function Reference

Organized by folder, in dependency order (leaf constants first). "Notes" only called out where non-trivial; purely presentational files with no logic get a short entry. **A fourth session found and fixed a severe correctness bug spanning two files: `SubjectProfile.copyWith` silently swallowed explicit nulls (so callers intending to clear a stale value never actually did), and `TrackingEngine.smoothSubject` separately dropped 4 of 9 `SubjectProfile` fields entirely when rebuilding its output. Combined, this meant `ReferenceComparisonEngine`'s face-pitch, face-roll, mouth-open, and eye-open coaching evaluators never fired in production — see `LIMITATIONS_AND_ROADMAP.md` for the full account.** A fifth session activated Track 2 end-to-end (device-verified smoke test, Settings toggle, two bugs fixed — see the `voice_director`/`settings` entries below) and fixed the Android toolchain versions required to build `flutter_gemma`. Entries below reflect current state; superseded notes from earlier sessions have been removed rather than kept as history.

## core/constants

#### `app_colors.dart`
`AppColors extends ThemeExtension<AppColors>` — 8-color palette (`background, surface, text, textMuted, accent, targetZone, success, warning`), `dark`/`light` static instances, standard `copyWith`/`lerp`. Clean, no issues. `targetZone` is used by `TargetZoneOverlay`; `warning` is now also used by the ML Kit unavailability banner in `camera_screen.dart`.

#### `app_spacing.dart`
Static `double` scale (`xs`4 … `xxl`48). No logic, no issues.

#### `app_strings.dart`
**Updated this session:** three new constants added — `settingsAiCoachingLabel`, `settingsAiCoachingSubtitle`, `settingsAiCoachingInstalling` — for the new AI Coaching Phrases toggle in `settings_screen.dart`. The original 10 constants unchanged.

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
`MemoryService` — thin wrapper over two Hive `Box`es (`shooting_habits`, `album_state`) with generic get/set. `memoryServiceProvider` is a `FutureProvider<MemoryService>` that awaits `init()` before resolving. **New this session:** the habits box now also stores the AI-coaching-toggle flag (`ai_coaching_enabled`, via the existing generic `getHabit`/`setHabit`) — no new methods needed, the service itself is unchanged. Schema versioning for the data it stores continues to live in the consumer (`album_providers.dart`), not in this generic service.

#### `ml_kit_service.dart`
`MlKitService` — owns the live-frame `PoseDetector`, `FaceDetector`, `SelfieSegmenter`, converts a `CameraImage` to ML Kit's `InputImage`, runs all three detectors sequentially per frame behind a `_busy` guard, broadcasting `MlKitAnalysisResult` on `analysisStream`. The live `FaceDetectorOptions` has `enableClassification: true`. `processImage` wraps the three detector calls in a `try`/`catch` — a failure is reported via `ErrorReportingService` and counted; after 5 consecutive failures (`_maxConsecutiveFailuresBeforeFlagging`) the service emits `true` on `unavailableStream`, and `false` again the next time a frame succeeds. Unchanged this session.

#### `theme_preference_service.dart`
`ThemePreferenceService extends StateNotifier<ThemeMode>` — persists dark/light via `shared_preferences`. Unchanged.

#### `tracking_engine.dart`
`TrackingEngine` — constructed with a `DetectionThresholds thresholds` (default `DetectionThresholds.defaultValues`). `smoothSubject`/`smoothScene` unchanged this session. `trackingProgress()` guards both `eyesOpen` and `expression` on *both sides non-null* before adding them to the weighted average, so they cleanly drop out now that they're permanently `null` — no change needed here, this behavior was already correct and is locked in by test.

#### `tts_service.dart`
`TtsService` — wraps `flutter_tts`; `speak()` guards on `_ready` (set by `init()`) so calls before initialization silently no-op rather than throwing. `ttsServiceProvider` calls `service.init()` (fire-and-forget) on construction. Unchanged this session.

#### `expression_classifier.dart`
`classifyExpression({smilingProbability, leftEyeOpenProbability, rightEyeOpenProbability}) → String?` — the single shared expression classifier used by both `face_analyzer.dart` and `reference_image_analyzer.dart`. Unchanged — per the Signal Disable plan's non-goals, this file is gated off from the live path by `face_analyzer.dart`'s flag, not edited or deleted.

#### `error_reporting_service.dart`
`ErrorReportingService` (singleton via `ErrorReportingService.instance`) — centralized error/crash capture. `report(error, stackTrace, {context})` records an `ErrorReport` (capped at the 200 most recent, in memory only) and `debugPrint`s it; `reportFlutterError(FlutterErrorDetails)` adapts framework errors to the same call. Wired from `main.dart` (`FlutterError.onError`, `PlatformDispatcher.instance.onError`, `runZonedGuarded`) and called directly from every previously-silent `catch` in `reference_image_analyzer.dart`, `album_providers.dart`, `camera_service.dart` (gallery save), and `ml_kit_service.dart` (per-frame processing failures). **Local-only** — a `TODO(remote-sink)` marks the intended extension point for a real service (Crashlytics/Sentry/custom backend) once one is chosen; reports do not currently survive app restart or leave the device.

## core/theme

#### `app_theme.dart`
`AppTheme.darkTheme`/`lightTheme` build a Material 3 `ThemeData` from `AppColors`. Unchanged.

## features/album

#### `album_providers.dart`
`AlbumNotifier extends StateNotifier<AlbumState>` — takes a `Ref`; on construction, asynchronously restores shots from `MemoryService`. A `schemaVersion` key (stored alongside `'shots'` in the album Hive box) is read on restore; if it's below `_currentShotsSchemaVersion` (currently `2`), `_migrateShots()` runs and the version is rewritten. `_persist()` always writes the current schema version alongside the data. All three previously-silent `catch` blocks (restore, persist, shot-file delete) report through `ErrorReportingService`.

#### `album_state.dart`
`AlbumState` — immutable list of `Shot` + public `shotTypes`. `diversityScore()`/`suggestNextShotType()` unchanged. Covered by `test/album/domain/album_state_test.dart`.

#### `shot.dart`
`Shot` — immutable record, includes `referenceImagePath` and `toleranceSettings` (both nullable, for backward-compatible deserialization of shots persisted before these fields existed). `toMap()`/`fromMap()` round-trip both.

#### `album_screen.dart`
`AlbumScreen` + `ShotDetailScreen` + `_confirmDeleteDialog`. Unchanged.

## features/camera_session

#### `camera_screen.dart`
The largest file in the app; hosts the live camera session. `_performCapture()` checks `cameraService.lastGallerySaveSucceeded == false` and sets `gallerySaveWarningProvider` if the gallery save failed. `build()` watches `mlKitAvailabilityListenerProvider`/`mlKitUnavailableProvider` for the persistent banner, and `ref.listen`s `gallerySaveWarningProvider` for a one-shot `SnackBar` (deferred via `addPostFrameCallback` to avoid a `markNeedsBuild`-during-build crash). `TargetZoneOverlay` removed from the `Stack`. Front-camera `InputImageRotation` uses `(360 - sensorOrientation) % 360` (mirrored sensor mount), back camera uses `sensorOrientation` directly. Unchanged this session.

#### ~~`album_button.dart`~~
**Deleted** (prior session — never instantiated).

#### `camera_preview_layer.dart`, `camera_top_nav_bar.dart`
Unchanged.

#### `debug_perf_overlay.dart`
`DebugPerfOverlay` — FPS counter + `AutoCaptureService.debugConditionBreakdown()` dump, reading `detectionThresholdsProvider`. Unchanged.

#### `focus_ring.dart`, `phrase_chip.dart`
Presentational, unchanged.

#### `shot_builder.dart`
`buildShotFromCapture(...)` — passes `referenceImagePath: reference.imagePath` and `toleranceSettings: tolerance` into the `Shot` it builds. Unchanged this session.

#### `capture_providers.dart`
`selectedShotTypeProvider`, `gallerySaveWarningProvider`, `gallerySaveFailedMessage`, `shouldCaptureProvider`/`autoCaptureProvider` — unchanged this session.

#### `auto_capture_service.dart`
`AutoCaptureService.shouldCapture(...)` — no `eyesOpen` gate (removed as part of Signal Disable Track 1). Every other gate (shoulder/face angle, pitch, roll, background clutter, brightness, tracking progress, cooldown) unchanged. Covered by `test/capture/services/auto_capture_service_test.dart`.

## features/editorial_score

#### `score_calculator.dart`
`calculateReferenceScore(...) → EditorialScore` — `story` derives from `_storyScore(scene)` (depth-estimate-based, neutral `50` fallback). `_expressionScore` returns a neutral `60` when the subject side has no expression signal (the permanent case now that `face_analyzer.dart` always produces `null`), instead of silently scoring it as a maximal mismatch. Covered by `test/editorial_score/domain/score_calculator_test.dart`.

#### `score_providers.dart`
Unchanged.

## features/home

#### `home_screen.dart`, `home_menu_card.dart`
Unchanged.

## features/reference_photo

#### `comparison_math.dart`
Unchanged. Covered by `test/reference_photo/domain/comparison_math_test.dart`.

#### `reference_profile.dart`
Unchanged.

#### `tolerance_settings.dart`
`ToleranceSettings` — 4 `double` sliders, `defaultBalanced`, `copyWith`, `toMap()`/`fromMap()` (so `Shot.toleranceSettings` round-trips through Hive).

#### `detection_thresholds.dart`, `detection_thresholds_provider.dart`, `reference_providers.dart`
Unchanged.

#### `reference_image_analyzer.dart`
`ReferenceImageAnalyzer.analyze(imagePath) → ReferenceProfile` — `bodyRatio` requires `nose`/`leftHip`/`leftAnkle` to pass the same `_minLandmarkLikelihood` confidence filter as `poseLandmarkPoints`; a half-body reference photo with an out-of-frame ankle yields `bodyRatio: null` rather than a silently-wrong ratio. The five independent analysis steps (pose, face, segmentation, decode, palette) run concurrently via `Future.wait`. Unchanged this session. **Still flagged, not fixed:** the same confidence-filter gap that was fixed for `reference_picker_sheet.dart`'s preview painter hasn't been applied here — see `LIMITATIONS_AND_ROADMAP.md`/`reference_picker_sheet.dart`'s entry below.

## features/scene_analysis

#### `scene_providers.dart`
`subjectProfileProvider`, `sceneProfileProvider`, `onFrameCallbackProvider`, `trackingEngineProvider`, `targetSceneProfileProvider`, `trackingProgressProvider`, `sceneAnalysisListenerProvider`, `mlKitUnavailableProvider`, `mlKitAvailabilityListenerProvider` — unchanged this session. `targetSubjectProfileProvider`'s no-reference-loaded fallback uses `bodyRatio: null` (not the live subject's own value), consistent with how a missing signal is treated everywhere else.

#### `face_analyzer.dart`
`FaceAnalyzer.analyzeFace(...)` — `eyesOpen`/`expression` permanently `null` behind `static const bool enableEyeAndExpressionSignals = false`. `faceAngleXDegrees`/`faceAngleZDegrees`/`mouthOpenRatio`/`eyeOpenRatio` unaffected. Covered by `test/scene_analysis/services/face_analyzer_test.dart`. Unchanged this session.

#### `light_analyzer.dart`
`LightAnalyzer.analyzeLight(...)` — `_atan2Degrees` calls `dart:math`'s `atan2` directly. The `planes[1]=U, planes[2]=V` assumption in `_estimateColorTone` remains unverified on a physical device. Unchanged this session.

#### `pose_analyzer.dart`, `scene_profile.dart`
Unchanged.

#### `subject_profile.dart`
`SubjectProfile` — immutable, 9 nullable fields + `timestamp`. `copyWith` uses a sentinel-object default per parameter so an explicit `null` is distinguishable from an omitted argument and actually clears the field. Unchanged this session.

## features/settings

#### `settings_screen.dart`
**Updated this session.** Second settings row added below Dark Mode: "AI Coaching Phrases" toggle, reading/writing `aiCoachingSettingsProvider`. Shows a progress indicator (`CircularProgressIndicator` with `value` bound to `installProgress/100` when known) while `ensureInstalled()` is running, and an inline warning-colored error line if the install fails. The switch is disabled (`onChanged: null`) while `isInstalling` is true, so the user can't re-trigger a concurrent install. Refactored the card layout into a small private `_SettingsCard` widget shared by both rows.

## features/settings/providers *(new)*

#### `ai_coaching_providers.dart` *(new)*
`AiCoachingSettings` (immutable: `enabled`, `isInstalling`, `installProgress`, `installError`) + `AiCoachingSettingsNotifier extends StateNotifier<AiCoachingSettings>` + `aiCoachingSettingsProvider`. On construction, reads the persisted flag from `MemoryService`'s habits box (`ai_coaching_enabled`, default `false`); if it was persisted as `true`, re-runs `_install()` on startup (idempotent — `ensureInstalled()` early-returns if the model's already `isReady`, and `flutter_gemma` caches its download, so this is a cheap verification, not a re-download, though that assumption is unconfirmed on-device — worth watching). `setEnabled(value)` persists the flag and, when turning on, awaits `_install()`. `_install()` reads `coachingPhraseModelServiceProvider`; if it's `null` (no `HF_TOKEN` at build time), sets a user-facing `installError` instead of crashing. Deliberately chosen over auto-triggering on first reference-photo pick, since the download is ~304MB and a user should consent to that rather than eat it silently.

## features/splash

#### `splash_screen.dart`
Unchanged.

## features/voice_director

#### `priority_engine.dart`
`PriorityAction` — carries a required `decision` field (`CoachingDecision`) alongside `phrase`/`severity`/`sourceLayer`. Unchanged this session.

#### `reference_comparison_engine.dart`
`ReferenceComparisonEngine.evaluate(...)` — 3-tier priority fallthrough (Pose & Face → Composition → Lighting/Color), severity-tiered phrases via `_tieredPhrase`, directional evaluators including `_evaluateFaceRoll` (left/right, gated behind `_faceRollDirectionIsMirrored`, still unverified on-device). Every `_evaluate*` method builds a `CoachingDecision` alongside the phrase. Unchanged this session. Covered by `reference_comparison_engine_test.dart`.

#### `voice_providers.dart`
`voiceDirectorListenerProvider` — Dedupe keyed on `next.decision.dedupeKey`. **Updated this session:** now reads `coachingPhraseModelServiceProvider` as nullable (`CoachingPhraseModelService?`) and gates generation on three conditions instead of one — `!aiUnavailable && aiCoachingEnabled && phraseModel != null && phraseModel.isReady` — where `aiCoachingEnabled` comes from `aiCoachingSettingsProvider.select((s) => s.enabled)` (new `features/settings/providers/ai_coaching_providers.dart` import). Falls back to `decision.fallbackPhrase` whenever any of those isn't true, same as before. `coachingAiUnavailableProvider` still trips after 3 consecutive failures. **No longer inert** — device-verified smoke test confirms the full path (install → generate → speak) works when the Settings toggle is on. `generationEpoch`/debounce/instrumentation (`lastPhraseGenerationLatencyMs`/`lastPhraseGenerationSucceeded`) unchanged.

## features/voice_director/models

#### `coaching_decision.dart`
`CoachingDecision` — `attribute`/`direction`/`tier`/`normalizedSeverity`/`fallbackPhrase`/`targetExpression`, plus `severityBand`/`dedupeKey` getters. Unchanged this session.

## features/voice_director/services

#### `coaching_phrase_model_service.dart`
`CoachingPhraseModelService` — wraps Gemma 3 270M via `flutter_gemma`/`flutter_gemma_mediapipe`. **Bug found and fixed this session:** `_ensurePluginInitialized()` called `FlutterGemma.initialize(...)` without awaiting it, then immediately proceeded to `install()` — a race condition where `install()`'s call into `ServiceRegistry.instance` could run before plugin registration actually finished, throwing `Bad state: FlutterGemma not initialized!`. Confirmed on-device: the smoke test failed with exactly that error, and the log showed `UnifiedModelManager initialized successfully` printing *after* the test had already failed — proof the async init was still running in the background. Fixed by making `_ensurePluginInitialized()` `async` and awaiting the `FlutterGemma.initialize(...)` call before `ensureInstalled()` proceeds to `install()`. `generate()`, `_buildPrompt()` unchanged.

## features/voice_director/providers

#### `coaching_phrase_model_providers.dart`
**Bug found and fixed this session:** `coachingPhraseModelServiceProvider` used `assert(_huggingFaceToken.isNotEmpty, ...)` — since Dart asserts are live in debug builds, this crashed immediately in any debug build missing `--dart-define=HF_TOKEN=...`, including ones where AI coaching was never meant to be used at all (the provider was read unconditionally at listener-setup time in `voice_providers.dart`, not lazily on toggle-on). Fixed: the provider now returns `CoachingPhraseModelService?` — `null` when the token is empty, a real instance otherwise. Consumers (`voice_providers.dart`, `ai_coaching_providers.dart`) treat `null` as "not available on this build" and surface that gracefully instead of crashing.

## features/capture/presentation/widgets

#### `shot_type_picker_sheet.dart`
Unchanged.

## features/reference_photo/presentation/widgets

#### `reference_picker_sheet.dart`
`ReferenceAnalysisPainter` — `_findSuspectExtremities`/`_torsoScale` hide any skeleton segment longer than 4x the shoulder/hip-width reference scale, preventing implausible extrapolated joint positions from being drawn for partial-body reference photos. Presentational-only fix — doesn't touch `reference_image_analyzer.dart`'s scoring pipeline, where the same underlying issue could still affect `bodyRatio` (flagged, not fixed — see that file's entry above). Unchanged this session.

#### `adjustments_sheet.dart`
Unchanged.

## shared/widgets

#### `app_background.dart`, `primary_button.dart`, `score_badge.dart`
Unchanged.

#### `target_zone_overlay.dart`
`TargetZoneOverlay` — animated, theme-aware alignment-box overlay with corner brackets. Unmounted from `camera_screen.dart`'s `Stack`. Dead code, unchanged this session.

## Root

#### `pubspec.yaml`
`flutter_gemma: ^1.5.2`, `flutter_gemma_mediapipe: ^1.0.0`, `integration_test` (dev). `environment.sdk: ^3.12.0`. Unchanged this session — the Android-side toolchain fixes below live in `android/` config files, not here.

#### `android/settings.gradle.kts`
**Updated this session.** AGP bumped `8.7.3` → `8.11.1` (prior version couldn't satisfy `androidx.core:core-ktx:1.17.0`'s minimum AGP requirement — build failed at `:app:checkDebugAarMetadata`). Kotlin bumped `2.1.0` → `2.2.20` alongside it (was separately flagged as due for an update; bundled into the same fix to avoid a second round).

#### `android/gradle/wrapper/gradle-wrapper.properties`
**Updated this session.** Gradle distribution bumped `8.12` → `8.14.3` (Flutter's own build output warned 8.12 support would soon be dropped).

#### `android/app/build.gradle.kts`
**Needs an NDK bump** — `ndkVersion` should be `28.2.13676358` (was `27.0.12077973`); `integration_test` specifically requires this version. Flagged by Gradle's own build output; confirm this was actually applied, since the AGP fix's build success doesn't by itself prove the NDK line was changed (the AGP failure occurred earlier in the build than the NDK mismatch would have been caught).

#### `main.dart`
`FlutterError.onError`/`PlatformDispatcher.instance.onError`/`runZonedGuarded` all wired to `ErrorReportingService`. Unchanged this session.

## test/

7 files, all passing (150 tests as of the Track-1 session's run — not re-run this session, since this session's changes were Track-2/toolchain-only and untouched by the existing suite):
- `test/reference_photo/domain/comparison_math_test.dart`
- `test/editorial_score/domain/score_calculator_test.dart`
- `test/core/services/tracking_engine_test.dart`
- `test/album/domain/album_state_test.dart`
- `test/capture/services/auto_capture_service_test.dart`
- `test/scene_analysis/services/face_analyzer_test.dart`
- `test/voice_director/domain/reference_comparison_engine_test.dart`

Not covered: `reference_image_analyzer.dart`'s `analyze()` orchestration (needs a physical device/platform channel) and `expression_classifier.dart` (gated off the live path). `coaching_phrase_model_service.dart` isn't a pure-Dart unit test target — see the integration test below, which now actually passes.

## integration_test/

#### `coaching_phrase_model_smoke_test.dart`
**Run this session — passed.** All 5 hand-picked `CoachingDecision`s installed and generated successfully on a physical device. One latency data point captured in this session's log excerpt: `hue`/strong severity → 2200ms. The other 4 decisions' individual latencies weren't captured in the pasted output — re-run and save the full log to complete the Phase 3 dataset. Getting to a passing run required: the Android toolchain bumps (AGP/Gradle/Kotlin/NDK, see `pubspec.yaml`'s entry above), fixing the `FlutterGemma.initialize()` race condition in `coaching_phrase_model_service.dart`, and the tester's Hugging Face account accepting the Gemma license on `litert-community/gemma-3-270m-it`'s model page (a valid token alone isn't sufficient for gated models).