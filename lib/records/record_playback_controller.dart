import 'dart:async';

import 'package:flutter/foundation.dart';

import 'record_replay.dart';

/// Owns only a playback cursor and timer, never an engine or storage writer.
class RecordPlaybackController extends ChangeNotifier {
  RecordPlaybackController(RecordReplay record, {this.canAdvance})
    : _record = record,
      _frame = record.frameAt(0);

  RecordReplay _record;
  RecordFrame _frame;
  final bool Function()? canAdvance;
  Timer? _timer;
  int _position = 0;
  double _speed = 1;
  bool _playing = false;
  bool _disposed = false;
  String? _error;

  RecordReplay get record => _record;
  RecordFrame get frame => _frame;
  int get position => _position;
  int get length => _record.length;
  double get speed => _speed;
  bool get playing => _playing;
  String? get error => _error;

  void play() {
    if (_disposed || _playing || length == 0) return;
    if (_position == length && !_moveTo(0)) {
      notifyListeners();
      return;
    }
    _playing = true;
    _error = null;
    _schedule();
    notifyListeners();
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    if (_disposed || !_playing) return;
    _playing = false;
    notifyListeners();
  }

  void seek(int position) {
    if (_disposed) return;
    pause();
    _moveTo(position.clamp(0, length));
    notifyListeners();
  }

  void setSpeed(double speed) {
    if (_disposed || !const [.5, 1.0, 2.0].contains(speed)) return;
    _speed = speed;
    if (_playing) _schedule();
    notifyListeners();
  }

  void selectVariation(int index) {
    if (_disposed || _record is! GoRecordReplay) return;
    pause();
    try {
      final next = GoRecordReplay(
        (_record as GoRecordReplay).sgf,
        variation: index,
      );
      final frame = next.frameAt(0);
      _record = next;
      _frame = frame;
      _position = 0;
      _error = null;
    } catch (error) {
      _error = '无法播放所选变化：$error';
    }
    notifyListeners();
  }

  bool _moveTo(int position) {
    try {
      final frame = _record.frameAt(position);
      _frame = frame;
      _position = position;
      _error = null;
      return true;
    } catch (error) {
      _error = '棋谱播放失败：$error';
      return false;
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: (1000 / _speed).round()), () {
      _timer = null;
      if (_disposed || !_playing) return;
      if (!(canAdvance?.call() ?? true) || !_moveTo(_position + 1)) {
        pause();
        notifyListeners();
        return;
      }
      if (_position == length) {
        _playing = false;
      } else {
        _schedule();
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
