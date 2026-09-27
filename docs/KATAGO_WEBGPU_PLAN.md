EasyPlay KataGo WebGPU 实现计划

状态：实施中。W1 已完成本地无 COOP/COEP 响应头的隔离与 Eigen `genmove` / `adjudicate` 验证；W2 已构建独立 WebGPU Search ABI；W3 的 b6 两个局面 WebGPU/Eigen NN 对照通过；W4 的独立浏览器页已完成 GPU 分析与黑白双方 Search，Android 16 Chrome 在正式 Pages URL 的同一烟测页也通过。Node 验证单线程 b6 Eigen 回退。EasyPlay 桥接、终局裁定、自动回退与性能验收仍待完成。

当前固定源码：`saigo-online/katago-webgpu@d5ad1c0423dba989c60a2f06b1848e7eec2b5941`，Emscripten `6.0.3`，emdawnwebgpu `v20260423.175430`，Eigen `3.4.0@3147391d946bb4b6c68edd901f2add6ac1f31f8c`。fork 的浏览器构建导出 `kataeval-mt` C ABI；它包含 Search，但没有现有 GTP `genmove` / `final_score` 接口。接入 Flutter 前必须实现等价的桥接与裁定，并完成结果对照，不能直接替换 `web/katago/`。fork 对应的 upstream KataGo 提交尚未核实。线程版强制 CPU 时，独立浏览器页的评估调用返回 `unwind`；自动回退因此仍需解决。

本地构建：`bash tools/build_katago_webgpu.sh` 和 `bash tools/build_katago_webgpu.sh single`；CPU 回退烟测：`node tools/test_katago_webgpu.mjs`。产物位于 `web/katago-webgpu/`，当前正式引擎仍使用 `web/katago/`。

浏览器 NN 对照页：`web/katago_webgpu_smoke.html`；Search 对照页：`web/katago_webgpu_search_smoke.html`。需从具备 cross-origin isolation 的静态服务器打开；前者对 b6 的空棋盘和中心有黑子的局面比较 WebGPU/Eigen FP32 输出，后者运行 GPU 分析与黑白双方 Search。CI 不具备真实浏览器 GPU，因此这两项仍需在 GPU 环境复验。

Pages 隔离还要求 `web/flutter_bootstrap.js` 不注册 Flutter 自带的 Service Worker；否则它会取代 `coi-serviceworker.js`，随后自行注销，导致下次访问失去隔离。2026-09-27 本地复验：启动 Flutter 后打开无脚本状态页，controller 仍为 `coi-serviceworker.js`，`crossOriginIsolated === true`，`SharedArrayBuffer` 可用。正式 Pages 上的同项复验待完成。

目标是在 GitHub Pages 上运行支持完整 KataGo Search 的 WebGPU 版围棋引擎，同时保留现有 Web Eigen/WASM CPU 路径作为回退。

最终目标架构：

GitHub Pages
    ↓
coi-serviceworker
    ↓
Cross-Origin Isolation
    ↓
WASM pthread KataGo
    ↓
┌────────────────────┐
│ NN backend         │
├────────────────────┤
│ WebGPU（优先）     │
│ Eigen WASM（回退） │
└────────────────────┘
    ↓
EasyPlay 现有 JS bridge
    ↓
Flutter Web

现有 Android OpenCL 路径不受本计划影响。

---

1. 当前基线

EasyPlay 当前 Web KataGo：

KataGo v1.18.2
USE_BACKEND=EIGEN
Emscripten 6.0.3
WASM SIMD
pthread × 4

构建脚本：

tools/build_katago_web.sh

主要产物：

web/katago/katago.js
web/katago/katago.wasm
web/katago/katago.worker.js

现有调用链：

Flutter
  ↓
katago_bridge.js
  ↓
katago_worker.js
  ↓
KataGo WASM

当前已经支持：

genmove
analyze
analyzeCancel
adjudicate

现有 Web 引擎已经能在具备 COOP/COEP 的环境下实际运行 KataGo v1.18.2。

---

2. 目标

第一阶段目标不是提高最大棋力，而是建立一个稳定、可回退、可验证的 WebGPU 后端。

必须满足：

