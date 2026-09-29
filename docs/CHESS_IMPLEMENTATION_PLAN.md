# EasyPlay Chess 一次性实现计划

**状态：待实现**

## 1. 目标

一次性把当前 Chess 原型升级成完整可用的国际象棋对战功能。

最终支持：

- 完整标准国际象棋规则
- 本地双人
- Stockfish 19 AI 对战
- Android Stockfish 原生引擎
- Web Stockfish WASM
- LAN 局域网联机
- 悔棋协商
- 和棋协商
- 认输
- 断线重连
- 对局进行期间的完整运行时状态
- Stockfish 多档难度

明确不做：

- 棋谱库
- 历史对局保存
- 自动恢复上次对局
- PGN 管理
- PGN 导入/导出 UI
- 开局库 UI
- 云端匹配
- Internet 中继服务器
- 排位
- Chess AI 分析页面
- 对局结束后的长期保存

产品定位：

```text
Chess
├── 本地双人
├── Stockfish AI
└── LAN 联机
```

关闭对局后，其状态可以直接销毁。

## 2. 核心原则

### 2.1 Chess 从 `GameSession` 中独立

不要继续把完整 Chess 规则堆进通用 `game_session.dart`。

新增独立模块：

```text
lib/chess/
```

Chess 的所有规则只有一个真源：

```text
ChessSession
```

UI、Stockfish 和 LAN 都不得自己实现规则。

最终关系：

```text
Chess UI
   ↓
ChessSession
   ↑
   ├── Stockfish
   └── LAN Authority
```

## 3. 目录结构

```text
lib/chess/
├── chess.dart
├── chess_piece.dart
├── chess_move.dart
├── chess_position.dart
├── chess_session.dart
├── chess_move_generator.dart
├── chess_result.dart
├── chess_fen.dart
├── chess_uci.dart
│
├── engine/
│   ├── chess_engine.dart
│   ├── stockfish_runtime.dart
│   ├── stockfish_io.dart
│   ├── stockfish_web.dart
│   └── stockfish_stub.dart
│
└── widgets/
    ├── chess_home_page.dart
    ├── chess_game_page.dart
    ├── chess_ai_settings.dart
    └── chess_board.dart
```

LAN 继续放在 `lib/lan/`，不得复制一套 Chess 专用 WebSocket 实现。

## 4. Chess 棋子模型

不要继续依赖通用 `PieceKind` 作为完整 Chess 规则数据层。

```dart
enum ChessPieceType {
  pawn,
  knight,
  bishop,
  rook,
  queen,
  king,
}

class ChessPiece {
  final Side side;
  final ChessPieceType type;

  const ChessPiece(this.side, this.type);
}
```

## 5. ChessMove

```dart
class ChessMove {
  final Cell from;
  final Cell to;
  final ChessPieceType? promotion;

  const ChessMove({
    required this.from,
    required this.to,
    this.promotion,
  });
}
```

普通着使用 `e2e4`，升变使用 `e7e8q`。王车易位仍表示王的移动（`e1g1` / `e1c1`），吃过路兵也仍表示兵的 `from → to`。特殊行为全部由 `ChessSession.applyMove()` 根据当前局面决定。

## 6. ChessPosition

完整局面不能只有棋盘，必须包含：

```dart
class ChessPosition {
  final List<List<ChessPiece?>> board;
  final Side sideToMove;
  final ChessCastlingRights castlingRights;
  final Cell? enPassantTarget;
  final int halfmoveClock;
  final int fullmoveNumber;
}
```

`castlingRights` 至少区分白方王翼、白方后翼、黑方王翼、黑方后翼。上述数据必须能完整生成 FEN。

## 7. FEN

虽然不做棋谱库，但 FEN 必须实现，用于 ChessSession 与 Stockfish 交互、测试以及 LAN 状态验证。

```dart
String exportFen(ChessPosition position);
ChessPosition parseFen(String fen);
```

FEN 第一版只作为内部工具，不需要做导入/导出 UI。

## 8. UCI

Stockfish 通信使用标准 UCI。至少支持：

```text
position fen ...
go movetime ...
bestmove ...
setoption ...
isready
ucinewgame
quit
```

同时实现 ChessMove 与 UCI move 互转，例如 `e2e4`、`e7e8q`。

## 9. 合法走法生成

唯一入口：

```dart
List<ChessMove> legalMoves();
List<ChessMove> legalMovesFrom(Cell from);
```

流程：

