# EasyPlay 开发文档

本文档是 EasyPlay 的开发基线。它同时说明当前版本能做什么、代码应该放在哪里、怎样运行和验收，以及后续需求应该怎样描述。实现与文档不一致时，先更新代码和测试，再更新本文档；不要把尚未实现的计划写成已完成能力。

**文档适用版本**：Flutter 3.44.0 / Dart 3.12.0；当前产品范围是本地围棋与本地棋谱，Android/Web 为主要平台。文档中的“支持”表示已有代码和测试覆盖，“计划”表示尚未实现。

## 围棋稳定性修复记录

这轮优先修复已复现的棋局损坏、保存和交互问题：

- 停一手后悔棋会恢复准确的连续停一手计数；双停进入“待确认计分”，支持确认、整块死子标记/取消、红叉显示、继续对局。
- 双方各停一手后，Android 与 Web 自动调用 KataGo `final_status_list dead` 和 `final_score` 裁定死子与最终结果；KataGo 将双活（seki）保留为活棋，并按当前规则处理循环劫争后的终局。引擎不可用时保留手动标记和确认流程。
- 中国规则当前采用位置超级劫，日韩使用简单劫；这是当前程序采用的规则约定，不代表所有地区赛事的循环局面处理完全相同。
- 9/13/19 路星位、走法记录坐标及2–9子让子布局已修正；6/8子不再错误占据天元。1子让子不作为固定摆子模式。
- 设置会验证贴目；切换设置/导入/恢复时取消旧电脑任务，避免在新局面补走。让子局会调度白方电脑。
- SGF 改用严格树解析，主变化回放不串入其他分支；多值属性、转义、中文UTF-8、初始摆子、PL及实际落子方得到保留。
- SGF 导入可选择主线或变例；已导入棋谱可切换到其他完整变化。沿选中变化编辑时只裁掉该变化被改写的后续，保留同一分支点的兄弟变化。
- 未修改的导入棋谱及其续弈保留评论、属性和分支；在主线悔棋后再导出会裁剪撤销点之后的内容。请先导出备份再编辑有价值的分支。
- 中途摆子、多个棋局的集合、终止后的继续落子、其他棋盘尺寸和其他规则会明确报错，不再静默改盘或漏着。
- Web SGF 导出使用浏览器 Blob 下载；Android 继续使用系统文件保存。旧版 file_picker 的 Web saveFile 未实现，现已绕开。
- 自动保存覆盖人/电脑落子、悔棋、重开、设置、停一手、计分和模式切换，写入串行执行。最近20条按棋局ID更新，不再每一步产生一盘。
- 围棋更多菜单提供“恢复上次对局”和“对局记录”。导入/从列表载入默认本地双人；恢复上次对局同时恢复模式。
- 测试文件：go_regression_test.dart、go_storage_test.dart、go_widget_regression_test.dart。

仍未完成：Web 静态端 KataGo 的跨源隔离部署验证、逐手 SGF 浏览/分支树编辑/中途摆子复盘。Android 和 Web 均已接入本地 KataGo b6 推理；Web 静态主机需配置 COOP/COEP 响应头。

## 1. 项目定位

EasyPlay 是一个 Flutter 跨平台棋类应用，主要平台是 Android 和 Web，最终支持三类棋：

- 围棋（Go）
- 国际象棋（Chess）
- 跳棋/西洋跳棋（Checkers）

当前项目参考目录中的 `upstream/围棋大师_1.4.0.apks` 进行围棋交互和 KataGo 集成；该 APK 只作为行为参考，项目没有可复用的原始 Dart 源码。

当前版本聚焦本地围棋。已支持 9/13/19 路、停一手、让子/自定义贴目、日韩/中国规则、KataGo b6、本地保存与 SGF 导入导出。国际象棋和跳棋仍在首页展示为未完成状态，不能进入。每日题目、统计、排行榜、积分、账号、联机与云同步不属于当前产品，也没有对应入口或数据服务。

### 1.1 当前能力清单

