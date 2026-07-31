# PowerShell Invoke-RestMethod 中文编码问题导致 Agent Memory 记忆提取失败

> **项目背景**：在 Windows 上配置并测试 [TencentDB-Agent-Memory](https://github.com/TencentCloud/TencentDB-Agent-Memory)（腾讯云四层渐进式 Agent 记忆系统）时，发现 PowerShell 的 `Invoke-RestMethod` 在发送含中文的 HTTP 请求时会将字符编码为 `?`，导致 LLM 收到乱码、记忆提取管线静默失败。

## 问题现象

通过 PowerShell `Invoke-RestMethod` 向本地 Gateway 发送 5 轮中文对话后：

| 检查项 | 结果 |
|--------|------|
| L0 JSONL 存储 | 中文全部变成 `????` |
| LLM L1 提取 | 运行了 4 秒，提取出 **0 条记忆** |
| L0 对话搜索 | BM25 命中但内容为乱码 |
| L1 记忆搜索 | 0 条结果 |

### 乱码证据（存储的 JSONL）

```json
{"content":"????,??????????,??? TypeScript ? React ???,Node.js ????"}
```

原始输入应为：
```
我叫张明，是一名全栈开发工程师，主要用 TypeScript 和 React 做前端，Node.js 做后端。
```

## 根因分析

**PowerShell 5.1（Windows 默认）的 `Invoke-RestMethod` 不使用 UTF-8 编码 HTTP body。**

PowerShell 5.1 将字符串转换为字节数组时使用系统默认编码（Windows-1252 / GBK），而非 UTF-8。中文字符在编码过程中被替换为 `?`（0x3F），这个替换是**不可逆**的——数据在网络传输前就已经丢失了。

关键链路：
```
PowerShell 脚本中的中文字符串
  → .NET String（UTF-16 内存表示，正确）
    → Invoke-RestMethod 序列化为 HTTP body 字节流
      → ❌ 使用 Windows-1252 编码，中文字符 → ?
        → Gateway 收到的 JSON 中中文已丢失
          → LLM 收到乱码，无法提取记忆
```

## 解决方案

### 方案一（推荐）：使用 Node.js `fetch` API

Node.js 的 `fetch` 和 `JSON.stringify` 原生使用 UTF-8，无需额外配置：

```javascript
// e2e-test.mjs — UTF-8 safe
const res = await fetch("http://127.0.0.1:8420/capture", {
  method: "POST",
  headers: { "Content-Type": "application/json; charset=utf-8" },
  body: JSON.stringify({
    session_key: "test-session",
    user_content: "我叫张明，是一名全栈开发工程师",
    assistant_content: "你好张明！",
  }),
});
const data = await res.json();
```

### 方案二：PowerShell 中强制 UTF-8 编码

如果必须使用 PowerShell，需要手动将 body 转换为 UTF-8 字节数组：

```powershell
$body = @{
    session_key = "test-session"
    user_content = "我叫张明，是一名全栈开发工程师"
    assistant_content = "你好张明！"
} | ConvertTo-Json -Depth 3

# 关键：将字符串转为 UTF-8 字节
$bytes = [System.Text.Encoding]::UTF8.GetBytes($body)

$response = Invoke-RestMethod -Uri "http://127.0.0.1:8420/capture" `
    -Method Post `
    -ContentType "application/json; charset=utf-8" `
    -Body $bytes
```

### 方案三：升级到 PowerShell 7+

PowerShell 7+ (Core) 默认使用 UTF-8 编码，可直接使用 `Invoke-RestMethod`：

```powershell
# pwsh (PowerShell 7+) 中直接可用
$body = @{ user_content = "中文测试" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://127.0.0.1:8420/capture" -Method Post `
    -ContentType "application/json; charset=utf-8" -Body $body
```

## 验证结果

切换到 Node.js 方案后，端到端测试全部通过：

| 测试项 | 修复前 | 修复后 |
|--------|--------|--------|
| L0 存储 | `????` 乱码 | 中文正确存储 |
| BM25 搜索 score | 0.590 | **0.883** |
| L1 记忆提取 | 0 条 | **1 条 persona 记忆** |
| L1 记忆搜索 | 0 结果 | **命中并返回** |

### 成功提取的 L1 记忆

```json
{
  "content": "用户（张明）是一名全栈开发工程师，主要使用TypeScript和React做前端开发，Node.js做后端开发",
  "type": "persona",
  "priority": 80,
  "scene_name": "我（AI）在和用户张明进行个人身份与技术栈交流"
}
```

## 影响范围

此问题不限于 TencentDB-Agent-Memory，**任何在 Windows PowerShell 5.1 上通过 `Invoke-RestMethod` 发送含非 ASCII 字符（中文、日文、韩文、emoji 等）的 HTTP 请求都会受到影响**。

常见受影响场景：
- 调用需要中文输入的 REST API（OpenAI、各种国产 LLM API）
- 向 API 发送含 Unicode 字符的 JSON 数据
- 测试国际化（i18n）功能的自动化脚本

## 环境信息

| 项目 | 版本 |
|------|------|
| OS | Windows 11 25H2 |
| PowerShell | 5.1 (WindowsPowerShell\v1.0) |
| Node.js | v26.3.1 |
| TencentDB-Agent-Memory | v0.1.0 |
| LLM | 阶跃星辰 step-3.7-flash |

## 文件说明

```
├── README.md              # 本文档（问题分析 + 解决方案）
├── reproduce-bug.ps1      # 问题复现脚本（PowerShell，会产生乱码）
├── e2e-test-fixed.mjs     # 修复后的 E2E 测试脚本（Node.js，UTF-8 安全）
└── LICENSE                # MIT
```

## License

MIT
