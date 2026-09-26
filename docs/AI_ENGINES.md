# AI 引擎开发与使用

参考资料为 `upstream/围棋大师_1.4.0.apks` 中的配置、资源和可观察行为；仓库没有该应用的原始 Dart 源码。EasyPlay 自行构建固定版本 KataGo v1.16.5，通过标准 GTP 接入。

## 使用入口

在设置的「AI 引擎」中新增或编辑配置。配置可以绑定主模型和独立人类棋风模型、选择运行后端、调整线程与时间、导入完整 `.cfg`、设置 override。内置配置也能编辑和恢复默认；右上角导入 JSON，单个配置的菜单可导出 JSON、设为默认及进入运行与调优页面。

围棋新局设置会应用默认引擎及其绑定模型，也可以临时更换模型。不可用的引擎会回退为本地摆棋/双人模式。

| 功能 | Android arm64 | 静态 Web |
| --- | --- | --- |
| 内置 b6、其他标准 `.bin.gz` / `.txt.gz` | CPU 或 OpenCL | WASM CPU |
| 人类棋风主模型 / 独立 human model | CPU 或 OpenCL | WASM CPU，受浏览器内存和性能限制 |
| 自定义 cfg、global / rank override | 支持 | 使用相同配置合并器 |
| OpenCL GPU 探测、调优、日志、取消、缓存清理 | 支持，取决于设备驱动 | 无浏览器 OpenCL；选择该配置时使用 WASM CPU |
| TFLite Mobile | 尚未提供可运行后端 | 不支持 |

TFLite 类型可导入和保存，但不会被冒充为 CPU 模型执行，也不会静默替换成 b6。上游 KataGo 没有参考 APK 中的私有 LiteRT 后端，该共享库也没有公开会话 ABI。

## 人类棋风

1. 在模型管理选择「人类棋风网络」，导入文件或使用下载对话框中的官方 b18 人类模型地址。
2. 新建或编辑引擎：主模型可以继续使用 b6，另选独立人类模型；也可以直接把人类网络设为主模型。
3. 在新局选择「人类棋风」，选择 20k～9d 段位。使用人类网络作为主模型时启用「使用主模型内置人类棋风」，不再加载独立模型。
4. `humanSLProfile` 留空时按段位生成，例如 `rank_5k`、`rank_1d`。可显式填写 `preaz_5k` 等 KataGo 支持的段位配置。

段位内部编码与参考资源一致：20k=20、1k=1、1d=0、9d=-8。默认人类规则有 20k～4d、5d～6d、7d～9d 三组。段位是模型条件参数，不是对真实棋力的保证。

导入时检查扩展名、gzip 完整性/CRC、KataGo 模型头、metadata encoder 和可选 SHA-256；模型的实际内容决定类型，普通模型不能标为 human。原生引擎加载时还会检查网络张量。大模型当前需要完整解压校验，导入和运行都应留出充足内存。

下载后保存在设备/浏览器本地。Web 下载地址必须允许 CORS；不允许跨域的地址可先在浏览器下载，再从文件导入。被引擎配置引用的模型需解除绑定后才能删除。

## 配置覆盖顺序

`lib/go_engine_config.dart` 生成 Android 和 Web 共用的最终配置。后者覆盖前者：

1. `assets/katago/android_gtp.cfg` 默认值。
2. 新局棋力、风格和引擎线程/时间。
3. 人类模式命中的内置段位 cfg。
4. 引擎的完整自定义 cfg。
5. 普通或人类模式的自定义 global 规则，再合并命中的段位规则。
6. 引擎的最终 `configOverrides` 文本。
7. 当前对局的棋盘、规则、贴目、human profile 和实际运行后端。

配置采用 `key = value` 格式，支持 `#` 注释；合并后每个键只有一个值。不能用旧 cfg 覆盖新局选择的规则；相冲突的 `koRule`、`scoringRule` 等细项会被移除。普通模式不保留 humanSL 参数；Web 不保留 OpenCL 参数。时间为 0 表示不限制时间，搜索仍受 `maxVisits` 约束。

global 可与段位规则共同生效；同一组只允许一条 global，段位区间不允许重叠。普通规则依据普通棋力选择，人类规则依据人类段位选择。引擎导出的 JSON 包含规则范围和内容，但不包含模型文件，换设备需要另行导入相同模型。

## Android OpenCL

编辑引擎时选择 OpenCL，设置 GPU 编号和驱动库名称（默认 `libOpenCL.so`）。在「引擎运行与调优」页检查设备，选定主模型和棋盘后开始调优。新局也提供当前配置的调优入口。模型推理、驱动探测和调优均在子进程中执行。

调优同时覆盖主模型与独立人类模型。成功后保存经过文件校验的缓存；未完成调优时不会启动 OpenCL 对局。缓存标识包含模型、棋盘、GPU、驱动、Android 系统指纹、引擎版本和神经网络/OpenCL 参数。修改贴目、规则、段位或思考时间不会无谓废弃调优结果。

可以查看日志、取消调优、清除该配置记录的缓存。退出调优页会取消任务；取消和退出对局不会等待长搜索结束。重新选择模型、棋盘或设备后，按实际组合重新调优，不能只依赖页面保存的「已调优」状态。

重建与通道契约见 [原生引擎说明](../tools/native/README.md)：

```bash
tools/build_katago_android.sh all
flutter build apk --debug
```

## 完全静态 Web

AI 在同源 Web Worker / WASM 内运行，没有推理服务器或账号服务。打包后上传整个 `build/web`。静态主机必须在 HTTPS 下提供以下响应头（localhost 可使用 HTTP）：

```text
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

`web/_headers` 提供 Netlify/Cloudflare Pages 格式；Nginx、Caddy 或 CDN 需设置等效响应头。GitHub Pages 无法自行设置这些响应头，其默认部署只能使用本地摆棋模式。普通 Python HTTP server 也不会提供隔离响应头，本地完整 AI 预览请运行：

```bash
flutter build web --release
python3 tools/serve_web.py --port 8080
```

每次应手创建 Worker 并重放当前棋谱，退出时终止 Worker。Web OpenCL 配置实际使用 WASM CPU，不会调用设备 OpenCL。浏览器内存限制会影响 b18 等大模型。

## 代码与验证

| 文件 | 职责 |
| --- | --- |
| `lib/go_engine_profiles.dart` | 后端、绑定模型、配置、override 规则和持久化 |
| `lib/go_ai_settings.dart` / `go_human_profiles.dart` | 对局棋风、段位、人类默认资源 |
| `lib/go_models.dart` | 模型类型、完整性、安装、兼容性 |
| `lib/go_engine_editor.dart` / `go_engine_runtime.dart` | 配置编辑、设备检测、调优 |
| `lib/go_engine_config.dart` | 跨平台唯一配置合并器 |
| `lib/katago.dart` | Android / Web 模型装载和 GTP 调度 |
| `android/.../AndroidKataGoGtp.kt` | Android 子进程、探测、调优缓存、取消 |
| `web/katago_worker.js` | 静态 WASM 执行和错误回传 |

运行 `flutter test`；构建 Web 后使用安装了 Selenium、Firefox 的 Python 运行 `tools/test_katago_web.py`。该测试实际验证 9/13/19 路、终局、完整 configText、错误配置恢复和 GTP 错误传播。

设备验证已在 Android API 36 / Adreno 830 上完成 b6 9 路 OpenCL 调优并落子 F5；CPU 以 b6 配合官方 b18 human、`rank_5k` 成功落子 F6。OpenCL 与 b18 human 的组合、其他厂商 GPU 仍需实际设备验证。人类模型管线另有配置、类型和通道测试。
