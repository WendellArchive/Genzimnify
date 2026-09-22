/* Genzimnify playground logic: compileGzim (from transpiler.js) + Pyodide. */

const EXAMPLES = {
  "fizzbuzz": `# ngl the classic
for real i up in vibes(1, 16):
    vibecheck i % 15 == 0:
        yap("FizzBuzz")
    or i % 3 == 0:
        yap("Fizz")
    or i % 5 == 0:
        yap("Buzz")
    otherwise:
        yap(i)
`,
  "functions": `# cooks, defaults, mini vibes, recursion
cook add(a, b):
    send it a + b fr

cook greet(name, greeting be "yo"):
    send it glow"{greeting} {name}!" fr

cook fib(n):
    vibecheck n < 2:
        send it n fr
    send it call up fib(n - 1) yo + call up fib(n - 2) yo fr

let double be mini vibe(x): x * 2
yap(call up add(4, 3) yo)
yap(call up greet("chat") yo)
yap(call up double(21) yo)
yap(call up fib(10) yo)
`,
  "classes": `# cliques roll deep
clique Dog:
    cook new(fam, name):
        fam.name be name

    cook speak(fam):
        yap(glow"{fam.name} says woof")

clique Puppy(Dog):
    cook new(fam, name):
        ancestor.new(fam, name)
        fam.cuteness be 100

    cook speak(fam):
        yap("tiny woof")

let d be call up Dog("Rex") yo
call up d.speak() yo
let p be call up Puppy("Bit") yo
call up p.speak() yo
yap(p.name, p.cuteness)
`,
  "try / catch": `# f around and find out
f_around:
    let x be 1 / 0
find_out SplitByZero as e:
    yap("can't divide by zero, bestie")
no_matter_what:
    yap("we move")

f_around:
    throw shade BadVibe("nah")
find_out BadVibe as e:
    yap(glow"caught: {e}")
`,
  "generator": `# drop makes a generator
cook countdown(n):
    vibe n > 0:
        drop n
        n be n - 1

for real i up in call up countdown(3) yo:
    yap(i)
`,
  "fit check": `# pattern matching, no cap
for real x up in [1, 2, 99]:
    fit check x:
        fit 1:
            yap("one")
        fit 2:
            yap("two")
        otherwise:
            yap("idk")
`,
  "collections": `# stacks, maps, squads, crews
let evens be [x for real x up in vibes(10) sus x % 2 == 0]
yap(evens)
let m be {"a": 1, "b": 2}
yap(m["a"])
yap(call up add up([1, 2, 3]) yo)
yap(call up ranked([3, 1, 2]) yo)
let s be {1, 2, 2}
yap(call up how many(s) yo)
`,
  "async": `# on timing, wait up
pull up timing

on timing cook main():
    wait up timing.sleep(0)
    yap("async vibes fr")

call up timing.run(main()) yo
`,
  "yap back": `# yap back = input (a prompt pops up)
let name be yap back("what's your name? ")
yap(glow"sup {name}, the vibes appreciate you")
`,
};

const $ = (id) => document.getElementById(id);
const editor = $("editor");
const output = $("output");
const diagsBox = $("diags");
const status = $("status");
const runBtn = $("runBtn");
const showPy = $("showPy");
const examples = $("examples");

/* populate the examples dropdown, sorted for vibes */
for (const key of Object.keys(EXAMPLES).sort()) {
  const opt = document.createElement("option");
  opt.value = key;
  opt.textContent = key;
  examples.appendChild(opt);
}
examples.addEventListener("change", () => {
  if (examples.value in EXAMPLES) {
    editor.value = EXAMPLES[examples.value];
    refreshDiags();
  }
});

/* ------------------------------------------------------------------ output */

function clearOutput() {
  output.textContent = "";
}

function write(text) {
  output.textContent += text;
  output.scrollTop = output.scrollHeight;
}

function writeCap(text) {
  const span = document.createElement("span");
  span.className = "cap";
  span.textContent = text;
  output.appendChild(span);
}

function writePy(text) {
  const span = document.createElement("span");
  span.className = "py";
  span.textContent = text;
  output.appendChild(span);
}

/* ------------------------------------------------------------------ diags */

