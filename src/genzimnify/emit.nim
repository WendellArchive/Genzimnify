## Python emitter, turns the Genzimnify AST into actual Python code.
## Keeps a source map (python line -> .gzim line) for error reporting.

import std/[strutils, tables]
import ast

type
  Emitter* = ref object
    lines: seq[string]
    indent: int
    maps: seq[(int, int)]  # (python line, gzim line)

let NAME_MAP = {
  "how many": "len", "vibes": "range", "num": "int", "drip": "float",
  "text": "str", "truth": "bool", "stack": "list", "map": "dict",
  "squad": "set", "crew": "tuple", "add up": "sum", "least": "min",
  "most": "max", "positive": "abs", "ranked": "sorted",
  "index up": "enumerate", "link": "zip", "unlock": "open",
  "round up": "round", "vibe check": "type",
  "yap": "print", "yap back": "input",
  "ancestor": "super", "new": "__init__",
  "L": "Exception", "BadVibe": "ValueError", "WrongType": "TypeError",
  "OutOfPocket": "IndexError", "Ghosted": "KeyError",
  "SplitByZero": "ZeroDivisionError", "NoPullUp": "ImportError",
  "CapDetected": "AssertionError", "StopTheCap": "StopIteration",
}.toTable

let MODULE_MAP = {
  "luck": "random", "clock": "time", "json": "json", "regex": "re",
  "stash": "collections", "loops": "itertools", "tools": "functools",
  "timing": "asyncio", "paths": "pathlib", "spawn": "subprocess",
  "net": "socket", "web": "http", "db": "sqlite3", "vibecheck": "unittest",
}.toTable

proc addLine(em: Emitter, text: string, gz: int) =
  em.lines.add "    ".repeat(em.indent) & text
  em.maps.add (em.lines.len, gz)

proc render*(em: Emitter): string =
  em.lines.join("\n") & "\n"

proc renderMaps*(em: Emitter): string =
  for (py, gz) in em.maps:
    result.add $py & ":" & $gz & "\n"

# ------------------------------------------------------------------ strings

proc pyStr(raw: string): string =
  ## Emit a normal string literal from raw (escaped) source content.
  var r = "\""
  var i = 0
  while i < raw.len:
    let ch = raw[i]
    if ch == '\\' and i + 1 < raw.len:
      r.add raw[i]
      r.add raw[i + 1]
      inc i
      inc i
      continue
    if ch == '"':
      r.add "\\\""
      inc i
      continue
    r.add ch
    inc i
  r & "\""

proc emitFStr(em: Emitter, e: Expr): string

# ------------------------------------------------------------------ exprs

proc emitExpr(em: Emitter, e: Expr): string

proc emitStmt(em: Emitter, s: Stmt)

proc emitStmts(em: Emitter, stmts: seq[Stmt]) =
  for s in stmts:
    em.emitStmt(s)

proc child(em: Emitter, e: Expr): string =
  if e == nil:
    return ""
  if e.grouped:
    "(" & em.emitExpr(e) & ")"
  else:
    em.emitExpr(e)

proc emitParams(em: Emitter, params: seq[Param], withAnnots: bool): string =
  var parts: seq[string] = @[]
  for prm in params:
    var s: string
    if prm.isStarStar:
      s = "**"
    elif prm.isStar:
      s = "*"
    if prm.name == "fam":
      s &= "self"
    else:
      s &= prm.name
    if withAnnots and prm.annot != "":
      s &= ": " & prm.annot
    if prm.default != nil:
      s &= " = " & em.emitExpr(prm.default)
    parts.add s
  parts.join(", ")

