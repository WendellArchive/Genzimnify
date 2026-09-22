## Parser for Genzimnify, recursive descent for statements,
## Pratt parsing for expressions. Slang in, AST out.

import std/[strutils, tables]
import token, lexer, ast, errors

type
  Parser = object
    toks: seq[Token]
    i: int
    usedAny: bool  # saw `whatever` in a type hint -> emit `from typing import Any`

# ------------------------------------------------------------------ helpers

proc peek(p: Parser): Token =
  if p.i >= p.toks.len: p.toks[^1] else: p.toks[p.i]

proc peekAt(p: Parser, k: int): Token =
  let j = p.i + k
  if j < 0 or j >= p.toks.len: p.toks[^1] else: p.toks[j]

proc advance(p: var Parser): Token =
  result = p.peek()
  if result.kind != tEOF:
    inc p.i

proc check(p: Parser, k: TokKind): bool =
  p.peek().kind == k

proc match(p: var Parser, k: TokKind): bool =
  if p.check(k):
    discard p.advance()
    result = true
  else:
    result = false

proc fail(p: Parser, msg: string): GzimError =
  let t = p.peek()
  newGzimError(msg, t.line, t.col)

proc expect(p: var Parser, k: TokKind, msg: string): Token =
  if not p.check(k):
    raise p.fail(msg)
  p.advance()

proc expectName(p: var Parser, what: string): Token =
  if not p.check(tIdent):
    raise p.fail("expected " & what & ", got " & tokDesc(p.peek().kind, p.peek().text))
  p.advance()

proc atTerminator(p: Parser): bool =
  p.check(tNewline) or p.check(tFR) or p.check(tDedent) or p.check(tEOF) or p.check(tColon)

proc finishStmt(p: var Parser) =
  ## End a statement: either an explicit `fr` (more statements may follow on
  ## the same line) or a newline / block boundary.
  if p.match(tFR):
    return
  if p.check(tNewline) or p.check(tDedent) or p.check(tEOF):
    return
  raise p.fail("statement didn't end right, finish it with a newline or 'fr'")

# ------------------------------------------------------------------ types

const TYPE_MAP = {
  "num": "int", "drip": "float", "text": "str", "truth": "bool",
  "whatever": "Any", "stack": "list", "map": "dict",
  "squad": "set", "crew": "tuple",
}.toTable

proc parseType(p: var Parser): string

proc parseExpr*(p: var Parser, prec: int = 0): Expr

proc parseTypeAtom(p: var Parser): string =
  var base: string
  if p.check(tGhost):
    discard p.advance()
    base = "None"
  elif p.check(tIdent):
    let n = p.peek().text
    base = if TYPE_MAP.hasKey(n): TYPE_MAP[n] else: n
    discard p.advance()
  else:
    raise p.fail("expected a type hint (num, text, stack[num], whatever...)")
  if p.match(tLBracket):
    var args: seq[string] = @[]
    if not p.check(tRBracket):
      while true:
        args.add p.parseTypeAtom()
        if not p.match(tComma):
          break
    discard p.expect(tRBracket, "expected ']' to close the type hint")
    base &= "[" & args.join(", ") & "]"
  while p.match(tQuestion):
    base &= " | None"
  base

proc parseType(p: var Parser): string =
  result = p.parseTypeAtom()
  while p.check(tOr):
    discard p.advance()
    result &= " | " & p.parseTypeAtom()
  if "Any" in result:
    p.usedAny = true

# ------------------------------------------------------------------ f-strings

proc splitSpec(s: string): tuple[expr: string, spec: string] =
  ## Split `x:03d` / `x!r` into expr part and format spec, respecting nesting.
  var depth = 0
  var inStr = '\0'
  var i = 0
  while i < s.len:
    let ch = s[i]
    if inStr != '\0':
      if ch == '\\':
        inc i; inc i
        continue
      if ch == inStr:
        inStr = '\0'
      inc i
      continue
    case ch
    of '\'', '"':
      inStr = ch
      inc i
    of '(', '[', '{':
      inc depth
      inc i
    of ')', ']', '}':
      dec depth
      inc i
    of '!':
      if depth == 0 and not (i + 1 < s.len and s[i + 1] == '='):
        return (s[0 ..< i], s[i .. ^1])
      inc i
    of ':':
      if depth == 0:
        return (s[0 ..< i], s[i .. ^1])
      inc i
    else:
      inc i
  (s, "")

