## Native Genzimnify runtime.
##
## Executes the checked Genzimnify AST directly in the gzim process.  There is
## deliberately no Python process, Python C API, or generated Python involved
## in this module.

import std/[algorithm, base64, json, math, os, osproc, random, sequtils, sets, streams,
            strutils, syncio, tables, times, monotimes]
import ast, lexer, parser, semantic, errors
import packages
import game/engine as game

proc pushbackChar(ch: cint, handle: File): cint {.importc: "ungetc", header: "<stdio.h>".}

type
  ValueKind* = enum
    vkNone, vkBool, vkInt, vkFloat, vkString, vkList, vkTuple, vkSet, vkDict,
    vkFunction, vkBuiltin, vkClass, vkInstance, vkModule, vkException, vkFile, vkGame

  Env* = ref object
    values: Table[string, Value]
    consts: HashSet[string]
    parent: Env
    globals: HashSet[string]
    nonlocals: HashSet[string]

  NativeFunction = ref object
    name: string
    filename: string
    params: seq[Param]
    defaults: seq[Value]
    body: seq[Stmt]
    closure: Env
    isGenerator: bool
    isAsync: bool
    lambdaBody: Expr

  NativeClass = ref object
    name: string
    base: NativeClass
    methods: Table[string, NativeFunction]

  Value* = ref object
    kind*: ValueKind
    intVal: int64
    floatVal: float64
    boolVal: bool
    strVal: string
    items: seq[Value]
    pairs: seq[tuple[key, val: Value]]
    fn: NativeFunction
    builtin: string
    klass: NativeClass
    fields: Table[string, Value]
    moduleEnv: Env
    boundSelf: Value
    fileHandle: File
    fileOpen: bool
    gameObject: GameObject

  RuntimeError* = object of CatchableError
    category*: string
    filename*: string
    line*, col*: int
    frames: seq[tuple[filename: string, line, col: int, name: string]]

  SignalKind = enum sigNone, sigReturn, sigBreak, sigContinue
  Signal = object
    kind: SignalKind
    value: Value

  Runtime* = ref object
    filename*: string
    args*: seq[string]
    moduleCache: Table[string, Value]
    moduleStack: seq[string]
    activeException: Value
    gameContext: GameContext

  ReplSession* = ref object
    runtime: Runtime
    env: Env
    source: string
    statementCount: int

proc noneVal(): Value = Value(kind: vkNone)
proc boolVal(value: bool): Value = Value(kind: vkBool, boolVal: value)
proc intVal(value: int64): Value = Value(kind: vkInt, intVal: value)
proc floatVal(value: float64): Value = Value(kind: vkFloat, floatVal: value)
proc stringVal(value: string): Value = Value(kind: vkString, strVal: value)
proc listVal(items: seq[Value] = @[]): Value = Value(kind: vkList, items: items)
proc tupleVal(items: seq[Value] = @[]): Value = Value(kind: vkTuple, items: items)
proc setVal(items: seq[Value] = @[]): Value = Value(kind: vkSet, items: items)
proc dictVal(pairs: seq[tuple[key, val: Value]] = @[]): Value = Value(kind: vkDict, pairs: pairs)

proc newEnv(parent: Env = nil): Env =
  Env(values: initTable[string, Value](), consts: initHashSet[string](),
      parent: parent, globals: initHashSet[string](), nonlocals: initHashSet[string]())

proc runtimeCap(category, message: string, line = 0, col = 0): ref RuntimeError =
  result = newException(RuntimeError, message)
  result.category = category
  result.line = line
  result.col = col

proc checkedAdd(a, b: int64): int64 =
  if (b > 0 and a > high(int64) - b) or (b < 0 and a < low(int64) - b):
    raise runtimeCap("BadVibe", "integer addition exceeds int64 range")
  a + b

proc checkedSub(a, b: int64): int64 =
  if (b > 0 and a < low(int64) + b) or (b < 0 and a > high(int64) + b):
    raise runtimeCap("BadVibe", "integer subtraction exceeds int64 range")
  a - b

proc checkedMul(a, b: int64): int64 =
  if a > 0:
    if (b > 0 and a > high(int64) div b) or (b < 0 and b < low(int64) div a):
      raise runtimeCap("BadVibe", "integer multiplication exceeds int64 range")
  elif a < 0:
    if (b > 0 and a < low(int64) div b) or (b < 0 and a < high(int64) div b):
      raise runtimeCap("BadVibe", "integer multiplication exceeds int64 range")
  a * b

proc checkedPow(base, exponent: int64): int64 =
  result = 1
  var factor = base
  var remaining = exponent
  while remaining > 0:
    if (remaining and 1) != 0: result = checkedMul(result, factor)
    remaining = remaining shr 1
    if remaining > 0: factor = checkedMul(factor, factor)

proc checkedFloatInt(value: float64): int64 =
  if value.classify in {fcNan, fcInf, fcNegInf} or
      value >= 9223372036854775808.0 or value < -9223372036854775808.0:
    raise runtimeCap("BadVibe", "number cannot be represented as int64")
  value.int64

proc rootEnv(env: Env): Env =
  result = env
  while result.parent != nil: result = result.parent

proc findEnv(env: Env, name: string): Env =
  var current = env
  while current != nil:
    if current.values.hasKey(name): return current
    current = current.parent

proc lookup(env: Env, name: string): Value =
  let owner = env.findEnv(name)
  if owner != nil: return owner.values[name]
  raise runtimeCap("Ghosted", "name '" & name & "' is not defined")

proc declare(env: Env, name: string, value: Value, isConst = false) =
  env.values[name] = value
  if isConst: env.consts.incl(name)

proc assignName(env: Env, name: string, value: Value) =
  var owner: Env
  if name in env.globals:
    owner = env.rootEnv()
  elif name in env.nonlocals:
    owner = env.parent
    while owner != nil and not owner.values.hasKey(name): owner = owner.parent
  else:
    owner = env.findEnv(name)
  if owner == nil: owner = env
  if name in owner.consts:
    raise runtimeCap("BadVibe", "'" & name & "' is locked")
  owner.values[name] = value

proc pyFloat(value: float64): string =
  if value.classify in {fcNan, fcInf, fcNegInf}: return $value
  result = $value
  if '.' notin result and 'e' notin result.toLowerAscii(): result.add ".0"

proc repr*(value: Value): string

proc quoted(value: string): string =
  "'" & value.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n").replace("\t", "\\t") & "'"

proc repr*(value: Value): string =
  if value == nil: return "None"
  case value.kind
  of vkNone: "None"
  of vkBool: (if value.boolVal: "True" else: "False")
  of vkInt: $value.intVal
  of vkFloat: pyFloat(value.floatVal)
  of vkString: quoted(value.strVal)
  of vkList: "[" & value.items.mapIt(repr(it)).join(", ") & "]"
  of vkTuple:
    let body = value.items.mapIt(repr(it)).join(", ")
    "(" & body & (if value.items.len == 1: "," else: "") & ")"
  of vkSet:
    if value.items.len == 0: "set()" else: "{" & value.items.mapIt(repr(it)).join(", ") & "}"
  of vkDict:
    var parts: seq[string]
    for pair in value.pairs: parts.add repr(pair.key) & ": " & repr(pair.val)
    "{" & parts.join(", ") & "}"
  of vkFunction: "<cook " & value.fn.name & ">"
  of vkBuiltin: "<native cook " & value.builtin & ">"
  of vkClass: "<clique " & value.klass.name & ">"
  of vkInstance: "<" & value.klass.name & " vibe>"
  of vkModule: "<module " & value.strVal & ">"
  of vkException: value.strVal
  of vkFile: "<file>"
  of vkGame: "<rizzgame." & kindName(value.gameObject.kind) & ">"

proc display(value: Value): string =
  if value != nil and value.kind == vkString: value.strVal else: repr(value)

proc numeric(value: Value): float64 =
  case value.kind
  of vkInt: value.intVal.float64
  of vkFloat: value.floatVal
  of vkBool: (if value.boolVal: 1.0 else: 0.0)
  else: raise runtimeCap("WrongType", "expected a number, got " & $value.kind)

proc asInt(value: Value): int64 =
  case value.kind
  of vkInt: value.intVal
  of vkBool: (if value.boolVal: 1 else: 0)
  of vkFloat: checkedFloatInt(value.floatVal)
  else: raise runtimeCap("WrongType", "expected an integer, got " & $value.kind)

proc truthy(value: Value): bool =
  if value == nil: return false
  case value.kind
  of vkNone: false
  of vkBool: value.boolVal
  of vkInt: value.intVal != 0
  of vkFloat: value.floatVal != 0
  of vkString: value.strVal.len > 0
  of vkList, vkTuple, vkSet: value.items.len > 0
  of vkDict: value.pairs.len > 0
  else: true

proc compareNumbers(a, b: Value): int =
  # Compare integers before converting: float64 cannot represent all int64 values.
  if a.kind == vkFloat and a.floatVal.isNaN:
    return if b.kind == vkFloat and b.floatVal.isNaN: 0 else: -1
  if b.kind == vkFloat and b.floatVal.isNaN: return 1
  let ai = a.kind in {vkInt, vkBool}
  let bi = b.kind in {vkInt, vkBool}
  if ai and bi: return cmp(a.asInt, b.asInt)
  if not ai and not bi: return cmp(a.floatVal, b.floatVal)
  if not ai: return -compareNumbers(b, a)
  let i = a.asInt
  let f = b.floatVal
  if f >= 9223372036854775808.0: return -1
  if f < -9223372036854775808.0: return 1
  let truncated = f.int64
  result = cmp(i, truncated)
  if result == 0:
    if f > truncated.float64: result = -1
    elif f < truncated.float64: result = 1

