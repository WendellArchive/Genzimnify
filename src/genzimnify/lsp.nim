## gzim-lsp — Language Server Protocol server for Genzimnify.
## Speaks JSON-RPC over stdio. Diagnostics, hover, go-to-definition,
## completion and document symbols. Errors are cap; we report them politely.

import std/[json, strutils, tables, options, strformat, sequtils]
import lexer, token, parser, semantic, ast, errors

type
  Doc = object
    text: string
    version: JsonNode
    toks: seq[Token]
    program: seq[Stmt]

var docs: Table[string, Doc]

# ------------------------------------------------------------------ json-rpc

proc readMessage(): Option[JsonNode] =
  var contentLength = 0
  while true:
    var line: string
    if not stdin.readLine(line):
      return none(JsonNode)  # EOF
    if line == "\r" or line == "":
      break
    let i = line.find(':')
    if i > 0:
      let key = line[0 ..< i].toLowerAscii()
      let val = line[(i + 1) .. ^1].strip()
      if key == "content-length":
        contentLength = val.parseInt()
  if contentLength == 0:
    return none(JsonNode)
  var buf = newString(contentLength)
  let got = stdin.readBuffer(addr buf[0], contentLength)
  buf.setLen(got)
  try:
    some(parseJson(buf))
  except CatchableError:
    none(JsonNode)

proc sendMessage(j: JsonNode) =
  let s = $j
  stdout.write("Content-Length: " & $s.len & "\r\n\r\n" & s)
  flushFile(stdout)

proc respond(id: JsonNode, result: JsonNode) =
  sendMessage(%*{"jsonrpc": "2.0", "id": id, "result": result})

proc notify(meth: string, params: JsonNode) =
  sendMessage(%*{"jsonrpc": "2.0", "method": meth, "params": params})

proc nullResponse(id: JsonNode) =
  sendMessage(%*{"jsonrpc": "2.0", "id": id, "result": newJNull()})

# ------------------------------------------------------------------ positions

type
  Pos = tuple[line: int, char: int]  # 0-based

proc lspPos(p: Pos): JsonNode =
  %*{"line": p.line, "character": p.char}

proc lspRange(startP, endP: Pos): JsonNode =
  %*{"start": lspPos(startP), "end": lspPos(endP)}

# ------------------------------------------------------------------ analysis

proc analyze(text: string): Doc =
  result = Doc(text: text)
  result.toks = lexer.lex(text)
  try:
    let (program, _) = parseProgram(result.toks)
    result.program = program
  except GzimError:
    discard

proc diagnosticsFor(text: string): seq[JsonNode] =
  var issues: seq[Issue]
  try:
    let toks = lex(text)
    let (program, _) = parseProgram(toks)
    issues = checkProgram(program)
    for iss in issues:
      result.add %*{
        "range": lspRange((iss.line - 1, iss.col), (iss.line - 1, iss.col + 1)),
        "severity": 1,
        "source": "gzim-lsp",
        "message": iss.msg,
      }
  except GzimError as e:
    let line = if e.line > 0: e.line - 1 else: 0
    let col = if e.col >= 0: e.col else: 0
    result.add %*{
      "range": lspRange((line, col), (line, col + 1)),
      "severity": 1,
      "source": "gzim-lsp",
      "message": e.msg,
    }

proc publishDiagnostics(uri: string, doc: Doc) =
  notify("textDocument/publishDiagnostics", %*{
    "uri": uri,
    "diagnostics": diagnosticsFor(doc.text),
  })

# ------------------------------------------------------------------ hover