| 模块 | 当前状态 | 说明 |
| --- | --- | --- |
| 首页 | 已实现 | 围棋入口；国际象棋和跳棋标记未完成且不可进入 |
| 围棋对局 | 已实现 | 人机模式和本地双人模式；新局要求确认棋盘与规则，默认 19 路、中国规则、7.5 贴目 |
| 棋盘交互 | 已实现 | 选择棋子、显示合法目标、落子/移动、非法操作拦截 |
| 悔棋/重开 | 已实现 | 规则层使用快照；人机模式一次悔棋撤回人和电脑各一步 |
| SGF 棋谱 | 已实现 | 本地保存、恢复、记录列表、导入、导出、变化选择 |
| 终局裁定 | 已实现 | KataGo 自动返回死子及最终胜负；不支持引擎的平台提供手动确认 |
| 题库/统计/排行榜/积分 | 已移除 | 首页和对局流程中无相关功能入口 |
| 账号/联机/云同步 | 已移除 | 无账号、远端对局或云端数据服务；KataGo 模型获取属于独立的引擎资源下载 |

## 2. 技术栈与版本

| 项目 | 当前值 |
| --- | --- |
| Flutter | 3.44.0 stable |
| Dart SDK | 3.12.0 |
| Android Gradle Plugin | 9.4.1 |
| Gradle Wrapper | 9.6.0 all |
| Kotlin Gradle Plugin | 2.3.20 |
| Android 编译方式 | Kotlin DSL (`*.gradle.kts`), app/plugin compileSdk 36 |
| UI | Flutter Material 3 |
| 依赖 | Flutter、cupertino_icons、http、crypto、web、file_picker、shared_preferences |

版本来源：`pubspec.yaml`、`android/settings.gradle.kts` 和 `android/gradle/wrapper/gradle-wrapper.properties`。升级 Gradle 时必须同时确认 AGP、Kotlin 和 Flutter 版本的兼容性，不要只改 Wrapper URL。

Android Studio 应打开项目根目录 `/home/fruit/项目/easyplay`，不要只打开 `android/` 子目录。

## 3. 目录结构

```text
.
├── lib/
│   ├── main.dart             # 应用入口与首页
│   ├── game_page.dart        # 围棋对局页面与交互调度
│   ├── board.dart            # 棋盘绘制
│   ├── game_session.dart     # 棋局状态与围棋规则
│   ├── games/                # 棋类页面入口（当前仅围棋可进入）
│   ├── go_sgf.dart           # 围棋 SGF FF[4] 导入/导出、评论和变化树
│   └── katago.dart           # KataGo 模型目录、下载客户端和 GTP 客户端
├── test/
│   ├── game_session_test.dart # 围棋、国际象棋、跳棋规则测试
│   └── widget_test.dart       # 首页和开局页面冒烟测试
├── android/                  # Android 容器、Gradle 和应用配置
├── web/                      # Web 壳、图标和 manifest
├── upstream/                 # 参考资料；当前包含围棋大师 APK
├── docs/
│   └── DEVELOPMENT.md        # 本文档
├── pubspec.yaml              # Dart/Flutter 依赖和版本
└── analysis_options.yaml     # Dart lint 配置
```

当前首页位于 `lib/main.dart`，围棋页面位于 `lib/game_page.dart`，棋盘绘制位于 `lib/board.dart`，状态与规则位于 `lib/game_session.dart`。新增围棋能力时优先沿现有职责扩展，避免将规则塞进 Widget。

实际存在的棋类入口文件为 `lib/games/go_game.dart`、`lib/games/chess_game.dart`、`lib/games/checkers_game.dart`。国际象棋和跳棋入口保留类型标识，但首页不可进入。

## 4. 当前应用流程

### 首页

首页显示 EasyPlay 品牌和三种棋类卡片。围棋可以开始新局；国际象棋和跳棋显示未完成状态并禁止进入。

开始围棋后必须先设置棋盘与规则。默认 19 路、中国规则、7.5 贴目；日本和韩国规则默认 6.5 贴目。对局更多菜单提供规则设置、SGF 导入导出、恢复和本地记录。

### 对局页

对局页包含：

