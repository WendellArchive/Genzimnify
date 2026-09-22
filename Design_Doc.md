# Genzimnify: Language Design Document

**Version:** 1.0  
**Target:** Python 3.10+  
**Implementation:** Nim  
**File Extension:** `.gzim`  
**Tagline:** Python semantics, Gen Z surface syntax. If it vibes, it compiles.

---

## 1. Overview

Genzimnify is a Turing-complete programming language that source-to-source transpiles to Python. It is written in Nim and uses Gen Z slang for all keywords, built-ins, and control flow. The language is designed to be expressive, memeable, and fully compatible with Python’s runtime and ecosystem.

A Genzimnify program is called a **vibe**. Running it is **vibing**. Errors are **cap**. Debugging is **checking the vibe**.

---

## 2. Lexical Structure

### 2.1 File Extension
- `.gzim`

### 2.2 Comments
- Single-line: `# ngl this is a comment`
- Multi-line: `#[[ this is a whole yap session ]]#`

### 2.3 Identifiers
- Same as Python: `[a-zA-Z_][a-zA-Z0-9_]*`
- Case-sensitive.
- Keywords are lowercase and reserved.

### 2.4 Keywords

| Genzimnify | Python | Purpose |
|---|---|---|
| `let` | — | Variable declaration |
| `be` | `=` | Assignment / binding |
| `lock` | `const` | Immutable declaration |
| `nocap` | `True` | Boolean true |
| `cap` | `False` | Boolean false |
| `ghost` | `None` | Null value |
| `both` | `and` | Logical AND |
| `either` | `or` | Logical OR |
| `aint` | `not` | Logical NOT |
| `same as` | `==` | Equality |
| `nah` | `!=` | Inequality |
| `literally` | `is` | Identity |
| `aint literally` | `is not` | Non-identity |
| `up in` | `in` | Membership |
| `aint up in` | `not in` | Non-membership |
| `vibecheck` | `if` | Conditional |
| `or` | `elif` | Else-if |
| `otherwise` | `else` | Else |
| `vibe` | `while` | While loop |
| `for real` | `for` | For loop |
| `dip` | `break` | Break loop |
| `next` | `continue` | Continue loop |
| `deadass` | `pass` | No-op |
| `cook` | `def` | Function definition |
| `send it` | `return` | Return value |
| `drop` | `yield` | Yield value |
| `call up` | — | Function call prefix |
| `yo` | — | Function call suffix |
| `clique` | `class` | Class definition |
| `new` | `__init__` | Constructor |
| `fam` | `self` | Self reference |
| `ancestor` | `super` | Superclass |
| `pull up` | `import` | Import module |
| `outta` | `from` | From import |
| `as` | `as` | Alias |
| `f_around` | `try` | Try block |
| `find_out` | `except` | Except block |
| `no_matter_what` | `finally` | Finally block |
| `throw shade` | `raise` | Raise exception |
| `roll with` | `with` | Context manager |
| `on timing` | `async` | Async definition |
| `wait up` | `await` | Await expression |
| `mini vibe` | `lambda` | Lambda expression |
| `worldwide` | `global` | Global scope |
| `localish` | `nonlocal` | Nonlocal scope |
| `cancel` | `del` | Delete |
| `on god` | `assert` | Assertion |
| `fit check` | `match` | Pattern matching |
| `fit` | `case` | Match case |
| `yap` | `print` | Print statement |
| `yap back` | `input` | Input statement |
| `fr` | — | Optional statement terminator |

### 2.5 Operators

Standard operators are used:

| Operator | Meaning |
|---|---|
| `+` | Addition |
| `-` | Subtraction |
| `*` | Multiplication |
| `/` | Division |
| `//` | Floor division |
| `%` | Modulo |
| `**` | Exponentiation |
| `==` | Equality (also `same as`) |
| `!=` | Inequality (also `nah`) |
| `<` | Less than |
| `>` | Greater than |
| `<=` | Less than or equal |
| `>=` | Greater than or equal |
| `and` | Logical AND (also `both`) |
| `or` | Logical OR (also `either`) |
| `not` | Logical NOT (also `aint`) |
| `in` | Membership (also `up in`) |
| `is` | Identity (also `literally`) |
| `is not` | Non-identity (also `aint literally`) |
| `=` | Assignment (also `be`) |
| `+=`, `-=`, `*=`, `/=` | Compound assignment (also `be+`, `be-`, etc.) |

