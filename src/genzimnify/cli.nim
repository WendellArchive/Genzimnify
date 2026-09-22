## gzimc — the Genzimnify compiler CLI.
## run / build / check / repl / init.

import std/[os, strutils, syncio, sequtils]
import lexer, parser, semantic, emit, errors

const Version* = "1.0"

# ------------------------------------------------------------------ compile

proc compileSource*(src: string, filename: string): tuple[code: string, maps: string] =
  let toks = lex(src)
  let parsed = parseProgram(toks)
  let issues = checkProgram(parsed.program)
  if issues.len > 0:
    var msg = ""
    for iss in issues:
      msg.add filename & ":" & $iss.line & ":" & $iss.col & ": cap: " & iss.msg & "\n"
    raise newGzimError(msg.strip(), issues[0].line, issues[0].col)
  let em = emitProgram(parsed.program, parsed.usedAny)
  result = (em.render(), em.renderMaps())

proc failHard(msg: string): void =
  stderr.writeLine("cap! " & msg)
  quit(1)

proc compileFile(path: string): tuple[code: string, maps: string] =
  if not fileExists(path):
    failHard("no file called " & path & " — that's ghost")
  let src = readFile(path)
  try:
    result = compileSource(src, path)
  except GzimError as e:
    failHard(e.msg)

# ------------------------------------------------------------------ commands

proc cmdRun(path: string, extraArgs: seq[string]) =
  let (code, _) = compileFile(path)
  let base = splitFile(path).name
  let pyPath = getTempDir() / (base & ".gzimrun.py")
  writeFile(pyPath, code)
  let args = extraArgs.mapIt(quoteShell(it)).join(" ")
  let rc = execShellCmd("python3 " & quoteShell(pyPath) &
                        (if args.len > 0: " " & args else: ""))
  quit(rc)

proc cmdBuild(path: string) =
  let (code, maps) = compileFile(path)
  let outPath = splitFile(path).dir / (splitFile(path).name & ".py")
  writeFile(outPath, code)
  writeFile(outPath & ".gzmap", maps)
  echo "cooked " & outPath & " — go vibe"

proc cmdCheck(path: string) =
  discard compileFile(path)
  echo "no cap — " & path & " passes the vibecheck fr"

const InitSample = """
# main.gzim — welcome to the vibe
cook greet(name, greeting be "hey"):
    send it glow"{greeting} {name}!" fr

yap(call up greet("world") yo)
"""

proc cmdInit() =
  if fileExists("main.gzim"):
    echo "main.gzim already exists — it's already vibing"
    return
  writeFile("main.gzim", InitSample)
  echo "dropped main.gzim — let's get this bread"

proc cmdRepl() =
  echo "gzimc repl " & Version & " — type your vibes, blank line to run, ctrl-d to dip"
  var session: seq[string] = @[]
  var line: string
  while true:
    stdout.write(if session.len > 0: "...> " else: "vibe> ")
    flushFile(stdout)
    if not stdin.readLine(line):
      break
    if line.strip() == "":
      if session.len == 0:
        continue
      let snapshot = session.len - 1
      let src = session.join("\n")
      var code: string
      try:
        let res = compileSource(src, "<repl>")
        code = res.code
      except GzimError as e:
        echo "cap! " & e.msg
        session.setLen(snapshot)
        continue
      let tmp = getTempDir() / "gzim_repl_run.py"
      writeFile(tmp, code)
      discard execShellCmd("python3 " & quoteShell(tmp))
    else:
      session.add line

proc showHelp() =
  echo """
gzimc — the Genzimnify compiler. Python in the streets, Gen Z in the sheets.

usage:
  gzimc run <file.gzim>      transpile + run it (no cap)
  gzimc build <file.gzim>    transpile to <file>.py (+ <file>.py.gzmap)
  gzimc check <file.gzim>    parse + vibecheck (semantic analysis) only
  gzimc repl                 start the vibe loop
  gzimc init                 drop a starter main.gzim
  gzimc help                 this menu

a Genzimnify program is called a vibe. running it is vibing.
errors are cap. debugging is checking the vibe.
"""

proc main*() =
  let params = commandLineParams()
  if params.len == 0:
    showHelp()
    quit(0)

  var cmd: string
  var rest: seq[string]
  if params[0] in ["run", "build", "check", "repl", "init", "help", "--help", "-h",
                   "--version", "-v"]:
    cmd = params[0]
    rest = params[1 .. ^1]
  elif params[0].endsWith(".gzim"):
    cmd = "run"
    rest = params
  else:
    showHelp()
    quit(1)

  case cmd
  of "run":
    if rest.len == 0:
      failHard("run needs a file — gzimc run <file.gzim>")
    cmdRun(rest[0], rest[1 .. ^1])
  of "build":
    if rest.len == 0:
      failHard("build needs a file — gzimc build <file.gzim>")
    cmdBuild(rest[0])
  of "check":
    if rest.len == 0:
      failHard("check needs a file — gzimc check <file.gzim>")
    cmdCheck(rest[0])
  of "repl":
    cmdRepl()
  of "init":
    cmdInit()
  of "--version", "-v":
    echo "gzimc " & Version
  else:
    showHelp()
    quit(0)
