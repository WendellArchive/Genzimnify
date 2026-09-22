## Lexer for Genzimnify (.gzim), slang in, tokens out.
##
## Handles:
##  - indentation-based blocks (INDENT / DEDENT tokens)
##  - `fr` statement terminators
##  - multi-word keywords (call up, for real, send it, throw shade, ...)
##  - `glow"..."` f-strings (kept raw; the parser splits interpolations)
##  - `#[[ ... ]]#` block comments
##  - implicit line joining inside (), [], {}

import std/strutils
import errors, token

type
  Lexer = object
    src: string
    pos: int
    line: int
    col: int
    indents: seq[int]
    parenDepth: int
    atLineStart: bool
    pendLine: int   # position where the current token starts
    pendCol: int
    toks: seq[Token]

proc cur(l: Lexer): char =
  if l.pos >= l.src.len: '\0' else: l.src[l.pos]

proc peekChar(l: Lexer, k: int = 1): char =
  let j = l.pos + k
  if j < 0 or j >= l.src.len: '\0' else: l.src[j]

proc advance(l: var Lexer): char =
  result = l.cur
  if result == '\0': return
  inc l.pos
  if result == '\n':
    inc l.line
    l.col = 0
  else:
    inc l.col

proc fail(l: Lexer, msg: string): GzimError =
  newGzimError(msg, l.line, l.col)

proc addTok(l: var Lexer, kind: TokKind, text = "", line = -1, col = -1) =
  let ln = if line < 0: l.pendLine else: line
  let cl = if col < 0: l.pendCol else: col
  l.toks.add Token(kind: kind, text: text, line: ln, col: cl)

# ------------------------------------------------------------------ helpers

proc peekWord(l: Lexer): string =
  ## The next identifier word after whitespace (never crosses a newline).
  var j = l.pos
  while j < l.src.len and l.src[j] in {' ', '\t'}:
    inc j
  while j < l.src.len and l.src[j] in GzIdent:
    result.add l.src[j]
    inc j

proc tryWord(l: var Lexer, w: string): bool =
  ## If the next word (after spaces) is exactly `w`, consume it and return
  ## true; otherwise restore position and return false.
  let savedPos = l.pos
  let savedCol = l.col
  while l.cur in {' ', '\t'}:
    discard l.advance()
  if l.src.substr(l.pos).startsWith(w):
    let after = l.pos + w.len
    let nextC = if after < l.src.len: l.src[after] else: '\0'
    if nextC notin GzIdent:
      for _ in 1 .. w.len:
        discard l.advance()
      return true
  l.pos = savedPos
  l.col = savedCol
  return false

proc skipBlockComment(l: var Lexer) =
  ## At `#[[`; skips through `]]#` (may span lines).
  for _ in 1 .. 3:
    discard l.advance()
  while true:
    if l.pos >= l.src.len:
      raise l.fail("yap session never ended, close the block comment with ]]#")
    if l.cur == ']' and l.peekChar == ']' and l.peekChar(2) == '#':
      for _ in 1 .. 3:
        discard l.advance()
      return
    discard l.advance()

# ------------------------------------------------------------------ strings

proc lexString(l: var Lexer, kind: TokKind) =
  let q = l.advance()
  var raw = ""
  if l.cur == q and l.peekChar == q:
    # triple-quoted string
    discard l.advance()
    discard l.advance()
    while true:
      if l.pos >= l.src.len:
        raise l.fail("string never ended, close the quote bestie")
      if l.cur == '\\' and l.peekChar != '\0':
        raw.add l.advance()
        raw.add l.advance()
        continue
      if l.cur == q and l.peekChar == q and l.peekChar(2) == q:
        discard l.advance()
        discard l.advance()
        discard l.advance()
        break
      raw.add l.advance()
  else:
    while true:
      if l.pos >= l.src.len or l.cur == '\n':
        raise l.fail("string never ended, close the quote bestie")
      if l.cur == q:
        discard l.advance()
        break
      if l.cur == '\\':
        raw.add l.advance()
        if l.cur != '\0' and l.cur != '\n':
          raw.add l.advance()
        continue
      raw.add l.advance()
  l.addTok(kind, raw)

