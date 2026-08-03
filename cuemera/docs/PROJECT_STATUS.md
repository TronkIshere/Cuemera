```markdown
# 1. Overview

Cuemera is an AI fashion photographer app built in Flutter. Its core philosophy is to direct the user like a real photographer would — giving live, spoken and visual cues ("square your shoulders", "find more light", "give a warm smile") — rather than asking the user to copy a static reference pose. The system watches the user through the phone's camera in real time, understands their body, face, and the scene around them, and produces a single, prioritized, real-time instruction at any given moment, then automatically (or manually) captures the shot when everything aligns, scores it editorially, and organizes it into an album that tracks shot diversity across a session.

The current architecture approach is 100% on-device edge AI in Flutter: camera capture (`camera`), pose/face/segmentation analysis (`google_mlkit_*` packages), local smoothing/decision logic in pure Dart, local persistence via Hive, and text-to-speech via `flutter_tts`. State is managed with Riverpod throughout. An optional Java/Spring backend has been discussed as a future layer (e.g. for cloud sync, heavier ML, or multi-device history) but has not been started — everything today runs entirely on-device.

The app's entry navigation was simplified: `goal_selection_screen.dart` is no longer a 6-goal picker grid — it is now the app's minimal home screen (Shoot / Album / Settings), and `PhotographyGoal` selection moved into a compact in-header picker on `camera_screen.dart`. The home screen's card widget was later extracted into its own file (`goal_card.dart`, public `EditorialMenuCard`) and went through several rounds of layout/performance iteration (bento layout tried and reverted, ghost page-number tried and replaced with an outline-icon watermark, BackdropFilter/shadow performance fix). A `camera_screen.dart` dispose-crash fix and top-UI redesign (SafeArea fixes, bottom-sheet goal picker, new top navbar) were prompted and **are now confirmed applied against actual file content** — no longer pending. This session also: fixed a real live-preview blur bug (dedicated high-res `previewController` in `camera_service.dart`, separate from the medium-res ML-Kit-analysis controller), added pinch-to-zoom and tap-to-focus on the live preview, refactored `camera_screen.dart` by extracting 5 inline widgets into `features/camera_session/presentation/widgets/` (`CameraPreviewLayer`, `FocusRing`, `CameraTopNavBar`, `GoalPill`, `PhraseChip`), and wired in the previously-paused `DebugPerfOverlay` (`kDebugMode`-gated FPS + auto-capture condition breakdown). **The large accumulated commit covering all of the above (through the album delete/gallery-save features) has now been pushed.** See Section 1 and Section 6 below for details.

# 2. Completion Summary

| Layer/Area | Status | % Complete | Notes |
|---|---|---|---|
| Infrastructure (core/shared/branding) | Done | 100% | AppColors (ThemeExtension, dark+light), AppTheme, AppSpacing, AppTypography, all core services, service_locator (MemoryService registration bug fixed — see Section 5), pubspec fully wired |
| Splash Screen | Done | 100% | Full init flow (Hive, locator, theme, permissions, ML Kit warm-up), logo fallback (single-line, non-wrapping wordmark; no real `logo.png` asset exists yet — see Section 5), retry-on-error |
| Settings (theme toggle) | Done | 100% | SettingsScreen with Dark Mode Switch bound to themeModeProvider/ThemePreferenceService.setDarkMode(); entry point is now a home-screen card (see Home Screen section below) instead of an app-bar gear icon; manual toggle only, no system-theme following |
| Home Screen (repurposed goal_selection) | Done, refined this session | 100% | `goal_selection_screen.dart` repurposed in place as the app's home screen: custom floating header (wordmark + tagline + gold rule, no AppBar) plus 3 layered glass-panel cards (Shoot/Album/Settings) navigating directly to CameraScreen/AlbumScreen/SettingsScreen, now stacked in a single full-width vertical column with identical sizing (a side-by-side bento layout and a hero-sized Shoot card were both tried and reverted). Card widget extracted from the screen file into `goal_card.dart` as public `EditorialMenuCard`, replacing old dead `GoalCard`. Right-side decorative zone settled on a stroked outline-icon watermark (an oversized ghost page-number treatment was tried and dropped). Overflow bugs fixed via spacing, not height. Performance pass reduced BackdropFilter blur and shadow layering to fix reported lag |
| Goal Selection (now in-camera) | Done, redesign confirmed applied | 100% | `PhotographyGoal` selection now lives in `GoalPill` (extracted widget), tapped to open a modal bottom sheet list — the old horizontal chip-row picker was replaced. Reads/writes `selectedGoalProvider` directly. `photography_goal.dart`/`goal_providers.dart` unchanged and still the single source of truth. `goal_card.dart` no longer holds the unused `GoalCard` — it was overwritten with the public `EditorialMenuCard` used by the home screen. **Confirmed applied**: the tappable-pill + bottom-sheet redesign, plus a new `CameraTopNavBar` (difficulty/settings, mode selector, sample/reference photo picker — buttons render but callbacks are still empty stubs) and `SafeArea` fixes so the Capture button and top content don't collide with Android system UI |
| 2. Human Understanding (scene_analysis: subject) | Near done | ~85% | SubjectProfile model, PoseAnalyzer, FaceAnalyzer implemented and wired; not yet validated on real device |
| 3. Scene Understanding (scene_analysis: scene) | Near done | ~88% | SceneProfile model; LightAnalyzer now populates brightness, lightDirectionDegrees, negativeSpaceScore, symmetryScore, and backgroundClutterCount via segmentation-mask/frame heuristics (depthEstimate intentionally left as a documented no-op); heuristics not yet validated on real device |
| 4. Editorial Brain (editorial_rules + score_calculator) | Near done | ~90% | Rule sets exist per goal but content is sparse (few rules per goal), intentionally left as-is pending real-device validation; score_calculator fully implemented with weighted breakdown |
| 5. Photographer Brain / Direction logic (priority_engine) | Near done | ~90% | getNextAction() implemented, selects highest-severity matching rule; now covered by priority_engine_test.dart; not yet personalized via memory |
| 6. Direction Engine (voice_director UI/TTS wiring) | Near done | ~90% | nextActionProvider + debounced TTS listener + on-screen phrase chip implemented and wired in camera_screen |
| 7. Tracking Engine (tracking_engine.dart) | Near done | ~87% | EMA smoothing + debounce implemented; trackingProgress() implemented and wired into TargetZoneOverlay and auto-capture gating; single shared instance now consumed via trackingEngineProvider (duplicate local instantiation removed) |
| 8. Capture Engine (capture feature) | Near done | ~88% | AutoCaptureService with multi-condition gate (eyes, brightness, angles, clutter, trackingProgress >= 0.9, cooldown) + manual capture fallback button; Shot construction consolidated into buildShotFromCapture() shared by both auto and manual paths |
| 9. Quality Engine (editorial_score) | Partial | ~70% | calculateScore() implemented with per-goal weights and 5-category breakdown; not tuned/validated against real captured photos |
| 10. Album Director (album feature) | Near done, extended this session | ~90% | AlbumState, Shot, album_screen grid, diversity score, next-shot-type suggestion, shot detail view with per-category ScoreBadge breakdown; reachable directly from the home screen's "Album" card. **This session**: added `removeShot(shotId)` on `AlbumState`/`AlbumNotifier` (filters by id + deletes the app-private image file from disk) with delete UI (long-press confirm dialog and/or `ShotDetailScreen` delete button) in `album_screen.dart`; captured photos now also saved to the public Gallery via the `gal` package in `camera_service.dart` (`Gal.putImage()`), gated behind a `Gal.requestAccess()` call and a `READ_MEDIA_IMAGES`/legacy-storage permission added to `AndroidManifest.xml`, with failures surfaced via `lastGallerySaveError` (previously silently swallowed) rather than failing the capture/album-add flow. AlbumState still not persisted to Hive — restart still clears the in-memory album (file-on-disk gallery copies persist, but the in-app album list does not) |
| 11. Memory Layer (memory_service) | Partial | ~60% | Hive-backed habit/correction storage methods implemented (saveHabit, getHabit, recordCorrection, getFrequentCorrections); not yet consumed anywhere (no read-side integration into priority_engine). Registration bug in `service_locator.dart` (splash crashed with "GetIt: MemoryService is not registered") is now fixed — see Section 5 |
| Ambient Background (app_background.dart) | Done | 100% | Redesigned from a simple gradient + soft-glow-circles into a layered, asymmetric editorial fashion-studio composition (off-canvas key-light gradient, softbox glow, contact-sheet/crop-frame stroked rectangles, alignment block, frame-corner accent), portrait/landscape-aware. Structural contract unchanged (AppBackground(child), RepaintBoundary, canvas-fraction sizing, shouldRepaint on Size/Brightness only, light mode = plain Container). Applied to splash, home, and settings screens only |
| Documentation (PROJECT_STATUS.md, README.md, AI_SESSION_CONTEXT.md) | Done | 100% | Full completion tracking, public-facing overview, and operational lookup reference for new AI sessions all maintained and current |
| Real-device testing | Not started | 0% | No FPS, battery, or on-device permission-flow validation has been performed at any point in this project |

**Overall estimated completion: ~68-72%**

# 3. What Has Been Built (Detailed)

## Infrastructure (core/shared/branding)

- `core/constants/app_colors.dart` — `AppColors` as a `ThemeExtension<AppColors>` with two static const instances, `AppColors.dark` and `AppColors.light`, each defining `background`, `surface`, `text`, `textMuted`, `accent`, `targetZone`, `success`, `warning`. Includes `copyWith` and `lerp` overrides required by `ThemeExtension`.
- `core/constants/app_spacing.dart` — `AppSpacing` abstract class with double constants: `xs (4)`, `sm (8)`, `md (16)`, `lg (24)`, `xl (32)`, `xl2 (40)`, `xxl (48)`.
- `core/constants/app_typography.dart` — `AppTypography` with static `TextStyle` builder methods (`heading1`, `heading2`, `body`, `bodyMuted`, `caption`, `score`), each taking an `AppColors` instance and returning a colored `TextStyle`. Also exposes `buildTextTheme(AppColors)` which builds a full Flutter `TextTheme`.
- `core/constants/app_strings.dart` — `AppStrings` with `appName`, `appTagline`, and various UI copy strings (permission, capture, album, error strings). Now also includes home-screen strings: `homeShootLabel`, `homeAlbumLabel`, `homeSettingsLabel`, `homeTagline`, `homeShootSubtitle`, `homeAlbumSubtitle`, `homeSettingsSubtitle`, `homeTapToBegin`. `goalSelectionTitle`/`goalSelectionSubtitle` remain defined but are likely unused now that `goal_selection_screen.dart` no longer renders a goal-picker grid.
- `core/theme/app_theme.dart` — `AppTheme` with `darkTheme` / `lightTheme` getters, both built via a shared `_build(AppColors, Brightness)` helper that registers the `AppColors` extension and wires `AppSpacing`/`AppTypography` into `ColorScheme`, `AppBarTheme`, `CardTheme`, `ElevatedButtonTheme`, and `TextTheme`.
- `core/services/camera_service.dart` — `CameraService` wraps `CameraController` lifecycle: `init()`, `switchLens()`, `startImageStream(onImage)`, `stopImageStream()`, `dispose()`, and `capture()` (returns `Future<String?>` image file path, stopping the image stream first). **This session**: added a second, preview-only `_previewController` (`ResolutionPreset.high`) via `initPreviewController()`, to fix a real bug where the live preview looked visibly blurry because it was rendering from the `ResolutionPreset.medium` analysis controller stretched full-screen by `BoxFit.cover`. The `medium` controller still exclusively drives `startImageStream`/ML Kit analysis — unchanged, kept at `medium` deliberately for frame-processing performance. `initPreviewController()` also caches `_minZoom`/`_maxZoom` via `getMinZoomLevel()`/`getMaxZoomLevel()`, exposed as `minZoom`/`maxZoom` getters, consumed by `camera_screen.dart`'s pinch-to-zoom handler. `dispose()` now disposes both `_controller` and `_previewController`. Exposed via `cameraServiceProvider` (Riverpod `Provider`).
- `core/services/ml_kit_service.dart` — `MlKitService` wraps `PoseDetector`, `FaceDetector`, `SelfieSegmenter` from `google_mlkit_*` packages behind a single `processImage(CameraImage, CameraDescription, InputImageRotation)` method. Converts `CameraImage` to `InputImage` via `InputImage.fromBytes` + `InputImageMetadata` (using `google_mlkit_commons`). Publishes `MlKitAnalysisResult` (poses, faces, segmentationMask) on a broadcast `analysisStream`. Exposed via `mlKitServiceProvider`.
- `core/services/tts_service.dart` — `TtsService` wraps `flutter_tts` tuned for short realtime phrases (rate 0.55, dedupes identical consecutive phrases via `_lastPhrase`). Exposes `speak(String)`, `stop()`. Exposed via `ttsServiceProvider`.
- `core/services/memory_service.dart` — `MemoryService` wraps two Hive boxes (`shooting_habits`, `album_state`). Methods: `getHabit<T>(key, {defaultValue})`, `setHabit<T>(key, value)`, `saveHabit(key, value)`, `recordCorrection(String correctionType)` (increments a count in a `corrections` map inside the habits box), `getFrequentCorrections()` (returns `Map<String, int>`), plus album-box `getAlbumValue`/`setAlbumValue` and `clearHabits`/`clearAlbum`. Exposed via `memoryServiceProvider`.
- `core/services/theme_preference_service.dart` — `ThemePreferenceService extends StateNotifier<ThemeMode>`, persisted via `shared_preferences` under key `dark_mode_enabled`, defaults to `ThemeMode.dark`. Exposes `isDarkMode`, `load()`, `setDarkMode(bool)`. Exposed via `themeModeProvider` (`StateNotifierProvider`). Fully wired to UI via `SettingsScreen`.
- `core/di/service_locator.dart` — GetIt-based `sl` locator. `setupLocator()` registers `CameraService`, `MlKitService`, `TtsService`, and `MemoryService` as lazy singletons, then explicitly `await`s `sl<MemoryService>().init()` before returning. This fixes a previously-shipped bug where `MemoryService` was never registered, causing splash to crash with `Bad state: GetIt: Object/factory with type MemoryService is not registered inside GetIt.` — see Section 5/6.
- `shared/widgets/app_background.dart` — `AppBackground(child)`, a `Stack` with a `CustomPainter` (`_BackgroundPainter`) layer behind `child`, wrapped in `RepaintBoundary`. Dark mode paints an asymmetric editorial fashion-studio composition, all positions/sizes computed as fractions of the canvas `Size` (no fixed pixel values): an off-canvas key-light gradient (simulated light origin near the top-left, sweeping through 4 charcoal color stops toward the bottom-right), a large heavily-blurred accent-gold radial "softbox" glow, a smaller surface-toned counter-balance glow, a large very-low-opacity filled circle ("studio softbox echo"), two rotated thin-stroked rectangle outlines evoking overlapping contact-sheet/crop frames, a rotated filled "matte backdrop strip" rectangle, a small rotated filled "alignment" square, and an open two-line corner-bracket accent — all at 2-8% opacity, layout adapting between portrait and landscape by reading the canvas `Size` at paint time (not `MediaQuery`). The central 40-50% of the canvas is kept free of shape overlap so foreground UI stays legible. `shouldRepaint()` still only compares `oldDelegate`'s `Size`/`Brightness`. Light mode still skips the painter entirely and returns a plain `Container` using the background token.
- `shared/widgets/primary_button.dart` — `PrimaryButton(label, onPressed, isLoading, enabled)`, accent-colored, disables on `isLoading || !enabled`, shows a spinner when loading.
- `shared/widgets/score_badge.dart` — `ScoreBadge(score, size)`, circular badge color-coded: `>=80` success, `>=50` accent, else warning.
- `shared/widgets/target_zone_overlay.dart` — see Tracking Engine section below.
- `pubspec.yaml` — dependencies: `camera`, `google_mlkit_pose_detection`, `google_mlkit_face_detection`, `google_mlkit_selfie_segmentation`, `google_mlkit_commons`, `flutter_tts`, `flutter_riverpod`, `hive`, `hive_flutter`, `path_provider`, `shared_preferences`, `permission_handler`, `get_it`, `cupertino_icons`; dev: `flutter_lints`, `hive_generator`, `build_runner`. Assets: `assets/images/` declared, but **no `logo.png` file or explicit asset entry currently exists** — `splash_screen.dart` relies on its `Image.asset` `errorBuilder` fallback to render the text wordmark instead. Treat as a known gap, not a runtime bug (see Section 5).

## Splash Screen

- `features/splash/presentation/screens/splash_screen.dart` — `SplashScreen` (ConsumerWidget) + `splashInitProvider` (`FutureProvider.autoDispose<void>`) that sequentially: runs `setupLocator()` (registers services incl. `MemoryService`, awaits its Hive init), awaits `ThemePreferenceService.load()`, requests camera + microphone permissions via `permission_handler` (throws if either denied), and instantiates `MlKitService` (warm-up). UI: centered `Image.asset('assets/images/logo.png')` with `errorBuilder` fallback to a `FittedBox`-wrapped, single-line, non-wrapping `Text(AppStrings.appName)` using `AppTypography.heading1` (fixes a prior bug where "Cuemera" could wrap onto two lines on narrower devices), tagline below via `AppTypography.bodyMuted`, accent-colored `CircularProgressIndicator` while loading, error state renders message + `PrimaryButton("Retry")` that calls `ref.invalidate(splashInitProvider)`. On success, `pushReplacement`s to `GoalSelectionScreen` (now the home screen).

## Settings (theme toggle)

- `features/settings/presentation/screens/settings_screen.dart` — `SettingsScreen` (ConsumerWidget). Single tile: "Dark Mode" label + `Switch` bound to `themeModeProvider` (`value: themeMode == ThemeMode.dark`, `onChanged` calls `ref.read(themeModeProvider.notifier).setDarkMode(value)`). Styled using `AppColors`/`AppSpacing`/`AppTypography` tokens consistent with other screens. Intentionally minimal — no other settings yet, and no `ThemeMode.system`/auto-detection (manual persisted toggle only, by design). Wrapped in `AppBackground`.
- Reached via the home screen's "Settings" card (`goal_selection_screen.dart`) — the old app-bar gear `IconButton` was removed since it's now a dedicated card.

## Home Screen (repurposed goal_selection_screen.dart)

- `features/goal_selection/presentation/screens/goal_selection_screen.dart` is no longer a `PhotographyGoal` picker. It is the app's home screen, reached from splash and shown as the first real UI. Structure: `Scaffold` with no `AppBar` (removed entirely so `AppBackground` shows through uninterrupted behind a floating header), body wrapped in `AppBackground` + `SafeArea` + scrollable `Column`.
  - `_HomeHeader` — custom wordmark/tagline block: a thin-stroke gold "aperture ring" `CustomPainter` monogram beside a bold, tightly-tracked "Cuemera" wordmark, an all-caps muted tagline (`AppStrings.homeTagline`), and a short gold horizontal rule beneath.
  - `EditorialMenuCard` (public class, `features/goal_selection/presentation/widgets/goal_card.dart`) — extracted this session out of `goal_selection_screen.dart` (was a private `_EditorialMenuCard` defined inline) and now overwrites the old dead `GoalCard` in `goal_card.dart`. A reusable stateful, layered "glass panel" card used for all 3 menu entries, redesigned iteratively this session:
    - Internal composition is a two-zone `Row`: left zone (icon badge, title, subtitle, thin gold divider, "Tap to begin" + arrow footer), right zone (purely decorative — a low-opacity `CustomPaint` atmosphere of a stroked frame/offset square/radial glow, plus a large stroked outline-icon watermark at ~25-35% opacity). An earlier oversized "01"/"02"/"03" ghost-page-number treatment for the right zone was tried and removed for looking too faint/unclear.
    - Layout was briefly changed to a side-by-side two-column ("bento") arrangement for Album/Settings under a full-width Shoot hero, then explicitly reverted back to a single full-width vertical stack per user preference.
    - Card sizing: all 3 cards (Shoot/Album/Settings) now use the same height and the same `isPrimary` value — the earlier size/opacity distinction that made Shoot a bigger "hero" card was removed so all 3 read as equal-weight.
    - Two rounds of bottom-overflow bug fixes ("BOTTOM OVERFLOWED BY N PIXELS" on Album/Settings) were resolved by tightening internal vertical spacing/padding rather than increasing card height.
    - Performance fix: `BackdropFilter` blur reduced from sigma 18 to ~7, the two stacked `BoxShadow`s collapsed into one, and the whole card wrapped in `RepaintBoundary`, after the user reported noticeable lag on `flutter run` on a mid-high-end Android device.
    - Minor spacing/typography polish requests (gap above "Tap to begin", divider-to-subtitle spacing) were also applied.
    - **Shoot**'s `onTap`: if `selectedGoalProvider` is currently `null`, sets it to `PhotographyGoal.values.first`, then pushes `CameraScreen`. **Album**'s `onTap` pushes `AlbumScreen` directly. **Settings**'s `onTap` pushes `SettingsScreen` directly — all three preserved unchanged throughout the redesign.
- `features/goal_selection/domain/models/photography_goal.dart` and `features/goal_selection/providers/goal_providers.dart` are unchanged — `PhotographyGoal`, `GoalStyleProfile`, `getStyleProfile()`, `selectedGoalProvider`, `styleProfileProvider` all still exist exactly as before and remain the single source of truth for goal state.

**Data flow**: home screen "Shoot" card ensures `selectedGoalProvider` is non-null (defaulting if needed) → `camera_screen.dart`'s in-header picker reads/writes `selectedGoalProvider` directly for the rest of the session → consumed by `priority_engine`, `score_calculator`, `editorial_rules` throughout the rest of the pipeline.

## 2 & 3. Human & Scene Understanding (scene_analysis)

- `features/scene_analysis/domain/models/subject_profile.dart` — `SubjectProfile { bodyRatio?, faceAngleDegrees?, shoulderAngleDegrees?, eyesOpen?, expression?, timestamp }`, immutable, `copyWith(...)` (note: `copyWith` always sets `timestamp: DateTime.now()`, does not accept a timestamp override).
- `features/scene_analysis/domain/models/scene_profile.dart` — `SceneProfile { brightness, lightDirectionDegrees?, negativeSpaceScore, symmetryScore, backgroundClutterCount, depthEstimate? }`, immutable, `copyWith(...)`.
- `features/scene_analysis/services/pose_analyzer.dart` — `PoseAnalyzer.analyzePose(List<Pose>? mlkitPoseResult, SubjectProfile previous) -> SubjectProfile`. Computes `shoulderAngleDegrees` via `atan2` on left/right shoulder landmarks, `bodyRatio` as (nose-to-hip length)/(hip-to-ankle length).
- `features/scene_analysis/services/face_analyzer.dart` — `FaceAnalyzer.analyzeFace(List<Face>? mlkitFaceResult, SubjectProfile previous) -> SubjectProfile`. Derives `faceAngleDegrees` from `headEulerAngleY`, `eyesOpen` from left/right eye-open probabilities (>0.5 both), `expression` from `smilingProbability` bucketed into `smiling`/`neutral`/`serious`.
- `features/scene_analysis/services/light_analyzer.dart` — `LightAnalyzer.analyzeLight(cameraFrame, previous, {SegmentationMask? segmentationMask, SubjectProfile? subject})`. Populates: `brightness` (Y-plane byte sampling average), `lightDirectionDegrees` (left/right and top/bottom frame brightness comparison via atan2), `negativeSpaceScore` (1 - subject-pixel ratio from segmentation mask confidences), `symmetryScore` (prefers pose shoulder-angle closeness when `subject` is provided, else falls back to left/right subject-pixel balance from the segmentation mask), `backgroundClutterCount` (edge/contrast variance sampled in non-subject region, scaled 0-10). `depthEstimate` remains a documented no-op returning `null` — flagged as needing real depth API support, deliberately not faked with a heuristic.
- `features/scene_analysis/services/tracking_engine.dart` — see Tracking Engine section.
- `features/scene_analysis/providers/scene_providers.dart` — `subjectProfileProvider` / `sceneProfileProvider` (`StateProvider`s, defaulted), `poseAnalyzerProvider`/`faceAnalyzerProvider`/`lightAnalyzerProvider`/`trackingEngineProvider`, `targetSubjectProfileProvider` (derives an idealized target subject: angles at 0, `eyesOpen: true`, `expression: 'smiling'`), `trackingProgressProvider` (calls `TrackingEngine.trackingProgress(current, target)`), `sceneAnalysisListenerProvider` (listens to `MlKitService.analysisStream`, runs pose/face analyzers, smooths via `TrackingEngine.smoothSubject`, writes to `subjectProfileProvider`), `lightAnalysisListenerProvider` (alternate camera-image-stream-based light listener; `camera_screen.dart` currently performs its own throttled light analysis inline in `_onFrame` instead, using the shared `trackingEngineProvider` instance rather than a local one).

## 4. Editorial Brain (editorial_rules + score_calculator)

- `features/voice_director/domain/editorial_rules.dart` — `RuleCondition { matches: bool Function(SubjectProfile, SceneProfile), directionPhrase: String, severity: int (1-10) }`. `rulesFor(PhotographyGoal) -> List<RuleCondition>` returns a shared "common" rule set (eyes closed, brightness too low/high, shoulder/face angle off, background clutter) plus 1-2 goal-specific rules per goal (e.g. LinkedIn adds a "smile" and "center yourself" rule; Editorial adds a negative-space rule). **This rule set is intentionally sparse per the 7-day scope cut — flagged as a gap, see Section 5. Deliberately not expanded without explicit request.**
- `features/editorial_score/domain/score_calculator.dart` — `EditorialScore { overall: int (0-100), breakdown: Map<String,int> (composition, lighting, expression, background, story), nextSuggestion?: String }`. `calculateScore(SubjectProfile, SceneProfile, PhotographyGoal) -> EditorialScore` computes each breakdown category from heuristics, then weights them per-goal (internal `_weightsFor(PhotographyGoal)`, same weight values as `GoalStyleProfile.priorityWeights`) to compute `overall`, and sets `nextSuggestion` to the lowest-scoring category if it's below 60.

## 5 & 6. Photographer Brain / Direction Engine (priority_engine + voice_director UI)

- `features/voice_director/domain/priority_engine.dart` — `PriorityAction { phrase: String, severity: int, sourceLayer: String }`. `getNextAction(SubjectProfile, SceneProfile, PhotographyGoal) -> PriorityAction?` iterates `rulesFor(goal)`, finds all matching rules, returns the one with highest `severity` (or `null` if none match), tagging `sourceLayer: 'editorial_rules'`.
- `test/voice_director/priority_engine_test.dart` — covers: `getNextAction()` returns `null` when subject/scene satisfy all conditions; returns exactly one `PriorityAction` (highest severity) when multiple rules match; different `PhotographyGoal` values route to distinct `rulesFor()` phrase sets. Uses realistic fake `SubjectProfile`/`SceneProfile` instances, not mocks.
- `features/voice_director/providers/voice_providers.dart` — `nextActionProvider` (`Provider<PriorityAction?>`, derives from `subjectProfileProvider` + `sceneProfileProvider` + `selectedGoalProvider`, null if no goal selected), `voiceDirectorListenerProvider` (`Provider<void>`, listens to `nextActionProvider`, debounces 400ms, skips if phrase equals last spoken phrase, calls `TtsService.speak()`).
- In `camera_screen.dart`: the current `nextActionProvider` phrase is displayed as an accent-bordered pill/chip overlaid on the camera preview (visual echo of the TTS speech, not a replacement), below the new in-header goal picker.

## 7. Tracking Engine

- `features/scene_analysis/services/tracking_engine.dart` — `TrackingEngine` class with:
  - `const double _emaAlpha = 0.3` (named constant, module-level).
  - `const int _debounceFrames = 2` (named constant, module-level).
  - `smoothSubject(SubjectProfile raw, SubjectProfile previous) -> SubjectProfile` — EMA on `bodyRatio`, `faceAngleDegrees`, `shoulderAngleDegrees`; 2-frame-consistency debounce on `eyesOpen` and `expression`.
  - `smoothScene(SceneProfile raw, SceneProfile previous) -> SceneProfile` — EMA on `brightness`, `lightDirectionDegrees`, `negativeSpaceScore`, `symmetryScore`, `depthEstimate`; debounce on `backgroundClutterCount`.
  - `trackingProgress(SubjectProfile current, SubjectProfile target) -> double (0.0-1.0)` — averages normalized closeness across comparable fields.
  - **Resolved duplication**: `camera_screen.dart` now reads the single shared instance via `ref.read(trackingEngineProvider)` inside `_onFrame` rather than holding its own local `TrackingEngine` field. `scene_providers.dart`'s `trackingEngineProvider` is the sole instantiation point.
- `shared/widgets/target_zone_overlay.dart` — `TargetZoneOverlay(aligned: bool, trackingProgress: double, zoneRect: Rect?)`, `StatefulWidget` using a `CustomPainter` (`_TargetZonePainter`) whose stroke width, stroke opacity, and fill opacity scale with `trackingProgress`. At `trackingProgress >= 0.95` (`_readyThreshold`), an `AnimationController` pulses the zone's scale as a "ready to capture" cue.

## 8. Capture Engine (capture feature)

- `features/capture/services/auto_capture_service.dart` — `AutoCaptureService.shouldCapture(SubjectProfile subject, SceneProfile scene, double trackingProgress) -> bool`. Gates on (AND, all must pass): `eyesOpen != false`, `scene.brightness >= 0.2`, `shoulderAngleDegrees` within ±15° (or null), `faceAngleDegrees` within ±20° (or null), `backgroundClutterCount <= 5`, `trackingProgress >= _minTrackingProgress (0.9)` (named constant, private, not a runtime-tunable provider), and a 1500ms cooldown since `_lastCapture`. `triggerCapture()` records `_lastCapture = DateTime.now()`.
- `features/capture/domain/shot_builder.dart` — `buildShotFromCapture({imagePath, subject, scene, goal, shotType}) -> Shot`. Single shared function that calls `calculateScore()` and populates all `Shot` fields (`id`, `score`, `timestamp`, `shotType`, `imagePath`). Resolves the prior duplication between auto- and manual-capture paths.
- `features/capture/providers/capture_providers.dart` — `autoCaptureServiceProvider`, `shouldCaptureProvider` (`Provider<bool>`), `autoCaptureProvider` (`Provider<void>`, listens to `shouldCaptureProvider`, on `true` triggers capture and calls `buildShotFromCapture()` with `imagePath: null`, writes result to `capturedShotProvider`), `capturedShotProvider` (`StateProvider<Shot?>`).
- `camera_screen.dart` manual capture path (`_performCapture()`) also calls `buildShotFromCapture()` directly with the real captured `imagePath`, rather than constructing `Shot` inline — both paths guaranteed to produce identical `Shot` objects given identical inputs. `camera_screen.dart` additionally implements `WidgetsBindingObserver`/`didChangeAppLifecycleState` to stop the image stream on `paused`/`inactive` and resume it on `resumed` (without disposing the controller), separate from its `dispose()` teardown.
- `test/auto_capture_service_test.dart` — covers all condition gates including `trackingProgress` threshold boundary cases (below, at, above 0.9).

## 9. Quality Engine (editorial_score)

Covered under Section 4 above (`score_calculator.dart`). Current gap: scoring heuristics have not been validated against real captured photos/real device sensor data — `LightAnalyzer`'s newly-added heuristics for negative space, symmetry, and clutter are directionally reasonable but unvalidated on-device.

## 10. Album Director (album feature)

- `features/album/domain/models/shot.dart` — `Shot { id, score: EditorialScore, timestamp, shotType (hero/half_body/walking/close_up/detail), imagePath? }`.
- `features/album/domain/models/album_state.dart` — `AlbumState { shots: List<Shot> }`. `addShot(Shot) -> AlbumState`, `diversityScore() -> double`, `suggestNextShotType() -> String`.
- `features/album/providers/album_providers.dart` — `AlbumNotifier extends StateNotifier<AlbumState>` with `addShot`, `suggestNextShotType`, `diversityScore` methods; exposed via `albumStateProvider`.
- `features/album/presentation/screens/album_screen.dart` — `AlbumScreen` (ConsumerWidget): diversity/next-shot header, `GridView` of `_ShotTile`, empty state with `PrimaryButton("Quay lại chụp")`, tapping a tile opens `ShotDetailScreen` (full image + per-category `ScoreBadge` breakdown). Now reachable both from the home screen's "Album" card and from `camera_screen.dart`'s `AlbumButton`.
- `features/camera_session/presentation/widgets/album_button.dart` — `AlbumButton` (ConsumerWidget), shows live shot count, navigates to `AlbumScreen`.

## 11. Memory Layer (memory_service)

Covered under Infrastructure above (`core/services/memory_service.dart`). Write-side is fully implemented (`saveHabit`, `getHabit`, `recordCorrection`, `getFrequentCorrections`). **No read-side integration exists yet** — nothing in `priority_engine.dart` or `editorial_rules.dart` currently reads from `MemoryService` to bias `getNextAction()` output. Its GetIt registration bug (unregistered, crashing splash) is fixed — see Section 5/6.

## Documentation

- `PROJECT_STATUS.md` — this file; completion tracking, detailed architecture writeup, ASCII data flow diagram, known gaps, chronological commit history.
- `README.md` — public-facing overview: hook intro, feature list, architecture summary, getting started, project structure, color palette, license/contributing placeholders.
- `AI_SESSION_CONTEXT.md` — operational lookup reference for any new AI session resuming work: exhaustive file inventory (path/purpose/exports/consumers) across `core/`, `shared/`, `features/`, and `test/`; full design token reference; copy-paste-ready model signatures; complete Riverpod provider map; concise data flow (linking to this file's Section 4 for detail); explicit "what not to do" conventions list; and a symptom-to-file debugging table. Distinct from this file — it is not a completion tracker, it exists purely to prevent a new session from re-deriving or duplicating existing work.

# 4. Data Flow Diagram (as text/ASCII)

```
PhotographyGoal (home screen "Shoot" card sets a default if unset;
thereafter changed via camera_screen.dart's in-header chip picker)
│
▼
selectedGoalProvider ──────────────────────────────────────────────┐
│                                                          │
▼                                                          │
CameraService (camera_service.dart) ── raw CameraImage frames      │
│                                                          │
├──► LightAnalyzer.analyzeLight() ──► raw SceneProfile     │
│    (brightness, lightDirectionDegrees,                   │
│     negativeSpaceScore, symmetryScore,                   │
│     backgroundClutterCount; depthEstimate stays null)    │
│                                          │               │
└──► MlKitService.processImage()           │               │
│ (pose, face, segmentation)     │               │
▼                                │               │
analysisStream (MlKitAnalysisResult)        │               │
│                                │               │
┌──────────┴──────────┐                     │               │
▼                     ▼                     │               │
PoseAnalyzer          FaceAnalyzer                 │               │
.analyzePose()        .analyzeFace()                │               │
│                     │                     │               │
└─────────┬───────────┘                     │               │
▼                                ▼               │
raw SubjectProfile              raw SceneProfile         │
│                                │               │
▼                                ▼               │
TrackingEngine.smoothSubject()   TrackingEngine.smoothScene()  │
(single shared instance via trackingEngineProvider,             │
EMA alpha=0.3 + 2-frame debounce, both fields)                │
│                                │               │
▼                                ▼               │
subjectProfileProvider            sceneProfileProvider      │
│                                │               │
└───────────────┬────────────────┘               │
▼                                │
┌──────────────┴──────────────┐                 │
▼                              ▼                 │
priority_engine.getNextAction()   AutoCaptureService        │
(subject, scene, goal) ◄──────────────────┘ .shouldCapture()│
│                        (subject, scene,        │
▼                         trackingProgress ◄─────┘
PriorityAction?                   >= 0.9 required)
│                              │
▼                              ▼
TtsService.speak()              triggerCapture()
(debounced, dedup'd)                    │
+ on-screen phrase chip                 ▼
  CameraService.capture()
  (manual capture button also                     │
  bypasses AutoCaptureService,                    ▼
  calls capture() directly)              buildShotFromCapture()
  (single shared builder —
  auto AND manual paths
  both call this)
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

MemoryService.recordCorrection() / saveHabit()
— currently has no caller anywhere in the pipeline above.
Intended future hook: priority_engine.getNextAction() should read
MemoryService.getFrequentCorrections() / getHabit() to bias which
RuleCondition is surfaced, but this read-side wiring does not exist yet.
(MemoryService is now correctly registered/initialized in
service_locator.dart — the fix only resolved the splash-time
GetIt crash, it did not add any new read-side consumer.)

trackingProgressProvider = TrackingEngine.trackingProgress(
subjectProfileProvider, targetSubjectProfileProvider)
— feeds both TargetZoneOverlay (visual pulse/fill animation) and
AutoCaptureService.shouldCapture() (capture gate).

themeModeProvider (ThemePreferenceService)
— independent side-channel, not part of the AI pipeline; toggled
manually via SettingsScreen, persisted via shared_preferences,
consumed by AppTheme in main.dart. No system-theme following.
```

# 5. Known Gaps / Not Yet Done

- **Real-device testing has never been performed.** No measurements exist for FPS under the current 10-15fps throttle, battery drain from continuous camera streaming + ML Kit inference, or the actual runtime behavior of the permission request flow on a physical device.
- **`editorial_rules.dart` content is likely too sparse to feel like a real photographer.** Each goal currently has ~6 common rules + 1-2 goal-specific rules. Intentionally left unexpanded pending real-device validation data.
- **`MemoryService` habit data is not yet consumed anywhere.** Write-side methods are fully implemented but nothing calls them from `priority_engine.dart` — no personalization loop exists yet. (Its GetIt registration crash is fixed — see below — but this is unrelated to the read-side personalization gap, which remains open.)
- **Only 2 (arguably 6, but shallow) photography styles are implemented** per the 7-day scope cut — all 6 `PhotographyGoal` enum values exist with `GoalStyleProfile`/rule entries, but content depth per style is minimal.
- **No Java/Spring backend exists.** All persistence is local (Hive/shared_preferences).
- **No GenAI on-device fallback exists** for scenarios where rule-based `editorial_rules.dart` fails to produce a confident direction.
- **Test coverage is limited to two files**: `auto_capture_service_test.dart` and `priority_engine_test.dart`. `score_calculator.dart`, `tracking_engine.dart`, `light_analyzer.dart`, and all UI screens have no automated test coverage.
- **`LightAnalyzer`'s heuristics (`lightDirectionDegrees`, `negativeSpaceScore`, `symmetryScore`, `backgroundClutterCount`) are unvalidated on real devices.** They are simple frame-sampling/segmentation-mask heuristics, not proven-accurate measurements — real-device sanity-checking (per the planned manual test pass) has not yet occurred.
- **`depthEstimate` remains a deliberate no-op returning `null`** — needs real depth API support (e.g. ARKit/ARCore depth or LiDAR where available), intentionally not faked with a placeholder heuristic.
- ~~**A proposed debug FPS/condition-breakdown overlay ... was discussed but never implemented**~~ **Fixed** — `DebugPerfOverlay` (`features/camera_session/presentation/widgets/debug_perf_overlay.dart`) is now wired into `camera_screen.dart`, `kDebugMode`-gated, calling `AutoCaptureService.debugConditionBreakdown()` and a per-frame FPS counter via a `GlobalKey`. A runtime-tunable auto-capture threshold was **not** part of this fix and is still not implemented — `_minTrackingProgress` remains a private compile-time constant in `auto_capture_service.dart`.
- **`GoalCard` (`features/goal_selection/presentation/widgets/goal_card.dart`) is now unused/dead code.** It was the tile widget for the old 6-goal picker grid; no file currently imports it. Not deleted — candidate for removal or reuse in a future task.
- **`goalSelectionTitle`/`goalSelectionSubtitle` in `app_strings.dart` are likely unused** now that `goal_selection_screen.dart` no longer renders a goal-picker grid with a title/subtitle. Not removed — flagged for cleanup.
- **No `logo.png` asset exists.** `splash_screen.dart` references `assets/images/logo.png`, but no such file or explicit `pubspec.yaml` asset declaration currently exists; the splash screen always falls through to its `errorBuilder` text-wordmark fallback in practice. Not a bug — the fallback path is functional — but a real logo asset has never been added.
- ~~**`MemoryService` GetIt registration bug** — splash previously crashed with `Bad state: GetIt: Object/factory with type MemoryService is not registered inside GetIt.` because `service_locator.dart`'s `setupLocator()` never registered it.~~ **Fixed** — `MemoryService` is now registered as a lazy singleton and its `.init()` is awaited inside `setupLocator()`.
- ~~**`camera_screen.dart` dispose-race crash**~~ **Fixed and confirmed applied** — `mounted` guards on `_onFrame` and other `ref`-using stream callbacks, earlier `stopImageStream()` in `dispose()`, and a `PopScope` stopping the stream before pop completes are all present in the current file, verified against actual content (previously listed as unconfirmed).
- ~~**`CameraScreen` top-of-screen UI has unresolved safe-area issues**~~ **Fixed and confirmed applied** — proper `SafeArea`/inset handling, `GoalPill` + modal bottom sheet replacing the old chip row, and a new `CameraTopNavBar` are all present, verified against actual content. The 3 navbar icon buttons (difficulty/settings, mode selector, sample/reference photo picker) still ship as functional stubs — `_onAdjustmentsTap`/`_onModeSelectorTap`/`_onReferencePhotoTap` are empty and not yet wired to real behavior.
- ~~**Live camera preview was visibly blurry compared to sharp captured photos**~~ **Fixed** — root cause was `BoxFit.cover` stretching the low-res `ResolutionPreset.medium` analysis-controller texture to full screen. `camera_service.dart` now has a dedicated `ResolutionPreset.high` preview-only `previewController`, and `camera_screen.dart`/`CameraPreviewLayer` render from that instead.
- **Pinch-to-zoom and tap-to-focus added to the live preview** (new capability, not a bug fix) — `CameraPreviewLayer` wraps the preview in a `GestureDetector`; zoom uses `previewController.setZoomLevel()` clamped to `cameraService.minZoom`/`maxZoom`, focus uses `setFocusPoint()`/`setExposurePoint()` with a `FocusRing` shown for 600ms. Known minor cosmetic gap: `FocusRing`'s `AnimatedOpacity` is hardcoded to `opacity: 1.0` and doesn't actually fade — it only disappears because the parent stops rendering it.
- **`camera_screen.dart` was refactored into 5 extracted widget files** under `features/camera_session/presentation/widgets/`: `CameraPreviewLayer`, `FocusRing`, `CameraTopNavBar`, `GoalPill`, `PhraseChip`. `camera_screen.dart` itself now holds only state/logic.
- ~~**Captured photos never appeared in the phone's public Gallery/Photos app**~~ **Fixed** — `camera_service.dart` now calls `Gal.putImage()` (package `gal`) after capture, gated behind `Gal.requestAccess()`; `AndroidManifest.xml` now declares the required media/storage permission (previously missing entirely, which caused `Gal.putImage()` to throw silently — the error was being caught into an unread `lastGallerySaveError` field). Failures now surface via a UI indicator instead of failing silently; the shot is still added to the album even if the gallery save fails.
- ~~**Album had no way to delete a shot**~~ **Fixed** — `AlbumState`/`AlbumNotifier` now expose `removeShot(shotId)`, which also deletes the app-private image file from disk; `album_screen.dart` has a delete affordance (long-press confirm and/or a `ShotDetailScreen` delete button).
- **`AlbumState` is still not persisted to Hive.** `MemoryService` has an `album_state` Hive box with generic `getAlbumValue`/`setAlbumValue`/`clearAlbum` methods, but nothing calls them for actual `Shot` data — the album list still lives only in Riverpod state and is lost on app restart (though gallery-saved copies of images now persist independently via the public-gallery-save feature above).
- **Newly reported, not yet diagnosed via code (as of this session): captured photos look sharp/clear on capture but appear blurry and/or feel less smooth when shown in the Album.** Two candidate causes flagged, pending the user's clarification of which symptom they mean and an updated `album_screen.dart` to confirm: (a) `Image.file` in `_ShotTile`/`ShotDetailScreen` decoding a `ResolutionPreset.max` full-resolution file at default `FilterQuality` without `cacheWidth`/`cacheHeight` hints, causing visible downscale-quality loss in the small grid tiles; (b) the same missing `cacheWidth`/`cacheHeight` causing every full-res image to be decoded at full size for a small grid cell, which is memory/CPU-heavy and could cause scroll jank in `GridView.builder`. Likely fix location is `album_screen.dart`'s `_ShotTile`, not `camera_service.dart` — not yet prompted/fixed.

# 6. Commit History Summary

| Commit subject | What it added |
|---|---|
| feat: scaffold cuemera project with core theming and services | Feature-first folder structure; AppColors (dark/light ThemeExtension); AppTheme; AppSpacing; AppTypography; ThemePreferenceService; CameraService; MlKitService; TtsService; MemoryService; service_locator; main.dart; shared widgets (PrimaryButton, ScoreBadge, TargetZoneOverlay) |
| feat: implement core AI decision-making architecture | PhotographyGoal + GoalStyleProfile; SubjectProfile + SceneProfile; PoseAnalyzer, FaceAnalyzer, LightAnalyzer; editorial_rules + priority_engine; AutoCaptureService; EditorialScore + score_calculator; Shot + AlbumState; MemoryService habit/correction methods |
| feat: wire Riverpod providers connecting AI architecture layers | goal_providers; scene_providers; voice_providers; capture_providers; score_providers; album_providers |
| feat: add splash screen as initial app route | SplashScreen with init flow; logo fallback; error/retry state; permission_handler dependency; main.dart updated |
| feat: build goal_selection UI | GoalCard widget; GoalSelectionScreen; placeholder CameraScreen |
| fix: resolve InputImageRotation compile error in ML Kit integration | google_mlkit_commons import + dependency; corrected InputImage construction |
| fix: add missing AppSpacing.xl2 token | Added xl2 (40.0) |
| feat: complete end-to-end camera capture loop | CameraService.capture(); TargetZoneOverlay + phrase chip + ScoreBadge on preview; provider wiring; capture flash animation; manual Capture button |
| feat: add album feature UI | Shot.imagePath; AlbumScreen; empty state; ShotDetailScreen; AlbumButton entry point |
| feat: add tracking engine for smoothed subject/scene state | TrackingEngine (EMA smoothing, debounce, trackingProgress()); wired into scene_providers.dart and camera_screen.dart |
| feat: wire trackingProgress into Target Zone overlay | trackingProgressProvider + targetSubjectProfileProvider; TargetZoneOverlay progress-driven animation + pulse; fix for undefined provider references |
| feat: gate auto-capture on tracking progress | AutoCaptureService.shouldCapture() trackingProgress param + _minTrackingProgress (0.9); autoCaptureProvider updated; auto_capture_service_test.dart threshold cases |
| test: add priority_engine tests and expand light_analyzer heuristics | priority_engine_test.dart; LightAnalyzer expanded to populate negativeSpaceScore, symmetryScore, backgroundClutterCount, lightDirectionDegrees; depthEstimate documented no-op |
| refactor: consolidate TrackingEngine instance and Shot construction | Removed duplicate local TrackingEngine in camera_screen.dart (reads trackingEngineProvider instead); added buildShotFromCapture() shared by auto- and manual-capture paths |
| docs: add AI_SESSION_CONTEXT.md and Settings screen | AI_SESSION_CONTEXT.md operational reference; SettingsScreen with Dark Mode toggle bound to themeModeProvider; settings gear icon added to goal_selection_screen app bar |
| feat: set medium-resolution analysis stream and handle camera lifecycle | camera_service.dart uses ResolutionPreset.medium for the analysis stream (capture() remains full-resolution); camera_screen.dart implements WidgetsBindingObserver to stop/resume the image stream on app pause/resume without disposing the controller |
| fix: register MemoryService in service_locator.dart | Fixed splash crash ("GetIt: MemoryService is not registered") by registering MemoryService as a lazy singleton and awaiting its Hive init inside setupLocator() |
| fix: prevent Cuemera wordmark from wrapping on splash | splash_screen.dart's app-name text now renders single-line via FittedBox + maxLines:1 + softWrap:false |
| redesign: rebuild ambient app background as editorial studio composition | app_background.dart's dark-mode painter redesigned into an asymmetric, portrait/landscape-aware composition (off-canvas key light, softbox glow, contact-sheet/crop-frame rectangles, alignment block, frame-corner accent), replacing the earlier simple gradient + glow-circles version |
| refactor: repurpose goal_selection_screen.dart as home screen | Replaced the 6-goal picker grid with a 3-card home menu (Shoot/Album/Settings); goal selection moved into camera_screen.dart's header as a compact in-line picker reading/writing selectedGoalProvider directly; new AppStrings entries for home card labels |
| redesign: rebuild home screen cards as layered editorial glass panels | goal_selection_screen.dart's 3 home cards rebuilt with backdrop blur, gradient border, ambient gold halo, icon badges, corner highlight/vignette, and a press-driven scale/glow micro-interaction; new floating wordmark/tagline/rule header treatment; new AppStrings entries for tagline and card subtitles |
| refactor: extract EditorialMenuCard widget into goal_card.dart | Moved the inline `_EditorialMenuCard` (+ supporting private state) out of goal_selection_screen.dart into goal_card.dart as a public `EditorialMenuCard`, overwriting the old dead `GoalCard`; goal_selection_screen.dart now imports and uses it, becoming leaner (header + layout only) |
| fix: resolve bottom overflow on Album/Settings home cards | Fixed "BOTTOM OVERFLOWED BY 1.00 PIXELS" by tightening internal vertical spacing/padding inside EditorialMenuCard instead of increasing card height |
| redesign: shrink home card sizing | Reduced icon badge (52→40px), title font (28→~20-22), and card heights (hero 220→~150-160, Album/Settings 185→~120-130) for tighter proportions |
| redesign: bento-grid home layout (Shoot hero + Album/Settings side-by-side) | Row-based two-column layout for Album/Settings below a full-width Shoot hero card — **later reverted** |
| refactor: revert home cards to full-width vertical stack | Reverted the bento side-by-side layout back to a single full-width vertical column (Shoot/Album/Settings), per user preference |
| fix: resolve recurring bottom overflow after reverting to vertical layout | Fixed "BOTTOM OVERFLOWED BY 14 PIXELS" on Album/Settings by restoring full-width-appropriate internal spacing |
| redesign: two-zone Row composition for EditorialMenuCard | Split card into left zone (icon/title/subtitle/footer) and right zone (low-opacity abstract atmosphere + oversized ghost page-number "01"/"02"/"03") to balance negative space |
| redesign: replace ghost page-number with outline-icon watermark | Removed the low-opacity ghost page-number treatment (looked too faint/unclear) in favor of a bolder stroked outline icon per card (camera/gallery/gear), opacity raised to ~25-35% |
| perf: optimize EditorialMenuCard rendering | Reduced BackdropFilter blur sigma (18→~7), collapsed two stacked BoxShadows into one, added RepaintBoundary per card, to fix reported lag on flutter run on a mid-high-end Android device |
| fix: unify home card sizing/isPrimary | Made all 3 home cards use identical height and isPrimary value, removing the earlier hero/bigger-Shoot-card distinction |
| polish: card internal spacing tweaks | Minor spacing adjustments — gap above "Tap to begin" row, divider-to-subtitle spacing |
| fix (confirmed applied): camera_screen.dart dispose-race crash | `mounted` guards on `_onFrame` and other ref-using stream callbacks, earlier `stopImageStream()` in dispose(), and a PopScope to stop the image stream before pop completes, resolving a "Bad state: Cannot use ref after widget disposed" crash on leaving CameraScreen via Android system back — verified against actual current file content |
| redesign (confirmed applied): camera_screen.dart top UI overhaul | SafeArea/inset fixes for the Capture button and top content, goal chip row replaced with `GoalPill` + modal bottom sheet list, new `CameraTopNavBar` (difficulty/settings, mode selector, sample/reference photo picker — stub callbacks) — verified against actual current file content |
| feat: add delete-shot functionality to album | `removeShot(shotId)` added to `AlbumState`/`AlbumNotifier` (filters by id, deletes app-private image file from disk); delete UI added to `album_screen.dart` (long-press confirm dialog and/or `ShotDetailScreen` delete button) |
| feat: save captures to public gallery | Added `gal` package usage in `camera_service.dart`'s `capture()` (`Gal.putImage()`); fixed missing `AndroidManifest.xml` media/storage permission and missing `Gal.requestAccess()` call that were causing silent failures (error was being caught into an unread `lastGallerySaveError` field); failures now surface via UI without breaking capture/album-add flow |
| — commit pushed — | The large accumulated commit spanning home-screen redesign through album delete/gallery-save features has been pushed to the remote |
| fix: live camera preview blur | Root cause diagnosed as `BoxFit.cover` stretching the low-res `ResolutionPreset.medium` analysis-controller texture to full screen. Added a dedicated `ResolutionPreset.high` preview-only `previewController` in `camera_service.dart` (`initPreviewController()`), kept fully separate from the `medium` analysis controller which still drives ML Kit's `startImageStream` unchanged |
| feat: pinch-to-zoom and tap-to-focus on live preview | `previewController.setZoomLevel()` (clamped to cached `minZoom`/`maxZoom`) on pinch; `setFocusPoint()`/`setExposurePoint()` on tap, with a 600ms `FocusRing` indicator. Implemented via `_onScaleStart`/`_onScaleUpdate`/`_onTapUp` in `camera_screen.dart`, wired through the new `CameraPreviewLayer` widget |
| refactor: extract camera_screen.dart's inline widgets | Pulled 5 previously-inline private widgets into public classes under `features/camera_session/presentation/widgets/`: `CameraPreviewLayer`, `FocusRing`, `CameraTopNavBar`, `GoalPill`, `PhraseChip`. `camera_screen.dart` now holds state/logic only |
| feat: wire DebugPerfOverlay | Previously-paused debug FPS + `AutoCaptureService.debugConditionBreakdown()` overlay is now implemented and wired into `camera_screen.dart`'s Stack, `kDebugMode`-gated, frame counter driven via a `GlobalKey` calling `registerFrame()` once per `_onFrame` invocation |

# 7. Suggested Next Steps

1. **Diagnose and fix the newly reported Album image quality/smoothness issue.** User reports captures look sharp when taken but appear blurry and/or less smooth in the Album grid/detail view — a separate issue from the now-fixed live-preview blur (that fix was for the camera viewfinder, not `album_screen.dart`). Needs an updated `album_screen.dart` to confirm current `_ShotTile`/`ShotDetailScreen` `Image.file` usage, then likely add `cacheWidth`/`cacheHeight` hints (or an appropriately-sized thumbnail generation step) to avoid decoding full `ResolutionPreset.max` images at small grid-tile size — not yet prompted.
2. **Decide what the 3 top-navbar icon buttons should actually do.** They currently ship as functional stubs — difficulty/settings adjustment, mode selector, and sample/reference photo picker currently have no clear target screen/provider; needs a follow-up task to wire real behavior (or confirm a mode concept is even needed vs reusing the existing goal picker).
3. **Optionally fix `FocusRing`'s non-functional fade-out.** `AnimatedOpacity` is currently hardcoded to `opacity: 1.0` and doesn't animate — the ring just disappears when the parent stops rendering it after 600ms. Minor cosmetic polish, not a functional bug.
4. **Consider persisting `AlbumState` to Hive** now that delete exists — without persistence, a user could delete a shot, restart the app, and the album resets anyway; persistence would make delete more meaningful across sessions.
5. **Perform real-device testing.** Validate actual FPS, battery drain, permission flow behavior, and sanity-check the `LightAnalyzer` heuristics (negative space, symmetry, clutter, light direction) against obviously-good vs obviously-bad framing on physical hardware — now also including a direct check of the `EditorialMenuCard` performance fix (BackdropFilter sigma reduction, shadow collapse, RepaintBoundary) and the new preview-only high-res controller's battery/perf impact, using `flutter run --profile` + DevTools Performance overlay.
6. **Enrich `editorial_rules.dart` content.** Expand the rule set per `PhotographyGoal` once real-device data confirms which signals are reliably available and worth acting on.
7. **Wire `MemoryService` into `priority_engine.dart` for personalization.** Implement the read side so `getNextAction()` can be biased by `getFrequentCorrections()`/`getHabit()`, closing the loop left as a placeholder hook.
8. **Clean up remaining minor gaps**: remove or repurpose the now-likely-unused `goalSelectionTitle`/`goalSelectionSubtitle` strings, and either add a real `assets/images/logo.png` or intentionally commit to the text-wordmark-only splash treatment.
9. **Consider a runtime-tunable auto-capture threshold**, now that `DebugPerfOverlay` exposes the condition breakdown for debugging — `_minTrackingProgress` is still a compile-time constant in `auto_capture_service.dart`.
10. **Only after the above are validated**, expand scope: add more photography styles/rule depth, consider a Java/Spring backend, evaluate a GenAI on-device fallback.
```