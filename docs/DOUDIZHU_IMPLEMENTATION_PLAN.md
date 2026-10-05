# EasyPlay 三人斗地主一次性实现计划

**状态：已完成；规则、AI、三人联机、隐私和 Android / Web 构建验收通过**
**目标文件：** docs/DOUDIZHU_IMPLEMENTATION_PLAN.md  
**仓库：** chorusfruit-233/easyplay  
**制定时检查基准：** main @ 0446eca184020cda165ea5b042f9421372d4fc12（v1.5.1）  
**定位：** 无真钱、无充值、无兑换的休闲卡牌对战；打开即玩，结束即可退出。

## 1. 一次性完成范围

新增第六种游戏：经典三人斗地主。最终一次性交付：

- 经典 54 张牌三人规则，17×3 + 3 张底牌。
- 发牌、叫分确定地主、地主取得底牌、地主先出。
- 全部常用牌型识别、压牌、不要、回合重置和胜负判定。
- 单人对战（1 真人 + 2 本地 AI）。
- 三名真人局域网对战，Android 房主及 Android / Web 加入。
- 三名真人浏览器 WebRTC 对战，复用现有手动 Offer/Answer / STUN。
- 两名真人 + 一名主机托管 AI 补位。
- 同机三人模式，交接设备时先遮挡前一位玩家的手牌。
- 私有手牌和公共状态严格分离；按座位认证、按座位同步。
- 房间内断线重连、重新发牌和再来一局。
- Android / Web 手机布局、出牌选择、提示及明确状态反馈。
- 全量单元、集成、真实网络和浏览器回归测试。

**不做：** 充值、下注、提现、兑换、真钱或虚拟货币结算、排行榜、云端账号、自动匹配服务器、广告/商业化逻辑、长期牌谱库及历史对局持久化。叫分只用于选出地主，不建立金钱/积分结算体系。

完成前不得以只有本地规则、却缺少三人联机或私有信息隔离的半成品宣告交付。

## 2. 当前仓库与复用边界

已存在的五种独立棋类：Go、Chess、Draughts、Gomoku、Xiangqi。当前 lib/lan/ 有：

- RoomCoordinator：双人座位、房主权威提交、事件序列、重连、协商。
- LanMessage、MessageTransport、MemoryTransport：通用消息传输基础。
- LAN WebSocket、局域网发现、/easyplay/probe、Android 内置 Web 客户端。
- rtc_room.dart / rtc_manual_signaling.dart / rtc_transport_web.dart：双人 WebRTC 手动信令、DataChannel。
- rtc_framing.dart：分片、完整性、流量控制等机制。
- 原有 AI / UI / 测试 / Pages / APK 打包工作流。

**不能直接复用双人房间的身份模型：**

~~~dart
enum Side { black, white }
~~~

当前 RoomCoordinator.startMatch() 和多个 UI 明确检查 playerCount == 2，座位通过 firstSide.opponent 分配；RtcRoom 当前只有一个远端 peer。给 Side 生硬增加第三个值会破坏棋类语义和既有测试。

斗地主另建三人 CardRoomCoordinator，但继续复用 MessageTransport、底层 WebSocket、WebRTC DataChannel、心跳、分片及部署设施。若抽出真正通用的身份/连接小组件，应保持现有二人 RoomCoordinator 对外兼容。

**更重要：** 现有棋类可向双方同步完整公开棋局的 event log；斗地主有隐藏手牌，不能原样转发权威原始事件日志或随机洗牌种子。

## 3. 固定玩法与规则版本

第一版固定一种经典三人规则集，明确 rulesVersion=1；不开放地方变体、抢地主、明牌、加倍等扩展。

- 一副 54 张牌，包含大小王，卡牌 ID 唯一。
- 每人发 17 张，剩下三张底牌在地主确定前不公开。
- 按固定座位顺序叫分，可不叫或叫出严格高于当前最高的 1/2/3；叫到 3 时立即确定地主。
- 三人均不叫：重新洗牌、发牌并重新进行叫分；保留房间及三座位。
- 地主取得三张公开底牌，持有 20 张并首先出牌；两名农民各 17 张。
- 出牌按固定座位环序，需出合法牌型并压过上一手，或在允许时选择不要。
- 领先者（新轮次首次出牌）不能不要；其他两位依次不要后，上一手出牌者获得新一轮领出权。
- 地主先出完：地主胜。任意农民先出完：农民阵营共同获胜。立即终局。
- 无下注、倍率、金钱/代币结算；叫分只作选地主流程。
- 规则边界需在 DouDizhuRules 中显式固定，例如：飞机翅膀可否使用重复点数、四带二的附件约束、主体中哪些牌可连续、王炸大小、炸弹能否压非炸弹，不能依 UI 分支隐式决定。

