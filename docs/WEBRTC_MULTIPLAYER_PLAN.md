# EasyPlay Web ↔ Web WebRTC 联机实施计划

> 状态：Phase 0 与 Phase 1 无服务器 MVP 代码及本地回归已完成；正式 Pages/跨设备验收待部署，Cloudflare 阶段按用户确认延后。基于 2026-10-01 的 `main` 仓库结构和公开平台文档。
> 实施与使用说明：[WEBRTC_MULTIPLAYER.md](WEBRTC_MULTIPLAYER.md)。
> 部署约束：**不购买 VPS，保留现有 GitHub Pages**。首个可用版本不依赖自有后端；自动信令和可靠跨网连接作为后续增强。  
> 范围：围棋、国际象棋、全部现有八种 Draughts/Checkers 变体，双人 Web ↔ Web 对局。**不替换、不破坏 Android 房主的现有 LAN/WebSocket 方案**。

## 1. 目标与非目标

### 1.1 目标

- 两个从 GitHub Pages 打开的浏览器通过 `RTCPeerConnection + RTCDataChannel` 对弈。
- 玩家可在 Web 端建房或加入；房主浏览器持有权威棋局，对手提交请求，房主校验后广播已提交事件。
- 复用现有 `LanMessage`、`LanAuthority`、`ChessAuthority`、`DraughtsAuthority` 及对应 Replica；避免另一套规则或结果计算逻辑。
- 保留局域网 WebSocket 模式；WebRTC 作为新的「浏览器点对点联机」入口。
- 无后端 MVP：通过复制/粘贴 Offer 和 Answer 完成一次性手工信令，公共 STUN 辅助直连。
- 增强版：Cloudflare Worker + Durable Object 自动信令；Cloudflare Realtime TURN 作为直连失败时的可选中继，**不自建 Coturn**。
- 遵守现有联机约束：局内禁用 AI；悔棋、提和、认输、围棋计分协商、再来一局均走已有权威协议。

### 1.2 非目标

- 不做视频、语音、聊天、公开匹配大厅、观战、排名或服务器托管的比赛。
- 不承诺「仅用 STUN，任何两张网络都能连通」；复杂 NAT、防火墙可能需要 TURN。
- 不承诺房主关闭页面后由客人接管权威；主机切后台可能被冻结，浏览器刷新会使内存中的房间丢失。
- 不把 Cloudflare Worker / TURN 当作游戏规则裁判：Worker 只交换信令和签发受控临时凭据。
- 初版不扩展 Android ↔ Web 的 WebRTC；原 Android LAN 模式照常工作。

## 2. 现有仓库基线（实施前确认）

| 位置 | 当前实现 | 需修改之处 |
| --- | --- | --- |
| `lib/lan/lan_transport.dart` | 条件导出 IO/Web 传输 | 保持 LAN 出口，另加 RTC 出口 |
| `lib/lan/lan_transport_io.dart` | `HttpServer`、WebSocket、`_LanPeer`、房主认证/广播/定时器 | 抽出可复用的房间权威控制器，不改变旧模式的外部行为 |
| `lib/lan/lan_transport_web.dart` | WebSocket 客户端；Web `LanHostServer.start()` 不支持 | 保留；新建独立 WebRTC Host/Guest，而非把 WebSocket 改名 |
| `lib/lan/lan_protocol.dart` | `lanProtocolVersion = 3`，JSON/seq、握手、状态同步、再来一局消息 | 先原样复用；新增分片应放在传输封装层 |
| `lib/lan/lan_game.dart` | 围棋权威与 Replica | 直接复用 |
| `lib/lan/chess_lan_game.dart` | 国际象棋权威与 Replica | 直接复用 |
| `lib/lan/draughts_lan_game.dart` | Checkers 权威与 Replica | 直接复用八种变体 |
| `lib/lan/lan_page.dart` | 围棋 LAN 建房/加入入口 | 新增 RTC 入口/共用页面组件 |
| `lib/chess/widgets/chess_lan_pages.dart` | Chess LAN 入口及等待页面 | 接入 RTC 模式 |
| `lib/draughts/widgets/draughts_lan_pages.dart` | Draughts LAN 入口及等待页面 | 接入 RTC 模式 |
| `web/index.html`、`web/coi-serviceworker.js` | Pages base href 与 KataGo 跨源隔离 | 保留；重点做 RTC/信令的跨浏览器回归 |

