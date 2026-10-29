# Package

version       = "2.0.6"
author        = "Genzimnify"
description   = "Genzimnify: a native, Python-free programming language with Gen Z syntax."
license       = "MIT"
srcDir        = "src"
bin           = @["gzim", "genzimc"]
namedBin["gzimlsp"] = "gzim-lsp"
requires "nim >= 2.0.0"