- 棋盘
- 当前回合和结束状态
- KataGo 人机/本地双人模式
- 落子或移动记录
- 本局吃子/提子数
- 悔棋
- 重新开始
- 围棋停一手
- 本地对局记录

电脑默认使用白方。切换为本地双人后，黑白双方都由用户操作。

### 4.1 对局状态流转

```text
首页选择棋种
    -> GamePage 创建 GameSession
    -> 用户点击棋盘
    -> GameSession 校验并修改状态
    -> setState 重绘棋盘和侧栏
    -> 若是 KataGo 人机模式且轮到电脑方，延迟约 300ms 请求 KataGo
    -> 对局结束或用户执行悔棋/重开
```

`GamePage` 只负责输入、页面状态和调度；规则判断必须放在 `GameSession`。新增按钮时要明确它改变的是页面状态还是棋局状态，避免把规则逻辑写进 Widget 回调。

## 5. 游戏状态模型

定义在 `lib/game_session.dart` 中。

### 基础类型

```dart
enum GameType { go, chess, checkers }
enum Side { black, white }
enum PieceKind { stone, pawn, rook, knight, bishop, queen, king, checker }
```

`Cell(row, col)` 使用 0 开始的行列坐标：

- 围棋：`row`、`col` 表示棋盘交叉点，范围 `0..8`
- 国际象棋/跳棋：`row`、`col` 表示棋盘格，范围 `0..7`
- 国际象棋和跳棋的 `row = 0` 是黑方初始侧，白方从底部开始
- 显示文本会把列转换为 A-H；围棋行号显示为 9-1

`GamePiece` 由 `Side` 和 `PieceKind` 组成。

`GameMove` 包含：

- `from`：移动类棋种的起点，围棋为空
- `to`：终点；围棋停一手使用 `Cell(-1, -1)`
- `captured`：本步是否吃子/提子
- `pass`：是否停一手

### `GameSession`

`GameSession` 是唯一负责规则和对局状态的对象。UI 不应直接修改棋盘内容，应该调用这些方法：

| 方法 | 用途 |
| --- | --- |
| `reset()` | 新建一盘棋 |
| `pieceAt(cell)` | 读取某个位置 |
| `placeGo(cell)` | 围棋落子 |
| `passGo()` | 围棋停一手 |
| `legalMovesFrom(cell)` | 获取当前方某棋子的合法目标 |
| `movePiece(from, to)` | 国际象棋/跳棋移动 |
| `undo()` | 恢复上一步 |

状态字段的含义：

| 字段 | 含义 |
| --- | --- |
| `board` | 当前棋盘；规则层内部可变，UI 只读 |
| `turn` | 当前轮到哪一方 |
| `moves` | 已确认的公开走法，停一手也计入 |
| `blackCaptures` / `whiteCaptures` | 各方本局吃子/提子数 |
| `gameOver` / `winner` | 终局标记和胜方；平局时 `winner == null` |
| `_undo` | 每个公开操作前的完整快照，供 `undo()` 恢复 |

每个成功的 `placeGo`、`passGo` 或 `movePiece` 都应产生一个可撤销快照；返回 `false` 的非法操作不能改变回合、棋盘或走法记录。测试可以直接给 `board` 构造局面，但生产 UI 不应绕过规则方法写入棋盘。

### 棋盘重绘约定

`Board` 每次绘制都会向 `BoardPainter` 传递棋盘快照。不要把同一个可变的 `List` 作为旧、新 painter 的状态引用，否则 Flutter 可能判断状态没有变化而跳过重绘。新增棋盘字段时，也要让 `BoardPainter.shouldRepaint` 能检测到变化。

## 6. 当前规则实现

### 围棋

当前支持 9×9、13×13、19×19 棋盘，黑方先手（让子局白方先手），支持：

- 空点检查
- 轮流落子
- 四连气计算
- 提子
- 自杀禁手
- 简单劫争：禁止回到前两步的局面
- 双方连续停一手结束
- 中国规则（子数+地）、日本/韩国规则（地+提子）基础计分
- 自定义贴目、2–9 子让子和标准星位布局
- FF[4] SGF 记录的导入和导出（棋盘、规则、贴目、让子、落子、停一手）
- KataGo 人机对局；引擎不可用时自动切换为本地双人模式
- 按路数绘制星位；九路使用四角星与天元