当前 `LanHostServer` 同时承担监听、身份绑定、房间人数、心跳、协商超时、权威提交和广播，不宜复制一份 Web 版后继续发散；**将无关传输的部分抽成共用 `RoomCoordinator` 是关键结构性工作**。

## 3. 网络拓扑与部署阶段

### A. 无服务器 MVP（必须首先完成）

```text
GitHub Pages (只提供静态 Web)
        │
        ├── 浏览器 A：创建 RTC Offer，等待 ICE gathering 完成
        │       │
        │       └── 玩家通过私密渠道分享完整邀请信息
        │
        └── 浏览器 B：导入 Offer，创建 Answer，等待 ICE gathering 完成
                │
                └── 玩家把完整回应交还浏览器 A

    RTCDataChannel (优先直连；STUN 辅助发现候选)
                │
      浏览器 A 内存中的权威对局
```

- 公共 STUN 默认采用国内候选 `stun:stun.miwifi.com:3478` 与 `stun:stun.hitv.com:3478`；可切换国际服务或自定义多地址。部分服务超时不丢弃已取得的映射候选，全部不可用时明确提示切换服务。
- 采用 non-trickle 手工信令：`setLocalDescription()` 后等待 `iceGatheringState == complete`，再导出最终 `localDescription`；提供超时/取消，不无限等待。
- Offer/Answer 容器需带 `formatVersion`、`sessionId`、`createdAt`、`game`、`variant/rulesVersion`（适用时）、`description.type` 和 `description.sdp`；校验大小、版本、过期时间与字段类型。
- 手动邀请内容可能包含连接候选和网络元数据；UI 告知只与对手私下分享，不自动发表或记录到日志。它不是短房间码，也不保证首次连接成功。
- MVP 可在同网和部分跨网环境成功；直连失败要结束握手并显示「当前网络无法直连，可稍后启用 TURN」，不能假装连接成功。
- 阶段 A 不需要开通 Cloudflare Workers、Realtime 或新增自己的 API。

### B. 自动信令（MVP 验收后）

```text
EasyPlay GitHub Pages ── WSS/HTTPS ── Cloudflare Worker
                                           │
                                           └── Durable Object / 每房间一个协调实例
                                                (房间/座位、Offer/Answer/ICE)
           浏览器 A ◄────── RTCDataChannel ──────► 浏览器 B
```

- Worker 仅负责创建房间、鉴权、转发 SDP/ICE、入房人数限制、失效清理；**不转发棋局走子**。
- 推荐使用 Durable Objects 的 WebSocket Hibernation API；支持房间级单写者、两人配对、断开后恢复信令，避免普通常驻 WebSocket 的空闲计费。
- SQLite-backed Durable Objects 在当期 Workers Free 计划中可用；实际账户额度、服务可用性及是否需要验证，以部署时控制台为准。
- 公共房间标识与私密邀请凭据分离：随机生成高熵 token（浏览器安全随机数），不沿用 LAN 的四位口令。邀请链接尽可能放入 URL fragment，避免直接落入静态站点请求路径；信令请求仍需显式提交凭据。
- 最多两名参与者；房主创建后拥有独立 host 身份，客人持独立 guest 身份和重连令牌。重复加入、冒用角色、第三人入房必须被拒绝。
- 信令消息可定义 `create`、`join`、`offer`、`answer`、`ice`、`ready`、`leave`、`resume`、`error`；带 `sessionId`、版本、有限长度和必要的幂等 ID。
- Worker 对创建/加入/发送信令做速率与尺寸限制、TTL 清理和 Origin 校验；Origin/CORS **不能代替**实际身份鉴权。
- Worker/DO 重启或休眠后，仅恢复必要的房间/身份/信令状态；不要默认承诺恢复浏览器已消失的权威棋局。

