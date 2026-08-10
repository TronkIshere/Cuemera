# File & Function Reference

Organized by folder, in dependency order (leaf constants first). "Notes" only called out where non-trivial; purely presentational files with no logic get a short entry. **A fourth session found and fixed a severe correctness bug spanning two files: `SubjectProfile.copyWith` silently swallowed explicit nulls (so callers intending to clear a stale value never actually did), and `TrackingEngine.smoothSubject` separately dropped 4 of 9 `SubjectProfile` fields entirely when rebuilding its output. Combined, this meant `ReferenceComparisonEngine`'s face-pitch, face-roll, mouth-open, and eye-open coaching evaluators never fired in production — see `LIMITATIONS_AND_ROADMAP.md` for the full account.** A fifth session activated Track 2 end-to-end (device-verified smoke test, Settings toggle, two bugs fixed — see the `voice_director`/`settings` entries below) and fixed the Android toolchain versions required to build `flutter_gemma`. **A sixth session fixed four more device-confirmed bugs**, all cross-referenced from their respective entries below: a front/back-camera rotation mismatch in `ml_kit_service.dart`/`camera_screen.dart`, a native crash in `coaching_phrase_model_service.dart` from too-low `maxTokens`, an EXIF-orientation bug in `reference_image_analyzer.dart`, and an Android release-build (R8/minify) failure fixed via `proguard-rules.pro` + a `build.gradle.kts` change. Also added: a short TTS capture confirmation in `camera_screen.dart`. **A seventh session started adding `sherpa_onnx` (VITS/Piper) as a second, primary TTS engine, with `flutter_tts` kept as fallback — see the new `sherpa_tts_service.dart`/`app_tts_service.dart` entries below. This work is incomplete: asset wiring in `pubspec.yaml` isn't finished and nothing has been device-verified yet.** Entries below reflect current state; superseded notes from earlier sessions have been removed rather than kept as history.

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
`CameraService` — wraps the `camera` plugin. **Merged this session from a two-`CameraController` design into one.** Previously maintained `_controller` (medium-res, live ML-analysis stream) and `_previewController` (high-res, on-screen preview) as two independently-opened sessions against the same camera lens — this is not how CameraX (the `camera` plugin's Android backend) is meant to be driven; it already supports Preview + ImageAnalysis + ImageCapture as one bound session, and running two separate sessions instead left CameraX negotiating a degraded configuration on devices reporting a `LIMITED` Camera2 hardware level (confirmed on an Oppo Reno 14/ColorOS device: preview/capture were visibly softer than the stock camera app, autofocus did not behave like continuous AF). Now there is a single `_controller` (`ResolutionPreset.high` — the old preview/capture preset) driving preview, `startImageStream()`, and `capture()` alike; `previewController`/`isPreviewInitialized`/`initPreviewController()` are gone. `capture()` no longer spins up any third, temporary controller either (that per-photo lifecycle was already replaced by directly reusing the (then-)preview controller in a prior session) — it now stops the shared controller's image stream before `takePicture()` and resumes it afterward via a `try`/`finally`, using the `onImage` callback `CameraService` retains internally from the last `startImageStream()` call, so the caller doesn't need to re-supply it after every capture. `lastCaptureControllerSetupLatency`/`lastCaptureControllerTeardownLatency` stay `Duration.zero` — there's no separate controller lifecycle left to time at all now, not just "no longer a separate per-photo controller" as before. `lastCaptureShutterLatency` (measuring `takePicture()` itself) and `lastGallerySaveSucceeded` tracking unchanged. `switchLens()` now creates one controller instead of two; `pauseCameras()`/`resumeCameras()`/`dispose()` similarly collapsed to one dispose/recreate path. **Not yet device-verified** — see `LIMITATIONS_AND_ROADMAP.md`.

#### `memory_service.dart`
`MemoryService` — thin wrapper over two Hive `Box`es (`shooting_habits`, `album_state`) with generic get/set. `memoryServiceProvider` is a `FutureProvider<MemoryService>` that awaits `init()` before resolving. **New this session:** the habits box now also stores the AI-coaching-toggle flag (`ai_coaching_enabled`, via the existing generic `getHabit`/`setHabit`) — no new methods needed, the service itself is unchanged. Schema versioning for the data it stores continues to live in the consumer (`album_providers.dart`), not in this generic service.

#### `ml_kit_service.dart`
`MlKitService` — owns the live-frame `PoseDetector`, `FaceDetector`, `SelfieSegmenter`, converts a `CameraImage` to ML Kit's `InputImage`, runs all three detectors sequentially per frame behind a `_busy` guard, broadcasting `MlKitAnalysisResult` on `analysisStream`. The live `FaceDetectorOptions` actually has `enableClassification: false` (this entry previously said `true` — that was wrong; see the `enableClassification` product-decision item in `LIMITATIONS_AND_ROADMAP.md`). `processImage` wraps the three detector calls in a `try`/`catch` — a failure is reported via `ErrorReportingService` and counted; after 5 consecutive failures (`_maxConsecutiveFailuresBeforeFlagging`) the service emits `true` on `unavailableStream`, and `false` again the next time a frame succeeds.

**Rewritten this session (bug fix):** `processImage(image, description, deviceOrientation)`'s third parameter changed from a pre-computed `InputImageRotation` to a raw `DeviceOrientation`. Previously the caller (`camera_screen.dart`) computed rotation itself with a formula that ignored device orientation and didn't match either camera's correct rotation-compensation convention; `description` was accepted here but never actually used. Now `rotationFor(description, deviceOrientation)` computes rotation internally, applying the front-camera formula (`sensorOrientation + deviceRotation`) or back-camera formula (`sensorOrientation - deviceRotation`, both mod 360) based on `description.lensDirection` — the two conventions differ and using the wrong one for front camera was the root cause of `shoulderAngle`/`faceAngle` reading `FAIL` regardless of actual pose. Not yet re-confirmed on a physical device after the fix — see `LIMITATIONS_AND_ROADMAP.md` §1.

#### `theme_preference_service.dart`
`ThemePreferenceService extends StateNotifier<ThemeMode>` — persists dark/light via `shared_preferences`. Unchanged.

#### `tracking_engine.dart`
`TrackingEngine` — constructed with a `DetectionThresholds thresholds` (default `DetectionThresholds.defaultValues`). `smoothSubject`/`smoothScene` unchanged this session. `trackingProgress()` guards both `eyesOpen` and `expression` on *both sides non-null* before adding them to the weighted average, so they cleanly drop out now that they're permanently `null` — no change needed here, this behavior was already correct and is locked in by test.

#### `tts_service.dart`
`TtsService` — wraps `flutter_tts`; `speak()` guards on `_ready` (set by `init()`) so calls before initialization silently no-op rather than throwing. `ttsServiceProvider` calls `service.init()` (fire-and-forget) on construction. File itself unchanged this (seventh) session, but its role changed: no longer called directly by feature code — it's now only reached as `AppTtsService`'s fallback (see below) when `sherpa_onnx` isn't ready or throws.

#### `sherpa_tts_service.dart` *(new, seventh session — in progress)*
`SherpaTtsService` — wraps `sherpa_onnx.OfflineTts` (VITS/Piper engine). `init()` extracts the bundled VITS model's asset files (expected under `assets/models/vits-en/`: `model.onnx`, `tokens.txt`, `espeak-ng-data/`) to a writable app-support directory on first run — reads `AssetManifest.json` and copies every file whose key starts with the configured prefix, since the native library needs real filesystem paths, not Flutter asset-bundle keys. `speak(phrase, {emphasis})` takes a `TtsEmphasis` (`mild`/`moderate`/`strong`) and maps it to both `speed` (1.0 → 0.88) and `OfflineTtsGenerationConfig.silenceScale` (0.2 → 0.45) via `generateWithConfig()`, plus appends a trailing `!` for `strong` — the practical ceiling of emphasis control this model exposes, since sherpa_onnx has no true prosody/SSML parameter. Output is written via the top-level `sherpa_onnx.writeWave()` (not a method on `GeneratedAudio` — an earlier draft assumed `audio.save()`, which doesn't exist in the Dart API and was a real compile error) to a temp WAV file, played via `audioplayers`' `AudioPlayer.play(DeviceFileSource(...))`. `OfflineTtsConfig`'s max-sentence-count field is named `maxNumSenetences` (that typo is genuinely in the shipped package, confirmed against multiple official sherpa-onnx examples — not a typo introduced here). **Not yet device-tested** — see `LIMITATIONS_AND_ROADMAP.md` §1.

