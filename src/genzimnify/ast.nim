## AST node definitions for Genzimnify.

type
  FStrPart* = object
    isExpr*: bool
    text*: string   # raw source text (expr incl. format spec, or literal text)
    ex*: Expr       # parsed expression (nil for literal parts)
    spec*: string   # format spec like "!r" or ":03d" ("" if none)

  CompClause* = object
    targets*: seq[string]
    iter*: Expr
    cond*: Expr     # nil if no `sus` filter

  Param* = object
    name*: string
    annot*: string  # "" if no type hint
    default*: Expr  # nil if none
    isStar*: bool
    isStarStar*: bool

  Handler* = object
    etype*: Expr    # nil for bare `find_out:`
    alias*: string  # "" if no `as e`
    body*: seq[Stmt]

  ExprKind* = enum
    ekNum, ekStr, ekFStr, ekBool, ekNone, ekName, ekSelf,
    ekList, ekSet, ekTuple, ekDict,
    ekUnary, ekBinary, ekCall, ekAttr, ekSub, ekSlice,
    ekLambda, ekAwait, ekYield, ekComp

  Expr* = ref object
    line*, col*: int
    grouped*: bool          # was wrapped in explicit parens by the user
    case kind*: ExprKind
    of ekNum, ekStr, ekName, ekBool, ekNone, ekSelf:
      s*: string
    of ekFStr:
      parts*: seq[FStrPart]
    of ekList, ekSet, ekTuple:
      items*: seq[Expr]
    of ekDict:
      dkeys*: seq[Expr]
      dvals*: seq[Expr]
    of ekUnary:
      uop*: string          # "-", "+", "not ", "*", "**" (splat in calls)
      uoperand*: Expr
    of ekBinary:
      bop*: string
      blhs*: Expr
      brhs*: Expr
    of ekCall:
      callee*: Expr
      cargs*: seq[Expr]
      ckwargs*: seq[tuple[nm: string, val: Expr]]
    of ekAttr:
      aobj*: Expr
      aname*: string
    of ekSub:
      sobj*: Expr
      sidx*: Expr
    of ekSlice:
      ssliceObj*: Expr
      slo*, shi*, sstep*: Expr   # nil-able
    of ekLambda:
      lparams*: seq[Param]
      lbody*: Expr
    of ekAwait:
      wexpr*: Expr
    of ekYield:
      yexpr*: Expr          # nil for bare `drop`
    of ekComp:
      celt*: Expr
      cclauses*: seq[CompClause]

  StmtKind* = enum
    skExpr, skAssign, skVarDecl, skIf, skWhile, skFor, skFuncDef, skClassDef,
    skReturn, skBreak, skContinue, skPass, skRaise, skTry, skWith, skImport,
    skFromImport, skMatch, skDelete, skAssert, skGlobal, skNonlocal, skYield

  Stmt* = ref object
    line*, col*: int
    case kind*: StmtKind
    of skExpr:
      e*: Expr
    of skAssign:
      target*: Expr
      value*: Expr
      op*: string           # "" for plain `be`, "+", "-", "*", "/", "//", "%", "**"
    of skVarDecl:
      vname*: string
      vvalue*: Expr         # nil when declaration has no value
      annot*: string        # type hint as python text, "" if none
      isConst*: bool
    of skIf:
      clauses*: seq[tuple[cond: Expr, body: seq[Stmt]]]
      elseBody*: seq[Stmt]
      hasElse*: bool
    of skWhile:
      wcond*: Expr
      wbody*: seq[Stmt]
    of skFor:
      ftargets*: seq[string]
      fiter*: Expr
      fbody*: seq[Stmt]
    of skFuncDef:
      fname*: string
      fparams*: seq[Param]
      fret*: string         # return type as python text, "" if none
      fndefBody*: seq[Stmt]
      isAsync*: bool
    of skClassDef:
      cname*: string
      cbases*: seq[Expr]
      cbody*: seq[Stmt]
    of skReturn:
      re*: Expr             # nil for bare `send it`
    of skRaise:
      rae*: Expr            # nil for bare `throw shade`
    of skTry:
      tbody*: seq[Stmt]
      handlers*: seq[Handler]
      orelse*: seq[Stmt]
      finallyB*: seq[Stmt]
    of skWith:
      witems*: seq[tuple[ctx: Expr, alias: string]]
      withBody*: seq[Stmt]
    of skImport:
      imod*: string
      ialias*: string
    of skFromImport:
      fmod*: string
      fnames*: seq[tuple[nm: string, alias: string]]
    of skMatch:
      msubject*: Expr
      mcases*: seq[tuple[pattern: Expr, body: seq[Stmt]]]
      mdefault*: seq[Stmt]
      hasDefault*: bool
    of skDelete:
      dtargets*: seq[Expr]
    of skAssert:
      acond*: Expr
      amsg*: Expr           # nil if none
    of skGlobal, skNonlocal:
      gnames*: seq[string]
    of skYield:
      ye*: Expr             # nil for bare `drop`
    of skBreak, skContinue, skPass:
      discard
