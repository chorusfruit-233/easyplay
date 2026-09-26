# 参考产品棋谱 UI 分析

对 `upstream/围棋大师_1.4.0.apks`(EasyGo,Flutter 应用)的棋谱相关界面做的逆向梳理。

**方法说明**:`libapp.so` 里的 AOT 快照字符串是压缩的,反编译文本不可行。但随包发布的
`assets/flutter_assets/assets/localization/zh.strings`(1355 条,带分组注释)与
`comments.zh.txt` 是**明文**,本分析的全部结论都由它推导而来。

**可信度**:界面文案与其分组是**事实**(资源里逐条存在);由文案推断的**布局与交互**是
**推测**,已在下文标注。凡未标注者均为事实。

---

## 一、棋谱功能的四个屏

| 屏 | 资源分组 | 文案数 | 职责 |
| --- | --- | --- | --- |
| 棋谱库 | 用户棋谱库界面 | 115 | 浏览、整理、导入导出、新建 |
| 棋谱编辑器 | 棋谱编辑器 | 23 | 看棋盘、看变化树、下 AI |
| 导航控件 | 棋谱导航控件 | 27 | 手数前后移动、换局、回放 |
| 编辑工具面板 | 棋谱工具面板 | 40 | 增删节点、摆子、标记、看 SGF |

**关键点:"库"和"编辑器"是两个独立屏**,不是同一屏的不同状态。库屏负责文件管理,编辑器屏
负责单局内容。这与我们项目现在把两者混在 `game_page.dart` 里的做法不同。

---

## 二、棋谱编辑器(编辑器屏)

### 2.1 底部三选项卡

```
"Comment"    = "注释"
"AI Summary" = "AI 摘要"
"Tree"       = "变化树"
"PV"         = "PV"
```

资源里 `Tree` 与 `PV` 各自成条,且编辑器分组里另有 `"Analyzing..."`、`"No analysis yet"`、
`"visits"`、`"percents"`——**推测**:底部面板是 **Comment / AI Summary / Tree / PV** 四个
页签(Tree 与 PV 可能是同一页签下的二级切换,因为参考截图中两者并排且 Tree 有下划线)。

### 2.2 注释

```
"Enter comment..."        = "输入注释..."
"No comment. Tap to edit." = "暂无注释，点击编辑。"
"Comment"                 = "注释"
```

注释即 SGF 的 `C[]` 属性,直接编辑。

### 2.3 AI 分析

```
"AI Summary"    = "AI 摘要"
"Analyzing..."  = "正在分析..."
"No analysis yet" = "暂无分析"
"visits"        = "搜索量"
"percents"      = "占比"
"Stop" / "Stop AI" = "停止"
"Analyze" / "Analysis" = "分析"
"AI Move"       = "AI 落子"
"AI move failed"     = "AI 落子失败"
"AI analysis failed" = "AI 分析失败"
```

**两个独立动作**:「分析」(看候选点、搜索量、占比)与「AI 落子」(让引擎代下)。

### 2.4 全屏

```
"Full screen"    = "全屏"
"Exit full screen" = "退出全屏"
"Drag the exit button to move it anywhere on the screen." = "拖动退出按钮，可将它移动到屏幕任意位置。"
"Double-tap to zoom in" = "双击放大"
"Enable double-tap zoom gesture" = "启用双击放大手势"
"Loading variation tree..." = "正在加载变化树..."
"No game loaded" = "未加载棋谱"
"Failed to load game" = "加载棋谱失败"
```

**推测**:全屏模式下棋盘铺满,退出按钮**可拖动**(避免遮挡棋盘);双击放大可开关;
变化树是**异步加载**的(有 loading 文案)。

---

## 三、导航控件

```
"Previous Game" / "Next Game"      = 上一局 / 下一局
"Previous Node" / "Next Node"      = 上一步 / 下一步
"Previous Branch"                  = 上一分支
"Previous Branch Point"            = 上一分支点
"Delete Last Node"                 = 删除最后一步
"Replay"                           = 回放
"Share"                            = 分享
"More Tools" / "More Options"      = 更多工具 / 更多选项
"Collapse panel" / "Expand panel"  = 收起面板 / 展开面板
"Current" / "Date" / "Filter" / "Misc" = 当前 / 日期 / 筛选 / 其它
"Pin" / "Skip" / "Switch"          = 固定 / 跳过 / 切换
"Switch Sides?"                    = 换边？
```