proc parseExpressionString*(src: string, baseLine: int): Expr =
  ## Parse a standalone expression (used for glow interpolations).
  var toks = lex(src)
  for t in toks.mitems:
    if t.line > 0:
      t.line = t.line + baseLine - 1
  var p = Parser(toks: toks)
  let e = p.parseExpr()
  if not (p.check(tEOF) or p.check(tNewline)):
    raise p.fail("couldn't parse this glow expression")
  e

proc parseFStrParts(raw: string, line: int): seq[FStrPart] =
  var lit = ""
  var i = 0
  template flush() =
    if lit.len > 0:
      result.add FStrPart(isExpr: false, text: lit)
      lit = ""

  template failFStr(msg: string) =
    raise newGzimError(msg, line, 0)

  while i < raw.len:
    let c = raw[i]
    if c == '{':
      if i + 1 < raw.len and raw[i + 1] == '{':
        lit.add '{'
        inc i
        inc i
        continue
      # find matching close brace, respecting nesting and strings
      var depth = 1
      var j = i + 1
      var inStr = '\0'
      while j < raw.len and depth > 0:
        let cj = raw[j]
        if inStr != '\0':
          if cj == '\\':
            inc j
          elif cj == inStr:
            inStr = '\0'
        else:
          case cj
          of '\'', '"': inStr = cj
          of '{': inc depth
          of '}': dec depth
          else: discard
        inc j
      if depth != 0:
        failFStr("glow interpolation never closed, missing '}'")
      let inner = raw[(i + 1) ..< (j - 1)]
      flush()
      let (esrc, spec) = splitSpec(inner)
      if esrc.strip().len == 0:
        failFStr("empty glow interpolation, put an expression in there")
      result.add FStrPart(
        isExpr: true,
        text: inner,
        ex: parseExpressionString(esrc, line),
        spec: spec,
      )
      i = j
    elif c == '}':
      if i + 1 < raw.len and raw[i + 1] == '}':
        lit.add '}'
        inc i
        inc i
      else:
        failFStr("stray '}' in glow string, double it (}}) if you meant it")
    else:
      lit.add c
      inc i
  flush()

# ------------------------------------------------------------------ blocks

proc parseStmt(p: var Parser): Stmt

proc parseStmts(p: var Parser): seq[Stmt] =
  while true:
    if p.check(tNewline):
      discard p.advance()
      continue
    if p.check(tFR):
      discard p.advance()
      continue
    if p.check(tDedent) or p.check(tEOF):
      break
    if p.check(tIndent):
      raise p.fail("sudden indent, a line can't start more-indented than the one before")
    result.add p.parseStmt()

proc parseBlock(p: var Parser): seq[Stmt] =
  if p.match(tNewline):
    if not p.match(tIndent):
      raise p.fail("expected an indented block after ':'")
    result = p.parseStmts()
    if not p.match(tDedent):
      raise p.fail("unindent doesn't match any outer level, check your spacing")
  else:
    # inline block: statements on the same line, separated by `fr`
    while true:
      if p.check(tNewline) or p.check(tEOF) or p.check(tDedent):
        break
      if p.match(tFR):
        continue
      result.add p.parseStmt()

# ------------------------------------------------------------------ statements

proc expectColon(p: var Parser, after: string) =
  discard p.expect(tColon, "expected ':' after " & after)

proc parseVarDecl(p: var Parser): Stmt =
  let t = p.advance()  # let / lock
  let nameTok = p.expectName("a variable name after '" & t.text & "'")
  result = Stmt(kind: skVarDecl, vname: nameTok.text, isConst: t.kind == tLock,
                line: t.line, col: t.col)
  if p.match(tAs):
    result.annot = p.parseType()
  if p.match(tBe):
    result.vvalue = p.parseExpr()
    if p.match(tAs) and result.annot.len == 0:
      result.annot = p.parseType()
  p.finishStmt()