1. GitHub Pages 可以运行完整 KataGo。
2. 支持 WebGPU 时优先使用 GPU。
3. WebGPU 不可用时可以回退 Eigen CPU。
4. 不改变 Flutter 层现有引擎 API。
5. Android KataGo 行为不受影响。
6. WebGPU 与 Eigen 对相同模型、相同局面产生合理一致的 NN 输出。
7. "genmove"、"analyze"、"adjudicate" 全部可以工作。
8. WebGPU 初始化失败不能导致整个 Web App 崩溃。
9. 构建必须固定上游 commit，避免不可复现构建。
10. CI 至少验证构建和 CPU fallback。

---

3. 非目标

第一阶段暂不做：

- 自己从零实现 KataGo WebGPU backend
- 自己重写 KataGo MCTS
- 强制所有浏览器支持 WebGPU
- 默认使用 FP16
- 删除 Eigen backend
- 修改 Android OpenCL 实现
- 追求桌面 RTX 级最高性能
- GitHub Pages 以外的平台专项优化

---

4. 技术路线

使用已有 KataGo WebGPU fork 作为基础，而不是直接修改 upstream KataGo 的 Eigen backend。

构建目标：

KataGo Search / AsyncBot
        ↓
NNEvaluator
        ↓
WebGPU backend
        ↓
Emscripten WebGPU / emdawnwebgpu
        ↓
Browser WebGPU

同时保留：

NNEvaluator
    ↓
Eigen
    ↓
WASM SIMD CPU

后端选择原则

默认：

auto

逻辑：

if WebGPU 可用:
    WebGPU
else:
    Eigen

未来 UI 可以提供：

计算后端

自动
WebGPU
CPU

第一阶段可以先不暴露用户设置，只实现 "auto"。

---

5. GitHub Pages Cross-Origin Isolation

当前 threaded KataGo 使用：

-pthread
SharedArrayBuffer

GitHub Pages 本身不能直接配置：

Cross-Origin-Opener-Policy
Cross-Origin-Embedder-Policy

因此使用：

coi-serviceworker

实现客户端 cross-origin isolation。

D1：接入 coi-serviceworker

加入：

web/coi-serviceworker.js

并在：

web/index.html

中尽可能早地加载：

<script src="coi-serviceworker.js"></script>

必须位于：

katago_bridge.js
flutter_bootstrap.js

之前。

验证

GitHub Pages 实际部署后检查：

window.crossOriginIsolated
typeof SharedArrayBuffer
navigator.gpu

预期支持环境：

crossOriginIsolated == true
SharedArrayBuffer 可用

首次访问允许发生一次 Service Worker 注册后的自动刷新。

退出标准

GitHub Pages 部署环境中：

crossOriginIsolated === true

且当前 Eigen pthread KataGo 能正常完成：

genmove
adjudicate

WebGPU 尚未接入前，必须先完成这一阶段。

---

6. 固定 WebGPU KataGo 源码

不要让构建脚本直接跟踪 fork 的 main。

新增明确 pin：

KATAGO_WEBGPU_REPO=...
KATAGO_WEBGPU_COMMIT=...

原则与当前：

KATAGO_COMMIT
EIGEN_COMMIT
EMSDK_VERSION

一致。

建议保留当前 upstream KataGo 构建方式，并将 WebGPU fork 单独作为 Web 专用 source。

例如：

.build/
├── katago-web/
│   ├── emsdk/
│   ├── eigen/
│   └── KataGo-WebGPU/

Android 继续使用：

lightvector/KataGo

Web 使用：

WebGPU fork

必须记录：

fork commit
对应 upstream KataGo commit/tag
WebGPU backend revision
Emscripten version

退出标准

执行两次全新构建得到一致版本信息，且 source tree dirty 时构建脚本拒绝继续。

---

7. 新建 WebGPU 构建脚本

不要立即覆盖稳定的：

tools/build_katago_web.sh

第一阶段增加：

tools/build_katago_webgpu.sh

两套产物并存。

建议输出到：

web/katago-webgpu/

例如：

web/
├── katago/
│   ├── katago.js
│   ├── katago.wasm
│   └── katago.worker.js
│
└── katago-webgpu/
    ├── katago.js
    ├── katago.wasm
    └── katago.worker.js

旧版作为稳定基准。

---

8. WebGPU 构建配置

