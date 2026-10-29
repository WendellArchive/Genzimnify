# Native rizzgame backend

`rizzgame` uses the raylib 5.5 C library directly from Nim. The CMake target
fetches the pinned 5.5 source archive, verifies its SHA-256, and builds a
shared library next to `gzim`. Normal language execution does not load it.

```sh
cmake -S native/rizzgame -B build/rizzgame -DCMAKE_BUILD_TYPE=Release -DRIZZGAME_OUTPUT_DIR="$PWD/build"
cmake --build build/rizzgame --config Release --parallel 4
nim c -d:release --out:build/gzim src/gzim.nim
build/gzim examples/rizzgame/neon_arena.gzim
```

The macOS release targets macOS 12+ on Apple Silicon. Linux needs a graphical
desktop with OpenGL drivers or Xvfb/Mesa. Windows targets x86-64. A local
raylib installation can be used by setting `GZIM_RAYLIB` to an absolute path
to the compatible raylib 5.5 shared library. The library is bundled with
release archives and installed beside `gzim` by the official installers.

raylib is by Ramon Santamaria and contributors under the zlib license; the
full text is in [LICENSE.raylib](LICENSE.raylib).
