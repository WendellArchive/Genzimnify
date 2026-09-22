# Genzimnify

**Python semantics, Gen Z surface syntax. If it vibes, it compiles.**

Genzimnify is a Turing-complete programming language that source-to-source
transpiles to Python. It is implemented in Nim. A Genzimnify program is called a
**vibe**. Running it is **vibing**. Errors are **cap**. Debugging is **checking
the vibe**.

```gzim
for real i up in vibes(1, 101):
    vibecheck i % 15 == 0:
        yap("FizzBuzz")
    or i % 3 == 0:
        yap("Fizz")
    or i % 5 == 0:
        yap("Buzz")
    otherwise:
        yap(i)
```

## Quick start

Requires [Nim](https://nim-lang.org) (>= 2.0) and Python 3.10+.

```sh
nimble build            # or: nim c -d:release -o:build/genzimc src/genzimc.nim
build/genzimc run examples/fizzbuzz.gzim
```

## CLI

```sh
gzimc run <file.gzim>      # transpile + run it (no cap)
gzimc build <file.gzim>    # transpile to <file>.py (+ <file>.py.gzmap source map)
gzimc check <file.gzim>    # parse + semantic vibecheck only
gzimc repl                 # the vibe loop (blank line runs, ctrl-d dips)
gzimc init                 # drop a starter main.gzim
```

## The language

File extension is `.gzim`. Single-line comments start with `#`; multi-line
comments are `#[[ ... ]]#`. Statements end with a newline; `fr` is an optional
explicit terminator (and lets several statements share a line). A colon opens a
block; indentation closes it.

### Keywords

| Genzimnify      | Python      | Genzimnify        | Python        |
|-----------------|-------------|-------------------|---------------|
| `let` / `lock`  | decl / const| `vibe`            | `while`       |
| `be` (`be+`…)   | `=` (`+=`…) | `for real … up in`| `for … in`    |
| `nocap` / `cap` | `True` / `False` | `dip` / `next` | `break` / `continue` |
| `ghost`         | `None`      | `deadass`         | `pass`        |
| `both` / `either` / `aint` | `and` / `or` / `not` | `cook` | `def` |
| `same as` / `nah` | `==` / `!=` | `send it` / `drop` | `return` / `yield` |
| `literally` / `aint literally` | `is` / `is not` | `call up … yo` | call |
| `up in` / `aint up in` | `in` / `not in` | `clique` / `new` / `fam` / `ancestor` | `class` / `__init__` / `self` / `super` |
| `vibecheck` / `or` / `otherwise` | `if` / `elif` / `else` | `pull up` / `outta` | `import` / `from` |
| `f_around` / `find_out` / `no_matter_what` | `try` / `except` / `finally` | `throw shade` | `raise` |
| `roll with` | `with` | `on timing` / `wait up` | `async` / `await` |
| `mini vibe` | `lambda` | `fit check` / `fit` | `match` / `case` |
| `worldwide` / `localish` | `global` / `nonlocal` | `cancel` / `on god` | `del` / `assert` |

### Types & collections

`num` (int), `drip` (float), `text` (str), `truth` (bool), `ghost` (None);
`stack` (list), `map` (dict), `squad` (set), `crew` (tuple).

Type hints: `let x be 5 as num`, `stack[num]` → `list[int]`,
`map[text, num]` → `dict[str, int]`, `num or text` → `int | str`,
`num?` → `int | None`, `whatever` → `Any`. Functions: `cook add(a as num, b as num) gives num:`.

### Function calls

Calls are expressions wrapped in `call up … yo`:

```gzim
yap(call up add(4, 3) yo)
let n be call up how many(stack) yo
```

### Highlights

- f-strings: `yap(glow"{fam.name} says woof")`
- comprehensions: `let evens be [x for real x up in vibes(10) sus x % 2 == 0]`
- generators: `drop n` inside a `cook` (bare `drop` yields `None`)
- classes, inheritance, `ancestor.new(fam, ...)` → `super().__init__(...)`
- exceptions: `f_around` / `find_out BadVibe as e` / `no_matter_what`
- pattern matching: `fit check x:` / `fit 1:` / `otherwise:`
- context managers: `roll with unlock("file.txt") as f:`
- async: `on timing cook fetch():`, run with `call up timing.run(fetch()) yo`

### Slang modules & exceptions

| Module | Python | | Exception | Python |
|--------|--------|-|-----------|--------|
| `luck` | `random` | | `L` | `Exception` |
| `clock` | `time` | | `BadVibe` | `ValueError` |
| `system` | `os` (+`sys` via `outta`) | | `SplitByZero` | `ZeroDivisionError` |
| `timing` | `asyncio` | | `Ghosted` | `KeyError` |
| `stash` / `loops` / `tools` | `collections` / `itertools` / `functools` | | `CapDetected` | `AssertionError` |
| `paths` / `spawn` / `net` / `web` / `db` | `pathlib` / `subprocess` / `socket` / `http` / `sqlite3` | | `StopTheCap` | `StopIteration` |

## Architecture (in Nim, under `src/genzimnify/`)

1. `lexer.nim`, tokens, INDENT/DEDENT stack, `fr`, multi-word keywords
2. `parser.nim`, recursive descent statements + Pratt expressions
3. `ast.nim`, variant AST nodes
4. `semantic.nim`, the vibecheck: scoping, locks, mis-scoped slang
5. `emit.nim`, Python emitter with indentation tracking + source map
6. `cli.nim`, run / build / check / repl / init

Semantic rules enforced at compile time: reassignment requires a prior `let`,
`lock` vars can't be rebound, `send it` only inside `cook`, `dip`/`next` only
inside loops, `fam` only inside clique methods, `wait up` only inside
`on timing cook`, `drop` marks generators.

## Browser playground (`site/`)

Fully static, no build step, works from `file://` too:

```sh
# rebuild the in-browser transpiler (Nim -> JS) after touching the core:
nim js -d:release --out:site/transpiler.js src/genzimnify/web.nim

# then just open it:
open site/index.html     # or: python3 -m http.server -d site
```

The transpiler core compiles to JavaScript (`nim js`), so code is transpiled
client-side; the emitted Python runs via [Pyodide](https://pyodide.org)
(Python→WASM, loaded from a CDN on first run). `yap back` pops a prompt,
stdout lands in the right pane, and the "python" toggle shows the generated
source.

## Tooling: LSP + Zed extension

### gzim-lsp (language server)

Build with `nim c -o:build/gzim-lsp src/gzimlsp.nim` (or `nimble build`). Speaks
JSON-RPC/LSP over stdio and provides:

- **Diagnostics**, parse + semantic cap, published live as you type
- **Hover**, slang keyword docs (with the Python equivalent), variable/cook/clique
  signatures, `fam`/`ancestor` explainers
- **Go-to-definition**, jump to `let` / `cook` / `clique` / param declarations
- **Completion**, all slang keywords, builtins, modules + file-local decls
- **Document symbols**, outline of cooks, cliques and variables

```sh
tests/lsp_test.sh   # scripted end-to-end protocol test
```

### Zed extension (`zed-genzimnify/`)

```
zed-genzimnify/
├── extension.toml                    # extension + grammar + language + server manifest
├── Cargo.toml / src/lib.rs           # wasm glue: locates gzim-lsp for Zed
├── languages/genzimnify/
│   ├── config.toml                   # .gzim files -> Genzimnify language
│   └── highlights.scm                # tree-sitter highlight queries
└── grammars/genzimnify/
    ├── grammar.js                    # the tree-sitter grammar
    ├── tree-sitter.json
    └── src/{parser.c,scanner.c,...}   # generated parser + external scanner
                                      # (NEWLINE/INDENT/DEDENT + glow f-strings)
```

Install as a dev extension: Zed → command palette → `zed: install dev extension`
→ select the `zed-genzimnify` folder. Zed compiles the tree-sitter grammar to
wasm and registers the language for `.gzim` files; the extension's Rust glue
spawns `gzim-lsp` from your PATH for diagnostics/hover/completion/navigation.

Build `gzim-lsp` first and keep it on PATH (e.g. `~/.local/bin`), otherwise
Zed will error when it tries to start the server.

To regenerate the parser after editing `grammar.js`:

```sh
cd grammars/genzimnify && tree-sitter generate
cp src/parser.c src/scanner.c src/node-types.json src/grammar.json \
   ../../zed-genzimnify/grammars/genzimnify/src/
```

## Tests

```sh
tests/run_tests.sh
```

## Notes & limits

- Same-quote nesting inside `glow` strings is unsupported (like Python <3.12), use mixed quotes.
- `pull up system` imports `os` (as `system`); `sys`-only names should use `outta system pull up <name>` (falls back to `sys` automatically).
- Comparison chains transpile left-associative, unlike Python's chaining, write `both` chains explicitly.
- Requires Python 3.10+ at runtime (`asyncio.run`, `int | str` unions, `match`).

---

**Genzimnify**, because why write Python when you can vibe?