proc equal(a, b: Value): bool =
  if a == nil or b == nil: return a == b
  if a.kind in {vkInt, vkFloat, vkBool} and b.kind in {vkInt, vkFloat, vkBool}:
    if (a.kind == vkFloat and a.floatVal.isNaN) or
        (b.kind == vkFloat and b.floatVal.isNaN): return false
    return compareNumbers(a, b) == 0
  if a.kind != b.kind: return false
  case a.kind
  of vkNone: true
  of vkBool: a.boolVal == b.boolVal
  of vkInt: a.intVal == b.intVal
  of vkFloat: a.floatVal == b.floatVal
  of vkString, vkException: a.strVal == b.strVal
  of vkSet:
    if a.items.len != b.items.len: return false
    for item in a.items:
      if not b.items.anyIt(equal(item, it)): return false
    true
  of vkList, vkTuple:
    if a.items.len != b.items.len: return false
    for i in 0 ..< a.items.len:
      if not equal(a.items[i], b.items[i]): return false
    true
  else: a == b

proc contains(container, needle: Value): bool =
  case container.kind
  of vkString:
    if needle.kind != vkString: return false
    needle.strVal in container.strVal
  of vkList, vkTuple, vkSet:
    for item in container.items:
      if equal(item, needle): return true
    false
  of vkDict:
    for pair in container.pairs:
      if equal(pair.key, needle): return true
    false
  else: raise runtimeCap("WrongType", "this value is not searchable")

proc unique(items: seq[Value]): seq[Value] =
  for item in items:
    var seen = false
    for existing in result:
      if equal(existing, item): seen = true; break
    if not seen: result.add item

proc iterable(value: Value): seq[Value] =
  case value.kind
  of vkList, vkTuple, vkSet: result = value.items
  of vkString:
    for ch in value.strVal: result.add stringVal($ch)
  of vkDict:
    for pair in value.pairs: result.add pair.key
  else: raise runtimeCap("WrongType", "value is not iterable")

proc dictIndex(value, key: Value): int =
  for i, pair in value.pairs:
    if equal(pair.key, key): return i
  -1

proc getItem(value, index: Value): Value =
  case value.kind
  of vkDict:
    let at = value.dictIndex(index)
    if at < 0: raise runtimeCap("Ghosted", display(index))
    value.pairs[at].val
  of vkList, vkTuple:
    var at = index.asInt.int
    if at < 0: at += value.items.len
    if at < 0 or at >= value.items.len: raise runtimeCap("OutOfPocket", "index out of range")
    value.items[at]
  of vkString:
    var at = index.asInt.int
    if at < 0: at += value.strVal.len
    if at < 0 or at >= value.strVal.len: raise runtimeCap("OutOfPocket", "string index out of range")
    stringVal($value.strVal[at])
  else: raise runtimeCap("WrongType", "value cannot be indexed")

proc normalizedSlice(length: int, lo, hi, step: Value): tuple[start, stop, step: int] =
  result.step = if step == nil: 1 else: step.asInt.int
  if result.step == 0: raise runtimeCap("BadVibe", "slice step cannot be zero")
  if result.step > 0:
    result.start = if lo == nil: 0 else: lo.asInt.int
    result.stop = if hi == nil: length else: hi.asInt.int
    if result.start < 0: result.start += length
    if result.stop < 0: result.stop += length
    result.start = max(0, min(length, result.start))
    result.stop = max(0, min(length, result.stop))
  else:
    result.start = if lo == nil: length - 1 else: lo.asInt.int
    result.stop = if hi == nil: -1 else: hi.asInt.int
    if lo != nil and result.start < 0: result.start += length
    if hi != nil and result.stop < 0: result.stop += length
    result.start = max(-1, min(length - 1, result.start))
    result.stop = max(-1, min(length - 1, result.stop))

proc sliceValue(value, lo, hi, step: Value): Value =
  let length = if value.kind == vkString: value.strVal.len else: value.items.len
  let sl = normalizedSlice(length, lo, hi, step)
  var indices: seq[int]
  var i = sl.start
  if sl.step > 0:
    while i < sl.stop: indices.add i; i += sl.step
  else:
    while i > sl.stop: indices.add i; i += sl.step
  case value.kind
  of vkString:
    var text = ""
    for at in indices: text.add value.strVal[at]
    stringVal(text)
  of vkList:
    var items: seq[Value]
    for at in indices: items.add value.items[at]
    listVal(items)
  of vkTuple:
    var items: seq[Value]
    for at in indices: items.add value.items[at]
    tupleVal(items)
  else: raise runtimeCap("WrongType", "value cannot be sliced")

proc findMethod(klass: NativeClass, name: string): NativeFunction =
  var current = klass
  while current != nil:
    if current.methods.hasKey(name): return current.methods[name]
    current = current.base

proc builtinValue(name: string, self: Value = nil): Value =
  Value(kind: vkBuiltin, builtin: name, boundSelf: self)

proc fromGame(value: GameValue): Value
proc toGame(value: Value): GameValue

proc getAttr(value: Value, name: string): Value =
  case value.kind
  of vkGame:
    try:
      if hasProperty(value.gameObject, name): return fromGame(getProperty(value.gameObject, name))
      if hasMethod(value.gameObject, name):
        return builtinValue("rizzgame." & kindName(value.gameObject.kind) & "." & name, value)
    except ValueError as error: raise runtimeCap("BadVibe", error.msg)
  of vkInstance:
    if value.fields.hasKey(name): return value.fields[name]
    let fn = value.klass.findMethod(name)
    if fn != nil: return Value(kind: vkFunction, fn: fn, boundSelf: value)
    raise runtimeCap("Ghosted", value.klass.name & " has no attribute '" & name & "'")
  of vkModule:
    if value.moduleEnv.values.hasKey(name): return value.moduleEnv.values[name]
    if value.strVal.startsWith("py."):
      return builtinValue("python:" & value.strVal[3 .. ^1] & ":" & name)
    raise runtimeCap("Ghosted", "module '" & value.strVal & "' has no '" & name & "'")
  of vkString:
    if name in ["upper", "lower", "strip", "split", "replace", "startswith", "endswith", "join"]:
      return builtinValue("str." & name, value)
  of vkList:
    if name in ["append", "extend", "pop", "insert", "remove", "reverse"]:
      return builtinValue("list." & name, value)
  of vkDict:
    if name in ["get", "keys", "values", "items", "pop"]:
      return builtinValue("dict." & name, value)
  of vkFile:
    if name in ["read", "readline", "write", "close"]:
      return builtinValue("file." & name, value)
  of vkBuiltin:
    if value.builtin == "ancestor": return builtinValue("ancestor." & name)
  else: discard
  raise runtimeCap("WrongType", "value has no attribute '" & name & "'")

proc setAttr(value: Value, name: string, newValue: Value) =
  if value.kind == vkGame:
    try: setProperty(value.gameObject, name, toGame(newValue))
    except ValueError as error: raise runtimeCap("BadVibe", error.msg)
    return
  if value.kind != vkInstance: raise runtimeCap("WrongType", "attributes can only be set on clique instances")
  value.fields[name] = newValue

proc hasYield(stmts: seq[Stmt]): bool =
  for stmt in stmts:
    case stmt.kind
    of skYield: return true
    of skIf:
      for clause in stmt.clauses:
        if hasYield(clause.body): return true
      if hasYield(stmt.elseBody): return true
    of skWhile:
      if hasYield(stmt.wbody): return true
    of skFor:
      if hasYield(stmt.fbody): return true
    of skTry:
      if hasYield(stmt.tbody) or hasYield(stmt.orelse) or hasYield(stmt.finallyB): return true
      for handler in stmt.handlers:
        if hasYield(handler.body): return true
    of skWith:
      if hasYield(stmt.withBody): return true
    of skMatch:
      for matchCase in stmt.mcases:
        if hasYield(matchCase.body): return true
      if hasYield(stmt.mdefault): return true
    of skFuncDef, skClassDef: discard
    else: discard

proc evalExpr(rt: Runtime, env: Env, expr: Expr): Value
proc execBlock(rt: Runtime, env: Env, stmts: seq[Stmt], yields: var seq[Value]): Signal
proc callValue(rt: Runtime, env: Env, callee: Value, args: seq[Value], kwargs: seq[tuple[nm: string, val: Value]]): Value

proc compareValues(a, b: Value): int =
  if a.kind in {vkInt, vkFloat, vkBool} and b.kind in {vkInt, vkFloat, vkBool}:
    return compareNumbers(a, b)
  if a.kind == vkString and b.kind == vkString: return cmp(a.strVal, b.strVal)
  raise runtimeCap("WrongType", "values cannot be ordered")

