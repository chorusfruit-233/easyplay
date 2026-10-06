import 'package:flutter/material.dart';

/// Shared spacing for pages and controls; board geometry uses its own sizing.
abstract final class AppSpacing {
  static const small = 8.0;
  static const control = 12.0;
  static const inset = 16.0;
  static const section = 24.0;
  static const pageInsets = EdgeInsets.fromLTRB(inset, inset, inset, section);
  static const cardMargin = EdgeInsets.only(bottom: control);
  static const controlInsets = EdgeInsets.symmetric(
    horizontal: inset,
    vertical: control,
  );
}

/// Keeps menus and forms readable on wide screens without constraining boards.
class AppPageList extends StatelessWidget {
  const AppPageList({
    super.key,
    required this.children,
    this.padding = AppSpacing.pageInsets,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ListView(padding: padding, children: children),
    ),
  );
}
