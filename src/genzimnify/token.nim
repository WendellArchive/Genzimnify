## Token definitions for Genzimnify (.gzim).

type
  TokKind* = enum
    tEOF, tNewline, tIndent, tDedent, tFR,
    # literals & names
    tNumber, tString, tFStr, tIdent,
    # slang keywords
    tLet, tBe, tLock, tNocap, tCap, tGhost,
    tBoth, tEither, tAint, tNah, tLiterally, tAintLiterally,
    tUpIn, tAintUpIn, tVibecheck, tOr, tOtherwise, tVibe,
    tForReal, tDip, tNext, tDeadass, tCook, tSendIt, tDrop, tCallUp, tYo,
    tClique, tNew, tFam, tAncestor, tPullUp, tOutta, tAs, tGives, tSus,
    tFAround, tFindOut, tNoMatterWhat, tThrowShade, tRollWith,
    tOnTiming, tOnGod, tWaitUp, tMiniVibe, tWorldwide, tLocalish, tCancel,
    tFitCheck, tFit, tYap, tYapBack, tVibeCheckType, tHowMany,
    tAddUp, tRoundUp, tIndexUp,
    # operators
    tPlus, tMinus, tStar, tSlash, tSlashSlash, tPercent, tStarStar,
    tEqEq, tNotEq, tLt, tGt, tLe, tGe, tAssign,
    tPlusEq, tMinusEq, tStarEq, tSlashEq, tSlashSlashEq, tPercentEq, tStarStarEq,
    tBePlus, tBeMinus, tBeStar, tBeSlash, tBeSlashSlash, tBePercent, tBeStarStar,
    # punctuation
    tLParen, tRParen, tLBracket, tRBracket, tLBrace, tRBrace,
    tComma, tColon, tDot, tQuestion

  Token* = object
    kind*: TokKind
    text*: string
    line*: int
    col*: int

proc tokDesc*(k: TokKind, text: string): string =
  ## Human-readable description of a token for error messages.
  case k
  of tNewline: "end of line"
  of tEOF: "end of file"
  of tIndent: "an indented block"
  of tDedent: "the end of a block"
  else: "'" & text & "'"

const GzIdentStart* = {'a' .. 'z', 'A' .. 'Z', '_'}
const GzIdent* = {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'}
