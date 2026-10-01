# 浏览器点对点联机

## 当前范围

无服务器手动信令 MVP 支持围棋、标准国际象棋和八种跳棋规则。房主浏览器持有权威状态，双方界面都使用已提交事件更新副本。原 Android LAN/WebSocket、首页快捷加入和协议版本 3 保留。尚未启用 Cloudflare 自动信令或 TURN。

## 使用步骤

1. 双方打开 EasyPlay Web，选择相同棋种（跳棋须选择相同变体），进入联机菜单的“浏览器点对点联机”。
2. 房主选择围棋棋盘/规则/贴目/让子（适用时），点击“创建邀请”，等候候选搜集结束，复制完整邀请并私下发给对手。
3. 客人粘贴邀请并点击“导入”，复制生成的回应并发回房主。不要在客人端再次创建邀请。
4. 房主导入回应。双方完成通道握手和状态同步后，房间显示 2/2；房主点击“开始对局”。
5. 对局中的悔棋、提和、认输、围棋计分和再来一局沿用已有联机操作；局内不启用 AI。

可以展开文本并手动复制/粘贴，浏览器剪贴板权限被拒绝时仍能操作。邀请有效期 30 分钟，含网络候选信息，不要公开分享、提交仓库或输出到日志。

## 断线和限制

- 公共 STUN 只帮助发现直连候选，不能保证所有网络互通。连接超时可取消并重试；没有 TURN 时，部分跨网连接会失败。
- “连接选项”默认选择国内服务：`stun:stun.miwifi.com:3478`、`stun:stun.hitv.com:3478`；国际预设为 Cloudflare / Nextcloud。浏览器同时尝试所选服务，列表顺序不代表网络优先级。国内候选参考 [Sukka 的 WebRTC 检测工具](https://ip.skk.moe/stun)，不代表服务商提供可用性保证。
- 可选“自定义服务”，每行输入一个 `stun:域名:端口` 或 `stuns:域名:端口`，最多四个，支持 IPv6。双方可使用不同服务；同网测试可关闭 STUN 后重试。自建服务也可填入这里，无需信令服务器。
- 候选搜集最多等候 15 秒。部分服务超时但已有 STUN 映射候选时仍可导出当前邀请；后续候选不再发送。全部服务不可达时提示切换服务；只有同网连接时才建议关闭 STUN。
- 2026-10-01 当前开发网络的 UDP Binding 验证：小米、芒果、Cloudflare 有响应；腾讯和斗鱼候选超时，因此未纳入默认值。这不等同于全国各运营商实测；正式使用需由双方网络验收。STUN 服务会看到请求来源地址；不记录候选地址或完整 SDP。
- 同一房主页面仍存活时，双方通过“重新连接”交换新邀请和回应，复用原房间凭据、权威事件与座位，再同步棋局。
- 房主刷新、关页或崩溃后内存中的房间丢失，客人不能接管或自动续局。断线不会被当作认输。
- 不支持 WebRTC 的平台隐藏入口。Safari/iOS、跨机器、不同运营商以及正式 Pages 地址需单独验收，不能由同机自动测试代替。

## 架构与资源限制

- `room_coordinator.dart` 共用身份绑定、座位、权威提交、协商超时和心跳；IO 服务器仅负责 Socket 与静态资源。
- `rtc_room.dart` 为现有棋局页面适配客户端，房主本机也经内存传输握手并更新 Replica。RTC 客人只绑定固定客人座位；不能凭 `resumeSide` 冒用房主。
- `rtc_transport_web.dart` 使用可靠有序 DataChannel；non-trickle SDP 在候选搜集完成后导出，搜集和连接均有超时。STUN 地址可从页面配置；开发者也可注入 `iceServers`。
- `rtc_framing.dart` 按 UTF-8 字节分片并以 SHA-256 校验；分片不超过 16 KiB，受 SCTP 上限约束，完整消息不超过 4 MiB。最多四组未完成传输、8 MiB 预留内存、15 秒重组期限。
- 发送队列最多 64 个传输及 8 MiB，缓冲超过 256 KiB 时等待下降，小消息在分片边界优先发送。损坏或超时触发状态重同步。
- 不引入信令服务、长期密钥、媒体权限或跨源隔离例外。

## 验证

```bash
flutter test test/lan
flutter test
dart analyze lib test
flutter build web --release --no-wasm-dry-run --base-href /easyplay/
flutter build web --release --no-wasm-dry-run --base-href /easyplay/ \
  --target test/lan/rtc_browser_smoke.dart --output build/rtc-smoke
npm install --no-save --package-lock=false playwright@1.58.2
npx playwright install --with-deps chromium
node tools/test_rtc_web.cjs
python3 tools/package_lan_android.py --debug
```

独立 smoke 目标不进入正式应用；它使用生产 Dart RTC/房间控制器，在 `/easyplay/` 路径和 COOP/COEP 下运行真实双端 DataChannel。CI 运行相同测试，检查三棋种、八种跳棋、状态同步和重赛。另需人工验证正式部署及真实跨设备连接。

额外 Firefox 检查（已安装 Selenium / Firefox 时）：`python3 tools/test_rtc_firefox.py`。本轮 Chromium 与 Firefox 的同机真实通道测试已通过；Safari/iOS、跨设备与正式 Pages 发布后的测试仍待人工验收。

可选公网 STUN 验证：构建 smoke 目标后运行 `RTC_STUN_PROBE=1 node tools/test_rtc_web.cjs`。检查国内默认配置和一个服务不响应时仍能取得映射候选，只输出候选数量与耗时。此检查依赖当前网络，CI 不默认运行。

本次 Chromium 公网检查通过：国内默认配置取得映射候选；加入故意不响应的服务后，15 秒截止时仍可生成邀请。三棋种/八种跳棋的真实通道回归通过。
