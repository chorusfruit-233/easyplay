import '../game_session.dart' show Side;
import 'draughts_move.dart';
import 'draughts_session.dart';
import 'draughts_variant.dart';
import 'draughts_ai_level.dart';

enum DraughtsGameKind { local, online, ai }

class DraughtsRecord {
  DraughtsRecord({
    required this.variant,
    required List<DraughtsMove> moves,
    required this.kind,
    required this.localSide,
    required this.createdAt,
    this.result,
    this.id,
    this.sessionState,
    this.aiLevel,
  }) : moves = List.unmodifiable(moves);

  final String? id;
  final DraughtsVariant variant;
  final List<DraughtsMove> moves;
  final DraughtsGameKind kind;
  final Side? localSide;
  final DateTime createdAt;
  final String? result;
  final Map<String, Object?>? sessionState;
  final DraughtsAiLevel? aiLevel;

  factory DraughtsRecord.fromSession(
    DraughtsSession session, {
    DraughtsGameKind kind = DraughtsGameKind.local,
    Side? localSide,
    String? id,
    DateTime? createdAt,
    DraughtsAiLevel? aiLevel,
  }) => DraughtsRecord(
    variant: session.variant,
    moves: session.moves,
    kind: kind,
    localSide: localSide,
    id: id,
    createdAt: createdAt ?? DateTime.now().toUtc(),
    aiLevel: aiLevel,
    sessionState: session.toJson(),
    result: session.result?.winner == null
        ? (session.gameOver ? '1/2-1/2' : null)
        : session.result!.winner == Side.black
        ? '1-0'
        : '0-1',
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'rulesVersion': draughtsRulesVersion,
    'id': id,
    'variant': variant.name,
    'kind': kind.name,
    'localSide': localSide?.name,
    if (aiLevel != null) 'aiLevel': aiLevel!.name,
    'createdAt': createdAt.toIso8601String(),
    'result': result,
    if (sessionState != null) 'session': sessionState,
    'moves': moves.map((move) => move.toJson()).toList(),
  };

  factory DraughtsRecord.fromJson(Object? value) {
    if (value is! Map ||
        value['version'] != 1 ||
        value['rulesVersion'] != draughtsRulesVersion) {
      throw const FormatException('unsupported draughts record');
    }
    final variant = DraughtsVariant.values
        .where((v) => v.name == value['variant'])
        .firstOrNull;
    final kind = DraughtsGameKind.values
        .where((v) => v.name == value['kind'])
        .firstOrNull;
    final sideRaw = value['localSide'];
    final side = sideRaw == null
        ? null
        : Side.values.where((v) => v.name == sideRaw).firstOrNull;
    final date = DateTime.tryParse(value['createdAt'] as String? ?? '');
    if (variant == null ||
        kind == null ||
        (sideRaw != null && side == null) ||
        date == null ||
        value['moves'] is! List) {
      throw const FormatException('invalid draughts record');
    }
    return DraughtsRecord(
      id: value['id'] as String?,
      variant: variant,
      kind: kind,
      localSide: side,
      aiLevel: DraughtsAiLevel.values
          .where((level) => level.name == value['aiLevel'])
          .firstOrNull,
      createdAt: date,
      result: value['result'] as String?,
      sessionState: value['session'] is Map
          ? (value['session'] as Map).cast<String, Object?>()
          : null,
      moves: (value['moves'] as List).map(DraughtsMove.fromJson).toList(),
    );
  }
}
