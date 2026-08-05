# Cuemera — Project Status

*Last regenerated: 2026-08-05. This file is a fully-overwritten snapshot — it is not append-only. It reflects only what could be verified from the 53 `.dart` files + `pubspec.yaml` uploaded and directly read/searched in this session. It does not reflect any file, asset, test, or platform folder not provided.*

---

## What Cuemera Is

Cuemera is a Flutter mobile app that helps a user replicate a reference photo in real time using their phone camera: the user picks a reference photo, an on-device ML pipeline (Google ML Kit pose/face/selfie-segmentation plus hand-rolled image analysis) extracts a `ReferenceProfile` from it, and while the live camera is pointed at the user, a parallel live analysis pipeline continuously compares the current scene/subject to that reference and speaks/displays the single worst-offending correction (via `flutter_tts` and an on-screen phrase chip), aiming to auto-capture a shot once the subject is close enough to the reference for long enough.

---

## Feature Inventory

| Feature folder | One-line role |
|---|---|
| `core/` | Cross-cutting services (camera, ML Kit, TTS, theme, memory), DI, design system constants/theme |
| `features/splash/` | App boot: locator setup, theme load, camera+mic permission request, ML Kit warm-up |
| `features/goal_selection/` | Home menu (Shoot / Album / Settings) — despite the name, no goal/style-selection UI exists |
| `features/camera_session/` | Live camera screen: preview, zoom/focus, top nav, capture button, debug overlay |
| `features/reference_photo/` | Reference photo picking + one-shot deep ML analysis → `ReferenceProfile`; tolerance sliders |
| `features/scene_analysis/` | Live per-frame subject/scene analysis (pose, face, light) + EMA smoothing/tracking progress |
| `features/capture/` | Auto-capture gating logic + `Shot` construction from a capture |
| `features/editorial_score/` | 0–100 scoring of a shot against the reference, per-attribute breakdown |
| `features/voice_director/` | Compares live subject/scene to reference, produces the single spoken/displayed coaching phrase |
| `features/album/` | In-memory gallery of captured shots, diversity scoring, shot-type suggestions |
| `features/settings/` | Single dark-mode toggle |
| `shared/widgets/` | Reusable presentational widgets (buttons, badges, backgrounds, overlays) |

---

## Dependency Table

