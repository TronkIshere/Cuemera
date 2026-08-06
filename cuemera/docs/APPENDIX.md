# Appendix

## Coding conventions observed

- **State management:** Riverpod throughout (`Provider`, `StateProvider`, `StateNotifierProvider`, `FutureProvider`), the only DI/state mechanism in the app since `get_it` was removed.
- **Immutable models with `copyWith`:** every domain model (`SubjectProfile`, `SceneProfile`, `ReferenceProfile`, `ToleranceSettings`, `DetectionThresholds`, `AlbumState`, `AppColors`) follows the same `const` constructor + `copyWith` pattern. `ToleranceSettings` and `EditorialScore` also now have `toMap()`/`fromMap()` for persistence, matching `Shot`'s existing pattern. **Bug found and fixed in `SubjectProfile.copyWith` this session:** the `value ?? this.value` pattern silently discarded any explicitly-passed `null`, so callers intending to clear a stale field (`face_analyzer.dart`, `pose_analyzer.dart`) never actually did. Fixed with a sentinel-object default per parameter. **Audit of the other models sharing this convention:** `SceneProfile.copyWith` has the exact same bug, confirmed actively triggered — `light_analyzer.dart` passes explicit `null` for `lightDirectionDegrees`/`depthEstimate` when no clear signal exists that frame, and it's silently swallowed, not yet fixed. `ReferenceProfile.copyWith` has the same syntactic pattern but isn't triggered in practice (built once via full constructor in `reference_image_analyzer.dart`, never incrementally patched). `ToleranceSettings.copyWith` is fine — all 4 fields are non-nullable, so there's no null-clearing case to hit. `DetectionThresholds`, `AlbumState`, and `AppColors` remain unaudited.
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

The app requests only the camera permission on launch. If the on-device ML Kit models fail to initialize (repeated per-frame failures), a persistent in-app banner now explains that pose/face detection, coaching, and auto-capture are unavailable — manual capture still works. If a captured photo fails to save to the device gallery, a snackbar now says so (the photo is still kept in the in-app album either way). **Changed this session:** `CameraService.capture()` now reuses the already-running preview controller instead of creating a dedicated `ResolutionPreset.max` controller per photo — captured photos are `ResolutionPreset.high` instead of `max`, trading resolution for eliminating the per-capture controller setup/teardown cost entirely.

## Testing

`test/` covers seven pure-Dart logic files: `comparison_math.dart`, `score_calculator.dart`, `tracking_engine.dart`, `album_state.dart`, `auto_capture_service.dart`, and — new this session — `reference_comparison_engine.dart` (a new test file covering the 3-tier priority fallthrough, severity tiering, and the newly-directional attributes) plus an extension of `tracking_engine_test.dart` covering the 4 fields `smoothSubject` previously dropped (`faceAngleXDegrees`, `faceAngleZDegrees`, `mouthOpenRatio`, `eyeOpenRatio`). Run via `flutter test`; confirmed passing (86 tests) against the current codebase, including this session's `subject_profile.dart`/`tracking_engine.dart` fix. Not yet covered: anything touching ML Kit types directly (`face_analyzer.dart`, `reference_image_analyzer.dart`, `expression_classifier.dart`), `camera_service.dart` (its `capture()` redesign this session touches real camera hardware, not unit-testable the way the pure-Dart layer is), and any widget-level testing.

## Next Steps Checklist

This checklist previously duplicated items also tracked in `LIMITATIONS_AND_ROADMAP.md`, and the two drifted out of sync — several items below were completed while this list still showed them open. To avoid that recurring, this file no longer maintains its own copy: see `LIMITATIONS_AND_ROADMAP.md` for the current, single source of truth on what's outstanding (physical-device testing, product decisions, test coverage/code audit, and the model-driven upgrade).