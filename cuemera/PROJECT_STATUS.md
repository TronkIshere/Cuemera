```markdown
# 1. Overview

Cuemera is an AI fashion photographer app built in Flutter. Its core philosophy is to direct the user like a real photographer would — giving live, spoken and visual cues ("square your shoulders", "find more light", "give a warm smile") — rather than asking the user to copy a static reference pose. The system watches the user through the phone's camera in real time, understands their body, face, and the scene around them, and produces a single, prioritized, real-time instruction at any given moment, then automatically (or manually) captures the shot when everything aligns, scores it editorially, and organizes it into an album that tracks shot diversity across a session.

The current architecture approach is 100% on-device edge AI in Flutter: camera capture (`camera`), pose/face/segmentation analysis (`google_mlkit_*` packages), local smoothing/decision logic in pure Dart, local persistence via Hive, and text-to-speech via `flutter_tts`. State is managed with Riverpod throughout. An optional Java/Spring backend has been discussed as a future layer (e.g. for cloud sync, heavier ML, or multi-device history) but has not been started — everything today runs entirely on-device.

# 2. Completion Summary

| Layer/Area | Status | % Complete | Notes |
|---|---|---|---|
| Infrastructure (core/shared/branding) | Done | 100% | AppColors (ThemeExtension, dark+light), AppTheme, AppSpacing, AppTypography, all core services, service_locator, pubspec fully wired |
| Splash Screen | Done | 100% | Full init flow (Hive, locator, theme, permissions, ML Kit warm-up), logo fallback, retry-on-error |
| 1. Goal Understanding (goal_selection) | Done | 100% | PhotographyGoal enum, GoalStyleProfile, goal_selection UI, fully wired to providers and navigation |
| 2. Human Understanding (scene_analysis: subject) | Near done | ~85% | SubjectProfile model, PoseAnalyzer, FaceAnalyzer implemented and wired; not yet validated on real device |
| 3. Scene Understanding (scene_analysis: scene) | Near done | ~85% | SceneProfile model, LightAnalyzer implemented; brightness estimation is a simple average-byte heuristic, not perceptual luminance |
| 4. Editorial Brain (editorial_rules + score_calculator) | Near done | ~90% | Rule sets exist per goal but content is sparse (few rules per goal); score_calculator fully implemented with weighted breakdown |
| 5. Photographer Brain / Direction logic (priority_engine) | Near done | ~90% | getNextAction() implemented, selects highest-severity matching rule; not yet personalized via memory |
| 6. Direction Engine (voice_director UI/TTS wiring) | Near done | ~90% | nextActionProvider + debounced TTS listener + on-screen phrase chip implemented and wired in camera_screen |
| 7. Tracking Engine (tracking_engine.dart) | Near done | ~85% | EMA smoothing + debounce implemented; trackingProgress() implemented and wired into TargetZoneOverlay and auto-capture gating |
| 8. Capture Engine (capture feature) | Near done | ~85% | AutoCaptureService with multi-condition gate (eyes, brightness, angles, clutter, trackingProgress >= 0.9, cooldown) + manual capture fallback button, both wired to AlbumState |
| 9. Quality Engine (editorial_score) | Partial | ~70% | calculateScore() implemented with per-goal weights and 5-category breakdown; not tuned/validated against real captured photos |
| 10. Album Director (album feature) | Near done | ~90% | AlbumState, Shot, album_screen grid, diversity score, next-shot-type suggestion, shot detail view with per-category ScoreBadge breakdown |
| 11. Memory Layer (memory_service) | Partial | ~60% | Hive-backed habit/correction storage methods implemented (saveHabit, getHabit, recordCorrection, getFrequentCorrections); not yet consumed anywhere (no read-side integration into priority_engine) |
| Real-device testing | Not started | 0% | No FPS, battery, or on-device permission-flow validation has been performed at any point in this project |

**Overall estimated completion: ~65-70%**

# 3. What Has Been Built (Detailed)

## Infrastructure (core/shared/branding)

- `core/constants/app_colors.dart` — `AppColors` as a `ThemeExtension<AppColors>` with two static const instances, `AppColors.dark` and `AppColors.light`, each defining `background`, `surface`, `text`, `textMuted`, `accent`, `targetZone`, `success`, `warning`. Includes `copyWith` and `lerp` overrides required by `ThemeExtension`.
- `core/constants/app_spacing.dart` — `AppSpacing` abstract class with double constants: `xs (4)`, `sm (8)`, `md (16)`, `lg (24)`, `xl (32)`, `xl2 (40)`, `xxl (48)`.
- `core/constants/app_typography.dart` — `AppTypography` with static `TextStyle` builder methods (`heading1`, `heading2`, `body`, `bodyMuted`, `caption`, `score`), each taking an `AppColors` instance and returning a colored `TextStyle`. Also exposes `buildTextTheme(AppColors)` which builds a full Flutter `TextTheme`.
- `core/constants/app_strings.dart` — `AppStrings` with `appName`, `appTagline`, and various UI copy strings (permission, capture, album, error strings).
- `core/theme/app_theme.dart` — `AppTheme` with `darkTheme` / `lightTheme` getters, both built via a shared `_build(AppColors, Brightness)` helper that registers the `AppColors` extension and wires `AppSpacing`/`AppTypography` into `ColorScheme`, `AppBarTheme`, `CardTheme`, `ElevatedButtonTheme`, and `TextTheme`.
- `core/services/camera_service.dart` — `CameraService` wraps `CameraController` lifecycle: `init()`, `switchLens()`, `startImageStream(onImage)`, `stopImageStream()`, `dispose()`, and `capture()` (returns `Future<String?>` image file path, stopping the image stream first). Exposed via `cameraServiceProvider` (Riverpod `Provider`).
- `core/services/ml_kit_service.dart` — `MlKitService` wraps `PoseDetector`, `FaceDetector`, `SelfieSegmenter` from `google_mlkit_*` packages behind a single `processImage(CameraImage, CameraDescription, InputImageRotation)` method. Converts `CameraImage` to `InputImage` via `InputImage.fromBytes` + `InputImageMetadata` (using `google_mlkit_commons`). Publishes `MlKitAnalysisResult` (poses, faces, segmentationMask) on a broadcast `analysisStream`. Exposed via `mlKitServiceProvider`.
- `core/services/tts_service.dart` — `TtsService` wraps `flutter_tts` tuned for short realtime phrases (rate 0.55, dedupes identical consecutive phrases via `_lastPhrase`). Exposes `speak(String)`, `stop()`. Exposed via `ttsServiceProvider`.
- `core/services/memory_service.dart` — `MemoryService` wraps two Hive boxes (`shooting_habits`, `album_state`). Methods: `getHabit<T>(key, {defaultValue})`, `setHabit<T>(key, value)`, `saveHabit(key, value)`, `recordCorrection(String correctionType)` (increments a count in a `corrections` map inside the habits box), `getFrequentCorrections()` (returns `Map<String, int>`), plus album-box `getAlbumValue`/`setAlbumValue` and `clearHabits`/`clearAlbum`. Exposed via `memoryServiceProvider`.
- `core/services/theme_preference_service.dart` — `ThemePreferenceService extends StateNotifier<ThemeMode>`, persisted via `shared_preferences` under key `dark_mode_enabled`, defaults to `ThemeMode.dark`. Exposed via `themeModeProvider` (`StateNotifierProvider`).
- `core/di/service_locator.dart` — GetIt-based `sl` locator registering `CameraService`, `MlKitService`, `TtsService`, `MemoryService` as lazy singletons (used primarily for pre-`runApp` bootstrapping in splash; Riverpod providers are the primary DI mechanism elsewhere).
- `shared/widgets/primary_button.dart` — `PrimaryButton(label, onPressed, isLoading, enabled)`, accent-colored, disables on `isLoading || !enabled`, shows a spinner when loading.
- `shared/widgets/score_badge.dart` — `ScoreBadge(score, size)`, circular badge color-coded: `>=80` success, `>=50` accent, else warning.
- `shared/widgets/target_zone_overlay.dart` — see Tracking Engine section below (has evolved significantly since initial version).
- `pubspec.yaml` — dependencies: `camera`, `google_mlkit_pose_detection`, `google_mlkit_face_detection`, `google_mlkit_selfie_segmentation`, `google_mlkit_commons`, `flutter_tts`, `flutter_riverpod`, `hive`, `hive_flutter`, `path_provider`, `shared_preferences`, `permission_handler`, `get_it`, `cupertino_icons`; dev: `flutter_lints`, `hive_generator`, `build_runner`. Assets: `assets/images/`.

## Splash Screen

- `features/splash/presentation/screens/splash_screen.dart` — `SplashScreen` (ConsumerWidget) + `splashInitProvider` (`FutureProvider.autoDispose<void>`) that sequentially: initializes `MemoryService` (Hive boxes), runs `setupLocator()`, awaits `ThemePreferenceService.load()`, requests camera + microphone permissions via `permission_handler` (throws if either denied), and instantiates `MlKitService` (warm-up). UI: centered `Image.asset('assets/images/logo.png')` with `errorBuilder` fallback to text wordmark using `AppTypography.heading1`, tagline below via `AppTypography.bodyMuted`, accent-colored `CircularProgressIndicator` while loading, error state renders message + `PrimaryButton("Retry")` that calls `ref.invalidate(splashInitProvider)`. On success, `pushReplacement`s to `GoalSelectionScreen`.

## 1. Goal Understanding (goal_selection)

- `features/goal_selection/domain/models/photography_goal.dart` — `enum PhotographyGoal { editorial, linkedin, travel, dating, beach, luxury }`. `GoalStyleProfile { goal, priorityWeights: Map<String,double>, targetCompositionRules: List<String> }`. `getStyleProfile(PhotographyGoal) -> GoalStyleProfile` returns a hardcoded profile per goal (weights across composition/lighting/expression/background/story, plus named composition rule tags).
- `features/goal_selection/providers/goal_providers.dart` — `selectedGoalProvider` (`StateProvider<PhotographyGoal?>`, starts null), `styleProfileProvider` (`Provider<GoalStyleProfile?>`, derives from `selectedGoalProvider`).
- `features/goal_selection/presentation/widgets/goal_card.dart` — `GoalCard(goal, isSelected, onTap)`, stateless, one distinct `Icons.*` per goal, accent border + accent icon/text color when selected.
- `features/goal_selection/presentation/screens/goal_selection_screen.dart` — `ConsumerWidget`, `GridView` (2 columns) of `GoalCard` for all `PhotographyGoal.values`, app bar showing `AppStrings.appName`, bottom `PrimaryButton("Bắt đầu chụp")` disabled until a goal is selected, navigates (push, not replace) to `CameraScreen`.

**Data flow**: user selection → `selectedGoalProvider` → consumed by `priority_engine`, `score_calculator`, `editorial_rules` throughout the rest of the pipeline.

## 2 & 3. Human & Scene Understanding (scene_analysis)

- `features/scene_analysis/domain/models/subject_profile.dart` — `SubjectProfile { bodyRatio?, faceAngleDegrees?, shoulderAngleDegrees?, eyesOpen?, expression?, timestamp }`, immutable, `copyWith(...)` (note: `copyWith` always sets `timestamp: DateTime.now()`, does not accept a timestamp override).
- `features/scene_analysis/domain/models/scene_profile.dart` — `SceneProfile { brightness, lightDirectionDegrees?, negativeSpaceScore, symmetryScore, backgroundClutterCount, depthEstimate? }`, immutable, `copyWith(...)`.
- `features/scene_analysis/services/pose_analyzer.dart` — `PoseAnalyzer.analyzePose(List<Pose>? mlkitPoseResult, SubjectProfile previous) -> SubjectProfile`. Computes `shoulderAngleDegrees` via `atan2` on left/right shoulder landmarks, `bodyRatio` as (nose-to-hip length)/(hip-to-ankle length).
- `features/scene_analysis/services/face_analyzer.dart` — `FaceAnalyzer.analyzeFace(List<Face>? mlkitFaceResult, SubjectProfile previous) -> SubjectProfile`. Derives `faceAngleDegrees` from `headEulerAngleY`, `eyesOpen` from left/right eye-open probabilities (>0.5 both), `expression` from `smilingProbability` bucketed into `smiling`/`neutral`/`serious`.
- `features/scene_analysis/services/light_analyzer.dart` — `LightAnalyzer.analyzeLight(CameraImage? cameraFrame, SceneProfile previous) -> SceneProfile`. Estimates `brightness` by sampling the Y-plane bytes of the camera frame and averaging (simple heuristic, not perceptual). Does not yet populate `lightDirectionDegrees`, `negativeSpaceScore`, `symmetryScore`, `backgroundClutterCount`, or `depthEstimate` — those remain whatever was previously set (initial defaults of 0.0/0).
- `features/scene_analysis/services/tracking_engine.dart` — see Tracking Engine section.
- `features/scene_analysis/providers/scene_providers.dart` — `subjectProfileProvider` / `sceneProfileProvider` (`StateProvider`s, defaulted), `poseAnalyzerProvider`/`faceAnalyzerProvider`/`lightAnalyzerProvider`/`trackingEngineProvider`, `targetSubjectProfileProvider` (derives an idealized target subject: angles at 0, `eyesOpen: true`, `expression: 'smiling'`), `trackingProgressProvider` (calls `TrackingEngine.trackingProgress(current, target)`), `sceneAnalysisListenerProvider` (listens to `MlKitService.analysisStream`, runs pose/face analyzers, smooths via `TrackingEngine.smoothSubject`, writes to `subjectProfileProvider`), `lightAnalysisListenerProvider` (alternate camera-image-stream-based light listener; in practice `camera_screen.dart` currently performs its own throttled light analysis inline rather than relying on this provider — see Data Flow notes).

## 4. Editorial Brain (editorial_rules + score_calculator)

- `features/voice_director/domain/editorial_rules.dart` — `RuleCondition { matches: bool Function(SubjectProfile, SceneProfile), directionPhrase: String, severity: int (1-10) }`. `rulesFor(PhotographyGoal) -> List<RuleCondition>` returns a shared "common" rule set (eyes closed, brightness too low/high, shoulder/face angle off, background clutter) plus 1-2 goal-specific rules per goal (e.g. LinkedIn adds a "smile" and "center yourself" rule; Editorial adds a negative-space rule). **This rule set is intentionally sparse per the 7-day scope cut — flagged as a gap, see Section 5.**
- `features/editorial_score/domain/score_calculator.dart` — `EditorialScore { overall: int (0-100), breakdown: Map<String,int> (composition, lighting, expression, background, story), nextSuggestion?: String }`. `calculateScore(SubjectProfile, SceneProfile, PhotographyGoal) -> EditorialScore` computes each breakdown category from heuristics (composition from negativeSpaceScore+symmetryScore, lighting from distance of brightness from 0.55 midpoint, expression from `expression`/`eyesOpen`, background from clutter count, story from whether `depthEstimate` is present), then weights them per-goal (internal `_weightsFor(PhotographyGoal)`, same weight values as `GoalStyleProfile.priorityWeights`) to compute `overall`, and sets `nextSuggestion` to the lowest-scoring category if it's below 60.

## 5 & 6. Photographer Brain / Direction Engine (priority_engine + voice_director UI)

- `features/voice_director/domain/priority_engine.dart` — `PriorityAction { phrase: String, severity: int, sourceLayer: String }`. `getNextAction(SubjectProfile, SceneProfile, PhotographyGoal) -> PriorityAction?` iterates `rulesFor(goal)`, finds all matching rules, returns the one with highest `severity` (or `null` if none match), tagging `sourceLayer: 'editorial_rules'`.
- `features/voice_director/providers/voice_providers.dart` — `nextActionProvider` (`Provider<PriorityAction?>`, derives from `subjectProfileProvider` + `sceneProfileProvider` + `selectedGoalProvider`, null if no goal selected), `voiceDirectorListenerProvider` (`Provider<void>`, listens to `nextActionProvider`, debounces 400ms, skips if phrase equals last spoken phrase, calls `TtsService.speak()`).
- In `camera_screen.dart`: the current `nextActionProvider` phrase is displayed as an accent-bordered pill/chip overlaid on the camera preview (visual echo of the TTS speech, not a replacement).

## 7. Tracking Engine

- `features/scene_analysis/services/tracking_engine.dart` — `TrackingEngine` class with:
  - `const double _emaAlpha = 0.3` (named constant, module-level).
  - `const int _debounceFrames = 2` (named constant, module-level).
  - `smoothSubject(SubjectProfile raw, SubjectProfile previous) -> SubjectProfile` — applies EMA (`previous + alpha*(raw-previous)`) to `bodyRatio`, `faceAngleDegrees`, `shoulderAngleDegrees`; applies 2-frame-consistency debounce (internal streak counters `_pendingEyesOpen`/`_eyesOpenStreak`, `_pendingExpression`/`_expressionStreak`) to `eyesOpen` and `expression`.
  - `smoothScene(SceneProfile raw, SceneProfile previous) -> SceneProfile` — EMA on `brightness`, `lightDirectionDegrees`, `negativeSpaceScore`, `symmetryScore`, `depthEstimate`; debounce (via `_pendingClutterCount`/`_clutterStreak`) on `backgroundClutterCount`.
  - `trackingProgress(SubjectProfile current, SubjectProfile target) -> double (0.0-1.0)` — averages normalized closeness across whichever of `shoulderAngleDegrees`, `faceAngleDegrees`, `bodyRatio`, `eyesOpen`, `expression` are non-null on both sides (angle diffs normalized against 45°, `bodyRatio` diff against 1.0, boolean/string fields scored 1.0/0.0 for match/mismatch); returns 0.0 if no comparable fields exist.
  - **Note**: `TrackingEngine` instances hold internal debounce state (`_pending*`/`*Streak` fields) — a single instance must be reused across frames for a given session, not recreated per frame. Both `scene_providers.dart` (via `trackingEngineProvider`) and `camera_screen.dart` (via a local `_trackingEngine` field) currently hold their own instances — this is a minor duplication worth resolving (see Section 5).
- `shared/widgets/target_zone_overlay.dart` — `TargetZoneOverlay(aligned: bool, trackingProgress: double, zoneRect: Rect?)`, now a `StatefulWidget` (`_TargetZoneOverlayState` with `SingleTickerProviderStateMixin`). Uses a `CustomPainter` (`_TargetZonePainter`) whose stroke width, stroke opacity, and fill opacity all scale with `trackingProgress`. When `trackingProgress >= 0.95` (`_readyThreshold` constant), an `AnimationController` pulses the zone's scale (1.0 → 1.06 loop) as a "ready to capture" cue.

## 8. Capture Engine (capture feature)

- `features/capture/services/auto_capture_service.dart` — `AutoCaptureService.shouldCapture(SubjectProfile subject, SceneProfile scene, double trackingProgress) -> bool`. Gates on (AND, all must pass): `eyesOpen != false`, `scene.brightness >= 0.2`, `shoulderAngleDegrees` within ±15° (or null), `faceAngleDegrees` within ±20° (or null), `backgroundClutterCount <= 5`, **`trackingProgress >= _minTrackingProgress (0.9)`** (named constant), and a 1500ms cooldown since `_lastCapture`. `triggerCapture()` records `_lastCapture = DateTime.now()`.
- `features/capture/providers/capture_providers.dart` — `autoCaptureServiceProvider`, `shouldCaptureProvider` (`Provider<bool>`, reads subject/scene/trackingProgress and calls `shouldCapture`), `autoCaptureProvider` (`Provider<void>`, listens to `shouldCaptureProvider`, on `true` triggers capture, computes `EditorialScore` via `calculateScore`, builds a `Shot`, writes it to `capturedShotProvider`), `capturedShotProvider` (`StateProvider<Shot?>`).
- `camera_screen.dart` also exposes a manual capture path: bottom `PrimaryButton("Capture")` calling `_performCapture()`, which calls `CameraService.capture()` directly, builds a `Shot` (hardcoded `shotType: 'hero'`), and adds it to `albumStateProvider` — independent of the auto-capture gate, per the explicit requirement that manual capture must always be available.
- **Note**: there are currently two separate places that build a `Shot` and add it to the album — the auto-capture path (via `capturedShotProvider` + a `ref.listen` in `camera_screen.dart`) and the manual-capture path (`_performCapture()` inline). Both work but duplicate shot-construction logic slightly (see Section 5).

## 9. Quality Engine (editorial_score)

Covered under Section 4 above (`score_calculator.dart`). Flagged separately here because it is conceptually the "Quality Engine" layer in the 11-layer architecture. Current gap: scoring heuristics have not been validated against real captured photos/real device sensor data — brightness, negative space, symmetry, and clutter inputs are still shallow heuristics or unpopulated defaults from `LightAnalyzer`.

## 10. Album Director (album feature)

- `features/album/domain/models/shot.dart` — `Shot { id, score: EditorialScore, timestamp, shotType (hero/half_body/walking/close_up/detail), imagePath? }`.
- `features/album/domain/models/album_state.dart` — `AlbumState { shots: List<Shot> }`. `addShot(Shot) -> AlbumState` (returns new state, append). `diversityScore() -> double` (distinct shot types / total known shot types, 5). `suggestNextShotType() -> String` (returns the shot type with the lowest count so far).
- `features/album/providers/album_providers.dart` — `AlbumNotifier extends StateNotifier<AlbumState>` with `addShot`, `suggestNextShotType`, `diversityScore` methods; exposed via `albumStateProvider` (`StateNotifierProvider<AlbumNotifier, AlbumState>`).
- `features/album/presentation/screens/album_screen.dart` — `AlbumScreen` (ConsumerWidget): header shows `diversityScore()` as a percentage and `suggestNextShotType()` as a hint; `GridView` of `_ShotTile` (image via `Image.file(shot.imagePath)` or surface-colored placeholder, shot type label chip, `ScoreBadge` in corner); empty state with message + `PrimaryButton("Quay lại chụp")` that pops back; tapping a tile opens `ShotDetailScreen` (full image + `ScoreBadge` per category in `shot.score.breakdown`).
- `features/camera_session/presentation/widgets/album_button.dart` — `AlbumButton` (ConsumerWidget), accent-bordered pill showing live `albumStateProvider.shots.length`, navigates to `AlbumScreen` on tap. Displayed top-right in `camera_screen.dart`.

## 11. Memory Layer (memory_service)

Covered under Infrastructure above (`core/services/memory_service.dart`). Write-side is fully implemented (`saveHabit`, `getHabit`, `recordCorrection`, `getFrequentCorrections`). **No read-side integration exists yet** — nothing in `priority_engine.dart` or `editorial_rules.dart` currently reads from `MemoryService` to bias `getNextAction()` output. This was explicitly left as "a hook, not required in this batch" per the original architecture spec and remains unimplemented.

# 4. Data Flow Diagram (as text/ASCII)

```
```
PhotographyGoal (goal_selection_screen, user tap)
    │
    ▼
selectedGoalProvider ────────────────────────────────────────┐
    │                                                        │
    ▼                                                        │
CameraService (camera_service.dart) — raw CameraImage frames │
    │                                                        │
    ├──► LightAnalyzer.analyzeLight() ──► raw SceneProfile   │
    │                                                        │
    └──► MlKitService.processImage() (pose, face, seg.)      │
              │                                              │
              ▼                                              │
       analysisStream (MlKitAnalysisResult)                  │
              │                                               
     ┌────────┴────────┐                                     │
     ▼                 ▼                                     │
PoseAnalyzer        FaceAnalyzer                              │
.analyzePose()      .analyzeFace()                            │
     └────────┬────────┘                                     │
              ▼                                               
      raw SubjectProfile                                     │
              │                                               
              ▼                                               
TrackingEngine.smoothSubject()      TrackingEngine.smoothScene()
(EMA α=0.3 + 2-frame debounce, both branches)
              │                                    │
              ▼                                    ▼
   subjectProfileProvider              sceneProfileProvider
              │                                    │
              └─────────────────┬──────────────────┘
                                 │
                ┌────────────────┴────────────────┐
                ▼                                  ▼
  priority_engine.getNextAction()      AutoCaptureService.shouldCapture()
  (subject, scene, goal)               (subject, scene,
                │                       trackingProgress >= 0.9 required)
                ▼                                  │
          PriorityAction?                          ▼
                │                          triggerCapture()
                ▼                                  │
      TtsService.speak()                           ▼
      (debounced, dedup'd)               CameraService.capture()
      + on-screen phrase chip                      ▲
                                    (manual capture button bypasses
                                     AutoCaptureService entirely,
                                     calls capture() directly)
                                                    │
                                                    ▼
                                    Shot (id, timestamp, shotType, imagePath)
                                                    │
                                                    ▼
                                    score_calculator.calculateScore()
                                    (subject, scene, goal)
                                                    │
                                                    ▼
                                    Shot.score = EditorialScore
                                                    │
                                                    ▼
                                    AlbumState.addShot() (via AlbumNotifier)
                                                    │
                                                    ▼
                                    AlbumState.suggestNextShotType()
                                    AlbumState.diversityScore()
                                    (surfaced in album_screen.dart,
                                     not yet fed back into capture loop)
```
MemoryService.recordCorrection() / saveHabit()
— currently has no caller anywhere in the pipeline above.
Intended future hook: priority_engine.getNextAction() should read
MemoryService.getFrequentCorrections() / getHabit() to bias which
RuleCondition is surfaced, but this read-side wiring does not exist yet.

