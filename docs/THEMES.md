# 主题设置

设置首页的「主题设置」进入独立 Material 页面，参考 KernelSU 的 [Material 主题页](https://github.com/tiann/KernelSU/blob/08a3b087e49227c8a6731c5f1114998b5e25255b/manager/app/src/main/java/me/weishu/kernelsu/ui/screen/colorpalette/ColorPaletteScreenMaterial.kt)。不提供 Miuix 界面。

- 预览 → 横向强调色色卡 → 四个明暗模式 → 色彩风格/标准 → 界面缩放，沿用参考页面的顺序。
- 默认强调色来自 Android 系统壁纸的亮/暗主色；其他平台或不可用时使用靛青。十五个预设采用 KernelSU 相同色值，包括绿色 `#4FAF50`。
- 跟随系统、浅色、深色、AMOLED 纯黑四种互斥模式。AMOLED 强制深色，并将全部表面容器设为纯黑。
- 九种风格：TonalSpot、Neutral、Vibrant、Expressive、Rainbow、FruitSalad、Monochrome、Fidelity、Content。
- 默认 SPEC_2025，可切换 SPEC_2021；只有前四种风格支持 2025，其他风格按参考实现使用 2021。
- 界面缩放范围 80%–110%，改变布局、绘制和触摸坐标；系统字体缩放仍保留。
- 所有选项即时生效并保存。旧的 `appearance`、强调色和风格偏好保留；旧 AMOLED 开关迁移为四种模式中的纯黑模式。

不加入仅用于 KernelSU 模块/导航的选项。Android/Web 共用主题状态；Linux 等没有配色桥接的平台使用 Flutter 内置算法（2021）。新增算法加载失败时显示重试提示，不改变跨源隔离设置。

## 配色来源和构建

Google [Material Color Utilities](https://github.com/material-foundation/material-color-utilities/tree/5b3618b16fdc3825e21d5679bafd144662088ea1) 固定到上述提交：

- Java 位于 `android/app/src/main/java/com/easyplay/easyplay/materialcolor/`，仅调整包名、移除可选 Error Prone 注解；在后台线程计算。
- TypeScript 位于 `third_party/material_colors/`，生成的 `web/material_colors.js` 随正式 Web/Android LAN 资源打包。运行时不依赖 CDN。
- Flutter 桥接将完整 46 个色彩角色映射为 `ColorScheme`，页面和应用使用同一配色，缓存按种子/风格/标准/明暗区分。
- 来源及许可证在应用「关于 EasyPlay」中提供；上游声明保留在源文件内。

重新生成 Web 算法（需要 Node 和 esbuild 0.25.12）：

```bash
npm install --prefix /tmp/easyplay-theme-node --no-save --package-lock=false esbuild@0.25.12
NODE_PATH=/tmp/easyplay-theme-node/node_modules node tools/build_material_colors.cjs
node tools/test_material_colors.cjs
flutter test
dart analyze lib test
python3 tools/package_lan_android.py --debug
```

Java/JS 对照覆盖三个种子、九种风格、两个标准和两种明暗，共 108 个方案的全部角色，并验证两个标准确实产生不同结果。独立浏览器 smoke 目标只用于回归，不进入正式应用。
