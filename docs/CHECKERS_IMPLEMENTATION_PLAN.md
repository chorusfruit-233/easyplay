EasyPlay Checkers / Draughts 一次性实现计划

状态：待实现

1. 目标

一次性把当前只有基础原型的 Checkers 重构成完整的 Draughts / Checkers 多规则系统。

最终必须支持：

- 多种主流 Draughts / Checkers 规则
- 本地双人对局
- 局域网联机
- 完整连续吃子
- 强制吃子及各种吃子优先级
- 短王 / 飞王
- 各规则不同的升王时机
- 各规则不同的和棋规则
- 悔棋
- 认输
- 和棋协商
- 断线重连
- 对局保存与恢复
- 棋谱记录
- 规则版本校验

明确不做：

- Checkers AI
- AI 分析
- 外部引擎
- WebGPU
- 排位 / 匹配服务器
- Internet 中继服务器

Checkers 的产品定位：

Draughts / Checkers
├── 多规则
├── 本地双人
├── LAN 联机
├── 棋谱
└── 对局恢复

围棋仍保持：

Go
├── 本地棋谱
├── KataGo AI
├── 分析
└── LAN 联机

两者不要求功能完全对称。

---

2. 核心设计原则

2.1 不再把 Checkers 写在 "GameSession" 里

当前：

GameSession
├── Go
├── Chess
└── Checkers

不适合继续扩展大量 Draughts 变体。

新的规则系统独立：

lib/draughts/

"GameSession" 最终只保留兼容入口，或者完全由上层按游戏类型持有不同 Session。

目标：

Go           → GameSession / GoSession
Chess        → ChessSession
Draughts     → DraughtsSession

Draughts 的规则逻辑不得继续堆入：

game_session.dart

---

3. 第一版支持的规则

一次实现以下规则族：

english
international
brazilian
russian
pool
italian
spanish
turkish

对应 UI：

英式 / 美式跳棋
国际跳棋
巴西跳棋
俄罗斯跳棋
Pool Checkers
意大利跳棋
西班牙跳棋
土耳其跳棋

内部统一使用：

enum DraughtsVariant {
  english,
  international,
  brazilian,
  russian,
  pool,
  italian,
  spanish,
  turkish,
}

不得把某个规则称为默认“真正的 Checkers”。

---

4. 新目录结构

新增：

lib/draughts/
├── draughts.dart
├── draughts_variant.dart
├── draughts_rules.dart
├── draughts_position.dart
├── draughts_piece.dart
├── draughts_move.dart
├── draughts_session.dart
├── draughts_move_generator.dart
├── draughts_capture_search.dart
├── draughts_result.dart
├── draughts_notation.dart
├── draughts_record.dart
├── draughts_storage.dart
│
├── variants/
│   ├── english.dart
│   ├── international.dart
│   ├── brazilian.dart
│   ├── russian.dart
│   ├── pool.dart
│   ├── italian.dart
│   ├── spanish.dart
│   └── turkish.dart
│
└── widgets/
    ├── draughts_board.dart
    ├── draughts_game_page.dart
    ├── draughts_new_game_page.dart
    └── draughts_variant_picker.dart

LAN 不重新复制一套 socket：

lib/lan/

继续复用现有 transport / heartbeat / reconnect。

---

5. 数据模型

5.1 棋子

不要继续用：

PieceKind.checker
PieceKind.king

表示 Draughts。

新增：

enum DraughtsRank {
  man,
  king,
}

class DraughtsPiece {
  final Side side;
  final DraughtsRank rank;
}

---

6. 一手棋的数据结构

这是整个实现最重要的改动。

当前：

GameMove(
  from: ...,
  to: ...,
)

不够表达 Draughts。

必须改为完整路径：

class DraughtsMove {
  final List<Cell> path;
  final List<Cell> captures;

  const DraughtsMove({
    required this.path,
    this.captures = const [],
  });

  Cell get from => path.first;
  Cell get to => path.last;

  bool get isCapture => captures.isNotEmpty;
}

例如普通走子：

C3 → D4

表示：

path = [c3, d4]
captures = []