### 2.6 Statement Termination

- Statements are terminated by a newline.
- `fr` is an optional explicit statement terminator. It can be used to end a statement on the same line or for emphasis.
- Multiple statements can share a line if separated by `fr`.

Example:
```gzim
let x be 5 fr
let y be 10
x be x + y fr
```

### 2.7 Blocks and Indentation

- A block is opened by a colon `:` at the end of a line.
- The block body is indented (spaces or tabs, consistent within a file).
- Dedentation closes the block.
- No `bet`/`fr` block delimiters are used.

Example:
```gzim
vibecheck x > 10:
    yap("big")
otherwise:
    yap("small")
```

---

## 3. Types and Values

Genzimnify is dynamically typed by default, like Python. Optional type hints are supported.

### 3.1 Primitive Types

| Genzimnify | Python | Description |
|---|---|---|
| `num` | `int` | Integer |
| `drip` | `float` | Floating-point |
| `text` | `str` | String |
| `truth` | `bool` | Boolean |
| `ghost` | `None` | Null |

### 3.2 Collection Types

| Genzimnify | Python | Description |
|---|---|---|
| `stack` | `list` | List |
| `map` | `dict` | Dictionary |
| `squad` | `set` | Set |
| `crew` | `tuple` | Tuple |

### 3.3 Type Hints

```gzim
let x be 5 as num

cook add(a as num, b as num) gives num:
    send it a + b fr
```

Type names can be combined:

| Genzimnify | Python |
|---|---|
| `num or text` | `Union[int, str]` |
| `num?` | `Optional[int]` |
| `stack[num]` | `List[int]` |
| `map[text, num]` | `Dict[str, int]` |
| `whatever` | `Any` |

---

## 4. Variables and Assignment

### 4.1 Declaration

```gzim
let x be 5
let name be "chat"
let score be 0
```

- `let` declares a new variable.
- `be` binds the value.
- `fr` is optional.

### 4.2 Reassignment

```gzim
x be 10
score be score + 1
```

### 4.3 Constants

```gzim
lock PI be 3.14159
```

Attempting to reassign a `lock` variable raises a compile-time error.

### 4.4 Compound Assignment

```gzim
x be+ 5   # x = x + 5
x be- 2   # x = x - 2
x be* 3   # x = x * 3
x be/ 4   # x = x / 4
```

---

## 5. Operators and Expressions

### 5.1 Arithmetic

```gzim
let a be 10 + 5
let b be 10 - 5
let c be 10 * 5
let d be 10 / 5
let e be 10 // 3
let f be 10 % 3
let g be 2 ** 8
```

### 5.2 Comparison

```gzim
x == y
x != y
x nah y   # same as x != y
x < y
x > y
x <= y
x >= y
x same as y  # same as x == y
```

### 5.3 Logical

```gzim
a both b   # a and b
a either b # a or b
aint a     # not a
```

### 5.4 Membership

```gzim
x up in stack
x aint up in stack
```

### 5.5 Identity

```gzim
x literally y
x aint literally y
```

### 5.6 Function Calls

Function calls use the `call up ... yo` syntax.

```gzim
call up add(4, 3) yo
call up obj.method(arg) yo
```

A function call is an expression. It can be used anywhere an expression is expected.

Example:
```gzim
yap(call up add(4, 3) yo)
```

### 5.7 Lambda

```gzim
let double be mini vibe(x): x * 2
```

### 5.8 Comprehensions

```gzim
let evens be [x for real x up in vibes(10) sus x % 2 == 0]
```

---

## 6. Control Flow

### 6.1 If / Elif / Else

```gzim
vibecheck x > 10:
    yap("yes it is bigger")
or x nah 6:
    yap("okay but x isn't 6 dough")
otherwise:
    yap("bro nvm at this point")
```

- `vibecheck` = `if`
- `or` = `elif`
- `otherwise` = `else`
- `nah` = `!=`
- Standard operators like `==`, `!=`, `<`, `>`, `<=`, `>=` are also valid.

### 6.2 While Loop

```gzim
vibe x < 10:
    x be x + 1
```

### 6.3 For Loop

```gzim
for real i up in vibes(1, 10):
    yap(i)
```