#### `app_tts_service.dart` *(new, seventh session)*
`AppTtsService` — thin wrapper exposing `speak(phrase, {emphasis})`/`stop()`. Tries `SherpaTtsService` first (if `isReady`); falls back to `TtsService` (flutter_tts) on any thrown error or when the sherpa model isn't ready yet — mirrors the existing AI-coaching-phrase-or-fallback pattern already used for Gemma. Call sites (`voice_providers.dart`, `camera_screen.dart`) only depend on this provider, not on `SherpaTtsService`/`TtsService` directly, so the fallback logic stays in one place.

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
The largest file in the app; hosts the live camera session. **This session:** follows `camera_service.dart`'s merge to a single `CameraController` — `_initCamera()` now only calls `cameraService.init()` (no separate `initPreviewController()` call), `_buildReadyBody()`/`_onScaleUpdate()`/`_onTapUp()` all read `cameraService.controller` instead of `cameraService.previewController`, and `CameraPreviewLayer` is now constructed with `controller:` (see `camera_preview_layer.dart`'s renamed parameter). `_performCapture()` no longer calls `cameraService.startImageStream(_onFrame)` itself after `capture()` returns — `CameraService.capture()` now resumes the stream internally with the callback it already has, so the old explicit re-call after a successful capture was redundant and has been removed. `_performCapture()` checks `cameraService.lastGallerySaveSucceeded == false` and sets `gallerySaveWarningProvider` if the gallery save failed; also calls `appTtsServiceProvider`'s `speak('Photo captured.', force: true)` right after a successful capture (the `force` flag bypasses `AppTtsService`'s same-phrase dedupe, which otherwise only let this confirmation play once per session — see `tts_service.dart`/`sherpa_tts_service.dart`/`app_tts_service.dart` entries). `build()` watches `mlKitAvailabilityListenerProvider`/`mlKitUnavailableProvider` for the persistent banner, and `ref.listen`s `gallerySaveWarningProvider` for a one-shot `SnackBar` (deferred via `addPostFrameCallback` to avoid a `markNeedsBuild`-during-build crash). `TargetZoneOverlay` removed from the `Stack`. `dispose()` now reads `CameraService` from a field (`_cameraService`, captured in `initState()`) rather than `ref.read()`, since `ref` cannot be used inside `dispose()` once the element is being torn down.

