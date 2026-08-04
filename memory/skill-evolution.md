# 技能演化记忆（Skill Evolution Memory）

> 对应论文：
> - **VeriSkill** —— Stage1 失败归因 / Stage2 责任抽象（lesson）/ Stage3 可执行验证与准入。
> - **SESA** —— Pose/Solve/Remember 闭环，技能卡的「写回有界非参数记忆」。
>
> 这份文件是该技能的**演化记忆**：记录每一次「失败 → 归因 → lesson → 验证 → 准入/拒绝」
> 的完整轨迹。VeriSkill 明确要求：被拒绝的修订也要留痕，避免重复无效更新。

---

## v1（seed）—— 一次性 bug 报告

**起点**：原仓库是一个针对 TencentDB-Agent-Memory 的 PowerShell 编码 bug 复现 + 单点修复。

**已有产物**：
- `scripts/reproduce-bug.ps1`：复现脚本（PS5.1 原生 `Invoke-RestMethod`，产生 `????`）。
- `scripts/e2e-test-fixed.mjs`：单点修复脚本（Node `fetch`）。
- `README.md`：根因分析 + 三种修复方案。

**局限（v1 的「失败」）**：
1. 是**示例级**产物（绑定「张明 / Magic Resume / TDAI 端口 8420」），不具备跨场景可复用性。
2. 没有**可触发**的技能描述——agent 不会主动命中它。
3. 没有**验证门槛**——无法回答「我的修复真的在所有非-ASCII 上都成立吗」。
4. 没有**演化闭环**——遇到 emoji/西里尔这类新失效时，没有既定流程。

---

## 失败归因（Stage1）—— 为什么 v1 不够

| 失效 | 归因类别（见 `attribution-taxonomy.md`） | 结论 |
|------|------------------------------------------|------|
| PS5.1 下中文变 `????` | **② 工具限制** | 不试图改 PS5.1；技能职责是「指出限制 + 给绕过路径」。 |
| 其它脚本/语言复用时无可复用代码 | **④ 知识缺口** | 抽象出可复用的 UTF-8 HTTP 客户端 + PS 封装。 |
| 无法回答「修复是否对 emoji/西里尔也成立」 | **④ 知识缺口** | 建立 corpus + 可执行验证门槛。 |
| v1 内容是示例级（绑定具体人物） | **④ 知识缺口（去示例化）** | 责任抽象为「非-ASCII 端到端 UTF-8」，剥离示例。 |

**反向归因证据**（`verify.mjs` 第二段）：用 latin1 坏客户端对 corpus 跑，非-ASCII 用例
8/8 全部失败；用编码安全客户端跑，9/9 全部通过。双向印证：失效真实存在，根因为客户端
序列化，技能的「绕过工具限制」策略有效。

---

## 责任抽象（Stage2）—— 从 v1 提炼可复用 lesson

**诊断签名（diagnostic signature）**——这是 VeriSkill 让 lesson 可迁移的关键，去示例化：

- **证明义务定位（proof-obligation localization）**：
  HTTP 请求体的**字节序列化阶段**（客户端侧、传输前）。不涉及服务端存储、不涉及检索语义。

- **验证责任抽象（verification-responsibility abstraction）**：
  「保证 Windows 下非-ASCII HTTP 载荷端到端 UTF-8 无损往返」。
  —— 保留这个可复用责任；剥离「张明」「Magic Resume」「8420 端口」等示例级路径信息。

- **技能失效机制（skill failure mechanism）**：
  PS5.1 的 `Invoke-RestMethod` 用系统默认编码（Windows-1252/GBK）序列化字符串，
  多字节字符被**不可逆替换为 0x3F（'?'）**，且**无任何报错**——这正是「静默失效」，
  也是它最危险的地方（数据在网络传输前已丢失，调用方毫无感知）。

**可复用产物（lesson 的代码具现）**：
- `scripts/encoding-safe-http.mjs`：Node 端 UTF-8 HTTP 客户端（强制 `charset=utf-8` + `JSON.stringify`）。
- `scripts/Send-Utf8Request.ps1`：PS 封装（5.1 走字节数组，7+ 走原生）。

---

## 可执行验证与准入（Stage3）—— v2 候选

**候选技能 S' = v2**（本仓库当前状态）。

**局部验证（Eq.5）**：对归因集与同模式迁移集（这里合并为 corpus 全集）：
- 归因集效果 τ̂_attr：v1 的失效场景（中文）→ v2 通过 ✓
- 迁移集效果 τ̂_trans：同模式未见案例（西里尔/希腊/emoji/混合）→ v2 通过 ✓

**全局成功率（Eq.6）**：`Ĵ_V(v2) = 9/9 = 100%`，`Ĵ_V(v1) ≈ 仅中文单点，无系统验证`。

**语义保持（M(x,a)=1）**：所有用例的发送文本与回显文本逐字符相等，无非-ASCII 处的
`?` 替换——即 HTTP 载荷语义未被修改。