proc emitFStr(em: Emitter, e: Expr): string =
  # choose the outer quote to avoid collisions with interpolated content
  var needsDQ = false
  var needsSQ = false
  for part in e.parts:
    if part.isExpr:
      let t = em.emitExpr(part.ex)
      if '"' in t: needsDQ = true
      if '\'' in t: needsSQ = true
    else:
      if '"' in part.text: needsDQ = true
      if '\'' in part.text: needsSQ = true
  let outer = if needsDQ and not needsSQ: '\'' else: '"'

  proc escLit(lit: string): string =
    var r = ""
    var i = 0
    while i < lit.len:
      let ch = lit[i]
      if ch == '\\' and i + 1 < lit.len:
        r.add lit[i]
        r.add lit[i + 1]
        inc i
        inc i
        continue
      if ch == '{' or ch == '}':
        r.add ch
        r.add ch
        inc i
        continue
      if ch == outer:
        r.add '\\'
        r.add ch
        inc i
        continue
      r.add ch
      inc i
    r

  var body = ""
  for part in e.parts:
    if part.isExpr:
      body.add "{" & em.emitExpr(part.ex) & part.spec & "}"
    else:
      body.add escLit(part.text)
  "f" & outer & body & outer

proc itemList(em: Emitter, e: Expr): seq[string] =
  for item in e.items:
    result.add em.emitExpr(item)

proc emitCall(em: Emitter, e: Expr): string =
  # super call sugar: ancestor.new(fam, x) -> super().__init__(x)
  if e.callee.kind == ekAttr and e.callee.aobj != nil and
      e.callee.aobj.kind == ekName and e.callee.aobj.s == "ancestor":
    var m = e.callee.aname
    if m == "new":
      m = "__init__"
    var args = e.cargs
    if args.len > 0 and args[0].kind == ekSelf:
      args = args[1 .. ^1]
    var parts: seq[string] = @[]
    for a in args:
      parts.add em.emitExpr(a)
    for kw in e.ckwargs:
      parts.add kw.nm & "=" & em.emitExpr(kw.val)
    return "super()." & m & "(" & parts.join(", ") & ")"

  let calleeStr = em.emitExpr(e.callee)
  var parts: seq[string] = @[]
  for a in e.cargs:
    if a.kind == ekUnary and (a.uop == "*" or a.uop == "**"):
      parts.add a.uop & em.emitExpr(a.uoperand)
    else:
      parts.add em.emitExpr(a)
  for kw in e.ckwargs:
    parts.add kw.nm & "=" & em.emitExpr(kw.val)
  calleeStr & "(" & parts.join(", ") & ")"

proc emitExpr(em: Emitter, e: Expr): string =
  if e == nil:
    return ""
  case e.kind
  of ekNum: e.s
  of ekStr: pyStr(e.s)
  of ekBool, ekNone: e.s
  of ekName:
    if NAME_MAP.hasKey(e.s): NAME_MAP[e.s] else: e.s
  of ekSelf: "self"
  of ekFStr: em.emitFStr(e)
  of ekList: "[" & em.itemList(e).join(", ") & "]"
  of ekSet: "{" & em.itemList(e).join(", ") & "}"
  of ekTuple:
    if e.items.len == 1:
      "(" & em.emitExpr(e.items[0]) & ",)"
    else:
      "(" & em.itemList(e).join(", ") & ")"
  of ekDict:
    var parts: seq[string] = @[]
    for i in 0 ..< e.dkeys.len:
      parts.add em.emitExpr(e.dkeys[i]) & ": " & em.emitExpr(e.dvals[i])
    "{" & parts.join(", ") & "}"
  of ekUnary:
    if e.uop == "not ":
      "not " & em.child(e.uoperand)
    else:
      e.uop & em.child(e.uoperand)
  of ekBinary:
    em.child(e.blhs) & " " & e.bop & " " & em.child(e.brhs)
  of ekCall: em.emitCall(e)
  of ekAttr:
    var nm = e.aname
    if nm == "new":
      nm = "__init__"
    em.child(e.aobj) & "." & nm
  of ekSub:
    em.child(e.sobj) & "[" & em.emitExpr(e.sidx) & "]"
  of ekSlice:
    em.child(e.ssliceObj) & "[" &
      (if e.slo != nil: em.emitExpr(e.slo) else: "") & ":" &
      (if e.shi != nil: em.emitExpr(e.shi) else: "") &
      (if e.sstep != nil: ":" & em.emitExpr(e.sstep) else: "") & "]"
  of ekLambda:
    let ps = em.emitParams(e.lparams, false)
    "lambda" & (if ps.len > 0: " " & ps else: "") & ": " & em.emitExpr(e.lbody)
  of ekAwait:
    "await " & em.child(e.wexpr)
  of ekYield:
    if e.yexpr != nil: "yield " & em.emitExpr(e.yexpr) else: "yield"
  of ekComp:
    var clauseStrs: seq[string] = @[]
    for cl in e.cclauses:
      var s = "for " & cl.targets.join(", ") & " in " & em.emitExpr(cl.iter)
      if cl.cond != nil:
        s &= " if " & em.emitExpr(cl.cond)
      clauseStrs.add s
    "[" & em.emitExpr(e.celt) & " " & clauseStrs.join(" ") & "]"

