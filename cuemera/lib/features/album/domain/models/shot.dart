// features/album/domain/models/shot.dart
import '../../../editorial_score/domain/score_calculator.dart';

class Shot {
  const Shot({
    required this.id,
    required this.score,
    required this.timestamp,
    required this.shotType,
  });

  final String id;
  final EditorialScore score;
  final DateTime timestamp;
  final String shotType;
}
