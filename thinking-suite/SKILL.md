---
name: thinking-suite
description: |
  思维模型集合总入口：deep-thinking（结论前置层）、problem-definition（问题界定）、problem-analysis（系统分析）三个思考类 skill 的分工总览、路由决策、交接协议与歧义裁决。
  当用户问"这几个思考 skill 什么区别 / 我该用哪个 / 帮我想清楚一件事但不知道用什么方法"，或抛出模糊的思考类请求需要路由判断时使用本 skill。
  本 skill 不做界定、不做分析、不给结论。单场景请求直接找对应成员：判断题找 deep-thinking，问题没弄清找 problem-definition，系统分析找 problem-analysis。

  Triggers when user mentions:
  - "思维模型集合 / 思考 skill 有什么区别 / 我该用哪个思考 skill"
  - "帮我想清楚一件事"（未指明界定还是分析时，本 skill 负责路由）
  - "界定问题和分析问题什么关系 / 这三个 skill 怎么分工"
metadata:
  author: "deepworks-user-2fqhuw"
---

# 思维模型集合（thinking-suite）

本 skill 是思维模型集合的总入口，只负责**总览、路由、交接协议说明**，**不做界定、不做分析、不给结论**。
单场景请求直接去对应成员；只有需要路由判断或集合说明时才进入本 skill。

## 集合成员

| 成员 | 定位 | 解决什么 | 输入状态 | 产物 |
|-|-|-|-|-|
| deep-thinking | 思考前置层 | 下结论前该走的工序走了没 | 判断/评估类问题 | 结论 + 置信度 + 关键假设 + 重判触发器 |
| problem-definition | 问题界定专家 | 事情到底是什么 | 问题描述模糊 / 感受与事实混杂 / 刚接到他人交代 | 三栏表 / 待问清单 / 核对话术 / 收束句 |
| problem-analysis | 系统分析执行库 | 怎么系统分析并交付 | 大而模糊的问题、一堆乱材料、要根因/排序/验证/汇报 | 分析卡（问题卡 + 证据 + 行动清单 + 验证指标） |

## 路由决策树

顺序判断，命中即停：

1. **事情还没弄清**（描述模糊、感受与事实混杂、接到他人交代但没问清）→ `problem-definition`
2. **问题已清楚、需要系统分析**（根因 / 拆解 / 乱材料 / 排优先级 / 方案验证 / 出汇报）→ `problem-analysis`
3. **判断/评估类、一轮给结论**（要不要 X / X 对不对 / 你怎么看 / 方案靠谱吗）→ `deep-thinking`
4. **无限定的泛化"帮我分析 X"** → `deep-thinking` 默认接；它就地发现兜不住时，按第 1/2 条移交
5. **复合链**：`problem-definition` 框定 → `problem-analysis` 分析交付；`problem-analysis` 的分析卡自带置信度与未查透项，无需回流

## 歧义裁决表

| 用户说法 | 路由 | 裁决依据 |
|-|-|-|
| "帮我分析 X"（无限定词） | deep-thinking | 泛化"分析"默认轻量；有无系统分析限定词是与 problem-analysis 的分界 |
| "系统分析 / 理一理 / 一堆乱材料 / 找根因 / 排优先级 / 用哪个模型" | problem-analysis | 带系统分析信号 |
| "到底怎么回事 / 这个问题是什么 / 这需求怎么理解" | problem-definition | 问题本身还没说清 |
| "该不该 X / X 对不对 / 方案靠谱吗 / 你怎么看" | deep-thinking | 判断/评估类 |
| 模糊不安且有评估对象（"这方案我觉得哪里不对"） | deep-thinking | 对象具体，要评估 |
| 模糊不安且说不清（"氛围很怪，说不上来"） | problem-definition | 需先还原事实 |
| "这事怎么跟领导说" | 简短同步 → problem-definition ⑧；正式汇报分析成果 → problem-analysis 场景 16 | 看分析是否已经跑过 |
| 点名"第一性原理 / 从零推 / break this down" | 装了 first-principles-decomposer → 交给它拆，deep-thinking 负责置信度收尾；未装 → deep-thinking 自己按第一性原理拆 | 点名模型尊重显式调用；未装时 deep-thinking 就地承接这一步，不让请求落空 |

## 交接协议

- `deep-thinking` 在清点事实时发现界定不清 → 移交 `problem-definition`，不猜测补位硬出结论。
- `problem-definition` → `problem-analysis`：附带收束句（`现状 + 目标 + 差距 + 影响`）作为问题卡输入。
- `problem-analysis` 填问题卡时发现事实未清 → 退回 `problem-definition` 界定。
- 路由规则的单一事实来源在 `deep-thinking` 的「与其他思考类 skill 的协作」章节；本 skill 是入口总览，两处不一致时以 deep-thinking 为准。

## 使用示例

**示例 1 路由判断**：用户问"这三个思考 skill 有什么区别、我该用哪个" →
本 skill 输出成员表 + 决策树，不代替成员执行分析。

**示例 2 模糊请求分流**：用户说"最近感觉工作上哪里不对劲，帮我想想怎么理清" →
先裁决：说不清哪里不对、无明确评估对象 → 路由到 `problem-definition`（AI 推荐模式，从还原事实切入），并向用户说明原因。

**示例 3 系统分析分流**：用户贴出缺陷清单说"帮我看看怎么回事" →
路由到 `problem-analysis`（直接分析模式），问题卡从已有材料填起。

## 为什么不合并成一个 skill

- **默认重量不同**：deep-thinking 始终轻量；problem-analysis 默认重流程。合并会让每个请求都背重流程的负担。
- **交互形态不同**：problem-definition 分步交互（每步停下提问）；deep-thinking 一次性给结论；合并会让轻量请求变啰嗦。
- **各自可独立单点取用**：筛一条事实、跑一个决策矩阵，都不需要走全链。
- **分工原则**：界定（definition）→ 分析（analysis）→ 结论纪律（deep-thinking），每段一段归一个 skill 负责，边界按路由决策树裁决。
