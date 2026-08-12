import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { locales } from "../src/site-data.mjs";

const dist = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../dist");
if (!fs.existsSync(dist)) throw new Error("Run npm run build first");
const required = ["styles.css", "favicon.svg", "_headers", "index.html", "404.html"];
for (const file of required) if (!fs.existsSync(path.join(dist, file))) throw new Error(`Missing ${file}`);
const pages = ["support", "privacy", "terms"];
for (const locale of locales) for (const page of pages) {
  const file = path.join(dist, locale.id, page, "index.html");
  if (!fs.existsSync(file)) throw new Error(`Missing ${locale.id}/${page}`);
  const html = fs.readFileSync(file, "utf8");
  for (const marker of [`lang="${locale.locale}"`, `hreflang="${locale.locale}"`, "canonical", "styles.css"]) {
    if (!html.includes(marker)) throw new Error(`${locale.id}/${page} missing ${marker}`);
  }
  for (const target of html.matchAll(/href="(\/[^"#]+\/?)"/g)) {
    const targetFile = /\.[a-z0-9]+$/.test(target[1])
      ? path.join(dist, target[1].replace(/^\//, ""))
      : path.join(dist, target[1].replace(/^\//, ""), "index.html");
    if (!fs.existsSync(targetFile)) throw new Error(`${locale.id}/${page} links to missing ${target[1]}`);
  }
  for (const fragment of html.matchAll(/href="#([^"]+)"/g)) {
    if (!html.includes(`id="${fragment[1]}"`)) throw new Error(`${locale.id}/${page} links to missing #${fragment[1]}`);
  }
}
console.log(`Checked ${locales.length * pages.length} localized pages and ${required.length} root assets.`);
