# EasyPlay

EasyPlay 是一个面向 Android 和 Web 的 Flutter 棋类应用，目标支持围棋、国际象棋和跳棋。

当前版本已经包含围棋完整对局流程、KataGo 人机模式、不可用时的本地双人回退、响应式首页、对局页、悔棋和棋谱入口；国际象棋与跳棋入口仍标记为未完成。

完整的项目结构、规则边界、构建方式、Gradle 注意事项、测试约定和后续需求模板见：

- [开发文档](docs/DEVELOPMENT.md)
- [AI 引擎、模型与 OpenCL 使用说明](docs/AI_ENGINES.md)

快速运行：

```bash
flutter pub get
flutter run -d chrome
```

稳定 Web 预览：

```bash
flutter build web
python3 tools/serve_web.py --port 8080
```

运行测试：

```bash
flutter test
```

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

本项目分发或构建时使用以下第三方组件，它们的许可证与上述 GPL 条款兼容，
原文归档在 `assets/katago/` 与 `docs/licenses/`：

| 组件 | 许可证 | 用途 |
| --- | --- | --- |
| [KataGo](https://github.com/lightvector/KataGo) | MPL-2.0 | 围棋引擎，Android 侧编译为原生 GTP 程序，Web 侧编译为 WebAssembly |
| [Eigen](https://gitlab.com/libeigen/eigen) | MPL-2.0 | KataGo 的 CPU 后端 |
| KataGo 神经网络 b6 | CC0-1.0（公有领域） | 内置的 g170 b6 权重，见 `MODEL-LICENSE.txt` |
| clblast、cpp-httplib、half、filesystem 等 | Apache-2.0 / BSD / MIT 等 | KataGo 的可选依赖，原文见 `assets/katago/THIRD-PARTY-LICENSES/` |

应用内「关于与许可证」页面会展示以上全部许可证原文。