proc binary(op: string, a, b: Value): Value =
  if op in ["<", ">", "<=", ">="] and
      a.kind in {vkInt, vkFloat, vkBool} and b.kind in {vkInt, vkFloat, vkBool} and
      ((a.kind == vkFloat and a.floatVal.isNaN) or (b.kind == vkFloat and b.floatVal.isNaN)):
    return boolVal(false)
  case op
  of "and": return if a.truthy: b else: a
  of "or": return if a.truthy: a else: b
  of "==": return boolVal(equal(a, b))
  of "!=": return boolVal(not equal(a, b))
  of "is": return boolVal(a == b or (a.kind == vkNone and b.kind == vkNone))
  of "is not": return boolVal(not (a == b or (a.kind == vkNone and b.kind == vkNone)))
  of "in": return boolVal(contains(b, a))
  of "not in": return boolVal(not contains(b, a))
  of "<": return boolVal(compareValues(a, b) < 0)
  of ">": return boolVal(compareValues(a, b) > 0)
  of "<=": return boolVal(compareValues(a, b) <= 0)
  of ">=": return boolVal(compareValues(a, b) >= 0)
  else: discard

  if op == "+":
    if a.kind == vkString and b.kind == vkString: return stringVal(a.strVal & b.strVal)
    if a.kind == vkList and b.kind == vkList: return listVal(a.items & b.items)
    if a.kind == vkTuple and b.kind == vkTuple: return tupleVal(a.items & b.items)
  if op == "*":
    if a.kind == vkString and b.kind == vkInt: return stringVal(a.strVal.repeat(b.intVal.int))
    if b.kind == vkString and a.kind == vkInt: return stringVal(b.strVal.repeat(a.intVal.int))
    if a.kind == vkList and b.kind == vkInt:
      var items: seq[Value]
      for _ in 0 ..< b.intVal.int: items.add a.items
      return listVal(items)
  if a.kind notin {vkInt, vkFloat, vkBool} or b.kind notin {vkInt, vkFloat, vkBool}:
    raise runtimeCap("WrongType", "operator '" & op & "' does not support these values")
  let bothInts = a.kind in {vkInt, vkBool} and b.kind in {vkInt, vkBool}
  case op
  of "+":
    if bothInts: intVal(checkedAdd(a.asInt, b.asInt)) else: floatVal(a.numeric + b.numeric)
  of "-":
    if bothInts: intVal(checkedSub(a.asInt, b.asInt)) else: floatVal(a.numeric - b.numeric)
  of "*":
    if bothInts: intVal(checkedMul(a.asInt, b.asInt)) else: floatVal(a.numeric * b.numeric)
  of "/":
    if b.numeric == 0: raise runtimeCap("SplitByZero", "division by zero")
    floatVal(a.numeric / b.numeric)
  of "//":
    if b.numeric == 0: raise runtimeCap("SplitByZero", "integer division by zero")
    if bothInts:
      let x = a.asInt
      let y = b.asInt
      if x == low(int64) and y == -1:
        raise runtimeCap("BadVibe", "integer division exceeds int64 range")
      var quotient = x div y
      if x mod y != 0 and (x < 0) != (y < 0): dec quotient
      intVal(quotient)
    else: floatVal(floor(a.numeric / b.numeric))
  of "%":
    if b.numeric == 0: raise runtimeCap("SplitByZero", "modulo by zero")
    if bothInts:
      let x = a.asInt
      let y = b.asInt
      if y == -1: return intVal(0)
      var remainder = x mod y
      if remainder != 0 and (remainder < 0) != (y < 0): remainder += y
      intVal(remainder)
    else: floatVal(a.numeric - floor(a.numeric / b.numeric) * b.numeric)
  of "**":
    if bothInts and b.asInt >= 0: intVal(checkedPow(a.asInt, b.asInt))
    else: floatVal(pow(a.numeric, b.numeric))
  else: raise runtimeCap("BadVibe", "unknown operator '" & op & "'")

proc formatValue(value: Value, spec: string): string =
  if spec.len == 0: return display(value)
  if spec == "!r": return repr(value)
  var fmt = spec
  if fmt.startsWith(":"): fmt = fmt[1 .. ^1]
  if fmt.endsWith("d") and value.kind == vkInt:
    let widthText = fmt[0 ..< fmt.len - 1]
    if widthText.len > 0:
      let width = parseInt(widthText.strip(chars = {'0'}))
      let padding = if fmt.startsWith("0"): '0' else: ' '
      return ($value.intVal).align(width, padding)
  display(value)

proc decodeEscapes(source: string): string =
  var i = 0
  while i < source.len:
    if source[i] == '\\' and i + 1 < source.len:
      case source[i + 1]
      of 'n': result.add '\n'
      of 'r': result.add '\r'
      of 't': result.add '\t'
      of '\\': result.add '\\'
      of '\'': result.add '\''
      of '"': result.add '"'
      else: result.add '\\'; result.add source[i + 1]
      i += 2
    else:
      result.add source[i]
      inc i

proc evalComprehension(rt: Runtime, env: Env, expr: Expr, clauseIndex: int,
                       output: var seq[Value]) =
  if clauseIndex >= expr.cclauses.len:
    output.add rt.evalExpr(env, expr.celt)
    return
  let clause = expr.cclauses[clauseIndex]
  for item in iterable(rt.evalExpr(env, clause.iter)):
    if clause.targets.len == 1:
      env.values[clause.targets[0]] = item
    else:
      let values = iterable(item)
      if values.len != clause.targets.len: raise runtimeCap("BadVibe", "cannot unpack comprehension value")
      for i, name in clause.targets: env.values[name] = values[i]
    if clause.cond == nil or rt.evalExpr(env, clause.cond).truthy:
      rt.evalComprehension(env, expr, clauseIndex + 1, output)

proc builtinNamed(name: string): Value =
  const names = ["how many", "vibes", "num", "drip", "text", "truth", "stack", "map",
    "squad", "crew", "add up", "least", "most", "positive", "ranked", "index up",
    "link", "unlock", "round up", "vibe check", "yap", "yap back",
    "L", "BadVibe", "WrongType", "OutOfPocket", "Ghosted", "SplitByZero",
    "NoPullUp", "CapDetected", "StopTheCap"]
  if name in names: return builtinValue(name)

proc evalExpr(rt: Runtime, env: Env, expr: Expr): Value =
  if expr == nil: return noneVal()
  case expr.kind
  of ekNum:
    if anyIt(expr.s, it in {'.', 'e', 'E'}): floatVal(parseFloat(expr.s))
    else: intVal(parseBiggestInt(expr.s).int64)
  of ekStr:
    stringVal(decodeEscapes(expr.s))
  of ekBool: boolVal(expr.s == "True")
  of ekNone: noneVal()
  of ekName:
    let native = builtinNamed(expr.s)
    if native != nil: native else: env.lookup(expr.s)
  of ekSelf: env.lookup("fam")
  of ekFStr:
    var text = ""
    for part in expr.parts:
      if part.isExpr: text.add formatValue(rt.evalExpr(env, part.ex), part.spec)
      else: text.add decodeEscapes(part.text)
    stringVal(text)
  of ekList:
    var items: seq[Value]
    for item in expr.items: items.add rt.evalExpr(env, item)
    listVal(items)
  of ekSet:
    var items: seq[Value]
    for item in expr.items: items.add rt.evalExpr(env, item)
    setVal(unique(items))
  of ekTuple:
    var items: seq[Value]
    for item in expr.items: items.add rt.evalExpr(env, item)
    tupleVal(items)
  of ekDict:
    let mapValue = dictVal()
    for i in 0 ..< expr.dkeys.len:
      let key = rt.evalExpr(env, expr.dkeys[i])
      let value = rt.evalExpr(env, expr.dvals[i])
      let at = mapValue.dictIndex(key)
      if at >= 0: mapValue.pairs[at].val = value else: mapValue.pairs.add (key, value)
    mapValue
  of ekUnary:
    let value = rt.evalExpr(env, expr.uoperand)
    case expr.uop
    of "not ": boolVal(not value.truthy)
    of "-":
      if value.kind == vkInt: intVal(checkedSub(0, value.intVal)) else: floatVal(-value.numeric)
    of "+":
      if value.kind == vkInt: value else: floatVal(value.numeric)
    of "*", "**": value
    else: raise runtimeCap("BadVibe", "unknown unary operator")
  of ekBinary:
    let left = rt.evalExpr(env, expr.blhs)
    if expr.bop == "and" and not left.truthy: return left
    if expr.bop == "or" and left.truthy: return left
    binary(expr.bop, left, rt.evalExpr(env, expr.brhs))
  of ekCall:
    var args: seq[Value]
    var kwargs: seq[tuple[nm: string, val: Value]]
    for arg in expr.cargs:
      if arg.kind == ekUnary and arg.uop == "*": args.add iterable(rt.evalExpr(env, arg.uoperand))
      elif arg.kind == ekUnary and arg.uop == "**":
        let unpacked = rt.evalExpr(env, arg.uoperand)
        if unpacked.kind != vkDict: raise runtimeCap("WrongType", "** needs a map")
        for pair in unpacked.pairs:
          if pair.key.kind != vkString: raise runtimeCap("WrongType", "** map keys must be text")
          kwargs.add (pair.key.strVal, pair.val)
      else: args.add rt.evalExpr(env, arg)
    for kw in expr.ckwargs: kwargs.add (kw.nm, rt.evalExpr(env, kw.val))
    let callee = rt.evalExpr(env, expr.callee)
    try:
      rt.callValue(env, callee, args, kwargs)
    except RuntimeError as error:
      let filename = if rt.moduleStack.len > 0: rt.moduleStack[^1] else: rt.filename
      let name = case callee.kind
        of vkFunction: callee.fn.name
        of vkBuiltin: callee.builtin
        of vkClass: callee.klass.name
        else: "<call>"
      error.frames.add (filename, expr.line, expr.col, name)
      raise
  of ekAttr: getAttr(rt.evalExpr(env, expr.aobj), expr.aname)
  of ekSub: getItem(rt.evalExpr(env, expr.sobj), rt.evalExpr(env, expr.sidx))
  of ekSlice:
    sliceValue(rt.evalExpr(env, expr.ssliceObj),
      (if expr.slo == nil: nil else: rt.evalExpr(env, expr.slo)),
      (if expr.shi == nil: nil else: rt.evalExpr(env, expr.shi)),
      (if expr.sstep == nil: nil else: rt.evalExpr(env, expr.sstep)))
  of ekLambda:
    var defaults: seq[Value]
    for param in expr.lparams:
      defaults.add(if param.default == nil: nil else: rt.evalExpr(env, param.default))
    Value(kind: vkFunction, fn: NativeFunction(name: "<mini vibe>", params: expr.lparams,
      defaults: defaults, body: @[], closure: env, isGenerator: false,
      lambdaBody: expr.lbody, filename: rt.moduleStack[^1]))
  of ekAwait: rt.evalExpr(env, expr.wexpr)
  of ekYield: rt.evalExpr(env, expr.yexpr)
  of ekComp:
    let scope = newEnv(env)
    var output: seq[Value]
    rt.evalComprehension(scope, expr, 0, output)
    listVal(output)