```text
生成 pseudo-legal move
↓
模拟走子
↓
检查己方王是否被将军
↓
过滤非法 move
```

UI、LAN 和 Stockfish 返回值都必须经过这一规则核心。

## 10. Pawn

完整支持：前进一步、初始前进两步、斜向吃子、吃过路兵、升变。

## 11. En Passant

必须使用 `position.enPassantTarget` 维护。只有紧接在对方兵从初始位置走两格后的下一手有效。执行吃过路兵时移动己方兵并删除目标格后方的对方兵；若下一手未执行则 `enPassantTarget = null`。Undo 必须恢复原值。

## 12. Promotion

兵到最后一行时必须允许升为 Queen、Rook、Bishop、Knight，不能只自动升后。UI 到达升变格后弹出四种选择；AI 返回的 `e7e8q` 等直接解析 promotion。

## 13. Castling

完整支持 O-O 和 O-O-O。判断条件：

- 王没有移动过
- 对应车没有移动过
- 王与车之间没有棋子
- 王当前不在被将军状态
- 王经过的格子不能受攻击
- 王目标格不能受攻击

王一旦移动永久取消该方两侧易位权；对应车移动或原始车被吃时永久取消对应侧易位权，不得因为棋子回到原位而恢复。

## 14. Check / Checkmate

提供：

```dart
bool isInCheck(Side side);
```

当 `legalMoves().isEmpty` 时：当前方被将军则为 Checkmate，否则为 Stalemate。结果统一由 ChessSession 产生。

## 15. ChessResult

```dart
enum ChessEndReason {
  checkmate,
  stalemate,
  resignation,
  drawAgreement,
  threefoldRepetition,
  fivefoldRepetition,
  fiftyMoveRule,
  seventyFiveMoveRule,
  deadPosition,
}

class ChessResult {
  final Side? winner;
  final ChessEndReason reason;
}
```

## 16. 重复局面

即使不保存棋谱，也必须在当前对局内记录 position history，以判断三次重复和五次重复。

position key 必须包含：棋盘、轮到谁、王车易位权、有实际意义的 en passant 状态；不能包含 halfmoveClock 和 fullmoveNumber。

## 17. 50 / 75 回合规则

维护 `halfmoveClock`。兵移动或吃子时归零，否则 +1。支持 50-move claim 和 75-move automatic draw。UI 第一版可以在达到 50 回合时提示“可以申请和棋”，75 回合自动结束。

## 18. Dead Position

实现标准无法将死局面判断，至少正确处理 K vs K、K+B vs K、K+N vs K，且不能错误地把 K+B+N vs K 判断为和棋。规则逻辑必须在 ChessSession 内，不得询问 Stockfish。

## 19. Resign / Draw Agreement

本地模式可直接认输；本地双人和棋需要双方确认。LAN 使用 `drawRequest` / `drawAccept` / `drawReject`，认输使用 `resign`。AI 对战允许用户认输，AI 不需要主动请求和棋。

## 20. Undo

- 本地双人：撤回上一手。
- AI：一次悔棋优先撤回 AI 上一手 + 玩家上一手，使局面回到玩家回合；若 AI 尚未走则只撤玩家上一手。
- LAN：必须双方协商，使用 `undoRequest` / `undoAccept` / `undoReject`。

## 21. Snapshot

运行时 Undo 需要完整快照：

```dart
class ChessSnapshot {
  final ChessPosition position;
  final ChessResult? result;
  final int moveCount;
  final Map<String, int> repetitionCounts;
}
```

Undo 后必须完整恢复棋盘、回合、易位权、en passant、halfmove clock、fullmove number、重复局面记录和结果。

## 22. 不保存棋谱

明确禁止增加：

```text
ChessStorage
ChessSavedRecord
ChessLibraryPage
```

关闭对局后 ChessSession dispose，当前状态直接销毁，不写 SharedPreferences、文件系统或数据库。

## 23. Chess 首页

```text
Chess

[ AI 对战 ]
[ 本地双人 ]
[ 局域网联机 ]
```

没有棋谱库、继续上次、最近对局、导入棋谱。

## 24. AI 设置

第一版：

```text
执棋：白 / 黑 / 随机

难度：
初学
简单
普通
困难
大师
最高
```

不直接暴露 Threads、Hash、NNUE、nodes 等高级参数。

## 25. Stockfish 19

固定使用 Stockfish 19，构建必须 pin 到明确 tag 和 commit，不跟踪 master。Android 与 Web 尽可能使用同一 Stockfish revision。