proc parseIf(p: var Parser, anchor: int): Stmt =
  let t = p.advance()  # vibecheck
  var clauses: seq[tuple[cond: Expr, body: seq[Stmt]]] = @[]
  let cond = p.parseExpr()
  p.expectColon("the vibecheck condition")
  clauses.add (cond, p.parseBlock())
  discard p.match(tNewline)  # an inline block leaves its trailing newline
  while p.check(tOr) and p.peek().col == anchor:
    discard p.advance()
    let c = p.parseExpr()
    p.expectColon("the 'or' condition")
    clauses.add (c, p.parseBlock())
  var eb: seq[Stmt] = @[]
  var hasElse = false
  if p.check(tOtherwise) and p.peek().col == anchor:
    discard p.advance()
    p.expectColon("otherwise")
    eb = p.parseBlock()
    hasElse = true
  Stmt(kind: skIf, clauses: clauses, elseBody: eb, hasElse: hasElse,
       line: t.line, col: t.col)

proc parseWhile(p: var Parser): Stmt =
  let t = p.advance()
  let cond = p.parseExpr()
  p.expectColon("the vibe condition")
  Stmt(kind: skWhile, wcond: cond, wbody: p.parseBlock(), line: t.line, col: t.col)

proc parseTargets(p: var Parser): seq[string] =
  if p.match(tLParen):
    while not p.check(tRParen):
      result.add p.expectName("a loop variable").text
      if not p.match(tComma):
        break
    discard p.expect(tRParen, "expected ')' after loop variables")
  else:
    result.add p.expectName("a loop variable").text
    while p.match(tComma):
      result.add p.expectName("a loop variable").text

proc parseFor(p: var Parser): Stmt =
  let t = p.advance()
  let targets = p.parseTargets()
  discard p.expect(tUpIn, "expected 'up in' in the for real loop")
  let iter = p.parseExpr()
  p.expectColon("the for real loop")
  Stmt(kind: skFor, ftargets: targets, fiter: iter, fbody: p.parseBlock(),
       line: t.line, col: t.col)

proc parseParams(p: var Parser): seq[Param] =
  while not p.check(tRParen):
    var prm = Param()
    if p.match(tStarStar):
      prm.isStarStar = true
      prm.name = p.expectName("a param name after '**'").text
    elif p.match(tStar):
      prm.isStar = true
      prm.name = p.expectName("a param name after '*'").text
    elif p.match(tFam):
      prm.name = "fam"
    else:
      prm.name = p.expectName("a param name").text
    if p.match(tAs):
      prm.annot = p.parseType()
    if p.check(tAssign) or p.check(tBe):
      discard p.advance()
      prm.default = p.parseExpr()
    result.add prm
    if not p.match(tComma):
      break

proc parseFunc(p: var Parser, isAsync: bool): Stmt =
  let t = p.advance()  # cook
  var fname: string
  if p.check(tNew):
    discard p.advance()
    fname = "new"
  elif p.check(tIdent):
    fname = p.advance().text
  else:
    raise p.fail("expected a function name after cook, got " &
                 tokDesc(p.peek().kind, p.peek().text))
  discard p.expect(tLParen, "expected '(' after the function name")
  let params = p.parseParams()
  discard p.expect(tRParen, "expected ')' to close the params")
  var ret = ""
  if p.match(tGives):
    ret = p.parseType()
  p.expectColon("the cook signature")
  Stmt(kind: skFuncDef, fname: fname, fparams: params, fret: ret,
       fndefBody: p.parseBlock(), isAsync: isAsync, line: t.line, col: t.col)