连续吃：

C3 → E5 → G7 → I9

必须表示成：

path = [c3, e5, g7, i9]
captures = [d4, f6, h8]

整个组合永远是一手。

不得拆成：

C3 → E5
E5 → G7
G7 → I9

三条游戏事件。

---

7. "DraughtsRules"

禁止大量：

if (variant == ...)

散落在 move generator 中。

建立统一规则描述：

class DraughtsRules {
  final DraughtsVariant variant;

  final int boardSize;
  final BoardGeometry geometry;

  final int startingRows;

  final ManMoveRule manMovement;
  final ManCaptureRule manCapture;

  final KingMoveRule kingMovement;
  final KingCaptureRule kingCapture;

  final CapturePriority capturePriority;

  final PromotionPolicy promotion;

  final CaptureRemovalPolicy captureRemoval;

  final DrawPolicy drawPolicy;
}

---

8. 棋盘几何

enum BoardGeometry {
  diagonalDarkSquares,
  orthogonalAllSquares,
}

大部分 Draughts：

diagonalDarkSquares

Turkish：

orthogonalAllSquares

不得在底层默认：

(r + c).isOdd

一定代表唯一合法格子。

合法格判断必须来自：

rules.geometry

---

9. 普通子移动

抽象：

enum ManMoveRule {
  forwardDiagonal,
  forwardOrthogonalWithSideways,
}

如果未来需要更多规则，继续扩展。

不要把：

side == Side.white ? -1 : 1

直接散落在整个 move generator。

统一由规则函数计算方向。

---

10. 普通子吃子

enum ManCaptureRule {
  forwardOnly,
  forwardAndBackward,
  orthogonal,
}

move generator 根据规则决定捕获方向。

---

11. 王的移动

enum KingMoveRule {
  short,
  flyingDiagonal,
  flyingOrthogonal,
}

short

只移动一格。

flyingDiagonal

沿对角线任意距离移动。

flyingOrthogonal

沿上下左右任意距离移动。

---

12. 王的吃子

不得把王移动和王吃子认为一定一致。

单独定义：

enum KingCaptureRule {
  short,
  flyingDiagonal,
  flyingOrthogonal,
}

飞王捕获需要：

找到第一个敌子
↓
敌子后所有允许落点
↓
对每个落点递归生成后续捕获

因此一个局面可能生成大量完整捕获路径。

---

13. 连续吃子搜索

新建：

draughts_capture_search.dart

使用 DFS / backtracking。

逻辑：

piece
  ↓
查所有合法捕获
  ↓
无捕获 → 当前路径完成
  ↓
有捕获
  ↓
对每种捕获：
    模拟
    ↓
    处理升王规则
    ↓
    继续 DFS

输出：

List<DraughtsMove>

必须直接输出完整的一手。

UI 不负责拼路径。

---

14. 被吃棋子的移除时机

新增：

enum CaptureRemovalPolicy {
  immediate,
  afterSequence,
}

这是必要规则维度。

捕获搜索不得默认：

board[captured] = null;

之后永远不存在。

如果规则要求整手结束后统一移除，则搜索中已经捕获的棋子：

- 不能再次被捕获
- 但是否继续阻挡飞王路线必须符合对应规则

所以搜索状态至少需要：

class CaptureSearchState {
  final DraughtsPosition position;
  final Set<Cell> captured;
  final DraughtsRank currentRank;
}

---

15. 升王

新增：

enum PromotionPolicy {
  afterTurn,
  stopOnPromotion,
  promoteAndContinue,
}

分别表达：

afterTurn

整手结束后成为王。

stopOnPromotion

到达王线后升王，本手立即结束。

promoteAndContinue

连续吃途中到达王线立即变王，并按王规则继续当前组合。

不得在：

_moveOn()

里简单判断：

if (to.row == 0 || to.row == 7)

然后统一升王。

---

16. 强制吃子

所有支持强制吃子的规则统一流程：

生成所有捕获
↓
捕获非空
  ↓
禁止所有普通移动

然后再调用：

CapturePriority

过滤允许的捕获路径。

---

17. 捕获优先级

