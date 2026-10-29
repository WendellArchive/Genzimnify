## File conversion is opt-in; ordinary execution stays Python-free.
import std/[os, osproc, streams, strutils, json, tempfiles, syncio]
import errors, runtime, lexer, parser, semantic, emit

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

const PythonConverter = staticRead("python_to_gzim.py")

proc fromPython*(path: string): string =
  var executable = ""
  var args: seq[string]
  for candidate in ["python3", "python"]:
    executable = findExe(candidate)
    if executable != "": break
  when defined(windows):
    if executable == "":
      executable = findExe("py")
      if executable != "": args.add "-3"
  if executable == "":
    raise newGzimError("Python-to-Genzimnify conversion needs Python 3.8+ on PATH; native execution does not")
  args.add @["-I", "-X", "utf8", "-c", PythonConverter]
  let process = startProcess(executable, args = args, options = {poStdErrToStdOut})
  defer: process.close()
  process.inputStream.write($(%*{"path": absolutePath(path)}))
  process.inputStream.close()
  let output = process.outputStream.readAll()
  if process.waitForExit() != 0:
    raise newGzimError("Python converter failed (requires Python 3.8+): " & output.strip())
  let response = parseJson(output)
  if not response["ok"].getBool():
    raise newGzimError(response["error"].getStr())
  result = response["code"].getStr()
  try:
    discard parseChecked(result, path)
  except GzimError as error:
    let mapping = response["lines"]
    let sourceLine = if error.line > 0 and error.line <= mapping.len:
      mapping[error.line - 1].getInt() else: 1
    raise newGzimError(path & ":" & $sourceLine &
      ": conversion could not pass Genzimnify validation: " & error.msg)

proc checkDestination*(source, destination: string, force: bool) =
  if normalizedPath(absolutePath(source)) == normalizedPath(absolutePath(destination)) or
      (fileExists(destination) and sameFile(source, destination)):
    raise newGzimError("conversion cannot overwrite its source file")
  if dirExists(destination):
    raise newGzimError("output is a directory: " & destination)
  if symlinkExists(destination):
    raise newGzimError("conversion output cannot be a symbolic link: " & destination)
  if fileExists(destination) and not force:
    raise newGzimError("output already exists: " & destination & "; use --force to replace it")
  let parent = parentDir(absolutePath(destination))
  if not dirExists(parent):
    raise newGzimError("output directory does not exist: " & parent)

proc writeConversion*(source, destination, code: string, force: bool) =
  ## Stage the complete result beside its destination before replacing it.
  checkDestination(source, destination, force)
  let (file, temporary) = createTempFile(".gzim-convert-", ".tmp", parentDir(absolutePath(destination)))
  var opened = true
  defer:
    if opened: file.close()
    if fileExists(temporary): removeFile(temporary)
  file.write(code)
  file.close()
  opened = false
  checkDestination(source, destination, force)
  moveFile(temporary, destination)
