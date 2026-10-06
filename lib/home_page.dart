import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'game_session.dart';
import 'game_page.dart' show GameTypeX;
import 'lan/lan_quick_join.dart';
import 'ui/app_layout.dart';
import 'ui/game_artwork.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onPlay, required this.onSettings});
  final ValueChanged<GameType> onPlay;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 32 : AppSpacing.inset,
            vertical: AppSpacing.section,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.blur_on,
                          color: colors.onPrimary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.control),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'EasyPlay',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.5,
                            ),
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: onSettings,
                        tooltip: '设置',
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    ],
                  ),
                  const LanQuickJoinCard(),
                  const SizedBox(height: AppSpacing.section),
                  Text(
                    '选一款，开始吧。',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.8,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.small),
                  Text(
                    '独自练习，或和朋友一起玩。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),
                  Row(
                    children: [
                      Text(
                        '全部游戏',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${GameType.values.length} 款',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.control),
                  LayoutBuilder(
                    builder: (context, grid) {
                      // Reflow instead of clipping labels when the user enlarges text.
                      final textScale =
                          MediaQuery.textScalerOf(context).scale(16) / 16;
                      final minWidth = textScale > 1.3 ? 220.0 : 136.0;
                      final columns = grid.maxWidth >= 700
                          ? 3
                          : grid.maxWidth >= minWidth * 2 + AppSpacing.control
                          ? 2
                          : 1;
                      final width =
                          (grid.maxWidth - (columns - 1) * AppSpacing.control) /
                          columns;
                      return Wrap(
                        spacing: AppSpacing.control,
                        runSpacing: AppSpacing.control,
                        children: [
                          for (final game in GameType.values)
                            SizedBox(
                              width: width,
                              child: GameCard(
                                type: game,
                                onTap: () => onPlay(game),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.section),
                  Wrap(
                    spacing: AppSpacing.section,
                    runSpacing: AppSpacing.small,
                    children: const [
                      _PlayMode(icon: Icons.person_outline, label: '单人练习'),
                      _PlayMode(icon: Icons.people_outline, label: '同机对战'),
                      _PlayMode(icon: Icons.wifi, label: '好友联机'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlayMode extends StatelessWidget {
  const _PlayMode({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class GameCard extends StatefulWidget {
  const GameCard({super.key, required this.type, required this.onTap});
  final GameType type;
  final VoidCallback? onTap;
  @override
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard> {
  bool _pressed = false, _focused = false, _hovered = false, _hasFocus = false;
  String get _description => switch (widget.type) {
    GameType.go => '布局与收官，一步一步来',
    GameType.chess => '战术攻防，将军与将杀',
    GameType.checkers => '多种规则，连跳与升王',
    GameType.gomoku => '标准五子棋与连珠规则',
    GameType.xiangqi => '楚河汉界，将帅交锋',
    GameType.doudizhu => '经典三人，叫分与出牌',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = widget.onTap != null;
    // Gesture feedback preserves the Android stretch effect of the original
    // cards. Focus and Actions also allow keyboard activation on the Web.
    return Semantics(
      button: true,
      focusable: enabled,
      focused: _hasFocus,
      enabled: enabled,
      label: '${widget.type.label}，$_description',
      excludeSemantics: true,
      onTap: widget.onTap,
      child: FocusableActionDetector(
        enabled: enabled,
        onFocusChange: (value) => setState(() => _hasFocus = value),
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            constraints: const BoxConstraints(minHeight: 164),
            padding: const EdgeInsets.all(AppSpacing.inset),
            decoration: BoxDecoration(
              color: _pressed || _hovered
                  ? colors.surfaceContainerHigh
                  : colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _focused
                    ? colors.primary
                    : colors.outlineVariant.withValues(alpha: .4),
                width: _focused ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GameArtwork(type: widget.type, size: 44),
                    const Spacer(),
                    Icon(
                      Icons.arrow_outward,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.control),
                Text(
                  widget.type.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