不要只写：

bool mustTakeMaximum;

定义：

abstract interface class CapturePriority {
  List<DraughtsMove> select(
    DraughtsPosition position,
    List<DraughtsMove> moves,
  );
}

实现至少：

AnyCapturePriority
MaximumPiecesPriority
MaximumPiecesThenKingsPriority
ItalianCapturePriority

后续规则需要特殊 tie-break 时，不修改 move generator。

---

18. 合法走法唯一入口

所有棋局逻辑最终必须经过：

List<DraughtsMove> legalMoves()

以及：

List<DraughtsMove> legalMovesFrom(Cell cell)

UI：

不能自己判断走法

LAN：

不能自己判断走法

棋谱：

不能自己判断走法

全部调用同一个规则核心。

---

19. 落子

唯一入口：

bool applyMove(DraughtsMove move)

流程：

查 legalMoves()
↓
确认完整路径存在
↓
保存 undo snapshot
↓
原子应用整个 move
↓
移除所有捕获
↓
执行升王
↓
更新计数器
↓
切换回合
↓
检查终局

一次连续吃过程中：

不能切换 turn

---

20. 终局

至少支持：

一方无棋
一方无合法走法
认输
协议规定的和棋
双方协商和棋

统一：

class DraughtsResult {
  final Side? winner;
  final DraughtsEndReason reason;
}

enum DraughtsEndReason {
  noPieces,
  noMoves,
  resignation,
  drawRule,
  drawAgreement,
}

---

21. 和棋状态

需要记录足够的历史状态，例如：

position repetition
无吃子着数
无普通子移动着数
特定残局计数

不要只提供一个统一：

movesSinceCapture

由：

DrawPolicy

维护对应计数。

undo 必须恢复这些状态。

---

22. Undo

"DraughtsSession" 保存完整 snapshot：

class DraughtsSnapshot {
  position;
  turn;
  result;
  counters;
  repetitionState;
  moveCount;
}

连续吃虽然路径很长，但：

整个 DraughtsMove

只保存一个 undo snapshot。

悔棋一次：

撤回整手

不是撤回最后一跳。

---

23. UI

新增独立：

DraughtsGamePage

不要继续依赖通用 "GamePage" 内部大量分支。

首页：

Checkers / Draughts
    ↓
选择规则
    ↓
┌─────────────┬─────────────┐
│ 本地双人     │ 局域网联机   │
└─────────────┴─────────────┘

---

24. 规则选择页

显示：

英式 / 美式
国际
巴西
俄罗斯
Pool
意大利
西班牙
土耳其

每张卡简短显示：

8×8 / 10×10
短王 / 飞王

不需要把整套规则写在首页。

提供：

查看规则

进入详细说明。

---

25. 棋盘尺寸

"DraughtsBoard" 必须动态支持：

8×8
10×10

不得假定：

size == 8

格子坐标、触摸检测、绘制全部基于：

session.rules.boardSize

---

26. 连续吃 UI

由于底层一次返回完整路径，而玩家实际操作需要一步步点击，因此 UI 维护：

List<Cell> pendingPath

交互：

点击棋子
↓
显示第一跳目标
↓
点击第一跳
↓
只显示仍属于合法完整 move 的下一跳
↓
...
↓
完整路径唯一/完成
↓
session.applyMove(fullMove)

注意：

中间步骤只属于 UI preview

不得修改正式 Session。

直到完整一手确定后：

applyMove()

一次提交。

这样本地和联机语义完全一致。

---

27. LAN 架构

复用现有：

HttpServer
WebSocket
heartbeat
PIN
reconnect
seq
stateSync

不要重新做一套 Draughts socket。

需要把目前偏 Go 的权威层逐步抽象。

目标：

LanTransport
     ↓
GameAuthority
     ↓
┌───────────────┬────────────────┐
│ GoAuthority   │ DraughtsAuthority
└───────────────┴────────────────┘

---

28. Draughts 房间握手

加入：

{
  "game": "draughts",
  "variant": "international",
  "rulesVersion": 1
}

双方必须完全匹配：

game
variant
rulesVersion

