# EasyPlay

面向 Android 和 Web 的 Flutter 棋牌应用，支持围棋、国际象棋、跳棋、五子棋、中国象棋和三人斗地主。提供本地双人、设备本地 AI、Android 局域网房间及浏览器 WebRTC 对弈，无需账号或远程 AI 服务。斗地主支持单人 AI、同机三人及三人联机。

[下载 Android APK](https://github.com/chorusfruit-233/easyplay/releases/latest) · [打开 Web 版](https://chorusfruit-233.github.io/easyplay/)

## 支持的游戏

| 游戏 | 规则与功能 | AI |
| --- | --- | --- |
| 围棋 | 多套规则、SGF 棋谱、死子与计分、选点分析 | KataGo CPU；内置 b6，Android 可管理其他模型 |
| 国际象棋 | 标准规则、将军与终局判定 | Stockfish 19 |
| 跳棋 | 英式/美式、国际、巴西、俄罗斯、Pool、意大利、西班牙、土耳其八种规则 | 自研本地搜索 |
| 五子棋 | 15×15 自由、标准与连珠禁手规则 | 自研本地搜索，三档难度 |
| 中国象棋 | 马腿、象眼、炮架、将帅照面、将死与困毙；固定亚洲长将/长捉配置 | Pikafish，六档难度 |
| 斗地主 | 54 张牌、叫分、全部常用牌型、地主与农民阵营；三人对战 | Dart 本地启发式 AI，仅使用自己的手牌 |

棋类游戏支持本地双人、AI 与联机。斗地主支持经典三人规则、同机遮挡交接、设备本地 AI、三人 LAN / WebRTC 和两名真人加 AI 补位，详见 [斗地主说明](docs/DOUDIZHU.md)。中国象棋的着法历史仅用于当前对局的规则、悔棋、搜索和重连，不持久化保存棋谱；规则范围见 [中国象棋说明](docs/XIANGQI.md)。

## 联机

- **Android LAN**：创建口令房间，支持自动发现、手动加入和内置 Web 客户端。浏览器打开主机网页后可快捷加入，仍须输入口令，并等待主机开始对局。
- **浏览器 WebRTC**：手动交换邀请和回应，通过 STUN 建立直连，支持国内、国际及自定义服务。当前未启用自动信令或 TURN，部分网络无法直连。
- 房主验证走子；支持断线重连、状态同步、悔棋协商、认输和再来一局。双方须使用匹配的游戏规则，房间依赖主机持续运行。

## 开发与构建

安装 Flutter 及 Python 3；准备 Pikafish 发布资源还需要 `7z` 或 `7zz`。首次准备引擎时需要联网下载固定版本，脚本会校验 SHA-256。

```bash
flutter pub get
python3 tools/prepare_stockfish.py
python3 tools/prepare_pikafish.py
flutter run -d chrome
```

构建并预览 Web（本地预览提供围棋 AI 所需的跨源隔离响应头）：

```bash
flutter build web --no-wasm-dry-run
python3 tools/serve_web.py --port 8080
```

构建包含三个引擎和 LAN Web 客户端的 Android 测试包：

```bash
python3 tools/package_lan_android.py --debug
```

Android Studio / Gradle 构建也会自动准备 Stockfish、Pikafish 和内置网页。原生引擎目标为 Android ARM64；KataGo 与 Web 构建的工具链说明见开发文档。

```bash
flutter test
dart analyze lib test
```

## 文档

- [开发文档](docs/DEVELOPMENT.md)：结构、规则、平台构建与测试约定
- [AI 引擎与模型](docs/AI_ENGINES.md)：KataGo CPU、配置和模型管理
- [五子棋说明](docs/GOMOKU.md)：规则、AI、存储与联机
- [斗地主说明](docs/DOUDIZHU.md)：固定规则、三人房间、手牌隐私与重连
- [中国象棋说明](docs/XIANGQI.md)：固定规则、Pikafish、构建与模型许可
- [WebRTC 联机说明](docs/WEBRTC_MULTIPLAYER.md)：邀请流程、STUN 与网络限制

## 许可证

Copyright (C) 2026 chorusfruit-233

本项目以 **GNU 通用公共许可证第 3 版或更新版本**（GPL-3.0-or-later）授权发布，
全文见 [LICENSE](LICENSE)。你可以依据自由软件基金会发布的 GPL 条款重新分发
和/或修改本项目；本项目按“现状”提供，不附带任何明示或暗示的担保。

```
EasyPlay - 面向 Android 和 Web 的棋类应用
Copyright (C) 2026 chorusfruit-233

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
```

### 第三方组件

引擎代码与模型权重分别遵循各自许可证；EasyPlay 的 GPL 授权不替代第三方资源授权。

| 组件 | 许可证 | 用途 |
| --- | --- | --- |
| [KataGo](https://github.com/lightvector/KataGo) | MPL-2.0 | 围棋 CPU 引擎，Android ARM64 原生程序与 WebAssembly Worker |
| [Eigen](https://gitlab.com/libeigen/eigen) | MPL-2.0 | KataGo 的 CPU 后端 |
| KataGo 神经网络 b6 | CC0-1.0（公有领域） | 内置 g170 b6 权重 |
| [Stockfish 19](https://github.com/official-stockfish/Stockfish) | GPL-3.0 | 国际象棋引擎，Android ARM64 与 Web Worker |
| [Pikafish](https://github.com/official-pikafish/Pikafish) | GPL-3.0-or-later | 中国象棋引擎，Android ARM64 与 WebAssembly Worker |
| Pikafish NNUE 权重 | 单独授权，未经许可不得商业使用 | 中国象棋 AI 网络，见 [模型许可](assets/pikafish/NNUE-License.md) |
| cpp-httplib、half、filesystem 等 | Apache-2.0 / BSD / MIT 等 | KataGo 依赖，原文见 `assets/katago/THIRD-PARTY-LICENSES/` |

许可证及来源归档在 `assets/katago/`、`assets/licenses/`、`assets/pikafish/`、`docs/licenses/` 和 `web/stockfish/`。应用内「关于与许可证」页面提供引擎与模型的许可信息。
