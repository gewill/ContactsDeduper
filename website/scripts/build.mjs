import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { siteURL, siteUpdated, locales, copy } from "../src/site-data.mjs";
import { header, footer, languageLinks, markdownSections, markdownToHTML, escapeHTML } from "../src/site.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const website = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const dist = path.join(website, "dist");
fs.rmSync(dist, { recursive: true, force: true });
fs.mkdirSync(dist, { recursive: true });
for (const asset of ["styles.css", "favicon.svg", "_headers"]) {
  fs.copyFileSync(path.join(website, asset === "styles.css" ? "src" : "public", asset), path.join(dist, asset));
}

function pagePath(locale, page) {
  return page === "home" ? `/${locale.id}/` : `/${locale.id}/${page}/`;
}

function shell({ locale, page, title, description, content, rootPage = false }) {
  const labels = copy[locale.id];
  const currentPath = rootPage ? "/en/" : pagePath(locale, page);
  const alternates = rootPage
    ? `${locales.map((entry) => `<link rel="alternate" hreflang="${entry.locale}" href="${siteURL}${pagePath(entry, "home")}">`).join("\n    ")}\n    <link rel="alternate" hreflang="x-default" href="${siteURL}/en/">`
    : locales.map((entry) => `<link rel="alternate" hreflang="${entry.locale}" href="${siteURL}${pagePath(entry, page)}">`).join("\n    ");
  return `<!doctype html><html lang="${locale.locale}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="description" content="${escapeHTML(description)}"><meta name="theme-color" content="#080B11"><title>${escapeHTML(title)} · ContactsDeduper</title><link rel="canonical" href="${siteURL}${currentPath}">${alternates}<link rel="icon" href="/favicon.svg" type="image/svg+xml"><link rel="stylesheet" href="/styles.css"></head><body>${header({ locale, page, locales, labels })}<main>${content}</main>${footer({ locale, labels })}</body></html>`;
}

function languageRedirectScript() {
  return `<script>(() => { const language = (navigator.language || "").toLowerCase(); const target = language.startsWith("zh-tw") || language.startsWith("zh-hk") || language.startsWith("zh-mo") || language.includes("hant") ? "/zh-Hant/" : language.startsWith("zh") ? "/zh-Hans/" : language.startsWith("ja") ? "/ja/" : language.startsWith("ko") ? "/ko/" : language.startsWith("es") ? "/es/" : language.startsWith("fr") ? "/fr/" : language.startsWith("de") ? "/de/" : "/en/"; if (window.location.pathname === "/") window.location.replace(target); })();</script>`;
}