proc parseClass(p: var Parser): Stmt =
  let t = p.advance()
  let name = p.expectName("a clique name").text
  var bases: seq[Expr] = @[]
  if p.match(tLParen):
    if not p.check(tRParen):
      while true:
        bases.add p.parseExpr()
        if not p.match(tComma):
          break
    discard p.expect(tRParen, "expected ')' after the base cliques")
  p.expectColon("the clique header")
  Stmt(kind: skClassDef, cname: name, cbases: bases, cbody: p.parseBlock(),
       line: t.line, col: t.col)

proc parseDottedName(p: var Parser): string =
  result = p.expectName("a module name").text
  while p.check(tDot):
    discard p.advance()
    result &= "." & p.expectName("a module name").text

proc parseImport(p: var Parser): Stmt =
  let t = p.advance()
  let modName = p.parseDottedName()
  var alias = ""
  if p.match(tAs):
    alias = p.expectName("an alias after 'as'").text
  p.finishStmt()
  result = Stmt(kind: skImport, imod: modName, ialias: alias, line: t.line, col: t.col)

proc parseFromImport(p: var Parser): Stmt =
  let t = p.advance()
  let modName = p.parseDottedName()
  discard p.expect(tPullUp, "expected 'pull up' after 'outta <module>'")
  var names: seq[tuple[nm: string, alias: string]] = @[]
  if p.check(tIdent) and p.peek().text == "all":
    discard p.advance()
    names.add (nm: "*", alias: "")
  else:
    while true:
      let n = p.expectName("a name to pull up").text
      var alias = ""
      if p.match(tAs):
        alias = p.expectName("an alias after 'as'").text
      names.add (nm: n, alias: alias)
      if not p.match(tComma):
        break
      if p.check(tIdent) and p.peek().text == "all":
        discard p.advance()
        names.add (nm: "*", alias: "")
        break
  p.finishStmt()
  result = Stmt(kind: skFromImport, fmod: modName, fnames: names, line: t.line, col: t.col)

proc parseTry(p: var Parser, anchor: int): Stmt =
  let t = p.advance()
  p.expectColon("f_around")
  result = Stmt(kind: skTry, line: t.line, col: t.col)
  result.tbody = p.parseBlock()
  while p.check(tFindOut) and p.peek().col == anchor:
    discard p.advance()
    var h: Handler
    if not (p.check(tColon) or p.check(tAs)):
      h.etype = p.parseExpr()
    if p.match(tAs):
      h.alias = p.expectName("a name after 'as'").text
    p.expectColon("the find_out clause")
    h.body = p.parseBlock()
    result.handlers.add h
  if p.check(tOtherwise) and p.peek().col == anchor:
    discard p.advance()
    p.expectColon("otherwise")
    result.orelse = p.parseBlock()
  if p.check(tNoMatterWhat) and p.peek().col == anchor:
    discard p.advance()
    p.expectColon("no_matter_what")
    result.finallyB = p.parseBlock()

proc parseWith(p: var Parser): Stmt =
  let t = p.advance()
  var items: seq[tuple[ctx: Expr, alias: string]] = @[]
  while true:
    let ctx = p.parseExpr()
    var alias = ""
    if p.match(tAs):
      alias = p.expectName("a name after 'as'").text
    items.add (ctx, alias)
    if not p.match(tComma):
      break
  p.expectColon("the roll with expression")
  Stmt(kind: skWith, witems: items, withBody: p.parseBlock(), line: t.line, col: t.col)

proc parseMatch(p: var Parser): Stmt =
  let t = p.advance()  # fit check
  let subject = p.parseExpr()
  p.expectColon("the fit check subject")
  if not p.match(tNewline):
    raise p.fail("expected a newline after 'fit check x:', each fit goes on its own line")
  if not p.match(tIndent):
    raise p.fail("expected an indented block of 'fit' cases")
  var cases: seq[tuple[pattern: Expr, body: seq[Stmt]]] = @[]
  var defBody: seq[Stmt] = @[]
  var hasDefault = false
  while p.check(tFit) or p.check(tOtherwise):
    if p.match(tFit):
      let pat = p.parseExpr()
      p.expectColon("the fit pattern")
      cases.add (pat, p.parseBlock())
    else:
      discard p.advance()
      p.expectColon("otherwise")
      defBody = p.parseBlock()
      hasDefault = true
  if not p.match(tDedent):
    raise p.fail("expected the fit cases to end, dedent to close the fit check")
  Stmt(kind: skMatch, msubject: subject, mcases: cases, mdefault: defBody,
       hasDefault: hasDefault, line: t.line, col: t.col)

