import '../game_session.dart' show Cell, Side, SideX;
import 'draughts_move.dart';
import 'draughts_piece.dart';
import 'draughts_position.dart';
import 'draughts_variant.dart';

enum BoardGeometry { diagonalDarkSquares, orthogonalAllSquares }

enum ManMoveRule { forwardDiagonal, forwardOrthogonalWithSideways }

enum ManCaptureRule { forwardOnly, forwardAndBackward, orthogonal }

enum KingMoveRule { short, flyingDiagonal, flyingOrthogonal }

enum KingCaptureRule { short, flyingDiagonal, flyingOrthogonal }

enum PromotionPolicy { afterTurn, stopOnPromotion, promoteAndContinue }

enum CaptureRemovalPolicy { immediate, afterSequence }

class DrawPolicy {
  const DrawPolicy({
    this.repetitions = 3,
    this.quietPlies = 80,
    this.kingRaceMoves,
    this.kingRaceAllowsMen = false,
  });
  final int repetitions;
  final int quietPlies;
  final int? kingRaceMoves;
  final bool kingRaceAllowsMen;
}

abstract interface class CapturePriority {
  List<DraughtsMove> select(
    DraughtsPosition position,
    List<DraughtsMove> moves,
  );
}

class AnyCapturePriority implements CapturePriority {
  const AnyCapturePriority();
  @override
  List<DraughtsMove> select(
    DraughtsPosition position,
    List<DraughtsMove> moves,
  ) => moves;
}

class MaximumPiecesPriority implements CapturePriority {
  const MaximumPiecesPriority();
  @override
  List<DraughtsMove> select(
    DraughtsPosition position,
    List<DraughtsMove> moves,
  ) {
    if (moves.isEmpty) return moves;
    final maxCount = moves
        .map((m) => m.captures.length)
        .reduce((a, b) => a > b ? a : b);
    return moves.where((m) => m.captures.length == maxCount).toList();
  }
}

class MaximumPiecesThenKingsPriority implements CapturePriority {
  const MaximumPiecesThenKingsPriority();
  @override
  List<DraughtsMove> select(
    DraughtsPosition position,
    List<DraughtsMove> moves,
  ) {
    var remaining = const MaximumPiecesPriority().select(position, moves);
    if (remaining.isEmpty) return remaining;
    int kings(DraughtsMove move) => move.captures
        .where((cell) => position[cell]?.rank == DraughtsRank.king)
        .length;
    final maxKings = remaining.map(kings).reduce((a, b) => a > b ? a : b);
    remaining = remaining.where((m) => kings(m) == maxKings).toList();
    return remaining;
  }
}

class ItalianCapturePriority implements CapturePriority {
  const ItalianCapturePriority();
  @override
  List<DraughtsMove> select(
    DraughtsPosition position,
    List<DraughtsMove> moves,
  ) {
    var remaining = const MaximumPiecesPriority().select(position, moves);
    if (remaining.length < 2) return remaining;
    final kingStarts = remaining
        .where((m) => position[m.from]?.rank == DraughtsRank.king)
        .toList();
    if (kingStarts.isNotEmpty) remaining = kingStarts;
    if (remaining.length < 2) return remaining;
    final maxKings = remaining
        .map(
          (m) => m.captures
              .where((cell) => position[cell]?.rank == DraughtsRank.king)
              .length,
        )
        .reduce((a, b) => a > b ? a : b);
    remaining = remaining
        .where(
          (m) =>
              m.captures
                  .where((cell) => position[cell]?.rank == DraughtsRank.king)
                  .length ==
              maxKings,
        )
        .toList();
    if (remaining.length < 2) return remaining;
    final firstKingCapture = remaining.where((m) {
      final first = m.captures.firstOrNull;
      return first != null && position[first]?.rank == DraughtsRank.king;
    }).toList();
    if (firstKingCapture.isNotEmpty) remaining = firstKingCapture;
    return remaining;
  }
}

class DraughtsRules {
  const DraughtsRules({
    required this.variant,
    required this.boardSize,
    required this.startingRows,
    this.startingOffset = 0,
    required this.geometry,
    required this.manMove,
    required this.manCapture,
    required this.kingMove,
    required this.kingCapture,
    required this.capturePriority,
    required this.promotion,
    required this.captureRemoval,
    required this.drawPolicy,
    this.firstMove = Side.black,
    this.menMayCaptureKings = true,
    this.forbidCaptureReverse = false,
  });

  final DraughtsVariant variant;
  final int boardSize;
  final int startingRows;
  final int startingOffset;
  final BoardGeometry geometry;
  final ManMoveRule manMove;
  final ManCaptureRule manCapture;
  final KingMoveRule kingMove;
  final KingCaptureRule kingCapture;
  final CapturePriority capturePriority;
  final PromotionPolicy promotion;
  final CaptureRemovalPolicy captureRemoval;
  final DrawPolicy drawPolicy;
  final Side firstMove;
  final bool menMayCaptureKings;
  final bool forbidCaptureReverse;

