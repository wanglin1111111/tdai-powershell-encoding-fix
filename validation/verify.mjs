// verify.mjs
// VeriSkill Stage3「可执行验证与准入闸」的离线实现。
//
// 流程（对应论文 Algorithm 1 的第三阶段）：
//   1) 启动 mock-gateway（可控真值来源）
//   2) 读取 corpus.json 的分级用例（SESA frontier shaping：从 ASCII 压到混合长文本）
//   3) 对每个用例：
//        a. 经「编码安全客户端」(encoding-safe-http) 做 roundTrip —— Solve
//        b. 用 V(x,a) 预言机 (encoding-assert) 判定是否 UTF-8 无损 —— Validate
//   4) 计算各 tier 与总通过率；全过 exit 0，否则 exit 1 —— Admission
//
// 同时做一次「反向归因」：用一个刻意用 latin1 序列化的坏客户端对同一 corpus 跑一遍，
// 预期 t1+ 全挂，从而证明：a) bug 真实存在；b) 是客户端编码而非网关问题。
// 这一步对应 VeriSkill 的失败归因证据，避免把「求解器能力不足」误判为「技能缺陷」。
//
// 用法：node validation/verify.mjs

import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";
import { startMockGateway } from "./mock-gateway.mjs";
import { roundTrip } from "../scripts/encoding-safe-http.mjs";
import { assertUtf8Preserved } from "../tests/encoding-assert.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const corpusPath = path.join(__dirname, "corpus.json");

function pct(n, d) {
  return d === 0 ? "n/a" : `${((n / d) * 100).toFixed(1)}%`;
}

/** 用编码安全客户端跑一轮验证。返回 {results, passed, total}。 */
async function runWithClient(gatewayUrl, cases, { label, postFn }) {
  const results = [];
  let passed = 0;
  for (const c of cases) {
    let received;
    try {
      const r = await postFn(gatewayUrl, c.text);
      received = r.received;
    } catch (e) {
      received = undefined;
    }
    const verdict = assertUtf8Preserved(c.text, received);
    passed += verdict.pass ? 1 : 0;
    results.push({ id: c.id, tier: c.tier, pass: verdict.pass, reason: verdict.reason });
  }
  return { label, results, passed, total: cases.length };
}

/** 一个「坏客户端」：用 latin1 序列化，复现 PS5.1 的 0x3F 替换行为。 */
async function brokenRoundTrip(gatewayUrl, text) {
  const body = Buffer.from(JSON.stringify({ text }), "utf8").toString("latin1");
  const res = await fetch(`${gatewayUrl}/__echo`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body,
  });
  const data = await res.json().catch(() => ({}));
  return { received: data.text };
}

async function main() {
  const corpus = JSON.parse(fs.readFileSync(corpusPath, "utf8"));
  const cases = corpus.cases.filter((c) => c.expectUtf8);

  const { url, close } = await startMockGateway();

  console.log("=".repeat(64));
  console.log("VeriSkill Stage3 可执行验证门槛（离线）");
  console.log(`mock-gateway: ${url}`);
  console.log(`corpus 用例数: ${cases.length}`);
  console.log("=".repeat(64));

  // ---- 主验证：编码安全客户端（待准入的候选技能 v2）----
  const good = await runWithClient(url, cases, {
    label: "encoding-safe-http (候选 v2)",
    postFn: (base, text) => roundTrip(base, text, { echoPath: "/__echo", field: "text" }),
  });

  console.log(`\n[1/2] 主验证：${good.label}`);
  const byTier = new Map();
  for (const r of good.results) {
    const t = r.tier;
    byTier.set(t, byTier.get(t) || { pass: 0, total: 0 });
    byTier.get(t).total += 1;
    byTier.get(t).pass += r.pass ? 1 : 0;
    const tag = r.pass ? "PASS" : "FAIL";
    console.log(`  ${tag}  ${r.id.padEnd(16)} ${r.tier}  ${r.reason ?? ""}`);
  }
  console.log("\n  按 tier 通过率：");
  for (const [t, v] of [...byTier.entries()].sort()) {
    console.log(`    ${t}: ${v.pass}/${v.total}  (${pct(v.pass, v.total)})`);
  }
  console.log(`  总计: ${good.passed}/${good.total}  (${pct(good.passed, good.total)})`);

  // ---- 反向归因：坏客户端（预期失败，证明 bug 真实 + 归因到客户端编码）----
  const bad = await runWithClient(url, cases, {
    label: "latin1 broken client (反向归因)",
    postFn: (base, text) => brokenRoundTrip(base, text),
  });
  const badNonAscii = bad.results.filter((r) => r.tier !== "t0");
  const badFail = badNonAscii.filter((r) => !r.pass).length;
  console.log(`\n[2/2] 反向归因：${bad.label}`);
  console.log(`  非-ASCII 用例应全部失败 → 失败 ${badFail}/${badNonAscii.length}`);
  console.log(`  ${badFail === badNonAscii.length ? "✓ 符合预期：编码失效真实存在，且根因为客户端序列化" : "⚠ 与预期不符，需复核"}`);

  await close();

  // ---- 准入决策（Eq.7：严格提升 + 语义保持）----
  console.log("\n" + "=".repeat(64));
  const admitted = good.passed === good.total;
  if (admitted) {
    console.log("准入决策：ACCEPT v2（候选技能在全部 corpus 上严格通过，语义无损）");
    console.log(`结果: PASS (exit 0)`);
  } else {
    console.log(`准入决策：REJECT（仍有 ${good.total - good.passed} 条用例未通过，走归因→lesson→验证闭环）`);
    console.log(`结果: FAIL (exit 1)`);
  }
  console.log("=".repeat(64));

  process.exit(admitted ? 0 : 1);
}

main().catch((e) => {
  console.error("verify.mjs 运行异常:", e);
  process.exit(2);
});