proc bindTargets(env: Env, names: seq[string], value: Value) =
  if names.len == 1:
    env.values[names[0]] = value
    return
  let values = iterable(value)
  if values.len != names.len: raise runtimeCap("BadVibe", "cannot unpack value")
  for i, name in names: env.values[name] = values[i]

proc setTarget(rt: Runtime, env: Env, target: Expr, value: Value) =
  case target.kind
  of ekName: env.assignName(target.s, value)
  of ekSelf: env.assignName("fam", value)
  of ekAttr: setAttr(rt.evalExpr(env, target.aobj), target.aname, value)
  of ekSub:
    let obj = rt.evalExpr(env, target.sobj)
    let index = rt.evalExpr(env, target.sidx)
    case obj.kind
    of vkList:
      var at = index.asInt.int
      if at < 0: at += obj.items.len
      if at < 0 or at >= obj.items.len: raise runtimeCap("OutOfPocket", "index out of range")
      obj.items[at] = value
    of vkDict:
      let at = obj.dictIndex(index)
      if at >= 0: obj.pairs[at].val = value else: obj.pairs.add (index, value)
    else: raise runtimeCap("WrongType", "value does not support item assignment")
  of ekTuple, ekList:
    let values = iterable(value)
    if values.len != target.items.len: raise runtimeCap("BadVibe", "cannot unpack value")
    for i, item in target.items: rt.setTarget(env, item, values[i])
  else: raise runtimeCap("BadVibe", "invalid assignment target")

proc delTarget(rt: Runtime, env: Env, target: Expr) =
  case target.kind
  of ekName:
    let owner = env.findEnv(target.s)
    if owner == nil: raise runtimeCap("Ghosted", "name '" & target.s & "' is not defined")
    owner.values.del(target.s)
  of ekAttr:
    let obj = rt.evalExpr(env, target.aobj)
    if obj.kind != vkInstance or not obj.fields.hasKey(target.aname): raise runtimeCap("Ghosted", "attribute not found")
    obj.fields.del(target.aname)
  of ekSub:
    let obj = rt.evalExpr(env, target.sobj)
    let index = rt.evalExpr(env, target.sidx)
    if obj.kind == vkDict:
      let at = obj.dictIndex(index)
      if at < 0: raise runtimeCap("Ghosted", display(index))
      obj.pairs.delete(at)
    elif obj.kind == vkList:
      var at = index.asInt.int
      if at < 0: at += obj.items.len
      obj.items.delete(at)
    else: raise runtimeCap("WrongType", "value does not support deletion")
  else: raise runtimeCap("BadVibe", "invalid cancel target")

proc exceptionMatches(rt: Runtime, env: Env, handler: Handler, error: ref RuntimeError): bool =
  if handler.etype == nil: return true
  if handler.etype.kind == ekName:
    return handler.etype.s == error.category or handler.etype.s == "L"
  false

proc gameModule(rt: Runtime): Value =
  if rt.gameContext == nil: rt.gameContext = newGameContext()
  result = Value(kind: vkModule, strVal: "rizzgame", moduleEnv: newEnv())
  for spec in GameSpecs:
    let name = spec.split(':')[0]
    if '.' in name and name[0].isUpperAscii(): continue # object methods
    let parts = name.split('.')
    var scope = result.moduleEnv
    for i in 0..<parts.len-1:
      if not scope.values.hasKey(parts[i]):
        scope.declare(parts[i], Value(kind: vkModule, strVal: "rizzgame." & parts[i], moduleEnv: newEnv()))
      scope = scope.values[parts[i]].moduleEnv
    scope.declare(parts[^1], builtinValue("rizzgame." & name))
  for constant in gameConstants(): result.moduleEnv.declare(constant.name, intVal(constant.value))

proc nativeModule(rt: Runtime, name: string): Value =
  if name == "rizzgame": return rt.gameModule()
  if name.startsWith("rizzgame."):
    let root = rt.gameModule()
    let child = name[9 .. ^1]
    if root.moduleEnv.values.hasKey(child) and root.moduleEnv.values[child].kind == vkModule:
      return root.moduleEnv.values[child]
    raise runtimeCap("NoPullUp", "unknown rizzgame module: " & child)
  let env = newEnv()
  case name
  of "math":
    for fn in ["floor", "ceil", "sqrt", "pow", "isfinite", "isnan", "isinf"]:
      env.declare(fn, builtinValue("math." & fn))
    env.declare("pi", floatVal(PI)); env.declare("e", floatVal(E))
  of "timing":
    env.declare("sleep", builtinValue("timing.sleep")); env.declare("run", builtinValue("timing.run"))
  of "clock":
    env.declare("time", builtinValue("clock.time")); env.declare("sleep", builtinValue("clock.sleep"))
    env.declare("monotonic", builtinValue("clock.monotonic"))
  of "luck":
    env.declare("manifest", builtinValue("luck.manifest"))
    env.declare("shuffle", builtinValue("luck.shuffle")); env.declare("sample", builtinValue("luck.sample"))
    env.declare("random", builtinValue("luck.random")); env.declare("randint", builtinValue("luck.randint")); env.declare("choice", builtinValue("luck.choice"))
  of "system":
    env.declare("args", listVal(rt.args.mapIt(stringVal(it))))
    env.declare("cwd", builtinValue("system.cwd")); env.declare("getenv", builtinValue("system.getenv")); env.declare("exit", builtinValue("system.exit"))
  of "json":
    env.declare("parse", builtinValue("json.parse")); env.declare("stringify", builtinValue("json.stringify"))
  of "path":
    for fn in ["join", "exists", "is_file", "is_dir", "basename", "dirname", "extension", "absolute"]:
      env.declare(fn, builtinValue("path." & fn))
  of "encoding":
    env.declare("base64_encode", builtinValue("encoding.base64_encode"))
    env.declare("base64_decode", builtinValue("encoding.base64_decode"))
  else: return nil
  Value(kind: vkModule, strVal: name, moduleEnv: env)

proc pythonProxyModule(name: string): Value =
  if not name.startsWith("py.") or name.len <= 3: return nil
  Value(kind: vkModule, strVal: name, moduleEnv: newEnv())

proc loadModule(rt: Runtime, name: string): Value =
  if rt.moduleCache.hasKey(name): return rt.moduleCache[name]
  let native = rt.nativeModule(name)
  if native != nil:
    rt.moduleCache[name] = native
    return native
  let pythonProxy = pythonProxyModule(name)
  if pythonProxy != nil:
    rt.moduleCache[name] = pythonProxy
    return pythonProxy
  let relative = name.replace(".", $DirSep) & ".gzim"
  var path = relative
  let base = if rt.moduleStack.len > 0: parentDir(rt.moduleStack[^1]) else: parentDir(rt.filename)
  if fileExists(base / relative): path = base / relative
  elif not fileExists(path):
    let project = findProjectRoot(base)
    var found = ""
    if project != "":
      let parts = name.split('.')
      let dependency = packageRoot(project) / parts[0]
      let rest = if parts.len > 1: parts[1 .. ^1].join($DirSep) & ".gzim" else: parts[0] & ".gzim"
      for candidate in [dependency / relative, dependency / rest,
                        dependency / "src" / relative, dependency / "src" / rest,
                        dependency / "main.gzim"]:
        if fileExists(candidate): found = candidate; break
    if found == "": raise runtimeCap("NoPullUp", "no native module called '" & name & "'")
    path = found
  let source = readFile(path)
  let parsed = parseProgram(lex(source))
  let issues = checkProgram(parsed.program)
  if issues.len > 0: raise runtimeCap("BadVibe", path & ":" & $issues[0].line & ":" & $issues[0].col & ": " & issues[0].msg)
  let moduleEnv = newEnv()
  let module = Value(kind: vkModule, strVal: name, moduleEnv: moduleEnv)
  rt.moduleCache[name] = module
  rt.moduleStack.add path
  defer: discard rt.moduleStack.pop()
  var yielded: seq[Value]
  try:
    discard rt.execBlock(moduleEnv, parsed.program, yielded)
  except:
    rt.moduleCache.del(name)
    raise
  module

