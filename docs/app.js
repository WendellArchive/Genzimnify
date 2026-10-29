const DOCS = [
  { title: "Genzimnify documentation", url: "index.html", section: "Overview", text: "runtime installation language reference" },
  { title: "Install Genzimnify", url: "installation.html", section: "Get started", text: "Homebrew macOS Windows PowerShell Ubuntu Kali Linux manual releases PATH" },
  { title: "First program", url: "getting-started.html", section: "Get started", text: "create run check project hello command line" },
  { title: "Language guide", url: "language-guide.html", section: "Language", text: "variables values operators control flow functions classes exceptions imports async types" },
  { title: "Native standard library", url: "stdlib.html", section: "Reference", text: "builtins collections math system luck clock timing files" },
  { title: "rizzgame", url: "rizzgame.html", section: "rizzgame", text: "native 2D game library slang pull_up show_off glow_up pygame camera particles animation graphics audio font image sprite" },
  { title: "rizzgame in Studio", url: "rizzgame-studio.html", section: "rizzgame", text: "browser IDE canvas preview tutorial keyboard mouse draw game loop limitations" },
  { title: "Packages and projects", url: "packages.html", section: "Tools", text: "gzim.toml dependencies Git local path add install remove package manager" },
  { title: "Python interoperability", url: "python-interop.html", section: "Interop", text: "optional Python libraries py numpy json keyword arguments native core" },
  { title: "Command-line tools", url: "cli.html", section: "Tools", text: "gzim run eval check repl init doctor convert source-map offline version update arguments exit code rizzgame" },
  { title: "Editor and language server", url: "tooling.html", section: "Tools", text: "LSP Zed diagnostics hover completion definition editor" },
  { title: "Changelog", url: "changelog.html", section: "Project", text: "release history versions changes added fixed removed 1.0 1.1 2.0" }
];

const groups = [
  ["Overview", [["Home", "index.html"]]],
  ["Get started", [["Installation", "installation.html"], ["First program", "getting-started.html"]]],
  ["Language", [["Language guide", "language-guide.html"], ["Standard library", "stdlib.html"]]],
  ["rizzgame", [["Overview & native API", "rizzgame.html"], ["Studio tutorial", "rizzgame-studio.html"]]],
  ["Tools", [["Command-line interface", "cli.html"], ["Packages & projects", "packages.html"], ["Editor & LSP", "tooling.html"]]],
  ["Interop", [["Python interoperability", "python-interop.html"]]],
  ["Project", [["Changelog", "changelog.html"], ["GitHub repository ↗", "https://github.com/Obliv1onis/Genzimnify"]]]
];

const page = location.pathname.split("/").pop() || "index.html";

function renderChrome() {
  document.getElementById("siteHeader").innerHTML = `
    <header class="topbar">
      <button class="mobile-menu" id="menuBtn" aria-label="Open navigation">☰</button>
      <a class="brand" href="index.html"><img class="brand-mark" src="favicon.svg" alt=""><span>GENZIMNIFY</span><span class="version">2.0.6</span></a>
      <nav class="toplinks"><a class="active" href="index.html">Docs</a><a href="https://github.com/Obliv1onis/Genzimnify">Source</a><a href="https://gzimide.obliv1onis.cloud">Online IDE</a></nav>
      <div class="top-actions">
        <div class="search-shell" id="searchShell">
          <span class="search-icon" aria-hidden="true">⌕</span>
          <input id="searchInput" type="search" placeholder="Search documentation" autocomplete="off" aria-label="Search documentation" aria-controls="searchResults" aria-expanded="false">
          <kbd>/</kbd>
          <div class="search-dropdown" id="searchResults" role="listbox" hidden></div>
        </div>
        <a class="github-link" href="https://github.com/Obliv1onis/Genzimnify">GitHub ↗</a>
      </div>
    </header>`;
  document.getElementById("siteSidebar").innerHTML = groups.map(([title, links]) => `
    <div class="nav-group"><div class="nav-title">${title}</div>${links.map(([label, url]) => `<a class="nav-link ${page === url ? "active" : ""}" href="${url}">${label}</a>`).join("")}</div>`).join("");
}