  int forward(Side side) => side == Side.black ? 1 : -1;
  int promotionRow(Side side) => side == Side.black ? boardSize - 1 : 0;
  bool isPromotionCell(Side side, Cell cell) => cell.row == promotionRow(side);
  bool isPlayable(Cell cell) =>
      cell.row >= 0 &&
      cell.col >= 0 &&
      cell.row < boardSize &&
      cell.col < boardSize &&
      (geometry == BoardGeometry.orthogonalAllSquares ||
          (cell.row + cell.col).isOdd);

  String get shortDescription =>
      '$boardSize×$boardSize · ${switch (kingMove) {
        KingMoveRule.short => '短王',
        KingMoveRule.flyingDiagonal => '飞王',
        KingMoveRule.flyingOrthogonal => '横纵飞王',
      }}';

  static DraughtsRules forVariant(DraughtsVariant variant) {
    final defaults = _base(variant);
    return defaults;
  }

  static DraughtsRules _base(DraughtsVariant v) {
    final any = const AnyCapturePriority();
    final max = const MaximumPiecesPriority();
    final maxKings = const MaximumPiecesThenKingsPriority();
    return switch (v) {
      DraughtsVariant.english => DraughtsRules(
        variant: v,
        boardSize: 8,
        startingRows: 3,
        geometry: BoardGeometry.diagonalDarkSquares,
        manMove: ManMoveRule.forwardDiagonal,
        manCapture: ManCaptureRule.forwardOnly,
        kingMove: KingMoveRule.short,
        kingCapture: KingCaptureRule.short,
        capturePriority: any,
        promotion: PromotionPolicy.stopOnPromotion,
        captureRemoval: CaptureRemovalPolicy.immediate,
        drawPolicy: const DrawPolicy(quietPlies: 80),
      ),
      DraughtsVariant.international => DraughtsRules(
        variant: v,
        boardSize: 10,
        startingRows: 4,
        geometry: BoardGeometry.diagonalDarkSquares,
        manMove: ManMoveRule.forwardDiagonal,
        manCapture: ManCaptureRule.forwardAndBackward,
        kingMove: KingMoveRule.flyingDiagonal,
        kingCapture: KingCaptureRule.flyingDiagonal,
        capturePriority: max,
        promotion: PromotionPolicy.afterTurn,
        captureRemoval: CaptureRemovalPolicy.afterSequence,
        drawPolicy: const DrawPolicy(
          quietPlies: 50,
          kingRaceMoves: 16,
          kingRaceAllowsMen: true,
        ),
        firstMove: Side.white,
      ),
      DraughtsVariant.brazilian => DraughtsRules(
        variant: v,
        boardSize: 8,
        startingRows: 3,
        geometry: BoardGeometry.diagonalDarkSquares,
        manMove: ManMoveRule.forwardDiagonal,
        manCapture: ManCaptureRule.forwardAndBackward,
        kingMove: KingMoveRule.flyingDiagonal,
        kingCapture: KingCaptureRule.flyingDiagonal,
        capturePriority: max,
        promotion: PromotionPolicy.afterTurn,
        captureRemoval: CaptureRemovalPolicy.afterSequence,
        drawPolicy: const DrawPolicy(
          quietPlies: 50,
          kingRaceMoves: 16,
          kingRaceAllowsMen: true,
        ),
        firstMove: Side.white,
      ),
      DraughtsVariant.russian => DraughtsRules(
        variant: v,
        boardSize: 8,
        startingRows: 3,
        geometry: BoardGeometry.diagonalDarkSquares,
        manMove: ManMoveRule.forwardDiagonal,
        manCapture: ManCaptureRule.forwardAndBackward,
        kingMove: KingMoveRule.flyingDiagonal,
        kingCapture: KingCaptureRule.flyingDiagonal,
        capturePriority: any,
        promotion: PromotionPolicy.promoteAndContinue,
        captureRemoval: CaptureRemovalPolicy.immediate,
        drawPolicy: const DrawPolicy(quietPlies: 80, kingRaceMoves: 15),
        firstMove: Side.white,
      ),
      DraughtsVariant.pool => DraughtsRules(
        variant: v,
        boardSize: 8,
        startingRows: 3,
        geometry: BoardGeometry.diagonalDarkSquares,
        manMove: ManMoveRule.forwardDiagonal,
        manCapture: ManCaptureRule.forwardAndBackward,
        kingMove: KingMoveRule.flyingDiagonal,
        kingCapture: KingCaptureRule.flyingDiagonal,
        capturePriority: any,
        promotion: PromotionPolicy.afterTurn,
        captureRemoval: CaptureRemovalPolicy.immediate,
        drawPolicy: const DrawPolicy(quietPlies: 80, kingRaceMoves: 13),
        firstMove: Side.white,
      ),
      DraughtsVariant.italian => DraughtsRules(
        variant: v,
        boardSize: 8,
        startingRows: 3,
        geometry: BoardGeometry.diagonalDarkSquares,
        manMove: ManMoveRule.forwardDiagonal,
        manCapture: ManCaptureRule.forwardOnly,
        kingMove: KingMoveRule.flyingDiagonal,
        kingCapture: KingCaptureRule.flyingDiagonal,
        capturePriority: const ItalianCapturePriority(),
        promotion: PromotionPolicy.stopOnPromotion,
        captureRemoval: CaptureRemovalPolicy.immediate,
        drawPolicy: const DrawPolicy(quietPlies: 80),
        menMayCaptureKings: false,
        firstMove: Side.white,
      ),
      DraughtsVariant.spanish => DraughtsRules(
        variant: v,
        boardSize: 8,
        startingRows: 3,
        geometry: BoardGeometry.diagonalDarkSquares,
        manMove: ManMoveRule.forwardDiagonal,
        manCapture: ManCaptureRule.forwardOnly,
        kingMove: KingMoveRule.flyingDiagonal,
        kingCapture: KingCaptureRule.flyingDiagonal,
        capturePriority: maxKings,
        promotion: PromotionPolicy.afterTurn,
        captureRemoval: CaptureRemovalPolicy.afterSequence,
        drawPolicy: const DrawPolicy(quietPlies: 80),
        firstMove: Side.white,
      ),
      DraughtsVariant.turkish => DraughtsRules(
        variant: v,
        boardSize: 8,
        startingRows: 2,
        startingOffset: 1,
        geometry: BoardGeometry.orthogonalAllSquares,
        manMove: ManMoveRule.forwardOrthogonalWithSideways,
        manCapture: ManCaptureRule.orthogonal,
        kingMove: KingMoveRule.flyingOrthogonal,
        kingCapture: KingCaptureRule.flyingOrthogonal,
        capturePriority: max,
        promotion: PromotionPolicy.afterTurn,
        captureRemoval: CaptureRemovalPolicy.immediate,
        drawPolicy: const DrawPolicy(quietPlies: 80),
        firstMove: Side.white,
        forbidCaptureReverse: true,
      ),
    };
  }
}