操作反馈:

```
"New branch started"      = "已开始新分支"
"Moved to previous node"  = "已移至上一步"
"Moved to next node"      = "已移至下一步"
"Moved to branch point"   = "已移至分支点"
"Node deleted"            = "节点已删除"
"Failed to load previous game" / "next game" = 加载上一局/下一局棋谱失败
"Game not found"          = "找不到棋谱"
```

**要点**:

- **跨局导航**与**局内导航**是两层。「上一局/下一局」在库里换棋谱,不必退回库屏。
- **「上一分支点」是独立动作**,不只是「上一步」——直接跳到上一个分叉处,复盘时常用。
- **「回放」**是按手自动播放。
- **「固定 / 跳过 / 切换」**很可能是复习模式(题目/定式)下的动作。

---

## 四、编辑工具面板

### 4.1 节点操作

```
"Insert Node"        = "插入节点"
"Add Variation"      = "增加分支"
"Delete Node"        = "删除节点"
"Delete Variation Tree" = "删除变化树"
"No valid node to delete" = "没有可删除的有效节点"
"Failed to delete node" / "delete variation tree" = 失败提示
```

删除有两种语义,**用两个确认文案区分**:

```
"This will delete the current node and all its children. This action cannot be undone."
  = 确定要删除整个变化树吗？此操作无法撤销。
"This will delete the current node and preserve its children. This action cannot be undone."
  = 确定要删除当前节点并保留其子节点吗？此操作无法撤销。
```

**这是设计要点**:删一个节点时「其子节点怎么办」必须有明确选择(一并删 / 保留并提升),
不能默认一种了事。

### 4.2 摆子与标记

```
"Black Move" / "White Move" = 黑棋落子 / 白棋落子
"Add Black" / "Add White"   = 添加黑子 / 添加白子
"Triangle" / "Square" / "Circle" / "Mark" / "Label"
  = 三角标记 / 方形标记 / 圆形标记 / 标记 / 文字标记
"Shift Up" / "Shift Down"   = 上移 / 下移
```

**「黑棋落子/白棋落子」与「添加黑子/添加白子」是两组不同动作**:前者是走子(记入 `B[]`/`W[]`),
后者是**摆子**(记入 `AB[]`/`AW[]`),即设置局面而非对局。SGF 里这是两种不同的属性。

标记覆盖 SGF 的 `TR`/`SQ`/`CR`/`LB`。

### 4.3 SGF 文本

```
"Show SGF" / "Copy SGF" / "SGF Content" = 显示SGF / 复制SGF / SGF内容
"SGF content copied to clipboard" = "SGF内容已复制到剪贴板"
"Save" / "Information" / "Close" = 保存 / 信息 / 关闭
"Select a game to edit" / "or create a new one" = 选择一个棋谱进行编辑 / 或创建一个新的棋谱
```

### 4.4 AI 工具栏

```
"Switch to AI Toolbar" = "切换到 AI 工具栏"
"Collapse AI"          = "收起 AI"
"Loading AI..." / "Reloading AI..." = 正在加载 AI... / 正在重新加载 AI...
"The AI engine is taking longer than expected to start. Please wait."
  = 当前启动引擎较慢，请耐心等待
"AI engine startup timed out" = "AI 引擎启动超时"
```

**推测**:编辑工具面板可在「编辑工具」与「AI 工具栏」之间切换,共用同一块空间。

---

## 五、棋谱库

### 5.1 组织方式

文件夹 + 子文件夹 + 多选 + 收藏 + 标签。

```
"New Folder" / "Folder Name" / "Rename Folder" = 新建文件夹 / 文件夹名称 / 重命名文件夹
"Move to Folder" / "Copy to Folder"            = 移动到文件夹 / 复制到文件夹
"Add to Games"                                 = "添加到棋谱库"
"Empty folder" / "There are no items in this folder" = 空文件夹 / 此文件夹中没有项目
```

