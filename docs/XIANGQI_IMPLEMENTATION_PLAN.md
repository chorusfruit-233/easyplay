# EasyPlay 中国象棋（Xiangqi）一次性实现计划

**状态：待实现**  
**仓库：** chorusfruit-233/easyplay  
**检查基准：** main @ de118c2e6a39b77bc31e62986ee027a6d607e140  
**检查时版本：** v1.4.5

## 1. 实现目标

一次性增加完整的中国象棋功能，复用 EasyPlay 现有 Chess、LAN、WebRTC 和引擎运行设施。

完成后支持：

- 完整标准中国象棋规则
- 本地双人对战
- Pikafish AI 对战
- Android ARM64 原生 AI
- GitHub Pages WebAssembly AI
- LAN WebSocket 联机
- WebRTC 手动交换连接
- 断线重连与局面同步
- 悔棋、认输、和棋协商
- 再来一局
- 完整移动端交互

**一次性交付，不留下只能本地下棋、AI 或联机尚未接入的半成品。**

产品定位：

~~~text
Xiangqi / 中国象棋
├── 本地双人
├── AI 对战（Pikafish）
├── 局域网联机
└── WebRTC 联机
~~~

明确不做：棋谱库、历史对局长期保存、自动恢复上一次对局、PGN/XQF/CBL 导入导出、开局库、残局题库、AI 分析页面、云端账号、排位、匹配服务器、远程 AI 推理服务。

允许在当前对局内保存临时着法历史，用于规则、悔棋、Pikafish 搜索和网络重连，不属于持久化棋谱。

## 2. 当前代码基线

### 2.1 已有能力

~~~text
lib/chess/
  独立 ChessSession
  国际象棋规则
  Stockfish 19
  Android / Web 引擎适配
  本地、AI、联机

lib/draughts/
  多规则引擎
  本地、AI、联机

lib/gomoku/
  多规则
  本地 AI
  联机

lib/lan/
  RoomCoordinator
  MessageTransport
  LAN WebSocket
  WebRTC
  完整 event log
  stateSync
  reconnect
  LanRematch
~~~

中国象棋应成为第五种独立游戏，而不是添加到 GameSession 内部。

### 2.2 现有约定

- GameSession 继续只承担围棋规则；各棋种使用独立 Session。
- 房主负责权威落子验证，客户端只应用已提交事件。
- 联机事件采用连续 seq；再来一局不重置房间事件序列号。
- Android / Web 使用平台条件导入。
- 不对现有 Go、Chess、Draughts、Gomoku 产生行为回归。

## 3. 游戏数据模型

新增：

~~~text
lib/xiangqi/
├── xiangqi.dart
├── xiangqi_side.dart
├── xiangqi_piece.dart
├── xiangqi_move.dart
├── xiangqi_position.dart
├── xiangqi_move_generator.dart
├── xiangqi_repetition.dart
├── xiangqi_rules.dart
├── xiangqi_result.dart
├── xiangqi_session.dart
├── xiangqi_fen.dart
├── xiangqi_uci.dart
├── xiangqi_match_controller.dart
│
├── engine/
│   ├── xiangqi_engine.dart
│   ├── pikafish_runtime.dart
│   ├── pikafish_io.dart
│   ├── pikafish_web.dart
│   └── pikafish_stub.dart
│
└── widgets/
    ├── xiangqi_home_page.dart
    ├── xiangqi_board.dart
    ├── xiangqi_piece_painter.dart
    ├── xiangqi_ai_settings.dart
    ├── xiangqi_game_page.dart
    └── xiangqi_lan_pages.dart
~~~

### 3.1 独立红黑方

~~~dart
enum XiangqiSide {
  red,
  black,
}

enum XiangqiPieceType {
  general,
  advisor,
  elephant,
  horse,
  chariot,
  cannon,
  soldier,
}
~~~

不能在中国象棋界面直接显示现有 Side.white.label，否则会出现错误的“白方”。

### 3.2 棋盘

棋盘有 10 行、9 列，棋子位于交叉点而非格子中心。内部统一：

~~~text
row 0：黑方底线
row 9：红方底线
col 0：左侧第一路
col 8：右侧第九路
~~~

~~~dart
class XiangqiPosition {
  final List<List<XiangqiPiece?>> board;
  final XiangqiSide sideToMove;

  const XiangqiPosition({
    required this.board,
    required this.sideToMove,
  });
}
~~~

采用不可变 Position，正式移动创建新状态。任何局面入口应验证棋盘维度、棋子数量和将帅位置等约束。

