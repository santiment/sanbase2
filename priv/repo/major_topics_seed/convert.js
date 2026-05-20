#!/usr/bin/env node
// Convert every data-*.ts in this directory to data-*.json.
// The .ts files are `export const NARRATIVES = { labels, datasets }` modules.
// They use single quotes and trailing commas, so JSON.parse can't handle them
// directly — we strip the `export const X = ` prefix and eval the rest as a JS
// object literal. The output JSON normalizes everything to standard form.

const fs = require("fs");
const path = require("path");

const dir = __dirname;
const files = fs
  .readdirSync(dir)
  .filter((f) => /^data-\d+\.ts$/.test(f))
  .sort((a, b) => fileNumber(a) - fileNumber(b));

function fileNumber(name) {
  return parseInt(name.match(/\d+/)[0], 10);
}

let written = 0;
let failed = 0;

for (const f of files) {
  const srcPath = path.join(dir, f);
  let src = fs.readFileSync(srcPath, "utf8");

  src = src.replace(/^\s*export\s+const\s+\w+\s*=\s*/, "");
  src = src.replace(/;\s*$/, "").trim();

  let obj;
  try {
    obj = (0, eval)("(" + src + ")");
  } catch (e) {
    console.error("[fail]", f, "—", e.message);
    failed++;
    continue;
  }

  if (!obj || !Array.isArray(obj.labels) || !Array.isArray(obj.datasets)) {
    console.error("[fail]", f, "— missing labels/datasets");
    failed++;
    continue;
  }

  const out = {
    labels: obj.labels,
    datasets: obj.datasets.map((d) => ({
      label: d.label,
      topics: d.topics,
      description: d.description,
      data: d.data,
    })),
  };

  const jsonName = f.replace(/\.ts$/, ".json");
  fs.writeFileSync(path.join(dir, jsonName), JSON.stringify(out));
  written++;
}

console.log(`Wrote ${written} JSON files, ${failed} failures.`);