WebGPU 构建必须保持：

WASM SIMD
pthread
exceptions
memory growth
filesystem

即现有：

-pthread
-msimd128
-fexceptions
-sALLOW_MEMORY_GROWTH=1

等配置尽量不变。

新增 WebGPU 所需 Emscripten port，例如：

emdawnwebgpu

不要继续使用废弃的旧式 WebGPU 编译参数。

后端目标：

USE_BACKEND=WEBGPU

具体参数以 pin 的 fork 实现为准。

---

9. 保留现有 JS API

WebGPU 接入不应该导致 Flutter 层知道：

Eigen
WebGPU

Flutter 仍然只面对当前引擎接口。

例如：

available()
start()
genmove()
analyze()
analyzeCancel()
adjudicate()
stop()

后端差异全部留在：

katago_bridge.js
katago_worker.js

或新的引擎 loader 内。

目标：

Flutter 无需因为 WebGPU 修改调用协议

---

10. Backend Probe

增加一个明确的 capability probe。

建议 JS 返回：

{
  "crossOriginIsolated": true,
  "sharedArrayBuffer": true,
  "webgpu": true,
  "backend": "webgpu"
}

WebGPU 检测至少包含：

navigator.gpu != null

以及实际：

requestAdapter()
requestDevice()

成功。

不能仅判断：

'navigator.gpu' in navigator

因为：

浏览器支持 API
≠
当前 GPU/驱动能创建 device

---

11. 后端回退

目标逻辑：

尝试 WebGPU
    ↓
成功 ─────→ WebGPU
    ↓失败
记录错误
    ↓
启动 Eigen

以下情况必须 fallback：

- "navigator.gpu" 不存在
- "requestAdapter()" 返回 null
- "requestDevice()" 失败
- shader 编译失败
- 模型加载失败
- WebGPU backend 初始化异常
- GPU device lost

第一阶段 device lost 可以：

停止当前 session
↓
显示引擎重启
↓
重新启动 Eigen

不要求无缝迁移搜索树。

---

12. 模型兼容

WebGPU 后端必须至少支持 EasyPlay 当前内置：

b6

在考虑把 WebGPU 作为默认路径前，再验证：

modelVersion 8
modelVersion 17

如果未来 Web 支持下载模型，则必须继续使用 EasyPlay 现有模型兼容检查。

不能出现：

UI 接受模型
↓
WebGPU backend 实际无法解析

---

13. 正确性验证

WebGPU 的第一目标是结果正确，不是 benchmark。

建立：

tools/test_katago_webgpu.py

或扩展：

tools/test_katago_web.py

至少测试：

NN 基础

固定模型、固定局面。

比较：

Eigen
WebGPU

允许浮点误差，但应验证：

policy 排序基本一致
value 合理接近
scoreLead 合理接近
无 NaN
无 Infinity

---

GTP / Search

至少：

boardsize 9
komi 7.5
play
genmove
genmove
final_score

并测试：

analyze
analyzeCancel

---

EasyPlay 路径

真正从：

Flutter Web
↓
bridge
↓
worker
↓
WebGPU KataGo

跑一次：

AI 对局

不能只测试裸 KataGo binary。

---

14. GitHub Pages 真机验收

必须使用真正 GitHub Pages URL。

不能只用：

localhost

因为 Service Worker、scope、base href 和 Pages 子路径都可能产生差异。

测试矩阵建议：

Desktop Chrome
Desktop Edge
Android Chrome

如果可以再加：

ChromeOS
Safari（如果 WebGPU 环境可用）
Firefox（根据届时 WebGPU 支持情况）

记录：

crossOriginIsolated
navigator.gpu
GPU adapter
backend
模型加载时间
首手时间
稳定 visits/s
内存占用
是否发生 device lost

---

15. 性能基线

在 WebGPU 接入前保存 Eigen 基准。

固定：

设备
浏览器版本
模型
棋盘
visits
threads

至少测：

引擎初始化时间
模型加载时间
首手时间
连续 10 手平均时间
analyze visits/s
内存占用

然后同一设备对比：

Eigen WASM
vs
WebGPU

第一阶段不设“必须快 N 倍”的硬指标。

退出标准只要求：

WebGPU 明显不是退化路径
且运行稳定

