## gzim, the native Genzimnify CLI.
## Native execution, project tools, and source conversion.

import std/[os, strutils, syncio, tables, algorithm]
import runtime, errors, packages, version
import convert, updates

const Version* = GenzimnifyVersion

proc failHard(msg: string): void =
  stderr.writeLine("cap! " & msg)
  quit(1)

proc requireNoArgs(command: string, args: seq[string]) =
  if args.len > 0:
    failHard(command & " doesn't take arguments")

# ------------------------------------------------------------------ commands

proc cmdRun(path: string, extraArgs: seq[string]) =
  if not fileExists(path):
    failHard("no file called " & path & ", that's ghost")
  quit(runSource(readFile(path), path, extraArgs))

proc checkFile(path: string): bool =
  try:
    discard parseChecked(readFile(path), path)
    echo "ok: " & path
    result = true
  except GzimError as error:
    if error.msg.startsWith(path & ":"):
      stderr.writeLine(error.msg)
    else:
      stderr.writeLine(path & ":" & $error.line & ":" & $error.col & ": " & error.msg)
  except CatchableError as error:
    stderr.writeLine(path & ": " & error.msg)

proc collectSources(dir: string, files: var seq[string]) =
  # Do not follow directory symlinks or inspect generated/dependency trees.
  for kind, path in walkDir(dir, checkDir = true):
    case kind
    of pcFile:
      if path.endsWith(".gzim"): files.add path
    of pcDir:
      if extractFilename(path) notin [".git", ".gzim", "build", "dist", "target", "node_modules", ".venv", "venv"]:
        collectSources(path, files)
    else: discard

proc cmdCheck(path: string) =
  var files: seq[string]
  if dirExists(path):
    collectSources(path, files)
    files.sort()
    if files.len == 0: failHard("no .gzim files found in " & path)
  elif fileExists(path): files.add path
  else: failHard("no file or directory called " & path)
  var failed = 0
  for file in files:
    if not checkFile(file): inc failed
  echo $files.len & " checked, " & $failed & " failed"
  if failed > 0: quit(1)

proc cmdConvert(args: seq[string]) =
  const usage = "usage: gzim convert <file> --to <py|gzim> [-o <output>] [--force] [--check] [--source-map]"
  if args.len == 0: failHard(usage)
  if args == @["--help"] or args == @["-h"]:
    echo usage
    return
  let source = args[0]
  var target, destination: string
  var force, checkOnly, sourceMap = false
  var i = 1
  while i < args.len:
    case args[i]
    of "--to", "-o", "--output":
      let option = args[i]
      inc i
      if i >= args.len or args[i].startsWith("-"): failHard("missing value for " & option & "\n" & usage)
      if option == "--to":
        if target != "": failHard("--to may only be supplied once")
        target = args[i]
      else:
        if destination != "": failHard("output may only be supplied once")
        destination = args[i]
    of "--force":
      force = true
    of "--check":
      checkOnly = true
    of "--source-map":
      sourceMap = true
    else:
      failHard("unknown convert argument: " & args[i] & "\n" & usage)
    inc i
  if target notin ["py", "gzim"]: failHard("--to must be py or gzim\n" & usage)
  if checkOnly and (force or destination != "" or sourceMap):
    failHard("--check cannot be combined with --force, --output, or --source-map")
  if sourceMap and target != "py": failHard("--source-map requires --to py")
  let parts = splitFile(source)
  let expected = if target == "py": ".gzim" else: ".py"
  if parts.ext != expected: failHard("conversion to " & target & " requires a " & expected & " source")
  if not fileExists(source): failHard("no file called " & source)
  if destination == "": destination = parts.dir / (parts.name & "." & target)
  try:
    if not checkOnly:
      checkDestination(source, destination, force)
      if sourceMap: checkDestination(source, destination & ".gzmap", force)
    var code, maps: string
    if target == "py":
      (code, maps) = compileSource(readFile(source), source)
    else:
      code = fromPython(source)
    if checkOnly:
      echo "conversion check passed: " & source & " -> " & target
      return
    writeConversion(source, destination, code, force)
    if sourceMap: writeConversion(source, destination & ".gzmap", maps, force)
    echo "converted " & source & " -> " & destination
  except CatchableError as error:
    failHard(error.msg)

const InitSample = """
# main.gzim, welcome to the vibe
cook greet(name, greeting be "hey"):
    send it glow"{greeting} {name}!" fr

yap(call up greet("world") yo)
"""

proc cmdInit() =
  if fileExists("main.gzim"):
    echo "main.gzim already exists, it's already vibing"
  else:
    writeFile("main.gzim", InitSample)
    echo "dropped main.gzim, let's get this bread"
  initManifest(getCurrentDir())
  echo "project manifest: gzim.toml"

proc cmdInstall(locked = false, update = false, name = "") =
  let count = installDependencies(getCurrentDir(), locked, update, name)
  echo $count & " packages ready fr"

proc cmdAdd(rest: seq[string]) =
  if rest.len != 2: failHard("add needs a name and source: gzim add <name> <git-url-or-path>")
  addDependency(getCurrentDir(), rest[0], rest[1])
  echo "added " & rest[0] & " fr"

