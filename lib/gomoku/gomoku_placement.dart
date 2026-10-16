import '../go_placement.dart';

/// Gomoku previews a move by default, including on a large board.
/// An explicitly selected placement mode keeps its own confirmation gesture.
GoPlacementMode resolveGomokuPlacementMode(GoPlacementMode preference) =>
    preference == GoPlacementMode.automatic
    ? GoPlacementMode.doubleTap
    : preference;

String gomokuPlacementHint(GoPlacementMode preference) => switch (preference) {
  GoPlacementMode.automatic ||
  GoPlacementMode.doubleTap => '点击预览，再点同一位置确认；上滑取消。',
  GoPlacementMode.direct => '点击空交点直接落子。',
  GoPlacementMode.swipeConfirm => '点击预览，下滑确认，上滑取消。',
  GoPlacementMode.pressRelease => '按住预览并移动调整，松手落子。',
};