proc lexNumber(l: var Lexer) =
  var raw = ""
  while l.cur in {'0' .. '9', '_'}:
    raw.add l.advance()
  if l.cur == '.' and l.peekChar in {'0' .. '9'}:
    raw.add l.advance()
    while l.cur in {'0' .. '9', '_'}:
      raw.add l.advance()
  if l.cur in {'e', 'E'}:
    let savedPos = l.pos
    let savedCol = l.col
    let savedRaw = raw
    raw.add l.advance()
    if l.cur in {'+', '-'}:
      raw.add l.advance()
    if l.cur in {'0' .. '9'}:
      while l.cur in {'0' .. '9', '_'}:
        raw.add l.advance()
    else:
      # not an exponent after all; rewind
      l.pos = savedPos
      l.col = savedCol
      raw = savedRaw
  l.addTok(tNumber, raw)

# ------------------------------------------------------------------ words

proc lexWord(l: var Lexer) =
  let startLine = l.line
  let startCol = l.col
  var w = ""
  while l.cur in GzIdent:
    w.add l.advance()

  case w
  of "let": l.addTok(tLet, "let")
  of "lock": l.addTok(tLock, "lock")
  of "nocap": l.addTok(tNocap, "nocap")
  of "cap": l.addTok(tCap, "cap")
  of "ghost": l.addTok(tGhost, "ghost")
  of "both": l.addTok(tBoth, "both")
  of "either": l.addTok(tEither, "either")
  of "nah": l.addTok(tNah, "nah")
  of "literally": l.addTok(tLiterally, "literally")
  of "vibecheck": l.addTok(tVibecheck, "vibecheck")
  of "or": l.addTok(tOr, "or")
  of "otherwise": l.addTok(tOtherwise, "otherwise")
  of "dip": l.addTok(tDip, "dip")
  of "next": l.addTok(tNext, "next")
  of "deadass": l.addTok(tDeadass, "deadass")
  of "cook": l.addTok(tCook, "cook")
  of "drop": l.addTok(tDrop, "drop")
  of "yo": l.addTok(tYo, "yo")
  of "clique": l.addTok(tClique, "clique")
  of "new": l.addTok(tNew, "new")
  of "fam": l.addTok(tFam, "fam")
  of "ancestor": l.addTok(tAncestor, "ancestor")
  of "outta": l.addTok(tOutta, "outta")
  of "as": l.addTok(tAs, "as")
  of "gives": l.addTok(tGives, "gives")
  of "sus": l.addTok(tSus, "sus")
  of "fr": l.addTok(tFR, "fr")
  of "worldwide": l.addTok(tWorldwide, "worldwide")
  of "localish": l.addTok(tLocalish, "localish")
  of "cancel": l.addTok(tCancel, "cancel")
  of "f_around": l.addTok(tFAround, "f_around")
  of "find_out": l.addTok(tFindOut, "find_out")
  of "no_matter_what": l.addTok(tNoMatterWhat, "no_matter_what")

  of "aint":
    if l.tryWord("literally"):
      l.addTok(tAintLiterally, "aint literally")
    else:
      let savedPos = l.pos
      let savedCol = l.col
      block found:
        if l.tryWord("up"):
          if l.tryWord("in"):
            l.addTok(tAintUpIn, "aint up in")
            break found
        l.pos = savedPos
        l.col = savedCol
        l.addTok(tAint, "aint")

  of "up":
    if l.tryWord("in"): l.addTok(tUpIn, "up in")
    else: l.addTok(tIdent, "up")

  of "same":
    if l.tryWord("as"): l.addTok(tEqEq, "same as")
    else: l.addTok(tIdent, "same")

  of "call":
    if l.tryWord("up"): l.addTok(tCallUp, "call up")
    else: l.addTok(tIdent, "call")

  of "for":
    if l.tryWord("real"): l.addTok(tForReal, "for real")
    else: l.addTok(tIdent, "for")

  of "send":
    if l.tryWord("it"): l.addTok(tSendIt, "send it")
    else: l.addTok(tIdent, "send")

  of "throw":
    if l.tryWord("shade"): l.addTok(tThrowShade, "throw shade")
    else: l.addTok(tIdent, "throw")

  of "yap":
    if l.tryWord("back"): l.addTok(tYapBack, "yap back")
    else: l.addTok(tYap, "yap")

  of "mini":
    if l.tryWord("vibe"): l.addTok(tMiniVibe, "mini vibe")
    else: l.addTok(tIdent, "mini")

  of "on":
    if l.tryWord("timing"): l.addTok(tOnTiming, "on timing")
    elif l.tryWord("god"): l.addTok(tOnGod, "on god")
    else: l.addTok(tIdent, "on")

  of "fit":
    if l.tryWord("check"): l.addTok(tFitCheck, "fit check")
    else: l.addTok(tFit, "fit")

  of "pull":
    if l.tryWord("up"): l.addTok(tPullUp, "pull up")
    else: l.addTok(tIdent, "pull")

  of "roll":
    if l.tryWord("with"): l.addTok(tRollWith, "roll with")
    else: l.addTok(tIdent, "roll")

  of "vibe":
    if l.tryWord("check"): l.addTok(tVibeCheckType, "vibe check")
    else: l.addTok(tVibe, "vibe")

  of "how":
    if l.tryWord("many"): l.addTok(tHowMany, "how many")
    else: l.addTok(tIdent, "how")

  of "add":
    if l.tryWord("up"): l.addTok(tAddUp, "add up")
    else: l.addTok(tIdent, "add")

  of "round":
    if l.tryWord("up"): l.addTok(tRoundUp, "round up")
    else: l.addTok(tIdent, "round")

  of "index":
    if l.tryWord("up"): l.addTok(tIndexUp, "index up")
    else: l.addTok(tIdent, "index")

  of "wait":
    if l.tryWord("up"): l.addTok(tWaitUp, "wait up")
    else: l.addTok(tIdent, "wait")

  of "glow":
    if l.cur in {'"', '\''}:
      l.lexString(tFStr)
    else:
      l.addTok(tIdent, "glow")

  of "be":
    # compound assignment: be+ be- be* be/ be// be% be**  (no space)
    let c = l.cur
    case c
    of '+': discard l.advance(); l.addTok(tBePlus, "be+")
    of '-': discard l.advance(); l.addTok(tBeMinus, "be-")
    of '*':
      discard l.advance()
      if l.cur == '*':
        discard l.advance(); l.addTok(tBeStarStar, "be**")
      else:
        l.addTok(tBeStar, "be*")
    of '/':
      discard l.advance()
      if l.cur == '/':
        discard l.advance(); l.addTok(tBeSlashSlash, "be//")
      else:
        l.addTok(tBeSlash, "be/")
    of '%': discard l.advance(); l.addTok(tBePercent, "be%")
    else: l.addTok(tBe, "be")

  else: l.addTok(tIdent, w)