proc assignOpText(k: TokKind, text: string): string =
  case k
  of tBePlus, tPlusEq: "+"
  of tBeMinus, tMinusEq: "-"
  of tBeStar, tStarEq: "*"
  of tBeSlash, tSlashEq: "/"
  of tBeSlashSlash, tSlashSlashEq: "//"
  of tBePercent, tPercentEq: "%"
  of tBeStarStar, tStarStarEq: "**"
  else: ""
  # note: `text` unused except for debugging

proc parseExprOrAssign(p: var Parser): Stmt =
  let t = p.peek()
  let first = p.parseExpr()
  if p.check(tBe) or p.check(tAssign):
    discard p.advance()
    let value = p.parseExpr()
    result = Stmt(kind: skAssign, target: first, value: value, op: "",
                  line: t.line, col: t.col)
  elif p.peek().kind in {tBePlus, tBeMinus, tBeStar, tBeSlash, tBeSlashSlash,
                         tBePercent, tBeStarStar, tPlusEq, tMinusEq, tStarEq,
                         tSlashEq, tSlashSlashEq, tPercentEq, tStarStarEq}:
    let opTok = p.advance()
    let value = p.parseExpr()
    result = Stmt(kind: skAssign, target: first, value: value,
                  op: assignOpText(opTok.kind, opTok.text), line: t.line, col: t.col)
  else:
    result = Stmt(kind: skExpr, e: first, line: t.line, col: t.col)
  p.finishStmt()

proc parseStmt(p: var Parser): Stmt =
  let t = p.peek()
  case t.kind
  of tLet, tLock:
    result = p.parseVarDecl()
  of tVibecheck:
    result = p.parseIf(t.col)
  of tVibe:
    result = p.parseWhile()
  of tForReal:
    result = p.parseFor()
  of tCook:
    result = p.parseFunc(false)
  of tOnTiming:
    discard p.advance()
    if not p.check(tCook):
      raise p.fail("on timing needs a cook right after it: on timing cook name():")
    result = p.parseFunc(true)
  of tClique:
    result = p.parseClass()
  of tPullUp:
    result = p.parseImport()
  of tOutta:
    result = p.parseFromImport()
  of tFAround:
    result = p.parseTry(t.col)
  of tSendIt:
    discard p.advance()
    result = Stmt(kind: skReturn, line: t.line, col: t.col)
    if not p.atTerminator():
      result.re = p.parseExpr()
    p.finishStmt()
  of tThrowShade:
    discard p.advance()
    result = Stmt(kind: skRaise, line: t.line, col: t.col)
    if not p.atTerminator():
      result.rae = p.parseExpr()
    p.finishStmt()
  of tDrop:
    discard p.advance()
    result = Stmt(kind: skYield, line: t.line, col: t.col)
    if not p.atTerminator():
      result.ye = p.parseExpr()
    p.finishStmt()
  of tDip, tNext, tDeadass:
    discard p.advance()
    let k: StmtKind = case t.kind
      of tDip: skBreak
      of tNext: skContinue
      else: skPass
    result = Stmt(kind: k, line: t.line, col: t.col)
    p.finishStmt()
  of tRollWith:
    result = p.parseWith()
  of tFitCheck:
    result = p.parseMatch()
  of tCancel:
    discard p.advance()
    var targets: seq[Expr] = @[]
    while true:
      targets.add p.parseExpr()
      if not p.match(tComma):
        break
    result = Stmt(kind: skDelete, dtargets: targets, line: t.line, col: t.col)
    p.finishStmt()
  of tOnGod:
    discard p.advance()
    let cond = p.parseExpr()
    var msg: Expr = nil
    if p.match(tComma):
      msg = p.parseExpr()
    result = Stmt(kind: skAssert, acond: cond, amsg: msg, line: t.line, col: t.col)
    p.finishStmt()
  of tWorldwide, tLocalish:
    discard p.advance()
    var names: seq[string] = @[]
    while true:
      names.add p.expectName("a variable name").text
      if not p.match(tComma):
        break
    let k: StmtKind = if t.kind == tWorldwide: skGlobal else: skNonlocal
    result = Stmt(kind: k, line: t.line, col: t.col)
    result.gnames = names
    p.finishStmt()
  else:
    result = p.parseExprOrAssign()