**`_onFrame` rewritten this session (bug fix):** previously computed `InputImageRotation` itself — front camera via `(360 - sensorOrientation) % 360`, back camera via `sensorOrientation` directly — a formula with no device-orientation term at all, which was wrong for the front camera and the root cause of front-camera `shoulderAngle`/`faceAngle` coaching always failing. That logic is now deleted entirely; `_onFrame` just passes `controller.value.deviceOrientation` through to `mlKitService.processImage(image, description, deviceOrientation)`, which computes rotation correctly per lens direction — see `ml_kit_service.dart`'s entry above.

#### ~~`album_button.dart`~~
**Deleted** (prior session — never instantiated).

#### `camera_preview_layer.dart`
`CameraPreviewLayer` — its `previewController` constructor parameter is renamed to `controller` this session, matching `CameraService`'s collapse to a single `CameraController` (see `camera_service.dart` above). Purely a rename at the call site in `camera_screen.dart`; the widget never read `cameraServiceProvider` directly, so no other behavior changes here.

#### `camera_top_nav_bar.dart`
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
`AutoCaptureService.shouldCapture(...)` — no `eyesOpen` gate (removed as part of Signal Disable Track 1). **This session:** added four gates that previously existed as `reference_comparison_engine.dart` coaching evaluators but had no bearing on capture timing at all — `bodyRatio`/`mouthOpen` (via `ComparisonMath.relativeDeviation`/`thresholdForPoseRatio`, mirroring `_evaluateBodyRatio`/`_evaluateMouthOpen`) and `negativeSpace`/`symmetry` (via `ComparisonMath.deviation`/`thresholdForComposition`, mirroring `_evaluateNegativeSpace`/`_evaluateSymmetry`). `warmth`/`hue` deliberately left ungated — color/lighting tone is harder for a subject to control instantly than pose/composition, and gating on it risked auto-capture rarely firing at all; they remain coaching-only. Every gate (shoulder/face angle, pitch, roll, body ratio, mouth open, negative space, symmetry, background clutter, brightness, tracking progress, cooldown) short-circuits `shouldCapture()` and is also surfaced in `debugConditionBreakdown()`. **Not yet device-verified** — the four new gates make auto-capture stricter than before; existing tuned thresholds may need re-checking on a physical device to confirm capture still fires in practice. Covered by `test/capture/services/auto_capture_service_test.dart` (tests likely need updating for the new gates).

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
`ReferenceImageAnalyzer.analyze(imagePath) → ReferenceProfile` — `bodyRatio` requires `nose`/`leftHip`/`leftAnkle` to pass the same `_minLandmarkLikelihood` confidence filter as `poseLandmarkPoints`; a half-body reference photo with an out-of-frame ankle yields `bodyRatio: null` rather than a silently-wrong ratio. The five independent analysis steps (pose, face, segmentation, decode, palette) run concurrently via `Future.wait`. **Still flagged, not fixed:** the same confidence-filter gap that was fixed for `reference_picker_sheet.dart`'s preview painter hasn't been applied here — see `LIMITATIONS_AND_ROADMAP.md`/`reference_picker_sheet.dart`'s entry below.