| Package | Used for | Exploitation | Evidence (if Partial/Minimal) |
|---|---|---|---|
| `camera` | Live preview, streaming, capture, zoom, lens switch | **Full** | — |
| `google_mlkit_pose_detection` | Live + reference-photo pose landmarks | **Full** | — |
| `google_mlkit_face_detection` | Live + reference-photo face analysis | **Partial** | `ml_kit_service.dart` — `FaceDetectorOptions(performanceMode: fast, enableTracking: true)`, no `enableClassification`/`enableContours`/`enableLandmarks`. Only `reference_image_analyzer.dart:98-103` sets all three. Only 2 `FaceDetectorOptions(` sites exist codebase-wide (confirmed by search). |
| `google_mlkit_selfie_segmentation` | Live + reference-photo body/background masking | **Minimal** | `ml_kit_service.dart:31-34` runs `SelfieSegmenter` every live frame; `scene_providers.dart:68-83`'s `sceneAnalysisListenerProvider` never reads `result.segmentationMask`. Both live call sites of `LightAnalyzer.analyzeLight()` (`camera_screen.dart:113`, `scene_providers.dart:99`) omit the optional `segmentationMask`/`subject` params. Only the reference-photo path (`reference_image_analyzer.dart:162-168`) uses the mask output. |
| `flutter_tts` | Spoken coaching phrases | **Full** | — |
| `flutter_riverpod` | State management throughout | **Full** | — |
| `hive` / `hive_flutter` | `MemoryService` — habits + album-state boxes | **Minimal** | `service_locator.dart` calls `sl<MemoryService>().init()`, opening both boxes, but no method on `MemoryService` (`getHabit`, `setHabit`, `recordCorrection`, `getAlbumValue`, `setAlbumValue`, etc.) has a call site anywhere outside `memory_service.dart` itself (confirmed by codebase-wide search). |
| `path_provider` | Listed in `pubspec.yaml` | **Unused (as provided)** | No import found in any of the 53 files. `[NEEDS CONFIRMATION]` — likely a transitive dep of `hive_flutter`, or a file not provided to this session. |
| `shared_preferences` | Dark-mode boolean persistence | **Full** (for its narrow scope) | — |
| `get_it` | Registers `CameraService`, `MlKitService`, `TtsService`, `MemoryService` | **Minimal** | Never resolved (`sl<T>()`) anywhere outside `service_locator.dart` except `sl<MemoryService>().init()`. All real service access goes through independent Riverpod providers that construct their own separate instances of the same classes (confirmed by codebase-wide search — see "Weaknesses" below). |
| `permission_handler` | Camera + microphone permission requests | **Partial** | `splash_screen.dart:21-25` requests and *requires* `Permission.microphone`, but no microphone/audio-recording code exists anywhere in the provided files; every `CameraController` is constructed with `enableAudio: false` (3 sites in `camera_service.dart`). |
| `google_mlkit_commons` | Shared ML Kit input types | **Full** (narrow scope) | Used only in `camera_screen.dart` for `InputImageRotationValue`/`InputImageRotation` — that is its entire intended job. |
| `gal` | Save captured photo to device gallery | **Full** | — |
| `image` | Pixel-level brightness/clutter analysis | **Full** | — |
| `palette_generator` | Dominant hue/warmth of reference photo | **Minimal** | `dominantHue`/`warmthScore` are computed and stored on `ReferenceProfile` (`reference_image_analyzer.dart:196-208`) but never read anywhere outside `reference_image_analyzer.dart`/`reference_profile.dart` (confirmed by codebase-wide search). |
| `image_picker` | Reference photo selection | **Full** | — |
| `flutter_launcher_icons` | Build-time icon generation | N/A (build tool, not runtime) | — |
| `hive_generator` / `build_runner` (dev deps) | Hive code generation | **Unused (as provided)** | No `@HiveType`/`@HiveField`/`part '*.g.dart'` found anywhere; `MemoryService` only stores raw dynamics/`Map`s, not typed objects. `[NEEDS CONFIRMATION]`. |

---

## End-to-End Data Flow

1. **Reference selection** — `camera_screen.dart` → taps reference icon → opens `ReferencePickerSheet` (modal sheet) → `image_picker` returns a path → `selectedReferenceImagePathProvider` is set.
2. **Reference analysis** — `referenceProfileProvider` (a `FutureProvider`) fires `ReferenceImageAnalyzer.analyze()`: runs `PoseDetector` (default options), `FaceDetector` (full options: contours/landmarks/classification, accurate mode), `SelfieSegmenter` (single mode), manual pixel decode for brightness/clutter, and `PaletteGenerator` for hue/warmth. Produces an immutable `ReferenceProfile`.
3. **Tolerance** — User adjusts 4 sliders (pose/composition/expression/color, default 0.5 each) in the same sheet → `toleranceSettingsProvider`.
4. **Live per-frame loop** (`camera_screen.dart._onFrame`, throttled to ~80ms):
  - A local `LightAnalyzer` field computes scene brightness/light-direction/negative-space/symmetry/clutter directly from the raw `CameraImage` (no segmentation mask passed in — see Fragile Spots).
  - `TrackingEngine.smoothScene()` EMA-smooths the result into `sceneProfileProvider`.
  - The frame is separately handed to `mlKitService.processImage()`, which runs pose + face + selfie-segmentation asynchronously (drops the frame if still busy on a prior one) and publishes an `MlKitAnalysisResult` on a broadcast stream.