proc execStmt(rt: Runtime, env: Env, stmt: Stmt, yields: var seq[Value]): Signal =
  case stmt.kind
  of skExpr:
    discard rt.evalExpr(env, stmt.e)
  of skVarDecl:
    env.declare(stmt.vname, if stmt.vvalue == nil: noneVal() else: rt.evalExpr(env, stmt.vvalue), stmt.isConst)
  of skAssign:
    var value = rt.evalExpr(env, stmt.value)
    if stmt.op != "": value = binary(stmt.op, rt.evalExpr(env, stmt.target), value)
    rt.setTarget(env, stmt.target, value)
  of skIf:
    var ran = false
    for clause in stmt.clauses:
      if rt.evalExpr(env, clause.cond).truthy:
        ran = true
        let signal = rt.execBlock(env, clause.body, yields)
        if signal.kind != sigNone: return signal
        break
    if not ran and stmt.hasElse:
      return rt.execBlock(env, stmt.elseBody, yields)
  of skWhile:
    while rt.evalExpr(env, stmt.wcond).truthy:
      let signal = rt.execBlock(env, stmt.wbody, yields)
      if signal.kind == sigBreak: break
      if signal.kind == sigContinue: continue
      if signal.kind != sigNone: return signal
  of skFor:
    for item in iterable(rt.evalExpr(env, stmt.fiter)):
      env.bindTargets(stmt.ftargets, item)
      let signal = rt.execBlock(env, stmt.fbody, yields)
      if signal.kind == sigBreak: break
      if signal.kind == sigContinue: continue
      if signal.kind != sigNone: return signal
  of skFuncDef:
    var defaults: seq[Value]
    for param in stmt.fparams:
      defaults.add(if param.default == nil: nil else: rt.evalExpr(env, param.default))
    let fn = NativeFunction(name: stmt.fname, params: stmt.fparams, defaults: defaults,
      body: stmt.fndefBody, closure: env, isGenerator: hasYield(stmt.fndefBody), isAsync: stmt.isAsync,
      filename: rt.moduleStack[^1])
    env.declare(stmt.fname, Value(kind: vkFunction, fn: fn))
  of skClassDef:
    var base: NativeClass
    if stmt.cbases.len > 0:
      let baseVal = rt.evalExpr(env, stmt.cbases[0])
      if baseVal.kind != vkClass: raise runtimeCap("WrongType", "clique base must be another clique")
      base = baseVal.klass
    let klass = NativeClass(name: stmt.cname, base: base, methods: initTable[string, NativeFunction]())
    let classEnv = newEnv(env)
    for child in stmt.cbody:
      if child.kind == skFuncDef:
        var defaults: seq[Value]
        for param in child.fparams:
          defaults.add(if param.default == nil: nil else: rt.evalExpr(env, param.default))
        klass.methods[child.fname] = NativeFunction(name: child.fname, params: child.fparams,
          defaults: defaults, body: child.fndefBody, closure: classEnv,
          isGenerator: hasYield(child.fndefBody), isAsync: child.isAsync, filename: rt.moduleStack[^1])
      elif child.kind == skVarDecl:
        classEnv.declare(child.vname, if child.vvalue == nil: noneVal() else: rt.evalExpr(classEnv, child.vvalue), child.isConst)
    env.declare(stmt.cname, Value(kind: vkClass, klass: klass))
  of skReturn:
    return Signal(kind: sigReturn, value: if stmt.re == nil: noneVal() else: rt.evalExpr(env, stmt.re))
  of skBreak: return Signal(kind: sigBreak)
  of skContinue: return Signal(kind: sigContinue)
  of skPass: discard
  of skRaise:
    if stmt.rae == nil:
      if rt.activeException == nil: raise runtimeCap("L", "no active cap to throw again")
      raise runtimeCap(rt.activeException.builtin, rt.activeException.strVal, stmt.line, stmt.col)
    let error = rt.evalExpr(env, stmt.rae)
    if error.kind != vkException: raise runtimeCap("WrongType", "throw shade needs an exception")
    raise runtimeCap(error.builtin, error.strVal, stmt.line, stmt.col)
  of skTry:
    var bodySignal = Signal(kind: sigNone)
    let previousException = rt.activeException
    try:
      try:
        var succeeded = false
        try:
          bodySignal = rt.execBlock(env, stmt.tbody, yields)
          succeeded = true
        except RuntimeError as error:
          rt.activeException = Value(kind: vkException, builtin: error.category, strVal: error.msg)
          var handled = false
          for handler in stmt.handlers:
            if rt.exceptionMatches(env, handler, error):
              handled = true
              if handler.alias != "": env.values[handler.alias] = rt.activeException
              bodySignal = rt.execBlock(env, handler.body, yields)
              break
          if not handled: raise
          rt.activeException = previousException
        if succeeded and stmt.orelse.len > 0 and bodySignal.kind == sigNone:
          bodySignal = rt.execBlock(env, stmt.orelse, yields)
      except RuntimeError as error:
        rt.activeException = Value(kind: vkException, builtin: error.category, strVal: error.msg)
        raise
      finally:
        if stmt.finallyB.len > 0:
          let finalSignal = rt.execBlock(env, stmt.finallyB, yields)
          if finalSignal.kind != sigNone: return finalSignal
    finally:
      rt.activeException = previousException
    if bodySignal.kind != sigNone: return bodySignal
  of skWith:
    var resources: seq[Value]
    for item in stmt.witems:
      let resource = rt.evalExpr(env, item.ctx)
      resources.add resource
      if item.alias != "": env.values[item.alias] = resource
    try:
      result = rt.execBlock(env, stmt.withBody, yields)
    finally:
      for resource in resources:
        if resource.kind == vkFile and resource.fileOpen:
          close(resource.fileHandle); resource.fileOpen = false
    return result
  of skImport:
    let importName = if stmt.ialias != "": stmt.ialias
      elif stmt.imod.startsWith("py."): stmt.imod.split('.')[^1]
      else: stmt.imod.split('.')[0]
    env.declare(importName, rt.loadModule(stmt.imod))
  of skFromImport:
    let module = rt.loadModule(stmt.fmod)
    for imported in stmt.fnames:
      if imported.nm == "*":
        for name, value in module.moduleEnv.values:
          if not name.startsWith("_"): env.declare(name, value)
      else:
        env.declare(if imported.alias != "": imported.alias else: imported.nm, getAttr(module, imported.nm))
  of skMatch:
    let subject = rt.evalExpr(env, stmt.msubject)
    var matched = false
    for matchCase in stmt.mcases:
      if equal(subject, rt.evalExpr(env, matchCase.pattern)):
        matched = true
        let signal = rt.execBlock(env, matchCase.body, yields)
        if signal.kind != sigNone: return signal
        break
    if not matched and stmt.hasDefault: return rt.execBlock(env, stmt.mdefault, yields)
  of skDelete:
    for target in stmt.dtargets: rt.delTarget(env, target)
  of skAssert:
    if not rt.evalExpr(env, stmt.acond).truthy:
      let message = if stmt.amsg == nil: "assertion failed" else: display(rt.evalExpr(env, stmt.amsg))
      raise runtimeCap("CapDetected", message, stmt.line, stmt.col)
  of skGlobal:
    for name in stmt.gnames: env.globals.incl(name)
  of skNonlocal:
    for name in stmt.gnames: env.nonlocals.incl(name)
  of skYield:
    yields.add(if stmt.ye == nil: noneVal() else: rt.evalExpr(env, stmt.ye))

proc execBlock(rt: Runtime, env: Env, stmts: seq[Stmt], yields: var seq[Value]): Signal =
  for stmt in stmts:
    try:
      let signal = rt.execStmt(env, stmt, yields)
      if signal.kind != sigNone: return signal
    except RuntimeError as error:
      if error.line == 0:
        error.line = stmt.line
        error.col = stmt.col
      if error.filename == "": error.filename = rt.moduleStack[^1]
      raise
  Signal(kind: sigNone)

proc requireArgs(name: string, args: seq[Value], low: int, high = -1) =
  let maxArgs = if high < 0: low else: high
  if args.len < low or args.len > maxArgs:
    raise runtimeCap("WrongType", name & " expected " & $low & (if maxArgs != low: ".." & $maxArgs else: "") & " arguments, got " & $args.len)

proc valueToJson(value: Value): JsonNode =
  case value.kind
  of vkNone: result = newJNull()
  of vkBool: result = %value.boolVal
  of vkInt: result = %value.intVal
  of vkFloat: result = %value.floatVal
  of vkString: result = %value.strVal
  of vkList, vkTuple, vkSet:
    result = newJArray()
    for item in value.items: result.add valueToJson(item)
  of vkDict:
    result = newJObject()
    for pair in value.pairs:
      if pair.key.kind != vkString:
        raise runtimeCap("WrongType", "Python bridge maps need text keys")
      result[pair.key.strVal] = valueToJson(pair.val)
  else:
    raise runtimeCap("WrongType", "Python bridge cannot send " & $value.kind)

