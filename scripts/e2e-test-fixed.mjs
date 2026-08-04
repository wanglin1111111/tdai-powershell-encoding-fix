// e2e-test-fixed.mjs
// 修复后的 E2E 测试脚本：使用 Node.js fetch API，原生 UTF-8 编码
// 运行前需先启动 TDAI Gateway (npx tsx src/gateway/server.ts)
// 用法: node e2e-test-fixed.mjs

const BASE = "http://127.0.0.1:8420";
const SESSION = "e2e-utf8-fixed";

// ---- 测试数据 ----
const conversations = [
  {
    user: "我叫张明，是一名全栈开发工程师，主要用 TypeScript 和 React 做前端，Node.js 做后端。",
    assistant: "你好张明！你的全栈技术栈很主流，TypeScript + React + Node.js 是目前非常高效的开发组合。",
  },
  {
    user: "我正在做一个叫 Magic Resume 的开源简历编辑器项目，用 TanStack Router 做路由，支持多模板切换。",
    assistant: "Magic Resume 听起来是个很实用的项目！TanStack Router 是类型安全的路由方案。",
  },
  {
    user: "我们团队最近还在研究 AI Agent 记忆系统，想在产品里加入个性化推荐能力。",
    assistant: "AI Agent 记忆系统是个前沿方向。四层渐进式记忆能有效降低 token 消耗。",
  },
  {
    user: "对了，我的 GitHub 用户名是 zhangming-dev，项目仓库是 magic-resume。",
    assistant: "已记下你的 GitHub 信息。如果后续需要配置 CI/CD 或自动化部署，随时可以帮你设置。",
  },
  {
    user: "我住在中国武汉，平时周末喜欢去东湖绿道骑行，也参加本地的 AI 技术沙龙。",
    assistant: "武汉是个充满活力的城市！东湖绿道非常适合骑行放松。",
  },
];

// ---- API 调用 ----
async function capture(user, assistant) {
  const res = await fetch(`${BASE}/capture`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify({ session_key: SESSION, user_content: user, assistant_content: assistant }),
  });
  return res.json();
}

async function searchConversations(query) {
  const res = await fetch(`${BASE}/search/conversations`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify({ query, limit: 5 }),
  });
  return res.json();
}

async function searchMemories(query) {
  const res = await fetch(`${BASE}/search/memories`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify({ query, limit: 5 }),
  });
  return res.json();
}

async function recall(query) {
  const res = await fetch(`${BASE}/recall`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify({ query, session_key: SESSION }),
  });
  return res.json();
}

// ---- 主流程 ----
console.log("=== Step 1: Capture 5 rounds (UTF-8 safe) ===");
for (let i = 0; i < conversations.length; i++) {
  const r = await capture(conversations[i].user, conversations[i].assistant);
  console.log(`  Round ${i + 1}: l0=${r.l0_recorded}, notified=${r.scheduler_notified}`);
  await new Promise((r) => setTimeout(r, 600));
}

console.log("\n=== Step 2: Wait for L1 extraction (15s) ===");
console.log("  (LLM will extract persona/episodic/instruction memories)");
await new Promise((r) => setTimeout(r, 15000));

console.log("\n=== Step 3: L0 Conversation Search ===");
const l0 = await searchConversations("全栈开发工程师");
console.log(`  total: ${l0.total}`);
console.log(`  preview: ${l0.results?.slice(0, 200)}...`);

console.log("\n=== Step 4: L1 Memory Search ===");
const l1 = await searchMemories("全栈开发工程师");
console.log(`  total: ${l1.total}, strategy: ${l1.strategy}`);
console.log(`  results: ${l1.results?.slice(0, 300)}`);

console.log("\n=== Step 5: Recall ===");
const rc = await recall("张明的技术栈");
console.log(`  memory_count: ${rc.memory_count}`);
console.log(`  context: ${rc.context?.slice(0, 300) ?? "(empty)"}`);

console.log("\n=== All tests completed ===");
console.log("Verify stored data at: ~/.memory-tencentdb/memory-tdai/conversations/");
console.log("Chinese characters should be correctly preserved (not ????)");