# ------------------------------------------------------------------ expressions

proc infixBp(k: TokKind): int =
  case k
  of tOr, tEither: 10
  of tBoth: 20
  of tEqEq, tNotEq, tNah, tLt, tGt, tLe, tGe,
     tUpIn, tAintUpIn, tLiterally, tAintLiterally: 30
  of tPlus, tMinus: 40
  of tStar, tSlash, tSlashSlash, tPercent: 50
  of tStarStar: 70
  of tDot, tLParen, tLBracket: 100  # postfix
  else: 0

proc binOpText(k: TokKind): string =
  case k
  of tOr, tEither: "or"
  of tBoth: "and"
  of tEqEq: "=="
  of tNotEq, tNah: "!="
  of tLt: "<"
  of tGt: ">"
  of tLe: "<="
  of tGe: ">="
  of tUpIn: "in"
  of tAintUpIn: "not in"
  of tLiterally: "is"
  of tAintLiterally: "is not"
  of tPlus: "+"
  of tMinus: "-"
  of tStar: "*"
  of tSlash: "/"
  of tSlashSlash: "//"
  of tPercent: "%"
  of tStarStar: "**"
  else: ""

proc parseSubscript(p: var Parser, obj: Expr): Expr =
  let t = p.advance()  # '['
  var lo: Expr = nil
  var hi: Expr = nil
  var step: Expr = nil
  var isSlice = false
  if p.check(tColon):
    isSlice = true
  else:
    lo = p.parseExpr()
    if p.check(tColon):
      isSlice = true
  if isSlice:
    if p.match(tColon):
      if not (p.check(tRBracket) or p.check(tColon)):
        hi = p.parseExpr()
      if p.match(tColon):
        if not p.check(tRBracket):
          step = p.parseExpr()
    discard p.expect(tRBracket, "expected ']' to close the subscript")
    result = Expr(kind: ekSlice, ssliceObj: obj, slo: lo, shi: hi, sstep: step,
         line: t.line, col: t.col)
  else:
    discard p.expect(tRBracket, "expected ']' to close the subscript")
    result = Expr(kind: ekSub, sobj: obj, sidx: lo, line: t.line, col: t.col)

# (parseExpr declared at top; implemented below)