# ------------------------------------------------------------------ ops

proc lexOp(l: var Lexer) =
  let c = l.cur
  case c
  of '+':
    discard l.advance()
    if l.cur == '=': discard l.advance(); l.addTok(tPlusEq, "+=")
    else: l.addTok(tPlus, "+")
  of '-':
    discard l.advance()
    if l.cur == '=': discard l.advance(); l.addTok(tMinusEq, "-=")
    else: l.addTok(tMinus, "-")
  of '*':
    discard l.advance()
    if l.cur == '*':
      discard l.advance()
      if l.cur == '=': discard l.advance(); l.addTok(tStarStarEq, "**=")
      else: l.addTok(tStarStar, "**")
    elif l.cur == '=':
      discard l.advance(); l.addTok(tStarEq, "*=")
    else:
      l.addTok(tStar, "*")
  of '/':
    discard l.advance()
    if l.cur == '/':
      discard l.advance()
      if l.cur == '=': discard l.advance(); l.addTok(tSlashSlashEq, "//=")
      else: l.addTok(tSlashSlash, "//")
    elif l.cur == '=':
      discard l.advance(); l.addTok(tSlashEq, "/=")
    else:
      l.addTok(tSlash, "/")
  of '%':
    discard l.advance()
    if l.cur == '=': discard l.advance(); l.addTok(tPercentEq, "%=")
    else: l.addTok(tPercent, "%")
  of '=':
    discard l.advance()
    if l.cur == '=': discard l.advance(); l.addTok(tEqEq, "==")
    else: l.addTok(tAssign, "=")
  of '!':
    discard l.advance()
    if l.cur == '=': discard l.advance(); l.addTok(tNotEq, "!=")
    else: raise l.fail("lone '!', that ain't it (did you mean '!=' ?)")
  of '<':
    discard l.advance()
    if l.cur == '=': discard l.advance(); l.addTok(tLe, "<=")
    else: l.addTok(tLt, "<")
  of '>':
    discard l.advance()
    if l.cur == '=': discard l.advance(); l.addTok(tGe, ">=")
    else: l.addTok(tGt, ">")
  of '(':
    discard l.advance(); inc l.parenDepth; l.addTok(tLParen, "(")
  of ')':
    discard l.advance(); if l.parenDepth > 0: dec l.parenDepth; l.addTok(tRParen, ")")
  of '[':
    discard l.advance(); inc l.parenDepth; l.addTok(tLBracket, "[")
  of ']':
    discard l.advance(); if l.parenDepth > 0: dec l.parenDepth; l.addTok(tRBracket, "]")
  of '{':
    discard l.advance(); inc l.parenDepth; l.addTok(tLBrace, "{")
  of '}':
    discard l.advance(); if l.parenDepth > 0: dec l.parenDepth; l.addTok(tRBrace, "}")
  of ',':
    discard l.advance(); l.addTok(tComma, ",")
  of ':':
    discard l.advance(); l.addTok(tColon, ":")
  of '.':
    discard l.advance(); l.addTok(tDot, ".")
  of '?':
    discard l.advance(); l.addTok(tQuestion, "?")
  else:
    raise l.fail("unexpected character '" & c & "', that ain't it")