## 4. 走法表示

~~~dart
class XiangqiMove {
  final Cell from;
  final Cell to;

  const XiangqiMove({
    required this.from,
    required this.to,
  });
}
~~~

不需要国际象棋 promotion 字段。所有正式移动必须经过 XiangqiSession.applyMove(XiangqiMove move)，UI / AI / LAN 不可自行修改棋盘。

## 5. 棋子规则

一次性实现全部标准棋子：

| 棋子 | 必须实现 |
|---|---|
| 帅 / 将 | 九宫内移动、将帅照面 |
| 仕 / 士 | 九宫内斜行 |
| 相 / 象 | 田字、塞象眼、不可过河 |
| 马 | 日字、蹩马腿 |
| 车 | 横竖直线 |
| 炮 | 不吃不越子、吃子隔恰好一个炮架 |
| 兵 / 卒 | 过河前向前、过河后可横行、不可后退 |

区分 pseudoLegalMoves() 和 legalMoves()：先生成棋子本身的候选着法，再过滤会导致己方将帅受攻击的走法。

~~~dart
List<XiangqiMove> legalMoves();
List<XiangqiMove> legalMovesFrom(Cell from);
bool isLegalMove(XiangqiMove move);
bool isInCheck(XiangqiSide side);
~~~

将帅照面属于规则约束，不是仅有 UI 提示。正常终局由将死、困毙等判定，不以“吃掉对方将帅再继续游戏”代替。

## 6. 终局规则

支持将军、将死、困毙、认输、双方协议和棋、重复局面裁定及固定规则配置中的无吃子着数和棋条件。

**困毙按中国象棋规则处理，不能直接照搬国际象棋 Stalemate 和棋。**

~~~dart
enum XiangqiEndReason {
  checkmate,
  noLegalMove,
  resignation,
  drawAgreement,
  repetitionViolation,
  repetitionDraw,
  moveLimitDraw,
}
~~~

最终结果只能由 XiangqiSession 产生。

## 7. 长将、长捉与重复局面

这是最重要、不能简化的部分。

### 7.1 固定规则基准

第一版固定明确的亚洲规则兼容配置，参考世界象棋联合会《世界象棋规则》2018，以及 Pikafish 的 AsianRule 实现和测试案例。不同平台的重复局面裁定并非完全一致；EasyPlay 必须固定自身规则版本、案例和实际行为，不声称兼容所有比赛规则。第一版不开放多种长将长捉标准自由切换。

### 7.2 独立判定器

~~~dart
class XiangqiRepetition {
  XiangqiRepetitionResult evaluate(
    XiangqiPosition position,
    List<XiangqiMoveRecord> history,
  );
}
~~~

历史至少包含移动前局面、移动后局面、行棋方、移动棋子、是否吃子、是否将军、是否构成规则意义上的捉子，以及重复周期信息。

禁止直接把“重复三次”一律判成和棋。

### 7.3 专项测试

- 单方长将
- 双方重复将军
- 单方长捉
- 双方长捉
- 一方长将、另一方长捉
- 将军与捉子混合循环
- 允许重复但不应判负的局面
- 吃子打断相关重复历史
- 悔棋后重复状态恢复

不得通过缩减重复判定测试来宣布规则完成。

## 8. 运行时历史与悔棋

不保存长期棋谱，但 XiangqiSession 需要维护：

~~~text
position
moves[]
undoSnapshots[]
repetitionHistory
moveLimitState
result
revision
~~~

悔棋完整恢复棋盘、轮到谁、终局状态、重复历史、长将/长捉判定和无吃子计数。

- 本地双人：撤回上一手。
- AI：优先撤回玩家上一手及 AI 应手，回到玩家回合；AI 尚未应手则只撤玩家一步，并取消搜索。
- 联机：沿用现有双方协商规则，只能在对手尚未应手时申请撤回自己最近一手。

## 9. FEN 与 UCI

参考 Chess 架构，但独立实现中国象棋 FEN / 坐标编解码器，不能复用国际象棋的坐标规则。

初始 FEN 棋盘部分：

~~~text
rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR
~~~

~~~dart
String exportXiangqiFen(XiangqiPosition position);
XiangqiPosition parseXiangqiFen(String fen);
String xiangqiMoveToUci(XiangqiMove move);
XiangqiMove parseXiangqiUciMove(String text);
~~~

统一坐标 a0–i9。内部 row 0 为黑方底线时，file = col，rank = 9 - row。与选定的 Pikafish 构建进行 round-trip 验证。