trackingProgressProvider = TrackingEngine.trackingProgress(
subjectProfileProvider, targetSubjectProfileProvider)
— feeds both TargetZoneOverlay (visual pulse/fill animation) and
AutoCaptureService.shouldCapture() (capture gate).
```

# 5. Known Gaps / Not Yet Done

- **Real-device testing has never been performed.** No measurements exist for FPS under the current 10-15fps throttle, battery drain from continuous camera streaming + ML Kit inference, or the actual runtime behavior of the permission request flow (camera/microphone) on a physical Android or iOS device. Everything has been validated only by reasoning about compiled code.
- **`editorial_rules.dart` content is likely too sparse to feel like a real photographer.** Each goal currently has ~6 common rules + 1-2 goal-specific rules. A real photographer gives much more varied, context-sensitive direction; the current rule set may feel repetitive or robotic in practice.
- **`MemoryService` habit data is not yet consumed anywhere.** `recordCorrection`/`saveHabit`/`getFrequentCorrections`/`getHabit` are fully implemented on the write side but nothing calls them from `priority_engine.dart`, so there is no personalization loop — the app currently gives the same direction to every user regardless of session history.
- **Only 2 (arguably 6, but shallow) photography styles are implemented** per the 7-day scope cut — all 6 `PhotographyGoal` enum values exist and have `GoalStyleProfile`/rule entries, but the content depth per style is minimal.
- **No Java/Spring backend exists.** All persistence is local (Hive/shared_preferences); there is no sync, no multi-device history, no server-side processing.
- **No GenAI on-device fallback exists.** There is no generative model integrated for scenarios where rule-based `editorial_rules.dart` fails to produce a confident direction.
- **No unit/widget tests exist beyond `auto_capture_service_test.dart`.** `priority_engine.dart`, `score_calculator.dart`, `tracking_engine.dart`, and all UI screens have no automated test coverage. (Note: the task description referenced an existing "priority_engine" test file, but no such test file has actually been created in this project's history — only `auto_capture_service_test.dart` exists.)
- **Minor architectural duplication**: `TrackingEngine` is instantiated separately in both `scene_providers.dart` (`trackingEngineProvider`) and `camera_screen.dart` (local `_trackingEngine` field), and `Shot` construction logic is duplicated between the auto-capture path (`capture_providers.dart`) and the manual-capture path (`camera_screen.dart._performCapture()`). Both work correctly today but should be consolidated.
- **`LightAnalyzer` only populates `brightness`.** `lightDirectionDegrees`, `negativeSpaceScore`, `symmetryScore`, `backgroundClutterCount`, and `depthEstimate` are never computed from real camera/scene data anywhere in the current codebase — they remain at their `SceneProfile` provider defaults (0.0 / 0) unless manually set, meaning `score_calculator.dart` and `editorial_rules.dart` conditions relying on those fields are effectively inert in real usage.

# 6. Commit History Summary

| Commit subject | What it added |
|---|---|
| feat: scaffold cuemera project with core theming and services | Feature-first folder structure; AppColors (dark/light ThemeExtension); AppTheme; AppSpacing; AppTypography; ThemePreferenceService; CameraService; MlKitService; TtsService; MemoryService; service_locator; main.dart; shared widgets (PrimaryButton, ScoreBadge, TargetZoneOverlay) |
| feat: implement core AI decision-making architecture | PhotographyGoal + GoalStyleProfile; SubjectProfile + SceneProfile; PoseAnalyzer, FaceAnalyzer, LightAnalyzer; editorial_rules + priority_engine; AutoCaptureService; EditorialScore + score_calculator; Shot + AlbumState; MemoryService habit/correction methods |
| feat: wire Riverpod providers connecting AI architecture layers | goal_providers; scene_providers (camera/ML Kit stream wiring); voice_providers (nextActionProvider + debounced TTS listener); capture_providers; score_providers; album_providers (AlbumNotifier) |
| feat: add splash screen as initial app route | SplashScreen with Hive/service_locator/theme/permission init flow; logo fallback wordmark; error/retry state; appTagline string; permission_handler dependency; assets/images/ in pubspec; main.dart updated to start at SplashScreen |
| feat: build goal_selection UI | GoalCard widget; GoalSelectionScreen (grid + app bar + bottom button); placeholder CameraScreen |
| fix: resolve InputImageRotation compile error in ML Kit integration | google_mlkit_commons import + dependency; corrected InputImage.fromBytes/InputImageMetadata usage in ml_kit_service.dart and camera_screen.dart |
| fix: add missing AppSpacing.xl2 token | Added `xl2 (40.0)` to app_spacing.dart |
| feat: complete end-to-end camera capture loop | CameraService.capture(); TargetZoneOverlay + phrase chip + ScoreBadge layered on CameraPreview; sceneAnalysisListenerProvider/voiceDirectorListenerProvider watched in camera_screen; autoCaptureProvider/capturedShotProvider wiring; capture flash animation; manual Capture button |
| feat: add album feature UI | Shot.imagePath; AlbumScreen (grid, diversity score, next-shot hint); empty state; ShotDetailScreen with per-category breakdown; AlbumButton entry point in camera_screen |
| feat: add tracking engine for smoothed subject/scene state | TrackingEngine (EMA smoothing alpha 0.3, 2-frame debounce, trackingProgress()); wired into scene_providers.dart and camera_screen.dart frame-update logic |
| feat: wire trackingProgress into Target Zone overlay | trackingProgressProvider + targetSubjectProfileProvider in scene_providers.dart; TargetZoneOverlay upgraded to StatefulWidget with progress-driven stroke/fill animation and ready-to-capture pulse; fix for undefined sceneProfileProvider/sceneAnalysisListenerProvider (stale file restoration) |
| feat: gate auto-capture on tracking progress | AutoCaptureService.shouldCapture() trackingProgress param + _minTrackingProgress (0.9) threshold; autoCaptureProvider updated to pass trackingProgressProvider; auto_capture_service_test.dart with threshold-boundary test cases |

# 7. Suggested Next Steps

1. **Perform real-device testing.** Validate actual FPS under the current throttle settings, battery drain during extended camera+ML Kit sessions, and the real-world behavior of the camera/microphone permission request flow on both Android and iOS hardware. This is the single largest unvalidated risk in the project.
2. **Enrich `editorial_rules.dart` content.** Expand the rule set per `PhotographyGoal` so direction feels varied and genuinely photographer-like rather than repetitive; consider adding more nuanced conditions (e.g. rule-of-thirds positioning, more expression states, pose variety prompts) once real-device pose/face data confirms what signals are reliably available.
3. **Wire `MemoryService` into `priority_engine.dart` for personalization.** Implement the read side: have `getNextAction()` (or a wrapper around it) consult `MemoryService.getFrequentCorrections()`/`getHabit()` to bias which `RuleCondition` is surfaced, closing the loop that was left as a placeholder hook.
4. **Only after the above three are validated**, expand scope: add more photography styles/rule depth, consider a Java/Spring backend for sync or heavier processing, and evaluate whether a GenAI on-device fallback is needed for cases where rule-based direction is insufficient.
```