proc jsonToValue(node: JsonNode): Value =
  case node.kind
  of JNull: result = noneVal()
  of JBool: result = boolVal(node.getBool())
  of JInt: result = intVal(node.getBiggestInt().int64)
  of JFloat: result = floatVal(node.getFloat())
  of JString: result = stringVal(node.getStr())
  of JArray:
    var items: seq[Value]
    for item in node: items.add jsonToValue(item)
    result = listVal(items)
  of JObject:
    let value = dictVal()
    for key, item in node: value.pairs.add (stringVal(key), jsonToValue(item))
    result = value

proc fromGame(value: GameValue): Value =
  if value.obj != nil: return Value(kind: vkGame, gameObject: value.obj)
  let node = value.data
  if node == nil: return noneVal()
  if node.kind == JArray:
    var items: seq[Value]
    for item in node: items.add fromGame(GameValue(data: item))
    return listVal(items)
  if node.kind == JObject and node.hasKey("$event"):
    let scope = newEnv()
    for key, item in node:
      if key != "$event": scope.declare(key, jsonToValue(item))
    return Value(kind: vkModule, strVal: "rizzgame.Event", moduleEnv: scope)
  jsonToValue(node)

proc toGame(value: Value): GameValue =
  if value.kind == vkGame: return GameValue(obj: value.gameObject)
  if value.kind notin {vkNone, vkBool, vkInt, vkFloat, vkString, vkList, vkTuple, vkDict}:
    raise runtimeCap("WrongType", "unsupported rizzgame argument: " & $value.kind)
  GameValue(data: valueToJson(value))

const PythonBridgeScript = """
import contextlib, importlib, io, json, sys

def normalize(value):
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    if isinstance(value, (list, tuple, set)):
        return [normalize(item) for item in value]
    if isinstance(value, dict):
        return {str(key): normalize(item) for key, item in value.items()}
    if hasattr(value, "tolist"):
        return normalize(value.tolist())
    if hasattr(value, "item"):
        try:
            return normalize(value.item())
        except Exception:
            pass
    return {"__python_type__": type(value).__name__, "__python_repr__": repr(value)}

try:
    request = json.loads(sys.stdin.read())
    target = importlib.import_module(request["module"])
    for part in request["path"].split("."):
        target = getattr(target, part)
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured):
        value = target(*request.get("args", []), **request.get("kwargs", {}))
    print(json.dumps({"ok": True, "value": normalize(value), "stdout": captured.getvalue()}))
except Exception as error:
    print(json.dumps({"ok": False, "type": type(error).__name__, "error": str(error)}))
"""

proc findPython(): tuple[exe: string, prefix: seq[string]] =
  for candidate in ["python3", "python"]:
    let found = findExe(candidate)
    if found != "": return (found, @[])
  when defined(windows):
    let launcher = findExe("py")
    if launcher != "": return (launcher, @["-3"])

proc invokePython(moduleName, path: string, args: seq[Value],
                  kwargs: seq[tuple[nm: string, val: Value]]): Value =
  let python = findPython()
  if python.exe == "":
    raise runtimeCap("NoPullUp", "Python bridge needs Python 3 on PATH; native Genzimnify itself does not")
  var request = newJObject()
  request["module"] = %moduleName
  request["path"] = %path
  request["args"] = newJArray()
  for arg in args: request["args"].add valueToJson(arg)
  request["kwargs"] = newJObject()
  for kw in kwargs: request["kwargs"][kw.nm] = valueToJson(kw.val)

  var processArgs = python.prefix
  processArgs.add @["-c", PythonBridgeScript]
  let process = startProcess(python.exe, args = processArgs,
    options = {poUsePath, poStdErrToStdOut})
  process.inputStream.write($request)
  process.inputStream.close()
  let output = process.outputStream.readAll().strip()
  let exitCode = process.waitForExit()
  process.close()
  if exitCode != 0 or output == "":
    raise runtimeCap("NoPullUp", "Python bridge process failed: " & output)
  var response: JsonNode
  try: response = parseJson(output)
  except JsonParsingError:
    raise runtimeCap("BadVibe", "Python library wrote invalid bridge output: " & output)
  if not response{"ok"}.getBool(false):
    raise runtimeCap("BadVibe", "Python " & response{"type"}.getStr("error") & ": " & response{"error"}.getStr("unknown error"))
  let captured = response{"stdout"}.getStr("")
  if captured != "": stdout.write(captured)
  jsonToValue(response["value"])