5. **Live subject analysis** — `sceneAnalysisListenerProvider` (a *different* set of analyzer instances than the ones camera_screen.dart declares locally — see Fragile Spots) consumes that stream: `PoseAnalyzer` + `FaceAnalyzer` compute raw pose/face fields, `TrackingEngine.smoothSubject()` EMA-smooths → `subjectProfileProvider`.
6. **Target derivation** — `targetSubjectProfileProvider` builds the "goal" pose either from the selected `ReferenceProfile` or a generic fallback (facing camera, smiling, eyes open).
7. **Tracking progress** — `trackingProgressProvider` averages per-attribute similarity between current and target subject profile (0–1).
8. **Coaching** — `nextActionProvider` runs `ReferenceComparisonEngine.evaluate()`: compares subject+scene to reference across 6 attributes via `ComparisonMath`, keeps only attributes exceeding their tolerance threshold, returns the single highest-severity one. `voiceDirectorListenerProvider` debounces 400ms, dedupes vs. the last spoken phrase, and calls `ttsService.speak()`; the same phrase is shown as an on-screen chip.
9. **Scoring** — `currentScoreProvider` independently recomputes a 0–100 `EditorialScore` (composition/lighting/expression/background/story, equally weighted) any time the watched state changes.
10. **Auto-capture gate** — `shouldCaptureProvider` re-evaluates `AutoCaptureService.shouldCapture()` on every state change: requires `eyesOpen == true`, brightness ≥ 0.2, shoulder/face angle within tolerance, clutter ≤ 5, tracking progress ≥ 0.9, and a 1500ms cooldown.
11. **If the gate passes** — `autoCaptureProvider`'s listener calls `triggerCapture()` (stamps a cooldown timestamp only — **does not take a photo**), builds a `Shot` with `imagePath: null` via `buildShotFromCapture()`, and pushes it through `capturedShotProvider`, which `camera_screen.dart` picks up and adds to the album.
12. **Manual capture** — The always-visible "Capture" button calls `cameraService.capture()` directly (a real photo, saved via `gal`), builds a `Shot` with a real `imagePath`, and adds it to the album immediately — this is the only path that produces an actual saved image.
13. **Album** — `AlbumScreen` renders `AlbumState.shots`, computing `diversityScore()` and `suggestNextShotType()` from a fixed 5-type taxonomy. `AlbumNotifier` is a plain in-memory `StateNotifier` — nothing is written to `MemoryService`/Hive, so **the album does not survive app restart**.

### Fragile Spots / Unhandled Edge Cases Found