**准入决策（Eq.7）**：`Ĵ_V(v2) > Ĵ_V(v1)` 且语义保持 ⇒ **ACCEPT v2**。

**验证命令与最近结果**：
```
$ node validation/verify.mjs
...
  总计: 9/9  (100.0%)
准入决策：ACCEPT v2（候选技能在全部 corpus 上严格通过，语义无损）
结果: PASS (exit 0)
```

---

## v2.1 —— 第二轮演化（能力边界扩展 + 部署健壮性 + CI 门禁）

v2 准入后，按「后续演化守则」再跑了一轮 Pose→Solve→Remember，产出 v2.1：

**① 能力边界扩展（frontier shaping）**：把 corpus 从 9 条扩到 14 条，新增 t5 tier（能力边界）：
- RTL 脚本（阿拉伯文、希伯来文）——验证方向性字符不损坏
- 泰文（无词间空格，易被错误截断）
- 零宽字符（U+200B/U+200D）与组合字符（U+0308）——往返须逐字符相等
- ZWJ emoji 序列、肤色修饰符、国旗码点（多码点单字形，最易被拆分）

**② 部署健壮性 lesson（真实发现的 ④ 知识缺口）**：编写 PowerShell Pester 测试时触发了一个
**新的诊断签名**——失效不在「发送 HTTP」，而在「PS5.1 读取含中文的 `.ps1` 脚本」。
无 BOM 时 PS5.1 按 GBK 读取脚本，中文直接变乱码导致解析失败。这是 PS5.1 编码问题的
**另一个面**（与 `Invoke-RestMethod` 的 body 序列化是不同根因，但同属「PS5.1 非 UTF-8」）。
- **lesson**：含非-ASCII 的 `.ps1` 必须保存为 **UTF-8 with BOM**。
- **落地**：`scripts/Send-Utf8Request.ps1`、`tests/*.Tests.ps1` 均加 BOM；归因分类法新增
  第 5 项检查（见 `attribution-taxonomy.md`）。

**③ CI 强制门禁**：新增 `.github/workflows/verify.yml`，把 Stage3 的「可执行验证」从手动
升级为 push/PR 自动门禁（Node 侧 `verify.mjs` 双平台 + Windows 侧 Pester）。对应 VeriSkill
「只有通过验证才准入」的自动化。

**④ PowerShell 自有验证**：新增 `tests/Send-Utf8Request.Tests.ps1`（Pester，版本自适应 3.x/5）。
此前只有 Node 侧有 `verify.mjs`，PS 侧缺独立验证；现在 PS5.1 字节数组路径与 PS7+ 原生路径
都有断言覆盖。

**验证准入（v2.1）**：
```
node validation/verify.mjs      → 14/14 (100.0%)，反向归因 13/13，ACCEPT v2.1 (exit 0)
Invoke-Pester tests/Send-Utf8Request.Tests.ps1（PS5.1 + Pester 3.4）
                                → 10/10 PASS（含中文/西里尔/emoji/拉丁扩展往返 + '?'替换检测）
```
PS7+ 路径本机无法验证（无 pwsh），由 CI 的 windows-latest 覆盖。

**准入决策**：`Ĵ_V(v2.1)=14/14 > Ĵ_V(v2)=9/9`，语义保持，新增 PS 侧独立验证 ⇒ **ACCEPT v2.1**。

---

## 后续演化守则（对应 SESA Remember / VeriSkill 演化循环）

当再次遇到编码失效时，按此闭环处理：

1. **Pose（造题）**：在 `corpus.json` 加一条能稳定复现该失效的用例（标注 tier）。
2. **Solve（解题）**：用 `scripts/encoding-safe-http.mjs`（或 PS 封装）对它做 roundTrip。
3. **归因（Stage1）**：按 `attribution-taxonomy.md` 判断类别。仅 **④ 知识缺口** 才继续。
4. **抽象 lesson（Stage2）**：如出现新诊断签名（非「客户端序列化非 UTF-8」），更新本文件的
   「责任抽象」段与 `skill-card.json` 的 `diagnostic_signature`；去重阈值 0.93。
5. **验证准入（Stage3）**：跑 `node validation/verify.mjs`。
   - 通过（exit 0）→ 更新本文件「准入决策」段、`skill-card.json` 的 `validation_gate.last_result`、bump version。
   - 未通过（exit 1）→ 进入 revise-test 循环，直到严格提升且语义保持，否则保持上一版（不回退技能质量）。
6. **淘汰（SESA eviction）**：若某条 corpus 用例在 3 次验证中均无新信息（不区分好坏），
   或与现有用例相似度 > 0.93，则移除以控制噪声。

**版本约定**：`SKILL.md` 的 `version` 与 `skill-card.json` 同步；每次准入 bump minor（如 2.0.0 → 2.1.0）。