const KEYWORD_DOCS: Table[string, string] = {
  "let": "Variable declaration (`x` becomes bindable).",
  "lock": "Immutable declaration — can't be rebound, fr.",
  "be": "`=` — assignment / binding.",
  "be+": "`+=` — compound add-assign.", "be-": "`-=`", "be*": "`*=`",
  "be/": "`/=`", "be//": "`//=`", "be%": "`%=`", "be**": "`**=`",
  "nocap": "`True`.", "cap": "`False`.", "ghost": "`None`.",
  "both": "`and`.", "either": "`or`.", "aint": "`not`.",
  "same as": "`==` — equality, no cap.",
  "nah": "`!=` — inequality.",
  "literally": "`is` — identity check.",
  "aint literally": "`is not`.",
  "up in": "`in` — membership.", "aint up in": "`not in`.",
  "vibecheck": "`if` — run the check.",
  "or": "`elif` (after vibecheck) or `or` (boolean).",
  "otherwise": "`else`.",
  "vibe": "`while` — keep it going.",
  "for real": "`for` — for real this time.", "up in": "`in`.",
  "dip": "`break` — leave the loop.", "next": "`continue` — skip one.",
  "deadass": "`pass` — do nothing, deadass.",
  "cook": "`def` — cook something up.",
  "send it": "`return` — send it back.",
  "drop": "`yield` — drop a value (makes a generator).",
  "call up": "Function call prefix — pairs with `yo`.",
  "yo": "Function call suffix — pairs with `call up`.",
  "clique": "`class` — roll with your clique.",
  "new": "`__init__` — the constructor glow-up.",
  "fam": "`self` — your fam.",
  "ancestor": "`super` — respect the ancestors.",
  "pull up": "`import` — pull up to the module.",
  "outta": "`from` — outta a module.",
  "as": "`as` — alias / type hint.",
  "f_around": "`try` — f around and find out.",
  "find_out": "`except` — find out what happens.",
  "no_matter_what": "`finally` — no matter what.",
  "throw shade": "`raise` — throw shade at the stack.",
  "roll with": "`with` — roll with a context manager.",
  "on timing": "`async` — on timing, not on target.",
  "wait up": "`await` — wait up for the future.",
  "mini vibe": "`lambda` — a tiny vibe.",
  "worldwide": "`global` — worldwide scope.",
  "localish": "`nonlocal` — kinda local.",
  "cancel": "`del` — cancel the variable.",
  "on god": "`assert` — on god this is true.",
  "fit check": "`match` — fit check the value.",
  "fit": "`case` — one fit per pattern.",
  "yap": "`print` — yap about it.",
  "yap back": "`input` — yap back at the user.",
  "fr": "Statement terminator (optional, for emphasis).",
  "sus": "`if` filter in comprehensions.",
  "gives": "Return type hint.",
  "glow": "f-string prefix — `glow\"{x}\"`.",
  "stack": "list — a stack of things.",
  "map": "dict — the map of the vibes.",
  "squad": "set — the squad.",
  "crew": "tuple — roll as a crew.",
  "num": "int type / int() builtin.",
  "drip": "float type / float() builtin.",
  "text": "str type / str() builtin.",
  "truth": "bool type / bool() builtin.",
  "vibes": "`range` — the vibes of iteration.",
  "how many": "`len` — how many are in it.",
  "add up": "`sum` — add it all up.",
  "least": "`min`.", "most": "`max`.", "positive": "`abs`.",
  "ranked": "`sorted` — put them on rank.",
  "index up": "`enumerate`.", "link": "`zip` — link up two squads.",
  "unlock": "`open` — unlock the file.",
  "round up": "`round`.",
  "vibe check": "`type` — vibe check the type.",
  "luck": "`random` module.", "clock": "`time` module.",
  "system": "`os`/`sys` modules.", "timing": "`asyncio` module.",
  "stash": "`collections`.", "loops": "`itertools`.", "tools": "`functools`.",
  "json": "`json`.", "regex": "`re`.", "paths": "`pathlib`.",
  "spawn": "`subprocess`.", "net": "`socket`.", "web": "`http`.",
  "db": "`sqlite3`.", "vibecheck": "`unittest` (module).",
  "L": "`Exception`.", "BadVibe": "`ValueError`.",
  "WrongType": "`TypeError`.", "OutOfPocket": "`IndexError`.",
  "Ghosted": "`KeyError`.", "SplitByZero": "`ZeroDivisionError`.",
  "NoPullUp": "`ImportError`.", "CapDetected": "`AssertionError`.",
  "StopTheCap": "`StopIteration`.",
}.toTable

type
  DeclKind = enum dkVariable, dkFunction, dkClass, dkParam
  Decl = object
    name: string
    kind: DeclKind
    line, col: int
    detail: string