**Bug found and fixed this (sixth) session:** `_decodeImageFile` called `img.decodeImage(bytes)` to get `imageWidth`/`imageHeight`, but that reads raw sensor-orientation pixels and ignores the file's EXIF orientation tag — while `_analyzePose`/`_analyzeFace` (both using `InputImage.fromFilePath`) do apply it. On an EXIF-rotated reference photo, this put `imageWidth`/`imageHeight` in a different coordinate space than the landmark points computed from the same image, so `reference_picker_sheet.dart`'s `ReferenceAnalysisPainter` scaled correct landmarks onto the wrong canvas dimensions — the visible symptom was skeleton lines running off toward unrelated parts of the photo. Fixed by calling `img.bakeOrientation()` on the decoded image before reading its width/height. Confirmed only via a before/after screenshot comparison so far, not a formal test.

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
`ReferenceComparisonEngine.evaluate(...)` — severity-tiered phrases via `_tieredPhrase`, directional evaluators including `_evaluateFaceRoll` (left/right, gated behind `_faceRollDirectionIsMirrored`, still unverified on-device). Every `_evaluate*` method builds a `CoachingDecision` alongside the phrase. **This session:** added `_evaluateFaceYaw` — `AutoCaptureService._faceOk()` was already gating capture on `subject.faceAngleDegrees`/`reference.faceAngleDegrees` (the yaw axis, distinct from `faceAngleXDegrees`/pitch and `faceAngleZDegrees`/roll), but there was no coaching evaluator for it at all, so capture could silently keep failing on face-yaw mismatch with zero spoken guidance about why. Same math as `_evaluateShoulderAngle` (`ComparisonMath.deviation`/`maxDeviationForPose`/`thresholdForPose`), gated behind a new `_faceYawDirectionIsMirrored` flag (default `false`) — **direction unverified on-device**, same caveat as `_faceRollDirectionIsMirrored`.