**AI 搜索不能永远只传当前 FEN。** 要向 Pikafish 提供相关完整着法历史，以便正确处理搜索中的重复局面：

~~~text
position startpos moves <已提交着法历史>
~~~

自定义初始局面未来可用：

~~~text
position fen <initialFen> moves <历史着法>
~~~

FEN 表示局面，当前对局的临时历史补充重复判定所需信息。

## 10. AI：Pikafish

采用官方 Pikafish，建议固定基线为 official-pikafish/Pikafish 的 Pikafish-2026-09-06 Release。构建脚本必须固定明确 commit，不跟踪浮动 master，并校验：

~~~text
source commit SHA
native binary SHA-256
WASM JS SHA-256
WASM binary SHA-256
NNUE SHA-256
~~~

### 10.1 接口

~~~dart
abstract interface class XiangqiEngine {
  Future<void> start();
  Future<void> newGame();
  Future<XiangqiMove> bestMove(
    XiangqiPosition position,
    List<XiangqiMove> history,
    XiangqiEngineLimits limits,
  );
  Future<void> stop();
  Future<void> dispose();
}
~~~

可提取 Chess / Xiangqi 共用的 UCI 会话机制（命令队列、响应等待、超时、取消、资源释放），但不能直接拿 ChessEngine 替代：两者的 FEN、坐标、规则选项和历史不同。

### 10.2 AI 工作流

~~~text
玩家完成合法着法
  ↓
XiangqiSession 更新并检查终局
  ↓
导出初始局面和历史
  ↓
Pikafish 搜索
  ↓
bestmove
  ↓
解析为 XiangqiMove
  ↓
XiangqiSession 二次验证并正式应用
~~~

Pikafish 不是 EasyPlay 的规则权威。

### 10.3 难度

沿用六档 UI：初学、简单、普通、困难、大师、最高。集中由 XiangqiAiLevel 映射 Pikafish 的 Skill Level、搜索时间和必要的限制，不照搬国际象棋 Stockfish Elo 数值。

### 10.4 生命周期

参考 ChessMatchController：每局使用 generation / sessionId；悔棋、退出、重开、认输后丢弃旧 AI 结果。stop 正确处理剩余 bestmove；dispose 后关闭原生进程 / 终止 Worker；不允许旧搜索修改新棋局。

## 11. Android Pikafish

参考现有 AndroidStockfish.kt 和 tools/prepare_stockfish.py，新增：

~~~text
android/app/src/main/kotlin/com/easyplay/easyplay/AndroidPikafish.kt
tools/prepare_pikafish.py
~~~

Android ARM64 产物目标：

~~~text
android/app/src/main/jniLibs/arm64-v8a/libpikafish.so
~~~

如 Stockfish 一样使用 nativeLibraryDir 的可执行文件路径。独立通道：

~~~text
easyplay/pikafish
easyplay/pikafish/output
~~~

不能与 Stockfish 共用命令流。Gradle 增加 preparePikafish，确保 Android Studio 直接构建也能准备资源；缺失或校验失败不得静默跳过；成功校验后不重复下载；打包所有必要许可；关闭对局后无残留进程。

## 12. Web Pikafish

新增同源 Web 资源，实际文件名按固定构建确定，例如：

~~~text
web/pikafish/
├── pikafish.js
├── pikafish.wasm
└── pikafish.nnue
~~~

参考 lib/chess/engine/stockfish_web.dart 与 tools/test_stockfish_web.cjs：

- Web Worker 内运行，不能阻塞 Flutter UI。
- 资源由 GitHub Pages 同源托管，不使用外部 AI API。
- 优先验证单线程 WASM；不强制依赖 SharedArrayBuffer。
- 现有围棋 coi-serviceworker 保持不变。
- 初始化失败时明确提示，不永久停在“AI 思考中”。

新增 tools/test_pikafish_web.cjs，真实浏览器验证：Worker、NNUE、uci/uciok、isready/readyok、position startpos、go、bestmove、stop、ucinewgame、terminate。必须模拟 /easyplay/ Pages 子路径。

## 13. 模型及许可证

Pikafish 程序代码与 NNUE 权重授权分别处理。记录引擎源码、许可证、构建版本、NNUE 来源、模型许可、下载地址及各项 SHA-256。官方 Pikafish NNUE 权重未经许可不能用于商业用途；正式发布 APK / Web 前核实 EasyPlay 分发方式与许可相符。增加相关 Notice / License 与“关于”页信息，不因引擎源码采用 GPLv3 就默认权重有相同授权。

