// test/full_pipeline_test.dart
//
// One comprehensive test file for Cuemera's coaching pipeline — front
// camera vs back camera, the comparison engine, scoring, tracking,
// auto-capture, and shot building — using synthetic (fixture) profiles
// instead of a real camera or real ML Kit detection.
//
// UPDATED THIS SESSION — see the dedicated groups/tests below for detail:
//   - shoulderBalance's front/back mirror-flip in
//     _evaluateShoulderBalance was found to be an unverified, unjustified
//     bug (no coordinate-level mirroring exists anywhere upstream) and
//     removed — front and back camera now produce the SAME direction for
//     the same numeric mismatch. The old test asserting the opposite has
//     been rewritten into a regression test documenting why; see
//     "ReferenceComparisonEngine" group, first test.
//   - AutoCaptureService._shoulderBalanceOk used relativeDeviation while
//     its own coaching counterpart used absolute deviation — since
//     shoulderBalanceRatio targets are typically small numbers (e.g.
//     0.18, a real reference photo's measured value), this silently
//     over-blocked capture. Fixed to match; regression test in the
//     "AutoCaptureService" group.
//   - ToleranceSettings gained bodyYawTolerance, decoupled from
//     poseTolerance specifically because bodyYaw (derived from ML Kit's
//     noisy per-landmark z/depth estimate) needed to be loosenable
//     without also loosening the x/y-based pose attributes that share
//     poseTolerance. New dedicated group: "bodyYawTolerance — decoupled
//     from poseTolerance".
//   - Arm-position evaluation (_evaluateRightArmPosition/
//     _evaluateLeftArmPosition, previously only in the standalone,
//     not-confirmed-wired pose_and_face_evaluators.dart) has been ported
//     into reference_comparison_engine.dart and wired into
//     evaluateTiers() — see the updated "Arm-pose coaching" group header
//     and the new "ReferenceComparisonEngine — arm position & arm-swap"
//     group, which tests the actual production path rather than only
//     the standalone functions.
//   - New evaluateArmSwap / _evaluateArmSwap: detects the common
//     mirrored-pose mistake (raising the wrong arm / wrong hand on the
//     hip) and fires a single "switch your arms" message instead of two
//     separate, confusing per-arm corrections. Covered in both the
//     standalone-function group and the engine-integration group above.
//
// SCOPE — what this file covers:
//   - MlKitService.rotationFor(): the pure per-lens rotation-compensation
//     formula (front vs back), which is what the sixth-session rotation
//     bug and every "*IsMirrored" flag ultimately sit on top of.
//   - ComparisonMath: the shared circular/relative-deviation primitives
//     every evaluator is built from.
//   - ReferenceComparisonEngine: front-vs-back mirrored direction (now
//     confirmed IDENTICAL for shoulderBalance — see above; still
//     genuinely flipped and unverified for faceRoll/faceYaw/bodyYaw's
//     phrase-direction logic, which reads a different signal source
//     [ML Kit's own headEulerAngle / landmark z] with no independent way
//     to verify sign convention the way shoulderBalance was verified —
//     not changed, deliberately), the seventeenth-session
//     confidence-wiring fix, root-cause collapsing, and the
//     sixteenth-session tier-rotation-only-advances-on-a-real-pick fix.
//   - score_calculator: the sixteenth-session "missing signal is omitted,
//     not diluted with a placeholder" fix.
//   - TrackingEngine: circular EMA across the ±180° wrap, missing-value
//     debounce, and trackingProgress scoring.
//   - AutoCaptureService: brightness/tracking-progress/cooldown gates, an
//     asymmetry this file found while writing these tests (see the
//     dedicated test + the chat message for details), the
//     relativeDeviation/absolute-deviation scale mismatch on
//     shoulderBalance (see above), and bodyYawTolerance's independence
//     from poseTolerance at the capture-gate level (see above).
//   - shot_builder / Shot: the actual capture endpoint, including a
//     toMap/fromMap round trip.
//   - expression_classifier.classifyExpression: a small standalone pure
//     function, included because it was sent for this file.
//   - A combined front-camera and back-camera end-to-end narrative tying
//     all of the above together.
//   - CorrectionRecord._classify() (correction_feedback.dart): including a
//     regression test for a circular-quantity misclassification bug found
//     and fixed this session.
//   - CoachingEligibility (coaching_eligibility.dart): gate ordering, and a
//     documented (not asserted-as-bug) finding about the default
//     cameraFacingChannelEnabled=false blocking all non-subjectAction
//     coaching.
//   - ResponsivenessModel (adaptive_correction_model.dart): intensity
//     adjustment from observed correction gain.
//   - CoachingStateMachine (coaching_state_machine.dart): a full
//     observe->instruct->wait->reobserve->confirm cycle, retry-then-escalate
//     on unmeasurable readings, and session-memory suppression after
//     repeated reversals.
//
// EXPLICITLY OUT OF SCOPE (by design — see the chat thread this file was
// delivered in):
//   - Real camera hardware, real ML Kit detection accuracy, real device
//     mirroring correctness. LIMITATIONS_AND_ROADMAP.md §1 is explicit that
//     those still need a real front/back device comparison — a test file
//     cannot look at a photo and tell whether it's mirrored.
//   - MlKitService.processImage()/dispose() and anything on CameraService —
//     both go through native platform channels. This file constructs
//     MlKitService() (to reach the pure rotationFor() method) but never
//     calls processImage()/dispose() on it, since those are expected to
//     require plugin/platform-channel setup this file does not provide.
//     If simply constructing MlKitService() throws in your environment,
//     that's useful information — report the error back and the
//     rotationFor() tests can be restructured around it (e.g. extracting
//     the formula into a standalone top-level function).
//   - AppTtsService's new `interrupt` parameter (added this session,
//     stops in-progress playback and resets the speak() queue for
//     time-critical phrases like "Hold still."). Untested here for the
//     same reason as camera/MlKitService above: AppTtsService's actual
//     behavior only matters once wired to SherpaTtsService/TtsService,
//     both of which go through native plugins (sherpa_onnx bindings,
//     audioplayers, flutter_tts platform channels) this file cannot
//     construct. The interrupt/queue-reset logic itself is pure Future
//     chaining and could be unit-tested in isolation if AppTtsService
//     were refactored to accept a mockable player interface — that is a
//     production-code change, not a test-file one, and hasn't been done.
//
// IMPORT-PATH CAVEAT: coaching_decision.dart's import path was ambiguous
// across the production files reviewed while writing this —
// action_plan.dart / reference_comparison_engine.dart import it as
// '.../voice_director/models/coaching_decision.dart' (no "domain/"),
// root_cause_engine.dart imports it as '.../voice_director/domain/models/
// coaching_decision.dart' (with "domain/"). This file follows the two-file
// majority below. If it fails to resolve, flip this one import line.

import 'package:camera/camera.dart' show CameraDescription, CameraLensDirection;
import 'package:cuemera/core/services/expression_classifier.dart';
import 'package:cuemera/core/services/ml_kit_service.dart';
import 'package:cuemera/core/services/tracking_engine.dart';
import 'package:cuemera/features/album/domain/models/shot.dart';
import 'package:cuemera/features/capture/domain/shot_builder.dart';
import 'package:cuemera/features/capture/services/auto_capture_service.dart';
import 'package:cuemera/features/editorial_score/domain/score_calculator.dart';
import 'package:cuemera/features/reference_photo/domain/comparison_math.dart';
import 'package:cuemera/features/reference_photo/domain/models/detection_thresholds.dart';
import 'package:cuemera/features/reference_photo/domain/models/reference_profile.dart';
import 'package:cuemera/features/reference_photo/domain/models/tolerance_settings.dart';
import 'package:cuemera/features/scene_analysis/domain/models/scene_profile.dart';
import 'package:cuemera/features/scene_analysis/domain/models/subject_profile.dart';
import 'package:cuemera/features/voice_director/domain/action_plan.dart';
import 'package:cuemera/features/voice_director/domain/adaptive_correction_model.dart';
import 'package:cuemera/features/voice_director/domain/coaching_eligibility.dart';
import 'package:cuemera/features/voice_director/domain/coaching_state_machine.dart';
import 'package:cuemera/features/voice_director/domain/correction_feedback.dart';
// pose_and_face_evaluators.dart / attribute_evaluation.dart: see the
// "Arm-pose coaching" group below for an important caveat — as of this
// writing these files are not confirmed wired into the live app (not
// referenced anywhere in FILE_REFERENCE.md/README.md). Their real
// package path is also a guess: neither file has the header-path
// comment every other file in this project has, so "evaluators/" below
// is inferred from their relative-import depth (3-4 levels up to reach
// core//features siblings, one more than domain/-level files use), not
// confirmed. If this doesn't resolve, that's the first thing to fix.
import 'package:cuemera/features/voice_director/domain/reference_comparison/pose_and_face_evaluators.dart';
import 'package:cuemera/features/voice_director/domain/reference_comparison_engine.dart';
// See the IMPORT-PATH CAVEAT note above.
import 'package:cuemera/features/voice_director/models/coaching_decision.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const tolerance = ToleranceSettings.defaultBalanced;

SubjectProfile subjectFixture({
  double? bodyRatio,
  double? faceAngleDegrees,
  double? faceAngleXDegrees,
  double? faceAngleZDegrees,
  double? mouthOpenRatio,
  double? eyeOpenRatio,
  double? shoulderAngleDegrees,
  double? shoulderBalanceRatio,
  double? shoulderSpanRatio,
  double? bodyYawEstimate,
  double? leftArmRaiseDegrees,
  double? rightArmRaiseDegrees,
  double? leftElbowAngleDegrees,
  double? rightElbowAngleDegrees,
  String? leftArmPoseCategory,
  String? rightArmPoseCategory,
  String? expression,
  Map<String, double>? metricConfidence,
  DateTime? timestamp,
}) {
  return SubjectProfile(
    bodyRatio: bodyRatio,
    faceAngleDegrees: faceAngleDegrees,
    faceAngleXDegrees: faceAngleXDegrees,
    faceAngleZDegrees: faceAngleZDegrees,
    mouthOpenRatio: mouthOpenRatio,
    eyeOpenRatio: eyeOpenRatio,
    shoulderAngleDegrees: shoulderAngleDegrees,
    shoulderBalanceRatio: shoulderBalanceRatio,
    shoulderSpanRatio: shoulderSpanRatio,
    bodyYawEstimate: bodyYawEstimate,
    leftArmRaiseDegrees: leftArmRaiseDegrees,
    rightArmRaiseDegrees: rightArmRaiseDegrees,
    leftElbowAngleDegrees: leftElbowAngleDegrees,
    rightElbowAngleDegrees: rightElbowAngleDegrees,
    leftArmPoseCategory: leftArmPoseCategory,
    rightArmPoseCategory: rightArmPoseCategory,
    expression: expression,
    metricConfidence: metricConfidence,
    timestamp: timestamp ?? DateTime(2026, 1, 1),
  );
}

ReferenceProfile referenceFixture({
  double? bodyRatio,
  double? faceAngleDegrees,
  double? faceAngleXDegrees,
  double? faceAngleZDegrees,
  double? shoulderAngleDegrees,
  double? shoulderBalanceRatio,
  double? shoulderSpanRatio,
  double? bodyYawEstimate,
  double? mouthOpenRatio,
  double? eyeOpenRatio,
  double? leftArmRaiseDegrees,
  double? rightArmRaiseDegrees,
  double? leftElbowAngleDegrees,
  double? rightElbowAngleDegrees,
  String? leftArmPoseCategory,
  String? rightArmPoseCategory,
  String? expression,
  double? negativeSpaceScore,
  double? symmetryScore,
  int? backgroundClutterCount,
  double? overallBrightness,
  double? warmthScore,
  double? dominantHue,
  Map<String, double>? metricConfidence,
}) {
  return ReferenceProfile(
    imagePath: 'reference.jpg',
    bodyRatio: bodyRatio,
    faceAngleDegrees: faceAngleDegrees,
    faceAngleXDegrees: faceAngleXDegrees,
    faceAngleZDegrees: faceAngleZDegrees,
    shoulderAngleDegrees: shoulderAngleDegrees,
    shoulderBalanceRatio: shoulderBalanceRatio,
    shoulderSpanRatio: shoulderSpanRatio,
    bodyYawEstimate: bodyYawEstimate,
    mouthOpenRatio: mouthOpenRatio,
    eyeOpenRatio: eyeOpenRatio,
    leftArmRaiseDegrees: leftArmRaiseDegrees,
    rightArmRaiseDegrees: rightArmRaiseDegrees,
    leftElbowAngleDegrees: leftElbowAngleDegrees,
    rightElbowAngleDegrees: rightElbowAngleDegrees,
    leftArmPoseCategory: leftArmPoseCategory,
    rightArmPoseCategory: rightArmPoseCategory,
    expression: expression,
    negativeSpaceScore: negativeSpaceScore,
    symmetryScore: symmetryScore,
    backgroundClutterCount: backgroundClutterCount,
    overallBrightness: overallBrightness,
    warmthScore: warmthScore,
    dominantHue: dominantHue,
    metricConfidence: metricConfidence,
  );
}