围棋仍可继续扩展：

- SGF 逐手导航、中途摆子与更完整的分支编辑体验
- KataGo 模型管理与下载的完整用户界面

### 国际象棋

当前使用标准 8×8 初始布局，支持：

- 兵、车、马、象、后、王的基础走法
- 轮流走子
- 吃子
- 兵到最后一排自动升变为后
- 将军检测
- 基础将死/无合法着法检测
- 移动前检查己方王是否处于将军状态

尚未支持：

- 王车易位
- 吃过路兵
- 升变选择
- 三次重复、五十回合和逼和规则
- 完整棋谱记谱（SAN/PGN）
- 专业引擎（Stockfish）

### 跳棋

当前使用 8×8、每方 12 子的西洋跳棋布局，支持：

- 斜向移动
- 单次跳吃
- 有吃子时优先强制吃子
- 普通棋子升王
- 吃子计数

当前一次移动只执行一次跳吃，尚未支持连续多跳、完整结束判定变体和棋谱导出。后续添加规则时，需要先确定采用 American Checkers、International Draughts 还是其他变体，不能直接混用规则。

### 6.1 规则扩展原则

1. 先在文档中确定棋种、棋盘尺寸、先手、胜负、和棋和规则变体。
2. 先在 `GameSession` 增加纯 Dart 规则和单元测试，再接入页面。
3. 所有对外操作都返回明确结果：成功返回 `true`，非法操作返回 `false`；需要展示原因时再增加错误码或结果对象，不要依赖 UI 猜测。
4. 规则变更必须覆盖边界局面：无路可走、吃子、升变、终局、悔棋和重开。
5. 不要让棋盘绘制代码决定合法性；`BoardPainter` 只负责显示状态。

### 6.2 KataGo 不可用时的回退

围棋人机模式只使用 KataGo。Android 引擎启动失败、WebAssembly 初始化失败或局面同步失败时，当前请求会被取消，界面自动切换为本地双人模式；双方随后都由用户手动落子，不会再生成模拟电脑着法。

`assets/katago/` 内置约 3.8 MB 的 g170 b6 网络，运行前校验 SHA-256。Android APK 将 KataGo v1.16.5 arm64 GTP 程序作为 `jniLibs/arm64-v8a/libkatago.so` 打包，使系统提取到可执行的 `nativeLibraryDir`；不要从 `filesDir` 解压并执行，因为部分 Android 设备会对应用可写目录启用 `noexec`。Flutter 通过 `easyplay/katago` MethodChannel 启停进程并串行发送命令，CPU 使用 Eigen 后端，模型和配置复制到应用私有目录。Web 使用相同模型和 KataGo 源码编译的 WASM，在同源 Worker 中推理。WASM 的 pthread 需要浏览器 `SharedArrayBuffer`，所以静态托管必须返回 COOP/COEP 响应头；`web/_headers` 为支持该格式的静态主机提供配置。未启用跨源隔离时 Web 会提示并切换本地双人模式。模型与 KataGo/Eigen 许可证位于 `assets/katago/` 和 `docs/licenses/`。Android 重建运行 `tools/build_katago_android.sh`，要求 Android NDK 28.2.13676358；Web 重建运行 `tools/build_katago_web.sh`，要求 Emscripten 6.0.3。两份脚本都会固定校验 KataGo/Eigen commit。

### 《围棋大师》APK 参考实现核查

`upstream/围棋大师_1.4.0.apks` 是 Android App Bundle 安装包，不是源码仓库。其 APK 暴露了原生 GTP 会话和 b6 模型的实现线索，但没有可复用源码或 ABI 头文件。本项目因此固定上游 KataGo 源码版本并自行构建 arm64 GTP 程序，不依赖猜测 APK 的私有 C ABI。Web Worker 使用标准 KataGo pthread WASM；静态主机需要提供 COOP/COEP 响应头。

## 7. 构建、运行和发布

### 初始化依赖

```bash
flutter pub get
```