proc parsePrefix(p: var Parser): Expr =
  let t = p.peek()
  case t.kind
  of tNumber:
    discard p.advance()
    result = Expr(kind: ekNum, s: t.text, line: t.line, col: t.col)
  of tString:
    discard p.advance()
    result = Expr(kind: ekStr, s: t.text, line: t.line, col: t.col)
  of tFStr:
    discard p.advance()
    result = Expr(kind: ekFStr, parts: parseFStrParts(t.text, t.line), line: t.line, col: t.col)
  of tNocap, tCap:
    discard p.advance()
    result = Expr(kind: ekBool, s: (if t.kind == tNocap: "True" else: "False"),
         line: t.line, col: t.col)
  of tGhost:
    discard p.advance()
    result = Expr(kind: ekNone, s: "None", line: t.line, col: t.col)
  of tIdent:
    discard p.advance()
    result = Expr(kind: ekName, s: t.text, line: t.line, col: t.col)
  of tFam:
    discard p.advance()
    result = Expr(kind: ekSelf, line: t.line, col: t.col)
  of tVibeCheckType, tHowMany, tAddUp, tRoundUp, tIndexUp, tYap, tYapBack:
    discard p.advance()
    result = Expr(kind: ekName, s: t.text, line: t.line, col: t.col)
  of tNew:
    discard p.advance()
    result = Expr(kind: ekName, s: "new", line: t.line, col: t.col)
  of tAncestor:
    discard p.advance()
    result = Expr(kind: ekName, s: "ancestor", line: t.line, col: t.col)
  of tMinus, tPlus:
    discard p.advance()
    let operand = p.parseExpr(55)
    result = Expr(kind: ekUnary, uop: (if t.kind == tMinus: "-" else: "+"),
         uoperand: operand, line: t.line, col: t.col)
  of tAint:
    discard p.advance()
    let operand = p.parseExpr(25)
    result = Expr(kind: ekUnary, uop: "not ", uoperand: operand, line: t.line, col: t.col)
  of tCallUp:
    discard p.advance()
    result = p.parseExpr()
    if not p.match(tYo):
      raise p.fail("you called it up but never said 'yo', close the vibe with yo")
  of tWaitUp:
    discard p.advance()
    let operand = p.parseExpr(45)
    result = Expr(kind: ekAwait, wexpr: operand, line: t.line, col: t.col)
  of tDrop:
    discard p.advance()
    var operand: Expr = nil
    if not p.atTerminator() and not p.check(tRParen) and not p.check(tComma):
      operand = p.parseExpr(5)
    result = Expr(kind: ekYield, yexpr: operand, line: t.line, col: t.col)
  of tMiniVibe:
    discard p.advance()
    discard p.expect(tLParen, "mini vibe needs parens: mini vibe(x): ...")
    let params = p.parseParams()
    discard p.expect(tRParen, "expected ')' to close the mini vibe params")
    p.expectColon("the mini vibe params")
    let body = p.parseExpr()
    result = Expr(kind: ekLambda, lparams: params, lbody: body, line: t.line, col: t.col)
  of tLParen:
    discard p.advance()
    if p.match(tRParen):
      return Expr(kind: ekTuple, items: @[], line: t.line, col: t.col)
    let first = p.parseExpr()
    if p.check(tComma):
      var items = @[first]
      while p.match(tComma):
        if p.check(tRParen):
          break
        items.add p.parseExpr()
      discard p.expect(tRParen, "expected ')' to close the crew")
      result = Expr(kind: ekTuple, items: items, line: t.line, col: t.col)
    else:
      discard p.expect(tRParen, "expected ')', you opened a paren and dipped")
      first.grouped = true
      result = first
  of tLBracket:
    discard p.advance()
    if p.match(tRBracket):
      return Expr(kind: ekList, items: @[], line: t.line, col: t.col)
    let first = p.parseExpr()
    if p.check(tForReal):
      var clauses: seq[CompClause] = @[]
      while p.match(tForReal):
        var cl = CompClause()
        cl.targets = p.parseTargets()
        discard p.expect(tUpIn, "expected 'up in' in the comprehension")
        cl.iter = p.parseExpr()
        if p.match(tSus):
          cl.cond = p.parseExpr()
        clauses.add cl
      discard p.expect(tRBracket, "expected ']' to close the comprehension")
      result = Expr(kind: ekComp, celt: first, cclauses: clauses, line: t.line, col: t.col)
    else:
      var items = @[first]
      while p.match(tComma):
        if p.check(tRBracket):
          break
        items.add p.parseExpr()
      discard p.expect(tRBracket, "expected ']' to close the stack literal")
      result = Expr(kind: ekList, items: items, line: t.line, col: t.col)
  of tLBrace:
    discard p.advance()
    if p.match(tRBrace):
      return Expr(kind: ekDict, line: t.line, col: t.col)
    let first = p.parseExpr()
    if p.match(tColon):
      var dk = @[first]
      var dv = @[p.parseExpr()]
      while p.match(tComma):
        if p.check(tRBrace):
          break
        let k = p.parseExpr()
        discard p.expect(tColon, "expected ':' in the map literal")
        dk.add k
        dv.add p.parseExpr()
      discard p.expect(tRBrace, "expected '}' to close the map literal")
      result = Expr(kind: ekDict, dkeys: dk, dvals: dv, line: t.line, col: t.col)
    else:
      var items = @[first]
      while p.match(tComma):
        if p.check(tRBrace):
          break
        items.add p.parseExpr()
      discard p.expect(tRBrace, "expected '}' to close the squad literal")
      result = Expr(kind: ekSet, items: items, line: t.line, col: t.col)
  else:
    case t.kind
    of tOr: raise p.fail("'or' (elif) needs to line up with its vibecheck")
    of tOtherwise: raise p.fail("otherwise needs a vibecheck or fit check above it")
    of tFit: raise p.fail("fit only makes sense inside a fit check")
    of tFindOut: raise p.fail("find_out needs an f_around above it")
    of tNoMatterWhat: raise p.fail("no_matter_what needs an f_around above it")
    of tYo: raise p.fail("'yo' with no 'call up', that's cap")
    of tDedent: raise p.fail("unexpected end of block")
    else: raise p.fail("didn't expect " & tokDesc(t.kind, t.text) & " here, that ain't it")