## 26. ChessEngine 接口

```dart
abstract interface class ChessEngine {
  Future<void> start();
  Future<void> newGame();
  Future<ChessMove> bestMove(
    ChessPosition position,
    ChessEngineLimits limits,
  );
  Future<void> stop();
  Future<void> dispose();
}
```

Flutter UI 不知道底层是 native Stockfish 还是 WASM Stockfish。

## 27. Android Stockfish

```text
Flutter
↓
ChessEngine
↓
MethodChannel / process wrapper
↓
Stockfish 19 ARM64
↓
UCI stdin/stdout
```

第一版只要求 arm64-v8a。

## 28. Web Stockfish

```text
Flutter Web
↓
JS bridge
↓
Web Worker
↓
Stockfish 19 WASM
```

必须放 Worker，不能把搜索直接跑在主 UI thread。若采用单线程 WASM，则无需 SharedArrayBuffer 或 coi-serviceworker。

## 29. AI 工作流

```text
ChessSession.applyMove()
↓
检查 gameOver
↓
轮到 AI
↓
锁定棋盘
↓
导出 FEN
↓
Stockfish position fen ...
↓
go ...
↓
bestmove
↓
解析 ChessMove
↓
再次交给 ChessSession 验证
↓
applyMove()
↓
解锁
```

Stockfish 返回的 move 永远不能绕过 ChessSession。

## 30. AI 并发安全

使用 generation / sessionId。每次新对局、undo、退出、重新启动引擎时递增 generation；异步 bestmove 返回时若 generation 不一致则丢弃，防止旧结果修改新棋局。

## 31. AI 取消

必须支持 `stop`。用户悔棋、退出、认输、游戏结束、重新开局、App dispose 时立即调用，不得让旧 search 留在后台。

## 32. AI 难度

优先使用 Stockfish 的 UCI_LimitStrength / UCI_Elo，或结合 movetime / nodes。UI 只显示档位，映射集中在 `ChessAiLevel`，不得散落在 Widget。

## 33. AI 性能原则

移动端不要默认无限搜索、巨大 Hash 或高线程数。第一版重视稳定、响应快、温度和电量，而不是最大棋力。

## 34. LAN 共用层

继续使用已有 WebSocket、PIN、heartbeat、seq、stateSync、reconnect。

```text
LanTransport
       ↓
GameAuthority
   ┌───┼──────────┐
   │   │          │
  Go Chess    Draughts
```

不要复制 ChessLanSocket。

## 35. LAN Chess 配置

握手：

```json
{
  "game": "chess",
  "rulesVersion": 1
}
```

标准 Chess 不需要 variant，但仍需 rulesVersion。

## 36. LAN Move

直接使用 UCI move：

```json
{
  "type": "move",
  "seq": 27,
  "move": "e2e4"
}
```

升变：

```json
{
  "type": "move",
  "seq": 52,
  "move": "e7e8q"
}
```

Host parse UCI → ChessSession.isLegalMove() → applyMove() → 成功才 commit seq，否则 rejected。

## 37. LAN Authority

房主仍是唯一权威。客户端只可显示选中格和目标格，不可提前正式修改 ChessSession；收到 committed event 后再由 Replica.applyMove()。

## 38. LAN 事件

至少支持：

```text
move
resign
undoRequest
undoAccept
undoReject
drawRequest
drawAccept
drawReject
```

Checkmate、stalemate、automatic draw 由双方应用同一 committed move 后自行得出。

## 39. LAN stateSync

只在房间生命周期内保存完整 event log。断线后重新创建 ChessSession 并按权威日志从初始局面全量重放。房间关闭后直接销毁，不持久化。

## 40. LAN 重连

重连后必须恢复 board、sideToMove、castlingRights、enPassantTarget、halfmoveClock、fullmoveNumber、repetition state、result。

## 41. LAN 与 AI 分离

一个 Chess 对局只能属于 local / ai / online。LAN 对局中不创建 Stockfish，也不提供 AI 提示。

## 42. ChessBoard

新增独立 ChessBoard，支持：选中棋子、合法目标提示、最后一步高亮、将军提示、升变 UI、棋盘翻转。

## 43. 棋盘方向

- 本地双人：默认白方在下。
- AI：用户执白则白在下，用户执黑则黑在下。
- LAN：我的一方在下。
- 提供手动翻转按钮。

## 44. 状态栏

