---
name: windows-nonascii-http-utf8
version: 2.0.0
description: >-
  保证 Windows 下含非-ASCII 字符（中文、日韩文、西里尔/希腊、emoji、数学符号等）的
  HTTP/JSON 载荷端到端 UTF-8 无损往返。当遇到这些情况时使用：发送中文后「存进去变成
  ???? 乱码」「LLM/Agent Memory 记忆提取为 0 条」「BM25 命中但内容是乱码」「PowerShell
  Invoke-RestMethod/WebRequest 中文丢失」「在 Windows 上调用需要非-ASCII 输入的 REST API
  （各类 LLM API、腾讯云 Agent Memory /capture /search /recall）时字符被替换成问号」。
  提供可复用的 UTF-8 安全 HTTP 客户端（Node）、PowerShell 字节封装（PS5.1/7+）、离线
  可执行验证门槛与失败归因分类法。不负责：纯 ASCII 请求、服务端/数据库字符集问题、
  非编码类网络故障。
---

# Windows 非-ASCII HTTP 编码安全技能

一个**自演化**的 Agent Skill：把一次 Windows PowerShell 中文乱码导致的 Agent Memory
静默失效，按 VeriSkill / SESA 两篇论文的方法论，升级为可触发、可复用、可验证、可演化
的技能。

## 边界

**负责（IN SCOPE）**：
- Windows 客户端发送含非-ASCII 的 HTTP/JSON 载荷时的**字节序列化**问题（传输前）。
- 覆盖：中文/日韩（CJK）、西里尔、希腊、emoji、数学符号、混合长文本。
- 覆盖工具：PowerShell 5.1 的 `Invoke-RestMethod`/`Invoke-WebRequest`、Node 脚本。
- 提供绕过 PS5.1 工具限制的封装，以及「修复是否真的成立」的离线验证门槛。

**不负责（OUT OF SCOPE）**：
- 服务端存储/检索的字符集问题（那是数据库/网关侧 charset 配置）。
- 纯 ASCII 载荷（任何编码都不会损坏）。
- 与编码无关的协议/网络错误。

## 触发场景

| 用户/agent 表述 | 命中 |
|----------------|------|
| 「存进去变成 ???? 乱码」「中文丢失」 | ✓ |
| 「记忆提取为 0 条 / LLM 抽取失败」 | ✓ |
| 「BM25 命中但内容是乱码」 | ✓ |
| 「PowerShell Invoke-RestMethod 中文乱码」 | ✓ |
| 「Windows 下发 emoji/俄文/特殊符号变成 ?」 | ✓ |
| 「调用 LLM API / Agent Memory 时中文乱码」 | ✓ |

## 标准工作流

> 阅读所需文件后再动手——渐进式披露（progressive disclosure）。

1. **先归因**：遇到失效先读 `memory/attribution-taxonomy.md`，确认属于「④ 知识缺口」
   才进入演化；若是「② 工具限制（PS5.1）」，直接走第 2 步的封装绕过，不要改技能内容。
2. **选修复路径**（按优先级）：
   - **推荐** Node：用 `scripts/encoding-safe-http.mjs` 的 `postJson`/`capture`/`searchConversations`/`searchMemories`/`recall`/`roundTrip`。
   - **必须留 PS**：用 `scripts/Send-Utf8Request.ps1` 的 `Send-Utf8RestMethod`（5.1 走字节数组，7+ 走原生）。
3. **复现与证明**：若需向他人证明 bug，跑 `scripts/reproduce-bug.ps1`（对真实网关）或
   `node validation/verify.mjs`（离线，含反向归因证据）。
4. **验证准入**：改动技能后，必须 `node validation/verify.mjs` 返回 exit 0 才算有效；
   见下方「验证门槛」。

## 可复用产物

