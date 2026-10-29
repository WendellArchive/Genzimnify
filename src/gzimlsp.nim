## gzim-lsp entry point (binary: gzim-lsp).

import std/[os, syncio]
import genzimnify/[lsp, version]

let args = commandLineParams()
if args.len == 0:
  lsp.main()
elif args == @["--version"] or args == @["-v"]:
  echo "gzim-lsp " & GenzimnifyVersion
elif args == @["--help"] or args == @["-h"]:
  echo "gzim-lsp, the Genzimnify language server\nusage: gzim-lsp [--help|--version]\nWith no arguments, reads LSP messages on stdin and writes replies on stdout."
else:
  stderr.writeLine("usage: gzim-lsp [--help|--version]")
  quit(1)