### 6.4 Break / Continue / Pass

```gzim
dip     # break
next    # continue
deadass # pass
```

---

## 7. Functions

### 7.1 Definition

```gzim
cook add(a, b):
    send it a + b fr
```

- `cook` = `def`
- `send it` = `return`
- `fr` is optional.

### 7.2 Default Arguments

```gzim
cook greet(name, greeting be "yo"):
    yap(greeting + " " + name)
```

### 7.3 Calling Functions

```gzim
yap(call up add(4, 3) yo)
```

- `call up` ... `yo` wraps the call.
- Built-in statements like `yap` do not use this syntax.

### 7.4 Generators

```gzim
cook countdown(n):
    vibe n > 0:
        drop n
        n be n - 1
```

### 7.5 Print and Input

```gzim
yap("Hello, world!")      # print
let name be yap back("What's your name? ")  # input with prompt
```

- `yap` is the print statement.
- `yap back` is the input statement.

---

## 8. Classes and Objects

### 8.1 Class Definition

```gzim
clique Dog:
    cook new(fam, name):
        fam.name be name

    cook speak(fam):
        yap(glow"{fam.name} says woof")
```

- `clique` = `class`
- `new` = `__init__`
- `fam` = `self`
- `glow"..."` = f-string

### 8.2 Inheritance

```gzim
clique Puppy(Dog):
    cook speak(fam):
        yap("tiny woof")
```

### 8.3 Super

```gzim
ancestor.new(fam, name)
```

---

## 9. Exception Handling

### 9.1 Try / Except / Finally

```gzim
f_around:
    # some code here
find_out:
    # some code here
```

- `f_around:` = `try:`
- `find_out:` = `except:` (catches all exceptions)

Specific exceptions:

```gzim
f_around:
    throw shade BadVibe("nah")
find_out BadVibe as e:
    yap("caught a bad vibe")
no_matter_what:
    yap("fr")
```

- `find_out BadVibe as e:` = `except BadVibe as e:`
- `no_matter_what:` = `finally:`

### 9.2 Raising Exceptions

```gzim
throw shade BadVibe("something went wrong")
```

---

## 10. Modules and Imports

### 10.1 Import

```gzim
pull up math
pull up math as m
```

- `pull up` = `import`

### 10.2 From Import

```gzim
outta math pull up sqrt
outta math pull up sqrt as root
outta math pull up all
```

- `outta` = `from`

---

## 11. Async and Concurrency

### 11.1 Async Functions

```gzim
on timing cook fetch():
    wait up timing.sleep(1)
    send it "done"
```

- `on timing` = `async`
- `wait up` = `await`

---

## 12. Pattern Matching

```gzim
fit check x:
    fit 1:
        yap("one")
    fit 2:
        yap("two")
    otherwise:
        yap("idk")
```

- `fit check` = `match`
- `fit` = `case`
- `otherwise` = default case

---

## 13. Context Managers

```gzim
roll with unlock("file.txt") as f:
    yap(f.read())
```

- `roll with` = `with`
- `unlock` = `open`

---

## 14. Standard Library and Built-ins

### 14.1 Built-in Statements

| Genzimnify | Python | Description |
|---|---|---|
| `yap(x)` | `print(x)` | Print |
| `yap back(prompt)` | `input(prompt)` | Input |
| `deadass` | `pass` | No-op |
| `dip` | `break` | Break |
| `next` | `continue` | Continue |
| `send it` | `return` | Return |
| `throw shade` | `raise` | Raise |

### 14.2 Built-in Functions

These are called using `call up ... yo`.

| Genzimnify | Python | Description |
|---|---|---|
| `how many(x)` | `len(x)` | Length |
| `vibes(n)` | `range(n)` | Range |
| `num(x)` | `int(x)` | To integer |
| `drip(x)` | `float(x)` | To float |
| `text(x)` | `str(x)` | To string |
| `truth(x)` | `bool(x)` | To boolean |
| `stack(x)` | `list(x)` | To list |
| `map(x)` | `dict(x)` | To dict |
| `squad(x)` | `set(x)` | To set |
| `crew(x)` | `tuple(x)` | To tuple |
| `vibe check(x)` | `type(x)` | Type |
| `add up(x)` | `sum(x)` | Sum |
| `least(x)` | `min(x)` | Minimum |
| `most(x)` | `max(x)` | Maximum |
| `positive(x)` | `abs(x)` | Absolute value |
| `ranked(x)` | `sorted(x)` | Sorted |
| `index up(x)` | `enumerate(x)` | Enumerate |
| `link(x, y)` | `zip(x, y)` | Zip |
| `unlock(x)` | `open(x)` | Open file |
| `round up(x)` | `round(x)` | Round |