# ------------------------------------------------------------------ stmts

proc emitBody(em: Emitter, body: seq[Stmt], gz: int) =
  if body.len == 0:
    em.addLine("pass", gz)
  else:
    for s in body:
      em.emitStmt(s)

proc emitStmt(em: Emitter, s: Stmt) =
  case s.kind
  of skExpr:
    em.addLine(em.emitExpr(s.e), s.line)
  of skAssign:
    let op = if s.op == "": "=" else: s.op & "="
    em.addLine(em.child(s.target) & " " & op & " " & em.emitExpr(s.value), s.line)
  of skVarDecl:
    var l = s.vname
    if s.annot != "":
      l &= ": " & s.annot
    if s.vvalue != nil:
      l &= " = " & em.emitExpr(s.vvalue)
    em.addLine(l, s.line)
  of skIf:
    var first = true
    for cl in s.clauses:
      let kw = if first: "if " else: "elif "
      first = false
      em.addLine(kw & em.emitExpr(cl.cond) & ":", s.line)
      inc em.indent
      em.emitBody(cl.body, s.line)
      dec em.indent
    if s.hasElse:
      em.addLine("else:", s.line)
      inc em.indent
      em.emitBody(s.elseBody, s.line)
      dec em.indent
  of skWhile:
    em.addLine("while " & em.emitExpr(s.wcond) & ":", s.line)
    inc em.indent
    em.emitBody(s.wbody, s.line)
    dec em.indent
  of skFor:
    em.addLine("for " & s.ftargets.join(", ") & " in " & em.emitExpr(s.fiter) & ":", s.line)
    inc em.indent
    em.emitBody(s.fbody, s.line)
    dec em.indent
  of skFuncDef:
    var nm = s.fname
    if nm == "new":
      nm = "__init__"
    let header = (if s.isAsync: "async def " else: "def ") & nm & "(" &
      em.emitParams(s.fparams, true) & ")" &
      (if s.fret != "": " -> " & s.fret else: "") & ":"
    em.addLine(header, s.line)
    inc em.indent
    em.emitBody(s.fndefBody, s.line)
    dec em.indent
  of skClassDef:
    var header = "class " & s.cname
    if s.cbases.len > 0:
      var bs: seq[string] = @[]
      for b in s.cbases:
        bs.add em.emitExpr(b)
      header &= "(" & bs.join(", ") & ")"
    header &= ":"
    em.addLine(header, s.line)
    inc em.indent
    em.emitBody(s.cbody, s.line)
    dec em.indent
  of skReturn:
    em.addLine(if s.re != nil: "return " & em.emitExpr(s.re) else: "return", s.line)
  of skBreak:
    em.addLine("break", s.line)
  of skContinue:
    em.addLine("continue", s.line)
  of skPass:
    em.addLine("pass", s.line)
  of skRaise:
    em.addLine(if s.rae != nil: "raise " & em.emitExpr(s.rae) else: "raise", s.line)
  of skTry:
    em.addLine("try:", s.line)
    inc em.indent
    em.emitBody(s.tbody, s.line)
    dec em.indent
    for h in s.handlers:
      var l = "except"
      if h.etype != nil:
        l &= " " & em.emitExpr(h.etype)
      if h.alias != "":
        l &= " as " & h.alias
      l &= ":"
      em.addLine(l, s.line)
      inc em.indent
      em.emitBody(h.body, s.line)
      dec em.indent
    if s.orelse.len > 0:
      em.addLine("else:", s.line)
      inc em.indent
      em.emitStmts(s.orelse)
      dec em.indent
    if s.finallyB.len > 0:
      em.addLine("finally:", s.line)
      inc em.indent
      em.emitStmts(s.finallyB)
      dec em.indent
  of skWith:
    var its: seq[string] = @[]
    for item in s.witems:
      var t = em.emitExpr(item.ctx)
      if item.alias != "":
        t &= " as " & item.alias
      its.add t
    em.addLine("with " & its.join(", ") & ":", s.line)
    inc em.indent
    em.emitBody(s.withBody, s.line)
    dec em.indent
  of skImport:
    if s.imod == "system":
      if s.ialias != "":
        em.addLine("import os as " & s.ialias, s.line)
      else:
        em.addLine("import os", s.line)
        em.addLine("import sys", s.line)
    else:
      let mapped = if MODULE_MAP.hasKey(s.imod): MODULE_MAP[s.imod] else: s.imod
      let local = if s.ialias != "": s.ialias else: s.imod
      if mapped != local:
        em.addLine("import " & mapped & " as " & local, s.line)
      else:
        em.addLine("import " & local, s.line)
  of skFromImport:
    var ns: seq[string] = @[]
    for n in s.fnames:
      if n.nm == "*":
        ns.add "*"
      elif n.alias != "":
        ns.add n.nm & " as " & n.alias
      else:
        ns.add n.nm
    let namesStr = ns.join(", ")
    if s.fmod == "system":
      em.addLine("try:", s.line)
      inc em.indent
      em.addLine("from os import " & namesStr, s.line)
      dec em.indent
      em.addLine("except ImportError:", s.line)
      inc em.indent
      em.addLine("from sys import " & namesStr, s.line)
      dec em.indent
    else:
      let mapped = if MODULE_MAP.hasKey(s.fmod): MODULE_MAP[s.fmod] else: s.fmod
      em.addLine("from " & mapped & " import " & namesStr, s.line)
  of skMatch:
    em.addLine("match " & em.emitExpr(s.msubject) & ":", s.line)
    inc em.indent
    for mc in s.mcases:
      em.addLine("case " & em.emitExpr(mc.pattern) & ":", s.line)
      inc em.indent
      em.emitBody(mc.body, s.line)
      dec em.indent
    if s.hasDefault:
      em.addLine("case _:", s.line)
      inc em.indent
      em.emitBody(s.mdefault, s.line)
      dec em.indent
    dec em.indent
  of skDelete:
    var ts: seq[string] = @[]
    for t in s.dtargets:
      ts.add em.emitExpr(t)
    em.addLine("del " & ts.join(", "), s.line)
  of skAssert:
    var l = "assert " & em.emitExpr(s.acond)
    if s.amsg != nil:
      l &= ", " & em.emitExpr(s.amsg)
    em.addLine(l, s.line)
  of skGlobal:
    em.addLine("global " & s.gnames.join(", "), s.line)
  of skNonlocal:
    em.addLine("nonlocal " & s.gnames.join(", "), s.line)
  of skYield:
    em.addLine(if s.ye != nil: "yield " & em.emitExpr(s.ye) else: "yield", s.line)

# ------------------------------------------------------------------ entry

proc emitProgram*(program: seq[Stmt], usedAny: bool): Emitter =
  var em = Emitter()
  em.lines.add "# Generated by gzimc, Genzimnify 1.0 (vibe responsibly)"
  if usedAny:
    em.lines.add "from typing import Any"
  em.emitStmts(program)
  em