**Also this session — `evaluate()`'s tier fallthrough rewritten:** previously `_pickWorst(poseAndFace) ?? _pickWorst(composition) ?? _pickWorst(lighting)` meant composition/lighting were *never* voiced as long as pose & face had anything exceeding threshold, however minor — in practice a live subject rarely holds pose/face perfectly still, so lighting/color coaching could go unheard for an entire session despite its evaluators firing correctly. Now: any tier whose worst issue is `moderate`/`strong` severity is still surfaced immediately in fixed tier order (a real problem shouldn't wait). But if every tier's worst issue is only `mild` (or has nothing), the three tiers now round-robin via a new `_tierRotation` instance field, so composition and lighting get a fair turn instead of being perpetually starved by a chronically-mild pose/face issue. `_pickWorst` split into `_worst` (returns the raw `_AttributeEvaluation` so severity can be inspected before deciding) and `_toPriorityAction`. Covered by `reference_comparison_engine_test.dart` (tests likely need updating for the new evaluator and fallthrough logic).

#### `voice_providers.dart`
`voiceDirectorListenerProvider` — Dedupe keyed on `next.decision.dedupeKey`. Reads `coachingPhraseModelServiceProvider` as nullable (`CoachingPhraseModelService?`) and gates generation on three conditions instead of one — `!aiUnavailable && aiCoachingEnabled && phraseModel != null && phraseModel.isReady` — where `aiCoachingEnabled` comes from `aiCoachingSettingsProvider.select((s) => s.enabled)`. Falls back to `decision.fallbackPhrase` whenever any of those isn't true, same as before. `coachingAiUnavailableProvider` still trips after 3 consecutive failures. `generationEpoch`/debounce/instrumentation (`lastPhraseGenerationLatencyMs`/`lastPhraseGenerationSucceeded`) unchanged.

**Updated this (seventh) session:** switched from `ttsServiceProvider` to `appTtsServiceProvider` (see `app_tts_service.dart`). Added a local `emphasisFor(severityBand)` mapping `CoachingDecision.severityBand` to `TtsEmphasis` by string-matching `.name` (`'strong'`/`'moderate'`/else `mild`) — passed into every `ttsService.speak(...)` call so both AI-generated and fallback phrases carry the right emphasis. **Deliberately left untyped** (no `SeverityBand` type annotation on the parameter) — `coaching_decision.dart`'s actual `severityBand` return type wasn't confirmed at the time this was written; see `LIMITATIONS_AND_ROADMAP.md` §3 for the follow-up to tighten this.

## features/voice_director/models

#### `coaching_decision.dart`
`CoachingDecision` — `attribute`/`direction`/`tier`/`normalizedSeverity`/`fallbackPhrase`/`targetExpression`, plus `severityBand`/`dedupeKey` getters. **This session:** added `faceYaw` to `CoachingAttribute` — see `reference_comparison_engine.dart`'s new `_evaluateFaceYaw`.

## features/voice_director/services

#### `coaching_phrase_model_service.dart`
`CoachingPhraseModelService` — wraps Gemma 3 270M via `flutter_gemma`/`flutter_gemma_mediapipe`. **Bug found and fixed (earlier session):** `_ensurePluginInitialized()` called `FlutterGemma.initialize(...)` without awaiting it, then immediately proceeded to `install()` — a race condition where `install()`'s call into `ServiceRegistry.instance` could run before plugin registration actually finished, throwing `Bad state: FlutterGemma not initialized!`. Confirmed on-device: the smoke test failed with exactly that error, and the log showed `UnifiedModelManager initialized successfully` printing *after* the test had already failed — proof the async init was still running in the background. Fixed by making `_ensurePluginInitialized()` `async` and awaiting the `FlutterGemma.initialize(...)` call before `ensureInstalled()` proceeds to `install()`.