function chevron() {
  return `<svg viewBox="0 0 16 16" aria-hidden="true"><path d="m6 3 5 5-5 5" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
}

function appMockup(localeID = "en") {
  const supportURL = `/${localeID}/support/`;
  return `<div class="phone-frame" aria-label="ContactsDeduper app preview"><div class="phone-screen"><div class="mock-content"><div class="phone-notch"></div><div class="mock-status"><span>9:41</span><span>••• ◔ ▰</span></div><div class="mock-toolbar"><strong>ContactsDeduper</strong><span class="mock-icon">⚙</span></div><div class="mock-heading"><div><h2>Duplicate groups</h2><p>Review groups and merge the ones you want to keep.</p></div><a href="/en/support/">3 groups</a></div><div class="mock-group-list"><a class="mock-group" href="/en/support/"><span>John Appleseed<small>3 contacts</small></span>${chevron()}</a><a class="mock-group" href="/en/support/"><span>Jane Smith<small>2 contacts</small></span>${chevron()}</a><a class="mock-group" href="/en/support/"><span>David Johnson<small>2 contacts</small></span>${chevron()}</a></div><div class="mock-heading mock-heading-review"><div><h2>Review a group</h2><p>Choose the contact to keep.</p></div><a href="/en/support/">1 of 3</a></div><div class="mock-review"><div class="mock-review-title"><span class="mock-avatar">⌁</span><span>John Appleseed<small>3 possible matches</small></span></div><div class="mock-contact selected"><span class="radio"></span><span>John Appleseed<small>Appleseed Inc.<br>john@appleseed.com</small></span><b>Keep</b></div><div class="mock-contact"><span class="radio"></span><span>J. Appleseed<small>Appleseed Inc.<br>john.appleseed@icloud.com</small></span></div><div class="mock-contact"><span class="radio"></span><span>John Appleseed<small>Appleseed Inc.<br>john@mac.com</small></span></div><a class="mock-merge" href="/en/support/">Merge 3 Contacts</a></div><div class="mock-bottom-nav"><span class="active"><i>⌘</i>Duplicates</span><span><i>✓</i>Merged</span><span><i>⚙</i>Settings</span></div></div></div></div>`.replaceAll("/en/support/", supportURL);
}

function homeContent(locale, labels) {
  return `<section class="hero home-hero"><div><h1>${labels.title}</h1><p>${labels.intro}</p><div class="actions"><a class="button" href="/${locale.id}/support/">${labels.getSupport}</a><a class="text-link" href="/${locale.id}/privacy/">${labels.readPrivacy} <span aria-hidden="true">→</span></a></div></div>${appMockup(locale.id)}</section><section class="language-band"><div class="language-band-inner"><span>${labels.switchLanguage}</span><div class="language-grid">${languageLinks(locales, "home")}</div></div></section>`;
}

function supportPage(locale, labels) {
  const features = [["⌂", labels.whatItDoes, labels.whatItDoesText], ["⌕", labels.careful, labels.carefulText], ["♢", labels.backup, labels.backupText]];
  return `<section class="hero support-hero"><div><h1>${labels.title}</h1><p>${labels.intro}</p><div class="actions"><a class="button" href="https://github.com/gewill/ContactsDeduper/issues">${labels.getSupport}</a><a class="text-link" href="/${locale.id}/privacy/">${labels.readPrivacy} <span aria-hidden="true">→</span></a></div></div>${appMockup(locale.id)}</section><section class="feedback-callout"><div><strong>${labels.support}</strong><p>${labels.feedback}</p></div></section><section class="feature-band"><div class="features">${features.map(([icon, title, text]) => `<article class="feature"><div class="feature-icon" aria-hidden="true">${icon}</div><h2>${title}</h2><p>${text}</p></article>`).join("")}</div></section><section class="faq"><h2>${labels.questions}</h2>${labels.faq.map(([question, answer]) => `<details><summary>${question}</summary><p>${answer}</p></details>`).join("")}</section>`;
}

function privacyPage(locale, labels, privacy) {
  const sections = markdownSections(privacy);
  const toc = sections.map(({ id, title }) => `<a href="#${id}">${escapeHTML(title)}</a>`).join("");
  return `<div class="article-layout"><aside class="toc"><strong>${locale.id === "en" ? "On this page" : labels.questions}</strong>${toc}</aside><article class="article"><h1>${locale.id === "en" ? "Privacy policy" : escapeHTML(privacy.split("\n")[0].replace(/^# /, ""))}</h1><p class="article-intro">${locale.id === "en" ? "ContactsDeduper processes your contacts on your device." : labels.intro}</p><p class="updated">${labels.updated} · ${siteUpdated}</p><div class="callout"><strong>${locale.id === "en" ? "Local-first by design" : labels.careful}</strong><p>${locale.id === "en" ? "Your data stays on your device. We do not collect, store, or transmit your contacts." : labels.backupText}</p></div><div class="callout feedback-callout"><strong>${labels.support}</strong><p>${labels.feedback}</p></div><div class="privacy-content">${markdownToHTML(privacy)}</div></article></div>`;
}

function termsContent(locale, labels, terms) {
  return `<div class="article-layout"><aside class="toc"><strong>${labels.terms}</strong><a href="#license">${locale.id === "en" ? "Apple App Store terms" : "App Store"}</a><a href="#use">${locale.id === "en" ? "Acceptable use" : "Use"}</a><a href="#backup">${locale.id === "en" ? "Backups and contact data" : labels.backup}</a><a href="#warranty">${locale.id === "en" ? "Disclaimer" : "Disclaimer"}</a><a href="#liability">${locale.id === "en" ? "Limitation of liability" : "Liability"}</a><a href="#changes">${locale.id === "en" ? "Changes" : "Changes"}</a><a href="#contact">${locale.id === "en" ? "Contact" : labels.support}</a></aside><article class="article"><h1>${escapeHTML(terms.split("\n")[0].replace(/^# /, ""))}</h1><p class="article-intro">${labels.termsIntro}</p><p class="updated">${labels.updated} · ${siteUpdated}</p><div class="callout"><strong>${locale.id === "en" ? "Please review before use" : labels.terms}</strong><p>${labels.termsIntro}</p></div><div class="privacy-content">${markdownToHTML(terms, ["license", "use", "backup", "warranty", "liability", "changes", "contact"])}</div></article></div>`;
}

for (const locale of locales) {
  const labels = copy[locale.id];
  write(path.join(dist, locale.id, "index.html"), shell({ locale, page: "home", title: labels.home, description: labels.intro, content: homeContent(locale, labels) }));
  write(path.join(dist, locale.id, "support", "index.html"), shell({ locale, page: "support", title: labels.support, description: labels.intro, content: supportPage(locale, labels) }));
  const privacy = fs.readFileSync(path.join(root, locale.privacy), "utf8");
  write(path.join(dist, locale.id, "privacy", "index.html"), shell({ locale, page: "privacy", title: locale.id === "en" ? "Privacy policy" : "Privacy", description: labels.intro, content: privacyPage(locale, labels, privacy) }));
  const terms = fs.readFileSync(path.join(root, locale.terms), "utf8");
  write(path.join(dist, locale.id, "terms", "index.html"), shell({ locale, page: "terms", title: labels.terms, description: labels.termsIntro, content: termsContent(locale, labels, terms) }));
}

const defaultLabels = copy.en;
write(path.join(dist, "index.html"), shell({ locale: locales[0], page: "home", title: defaultLabels.home, description: defaultLabels.intro, content: `${homeContent(locales[0], defaultLabels)}${languageRedirectScript()}`, rootPage: true }));
write(path.join(dist, "404.html"), `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="description" content="The ContactsDeduper page you requested does not exist."><title>Page not found · ContactsDeduper</title><link rel="canonical" href="${siteURL}/404.html"><link rel="alternate" hreflang="x-default" href="${siteURL}/en/"><link rel="icon" href="/favicon.svg" type="image/svg+xml"><link rel="stylesheet" href="/styles.css"></head><body><main class="faq"><h1>Page not found</h1><p>The page you requested does not exist.</p><a class="button" href="/">Go home</a></main></body></html>`);

function write(file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
}