### Web 开发运行

Chrome 已安装时，推荐：

```bash
flutter run -d chrome
```

`flutter run -d web-server` 是调试服务器模式，需要 Dart Debug Chrome 扩展。在当前环境中它可能只显示顶部加载条，因此不作为默认预览方式。

### Web 稳定预览

先构建，再使用静态服务器：

```bash
flutter build web
python3 -m http.server 8080 --directory build/web
```

浏览器访问：

```text
http://localhost:8080
```

修改 Dart 代码后，需要重新执行 `flutter build web`，再刷新页面。静态服务器不会自动热更新。

生产 Web 发布时使用 `build/web` 的静态文件，并根据部署平台配置路由回退到 `index.html`。当前项目没有服务端 API；刷新后可从围棋更多菜单恢复上次保存的棋局。

### Web 静态部署清单

```bash
flutter pub get
flutter build web --release
python3 -m http.server 8080 --directory build/web
```

`build/web` 可以直接上传到 Nginx、Caddy、GitHub Pages、对象存储静态网站或 CDN。需要将所有未知路径回退到 `index.html`，并允许浏览器下载 `.sgf` 文件。棋局最近记录使用浏览器 `localStorage`（通过 `shared_preferences`），不依赖服务器；清理浏览器站点数据会清除本地记录。

部署时必须上传整个 `build/web` 目录，不能只替换 `index.html`，也不能上传源码目录 `web/`。推荐先清空目标目录再同步，避免旧的 `main.dart.js`、`assets/` 或 service worker 残留：

```bash
flutter clean
flutter pub get
flutter build web --release --no-wasm-dry-run
rsync -av --delete build/web/ user@server:/var/www/easyplay/
```

静态服务器建议设置以下缓存策略：`index.html`、`flutter_bootstrap.js`、`flutter_service_worker.js` 和 `version.json` 使用 `no-cache`；带内容哈希的资源可以长缓存。如果页面仍显示旧版，在浏览器开发者工具的 Application/应用 → Service Workers 中点击 Unregister，然后清除站点数据并强制刷新；使用 CDN 时还要清理 CDN 缓存。部署到子路径时需要传入对应参数，例如 `flutter build web --release --base-href /easyplay/`。

Web KataGo 在 Worker 中重启搜索进程并重放当前棋局，因此不需要服务器 API；它依赖 COOP/COEP 响应头以启用 WASM pthread。Netlify/Cloudflare Pages 等支持 `_headers` 的纯静态主机可以直接部署；GitHub Pages 不能配置这些响应头，因此会自动切换本地双人模式。发布前要在部署后的域名验证 `crossOriginIsolated === true`，并在 Network 面板确认 `katago/katago.wasm`、Worker、配置和 b6 模型请求成功。Web Worker 每次生成应手都会从棋谱重放开始搜索，模型可由浏览器缓存，但搜索进程状态不跨回合保留。可以在构建后运行 `python tools/test_katago_web.py`，该测试需安装 Selenium 和 Firefox，会启动本地带跨源隔离响应头的静态服务器并实际搜索一步。

### Android Studio

1. 打开 `/home/fruit/项目/easyplay`
2. 等待 Gradle Sync 完成
3. 选择 Android 模拟器或真机
4. 运行 `lib/main.dart`

命令行运行：

```bash
flutter run
```

生成 Debug APK：

```bash
flutter build apk --debug
```

生成 Release APK（当前仍使用 debug signing，仅适合内部验证）：

```bash
flutter build apk --release
```

Debug APK 默认输出到：

```text
build/app/outputs/flutter-apk/app-debug.apk
```

发布前必须配置正式签名、包名、版本号和隐私/权限说明。

### Gradle 的 Java 25 warning

Android Studio 当前可能使用 JDK 25，Gradle 会输出：

```text
WARNING: A restricted method in java.lang.System has been called
WARNING: ... NativeLibraryLoader ...
WARNING: Use --enable-native-access=ALL-UNNAMED ...
```

这是 Java 25 对 Gradle native-platform 的兼容性提示，不是构建失败。当前项目已经实际生成过 APK。可以忽略，也可以把 Android Studio 的 Gradle JDK 改为 JDK 17，或给 Gradle 进程增加：