proc walkExprDecls(e: Expr, out_decls: var seq[Decl]) =
  if e == nil:
    return
  case e.kind
  of ekFStr:
    for part in e.parts:
      if part.isExpr:
        walkExprDecls(part.ex, out_decls)
  of ekList, ekSet, ekTuple:
    for item in e.items:
      walkExprDecls(item, out_decls)
  of ekDict:
    for k in e.dkeys: walkExprDecls(k, out_decls)
    for v in e.dvals: walkExprDecls(v, out_decls)
  of ekUnary: walkExprDecls(e.uoperand, out_decls)
  of ekBinary: walkExprDecls(e.blhs, out_decls); walkExprDecls(e.brhs, out_decls)
  of ekCall:
    walkExprDecls(e.callee, out_decls)
    for a in e.cargs: walkExprDecls(a, out_decls)
    for kw in e.ckwargs: walkExprDecls(kw.val, out_decls)
  of ekAttr: walkExprDecls(e.aobj, out_decls)
  of ekSub: walkExprDecls(e.sobj, out_decls); walkExprDecls(e.sidx, out_decls)
  of ekSlice:
    walkExprDecls(e.ssliceObj, out_decls)
    if e.slo != nil: walkExprDecls(e.slo, out_decls)
    if e.shi != nil: walkExprDecls(e.shi, out_decls)
    if e.sstep != nil: walkExprDecls(e.sstep, out_decls)
  else:
    discard

proc collectDecls(program: seq[Stmt]): seq[Decl] =
  var out_decls: seq[Decl] = @[]
  proc walkStmts(stmts: seq[Stmt]) =
    ## appends to out_decls
    for s in stmts:
      case s.kind
      of skVarDecl:
        out_decls.add Decl(name: s.vname, kind: dkVariable, line: s.line, col: s.col,
                        detail: (if s.annot != "": s.annot else: ""))
      of skFuncDef:
        out_decls.add Decl(name: s.fname, kind: dkFunction, line: s.line, col: s.col,
                        detail: "(" & s.fparams.mapIt(it.name).join(", ") & ")")
        for prm in s.fparams:
          if prm.name != "":
            out_decls.add Decl(name: prm.name, kind: dkParam, line: s.line, col: s.col,
                            detail: (if prm.annot != "": prm.annot else: ""))
        walkStmts(s.fndefBody)
      of skClassDef:
        out_decls.add Decl(name: s.cname, kind: dkClass, line: s.line, col: s.col)
        walkStmts(s.cbody)
      of skFor:
        for t in s.ftargets:
          out_decls.add Decl(name: t, kind: dkVariable, line: s.line, col: s.col)
        walkExprDecls(s.fiter, out_decls)
        walkStmts(s.fbody)
      of skIf:
        for cl in s.clauses:
          walkExprDecls(cl.cond, out_decls)
          walkStmts(cl.body)
        walkStmts(s.elseBody)
      of skWhile:
        walkExprDecls(s.wcond, out_decls)
        walkStmts(s.wbody)
      of skExpr:
        walkExprDecls(s.e, out_decls)
      of skAssign:
        walkExprDecls(s.target, out_decls)
        walkExprDecls(s.value, out_decls)
      of skReturn:
        if s.re != nil: walkExprDecls(s.re, out_decls)
      of skRaise:
        if s.rae != nil: walkExprDecls(s.rae, out_decls)
      of skTry:
        walkStmts(s.tbody)
        for h in s.handlers:
          if h.etype != nil: walkExprDecls(h.etype, out_decls)
          if h.alias != "":
            out_decls.add Decl(name: h.alias, kind: dkVariable, line: s.line, col: s.col)
          walkStmts(h.body)
        walkStmts(s.orelse)
        walkStmts(s.finallyB)
      of skWith:
        for item in s.witems:
          walkExprDecls(item.ctx, out_decls)
          if item.alias != "":
            out_decls.add Decl(name: item.alias, kind: dkVariable, line: s.line, col: s.col)
        walkStmts(s.withBody)
      of skMatch:
        walkExprDecls(s.msubject, out_decls)
        for mc in s.mcases:
          walkStmts(mc.body)
        walkStmts(s.mdefault)
      of skDelete:
        for t in s.dtargets: walkExprDecls(t, out_decls)
      of skAssert:
        walkExprDecls(s.acond, out_decls)
        if s.amsg != nil: walkExprDecls(s.amsg, out_decls)
      of skYield:
        if s.ye != nil: walkExprDecls(s.ye, out_decls)
      of skImport:
        out_decls.add Decl(name: (if s.ialias != "": s.ialias else: s.imod),
                        kind: dkVariable, line: s.line, col: s.col, detail: "module")
      of skFromImport:
        for n in s.fnames:
          if n.nm != "*":
            out_decls.add Decl(name: (if n.alias != "": n.alias else: n.nm),
                            kind: dkVariable, line: s.line, col: s.col, detail: "import")
      of skBreak, skContinue, skPass, skGlobal, skNonlocal:
        discard

  walkStmts(program)
  out_decls