### C. 托管 TURN（可靠跨网增强）

- 使用 Cloudflare Realtime TURN，不购买 VPS、不运行 Coturn。
- 长期 TURN Key ID/API Token 仅放在 Worker Secrets；**绝不能提交 Git、放进 Pages 的 Dart/JS、拼进邀请链接或直接发给浏览器**。
- Worker 验证已经加入的房间和角色后，调用 Cloudflare 官方 `generate-ice-servers` 接口，返回有 TTL 的 `iceServers`；限制签发频率、并发和房间生命周期。
- ICE 优先 `iceTransportPolicy: all`，让浏览器使用可用的直接连接；只有专门测试中继时临时设为 `relay`。
- 正式配置 UDP TURN、TCP TURN 与 TLS TURN 备用地址；动态使用 Cloudflare 返回的 URL/username/credential，而不是前端写死密码。
- 设定凭据有效期，长局或重新协商前按需重新签发，并通过 `RTCPeerConnection.setConfiguration()` 更新。
- Cloudflare Realtime 当前公开说明：STUN 免费；Realtime SFU 与 TURN **共享**月度免费流量额度，而非两份独立额度。价格、配额、账户要求与服务区域在部署时再次核实；设置用量/预算提醒。不能把「免费额度」解释为永不收费或保证服务可达。

## 4. 客户端与权威架构

### 4.1 两层接口，不复制规则

推荐分离：

```text
UI (Go / Chess / Draughts)
           │
   OnlineRoom / MatchClient
           │
   ┌───────┴─────────────────────┐
   │                             │
RoomCoordinator             MessageTransport
(权威/座位/定时器/seq)        ├── WebSocket (旧 LAN)
   │                         └── RTCDataChannel (新)
   ├── LanAuthority / LanReplica
   ├── ChessAuthority / ChessLanReplica
   └── DraughtsAuthority / DraughtsLanReplica
```

- `MessageTransport` 提供连接状态、`Stream<LanMessage>`、`send()`、`close()`；内部负责 JSON 编解码、数据分片与背压。
- `RoomCoordinator` 复用服务器端已有的 `acceptsHello`、座位分配、`startMatch`、`sync`、`submit`、`_broadcast`、协商 30 秒定时器与心跳；不要新实现一套规则判定。
- Browser Host 创建 Authority，并建立**本地 Replica**；本机也从「已提交事件」更新 UI，不通过用户点击直接越过 Authority 修改棋局。
- 对方 DataChannel 经房间握手绑定为 guest side。提交调用 `submit(authenticatedSide, message)`；消息里的 `side` 只供核验，绝不授予身份。
- 保持各变体已有的房主先手逻辑：Chess 白方先手、Draughts 使用 `rules.firstMove`；围棋维持现有房间设定。
- 若现有协议字段足以兼容，`lanProtocolVersion=3` 不因更换底层传输而无谓升级；确实新增有线语义时才升级版本并加兼容性测试。
- 联机状态禁止启动 KataGo、Stockfish 或未来的 Checkers AI；对局结束后才允许正常复盘分析。

### 4.2 WebRTC 通道