## 4. 数据模型

新增 lib/doudizhu/，采用专属座位和阶段模型，不复用棋类 Side：

~~~dart
enum PlayerSeat { seat0, seat1, seat2 }
enum DouDizhuPhase { waiting, dealing, bidding, playing, finished }
enum DouDizhuTeam { landlord, farmers }

enum CardSuit { spade, heart, club, diamond, joker }

class PlayingCard {
  final int id; // 0..53，实体唯一
  final int rank;
  final CardSuit suit;
}

class CardPlay {
  final PlayerSeat seat;
  final List<int> cardIds;
}
~~~

在规则模型中区分：完整权威 DouDizhuSession、公共 PublicGameState、具体座位的 DouDizhuPlayerView；不让 Replica 直接持有完整 Session。

- 权威层保存三人的牌、底牌、叫分记录、轮到谁、上家牌型、连续不要次数、赢家与本局阶段。
- 公共层仅包含可公开的出牌、剩余张数、已公开底牌、地主身份、轮次和阶段。
- 每位玩家视图额外包含自己的完整手牌，绝不包含其余玩家的未公开牌 ID。
- Card ID 必须保证本局 54 张不重复；发牌、出牌、回收及重发时校验守恒。

## 5. 牌型识别与比较

独立实现：

~~~dart
PlayPattern? classifyPlay(List<PlayingCard> cards);
bool canBeat(PlayPattern candidate, PlayPattern previous);
List<CardPlay> legalPlays(List<PlayingCard> hand, TrickState trick);
~~~

第一版支持：单牌、对子、三张、三带一、三带二、单顺（至少 5 张）、连对（至少 3 对）、连续三张（飞机无翅膀）、飞机带单、飞机带对、四带二单、四带两对、四张炸弹、大小王王炸。

标准化 PlayPattern 字段：type、mainRank、sequenceLength、totalCards；必要时还需主体与附件的结构信息。连续主体不能包含点数 2 或大小王；只对规定的同类型、同张数、同主体长度进行常规大小比较。炸弹、王炸走明确的跨类型比较路径。

**防止贪心拆牌误判：** 一组选牌可能存在多个主体候选，识别器应按牌型规则枚举并验证候选主体与附件，而不是只取第一组连续三张。为同一批牌的多种潜在拆分建立测试。

不得写成依赖卡牌当前 UI 排序的比较函数。

## 6. 对局状态机与操作校验

~~~text
waiting (3 seats ready / AI fill)
  → dealing (安全洗牌、每人私发 17 张、底牌保密)
  → bidding (轮流叫分/不叫)
      ├─ 全员不叫 → 新一轮 dealing
      └─ 叫分结束 → 确认地主，公开底牌并仅加到地主手牌
  → playing (地主首次领出)
      ├─ 合法出牌、不要、两次不要后新轮次
      └─ 任一玩家手牌清空 → finished
  → rematch / close
~~~

必须验证：

- 当前阶段、当前座位、请求者认证身份、牌的所有权和唯一性。
- 叫分严格递增且符合当前回合。
- 不可重复出牌、不可提交未拥有的牌、不能在领出时不要。
- 非法出牌或过期 seq 不改变任何手牌、阶段或计数。
- 两次连续不要后，轮到上一手出牌者重新领出。
- 胜负一旦产生，不接受后续出牌或叫分。

房主采用 Random.secure() 或平台上等价的安全随机源生成洗牌；**绝对不公开完整排列、种子或未揭示底牌**。这只保证常规随机性和客户端信息隔离，不构成对恶意房主的密码学公平发牌证明。

## 7. 隐藏信息安全边界

斗地主不能通过“广播完整局面、UI 再隐藏”的方式实现。

~~~text
DouDizhuAuthority（房主）
  ├─ 公共状态 → 三名玩家
  ├─ seat0 手牌 → 仅 seat0 经认证连接
  ├─ seat1 手牌 → 仅 seat1 经认证连接
  └─ seat2 手牌 → 仅 seat2 经认证连接
~~~

建议事件类别分成公共事件和面向座位的私有消息。私有消息不得被公共 event log、rejected 的错误详情、调试日志、房间 probe、邀请文本、stateSync 广播间接泄漏。

