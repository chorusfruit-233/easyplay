enum DraughtsAiLevel {
  beginner('初级', 1, 120, 100),
  intermediate('中级', 5, 4000, 800),
  advanced('高级', 8, 16000, 1800);

  const DraughtsAiLevel(this.label, this.depth, this.nodes, this.milliseconds);
  final String label;
  final int depth;
  final int nodes;
  final int milliseconds;
}