至少显示：白方回合、黑方回合、将军、将死、和棋、对方认输、你获胜、AI 思考中、重连中。

## 45. Promotion UI

当一个兵有四个合法升变 move（如 e7e8q / r / b / n）时，点击目标格后弹出 Queen / Rook / Bishop / Knight 选择，选择后再生成最终 ChessMove。

## 46. 测试目录

```text
test/chess/
├── chess_initial_position_test.dart
├── chess_piece_moves_test.dart
├── chess_check_test.dart
├── chess_castling_test.dart
├── chess_en_passant_test.dart
├── chess_promotion_test.dart
├── chess_checkmate_test.dart
├── chess_draw_test.dart
├── chess_repetition_test.dart
├── chess_fen_test.dart
├── chess_uci_test.dart
├── chess_undo_test.dart
├── chess_engine_test.dart
├── chess_widget_test.dart
└── chess_lan_test.dart
```

## 47. Perft

Chess move generator 必须加入 perft 测试：

```dart
int perft(ChessPosition position, int depth)
```

至少验证标准初始局面：

```text
depth 1 = 20
depth 2 = 400
depth 3 = 8902
depth 4 = 197281
```

并加入包含 castling、en passant、promotion、check 的经典 perft 局面。若 perft 不对，Chess 规则不能算完成。

## 48. 特殊规则测试

Castling：合法短/长易位、王或车移动后禁止、回原位仍禁止、被将军时禁止、经过攻击格禁止、目标格受攻击禁止、路径被占禁止。

En Passant：立即可吃、下一手失效、吃过路兵若暴露己方王则非法。

Promotion：升后、升车、升象、升马、吃子升变、AI UCI 升变解析。

## 49. Check 测试

至少覆盖普通将军、双将、挡将、吃掉将军棋子、王逃走、钉住棋子不能走、王不能走进攻击格。

## 50. Draw 测试

至少覆盖 stalemate、threefold、fivefold、50-move、75-move、K vs K、K+B vs K、K+N vs K、不得错误判断 K+B+N vs K、draw agreement。

## 51. Stockfish 测试

不要求 AI 每次选择固定最佳着。测试 UCI handshake、isready、position fen、go、bestmove 可解析、返回 move 被 ChessSession 接受、stop、new game、dispose。

## 52. Web Stockfish 测试

验证 Worker 启动、WASM 加载、UCI handshake、bestmove、stop、terminate，以及 UI thread 不被冻结。

## 53. Android Stockfish 测试

验证 native binary 可执行、stdin 可写、stdout 可读、异常退出可恢复、stop 生效、dispose 不残留进程。

## 54. LAN 测试

单进程模拟 host / white / black，覆盖握手、move、非法 move、seq duplicate、seq gap、castling、en passant、promotion、checkmate、draw、undo、resign、disconnect、reconnect、stateSync。

## 55. 联机一致性测试

给多份 ChessSession 重放相同 committed events，每一步都断言：

```text
FEN(host) == FEN(clientA)
FEN(host) == FEN(clientB)
result(host) == result(clientA)
```

## 56. 不需要的东西

本次实现不要顺手加入：

```text
ChessStorage
ChessRecordLibrary
PGN parser
PGN exporter
opening database
cloud account
Elo rating
online matchmaking
spectator mode
engine analysis arrows
evaluation bar
best-line display
```

Stockfish 只负责 AI 对战，不是分析工具。

## 57. 旧 Chess 代码清理

新 ChessSession 验证完成后，从通用 GameSession 删除 `_setupChess()`、`_chessPseudoMoves()`、Chess 专用 `_isInCheck()`、Chess 相关 movePiece 分支和 `_hasAnyLegalMove` 分支，避免旧规则 + 新规则两套实现并存。

## 58. 一次实现顺序

```text
1. Chess 数据模型
2. ChessPosition
3. Move generator
4. Check / attack detection
5. Castling
6. En passant
7. Promotion
8. ChessSession
9. Draw / repetition
10. Undo
11. FEN
12. UCI move codec
13. Perft + 完整规则测试
14. ChessBoard
15. 本地双人
16. Stockfish 19 通用接口
17. Android Stockfish
18. Web Stockfish WASM
19. AI 对战 UI
20. LAN 通用层接入
21. ChessAuthority / Replica
22. LAN UI
23. Disconnect / reconnect
24. Undo / draw / resign
25. 回归测试
26. 删除旧 Chess prototype
```

最终不要留下“规则完整但 AI 未接”或“AI 能走但王车易位没做”的半成品状态。

