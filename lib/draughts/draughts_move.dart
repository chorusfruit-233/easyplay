import '../game_session.dart' show Cell;

class DraughtsMove {
  DraughtsMove({required List<Cell> path, List<Cell> captures = const []})
    : path = List.unmodifiable(path),
      captures = List.unmodifiable(captures) {
    if (this.path.length < 2) throw ArgumentError('a move needs a path');
    if (this.captures.length > this.path.length - 1) {
      throw ArgumentError('more captures than move segments');
    }
    if (this.captures.toSet().length != this.captures.length) {
      throw ArgumentError('a piece cannot be captured twice');
    }
  }

  final List<Cell> path;
  final List<Cell> captures;
  Cell get from => path.first;
  Cell get to => path.last;
  bool get isCapture => captures.isNotEmpty;

  bool hasPrefix(List<Cell> prefix) =>
      prefix.length <= path.length &&
      List.generate(prefix.length, (i) => path[i] == prefix[i]).every((v) => v);

  Map<String, Object?> toJson() => {
    'path': path.map((c) => [c.row, c.col]).toList(),
    'captures': captures.map((c) => [c.row, c.col]).toList(),
  };

  factory DraughtsMove.fromJson(Object? json) {
    if (json is! Map || json['path'] is! List || json['captures'] is! List) {
      throw const FormatException('invalid draughts move');
    }
    Cell parse(Object? value) {
      if (value is! List || value.length != 2 || value.any((v) => v is! int)) {
        throw const FormatException('invalid draughts coordinate');
      }
      return Cell(value[0] as int, value[1] as int);
    }

    return DraughtsMove(
      path: (json['path'] as List).map(parse).toList(),
      captures: (json['captures'] as List).map(parse).toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DraughtsMove &&
      _cellsEqual(path, other.path) &&
      _cellsEqual(captures, other.captures);
  @override
  int get hashCode =>
      Object.hash(Object.hashAll(path), Object.hashAll(captures));

  static bool _cellsEqual(List<Cell> a, List<Cell> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);
}
