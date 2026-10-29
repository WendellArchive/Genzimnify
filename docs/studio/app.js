/* Genzimnify Studio v2.0.6 - static, local-first browser IDE. */
const lines = (...items) => items.join("\n") + "\n";
const EXAMPLES = {
  "hello-vibes.gzim": lines("# welcome to Genzimnify", "let name be \"chat\"", "let energy be 100", "", "vibecheck energy > 90:", "    yap(glow\"yo {name}, the vibes are immaculate\")", "otherwise:", "    yap(\"we can work with this\")"),
  "fizzbuzz.gzim": lines("# ngl the classic", "for real i up in vibes(1, 16):", "    vibecheck i % 15 == 0:", "        yap(\"FizzBuzz\")", "    or i % 3 == 0:", "        yap(\"Fizz\")", "    or i % 5 == 0:", "        yap(\"Buzz\")", "    otherwise:", "        yap(i)"),
  "functions.gzim": lines("cook greet(name, greeting be \"yo\"):", "    send it glow\"{greeting} {name}!\"", "", "cook fib(n):", "    vibecheck n < 2:", "        send it n", "    send it call up fib(n - 1) yo + call up fib(n - 2) yo", "", "let double be mini vibe(x): x * 2", "yap(call up greet(\"chat\") yo)", "yap(call up double(21) yo)", "yap(call up fib(10) yo)"),
  "classes.gzim": lines("clique Dog:", "    cook new(fam, name):", "        fam.name be name", "", "    cook speak(fam):", "        yap(glow\"{fam.name} says woof\")", "", "clique Puppy(Dog):", "    cook speak(fam):", "        yap(\"tiny woof\")", "", "let pup be call up Puppy(\"Bit\") yo", "call up pup.speak() yo"),
  "collections.gzim": lines("let evens be [x for real x up in vibes(10) sus x % 2 == 0]", "let scores be {\"amy\": 9, \"bob\": 7}", "let tags be {\"code\", \"vibes\", \"code\"}", "", "yap(evens)", "yap(scores[\"amy\"])", "yap(call up ranked(tags) yo)", "yap(call up add up([1, 2, 3]) yo)"),
  "exceptions.gzim": lines("f_around:", "    let answer be 1 / 0", "find_out SplitByZero as err:", "    yap(\"can't divide by zero, bestie\")", "no_matter_what:", "    yap(\"we move\")"),
  "async.gzim": lines("pull up timing", "", "on timing cook main():", "    yap(\"loading the vibes...\")", "    wait up timing.sleep(0.2)", "    yap(\"async vibes delivered\")", "", "call up timing.run(main()) yo"),
  "utilities.gzim": lines("# v2.0.6 utilities", "pull up clock", "pull up luck", "pull up math", "let started be clock.monotonic()", "clock.sleep(0.01)", "yap(clock.monotonic() - started)", "let cards be [1, 2, 3, 4, 5]", "luck.shuffle(cards)", "yap(luck.sample(cards, 2))", "yap(math.isfinite(3.14))", "yap(3 ** 34)"),
  "fit-check.gzim": lines("for real value up in [1, 2, 99]:", "    fit check value:", "        fit 1:", "            yap(\"one\")", "        fit 2:", "            yap(\"two\")", "        otherwise:", "            yap(\"mystery vibe\")"),
  "rizzgame-starter.gzim": lines("pull up rizzgame as rg", "", "let screen be call up rg.display.pull_up([640, 360]) yo", "call up rg.display.set_caption(\"Rizzgame Studio\") yo", "let clock be call up rg.time.Clock() yo", "let player be call up rg.Rect(300, 160, 36, 36) yo", "let running be nocap", "vibe running:", "    let dt be call up clock.keep_up(60) yo / 1000", "    for real event up in call up rg.event.catch_vibes() yo:", "        vibecheck event.type == rg.KEYDOWN both event.key == rg.K_ESCAPE:", "            running be cap", "    let keys be call up rg.key.check_the_vibe() yo", "    vibecheck keys[rg.K_LEFT] either keys[rg.K_a]: player.x be player.x - 220 * dt", "    vibecheck keys[rg.K_RIGHT] either keys[rg.K_d]: player.x be player.x + 220 * dt", "    vibecheck keys[rg.K_UP] either keys[rg.K_w]: player.y be player.y - 220 * dt", "    vibecheck keys[rg.K_DOWN] either keys[rg.K_s]: player.y be player.y + 220 * dt", "    call up screen.glow_up([14, 19, 32]) yo", "    call up rg.draw.flex_circle(screen, [60, 100, 130], [320, 180], 100) yo", "    call up rg.draw.flex_rect(screen, [103, 245, 201], player, 0) yo", "    call up rg.draw.yap_text(screen, \"WASD / ARROWS TO MOVE · ESC TO STOP\", [18, 18], 18, [235, 242, 255]) yo", "    call up rg.display.show_off() yo", "call up rg.dip_out() yo")
};
const REFERENCE = [
  ["let x be 1", "declare"], ["lock PI be 3.14", "constant"], ["nocap / cap", "True / False"],
  ["ghost", "None"], ["yap(...)", "print"], ["yap back(...)", "input"], ["call up fn() yo", "call"],
  ["how many(x)", "len"], ["vibecheck / or", "if / elif"], ["otherwise", "else"],
  ["vibe condition", "while"], ["for real x up in y", "for x in y"], ["cook fn():", "def"],
  ["send it", "return"], ["clique Name:", "class"], ["fam / ancestor", "self / super"],
  ["both / either / aint", "and / or / not"], ["same as / nah", "== / !="],
  ["f_around / find_out", "try / except"], ["throw shade", "raise"],
  ["on timing / wait up", "async / await"], ["fit check / fit", "match / case"]
];