- **Auto-capture is very unlikely to ever fire.** The live `FaceDetector` (`ml_kit_service.dart`) never sets `enableClassification: true`, so `smilingProbability`/`leftEyeOpenProbability`/`rightEyeOpenProbability` are almost certainly always `null` on live frames. `face_analyzer.dart` derives `eyesOpen` from those probabilities, so it stays `null`/never-true, and `AutoCaptureService.shouldCapture()` hard-gates on `subject.eyesOpen != true` returning `false` first thing. *(Confirmed by direct code read; ML Kit's classification-gating behavior is documented API contract, not a line I could read in the plugin itself.)*
- **Even if it did fire, auto-capture wouldn't save a photo.** `AutoCaptureService.triggerCapture()` only stamps a timestamp; `capture_providers.dart` always builds the resulting `Shot` with `imagePath: null`. Only the manual capture button calls `CameraService.capture()`.
- **Selfie segmentation runs on every live frame for no benefit.** The mask ML Kit computes every frame in `ml_kit_service.dart` is never read by anything downstream — real CPU/battery cost, zero payoff, on the live path only.
- **No image → no visual feedback on auto-captured shots.** Since `imagePath` is `null`, `AlbumScreen`'s `_ShotTile`/`ShotDetailScreen` fall back to a blank colored container for these entries.
- **Two redundant analyzer instantiations.** `camera_screen.dart` declares its own `PoseAnalyzer`/`FaceAnalyzer` fields that are never called; the actually-active instances live in `scene_providers.dart`'s providers.
- **A dead listener provider.** `lightAnalysisListenerProvider` (`scene_providers.dart`) is fully wired but never watched anywhere; live light analysis actually happens through `camera_screen.dart`'s own direct call to its local `LightAnalyzer` field instead.
- **The album has no persistence** despite `MemoryService`/Hive being fully initialized for exactly this purpose.
- **Microphone permission is required to pass the splash screen**, even though the app has no microphone/audio-recording feature anywhere.

---

## Strengths

- **Centralized comparison math.** `ComparisonMath` (`features/reference_photo/domain/comparison_math.dart`) is genuinely shared and reused by three independent consumers — `auto_capture_service.dart`, `score_calculator.dart`, and `reference_comparison_engine.dart` (confirmed by codebase search) — avoiding threshold-logic drift between the auto-capture gate, the coaching engine, and the scoring engine.
- **Consistent design-system usage.** Every screen pulls colors/typography from `Theme.of(context).extension<AppColors>()!` rather than hardcoding values; `AppTheme._build()` is the single source of both light and dark `ThemeData`.
- **Defensive ML Kit frame handling.** `ml_kit_service.dart`'s `_busy` flag drops incoming frames while a previous frame is still processing, avoiding an unbounded backlog under load.
- **Consistent smoothing strategy.** `TrackingEngine` applies the same EMA (`alpha=0.3`) + 2-frame debounce pattern to every noisy per-frame field on both `SubjectProfile` and `SceneProfile`, giving predictable, centrally-tunable jitter reduction.
- **UX polish details that are easy to skip and weren't.** TTS phrase dedup + 400ms debounce (`voice_providers.dart`) prevents audio spam from rapidly-changing coaching states; `didChangeAppLifecycleState` in `camera_screen.dart` correctly pauses the image stream when backgrounded and resumes it only if it was previously active.
- **Sensible accuracy/performance tradeoff by design.** The reference-photo analyzer intentionally uses the expensive, full-feature ML Kit options (`FaceDetectorMode.accurate`, full contours/landmarks/classification) since it runs once per reference selection, while the live pipeline uses the cheap/fast options — the right instinct, even though the live side currently under-uses the classification data it *does* need (see Weaknesses).

---

## Weaknesses / Technical Debt

1. **Auto-capture is functionally broken in two independent ways** — the `eyesOpen`-never-true gate and the `imagePath`-always-null capture (see Fragile Spots above).
2. **Live selfie segmentation is computed and fully discarded every frame.**
3. **Two parallel, non-unified DI systems.** `get_it` registers `CameraService`/`MlKitService`/`TtsService`/`MemoryService` as singletons, but every Riverpod provider that needs one of these classes constructs its own separate instance instead of resolving through `sl`. The GetIt-registered instances are orphaned except for `MemoryService.init()`.
4. **`MemoryService`/Hive is fully wired but entirely unused for reads/writes** outside its own file — habit-tracking and album persistence don't actually happen.
5. **Dead code:** `camera_screen.dart`'s local `_poseAnalyzer`/`_faceAnalyzer` fields; `scene_providers.dart`'s `lightAnalysisListenerProvider`; `debug_flags.dart`'s `kDebugPerfOverlay` (superseded by Flutter's built-in `kDebugMode`); 15 of 24 `AppStrings` constants (including the entire `goalSelectionTitle`/canned-coaching-phrase set, which look like leftovers from an earlier design that `ReferenceComparisonEngine`'s dynamic phrases superseded).
6. **`SceneProfile.depthEstimate` is a permanent stub** (`LightAnalyzer._estimateDepth()` always returns `null`), which makes the "story" component of every `EditorialScore` a fixed `53/100`, never actually varying shot to shot.
7. **Reference-photo analysis computes significantly more than the live pipeline can ever compare against:** detailed face contours (oval/eyes/eyebrows/lips/nose), `dominantHue`/`warmthScore`, X/Z face angles, and the reference's own `backgroundClutterCount` are all computed and stored on `ReferenceProfile` but never read anywhere downstream.
8. **Microphone permission requirement with no microphone feature** — unnecessary onboarding friction; a user who denies mic access is fully blocked from an app that never uses the mic.
9. **Two widgets with no confirmed call site** in the provided files: `AlbumButton` (`camera_session/presentation/widgets/album_button.dart`) and `TargetZoneOverlay` (`shared/widgets/target_zone_overlay.dart`). `[NEEDS CONFIRMATION]` — an unseen file may use either.
10. **Unresolved file-location discrepancy:** `scene_providers.dart` imports `TrackingEngine` from `package:cuemera/core/services/tracking_engine.dart`, but the file's own header comment says `features/scene_analysis/services/tracking_engine.dart`. `[NEEDS CONFIRMATION]` — one of the two is stale.
11. **A duplicate/conflicting version of `reference_comparison_engine.dart` was uploaded during this session** — one using inline math with an absolute import, one using `ComparisonMath` with a relative import. The `ComparisonMath`-based version is what persisted on disk and is treated as authoritative throughout this document, but this is worth double-checking against the real repo. `[NEEDS CONFIRMATION]`.

---

## Known Limitations of Underlying Tech

- ML Kit's pose/face detectors are trained on real photographs of people and are known to perform poorly or fail entirely on illustrations, anime, drawings, or heavily stylized images. The team is already aware of this — `reference_picker_sheet.dart` shows an explicit "No pose or face detected... works best with real photos of people, not illustrations or drawings" warning when detection comes back empty.
- ML Kit's face-classification outputs (`smilingProbability`, `leftEyeOpenProbability`, `rightEyeOpenProbability`) are `null` unless `enableClassification: true` is explicitly set on `FaceDetectorOptions` — an easy option to forget, and the live pipeline currently has forgotten it (see Fragile Spots).
- Selfie segmentation is computationally nontrivial; running it on every live camera frame carries a real, ongoing battery/thermal cost independent of whether anything consumes its output.
- The EMA + 2-frame-debounce smoothing strategy trades a small amount of responsiveness lag (state changes take ~2 frames to register) for resistance to noisy per-frame ML output — a reasonable and common tradeoff, but worth knowing about (`_emaAlpha = 0.3`, `_debounceFrames = 2` in `tracking_engine.dart`) before tuning perceived responsiveness.

---

## Project Structure Map

```
lib/
├── main.dart                                   # App entry: ProviderScope, MaterialApp, home=SplashScreen
│                                                # → to change app-wide theme wiring, edit here
│
├── core/
│   ├── constants/
│   │   ├── app_colors.dart                     # ThemeExtension<AppColors> — light/dark palettes
│   │   │                                        # → to change any app color, edit here
│   │   ├── app_spacing.dart                    # xs..xxl spacing scale
│   │   ├── app_strings.dart                    # String constants (15/24 currently unused — see Weaknesses #5)
│   │   ├── app_typography.dart                 # Text styles + TextTheme builder
│   │   │                                        # → to change any font size/weight, edit here
│   │   └── debug_flags.dart                    # kDebugPerfOverlay — currently dead, see Weaknesses #5
│   ├── di/
│   │   └── service_locator.dart                # get_it registrations — currently orphaned, see Weaknesses #3
│   ├── services/
│   │   ├── camera_service.dart                 # 3 CameraController lifecycle, capture, gallery save
│   │   │                                        # → to change resolution presets/zoom/capture flow, edit here
│   │   ├── memory_service.dart                 # Hive wrapper — wired but unused, see Weaknesses #4
│   │   ├── ml_kit_service.dart                 # Live pose+face+segmentation pipeline
│   │   │                                        # → to change live FaceDetector/PoseDetector options
│   │   │                                          (e.g. to fix the eyesOpen bug), edit here
│   │   ├── theme_preference_service.dart        # Dark-mode toggle persistence
│   │   └── tts_service.dart                     # flutter_tts wrapper, phrase dedup
│   │                                             # → to change speech rate/pitch/voice, edit here
│   └── theme/
│       └── app_theme.dart                       # ThemeData builder (light/dark)
│
├── features/
│   ├── splash/presentation/screens/
│   │   └── splash_screen.dart                   # Boot sequence, permission requests
│   │                                             # → to change required permissions, edit splashInitProvider here
│   │
│   ├── goal_selection/presentation/
│   │   ├── screens/goal_selection_screen.dart    # Home menu (Shoot/Album/Settings)
│   │   └── widgets/goal_card.dart                # EditorialMenuCard — glassmorphic menu card
│   │
│   ├── camera_session/presentation/
│   │   ├── screens/camera_screen.dart            # Orchestration hub — the single largest/most central file
│   │   │                                         # → to change per-frame processing, throttle, or which
│   │   │                                           providers drive the live screen, edit _onFrame() here
│   │   └── widgets/
│   │       ├── camera_preview_layer.dart         # Preview + pinch-zoom + tap-to-focus gesture surface
│   │       ├── camera_top_nav_bar.dart            # Top icon row (2 of 5 icons are no-op stubs)
│   │       ├── debug_perf_overlay.dart            # Debug-only FPS + auto-capture condition dump
│   │       ├── focus_ring.dart                    # Tap-to-focus visual feedback
│   │       ├── phrase_chip.dart                   # Renders the current coaching phrase
│   │       └── album_button.dart                  # No confirmed call site — see Weaknesses #9
│   │
│   ├── reference_photo/
│   │   ├── domain/
│   │   │   ├── comparison_math.dart               # Shared deviation/threshold/similarity math
│   │   │   │                                       # → to change any tolerance-threshold formula, edit here
│   │   │   └── models/
│   │   │       ├── reference_profile.dart         # The full analyzed-reference data model
│   │   │       └── tolerance_settings.dart        # 4 tolerance sliders' backing model
│   │   ├── services/
│   │   │   └── reference_image_analyzer.dart      # One-shot deep ML analysis of the reference photo
│   │   │                                          # → to change what's extracted from the reference, edit here
│   │   ├── providers/reference_providers.dart      # selectedReferenceImagePathProvider → referenceProfileProvider
│   │   └── presentation/widgets/
│   │       └── reference_picker_sheet.dart         # Picker UI + skeleton/face overlay painter + sliders
│   │
│   ├── scene_analysis/
│   │   ├── domain/models/
│   │   │   ├── scene_profile.dart                 # Per-frame scene data model
│   │   │   └── subject_profile.dart               # Per-frame subject (person) data model
│   │   ├── services/
│   │   │   ├── pose_analyzer.dart                  # Raw pose landmarks → shoulder angle, body ratio
│   │   │   ├── face_analyzer.dart                  # Raw face → eyesOpen/expression (currently broken live, see Fragile Spots)
│   │   │   │                                       # → to fix the eyesOpen bug from the *consumer* side, this
│   │   │   │                                         file is where eyesOpen/expression are derived
│   │   │   ├── light_analyzer.dart                 # Brightness/light-direction/clutter/negative-space/symmetry
│   │   │   │                                       # → to implement real depth estimation, replace
│   │   │   │                                         _estimateDepth() here
│   │   │   └── tracking_engine.dart                # EMA smoothing + debounce + trackingProgress()
│   │   │                                           # [path discrepancy — header comment says this location,
│   │   │                                             but scene_providers.dart imports it from core/services/]
│   │   └── providers/scene_providers.dart          # Wires all of the above; sceneAnalysisListenerProvider is
│   │                                                # the active live listener; lightAnalysisListenerProvider
│   │                                                # is dead code (see Weaknesses #5)
│   │
│   ├── capture/
│   │   ├── domain/shot_builder.dart                # Pure function: inputs → scored Shot
│   │   ├── services/auto_capture_service.dart       # shouldCapture() gate logic
│   │   │                                            # → to change auto-capture trigger conditions, edit here
│   │   └── providers/capture_providers.dart          # Reactive gate + the (currently no-photo) auto-capture flow
│   │
│   ├── editorial_score/
│   │   ├── domain/score_calculator.dart              # 0–100 scoring, 5 equally-weighted sub-scores
│   │   │                                             # → to change scoring weights/formula, edit here
│   │   └── providers/score_providers.dart             # currentScoreProvider
│   │
│   ├── voice_director/
│   │   ├── domain/
│   │   │   ├── priority_engine.dart                  # PriorityAction data class
│   │   │   └── reference_comparison_engine.dart       # Picks the single worst-offending attribute to coach on
│   │   │                                             # → to change which attributes are coached or their
│   │   │                                               phrasing, edit here
│   │   └── providers/voice_providers.dart              # Debounce + TTS dispatch
│   │
│   ├── album/
│   │   ├── domain/models/
│   │   │   ├── shot.dart                             # Single captured/auto-captured shot record
│   │   │   └── album_state.dart                       # Shot list + diversityScore()/suggestNextShotType()
│   │   ├── providers/album_providers.dart              # In-memory StateNotifier — no persistence, see Weaknesses #4
│   │   └── presentation/screens/album_screen.dart       # Grid + detail view + delete
│   │
│   └── settings/presentation/screens/settings_screen.dart  # Dark-mode toggle only
│
└── shared/widgets/
    ├── app_background.dart                          # Studio-photography-themed custom-painted background
    ├── primary_button.dart                           # Standard CTA button
    ├── score_badge.dart                              # Color-coded score circle (≥80 success/≥50 accent/else warning)
    └── target_zone_overlay.dart                      # No confirmed call site — see Weaknesses #9

pubspec.yaml                                          # Dependency table above is derived from this file
```

*This tree is built from the `//`-comment path header at the top of each file, cross-checked against import statements wherever both were available. Where the two disagreed (`tracking_engine.dart` only), the discrepancy is called out inline rather than guessed at. No file/asset not provided to this session is reflected here.*