- `scripts/encoding-safe-http.mjs` — Node 端 UTF-8 安全 HTTP 客户端（强制 `charset=utf-8` + `JSON.stringify`）。
- `scripts/Send-Utf8Request.ps1` — PowerShell UTF-8 封装（版本自动分流）。
- `scripts/e2e-test-fixed.mjs` — 针对真实 TDAI 网关的端到端示例（保留）。
- `scripts/reproduce-bug.ps1` — bug 复现脚本（保留，作为 failure/before 演示）。

## 验证门槛（VeriSkill Stage3）

这是该技能区别于「一次性 bug 报告」的核心：**改动后必须可执行验证**。

```bash
node validation/verify.mjs
# 期望：9/9 corpus 用例通过 + 反向归因符合预期 → exit 0（ACCEPT 候选技能）
```

门槛会：① 启动离线 mock-gateway；② 对分级 corpus（ASCII→CJK→西里尔/希腊→emoji→混合长文本）
逐条做 UTF-8 往返；③ 用预言机 `tests/encoding-assert.mjs` 判定（原文非-ASCII 处不得出现 `?`）；
④ 再用「坏客户端」反向跑一遍证明 bug 真实、根因为客户端序列化。

判定与准入规则对应 VeriSkill 的 Eq.5/6/7：候选必须**严格提升**且**语义保持**，否则维持上一版。

## 失败归因（VeriSkill Stage1）

见 `memory/attribution-taxonomy.md`。要点：最常见的「PS5.1 中文变 ?」属于
**② 工具限制**，技能的正确应对是「绕过」（提供封装/迁移路径），而非试图改 PS5.1。
只有 **④ 知识缺口**（如技能没覆盖 emoji）才触发 lesson 抽象与 corpus 扩展。

## 演化记忆（SESA Remember / VeriSkill Stage2）

- `memory/skill-evolution.md` — v1 seed → 失败归因 → 责任抽象（诊断签名）→ 验证准入 → 后续演化守则。
- `memory/skill-card.json` — SESA 结构化技能卡（category/pattern/distinction/triggers/query_templates/fix_templates）+ 准入去重（0.93）与淘汰（LRU）策略。
- `memory/attribution-taxonomy.md` — 四类失败归因分类法 + 检查清单。

## 如何继续演化（Pose → Solve → Remember）

1. 遇到新失效 → 在 `validation/corpus.json` 加一条能稳定复现的用例（**Pose**）。
2. 用 `scripts/encoding-safe-http.mjs` 跑它（**Solve**）。
3. 按 `memory/attribution-taxonomy.md` 归因；仅「④ 知识缺口」继续。
4. 若是新诊断签名，更新 `skill-evolution.md` 的责任抽象段与 `skill-card.json`，去重阈值 0.93。
5. 跑 `node validation/verify.mjs`；通过才 bump version 并写入 `skill-card.json` 的
   `validation_gate.last_result`（**Remember**）。未通过则进入 revise-test 循环，不回退质量。

## 方法论来源

| 论文机制 | 本技能落地 |
|----------|-----------|
| VeriSkill 技能定义 `J(S)` + Eq.7 准入 | `SKILL.md` + `validation/verify.mjs` 的 exit 0 门槛 |
| VeriSkill Stage1 失败归因（4 类） | `memory/attribution-taxonomy.md` |
| VeriSkill Stage2 责任抽象 + 诊断签名（去示例化） | `memory/skill-evolution.md` 的「责任抽象」段 |
| VeriSkill Stage3 可执行验证与准入 | `validation/`（verify + mock-gateway + corpus）+ `tests/encoding-assert.mjs` |
| SESA Skill Card（category/pattern/...）+ 准入去重 + 淘汰 | `memory/skill-card.json` |
| SESA Pose/Solve/Remember | 本节「如何继续演化」流程 |
| SESA frontier shaping（钟形难度） | `validation/corpus.json` 的 tier 分级 |

> 论文：*VeriSkill: A Self-Evolution Framework for Program Verification Skills*；
> *Self-Play Meets Skill Evolution: Self-Evolving Search Agents that Pose, Solve, and Remember*。