class DraughtsVariantInfo {
  const DraughtsVariantInfo(this.rules, this.name, this.summary);
  final DraughtsRules rules;
  final String name;
  final String summary;
  static DraughtsVariantInfo of(DraughtsVariant variant) {
    final rules = DraughtsRules.forVariant(variant);
    return DraughtsVariantInfo(
      rules,
      variant.englishName,
      '${rules.shortDescription} · 强制吃子',
    );
  }

  String get details {
    final manMovement = rules.geometry == BoardGeometry.orthogonalAllSquares
        ? '普通子向前或横向走一格'
        : '普通子向前斜走一格';
    final manCapture = switch (rules.manCapture) {
      ManCaptureRule.forwardOnly => '普通子只能向前吃子',
      ManCaptureRule.forwardAndBackward => '普通子可前后吃子',
      ManCaptureRule.orthogonal => '普通子横向或向前吃子',
    };
    final kingMovement = switch (rules.kingMove) {
      KingMoveRule.short => '王斜向走一格',
      KingMoveRule.flyingDiagonal => '王可沿对角线飞行',
      KingMoveRule.flyingOrthogonal => '王可横纵飞行',
    };
    final kingCapture = switch (rules.kingCapture) {
      KingCaptureRule.short => '王隔一格吃子',
      KingCaptureRule.flyingDiagonal => '王可越过一颗敌子并选后方落点',
      KingCaptureRule.flyingOrthogonal => '王可横纵越过一颗敌子并选落点',
    };
    final priority = switch (rules.capturePriority) {
      AnyCapturePriority() => '强制吃子，可选择任一完整吃子路径',
      MaximumPiecesPriority() => '强制吃子，并优先吃最多棋子的路径',
      MaximumPiecesThenKingsPriority() => '最多吃子；数量相同时优先吃更多王',
      ItalianCapturePriority() => '最多吃子；平手时按意大利规则依次比较出击王、所吃王数及先吃王',
      _ => '按本变体的强制吃子规则选路',
    };
    final promotion = switch (rules.promotion) {
      PromotionPolicy.afterTurn => '到达底线后升王；连续吃子在整手结束后升王',
      PromotionPolicy.stopOnPromotion => '到达底线立即升王并结束本手',
      PromotionPolicy.promoteAndContinue => '连续吃子中到达底线立即升王并按王继续',
    };
    final quietRounds = rules.drawPolicy.quietPlies ~/ 2;
    final draw = [
      '同一局面三次重复和棋',
      '$quietRounds 回合没有普通子移动或吃子时按无进展和棋',
      if (rules.drawPolicy.kingRaceMoves != null)
        '三王对单王残局计数 ${rules.drawPolicy.kingRaceMoves} 次强方走子',
    ].join('；');
    return [
      '${rules.boardSize}×${rules.boardSize} 棋盘',
      manMovement,
      manCapture,
      kingMovement,
      kingCapture,
      priority,
      promotion,
      rules.captureRemoval == CaptureRemovalPolicy.immediate
          ? '吃子后立即移除被吃棋子'
          : '连续吃子结束后统一移除被吃棋子',
      draw,
      '${rules.firstMove.label}先手',
    ].join('\n');
  }
}
