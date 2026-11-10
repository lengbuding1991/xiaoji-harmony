#!/usr/bin/env node
/**
 * 把本地提交推到 GitHub —— 走 api.github.com 的 Git Data API。
 *
 * 为什么不用 `git push`：
 *   这台机器到 github.com:443 的 TLS 握手会被中断（TCP 通、握手被掐），
 *   `git push` / `git ls-remote` 会一直挂着直到超时。
 *   但 api.github.com 是通的，所以用 REST API 手工建 blob → tree → commit → 更新分支引用。
 *
 * 用法：
 *   node scripts/push-to-github.mjs                 # 推 main，默认仓库见下
 *   node scripts/push-to-github.mjs --dry           # 只打印要推什么
 *
 * 注意：Git Data API 的 base_tree 只叠加不删除，本地删掉/挪走的文件必须显式用
 * sha:null 删掉，否则远端会一直留着（曾经因此让 app/ 下出现新旧两份同名路由，
 * 服务器构建直接失败）。脚本每次会对比远端完整文件树，自动补删除条目。
 *
 * token 来源（按顺序）：
 *   $GH_TOKEN  →  ~/.dsh/workbench-token  →  ~/.dsh/deng-stock-token
 * 文件内容只放 token 本身，chmod 600。
 */

import { execSync, execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const REPO = process.env.GH_REPO ?? "lengbuding1991/personal-workbench";
const BRANCH = process.env.GH_BRANCH ?? "main";
const API = "https://api.github.com";
const DRY = process.argv.includes("--dry");
// fresh：远端已经有自动生成的初始提交、但和本地历史毫无关系时，
// 把本地 HEAD 做成一个「没有父提交」的根提交，强制覆盖远端分支。
const FRESH = process.argv.includes("--fresh");
const CONCURRENCY = 3; // api.github.com 并发高了会被掐连接

function readToken() {
  const candidates = [
    process.env.GH_TOKEN,
    path.join(os.homedir(), ".dsh", "workbench-token"),
    path.join(os.homedir(), ".dsh", "deng-stock-token"),
  ];
  for (const c of candidates) {
    if (!c) continue;
    try {
      const t = fs.readFileSync(c, "utf8").trim();
      if (t) return t;
    } catch {
      /* 下一个 */
    }
  }
  return "";
}

const TOKEN = readToken();
if (!TOKEN) {
  console.error("没有 token。写进 ~/.dsh/workbench-token（chmod 600），或用 GH_TOKEN=... 传进来。");
  process.exit(1);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** api.github.com 偶发掐长连接，失败退避重试 */
async function gh(pathname, init = {}, tries = 6) {
  for (let i = 0; i < tries; i++) {
    try {
      const res = await fetch(`${API}${pathname}`, {
        ...init,
        headers: {
          Authorization: `Bearer ${TOKEN}`,
          Accept: "application/vnd.github+json",
          "Content-Type": "application/json",
          "User-Agent": "workbench-push",
          ...(init.headers ?? {}),
        },
      });
      const text = await res.text();
      if (!res.ok) throw new Error(`${init.method ?? "GET"} ${pathname} → ${res.status} ${text.slice(0, 300)}`);
      return text ? JSON.parse(text) : null;
    } catch (e) {
      const msg = String(e?.message ?? e);
      const retriable = /UND_ERR_SOCKET|other side closed|ECONNRESET|fetch failed|502|503|504|timeout/i.test(msg);
      if (!retriable || i === tries - 1) throw e;
      console.log(`  重试 ${i + 1}/${tries - 1}（${msg.slice(0, 60)}）`);
      await sleep(800 * (i + 1));
    }
  }
}

const root = execSync("git rev-parse --show-toplevel").toString().trim();
const git = (cmd) => execSync(cmd, { cwd: root, maxBuffer: 64 * 1024 * 1024 }).toString();

/* 远端已有哪个提交？本地从它之后开始补 */
let remoteHead = null;
try {
  const ref = await gh(`/repos/${REPO}/git/ref/heads/${BRANCH}`);
  remoteHead = ref.object.sha;
} catch (e) {
  const msg = String(e.message);
  // 404 = 分支不存在；409 "Git Repository is empty." = 仓库刚建、还没有任何提交
  if (!/→ 404/.test(msg) && !/→ 409/.test(msg)) throw e;
}
if (FRESH) {
  // fresh 模式：忽略远端已有历史（tree 不带 base_tree、commit 不带 parents），
  // 把本地 HEAD 做成一个根提交，最后强制改写远端分支
  remoteHead = null;
  console.log("fresh 模式：把本地 HEAD 做成一个根提交，强制覆盖远端分支");
}

/**
 * 用 API 推上去的提交，sha 跟本地不一样（作者/时间戳都要重新拼）。
 * 所以本地记一份「远端 sha ↔ 本地 sha」对照，下次才知道从哪儿接着推。
 */
const MAP_FILE = path.join(root, ".git", "github-pushed.json");
function readMap() {
  try {
    return JSON.parse(fs.readFileSync(MAP_FILE, "utf8"));
  } catch {
    return {};
  }
}
function writeMap(m) {
  fs.writeFileSync(MAP_FILE, JSON.stringify(m, null, 2));
}
const syncMap = readMap();

const allCommits = git("git rev-list --reverse HEAD").trim().split("\n");
/** 远端 head 对应本地哪个提交：本地直接有就用，否则查对照表 */
function localIndexOf(remoteSha) {
  if (!remoteSha) return -1;
  const direct = allCommits.indexOf(remoteSha);
  if (direct >= 0) return direct;
  const mapped = syncMap[remoteSha];
  return mapped ? allCommits.indexOf(mapped) : -1;
}

let startIdx = remoteHead ? localIndexOf(remoteHead) + 1 : 0;
if (remoteHead && startIdx === 0) {
  console.error(
    `远端 head ${remoteHead.slice(0, 7)} 在本地找不到，也没有对照记录。\n` +
      `如果确认远端内容就等于本地某个提交，用 --base=<本地sha> 指定，然后重跑。`,
  );
  const forced = process.argv.find((a) => a.startsWith("--base="));
  if (!forced) process.exit(2);
  const base = forced.split("=")[1];
  const idx = allCommits.indexOf(base);
  if (idx < 0) {
    console.error(`--base=${base} 不是本地提交。`);
    process.exit(2);
  }
  startIdx = idx + 1;
}
let todo = allCommits.slice(startIdx);
if (FRESH) {
  todo = [allCommits[allCommits.length - 1]];
}
console.log(`${REPO}#${BRANCH}：远端 ${remoteHead?.slice(0, 7) ?? "空"}，待推 ${todo.length} 个提交`);
if (todo.length === 0) {
  console.log("已经是最新的。");
  process.exit(0);
}
if (DRY) {
  for (const c of todo) console.log("  ", c.slice(0, 7), git(`git log -1 --pretty=%s ${c}`).trim());
  process.exit(0);
}

/** 取某个提交里某文件的原始字节 */
function fileAt(commit, rel) {
  // 用参数数组而不是拼字符串：路径里可能有 () 等 shell 元字符（如 app/(app)/page.tsx）
  return execFileSync("git", ["cat-file", "blob", `${commit}:${rel}`], {
    cwd: root,
    maxBuffer: 64 * 1024 * 1024,
  });
}

let parentSha = remoteHead;
let parentTree = null;
let remoteFiles = null; // 远端当前分支上的全部文件，用来算出「本地删掉了哪些」
if (remoteHead) {
  const c = await gh(`/repos/${REPO}/git/commits/${remoteHead}`);
  parentTree = c.tree.sha;
  const t = await gh(`/repos/${REPO}/git/trees/${parentTree}?recursive=1`);
  remoteFiles = (t.tree ?? []).filter((n) => n.type === "blob").map((n) => n.path);
}
/* 远端 sha 跟本地不等，diff 要用本地那个对应提交 */
let parentLocal = startIdx > 0 ? allCommits[startIdx - 1] : null;

for (const commit of todo) {
  const files = git(`git ls-tree -r -z --name-only ${commit}`).split("\0").filter(Boolean);
  const fileSet = new Set(files);

  let changed = files;
  if (parentLocal) {
    // --diff-filter=AM：只要「新增」和「修改」。
    // 被删掉的文件不能进这份清单——git cat-file 取不到它的内容会直接抛错；
    // 而且服务器那边是 tar 覆盖更新，本来也不会删文件，两边行为保持一致。
    const changedRaw = execFileSync("git", ["diff", "--name-only", "--diff-filter=AM", "-z", parentLocal, commit], {
      cwd: root,
      maxBuffer: 64 * 1024 * 1024,
    })
      .toString()
      .split("\0")
      .filter(Boolean);
    changed = changedRaw;
  }
  console.log(`${commit.slice(0, 7)}：${files.length} 个文件，变更 ${changed.length}`);

  const entries = [];
  let cursor = 0;
  async function worker() {
    while (cursor < changed.length) {
      const rel = changed[cursor++];
      const buf = fileAt(commit, rel);
      const blob = await gh(`/repos/${REPO}/git/blobs`, {
        method: "POST",
        body: JSON.stringify({ content: buf.toString("base64"), encoding: "base64" }),
      });
      entries.push({ path: rel, mode: "100644", type: "blob", sha: blob.sha });
    }
  }
  await Promise.all(Array.from({ length: CONCURRENCY }, worker));

  // base_tree 只会「叠加」，不会「删除」：本地删掉/挪走的文件在远端会一直留着。
  // 之前 git mv 到 app/(app)/ 之后，远端就同时存在 app/calendar 和 app/(app)/calendar，
  // 构建直接报 “two parallel pages that resolve to the same path”。
  // GitHub 的 Trees API 支持用 sha:null 删除条目，这里把「远端有、本地没有」的路径全删掉。
  const gone = [...(remoteFiles ?? [])].filter((p) => !fileSet.has(p));
  if (gone.length) {
    for (const p of gone) entries.push({ path: p, mode: "100644", type: "blob", sha: null });
    console.log(`  删除远端多余文件 ${gone.length} 个`);
  }

  const tree = await gh(`/repos/${REPO}/git/trees`, {
    method: "POST",
    body: JSON.stringify(parentTree ? { base_tree: parentTree, tree: entries } : { tree: entries }),
  });

  const message = execSync(`git log -1 --pretty=%B ${commit}`, { cwd: root }).toString().trim();
  const created = await gh(`/repos/${REPO}/git/commits`, {
    method: "POST",
    body: JSON.stringify({
      message,
      tree: tree.sha,
      ...(parentSha ? { parents: [parentSha] } : {}),
    }),
  });

  parentSha = created.sha;
  parentTree = tree.sha;
  parentLocal = commit;
  syncMap[created.sha] = commit;
  writeMap(syncMap);
  console.log(`  → ${created.sha.slice(0, 7)}`);
}

try {
  // 分支已存在 → PATCH 强制改写
  await gh(`/repos/${REPO}/git/refs/heads/${BRANCH}`, {
    method: "PATCH",
    body: JSON.stringify({ sha: parentSha, force: true }),
  });
} catch (e) {
  if (!/→ 404/.test(String(e.message))) throw e;
  // 分支还不存在 → POST 新建
  await gh(`/repos/${REPO}/git/refs`, {
    method: "POST",
    body: JSON.stringify({ ref: `refs/heads/${BRANCH}`, sha: parentSha }),
  });
}

console.log(`完成 → https://github.com/${REPO}/tree/${BRANCH}`);
