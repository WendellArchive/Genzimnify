## Semantic analysis ("the vibecheck"). Catches the cap before Python does:
## undeclared reassignments, rebinding locks, mis-scoped slang, etc.

import std/[tables, strutils]
import ast

type
  Issue* = object
    line*: int
    col*: int
    msg*: string

type
  Ctx = ref object
    scopes: seq[Table[string, bool]]  # name -> isConst
    funcDepth: int
    loopDepth: int
    asyncDepth: int
    selfDepth: int
    issues: seq[Issue]

proc lookup(c: Ctx, name: string): tuple[found: bool, isConst: bool] =
  for i in countdown(c.scopes.high, 0):
    if c.scopes[i].hasKey(name):
      return (true, c.scopes[i][name])
  (false, false)

proc declare(c: Ctx, name: string, isConst: bool) =
  c.scopes[^1][name] = isConst

proc issue(c: Ctx, line, col: int, msg: string) =
  c.issues.add Issue(line: line, col: col, msg: msg)

# ------------------------------------------------------------------ exprs

proc checkExpr(c: Ctx, e: Expr)

proc checkStmts(c: Ctx, stmts: seq[Stmt])

proc checkAssignTarget(c: Ctx, e: Expr, line, col: int) =
  ## Keep invalid targets from leaking through as confusing Python syntax errors.
  if e == nil:
    return
  case e.kind
  of ekName:
    let (found, isC) = c.lookup(e.s)
    if not found:
      c.issue(line, col,
        "`" & e.s & "` never got declared, hit it with a `let` first")
    elif isC:
      c.issue(line, col, "`" & e.s & "` is locked, `lock` vars don't move")
  of ekAttr, ekSub, ekSlice:
    discard
  of ekTuple, ekList:
    for item in e.items:
      c.checkAssignTarget(item, line, col)
  else:
    c.issue(line, col,
      "that can't go on the left of `be`; assign to a name, attribute, or subscript")

proc checkFunc(c: Ctx, s: Stmt, isMethod: bool) =
  let (found, isC) = c.lookup(s.fname)
  if isC:
    c.issue(s.line, s.col, "`" & s.fname & "` is locked, can't cook over a lock")
  c.declare(s.fname, false)

  if isMethod and (s.fparams.len == 0 or s.fparams[0].name != "fam"):
    c.issue(s.line, s.col,
      "clique methods need `fam` as their first param (that's the self)")
  if s.fname == "new" and isMethod and (s.fparams.len == 0 or s.fparams[0].name != "fam"):
    c.issue(s.line, s.col, "the `new` glow-up needs `fam` as its first param")

  # Defaults are evaluated in the enclosing scope, not inside the new cook.
  for prm in s.fparams:
    if prm.default != nil:
      c.checkExpr(prm.default)

  let savedFunc = c.funcDepth
  let savedLoop = c.loopDepth
  let savedAsync = c.asyncDepth
  let savedSelf = c.selfDepth
  c.funcDepth = 1
  c.loopDepth = 0
  c.asyncDepth = (if s.isAsync: 1 else: 0)
  c.selfDepth = (if isMethod: 1 else: 0)
  c.scopes.add initTable[string, bool]()
  for prm in s.fparams:
    if prm.name != "":
      c.declare(prm.name, false)
  c.checkStmts(s.fndefBody)
  discard c.scopes.pop()
  c.funcDepth = savedFunc
  c.loopDepth = savedLoop
  c.asyncDepth = savedAsync
  c.selfDepth = savedSelf

proc declarePattern(c: Ctx, e: Expr) =
  if e == nil:
    return
  case e.kind
  of ekName:
    c.declare(e.s, false)
  of ekTuple, ekList:
    for item in e.items:
      c.declarePattern(item)
  else:
    discard

proc checkExpr(c: Ctx, e: Expr) =
  if e == nil:
    return
  case e.kind
  of ekSelf:
    if c.selfDepth == 0:
      c.issue(e.line, e.col, "`fam` only makes sense inside clique methods")
  of ekAwait:
    if c.asyncDepth == 0:
      c.issue(e.line, e.col, "`wait up` only works inside an `on timing cook`")
    c.checkExpr(e.wexpr)
  of ekYield:
    if c.funcDepth == 0:
      c.issue(e.line, e.col, "`drop` only works inside a cook")
    if e.yexpr != nil:
      c.checkExpr(e.yexpr)
  of ekNum, ekStr, ekBool, ekNone:
    discard
  of ekName:
    discard
  of ekFStr:
    for part in e.parts:
      if part.isExpr:
        c.checkExpr(part.ex)
  of ekList, ekSet, ekTuple:
    for item in e.items:
      c.checkExpr(item)
  of ekDict:
    for k in e.dkeys:
      c.checkExpr(k)
    for v in e.dvals:
      c.checkExpr(v)
  of ekUnary:
    c.checkExpr(e.uoperand)
  of ekBinary:
    c.checkExpr(e.blhs)
    c.checkExpr(e.brhs)
  of ekCall:
    c.checkExpr(e.callee)
    for a in e.cargs:
      c.checkExpr(a)
    for kw in e.ckwargs:
      c.checkExpr(kw.val)
  of ekAttr:
    c.checkExpr(e.aobj)
  of ekSub:
    c.checkExpr(e.sobj)
    c.checkExpr(e.sidx)
  of ekSlice:
    c.checkExpr(e.ssliceObj)
    if e.slo != nil: c.checkExpr(e.slo)
    if e.shi != nil: c.checkExpr(e.shi)
    if e.sstep != nil: c.checkExpr(e.sstep)
  of ekLambda:
    c.scopes.add initTable[string, bool]()
    for prm in e.lparams:
      c.declare(prm.name, false)
      if prm.default != nil:
        c.checkExpr(prm.default)
    inc c.funcDepth
    c.checkExpr(e.lbody)
    dec c.funcDepth
    discard c.scopes.pop()
  of ekComp:
    c.scopes.add initTable[string, bool]()
    for cl in e.cclauses:
      for t in cl.targets:
        c.declare(t, false)
    for cl in e.cclauses:
      c.checkExpr(cl.iter)
      if cl.cond != nil:
        c.checkExpr(cl.cond)
    c.checkExpr(e.celt)
    discard c.scopes.pop()

