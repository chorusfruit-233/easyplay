# 局域网联机设计研究

**范围**:架构选择、硬约束与风险。部分实现已在 `lib/lan/`，当前进度见
`LAN_MULTIPLAYER_PLAN.md`；本文件中的真机假设仍需按计划实测。

> 界面部分见 **`docs/LAN_MULTIPLAYER_UI.md`**,执行顺序与上线步骤见
> **`docs/LAN_MULTIPLAYER_PLAN.md`**。界面那份的结论之一值得在这里先记一句:
> **参考产品没有联机功能**(逐条查证,不是印象),所以联机 UI 没有可对齐的对象。

---

## 一、前提判断

**围棋对联机的技术门槛极低,而工程门槛集中在两处,都不在网络本身。**

理由是围棋的三个特性:

1. **回合制**,无实时性要求。LAN 往返延迟(1–5ms)相对人类思考时间(数秒)可忽略
2. **完全确定性**。没有随机数、没有隐藏信息(不像牌类),同一串走子必然得到同一局面
3. **增量状态极小**。一手棋 = 一个坐标 + 一方,几十字节。整局不过几十 KB

推论:**不需要同步棋盘状态,只需要同步走子序列。** 双方各自在本地重放。这消掉了
传统联机里最难的一块(状态对账)。

因此真正的门槛是:

- **Android 后台限制**——主机是手机,息屏/切后台会掐掉服务端(第四节)
- **对局语义的一致性**——悔棋与终局计分必须协商,否则双方状态必然分叉(第三节)

---

## 二、硬约束(已核实)

### 2.1 浏览器不能当主机

浏览器不允许打开监听 socket。所以拓扑被限定为:

| 角色 | Android | Web |
| --- | --- | --- |
| 主机(监听) | ✅ | ❌ |
| 客户端(连接) | ✅ | ✅ |

**手机当主机、Web 当客户端是唯一可行方向。**

### 2.2 Android 14+ 的后台限制:要跨息屏就得上前台服务

本项目 `targetSdk = 36`(Flutter 3.44 默认值,已核实于
`FlutterExtension.kt`),因此 Android 14+ 的行为变更全部适用:

