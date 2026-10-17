# Rapfi 集成

五子棋的人机和 AI 观战均使用 Rapfi 250615（0.43.01）。Android 使用随 APK 打包的 ARM64 可执行文件和约 20 MB 的连珠黑、白模型；Web 在独立 Worker 中运行 SIMD128 WASM，首次使用会读取同源的约 20 MB 模型数据，后续由浏览器缓存。不使用远程推理服务，不要求 SharedArrayBuffer 或 COOP/COEP。首轮模型初始化时间不计入搜索预算。

Rapfi 只搜索 `INFO RULE 4` 的自由开局连珠局面。索索夫-8开局、身份与颜色映射、黑方禁手判负、停一手和终局由应用规则核心管理。不是把 Rapfi 的 Swap2 当成索索夫-8。

| 难度 | Rapfi STRENGTH（0–100） | 每次正常搜索预算 |
| --- | --- | --- |
| 初级 | 10 | 100 ms |
| 中级 | 60 | 700 ms |
| 高级 | 100 | 2,400 ms |

这些是引擎强度参数，不是 Elo。搜索深度随设备和局面变化。高级使用最大内置强度；较低难度由 Rapfi 自己的 SkillMovePicker 从候选中选择。哈希表限制为 32 MiB，进程实际内存还包括模型、棋盘和运行时。各平台均单线程；Android 使用 ARMv8 NEON，不要求 DotProd，兼容较早的 ARM64 设备。

开局摆前三子在合法的26类开局内随机变化。第一次交换用 Rapfi 对三子局面的估分近似决定；第四手由 Rapfi 搜索。白方声明 N 时，分析最多8个不同形的黑5候选，按白方会选最弱候选、黑方拥有第二次交换权的条件，挑选评分最接近平衡的 N。第二次交换看第 N 个候选的评分；黑方逐个提出最强的剩余不同形候选，白方逐一搜索这些候选落定后的白6局面并择优。开局决策使用完整强度，数量声明及第二次交换的8候选分析至少用500 ms，白方选点将思考预算分摊到候选，最低每点 80 ms。所有决策是有界搜索的近似，不是索索夫-8的完整博弈求解。

只接受已完成的一整轮 MultiPV 评分，避免把中断的下一轮混入候选排序。BOARD 以实际棋子颜色、时间顺序和停一手状态构造，不依赖玩家原始座位。YXBLOCK 排除禁手、已提候选及其同形点；应用再次验证返回点。引擎报错会显示失败并允许重试，不会暗中切回旧 Dart AI。

后台、悔棋、暂停、重开和离开页面会销毁同步搜索所在的 Worker 或原生进程。下一次思考先等旧实例关闭，再新建实例并重放局面；旧结果用任务代号与局面版本隔离。普通连续行棋复用实例，避免重复初始化模型。

## 源码、模型与构建

- 引擎完整源码固定到 [`1be1551ced57e38d53ed58f6d74bf6f8b4bdc230`](https://github.com/dhbloo/rapfi/tree/1be1551ced57e38d53ed58f6d74bf6f8b4bdc230)，GPL-3.0-or-later。源代码归档 SHA-256 为 `22e7ab8f4ce850ff1efd95e6a0a287d977dd66e5b2068e05fd38fb3a51d38efd`。
- 模型固定到 [`918b757a129258e9e765f77fe17d507c2bb1a60b`](https://github.com/dhbloo/rapfi-networks/tree/918b757a129258e9e765f77fe17d507c2bb1a60b)，CC0。只打包 Renju 的两份 mix9svq 和 classical/model210901.bin。
- `assets/rapfi/NOTICE.txt`、`MODEL-LICENSE.txt` 和 `THIRD-PARTY-LICENSES.txt` 随应用提供，并可从“关于与许可证”查看。
- `tools/prepare_rapfi.py` 校验代码和所有资源 SHA-256，按固定提交下载缺失模型并组装与 JS 元数据一致的 `.data` 文件。发布、Pages、Gradle 和 LAN 打包均调用它。二进制、JS 和 WASM 已随仓库提供；网络模型和可重建的 `.data` 不进入 Git。
- `tools/build_rapfi.py` 下载并校验完整源代码，复制固定配置和模型，执行唯一的源修改：在 `ThreadPool::waitForIdle` 中给只存在于多线程构建的 `thread` 成员访问添加 `#ifdef MULTI_THREADING`。不修改搜索和禁手算法。

复现构建需 CMake/Ninja、Android NDK **28.2.13676358（r28c）**、激活的 Emsdk **3.1.64**。命令模块和多线程关闭；Web 开 SIMD128、关闭 relaxed SIMD；Android 开基线 NEON、关闭 DotProd、静态链接，ELF 最大页面大小 16 KiB。仓库中的构建使用 CMake 4.4.4、Ninja 1.13.2。全部参数及补丁正文在构建脚本中。

```bash
python3 tools/prepare_rapfi.py
python3 tools/build_rapfi.py --android --ndk "$ANDROID_NDK_HOME"
python3 tools/build_rapfi.py --web
```

构建不同工具链的结果可能有不同校验值。修改源代码、配置、工具链或打包顺序后，应审查构建结果和测试，再更新 `prepare_rapfi.py` 的固定值；Android 安装资源的校验值也须同步。

## 验证

```bash
flutter test test/gomoku/soosyrv8_test.dart test/gomoku/rapfi_player_test.dart
# 本机 Rapfi 或 QEMU 启动脚本，工作目录由测试设为 assets/rapfi
RAPFI_TEST_EXECUTABLE=/path/to/rapfi flutter test test/gomoku/rapfi_native_test.dart
node tools/test_rapfi_web.cjs
node tools/test_gomoku_placement_web.cjs
node tools/test_ai_duel_web.cjs
```

原生回归使用实际打包的 ARM64 引擎，经 QEMU 完成索索夫-8开局、普通行棋、停一手、取消恢复和直接成五。浏览器回归在嵌套 `/easyplay/` 路径、无跨源隔离的环境启动实际 Worker，检查多候选、杀棋、搜索时 UI 响应和终止后重启。完整应用回归另外验证人机双方、两次交换、候选数1和8、落子确认、观战及存档。