---

16. Batch 调优

WebGPU 的价值很大程度取决于 batch。

不能直接把 Android OpenCL 参数照搬过来。

后续测试：

batch 1
batch 2
batch 4
batch 8
batch 16

分别记录：

NN eval/s
Search visits/s
latency
GPU 使用情况
内存

移动设备尤其需要平衡：

大 batch → 吞吐高
大 batch → 单步延迟可能增加

AI 对弈和实时分析可以最终采用不同配置。

---

17. FP16

第一阶段：

只使用 FP32

不要默认请求：

shader-f16

FP16 放在第二阶段实验。

启用前要求：

模型兼容验证
局面输出对照
长时间搜索稳定性
无 activation overflow

以后如果加入：

WebGPU FP16

应该是 capability-based：

adapter.features.contains("shader-f16")

而不是默认假设支持。

---

18. UI

第一阶段 UI 尽量简单。

引擎设置可以显示：

Web 引擎

后端：WebGPU
GPU：xxxx
线程：4

fallback 时：

WebGPU 不可用，正在使用 CPU

不要直接把底层异常堆栈显示给普通用户。

详细信息放：

引擎诊断

例如：

crossOriginIsolated: yes
SharedArrayBuffer: yes
WebGPU API: yes
Adapter: Qualcomm Adreno ...
Backend: WebGPU FP32

---

19. GitHub Pages 与 LAN Web 共存

EasyPlay 有两个 Web 使用场景：

A. GitHub Pages
B. Android LAN 主机内置 Web 页面

两者必须都验证。

GitHub Pages

依赖：

coi-serviceworker

实现 cross-origin isolation。

Android LAN Host

现有：

HttpServer

已经直接设置：

Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp

因此 LAN 页面不应依赖 Service Worker 才能正常工作。

最好让：

有真实 COOP/COEP header
→ coi-serviceworker 不干预

无 header
→ coi-serviceworker 接管

避免 Android LAN 模式多余刷新。

---

20. 打包体积

WebGPU 接入后监控：

katago.wasm
katago.js
shader / embedded data
Android LAN APK
GitHub Pages artifact

当前 Android APK 会内置整个 Web bundle，因此：

WebGPU 增加多少 Web 体积
≈ APK 也会增加多少

如果 WebGPU backend 导致 WASM 明显膨胀，应记录差值。

不要在第一阶段为了几十 MB 以内的增长提前做复杂拆包，先完成稳定性验证。

---

21. 缓存

GitHub Pages 更新 WebGPU binary 时必须避免：

旧 JS + 新 WASM

或：

新 JS + 旧 WASM

混用。

建议最终给 KataGo 资源做版本化，例如：

katago/v1.18.2-webgpu-r1/

或者构建时加入内容 hash。

Service Worker 更新也需要纳入测试。

---

22. CI

现有 CI 保持：

dart analyze
flutter test
flutter build web
Android debug LAN package

增加 WebGPU 构建检查后：

build_katago_webgpu.sh

不一定每次普通 push 都重新编译 KataGo。

可以单独：

workflow_dispatch

或仅当以下文件变化：

tools/build_katago_webgpu.sh
WebGPU pin
bridge
worker
模型

时执行。

普通 Flutter CI 继续使用已提交的 WebGPU 产物。

---

23. GitHub Pages workflow

Pages 构建继续：

flutter build web \
  --release \
  --no-wasm-dry-run \
  --base-href /easyplay/

发布前检查：

coi-serviceworker.js 存在
katago WebGPU JS 存在
katago WASM 存在
模型存在

必要时 CI 直接失败，而不是发布一个缺引擎资源的页面。

---

24. 回滚机制

WebGPU 进入主分支之前必须保留：

Eigen-only build

至少一个版本周期。

如果线上出现：

特定 GPU crash
driver bug
WebGPU device lost
shader 编译错误

可以快速：

forceBackend = eigen

而不需要重新设计 Flutter UI。

未来可考虑远端静态配置：

disabledAdapters
disabledVendors

但第一阶段不需要。

---

25. 开发顺序

W1：Pages isolation

实现：

coi-serviceworker

验证 GitHub Pages 上当前 Eigen threaded KataGo。

退出标准：

