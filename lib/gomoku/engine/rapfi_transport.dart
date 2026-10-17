abstract interface class RapfiTransport {
  Stream<String> get lines;
  Future<void> start();

  /// One protocol command, including a complete BOARD/BLOCK body if applicable.
  Future<void> send(String command);
  Future<void> close();
}