function highlightCode() {
  document.querySelectorAll("pre code.language-gzim").forEach((block) => {
    const escape = (value) => value.replace(/[&<>]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[char]);
    const source = block.textContent;
    const pattern = /(#[^\n]*|glow"(?:\\.|[^"\\])*"|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\b(?:for real|up in|send it|call up|throw shade|on timing|wait up|fit check|yap back|how many|same as|let|lock|be|vibecheck|otherwise|vibe|cook|yo|clique|pull up|outta|as|f_around|find_out|no_matter_what|both|either|aint)\b|\b(?:nocap|cap|ghost)\b|\b(?:yap|vibes|ranked|add up|round up)\b)/g;
    let html = "", last = 0;
    for (const match of source.matchAll(pattern)) {
      html += escape(source.slice(last, match.index));
      const raw = match[0];
      const cls = raw.startsWith("#") ? "tok-comment" : /^(?:glow)?["']/.test(raw) ? "tok-string" : /^(?:nocap|cap|ghost)$/.test(raw) ? "tok-value" : /^(?:yap|vibes|ranked|add up|round up)$/.test(raw) ? "tok-builtin" : "tok-keyword";
      html += `<span class="${cls}">${escape(raw)}</span>`;
      last = match.index + raw.length;
    }
    block.innerHTML = html + escape(source.slice(last));
  });
}

function addCopyButtons() {
  document.querySelectorAll("pre").forEach((pre) => {
    const button = document.createElement("button");
    button.className = "copy-button"; button.textContent = "Copy";
    button.addEventListener("click", async () => {
      await navigator.clipboard.writeText(pre.querySelector("code")?.textContent || pre.textContent);
      button.textContent = "Copied"; setTimeout(() => button.textContent = "Copy", 1200);
    });
    pre.appendChild(button);
  });
}

function setupToc() {
  const toc = document.getElementById("pageToc");
  if (!toc) return;
  const headings = [...document.querySelectorAll(
    document.querySelector("article.changelog") ? "article h2" : "article h2, article h3"
  )];
  const usedIds = new Set();
  toc.innerHTML = '<div class="toc-title">On this page</div>' + headings.map((heading) => {
    const base = heading.id || heading.textContent.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, "");
    let unique = base, suffix = 2;
    while (usedIds.has(unique)) unique = `${base}-${suffix++}`;
    heading.id = unique;
    usedIds.add(unique);
    return `<a href="#${heading.id}" style="padding-left:${heading.tagName === "H3" ? 10 : 0}px">${heading.textContent}</a>`;
  }).join("");
  const links = [...toc.querySelectorAll("a")];
  const observer = new IntersectionObserver((entries) => entries.forEach((entry) => {
    if (entry.isIntersecting) { links.forEach((link) => link.classList.toggle("active", link.hash === `#${entry.target.id}`)); }
  }), { rootMargin: "-15% 0px -75%" });
  headings.forEach((heading) => observer.observe(heading));
}

function setupSearch() {
  const shell = document.getElementById("searchShell");
  const input = document.getElementById("searchInput");
  const results = document.getElementById("searchResults");
  let selected = 0;
  const matches = () => {
    const query = input.value.trim().toLowerCase();
    return DOCS.filter((item) => !query || `${item.title} ${item.section} ${item.text}`.toLowerCase().includes(query));
  };
  const render = () => {
    const items = matches();
    selected = Math.min(selected, Math.max(items.length - 1, 0));
    results.innerHTML = items.length ? items.map((item, index) => `<a class="search-result ${index === selected ? "selected" : ""}" role="option" aria-selected="${index === selected}" href="${item.url}"><b>${item.title}</b><span>${item.section} · ${item.text}</span></a>`).join("") : '<div class="search-empty">No documentation found.</div>';
  };
  const open = () => { render(); results.hidden = false; input.setAttribute("aria-expanded", "true"); };
  const close = () => { results.hidden = true; input.setAttribute("aria-expanded", "false"); };
  const focus = () => { input.focus(); input.select(); open(); };
  input.addEventListener("focus", open);
  input.addEventListener("input", () => { selected = 0; open(); });
  input.addEventListener("keydown", (event) => {
    const links = [...results.querySelectorAll("a")];
    if (event.key === "Escape") { close(); input.blur(); }
    if (event.key === "ArrowDown" && links.length) { event.preventDefault(); selected = (selected + 1) % links.length; render(); }
    if (event.key === "ArrowUp" && links.length) { event.preventDefault(); selected = (selected - 1 + links.length) % links.length; render(); }
    if (event.key === "Enter" && links.length) { event.preventDefault(); links[selected]?.click(); }
  });
  document.addEventListener("pointerdown", (event) => { if (!shell.contains(event.target)) close(); });
  addEventListener("keydown", (event) => {
    const typing = event.target.matches?.("input, textarea, select, [contenteditable='true']");
    if (event.key === "/" && !typing && !event.metaKey && !event.ctrlKey && !event.altKey) { event.preventDefault(); focus(); }
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") { event.preventDefault(); focus(); }
  });
}

renderChrome();
document.getElementById("menuBtn").addEventListener("click", () => document.body.classList.toggle("nav-open"));
document.addEventListener("click", (event) => { if (document.body.classList.contains("nav-open") && !event.target.closest(".sidebar, #menuBtn")) document.body.classList.remove("nav-open"); });
highlightCode(); addCopyButtons(); setupToc(); setupSearch();