## 14. LAN 协议接入

新增 lib/lan/xiangqi_lan_game.dart：

~~~dart
XiangqiAuthority
XiangqiLanReplica
XiangqiNegotiation
~~~

对接 RoomCoordinator、LanHostServer、LanClientConnection、LanRematch，不另写 WebSocket。

### 14.1 握手

~~~json
{
  "game": "xiangqi",
  "rulesVersion": 1,
  "ruleProfile": "asian"
}
~~~

规则版本及 profile 必须一致。

### 14.2 红黑座位映射

现有 LAN Side 仅有 black / white。为避免破坏旧游戏，只在联机边界映射：

~~~text
LAN Side.white → XiangqiSide.red
LAN Side.black → XiangqiSide.black
~~~

房主通过 firstSide = Side.white 获取红方先手。UI 永远显示红方/黑方，不对用户显示“白方”。映射仅用于协议适配；规则层不得混用两类 Side。

### 14.3 Move 事件

复用 LanMessageType.move，包含明确棋种：

~~~json
{
  "type": "move",
  "seq": 12,
  "game": "xiangqi",
  "side": "W",
  "move": "h2e2"
}
~~~

W 只是现有传输层内部座位码。

### 14.4 必须修改协议验证

当前 lan_protocol.dart 将字符串 move 交给国际象棋 parseUciMove。新增 Xiangqi 时必须按棋种分派，且房主验证事件 game 与房间一致：

~~~text
Chess move → parseUciMove()
Xiangqi move → parseXiangqiUciMove()
~~~

其他 move 格式继续使用现有各棋种协议约定；格式正确并不代表规则合法，最终仍须 Session 验证。

## 15. RoomCoordinator 接入

扩展当前四分支：

~~~text
RoomCoordinator
├── GoAuthority
├── ChessAuthority
├── DraughtsAuthority
├── GomokuLanAuthority
└── XiangqiAuthority
~~~

同步修改 constructor、seq、gameOver、firstSide、submit、sync、acceptsHello、expireUndo、draw negotiation、rematch、dispose 等分派。

保留 host authoritative state、committed events、monotonic seq 与 full stateSync。客户端不可预测性提交正式棋盘状态。

## 16. LAN 生命周期

新增中国象棋联机大厅：

~~~text
中国象棋联机
├── WebRTC 连接
├── 创建局域网房间
└── 加入局域网房间
~~~

支持建房、口令、红黑分配、自动发现、手动 IP、断线重连、完整状态同步、非法着拒绝、认输、悔棋/和棋协商、再来一局。重连时必须恢复长将、长捉与重复历史；stateSync 不能仅替换成当前 FEN。

## 17. WebRTC 同步接入

修改：

~~~text
lib/lan/rtc_manual_signaling.dart
lib/lan/rtc_room.dart
lib/lan/rtc_lobby_page.dart
~~~

~~~text
RtcInvitation(game: 'xiangqi')
  ↓
RtcRoom.host
  ↓
XiangqiAuthority
  ↓
RtcMatchClient
  ↓
XiangqiLanReplica
  ↓
XiangqiGamePage.online
~~~

适配 invitation game 白名单、规则版本与 configuration、answer 一致性、房主 authority、客户端 replica、seq / 事件分派、页面跳转、关闭和释放。继续使用现有手动 Offer/Answer 与 STUN，不新建信令服务器，不强制用户注册其他服务。

## 18. LAN Quick Join

目前快捷加入识别 go/chess/draughts/gomoku，增加 xiangqi。修改：

~~~text
lib/lan/lan_quick_join.dart
lib/lan/lan_transport_io.dart
lib/lan/lan_scanner_io.dart
~~~

/easyplay/probe 返回 game: xiangqi，棋盘信息 9×10；UI 显示中国象棋；输入口令后进入中国象棋等待页；Web 客户端能快捷加入 Android 房主；规则版本不符明确报错，不可错误回退至围棋页面。

## 19. 再来一局

直接复用 lib/lan/lan_rematch.dart。终局后一方请求、对方接受：

~~~text
双方 XiangqiSession.reset()
→ 初始棋盘
→ 清除本局重复历史
→ room.round + 1
~~~

保留房间、座位和累计 seq。跨轮次断线重放应正确恢复新局面。

## 20. 中国象棋 UI

