## Web glue for Genzimnify, compiled to JavaScript with `nim js`.
## Exposes a single global `compileGzim(source) -> json-string` used by the
## static site: transpiles .gzim to Python and reports cap (diagnostics).

import std/json
import errors, lexer, parser, semantic, emit

proc diagList(issues: seq[Issue]): seq[JsonNode] =
  for iss in issues:
    result.add %*{
      "line": iss.line,
      "col": iss.col,
      "message": iss.msg,
      "severity": 1,
    }

proc compileGzim*(source: cstring): cstring {.exportc.} =
  ## Transpile Genzimnify source to Python; never throws, returns a JSON
  ## envelope: {ok, code?, error?, line?, col?, diags: [{line, col, message}]}
  var resp: JsonNode
  try:
    let toks = lex($source)
    let (program, usedAny) = parseProgram(toks)
    let issues = checkProgram(program)
    if issues.len > 0:
      resp = %*{
        "ok": false,
        "error": "cap detected, the vibes below ain't it",
        "line": issues[0].line,
        "col": issues[0].col,
        "diags": diagList(issues),
      }
    else:
      let em = emitProgram(program, usedAny)
      resp = %*{"ok": true, "code": em.render(), "diags": diagList(issues)}
  except GzimError as e:
    let line = if e.line > 0: e.line else: 0
    let col = if e.col > 0: e.col else: 0
    resp = %*{
      "ok": false,
      "error": e.msg,
      "line": line,
      "col": col,
      "diags": [{"line": line, "col": col, "message": e.msg, "severity": 1}],
    }
  except CatchableError as e:
    resp = %*{
      "ok": false,
      "error": "something wild happened: " & e.msg,
      "diags": [],
    }
  ($resp).cstring