## 59. CI

必须继续通过：

```text
dart analyze lib test
flutter test
flutter build web
python3 tools/package_lan_android.py --debug
```

另外增加 Chess perft tests 和 Stockfish bridge smoke test。若 native/Web Stockfish 编译成本过高，可以固定已构建产物并使用独立 rebuild workflow，而不是每次 push 都重编。

## 60. 验收标准

### Chess Rules

- [ ] 初始局面正确
- [ ] 所有棋子基本走法正确
- [ ] 将军正确
- [ ] 将死正确
- [ ] 逼和正确
- [ ] 王车短易位正确
- [ ] 王车长易位正确
- [ ] 吃过路兵正确
- [ ] Q/R/B/N 四种升变正确
- [ ] 三次重复正确
- [ ] 五次重复正确
- [ ] 50 回合规则正确
- [ ] 75 回合规则正确
- [ ] dead position 正确
- [ ] 认输正确
- [ ] 和棋协议正确

### Rule Validation

- [ ] 初始局面 perft 1 = 20
- [ ] perft 2 = 400
- [ ] perft 3 = 8902
- [ ] perft 4 = 197281
- [ ] 特殊 perft 局面通过
- [ ] Undo 完全恢复局面状态

### Local

- [ ] 本地双人完整可玩
- [ ] Promotion UI 正常
- [ ] 棋盘翻转正常
- [ ] 退出后不保存对局

### AI

- [ ] Stockfish 19 启动
- [ ] Android AI 正常
- [ ] Web AI 正常
- [ ] 用户可执白
- [ ] 用户可执黑
- [ ] 随机执棋
- [ ] 多档难度
- [ ] 悔棋正确
- [ ] `stop` 正确
- [ ] 页面退出不残留引擎
- [ ] Stockfish move 再经过 ChessSession 校验

### LAN

- [ ] 创建房间
- [ ] 加入房间
- [ ] 黑白分配正确
- [ ] 普通走子同步
- [ ] 易位同步
- [ ] en passant 同步
- [ ] promotion 同步
- [ ] 将死同步
- [ ] 和棋同步
- [ ] 认输同步
- [ ] 悔棋协商
- [ ] 和棋协商
- [ ] 非法 move 不推进 seq
- [ ] 断线重连
- [ ] stateSync 完全恢复
- [ ] 双方 FEN 始终一致
- [ ] 房间关闭后不保存历史

### Regression

- [ ] Go 不受影响
- [ ] KataGo 不受影响
- [ ] Go LAN 不受影响
- [ ] Draughts 不受影响
- [ ] Android 构建通过
- [ ] Web 构建通过
- [ ] 全测试通过

## 61. 不允许的妥协

以下任何一种情况都不能作为“Chess 已完成”：

```text
没有王车易位
没有吃过路兵
只能升后
用 Stockfish 代替自己的规则判断
Stockfish move 不二次验证
不实现 repetition
不维护 castling rights
不维护 en passant target
LAN 客户端自己决定游戏结果
联机使用不同规则实现
只测试几个手写局面而不跑 perft
把 Chess 继续全部塞进 GameSession
AI 在 UI isolate 里阻塞
关闭页面后 Stockfish 仍在运行
为了 FEN 又顺手做一个棋谱库
```

## 62. 最终架构

```text
                       EasyPlay Chess
                             │
                       ChessGamePage
                             │
                       ChessSession
                             │
                 ┌───────────┼───────────┐
                 │           │           │
            Local Human   Stockfish     LAN
                             │           │
                     ChessEngine      Authority
                        /    \           │
                 Android     Web      ChessSession
                 Native      WASM
```

所有路径最终都回到 ChessSession 进行合法性验证和状态更新。

Stockfish 只负责选 move；LAN 只负责传 move；UI 只负责让用户选 move。真正决定这一步是否合法、执行后是什么局面、游戏是否结束的只有 ChessSession。

## 63. 完成定义

Chess 功能完成时，EasyPlay 应达到：

> 用户打开 Chess 后，可以立即选择本地双人、Stockfish 19 AI 或局域网联机进行一盘完整标准国际象棋对局。EasyPlay 自己负责所有国际象棋规则，Stockfish 只负责 AI 选着，LAN 只负责同步权威事件；对局关闭后不保存棋谱、不产生历史记录，也不存在依赖 Stockfish 才能判断合法走法或游戏结果的情况。

这就是 Chess 的最终产品边界。