- 房主调用 `createDataChannel('easyplay-game', {ordered: true})`，另一端通过 `ondatachannel` 接收；采用默认可靠重传，不设置 `maxRetransmits=0` 或很短的 `maxPacketLifeTime`。
- DataChannel `open` 后才开始 `hello` / `helloAck` / `stateSync`；`connected` 不等同「已经完成握手且棋局可操作」。
- UI 记录 `connectionState`、`iceConnectionState` 和 DataChannel 状态：等待邀请、正在协商、连接中、握手/同步、对局中、重连中、已断开。
- 继续使用 `LanMessage.encode()/decode()`，但不能直接把一次可能数 MB 的 `stateSync` 送入一个 DataChannel `send()`。
- 在传输层添加带 `transferId`、`index`、`total`、`byteLength`、校验摘要的分片封装；按 UTF-8 **字节数**分片，目标载荷 ≤ 16 KiB，并受 `pc.sctp.maxMessageSize`（及必要保守限额）约束。
- 接收端只在分片完备、顺序/长度/校验正确、未超限时交给 `LanMessage.decode()`。限制未完成传输的数量、总内存及超时；错误时丢弃整组并主动请求重同步。
- 实现 `bufferedAmount` / `bufferedAmountLowThreshold` 背压与发送队列，避免大同步包阻塞实时控制消息；正常走子走小消息优先通道或调度优先级。
- 原协议现有 `lanMaxEvents=20000`、`LanMessage.decode` 4 MiB 上限继续适用；如果同步设计真的需要调整，要独立评审资源限制，不可悄悄移除上限。

### 4.3 重连与权威生命周期

- Host 保持在线时：双方重新协商/必要时 `restartIce()`，重建 DataChannel，按受认证的 session/role 恢复位置，重用现有 `stateRequest` / `stateSync` 校准 seq。
- **不能只信任客户端给的 `resumeSide`**；必须用入房时签发并保护的重连身份验证。
- Host 刷新、关页、崩溃、长时间被系统冻结：MVP 明确提示房间已不可用；不能宣称 guest 能自行变更为权威或无损续局。
- 如需未来恢复 Host，可额外设计版本化本地快照、完整事件日志和恢复授权，并写单独计划；不得在这一期暗中扩大目标。
- ICE/TURN 失效时，显示明确可操作的错误；不能将网络断连解释成玩家认输，也不能单方面判胜。

## 5. 页面与用户体验

- 三种游戏原 LAN 入口继续存在；另加「浏览器点对点联机（WebRTC）」创建/加入。
- MVP 建房：显示「复制邀请信息」；加入：输入邀请，显示「复制回应信息」；房主导入回应；显示 ICE/通道/握手状态、可取消与重试按钮。
- 手动邀请与回应文本加格式/长度校验和版本说明，支持一键复制/粘贴；不强求塞入短二维码。
- 自动信令阶段改为「复制邀请链接 / 输入房间码」；保留手动信令作为无服务后备入口。
- 与现有棋局页面共用 `LanMatchPage`、`ChessGamePage.online`、`DraughtsLanMatchPage` 的消息和交互逻辑；优先抽共用控制器，避免复制整个 UI。
- 房主等待 2/2 后手动开始；对手中途退出显示断线并保留界面；原再来一局不重新创建 PeerConnection（正常保持通道并复用事件协议）。
- 对用户只显示必要连接状态；诊断页可区分直连和 `relay`（依据 `getStats()` 的选中候选对，不作为绝对隐私保证）；不记录敏感 SDP、ICE/IP、邀请凭据和 TURN 密码。

## 6. 安全、隐私与兼容

- `RTCDataChannel` 默认使用 DTLS 加密；这不等于陌生 Web Host 可信。Web Host 可以控制权威局面，也可以断线，产品文案应定位为好友对弈而非可信竞技裁判。
- 使用高熵随机房间令牌、一次性或限期邀请；信令限制两名玩家、消息大小、创建频率、连接数，并在过期/离房时释放状态。
- WebRTC SDP/ICE 可能暴露网络候选；不上传公开日志。采用隐私友好的错误诊断，显示必要状态而不暴露对手网络地址。
- 公共 STUN/托管 TURN 是外部服务依赖：可配置、可失败、可替换。明确服务所在区域、隐私说明和网络可达性差异。
- **不要改坏 KataGo 的 `coi-serviceworker.js` 跨源隔离**。Cloudflare 信令 HTTP API 应正确响应 CORS；测试 `Cross-Origin-Embedder-Policy` 环境下的 fetch / WebSocket 和其他第三方资源，不为 WebRTC 关闭整个站点的隔离。
- GitHub Pages 保持 `--base-href /easyplay/`；RTC 桥接资源通过 baseURI/相对路径加载。
- Safari（含 iOS）、Chrome/Edge、Firefox 需实测；`RTCPeerConnection` / `RTCDataChannel` 不可用时应隐藏入口或提供可理解的提示。

