enum XiangqiSide { red, black }

extension XiangqiSideX on XiangqiSide {
  XiangqiSide get opponent =>
      this == XiangqiSide.red ? XiangqiSide.black : XiangqiSide.red;
  String get label => this == XiangqiSide.red ? '红方' : '黑方';
  int get forward => this == XiangqiSide.red ? -1 : 1;
  bool crossedRiver(int row) => this == XiangqiSide.red ? row <= 4 : row >= 5;
  bool inPalace(int row, int col) =>
      col >= 3 &&
      col <= 5 &&
      (this == XiangqiSide.red ? row >= 7 && row <= 9 : row >= 0 && row <= 2);
}
