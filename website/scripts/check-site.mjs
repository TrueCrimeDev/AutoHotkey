import { readFile, readdir, access } from "node:fs/promises";
import { resolve, join, dirname, extname, relative } from "node:path";
import assert from "node:assert/strict";

const root = resolve(".vitepress/dist");
const base = "/AutoHotkey/";
const files = [];
async function walk(path) {
  for (const item of await readdir(path, { withFileTypes: true })) {
    const full = join(path, item.name);
    if (item.isDirectory()) await walk(full);
    else files.push(full);
  }
}
await walk(root);
const htmlFiles = files.filter((f) => f.endsWith(".html"));
assert(
  htmlFiles.length >= 28,
  `Expected a complete docs build; found ${htmlFiles.length} HTML pages`,
);
const failures = [];
let localLinks = 0;
const decode = (s) =>
  s.replaceAll("&amp;", "&").replaceAll("&#39;", "'").replaceAll("&quot;", '"');
for (const file of files.filter((f) =>
  /\.(html|js|json|css|xml|txt|ahk|svg)$/i.test(f),
)) {
  const body = await readFile(file, "utf8");
  if (
    /\b[A-Z]:\\+(?:Users|Documents and Settings)\\+|\/mnt\/[a-z]\/Users\/|\/home\/[a-z0-9_.-]+\//i.test(
      body,
    )
  ) {
    failures.push(`Personal filesystem path in ${relative(root, file)}`);
  }
}
for (const file of htmlFiles) {
  const html = await readFile(file, "utf8");
  for (const match of html.matchAll(/\b(href|src)="([^"]+)"/g)) {
    const raw = decode(match[2]);
    if (
      /^(?:https?:|mailto:|tel:|data:|\/\/)/i.test(raw) ||
      !raw ||
      raw.startsWith("#")
    )
      continue;
    const url = new URL(
      raw,
      `https://docs.invalid${base}${relative(root, file).replaceAll("\\", "/")}`,
    );
    if (!url.pathname.startsWith(base)) {
      failures.push(`Incorrect base path: ${raw} in ${relative(root, file)}`);
      continue;
    }
    let target = resolve(
      root,
      decodeURIComponent(url.pathname.slice(base.length)),
    );
    if (!target.startsWith(root)) {
      failures.push(`Escaping link: ${raw}`);
      continue;
    }
    if (url.pathname.endsWith("/")) target = join(target, "index.html");
    else if (!extname(target)) target += ".html";
    try {
      await access(target);
      localLinks++;
    } catch {
      failures.push(`Missing ${raw} from ${relative(root, file)}`);
      continue;
    }
    if (url.hash && target.endsWith(".html")) {
      const destination =
        target === file ? html : await readFile(target, "utf8");
      const id = decodeURIComponent(url.hash.slice(1));
      if (!destination.includes(`id="${id}"`))
        failures.push(`Missing anchor ${raw} from ${relative(root, file)}`);
    }
  }
}
for (const path of [
  "index.html",
  "guide/quick-start.html",
  "guide/ai-feedback.html",
  "examples/error-demo.ahk",
  "examples/error-demo-fixed.ahk",
  "examples/ai-error-feedback.json",
  "console/overview.html",
  "clautohotkey/harness.html",
  "clautohotkey/mcp.html",
  "showcase.html",
  "sitemap.xml",
  "images/features.png",
  "images/harness.png",
  "downloads/ClautoHotkey-screenshots.zip",
]) {
  try {
    await access(join(root, path));
  } catch {
    failures.push(`Required artifact missing: ${path}`);
  }
}
assert.equal(failures.length, 0, [...new Set(failures)].join("\n"));
console.log(
  `PASS: ${htmlFiles.length} pages, ${localLinks} internal link/asset references; required artifacts and personal-path scan passed.`,
);