const $ = (id) => document.getElementById(id);
const editor = $("editor");
const highlight = $("highlight");
const lineNumbers = $("lineNumbers");
const output = $("output");
const pythonOutput = $("pythonOutput");
const status = $("status");
const runBtn = $("runBtn");
const workbench = document.querySelector(".workbench");
let fileName = "main.gzim";
let savedValue = "";
let diagnostics = [];
let diagTimer = 0;
let toastTimer = 0;
let pyodide = null;
let pyodideLoading = null;
let rizzgameReady = false;
let gameRunning = false;
let programRunning = false;
let stopRequested = false;
let outputSize = 0;
let outputLimited = false;
const OUTPUT_LIMIT = 100000;
const runner = new StudioRunner((text, kind) => write(text, kind), (text) => { status.textContent = text; });
const preview = new RizzgamePreview($("gameCanvas"), $("previewStage"), $("previewState"));
window.rizzgameBridge = preview;
let findMatches = [];
let findIndex = -1;
let completionItems = [];
let completionIndex = 0;
let completionContext = null;
let suppressCompletionOnce = false;

function escapeHtml(value) {
  return value.replace(/[&<>]/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[ch]);
}
const KEYWORDS = new Set(["let", "lock", "be", "vibecheck", "or", "otherwise", "vibe", "for real", "up in", "dip", "next", "deadass", "cook", "send it", "drop", "call up", "yo", "clique", "new", "fam", "ancestor", "pull up", "outta", "as", "gives", "sus", "f_around", "find_out", "no_matter_what", "throw shade", "roll with", "on timing", "wait up", "mini vibe", "worldwide", "localish", "cancel", "on god", "fit check", "fit", "both", "either", "aint", "same as", "nah", "literally", "fr"]);
const BUILTINS = new Set(["yap", "yap back", "how many", "add up", "round up", "index up", "vibes", "ranked", "unlock", "link"]);
const BOOLEANS = new Set(["nocap", "cap", "ghost"]);
const COMPLETION_ITEMS = [
  { label: "yap", insert: "yap()", cursor: 4, kind: "builtin", detail: "Print values; glue and micdrop set separator/ending" },
  { label: "yap back", insert: "yap back()", cursor: 9, kind: "builtin", detail: "Read user input" },
  { label: "how many", insert: "how many()", cursor: 9, kind: "builtin", detail: "Get a value's length" },
  { label: "add up", insert: "add up()", cursor: 7, kind: "builtin", detail: "Sum an iterable" },
  { label: "round up", insert: "round up()", cursor: 9, kind: "builtin", detail: "Round a number" },
  { label: "index up", insert: "index up()", cursor: 9, kind: "builtin", detail: "Enumerate values" },
  { label: "vibes", insert: "vibes()", cursor: 6, kind: "builtin", detail: "Create a range" },
  { label: "ranked", insert: "ranked()", cursor: 7, kind: "builtin", detail: "Sort an iterable; uno_reverse=nocap for descending" },
  { label: "unlock", insert: "unlock()", cursor: 7, kind: "builtin", detail: "Open a file" },
  { label: "link", insert: "link()", cursor: 5, kind: "builtin", detail: "Zip iterables" },
  { label: "let", insert: "let ", kind: "keyword", detail: "Declare a variable" },
  { label: "lock", insert: "lock ", kind: "keyword", detail: "Declare a constant" },
  { label: "vibecheck", insert: "vibecheck :", cursor: 10, kind: "keyword", detail: "Conditional branch" },
  { label: "otherwise", insert: "otherwise:", kind: "keyword", detail: "Fallback branch" },
  { label: "for real", insert: "for real  up in :", cursor: 9, kind: "keyword", detail: "Loop over values" },
  { label: "vibe", insert: "vibe :", cursor: 5, kind: "keyword", detail: "While loop" },
  { label: "cook", insert: "cook ():", cursor: 5, kind: "keyword", detail: "Define a function" },
  { label: "send it", insert: "send it ", kind: "keyword", detail: "Return a value" },
  { label: "call up", insert: "call up  yo", cursor: 8, kind: "keyword", detail: "Call a function" },
  { label: "clique", insert: "clique :", cursor: 7, kind: "keyword", detail: "Define a class" },
  { label: "pull up", insert: "pull up ", kind: "keyword", detail: "Import a module" },
  { label: "f_around", insert: "f_around:", kind: "keyword", detail: "Try a block" },
  { label: "find_out", insert: "find_out :", cursor: 9, kind: "keyword", detail: "Catch an exception" },
  { label: "no_matter_what", insert: "no_matter_what:", kind: "keyword", detail: "Always run a block" },
  { label: "throw shade", insert: "throw shade ", kind: "keyword", detail: "Raise an exception" },
  { label: "on timing", insert: "on timing ", kind: "keyword", detail: "Define async code" },
  { label: "wait up", insert: "wait up ", kind: "keyword", detail: "Await a result" },
  { label: "fit check", insert: "fit check :", cursor: 10, kind: "keyword", detail: "Pattern matching" },
  { label: "fit", insert: "fit :", cursor: 4, kind: "keyword", detail: "Match a case" },
  { label: "nocap", kind: "value", detail: "True" },
  { label: "cap", kind: "value", detail: "False" },
  { label: "ghost", kind: "value", detail: "None" },
  { label: "both", insert: "both ", kind: "operator", detail: "Logical and" },
  { label: "either", insert: "either ", kind: "operator", detail: "Logical or" },
  { label: "aint", insert: "aint ", kind: "operator", detail: "Logical not" },
  { label: "same as", insert: "same as ", kind: "operator", detail: "Equality comparison" },
  { label: "nah", insert: "nah ", kind: "operator", detail: "Inequality comparison" }
];
const tokenPattern = /(#\[\[[\s\S]*?\]\]#|#[^\n]*|"""[\s\S]*?"""|'''[\s\S]*?'''|glow"(?:\\.|[^"\\])*"|glow'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\b(?:for real|up in|send it|call up|throw shade|roll with|on timing|wait up|mini vibe|fit check|yap back|how many|add up|round up|index up|same as|no_matter_what)\b|\b\d+(?:\.\d+)?(?:e[+-]?\d+)?\b|\b[A-Za-z_][A-Za-z0-9_]*\b)/gi;

const completionPopup = document.createElement("div");
completionPopup.id = "completionPopup";
completionPopup.className = "completion-popup";
completionPopup.hidden = true;
completionPopup.setAttribute("role", "listbox");
completionPopup.setAttribute("aria-label", "Code suggestions");
completionPopup.innerHTML = '<div class="completion-list"></div><div class="completion-help"><span><kbd>Tab</kbd>/<kbd>Shift Tab</kbd> navigate</span><span><kbd>Enter</kbd> insert · <kbd>Esc</kbd> close</span></div>';
$("codeScroll").appendChild(completionPopup);
editor.setAttribute("aria-controls", "completionPopup");
editor.setAttribute("aria-autocomplete", "list");
const completionList = completionPopup.querySelector(".completion-list");
const completionCanvas = document.createElement("canvas");
const completionMeasure = completionCanvas.getContext("2d");

function syntaxHighlight(source) {
  let result = "";
  let last = 0;
  for (const match of source.matchAll(tokenPattern)) {
    result += escapeHtml(source.slice(last, match.index));
    const raw = match[0];
    const lower = raw.toLowerCase();
    let cls = "";
    if (raw.startsWith("#")) cls = "tok-comment";
    else if (/^(?:glow)?["']/.test(raw)) cls = "tok-string";
    else if (/^\d/.test(raw)) cls = "tok-number";
    else if (BOOLEANS.has(lower)) cls = "tok-bool";
    else if (BUILTINS.has(lower)) cls = "tok-builtin";
    else if (KEYWORDS.has(lower)) cls = "tok-keyword";
    result += cls ? "<span class=\"" + cls + "\">" + escapeHtml(raw) + "</span>" : escapeHtml(raw);
    last = match.index + raw.length;
  }
  result += escapeHtml(source.slice(last));
  return result + (source.endsWith("\n") ? " " : "");
}
function renderEditor() {
  const count = Math.max(1, editor.value.split("\n").length);
  lineNumbers.textContent = Array.from({ length: count }, (_, i) => i + 1).join("\n");
  highlight.innerHTML = syntaxHighlight(editor.value);
  syncScroll();
  updateCursor();
  const dirty = editor.value !== savedValue;
  $("dirtyDot").classList.toggle("visible", dirty);
  $("tabDirty").classList.toggle("visible", dirty);
  document.title = (dirty ? "● " : "") + fileName + " — Genzimnify Studio";
}
function safeCompile(source = editor.value) {
  try {
    if (typeof compileGzim !== "function") throw new Error("browser transpiler did not load");
    return JSON.parse(compileGzim(source));
  } catch (error) {
    return { ok: false, error: error.message, diags: [{ line: 0, col: 0, message: error.message }] };
  }
}
function setFile(nextName, source, markSaved = true) {
  closeCompletions();
  fileName = nextName.endsWith(".gzim") ? nextName : nextName + ".gzim";
  editor.value = source;
  if (markSaved) savedValue = source;
  ["fileName", "tabName", "crumbName"].forEach((id) => $(id).textContent = fileName);
  renderEditor();
  refreshDiagnostics(true);
  editor.focus();
  localStorage.setItem("genzimnify.filename", fileName);
  if (window.innerWidth <= 620) $("sidebar").classList.remove("mobile-open");
}
function saveLocal() {
  localStorage.setItem("genzimnify.source", editor.value);
  localStorage.setItem("genzimnify.filename", fileName);
}
function showToast(message) {
  $("toast").textContent = message;
  $("toast").classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => $("toast").classList.remove("show"), 2200);
}
function switchPanel(name) {
  document.querySelectorAll(".panel-tab").forEach((tab) => tab.classList.toggle("active", tab.dataset.panel === name));
  document.querySelectorAll(".panel-content").forEach((panel) => panel.classList.toggle("active", panel.id === name + "Panel"));
  if ($("panel").classList.contains("collapsed")) {
    $("panel").classList.remove("collapsed");
    workbench.style.gridTemplateRows = "minmax(140px, 1fr) 4px var(--panel)";
  }
}
function showDiagnostics(result) {
  diagnostics = result && result.diags || [];
  const box = $("diags");
  box.textContent = "";
  $("problemCount").textContent = diagnostics.length;
  $("problemCount").classList.toggle("has-errors", diagnostics.length > 0);
  $("diagStatus").textContent = diagnostics.length ? "⚠ " + diagnostics.length + " cap" + (diagnostics.length > 1 ? "s" : "") : "✓ No cap";
  if (!diagnostics.length) {
    const ok = document.createElement("div");
    ok.className = "ok";
    ok.textContent = "✓ No cap detected. The vibes check out.";
    box.appendChild(ok);
    return;
  }
  diagnostics.forEach((item) => {
    const row = document.createElement("button");
    row.className = "diag";
    const icon = document.createElement("span"); icon.className = "diag-icon"; icon.textContent = "●";
    const msg = document.createElement("span"); msg.className = "msg"; msg.textContent = item.message;
    const where = document.createElement("span"); where.className = "where"; where.textContent = "Ln " + (item.line || "?") + ", Col " + (item.col || "?");
    row.append(icon, msg, where);
    row.addEventListener("click", () => goToLine(item.line || 1, item.col || 1));
    box.appendChild(row);
  });
}
function refreshDiagnostics(immediate = false) {
  clearTimeout(diagTimer);
  const update = () => {
    const result = safeCompile();
    showDiagnostics(result);
    pythonOutput.textContent = result.ok ? result.code : "# cap\n" + (result.error || "Could not transpile.");
    if (!programRunning) status.textContent = result.ok ? "Ready" : "Cap detected";
  };
  if (immediate) update(); else diagTimer = setTimeout(update, 220);
}
function goToLine(line, col = 1) {
  const sourceLines = editor.value.split("\n");
  const target = Math.max(0, Math.min(sourceLines.length - 1, line - 1));
  let offset = 0;
  for (let i = 0; i < target; i++) offset += sourceLines[i].length + 1;
  offset += Math.max(0, Math.min(sourceLines[target].length, col - 1));
  editor.focus();
  editor.setSelectionRange(offset, offset);
  const lineHeight = parseFloat(getComputedStyle(editor).lineHeight);
  editor.scrollTop = Math.max(0, target * lineHeight - editor.clientHeight / 2);
  syncScroll();
  updateCursor();
}
function clearOutput() { output.textContent = ""; outputSize = 0; outputLimited = false; }
function write(text, className = "") {
  if (outputLimited) return;
  const remaining = OUTPUT_LIMIT - outputSize;
  const limited = text.length > remaining;
  text = text.slice(0, remaining);
  outputSize += text.length;
  const span = document.createElement("span");
  if (className) span.className = className;
  span.textContent = text;
  output.appendChild(span);
  if (limited) {
    outputLimited = true;
    const notice = document.createElement("span");
    notice.className = "cap";
    notice.textContent = "\nConsole output limit reached (100,000 characters).\n";
    output.appendChild(notice);
    stopRequested = true;
    if (gameRunning) preview.stop();
    else runner.stop();
  }
  output.scrollTop = output.scrollHeight;
}
async function ensurePyodide() {
  if (pyodide) return pyodide;
  if (!pyodideLoading) {
    status.textContent = "Loading Python runtime...";
    write("Pulling up Python/WASM — first run may take a moment...\n", "welcome");
    pyodideLoading = loadPyodide({ indexURL: "https://cdn.jsdelivr.net/pyodide/v0.26.4/full/" }).then((runtime) => {
      pyodide = runtime;
      runtime.setStdout({ batched: (text) => write(text + "\n") });
      runtime.setStderr({ batched: (text) => write(text + "\n", "cap") });

      return runtime;
    }).catch((error) => { pyodideLoading = null; throw error; });
  }
  return pyodideLoading;
}
async function ensureRizzgame(runtime) {
  if (rizzgameReady) return;
  const response = await fetch("rizzgame.py");
  if (!response.ok) throw new Error("Could not load the rizzgame browser adapter");
  runtime.FS.writeFile("/home/pyodide/rizzgame.py", await response.text());
  runtime.runPython("import sys; sys.path.insert(0, '/home/pyodide')");
  rizzgameReady = true;
}
async function run() {
  if (programRunning) {
    stopRequested = true;
    if (gameRunning) preview.stop();
    else runner.stop();
    return;
  }
  programRunning = true;
  stopRequested = false;
  runBtn.disabled = false;
  runBtn.querySelector(".play + span").textContent = "Stop";
  runBtn.title = "Stop the running program (Ctrl/⌘ + Enter)";
  switchPanel("console");
  clearOutput();
  const started = performance.now();
  const source = editor.value;
  const runningFile = fileName;
  const input = $("programInput").value;
  const timeout = Number($("runTimeout").value);
  let gameTimer = null;
  let timedOut = false;
  try {
    const result = safeCompile(source);
    showDiagnostics(result);
    pythonOutput.textContent = result.ok ? result.code : "";
    if (!result.ok) {
      status.textContent = "Build failed";
      write("cap! " + (result.error || "the vibes ain't it") + "\n", "cap");
      switchPanel("problems");
      return;
    }
    gameRunning = /^\s*(?:import rizzgame(?:\.|\b)|from rizzgame(?:\.|\b))/m.test(result.code);
    write("▶ Running " + runningFile + "\n", "run-label");
    if (gameRunning) {
      preview.reset();
      const runtime = await ensurePyodide();
      if (stopRequested) { status.textContent = "Stopped"; return; }
      await ensureRizzgame(runtime);
      if (stopRequested) { status.textContent = "Stopped"; return; }
      const inputs = input === "" ? [] : input.replace(/\r\n?/g, "\n").split("\n");
      if (inputs.length > 1 && inputs[inputs.length - 1] === "") inputs.pop();
      let inputIndex = 0;
      runtime.setStdin({ stdin: () => inputIndex < inputs.length ? inputs[inputIndex++] : null });
      status.textContent = "Vibing...";
      if (timeout > 0) gameTimer = setTimeout(() => {
        timedOut = true;
        stopRequested = true;
        preview.stop();
      }, timeout);
      runtime.globals.set("_studio_source", result.code);
      try { await runtime.runPythonAsync("import rizzgame as _studio_rg; await _studio_rg.run_source(_studio_source)"); }
      finally { runtime.runPython("del _studio_source"); }
    } else {
      const outcome = await runner.run(result.code, { input, filename: runningFile, timeout });
      if (outcome.stopped) stopRequested = true;
    }
    if (stopRequested) {
      status.textContent = timedOut ? "Time limit reached" : outputLimited ? "Output limit reached" : "Stopped";
      write(timedOut ? "\nTime limit reached.\n" : "\n■ Program stopped.\n", "welcome");
    } else {
      const elapsed = Math.round(performance.now() - started);
      write("\n✓ Process finished in " + elapsed + " ms\n", "welcome");
      status.textContent = "Done in " + elapsed + " ms";
    }
  } catch (error) {
    status.textContent = "Runtime cap";
    write((error.message || error) + "\n", "cap");
  } finally {
    clearTimeout(gameTimer);
    gameRunning = false;
    programRunning = false;
    runBtn.disabled = false;
    runBtn.querySelector(".play + span").textContent = "Run vibe";
    runBtn.title = "Run vibe (Ctrl/⌘ + Enter)";
  }
}
function insertText(text, selectionOffset = text.length) {
  const start = editor.selectionStart;
  editor.setRangeText(text, start, editor.selectionEnd, "end");
  editor.selectionStart = editor.selectionEnd = start + selectionOffset;
  handleChange();
}
function closeCompletions() {
  completionPopup.hidden = true;
  completionItems = [];
  completionContext = null;
  editor.removeAttribute("aria-activedescendant");
}
function declaredCompletions() {
  const found = new Map();
  const patterns = [
    [/\b(?:let|lock)\s+([A-Za-z_][A-Za-z0-9_]*)/g, "variable"],
    [/\bcook\s+([A-Za-z_][A-Za-z0-9_]*)/g, "function"],
    [/\bclique\s+([A-Za-z_][A-Za-z0-9_]*)/g, "class"],
    [/\bfor real\s+([A-Za-z_][A-Za-z0-9_]*)/g, "variable"]
  ];
  patterns.forEach(([pattern, kind]) => {
    for (const match of editor.value.matchAll(pattern)) {
      if (!found.has(match[1])) found.set(match[1], { label: match[1], kind, detail: "From this file" });
    }
  });
  return [...found.values()];
}
function getCompletionContext(force = false) {
  if (editor.selectionStart !== editor.selectionEnd) return null;
  const cursor = editor.selectionStart;
  const lineStart = editor.value.lastIndexOf("\n", cursor - 1) + 1;
  const before = editor.value.slice(lineStart, cursor);
  let quote = "";
  let escaped = false;
  for (const character of before) {
    if (escaped) { escaped = false; continue; }
    if (character === "\\" && quote) { escaped = true; continue; }
    if (quote) { if (character === quote) quote = ""; continue; }
    if (character === '"' || character === "'") { quote = character; continue; }
    if (character === "#") return null;
  }
  if (quote) return null;
  const match = before.match(/[A-Za-z_][A-Za-z0-9_]*$/);
  if (!match && !force) return null;
  const prefix = match ? match[0] : "";
  return { start: cursor - prefix.length, cursor, prefix, lineStart, before };
}
function completionIcon(kind) {
  return ({ builtin: "ƒ", keyword: "K", value: "V", operator: "◇", function: "ƒ", class: "C", variable: "x" })[kind] || "·";
}
function positionCompletions() {
  if (completionPopup.hidden || !completionContext) return;
  const style = getComputedStyle(editor);
  const beforeCursor = editor.value.slice(completionContext.lineStart, completionContext.cursor);
  const line = editor.value.slice(0, completionContext.cursor).split("\n").length - 1;
  const lineHeight = parseFloat(style.lineHeight);
  const paddingLeft = parseFloat(style.paddingLeft);
  const paddingTop = parseFloat(style.paddingTop);
  completionMeasure.font = style.font;
  const caretLeft = paddingLeft + completionMeasure.measureText(beforeCursor).width - editor.scrollLeft;
  const caretBottom = paddingTop + (line + 1) * lineHeight - editor.scrollTop + 4;
  const maxLeft = Math.max(8, $("codeScroll").clientWidth - completionPopup.offsetWidth - 8);
  let top = caretBottom;
  if (top + completionPopup.offsetHeight > $("codeScroll").clientHeight - 8) {
    top = paddingTop + line * lineHeight - editor.scrollTop - completionPopup.offsetHeight - 4;
  }
  completionPopup.style.left = Math.max(8, Math.min(caretLeft, maxLeft)) + "px";
  completionPopup.style.top = Math.max(8, top) + "px";
}
function selectCompletion(index) {
  if (!completionItems.length) return;
  completionIndex = (index + completionItems.length) % completionItems.length;
  completionList.querySelectorAll(".completion-item").forEach((item, itemIndex) => {
    const selected = itemIndex === completionIndex;
    item.classList.toggle("selected", selected);
    item.setAttribute("aria-selected", selected ? "true" : "false");
    if (selected) {
      editor.setAttribute("aria-activedescendant", item.id);
      item.scrollIntoView({ block: "nearest" });
    }
  });
}
function renderCompletions() {
  completionList.textContent = "";
  completionItems.forEach((suggestion, index) => {
    const row = document.createElement("button");
    row.type = "button";
    row.id = "completion-" + index;
    row.className = "completion-item";
    row.setAttribute("role", "option");
    const icon = document.createElement("span"); icon.className = "completion-icon " + suggestion.kind; icon.textContent = completionIcon(suggestion.kind);
    const label = document.createElement("span"); label.className = "completion-label"; label.textContent = suggestion.label;
    const detail = document.createElement("span"); detail.className = "completion-detail"; detail.textContent = suggestion.detail || suggestion.kind;
    row.append(icon, label, detail);
    row.addEventListener("mouseenter", () => selectCompletion(index));
    row.addEventListener("mousedown", (event) => { event.preventDefault(); selectCompletion(index); acceptCompletion(); });
    completionList.appendChild(row);
  });
  completionPopup.hidden = false;
  selectCompletion(Math.min(completionIndex, completionItems.length - 1));
  requestAnimationFrame(positionCompletions);
}
function updateCompletions(force = false) {
  const context = getCompletionContext(force);
  if (!context) { closeCompletions(); return; }
  const all = [...declaredCompletions(), ...COMPLETION_ITEMS];
  const phrase = context.before.match(/[A-Za-z_][A-Za-z0-9_]*(?:\s+[A-Za-z_][A-Za-z0-9_]*)+$/)?.[0] || "";
  if (phrase && all.some((item) => item.label.toLowerCase().startsWith(phrase.toLowerCase()))) {
    context.prefix = phrase;
    context.start = context.cursor - phrase.length;
  }
  const prefix = context.prefix.toLowerCase();
  const seen = new Set();
  completionItems = all.filter((item) => {
    const label = item.label.toLowerCase();
    if ((!force && !label.startsWith(prefix)) || seen.has(label)) return false;
    seen.add(label);
    return true;
  }).slice(0, 9);
  if (!completionItems.length) { closeCompletions(); return; }
  completionContext = context;
  completionIndex = 0;
  renderCompletions();
}
function acceptCompletion() {
  const item = completionItems[completionIndex];
  if (!item || !completionContext) return;
  const insert = item.insert || item.label;
  editor.setRangeText(insert, completionContext.start, completionContext.cursor, "end");
  const cursor = completionContext.start + (item.cursor ?? insert.length);
  editor.setSelectionRange(cursor, cursor);
  suppressCompletionOnce = true;
  handleChange();
  closeCompletions();
}
function handleEditorKeydown(event) {
  const mod = event.ctrlKey || event.metaKey;
  if (!completionPopup.hidden) {
    if (event.key === "Escape") { event.preventDefault(); closeCompletions(); return; }
    if (event.key === "Tab") { event.preventDefault(); selectCompletion(completionIndex + (event.shiftKey ? -1 : 1)); return; }
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault(); selectCompletion(completionIndex + (event.key === "ArrowDown" ? 1 : -1)); return;
    }
    if (event.key === "Enter" && !mod) { event.preventDefault(); acceptCompletion(); return; }
  }
  if (mod && event.key === " ") { event.preventDefault(); updateCompletions(true); return; }
  if (mod && event.key === "Enter") { event.preventDefault(); run(); return; }
  if (mod && event.key.toLowerCase() === "s") { event.preventDefault(); saveLocal(); savedValue = editor.value; renderEditor(); showToast("Saved in this browser"); return; }
  if (mod && event.key.toLowerCase() === "f") { event.preventDefault(); openFind(); return; }
  if ((mod && event.key.toLowerCase() === "k") || event.key === "F1") { event.preventDefault(); openCommands(); return; }
  if (event.shiftKey && event.altKey && event.key.toLowerCase() === "f") { event.preventDefault(); formatDocument(); return; }
  if (event.key === "Tab") {
    event.preventDefault();
    const start = editor.selectionStart;
    const end = editor.selectionEnd;
    if (start !== end && editor.value.slice(start, end).includes("\n")) {
      const lineStart = editor.value.lastIndexOf("\n", start - 1) + 1;
      const selected = editor.value.slice(lineStart, end);
      const changed = event.shiftKey ? selected.replace(/^ {1,4}/gm, "") : selected.replace(/^/gm, "    ");
      editor.setRangeText(changed, lineStart, end, "select");
      handleChange();
    } else if (event.shiftKey) {
      const lineStart = editor.value.lastIndexOf("\n", start - 1) + 1;
      const spaces = (editor.value.slice(lineStart, start).match(/^ {1,4}/) || [""])[0];
      editor.setRangeText("", lineStart, lineStart + spaces.length, "end");
      handleChange();
    } else insertText("    ");
    return;
  }
  if (event.key === "Enter") {
    event.preventDefault();
    const before = editor.value.slice(0, editor.selectionStart);
    const line = before.slice(before.lastIndexOf("\n") + 1);
    const indent = (line.match(/^[ \t]*/) || [""])[0];
    insertText("\n" + indent + (line.trimEnd().endsWith(":") ? "    " : ""));
    return;
  }
  const closingPairs = new Set([")", "]", "}", "\"", "'"]);
  if (closingPairs.has(event.key) && editor.selectionStart === editor.selectionEnd && editor.value[editor.selectionStart] === event.key) {
    event.preventDefault();
    editor.setSelectionRange(editor.selectionStart + 1, editor.selectionStart + 1);
    closeCompletions();
    updateCursor();
    return;
  }
  const pairs = { "(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'" };
  if (pairs[event.key] && editor.selectionStart === editor.selectionEnd) {
    event.preventDefault();
    insertText(event.key + pairs[event.key], 1);
  }
}
function handleChange() {
  renderEditor(); saveLocal(); refreshDiagnostics();
  if (suppressCompletionOnce) { suppressCompletionOnce = false; closeCompletions(); }
  else updateCompletions();
}
function syncScroll() {
  highlight.scrollTop = editor.scrollTop;
  highlight.scrollLeft = editor.scrollLeft;
  lineNumbers.scrollTop = editor.scrollTop;
  positionCompletions();
}
function updateCursor() {
  const before = editor.value.slice(0, editor.selectionStart);
  const line = before.split("\n").length;
  const col = before.length - before.lastIndexOf("\n");
  const selected = Math.abs(editor.selectionEnd - editor.selectionStart);
  $("cursorStatus").textContent = "Ln " + line + ", Col " + col + (selected ? " (" + selected + " selected)" : "");
}
function formatDocument() {
  const cursor = editor.selectionStart;
  editor.value = editor.value.split("\n").map((line) => line.replace(/\t/g, "    ").replace(/[ \t]+$/g, "")).join("\n").replace(/\n*$/, "\n");
  editor.selectionStart = editor.selectionEnd = Math.min(cursor, editor.value.length);
  handleChange();
  showToast("Document formatted");
}
function newFile() {
  if (editor.value !== savedValue && !window.confirm("Start a new vibe? Your current code is autosaved in this browser.")) return;
  setFile("untitled.gzim", "# start cooking\n", false);
}
function downloadFile() {
  const blob = new Blob([editor.value], { type: "text/plain;charset=utf-8" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = fileName;
  link.click();
  URL.revokeObjectURL(link.href);
  savedValue = editor.value;
  renderEditor();
  showToast("Downloaded " + fileName);
}
function importFile(file) {
  if (!file) return;
  const reader = new FileReader();
  reader.onload = () => setFile(file.name, String(reader.result));
  reader.readAsText(file);
}
async function shareCode() {
  const encoded = btoa(unescape(encodeURIComponent(editor.value)));
  const url = new URL(location.href);
  url.hash = "code=" + encoded;
  try { await navigator.clipboard.writeText(url.href); showToast("Share link copied"); }
  catch { window.prompt("Copy this share link:", url.href); }
}
function toggleTheme() {
  const next = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
  document.documentElement.dataset.theme = next;
  localStorage.setItem("genzimnify.theme", next);
  $("themeBtn").textContent = next === "dark" ? "☼" : "◐";
}
function openFind() {
  $("findWidget").hidden = false;
  $("findInput").focus();
  $("findInput").select();
  updateFind();
}
function updateFind(direction = 0) {
  const query = $("findInput").value;
  findMatches = [];
  if (query) {
    let position = 0;
    const haystack = editor.value.toLocaleLowerCase();
    const needle = query.toLocaleLowerCase();
    while ((position = haystack.indexOf(needle, position)) !== -1) {
      findMatches.push(position);
      position += Math.max(1, needle.length);
    }
  }
  if (findMatches.length) {
    findIndex = direction ? (findIndex + direction + findMatches.length) % findMatches.length : Math.max(0, findMatches.findIndex((x) => x >= editor.selectionStart));
    if (findIndex < 0) findIndex = 0;
    const at = findMatches[findIndex];
    editor.focus();
    editor.setSelectionRange(at, at + query.length);
  } else findIndex = -1;
  $("findCount").textContent = (findIndex + 1) + "/" + findMatches.length;
}
const COMMANDS = [
  ["Run vibe", "⌘ Enter", run], ["New file", "⌘ N", newFile], ["Format document", "⇧⌥ F", formatDocument],
  ["Find in file", "⌘ F", openFind], ["Download .gzim", "", downloadFile], ["Toggle color theme", "", toggleTheme],
  ["Show generated Python", "", () => switchPanel("python")], ["Show problems", "", () => switchPanel("problems")]
];
function renderCommands() {
  const query = $("commandInput").value.toLowerCase();
  $("commandList").textContent = "";
  COMMANDS.filter((item) => item[0].toLowerCase().includes(query)).forEach((item, index) => {
    const button = document.createElement("button");
    button.className = "command-item" + (index === 0 ? " selected" : "");
    const label = document.createElement("span"); label.textContent = item[0];
    const shortcut = document.createElement("kbd"); shortcut.textContent = item[1];
    button.append(label, shortcut);
    button.addEventListener("click", () => { closeCommands(); item[2](); });
    $("commandList").appendChild(button);
  });
}
function openCommands() { $("commandBackdrop").hidden = false; $("commandInput").value = ""; renderCommands(); $("commandInput").focus(); }
function closeCommands() { $("commandBackdrop").hidden = true; editor.focus(); }

Object.entries(EXAMPLES).forEach(([name, source]) => {
  const button = document.createElement("button");
  button.className = "example-row";
  const icon = document.createElement("span"); icon.className = "file-icon"; icon.textContent = "G";
  const label = document.createElement("span"); label.textContent = name;
  button.append(icon, label);
  button.addEventListener("click", () => setFile(name, source));
  $("exampleList").appendChild(button);
});
REFERENCE.forEach(([gzim, python]) => {
  const row = document.createElement("div"); row.className = "ref-row";
  const code = document.createElement("code"); code.textContent = gzim;
  const meaning = document.createElement("span"); meaning.textContent = python;
  row.append(code, meaning); $("referenceList").appendChild(row);
});

editor.addEventListener("input", handleChange);
editor.addEventListener("keydown", handleEditorKeydown);
editor.addEventListener("scroll", syncScroll);
editor.addEventListener("click", () => { updateCursor(); closeCompletions(); });
editor.addEventListener("keyup", updateCursor);
editor.addEventListener("blur", () => setTimeout(() => { if (document.activeElement !== editor) closeCompletions(); }, 100));
runBtn.addEventListener("click", run);
$("loadRizzgameBtn").addEventListener("click", () => setFile("rizzgame-starter.gzim", EXAMPLES["rizzgame-starter.gzim"]));
$("newBtn").addEventListener("click", newFile);
$("formatBtn").addEventListener("click", formatDocument);
$("downloadBtn").addEventListener("click", downloadFile);
$("importBtn").addEventListener("click", () => $("fileInput").click());
$("fileInput").addEventListener("change", (event) => importFile(event.target.files[0]));
$("shareBtn").addEventListener("click", shareCode);
$("themeBtn").addEventListener("click", toggleTheme);
$("clearBtn").addEventListener("click", clearOutput);
$("diagStatus").addEventListener("click", () => switchPanel("problems"));
$("searchBtn").addEventListener("click", openFind);
document.querySelectorAll(".panel-tab").forEach((tab) => tab.addEventListener("click", () => switchPanel(tab.dataset.panel)));
document.querySelectorAll(".menu-button").forEach((button) => button.addEventListener("click", () => {
  ({ new: newFile, format: formatDocument, run: run })[button.dataset.command]();
}));
document.querySelectorAll(".activity[data-view]").forEach((button) => button.addEventListener("click", () => {
  const view = button.dataset.view;
  const sidebar = $("sidebar");
  const already = button.classList.contains("active") && sidebar.classList.contains("mobile-open");
  document.querySelectorAll(".activity[data-view]").forEach((item) => item.classList.toggle("active", item === button));
  document.querySelectorAll(".side-view").forEach((item) => item.classList.toggle("active", item.id === view + "View"));
  if (window.innerWidth <= 620) sidebar.classList.toggle("mobile-open", !already);
}));
$("togglePanelBtn").addEventListener("click", () => {
  const collapsed = !$("panel").classList.contains("collapsed");
  $("panel").classList.toggle("collapsed", collapsed);
  $("resizeHandle").style.display = collapsed ? "none" : "";
  workbench.style.gridTemplateRows = collapsed ? "minmax(0, 1fr) 0 0" : "minmax(140px, 1fr) 4px var(--panel)";
});
$("findInput").addEventListener("input", () => updateFind());
$("findInput").addEventListener("keydown", (event) => {
  if (event.key === "Enter") { event.preventDefault(); updateFind(event.shiftKey ? -1 : 1); }
  if (event.key === "Escape") { $("findWidget").hidden = true; editor.focus(); }
});
$("findPrev").addEventListener("click", () => updateFind(-1));
$("findNext").addEventListener("click", () => updateFind(1));
$("findClose").addEventListener("click", () => { $("findWidget").hidden = true; editor.focus(); });
$("commandInput").addEventListener("input", renderCommands);
$("commandInput").addEventListener("keydown", (event) => {
  if (event.key === "Escape") closeCommands();
  if (event.key === "Enter") document.querySelector(".command-item")?.click();
});
$("commandBackdrop").addEventListener("click", (event) => { if (event.target === $("commandBackdrop")) closeCommands(); });
$("resizeHandle").addEventListener("pointerdown", (event) => {
  event.preventDefault();
  $("resizeHandle").classList.add("dragging");
  const move = (pointer) => {
    const rect = workbench.getBoundingClientRect();
    const height = Math.max(100, Math.min(rect.height - 150, rect.bottom - pointer.clientY));
    document.documentElement.style.setProperty("--panel", height + "px");
  };
  const done = () => {
    $("resizeHandle").classList.remove("dragging");
    window.removeEventListener("pointermove", move);
    window.removeEventListener("pointerup", done);
  };
  window.addEventListener("pointermove", move);
  window.addEventListener("pointerup", done);
});
window.addEventListener("keydown", (event) => {
  const mod = event.ctrlKey || event.metaKey;
  if (mod && event.key.toLowerCase() === "n") { event.preventDefault(); newFile(); }
  if (event.key === "Escape" && !$("commandBackdrop").hidden) closeCommands();
});

document.documentElement.dataset.theme = localStorage.getItem("genzimnify.theme") || "dark";
$("themeBtn").textContent = document.documentElement.dataset.theme === "dark" ? "☼" : "◐";
let initialSource = "";
try {
  const code = new URLSearchParams(location.hash.slice(1)).get("code");
  if (code) initialSource = decodeURIComponent(escape(atob(code)));
} catch { showToast("That share link is invalid"); }
initialSource ||= localStorage.getItem("genzimnify.source") || EXAMPLES["hello-vibes.gzim"];
fileName = localStorage.getItem("genzimnify.filename") || "main.gzim";
setFile(fileName, initialSource);