## 7. 预期文件规划（实施时可依项目代码细化）

```text
lib/lan/
  room_coordinator.dart         # 从现有 Host 提取权威房间逻辑
  message_transport.dart        # 传输抽象与消息分片
  rtc_room.dart                 # RTC Host/Guest 会话与角色绑定
  rtc_transport_web.dart        # 条件导入的 Web 实现
  rtc_transport_stub.dart       # 不支持平台占位
  rtc_manual_signaling.dart     # MVP 手工 Offer/Answer
  rtc_signaling_client.dart     # 可选自动信令接口与 Worker 客户端
  rtc_lobby_page.dart           # WebRTC 建房/加入、连接状态

web/
  rtc_bridge.js                 # 可选：简化 Dart JS interop 的浏览器桥接

workers/easyplay-signaling/     # 第二阶段独立部署；不随 GitHub Pages 上传
  src/index.ts                 # Worker API、TURN 临时凭据签发
  src/room.ts                  # 每房间 Durable Object + WebSocket Hibernation
  wrangler.jsonc               # 配置只引用 Secret 名称，不含密钥

test/lan/
  rtc_room_test.dart
  rtc_framing_test.dart
  rtc_signaling_test.dart
  rtc_widget_test.dart
```

若纯 `package:web` + `dart:js_interop` 足够易维护，可不创建 `rtc_bridge.js`。共享层应可在普通 Dart 测试中注入 fake transport，不把协议测试绑定于真浏览器。

## 8. 逐步实施和完成标准

### Phase 0 — 先抽房间核心，不改变旧行为

- [x] 引入 `RoomCoordinator` / `MessageTransport`，把监听 socket 的部分与权威协议分开。
- [x] 保持 Android LAN 建房/加入、Web LAN 加入、协议版本和现有 UI 功能。
- [x] 利用 fake transport 跑三类游戏双端：开房、握手、落子、非法步拒绝、悔棋/提和/计分/再来一局、断线同步。
- **验收：** 旧 LAN 全量测试、`dart analyze lib test` 和 `flutter test` 通过；旧联机行为没有回归。

### Phase 1 — GitHub Pages 手动信令 WebRTC MVP（无服务成本）

- [x] `rtc_manual_signaling.dart` 完整导出/导入 non-trickle Offer/Answer；候选搜集完成/超时/取消。
- [x] 建立可靠有序 DataChannel + 传输分片/重组/背压。
- [x] Web Host 建立 Authority + 本地 Replica；Web Guest 经 DataChannel 加入。
- [x] 三游戏复用现有联机交互、房主先手、规则/配置校验。
- [x] Chromium / Firefox 真实双标签页通道通过握手、落子、大包同步及重协商；Chromium 另验证计分、重赛和实际 Flutter 创建/加入页面。
- [ ] 跨机器同 LAN、可直连的跨网环境和正式 GitHub Pages 地址仍需发布后验收。
- [x] UI 有真实连接状态、失败/取消与重新开始；无 TURN 时明确提示可能无法跨网。
- **验收：** 不创建任何 Worker/Realtime 账号，不购买 VPS，在 GitHub Pages 的正式 `/easyplay/` 路径上完成 Web ↔ Web 对局；Android LAN 不受影响。

### Phase 2 — 自动信令（仍无 VPS）

