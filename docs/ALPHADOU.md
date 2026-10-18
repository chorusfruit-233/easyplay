# AlphaDou 接入评估

评估日期：2026-10-18。当前斗地主仍使用 EasyPlay 的本地 Dart AI；单人、房间 AI 补位和跟牌提示均未接入 AlphaDou。

## 结论与来源

[官方仓库 RuBP17/AlphaDou](https://github.com/RuBP17/AlphaDou) 提供训练、测试与 PyTorch 模型源码，但**没有公开训练好的 AlphaDou 权重**。作者在 [issue #10 的回复](https://github.com/RuBP17/AlphaDou/issues/10#issuecomment-2869534372)中明确说明：未公开模型参数，`baseline/best` 是 DouZero ResNet 权重，`baseline/test` 是 DouZero 权重，baseline 仅用于测试。不能把这些对照模型作为 AlphaDou 接入并标注。

源码有适配路径；真正接入需要先取得可用、获准分发的 AlphaDou 权重，或按公开代码自行训练。仓库采用 GPL-3.0，模型权重的分发条件须另行确认。本次没有下载、打包任何模型，没有增加在线服务或上传牌局。

本次核对的源码版本为 [`13e740c`](https://github.com/RuBP17/AlphaDou/tree/13e740c08c3b653c2bef6ca345fc8fa6adc7d362)：

- [`README.md`](https://github.com/RuBP17/AlphaDou/blob/13e740c08c3b653c2bef6ca345fc8fa6adc7d362/README.md) 描述 Python / PyTorch 训练、测试流程。
- [`douzero/dmc/models.py`](https://github.com/RuBP17/AlphaDou/blob/13e740c08c3b653c2bef6ca345fc8fa6adc7d362/douzero/dmc/models.py) 包含三个叫牌位置与地主、地主上家、地主下家的模型。
- [`douzero/evaluation/deep_agent.py`](https://github.com/RuBP17/AlphaDou/blob/13e740c08c3b653c2bef6ca345fc8fa6adc7d362/douzero/evaluation/deep_agent.py) 使用 PyTorch 推理，可选择 CPU；没有现成的 Android / Web 推理接口。

## 与现有规则和接口的适配

EasyPlay 的 `DouDizhuAi.chooseAsync(view)` 只接收本座位手牌与公开信息；将来替换引擎也应保留这个边界。适配器需要从公共历史还原观察量，不能读取其他玩家的私有手牌。

| 项目 | 适配要求 |
| --- | --- |
| 牌编码 | 应用使用 0–53 的实体牌 ID；模型使用点数及重复次数。普通 3–A 对应 3–14，2 对应 17，小王 / 大王对应 20 / 30；模型动作需还原为当前手牌中的实体 ID。 |
| 身份与顺序 | 以地主为基准映射地主、上家、下家；按叫牌先后选择对应叫牌模型。 |
| 观察量 | 转换手牌、未知牌集合、底牌、各座位公开出牌与不要、剩余张数、叫分和历史窗口；炸弹及春天等特征按公开行动计算。 |
| 合法动作 | 继续由 EasyPlay 的合法出牌生成器枚举并校验。双方在飞机单翅膀、主体点数与双王附件等边界上有差异，不能直接接受上游生成器的动作。 |
| 权重校验 | 验证来源、哈希及每个参数的名称和形状，禁止缺失参数后保留随机初始化值。上游测试加载器允许只合并匹配的参数，不能原样用于产品。 |

应用不做倍率计分。模型特征与策略仍须按训练规则校准；仅能成功加载权重不代表牌型、叫分和策略已经兼容。

## 可实施路线

1. 取得六个位置的兼容权重、配置和许可，确认网络结构与训练规则。
2. 在 Python 中建立固定观察量与候选动作样本，严格加载模型，保存参考输出；尝试导出 ONNX 等可移植格式。导出候选动作的评分网络，动作选择留在应用层。
3. Android 评估原生 CPU 推理，Web 评估 Worker 中的 WASM 推理。核查动态候选动作批次、算子支持、包体、峰值内存、单步延迟和取消过期回合的行为。目前没有移动端实测或成功导出的模型，不承诺速度与棋力。
4. 用同一组观察量检查 Python、Android、Web 的输出一致性，再做固定发牌、角色轮换与当前 AI 的对照对局；加入合法性、手牌隐私、农民协作和联机重连验证。

在权重和跨平台验证完成前，保留现有本地 AI；如改用公开的 DouZero 模型，应独立评估并按实际引擎命名。
