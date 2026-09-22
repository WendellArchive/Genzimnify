## Shared error type for the Genzimnify toolchain.
## Errors are "cap". Reporting them is "calling cap".

type
  GzimError* = ref object of CatchableError
    line*: int
    col*: int

proc newGzimError*(msg: string, line = 0, col = 0): GzimError =
  GzimError(msg: msg, line: line, col: col)