不可简单套用 ChessBoard：棋子位于交叉点且棋盘结构不同。新增 xiangqi_board.dart、xiangqi_piece_painter.dart。绘制 9×10 交叉点、楚河汉界、九宫斜线、红黑棋子、选中和合法目标、最后一手、将军提示、棋盘翻转和响应式手机触摸。

默认黑方在上、红方在下。文字：

~~~text
红：帅 仕 相 马 车 炮 兵
黑：将 士 象 马 车 炮 卒
~~~

内部棋子类型保持统一，不因汉字不同复制规则实现。可用 CustomPainter，不依赖外部棋子图片资源。

棋盘方向：本地双人默认红在下；AI 按用户执棋方；联机始终我方在下。翻转不改变内部或网络坐标。

## 21. 页面结构

首页新增第五张游戏卡：

~~~text
中国象棋
XIANGQI
~~~

进入：

~~~text
中国象棋
├── AI 对战
├── 本地双人
└── 联机
    ├── WebRTC
    ├── 创建房间
    └── 加入房间
~~~

修改 lib/game_session.dart 和 lib/main.dart，为 GameType 增加 xiangqi，Shell._openGame 路由 XiangqiHomePage。新页面遵守现有主题系统，不能自建一套写死颜色。

## 22. 本地与 AI 对战

对标 ChessGamePage：

~~~dart
XiangqiGamePage.local();

XiangqiGamePage.ai(
  humanSide: XiangqiSide.red,
  level: XiangqiAiLevel.normal,
);

XiangqiGamePage.online(
  connection: connection,
);
~~~

AI 对战可选执红、执黑、随机以及六档难度。AI 搜索时展示思考状态，但不冻结页面导航。引擎启动失败允许重试或返回本地双人，不生成虚假 AI 着法。

## 23. 测试结构

~~~text
test/xiangqi/
├── initial_position_test.dart
├── piece_moves_test.dart
├── horse_leg_test.dart
├── elephant_eye_test.dart
├── cannon_test.dart
├── palace_test.dart
├── flying_general_test.dart
├── check_test.dart
├── endgame_test.dart
├── repetition_test.dart
├── move_limit_test.dart
├── fen_test.dart
├── uci_test.dart
├── undo_test.dart
├── perft_test.dart
├── ai_test.dart
├── board_test.dart
├── game_page_test.dart
├── lan_test.dart
└── rtc_test.dart
~~~

### 23.1 规则

初始布局、各棋子走法、马腿、象眼、炮架、过河兵、将帅照面、不能主动送将、应将、双将、将死、困毙、长将长捉及特殊重复、悔棋恢复。

### 23.2 Perft

~~~dart
int xiangqiPerft(
  XiangqiPosition position,
  int depth,
);
~~~

采用固定公开参考局面与经过核实的参考结果，对照 Pikafish 合法着法进行差异测试。覆盖初始局面、马腿、炮架、将帅照面、将军。不能以同一套错误规则生成参考值来自证正确。

### 23.3 AI

真实 native 启动、UCI、NNUE 加载、初始局面返回合法着、红黑两方、stop、undo 取消旧搜索、dispose 后无残留、非法引擎着不改变 Session。

### 23.4 联机

双方座位、红先、Chess/Xiangqi move parser 不混用、非法着不推进 seq、重复事件拒绝、断线历史恢复、长将长捉一致、悔棋认输和棋、再来一局、WebSocket / WebRTC 共用权威规则。

## 24. CI 与打包

新增：

~~~text
tools/prepare_pikafish.py
tools/test_pikafish_web.cjs
~~~

修改：

~~~text
.github/workflows/flutter.yml
.github/workflows/pages.yml
.github/workflows/release.yml
tools/package_lan_android.py
tools/prepare_lan_web.py
android/app/build.gradle.kts
~~~

CI 必须执行：

~~~sh
python3 tools/prepare_pikafish.py
dart analyze lib test
flutter test
flutter build web --no-wasm-dry-run
python3 tools/package_lan_android.py --debug
~~~

另外执行 Pikafish Web Worker smoke、ARM64 native smoke、中国象棋 rules/perft、LAN/RTC 回归。浏览器测试包含 Pages 子路径 /easyplay/。

Android APK 应同时包含 KataGo、Stockfish、Pikafish 和内置 LAN Web 客户端，不得因新增 Pikafish 覆盖或丢失旧资源。

单独记录 Pikafish ARM64、Web WASM、NNUE、最终 APK 及 Web 部署大小。评估 Android native 与内置 Web 重复打包的成本，但不能为去重破坏 Pages 独立运行。