不一致立即拒绝。

不得只发：

boardSize

因为同样 8×8 可以代表完全不同规则。

---

29. 联机 move 消息

发送整个原子 move：

{
  "type": "move",
  "seq": 42,
  "path": [
    [5, 0],
    [3, 2],
    [1, 4]
  ]
}

服务端：

收到完整路径
↓
构造 DraughtsMove
↓
authority.session.applyMove()
↓
合法 → seq++
非法 → rejected

客户端不得发送：

jumpBegin
jumpContinue
jumpEnd

之类中间状态。

---

30. 权威模型

仍然保持：

Host = 唯一权威

客户端：

点击完成整手
↓
发送请求
↓
等待 host 广播
↓
收到 committed move
↓
本地 replica 应用

不得：

本地先正式落子
然后等待服务器确认

可以有 UI preview，但不能修改权威状态。

---

31. LAN 事件

Draughts 至少：

move
resign
drawRequest
drawAccept
drawReject
undoRequest
undoAccept
undoReject

继续使用：

seq

作为所有已提交游戏事件的顺序。

---

32. stateSync

Draughts 也使用：

完整权威事件日志

恢复。

事件：

variant
initial config
moves
undo events
draw events
resignation

重连后：

从头重放
↓
得到完全一致状态

第一版不需要复杂增量快照。

---

33. 棋谱

建立自己的：

DraughtsRecord

第一目标是：

EasyPlay 自己能可靠保存/恢复

不是立即实现所有外部格式。

建议内部 JSON：

{
  "version": 1,
  "variant": "international",
  "moves": [
    {
      "path": [[6,1],[4,3],[2,5]],
      "captures": [[5,2],[3,4]]
    }
  ],
  "result": null
}

---

34. PDN

在核心完成后，同一次实现中加入基础 PDN import/export。

建立：

draughts_notation.dart

但是：

内部状态 != PDN 文本

内部始终保存结构化 move。

PDN 只是导入导出层。

对于无法无损表示的变体扩展：

保留 variant metadata

---

35. 存储

新增：

DraughtsStorage

不要继续往 "GoStorage" 塞东西。

记录至少：

class DraughtsSavedRecord {
  id;
  variant;
  record;
  kind;
  localSide;
  createdAt;
}

enum DraughtsGameKind {
  local,
  online,
}

---

36. 最近对局

Draughts 首页：

继续最近对局

显示：

规则
本地 / 联机
执棋方
手数
日期
结果

联机断线或退出后仍保留棋谱。

---

37. 规则版本

定义：

const draughtsRulesVersion = 1;

LAN 和保存格式都记录。

规则实现如果未来发生会改变合法着法的修改：

rulesVersion++

防止两个版本客户端认为同一局面具有不同合法走法。

---

38. 单元测试

每个 variant 单独测试。

目录：

test/draughts/
├── english_test.dart
├── international_test.dart
├── brazilian_test.dart
├── russian_test.dart
├── pool_test.dart
├── italian_test.dart
├── spanish_test.dart
├── turkish_test.dart
├── capture_search_test.dart
├── promotion_test.dart
├── draw_test.dart
├── notation_test.dart
├── storage_test.dart
└── lan_test.dart

---

39. 每个规则最低测试

每个 variant 至少验证：

初始布局
先手
合法普通移动
强制吃子
普通子吃子方向
王移动
王吃子
连续吃
吃子选择优先级
升王
连续吃中升王
被吃子移除时机
无棋终局
无合法走法终局
和棋
undo
序列化再恢复

---

40. Capture Search 专项测试

至少包含：

单吃
双吃
三吃
分叉吃
回转吃
飞王多个落点
同一敌子不得吃两次
最大吃子过滤
tie-break
升王后继续吃
升王后停止
延迟移除被吃子

这部分是整个 Draughts 引擎最重要的测试。

---

41. Property / invariant 测试

对所有合法 move：

applyMove(move)

必须保证：

己方棋子数量不会无故增加
对方棋子只按 captures 减少
棋盘上不会出现两个棋子同格
turn 正确切换
move path 合法
captured cell 不重复

