# File & Function Reference

Organized by folder, in dependency order (leaf constants first). "Notes" only called out where non-trivial; purely presentational files with no logic get a short entry. **Updated after two follow-up sessions applied fixes across the codebase, plus a third live-debugging session that found and fixed two previously-unidentified bugs (TTS never initializing, and wrong rotation compensation on the front camera) and reversed one earlier UI decision (`TargetZoneOverlay` removed at the user's request) — see `LIMITATIONS_AND_ROADMAP.md` for the full list.** Entries below reflect current state; superseded notes from earlier sessions have been removed rather than kept as history.

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
`TrackingEngine` — constructed with a `DetectionThresholds thresholds` (default `DetectionThresholds.defaultValues`). `smoothSubject`/`smoothScene` EMA/debounce as before. `trackingProgress(current, target, scene, targetScene, tolerance)` delegates to `ComparisonMath` and folds in brightness/background clutter. Unchanged this session; now covered by `test/core/services/tracking_engine_test.dart`.

#### `tts_service.dart`
`TtsService` — wraps `flutter_tts`; `speak()` guards on `_ready` (set by `init()`) so calls before initialization silently no-op rather than throwing. **Bug found and fixed this session:** `init()` was never called anywhere in the codebase — `ttsServiceProvider` only constructed `TtsService()` and returned it, so `_ready` stayed `false` forever and every `speak()` call was silently dropped. This was the root cause of "no voice coaching at all." Fixed by calling `service.init()` (fire-and-forget) inside `ttsServiceProvider`.

#### `expression_classifier.dart`
`classifyExpression({smilingProbability, leftEyeOpenProbability, rightEyeOpenProbability}) → String?` — the single shared expression classifier used by both `face_analyzer.dart` and `reference_image_analyzer.dart`. Unchanged this session.

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
Unchanged this session. Now covered by `test/capture/services/auto_capture_service_test.dart`, including a test that specifically demonstrates the reference-aware background gate rejecting a case the old fixed `<=5` literal would have allowed.

## features/editorial_score

#### `score_calculator.dart`
`calculateReferenceScore(...) → EditorialScore` — **the P0 fix**: `story` no longer reads a flat constant. A new `_storyScore(scene)` returns `(depthEstimate.clamp(0.0, 1.0) * 100).round()` when `scene.depthEstimate` is populated, falling back to a neutral `50` when it's `null` (instead of the old binary `depthFactor` producing a flat 75 or 53). `EditorialScore.toMap()`/`fromMap()` unchanged from the prior session. Now covered by `test/editorial_score/domain/score_calculator_test.dart`, including tests that assert `story` actually varies with `depthEstimate` and specifically is not `75`.

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
`ReferenceImageAnalyzer.analyze(imagePath) → ReferenceProfile` — unchanged pipeline. The five `catch` blocks (pose detector, face detector, segmenter, image decode, palette generator) now report through `ErrorReportingService.instance.report(e, st, context: ...)` instead of a bare `debugPrint`, so failures are retained in `ErrorReportingService.recentReports`, not just printed to console.

## features/scene_analysis

#### `scene_providers.dart`
`subjectProfileProvider`, `sceneProfileProvider`, `onFrameCallbackProvider`, `trackingEngineProvider`, `targetSubjectProfileProvider`, `targetSceneProfileProvider`, `trackingProgressProvider`, `sceneAnalysisListenerProvider` all unchanged this session. **New:** `mlKitUnavailableProvider` (`StateProvider<bool>`, default `false`) and `mlKitAvailabilityListenerProvider` — subscribes to `MlKitService.unavailableStream` and mirrors it into `mlKitUnavailableProvider`, which `camera_screen.dart` watches to show its banner.

#### `face_analyzer.dart`
Unchanged this session.

#### `light_analyzer.dart`
`LightAnalyzer.analyzeLight(...)` — **updated this session**: `_atan`/`_atan2` (the hand-rolled 7th-order Taylor-series approximation with no domain reduction) have been removed. `_atan2Degrees` now calls `dart:math`'s `atan2` directly, matching the pattern `pose_analyzer.dart` already used. No other behavior change — same call sites (`_estimateLightDirection`, `_estimateColorTone`), same signature. The `planes[1]=U, planes[2]=V` assumption in `_estimateColorTone` remains unverified (needs physical-device testing, out of scope for a code-only session).

#### `pose_analyzer.dart`
Unchanged.

#### `scene_profile.dart`, `subject_profile.dart`
Unchanged.

## features/settings

#### `settings_screen.dart`
Unchanged.

## features/splash

#### `splash_screen.dart`
Unchanged this session (mic permission drop, `get_it` removal, `HomeScreen` routing, and awaiting `memoryServiceProvider.future` were all done in the prior session).

## features/voice_director

#### `priority_engine.dart`
Unchanged.

#### `reference_comparison_engine.dart`
`ReferenceComparisonEngine.evaluate(...)` — **updated this session**: every `_evaluate*` method now selects from a **severity-tiered phrase bank** (mild/moderate/strong, via a new `_tieredPhrase(severity, [mild, moderate, strong])` helper) instead of one fixed literal per direction. E.g. shoulder-angle coaching now says "just a touch" at low severity vs. "a lot more — they're quite off" at high severity. `_evaluateExpression` keeps a single effective phrase since its underlying deviation is still binary (match/no-match) — noted in a code comment as the natural seam for a future partial-match-aware classifier. This is an interim, still-rule-based step toward the "model-driven upgrade" roadmap item, not a replacement for it — no on-device GenAI call has been wired in.

#### `voice_providers.dart`
Unchanged.

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

#### `main.dart`
**Updated this session:** `main()` now wires `FlutterError.onError` to `ErrorReportingService.instance.reportFlutterError`, sets `PlatformDispatcher.instance.onError` to report platform-level errors, and wraps `WidgetsFlutterBinding.ensureInitialized()`/`runApp(...)` in `runZonedGuarded` to catch uncaught async errors — all three previously had no handler at all. `MyApp` unchanged.

## test/ *(new)*

No `test/` directory existed before this session. Five files now cover the pure-Dart logic layer (no Flutter widget harness needed):
- `test/reference_photo/domain/comparison_math_test.dart` — `ComparisonMath`'s deviation/threshold/similarity functions.
- `test/editorial_score/domain/score_calculator_test.dart` — `calculateReferenceScore`, with explicit tests for the `story`-score P0 fix and `EditorialScore` persistence round-trip.
- `test/core/services/tracking_engine_test.dart` — EMA/debounce smoothing and the `ComparisonMath`-delegating `trackingProgress`.
- `test/album/domain/album_state_test.dart` — `AlbumState`'s add/remove/diversity/suggestion logic.
- `test/capture/services/auto_capture_service_test.dart` — `AutoCaptureService`'s gate chain, cooldown, and the reference-aware background-clutter gate.

Run via `flutter test`. Confirmed passing (65 tests) against the codebase as of this session. Not covered: `face_analyzer.dart`/`reference_image_analyzer.dart`/`expression_classifier.dart` and anything else requiring ML Kit or widget mocking — out of scope for the "pure Dart" starting point the roadmap called for.