Example:
```gzim
let length be call up how many(stack) yo
let numbers be call up vibes(10) yo
```

### 14.3 Standard Modules

| Genzimnify | Python |
|---|---|
| `luck` | `random` |
| `clock` | `time` |
| `system` | `os`, `sys` |
| `json` | `json` |
| `regex` | `re` |
| `stash` | `collections` |
| `loops` | `itertools` |
| `tools` | `functools` |
| `timing` | `asyncio` |
| `types` | `typing` |
| `paths` | `pathlib` |
| `spawn` | `subprocess` |
| `net` | `socket` |
| `web` | `http` |
| `db` | `sqlite3` |
| `vibecheck` | `unittest` |

### 14.4 Exception Types

| Genzimnify | Python |
|---|---|
| `L` | `Exception` |
| `BadVibe` | `ValueError` |
| `WrongType` | `TypeError` |
| `OutOfPocket` | `IndexError` |
| `Ghosted` | `KeyError` |
| `SplitByZero` | `ZeroDivisionError` |
| `NoPullUp` | `ImportError` |
| `CapDetected` | `AssertionError` |
| `StopTheCap` | `StopIteration` |

---

## 15. Grammar (EBNF)

```ebnf
program        := statement* EOF

statement      := varDecl | assignment | exprStmt | ifStmt | whileStmt
                | forStmt | funcDef | classDef | importStmt | tryStmt
                | returnStmt | breakStmt | continueStmt | passStmt
                | raiseStmt | withStmt | asyncFuncDef | matchStmt

varDecl        := "let" IDENT "be" expr ("fr")?
                | "lock" IDENT "be" expr ("fr")?

assignment     := IDENT "be" expr ("fr")?
                | IDENT ("be+" | "be-" | "be*" | "be/" | "be%") expr ("fr")?

exprStmt       := expr ("fr")?

ifStmt         := "vibecheck" expr ":" block
                  ("or" expr ":" block)*
                  ("otherwise" ":" block)?

whileStmt      := "vibe" expr ":" block

forStmt        := "for real" IDENT "up in" expr ":" block

funcDef        := "cook" IDENT "(" params? ")" ("gives" type)? ":" block

classDef       := "clique" IDENT ("(" IDENT ")")? ":" block

importStmt     := "pull up" IDENT ("as" IDENT)? ("fr")?
                | "outta" IDENT "pull up" (IDENT | "all") ("as" IDENT)? ("fr")?

tryStmt        := "f_around" ":" block
                  ("find_out" type? ("as" IDENT)? ":" block)*
                  ("otherwise" ":" block)?
                  ("no_matter_what" ":" block)?

returnStmt     := "send it" expr? ("fr")?
breakStmt      := "dip" ("fr")?
continueStmt   := "next" ("fr")?
passStmt       := "deadass" ("fr")?
raiseStmt      := "throw shade" expr ("fr")?
withStmt       := "roll with" expr ("as" IDENT)? ":" block

asyncFuncDef   := "on timing" "cook" IDENT "(" params? ")" ":" block

matchStmt      := "fit check" expr ":" block
                  ("fit" pattern ":" block)*
                  ("otherwise" ":" block)?

block          := INDENT statement* DEDENT

expr           := literal | IDENT | unary | binary | call | attribute
                | subscript | lambda | await | yield | comprehension

call           := "call up" expr "(" args? ")" "yo"

literal        := "nocap" | "cap" | "ghost" | NUMBER | STRING | fstring
                | list | tuple | dict | set

lambda         := "mini vibe" "(" params? ")" ":" expr

await          := "wait up" expr

yield          := "drop" expr?

comprehension  := "[" expr "for real" IDENT "up in" expr ("sus" expr)? "]"
```

---

## 16. Transpiler Architecture in Nim

### 16.1 Pipeline

