# Appendix

## Coding conventions observed

- **State management:** Riverpod throughout (`Provider`, `StateProvider`, `StateNotifierProvider`, `FutureProvider`), the only DI/state mechanism in the app since `get_it` was removed.
- **Immutable models with `copyWith`:** every domain model (`SubjectProfile`, `SceneProfile`, `ReferenceProfile`, `ToleranceSettings`, `DetectionThresholds`, `AlbumState`, `AppColors`) follows the same `const` constructor + `copyWith` pattern. `ToleranceSettings` and `EditorialScore` also now have `toMap()`/`fromMap()` for persistence, matching `Shot`'s existing pattern.
- **Theme access:** always `Theme.of(context).extension<AppColors>()!`, never raw hex values in widget code.
- **File header comments:** every file begins with a `// <path>` comment stating its intended location, and this now matches every file's real location.
- **Error handling style:** centralized as of this session. `ErrorReportingService.instance.report(error, stackTrace, {context})` is now the standard call from any `catch` block that would otherwise be silent — used in `reference_image_analyzer.dart` (5 sites), `album_providers.dart` (3 sites), `camera_service.dart` (gallery save), and `ml_kit_service.dart` (per-frame processing). `FlutterError.onError`, `PlatformDispatcher.instance.onError`, and `runZonedGuarded` in `main.dart` route framework/platform/async errors through the same service. `light_analyzer.dart` and `pose_analyzer.dart` contain no `try`/`catch` at all, so nothing needed changing there.
- **No inline code comments beyond file headers** — still true, with the same one exception (`expression_classifier.dart`'s brief doc-comment) plus new doc-comments on `ErrorReportingService` and the `DetectionThresholds`/schema-versioning additions, which are deliberately more explanatory since they're extension points for future work.
- **English-only user-facing strings.** No localization framework in the dependency tree, still.

## Environment setup

```
flutter pub get
```

Requires (per `pubspec.yaml`): Dart SDK `^3.8.1`, and native camera + ML Kit + gallery-write capability on the target device (physical device or emulator with camera support — ML Kit pose/face/segmentation models require Google Play Services on Android). `get_it`, `hive_generator`, and `build_runner` remain removed; `hive`/`hive_flutter`/`path_provider` remain load-bearing (album persistence, now with schema versioning).

No `.env`, flavors, or build-time configuration exist — all values are compiled-in constants.

## Running the project

```
flutter run
```

The app requests only the camera permission on launch. If the on-device ML Kit models fail to initialize (repeated per-frame failures), a persistent in-app banner now explains that pose/face detection, coaching, and auto-capture are unavailable — manual capture still works. If a captured photo fails to save to the device gallery, a snackbar now says so (the photo is still kept in the in-app album either way).

## Testing

`test/` now exists, covering the five pure-Dart logic files the roadmap called out as the cheapest starting point: `comparison_math.dart`, `score_calculator.dart`, `tracking_engine.dart`, `album_state.dart`, `auto_capture_service.dart`. Run via `flutter test`; confirmed passing (65 tests) against this session's codebase. Not yet covered: anything touching ML Kit types directly (`face_analyzer.dart`, `reference_image_analyzer.dart`, `expression_classifier.dart`) or any widget-level testing.

## Next Steps Checklist

- [ ] Fix `bodyRatio` in `reference_image_analyzer.dart` to use the same confidence-filtered landmarks as `poseLandmarkPoints`, instead of raw landmarks that bypass the filter (found via the pose-skeleton preview bug — likely affects scoring/tracking for partial-body reference photos, not just the preview)
- [ ] Verify the `planes[1]=U, planes[2]=V` assumption in `LightAnalyzer._estimateColorTone` against real device camera streams (needs physical-device testing)
- [ ] Decide whether to redesign `CameraService.capture()`'s per-photo controller lifecycle — its latency is now instrumented (`lastCaptureControllerSetupLatency`/`lastCaptureShutterLatency`/`lastCaptureControllerTeardownLatency`), pending real numbers from real devices
- [ ] Run `ReferenceImageAnalyzer.analyze()`'s independent steps concurrently (`Future.wait`) to cut reference-photo-picking latency
- [ ] Wire `ErrorReportingService` to a real remote sink (Crashlytics/Sentry/custom backend) once one is chosen — currently local-only, reports don't survive app restart
- [ ] Replace `ReferenceComparisonEngine`'s severity-tiered-but-still-hardcoded phrase bank with an on-device GenAI call (Gemini Nano/ML Kit GenAI on Android, Apple Foundation Models on iOS), keeping the current phrase bank as the fallback for unsupported devices/regions
- [ ] Fold the unified expression classifier into that same modeling effort
- [ ] Scope a Quality Engine (aesthetic scoring model) — no ready-made on-device model exists; likely a NIMA-style CNN fine-tuned and exported to LiteRT, needing a labeled dataset first
- [ ] Expand widget/integration test coverage beyond the current pure-Dart layer, and ideally add a real-device test pass for camera-orientation issues (the front-camera rotation bug found this session wouldn't have been caught by the existing pure-Dart unit tests)