enum GomokuAiLevel {
  beginner('初级', 1, 200, 100),
  intermediate('中级', 3, 6000, 700),
  advanced('高级', 5, 20000, 1600);

  const GomokuAiLevel(this.label, this.depth, this.nodes, this.milliseconds);
  final String label;
  final int depth;
  final int nodes;
  final int milliseconds;
}