- 主机权威记录可包含完整牌局，但仅保留在当前房间内存，不直接序列化广播。
- 客户端不获得完整牌堆、其他人初始/当前手牌、隐藏底牌或洗牌种子。
- 同一公开提交 seq 的私有牌视图与公开快照必须一致；重连采取认证后按座位生成的原子快照（公开局面 + **自己的当前手牌** + phase/turn/negotiations + snapshotSeq），再接收后续事件，不能对已经是当前手牌的快照再次重放扣牌。
- 所有发送前按收件人做显式投影，避免把整份 Authority event log 放入 stateSync。
- 每个座位有独立高熵、绑定房间的 resume credential；不能仅凭客户端提交 seat0/seat1/seat2 夺取其他人的座位。
- 断线不等于认输；已占座位可按认证机制恢复。
- 房主因为需要完整发牌权威状态，技术上能够检查所有手牌。第一版明确采用熟人房间的信任模型，不宣称恶意房主也无法作弊。

## 8. 三人房间架构

新增：

~~~text
lib/doudizhu/multiplayer/
├── doudizhu_authority.dart
├── doudizhu_replica.dart
├── card_room_coordinator.dart
├── private_state_sync.dart
└── card_room_protocol.dart
~~~

共享已有 MessageTransport、WebSocket socket adapter 和内存传输；不要将 CardRoomCoordinator 强制塞入 Side.opponent 模型。

CardRoomCoordinator 负责：

- 3 个固定 seat、身份凭据、人数、ready、房间阶段。
- 可配置的人类 / AI 占位；AI 是房主本地参与者，不占一条伪装真人的网络连接。
- 请求验权、权威序列分配、公共广播及定向私有消息。
- 断线、重连、心跳、3 人房间满员、托管 AI / 真人角色对应。
- startMatch 要求座位全部就绪；2 真人 + 1 AI 时 AI 座位自动 ready。
- 再来一局保留房间与身份，重新洗牌清空上一局私有数据。

接口设计尽量让双人 RoomCoordinator 完全保持行为与旧协议兼容。斗地主网络消息最好有独立 game='doudizhu' / rulesVersion=1 / protocolVersion，复用底层 transport，不依赖棋类 Side。

## 9. LAN Android / Web 客户端

支持 Android 房主创建三人 WebSocket 房间、扫描、手动地址、网页快捷加入与内置 Web 客户端。probe 返回 game=doudizhu、players 及 maxPlayers=3、phase，不返回私有状态。

现有快捷加入、扫描与前端路由需增加斗地主类型，不允许把它当围棋默认房间。

Web 浏览器不必充当 LAN 监听服务器；与现有玩法一样可加入 Android 房间。原棋类双人房间不改变人数限制和协议行为。

## 10. 三人 WebRTC：房主星形拓扑

当前 RtcRoom 只有一个 peer；斗地主不能直接用单 peer 房间作为三人连接。

采用：

~~~text
                 Host（房主 + Authority）
                    /             \
        RTCPeerConnection 1   RTCPeerConnection 2
                  /                 \
               Guest B             Guest C
~~~

客人与客人无须直接建立一条额外连接。房主分别生成两套有独立 token/sessionId 的 Offer，分别接收 Answer；每条连接映射到具体 seat；双方连接到房主后才开始发牌。

复用现有 RtcPeer、可靠有序 DataChannel、rtc_framing 分片、STUN 配置、手动信令及生命周期管理。新增三人房间的邀请管理，不修改现有双人 RtcRoom 的固定 firstSide / firstSide.opponent 逻辑。

- 仅当三座位就绪才允许开始（或 2 真人 + AI 补位模式）。
- 断线时仅对应 peer 重新交换邀请，其他连接可继续存活；房主保留权威内存状态。
- 重连须重新验证该座位专属身份，再定向同步自己的牌。
- 房主关闭页面 / App 后，内存房间消失；不宣称跨房主无服务器接管能力。
- 没有 TURN 时部分跨网环境仍可能无法连接；保留连接失败与重试提示。
- WebRTC SDP / 邀请文本不包含洗牌信息、手牌或服务端权威事件日志。

## 11. AI（Dart，本地，无外部模型）

斗地主不同于 Chess，不引入 Stockfish 类外部引擎。使用 Dart 规则驱动的启发式 AI，Android/Web 同构运行。

~~~text
lib/doudizhu/ai/
├── doudizhu_ai.dart
├── bidding_policy.dart
├── hand_evaluator.dart
├── legal_play_generator.dart
└── team_policy.dart
~~~