proc cmdRemove(rest: seq[string]) =
  if rest.len != 1: failHard("remove needs a package name: gzim remove <name>")
  removeDependency(getCurrentDir(), rest[0])
  echo "removed " & rest[0] & " fr"

proc cmdPackages() =
  let manifest = loadManifest(getCurrentDir())
  if manifest.dependencies.len == 0: echo "no packages yet"
  for name, source in manifest.dependencies: echo name & "  " & source

proc cmdRepl() =
  echo "gzim repl " & Version & " native runtime, blank line to run, ctrl-d to dip"
  let session = newReplSession("<repl>")
  defer: session.closeReplSession()
  var chunk: seq[string] = @[]
  var line: string
  while true:
    stdout.write(if chunk.len > 0: "...> " else: "vibe> ")
    flushFile(stdout)
    if not stdin.readLine(line):
      break
    if line.strip() == "":
      if chunk.len == 0:
        continue
      let src = chunk.join("\n")
      try:
        discard session.runReplChunk(src)
      except GzimError as e:
        echo "cap! " & e.msg
      chunk.setLen(0)
    else:
      chunk.add line

proc showHelp() =
  echo """
gzim, the native Genzimnify runtime. Gen Z syntax, zero Python required.

usage:
  gzim <file.gzim> [args]       run a vibe directly
  gzim run <file.gzim> [args]   same thing, spelled out
  gzim check <file|directory>   check source files without running
  gzim eval <code> [args]       run an inline program
  gzim repl                     start the native vibe loop
  gzim init                     drop a starter main.gzim
  gzim add <name> <source>      add a Git or local-path dependency
  gzim install [--locked]       restore dependencies; optionally require the lock
  gzim update [name]            refresh one or all dependency revisions
  gzim remove <name>            remove a dependency
  gzim packages                 list project dependencies
  gzim doctor                   show runtime and platform information
  gzim convert <file> --to <py|gzim> [-o <output>] [--force] [--check] [--source-map]
                               convert source files (Python import: preview)
  gzim --version [--offline]   show version and check for updates
  gzim help                     this menu

a Genzimnify program is called a vibe. running it is vibing.
errors are cap. debugging is checking the vibe.
"""

proc cmdDoctor() =
  echo "gzim " & Version
  echo "runtime: native Nim (Python-free)"
  echo "platform: " & hostOS & "/" & hostCPU
  echo "executable: " & getAppFilename()
  echo "project: " & getCurrentDir()
  var python = findExe("python3")
  if python == "": python = findExe("python")
  when defined(windows):
    if python == "": python = findExe("py")
  echo "Python (optional): " & (if python == "": "not found" else: python)

proc dispatch() =
  let params = commandLineParams()
  if params.len == 0:
    showHelp()
    quit(0)

  let cmd = params[0]
  let rest = params[1 .. ^1]

  case cmd
  of "convert":
    cmdConvert(rest)
  of "run":
    if rest.len == 0:
      failHard("run needs a file, gzim run <file.gzim>")
    cmdRun(rest[0], rest[1 .. ^1])
  of "build", "emit-python":
    failHard(cmd & " was removed; use gzim convert <file.gzim> --to py --source-map")
  of "eval":
    if rest.len == 0: failHard("usage: gzim eval <code> [args]")
    quit(runSource(rest[0], "<eval>", rest[1 .. ^1]))
  of "check":
    if rest.len != 1:
      failHard("usage: gzim check <file|directory>")
    cmdCheck(rest[0])
  of "repl":
    requireNoArgs("repl", rest)
    cmdRepl()
  of "init":
    requireNoArgs("init", rest)
    cmdInit()
  of "add":
    cmdAdd(rest)
  of "install":
    if rest.len > 0 and rest != @["--locked"]: failHard("usage: gzim install [--locked]")
    cmdInstall(locked = rest.len > 0)
  of "update":
    if rest.len > 1 or (rest.len == 1 and rest[0].startsWith("-")):
      failHard("usage: gzim update [name]")
    cmdInstall(update = true, name = if rest.len == 1: rest[0] else: "")
  of "remove":
    cmdRemove(rest)
  of "packages":
    requireNoArgs("packages", rest)
    cmdPackages()
  of "doctor":
    requireNoArgs("doctor", rest)
    cmdDoctor()
  of "--version", "-v":
    if rest.len > 0 and rest != @["--offline"]:
      failHard("usage: gzim --version [--offline]")
    echo "gzim " & Version
    flushFile(stdout)
    if rest.len == 0: showUpdateNotice()
  of "help", "--help", "-h":
    requireNoArgs("help", rest)
    showHelp()
  else:
    if cmd.endsWith(".gzim"):
      cmdRun(cmd, rest)
    else:
      failHard("unknown command: " & cmd & "; run gzim help")

proc main*() =
  # Give filesystem and parsing failures the same CLI exit behavior.
  try:
    dispatch()
  except CatchableError as error:
    failHard(error.msg)
