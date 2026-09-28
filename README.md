# thinking-skills

DeepWorks 思维模型集合（thinking-suite）——四个思考类 skill，按"界定 → 分析 → 结论纪律"分工，边界清晰，各自可独立单点取用。

## 成员与分工

| 成员 | 定位 | 解决什么 | 产物 |
|-|-|-|-|
| [deep-thinking](deep-thinking/SKILL.md) | 思考前置层 | 下结论前该走的工序走了没 | 结论 + 置信度 + 关键假设 + 重判触发器 |
| [problem-definition](problem-definition/SKILL.md) | 问题界定专家 | 事情到底是什么 | 三栏表 / 待问清单 / 核对话术 / 收束句 |
| [problem-analysis](problem-analysis/SKILL.md) | 系统分析执行库 | 怎么系统分析并交付 | 分析卡（问题卡 + 证据 + 行动清单 + 验证指标） |
| [thinking-suite](thinking-suite/SKILL.md) | 集合入口 | 路由判断与分工总览 | 路由决策树 + 歧义裁决表（不执行分析） |

## 路由速查

顺序判断，命中即停：

1. **事情没弄清**（描述模糊 / 感受事实混杂 / 刚接到他人交代）→ `problem-definition`
2. **需要系统分析**（根因 / 拆解 / 乱材料 / 排优先级 / 方案验证 / 出汇报）→ `problem-analysis`
3. **判断题一轮给结论**（该不该 X / X 对不对 / 你怎么看）→ `deep-thinking`
4. **泛化"帮我分析 X"** → `deep-thinking` 默认接，兜不住时移交
5. **集合入口与路由说明** → `thinking-suite`

路由规则的单一事实来源：[deep-thinking/SKILL.md](deep-thinking/SKILL.md) 的「与其他思考 skill 的协作」章节（含歧义裁决表）。

## 目录结构

```
thinking-skills/
├── README.md
├── deep-thinking/          # SKILL.md + references/
├── problem-definition/     # SKILL.md + references/ + templates/
├── problem-analysis/       # SKILL.md + references/ + scripts/
├── thinking-suite/         # SKILL.md
└── scripts/
    └── sync-to-github.ps1  # 本仓库同步脚本（Repo 默认 thinking-skills）
```

## 同步协议（本地工作位置 → 本仓库）

成员的本地工作位置（skill 实际加载处）：

| 成员 | 本地路径 |
|-|-|
| deep-thinking | `<workspace>/.opencode/skills/deep-thinking/` |
| problem-definition | `~/.agents/skills/problem-definition/` |
| problem-analysis | `~/.agents/skills/problem-analysis/` |
| thinking-suite | `~/.agents/skills/thinking-suite/` |

修改 skill 后同步到本仓库：

1. 把成员最新文件复制到本仓库同名子目录（deep-thinking 注意排除 `.git`）
2. 在本仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File ".\scripts\sync-to-github.ps1" -Message "feat: 本次更新说明"
```

脚本走 GitHub REST API 推送，绕开本机 git push 到 github.com 被网络重置的问题，并保证远端提交与本地 git 提交 sha 完全一致，可反复增量同步。凭据自动从 git credential manager 读取，脚本不存任何密钥。

## 历史

本仓库于 2026-09-28 由三个独立仓库合并而成；原 `deep-thinking`、`problem-definition`、`problem-analysis` 三个独立仓库已归档（archive），版本历史仍可在各自仓库中查看。