```bash
GRADLE_OPTS="--enable-native-access=ALL-UNNAMED" flutter build apk
```

升级 Gradle 时要一起检查：

- `android/gradle/wrapper/gradle-wrapper.properties`
- `android/settings.gradle.kts` 中的 AGP 版本
- Kotlin 插件版本
- Android Studio 支持的 JDK 版本
- Flutter 当前稳定版的 Gradle 模板

`file_picker` 依赖的 `flutter_plugin_android_lifecycle` 要求 compileSdk 36。项目在 `android/app/build.gradle.kts` 和根 `android/build.gradle.kts` 同时设置了 36：前者覆盖应用模块，后者在所有 Flutter Android library 模块评估完成后统一覆盖插件模块。这个设置只影响编译 API，不会自动提高 `targetSdk` 或 `minSdk`。

## 8. 测试与质量检查

运行全部测试：

```bash
flutter test
```

当前测试覆盖：

- 围棋占位检查、悔棋、自杀禁手、提子
- 国际象棋初始布局、兵移动、王安全
- 跳棋初始布局和基础移动
- 首页三种棋类入口
- 从首页进入新围棋对局

静态分析：

```bash
dart analyze lib test
```

Web 构建检查：

```bash
flutter build web
```

每次新增规则时，必须同时新增至少一个规则测试；每次修改页面导航或核心按钮时，至少补一个 widget 测试。

### 8.1 测试映射

| 修改内容 | 最低验证 |
| --- | --- |
| 围棋/象棋/跳棋规则 | `test/game_session_test.dart` 增加或修改单元测试，运行 `flutter test` |
| 首页、导航、对局按钮 | `test/widget_test.dart` 增加 widget 测试，运行 `flutter test` |
| 棋盘布局或响应式 UI | `flutter test`，再运行 `flutter build web` |
| Android Gradle、Manifest、签名 | `flutter build apk --debug`；发布前再做 release 构建 |
| 资源、字体、Web 壳 | `flutter build web`，用静态 HTTP 服务打开检查 |

当前测试基线：规则测试覆盖围棋占位/禁自杀/提子/悔棋，象棋初始布局/兵双步/王安全，跳棋初始布局/基础移动；widget 测试覆盖首页三种棋类入口和进入围棋对局。

## 9. 已知限制与建议优先级

### 高优先级

1. 围棋补充 SGF 逐手导航、完整分支树编辑及中途摆子复盘。
2. 优化围棋 Android/Web 上的 KataGo 启动、取消和终局裁定体验。
3. 只有在用户重新确定产品范围后，再恢复国际象棋或跳棋实现。

### 中优先级

1. 统一棋盘主题、棋子资源和动画。
2. 增加浅色/深色主题与中英文切换。
3. 增加局时、读秒和落子音效。
4. 继续适配手机小屏、平板和桌面 Web 宽屏。

### 低优先级

当前范围不包含账号、联机、云同步、每日题目、统计、排行榜或积分系统。

### 9.1 推荐实现顺序

跨模块需求按下面顺序拆分，便于每一步都能运行和回归：

```text
数据模型/规则 -> 单元测试 -> GameSession API -> GamePage 交互
-> 棋盘显示/动画 -> 持久化 -> Web/Android 验收
```

例如“支持围棋 19 路并保存棋谱”应拆成棋盘尺寸与坐标、落子/提子性能、计分、棋谱格式、本地存储、列表/复盘 UI 六个可独立验收的任务。

## 10. 新需求的推荐描述方式

后续提需求时，尽量包含以下信息：

```text
目标：要解决什么问题
游戏：围棋 / 国际象棋 / 跳棋 / 公共功能
平台：Android / Web / 两者
入口：从哪个页面进入
用户流程：用户按什么顺序操作
规则：具体采用哪一种棋规或变体
数据：是否需要保存、导入、同步
视觉：布局、颜色、棋子或参考页面
验收标准：完成后必须能看到或验证什么
优先级：P0 / P1 / P2
```

