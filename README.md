<p align="center">
  <img src="assets/genzimnify-mark.svg" width="96" alt="Genzimnify logo">
</p>

<h1 align="center">Genzimnify</h1>

<p align="center">
  A native programming language with Python-like semantics and Gen Z syntax.
</p>

<p align="center">
  <a href="https://github.com/Obliv1onis/Genzimnify/actions/workflows/ci.yml"><img src="https://github.com/Obliv1onis/Genzimnify/actions/workflows/ci.yml/badge.svg" alt="Native runtime CI"></a>
  <a href="https://github.com/Obliv1onis/Genzimnify/releases/latest"><img src="https://img.shields.io/github/v/release/Obliv1onis/Genzimnify" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Obliv1onis/Genzimnify" alt="MIT license"></a>
</p>

<p align="center">
  <a href="https://obliv1onis.github.io/Genzimnify/">Documentation</a> ·
  <a href="https://obliv1onis.github.io/Genzimnify/installation.html">Installation</a> ·
  <a href="https://obliv1onis.github.io/Genzimnify/language-guide.html">Language guide</a> ·
  <a href="https://github.com/Obliv1onis/Genzimnify/releases">Releases</a>
</p>

Genzimnify is a standalone, dynamically typed programming language with a
runtime written in Nim. The `gzim` executable parses, checks, and executes
`.gzim` files directly—normal execution does not generate Python or require a
Python installation.

```gzim
cook fizzbuzz(limit as num):
    for real i up in vibes(1, limit + 1):
        vibecheck i % 15 == 0:
            yap("FizzBuzz")
        or i % 3 == 0:
            yap("Fizz")
        or i % 5 == 0:
            yap("Buzz")
        otherwise:
            yap(i)

call up fizzbuzz(100) yo
```

## Why Genzimnify?

- **Native execution:** lexer, parser, semantic checker, and interpreter ship
  in one compiled runtime.
- **Familiar semantics:** indentation-based blocks, functions, collections,
  comprehensions, classes, exceptions, matching, generators, and type hints.
- **Distinct syntax:** functions are `cook`, classes are `clique`, output is
  `yap`, and errors are `cap`.
- **Project tooling:** manifests, lockfiles, Git and local-path dependencies,
  a REPL, editor integration, and a language server.
- **Optional interoperability:** explicitly import Python libraries through
  `py.*` without making Python a dependency of ordinary programs.

## Quick start

### macOS and Linux

The shell installer supports Apple Silicon macOS, Ubuntu, and Kali Linux.
Genzimnify 2.0.2 and newer no longer publish Intel Mac binaries:

```sh
curl -fsSL https://raw.githubusercontent.com/Obliv1onis/Genzimnify/master/scripts/install.sh | sh
gzim doctor
```

### Windows

Run the PowerShell installer on Windows 10 or newer:

```powershell
irm https://raw.githubusercontent.com/Obliv1onis/Genzimnify/master/scripts/install.ps1 | iex
gzim doctor
```