- 启动前台服务**必须声明类型**([Android 官方](https://developer.android.google.cn/about/versions/14/changes/fgs-types-required)),
  且类型要与实际用途匹配,否则 Play 审核会拒
- **Doze / App Standby** 在息屏后会限制网络([官方文档](https://developer.android.google.cn/training/monitoring-device-state/doze-standby))。
  不申请电池优化白名单的话,长时间对局中途息屏就可能断连
- Android 14 起后台启动 Activity 受限,不能靠"弹一个 Activity"来保活

**类型选择这一项我未能从官方文档确认。** 候选是 `dataSync` 与 `connectedDevice`,
但前者官方描述偏向"数据同步",后者偏向"与外部设备交互"(蓝牙/USB/投屏一类),
都不完全贴合"本机监听端口等局域网客户端连入"这一用途。`specialUse` 曾被认为是
兜底选项,但其现状我同样没有确认。

**因此这一条必须实测**:声明一个类型、跑一次长时间息屏对局,看系统是否放行、
Play 是否接受。不要照抄任何网上的说法(包括本文档的)。

(该不确定性因决定 6 而**不再是阻塞项**——不采用前台服务,就不必选类型。)

**结论(已按决定 6 调整)**:若要让对局**跨息屏延续**,就必须配一个带常驻通知的前台
服务,且只能在 Kotlin 侧做(Dart 无法声明前台服务),意味着又一个 MethodChannel。

**本项目已决定不做。** 因此主机息屏即视为断线,见决定 6。这一节的其余内容保留为
背景:它说明的是"为什么息屏会断",而不是"必须做什么"。

### 2.3 浏览器看不到本机 IP

Web 端拿不到本机 IP,所以客户端地址只能来自:

- 手动输入 `192.168.x.x:8080`
- 或扫二维码

但**扫码需要摄像头,而 `getUserMedia` 要求安全上下文**。若 Web 端由主机以
`http://192.168.x.x` 提供(同源方案,见 5.2),则是 http 页面,**摄像头不可用**,
只能手输。这是两个方案之间的取舍,不能既要同源又要扫码。

### 2.4 Android 17 起局域网访问需要运行时权限(2026-09 补)

**这是本文档原先漏掉的一条硬约束,而且它同时影响主机和客户端。**

[Flutter 官方文档](https://flutter-docs-prod.web.app/platform-integration/android/local-network-permission)
(对应 [Android 官方说明](https://developer.android.com/privacy-and-security/local-network-permission#android-17-enforcement)):

> Starting in Android 17 (API level 37), Android blocks local network access by
> default. Apps targeting Android 17 or higher that **discover, scan, or connect
> to** devices on the local area network must declare and request the
> `ACCESS_LOCAL_NETWORK` runtime permission.

关键点:

- 目标 API ≥ 37 的应用,**默认被禁止访问局域网**,必须声明
  `ACCESS_LOCAL_NETWORK` 并在运行时申请
- **可以通过 `permission_handler`(`Permission.accessLocalNetwork`)申请**,
  该常量已存在于 `permission_handler 13.0.2`
- **Dart socket 弹不出权限框**。官方原话:Dart socket 不与 Android 应用框架 UI
  交互,所以**没有权限时 `Socket.connect` 直接抛 `SocketException`**。必须在打开
  socket **之前**申请完
- 按 Flutter 文档,Android 16(API 36)上可以**主动开启**该行为来提前测试

**本项目当前的状态**:`targetSdk` 由 Flutter 的 `FlutterExtension.targetSdkVersion`
决定,当前是 **36**,所以这条**尚未生效**。但该字段的注释写着 "should always be the
latest available stable version"——它会随 Flutter 升级而升到 37,届时**强制生效**。

**必须实测的一点(比客户端更要紧)**:官方措辞覆盖的是 "discover, scan, or connect",
**没有明说"监听/被连接"是否也受限**。主机是被客户端连入的一方,如果 `ServerSocket`
同样被拦,那**整个方案在 Android 17 上直接不成立**——连"发 Web 页面给浏览器"都做不了。

**所以要在 Android 16 上先打开该行为跑一次**:主机开房、客户端连入,看是否需要权限、
需要谁的权限。这一条排在做任何联机实现之前。

### 2.5 系统版本范围:Android 7 – 16 都可用

**结论先行**:从 **Android 7.0(API 24)** 到 **Android 16(API 36)** 全段可用,
且**不需要任何新增危险权限**——只要坚持两条已经定了的设计:**不用组播**(改用主动
扫描)和**不用前台服务**。

**本项目实测解析值**(读 `build/app/intermediates/merged_manifests/.../AndroidManifest.xml`):

```
android:minSdkVersion="24"      ← Android 7.0
android:targetSdkVersion="36"   ← Android 16
uses-permission: INTERNET       ← 仅此一条
usesCleartextTraffic            ← 未设置(targetSdk≥28 时默认 false)
```

`minSdk`/`targetSdk` 都来自 Flutter 的 `FlutterExtension.kt`(当前 24 / 36),
项目自己没覆盖。

#### 逐版本影响

| 版本 | API | 该版本引入的限制 | 对本方案 |
| --- | --- | --- | --- |
| 7.0 | 24 | **本项目的下限** | 基线 |
| 8.0 | 26 | 后台执行限制、通知渠道 | 无关(不用通知) |
| 9 | 28 | **明文 HTTP 默认禁止**(`usesCleartextTraffic=false`) | **需实测**,见下 |
| 10 | 29 | 分区存储、后台启动 Activity 受限 | 无关 |
| 11 | 30 | 软件包可见性 | 无关 |
| 12 | 31 | `android:exported` 必填;接收组播需 `MulticastLock` | 无关(**不用组播**) |
| 13 | 33 | `NEARBY_WIFI_DEVICES`(仅 WiFi 扫描类 API 需要) | **无关**——我们枚举网卡,不调 WiFiManager |
| 14 | 34 | **前台服务必须声明类型** | 无关(**决定 6:不做前台服务**) |
| 15 | 35 | 前台服务超时 | 无关 |
| 16 | 36 | 本地网络保护可**手动开启**测试 | 见 §2.4 |
| 17 | 37 | 本地网络保护**强制生效** | 见 §2.4,届时必须加权限 |

**关键推论**:这条路径上真正的两个"关卡"是 **Android 9 的明文 HTTP** 和
**Android 17 的本地网络权限**。中间那些版本限制(通知、前台服务、组播、WiFi 扫描、
存储)全都因为我们不用那些 API 而绕开了。

**一个顺带的好处**:因为用 `NetworkInterface.list()` 枚举网卡、而不是
`WifiManager.getConnectionInfo()`,我们**不需要定位权限**。Android 10 起把 WiFi 名称
划归定位权限,很多联机应用因此被迫申请位置——我们不碰这条路。

#### 必须实测的两件事

1. **Android 9+ 的明文策略会不会拦住 Dart 的 socket**

   官方那份 [breaking change 文档](https://flutter-docs-prod.web.app/release/breaking-changes/network-policy-ios-android)
   明确写着:

   > Flutter does not enforce any policy at socket level... **If the socket is owned
   > by Dart/Flutter, no policy will be enforced.**

   按这句,我们的 `Socket` / `WebSocket.connect` / `HttpServer` 都是 Dart 持有的
   socket,**不受影响**。但同一页的 Timeline 又写着 "Reverted in version: 2.2.0
   (proposed)",且官方声明 "we don't keep these breaking change docs up to date"。

   **所以不能按文档下结论,要在 Android 9 的真机上用 release 包跑一次**:
   - 客户端 `Socket.connect` 到局域网地址(扫描探针)
   - 客户端 `WebSocket.connect('ws://192.168.x.x:8080')`
   - 主机 `HttpServer` 被浏览器访问

   如果确实被拦,补救是加 `networkSecurityConfig` 允许明文——但注意
   **Android 的 `<domain>` 不支持网段**,没法只放行 `192.168.0.0/16`,只能全局
   `cleartextTrafficPermitted="true"`。这是要尽量避免的结果,也是为什么先测。

2. **手机热点当主机能不能拿到自己的地址**

   这是很常见的用法(没有路由器时,一台手机开热点,另一台连上)。热点网卡在
   AOSP 上通常是 `192.168.43.1`,但 **Android 11 起各厂商差异很大**
   (`swlan0` / `wlan1` / 有的干脆对应用不可见,因为跑在独立网络命名空间里)。

   `NetworkInterface.list()` 能不能列出热点网卡,**是设备相关的,必须逐机型测**。
   测不过的话,热点场景就只能靠手输地址(玩家从系统设置里看自己的热点 IP)。

### 2.6 已有可复用资产

| 资产 | 用途 |
| --- | --- |
| `crypto: ^3.0.6` | 入房令牌的 HMAC 校验,无需新依赖 |
| `archive: ^4.3.0` | 与联机无关,但说明已能处理打包格式 |
| `dart:io` 的 `ServerSocket` / `WebSocketTransformer` | 服务端,SDK 自带 |
| `GoSgfController` + `GoRecordNode` | 记录树,天然适合作为走子序列的载体 |
| `GoSgfController.sessionForCurrent()` | 从根重放到游标,重连恢复的基础 |
| `GameSession.isLegalGoMove()` | 服务端权威校验的现成入口 |

**注意**:目前项目**完全没有网络代码**(`grep dart:io` 为空),这是从零开始的一块。

---

## 三、状态同步的设计

### 3.1 传走子,不传棋盘

一手棋的消息体:

```json
{"type":"move","seq":7,"side":"B","cell":[3,3]}
{"type":"pass","seq":8,"side":"W"}
{"type":"resign","seq":9,"side":"B"}
```

接收方在自己的 `GameSession` 上重放。因为围棋确定性,双方必然收敛到同一局面。

### 3.2 两个必须协商的语义(否则必然分叉)

**a) 悔棋**

单方调用 `undo()` 会让双方立刻不一致。必须改成请求—应答:

```
B → S: undoRequest(seq)
S → B: undoAccept(seq) | undoReject(seq, reason)
```

参考产品把这事做得更重——它的 **AI 悔棋是配额动作**,因为悔棋要让引擎重算。我们
若在联机里允许悔棋,至少要有"对方同意"这一步。

**b) 终局计分**

死子标记是**双方各自的主观判断**。参考产品里 `"Manual" = "手动"` 与
`"Scoring..." = "正在数目..."` 并存,说明它把"引擎判"和"人工确认"分开。

联机里必须:

1. 一方 `scoreProposal(deadStones[])`
2. 另一方 `scoreAccept | scoreCounter(deadStones[])`
3. 双方一致才写入终局

**否则各算各的,一盘棋会得出两个结果。**

### 3.3 一条性能要点

`sessionForCurrent()` 的当前实现是 `exportRecord → importGame`,即**每次导航都完整
序列化再解析一遍 SGF**。复盘场景下这没问题(还能顺带验证 SGF 往返一致性),但
**实时对局每手都这么做不划算**。

实时路径应当维护一个**活的对局实例**:

```
对局中:  session(活) ← 直接 placeGo()
结束/重连: controller + sessionForCurrent() 兜底
```

也就是说,记录树负责持久化与复盘,活会话负责实时。两者在关键节点对齐。

---

## 四、Android 后台:已知会断,已接受

把风险写清楚,因为这一项最容易低估:

| 场景 | 后果 | 本项目如何处置 |
| --- | --- | --- |
| 主机息屏 | Doze 限制网络,客户端超时 | **接受断连**(决定 6),恢复后从记录重建 |
| 主机切后台 | 进程可能被冻结,服务端停止响应 | 同上 |
| 系统内存回收 | 进程被杀 | 对局不丢:走子已持久化在记录树中 |
| 客户端切后台 | 浏览器/App 被节流,心跳延迟,表现为"连接假死" | 主动心跳 + 切回前台时重连并重放 |

**不采用前台服务**意味着"息屏断连"是设计的一部分而非缺陷。因此下面这条从
"可选的优化"变成"必须做对的核心逻辑":重连与重建。

因为状态就是走子序列,**重连 = 补发缺失的走子**,天然幂等,不需要额外设计。
这是"传走子不传状态"这个选择带来的额外好处。

---

## 四点五、已决定(2026-09-26)

以下为拍板结论,后续实现按此执行。

### 决定 1:状态以谁为准 → **服务端权威**(选项 B)

服务端持有权威 `GameSession`,对每一手做合法性校验(劫争、自杀、已占点),
通过后才广播。**主观判断(死子归属)不做权威裁决**,留待双方协商——这与围棋
本身的习惯一致,也避免服务端去猜人的意图。

### 决定 2:悔棋 → **请求—对方同意**(选项 B)

不做无条件允许(那会让双方状态必然分叉)。

### 决定 3:主机角色 → **Android 建房,Android 与 Web 都可加入**(选项 A)

Web 无法监听端口,所以「谁能建房」在技术上只有一个答案:Android。这一条实际
决定的是**客户端范围**:两种客户端都要支持。

### 决定 4:Web 页面来源 → **主机发应用 + HTTPS 托管,两条都要**

- **同源路径**:主机经本地静态服务提供 Web 应用(`http://192.168.x.x:8080`),
  无跨域、无混合内容、不触发 Local Network Access
- **HTTPS 路径**:Web 应用托管在 HTTPS 站点,连 `ws://192.168.x.x`

两条并存意味着 HTTP 客户端 UI **不能依赖摄像头扫码**(同源路径下是 http 页面),
必须提供手动输入地址的路径;扫码只作为 HTTPS 路径下的增强。

**注意**:HTTPS 路径会触发 Chrome 的 Local Network Access 权限,且官方已声明
WebSocket 即将纳入该限制。这条路径要接受将来可能被浏览器进一步收紧的风险。

### 决定 5:发现方式 → **主动扫描为主,手输兜底**(2026-09 修订)

**原决定**是「手动输入(扫码仅作增强)、不做 mDNS」。修订的原因是当初漏了一个选项:
本文档只列了 mDNS 与手输两条路,而**否决 mDNS 的理由(组播在真实网络里不可靠:
AP 隔离、访客网络、多卡)对主动 TCP 扫描不成立**——扫描不用组播。

**现决定**:客户端进「加入房间」时提供「扫描局域网」按钮,扫本地 /24(254 个地址、
64 路并发、单超时 250ms,约 1 秒),命中主机已有的 HTTP 服务探针路径即列出房间;
手输作为兜底保留(AP 隔离下两者都连不上,不同网段或客户端挂 VPN 时手输可能可行)。

- 不做 mDNS(维持原判断)
- 扫码仍留第二期,理由与成本见 UI 文档 §4.2b
- 扫描是**用户点了才扫**,不自动跑,也不扫比 /24 更宽的网段

实现细节与边界见 `docs/LAN_MULTIPLAYER_UI.md` §5.0。

### 决定 6:息屏 → **接受断连,不做前台服务**

**明确放弃**前台服务与电池优化白名单。因此主机息屏或切后台即视为断线,
客户端需按断线处理。

这条决定移除了一整块 Kotlin 侧工作(前台服务、服务类型声明、常驻通知),代价是
**对局不能跨息屏延续**。设计上必须保证:

- 主机恢复前台后能从记录重建对局(记录树已持久化,天然支持)
- 客户端断线后按重连流程处理(见 3.3 与第四节)

### 决定 7:断线策略

- 主机断:对局保留在本地记录中,恢复后重建
- 客户端断:重连后发 `stateRequest{lastSeq}`,服务端补发缺失走子
- **超时判定要宽松**:围棋一手可能长时间思考,过短的超时会误判在线对手为掉线

### 决定 8:联机对局期间 **禁用一切 AI 功能**

不只是「分析」。凡是会调用引擎、或展示引擎产出的入口,在联机对局进行期间一律不可用:

| 入口 | 为什么 |
| --- | --- |
| 机器人面板的「AI 对弈」 | 引擎不能接手 |
| 「分析」 | 候选点+胜率就是引擎提示,等于开狗 |
| 「选点」「局势」叠加 | 分析结果的呈现 |
| 「AI 摘要」页签 | 同上 |
| 「PV」页签 | 同上 |
| 落子后的 `_scheduleComputerMove` | 会发 `genmove` |
| **终局裁定 `_autoAdjudicate`** | **最容易漏的一处**:它调 `final_status_list dead` 与 `final_score`,既是 AI 调用,也与「死子由双方协商」的语义冲突,联机必须改走协商流程 |

「设置」里的引擎/棋力/风格/模型同样锁死,但理由不同——那是改了会分叉(§二.1),
不是 AI。

**执行方式**:界面隐藏只是表象,真正的保证是**联机对局期间引擎进程不得启动**。
实现上是一个统一的判据(例如 `vsOnline && !gameOver`)加在每条 AI 路径的入口,
并用测试钉住,而不是逐个按钮去藏。

**对局结束后恢复**:终局/认输之后这就是一盘棋谱,复盘用分析是正当的。

---

## 五、架构选择(以下为备选分析,结论见 4.5)


### 5.1 发现机制:两个选项

| 方案 | 成本 | 风险 |
| --- | --- | --- |
| mDNS / NSD | 中,需插件与 `MulticastLock` | Android 12+ 多播受限;**AP 隔离、访客网络、多网卡下直接失效** |
| **主机显示地址 / 二维码,客户端输入** | 低,零依赖零权限 | 需手动输入,略笨 |

**建议后者。** mDNS 在真实家庭网络里翻车率不低,而手动输入是"一定能用"的方案。
可以两者都留:先手动输入打通链路,再按需要加发现。

### 5.2 拓扑:主机是否顺带当 Web 服务器

| 方案 | 优点 | 缺点 |
| --- | --- | --- |
| **A. 主机发 Web 应用**(客户端访问 `http://192.168.x.x:8080`) | **同源**:无跨域、无混合内容、不触发 Chrome 本地网络权限 | 主机要传约 12MB 产物;http 页面无法扫码 |
| B. Web 端托管在 HTTPS(如 GitHub Pages),连 `ws://192.168.x.x` | 页面可用摄像头扫码 | 触发 **Local Network Access** 权限(Chrome 142 起);WebSocket 目前未被拦但**官方明确说即将纳入** |

**A 更稳**,因为它绕开了正在变化中的浏览器策略。代价是放弃扫码。

### 5.3 服务端权威程度

三个档位:

| 档位 | 做法 | 代价 |
| --- | --- | --- |
| 纯转发 | 客户端各算各的,服务端只广播 | 非法走子会立刻分叉,且是作弊入口 |
| **服务端校验**(建议) | 服务端用 `isLegalGoMove` 验证后再广播 | 需要服务端持有权威会话 |
| 全程权威 | 服务端算分、判死子、仲裁 | 复杂,且与"双方各自判断死子"的围棋习惯冲突 |

中间档足够:合法性由服务端把关(劫争、自杀、已占点),而**主观判断(死子)仍留给
双方协商**。

### 5.4 房间令牌

LAN 不等于可信,同一 WiFi 下任何设备都能连端口。最低要求:

- 入房令牌(主机生成,二维码/口令传递),`crypto` 做 HMAC 校验
- 服务端拒绝未通过握手的连接
- **不上 TLS**:自签证书在移动端的信任链处理成本远超收益,对局数据也不敏感

---

## 六、协议草案(消息层面)

握手后所有消息带 `seq`,服务端维护权威序列号。

```
← hello        {roomVersion, boardSize, rules, komi, handicap, token}
→ helloAck     {assignedSide, started, seq}
→ matchStart   {seq}             // 房主点击开始后广播，不消耗序列号
→ stateRequest {lastSeq}          // 重连时用
← stateSync    {events:[...], seq} // 同步完整权威事件日志

→ move         {seq, side, cell}
→ pass         {seq, side}
→ resign       {seq, side}
← rejected     {seq, reason}      // 服务端校验失败

→ undoRequest  {seq}
← undoAccept   {seq} | undoReject {seq, reason}

→ scoreProposal{seq, deadStones[]}
← scoreAccept  {seq} | scoreCounter{seq, deadStones[]}

→ ping / ← pong                   // 心跳,探测假死
```

**设计原则**:`seq` 单调递增,接收方只接受 `seq == last + 1`。乱序或重放直接丢弃——
这让重连补发变得简单且安全。
`helloAck.started` 与 `matchStart` 是房间控制状态，不计入对局事件；开始前主机拒绝落子。

---

## 七、落地方案建议(分步、每步可验证)

**关键原则:先做不需要网络的部分。** 联机最难的不是 socket,而是状态一致性;而一致性
可以在单进程里用测试验证。

### 第 1 步:本地热座双人(已有基础)

`GoOpponentMode.local` 已存在。确认它真的可用——它是联机的地基:同一份会话、交替
落子、不需要网络。**这一步不写代码也应该先手动验一遍。**

### 第 2 步:协议层 + 单进程双实例对打

定义消息格式,写 `toWire` / `fromWire`。在**同一个进程里**用两个 `GameSession`
互相对打,断言:

- 同一串走子重放得到同一局面
- 非法走子被拒绝且不改变状态
- 悔棋协商后双方一致
- 乱序/重复 `seq` 被丢弃

**这一步完全不碰网络,却是整个方案成立与否的证明。** 而且它能在 CI 里跑。

### 第 3 步:host / join 骨架

主机开 `ServerSocket`,客户端连,只支持手动输入 IP。先不做:发现、扫码、前台服务、
重连。

### 第 4 步:补语义

权威校验、悔棋协商、终局确认、断线重连补发。

### 第 5 步:体验层

二维码(仅 HTTPS 路径可用)、HTTPS 托管路径。**不含前台服务**——已明确放弃。

---

## 八、风险排序

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| **Android 后台限制** | 主机息屏即断线 | **已接受**;靠重连与从记录重建兜底(决定 6) |
| **终局计分分歧** | 一盘棋两个结果 | 双方确认流程 |
| **悔棋导致分叉** | 状态不一致 | 请求—应答 |
| **浏览器策略变化** | Web 客户端某天连不上 | 采用同源方案(5.2 A)绕开 |
| mDNS 在真实网络失效 | 找不到房间 | 手动输入兜底 |
| 主机进程被杀 | 对局丢失 | 记录树已在本地持久化,重开可续 |

**注意最后一项**:因为走子已经写进 `GoSgfController` 并持久化,**主机被杀不会丢对局**,
重启后从记录重建即可。这是现有架构白送的好处。

---

## 九、结论

1. **可行,且难度低于预期**——确定性 + 回合制让状态同步变得简单
2. **真正的成本在两处**:Android 后台保活(Kotlin 侧,又一个 MethodChannel)、
   以及对局语义的协商(悔棋、终局)
3. **不要从 Web 端开始**——浏览器策略正在收紧(Local Network Access),而它依赖的
   协议层与服务端逻辑与 Android 完全相同
4. **第 2 步是分水岭**:单进程双实例对打能证明方案成立,且不依赖任何网络环境
5. **现有资产可复用度高**:记录树可直接作走子序列载体,`sessionForCurrent()` 就是
   重连恢复,`isLegalGoMove()` 就是服务端校验入口
