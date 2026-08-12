import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { locales } from "../src/site-data.mjs";

const dist = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../dist");
if (!fs.existsSync(dist)) throw new Error("Run npm run build first");
const required = ["styles.css", "favicon.svg", "_headers", "index.html", "404.html"];
for (const file of required) if (!fs.existsSync(path.join(dist, file))) throw new Error(`Missing ${file}`);
const notFoundHTML = fs.readFileSync(path.join(dist, "404.html"), "utf8");
for (const marker of ['lang="en"', "description", "canonical", 'hreflang="x-default"']) {
  if (!notFoundHTML.includes(marker)) throw new Error(`404 missing ${marker}`);
}
const pages = ["support", "privacy", "terms"];
const rootHTML = fs.readFileSync(path.join(dist, "index.html"), "utf8");
for (const marker of ['canonical" href="https://contactsdeduper.gewill.org/en/', 'hreflang="x-default"', 'navigator.language', '"/en/"']) {
  if (!rootHTML.includes(marker)) throw new Error(`Root homepage missing ${marker}`);
}
if (!rootHTML.includes('window.location.replace(target)')) throw new Error("Root homepage missing language fallback");
for (const locale of locales) {
  const homeFile = path.join(dist, locale.id, "index.html");
  if (!fs.existsSync(homeFile)) throw new Error(`Missing ${locale.id}/ homepage`);
  const homeHTML = fs.readFileSync(homeFile, "utf8");
  for (const marker of [`lang="${locale.locale}"`, "canonical", "styles.css"]) {
    if (!homeHTML.includes(marker)) throw new Error(`${locale.id}/ missing ${marker}`);
  }
  if (homeHTML.includes('http-equiv="refresh"')) throw new Error(`${locale.id}/ homepage must not redirect`);
}
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
console.log(`Checked ${locales.length * (pages.length + 1)} localized pages and ${required.length} root assets.`);
