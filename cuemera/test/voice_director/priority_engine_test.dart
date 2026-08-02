// test/voice_director/priority_engine_test.dart
import 'package:cuemera/features/goal_selection/domain/models/photography_goal.dart';
import 'package:cuemera/features/scene_analysis/domain/models/scene_profile.dart';
import 'package:cuemera/features/scene_analysis/domain/models/subject_profile.dart';
import 'package:cuemera/features/voice_director/domain/editorial_rules.dart';
import 'package:cuemera/features/voice_director/domain/priority_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('getNextAction', () {
    test(
      'returns null when subject and scene satisfy all rule conditions for the goal',
      () {
        final subject = SubjectProfile(
          eyesOpen: true,
          shoulderAngleDegrees: 2,
          faceAngleDegrees: 5,
          expression: 'smiling',
          timestamp: DateTime.now(),
        );

        final scene = const SceneProfile(
          brightness: 0.5,
          lightDirectionDegrees: 10,
          negativeSpaceScore: 0.6,
          symmetryScore: 0.8,
          backgroundClutterCount: 1,
        );

        final result = getNextAction(subject, scene, PhotographyGoal.linkedin);

        expect(result, isNull);
      },
    );

    test(
      'returns exactly one PriorityAction and picks the highest severity when multiple conditions match',
      () {
        final subject = SubjectProfile(
          eyesOpen: false,
          shoulderAngleDegrees: 30,
          faceAngleDegrees: 5,
          expression: 'smiling',
          timestamp: DateTime.now(),
        );

        final scene = const SceneProfile(
          brightness: 0.1,
          lightDirectionDegrees: 10,
          negativeSpaceScore: 0.6,
          symmetryScore: 0.8,
          backgroundClutterCount: 1,
        );

        final result = getNextAction(subject, scene, PhotographyGoal.editorial);

        expect(result, isNotNull);
        expect(result, isA<PriorityAction>());
        expect(result!.severity, 9);
        expect(result.phrase, 'Open your eyes');
      },
    );

    test(
      'different PhotographyGoal values route to different rulesFor results',
      () {
        final editorialRules = rulesFor(PhotographyGoal.editorial);
        final linkedinRules = rulesFor(PhotographyGoal.linkedin);
        final datingRules = rulesFor(PhotographyGoal.dating);

        final editorialPhrases = editorialRules
            .map((r) => r.directionPhrase)
            .toSet();
        final linkedinPhrases = linkedinRules
            .map((r) => r.directionPhrase)
            .toSet();
        final datingPhrases = datingRules.map((r) => r.directionPhrase).toSet();

        expect(editorialPhrases, isNot(equals(linkedinPhrases)));
        expect(linkedinPhrases, isNot(equals(datingPhrases)));
        expect(
          editorialPhrases.contains('Give me more space in the frame'),
          isTrue,
        );
        expect(linkedinPhrases.contains('Give a warm smile'), isTrue);
        expect(datingPhrases.contains('Relax and smile naturally'), isTrue);
      },
    );

    test(
      'linkedin goal returns smile direction when expression is not smiling and nothing else fails',
      () {
        final subject = SubjectProfile(
          eyesOpen: true,
          shoulderAngleDegrees: 2,
          faceAngleDegrees: 5,
          expression: 'neutral',
          timestamp: DateTime.now(),
        );

        final scene = const SceneProfile(
          brightness: 0.5,
          negativeSpaceScore: 0.6,
          symmetryScore: 0.8,
          backgroundClutterCount: 1,
        );

        final result = getNextAction(subject, scene, PhotographyGoal.linkedin);

        expect(result, isNotNull);
        expect(result!.phrase, 'Give a warm smile');
        expect(result.severity, 5);
      },
    );
  });
}