# ------------------------------------------------------------------ stmts

proc checkStmt(c: Ctx, s: Stmt) =
  case s.kind
  of skVarDecl:
    let (found, isC) = c.lookup(s.vname)
    if isC:
      c.issue(s.line, s.col,
        "`" & s.vname & "` is locked in fr, you can't rebind a `lock`")
    elif found and s.isConst:
      c.issue(s.line, s.col,
        "`" & s.vname & "` already exists, you can't upgrade it to `lock` mid-vibe")
    c.declare(s.vname, s.isConst)
    if s.vvalue != nil:
      c.checkExpr(s.vvalue)
  of skAssign:
    c.checkAssignTarget(s.target, s.line, s.col)
    c.checkExpr(s.target)
    c.checkExpr(s.value)
  of skExpr:
    c.checkExpr(s.e)
  of skIf:
    for cl in s.clauses:
      c.checkExpr(cl.cond)
      c.checkStmts(cl.body)
    c.checkStmts(s.elseBody)
  of skWhile:
    c.checkExpr(s.wcond)
    inc c.loopDepth
    c.checkStmts(s.wbody)
    dec c.loopDepth
  of skFor:
    c.checkExpr(s.fiter)
    for t in s.ftargets:
      c.declare(t, false)
    inc c.loopDepth
    c.checkStmts(s.fbody)
    dec c.loopDepth
  of skFuncDef:
    c.checkFunc(s, false)
  of skClassDef:
    let (found, isC) = c.lookup(s.cname)
    if isC:
      c.issue(s.line, s.col, "`" & s.cname & "` is locked, can't restack a lock")
    c.declare(s.cname, false)
    for b in s.cbases:
      c.checkExpr(b)
    let savedFunc = c.funcDepth
    let savedLoop = c.loopDepth
    let savedAsync = c.asyncDepth
    let savedSelf = c.selfDepth
    c.funcDepth = 0
    c.loopDepth = 0
    c.asyncDepth = 0
    c.selfDepth = 0
    c.scopes.add initTable[string, bool]()
    for stmt in s.cbody:
      if stmt.kind == skFuncDef:
        c.checkFunc(stmt, true)
      else:
        c.checkStmt(stmt)
    discard c.scopes.pop()
    c.funcDepth = savedFunc
    c.loopDepth = savedLoop
    c.asyncDepth = savedAsync
    c.selfDepth = savedSelf
  of skReturn:
    if c.funcDepth == 0:
      c.issue(s.line, s.col, "`send it` only makes sense inside a cook")
    if s.re != nil:
      c.checkExpr(s.re)
  of skBreak:
    if c.loopDepth == 0:
      c.issue(s.line, s.col, "`dip` only works inside a vibe or for real loop")
  of skContinue:
    if c.loopDepth == 0:
      c.issue(s.line, s.col, "`next` only works inside a vibe or for real loop")
  of skPass:
    discard
  of skRaise:
    if s.rae != nil:
      c.checkExpr(s.rae)
  of skTry:
    c.checkStmts(s.tbody)
    for h in s.handlers:
      if h.etype != nil:
        c.checkExpr(h.etype)
      elif h.alias != "":
        c.issue(s.line, s.col,
          "can't `find_out as " & h.alias & "` without naming an exception type")
      if h.alias != "":
        c.declare(h.alias, false)
      c.checkStmts(h.body)
    c.checkStmts(s.orelse)
    c.checkStmts(s.finallyB)
  of skWith:
    for item in s.witems:
      c.checkExpr(item.ctx)
      if item.alias != "":
        c.declare(item.alias, false)
    c.checkStmts(s.withBody)
  of skImport:
    var local = s.imod
    if local.contains('.'):
      local = local.split('.')[0]
    if s.ialias != "":
      local = s.ialias
    c.declare(local, false)
  of skFromImport:
    for n in s.fnames:
      if n.nm != "*":
        let local = if n.alias != "": n.alias else: n.nm
        c.declare(local, false)
  of skMatch:
    c.checkExpr(s.msubject)
    for mc in s.mcases:
      c.declarePattern(mc.pattern)
      c.checkStmts(mc.body)
    c.checkStmts(s.mdefault)
  of skDelete:
    for t in s.dtargets:
      c.checkExpr(t)
  of skAssert:
    c.checkExpr(s.acond)
    if s.amsg != nil:
      c.checkExpr(s.amsg)
  of skGlobal, skNonlocal:
    if s.kind == skNonlocal and c.funcDepth == 0:
      c.issue(s.line, s.col, "`localish` only works inside a nested cook")
    for n in s.gnames:
      c.declare(n, false)
  of skYield:
    if c.funcDepth == 0:
      c.issue(s.line, s.col, "`drop` only works inside a cook")
    if s.ye != nil:
      c.checkExpr(s.ye)

proc checkStmts(c: Ctx, stmts: seq[Stmt]) =
  for s in stmts:
    c.checkStmt(s)

proc checkProgram*(program: seq[Stmt]): seq[Issue] =
  var c = Ctx()
  c.scopes.add initTable[string, bool]()
  c.checkStmts(program)
  c.issues
