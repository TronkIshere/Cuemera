# Cuemera — AI Session Log

This file is **append-only**. Every AI onboarding/work session gets a new dated entry added at the **top** of the log (immediately below this header), directly above the previous most-recent entry. Never delete, rewrite, or reorder previous entries — if something in an old entry turns out to be wrong, add a note in a new entry correcting it rather than editing the old one. This preserves the actual history of what was known/found/done at each point in time.

Companion file: `PROJECT_STATUS.md` (overwritten snapshot of current truth — read that first for "what is this codebase right now"; read this file for "what has been done to/learned about it over time").

---

## 2026-08-05 — Initial onboarding & investigation session

**Scope:** Pure investigation, no code written. Read all 53 `.dart` files + `pubspec.yaml` provided (uploaded incrementally across the session), grouped by feature folder, cross-referenced path-comment headers against actual import statements, and ran codebase-wide `grep` searches before making any capability-used/unused claim (per the process this file's predecessor prompt required). Produced `PROJECT_STATUS.md` from the results.

**What was NOT covered:** `assets/`, `test/`, `android/`, `ios/`, `analysis_options.yaml`, and any file not uploaded to this session. No code was run, built, or tested — all findings are static-analysis-by-reading, not runtime-verified.

### Key findings this session

- **Two confirmed, independent bugs in the auto-capture feature:**
    1. The live `FaceDetector` (`ml_kit_service.dart`) never sets `enableClassification: true`, so `eyesOpen` almost certainly never becomes `true` on the live pipeline, and `AutoCaptureService.shouldCapture()` hard-gates on it first — auto-capture is very unlikely to ever fire.
    2. Even when the gate does pass, `AutoCaptureService.triggerCapture()` only stamps a cooldown timestamp; it never calls `CameraService.capture()`. The resulting `Shot` always has `imagePath: null`. Only the manual "Capture" button takes a real photo.
- **Live selfie segmentation runs every frame and is fully discarded** — computed in `ml_kit_service.dart`, never read by `sceneAnalysisListenerProvider` or either live call site of `LightAnalyzer.analyzeLight()`.
- **Two parallel, unreconciled DI systems** — `get_it` registers 4 singletons that are essentially orphaned; every Riverpod provider constructs its own separate instance of the same classes instead.
- **`MemoryService`/Hive is fully initialized but has zero read/write call sites anywhere else** — the album has no persistence despite the infrastructure existing for it.
- **A meaningful amount of computed reference-photo data is never consumed downstream**: detailed face contours, dominant hue/warmth, X/Z face angle, and the reference's own background-clutter count are all computed and stored but never read again.
- **Dead code found:** `camera_screen.dart`'s local `PoseAnalyzer`/`FaceAnalyzer` fields; `lightAnalysisListenerProvider`; `debug_flags.dart`'s `kDebugPerfOverlay`; 15 of 24 `AppStrings` constants (including an apparent leftover "goal selection" / canned-coaching-phrase design that's been superseded).
- **Microphone permission is required at splash but the app has no microphone feature anywhere** — unnecessary onboarding friction.
- **`SceneProfile.depthEstimate` is permanently stubbed to `null`**, making the "story" component of every editorial score a fixed 53/100.
- Full dependency capability-vs-usage table and evidence notes are in `PROJECT_STATUS.md` — not duplicated here.

### Unresolved / flagged for confirmation against the real repo

- `tracking_engine.dart`'s header comment (`features/scene_analysis/services/`) disagrees with how `scene_providers.dart` imports it (`core/services/`). Could not determine which is correct without the actual file tree — only flat file uploads were available this session.
- Two versions of `reference_comparison_engine.dart` were uploaded with different implementations (inline math vs. `ComparisonMath`-based). The `ComparisonMath`-based version is what persisted on disk and was treated as authoritative, but this is worth a manual check against the real repo.
- `AlbumButton` and `TargetZoneOverlay` widgets are fully implemented with no confirmed instantiation site in the files provided — may be used by a file not uploaded this session.
- `path_provider`, `hive_generator`, and `build_runner` show no usage in the provided files — plausible but unconfirmed that they're genuinely unused (vs. used in an unseen file).

### Suggested next steps / open opportunities

1. **Fix the auto-capture pipeline** — add `enableClassification: true` to the live `FaceDetectorOptions` in `ml_kit_service.dart`, and make `AutoCaptureService.triggerCapture()` (or its caller in `capture_providers.dart`) actually call `CameraService.capture()` so auto-captured shots have a real image.
2. **Either wire up `MemoryService` or remove it** — right now it's dead weight that opens two Hive boxes for nothing. If album persistence across restarts is wanted, this is the natural place to add it.
3. **Reconcile the two DI systems** — either drop `get_it` entirely in favor of the Riverpod providers already doing the real work, or have the Riverpod providers resolve through `sl` instead of constructing duplicate instances.
4. **Drop the microphone permission requirement** from `splash_screen.dart` unless a voice-input feature is planned — as written it can block users from an app that never uses the mic.
5. **Decide whether to consume or remove the discarded live selfie-segmentation output** — either wire the mask into `LightAnalyzer`'s composition estimates (which already accept it as an optional param) for a real accuracy improvement, or stop running the segmenter live to save battery.
6. **Clean up dead code** identified above (`kDebugPerfOverlay`, unused `AppStrings`, the local unused analyzer fields in `camera_screen.dart`, `lightAnalysisListenerProvider`) — low-risk, improves future-session signal-to-noise.
7. **Confirm the `tracking_engine.dart` file location** and the authoritative `reference_comparison_engine.dart` implementation directly against the real repo, since this session only had flat file uploads to work from.
8. **Consider whether the reference photo's unused richer data** (contours, hue/warmth, X/Z angle, its own clutter count) should feed into scoring/coaching, or whether it's genuinely not needed and the analyzer should stop computing it to save time on reference selection.