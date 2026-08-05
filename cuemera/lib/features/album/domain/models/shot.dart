// features/album/domain/models/shot.dart
import '../../../editorial_score/domain/score_calculator.dart';

class Shot {
  const Shot({
    required this.id,
    required this.score,
    required this.timestamp,
    required this.shotType,
    this.imagePath,
  });

  final String id;
  final EditorialScore score;
  final DateTime timestamp;
  final String shotType;
  final String? imagePath;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'score': score.toMap(),
      'timestamp': timestamp.millisecondsSinceEpoch,
      'shotType': shotType,
      'imagePath': imagePath,
    };
  }

  factory Shot.fromMap(Map<String, dynamic> map) {
    return Shot(
      id: map['id'] as String,
      score: EditorialScore.fromMap(
        Map<String, dynamic>.from(map['score'] as Map),
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      shotType: map['shotType'] as String,
      imagePath: map['imagePath'] as String?,
    );
  }
}