proc attrName(p: var Parser): string =
  let at = p.peek()
  case at.kind
  of tIdent, tNew, tYap, tYapBack, tHowMany, tAddUp, tRoundUp, tIndexUp,
     tVibeCheckType, tGhost, tNocap, tCap, tDip, tNext, tDeadass, tDrop,
     tSus, tGives, tAs, tOr, tBoth, tEither, tAint, tNah, tLiterally,
     tAncestor, tFam:
    discard p.advance()
    result = at.text
  else:
    raise p.fail("expected a name after '.', got " & tokDesc(at.kind, at.text))

proc parseExpr*(p: var Parser, prec: int = 0): Expr =
  result = p.parsePrefix()
  while true:
    let t = p.peek()
    let bp = infixBp(t.kind)
    if bp <= prec:
      break
    case t.kind
    of tDot:
      discard p.advance()
      let nm = p.attrName()
      result = Expr(kind: ekAttr, aobj: result, aname: nm, line: t.line, col: t.col)
    of tLParen:
      discard p.advance()
      var args: seq[Expr] = @[]
      var kwargs: seq[tuple[nm: string, val: Expr]] = @[]
      if not p.match(tRParen):
        while true:
          if p.match(tStarStar):
            args.add Expr(kind: ekUnary, uop: "**", uoperand: p.parseExpr(55),
                          line: t.line, col: t.col)
          elif p.match(tStar):
            args.add Expr(kind: ekUnary, uop: "*", uoperand: p.parseExpr(55),
                          line: t.line, col: t.col)
          elif p.peek().kind == tIdent and p.peekAt(1).kind in {tBe, tAssign}:
            let nm = p.advance().text
            discard p.advance()
            kwargs.add (nm: nm, val: p.parseExpr())
          else:
            args.add p.parseExpr()
          if not p.match(tComma):
            break
        discard p.expect(tRParen, "expected ')' to close the call")
      result = Expr(kind: ekCall, callee: result, cargs: args, ckwargs: kwargs,
                    line: t.line, col: t.col)
    of tLBracket:
      result = p.parseSubscript(result)
    else:
      discard p.advance()
      let rhsPrec = if t.kind == tStarStar: bp - 1 else: bp
      let rhs = p.parseExpr(rhsPrec)
      result = Expr(kind: ekBinary, bop: binOpText(t.kind), blhs: result,
                    brhs: rhs, line: t.line, col: t.col)

# ------------------------------------------------------------------ entry

proc parseProgram*(toks: seq[Token]): tuple[program: seq[Stmt], usedAny: bool] =
  var p = Parser(toks: toks)
  let prog = p.parseStmts()
  if not p.check(tEOF):
    raise p.fail("unexpected " & tokDesc(p.peek().kind, p.peek().text))
  (prog, p.usedAny)