function showDiags(res) {
  diagsBox.textContent = "";
  const list = (res && res.diags) || [];
  if (list.length === 0) {
    const ok = document.createElement("div");
    ok.className = "ok";
    ok.textContent = "no cap, the vibes check out";
    diagsBox.appendChild(ok);
    return;
  }
  for (const d of list) {
    const row = document.createElement("div");
    row.className = "diag";
    const where = document.createElement("span");
    where.className = "where";
    where.textContent = `L${d.line}:${d.col}  `;
    const msg = document.createElement("span");
    msg.className = "msg";
    msg.textContent = d.message;
    row.appendChild(where);
    row.appendChild(msg);
    diagsBox.appendChild(row);
  }
}

let diagTimer = null;
function refreshDiags() {
  clearTimeout(diagTimer);
  diagTimer = setTimeout(() => {
    try {
      showDiags(JSON.parse(compileGzim(editor.value)));
    } catch (e) {
      /* transpiler exploded; stay calm, stay vibing */
    }
  }, 250);
}
editor.addEventListener("input", refreshDiags);

/* ------------------------------------------------------------------ editing */

editor.addEventListener("keydown", (e) => {
  if (e.key === "Tab") {
    e.preventDefault();
    insertAtCursor("    ");
  } else if (e.key === "Enter" && !e.ctrlKey && !e.metaKey) {
    e.preventDefault();
    const upTo = editor.value.slice(0, editor.selectionStart);
    const line = upTo.slice(upTo.lastIndexOf("\n") + 1);
    const indent = (line.match(/^[ \t]*/) || [""])[0];
    const extra = line.trim().endsWith(":") ? "    " : "";
    insertAtCursor("\n" + indent + extra);
  } else if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
    e.preventDefault();
    run();
  }
});

function insertAtCursor(text) {
  const start = editor.selectionStart;
  const end = editor.selectionEnd;
  editor.value = editor.value.slice(0, start) + text + editor.value.slice(end);
  const pos = start + text.length;
  editor.selectionStart = editor.selectionEnd = pos;
  refreshDiags();
}

/* ------------------------------------------------------------------ run */

let pyodide = null;
let pyodideLoading = null;

async function ensurePyodide() {
  if (pyodide) return pyodide;
  if (!pyodideLoading) {
    status.textContent = "pulling up the python runtime (pyodide), first run takes a sec fr";
    pyodideLoading = loadPyodide({
      indexURL: "https://cdn.jsdelivr.net/pyodide/v0.26.4/full/",
    }).then((py) => {
      pyodide = py;
      py.setStdout({ batched: (s) => write(s + "\n") });
      py.setStderr({ batched: (s) => writeCap(s + "\n") });
      py.setStdin({ stdin: () => window.prompt("yap back (input):") ?? "" });
      return py;
    });
  }
  return pyodideLoading;
}

async function run() {
  runBtn.disabled = true;
  clearOutput();
  try {
    let res;
    try {
      res = JSON.parse(compileGzim(editor.value));
    } catch (e) {
      writeCap("cap! transpiler exploded: " + e.message + "\n");
      return;
    }
    showDiags(res);
    if (!res.ok) {
      status.textContent = "cap";
      writeCap("cap! " + (res.error || "the vibes ain't it") + "\n");
      return;
    }
    if (showPy.checked) {
      status.textContent = "python output";
      writePy(res.code);
      return;
    }
    const py = await ensurePyodide();
    status.textContent = "vibing…";
    try {
      await py.runPythonAsync(res.code);
      status.textContent = "done. no cap.";
    } catch (e) {
      status.textContent = "cap at runtime";
      writeCap(e.message + "\n");
    }
  } finally {
    runBtn.disabled = false;
  }
}

runBtn.addEventListener("click", run);
showPy.addEventListener("change", () => {
  /* re-render without running: show the last compiled python */
  const res = JSON.parse(compileGzim(editor.value));
  clearOutput();
  if (showPy.checked && res.ok) {
    writePy(res.code);
  } else {
    refreshDiags();
  }
});

/* boot with an example, deadass */
editor.value = EXAMPLES["fizzbuzz"];
refreshDiags();