proc findDecl(decls: seq[Decl], name: string): Option[Decl] =
  for d in decls:
    if d.name == name:
      return some(d)
  none(Decl)

proc tokenAt(toks: seq[Token], line, charPos: int): Option[Token] =
  for t in toks:
    if t.line - 1 == line and t.text.len > 0 and
        charPos >= t.col and charPos < t.col + t.text.len:
      return some(t)
  none(Token)

proc wordTokenAt(toks: seq[Token], line, charPos: int): Option[Token] =
  let t = tokenAt(toks, line, charPos)
  if t.isSome and t.get.kind in {tIdent, tFam, tAncestor}:
    return t
  none(Token)

proc hover(uri: string, pos: Pos): JsonNode =
  let doc = docs[uri]
  let t = tokenAt(doc.toks, pos.line, pos.char)
  if t.isNone:
    return newJNull()
  let tok = t.get
  var md = ""
  case tok.kind
  of tIdent:
    let decls = collectDecls(doc.program)
    let d = findDecl(decls, tok.text)
    if d.isSome:
      let kindLabel = case d.get.kind
        of dkVariable: "variable"
        of dkFunction: "cook"
        of dkClass: "clique"
        of dkParam: "param"
      md = &"**{d.get.name}** — *{kindLabel}*" & (if d.get.detail != "": " — " & d.get.detail else: "") &
           "\n\nno cap, declared at line " & $d.get.line
    elif KEYWORD_DOCS.hasKey(tok.text):
      md = KEYWORD_DOCS[tok.text]
    else:
      return newJNull()
  of tFam:
    md = "**fam** — `self`, the method's bestie. Only vibes inside clique methods."
  of tAncestor:
    md = "**ancestor** — `super()`. Respect the ancestors."
  of tNew:
    md = "**new** — `__init__`, the constructor."
  else:
    if KEYWORD_DOCS.hasKey(tok.text):
      md = KEYWORD_DOCS[tok.text]
    else:
      return newJNull()
  result = %*{"contents": {"kind": "markdown", "value": md}}

proc definition(uri: string, pos: Pos): JsonNode =
  let doc = docs[uri]
  let t = wordTokenAt(doc.toks, pos.line, pos.char)
  if t.isNone:
    return newJNull()
  let decls = collectDecls(doc.program)
  let d = findDecl(decls, t.get.text)
  if d.isNone:
    return newJNull()
  # Location { uri, range }
  %*{
    "uri": uri,
    "range": lspRange((d.get.line - 1, d.get.col),
                      (d.get.line - 1, d.get.col + d.get.name.len)),
  }

proc completionList(decls: seq[Decl]): JsonNode =
  var items: seq[JsonNode] = @[]
  proc item(label: string, kind: int, detail: string) =
    items.add %*{"label": label, "kind": kind, "detail": detail}
  for k, v in KEYWORD_DOCS:
    let isCall = k in ["how many", "vibes", "add up", "least", "most", "positive",
                       "ranked", "index up", "link", "unlock", "round up",
                       "vibe check", "num", "drip", "text", "truth", "stack",
                       "map", "squad", "crew", "yap", "yap back"]
    item(k, if isCall: 3 else: 14, v)  # Function / Keyword
  for modname in ["luck", "clock", "system", "json", "regex", "stash", "loops",
                  "tools", "timing", "types", "paths", "spawn", "net", "web", "db"]:
    item(modname, 9, "slang module")
  for d in decls:
    if d.kind != dkParam:
      item(d.name, (case d.kind
        of dkVariable: 6
        of dkFunction: 3
        of dkClass: 7
        of dkParam: 6), d.detail)
  %*{"isIncomplete": false, "items": items}

