# Windows 非-ASCII HTTP 编码安全技能（自演化 Agent Skill）

> 从一个真实的 Windows PowerShell 中文乱码 bug，按 **VeriSkill** 与 **SESA** 两篇论文的
> 方法论，升级为**可触发、可复用、可验证、可演化**的 Agent Skill。

**原项目背景**：在 Windows 上测试 [TencentDB-Agent-Memory](https://github.com/TencentCloud/TencentDB-Agent-Memory)
（腾讯云四层渐进式 Agent 记忆系统）时，发现 PowerShell 5.1 的 `Invoke-RestMethod` 发送中文
请求时把字符编码为 `?`，导致 LLM 收到乱码、记忆提取管线静默失败。

**本次升级**：把这个一次性 bug 报告，泛化为「保证 Windows 下非-ASCII HTTP 载荷端到端
UTF-8 安全」的通用技能——可被 agent 触发命中、提供可复用代码、带有离线可执行验证门槛，
并具备失败归因 + 责任抽象 + 准入演化的完整闭环。

---

## 快速开始

```bash
# 1) 验证门槛（离线、零依赖）：确认当前技能在分级 corpus 上全部通过
node validation/verify.mjs
# 期望输出末尾：准入决策：ACCEPT v2 ... 结果: PASS (exit 0)

# 2) 想看 bug 真实长什么样（需要先启动一个真实/兼容网关）
#    .\scripts\reproduce-bug.ps1   # PS5.1 原生 Invoke-RestMethod → 中文变 ????

# 3) 用修复后的端到端示例（针对真实 TDAI 网关）
#    node scripts/e2e-test-fixed.mjs
```

## 核心问题与根因（一句话版）

> **Windows PowerShell 5.1 的 `Invoke-RestMethod` 用系统默认编码（Windows-1252/GBK）
> 序列化 HTTP body，把中文等非-ASCII 字符不可逆替换成 `0x3F`（`?`）——数据在网络
> 传输前就已丢失，且无任何报错。**

```
PowerShell 脚本中的中文字符串
  → .NET String（UTF-16 内存表示，正确）
    → Invoke-RestMethod 序列化为 HTTP body 字节流
      → ❌ 使用 Windows-1252 编码，中文字符 → ?
        → 网关收到的 JSON 中中文已丢失
          → LLM 收到乱码，无法提取记忆（静默失败）
```

三种修复（按推荐度）：① **Node `fetch`**（原生 UTF-8，见 `scripts/encoding-safe-http.mjs`）；
② **PowerShell 字节封装**（见 `scripts/Send-Utf8Request.ps1`）；③ **升级 PowerShell 7+**。

---

## 方法论映射（两篇论文 → 本仓库产物）

| 论文机制 | 本仓库落地 |
|----------|-----------|
| VeriSkill 技能定义 `J(S)`；Eq.7 准入（严格提升 + 语义保持） | [`SKILL.md`](SKILL.md) + [`validation/verify.mjs`](validation/verify.mjs) 的 exit 0 门槛 |
| VeriSkill Stage1 失败归因与过滤（4 类，区分工具限制 vs 知识缺口） | [`memory/attribution-taxonomy.md`](memory/attribution-taxonomy.md) |
| VeriSkill Stage2 责任抽象 + 诊断签名（去示例化） | [`memory/skill-evolution.md`](memory/skill-evolution.md) 的「责任抽象」段 |
| VeriSkill Stage3 可执行验证与准入（Eq.5/6/7） | [`validation/`](validation) + [`tests/encoding-assert.mjs`](tests/encoding-assert.mjs) |
| VeriSkill 演化记忆（归因/lesson/验证/准入全留痕） | [`memory/skill-evolution.md`](memory/skill-evolution.md) |
| SESA Skill Card（category/pattern/distinction/triggers/query_templates） | [`memory/skill-card.json`](memory/skill-card.json) |
| SESA 准入去重（余弦 ≤ 0.93）+ 淘汰（净负分/LRU） | [`memory/skill-card.json`](memory/skill-card.json) 的 admission/eviction |
| SESA Pose/Solve/Remember | [`validation/corpus.json`](validation/corpus.json)（造题）→ `scripts/encoding-safe-http.mjs`（解题）→ evolution 记忆（记忆） |
| SESA frontier shaping（钟形难度奖励） | [`validation/corpus.json`](validation/corpus.json) 的 tier 分级（t0–t4） |

---

## 文件地图

```
├── SKILL.md                       # 技能本体：可触发描述 + 边界 + 工作流 + 验证门槛
├── README.md                      # 本文档（升级叙事 + 方法论映射 + 快速开始）
├── LICENSE                        # MIT
├── scripts/
│   ├── encoding-safe-http.mjs     # 可复用 UTF-8 HTTP 客户端（postJson/capture/search*/recall/roundTrip）
│   ├── Send-Utf8Request.ps1       # PowerShell UTF-8 封装（5.1 字节数组 / 7+ 原生自动分流）
│   ├── reproduce-bug.ps1          # bug 复现脚本（PS5.1 → 中文变 ????）
│   └── e2e-test-fixed.mjs         # 针对真实 TDAI 网关的修复后端到端示例
├── validation/
│   ├── verify.mjs                 # 可执行验证门槛（VeriSkill Stage3 准入闸）
│   ├── mock-gateway.mjs           # 离线 mock 网关（/__echo + /capture + /search/* + /recall）
│   └── corpus.json                # 分级非-ASCII 语料（t0 ASCII → t4 混合长文本）
├── memory/
│   ├── skill-evolution.md         # 演化记忆日志（v1→v2 归因/lesson/验证/准入）
│   ├── skill-card.json            # SESA 结构化技能卡 + 准入/淘汰策略
│   └── attribution-taxonomy.md    # VeriSkill Stage1 失败归因分类法（本领域）
└── tests/
    └── encoding-assert.mjs        # 字节级 UTF-8 往返断言（V(x,a) 预言机）
```

---

## 验证结果（最近一次）

```
$ node validation/verify.mjs
================================================================
[1/2] 主验证：encoding-safe-http (候选 v2)
  PASS  t0-ascii / t1-zh-intro / t1-zh-address / t2-cyrillic / t2-greek
  PASS  t3-emoji / t3-symbols / t4-mixed-long / t4-json-special
  按 tier 通过率：t0..t4 各 100%
  总计: 9/9  (100.0%)
[2/2] 反向归因：latin1 broken client
  非-ASCII 用例应全部失败 → 失败 8/8   ✓ 符合预期
准入决策：ACCEPT v2  结果: PASS (exit 0)
```

| 验证项 | v1（一次性修复） | v2（自演化技能） |
|--------|------------------|------------------|
| 中文往返 | 单点示例，无系统验证 | t1 全过 |
| emoji/西里尔/希腊 | 未覆盖 | t2/t3 全过 |
| 混合长文本 | 未覆盖 | t4 全过 |
| 反向归因证据 | 无 | latin1 坏客户端 8/8 失败，双向印证根因 |
| 可触发 | 无 | SKILL.md 描述 + 触发表 |
| 失败归因流程 | 无 | 四类分类法 + 检查清单 |
| 演化闭环 | 无 | Pose→Solve→Remember + 准入去重/淘汰 |

---

## 如何继续演化这个技能

1. **造题（Pose）**：遇到新的编码失效，在 `validation/corpus.json` 加一条能稳定复现的用例。
2. **解题（Solve）**：用 `scripts/encoding-safe-http.mjs`（或 PS 封装）跑它。
3. **归因**：按 `memory/attribution-taxonomy.md` 判断——只有「④ 知识缺口」才演化技能内容；
   若是「② 工具限制」，用封装绕过即可。
4. **抽象 lesson**：若是新诊断签名（非「客户端序列化非 UTF-8」），更新
   `memory/skill-evolution.md` 与 `memory/skill-card.json`，去重阈值 0.93。
5. **验证准入（Remember）**：跑 `node validation/verify.mjs`；通过才 bump version 并记录，
   否则进入 revise-test 循环，**不回退技能质量**。

---

## 影响范围

此问题不限于 TencentDB-Agent-Memory。**任何在 Windows PowerShell 5.1 上通过
`Invoke-RestMethod` 发送含非-ASCII 字符（中文、日文、韩文、emoji、西里尔等）的 HTTP 请求
都会受到影响**。常见场景：调用需中文输入的 REST API（OpenAI、各类国产 LLM API）、
向 API 发送含 Unicode 的 JSON、国际化（i18n）功能的自动化测试。

## 环境信息

| 项目 | 版本 |
|------|------|
| OS | Windows 11 25H2 |
| PowerShell | 5.1（WindowsPowerShell\v1.0） |
| Node.js | v26.3.1（验证门槛所需） |
| TencentDB-Agent-Memory | v0.1.0（原始复现场景） |
| LLM | 阶跃星辰 step-3.7-flash（原始复现场景） |

## 方法论参考

- **VeriSkill**: *A Self-Evolution Framework for Program Verification Skills* —— 三阶段闭环（失败归因 → 责任抽象 → 可执行验证与准入）。
- **SESA**: *Self-Play Meets Skill Evolution: Self-Evolving Search Agents that Pose, Solve, and Remember* —— Skill Card + Pose/Solve/Remember + 准入去重/淘汰。

## License

MIT
