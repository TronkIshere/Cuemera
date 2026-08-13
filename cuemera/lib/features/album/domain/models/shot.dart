// features/album/domain/models/shot.dart
import '../../../editorial_score/domain/score_calculator.dart';
import '../../../reference_photo/domain/models/tolerance_settings.dart';

class Shot {
  const Shot({
    required this.id,
    required this.score,
    required this.timestamp,
    required this.shotType,
    this.imagePath,
    this.referenceImagePath,
    this.toleranceSettings,
  });

  final String id;
  final EditorialScore score;
  final DateTime timestamp;
  final String shotType;
  final String? imagePath;

  final String? referenceImagePath;

  final ToleranceSettings? toleranceSettings;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'score': score.toMap(),
      'timestamp': timestamp.millisecondsSinceEpoch,
      'shotType': shotType,
      'imagePath': imagePath,
      'referenceImagePath': referenceImagePath,
      'toleranceSettings': toleranceSettings?.toMap(),
    };
  }

  factory Shot.fromMap(Map<String, dynamic> map) {
    final toleranceMap = map['toleranceSettings'] as Map?;
    return Shot(
      id: map['id'] as String,
      score: EditorialScore.fromMap(
        Map<String, dynamic>.from(map['score'] as Map),
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      shotType: map['shotType'] as String,
      imagePath: map['imagePath'] as String?,
      referenceImagePath: map['referenceImagePath'] as String?,
      toleranceSettings: toleranceMap == null
          ? null
          : ToleranceSettings.fromMap(Map<String, dynamic>.from(toleranceMap)),
    );
  }
}
