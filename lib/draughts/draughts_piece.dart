import '../game_session.dart' show Side;

enum DraughtsRank { man, king }

class DraughtsPiece {
  final Side side;
  final DraughtsRank rank;

  const DraughtsPiece(this.side, [this.rank = DraughtsRank.man]);

  DraughtsPiece promote() => DraughtsPiece(side, DraughtsRank.king);

  Map<String, Object?> toJson() => {'side': side.name, 'rank': rank.name};

  factory DraughtsPiece.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('invalid draughts piece');
    final side = Side.values.where((v) => v.name == json['side']).firstOrNull;
    final rank = DraughtsRank.values
        .where((v) => v.name == json['rank'])
        .firstOrNull;
    if (side == null || rank == null) {
      throw const FormatException('invalid draughts piece');
    }
    return DraughtsPiece(side, rank);
  }

  @override
  bool operator ==(Object other) =>
      other is DraughtsPiece && side == other.side && rank == other.rank;
  @override
  int get hashCode => Object.hash(side, rank);
}
