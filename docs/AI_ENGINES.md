# AI 引擎与模型

## 支持范围

围棋仅使用本地 KataGo CPU：Android 为 arm64 Eigen 程序，Web 为 Eigen/WASM Worker。Web 需要 COOP/COEP 响应头与 `SharedArrayBuffer`；GitHub Pages 使用跨源隔离 service worker。其他平台尚未接入原生围棋引擎。

Android 支持内置 b6、导入或下载的标准 `.bin.gz` / `.txt.gz` 网络，以及独立人类棋风网络。Web 仅使用内置 b6，不支持其他模型。较大的网络在 CPU 上可能较慢，建议先使用 b6 和较小搜索预算。

## 引擎配置

引擎管理提供名称、最大思考时间、搜索线程、自定义 cfg、主模型与人类模型。运行方式固定为 CPU，无需调优。时间范围为 0–120 秒，线程为 1–16；时间 0 不限制时间，搜索仍受 `maxVisits` 限制。

配置采用 `key = value`，支持 `#` 注释。合并顺序为内置参数、自定义 cfg、全局或段位 override、最终参数覆盖。新局的棋盘、规则、贴目和人类段位具有最终优先级。旧配置的设备参数不会传入 CPU 引擎。

Override 支持全局规则及 20k 至 9d 的范围，范围不能重叠。普通与人类棋风分别维护规则。内置规则位于 `assets/katago/`。

## 模型与人类棋风

导入时检查 gzip 完整性、SHA-256、网络版本及元数据。人类网络由内部 metadata encoder 识别，不能仅凭名称或扩展名判断，也不能作为主模型。

人类棋风需要主模型和独立 human model，使用 `humanSLProfile`（如 `rank_5k`、`preaz_5k`）及对应 override。普通棋风移除人类专用参数。Android CPU 已验证 b6 配合官方 b18 human 网络运行。

Android 新局预检查、引擎启动通过模型 ID 引用已保存的文件。原生端流式校验 SHA-256 并复制到引擎目录，避免整份大模型在 Flutter 通道中反复复制。仅小型内置 b6 传输字节；旧的整文件读取接口拒绝超过 8 MB 的文件。

## 运行与排错

“运行检测与日志”检查 CPU 程序并读取最近日志。原生 GTP 子进程处理搜索、分析、取消和终局裁定。退出或切换棋局取消旧请求；引擎不可用时回退为本地双人模式，不生成模拟着法。

Web 每次请求创建 Worker 并重放棋谱，退出时终止 Worker。所有模型与配置均为同源资源，没有远程推理服务。

## 构建与验证

- `tools/build_katago_android.sh`：固定 KataGo/Eigen 版本，使用 NDK 28.2.13676358 构建 CPU 程序。
- `tools/build_katago_web.sh`：构建 WASM CPU，要求 Emscripten 6.0.3。
- `flutter test`、`dart analyze lib test`：验证配置、模型、界面和游戏行为。
- `python3 tools/package_lan_android.py --debug`：构建包含 Web 客户端的 Android APK。
- `python3 tools/test_katago_web.py`：实际 WASM 搜索验证，需要 Selenium 和 Firefox。
