// encoding-assert.mjs
// 验证门槛的核心预言机（V(x,a)）：判定「客户端发出的非-ASCII 文本」是否被
// 网关原样接收、逐字符无损往返。
//
// 判据（两道，都要满足）：
//   1) 语义等价：received === sent（逐字符严格相等）。
//   2) 失效特征：原文在非-ASCII 处若被替换，会出现连续 0x3F（'?'）。
//      只要 sent 含非-ASCII 且 received 含 '?'，即认为命中静默失效特征。
//      （PS5.1 的 Invoke-RestMethod 正是如此：把编码不了的字符替换成 '?'）
//
// 失效若发生，给出诊断信息（哪段被替换），便于归因（VeriSkill Stage1）。

/** 是否含非-ASCII 字符（码点 > 127）。 */
export function hasNonAscii(s) {
  if (typeof s !== "string") return false;
  for (const ch of s) if (ch.codePointAt(0) > 0x7f) return true;
  return false;
}

/** 收集 received 中出现 '?' 的上下文片段（用于诊断）。 */
function detectQuestionMarks(received) {
  const hits = [];
  if (typeof received !== "string") return hits;
  for (let i = 0; i < received.length; i++) {
    if (received[i] === "?") {
      const start = Math.max(0, i - 6);
      const end = Math.min(received.length, i + 7);
      hits.push({ index: i, ctx: received.slice(start, end) });
    }
  }
  return hits;
}

/**
 * 断言 UTF-8 往返无损。
 * @param {string} sent 原始发送文本
 * @param {string} received 网关回显文本
 * @returns {{ pass: boolean, reason?: string, diagnostics?: any }}
 */
export function assertUtf8Preserved(sent, received) {
  // 1) 严格逐字符相等
  if (sent === received) {
    return { pass: true };
  }

  // 2) 不相等：进一步给出失效特征诊断
  const reasons = [];

  // 2a) 回显为空 / 字段缺失
  if (received === undefined || received === null || received === "") {
    return { pass: false, reason: "received 为空（网关未回显或字段缺失）" };
  }

  // 2b) 长度缩短：典型乱码（多字节字符被压成单字节 '?'）
  if (typeof received === "string" && received.length < sent.length) {
    reasons.push(
      `长度缩短：sent=${sent.length} 字符 → received=${received.length} 字符（疑似多字节字符被替换为 '?'）`,
    );
  }

  // 2c) '?' 替换特征：原文非-ASCII、回显出现 '?'，即静默失效
  if (hasNonAscii(sent) && typeof received === "string" && received.includes("?")) {
    const qm = detectQuestionMarks(received);
    reasons.push(
      `检测到 '?' 替换特征：原文含非-ASCII，回显出现 ${qm.length} 处 '?'（首处上下文：「${qm[0]?.ctx ?? ""}」）`,
    );
  }

  // 2d) 反斜杠 / 引号等转义不对称
  if (sent.includes("\\") && typeof received === "string" && !received.includes("\\")) {
    reasons.push("反斜杠丢失：原文含反斜杠但回显没有（疑似转义不对称）");
  }

  return {
    pass: false,
    reason: reasons.length ? reasons.join("；") : "sent 与 received 不相等",
    diagnostics: { sent, received },
  };
}

import { pathToFileURL } from "node:url";

// 直接运行：对一个 (sent, received) 对做断言（便于手工复现）
//   node tests/encoding-assert.mjs "你好" "你好"
// 跨平台入口判定（Windows 上 process.argv[1] 带驱动器号，需经 pathToFileURL 归一化）
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [sent, received] = process.argv.slice(2);
  if (!sent) {
    console.error("用法: node tests/encoding-assert.mjs <sent> [received]");
    process.exit(2);
  }
  const r = assertUtf8Preserved(sent, received ?? "");
  console.log(JSON.stringify(r, null, 2));
  process.exit(r.pass ? 0 : 1);
}