### 5.2 滑动与长按

```
"Swipe left on an item" = "在项目上向左滑动"
"Show actions like Share/Export, Copy, Move, and Delete."
  = 显示分享/导出、复制、移动和删除等操作。
"Long-press an item" = "长按项目"
"Enter multi-select mode to manage several items at once."
  = 进入多选模式，一次管理多个项目。
```

批量动作:导出所选 / 复制所选 / 移动所选 / 删除所选 / 分享所选。

### 5.3 新建棋谱

```
"New Game" / "New AI Game" = 新建棋谱 / 新建AI对局
"Game Name" / "Black Player" / "White Player" = 棋谱名称 / 黑方棋手 / 白方棋手
"Komi" = "贴目"    "Handicap:" = "让子:"    "Board Size:" = "棋盘大小:"
"Rule-chinese" / "Rule-japanese" = 中国规则 / 日式规则
"Style" / "Traditional" / "Modern" = 风格 / 传统 / 现代
"Random Color" = "猜先"    "Create" = "创建"
```

**「风格:传统/现代」**对应我们前面查到的 KataGo `preaz_*`(AlphaZero 前)与 `rank_*`(现代)
两套人类棋风开局库——所以这个选项存在的原因**是为了选对 humanSLProfile**。

### 5.4 导入导出

```
"Import SGF or ZIP" / "Import SGF File"     = 导入 SGF 或 ZIP / 导入棋谱文件
"SGF Files" / "ZIP Files"                   = SGF 文件 / ZIP 文件
"Export" / "Export selected" / "Export complete" = 导出 / 导出所选 / 导出完成
"Exporting Games" / "Export cancelled"      = 导出棋谱 / 导出已取消
"Processing %d of %d%s"                     = 处理第%d个(共%d)%s
"Started ZIP import" / "No SGF files found in the ZIP archive" = 开始导入ZIP文件 / 未找到SGF文件
"Failed to parse SGF file. It may be corrupt or invalid."
  = 解析SGF文件失败。文件可能损坏或无效。
"Some errors occurred during import" = "导入过程中发生了一些错误"
```

**ZIP 导入**且带进度与取消,说明面向"整包棋谱"场景(题库/棋谱合集)。

### 5.5 文件编码

```
"File Encoding" = "文件编码"    "Auto Detect Encoding" = "自动检测编码"
"Japanese (EUC-JP)" / "Japanese (Shift_JIS)"
"Korean (EUC-KR)" / "Simplified Chinese (GB18030)"
"Traditional Chinese (BIG5)" / "Western European (Windows-1252)"
```

**这是实战需求**:日韩老棋谱大量使用非 UTF-8 编码,不处理就是乱码。

### 5.6 排序与统计

```
"Sort" / "Default" / "Current" / "Date" / "Next due"
"Win Rate" = "胜率"
"Total Attempts" / "Correct Attempts" / "Wrong Attempts"
```

---

## 六、设置里与棋谱相关的项

### 棋谱编辑器

```
"Game Editor" = "棋谱编辑器"
"Show next move" = "显示下一手"
"When to display the next move" = "何时显示下一手"
"Hidden" / "Always show" / "Show only when the next move has branches"
  = 隐藏 / 始终显示 / 仅在下一手有分支时显示
"Display alternative move options in editor" = "在编辑器中显示替代着法选项"
"Mark correct and incorrect branches in variation tree" = "在变化树中标记正确和错误分支"
"Highlight solution paths when game is a problem" = "当棋谱为题目时高亮解答路径"
```

**「何时显示下一手」有三档**,默认很可能是有分支时才显示——避免剧透下一手。

### AI 分析持久化

```
"Analysis Persistence" = "分析持久化"
"Save analysis to SGF" = "保存分析到 SGF"
"Persist AI analysis in SGF LZ properties." = "将 AI 分析保存到 SGF 的 LZ 属性中。"
"Overwrite existing analysis" = "覆盖已有分析"
"Overwrite EasyGo analysis, preserve external analysis."
  = "覆盖 EasyGo 分析，保留外部分析。"
"Always overwrite existing SGF analysis." / "Never overwrite existing SGF analysis."
"Export with analysis" = "导出时包含分析"
"Include SGF LZ analysis data when exporting."
"Enable Save analysis to SGF before exporting analysis data."
  = "需要先开启保存分析到 SGF，才能导出分析数据。"
```