- [ ] 部署 Cloudflare Worker + SQLite-backed Durable Object 房间。
- [ ] 建立创建/加入/断开/恢复、Offer/Answer/Trickle ICE 消息接口，校验房间 token、身份、TTL、大小和速率。
- [ ] 使用官方 WebSocket Hibernation API；避免在 DO 上持续跑会阻碍休眠的普通定时器。
- [ ] Pages UI 改成邀请链接/房间码一键加入；手动信令仍可在服务不可用时独立工作。
- **验收：** 两台浏览器不需要复制 SDP；第三人/错误 token/过期房间被拒绝；服务中断或重新协商有明确提示。

### Phase 3 — Cloudflare Realtime TURN（按需启用）

- [ ] 在 Cloudflare 控制台建立 TURN Key；密钥只存 Worker Secret。
- [ ] 仅向已鉴权的当前房间参与者签发短期 `iceServers`；限制滥用并支持到期刷新。
- [ ] 添加 STUN、TURN UDP/TCP/TLS 候选，默认 `all`，测试时可开 `relay`。
- [ ] 用官方 Trickle ICE 测试验证 `relay` 候选；真实双设备跨不同运营商/Wi-Fi/蜂窝网络完成对局。
- [ ] 记录匿名化的 ICE 结果和服务额度使用情况；部署前核实免费额度/收费条件，预算用量可见。
- **验收：** 强制 relay 真实走子/同步/再来一局成功；TURN 服务不可用时可直连的玩家仍能对弈，不可直连者看到明确错误。

### Phase 4 — CI 与完整回归

- [ ] 单元测试：输入格式、seq、分片乱序/重复/丢包、4 MiB 限制、角色伪造、重连/超时。
- [ ] 房间集成测试：Go、Chess、八种 Draughts 逐一验证开局先手、走子一致性、协商与重赛。
- [ ] Playwright 双浏览器测试：真 WebRTC DataChannel；非根路径部署；关闭/刷新/恢复；不同浏览器矩阵。
- [ ] 页面测试：手动信令按钮、自动信令可用时的邀请流程、失败提示与禁用联机 AI。
- [ ] 已有 `flutter build web --release --no-wasm-dry-run --base-href /easyplay/`、Android Debug/Release 检查及 KataGo/Stockfish Worker smoke 不退化。
- **最终验收：** 无需 VPS；Web ↔ Web 成立；Android LAN 保留；未向公开资源泄露任何长期 TURN Key/API Token。

## 9. 发布与版本策略

- 每个 Phase 单独 PR/提交和验收，不要求一次完成全部；先上线无服务器 MVP，再根据真实跨网连接率决定是否接入 TURN。
- Phase 0 是内部重构，不改变线上协议时保持 `lanProtocolVersion`；需要改变消息语义时再升版本。
- GitHub Pages 工作流继续发布静态 `build/web`；Cloudflare Worker 作为独立部署任务，部署失败不应阻断原本的静态站点发布。
- 新服务密钥仅在 Cloudflare Secrets / GitHub Actions Secrets（若自动部署确有需要）中管理；仓库只存变量名与脱敏配置示例。
- 计划通过评审后再实施。WebRTC 手动信令已在本轮实现；Worker 与 TURN 尚未启用。正式 Pages 验收需在部署后进行。

## 10. 官方参考

- [MDN — WebRTC connectivity / Signaling](https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Connectivity)
- [MDN — Using WebRTC data channels（消息上限、缓冲、DTLS）](https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Using_data_channels)
- [MDN — ICE candidate / gathering completion](https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/icecandidate_event)
- [Cloudflare Realtime TURN](https://developers.cloudflare.com/realtime/turn/)
- [Cloudflare TURN — Generate Credentials](https://developers.cloudflare.com/realtime/turn/generate-credentials/)
- [Cloudflare TURN — FAQ / 价格与 STUN](https://developers.cloudflare.com/realtime/turn/faq/)
- [Cloudflare Durable Objects — WebSocket Hibernation](https://developers.cloudflare.com/durable-objects/best-practices/websockets/)
- [Cloudflare Workers — Pricing](https://developers.cloudflare.com/workers/platform/pricing/)
- [Cloudflare Durable Objects — Pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/)