crossOriginIsolated == true
SharedArrayBuffer 可用
现有 KataGo 可以 genmove

---

W2：独立 WebGPU binary

新增：

build_katago_webgpu.sh

固定 fork commit。

退出标准：

WebGPU KataGo 可以在本地页面启动
模型加载成功

---

W3：NN 正确性

对照：

WebGPU
Eigen

固定测试局面。

退出标准：

无明显输出错误
无 NaN/Inf
主要输出在允许误差范围内

---

W4：完整 Search

接通：

genmove
analyze
analyzeCancel
adjudicate

退出标准：

现有 EasyPlay Web 引擎 smoke test 全部通过。

---

W5：EasyPlay bridge

让 Flutter 使用 WebGPU binary。

退出标准：

AI 对局
分析
终局裁定

均可实际使用。

---

W6：自动 fallback

实现：

WebGPU → Eigen

退出标准：

人为禁用 WebGPU 后应用仍然可以启动 CPU AI。

---

W7：GitHub Pages 实测

部署正式 Pages。

退出标准：

至少：

Desktop Chromium
Android Chrome

完整完成一局 AI 对弈。

---

W8：性能调优

测试：

batch
threads
memory

确定默认值。

---

W9：默认启用

满足以下条件后将 WebGPU 设置为 Web 默认：

正确性通过
fallback 可用
Pages 实测通过
移动设备稳定
没有明显内存泄漏

---

26. 测试清单

发布前：

- [ ] GitHub Pages "crossOriginIsolated == true"
- [ ] SharedArrayBuffer 可用
- [ ] WebGPU adapter 获取成功
- [ ] WebGPU device 创建成功
- [ ] 内置 b6 模型加载成功
- [ ] CPU fallback 可用
- [ ] "genmove" 正常
- [ ] "analyze" 正常
- [ ] "analyzeCancel" 正常
- [ ] "adjudicate" 正常
- [ ] 黑白双方都能 AI 落子
- [ ] 9 路正常
- [ ] 13 路正常
- [ ] 19 路正常
- [ ] 中国规则正常
- [ ] 日本规则正常
- [ ] 韩国规则正常
- [ ] 连续运行分析不会无限增内存
- [ ] 页面切出再返回不会残留多个引擎
- [ ] 引擎 dispose 后 worker 结束
- [ ] GPU device lost 有处理
- [ ] 不支持 WebGPU 的浏览器不会白屏
- [ ] Android LAN Web 页面仍正常
- [ ] GitHub Pages base href 正常
- [ ] Service Worker 更新正常
- [ ] 首次访问刷新行为可接受

---

27. 最终期望架构

                           EasyPlay
                              │
                    GoEngineRuntime
                              │
                         Web Bridge
                              │
                    KataGo Web Worker
                              │
                  ┌───────────┴───────────┐
                  │                       │
              KataGo Search          Game Rules
                  │
              NNEvaluator
                  │
        ┌─────────┴──────────┐
        │                    │
     WebGPU                Eigen
        │                    │
 Browser GPU          WASM SIMD CPU
        │                    │
        └─────────┬──────────┘
                  │
               fallback

Android 保持：

KataGo
├── OpenCL
└── Eigen

Web 变成：

KataGo
├── WebGPU
└── Eigen

这样 Android 与 Web 的结构保持对称，同时规则、模型管理、AI 设置和 Flutter UI 不需要依赖具体 GPU API。

---

28. 完成定义

只有同时满足以下条件，WebGPU 才算完成，而不是“能跑一个 demo”：

1. GitHub Pages 正式 URL 可以启动。
2. 完整 KataGo Search 工作。
3. AI 对局正常。
4. 分析正常。
5. 终局裁定正常。
6. WebGPU 不可用时 CPU fallback 正常。
7. 不需要修改 Flutter 游戏规则代码。
8. 不影响 Android OpenCL。
9. 已有 Web 回归测试继续通过。
10. 至少一个桌面 Chromium 和一个 Android Chrome 真机通过。
11. WebGPU 失败不会导致应用无法进入棋盘。
12. 构建版本和 WebGPU fork commit 完全可复现。

达到以上条件后，再考虑：

FP16
更大模型
自动 batch 调优
GPU 黑名单
更细的性能档位

而不是在第一阶段提前增加复杂度。
