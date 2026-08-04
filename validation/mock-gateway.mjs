// mock-gateway.mjs
// 离线 Mock 网关（零外部依赖，仅用 Node 内置 http）。
//
// 作用：验证门槛（VeriSkill Stage3）需要一个可信任的「真值」来源——它必须能
// 精确回显「自己实际收到的字节」，才能判断客户端的编码是否破坏了非-ASCII 文本。
// 真实网关（TencentDB-Agent-Memory Gateway / 各类 LLM API）通常不会把原始字节
// 吐回来，因此验证必须用一个我们自己掌控、行为确定的 Mock。
//
// 它实现两组端点：
//   1) 行为端点（模拟真实网关的语义）：/capture、/search/conversations、
//      /search/memories、/recall —— 内存存储 + 简单子串检索，便于端到端跑通。
//   2) 真值端点：/__echo —— 把解析后的 body 原样回显，用于字节级 UTF-8 断言。
//
// 内存存储按 session_key 隔离；进程退出即清空（仅用于验证）。

import http from "node:http";
import { URL, pathToFileURL } from "node:url";

/** 解析请求 body 为 JSON；非 JSON 则返回原始文本。 */
function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => {
      const buf = Buffer.concat(chunks);
      const text = buf.toString("utf8");
      try {
        resolve({ json: text.length ? JSON.parse(text) : {}, raw: text, bytes: buf });
      } catch {
        resolve({ json: null, raw: text, bytes: buf });
      }
    });
    req.on("error", () => resolve({ json: null, raw: "", bytes: Buffer.alloc(0) }));
  });
}

/** 构造一个内存存储。 */
function createStore() {
  const conversations = new Map(); // session_key -> [{user_content, assistant_content}]
  return {
    capture(sessionKey, userContent, assistantContent) {
      if (!conversations.has(sessionKey)) conversations.set(sessionKey, []);
      const rec = { user_content: userContent ?? "", assistant_content: assistantContent ?? "", t: Date.now() };
      conversations.get(sessionKey).push(rec);
      return rec;
    },
    searchConversations(query, limit) {
      const out = [];
      for (const [, recs] of conversations) {
        for (const r of recs) {
          if (String(r.user_content).includes(query) || String(r.assistant_content).includes(query)) {
            out.push(r);
          }
        }
      }
      return { total: out.length, results: out.slice(0, limit) };
    },
    searchMemories(query, limit) {
      // 简化：把对话片段当作「记忆」回显，重点验证编码而非检索语义
      const hits = [];
      for (const [, recs] of conversations) {
        for (const r of recs) {
          if (String(r.user_content).includes(query)) hits.push({ content: r.user_content });
        }
      }
      return { total: hits.length, strategy: "mock-substring", results: hits.slice(0, limit) };
    },
    recall(query, sessionKey) {
      const recs = conversations.get(sessionKey) ?? [];
      const ctx = recs.map((r) => r.user_content).join("\n");
      const hit = ctx.includes(query);
      return { memory_count: hit ? 1 : 0, context: hit ? ctx : "" };
    },
  };
}

/** 启动 mock 网关。返回 { server, url, close }。 */
export function startMockGateway({ port = 0, host = "127.0.0.1" } = {}) {
  return new Promise((resolve) => {
    const store = createStore();
    const server = http.createServer(async (req, res) => {
      const u = new URL(req.url, `http://${req.headers.host}`);
      const path = u.pathname;
      const { json } = await readBody(req);

      const send = (obj, status = 200) => {
        const body = JSON.stringify(obj);
        res.writeHead(status, {
          "Content-Type": "application/json; charset=utf-8",
          "Content-Length": Buffer.byteLength(body, "utf8"),
        });
        res.end(body);
      };

      try {
        if (req.method !== "POST") {
          send({ error: "method not allowed" }, 405);
          return;
        }

        switch (path) {
          case "/__echo": {
            // 真值端点：原样回显解析后的 JSON（保留全部 Unicode）
            send(json ?? { _raw: "" });
            return;
          }
          case "/capture": {
            const rec = store.capture(json.session_key, json.user_content, json.assistant_content);
            send({ l0_recorded: true, scheduler_notified: true, record: rec });
            return;
          }
          case "/search/conversations": {
            send(store.searchConversations(json.query, json.limit ?? 5));
            return;
          }
          case "/search/memories": {
            send(store.searchMemories(json.query, json.limit ?? 5));
            return;
          }
          case "/recall": {
            send(store.recall(json.query, json.session_key));
            return;
          }
          default:
            send({ error: "not found", path }, 404);
        }
      } catch (e) {
        send({ error: String(e && e.message ? e.message : e) }, 500);
      }
    });

    server.on("error", (err) => {
      // 监听 server 错误，避免未捕获事件导致进程异常退出
      console.error("[mock-gateway] server error:", err.message);
    });

    server.listen(port, host, () => {
      const addr = server.address();
      const url = `http://${host}:${addr.port}`;
      resolve({
        server,
        url,
        // 稳健关闭：先停止接受新连接，再关闭底层 server。
        // 直接 server.close() 在 Windows 上偶发 libuv 断言（UV_HANDLE_CLOSING），
        // 尤其是仍有 keep-alive 连接时。先 unref + closeAllConnections 更安全。
        close: () =>
          new Promise((r) => {
            server.close(() => r());
            // 兜底：若 closeAllConnections 可用（Node 18.2+），强制关闭闲置连接
            if (typeof server.closeAllConnections === "function") {
              try { server.closeAllConnections(); } catch {}
            }
          }),
      });
    });
  });
}

// 直接运行：node validation/mock-gateway.mjs [port]
// 注意：当被以 --input-type=module -e 等方式加载时 process.argv[1] 可能为 undefined，
// 此时跳过 CLI 入口（仅作为模块被 import），避免 pathToFileURL 崩溃。
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.argv[2] || 8420);
  const { url } = await startMockGateway({ port, host: "127.0.0.1" });
  console.log(`[mock-gateway] listening on ${url}  (Ctrl+C 退出)`);
  console.log(`  /__echo / /capture / /search/conversations / /search/memories / /recall`);
}