**用 SGF 的 `LZ` 属性存分析结果**,并区分「自己的分析」与「外部分析」(别的软件写的),
提供 3 档覆盖策略。这是与 Lizzie/Katrain 生态互通的做法。

### 库界面

```
"Always use file name" = "始终使用文件名"
"Always use file name instead of game name (UI, export filename)"
"Default Board Size" = "默认棋盘大小"
```

---

## 六点五、另外几处值得记的交互

这一节是后来从 `zh.strings` 里另几组文案翻出来的,不在前面的四个分组里。

### 单/双面板切换(即参考截图右上角那个方框按钮)

```
"Show one pane"  = "显示单面板"
"Show two panes" = "显示双面板"
```

**这就是你截图里那个圆形矩阵图标**——切换棋盘区域显示一个还是两个面板。不是单双行。

### 回放模式

```
"Replay"       = "回放"
"Exit Replay"  = "退出回放"
"ReplayModeTip" = "点击棋盘左半边后退，点击右半边前进。"
```

回放时**点棋盘左右半边即可前后翻手**,不需要找按钮。这是个很省的交互设计。

### 长按棋子跳转

```
"Long press a stone to navigate" = "长按棋子跳转"
```

### 落子模式(与我们的五种对应)

参考产品的四种模式,文案与我们 `go_placement.dart` 里的前四种**几乎逐字一致**:

```
"Move input mode" = "落子模式设置"
"Direct tap"      = "直接点击"
"Tap twice"       = "点击两次"
"Swipe to confirm" = "滑动确认"
"Press & release"  = "按下并松开"
"Play directly when the board grid is large. Use two-step confirmation when the grid is small."
  = 网格大时直接落子，网格小时采用二次确认。
"Tap once to preview, then tap the same point again to play. Swipe up to cancel the preview."
  = 第一次点击预览，再次点击该位置确认落子。向上滑动取消预览。
"Tap once to preview. Swipe down to confirm the previewed move, or swipe up to cancel."
  = 点击预览，向下滑动确认落子，向上滑动取消。
"Press to preview. Keep pressing and move to adjust the position. Release to play."
  = 按下以预览。保持按住并移动以调整位置。松开后落子。
```

另有一项我们没做的**正交增强**:

```
"Enable offset drag fine tuning" = "开启“偏移拖拽”微调"
"After enabling, drag on the board to show an offset move cursor. Release to play the cursor point.
 This can be used together with Tap twice and Swipe to confirm modes."
  = 开启后，在棋盘上滑动可唤出带有偏移量的落子光标，松手即落子。
    该功能可与“点击两次”和“滑动确认”模式同时使用。
```

**它是与四种模式正交的一个开关**,不是第五种模式——「点击两次」和「滑动确认」可以同时启用它。

### 分析上限

```
"Time limit" / "Visit limit"          = 时间上限 / 搜索量上限
"Seconds per analysis run"            = 每次分析的秒数上限
"Visits per analysis run"             = 每次分析的搜索量上限
"Analysis stops when either limit is reached." = 分析达到任一上限时会停止。
```

**分析用的是「时间与搜索量取先到者」**,与我们对局引擎的 `maxTime`/`maxVisits` 同构。

### 商业化:AI 次数配额

这一块揭示了参考产品的商业模式,值得单独知道:

```
"ai_quota_name_play_start" = "AI 对弈次数"
"ai_quota_name_undo"       = "AI 悔棋"
"ai_quota_name_analysis"   = "AI 分析次数"
"今日 AI 对弈次数已用完" / "今日 AI 悔棋次数已用完" / "今日 AI 分析次数已用完"
"升级 Pro 可终身无限使用 AI 对弈、AI 悔棋、AI 分析、完整 SGF 编辑功能、2400+ 内置题目，并获得免费更新。"
"已有 PV 数据的位置再次分析免费。"
```

**三个要点**:

