export function escapeHTML(value) {
  return value.replace(/[&<>'"]/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" }[character]));
}

export function markdownToHTML(markdown, ids = ["data", "local", "collect", "backup", "changes", "permissions", "contact"]) {
  const lines = markdown.replace(/^# .+\n\n?/m, "").replace(/^\[.*\n\n?/m, "").split("\n");
  const output = [];
  let sectionIndex = -1;
  let list = [];
  const flushList = () => {
    if (list.length) output.push(`<ul>${list.map((line) => `<li>${inline(line.slice(2))}</li>`).join("")}</ul>`);
    list = [];
  };
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) { flushList(); continue; }
    if (line.startsWith("## ")) {
      flushList();
      if (sectionIndex >= 0) output.push("</section>");
      sectionIndex += 1;
      output.push(`<section id="${ids[sectionIndex] ?? `section-${sectionIndex + 1}`}"><h2>${escapeHTML(line.slice(3))}</h2>`);
    } else if (line.startsWith("- ")) {
      list.push(line);
    } else {
      flushList();
      output.push(`<p>${inline(line)}</p>`);
    }
  }
  flushList();
  if (sectionIndex >= 0) output.push("</section>");
  return output.join("\n");
}

function inline(value) {
  return escapeHTML(value).replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>').replace(/`([^`]+)`/g, "<code>$1</code>");
}

export function languageLinks(locales, current, page) {
  return locales.map((locale) => `<a href="/${locale.id}/${page}/" hreflang="${locale.locale}" lang="${locale.locale}">${locale.label}</a>`).join("");
}

export function header({ locale, current, page, locales, labels }) {
  return `<header class="site-header"><nav class="nav" aria-label="Primary"><a class="brand" href="/${locale.id}/">ContactsDeduper</a><div class="nav-links"><a href="/${locale.id}/support/" ${page === "support" ? 'aria-current="page"' : ""}>${labels.support}</a><a href="/${locale.id}/privacy/" ${page === "privacy" ? 'aria-current="page"' : ""}>${labels.privacy}</a><a href="/${locale.id}/terms/" ${page === "terms" ? 'aria-current="page"' : ""}>${labels.terms}</a><details class="language"><summary>${locale.label}</summary><div class="language-menu">${languageLinks(locales, current, page)}</div></details></div><details class="language menu-toggle"><summary aria-label="${labels.switchLanguage}">☰</summary><div class="language-menu"><a href="/${locale.id}/support/">${labels.support}</a><a href="/${locale.id}/privacy/">${labels.privacy}</a><a href="/${locale.id}/terms/">${labels.terms}</a>${languageLinks(locales, current, page)}</div></details></nav></header>`;
}

export function footer({ locale, labels }) {
  return `<footer class="site-footer"><div class="footer-inner"><span>© 2026 ContactsDeduper</span><div class="footer-links"><a href="/${locale.id}/support/">${labels.support}</a><a href="/${locale.id}/privacy/">${labels.privacy}</a><a href="/${locale.id}/terms/">${labels.terms}</a><a href="https://github.com/gewill/ContactsDeduper">${labels.github}</a></div></div></footer>`;
}