分层：LegalPlayGenerator 枚举合法牌型组合；BiddingPolicy 根据本方手牌给出叫分；HandEvaluator 评估手牌拆组成本；PlayEvaluator 评估出牌和要不要；TeamPolicy 区分地主与两名农民的共同获胜目标；DouDizhuAi 选择动作。

**AI 只能接收它所属座位的 PlayerView、公开已出牌和公开剩余张数，不读取其他座位在 Authority 内存里的私有手牌。** 单人模式即使完整发牌状态同在进程，也需通过受限视图注入 AI。

模式：

- 单人：1 真人 + 2 AI。
- 真人三人：3 个独立客户端。
- 混合：2 真人 + 1 房主托管 AI。
- 同机三人：轮流交接设备；显示遮挡确认页后才切换当前手牌。

搜索预算有上限，可取消、可防旧回合异步结果污染新局；不把全部组合搜索阻塞在 Flutter UI 帧上。只提供出牌提示，不提供对其他人隐藏手牌的“分析”。

## 12. UI 与交互

新增：

~~~text
lib/doudizhu/widgets/
├── doudizhu_home_page.dart
├── doudizhu_game_page.dart
├── doudizhu_hand.dart
├── doudizhu_card.dart
├── bidding_panel.dart
└── doudizhu_lobby_page.dart
~~~

新增 GameType.doudizhu 及首页入口，保留原有五种棋类入口。Material 主题统一；牌面与牌背可用 Flutter 自绘、无外部图片依赖。

手机竖屏首要布局：

~~~text
┌──────────────────────────────┐
│ 玩家 B  剩余12    玩家 C 剩余9 │
│                              │
│       桌面公开出牌区域         │
│       当前回合与叫分状态       │
│                              │
│     [提示] [不出] [出牌]       │
│                              │
│      自己的 17~20 张手牌       │
└──────────────────────────────┘
~~~

手牌重叠排布、拖动/点击选中、选中上抬、撤销选中、按点数/花色排序、叫分弹层、非法牌型原因提示、可见的剩余牌数和地主标识、屏幕窄时避免溢出。实际 UI 输入统一使用卡牌唯一 ID，而非当前排序下的下标。

同机三人：切换玩家时先遮挡上一位手牌，下一位确认后再显示其专属视图。

## 13. 对局记录与隐私

不实现长期牌谱库，不保存完整对局记录到 SharedPreferences、文件或数据库。房间存活期间权威层可以保留内存事件和私有状态供规则、AI 与重连使用；房间关闭必须清空。调试日志不得记录完整牌组、私有凭据、隐藏底牌或 SDP。

## 14. 测试

建议新增：

~~~text
test/doudizhu/
├── deck_test.dart
├── pattern_classifier_test.dart
├── play_comparator_test.dart
├── legal_plays_test.dart
├── bidding_test.dart
├── session_test.dart
├── trick_test.dart
├── team_result_test.dart
├── player_view_privacy_test.dart
├── authority_test.dart
├── reconnect_test.dart
├── ai_test.dart
├── local_ui_test.dart
├── lan_test.dart
└── rtc_test.dart
~~~

强制验收：

- 一局洗牌分牌恰有 54 个唯一 ID，三手 17、底牌 3；地主最终 20。
- 所有牌型与边界案例、复杂飞机拆分、炸弹与王炸比较。
- 当前座位、牌的所有权、重复 ID、规则非法着都被拒绝，拒绝不推进 seq。
- 叫分严格递增、叫 3 即结束、全部不叫重发牌；轮到地主先出。
- 首手不能不要；连续两人不要后，上一出牌者重新领出。
- 地主手牌清空与任一农民手牌清空的阵营判定。
- 通过**直接检查序列化后的每名客户端网络消息**确认不泄漏其他人的私有手牌 / 底牌 / 洗牌种子；不能只做 UI 视觉隐藏测试。
- 3 人同场 LAN 与 WebRTC、2 真人+AI、私有快照认证、断线重连、再来一局。
- seat 凭据冒用/重放、过期请求、跨房间请求、错误人数等异常路径。
- AI 未拿到其他玩家隐藏信息；停止、重开、退出时无过期动作。
- 现有五游戏的双人 LAN / WebRTC、围棋分析、所有 AI 与 UI 测试无回归。

浏览器 smoke 要实际建立房主到两名远端的 DataChannel，测试定向私有发牌、公开出牌、重连后视图一致。既有 WebRTC/browser smoke 不得被改为只测斗地主。

## 15. 工程实施顺序（整体一次交付）