SceneProfile sceneFixture({
  double brightness = 0.5,
  double negativeSpaceScore = 0.5,
  double symmetryScore = 0.5,
  int backgroundClutterCount = 0,
  double? depthEstimate,
  double? liveWarmthScore,
  double? liveDominantHue,
}) {
  return SceneProfile(
    brightness: brightness,
    negativeSpaceScore: negativeSpaceScore,
    symmetryScore: symmetryScore,
    backgroundClutterCount: backgroundClutterCount,
    depthEstimate: depthEstimate,
    liveWarmthScore: liveWarmthScore,
    liveDominantHue: liveDominantHue,
  );
}

void main() {
  // -------------------------------------------------------------------------
  group('MlKitService.rotationFor — front vs back camera', () {
    // Platform.isIOS is false on any host `flutter test` actually runs on
    // (it only reports true inside a compiled iOS app process), so every
    // case below exercises the non-iOS branch — which is also the only
    // branch that treats front/back differently, so that is not a gap for
    // what we're testing here.
    final service = MlKitService();

    const back = CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    );
    const front = CameraDescription(
      name: 'front',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 270,
    );

    test(
      'back camera, portraitUp -> sensorOrientation - deviceRotation(0)',
      () {
        final result = service.rotationFor(back, DeviceOrientation.portraitUp);
        expect(
          result,
          InputImageRotation.rotation90deg,
        ); // (90 - 0 + 360) % 360
      },
    );

    test(
      'back camera, landscapeLeft -> sensorOrientation - deviceRotation(90)',
      () {
        final result = service.rotationFor(
          back,
          DeviceOrientation.landscapeLeft,
        );
        expect(result, InputImageRotation.rotation0deg); // (90-90+360)%360
      },
    );

    test(
      'front camera, portraitUp -> sensorOrientation + deviceRotation(0)',
      () {
        final result = service.rotationFor(front, DeviceOrientation.portraitUp);
        expect(result, InputImageRotation.rotation270deg); // (270+0)%360
      },
    );

    test(
      'front camera, landscapeLeft -> sensorOrientation + deviceRotation(90) wraps',
      () {
        final result = service.rotationFor(
          front,
          DeviceOrientation.landscapeLeft,
        );
        expect(result, InputImageRotation.rotation0deg); // (270+90)%360==0
      },
    );

    test('same sensorOrientation + same device rotation still diverge between '
        'lenses — this asymmetry is exactly the sixth-session mirroring bug '
        'rotationFor() exists to fix', () {
      const sameSensor = 90;
      final backResult = service.rotationFor(
        const CameraDescription(
          name: 'back-shared',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: sameSensor,
        ),
        DeviceOrientation.landscapeLeft,
      );
      final frontResult = service.rotationFor(
        const CameraDescription(
          name: 'front-shared',
          lensDirection: CameraLensDirection.front,
          sensorOrientation: sameSensor,
        ),
        DeviceOrientation.landscapeLeft,
      );
      expect(backResult, InputImageRotation.rotation0deg); // (90-90+360)%360
      expect(frontResult, InputImageRotation.rotation180deg); // (90+90)%360
      expect(backResult, isNot(equals(frontResult)));
    });
  });

  // -------------------------------------------------------------------------
  group('classifyExpression', () {
    test('returns null with no smiling signal at all', () {
      final result = classifyExpression(
        smilingProbability: null,
        leftEyeOpenProbability: 0.9,
        rightEyeOpenProbability: 0.9,
      );
      expect(result, isNull);
    });

    test('one eye clearly open, one clearly closed -> wink', () {
      final result = classifyExpression(
        smilingProbability: 0.5,
        leftEyeOpenProbability: 0.9,
        rightEyeOpenProbability: 0.1,
      );
      expect(result, 'wink');
    });

    test('both eyes closed + smiling -> laughing_eyes_closed', () {
      final result = classifyExpression(
        smilingProbability: 0.9,
        leftEyeOpenProbability: 0.1,
        rightEyeOpenProbability: 0.1,
      );
      expect(result, 'laughing_eyes_closed');
    });

    test('both eyes closed + not smiling -> eyes_closed', () {
      final result = classifyExpression(
        smilingProbability: 0.3,
        leftEyeOpenProbability: 0.1,
        rightEyeOpenProbability: 0.1,
      );
      expect(result, 'eyes_closed');
    });

    test('smiling-probability tiers, eyes not part of the signal', () {
      final cases = <double, String>{
        0.9: 'big_smile',
        0.7: 'smiling',
        0.4: 'slight_smile',
        0.2: 'neutral',
        0.05: 'serious',
      };
      cases.forEach((probability, expected) {
        final result = classifyExpression(
          smilingProbability: probability,
          leftEyeOpenProbability: null,
          rightEyeOpenProbability: null,
        );
        expect(result, expected, reason: 'smilingProbability=$probability');
      });
    });
  });

  // -------------------------------------------------------------------------
  group('ComparisonMath — the shared primitive every evaluator is built on', () {
    test('circularDeviation handles the ±180° wrap correctly', () {
      // current=-178, reference=170 -> true angular gap is 12°, not ~348°.
      final deviation = ComparisonMath.circularDeviation(-178, 170, 360.0);
      expect(deviation, closeTo(12.0, 0.0001));
    });

    test('signedCircularDiff keeps the sign correct across the wrap', () {
      // -178 sits at +182° the short way around from 170°, i.e. *ahead* of
      // it by 12° -> signedDiff should be +12, not -12 and not ~-348.
      final diff = ComparisonMath.signedCircularDiff(-178, 170, 360.0);
      expect(diff, closeTo(12.0, 0.0001));
    });

    test(
      'relativeDeviation returns null against a zero reference instead of dividing by zero',
      () {
        expect(ComparisonMath.relativeDeviation(0.5, 0.0), isNull);
      },
    );

    test(
      'similarity is 1.0 within threshold and decays linearly beyond it',
      () {
        expect(ComparisonMath.similarity(5.0, 10.0, 90.0), 1.0);
        final decayed = ComparisonMath.similarity(50.0, 10.0, 90.0);
        expect(decayed, closeTo(0.5, 0.0001)); // 1 - (50-10)/(90-10)
      },
    );
  });

  // -------------------------------------------------------------------------
  group('ReferenceComparisonEngine', () {
    test('shoulderBalance direction is IDENTICAL between front and back '
        'camera for the same numeric mismatch (regression test — this '
        'used to assert the opposite, see below)', () {
      // HISTORY: this test originally asserted that front and back camera
      // produced OPPOSITE directions here (front=right, back=left) for
      // the exact same subject/reference values — i.e. it treated the
      // isFrontCamera mirror-flip in _evaluateShoulderBalance as correct
      // behavior. That flip was found to be an unverified, unjustified
      // bug during a real-device debugging session: no coordinate-level
      // mirroring exists anywhere upstream (ml_kit_service.dart,
      // pose_analyzer.dart, reference_image_analyzer.dart all derive
      // shoulderBalanceRatio identically regardless of lens), and a real
      // front-camera device log showed the app repeatedly saying "lift
      // your left shoulder" while shoulderBalanceRatio drifted FURTHER
      // from target, then trended the correct direction once the flip
      // was removed (crossing target from -0.31 to +0.25 in one
      // continuous, correct-direction correction). The fix: front camera
      // now uses the identical formula as back camera for this attribute.
      final engine = ReferenceComparisonEngine();
      final subject = subjectFixture(shoulderBalanceRatio: 0.7);
      final reference = referenceFixture(shoulderBalanceRatio: 0.3);
      final scene = sceneFixture();

      final backTiers = engine.evaluateTiers(
        subject: subject,
        scene: scene,
        reference: reference,
        tolerance: tolerance,
        isFrontCamera: false,
      );
      final frontTiers = engine.evaluateTiers(
        subject: subject,
        scene: scene,
        reference: reference,
        tolerance: tolerance,
        isFrontCamera: true,
      );

      expect(backTiers.poseAndFace, hasLength(1));
      expect(frontTiers.poseAndFace, hasLength(1));
      final backDirection = backTiers.poseAndFace.single.decision.direction;
      final frontDirection = frontTiers.poseAndFace.single.decision.direction;
      // subjectValue (0.7) > referenceValue (0.3) -> the subject's left
      // shoulder really is lower than the reference wants, on both
      // lenses now -> both should say "lift the left shoulder".
      expect(backDirection, CoachingDirection.left);
      expect(
        frontDirection,
        CoachingDirection.left,
        reason:
            'front camera must match back camera here — no verified '
            'mirroring exists for this attribute',
      );
      expect(
        frontDirection,
        backDirection,
        reason: 'the core assertion of this regression test',
      );
    });

    test("faceRoll's confidence now reflects face_analyzer.dart's live-side "
        'metricConfidence instead of the old hardcoded 1.0 (regression test '
        'for the seventeenth-session fix)', () {
      final engine = ReferenceComparisonEngine();
      final subject = subjectFixture(
        faceAngleZDegrees: 40,
        metricConfidence: {'faceAngleZDegrees': 0.3},
      );
      // No metricConfidence on the reference side -> confidenceFor()
      // falls back to its 1.0 default, per reference_profile.dart.
      final reference = referenceFixture(faceAngleZDegrees: 0);
      final scene = sceneFixture();

      final tiers = engine.evaluateTiers(
        subject: subject,
        scene: scene,
        reference: reference,
        tolerance: tolerance,
        isFrontCamera: false,
      );

      expect(tiers.poseAndFace, hasLength(1));
      final decision = tiers.poseAndFace.single.decision;
      expect(decision.attribute, CoachingAttribute.faceRoll);
      expect(decision.confidence, closeTo(0.3, 0.0001)); // min(0.3, 1.0)
    });

    test(
      'bodyYaw/shoulderAngle/shoulderBalance/shoulderSpan collapse into one '
      'representative correction when all four exceed threshold together',
      () {
        final engine = ReferenceComparisonEngine();
        final subject = subjectFixture(
          bodyYawEstimate: 40,
          shoulderAngleDegrees: 40,
          shoulderBalanceRatio: 0.7,
          shoulderSpanRatio: 1.6,
        );
        final reference = referenceFixture(
          bodyYawEstimate: 0,
          shoulderAngleDegrees: 0,
          shoulderBalanceRatio: 0.3,
          shoulderSpanRatio: 1.0,
        );
        final scene = sceneFixture();

        final tiers = engine.evaluateTiers(
          subject: subject,
          scene: scene,
          reference: reference,
          tolerance: tolerance,
          isFrontCamera: false,
        );

        expect(tiers.poseAndFace, hasLength(1)); // 4 raw hits -> 1 collapsed
        expect(
          tiers.poseAndFace.single.decision.attribute,
          CoachingAttribute.bodyYaw, // fixed cluster representative
        );
      },
    );

    test('evaluate() only advances the tier-rotation counter when a candidate '
        'is actually chosen (regression for the sixteenth-session '
        'tier-rotation bug)', () {
      final engine = ReferenceComparisonEngine();
      const looseTolerance = ToleranceSettings(
        poseTolerance: 0.5,
        compositionTolerance: 0.2,
        expressionTolerance: 0.5,
        colorTolerance: 0.2,
        // Added this session alongside bodyYawTolerance's introduction —
        // ToleranceSettings' constructor now requires this field. Set
        // equal to poseTolerance here since this test isn't exercising
        // bodyYaw at all; see the dedicated bodyYawTolerance group below
        // for tests that actually vary it independently.
        bodyYawTolerance: 0.5,
      );

      final mismatchReference = referenceFixture(
        negativeSpaceScore: 0.5,
        overallBrightness: 0.5,
      );
      final mismatchScene = sceneFixture(
        brightness: 0.8,
        negativeSpaceScore: 0.8,
      );
      // All pose fields null on both sides -> poseAndFace tier is always
      // empty here, isolating the composition/lighting rotation.
      final noSignalSubject = subjectFixture();

      // negativeSpaceScore/overallBrightness both null -> those two
      // evaluators return null outright, so this call produces zero
      // candidates in any tier.
      final matchReference = referenceFixture();
      final matchScene = sceneFixture();

      ActionPlan? call(SceneProfile scene, ReferenceProfile reference) {
        return engine.evaluate(
          subject: noSignalSubject,
          scene: scene,
          reference: reference,
          tolerance: looseTolerance,
          isFrontCamera: false,
        );
      }

      final first = call(mismatchScene, mismatchReference);
      final second = call(mismatchScene, mismatchReference);
      final duringMiss = call(matchScene, matchReference);
      final third = call(mismatchScene, mismatchReference);

      expect(first?.decision.attribute, CoachingAttribute.negativeSpace);
      expect(second?.decision.attribute, CoachingAttribute.brightness);
      expect(duringMiss, isNull);
      // If the old bug were present, `duringMiss` would have advanced the
      // rotation counter too, and `third` would wrongly repeat
      // `brightness` instead of correctly rotating back to
      // `negativeSpace`.
      expect(third?.decision.attribute, CoachingAttribute.negativeSpace);
    });

    test('faceRoll direction flips between front and back camera — '
        'CURRENT BEHAVIOR ONLY, NOT CONFIRMED CORRECT. This is the exact '
        'same isFrontCamera-flip pattern shoulderBalance had before it was '
        'found (via a real device log) to be an unverified, unjustified '
        'bug and removed. faceRoll reads a different signal source (ML '
        "Kit's own headEulerAngleZ, not the custom shoulder-landmark atan2 "
        "math shoulderBalance used), so there is no independent way yet to "
        'confirm or deny this flip the way shoulderBalance was confirmed. '
        'If this test starts failing after a real front-camera device '
        'test, that is expected progress, not a regression — update the '
        'expected direction below to match reality and remove this note.', () {
      final engine = ReferenceComparisonEngine();
      final subject = subjectFixture(faceAngleZDegrees: 30);
      final reference = referenceFixture(faceAngleZDegrees: 0);
      final scene = sceneFixture();

      final back = engine.evaluateTiers(
        subject: subject,
        scene: scene,
        reference: reference,
        tolerance: tolerance,
        isFrontCamera: false,
      );
      final front = engine.evaluateTiers(
        subject: subject,
        scene: scene,
        reference: reference,
        tolerance: tolerance,
        isFrontCamera: true,
      );

      expect(
        back.poseAndFace.single.decision.direction,
        CoachingDirection.right,
      );
      expect(
        front.poseAndFace.single.decision.direction,
        CoachingDirection.left,
      );
    });

    test('faceYaw direction flips between front and back camera — CURRENT '
        'BEHAVIOR ONLY, NOT CONFIRMED CORRECT (see the faceRoll test '
        'immediately above for the full explanation — same pattern, same '
        'caveat, same signal-source difference from the confirmed '
        'shoulderBalance fix)', () {
      final engine = ReferenceComparisonEngine();
      final subject = subjectFixture(faceAngleDegrees: 30);
      final reference = referenceFixture(faceAngleDegrees: 0);
      final scene = sceneFixture();

      final back = engine.evaluateTiers(
        subject: subject,
        scene: scene,
        reference: reference,
        tolerance: tolerance,
        isFrontCamera: false,
      );
      final front = engine.evaluateTiers(
        subject: subject,
        scene: scene,
        reference: reference,
        tolerance: tolerance,
        isFrontCamera: true,
      );

      expect(
        back.poseAndFace.single.decision.direction,
        CoachingDirection.left,
      );
      expect(
        front.poseAndFace.single.decision.direction,
        CoachingDirection.right,
      );
    });

    test('bodyYaw direction flips between front and back camera — CURRENT '
        'BEHAVIOR ONLY, NOT CONFIRMED CORRECT. Same unverified pattern as '
        'faceRoll/faceYaw above, and for a related but distinct reason: '
        'this reads leftShoulder/rightShoulder .z (ML Kit landmark depth) '
        'rather than a face-detector angle, and z-depth is independently '
        'known to be this project\'s noisiest signal (see bodyYawTolerance '
        'above, added specifically because this axis needed a much looser '
        'threshold than the rest of pose in real device logs) — a further '
        'reason not to trust this flip\'s correctness without a dedicated '
        'device test.', () {
      final engine = ReferenceComparisonEngine();
      final subject = subjectFixture(bodyYawEstimate: 30);
      final reference = referenceFixture(bodyYawEstimate: 0);
      final scene = sceneFixture();

      final back = engine.evaluateTiers(
        subject: subject,
        scene: scene,
        reference: reference,
        tolerance: tolerance,
        isFrontCamera: false,
      );
      final front = engine.evaluateTiers(
        subject: subject,
        scene: scene,
        reference: reference,
        tolerance: tolerance,
        isFrontCamera: true,
      );

      expect(
        back.poseAndFace.single.decision.direction,
        CoachingDirection.left,
      );
      expect(
        front.poseAndFace.single.decision.direction,
        CoachingDirection.right,
      );
    });

    test('headOrientation cluster (facePitch/faceRoll/faceYaw) collapses to '
        'whichever member has the highest severity, since this cluster has '
        'no fixed representative (unlike torsoRotationOrLean\'s bodyYaw)', () {
      final engine = ReferenceComparisonEngine();
      final subject = subjectFixture(
        faceAngleXDegrees: 27, // facePitch, severity 0.3
        faceAngleZDegrees: 45, // faceRoll, severity 0.5
        faceAngleDegrees: 63, // faceYaw, severity 0.7 -- highest
      );
      final reference = referenceFixture(
        faceAngleXDegrees: 0,
        faceAngleZDegrees: 0,
        faceAngleDegrees: 0,
      );
      final scene = sceneFixture();

      final tiers = engine.evaluateTiers(
        subject: subject,
        scene: scene,
        reference: reference,
        tolerance: tolerance,
        isFrontCamera: false,
      );

      expect(tiers.poseAndFace, hasLength(1)); // 3 raw hits -> 1 collapsed
      final decision = tiers.poseAndFace.single.decision;
      expect(decision.attribute, CoachingAttribute.faceYaw);
      expect(decision.normalizedSeverity, closeTo(0.7, 0.001));
    });

    test('facialExpression cluster (mouthOpen/eyeOpen/expression) always '
        'reports as expression, its fixed representative — even though '
        'mouthOpen/eyeOpen also exceed threshold here', () {
      final engine = ReferenceComparisonEngine();
      final subject = subjectFixture(
        mouthOpenRatio: 0.8,
        eyeOpenRatio: 0.7,
        expression: 'serious',
      );
      final reference = referenceFixture(
        mouthOpenRatio: 0.5,
        eyeOpenRatio: 0.5,
        expression: 'smiling',
      );
      final scene = sceneFixture();

      final tiers = engine.evaluateTiers(
        subject: subject,
        scene: scene,
        reference: reference,
        tolerance: tolerance,
        isFrontCamera: false,
      );

      expect(tiers.poseAndFace, hasLength(1));
      final decision = tiers.poseAndFace.single.decision;
      expect(decision.attribute, CoachingAttribute.expression);
      expect(decision.targetExpression, 'smiling');
    });
  });

  // -------------------------------------------------------------------------
  group('bodyYawTolerance — decoupled from poseTolerance (added this '
      'session, in reference_comparison_engine.dart and '
      'pose_and_face_evaluators.dart)', () {
    // bodyYaw is derived from ML Kit's per-landmark z (depth) estimate, a
    // single-camera guess noticeably noisier than the x/y-based pose
    // attributes that share poseTolerance — real device logs showed
    // bodyYaw deviations of 40-65° even with an otherwise near-perfect
    // pose. ToleranceSettings gained a separate bodyYawTolerance field so
    // this can be loosened without also loosening
    // shoulderAngle/shoulderBalance/etc.
    test('at the shared default (bodyYawTolerance == poseTolerance == 0.5), '
        'behavior is unchanged from before this field existed: a 40° '
        'bodyYaw deviation still exceeds the (22.5°) threshold', () {
      final engine = ReferenceComparisonEngine();
      final subject = subjectFixture(bodyYawEstimate: 40);
      final reference = referenceFixture(bodyYawEstimate: 0);
      final scene = sceneFixture();

      final tiers = engine.evaluateTiers(
        subject: subject,
        scene: scene,
        reference: reference,
        tolerance: tolerance, // defaultBalanced: both tolerances at 0.5
        isFrontCamera: false,
      );

      expect(tiers.poseAndFace, hasLength(1));
      expect(
        tiers.poseAndFace.single.decision.attribute,
        CoachingAttribute.bodyYaw,
      );
    });

    test('loosening ONLY bodyYawTolerance clears a 40° bodyYaw deviation '
        'while poseTolerance-sharing attributes are untouched — the core '
        'point of splitting this out', () {
      final engine = ReferenceComparisonEngine();
      const looseBodyYawOnly = ToleranceSettings(
        poseTolerance: 0.5, // unchanged — thresholdForPose stays 22.5°
        compositionTolerance: 0.5,
        expressionTolerance: 0.5,
        colorTolerance: 0.5,
        bodyYawTolerance: 1.0, // loosened — thresholdForBodyYaw becomes 45°
      );
      final subject = subjectFixture(
        bodyYawEstimate: 40, // would exceed 22.5° but not 45°
        shoulderAngleDegrees: 40, // still exceeds the untouched 22.5°
      );
      final reference = referenceFixture(
        bodyYawEstimate: 0,
        shoulderAngleDegrees: 0,
      );
      final scene = sceneFixture();

      final tiers = engine.evaluateTiers(
        subject: subject,
        scene: scene,
        reference: reference,
        tolerance: looseBodyYawOnly,
        isFrontCamera: false,
      );

      // bodyYaw should have dropped out (cleared by the loosened
      // threshold); shoulderAngle should be the sole remaining candidate,
      // proving poseTolerance-driven attributes were not affected.
      expect(tiers.poseAndFace, hasLength(1));
      expect(
        tiers.poseAndFace.single.decision.attribute,
        CoachingAttribute.shoulderAngle,
      );
    });

    test('AutoCaptureService._bodyYawOk / debugConditionBreakdown: same '
        'independence at the capture-gate level, matching a real device '
        'log where a capture succeeded with a live ~45° bodyYaw deviation '
        'while shoulderAngle/shoulderBalance stayed tightly gated', () {
      final service = AutoCaptureService();
      const looseBodyYawOnly = ToleranceSettings(
        poseTolerance: 0.5,
        compositionTolerance: 0.5,
        expressionTolerance: 0.5,
        colorTolerance: 0.5,
        bodyYawTolerance: 1.0, // 45° threshold
      );
      final subject = subjectFixture(
        bodyYawEstimate: 40,
        shoulderAngleDegrees: 40,
        faceAngleDegrees: 0,
        faceAngleXDegrees: 0,
        faceAngleZDegrees: 0,
      );
      final reference = referenceFixture(
        bodyYawEstimate: 0,
        shoulderAngleDegrees: 0,
      );
      final scene = sceneFixture(brightness: 0.8);

      final breakdown = service.debugConditionBreakdown(
        subject,
        scene,
        reference,
        looseBodyYawOnly,
        0.95,
        DetectionThresholds.defaultValues,
      );

      expect(
        breakdown['bodyYaw'],
        isTrue,
        reason: '40° is within the loosened 45° bodyYaw threshold',
      );
      expect(
        breakdown['shoulderAngle'],
        isFalse,
        reason:
            'shoulderAngle still uses the untouched 22.5° poseTolerance '
            'threshold and 40° exceeds it',
      );

      final overall = service.shouldCapture(
        subject,
        scene,
        reference,
        looseBodyYawOnly,
        0.95,
        DetectionThresholds.defaultValues,
      );
      expect(
        overall,
        isFalse,
        reason:
            'still blocked overall, just for a different reason than '
            'bodyYaw now — confirms the two thresholds are independent, '
            'not that loosening one loosens the whole gate',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('score_calculator.calculateReferenceScore', () {
    test('all five categories present and perfectly matching -> overall 100, '
        'no missing keys', () {
      final subject = subjectFixture(expression: 'smiling');
      final reference = referenceFixture(
        negativeSpaceScore: 0.5,
        symmetryScore: 0.5,
        overallBrightness: 0.5,
        expression: 'smiling',
        backgroundClutterCount: 2,
      );
      final scene = sceneFixture(
        negativeSpaceScore: 0.5,
        symmetryScore: 0.5,
        brightness: 0.5,
        backgroundClutterCount: 2,
        depthEstimate: 1.0,
      );

      final score = calculateReferenceScore(
        subject,
        scene,
        reference,
        tolerance,
      );

      expect(score.breakdown, {
        'composition': 100,
        'lighting': 100,
        'expression': 100,
        'background': 100,
        'story': 100,
      });
      expect(score.overall, 100);
      expect(score.nextSuggestion, isNull);
    });

    test('missing expression/story signal omits those keys instead of diluting '
        'the average with a placeholder (regression for the sixteenth-session '
        'fix)', () {
      final subject = subjectFixture(); // expression always null live
      final reference = referenceFixture(
        negativeSpaceScore: 0.5,
        symmetryScore: 0.5,
        overallBrightness: 0.5,
        expression: 'smiling', // present on reference, nothing to compare
        backgroundClutterCount: 2,
      );
      final scene = sceneFixture(
        negativeSpaceScore: 0.5,
        symmetryScore: 0.5,
        brightness: 0.5,
        backgroundClutterCount: 2,
        // depthEstimate left null -> no story signal
      );

      final score = calculateReferenceScore(
        subject,
        scene,
        reference,
        tolerance,
      );

      expect(score.breakdown.containsKey('expression'), isFalse);
      expect(score.breakdown.containsKey('story'), isFalse);
      expect(score.breakdown.keys.toSet(), {
        'composition',
        'lighting',
        'background',
      });
      expect(score.overall, 100); // not diluted toward 50/60
    });

    test('nextSuggestion names the lowest-scoring present category when it is '
        'below 60 (FIX: also accounts for background\'s always-on fallback '
        'score, missed in an earlier version of this test)', () {
      final subject = subjectFixture();
      final reference = referenceFixture(overallBrightness: 0.9);
      final scene = sceneFixture(brightness: 0.1); // big mismatch

      final score = calculateReferenceScore(
        subject,
        scene,
        reference,
        tolerance,
      );

      expect(score.breakdown, {'lighting': 40, 'background': 100});
      expect(score.nextSuggestion, 'Improve lighting');
    });

    test("FIX to a wrong test found this session: 'no signal anywhere' isn't "
        'actually empty. _backgroundScore has no null-returning path at all '
        "— when the reference has no clutter data it falls back to scoring "
        "the scene's own absolute cleanliness, so it always contributes "
        'something. That makes calculateReferenceScore()\'s '
        "`breakdown.isEmpty` early-return dead code in practice — worth "
        'knowing, not a bug to fix.', () {
      final subject = subjectFixture();
      final reference = referenceFixture();
      final scene = sceneFixture(); // backgroundClutterCount defaults to 0

      final score = calculateReferenceScore(
        subject,
        scene,
        reference,
        tolerance,
      );

      // Every OTHER category correctly returns null with nothing to
      // compare against; background is the sole exception.
      expect(score.breakdown, {'background': 100});
      expect(score.overall, 100);
      expect(score.nextSuggestion, isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('TrackingEngine', () {
    test(
      'smoothSubject: circular EMA takes the short path across the ±180° wrap',
      () {
        final engine = TrackingEngine();
        final previous = subjectFixture(shoulderAngleDegrees: 170);
        final raw = subjectFixture(shoulderAngleDegrees: -170);

        final smoothed = engine.smoothSubject(raw, previous);

        expect(smoothed.shoulderAngleDegrees, isNotNull);
        // A linear EMA between 170 and -170 would collapse toward 0; the
        // circular EMA should stay near ±180 instead.
        expect(smoothed.shoulderAngleDegrees!.abs(), greaterThan(150));
      },
    );

    test('smoothSubject: a value nulls out only after missing for '
        'debounceFrames consecutive frames', () {
      final engine = TrackingEngine(); // debounceFrames = 2 by default
      final previous = subjectFixture(bodyRatio: 1.5);
      final rawMissing = subjectFixture(bodyRatio: null);

      final afterOneMiss = engine.smoothSubject(rawMissing, previous);
      expect(afterOneMiss.bodyRatio, isNotNull); // streak=1, not yet 2

      final afterTwoMisses = engine.smoothSubject(rawMissing, afterOneMiss);
      expect(afterTwoMisses.bodyRatio, isNull); // streak=2 hits the debounce
    });

    test(
      'trackingProgress: a perfect match against every target field scores 1.0',
      () {
        final engine = TrackingEngine();
        final target = subjectFixture(
          shoulderAngleDegrees: 10,
          faceAngleDegrees: 10,
          bodyYawEstimate: 10,
        );
        final current = subjectFixture(
          shoulderAngleDegrees: 10,
          faceAngleDegrees: 10,
          bodyYawEstimate: 10,
        );
        final scene = sceneFixture(brightness: 0.5, backgroundClutterCount: 2);
        final targetScene = sceneFixture(
          brightness: 0.5,
          backgroundClutterCount: 2,
        );

        final progress = engine.trackingProgress(
          current,
          target,
          scene,
          targetScene,
          tolerance,
        );
        expect(progress, closeTo(1.0, 0.0001));
      },
    );

    test('trackingProgress: a missing current value against a present target '
        'contributes 0, it does not just get skipped', () {
      final engine = TrackingEngine();
      final target = subjectFixture(shoulderAngleDegrees: 10);
      final current = subjectFixture(shoulderAngleDegrees: null);
      final scene = sceneFixture();
      final targetScene = sceneFixture();

      final progress = engine.trackingProgress(
        current,
        target,
        scene,
        targetScene,
        tolerance,
      );
      // shoulderAngle contributes 0.0; brightness+clutter (always scored,
      // and identical here) each contribute 1.0 -> average of 3 = 2/3.
      expect(progress, closeTo(2 / 3, 0.01));
    });
  });

  // -------------------------------------------------------------------------
  group('AutoCaptureService', () {
    test(
      'rejects capture when brightness is below the threshold, regardless of pose match',
      () {
        final service = AutoCaptureService();
        final subject = subjectFixture();
        final reference = referenceFixture();
        final scene = sceneFixture(brightness: 0.05); // below 0.2 default

        final result = service.shouldCapture(
          subject,
          scene,
          reference,
          tolerance,
          1.0,
          DetectionThresholds.defaultValues,
        );
        expect(result, isFalse);
      },
    );

    test(
      'rejects capture when trackingProgress is below minTrackingProgressForCapture '
      'even if every pose gate passes',
      () {
        final service = AutoCaptureService();
        final subject = subjectFixture(
          faceAngleDegrees: 0,
          faceAngleXDegrees: 0,
          faceAngleZDegrees: 0,
        );
        final reference = referenceFixture(); // every gate vacuously true
        final scene = sceneFixture(brightness: 0.8);

        final result = service.shouldCapture(
          subject,
          scene,
          reference,
          tolerance,
          0.5, // < defaultValues.minTrackingProgressForCapture (0.9)
          DetectionThresholds.defaultValues,
        );
        expect(result, isFalse);
      },
    );

    test('accepts capture when every gate passes, brightness is fine, and '
        'tracking progress clears the bar', () {
      final service = AutoCaptureService();
      final subject = subjectFixture(
        faceAngleDegrees: 0,
        faceAngleXDegrees: 0,
        faceAngleZDegrees: 0,
      );
      final reference = referenceFixture();
      final scene = sceneFixture(brightness: 0.8);

      final result = service.shouldCapture(
        subject,
        scene,
        reference,
        tolerance,
        0.95,
        DetectionThresholds.defaultValues,
      );
      expect(result, isTrue);
    });

    test(
      'enforces the cooldown immediately after a triggered capture',
      () async {
        final service = AutoCaptureService();
        final subject = subjectFixture(
          faceAngleDegrees: 0,
          faceAngleXDegrees: 0,
          faceAngleZDegrees: 0,
        );
        final reference = referenceFixture();
        final scene = sceneFixture(brightness: 0.8);

        await service.triggerCapture();
        final immediatelyAfter = service.shouldCapture(
          subject,
          scene,
          reference,
          tolerance,
          0.95,
          DetectionThresholds.defaultValues,
        );
        // captureCooldownMs defaults to 1500ms; essentially no time has
        // elapsed between triggerCapture() and this call.
        expect(immediatelyAfter, isFalse);
      },
    );

    test("debugConditionBreakdown reports each gate individually, matching "
        "shouldCapture's combined result", () {
      final service = AutoCaptureService();
      final subject = subjectFixture(
        shoulderAngleDegrees: 80,
        faceAngleDegrees: 0,
        faceAngleXDegrees: 0,
        faceAngleZDegrees: 0,
      );
      final reference = referenceFixture(shoulderAngleDegrees: 0);
      final scene = sceneFixture(brightness: 0.8);

      final breakdown = service.debugConditionBreakdown(
        subject,
        scene,
        reference,
        tolerance,
        0.95,
        DetectionThresholds.defaultValues,
      );
      expect(breakdown['shoulderAngle'], isFalse);
      expect(breakdown['brightness'], isTrue);

      final overall = service.shouldCapture(
        subject,
        scene,
        reference,
        tolerance,
        0.95,
        DetectionThresholds.defaultValues,
      );
      expect(overall, isFalse); // must agree with the failing gate
    });

    test('FINDING, not asserted as a bug: _faceOk/_facePitchOk/_faceRollOk '
        'require the LIVE subject to have a face-angle reading even when the '
        'reference has no opinion on face angle at all — unlike every other '
        'gate (_shoulderOk, _bodyYawOk, _shoulderBalanceOk, etc.), which pass '
        'vacuously when the reference field is null. Whether that is '
        'intentional (always require a visible face to auto-capture) or a '
        'copy-paste asymmetry is a product call — this test just documents '
        'the current behavior so the decision can be made deliberately.', () {
      final service = AutoCaptureService();
      final subjectWithNoFaceReading = subjectFixture();
      final referenceWithNoFaceOpinion = referenceFixture();
      final scene = sceneFixture(brightness: 0.8);

      final breakdown = service.debugConditionBreakdown(
        subjectWithNoFaceReading,
        scene,
        referenceWithNoFaceOpinion,
        tolerance,
        0.95,
        DetectionThresholds.defaultValues,
      );

      // Every other pose gate passes vacuously when the reference has no
      // target for it...
      expect(breakdown['shoulderAngle'], isTrue);
      expect(breakdown['bodyYaw'], isTrue);
      expect(breakdown['shoulderBalance'], isTrue);
      // ...but these three block capture anyway, purely because the
      // subject currently has no reading — regardless of the reference.
      expect(breakdown['faceAngle'], isFalse);
      expect(breakdown['facePitch'], isFalse);
      expect(breakdown['faceRoll'], isFalse);
    });

    test('threshold boundary: a deviation exactly at the threshold passes, one '
        'unit past it fails (exceedsThreshold is a strict >, not >=)', () {
      final service = AutoCaptureService();
      final scene = sceneFixture(brightness: 0.8);
      // thresholdForPose(poseTolerance=0.5) = 22.5
      final atThreshold = service.shouldCapture(
        subjectFixture(
          shoulderAngleDegrees: 22.5,
          faceAngleDegrees: 0,
          faceAngleXDegrees: 0,
          faceAngleZDegrees: 0,
        ),
        scene,
        referenceFixture(shoulderAngleDegrees: 0),
        tolerance,
        0.95,
        DetectionThresholds.defaultValues,
      );
      final pastThreshold = service.shouldCapture(
        subjectFixture(
          shoulderAngleDegrees: 22.6,
          faceAngleDegrees: 0,
          faceAngleXDegrees: 0,
          faceAngleZDegrees: 0,
        ),
        scene,
        referenceFixture(shoulderAngleDegrees: 0),
        tolerance,
        0.95,
        DetectionThresholds.defaultValues,
      );

      expect(atThreshold, isTrue);
      expect(pastThreshold, isFalse);
    });

    test('_shoulderBalanceOk uses ABSOLUTE deviation, matching '
        '_evaluateShoulderBalance\'s coaching formula — regression test for '
        'a real bug found this session: this gate used to call '
        'ComparisonMath.relativeDeviation instead, which — since '
        'shoulderBalanceRatio targets are typically small numbers like '
        '0.18 (a real reference photo\'s measured value) — inflated a '
        'modest absolute gap into a relative one large enough to fail, '
        'silently blocking capture well after coaching had already '
        'stopped complaining about this attribute', () {
      final service = AutoCaptureService();
      final scene = sceneFixture(brightness: 0.8);
      // Real values from a real device log: reference shoulderBalanceRatio
      // measured at 0.18, subject measured at 0.05 at a moment coaching had
      // already gone quiet about the shoulders.
      final subject = subjectFixture(
        shoulderBalanceRatio: 0.05,
        faceAngleDegrees: 0,
        faceAngleXDegrees: 0,
        faceAngleZDegrees: 0,
      );
      final reference = referenceFixture(shoulderBalanceRatio: 0.18);

      final breakdown = service.debugConditionBreakdown(
        subject,
        scene,
        reference,
        tolerance,
        0.95,
        DetectionThresholds.defaultValues,
      );

      // Absolute deviation = |0.05 - 0.18| = 0.13, threshold
      // (thresholdForPoseRatio(0.5) = 0.25) -> 0.13 < 0.25 -> should pass.
      // Under the old relativeDeviation formula this would have computed
      // 0.13 / 0.18 = 0.722, which is > 0.25 and would have wrongly failed.
      expect(
        breakdown['shoulderBalance'],
        isTrue,
        reason:
            'with the fix (absolute deviation), 0.13 is comfortably under '
            'the 0.25 threshold; if this is false, the relativeDeviation '
            'regression has crept back in',
      );
    });

    test('_shoulderSpanOk / _bodyRatioOk / _mouthOpenOk still use RELATIVE '
        'deviation, unlike the now-fixed _shoulderBalanceOk — guard against '
        'someone "fixing" these to match shoulderBalance\'s new absolute '
        'formula by mistake. Their coaching counterparts '
        '(_evaluateShoulderSpan/_evaluateBodyRatio/_evaluateMouthOpen) were '
        'already relative-deviation before this session and were never '
        'part of the bug — shoulderBalance was the one exception.', () {
      final service = AutoCaptureService();
      final scene = sceneFixture(brightness: 0.8);

      // For each of these, a small absolute gap against a small reference
      // value should still FAIL under relativeDeviation, proving the
      // formula is still relative and not accidentally switched to
      // absolute (which would pass here instead).
      final shoulderSpanBreakdown = service.debugConditionBreakdown(
        subjectFixture(
          shoulderSpanRatio: 0.05,
          faceAngleDegrees: 0,
          faceAngleXDegrees: 0,
          faceAngleZDegrees: 0,
        ),
        scene,
        referenceFixture(shoulderSpanRatio: 0.18),
        tolerance,
        0.95,
        DetectionThresholds.defaultValues,
      );
      expect(
        shoulderSpanBreakdown['shoulderSpan'],
        isFalse,
        reason:
            '0.13/0.18=0.722 > 0.25 under relativeDeviation — should still '
            'fail; if true, this gate was wrongly switched to absolute',
      );

      final bodyRatioBreakdown = service.debugConditionBreakdown(
        subjectFixture(
          bodyRatio: 0.05,
          faceAngleDegrees: 0,
          faceAngleXDegrees: 0,
          faceAngleZDegrees: 0,
        ),
        scene,
        referenceFixture(bodyRatio: 0.18),
        tolerance,
        0.95,
        DetectionThresholds.defaultValues,
      );
      expect(bodyRatioBreakdown['bodyRatio'], isFalse);

      final mouthOpenBreakdown = service.debugConditionBreakdown(
        subjectFixture(
          mouthOpenRatio: 0.05,
          faceAngleDegrees: 0,
          faceAngleXDegrees: 0,
          faceAngleZDegrees: 0,
        ),
        scene,
        referenceFixture(mouthOpenRatio: 0.18),
        tolerance,
        0.95,
        DetectionThresholds.defaultValues,
      );
      expect(mouthOpenBreakdown['mouthOpen'], isFalse);
    });

    test('FINDING, NOT CONFIRMED — worth checking once analysis_constants '
        '.dart is available: _backgroundOk normalizes '
        'scene.backgroundClutterCount with an inline "/10", while the '
        'coaching evaluator for the same attribute '
        '(_evaluateBackgroundClutter in composition_evaluators.dart) calls '
        'a shared normalizeClutterCount(...) helper from '
        'core/analysis/analysis_constants.dart — added in a later session '
        'specifically to fix a live-vs-reference sampling-scale mismatch. '
        'If normalizeClutterCount no longer means "divide by 10", this '
        'gate and its coaching counterpart could disagree the same way '
        'shoulderBalance\'s absolute/relative mismatch did. This test only '
        'pins down _backgroundOk\'s CURRENT literal behavior so a future '
        'change to analysis_constants.dart shows up as a diff here, not a '
        'silent divergence.', () {
      final service = AutoCaptureService();
      final scene = sceneFixture(
        brightness: 0.8,
        backgroundClutterCount: 3, // 3/10 = 0.3 under the current formula
      );
      final reference = referenceFixture(
        backgroundClutterCount: 5, // 5/10 = 0.5
      );
      // |0.3 - 0.5| = 0.2, thresholdForComposition(0.5) = 0.5 -> passes.
      final breakdown = service.debugConditionBreakdown(
        subjectFixture(
          faceAngleDegrees: 0,
          faceAngleXDegrees: 0,
          faceAngleZDegrees: 0,
        ),
        scene,
        reference,
        tolerance,
        0.95,
        DetectionThresholds.defaultValues,
      );
      expect(breakdown['backgroundClutter'], isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('buildShotFromCapture — the actual A-to-Z endpoint', () {
    test('produces a Shot whose score matches calling calculateReferenceScore '
        'directly (no duplicated scoring logic)', () {
      final subject = subjectFixture();
      final reference = referenceFixture(overallBrightness: 0.5);
      final scene = sceneFixture(brightness: 0.5);

      final expectedScore = calculateReferenceScore(
        subject,
        scene,
        reference,
        tolerance,
      );
      final shot = buildShotFromCapture(
        imagePath: '/tmp/shot.jpg',
        subject: subject,
        scene: scene,
        reference: reference,
        tolerance: tolerance,
        shotType: 'portrait',
      );

      expect(shot.score.overall, expectedScore.overall);
      expect(shot.score.breakdown, expectedScore.breakdown);
      expect(shot.shotType, 'portrait');
      expect(shot.imagePath, '/tmp/shot.jpg');
      expect(shot.referenceImagePath, reference.imagePath);
      expect(shot.toleranceSettings, tolerance);
    });

    test('Shot round-trips through toMap/fromMap without losing the score or '
        'tolerance settings', () {
      final subject = subjectFixture();
      final reference = referenceFixture(overallBrightness: 0.6);
      final scene = sceneFixture(brightness: 0.6);
      final shot = buildShotFromCapture(
        imagePath: null,
        subject: subject,
        scene: scene,
        reference: reference,
        tolerance: tolerance,
        shotType: 'candid',
      );

      final restored = Shot.fromMap(shot.toMap());

      expect(restored.id, shot.id);
      expect(restored.shotType, shot.shotType);
      expect(restored.score.overall, shot.score.overall);
      expect(restored.score.breakdown, shot.score.breakdown);
      expect(
        restored.toleranceSettings?.poseTolerance,
        tolerance.poseTolerance,
      );
      expect(restored.referenceImagePath, reference.imagePath);
    });
  });

  // -------------------------------------------------------------------------
  group('End-to-end: mismatched pose blocks capture, corrected pose allows it '
      '— run once for back camera and once for front camera', () {
    for (final isFrontCamera in [false, true]) {
      final label = isFrontCamera ? 'front camera' : 'back camera';

      test(
        '$label: full pipeline from mismatch through correction to a captured Shot',
        () async {
          final engine = ReferenceComparisonEngine();
          final trackingEngine = TrackingEngine();
          final autoCapture = AutoCaptureService();

          final reference = referenceFixture(
            shoulderAngleDegrees: 0,
            shoulderBalanceRatio: 0.5,
            bodyYawEstimate: 0,
            overallBrightness: 0.5,
            negativeSpaceScore: 0.5,
            symmetryScore: 0.5,
          );
          // Hand-mirrors what targetSubjectProfileProvider/
          // targetSceneProfileProvider do in scene_providers.dart, without
          // going through Riverpod for this pure-Dart test.
          final target = subjectFixture(
            shoulderAngleDegrees: 0,
            shoulderBalanceRatio: 0.5,
            bodyYawEstimate: 0,
          );
          final targetScene = sceneFixture(
            brightness: 0.5,
            negativeSpaceScore: 0.5,
            symmetryScore: 0.5,
          );
          final scene = sceneFixture(
            brightness: 0.5,
            negativeSpaceScore: 0.5,
            symmetryScore: 0.5,
          );

          // --- Step 1: subject is clearly mismatched ---
          final mismatchedSubject = subjectFixture(
            shoulderAngleDegrees: 45,
            shoulderBalanceRatio: 0.9,
            bodyYawEstimate: 45,
          );

          final coachingWhileMismatched = engine.evaluate(
            subject: mismatchedSubject,
            scene: scene,
            reference: reference,
            tolerance: tolerance,
            isFrontCamera: isFrontCamera,
          );
          expect(coachingWhileMismatched, isNotNull);

          final progressWhileMismatched = trackingEngine.trackingProgress(
            mismatchedSubject,
            target,
            scene,
            targetScene,
            tolerance,
          );
          expect(progressWhileMismatched, lessThan(0.9));

          final captureWhileMismatched = autoCapture.shouldCapture(
            mismatchedSubject,
            scene,
            reference,
            tolerance,
            progressWhileMismatched,
            DetectionThresholds.defaultValues,
          );
          expect(captureWhileMismatched, isFalse);

          // --- Step 2: subject corrects to match the reference ---
          final correctedSubject = subjectFixture(
            shoulderAngleDegrees: 0,
            shoulderBalanceRatio: 0.5,
            bodyYawEstimate: 0,
            faceAngleDegrees: 0,
            faceAngleXDegrees: 0,
            faceAngleZDegrees: 0,
          );

          final coachingWhileCorrected = engine.evaluate(
            subject: correctedSubject,
            scene: scene,
            reference: reference,
            tolerance: tolerance,
            isFrontCamera: isFrontCamera,
          );
          expect(coachingWhileCorrected, isNull);

          final progressWhileCorrected = trackingEngine.trackingProgress(
            correctedSubject,
            target,
            scene,
            targetScene,
            tolerance,
          );
          expect(progressWhileCorrected, closeTo(1.0, 0.0001));

          final canCaptureNow = autoCapture.shouldCapture(
            correctedSubject,
            scene,
            reference,
            tolerance,
            progressWhileCorrected,
            DetectionThresholds.defaultValues,
          );
          expect(canCaptureNow, isTrue);

          await autoCapture.triggerCapture();

          final shot = buildShotFromCapture(
            imagePath: '/tmp/${label.replaceAll(' ', '_')}.jpg',
            subject: correctedSubject,
            scene: scene,
            reference: reference,
            tolerance: tolerance,
            shotType: 'portrait',
          );
          expect(shot.score.overall, greaterThanOrEqualTo(90));
        },
      );
    }
  });

  // -------------------------------------------------------------------------
  group('CorrectionRecord._classify() (correction_feedback.dart)', () {
    CorrectionRecord makeRecord({
      required CoachingAttribute attribute,
      required double pre,
      double? target,
      CoachingDirection direction = CoachingDirection.none,
      double noiseFloor = 0.5,
    }) {
      return CorrectionRecord(
        attribute: attribute,
        preMeasurement: pre,
        referenceTarget: target,
        expectedDirection: direction,
        instructedAt: DateTime(2026, 1, 1),
        noiseFloor: noiseFloor,
      );
    }

    test(
      'circular attribute near the ±180° wrap classifies correctly as '
      'reversed, not improved (regression for the bug found this session)',
      () {
        // pre=-179 is really 2° from target=179 (short way); post=-170 is
        // really 11° away -> it got worse. Plain linear subtraction reads
        // this as 358 -> 349, i.e. "closer", and would wrongly say improved.
        final r = makeRecord(
          attribute: CoachingAttribute.shoulderAngle,
          pre: -179,
          target: 179,
        );
        r.close(measuredValue: -170, measurementConfident: true);
        expect(r.outcome, CorrectionOutcome.reversed);
      },
    );

    test('circular attribute correctly detects improvement when the short path '
        'crosses the target', () {
      final r = makeRecord(
        attribute: CoachingAttribute.shoulderAngle,
        pre: -179,
        target: 179,
      );
      r.close(measuredValue: 178, measurementConfident: true);
      expect(r.outcome, CorrectionOutcome.improved);
    });

    test(
      'a non-circular attribute is unaffected by the circular-aware code path',
      () {
        final r = makeRecord(
          attribute: CoachingAttribute.shoulderBalance,
          pre: 0.3,
          target: 0.5,
          noiseFloor: 0.05,
        );
        r.close(measuredValue: 0.45, measurementConfident: true);
        expect(r.outcome, CorrectionOutcome.improved);
      },
    );

    test('unmeasurable when there is no value or confidence is too low', () {
      final noValue = makeRecord(
        attribute: CoachingAttribute.shoulderAngle,
        pre: 10,
        target: 0,
      );
      noValue.close(measuredValue: null, measurementConfident: true);
      expect(noValue.outcome, CorrectionOutcome.unmeasurable);

      final lowConfidence = makeRecord(
        attribute: CoachingAttribute.shoulderAngle,
        pre: 10,
        target: 0,
      );
      lowConfidence.close(measuredValue: 5, measurementConfident: false);
      expect(lowConfidence.outcome, CorrectionOutcome.unmeasurable);
    });

    test('unchanged when the movement is within the noise floor', () {
      final r = makeRecord(
        attribute: CoachingAttribute.shoulderBalance,
        pre: 0.5,
        target: 0.8,
        noiseFloor: 0.1,
      );
      r.close(measuredValue: 0.52, measurementConfident: true); // moved 0.02
      expect(r.outcome, CorrectionOutcome.unchanged);
    });

    test(
      'overshot when the correction crosses the target and lands far past it',
      () {
        final r = makeRecord(
          attribute: CoachingAttribute.shoulderBalance,
          pre: 0.2,
          target: 0.5,
          noiseFloor: 0.05,
        );
        r.close(measuredValue: 0.9, measurementConfident: true);
        expect(r.outcome, CorrectionOutcome.overshot);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('CoachingEligibility (coaching_eligibility.dart)', () {
    test('doNotCoach controllability is always ineligible', () {
      const elig = CoachingEligibility();
      final result = elig.evaluate(
        decisionConfidence: 1.0,
        controllability: ActionControllability.doNotCoach,
        subjectFullyInFrame: true,
        detectorsAgree: true,
        temporallyEligible: true,
        inCooldown: false,
      );
      expect(result.eligible, isFalse);
      expect(result.reason, IneligibilityReason.notSubjectControllable);
    });

    test('FINDING, not asserted as a bug: with the default '
        'cameraFacingChannelEnabled=false, every non-subjectAction attribute '
        'is ineligible regardless of confidence/detectors/frame — only '
        'subjectAction is unaffected. Confirm this default is intentional '
        'before wiring composition/lighting coaching through this gate.', () {
      const elig = CoachingEligibility();
      for (final controllability in [
        ActionControllability.cameraAction,
        ActionControllability.environmentAction,
        ActionControllability.lightingAction,
        ActionControllability.compositionAction,
      ]) {
        final result = elig.evaluate(
          decisionConfidence: 1.0,
          controllability: controllability,
          subjectFullyInFrame: true,
          detectorsAgree: true,
          temporallyEligible: true,
          inCooldown: false,
        );
        expect(
          result.eligible,
          isFalse,
          reason: '$controllability should be blocked by the default flag',
        );
      }
      final subjectResult = elig.evaluate(
        decisionConfidence: 1.0,
        controllability: ActionControllability.subjectAction,
        subjectFullyInFrame: true,
        detectorsAgree: true,
        temporallyEligible: true,
        inCooldown: false,
      );
      expect(subjectResult.eligible, isTrue);
    });

    test('enabling cameraFacingChannelEnabled lifts that restriction', () {
      const elig = CoachingEligibility(cameraFacingChannelEnabled: true);
      final result = elig.evaluate(
        decisionConfidence: 1.0,
        controllability: ActionControllability.lightingAction,
        subjectFullyInFrame: true,
        detectorsAgree: true,
        temporallyEligible: true,
        inCooldown: false,
      );
      expect(result.eligible, isTrue);
    });

    test('confidence below the floor is ineligible', () {
      const elig = CoachingEligibility();
      final result = elig.evaluate(
        decisionConfidence: 0.3, // below ConfidenceFloors.eligibleToSpeak
        controllability: ActionControllability.subjectAction,
        subjectFullyInFrame: true,
        detectorsAgree: true,
        temporallyEligible: true,
        inCooldown: false,
      );
      expect(result.eligible, isFalse);
      expect(result.reason, IneligibilityReason.confidenceTooLow);
    });

    test('subjectAction requires the subject to be fully in frame', () {
      const elig = CoachingEligibility();
      final result = elig.evaluate(
        decisionConfidence: 1.0,
        controllability: ActionControllability.subjectAction,
        subjectFullyInFrame: false,
        detectorsAgree: true,
        temporallyEligible: true,
        inCooldown: false,
      );
      expect(result.eligible, isFalse);
      expect(result.reason, IneligibilityReason.subjectPartiallyOutOfFrame);
    });

    test('cooldown is checked last and blocks an otherwise-eligible plan', () {
      const elig = CoachingEligibility();
      final result = elig.evaluate(
        decisionConfidence: 1.0,
        controllability: ActionControllability.subjectAction,
        subjectFullyInFrame: true,
        detectorsAgree: true,
        temporallyEligible: true,
        inCooldown: true,
      );
      expect(result.eligible, isFalse);
      expect(result.reason, IneligibilityReason.inCooldown);
    });
  });

  // -------------------------------------------------------------------------
  group('ResponsivenessModel (adaptive_correction_model.dart)', () {
    test('defaults to asAuthored before enough samples exist', () {
      final model = ResponsivenessModel();
      expect(
        model.adjustmentFor(CoachingAttribute.shoulderAngle),
        IntensityAdjustment.asAuthored,
      );
    });

    test('recommends softening after consistent overshoot', () {
      final model = ResponsivenessModel(minSamplesBeforeAdjusting: 2);
      for (var i = 0; i < 2; i++) {
        final r = CorrectionRecord(
          attribute: CoachingAttribute.shoulderAngle,
          preMeasurement: 0,
          referenceTarget: null,
          expectedDirection: CoachingDirection.increase,
          instructedAt: DateTime(2026, 1, 1),
        );
        r.close(measuredValue: 10, measurementConfident: true);
        model.recordOutcome(r, CoachingSeverityBand.mild);
      }
      expect(
        model.adjustmentFor(CoachingAttribute.shoulderAngle),
        IntensityAdjustment.soften,
      );
    });

    test('adjustedBand clamps at the edges of mild/moderate/strong instead of '
        'going out of range', () {
      final model = ResponsivenessModel(minSamplesBeforeAdjusting: 1);
      final r = CorrectionRecord(
        attribute: CoachingAttribute.shoulderAngle,
        preMeasurement: 0,
        referenceTarget: null,
        expectedDirection: CoachingDirection.increase,
        instructedAt: DateTime(2026, 1, 1),
      );
      r.close(measuredValue: 10, measurementConfident: true);
      model.recordOutcome(r, CoachingSeverityBand.mild); // gain=10 -> soften

      expect(
        model.adjustedBand(
          CoachingAttribute.shoulderAngle,
          CoachingSeverityBand.mild,
        ),
        CoachingSeverityBand.mild, // already at the floor, stays put
      );
      expect(
        model.adjustedBand(
          CoachingAttribute.shoulderAngle,
          CoachingSeverityBand.strong,
        ),
        CoachingSeverityBand.moderate,
      );
    });

    test('recommends strengthening after consistent undershoot', () {
      final model = ResponsivenessModel(minSamplesBeforeAdjusting: 2);
      for (var i = 0; i < 2; i++) {
        final r = CorrectionRecord(
          attribute: CoachingAttribute.shoulderBalance,
          preMeasurement: 0.5,
          referenceTarget: null,
          expectedDirection: CoachingDirection.increase,
          instructedAt: DateTime(2026, 1, 1),
          noiseFloor: 0.05,
        );
        r.close(measuredValue: 0.8, measurementConfident: true); // moved 0.3
        model.recordOutcome(r, CoachingSeverityBand.mild); // gain=0.3
      }
      expect(
        model.adjustmentFor(CoachingAttribute.shoulderBalance),
        IntensityAdjustment.strengthen,
      );
    });

    test('regression: recordOutcome() now measures movement circularly for '
        'angle-wrapping attributes — a real ~1° movement near the ±180° wrap '
        'no longer reads as an enormous ~359° swing', () {
      final model = ResponsivenessModel(minSamplesBeforeAdjusting: 1);
      final r = CorrectionRecord(
        attribute: CoachingAttribute.shoulderAngle,
        preMeasurement: 179.5,
        referenceTarget: null,
        expectedDirection: CoachingDirection.none,
        instructedAt: DateTime(2026, 1, 1),
        noiseFloor: 0.5,
      );
      r.close(measuredValue: -179.5, measurementConfident: true);
      // sanity: _classify() is already circular-aware from the earlier fix
      expect(r.outcome, CorrectionOutcome.improved);

      model.recordOutcome(r, CoachingSeverityBand.mild);
      // Real movement is ~1°, matching a mild instruction almost exactly
      // -> asAuthored. Before this fix, linear |post-pre| = 359 would
      // have read as a wild overshoot and recommended softening instead.
      expect(
        model.adjustmentFor(CoachingAttribute.shoulderAngle),
        IntensityAdjustment.asAuthored,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('CoachingStateMachine (coaching_state_machine.dart)', () {
    EligibilityContext alwaysEligibleContext(ActionPlan _) {
      return const EligibilityContext(
        subjectFullyInFrame: true,
        detectorsAgree: true,
        temporallyEligible: true,
      );
    }

    ActionPlan planFor(
      CoachingAttribute attribute,
      double severity, {
      ActionControllability controllability =
          ActionControllability.subjectAction,
    }) {
      final decision = CoachingDecision(
        attribute: attribute,
        direction: CoachingDirection.increase,
        tier: CoachingTier.poseAndFace,
        normalizedSeverity: severity,
        fallbackPhrase: 'test phrase for ${attribute.name}',
        confidence: 0.9,
        controllability: controllability,
      );
      return ActionPlan(
        phrase: decision.fallbackPhrase,
        decision: decision,
        sourceLayer: 'test',
        confidence: decision.confidence,
        controllability: controllability,
      );
    }

    test(
      'observe() picks the most severe eligible candidate and enters instruct',
      () {
        final machine = CoachingStateMachine();
        final plan = planFor(CoachingAttribute.shoulderAngle, 0.6);

        final output = machine.observe(
          poseAndFace: [plan],
          composition: [],
          lighting: [],
          contextFor: alwaysEligibleContext,
          tierRotation: 0,
        );

        expect(output.state, CoachingState.instruct);
        expect(
          output.planToSpeak?.decision.attribute,
          CoachingAttribute.shoulderAngle,
        );
        expect(machine.state, CoachingState.instruct);
      },
    );

    test('observe() stays in observe with nothing to speak when every '
        'candidate is ineligible (here: blocked by cameraFacingChannelEnabled '
        "defaulting to false, since coaching_eligibility.dart's default is "
        'used inside this machine)', () {
      final machine = CoachingStateMachine();
      final plan = planFor(
        CoachingAttribute.backgroundClutter,
        0.6,
        controllability: ActionControllability.environmentAction,
      );

      final output = machine.observe(
        poseAndFace: [],
        composition: [plan],
        lighting: [],
        contextFor: alwaysEligibleContext,
        tierRotation: 0,
      );

      expect(output.state, CoachingState.observe);
      expect(output.planToSpeak, isNull);
      expect(machine.state, CoachingState.observe);
    });

    test('a full cycle: observe -> instruct -> wait -> reobserve -> confirm, '
        'then next() resets to observe', () {
      final machine = CoachingStateMachine();
      final plan = planFor(CoachingAttribute.shoulderAngle, 0.6);

      machine.observe(
        poseAndFace: [plan],
        composition: [],
        lighting: [],
        contextFor: alwaysEligibleContext,
        tierRotation: 0,
      );
      expect(machine.state, CoachingState.instruct);

      machine.instructed(
        preMeasurement: 40.0,
        referenceTarget: 0.0,
        noiseFloor: 5.0,
      );
      expect(machine.state, CoachingState.wait);

      final outcome = machine.reobserve(
        measuredValue: 5.0,
        measurementConfident: true,
      );
      expect(outcome, CorrectionOutcome.improved);
      expect(machine.state, CoachingState.confirm);

      machine.next();
      expect(machine.state, CoachingState.observe);
      expect(machine.currentPlan, isNull);
    });

    test('reobserve() with an unmeasurable reading retries up to '
        'maxWaitRetries before falling through to escalate', () {
      final machine = CoachingStateMachine(maxWaitRetries: 1);
      final plan = planFor(CoachingAttribute.shoulderAngle, 0.6);
      machine.observe(
        poseAndFace: [plan],
        composition: [],
        lighting: [],
        contextFor: alwaysEligibleContext,
        tierRotation: 0,
      );
      machine.instructed(
        preMeasurement: 40.0,
        referenceTarget: 0.0,
        noiseFloor: 5.0,
      );

      final firstAttempt = machine.reobserve(
        measuredValue: null,
        measurementConfident: true,
      );
      expect(firstAttempt, CorrectionOutcome.unmeasurable);
      expect(machine.state, CoachingState.wait); // one retry left

      final secondAttempt = machine.reobserve(
        measuredValue: null,
        measurementConfident: true,
      );
      expect(secondAttempt, CorrectionOutcome.unmeasurable);
      expect(machine.state, isNot(CoachingState.wait)); // retries exhausted
    });

    test('SessionMemory suppresses an attribute after repeated reversals, and '
        'observe() then filters it out before eligibility even runs', () {
      final machine = CoachingStateMachine();
      final plan = planFor(CoachingAttribute.shoulderAngle, 0.6);

      for (var i = 0; i < 2; i++) {
        machine.observe(
          poseAndFace: [plan],
          composition: [],
          lighting: [],
          contextFor: alwaysEligibleContext,
          tierRotation: 0,
        );
        machine.instructed(
          preMeasurement: 40.0,
          referenceTarget: 0.0,
          noiseFloor: 1.0,
        );
        // moved the wrong way each time -> reversed
        machine.reobserve(measuredValue: 45.0, measurementConfident: true);
        machine.next();
      }

      expect(
        machine.sessionMemory.isSuppressed(CoachingAttribute.shoulderAngle),
        isTrue,
      );

      final output = machine.observe(
        poseAndFace: [plan],
        composition: [],
        lighting: [],
        contextFor: alwaysEligibleContext,
        tierRotation: 0,
      );
      expect(output.planToSpeak, isNull);
    });

    test('an improved outcome resets the attempt count to 0 and starts the '
        'post-resolution grace period', () {
      final machine = CoachingStateMachine();
      final plan = planFor(CoachingAttribute.shoulderAngle, 0.6);

      machine.observe(
        poseAndFace: [plan],
        composition: [],
        lighting: [],
        contextFor: alwaysEligibleContext,
        tierRotation: 0,
      );
      expect(
        machine.sessionMemory.attemptCounts[CoachingAttribute.shoulderAngle],
        1,
      );

      machine.instructed(
        preMeasurement: 40.0,
        referenceTarget: 0.0,
        noiseFloor: 5.0,
      );
      machine.reobserve(measuredValue: 5.0, measurementConfident: true);

      expect(
        machine.sessionMemory.attemptCounts[CoachingAttribute.shoulderAngle],
        0,
      );
      expect(
        machine.sessionMemory.inPostResolutionGrace(
          CoachingAttribute.shoulderAngle,
          DateTime.now(),
          const Duration(seconds: 3),
        ),
        isTrue,
      );
    });

    test('the second reversal in a row lands in abandon specifically, not '
        'just escalate (reversalCount hit maxReversalsBeforeSuppression)', () {
      final machine = CoachingStateMachine();
      final plan = planFor(CoachingAttribute.shoulderAngle, 0.6);

      for (var i = 0; i < 2; i++) {
        machine.observe(
          poseAndFace: [plan],
          composition: [],
          lighting: [],
          contextFor: alwaysEligibleContext,
          tierRotation: 0,
        );
        machine.instructed(
          preMeasurement: 40.0,
          referenceTarget: 0.0,
          noiseFloor: 1.0,
        );
        machine.reobserve(measuredValue: 45.0, measurementConfident: true);
        if (i == 0) {
          expect(machine.state, CoachingState.escalate); // first: not yet
          machine.next();
        }
      }
      expect(machine.state, CoachingState.abandon); // second: suppressed
    });

    test('abandons via the plain attempt-count path too — three unchanged '
        'attempts with no reversal involved at all', () {
      final machine = CoachingStateMachine();
      final plan = planFor(CoachingAttribute.shoulderBalance, 0.6);

      for (var i = 0; i < 3; i++) {
        machine.observe(
          poseAndFace: [plan],
          composition: [],
          lighting: [],
          contextFor: alwaysEligibleContext,
          tierRotation: 0,
        );
        machine.instructed(
          preMeasurement: 0.5,
          referenceTarget: 0.8,
          noiseFloor: 1.0, // huge, relative to the tiny movement below
        );
        final outcome = machine.reobserve(
          measuredValue: 0.51, // moved 0.01 -- well under the noise floor
          measurementConfident: true,
        );
        expect(outcome, CorrectionOutcome.unchanged);
        if (i < 2) machine.next();
      }

      expect(machine.state, CoachingState.abandon);
      expect(
        machine.sessionMemory.reversalCounts[CoachingAttribute.shoulderBalance],
        isNull, // confirms this path is attempt-count-driven, not reversals
      );
    });
  });

  // -------------------------------------------------------------------------
  group(
    'Arm-pose coaching (pose_and_face_evaluators.dart) — UPDATE: equivalent '
    'logic (same phrasing, expanded vocabulary) has since been ported into '
    'reference_comparison_engine.dart\'s _evaluateRightArmPosition/'
    '_evaluateLeftArmPosition and wired into evaluateTiers(), so this is no '
    'longer purely draft logic a real user never hears — see the '
    "'ReferenceComparisonEngine — arm position & arm-swap' group below for "
    'tests against that actual production path. pose_and_face_evaluators.'
    'dart itself remains unconfirmed as reachable from the live app (still '
    'flagged "likely orphaned" per the project\'s own docs), so these '
    'tests still only prove the standalone-file logic, not what a user '
    'hears today.',
    () {
      test('Vogue-cover-style reference pose: left hand near the face, right '
          'hand on the hip — subject with both arms down gets told to move '
          'both, in the right direction', () {
        // Matches the uploaded reference photo: left arm bent up with the
        // hand resting near the forehead/hair (nearFace), right hand on
        // the hip (akimbo).
        final reference = referenceFixture(
          leftArmPoseCategory: 'nearFace',
          rightArmPoseCategory: 'akimbo',
        );
        final subject = subjectFixture(
          leftArmPoseCategory: 'down',
          rightArmPoseCategory: 'down',
        );

        final left = evaluateLeftArmPosition(subject, reference, tolerance);
        final right = evaluateRightArmPosition(subject, reference, tolerance);

        expect(left, isNotNull);
        expect(left!.deviationExceedsThreshold, isTrue);
        // Broad match, not one exact string: the category-instruction bank
        // has 8 randomly-chosen nearFace variants (added this session for
        // vocabulary depth) — every one mentions "hand" plus one of
        // face/head/forehead/hairline/temple, but no single literal
        // substring is common to all 8.
        expect(
          left.phrase.toLowerCase(),
          allOf(
            contains('hand'),
            anyOf(
              contains('face'),
              contains('head'),
              contains('forehead'),
              contains('hairline'),
              contains('temple'),
            ),
          ),
          reason:
              'should tell the subject to bring the left hand up, '
              'like the reference photo',
        );

        expect(right, isNotNull);
        expect(right!.deviationExceedsThreshold, isTrue);
        // Same reasoning: 7 randomly-chosen akimbo variants, one of which
        // ("rest your right hand on your waist") says "waist" not "hip".
        expect(
          right.phrase.toLowerCase(),
          anyOf(contains('hip'), contains('waist')),
          reason:
              'should tell the subject to put the right hand on the '
              'hip, like the reference photo',
        );
      });

      test('subject already matches the reference pose (same category, close '
          'angles) -> no correction needed on either arm', () {
        final reference = referenceFixture(
          leftArmPoseCategory: 'nearFace',
          leftArmRaiseDegrees: 100,
          leftElbowAngleDegrees: 40,
          rightArmPoseCategory: 'akimbo',
          rightArmRaiseDegrees: 30,
          rightElbowAngleDegrees: 100,
        );
        final subject = subjectFixture(
          leftArmPoseCategory: 'nearFace',
          leftArmRaiseDegrees: 102,
          leftElbowAngleDegrees: 42,
          rightArmPoseCategory: 'akimbo',
          rightArmRaiseDegrees: 31,
          rightElbowAngleDegrees: 98,
        );

        final left = evaluateLeftArmPosition(subject, reference, tolerance);
        final right = evaluateRightArmPosition(subject, reference, tolerance);

        expect(left?.deviationExceedsThreshold, isFalse);
        expect(right?.deviationExceedsThreshold, isFalse);
      });

      test('same category (akimbo) but the elbow angle itself is off -> bends '
          'the elbow in the correct direction, not a category instruction', () {
        final reference = referenceFixture(
          rightArmPoseCategory: 'akimbo',
          rightArmRaiseDegrees: 30,
          rightElbowAngleDegrees: 100,
        );
        final subject = subjectFixture(
          rightArmPoseCategory: 'akimbo', // same category as reference
          rightArmRaiseDegrees: 30, // raise matches
          rightElbowAngleDegrees: 170, // elbow much straighter
        );

        final result = evaluateRightArmPosition(subject, reference, tolerance);

        expect(result, isNotNull);
        expect(result!.deviationExceedsThreshold, isTrue);
        // Broad match across all 6 randomly-chosen "bend the elbow in"
        // variants (added this session), not one hardcoded string.
        expect(
          result.phrase.toLowerCase(),
          anyOf(
            contains('bend your right elbow in more'),
            contains('fold your right elbow in a bit more'),
            contains('bring your right elbow in closer'),
            contains('tuck that right elbow in a bit more'),
            contains('bend your right arm at the elbow'),
            contains('bring your right elbow in tighter'),
          ),
        );
        expect(result.decision.direction, CoachingDirection.decrease);
      });

      test('raised too high relative to the reference -> told to lower it '
          '(direction correctness)', () {
        final reference = referenceFixture(
          leftArmPoseCategory: 'raised',
          leftArmRaiseDegrees: 90,
        );
        final subject = subjectFixture(
          leftArmPoseCategory: 'raised',
          leftArmRaiseDegrees: 150, // raised well past the reference
        );

        final result = evaluateLeftArmPosition(subject, reference, tolerance);

        expect(result, isNotNull);
        expect(result!.deviationExceedsThreshold, isTrue);
        // Broad match across all 6 randomly-chosen "lower the arm" variants
        // (added this session) — all mention "left arm" and either
        // "lower" or "down", but no single exact phrase is common to all 6.
        expect(
          result.phrase.toLowerCase(),
          allOf(
            contains('left arm'),
            anyOf(contains('lower'), contains('down')),
          ),
        );
        expect(result.decision.direction, CoachingDirection.decrease);
      });

      test('raised too little relative to the reference -> told to raise it '
          'further (direction correctness, the mirror image of the above)', () {
        final reference = referenceFixture(
          leftArmPoseCategory: 'raised',
          leftArmRaiseDegrees: 90,
        );
        final subject = subjectFixture(
          leftArmPoseCategory: 'raised',
          leftArmRaiseDegrees: 20,
        );

        final result = evaluateLeftArmPosition(subject, reference, tolerance);

        expect(result, isNotNull);
        expect(result!.deviationExceedsThreshold, isTrue);
        // Broad match across all 6 randomly-chosen "raise the arm" variants
        // (added this session) — all mention "left arm" and one of
        // raise/lift/up/higher, but no single exact phrase is common to
        // all 6, and none of the "lower" variants (see the test above)
        // contain any of these words, so this can't accidentally match
        // the wrong direction.
        expect(
          result.phrase.toLowerCase(),
          allOf(
            contains('left arm'),
            anyOf(
              contains('raise'),
              contains('lift'),
              contains('up'),
              contains('higher'),
            ),
          ),
        );
        expect(result.decision.direction, CoachingDirection.increase);
      });

      test('reference photo has no arm data at all -> null, nothing to coach '
          'against', () {
        final reference = referenceFixture(); // no arm fields set
        final subject = subjectFixture(rightArmRaiseDegrees: 90);

        final result = evaluateRightArmPosition(subject, reference, tolerance);
        expect(result, isNull);
      });

      test('both raise and elbow deviate at once -> both make it into the '
          'phrase, and the direction tie-break follows whichever deviation '
          'is larger', () {
        final reference = referenceFixture(
          rightArmPoseCategory: 'akimbo',
          rightArmRaiseDegrees: 30,
          rightElbowAngleDegrees: 100,
        );
        final subject = subjectFixture(
          rightArmPoseCategory: 'akimbo', // same category
          rightArmRaiseDegrees: 80, // deviation 50
          rightElbowAngleDegrees: 170, // deviation 70 -- larger
        );

        final result = evaluateRightArmPosition(subject, reference, tolerance);

        expect(result, isNotNull);
        expect(result!.deviationExceedsThreshold, isTrue);
        final phrase = result.phrase.toLowerCase();
        // Same broad-match reasoning as the two direction-correctness tests
        // above, applied to both halves of the combined phrase.
        expect(
          phrase,
          allOf(
            contains('right arm'),
            anyOf(contains('lower'), contains('down')),
          ),
        );
        expect(
          phrase,
          anyOf(
            contains('bend your right elbow in more'),
            contains('fold your right elbow in a bit more'),
            contains('bring your right elbow in closer'),
            contains('tuck that right elbow in a bit more'),
            contains('bend your right arm at the elbow'),
            contains('bring your right elbow in tighter'),
          ),
        );
        // elbow's deviation (70) is larger than raise's (50), so the
        // direction should follow the elbow instruction (decrease).
        expect(result.decision.direction, CoachingDirection.decrease);
      });

      test('EDGE CASE: raise and elbow deviations are EXACTLY equal -> tie '
          'goes to raise, since the tie-break condition is '
          '"raiseDeviation >= elbowDeviation" (>=, not >)', () {
        final reference = referenceFixture(
          rightArmPoseCategory: 'akimbo',
          rightArmRaiseDegrees: 30,
          rightElbowAngleDegrees: 100,
        );
        final subject = subjectFixture(
          rightArmPoseCategory: 'akimbo',
          // Both deviations are 30° — comfortably past the 22.5°
          // threshold (poseTolerance=0.5) so both actually register as
          // exceeding it, not just tied at a sub-threshold value.
          rightArmRaiseDegrees: 0, // deviation 30, subject < reference
          rightElbowAngleDegrees: 130, // deviation 30, subject > reference
        );

        final result = evaluateRightArmPosition(subject, reference, tolerance);

        expect(result, isNotNull);
        expect(result!.deviationExceedsThreshold, isTrue);
        // Both deviations are 30 -> raise wins the tie -> direction should
        // follow the raise instruction (subject < reference -> increase),
        // not the elbow instruction (subject > reference -> decrease).
        expect(result.decision.direction, CoachingDirection.increase);
      });

      test('KNOWN LIMITATION, documented not fixed: evaluateArmSwap only '
          'compares CATEGORICAL fields (leftArmPoseCategory/'
          'rightArmPoseCategory) — if both arms happen to share the same '
          'category as the reference but their raise/elbow ANGLES are '
          'swapped between the two arms, this is not detected as a swap '
          'at all, and each arm is scored against its own reference '
          'target independently, likely producing two confusing '
          '"both a bit off" corrections instead of one clear "you have '
          'them backwards" message.', () {
        final reference = referenceFixture(
          leftArmPoseCategory: 'raised',
          leftArmRaiseDegrees: 30,
          rightArmPoseCategory: 'raised', // same category both sides
          rightArmRaiseDegrees: 150,
        );
        // Subject's raise angles are swapped between the two arms, but
        // both are still 'raised' -> armsAppearSwapped() can't see this,
        // since it only ever compares the category strings, which match
        // on both sides trivially (see the "reference wants the SAME "
        // "category on both arms" test above for why: no swap concept
        // applies when categories don't differ in the first place).
        final subject = subjectFixture(
          leftArmPoseCategory: 'raised',
          leftArmRaiseDegrees: 150, // has the reference's RIGHT angle
          rightArmPoseCategory: 'raised',
          rightArmRaiseDegrees: 30, // has the reference's LEFT angle
        );

        expect(
          evaluateArmSwap(subject, reference),
          isNull,
          reason:
              'documents the real gap — this SHOULD arguably be a swap, '
              'but the categorical-only check cannot see it',
        );

        // Each arm gets scored independently instead, per the current
        // (limited) design:
        final left = evaluateLeftArmPosition(subject, reference, tolerance);
        final right = evaluateRightArmPosition(subject, reference, tolerance);
        expect(left, isNotNull);
        expect(left!.deviationExceedsThreshold, isTrue);
        expect(right, isNotNull);
        expect(right!.deviationExceedsThreshold, isTrue);
      });

      test('an unrecognized reference category falls back to the generic '
          '"match your arm to the reference" instruction instead of crashing '
          'on a missing map entry', () {
        final reference = referenceFixture(leftArmPoseCategory: 'floating');
        final subject = subjectFixture(leftArmPoseCategory: 'down');

        final result = evaluateLeftArmPosition(subject, reference, tolerance);

        expect(result, isNotNull);
        expect(
          result!.phrase.toLowerCase(),
          contains('match your left arm to the reference'),
        );
      });

      // -----------------------------------------------------------------
      // evaluateArmSwap — added this session. Catches the common
      // "mirrored the whole pose" mistake: raising the wrong arm and/or
      // resting the wrong hand on the hip, i.e. the subject's left/right
      // arm categories are cleanly swapped relative to the reference's.
      // -----------------------------------------------------------------

      test('evaluateArmSwap: a clean swap (subject\'s left matches the '
          "reference's right and vice versa) is detected", () {
        final reference = referenceFixture(
          leftArmPoseCategory: 'nearFace',
          rightArmPoseCategory: 'akimbo',
        );
        final subject = subjectFixture(
          leftArmPoseCategory: 'akimbo', // has the reference's RIGHT category
          rightArmPoseCategory: 'nearFace', // has the reference's LEFT one
        );

        final result = evaluateArmSwap(subject, reference);

        expect(result, isNotNull);
        expect(result!.deviationExceedsThreshold, isTrue);
        expect(
          result.phrase.toLowerCase(),
          anyOf(contains('swap'), contains('switch')),
          reason:
              'should tell the subject to swap arms, not adjust each '
              'one individually',
        );
        expect(result.decision.direction, CoachingDirection.none);
      });

      test('evaluateArmSwap: matching categories (no swap) -> null, nothing '
          'to say', () {
        final reference = referenceFixture(
          leftArmPoseCategory: 'nearFace',
          rightArmPoseCategory: 'akimbo',
        );
        final subject = subjectFixture(
          leftArmPoseCategory: 'nearFace',
          rightArmPoseCategory: 'akimbo',
        );

        expect(evaluateArmSwap(subject, reference), isNull);
      });

      test('evaluateArmSwap: both arms mismatched but NOT a clean swap '
          '(e.g. both down, reference wants nearFace/akimbo) -> null — this '
          'is two independent corrections, not a swap', () {
        final reference = referenceFixture(
          leftArmPoseCategory: 'nearFace',
          rightArmPoseCategory: 'akimbo',
        );
        final subject = subjectFixture(
          leftArmPoseCategory: 'down',
          rightArmPoseCategory: 'down',
        );

        expect(evaluateArmSwap(subject, reference), isNull);
      });

      test('evaluateArmSwap: reference wants the SAME category on both arms '
          '(e.g. both down) -> null even if the subject also has both arms '
          'in the same (different) category — there is no "wrong side" '
          'concept when both reference targets are identical', () {
        final reference = referenceFixture(
          leftArmPoseCategory: 'down',
          rightArmPoseCategory: 'down',
        );
        final subject = subjectFixture(
          leftArmPoseCategory: 'raised',
          rightArmPoseCategory: 'raised',
        );

        expect(evaluateArmSwap(subject, reference), isNull);
      });

      test('evaluateArmSwap: missing category data on either side -> null, '
          'not a crash', () {
        final reference = referenceFixture(rightArmPoseCategory: 'akimbo');
        final subject = subjectFixture(rightArmPoseCategory: 'nearFace');
        // leftArmPoseCategory is null on both -> can't determine a swap.

        expect(evaluateArmSwap(subject, reference), isNull);
      });
    },
  );

  // -------------------------------------------------------------------------
  group('ReferenceComparisonEngine — arm position & arm-swap (wired into '
      'evaluateTiers() this session)', () {
    test(
      'arm-position mismatch (non-swap) surfaces through the real '
      'production path, not just the standalone pose_and_face_evaluators '
      '.dart functions — proves this is actually wired in, not draft-only',
      () {
        final engine = ReferenceComparisonEngine();
        final reference = referenceFixture(
          rightArmPoseCategory: 'akimbo',
          rightArmRaiseDegrees: 30,
          rightElbowAngleDegrees: 100,
        );
        final subject = subjectFixture(
          rightArmPoseCategory: 'down', // mismatched category, not a swap
        );
        final scene = sceneFixture();

        final tiers = engine.evaluateTiers(
          subject: subject,
          scene: scene,
          reference: reference,
          tolerance: tolerance,
          isFrontCamera: false,
        );

        expect(tiers.poseAndFace, isNotEmpty);
        expect(
          tiers.poseAndFace.any(
            (c) => c.decision.attribute == CoachingAttribute.rightArmPosition,
          ),
          isTrue,
        );
      },
    );

    test('a clean arm swap produces exactly ONE candidate (the swap '
        'message) instead of two separate, confusing per-arm corrections', () {
      final engine = ReferenceComparisonEngine();
      final reference = referenceFixture(
        leftArmPoseCategory: 'nearFace',
        rightArmPoseCategory: 'akimbo',
      );
      final subject = subjectFixture(
        leftArmPoseCategory: 'akimbo',
        rightArmPoseCategory: 'nearFace',
      );
      final scene = sceneFixture();

      final tiers = engine.evaluateTiers(
        subject: subject,
        scene: scene,
        reference: reference,
        tolerance: tolerance,
        isFrontCamera: false,
      );

      // If the swap short-circuit were NOT wired in, this would produce
      // two candidates (rightArmPosition and leftArmPosition, both
      // mismatched categories) instead of one swap message.
      expect(
        tiers.poseAndFace,
        hasLength(1),
        reason:
            'expected exactly the swap message, not two separate '
            'per-arm corrections',
      );
      expect(
        tiers.poseAndFace.single.decision.fallbackPhrase.toLowerCase(),
        anyOf(contains('swap'), contains('switch')),
      );
    });

    test('no swap -> the two per-arm evaluators run normally through the '
        'engine (regression guard: the swap check must not swallow '
        'legitimate individual corrections)', () {
      final engine = ReferenceComparisonEngine();
      final reference = referenceFixture(
        leftArmPoseCategory: 'nearFace',
        rightArmPoseCategory: 'akimbo',
      );
      final subject = subjectFixture(
        leftArmPoseCategory: 'down',
        rightArmPoseCategory: 'down',
      );
      final scene = sceneFixture();

      final tiers = engine.evaluateTiers(
        subject: subject,
        scene: scene,
        reference: reference,
        tolerance: tolerance,
        isFrontCamera: false,
      );

      final attributes = tiers.poseAndFace
          .map((c) => c.decision.attribute)
          .toSet();
      expect(attributes, contains(CoachingAttribute.leftArmPosition));
      expect(attributes, contains(CoachingAttribute.rightArmPosition));
    });
  });
}
