import 'game_session.dart';

/// One analysed candidate move.
///
/// Every number is from **Black's** perspective, whatever side the engine was
/// asked about, so a review table never has to track a sign flip per row.
class GoAnalysisMove {
  final String vertex;
  final int visits;
  final double winRate;
  final double scoreLead;
  final double prior;
  final int order;
  final List<String> pv;

  const GoAnalysisMove({
    required this.vertex,
    required this.visits,
    required this.winRate,
    required this.scoreLead,
    required this.prior,
    required this.order,
    required this.pv,
  });

  /// Share of the root's visits, which is what a review UI shows next to the
  /// raw visit count.
  double shareOf(int rootVisits) => rootVisits <= 0 ? 0 : visits / rootVisits;
}

/// A parsed `kata-analyze` snapshot, normalised to Black's perspective.
class GoAnalysis {
  /// Visits accumulated at the root, and Black's winrate and score lead for the
  /// position itself.
  final int rootVisits;
  final double rootWinRate;
  final double rootScoreLead;

  /// Predicted ownership per board point, row-major, when requested. Positive
  /// means Black owns the point.
  final List<double>? ownership;

  /// Positive means Black is ahead.
  final List<GoAnalysisMove> moves;

  const GoAnalysis({
    required this.rootVisits,
    required this.rootWinRate,
    required this.rootScoreLead,
    required this.moves,
    this.ownership,
  });

  bool get isEmpty => moves.isEmpty;

  /// Winrate difference between the best move and the position's own value, in
  /// percentage points. This is the "损失" a review UI highlights.
  double get bestMoveWinRate =>
      moves.isEmpty ? rootWinRate : moves.first.winRate;

  /// How far behind Black the top candidate leaves the position.
  double get topMoveLoss => rootWinRate - bestMoveWinRate;
}

/// Parses the single-block output of `kata-analyze ... rootInfo true ownership true`.
///
/// The stream is a sequence of top-level sections, each a keyword followed by
/// key/value pairs: `info` sections describe one candidate move, `rootInfo`
/// describes the position, and `ownership` is a flat list of floats. KataGo
/// documents that field order may change and new fields may appear, so unknown
/// keys are skipped rather than treated as errors.
///
/// [perspective] is the side the command named. KataGo reports from that side's
/// point of view, so White's numbers are flipped to keep the result in Black's
/// frame throughout.
GoAnalysis parseKataGoAnalysis(
  String raw, {
  required int boardSize,
  Side perspective = Side.black,
}) {
  final tokens = raw.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

  final moves = <GoAnalysisMove>[];
  var rootVisits = 0;
  var rootWinRate = 0.0;
  var rootScoreLead = 0.0;
  List<double>? ownership;

  var index = 0;
  while (index < tokens.length) {
    final section = tokens[index];
    index++;
    final fields = <String, String>{};
    final pv = <String>[];
    final ownershipValues = <double>[];

    while (index < tokens.length) {
      final token = tokens[index];
      // A new section starts; stop collecting for this one.
      if (token == 'info' || token == 'rootInfo' || token == 'ownership') {
        break;
      }
      // Values of `ownership` are bare floats, not key/value pairs.
      if (section == 'ownership') {
        final value = double.tryParse(token);
        if (value != null) ownershipValues.add(value);
        index++;
        continue;
      }
      index++;
      final value = index < tokens.length ? tokens[index] : '';
      if (token == 'pv') {
        // `pv` consumes move tokens until the next known key.
        while (index < tokens.length &&
            !_isKnownKey(tokens[index]) &&
            tokens[index] != 'info' &&
            tokens[index] != 'rootInfo' &&
            tokens[index] != 'ownership') {
          pv.add(tokens[index]);
          index++;
        }
        continue;
      }
      fields[token] = value;
      index++;
    }

    switch (section) {
      case 'info':
        final vertex = fields['move'];
        if (vertex != null) {
          moves.add(
            GoAnalysisMove(
              vertex: vertex,
              visits: int.tryParse(fields['visits'] ?? '') ?? 0,
              winRate: double.tryParse(fields['winrate'] ?? '') ?? 0,
              scoreLead: double.tryParse(fields['scoreLead'] ?? '') ?? 0,
              prior: double.tryParse(fields['prior'] ?? '') ?? 0,
              order: int.tryParse(fields['order'] ?? '') ?? moves.length,
              pv: pv,
            ),
          );
        }
      case 'rootInfo':
        rootVisits = int.tryParse(fields['visits'] ?? '') ?? rootVisits;
        rootWinRate = double.tryParse(fields['winrate'] ?? '') ?? rootWinRate;
        rootScoreLead = double.tryParse(fields['scoreLead'] ?? '') ?? 0;
      case 'ownership':
        if (ownershipValues.length == boardSize * boardSize) {
          ownership = ownershipValues;
        }
    }
  }

  // Without an explicit root visit count, the candidates are the only source.
  final effectiveRoot = rootVisits > 0
      ? rootVisits
      : moves.fold<int>(0, (sum, m) => sum + m.visits);
  if (rootVisits == 0 && effectiveRoot > 0) rootVisits = effectiveRoot;

  moves.sort((a, b) => a.order.compareTo(b.order));
  if (perspective == Side.white) {
    return GoAnalysis(
      rootVisits: rootVisits,
      rootWinRate: 1 - rootWinRate,
      rootScoreLead: -rootScoreLead,
      ownership: ownership?.map((v) => -v).toList(),
      moves: [
        for (final move in moves)
          GoAnalysisMove(
            vertex: move.vertex,
            visits: move.visits,
            winRate: 1 - move.winRate,
            scoreLead: -move.scoreLead,
            prior: move.prior,
            order: move.order,
            pv: move.pv,
          ),
      ],
    );
  }
  return GoAnalysis(
    rootVisits: rootVisits,
    rootWinRate: rootWinRate,
    rootScoreLead: rootScoreLead,
    ownership: ownership,
    moves: moves,
  );
}

/// Keys KataGo emits inside an `info` block, used to know where `pv` ends.
const _knownKeys = {
  'move',
  'visits',
  'edgeVisits',
  'winrate',
  'scoreMean',
  'scoreStdev',
  'scoreLead',
  'scoreSelfplay',
  'prior',
  'lcb',
  'utility',
  'utilityLcb',
  'order',
  'weight',
  'edgeWeight',
  'playSelectionValue',
  'noResultValue',
  'isSymmetryOf',
};

bool _isKnownKey(String token) => _knownKeys.contains(token);

/// GTP vertex for a board coordinate.
///
/// GTP columns skip `I` (so index 8 is `J`) and rows count from the bottom, so
/// array row 0 on a 19-line board is row 19.
String gtpVertex(Cell cell, {required int boardSize}) {
  const letters = 'ABCDEFGHJKLMNOPQRST';
  final column = cell.col >= 0 && cell.col < letters.length
      ? letters[cell.col]
      : '?';
  return '$column${boardSize - cell.row}';
}

/// Inverse of [gtpVertex]; returns null when the vertex is `pass` or malformed.
Cell? cellFromGtpVertex(String vertex, {required int boardSize}) {
  const letters = 'ABCDEFGHJKLMNOPQRST';
  final text = vertex.trim().toUpperCase();
  if (text.isEmpty || text == 'PASS') return null;
  final column = letters.indexOf(text[0]);
  final row = int.tryParse(text.substring(1));
  if (column < 0 || row == null) return null;
  final cell = Cell(boardSize - row, column);
  if (cell.row < 0 || cell.row >= boardSize) return null;
  if (cell.col < 0 || cell.col >= boardSize) return null;
  return cell;
}