# ------------------------------------------------------------------ main

proc handleLineStart(l: var Lexer) =
  ## Process indentation at the start of a logical line.
  ## Blank and comment-only lines are consumed without producing tokens.
  while true:
    var width = 0
    while l.cur in {' ', '\t'}:
      width += (if l.cur == '\t': 4 else: 1)
      discard l.advance()
    if l.pos >= l.src.len:
      return
    case l.cur
    of '\n':
      discard l.advance()  # blank line
      continue
    of '#':
      if l.peekChar == '[' and l.peekChar(2) == '[':
        l.skipBlockComment()
        continue
      while l.cur != '\n' and l.cur != '\0':
        discard l.advance()
      if l.cur == '\n':
        discard l.advance()
      continue
    else:
      l.pendLine = l.line
      l.pendCol = width
      if width > l.indents[^1]:
        l.indents.add width
        l.addTok(tIndent, "<indent " & $width & ">")
      elif width < l.indents[^1]:
        while l.indents.len > 0 and width < l.indents[^1]:
          l.indents.setLen(l.indents.len - 1)
          l.addTok(tDedent, "<dedent>")
        if l.indents.len == 0 or width != l.indents[^1]:
          raise l.fail("inconsistent indentation, pick a lane (consistent spaces or tabs)")
      l.atLineStart = false
      return

proc lexToken(l: var Lexer) =
  l.pendLine = l.line
  l.pendCol = l.col
  let c = l.cur
  case c
  of '\n':
    discard l.advance()
    if l.parenDepth == 0:
      l.addTok(tNewline, "⏎")
      l.atLineStart = true
    # inside brackets: implicit line joining, no token
  of ' ', '\t', '\r':
    discard l.advance()
  of '#':
    if l.peekChar == '[' and l.peekChar(2) == '[':
      l.skipBlockComment()
    else:
      while l.cur != '\n' and l.cur != '\0':
        discard l.advance()
  of '"', '\'':
    l.lexString(tString)
  of '0' .. '9':
    l.lexNumber()
  of 'a' .. 'z', 'A' .. 'Z', '_':
    l.lexWord()
  else:
    l.lexOp()

proc lex*(source: string): seq[Token] =
  var l = Lexer(src: source, line: 1, indents: @[0], atLineStart: true)
  if l.src.startsWith("\xEF\xBB\xBF"):
    l.pos = 3
  while true:
    if l.atLineStart and l.parenDepth == 0 and l.pos < l.src.len:
      l.handleLineStart()
    if l.pos >= l.src.len:
      break
    l.lexToken()
  if l.toks.len > 0 and l.toks[^1].kind != tNewline:
    l.addTok(tNewline, "⏎")
  while l.indents.len > 1:
    l.indents.setLen(l.indents.len - 1)
    l.addTok(tDedent, "<dedent>")
  l.addTok(tEOF, "<end>")
  l.toks
