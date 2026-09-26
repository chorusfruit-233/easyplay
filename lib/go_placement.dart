import 'package:shared_preferences/shared_preferences.dart';

enum GoPlacementMode {
  automatic,
  direct,
  doubleTap,
  swipeConfirm,
  pressRelease,
}

extension GoPlacementModeX on GoPlacementMode {
  String get label => switch (this) {
    GoPlacementMode.automatic => '自动',
    GoPlacementMode.direct => '直接点击',
    GoPlacementMode.doubleTap => '点击两次',
    GoPlacementMode.swipeConfirm => '滑动确认',
    GoPlacementMode.pressRelease => '按下并松开',
  };

  String get description => switch (this) {
    GoPlacementMode.automatic => '网格大时直接落子，网格小时采用二次确认。',
    GoPlacementMode.direct => '点击棋盘直接落子，适合大屏幕或放大后的棋盘。',
    GoPlacementMode.doubleTap => '第一次点击预览，再次点击该位置确认落子。向上滑动取消预览。',
    GoPlacementMode.swipeConfirm => '点击预览，向下滑动确认落子，向上滑动取消。',
    GoPlacementMode.pressRelease => '按下可以预览，保持按住并移动以调整位置，松开后落子。',
  };
}

class GoPlacementPreferences {
  static const key = 'easyplay.go_placement_mode';

  static Future<GoPlacementMode> load() async {
    final value = (await SharedPreferences.getInstance()).getString(key);
    return GoPlacementMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => GoPlacementMode.automatic,
    );
  }

  static Future<void> save(GoPlacementMode mode) async {
    await (await SharedPreferences.getInstance()).setString(key, mode.name);
  }
}