**Second bug found and fixed this (sixth) session, from a device crash log:** `ensureInstalled()` called `FlutterGemma.getActiveModel(maxTokens: 128)` — too low. A real coaching prompt from `_buildPrompt()` reached 185 tokens on its own, already over `maxTokens` before any output token was generated, which aborted the native LLM inference process (`JNI DETECTED ERROR IN APPLICATION`, `SIGABRT`) instead of failing gracefully — this crash happens below the Dart/FFI boundary, so it's uncatchable by the `try`/`catch` around `generate()` in `voice_providers.dart`. Fixed by raising `maxTokens` to `512`. `_buildPrompt()` itself is otherwise unchanged and still has no explicit length cap — see the related `LIMITATIONS_AND_ROADMAP.md` §3 item on hardening this further.

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
`flutter_gemma: ^1.5.2`, `flutter_gemma_mediapipe: ^1.0.0`, `integration_test` (dev). `environment.sdk: ^3.8.1` — **this contradicts the `^3.12.0` this doc previously stated** for the Track-2/Gemma toolchain bump; flagged as unresolved, not changed (see `LIMITATIONS_AND_ROADMAP.md` §4's seventh-session toolchain note).

**Updated this (seventh) session:** added `sherpa_onnx: ^1.12.11` and `audioplayers: ^6.0.0` for the new TTS engine (see `sherpa_tts_service.dart`). Also **two structural bugs found and fixed, unrelated to sherpa_onnx but blocking its assets from ever being bundled:**
- a stray top-level `assets:` key — Flutter only reads `assets:` when nested under the `flutter:` key; this one was silently ignored, so *no* assets (including the pre-existing `assets/images/`) were ever actually being bundled. Fixed: merged into the single `flutter:` block, which now holds `uses-material-design: true` and `assets:` together.
- `flutter_launcher_icons.image_path` had `assets/models/vits-en/` mistakenly appended to what should be a single icon-file path (`image_path` expects one string, not a list). Fixed: back to `image_path: "assets/images/logo.png"`.

**Still incomplete:** the `assets:` list under `flutter:` is missing the `espeak-ng-data/` subdirectory entries for the VITS model — Flutter doesn't bundle directories recursively, so each nested subdirectory needs its own line, and the real subdirectory list (via `find assets/models/vits-en -type d`) hadn't been supplied as of this writing.

#### `android/settings.gradle.kts`
**Updated this session.** AGP bumped `8.7.3` → `8.11.1` (prior version couldn't satisfy `androidx.core:core-ktx:1.17.0`'s minimum AGP requirement — build failed at `:app:checkDebugAarMetadata`). Kotlin bumped `2.1.0` → `2.2.20` alongside it (was separately flagged as due for an update; bundled into the same fix to avoid a second round).

#### `android/gradle/wrapper/gradle-wrapper.properties`
**Updated this session.** Gradle distribution bumped `8.12` → `8.14.3` (Flutter's own build output warned 8.12 support would soon be dropped).

#### `android/app/build.gradle.kts`
NDK bump to `28.2.13676358` is confirmed applied — `ndkVersion = "28.2.13676358"` is present, and a release APK now builds end-to-end (see below), which it couldn't have done with the old NDK version. **Updated this (sixth) session:** the `release` block previously had no `proguardFiles(...)` call at all, so `android/app/proguard-rules.pro` (see the new entry below) was never actually applied by R8 no matter what it contained. Release builds failed at `:app:minifyReleaseWithR8` with two missing MediaPipe profiling classes pulled in transitively by `flutter_gemma_mediapipe`. Fixed by adding `proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")` to the `release` block. A release APK now builds successfully (~230MB universal APK — `--split-per-abi` would shrink this for real distribution).

#### `android/app/proguard-rules.pro` *(new this session)*
Two `-dontwarn` lines for `com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile` and `com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate` — copied verbatim from Gradle's own generated `missing_rules.txt` after the R8 failure above. Only takes effect now that `build.gradle.kts`'s `release` block actually references this file (see above).

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