proc invokeBuiltin(rt: Runtime, env: Env, callee: Value, args: seq[Value],
                   kwargs: seq[tuple[nm: string, val: Value]] = @[]): Value =
  let name = callee.builtin
  let self = callee.boundSelf
  if name.startsWith("rizzgame."):
    if rt.gameContext == nil: rt.gameContext = newGameContext()
    var positional: seq[GameValue]
    if self != nil: positional.add toGame(self)
    for arg in args: positional.add toGame(arg)
    var named: seq[tuple[name: string, val: GameValue]]
    for kw in kwargs: named.add (kw.nm, toGame(kw.val))
    try: return fromGame(game.call(rt.gameContext, name[9 .. ^1], positional, named))
    except ValueError as error: raise runtimeCap("BadVibe", error.msg)
  if name.startsWith("python:"):
    let parts = name.split(':', maxsplit = 2)
    return invokePython(parts[1], parts[2], args, kwargs)
  if name.startsWith("ancestor."):
    let instance = env.lookup("fam")
    if instance.kind != vkInstance or instance.klass.base == nil:
      raise runtimeCap("BadVibe", "ancestor needs a base clique")
    let methodName = name["ancestor.".len .. ^1]
    let fn = instance.klass.base.findMethod(methodName)
    if fn == nil: raise runtimeCap("Ghosted", "ancestor has no method '" & methodName & "'")
    let forwarded = if args.len > 0 and args[0] == instance: args[1 .. ^1] else: args
    return rt.callValue(env, Value(kind: vkFunction, fn: fn, boundSelf: instance), forwarded, kwargs)
  for kw in kwargs:
    if not ((name == "yap" and kw.nm in ["glue", "micdrop"]) or
            (name == "ranked" and kw.nm == "uno_reverse")):
      raise runtimeCap("WrongType", name & " got unexpected argument '" & kw.nm & "'")
  case name
  of "yap":
    var parts: seq[string]
    for arg in args: parts.add display(arg)
    var glue = " "
    var micdrop = "\n"
    for kw in kwargs:
      if kw.val.kind != vkString: raise runtimeCap("WrongType", kw.nm & " expects text")
      if kw.nm == "glue": glue = kw.val.strVal
      else: micdrop = kw.val.strVal
    stdout.write(parts.join(glue) & micdrop)
    return noneVal()
  of "yap back":
    if args.len > 0: stdout.write(display(args[0])); flushFile(stdout)
    return stringVal(stdin.readLine())
  of "how many":
    requireArgs(name, args, 1)
    case args[0].kind
    of vkString: return intVal(args[0].strVal.len)
    of vkList, vkTuple, vkSet: return intVal(args[0].items.len)
    of vkDict: return intVal(args[0].pairs.len)
    else: raise runtimeCap("WrongType", "how many needs a collection")
  of "vibes":
    if args.len < 1 or args.len > 3: raise runtimeCap("WrongType", "vibes expects 1..3 arguments")
    var start = 0'i64
    var stop = args[0].asInt
    var step = 1'i64
    if args.len >= 2: start = args[0].asInt; stop = args[1].asInt
    if args.len == 3: step = args[2].asInt
    if step == 0: raise runtimeCap("BadVibe", "vibes step cannot be zero")
    var items: seq[Value]
    var current = start
    if step > 0:
      while current < stop: items.add intVal(current); current += step
    else:
      while current > stop: items.add intVal(current); current += step
    return listVal(items)
  of "num":
    requireArgs(name, args, 1)
    case args[0].kind
    of vkString: return intVal(parseBiggestInt(args[0].strVal).int64)
    else: return intVal(args[0].asInt)
  of "drip":
    requireArgs(name, args, 1)
    return if args[0].kind == vkString: floatVal(parseFloat(args[0].strVal)) else: floatVal(args[0].numeric)
  of "text": requireArgs(name, args, 1); return stringVal(display(args[0]))
  of "truth": requireArgs(name, args, 1); return boolVal(args[0].truthy)
  of "stack": requireArgs(name, args, 1); return listVal(iterable(args[0]))
  of "crew": requireArgs(name, args, 1); return tupleVal(iterable(args[0]))
  of "squad": requireArgs(name, args, 1); return setVal(unique(iterable(args[0])))
  of "map":
    if args.len == 0: return dictVal()
    elif args.len == 1 and args[0].kind == vkDict: return dictVal(args[0].pairs)
    else: raise runtimeCap("WrongType", "map expects zero args or another map")
  of "add up":
    requireArgs(name, args, 1)
    var total = intVal(0)
    for item in iterable(args[0]): total = binary("+", total, item)
    return total
  of "least", "most":
    requireArgs(name, args, 1)
    let values = iterable(args[0])
    if values.len == 0: raise runtimeCap("BadVibe", name & " needs at least one value")
    result = values[0]
    for item in values[1 .. ^1]:
      if (name == "least" and compareValues(item, result) < 0) or (name == "most" and compareValues(item, result) > 0): result = item
  of "positive":
    requireArgs(name, args, 1)
    return if args[0].kind == vkInt:
      intVal(if args[0].intVal < 0: checkedSub(0, args[0].intVal) else: args[0].intVal)
    else: floatVal(abs(args[0].numeric))
  of "ranked":
    requireArgs(name, args, 1)
    var values = iterable(args[0])
    var descending = false
    for kw in kwargs:
      if kw.val.kind != vkBool: raise runtimeCap("WrongType", "uno_reverse expects nocap or cap")
      descending = kw.val.boolVal
    values.sort(proc(a, b: Value): int =
      if descending: compareValues(b, a) else: compareValues(a, b))
    return listVal(values)
  of "index up":
    if args.len < 1 or args.len > 2: raise runtimeCap("WrongType", "index up expects 1..2 arguments")
    let start = if args.len == 2: args[1].asInt else: 0
    var values: seq[Value]
    for i, item in iterable(args[0]): values.add tupleVal(@[intVal(start + i), item])
    return listVal(values)
  of "link":
    if args.len == 0: return listVal()
    var sequences: seq[seq[Value]]
    var length = high(int)
    for arg in args:
      let values = iterable(arg)
      sequences.add values
      length = min(length, values.len)
    var rows: seq[Value]
    for i in 0 ..< length:
      var row: seq[Value]
      for values in sequences: row.add values[i]
      rows.add tupleVal(row)
    return listVal(rows)
  of "round up":
    if args.len < 1 or args.len > 2: raise runtimeCap("WrongType", "round up expects 1..2 arguments")
    let digits = if args.len == 2: args[1].asInt.int else: 0
    let factor = pow(10.0, digits.float64)
    let rounded = round(args[0].numeric * factor) / factor
    return if digits == 0: intVal(checkedFloatInt(rounded)) else: floatVal(rounded)
  of "vibe check": requireArgs(name, args, 1); return stringVal($args[0].kind)
  of "unlock":
    if args.len < 1 or args.len > 2 or args[0].kind != vkString: raise runtimeCap("WrongType", "unlock(path, mode) expects text")
    let mode = if args.len == 2: args[1].strVal else: "r"
    var handle: File
    let nimMode = if "a" in mode: fmAppend elif "w" in mode: fmWrite else: fmRead
    if not open(handle, args[0].strVal, nimMode): raise runtimeCap("NoPullUp", "could not open " & args[0].strVal)
    return Value(kind: vkFile, fileHandle: handle, fileOpen: true, strVal: mode)
  of "L", "BadVibe", "WrongType", "OutOfPocket", "Ghosted", "SplitByZero", "NoPullUp", "CapDetected", "StopTheCap":
    return Value(kind: vkException, builtin: name, strVal: if args.len > 0: display(args[0]) else: name)
  of "str.upper": return stringVal(self.strVal.toUpperAscii())
  of "str.lower": return stringVal(self.strVal.toLowerAscii())
  of "str.strip": return stringVal(self.strVal.strip())
  of "str.split":
    let separator = if args.len == 0: " " else: args[0].strVal
    return listVal(self.strVal.split(separator).mapIt(stringVal(it)))
  of "str.replace": requireArgs(name, args, 2); return stringVal(self.strVal.replace(args[0].strVal, args[1].strVal))
  of "str.startswith": requireArgs(name, args, 1); return boolVal(self.strVal.startsWith(args[0].strVal))
  of "str.endswith": requireArgs(name, args, 1); return boolVal(self.strVal.endsWith(args[0].strVal))
  of "str.join": requireArgs(name, args, 1); return stringVal(iterable(args[0]).mapIt(display(it)).join(self.strVal))
  of "list.append": requireArgs(name, args, 1); self.items.add args[0]; return noneVal()
  of "list.extend": requireArgs(name, args, 1); self.items.add iterable(args[0]); return noneVal()
  of "list.insert": requireArgs(name, args, 2); self.items.insert(args[1], args[0].asInt.int); return noneVal()
  of "list.remove":
    requireArgs(name, args, 1)
    for i, item in self.items:
      if equal(item, args[0]): self.items.delete(i); return noneVal()
    raise runtimeCap("BadVibe", "value not in stack")
  of "list.reverse": self.items.reverse(); return noneVal()
  of "list.pop":
    var at = if args.len == 0: self.items.high else: args[0].asInt.int
    if at < 0: at += self.items.len
    if at < 0 or at >= self.items.len: raise runtimeCap("OutOfPocket", "pop index out of range")
    result = self.items[at]; self.items.delete(at)
  of "dict.get":
    if args.len < 1 or args.len > 2: raise runtimeCap("WrongType", "get expects 1..2 arguments")
    let at = self.dictIndex(args[0])
    if at >= 0: return self.pairs[at].val
    elif args.len == 2: return args[1]
    else: return noneVal()
  of "dict.keys": return listVal(self.pairs.mapIt(it.key))
  of "dict.values": return listVal(self.pairs.mapIt(it.val))
  of "dict.items": return listVal(self.pairs.mapIt(tupleVal(@[it.key, it.val])))
  of "dict.pop":
    requireArgs(name, args, 1)
    let at = self.dictIndex(args[0])
    if at < 0: raise runtimeCap("Ghosted", display(args[0]))
    result = self.pairs[at].val; self.pairs.delete(at)
  of "file.read":
    if not self.fileOpen: raise runtimeCap("BadVibe", "file is closed")
    return stringVal(readAll(self.fileHandle))
  of "file.readline":
    if not self.fileOpen: raise runtimeCap("BadVibe", "file is closed")
    var line = ""
    while not self.fileHandle.endOfFile:
      let ch = self.fileHandle.readChar()
      if ch == '\r':
        if not self.fileHandle.endOfFile:
          let next = self.fileHandle.readChar()
          if next != '\n': discard pushbackChar(next.ord.cint, self.fileHandle)
        line.add '\n'
        break
      line.add ch
      if ch == '\n': break
    return stringVal(line)
  of "file.write":
    requireArgs(name, args, 1)
    if not self.fileOpen: raise runtimeCap("BadVibe", "file is closed")
    self.fileHandle.write(display(args[0])); return intVal(display(args[0]).len)
  of "file.close":
    if self.fileOpen: close(self.fileHandle); self.fileOpen = false
    return noneVal()
  of "math.floor":
    requireArgs(name, args, 1)
    return intVal(if args[0].kind == vkInt: args[0].intVal else: checkedFloatInt(floor(args[0].numeric)))
  of "math.ceil":
    requireArgs(name, args, 1)
    return intVal(if args[0].kind == vkInt: args[0].intVal else: checkedFloatInt(ceil(args[0].numeric)))
  of "math.sqrt": requireArgs(name, args, 1); return floatVal(sqrt(args[0].numeric))
  of "math.pow": requireArgs(name, args, 2); return floatVal(pow(args[0].numeric, args[1].numeric))
  of "math.isfinite": requireArgs(name, args, 1); return boolVal(args[0].numeric.classify notin {fcNan, fcInf, fcNegInf})
  of "math.isnan": requireArgs(name, args, 1); return boolVal(args[0].numeric.isNaN)
  of "math.isinf": requireArgs(name, args, 1); return boolVal(args[0].numeric.classify in {fcInf, fcNegInf})
  of "timing.sleep", "clock.sleep":
    requireArgs(name, args, 1)
    let seconds = args[0].numeric
    if seconds.classify in {fcNan, fcInf, fcNegInf} or seconds < 0 or seconds > high(int32).float64 / 1000:
      raise runtimeCap("BadVibe", "sleep expects finite, nonnegative seconds up to 2147483.647")
    sleep(ceil(seconds * 1000).int)
    return noneVal()
  of "timing.run": requireArgs(name, args, 1); return args[0]
  of "clock.time": requireArgs(name, args, 0); return floatVal(epochTime())
  of "clock.monotonic": requireArgs(name, args, 0); return floatVal(getMonoTime().ticks.float64 / 1_000_000_000)
  of "luck.manifest":
    requireArgs(name, args, 1)
    if args[0].kind != vkInt: raise runtimeCap("WrongType", "manifest expects an integer seed")
    randomize(args[0].intVal)
    return noneVal()
  of "luck.random": requireArgs(name, args, 0); return floatVal(rand(1.0))
  of "luck.shuffle":
    requireArgs(name, args, 1)
    if args[0].kind != vkList: raise runtimeCap("WrongType", "shuffle expects a stack")
    shuffle(args[0].items)
    return noneVal()
  of "luck.sample":
    requireArgs(name, args, 2)
    if args[1].kind != vkInt: raise runtimeCap("WrongType", "sample count expects an integer")
    var values = iterable(args[0])
    let count = args[1].intVal
    if count < 0 or count > values.len: raise runtimeCap("BadVibe", "sample count is outside collection size")
    # Copy before swapping: sampling must not mutate the source collection.
    var sampled: seq[Value]
    for value in values: sampled.add value
    for i in 0 ..< count.int:
      let chosen = rand(i .. sampled.high)
      swap(sampled[i], sampled[chosen])
    sampled.setLen(count.int)
    return listVal(sampled)
  of "luck.randint": requireArgs(name, args, 2); return intVal(rand(args[0].asInt.int .. args[1].asInt.int))
  of "luck.choice":
    requireArgs(name, args, 1)
    let values = iterable(args[0])
    if values.len == 0: raise runtimeCap("OutOfPocket", "cannot choose from an empty collection")
    return values[rand(values.high)]
  of "system.cwd": return stringVal(getCurrentDir())
  of "system.getenv": requireArgs(name, args, 1); return stringVal(getEnv(args[0].strVal))
  of "system.exit": quit(if args.len > 0: args[0].asInt.int else: 0)
  of "json.parse":
    requireArgs(name, args, 1)
    if args[0].kind != vkString: raise runtimeCap("WrongType", "json.parse needs text")
    try: return jsonToValue(parseJson(args[0].strVal))
    except JsonParsingError as error: raise runtimeCap("BadVibe", "invalid JSON: " & error.msg)
  of "json.stringify":
    if args.len < 1 or args.len > 2: raise runtimeCap("WrongType", "json.stringify expects 1..2 arguments")
    let encoded = valueToJson(args[0])
    return stringVal(if args.len == 2 and args[1].truthy: encoded.pretty() else: $encoded)
  of "path.join":
    if args.len == 0: return stringVal("")
    var joined = args[0].strVal
    for arg in args[1 .. ^1]: joined = joined / arg.strVal
    return stringVal(joined)
  of "path.exists": requireArgs(name, args, 1); return boolVal(fileExists(args[0].strVal) or dirExists(args[0].strVal))
  of "path.is_file": requireArgs(name, args, 1); return boolVal(fileExists(args[0].strVal))
  of "path.is_dir": requireArgs(name, args, 1); return boolVal(dirExists(args[0].strVal))
  of "path.basename": requireArgs(name, args, 1); return stringVal(lastPathPart(args[0].strVal))
  of "path.dirname": requireArgs(name, args, 1); return stringVal(parentDir(args[0].strVal))
  of "path.extension": requireArgs(name, args, 1); return stringVal(splitFile(args[0].strVal).ext)
  of "path.absolute": requireArgs(name, args, 1); return stringVal(absolutePath(args[0].strVal))
  of "encoding.base64_encode": requireArgs(name, args, 1); return stringVal(encode(args[0].strVal))
  of "encoding.base64_decode":
    requireArgs(name, args, 1)
    try: return stringVal(decode(args[0].strVal))
    except ValueError as error: raise runtimeCap("BadVibe", "invalid base64: " & error.msg)
  else: raise runtimeCap("NoPullUp", "native cook '" & name & "' is not implemented")