## 25. 一次性实现顺序

1. XiangqiSide / Piece / Move / Position
2. 棋盘初始布局
3. 全部棋子的走法生成
4. 将军与合法性过滤
5. 将死与困毙
6. 重复局面、长将和长捉
7. 无吃子着数规则
8. XiangqiSession / Undo
9. FEN / UCI 编解码
10. 规则与 Perft 测试
11. XiangqiBoard / PiecePainter
12. 本地双人页面
13. Pikafish 固定版本及模型校验
14. Android 原生引擎
15. Web WASM 引擎
16. AI 对战与生命周期管理
17. XiangqiAuthority / Replica
18. LAN 协议适配
19. RoomCoordinator 适配
20. LAN 建房、加入、快捷加入
21. WebRTC 接入
22. 悔棋、和棋、认输、再来一局
23. 完整回归测试
24. CI、GitHub Pages、APK 打包和许可证验收

允许内部多次提交，最终不得留下未完成的对局模式。

## 26. 最终验收标准

### 规则

- [ ] 32 枚初始棋子布局正确
- [ ] 红方先手
- [ ] 全部棋子走法正确
- [ ] 马腿、象眼、炮架正确
- [ ] 将帅照面正确
- [ ] 将军、应将正确
- [ ] 将死与困毙正确
- [ ] 长将、长捉符合固定规则配置
- [ ] 无吃子着数判定正确
- [ ] Undo 完整恢复历史状态
- [ ] FEN / UCI round-trip 正确
- [ ] Perft 和固定案例通过

### AI

- [ ] Android Pikafish 可运行
- [ ] Web Pikafish 可运行
- [ ] NNUE 校验通过
- [ ] 红黑 AI 对战正常
- [ ] 六档难度
- [ ] 无虚假着法
- [ ] 取消旧搜索有效
- [ ] 退出无残留进程 / Worker

### 联机

- [ ] Android 建房
- [ ] LAN 自动发现
- [ ] 手动加入
- [ ] 内置 Web 客户端
- [ ] WebRTC 双端
- [ ] 非法着由权威拒绝
- [ ] seq 和 stateSync 正确
- [ ] 断线后完整恢复
- [ ] 悔棋、和棋、认输
- [ ] 再来一局
- [ ] 长将长捉无状态分叉

### 发布回归

- [ ] Go / KataGo 正常
- [ ] Chess / Stockfish 19 正常
- [ ] Draughts 正常
- [ ] Gomoku 正常
- [ ] 既有 LAN / WebRTC 测试通过
- [ ] Android Debug / Release 构建通过
- [ ] GitHub Pages 构建通过
- [ ] 第三方许可证和模型来源完整
- [ ] 无棋谱库或对局持久化记录

## 27. 不允许的妥协

- 只实现普通走法
- 将帅照面仅有 UI 提示、无规则校验
- 将死和困毙套用国际象棋相同结果
- 三次重复一律判和
- 用 Pikafish 代替 EasyPlay 的全部规则判断
- AI 只传当前 FEN 而丢失重复历史
- 只支持 Android AI、不支持 Web
- 只接 LAN、不接现有 WebRTC
- 把中国象棋 move 传给 Chess UCI parser
- 把红方显示为白方
- 重连只恢复棋盘而不恢复规则历史
- 为临时历史另造长期棋谱存储
- 新功能破坏其他四种游戏

## 28. 最终架构

~~~text
                         EasyPlay
                            │
                     XiangqiGamePage
                            │
                     XiangqiSession
                            │
               ┌────────────┴────────────┐
               │                         │
         XiangqiRules            XiangqiRepetition
               │                         │
               └────────────┬────────────┘
                            │
               ┌────────────┼────────────┐
               │            │            │
            Local        Pikafish      Online
                            │            │
                        UCI Runtime   XiangqiAuthority
                         /      \         │
                    Android     Web   RoomCoordinator
                    Native      WASM      │
                                     ┌────┴────┐
                                     LAN      WebRTC
~~~

本地、AI 和联机都通过同一个 XiangqiSession 验证着法和游戏结果。

## 29. 完成定义

中国象棋完成后，EasyPlay 用户可以在 Android 或 Web 打开中国象棋，直接选择本地双人、Pikafish AI 或联机进行完整对局。应用独立负责规则，Pikafish 仅负责 AI 选着，LAN 与 WebRTC 共用权威状态同步。对局结束或关闭后不持久化保存棋谱，同时不影响仓库已有四种游戏。