1. **AI 悔棋是配额动作**,不是普通的悔棋——悔棋要请引擎重算,所以按次计费
2. **同一局面重复分析免费**(已有 PV 数据则不计次),这个规则设计得很细
3. **完整 SGF 编辑功能在 Pro 里**,免费版应该只读

也就是说参考产品把「棋谱库 + 只读复盘」作为免费层,把「编辑 / AI / 题目」作为付费层。
我们自己怎么定是另一回事,但**它说明「编辑」和「查看」被有意分成两档**——这与前面
观察到的「库屏与编辑器屏分离」是同一个设计取向的两面。

另有 AI 对局分支的警告:

```
"ai_play_branch_delete_warning_resume"
  = 此操作可能删除当前 AI 对局分支，并会中断 AI 对局。之后如需继续 AI 对弈，请点击 {aiMove}。
```

**「AI 对局」本身是一条 SGF 分支**。从某局面开始与 AI 对弈,结果会作为该节点的新分支写入——
所以删节点才可能"删除 AI 对局分支"。这与我们 `GoSgfController` 里
「在已有后续变化的节点追加会生成兄弟分支」是同一个模型。

---

## 七、与我们项目的差距

| 能力 | 参考产品 | 我们 |
| --- | --- | --- |
| 变化树可视化 | ✅ 带分支、注释、正确/错误分支标记 | ✅ 刚做(仅主干 + 分支道) |
| 库 / 编辑器分屏 | ✅ 两个独立屏 | ❌ 混在 `game_page.dart` |
| 注释编辑(`C[]`) | ✅ | ❌ |
| 节点增删(含"保留子节点"语义) | ✅ | ❌ |
| 摆子 vs 走子区分 | ✅ 两组动作 | ❌ 只有走子 |
| 标记(`TR`/`SQ`/`CR`/`LB`) | ✅ | ❌ |
| SGF 文本查看/复制 | ✅ | ❌ 只有导出文件 |
| PV 显示 | ✅ 独立页签 | ❌ 未接 `kata-analyze` |
| AI 分析存 SGF(`LZ`) | ✅ 含 3 档覆盖策略 | ❌ |
| 文件夹 / 多选 / 标签 / 收藏 | ✅ | ❌(仅最近 20 盘) |
| ZIP 批量导入(带进度/取消) | ✅ | ❌ |
| 非 UTF-8 编码支持 | ✅ 6 种 | ❌(仅 UTF-8) |
| 跨局导航 | ✅ 上一局/下一局 | ❌ |
| 全屏 + 双击缩放 | ✅ | ❌ |
| 单/双面板切换 | ✅ | ❌ |
| 回放(点半屏前后翻) | ✅ | ❌ |
| 长按棋子跳转 | ✅ | ❌ |
| 偏移拖拽微调 | ✅ | ❌ |
| 回放 | ✅ | ❌ |
| 题目 / 定式 / SRS 复习 | ✅ 完整体系 | ❌ |

---

## 八、若要挑优先级

按「实现成本 / 用户价值」排序,我会这样取舍:

1. **注释编辑 + 标记** — 成本低(`C[]`、`TR`/`SQ`/`CR`/`LB` 都是简单属性),复盘必需
2. **SGF 文本查看/复制** — 成本极低,调试与分享都有用
3. **摆子与走子分离** — 中等成本,但「从任意局面开始」依赖它,参考产品的 AI 对局也靠它
4. **节点增删(含保留子节点)** — 中等,是"编辑"而非"查看"的门槛
5. **跨局导航** — 低成本,前提是库屏独立出来
6. **PV 显示** — 需先接 `kata-analyze` 分析通道,成本高
7. **库屏独立 + 文件夹 + 多选** — 成本高(等于重做一层),但库一大就必须有
8. **编码支持** — 只在真的要导入日韩老棋谱时才紧急;实现简单(`charset` 探测)
9. **题目 / SRS** — 是另一条产品线,不建议在棋谱做完前动

**注意第 3 项是分水岭**:参考产品那句
`"AI features are now available. ... continue from any position in an SGF record"`
说明「从任意局面继续」被当作核心卖点。而我们的 `GoSgfController` 已经有
`sessionForCurrent()`(从根重放到游标),**基础已经在了**,差的是把「摆子」写进记录。