undo 后：

position == 原始 position

---

42. LAN 测试

单进程创建：

host
client A
client B

覆盖：

握手
规则不一致拒绝
完整 move 广播
非法 move 拒绝
seq 重复
seq 跳号
连续吃原子性
悔棋
认输
和棋请求
断线
重连
stateSync

---

43. 最关键的联机回归

构造一个三段连续吃：

A → B → C → D

测试：

客户端只发送一个事件
host 只增加一次 seq
双方 moves.length 只增加 1
掉线恢复后不会出现半条路径
undo 一次撤回整个组合

---

44. 与现有 LAN 的兼容

围棋 LAN 不允许因为这次抽象而退化。

现有测试：

Go move
pass
resign
undo
score negotiation
reconnect

必须全部继续通过。

也就是说：

抽象 LAN
≠
重写 Go LAN

优先移动通用代码，保持现有行为。

---

45. 清理旧 Checkers 代码

新 Draughts 引擎完成后删除：

GameSession._setupCheckers()
GameSession._allCheckerMoves()
GameSession 中的 checkers 特判

以及：

PieceKind.checker

如果没有其他用途。

不得留下两套规则实现。

---

46. UI 命名

内部统一：

Draughts

用户界面可显示：

Checkers / 跳棋

规则页显示具体名称。

例如：

Checkers

选择规则

英式 / 美式
国际
俄罗斯
巴西
...

---

47. 默认规则

默认进入：

English / American

仅作为 UI 默认选择。

核心代码不得认为：

Draughts == English

---

48. 本地双人

本地模式：

不需要网络
不需要 authority

直接：

DraughtsSession

UI 完成一整手后：

session.applyMove(move)

---

49. 联机模式

联机模式：

UI
↓
生成完整 DraughtsMove
↓
发送
↓
Host Authority
↓
验证
↓
广播
↓
Replica

本地与联机必须使用同一个：

DraughtsMoveGenerator
DraughtsSession

禁止服务器和客户端各写一份规则。

---

50. 性能

10×10 International 的多吃搜索可能产生较多分支。

第一版优化原则：

正确性优先

但避免每次 UI rebuild 都重新完整搜索。

"DraughtsSession" 可以缓存：

List<DraughtsMove>? _legalMovesCache;

只在 position revision 改变时失效。

---

51. Position revision

加入：

int revision

每次正式：

move
undo
reset
restore

更新。

UI 的 pending path 绑定 revision。

如果期间状态变化：

清除 pendingPath

避免联机事件到达后仍操作旧局面。

---

52. UI 连续吃候选过滤

假设完整合法着法：

A-B-C-D
A-B-E-F
A-G-H

用户选择：

A → B

则 UI 只保留：

A-B-C-D
A-B-E-F

下一步目标显示：

C
E

直到：

只剩完整路径

或所有剩余 move 均在当前位置结束。

然后提交整个 "DraughtsMove"。

---

53. 动画

正式 move 到达后，可以逐段动画：

A → B
移除捕获
B → C
移除捕获
...

但：

动画 != 游戏状态

Session 应一次性完成。

UI 根据完整 move 重放动画。

---

54. 规则说明

每种 variant 提供：

DraughtsVariantInfo

包含：

名称
棋盘
普通子移动
普通子吃
王
强制吃子
升王
特殊吃子优先级
和棋摘要

避免 UI 文案散落在 Widget。

---

55. 完成后的首页结构

EasyPlay
├── Go
│   ├── 新建棋谱
│   ├── AI 对弈
│   ├── 棋谱库
│   └── LAN
│
├── Checkers
│   ├── 选择规则
│   ├── 本地双人
│   ├── LAN
│   └── 棋谱
│
└── Chess
    └── 未完成

---

56. 一次实现顺序

虽然本计划要求“一次完成”，代码提交内部仍按以下顺序施工：

1. Draughts 数据模型
2. Rules abstraction
3. Position
4. Capture search
5. Move generator
6. Session
7. 8 个 variant
8. 单元测试
9. DraughtsBoard
10. 本地双人 UI
11. Record / storage
12. LAN 通用层抽象
13. DraughtsAuthority / Replica
14. LAN UI
15. 重连 / undo / draw / resign
16. PDN
17. 完整回归
18. 删除旧 Checkers prototype

