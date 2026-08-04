// encoding-safe-http.mjs
// 可复用的 UTF-8 安全 HTTP 客户端（零外部依赖，仅用 Node 内置 fetch）
//
// 设计动机：Windows PowerShell 5.1 的 Invoke-RestMethod 会用 Windows-1252/GBK
// 序列化 HTTP body，把中文等非-ASCII 字符不可逆替换成 0x3F（'?'）。Node.js 的
// fetch + JSON.stringify 原生使用 UTF-8，从源头消除该静默失效。
//
// 这是该技能的「可复用过程知识」载体（对应 VeriSkill 的技能 S、SESA 的 Solve 策略）。
// 所有发往非-ASCII 友好 REST API（如腾讯云 Agent Memory /capture /search /recall、
// OpenAI 及各类国产 LLM API）的请求都应走本模块，而非手写 fetch。
//
// 用法：
//   import { capture, searchConversations, searchMemories, recall, roundTrip } from "./encoding-safe-http.mjs";
//   await capture("http://127.0.0.1:8420", "session-1", "我叫张明", "你好张明！");

// ---- 内部工具 ----

/** 发送一个 UTF-8 安全的 JSON POST 请求。
 *  关键：始终带 charset=utf-8，body 始终用 JSON.stringify（Node 原生 UTF-8）。 */
export async function postJson(url, body, { headers = {}, signal } = {}) {
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Accept": "application/json; charset=utf-8",
      ...headers,
    },
    body: JSON.stringify(body),
    signal,
  });
  const text = await res.text();
  // 不假定对方一定返回 JSON；尽量解析，失败则回退原始文本
  let data;
  try {
    data = text.length ? JSON.parse(text) : {};
  } catch {
    data = { _raw: text };
  }
  return { ok: res.ok, status: res.status, data };
}

/** 通用：对一个 base 依次 POST 若干路径的薄封装，统一注入 UTF-8 头。 */
function builder(base) {
  return {
    post: (path, body, opts) => postJson(`${base}${path}`, body, opts),
  };
}

// ---- 腾讯云 Agent Memory / 通用网关 的常用端点封装 ----
// 注：端点形态取自 TencentDB-Agent-Memory 的 Gateway，但字段足够通用，可直接复用。

/** /capture：记录一轮对话（user_content / assistant_content 必须端到端 UTF-8）。 */
export async function capture(base, sessionKey, userContent, assistantContent, opts) {
  return postJson(
    `${base}/capture`,
    { session_key: sessionKey, user_content: userContent, assistant_content: assistantContent },
    opts,
  );
}

/** /search/conversations：L0 原始对话检索。 */
export async function searchConversations(base, query, { limit = 5 } = {}, opts) {
  return postJson(`${base}/search/conversations`, { query, limit }, opts);
}

/** /search/memories：L1 抽取记忆检索。 */
export async function searchMemories(base, query, { limit = 5 } = {}, opts) {
  return postJson(`${base}/search/memories`, { query, limit }, opts);
}

/** /recall：给定 query 召回上下文。 */
export async function recall(base, query, sessionKey, opts) {
  return postJson(`${base}/recall`, { query, session_key: sessionKey }, opts);
}

/** 通用 client：base 之外还想调用任意端点时使用。 */
export function createClient(base) {
  const api = builder(base);
  return {
    capture: (s, u, a, o) => capture(base, s, u, a, o),
    searchConversations: (q, o, opt) => searchConversations(base, q, o, opt),
    searchMemories: (q, o, opt) => searchMemories(base, q, o, opt),
    recall: (q, s, o) => recall(base, q, s, o),
    raw: (path, body, opts) => api.post(path, body, opts),
  };
}

// ---- 验证门槛（VeriSkill Stage3）使用的预言机：端到端 UTF-8 往返 ----
// 流程：把任意文本以 JSON 形式 POST 给一个「回显」端点，再把对方回显的文本与
// 原文逐字符比对。若原文含非-ASCII、回显出现 0x3F(?) 替换，即判定编码破损。
//
// 这里默认走 echo 路径 /__echo；validation/mock-gateway.mjs 实现了该端点。
// 你也可传入 echoPath 指向自己网关里任意「原样回传 body 文本」的调试端点。
export async function roundTrip(base, text, { echoPath = "/__echo", field = "text" } = {}) {
  const res = await postJson(`${base}${echoPath}`, { [field]: text });
  const received = res.data?.[field];
  return { ok: res.ok, status: res.status, sent: text, received };
}

// ---- 自检：被 import 时可直接运行 ----
// 用法：node scripts/encoding-safe-http.mjs <base>
import { pathToFileURL } from "node:url";
// process.argv[1] 在 --input-type=module -e 等场景下可能为 undefined，此时跳过 CLI 入口
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const base = process.argv[2] || "http://127.0.0.1:8420";
  const sample = "我叫张明，全栈工程师，技术栈：TypeScript + React + Node.js ✓ 🚀";
  console.log(`[encoding-safe-http] round-trip self-check against ${base}`);
  try {
    const r = await roundTrip(base, sample);
    const pass = r.received === sample;
    console.log(`  sent:     ${sample}`);
    console.log(`  received: ${r.received ?? "(no echo)"}`);
    console.log(`  result:   ${pass ? "PASS (UTF-8 preserved)" : "FAIL (encoding broken / no echo)"}`);
    process.exit(pass ? 0 : 1);
  } catch (e) {
    console.error(`  error: ${e.message} (服务是否已启动？)`);
    process.exit(2);
  }
}