proc documentSymbols(uri: string): JsonNode =
  let doc = docs[uri]
  proc sym(name: string, kind: int, line, col: int, children: seq[JsonNode]): JsonNode =
    var n = %*{
      "name": name,
      "kind": kind,
      "range": lspRange((line - 1, col), (line - 1, col + name.len)),
      "selectionRange": lspRange((line - 1, col), (line - 1, col + name.len)),
    }
    if children.len > 0:
      n["children"] = %children
    n

  proc walkStmts(stmts: seq[Stmt]): seq[JsonNode] =
    for s in stmts:
      case s.kind
      of skFuncDef:
        result.add sym(s.fname, 12, s.line, s.col, walkStmts(s.fndefBody))
      of skClassDef:
        result.add sym(s.cname, 5, s.line, s.col, walkStmts(s.cbody))
      of skVarDecl:
        result.add sym(s.vname, 13, s.line, s.col, @[])
      of skFor:
        for t in s.ftargets:
          result.add sym(t, 13, s.line, s.col, @[])
      else:
        discard
  %walkStmts(doc.program)

# ------------------------------------------------------------------ main loop

proc main*() =
  var initialized = false
  var shutdownRequested = false
  while true:
    let msgOpt = readMessage()
    if msgOpt.isNone:
      quit(0)
    let msg = msgOpt.get
    let m = msg{"method"}.getStr()
    let id = msg{"id"}

    if m == "initialize":
      initialized = true
      respond(id, %*{
        "capabilities": {
          "textDocumentSync": 1,
          "hoverProvider": true,
          "definitionProvider": true,
          "completionProvider": {"resolveProvider": false, "triggerCharacters": []},
          "documentSymbolProvider": true,
        },
        "serverInfo": {"name": "gzim-lsp", "version": "1.0.0"},
      })
    elif m == "initialized":
      discard
    elif m == "shutdown":
      shutdownRequested = true
      nullResponse(id)
    elif m == "exit":
      quit(if shutdownRequested: 0 else: 1)
    elif not initialized:
      discard
    elif m == "textDocument/didOpen":
      let td = msg{"params"}{"textDocument"}
      let uri = td{"uri"}.getStr()
      let text = td{"text"}.getStr()
      docs[uri] = analyze(text)
      publishDiagnostics(uri, docs[uri])
    elif m == "textDocument/didChange":
      let td = msg{"params"}{"textDocument"}
      let uri = td{"uri"}.getStr()
      let changes = msg{"params"}{"contentChanges"}
      if changes.len > 0:
        let text = changes[^1]{"text"}.getStr()
        docs[uri] = analyze(text)
        publishDiagnostics(uri, docs[uri])
    elif m == "textDocument/didSave":
      discard
    elif m == "textDocument/didClose":
      docs.del(msg{"params"}{"textDocument"}{"uri"}.getStr())
    elif m == "textDocument/hover":
      let uri = msg{"params"}{"textDocument"}{"uri"}.getStr()
      if uri in docs:
        let p = msg{"params"}{"position"}
        respond(id, hover(uri, (p{"line"}.getInt(), p{"character"}.getInt())))
      else:
        nullResponse(id)
    elif m == "textDocument/definition":
      let uri = msg{"params"}{"textDocument"}{"uri"}.getStr()
      if uri in docs:
        let p = msg{"params"}{"position"}
        respond(id, definition(uri, (p{"line"}.getInt(), p{"character"}.getInt())))
      else:
        nullResponse(id)
    elif m == "textDocument/completion":
      let uri = msg{"params"}{"textDocument"}{"uri"}.getStr()
      if uri in docs:
        respond(id, completionList(collectDecls(docs[uri].program)))
      else:
        nullResponse(id)
    elif m == "textDocument/documentSymbol":
      let uri = msg{"params"}{"textDocument"}{"uri"}.getStr()
      if uri in docs:
        respond(id, documentSymbols(uri))
      else:
        nullResponse(id)
    else:
      # unknown notification/request — silence is a vibe
      if not msg{"id"}.isNil:
        nullResponse(msg{"id"})

when isMainModule:
  main()