1. 卡牌/座位/阶段模型；固定规则 profile。
2. 洗牌、发牌、叫分状态机。
3. 牌型 classifier、comparison、legal play generator。
4. Session、出牌流转、终局、不变量与规则测试。
5. PublicGameState / PlayerView 与按座位私有消息投影。
6. Dart AI、单人模式和交接遮挡的同机三人。
7. CardRoomCoordinator、三人认证、公开/私有 seq 同步。
8. Android LAN 建房、发现、手动/网页加入。
9. 三人 WebRTC 房主双 peer、邀请/回应及重连。
10. 完整响应式出牌 UI、提示、叫分/终局/再来一局。
11. 隐私/协议异常/真实浏览器与 Android/Web 回归测试。
12. CI、Pages、内置 LAN Web、APK 构建验收与文档更新。

建议按此顺序内部施工，但用户可用的最终版本应整体交付，不把缺失隐私隔离的联机原型投入正式发布。

## 16. CI 与完成定义

继续执行：

~~~sh
dart analyze lib test
flutter test
flutter build web --no-wasm-dry-run
python3 tools/package_lan_android.py --debug
~~~

另新增斗地主专属牌型性质测试、三人 LAN 集成测试、三人 RTC 真实浏览器 smoke。构建时保持原有五棋种及 KataGo / Stockfish / Pikafish 资源不受影响。

**完成定义：** 用户在 Android 或 Web 打开斗地主，可与两名本地 AI、两名真人或一名真人加一名 AI 完成一局经典三人斗地主。房主权威校验每个动作，三个玩家各自只收到有权查看的牌，网络掉线后凭座位身份恢复正确私有视图；结束后不保存历史牌谱，不引入下注或货币结算，也不破坏原有双人棋类系统。

## 17. 实现与验收记录（2026-10-04）

完整实现与使用说明见 [斗地主说明](DOUDIZHU.md)。规则、Session、受限玩家视图、AI、三人房间、LAN、双 peer WebRTC、同机遮挡及响应式界面均已接入首页；原有双人棋类房间保持独立。

使用与 CI 一致的 Flutter 3.44.0 验证：

- `dart format lib test` 与 `dart analyze lib test` 通过，无静态问题。
- 全量 `flutter test`：566 项通过，包含原生 Stockfish / Pikafish smoke，无跳过项。
- 斗地主及快捷加入针对性测试：46 项通过，包括真实三人 WebSocket、私有消息投影、认证重连、非法请求不改变权威状态及完整 AI 对局。
- 三个独立 Chromium 上下文建立两条真实 DataChannel，完成私有发牌、公开出牌、单客人重连、终局、再来一局和两名真人加 AI 对局；实际大厅完成两套邀请/回应交换、开始、叫分和选牌出牌，横竖屏无布局异常。
- 原有棋类 WebRTC transport / 大厅 smoke、Stockfish / Pikafish 浏览器 Worker、固定亚洲规则 C++ 对照均通过。
- 产品 Web 构建及 `python3 tools/package_lan_android.py --debug` 通过；APK 包含更新后的内置 LAN Web 客户端，产物为 `build/web/` 与 `build/app/outputs/flutter-apk/app-debug.apk`。

三人浏览器 smoke 已加入 CI；测试桥接与网络消息捕获仅用于测试，不随产品构建发布。房间与私有牌保留在内存，退出清空；联网限制与房主信任边界在使用说明中明确。


## 18. PR 审查与 v1.6.0 发布验证（2026-10-05）

PR #5 经审查修复后合并：

- WebRTC 重新生成邀请时先释放旧座位，双人和三人房间均支持可靠重连，第三位玩家连接保持有效。
- 准备操作校验序列号，创建房间等待房主准备确认后再允许配置 AI；退出大厅时清理尚未完成的建房资源。
- 客户端先验证完整快照，再原子更新公开状态与私有手牌；校验欢迎消息座位、卡牌范围和唯一性、公共牌数守恒及胜负结果。
- 修复畸形邀请类型、加入失败后凭据保留、HTTPS 快捷加入及提示异常反馈。

最终 PR CI 全部通过：577 项测试（包含原生 Stockfish / Pikafish）、原有 14 种棋类规则的 WebRTC 回归、三人斗地主完整对局/重连/再来一局/混合 AI/真实大厅操作、主题测试，以及 Web 和内置 LAN Web 的 Android APK 构建。本地通过 575 项测试，另外两项原生引擎测试由 CI 验证。按用户要求跳过真机安装和操作验证。