但最终合入主线时，应视为：

一个完整功能

而不是留下半成品 variant。

---

57. 验收标准

只有满足以下全部条件才算 Checkers 完成。

Rules

- [ ] English 可完整对局
- [ ] International 可完整对局
- [ ] Brazilian 可完整对局
- [ ] Russian 可完整对局
- [ ] Pool 可完整对局
- [ ] Italian 可完整对局
- [ ] Spanish 可完整对局
- [ ] Turkish 可完整对局

Moves

- [ ] 强制吃子正确
- [ ] 连续吃正确
- [ ] 多分支连续吃正确
- [ ] 最大吃子正确
- [ ] 复杂 tie-break 正确
- [ ] 短王正确
- [ ] 飞王正确
- [ ] 升王正确
- [ ] 连续吃中升王正确
- [ ] 捕获移除时机正确

Game

- [ ] 本地双人完整可玩
- [ ] Undo 撤回完整一手
- [ ] 认输
- [ ] 和棋规则
- [ ] 和棋协商
- [ ] 游戏结束判定

Storage

- [ ] 自动保存
- [ ] 恢复后局面完全一致
- [ ] variant 保存正确
- [ ] rulesVersion 保存正确
- [ ] 历史棋谱可打开
- [ ] PDN 基础导入导出可用

LAN

- [ ] 创建 Draughts 房间
- [ ] 加入房间
- [ ] variant 不一致拒绝
- [ ] rulesVersion 不一致拒绝
- [ ] 普通移动同步
- [ ] 多段连续吃作为单事件同步
- [ ] 非法 move 不改变状态
- [ ] seq 正确
- [ ] Undo 正确
- [ ] Draw 正确
- [ ] Resign 正确
- [ ] 断线恢复
- [ ] stateSync 后双方完全一致
- [ ] 无半手棋状态

Regression

- [ ] 围棋本地功能不受影响
- [ ] KataGo 不受影响
- [ ] 围棋 LAN 不受影响
- [ ] Web 构建通过
- [ ] Android 构建通过
- [ ] "dart analyze lib test" 通过
- [ ] "flutter test" 全绿

---

58. 不允许的妥协

为了避免重新变成原型，以下情况不能作为完成：

只实现单跳
只实现 English
连续吃让 UI 自己处理
LAN 每跳发一个消息
用 if variant == ... 堆规则
把 Draughts 继续塞进 GameSession
先做八个空 variant 名称但规则实际共用
和棋规则全部统一成一个计数器
省略飞王路径分支
省略 Italian 等优先级规则

---

59. 最终架构

                     EasyPlay
                        │
                  Draughts UI
                        │
                 DraughtsSession
                        │
              DraughtsMoveGenerator
                        │
             DraughtsCaptureSearch
                        │
                  DraughtsRules
                        │
       ┌────────────────┼────────────────┐
       │                │                │
    English       International       Turkish
       │                │                │
      ...              ...              ...

联机：

Draughts UI
    ↓
完整 DraughtsMove
    ↓
LanTransport
    ↓
DraughtsAuthority
    ↓
DraughtsSession
    ↓
验证成功
    ↓
Committed Event + seq
    ↓
双方 Replica

无论：

本地
联机
恢复棋谱
重连 stateSync

最终都只使用同一套：

DraughtsRules
DraughtsMove
DraughtsSession

---

60. 完成定义

Checkers / Draughts 功能完成时，EasyPlay 应达到：

«用户可以选择主要 Draughts / Checkers 规则，在 8×8 或 10×10 棋盘上进行规则正确的本地或 LAN 对局；所有连续吃子均作为完整的一手处理；规则、存档、重连与双方状态使用同一个权威规则核心，不依赖 AI，也不存在某个特定 Checkers 变体被硬编码为整个游戏的情况。»

这才算从当前的 Checkers prototype 正式升级成 EasyPlay 的多规则 Draughts 功能。