1. **Lexer** — Converts `.gzim` source into a stream of tokens.
2. **Parser** — Recursive descent + Pratt parser for expressions. Produces an AST.
3. **AST** — Nodes for Program, Block, VarDecl, Assign, If, While, For, FuncDef, ClassDef, Import, Try, Return, Break, Continue, Pass, ExprStmt, Call, Binary, Unary, Literal, Identifier, Attribute, Subscript, Lambda, Await, Yield, With, Match.
4. **Semantic Analysis** — Scope checking, type hint validation, `fam` only in methods, `send it` only in functions, `dip`/`next` only in loops, `wait up` only in async.
5. **Python Emitter** — Maps Genzimnify constructs to Python. Tracks indentation, handles `:` and dedent, emits `.py`.
6. **Source Maps** — Maps generated Python lines back to `.gzim` lines for error reporting.

### 16.2 Suggested Nim Modules

- `lexer.nim`
- `token.nim`
- `ast.nim`
- `parser.nim`
- `semantic.nim`
- `emit_python.nim`
- `cli.nim`

Use Nim’s `std/strutils`, `std/tables`, `std/options`, `std/os`, `std/parseopt`. A Pratt parser is ideal for expression precedence.

### 16.3 Semantic Rules

- `let` declares a new variable.
- Reassignment without `let` is allowed only if the variable exists.
- `lock` variables cannot be reassigned.
- `send it` only inside `cook` or `mini vibe`.
- `dip` and `next` only inside loops.
- `fam` only inside `clique` methods.
- `wait up` only inside `on timing cook`.
- `drop` makes the function a generator.
- `fr` is optional and treated as a statement terminator.
- A colon `:` at the end of a line opens a block; indentation defines scope.

---

## 17. Tooling and Ecosystem

- **Compiler:** `gzimc` / `genzimnify`
- **CLI:**
  - `gzimc run file.gzim`
  - `gzimc build file.gzim` → `file.py`
  - `gzimc check file.gzim`
  - `gzimc repl`
  - `gzimc init`
- **Formatter:** `gzimfmt`
- **Linter:** `gzimlint`
- **Language Server:** `gzim-lsp`
- **Package Manager:** `gzimble`
  - Manifest: `gzimble.toml` or `vibes.toml`
  - Can wrap PyPI since target is Python.
- **Testing Framework:** `vibecheck`

---

## 18. Examples

### 18.1 FizzBuzz

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

### 18.2 Function

```gzim
cook add(a, b):
    send it a + b fr

yap(call up add(4, 3) yo)
```

### 18.3 Class

```gzim
clique Dog:
    cook new(fam, name):
        fam.name be name

    cook speak(fam):
        yap(glow"{fam.name} says woof")

let d be call up Dog("Rex") yo
call up d.speak() yo
```

### 18.4 Try / Catch

```gzim
f_around:
    let x be 1 / 0
find_out SplitByZero as e:
    yap("can't divide by zero, bestie")
no_matter_what:
    yap("we move")
```

### 18.5 If / Elif / Else

```gzim
vibecheck x > 10:
    yap("yes it is bigger")
or x nah 6:
    yap("okay but x isn't 6 dough")
otherwise:
    yap("bro nvm at this point")
```

---

## 19. Turing Completeness

Genzimnify is Turing complete because it has:

- Mutable variables: `let x be ...`, `x be ...`
- Unbounded integer arithmetic: `+`, `-`, `*`, `//`, `%`, `**`
- Conditional branching: `vibecheck`, `or`, `otherwise`
- Unbounded loops: `vibe`, `for real`
- Functions and recursion: `cook`, `send it`
- Data structures: lists, dicts, sets, tuples
- Exceptions, async, generators, classes

Since it transpiles directly to Python and preserves these constructs, it inherits Python’s Turing completeness.

---

## 20. Future Work

1. Finalize keyword list and reserve words.
2. Write the formal grammar.
3. Build the lexer in Nim.
4. Build the Pratt parser and AST.
5. Implement the Python emitter with indentation tracking.
6. Add semantic checks and slang error messages.
7. Build CLI, formatter, and REPL.
8. Create a test suite of `.gzim` programs and expected `.py` output.
9. Write docs and examples.
10. Ship `gzimble` and the first package.

---

**Genzimnify** — because why write Python when you can vibe?