建议再补充两项，减少来回确认：

```text
不在本次范围：明确暂时不做的内容
测试场景：至少一个正常流程和一个边界/失败流程
```

例如：

```text
目标：支持围棋 19×19 对局
游戏：围棋
平台：Android 和 Web
入口：首页围棋卡片 → 对局设置
规则：支持贴目、双 pass 结束和中国规则计分
数据：本地保存最近 10 盘，不接账号
验收标准：可以切换 9/13/19 路，结束后显示双方目数，刷新页面后最近对局仍存在
优先级：P1
```

如果需求只涉及视觉，也要说明是否改变行为。例如“棋盘变成木纹”只改变显示；“落子后显示 AI 推荐点”同时需要状态、算法和交互设计。

### 10.1 可直接复制的需求模板

```text
目标：
游戏：围棋 / 国际象棋 / 跳棋 / 公共功能
平台：Android / Web / 两者
入口：
用户流程：
规则与变体：先手、棋盘尺寸、胜负、和棋、特殊规则
AI：是否需要；难度、思考时间、是否允许提示
数据：是否保存；保存范围、格式、清理方式、是否同步
视觉与响应式：布局、颜色、资源、窄屏/宽屏差异
不在本次范围：
验收标准：用可观察结果描述
测试场景：正常流程；非法/边界流程
优先级：P0 / P1 / P2
```

验收标准应写成“用户做什么后看到什么”，例如“点击悔棋后，最近一手从记录消失、棋盘恢复、回合恢复”，不要只写“完成悔棋功能”。

## 11. 需求验收清单

提交一个功能前，应确认：

- Android 和 Web 都能编译
- `flutter test` 通过
- 新规则有对应单元测试
- 页面在窄屏和宽屏都不溢出
- 点击、返回、重开、悔棋等状态不会残留
- 电脑模式和双人模式行为一致且可解释
- 需要保存的数据说明了生命周期和存储位置
- 规则变体已经写入文档，不靠默认猜测
- 用户能看到明确的成功、失败、非法操作或开发中提示
- 需求中承诺的平台、规则变体和数据生命周期都有对应实现或明确标记为未实现
- 构建日志中的 warning 与 error 已区分；没有把 JDK/Gradle warning 当作功能验收通过

### 11.1 交付说明格式

完成后在提交或 PR 描述中写明：

```text
变更：改了哪些用户可见行为和代码模块
规则：采用了什么变体，哪些规则仍未实现
数据：是否新增本地/远端存储
验证：执行过哪些命令，结果是什么
已知问题：仍可复现的问题和下一步
```

推荐每个提交只完成一个可验证主题，例如“增加跳棋连续跳吃规则”和“调整棋盘颜色”分开提交。

## 12. 常见问题

### Web 页面一直显示加载条

不要优先使用 `flutter run -d web-server`。执行：

```bash
flutter build web
python3 -m http.server 8080 --directory build/web
```

再打开 `http://localhost:8080`，并强制刷新浏览器。

### Android Studio 一直在下载 Gradle

第一次导入会下载 Gradle、AGP、Kotlin 和 Android SDK 组件。确认网络可用，并等待 Gradle Sync 完成。不要在下载中途反复修改 Wrapper 版本。

### Android 构建出现 restricted method warning

这是 JDK 25 的 warning。只要最后出现 `BUILD SUCCESSFUL` 或 APK 生成，就不是构建错误。可以改用 JDK 17 或添加 `--enable-native-access=ALL-UNNAMED`。

### 修改代码后 Web 没变化

静态服务器不会编译源码。重新执行：

```bash
flutter build web
```

然后刷新浏览器。

### 棋子没有显示或画布不刷新

检查是否向 painter 传入了新的棋盘快照，不能复用正在被 `GameSession` 修改的可变列表。先确认 `session.board` 状态，再检查 `BoardPainter.shouldRepaint`。

## 13. 当前验证基线

在编写本文档时，项目已验证：

```text
flutter test       通过
flutter build web  通过
Android debug APK 已成功生成
```

Android 构建过程中的 Java 25 restricted-method warning 不影响上述 APK 生成结果。
