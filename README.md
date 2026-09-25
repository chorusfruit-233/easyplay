# EasyPlay

EasyPlay 是一个面向 Android 和 Web 的 Flutter 棋类应用，目标支持围棋、国际象棋和跳棋。

当前版本已经包含三种棋类的本地可玩规则原型、响应式首页、对局页、基础电脑走法、悔棋和棋谱/个人页入口。

完整的项目结构、规则边界、构建方式、Gradle 注意事项、测试约定和后续需求模板见：

- [开发文档](docs/DEVELOPMENT.md)

快速运行：

```bash
flutter pub get
flutter run -d chrome
```

稳定 Web 预览：

```bash
flutter build web
python3 -m http.server 8080 --directory build/web
```

运行测试：

```bash
flutter test
```
