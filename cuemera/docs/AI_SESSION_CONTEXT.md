# AI_SESSION_CONTEXT.md

## 1. Read This First

Cuemera is a Flutter app that acts as an AI fashion photographer, directing the user in real time (via voice + visual cues) instead of asking them to copy a static pose. Before writing any code, check the relevant section below. If a file, token, or function is listed here, it already exists — read it, do not recreate it. Only ask the user for a file's exact current content if this document references it but you need to see the precise current implementation before editing it (this document describes shape and intent, not always byte-for-byte contents).

## 2. File Inventory by Layer

| File path | Purpose | Key exports | Consumed by |
|---|---|---|---|
| `lib/main.dart` | App entry point, sets up `ProviderScope` and `MaterialApp` | `MyApp` | N/A (root) |
| `core/constants/app_colors.dart` | Design token definitions (dark + light) as a `ThemeExtension` | `AppColors` | `app_theme.dart`, every screen/widget reading colors |
| `core/constants/app_spacing.dart` | Spacing scale constants | `AppSpacing` | every screen/widget needing padding/margin |
| `core/constants/app_typography.dart` | Text style builders keyed off `AppColors` | `AppTypography` | `app_theme.dart`, every screen/widget rendering text |
| `core/constants/app_strings.dart` | User-facing copy strings | `AppStrings` | `splash_screen.dart`, `goal_selection_screen.dart` (home), `camera_screen.dart`. Now includes home-screen strings (`homeShootLabel`, `homeAlbumLabel`, `homeSettingsLabel`, `homeTagline`, `homeShootSubtitle`, `homeAlbumSubtitle`, `homeSettingsSubtitle`, `homeTapToBegin`). `goalSelectionTitle`/`goalSelectionSubtitle` are likely dead now that `goal_selection_screen.dart` no longer renders a goal-picker grid — not removed, just unused |
| `core/theme/app_theme.dart` | Builds `ThemeData` for dark/light, wires tokens into Flutter theme | `AppTheme` | `lib/main.dart` |
| `core/di/service_locator.dart` | GetIt-based locator for pre-`runApp` bootstrapping | `sl`, `setupLocator()` | `splash_screen.dart`. Registers `CameraService`, `MlKitService`, `TtsService`, `MemoryService` as lazy singletons; `setupLocator()` now correctly awaits `sl<MemoryService>().init()` before returning (previously `MemoryService` was unregistered, causing a `GetIt: Object/factory with type MemoryService is not registered` crash on splash — fixed) |
| `core/services/camera_service.dart` | Wraps `CameraController` lifecycle, capture | `CameraService`, `cameraServiceProvider` | `camera_screen.dart`, `scene_providers.dart` |
| `core/services/ml_kit_service.dart` | Wraps ML Kit pose/face/segmentation detectors, emits `analysisStream` | `MlKitService`, `MlKitAnalysisResult`, `mlKitServiceProvider` | `camera_screen.dart`, `scene_providers.dart` |
| `core/services/tts_service.dart` | Wraps `flutter_tts`, dedupes repeated phrases | `TtsService`, `ttsServiceProvider` | `voice_providers.dart` |
| `core/services/memory_service.dart` | Hive-backed habit/correction/album persistence | `MemoryService`, `memoryServiceProvider` | `splash_screen.dart` (init only, via `service_locator.dart`); no read-side consumer yet |
| `core/services/theme_preference_service.dart` | Persists dark/light mode via `shared_preferences` | `ThemePreferenceService`, `themeModeProvider` | `lib/main.dart`, `splash_screen.dart`, `settings_screen.dart` |
| `shared/widgets/app_background.dart` | Canvas-fraction-based `CustomPainter` background: in dark mode paints an asymmetric editorial fashion-studio composition (off-canvas key-light gradient, softbox glow, contact-sheet/crop-frame stroked rectangles, alignment block, frame-corner accent), portrait/landscape-aware; in light mode returns a plain `Container` using the background token. `AppBackground(child)` signature, `RepaintBoundary` wrapping, and a `shouldRepaint()` that only compares `Size`/`Brightness` against `oldDelegate` are all unchanged from the original simpler-gradient version | `AppBackground` | `splash_screen.dart`, `goal_selection_screen.dart` (now the home screen), `settings_screen.dart` — not `camera_screen.dart` (its background is the live `CameraPreview`) |
| `shared/widgets/primary_button.dart` | Accent-colored button, loading/disabled states | `PrimaryButton` | `splash_screen.dart`, `camera_screen.dart` |
| `shared/widgets/score_badge.dart` | Circular score badge, color-coded by threshold | `ScoreBadge` | `camera_screen.dart`, `album_screen.dart` (grid + detail) |
| `shared/widgets/target_zone_overlay.dart` | Animated pose-alignment overlay driven by `trackingProgress` | `TargetZoneOverlay` | `camera_screen.dart` |
| `features/goal_selection/domain/models/photography_goal.dart` | Goal enum + per-goal style profile | `PhotographyGoal`, `GoalStyleProfile`, `getStyleProfile()` | almost every domain/service file downstream (rules, scoring, providers); goal is now selected directly inside `camera_screen.dart`'s in-header picker rather than on a dedicated screen |
| `features/goal_selection/providers/goal_providers.dart` | Exposes selected goal + derived style profile | `selectedGoalProvider`, `styleProfileProvider` | `camera_screen.dart` (reads/writes directly via its in-header goal picker; also sets a default on first entry from home), `voice_providers.dart`, `capture_providers.dart`, `score_providers.dart` |
| `features/goal_selection/presentation/widgets/goal_card.dart` | Now holds the **public `EditorialMenuCard`** widget (extracted out of `goal_selection_screen.dart`, overwriting the old dead `GoalCard`). Stateful glass-panel card: two-zone `Row` layout (left: circular icon badge + title + subtitle + thin gold divider + "Tap to begin" footer row with arrow; right: low-opacity `CustomPaint` atmosphere — stroked frame, offset square, radial glow — plus a large stroked outline-icon watermark at ~25-35% opacity, replacing an earlier ghost-page-number treatment that was tried and removed for looking too faint/unclear). `RepaintBoundary`-wrapped, `BackdropFilter` blur reduced to sigma ~7 (was 18) and shadows collapsed to a single `BoxShadow`, for a performance fix after reported lag on `flutter run`. All 3 home cards (Shoot/Album/Settings) now use identical height and `isPrimary` treatment — the earlier hero/bigger-Shoot-card size distinction was removed per user preference | `EditorialMenuCard` | `goal_selection_screen.dart` (only consumer) |
| `features/goal_selection/presentation/screens/goal_selection_screen.dart` | Repurposed as the app's **home screen**. No longer a 6-goal picker grid, and no longer defines its card widget inline — imports and uses `EditorialMenuCard` from `goal_card.dart`. Custom floating header (`_HomeHeader`/`_ApertureRingPainter`: wordmark + tagline + gold rule, no `AppBar`) over `AppBackground`, followed by 3 identically-sized `EditorialMenuCard`s stacked vertically: Shoot, Album, Settings (a side-by-side two-column "bento" layout for Album/Settings was tried and then explicitly reverted back to a vertical stack per user preference). "Shoot" sets `selectedGoalProvider` to `PhotographyGoal.values.first` if it's currently `null`, then pushes `CameraScreen`. "Album" pushes `AlbumScreen`. "Settings" pushes `SettingsScreen` | `GoalSelectionScreen` | `splash_screen.dart` (navigation target, unchanged route/class name), `camera_screen.dart` (fallback nav target if `selectedGoalProvider` is null on entry) |
| `features/scene_analysis/domain/models/subject_profile.dart` | Immutable subject pose/face state | `SubjectProfile` | pose/face analyzers, `TrackingEngine`, `scene_providers.dart`, `priority_engine.dart`, `score_calculator.dart`, `auto_capture_service.dart` |
| `features/scene_analysis/domain/models/scene_profile.dart` | Immutable scene/lighting state | `SceneProfile` | `light_analyzer.dart`, `TrackingEngine`, `scene_providers.dart`, `priority_engine.dart`, `score_calculator.dart`, `auto_capture_service.dart` |
| `features/scene_analysis/services/pose_analyzer.dart` | Derives shoulder angle + body ratio from ML Kit pose | `PoseAnalyzer` | `camera_screen.dart`, `scene_providers.dart` |
| `features/scene_analysis/services/face_analyzer.dart` | Derives face angle, eyesOpen, expression from ML Kit face | `FaceAnalyzer` | `camera_screen.dart`, `scene_providers.dart` |
| `features/scene_analysis/services/light_analyzer.dart` | Derives brightness, lightDirectionDegrees, negativeSpaceScore, symmetryScore, backgroundClutterCount from camera frame (+ optional segmentation mask/subject); depthEstimate is a documented no-op returning null | `LightAnalyzer` | `camera_screen.dart`, `scene_providers.dart` |
| `features/scene_analysis/services/tracking_engine.dart` | EMA smoothing + debounce for subject/scene, tracking progress scoring | `TrackingEngine` | `scene_providers.dart` (via `trackingEngineProvider`), `camera_screen.dart` (reads via provider, does not instantiate locally) |
| `features/scene_analysis/providers/scene_providers.dart` | Subject/scene state, analyzers, tracking engine, tracking progress, listener wiring | `subjectProfileProvider`, `sceneProfileProvider`, `poseAnalyzerProvider`, `faceAnalyzerProvider`, `lightAnalyzerProvider`, `trackingEngineProvider`, `targetSubjectProfileProvider`, `trackingProgressProvider`, `sceneAnalysisListenerProvider`, `lightAnalysisListenerProvider` | `camera_screen.dart`, `voice_providers.dart`, `capture_providers.dart`, `score_providers.dart` |
| `features/voice_director/domain/editorial_rules.dart` | Per-goal rule conditions mapping subject/scene state to direction phrases | `RuleCondition`, `rulesFor()` | `priority_engine.dart` |
| `features/voice_director/domain/priority_engine.dart` | Selects single highest-severity matching rule as next action | `PriorityAction`, `getNextAction()` | `voice_providers.dart` |
| `features/voice_director/providers/voice_providers.dart` | Exposes next action + debounced TTS-speaking listener | `nextActionProvider`, `voiceDirectorListenerProvider` | `camera_screen.dart` |
| `features/capture/services/auto_capture_service.dart` | Gates auto-capture on subject/scene/trackingProgress conditions + cooldown | `AutoCaptureService` | `capture_providers.dart` |
| `features/capture/providers/capture_providers.dart` | Auto-capture gating + triggering, exposes captured shot | `autoCaptureServiceProvider`, `shouldCaptureProvider`, `autoCaptureProvider`, `capturedShotProvider` | `camera_screen.dart` |
| `features/capture/domain/shot_builder.dart` | Single shared Shot construction (score calc + field population) | `buildShotFromCapture()` | `capture_providers.dart` (auto path), `camera_screen.dart` (manual path) |
| `features/editorial_score/domain/score_calculator.dart` | Computes weighted per-category + overall editorial score | `EditorialScore`, `calculateScore()` | `score_providers.dart`, `shot_builder.dart` |
| `features/editorial_score/providers/score_providers.dart` | Exposes live editorial score for current subject/scene/goal | `currentScoreProvider` | `camera_screen.dart` |
| `features/album/domain/models/shot.dart` | Captured shot record | `Shot` | `album_state.dart`, `shot_builder.dart`, `album_screen.dart`, `capture_providers.dart`, `camera_screen.dart` |
| `features/album/domain/models/album_state.dart` | Immutable shot collection + diversity/suggestion logic | `AlbumState` | `album_providers.dart` |
| `features/album/providers/album_providers.dart` | Album state notifier exposing add/suggest/diversity | `AlbumNotifier`, `albumStateProvider` | `camera_screen.dart`, `album_screen.dart`, `album_button.dart` |
| `features/album/presentation/screens/album_screen.dart` | Shot grid, diversity header, empty state, detail view | `AlbumScreen`, `ShotDetailScreen` | `camera_screen.dart` (via `album_button.dart` navigation), `goal_selection_screen.dart` (home screen's "Album" card navigates here directly) |
| `features/camera_session/presentation/screens/camera_screen.dart` | Main capture screen: preview, overlays, voice, auto/manual capture. Currently hosts a compact horizontal goal picker (chip row) directly in its header, reading/writing `selectedGoalProvider` in place — no separate goal-selection screen is used to enter the camera. If `selectedGoalProvider` is `null` on entry (e.g. reached without going through home), redirects back to `GoalSelectionScreen` (home). **Pending/unconfirmed as of this session**: (1) a dispose-safety fix was prompted for a crash — `_onFrame` (the `CameraController.startImageStream` callback) could call `ref` after widget disposal when leaving via the Android system back button, throwing `Bad state: Cannot use "ref" after the widget was disposed`; fix requested `if (!mounted) return;` guards + earlier `stopImageStream()` call + a `PopScope` to stop the stream before pop completes — not yet confirmed fixed/tested. (2) A UI redesign prompt was issued but not yet confirmed applied: fix top content colliding with the system status bar and the Capture button being covered by the Android system nav bar (both need proper `SafeArea`/inset handling); replace the horizontal goal chip row with a single tappable pill that opens a modal bottom sheet list; add a new custom top navbar row (separate from the existing "find more light" phrase chip + album count badge) with 3 icon buttons — difficulty/settings adjustment, mode selector, and a sample/reference photo picker to show the user an example pose — some of these were expected to ship as functional stubs pending further wiring decisions | `CameraScreen` | `goal_selection_screen.dart` (home screen's "Shoot" card, nav target) |
| `features/camera_session/presentation/widgets/album_button.dart` | Top-corner shot-count button navigating to album | `AlbumButton` | `camera_screen.dart` |
| `features/settings/presentation/screens/settings_screen.dart` | Minimal settings screen: dark mode toggle bound to `themeModeProvider` | `SettingsScreen` | `goal_selection_screen.dart` (home screen's "Settings" card, nav target; the old app-bar gear `IconButton` was removed since Settings is now its own home card) |
| `features/splash/presentation/screens/splash_screen.dart` | App init flow (Hive, locator, theme, permissions, ML Kit warm-up). Renders `assets/images/logo.png` via `Image.asset`, with an `errorBuilder` fallback to a `FittedBox`-wrapped, single-line, non-wrapping `Text(AppStrings.appName)` using `AppTypography.heading1` (fixes a prior bug where "Cuemera" could wrap to two lines). **Note:** no `logo.png` asset is currently registered in `pubspec.yaml`, so the fallback text path is what actually renders today — treat this as a known gap, not a bug, unless asked to add a real logo asset | `SplashScreen`, `splashInitProvider` | `lib/main.dart` (set as `home`) |
| `test/auto_capture_service_test.dart` | Tests for `AutoCaptureService.shouldCapture()` incl. trackingProgress threshold | N/A (test file) | N/A |
| `test/voice_director/priority_engine_test.dart` | Tests for `getNextAction()` — null case, single-highest-severity case, per-goal rule routing | N/A (test file) | N/A |
| `PROJECT_STATUS.md` | Completion tracking, detailed data flow diagram, known gaps, commit history | N/A (doc) | N/A |
| `README.md` | Public-facing project overview | N/A (doc) | N/A |

## 3. Design Tokens Quick Reference

**Never hardcode a hex color or raw spacing number in new code — always reference these tokens.**

Access pattern: `Theme.of(context).extension<AppColors>()!.<token>`

| Token | Dark value | Light value | Usage |
|---|---|---|---|
| background | `#14141A` | `#F5F3EE` | scaffold/app background |
| surface | `#232329` | `#FFFFFF` | cards, elevated surfaces |
| text | `#F3F1EA` | `#1B1A17` | primary text |
| textMuted | `#9B978C` | `#6B675C` | secondary/caption text, disabled state |
| accent | `#C9A227` | `#B5822A` | primary CTA, highlights, selected state |
| targetZone | `#5ED1C9` | `#1F8F86` | target zone overlay (unaligned state) |
| success | `#7FA65C` | `#4F7A34` | high scores, aligned state |
| warning | `#E0A458` | `#B5762A` | errors, low scores, alerts |

`AppSpacing` (`core/constants/app_spacing.dart`), access as `AppSpacing.<token>`:

| Token | Value |
|---|---|
| xs | 4.0 |
| sm | 8.0 |
| md | 16.0 |
| lg | 24.0 |
| xl | 32.0 |
| xl2 | 40.0 |
| xxl | 48.0 |

`AppTypography` (`core/constants/app_typography.dart`), each a method taking `AppColors` and returning a colored `TextStyle`, access as `AppTypography.<method>(colors)`:

- `heading1(colors)`
- `heading2(colors)`
- `body(colors)`
- `bodyMuted(colors)`
- `caption(colors)`
- `score(colors)`
- `buildTextTheme(colors)` — returns a full `TextTheme` for `ThemeData`

## 4. Established Data Models

Do not redefine or rename fields on these models — extend via new files, not by modifying core fields, unless the user explicitly requests a breaking model change.

```
enum PhotographyGoal { editorial, linkedin, travel, dating, beach, luxury }

class GoalStyleProfile {
  final PhotographyGoal goal;
  final Map<String, double> priorityWeights;
  final List<String> targetCompositionRules;
}
GoalStyleProfile getStyleProfile(PhotographyGoal goal);

class SubjectProfile {
  final double? bodyRatio;
  final double? faceAngleDegrees;
  final double? shoulderAngleDegrees;
  final bool? eyesOpen;
  final String? expression;
  final DateTime timestamp;
  SubjectProfile copyWith({double? bodyRatio, double? faceAngleDegrees, double? shoulderAngleDegrees, bool? eyesOpen, String? expression});
  // note: copyWith always sets timestamp to DateTime.now(), it does not accept a timestamp override
}

class SceneProfile {
  final double brightness;
  final double? lightDirectionDegrees;
  final double negativeSpaceScore;
  final double symmetryScore;
  final int backgroundClutterCount;
  final double? depthEstimate;
  SceneProfile copyWith({double? brightness, double? lightDirectionDegrees, double? negativeSpaceScore, double? symmetryScore, int? backgroundClutterCount, double? depthEstimate});
}

class RuleCondition {
  final bool Function(SubjectProfile subject, SceneProfile scene) matches;
  final String directionPhrase;
  final int severity; // 1-10
}
List<RuleCondition> rulesFor(PhotographyGoal goal);

class PriorityAction {
  final String phrase;
  final int severity;
  final String sourceLayer;
}
PriorityAction? getNextAction(SubjectProfile subject, SceneProfile scene, PhotographyGoal goal);

class EditorialScore {
  final int overall; // 0-100
  final Map<String, int> breakdown; // composition, lighting, expression, background, story
  final String? nextSuggestion;
}
EditorialScore calculateScore(SubjectProfile subject, SceneProfile scene, PhotographyGoal goal);

class Shot {
  final String id;
  final EditorialScore score;
  final DateTime timestamp;
  final String shotType; // hero, half_body, walking, close_up, detail
  final String? imagePath;
}

class AlbumState {
  final List<Shot> shots;
  AlbumState addShot(Shot shot);
  double diversityScore();
  String suggestNextShotType();
}

class AutoCaptureService {
  bool shouldCapture(SubjectProfile subject, SceneProfile scene, double trackingProgress);
  Future<void> triggerCapture();
}

Shot buildShotFromCapture({
  required String? imagePath,
  required SubjectProfile subject,
  required SceneProfile scene,
  required PhotographyGoal goal,
  required String shotType,
});
```

## 5. State Management Map

| Provider | Type | File | Exposes | Watched/read by |
|---|---|---|---|---|
| `selectedGoalProvider` | `StateProvider<PhotographyGoal?>` | `goal_providers.dart` | current selected goal | `goal_selection_screen.dart` (home; sets a default when opening "Shoot" if null), `camera_screen.dart` (reads/writes directly via in-header picker; redirects to home if null on entry), `voice_providers.dart`, `capture_providers.dart`, `score_providers.dart` |
| `styleProfileProvider` | `Provider<GoalStyleProfile?>` | `goal_providers.dart` | derived style profile for selected goal | (available, not yet consumed by UI) |
| `subjectProfileProvider` | `StateProvider<SubjectProfile>` | `scene_providers.dart` | current smoothed subject state | `camera_screen.dart`, `voice_providers.dart`, `capture_providers.dart`, `score_providers.dart` |
| `sceneProfileProvider` | `StateProvider<SceneProfile>` | `scene_providers.dart` | current smoothed scene state | `camera_screen.dart`, `voice_providers.dart`, `capture_providers.dart`, `score_providers.dart` |
| `poseAnalyzerProvider` | `Provider<PoseAnalyzer>` | `scene_providers.dart` | shared pose analyzer instance | `sceneAnalysisListenerProvider` |
| `faceAnalyzerProvider` | `Provider<FaceAnalyzer>` | `scene_providers.dart` | shared face analyzer instance | `sceneAnalysisListenerProvider` |
| `lightAnalyzerProvider` | `Provider<LightAnalyzer>` | `scene_providers.dart` | shared light analyzer instance | `lightAnalysisListenerProvider` |
| `trackingEngineProvider` | `Provider<TrackingEngine>` | `scene_providers.dart` | single shared `TrackingEngine` instance | `sceneAnalysisListenerProvider`, `lightAnalysisListenerProvider`, `trackingProgressProvider`, `camera_screen.dart` |
| `targetSubjectProfileProvider` | `Provider<SubjectProfile>` | `scene_providers.dart` | idealized target pose (angles 0, eyesOpen true, expression smiling) | `trackingProgressProvider` |
| `trackingProgressProvider` | `Provider<double>` | `scene_providers.dart` | 0.0-1.0 closeness of current subject to target | `camera_screen.dart` (TargetZoneOverlay), `capture_providers.dart` (shouldCaptureProvider) |
| `sceneAnalysisListenerProvider` | `Provider<void>` | `scene_providers.dart` | side-effect: listens to ML Kit stream, updates `subjectProfileProvider` | `camera_screen.dart` (watched to stay active) |
| `lightAnalysisListenerProvider` | `Provider<void>` | `scene_providers.dart` | side-effect: alternate light-analysis stream listener | defined but not currently watched anywhere (camera_screen does light analysis inline in `_onFrame` instead) |
| `nextActionProvider` | `Provider<PriorityAction?>` | `voice_providers.dart` | current highest-priority direction | `camera_screen.dart` (chip UI), `voiceDirectorListenerProvider` |
| `voiceDirectorListenerProvider` | `Provider<void>` | `voice_providers.dart` | side-effect: debounced TTS speak on phrase change | `camera_screen.dart` (watched to stay active) |
| `autoCaptureServiceProvider` | `Provider<AutoCaptureService>` | `capture_providers.dart` | shared `AutoCaptureService` instance | `shouldCaptureProvider`, `autoCaptureProvider` |
| `shouldCaptureProvider` | `Provider<bool>` | `capture_providers.dart` | whether auto-capture conditions currently pass | `autoCaptureProvider` |
| `autoCaptureProvider` | `Provider<void>` | `capture_providers.dart` | side-effect: triggers capture + builds Shot when `shouldCaptureProvider` flips true | `camera_screen.dart` (watched to stay active) |
| `capturedShotProvider` | `StateProvider<Shot?>` | `capture_providers.dart` | most recently auto-captured shot | `camera_screen.dart` (`ref.listen` adds it to album) |
| `currentScoreProvider` | `Provider<EditorialScore?>` | `score_providers.dart` | live editorial score for current state | `camera_screen.dart` (ScoreBadge display) |
| `albumStateProvider` | `StateNotifierProvider<AlbumNotifier, AlbumState>` | `album_providers.dart` | full album state + add/suggest/diversity methods | `camera_screen.dart`, `album_screen.dart`, `album_button.dart` |
| `cameraServiceProvider` | `Provider<CameraService>` | `camera_service.dart` | shared camera controller wrapper | `camera_screen.dart`, `scene_providers.dart` |
| `mlKitServiceProvider` | `Provider<MlKitService>` | `ml_kit_service.dart` | shared ML Kit detector wrapper | `camera_screen.dart`, `scene_providers.dart`, `splash_screen.dart` (warm-up) |
| `ttsServiceProvider` | `Provider<TtsService>` | `tts_service.dart` | shared TTS wrapper | `voice_providers.dart` |
| `memoryServiceProvider` | `Provider<MemoryService>` | `memory_service.dart` | shared Hive-backed memory service | not currently read anywhere (write-side only, via `sl<MemoryService>()` in splash, now correctly registered/awaited in `service_locator.dart`) |
| `themeModeProvider` | `StateNotifierProvider<ThemePreferenceService, ThemeMode>` | `theme_preference_service.dart` | current theme mode | `lib/main.dart`, `splash_screen.dart`, `settings_screen.dart` |
| `splashInitProvider` | `FutureProvider.autoDispose<void>` | `splash_screen.dart` | splash init sequence result | `splash_screen.dart` only |

## 6. Data Flow

Home screen (`goal_selection_screen.dart`) → "Shoot" card sets `selectedGoalProvider` to a default (`PhotographyGoal.values.first`) if unset, then navigates to camera → camera frames → ML Kit (pose/face) + light analysis → per-frame analyzers → `TrackingEngine` smoothing → `subjectProfileProvider`/`sceneProfileProvider` → fan-out to `priority_engine` (voice direction) and `AutoCaptureService` (gated on `trackingProgressProvider`) → capture → `buildShotFromCapture()` (calls `score_calculator`) → `AlbumState`. The active `PhotographyGoal` can be changed at any point from `camera_screen.dart`'s in-header picker, which reads/writes `selectedGoalProvider` directly — there is no longer a separate goal-selection step before entering the camera.

For the full diagram with every intermediate step and the current memory-layer gap, see **[PROJECT_STATUS.md, Section 4](./PROJECT_STATUS.md#4-data-flow-diagram-as-textascii)** — do not re-derive it here.

## 7. What NOT To Do

- No comments in code — this is an established project convention across every file so far.
- Never hardcode a hex color or raw spacing/typography value — always use `AppColors`/`AppSpacing`/`AppTypography` tokens.
- Do not instantiate `TrackingEngine` locally in a new file — always read the shared instance via `trackingEngineProvider`.
- Do not construct a `Shot` + call `calculateScore()` inline for any new capture path — always call `buildShotFromCapture()` from `features/capture/domain/shot_builder.dart`.
- The auto-capture tracking threshold (`_minTrackingProgress = 0.9`) is currently a private named constant inside `auto_capture_service.dart`, not a runtime-adjustable provider — no such refactor has been applied. If the user asks for runtime tuning, treat it as a new task.
- Permission handling (camera + microphone) is already fully implemented in `splash_screen.dart` via `permission_handler` — do not add new permission requests elsewhere without checking here first.
- `editorial_rules.dart` content is intentionally sparse (a handful of rules per goal) pending real-device validation — do not silently expand its content unless explicitly asked to.
- A debug FPS/condition-breakdown overlay + runtime-tunable auto-capture threshold were proposed but not yet implemented — the user paused before running that prompt. Do not assume `kDebugPerfOverlay`, `debug_flags.dart`, or a runtime-adjustable threshold provider exist unless confirmed.
- `LightAnalyzer`'s derived fields (`negativeSpaceScore`, `symmetryScore`, `backgroundClutterCount`, `lightDirectionDegrees`) are heuristic approximations, not ground truth — don't treat their exact values as reliable without real-device sanity-checking.
- `depthEstimate` is a deliberate no-op returning `null` — do not fake it with a placeholder heuristic.
- `ThemeMode.system`/auto-detection is intentionally not implemented — theme switching is a manual, persisted toggle only (`SettingsScreen`). Do not add system-theme-following behavior unless explicitly asked.
- Do not assume `goal_selection_screen.dart` is a 6-goal picker grid — it was repurposed into the home screen (Shoot/Album/Settings cards). Goal selection now happens inside `camera_screen.dart`'s header.
- Do not assume `GoalCard` in `goal_card.dart` still exists — that class/dead code was overwritten by the public `EditorialMenuCard` (extracted from `goal_selection_screen.dart`). `goal_card.dart` is now actively imported and used, not dead code.
- Do not assume the 3 home cards differ in size — an earlier "Shoot is a bigger hero card" (`isPrimary: true` with taller height) distinction was intentionally removed; all 3 cards should be identical in height/visual weight unless a new task changes that again.
- Do not assume the home cards use a side-by-side "bento" two-column layout for Album/Settings — that was tried and then explicitly reverted back to a full-width vertical stack per user preference.
- Do not assume `EditorialMenuCard`'s right-side decorative zone shows an oversized "01"/"02"/"03" ghost page number — that was tried and removed (looked too faint/unclear); it currently shows a stroked outline-icon watermark instead.
- `EditorialMenuCard`'s `BackdropFilter` blur sigma and shadow count were deliberately reduced (sigma ~18 → ~7, two stacked `BoxShadow`s → one) as a performance fix for reported lag in `flutter run` on a mid-high-end device — do not casually increase blur/shadow intensity back up without checking perf impact.
- Do not assume a real `logo.png` exists — `splash_screen.dart` references `assets/images/logo.png` but no such asset or `pubspec.yaml` declaration currently exists; the app relies on the `errorBuilder` text fallback.
- `camera_screen.dart`'s dispose-safety fix (for the `Bad state: Cannot use "ref" after the widget was disposed` crash on system-back-triggered exit) and its top-navbar/bottom-sheet-picker/safe-area UI redesign were both prompted in this session but **not yet confirmed applied or tested** — verify current file state before assuming either is in place.

## 8. Where to Look When Something Breaks

| Symptom | Likely file(s) to check first |
|---|---|
| TTS not speaking / silent | `tts_service.dart`, `voice_providers.dart` (debounce/dedup logic), confirm `voiceDirectorListenerProvider` is watched in `camera_screen.dart` |
| Auto-capture never triggers | `auto_capture_service.dart` (`_minTrackingProgress` + other AND conditions), `trackingProgressProvider`/`targetSubjectProfileProvider` in `scene_providers.dart` |
| Colors look wrong / theme not applying | `app_colors.dart` (`AppColors.dark`/`.light`), `app_theme.dart` (`_build` wiring), confirm code uses `Theme.of(context).extension<AppColors>()` and not raw `ColorScheme` |
| Dark mode toggle not persisting/updating | `theme_preference_service.dart` (`setDarkMode`/`load`), `settings_screen.dart` (Switch binding), `lib/main.dart` (`themeModeProvider` watch) |
| Target Zone overlay not animating | `target_zone_overlay.dart` (`_TargetZonePainter`, pulse `AnimationController`), confirm `trackingProgressProvider` is watched and passed in from `camera_screen.dart` |
| Camera preview black / not showing | `camera_service.dart` (`init`/`startImageStream`), permission grant status from `splash_screen.dart`, `camera_screen.dart` `_CameraInitState` handling |
| Shot not appearing in album | `album_providers.dart` (`AlbumNotifier.addShot`), `shot_builder.dart` (`buildShotFromCapture`), `capture_providers.dart` (`capturedShotProvider` listener) or `camera_screen.dart` `_performCapture()` |
| Score badge missing or wrong | `score_calculator.dart` (weights/breakdown), `score_providers.dart` (`currentScoreProvider`), `score_badge.dart` (color thresholds) |
| ML Kit `InputImage`/compile errors | `ml_kit_service.dart` imports (`google_mlkit_commons`), `InputImage.fromBytes`/`InputImageMetadata` construction |
| Subject/scene fields stuck at default | `pose_analyzer.dart`/`face_analyzer.dart`/`light_analyzer.dart` (raw extraction), `tracking_engine.dart` (EMA/debounce smoothing), `scene_providers.dart` listener wiring |
| Splash crashes with "GetIt: ... is not registered" | `service_locator.dart` (`setupLocator()` — confirm the missing type is registered as a lazy singleton and any async `.init()` it needs is awaited before splash proceeds) |
| Wrong screen after splash, or Shoot card behaves oddly | `goal_selection_screen.dart` (now home screen — confirm it still navigates to `CameraScreen`/`AlbumScreen`/`SettingsScreen` correctly), `selectedGoalProvider` default-setting logic on the "Shoot" card |
| Goal picker missing/not updating in camera | `camera_screen.dart` header chip-row widget, confirm it reads/writes `selectedGoalProvider` directly and not a local/parallel state |
| Background looks flat / geometric shapes missing | `app_background.dart` (`_BackgroundPainter`, dark-mode-only paint path), confirm screen is dark mode and is one of the 3 screens that use `AppBackground` |
| Home card content overflows ("BOTTOM OVERFLOWED BY N PIXELS") | `goal_card.dart` (`EditorialMenuCard`'s internal `Column`/`Row` spacing, `innerPadding`, `FittedBox` usage) — fix via tightening spacing/padding, not by increasing card `height` |
| Home cards feel laggy / janky on `flutter run` | `goal_card.dart` (`BackdropFilter` sigma, stacked `BoxShadow`s, layered `Positioned.fill` gradients, missing `RepaintBoundary`) — test with `flutter run --profile` + DevTools Performance overlay before assuming it's just debug-mode overhead |
| Crash on leaving `CameraScreen`: "Bad state: Cannot use 'ref' after the widget was disposed" | `camera_screen.dart` `_onFrame` (image-stream callback race condition on dispose, especially via Android system back gesture) — check `mounted` guards at the top of every `ref`-using stream callback, `stopImageStream()` ordering in `dispose()`, and whether a `PopScope` stops the stream before pop completes |
| Capture button hidden behind Android system nav bar / top content collides with status bar | `camera_screen.dart` — check `SafeArea`/`MediaQuery.of(context).padding` handling for top and bottom insets |