Release packages include both `gzim` and `gzim-lsp`. See the
[installation guide](https://obliv1onis.github.io/Genzimnify/installation.html)
for Homebrew, manual downloads, supported architectures, and custom install
locations.

### Create a project

```sh
mkdir hello-gzim
cd hello-gzim
gzim init
gzim main.gzim
```

`gzim init` creates a starter `main.gzim` file and a `gzim.toml` project
manifest.

## Language at a glance

```gzim
# Variables and interpolation
let name be "world"
lock language be "Genzimnify"
yap(glow"Hello, {name} from {language}")

# Collections and comprehensions
let numbers be [1, 2, 3, 4, 5]
let evens be [n for real n up in numbers sus n % 2 == 0]

# Functions
cook add(a as num, b as num) gives num:
    send it a + b

# Classes
clique Greeter:
    cook new(fam, greeting):
        fam.greeting be greeting

    cook greet(fam, who):
        send it glow"{fam.greeting}, {who}"

let greeter be call up Greeter("yo") yo
yap(call up greeter.greet("chat") yo)
```

Common syntax:

| Genzimnify | Meaning | Python equivalent |
|---|---|---|
| `let x be 1` / `lock x be 1` | Mutable / immutable binding | `x = 1` |
| `nocap`, `cap`, `ghost` | Boolean and empty values | `True`, `False`, `None` |
| `vibecheck` / `or` / `otherwise` | Conditional branches | `if` / `elif` / `else` |
| `for real x up in values` | Iteration | `for x in values` |
| `vibe condition` | Loop while true | `while condition` |
| `cook` / `send it` | Function / return | `def` / `return` |
| `clique` / `fam` / `ancestor` | Class / self / super | `class` / `self` / `super` |
| `pull up` / `outta … pull up` | Import | `import` / `from … import` |
| `f_around` / `find_out` | Exception handling | `try` / `except` |
| `call up function() yo` | Call expression | `function()` |

The language also supports `glow` strings, generators, comprehensions,
pattern matching, context managers, async syntax, global/nonlocal bindings,
and optional type annotations. The
[language guide](https://obliv1onis.github.io/Genzimnify/language-guide.html)
contains the complete reference.

## Command-line interface

| Command | Purpose |
|---|---|
| `gzim app.gzim [args]` | Run a program in the native runtime |
| `gzim run app.gzim [args]` | Explicit form of the run command |
| `gzim check app.gzim` / `gzim check .` | Check a file or source directory without running |
| `gzim eval 'yap(1 + 2)'` | Run an inline program |
| `gzim repl` | Start an interactive session |
| `gzim init` | Create `main.gzim` and `gzim.toml` |
| `gzim add <name> <source>` | Add a Git or local dependency |
| `gzim install [--locked]` | Restore dependencies; optionally require a matching lockfile |
| `gzim update [name]` | Update one or all dependencies to their source revisions |
| `gzim packages` | List project dependencies |
| `gzim remove <name>` | Remove a dependency |
| `gzim doctor` | Show runtime and platform information |
| `gzim --version` / `gzim --version --offline` | Show version, with optional update guidance |
| `gzim convert <file> --to <py\|gzim>` | Convert source files; Python import is a limited preview |

See the [CLI reference](https://obliv1onis.github.io/Genzimnify/cli.html) for
exit behavior and command details.

`gzim --version` prints the local version first, then checks GitHub for a newer
stable release using curl with a two-second transfer limit. Update instructions
appear on stderr; no installer runs automatically. Offline failures do not change
the exit code. Use `--offline` or `GZIM_NO_UPDATE_CHECK=1` to skip the check.
`gzim doctor` shows the executable path to help diagnose stale copies on PATH.

`gzim check <directory>` recursively checks `.gzim` files in sorted order, skips
symlink directories and generated/dependency trees, reports all failures, and
returns nonzero if any file fails or no source files are found.

## Ecosystem

### Projects and packages

Dependencies live in `gzim.toml` and can point to Git repositories or local
directories:

```sh
gzim add cool https://github.com/example/cool.git#v1.0.0
gzim add local ../my-local-package
gzim install
```

Packages are installed under `.gzim/packages/`. Git revisions are recorded in
`gzim.lock`, and take precedence over branch or tag names during installation.
Use `gzim install --locked` in CI to require a matching lockfile without changing it,
and `gzim update [name]` to explicitly refresh revisions. Local path dependencies
are copied from their current contents and are not pinned by content. Commit
`gzim.toml` and `gzim.lock`; keep `.gzim/` out of version control.

Read the [package guide](https://obliv1onis.github.io/Genzimnify/packages.html)
for the manifest format and import rules.

### Optional Python interoperability

Python libraries are available only through the explicit `py.` namespace:

```gzim
pull up py.math as pymath
outta py.json pull up dumps

yap(call up pymath.sqrt(81) yo)
yap(call up dumps({"ready": nocap}, sort_keys be nocap) yo)
```

The bridge supports positional and keyword arguments plus JSON-compatible value
conversion. NumPy scalars and arrays are converted through `item()` and
`tolist()`. Each bridge call is isolated; a program that never imports `py.*`
never starts or requires Python.

See [Python interoperability](https://obliv1onis.github.io/Genzimnify/python-interop.html)
for supported conversions and limitations.

### Source conversion

```sh
gzim convert main.gzim --to py       # creates main.py beside the source
gzim convert main.py --to gzim       # creates main.gzim beside the source
gzim convert main.py --to gzim -o converted.gzim
gzim convert main.gzim --to py --force
gzim convert main.py --to gzim --check  # validate without writing
gzim convert main.gzim --to py --source-map
```

Existing output files require `--force`; the source itself cannot be overwritten.
Conversion finishes and validates before replacing an output file. The new command
writes a single source file; add `--source-map` when exporting Python to also
write a `.py.gzmap` sidecar. The older `build` and `emit-python` commands were
removed in 2.0.4; use `convert --to py --source-map` instead.

Python import requires Python 3.8+ on `PATH` and parses the input without running
it. The parser is embedded in the native executable; there is no additional
package to install. Native execution and exporting Python do not require Python.

The reverse converter supports basic assignments, arithmetic, conditions, loops,
ordinary functions, collection literals, indexing, and selected builtin calls.
Unsupported syntax reports its source location instead of producing a partial
file. Imports, classes, decorators, annotations, async, comprehensions, f-strings,
chained comparisons, and advanced parameters are outside this first preview.
Comments and original formatting are not preserved. Conflicting variable names
are escaped with `_py_`; builtin names are mapped according to lexical scope.

This is a source migration aid, not full Python compatibility or a lossless
round trip. Generated programs use Genzimnify's native value and library semantics
(including 64-bit integers, byte-oriented text operations, and eager iteration).
See the [conversion reference](https://obliv1onis.github.io/Genzimnify/python-interop.html#source-conversion)
for the supported builtin forms and restrictions.

### Native standard library

The runtime includes `math`, `system`, `luck`, `clock`, `timing`, `json`,
`path`, `encoding`, and the `rizzgame` 2D game library, plus relative imports
of local `.gzim` modules. `rizzgame` uses a native raylib 5.5 shared library
bundled in graphics-enabled releases; it never starts Python. The
[standard-library reference](https://obliv1onis.github.io/Genzimnify/stdlib.html)
lists the available functions. See the
[rizzgame guide](https://obliv1onis.github.io/Genzimnify/rizzgame.html) for
window, input, drawing, camera, particle, animation, and audio examples.

### Make a game with rizzgame

```gzim
pull up rizzgame as rg
let screen be call up rg.display.pull_up([800, 450]) yo
let clock be call up rg.time.Clock() yo
let running be nocap
vibe running:
    for real event up in call up rg.event.catch_vibes() yo:
        vibecheck event.type == rg.QUIT: running be cap
    call up screen.glow_up([18, 22, 36]) yo
    call up rg.draw.flex_circle(screen, [92, 247, 224], [400, 225], 48) yo
    call up rg.display.show_off() yo
    call up clock.keep_up(60) yo
call up rg.dip_out() yo
```

A full [Neon Arena demo](examples/rizzgame/neon_arena.gzim) includes procedural
sprite animation, camera effects, particles, and frame pacing. Run it with
`gzim examples/rizzgame/neon_arena.gzim`; pass `--frames 120` for a bounded run.
The Gen Z names above have pygame-style aliases (`set_mode`, `flip`, `fill`,
`draw.circle`, etc.) for compatibility. See the [rizzgame guide](https://obliv1onis.github.io/Genzimnify/rizzgame.html)
for the full mapping. The graphics backend is built with `cmake -S native/rizzgame -B build/rizzgame`
followed by `cmake --build build/rizzgame --config Release` when building from source.

## Tooling

### Language server and Zed

`gzim-lsp` communicates over stdio and provides diagnostics, hover information,
completion, go-to-definition, and document symbols. Release archives include
the server alongside the runtime.

The repository also contains a Zed development extension under
[`zed-genzimnify/`](zed-genzimnify). Build `gzim-lsp`, place it on `PATH`, then
use **Zed: Install Dev Extension** and select that directory.

### Genzimnify Studio

[`studio/`](studio) contains a static, local-first browser IDE with diagnostics,
syntax highlighting, completion, examples, import/export, share links,
formatting, autosave, and a resizable console. Its dedicated rizzgame workspace
shows the terminal on the left and a live Canvas preview on the right. Ordinary
programs run in a background worker with a Stop button, a configurable time limit
(default 10 seconds, starting after runtime loading), and a 100,000-character
console limit. Expand **Program input** and enter one line per `yap back` call
before running; exhausted input raises EOF. Stopping a worker discards its Python
state and temporary files. Games use the cooperative Canvas adapter; choose
**None** for the time limit when playing longer games. Open the
[web Studio](https://obliv1onis.github.io/Genzimnify/studio/) or follow the
[Studio game tutorial](https://obliv1onis.github.io/Genzimnify/rizzgame-studio.html).
The browser preview uses a JavaScript transpiler and Pyodide; the installable
`gzim` runtime remains the authoritative native implementation. Run
`python3 scripts/sync-studio-pages.py` after editing Studio to update the
GitHub Pages copy in `docs/studio/`.

Rebuild the browser transpiler after changing the language core:

```sh
nim js -d:release --out:studio/transpiler.js src/genzimnify/web.nim
```

<details>
<summary><strong>Build from source and explore the architecture</strong></summary>

## Build from source

Requirements: Nim 2.0 or newer and Nimble.

```sh
git clone https://github.com/Obliv1onis/Genzimnify.git
cd Genzimnify
nimble build -d:release
./gzim doctor
```

The main implementation lives in `src/genzimnify/`:

| Component | Responsibility |
|---|---|
| `lexer.nim` | Tokens, indentation, comments, and multi-word syntax |
| `parser.nim` | Recursive-descent statements and Pratt expressions |
| `ast.nim` | Syntax tree node definitions |
| `semantic.nim` | Scope, binding, and control-flow validation |
| `runtime.nim` | Native values, calls, modules, and execution |
| `packages.nim` | Manifests, lockfiles, and dependency installation |
| `emit.nim` | Optional Python export backend |
| `lsp.nim` | Language Server Protocol implementation |
| `cli.nim` | Command-line interface |

The broader design is documented in [`Design_Doc.md`](Design_Doc.md).

</details>

## Tests

```sh
tests/run_tests.sh       # language, runtime, bridge, and package tests
tests/regression_test.sh # negative semantic cases
tests/lsp_test.sh        # end-to-end LSP protocol test
```

<details>
<summary><strong>Current limitations</strong></summary>

<br>

- Same-quote nesting inside `glow` strings is unsupported; use mixed quotes.
- Unparenthesized comparison chains are rejected; use explicit `both` expressions
  when combining comparisons.
- `timing` is currently cooperative and does not provide a full event loop.
- Running exported Python, Python-to-Genzimnify conversion, and `py.*` imports
  require Python; native execution and exporting Python do not.

</details>

### New in 2.0.6

- Exact integer powers and catchable int64 overflow errors.
- Runtime call stacks include function names and source files, including imported modules.
- Real native sleep, `clock.monotonic()`, and `math.isfinite/isnan/isinf`.
- `luck.shuffle(stack)` shuffles in place; `luck.sample(values, count)` samples without replacement and leaves its input unchanged.
- `gzim update [name]`, `gzim install --locked`, and dependency batches that preserve existing packages on a fetch failure.
- `gzim-lsp --help` and `gzim-lsp --version` for checking the installed editor server.
- Studio background execution, Stop, time limits, prefilled stdin, and bounded console output.
- LSP survives incomplete strings and clears diagnostics when a file closes; Python exports avoid helper name collisions; file `readline()` normalizes CRLF/CR line endings and retains newlines and returns empty text at EOF.

```gzim
pull up clock
pull up luck
pull up math
let started be clock.monotonic()
clock.sleep(0.01)
yap(clock.monotonic() - started)
let cards be [1, 2, 3, 4, 5]
luck.shuffle(cards)
yap(luck.sample(cards, 2))
yap(math.isfinite(3.14))
```

Native timing remains synchronous: `timing.sleep()` blocks, and async syntax
executes eagerly without a concurrent event loop. Python exports use asyncio.
Native integers remain signed int64; Python/Studio may represent larger integers.

### New in 2.0.5

```gzim
yap("no", "cap", glue="-", micdrop="!")
yap()
yap(call up ranked([3, 1, 2], uno_reverse=nocap) yo)
pull up luck
call up luck.manifest(42) yo
```

`glue` joins output values and `micdrop` controls the ending (defaults: a space
and a newline). `uno_reverse` takes `nocap` for descending order or `cap` for
ascending order. `luck.manifest(integer)` resets the random sequence for
repeatable runs within the same runtime; native and Python sequences can differ.
Unsupported or duplicate keyword arguments now raise errors.

## License

Genzimnify is available under the [MIT License](LICENSE).