proc callFunction(rt: Runtime, caller: Env, callee: Value, args: seq[Value],
                  kwargs: seq[tuple[nm: string, val: Value]]): Value =
  let fn = callee.fn
  rt.moduleStack.add fn.filename
  defer: discard rt.moduleStack.pop()
  let scope = newEnv(fn.closure)
  var positional = args
  if callee.boundSelf != nil: positional.insert(callee.boundSelf, 0)
  var argIndex = 0
  var usedKw = initHashSet[string]()
  var bound = initHashSet[string]()
  for i, param in fn.params:
    if param.isStar:
      scope.declare(param.name, listVal(if argIndex < positional.len: positional[argIndex .. ^1] else: @[]))
      argIndex = positional.len
    elif param.isStarStar:
      let values = dictVal()
      for kw in kwargs:
        if kw.nm notin usedKw: values.pairs.add (stringVal(kw.nm), kw.val)
      scope.declare(param.name, values)
    elif argIndex < positional.len:
      scope.declare(param.name, positional[argIndex])
      bound.incl(param.name)
      inc argIndex
    else:
      var found: Value
      for kw in kwargs:
        if kw.nm == param.name: found = kw.val; usedKw.incl(kw.nm); break
      if found != nil: scope.declare(param.name, found)
      elif i < fn.defaults.len and fn.defaults[i] != nil: scope.declare(param.name, fn.defaults[i])
      else: raise runtimeCap("WrongType", fn.name & " is missing argument '" & param.name & "'")
  if argIndex < positional.len and not fn.params.anyIt(it.isStar): raise runtimeCap("WrongType", fn.name & " got too many arguments")
  for kw in kwargs:
    if kw.nm in bound:
      raise runtimeCap("WrongType", fn.name & " got multiple values for argument '" & kw.nm & "'")
    if kw.nm notin usedKw and not fn.params.anyIt(it.isStarStar):
      raise runtimeCap("WrongType", fn.name & " got unexpected argument '" & kw.nm & "'")
  var yielded: seq[Value]
  if fn.lambdaBody != nil:
    return rt.evalExpr(scope, fn.lambdaBody)
  let signal = rt.execBlock(scope, fn.body, yielded)
  if fn.isGenerator: return Value(kind: vkList, items: yielded)
  if signal.kind == sigReturn: signal.value else: noneVal()

proc callValue(rt: Runtime, env: Env, callee: Value, args: seq[Value], kwargs: seq[tuple[nm: string, val: Value]]): Value =
  if callee == nil: raise runtimeCap("WrongType", "ghost is not callable")
  var keywordNames = initHashSet[string]()
  for kw in kwargs:
    if kw.nm in keywordNames:
      raise runtimeCap("WrongType", "multiple values for argument '" & kw.nm & "'")
    keywordNames.incl kw.nm
  case callee.kind
  of vkBuiltin: rt.invokeBuiltin(env, callee, args, kwargs)
  of vkFunction: rt.callFunction(env, callee, args, kwargs)
  of vkClass:
    let instance = Value(kind: vkInstance, klass: callee.klass, fields: initTable[string, Value]())
    let init = callee.klass.findMethod("new")
    if init != nil: discard rt.callFunction(env, Value(kind: vkFunction, fn: init, boundSelf: instance), args, kwargs)
    elif args.len > 0 or kwargs.len > 0: raise runtimeCap("WrongType", callee.klass.name & " takes no arguments")
    instance
  else: raise runtimeCap("WrongType", repr(callee) & " is not callable")

proc installRuntimeNames(env: Env, rt: Runtime) =
  env.declare("__name__", stringVal("__main__"), true)
  env.declare("args", listVal(rt.args.mapIt(stringVal(it))), true)
  # ancestor is resolved as a bound native operation inside methods.
  env.declare("ancestor", builtinValue("ancestor"), true)

proc reportRuntimeError(error: ref RuntimeError, fallback: string) =
  if error.frames.len > 0:
    stderr.writeLine("Call stack (outermost first):")
    for i in countdown(error.frames.high, 0):
      let frame = error.frames[i]
      stderr.writeLine("  " & frame.filename & ":" & $frame.line & ":" & $frame.col & " in " & frame.name)
  let filename = if error.filename != "": error.filename else: fallback
  let where = if error.line > 0: filename & ":" & $error.line & ":" & $error.col & ": " else: ""
  stderr.writeLine(where & "cap: " & error.category & ": " & error.msg)

proc runProgram*(program: seq[Stmt], filename: string, args: seq[string] = @[]): int =
  randomize()
  let rt = Runtime(filename: absolutePath(filename), args: args,
    moduleCache: initTable[string, Value](), moduleStack: @[absolutePath(filename)])
  let env = newEnv()
  env.installRuntimeNames(rt)
  defer: rt.gameContext.close()
  var yielded: seq[Value]
  try:
    discard rt.execBlock(env, program, yielded)
    0
  except RuntimeError as error:
    reportRuntimeError(error, filename)
    1
  except CatchableError as error:
    stderr.writeLine(filename & ": cap: L: " & error.msg)
    1

proc parseChecked*(source, filename: string): seq[Stmt] =
  let parsed = parseProgram(lex(source))
  let issues = checkProgram(parsed.program)
  if issues.len > 0:
    var message = ""
    for issue in issues:
      message.add filename & ":" & $issue.line & ":" & $issue.col & ": cap: " & issue.msg & "\n"
    raise newGzimError(message.strip(), issues[0].line, issues[0].col)
  parsed.program

proc runSource*(source, filename: string, args: seq[string] = @[]): int =
  runProgram(parseChecked(source, filename), filename, args)

proc newReplSession*(filename = "<repl>"): ReplSession =
  let rt = Runtime(filename: absolutePath(filename), args: @[],
    moduleCache: initTable[string, Value](), moduleStack: @[absolutePath(filename)])
  let env = newEnv()
  env.installRuntimeNames(rt)
  ReplSession(runtime: rt, env: env)

proc runReplChunk*(session: ReplSession, source: string): int =
  ## Check the complete REPL history, but execute only the newly submitted
  ## statements. This preserves bindings without replaying earlier side effects.
  let combined = if session.source == "": source else: session.source & "\n" & source
  let program = parseChecked(combined, session.runtime.filename)
  let firstNew = session.statementCount
  var yielded: seq[Value]
  try:
    if firstNew < program.len:
      discard session.runtime.execBlock(session.env, program[firstNew .. ^1], yielded)
    session.source = combined
    session.statementCount = program.len
    0
  except RuntimeError as error:
    reportRuntimeError(error, session.runtime.filename)
    1
  except CatchableError as error:
    stderr.writeLine(session.runtime.filename & ": cap: L: " & error.msg)
    1

proc closeReplSession*(session: ReplSession) =
  session.runtime.gameContext.close()
