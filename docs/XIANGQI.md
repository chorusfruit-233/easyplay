# 中国象棋

中国象棋是独立的第五种游戏，支持本地双人、六档 Pikafish AI、LAN 和手动 WebRTC。棋盘为 10 行、9 列交叉点；红方先走，默认红在下。AI 与联机把我方放在下方，翻转不会改变坐标。棋盘监听系统字体加载变化，自动重绘迟到的汉字字形。当前着法历史仅用于规则、悔棋、搜索和重连，关闭页面后不保存棋谱。

## 固定规则配置

`rulesVersion: 1`、`ruleProfile: asian`。全部正式移动由 `XiangqiSession` 验证，包括蹩马腿、塞象眼、炮架、九宫、河界、将帅照面和应将；将死与困毙均判负，不能吃掉将帅继续对局。

重复裁定参考官方 Pikafish 2026-09-06 的 Asian 实现：同局面和行棋方出现三次后，单方持续将军判该方负；双方持续将军判和。无将军周期中，只有一方每步新产生对同一枚棋子的规则意义捉子，该方判负；双方长捉或允许的重复判和。混合将军与捉子/闲着周期，未形成单方持续将军时判和。兵帅捉子、未过河兵卒、可合法反吃和同类互捉按固定例外处理，弱子捉车等不因此豁免。这是固定兼容配置，不声称兼容所有比赛条例。

无吃子计数到 120 半回合判和；每方超过十次将军及对应应将不继续增加该计数。吃子清零。悔棋恢复计数、重复周期、终局和行棋方。

## 引擎与许可证

官方版本 `Pikafish-2026-09-06`，源码提交 `4c17cee11f888ae1d48a9494f2e2239f019f0a1f`。程序 GPL-3.0-or-later；官方 NNUE 另有非商业授权，未经许可不能商业使用。关于页列出两类许可和来源，详见 `assets/pikafish/`。

`python3 tools/prepare_pikafish.py` 校验 ARM64、Worker/JS、WASM 和 NNUE；缺失模型/原生程序时下载已固定哈希的官方发布包。需安装 `7z` 或 `7zz`。Android Studio 的 Gradle `preparePikafish` 同样执行校验，不能静默省略引擎。Native 使用独立 Method/Event Channel，模型校验后在后台线程复制到应用私有目录。

Web 引擎在同源单线程 Worker 中运行，不需要 SharedArrayBuffer；初始局面与完整历史通过 UCI 提供。停止搜索先消耗旧 bestmove；悔棋、重开、退出使用 generation 丢弃旧结果。初始化失败显示错误并可重试。

## 重建 Web 引擎

使用 Emscripten **4.0.23**（emsdk 提交 `c0bb220cb6e6f4e0fabb6f6db9efd53390ef5e56`，SDK 构建 `aaa43392544d695232b70eda706d751f18980c2a`）：

```sh
source /path/to/emsdk/emsdk_env.sh
python3 tools/build_pikafish_web.py --emxx /path/to/emsdk/upstream/emscripten/em++
```

脚本下载精确提交归档，验证归档及干净源码树，再将调度/标准输入替换为 Asyncify 协作循环；上游搜索代码保持原算法。也可传 `--source /clean/pinned/src`，该目录会被修改，需使用一次性副本。产物 `pikafish-core.js`、`pikafish-core.wasm` 已随仓库提供，预备脚本校验其哈希。重建已确认字节一致。

## 联机与验证

传输边界 `Side.white → red`、`Side.black → black`；界面只显示红黑。Move 带 `game: xiangqi`，使用 `a0–i9`，Chess parser 不接收象棋事件。LAN/RTC 共用权威规则与连续 seq，stateSync 重放完整事件，包括悔棋、协商、重开；再来一局保留 seq、座位和房间。

```sh
dart analyze lib test
flutter test
python3 tools/test_pikafish_rules.py
node tools/test_pikafish_web.cjs
python3 tools/package_lan_android.py --debug
```

原生自动测试可设置 `PIKAFISH_TEST_EXECUTABLE`；CI 使用 qemu-aarch64 执行固定 ARM64 程序。真实浏览器测试需 Playwright Chromium，覆盖 `/easyplay/` 子路径、红黑搜索、stop、新局、终止 Worker 和 UI 不阻塞。初始 perft 为 44 / 1920 / 79666，其他固定局面对照官方原生程序，测试包含受保护目标与互捉例外。

## 资源成本

ARM64 引擎 2,413,440 字节；Web WASM 915,125 字节；NNUE 50,706,378 字节。Android 同时包含 Native NNUE 和内置 Web Worker NNUE，两份模型有意保留以支持 Android 主机向浏览器提供 AI；内置 Web 中去掉未使用的 Flutter NNUE 副本。Pages 独立部署保留完整模型。

2026-10-04 验证产物：Debug APK 331,642,603 字节；ARM64 Release APK 214,390,529 字节（本地测试签名）。大小包含现有 KataGo/Stockfish 及 LAN Web，不仅是新增象棋资源。
Pages 独立 Web 构建总计 161,750,463 字节；部署前应沿用现有页面工作流的产物过滤规则。
