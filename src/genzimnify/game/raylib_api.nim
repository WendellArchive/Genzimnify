## Minimal raylib 5.5 ABI. Loaded only when graphics/audio is requested.
## raylib is Copyright (c) 2013-2024 Ramon Santamaria; see native/rizzgame/LICENSE.raylib.
import std/[dynlib, os]

type
  Vector2* {.bycopy.} = object
    x*, y*: cfloat
  Rectangle* {.bycopy.} = object
    x*, y*, width*, height*: cfloat
  Color* {.bycopy.} = object
    r*, g*, b*, a*: uint8
  Texture* {.bycopy.} = object
    id*: cuint
    width*, height*, mipmaps*, format*: cint
  RenderTexture* {.bycopy.} = object
    id*: cuint
    texture*, depth*: Texture
  Image* {.bycopy.} = object
    data*: pointer
    width*, height*, mipmaps*, format*: cint
  Font* {.bycopy.} = object
    baseSize*, glyphCount*, glyphPadding*: cint
    texture*: Texture
    recs*, glyphs*: pointer
  Camera2D* {.bycopy.} = object
    offset*, target*: Vector2
    rotation*, zoom*: cfloat
  AudioStream* {.bycopy.} = object
    buffer*, processor*: pointer
    sampleRate*, sampleSize*, channels*: cuint
  Sound* {.bycopy.} = object
    stream*: AudioStream
    frameCount*: cuint
  Music* {.bycopy.} = object
    stream*: AudioStream
    frameCount*: cuint
    looping*: bool
    ctxType*: cint
    ctxData*: pointer
  Raylib* = ref object
    library: LibHandle
    SetTraceLogLevel*: proc(level: cint): void {.cdecl.}
    SetConfigFlags*: proc(flags: cuint): void {.cdecl.}
    InitWindow*: proc(width, height: cint; title: cstring): void {.cdecl.}
    IsWindowReady*: proc(): bool {.cdecl.}
    CloseWindow*: proc(): void {.cdecl.}
    WindowShouldClose*: proc(): bool {.cdecl.}
    SetWindowTitle*: proc(title: cstring): void {.cdecl.}
    SetExitKey*: proc(key: cint): void {.cdecl.}
    GetScreenWidth*: proc(): cint {.cdecl.}
    GetScreenHeight*: proc(): cint {.cdecl.}
    BeginDrawing*: proc(): void {.cdecl.}
    EndDrawing*: proc(): void {.cdecl.}
    ClearBackground*: proc(color: Color): void {.cdecl.}
    BeginTextureMode*: proc(target: RenderTexture): void {.cdecl.}
    EndTextureMode*: proc(): void {.cdecl.}
    BeginMode2D*: proc(camera: Camera2D): void {.cdecl.}
    EndMode2D*: proc(): void {.cdecl.}
    GetKeyPressed*: proc(): cint {.cdecl.}
    IsKeyDown*: proc(key: cint): bool {.cdecl.}
    IsKeyReleased*: proc(key: cint): bool {.cdecl.}
    GetCharPressed*: proc(): cint {.cdecl.}
    GetMousePosition*: proc(): Vector2 {.cdecl.}
    IsMouseButtonPressed*: proc(button: cint): bool {.cdecl.}
    IsMouseButtonReleased*: proc(button: cint): bool {.cdecl.}
    IsMouseButtonDown*: proc(button: cint): bool {.cdecl.}
    GetMouseWheelMove*: proc(): cfloat {.cdecl.}
    DrawRectangleRec*: proc(rect: Rectangle; color: Color): void {.cdecl.}
    DrawRectangleLinesEx*: proc(rect: Rectangle; thick: cfloat; color: Color): void {.cdecl.}
    DrawCircleV*: proc(center: Vector2; radius: cfloat; color: Color): void {.cdecl.}
    DrawCircleLinesV*: proc(center: Vector2; radius: cfloat; color: Color): void {.cdecl.}
    DrawLineEx*: proc(start, finish: Vector2; thick: cfloat; color: Color): void {.cdecl.}
    DrawTriangle*: proc(a, b, c: Vector2; color: Color): void {.cdecl.}
    DrawTexturePro*: proc(texture: Texture; source, dest: Rectangle; origin: Vector2; rotation: cfloat; tint: Color): void {.cdecl.}
    LoadTexture*: proc(fileName: cstring): Texture {.cdecl.}
    IsTextureValid*: proc(texture: Texture): bool {.cdecl.}
    UnloadTexture*: proc(texture: Texture): void {.cdecl.}
    LoadRenderTexture*: proc(width, height: cint): RenderTexture {.cdecl.}
    IsRenderTextureValid*: proc(target: RenderTexture): bool {.cdecl.}
    UnloadRenderTexture*: proc(target: RenderTexture): void {.cdecl.}
    SetTextureFilter*: proc(texture: Texture; filter: cint): void {.cdecl.}
    LoadImageFromTexture*: proc(texture: Texture): Image {.cdecl.}
    LoadImageFromScreen*: proc(): Image {.cdecl.}
    ImageFlipVertical*: proc(image: ptr Image): void {.cdecl.}
    UnloadImage*: proc(image: Image): void {.cdecl.}
    ExportImage*: proc(image: Image; fileName: cstring): bool {.cdecl.}
    GetImageColor*: proc(image: Image; x, y: cint): Color {.cdecl.}
    LoadTextureFromImage*: proc(image: Image): Texture {.cdecl.}
    GetFontDefault*: proc(): Font {.cdecl.}
    LoadFontEx*: proc(fileName: cstring; size: cint; codepoints: ptr cint; count: cint): Font {.cdecl.}
    IsFontValid*: proc(font: Font): bool {.cdecl.}
    UnloadFont*: proc(font: Font): void {.cdecl.}
    ImageTextEx*: proc(font: Font; text: cstring; size, spacing: cfloat; tint: Color): Image {.cdecl.}
    DrawTextEx*: proc(font: Font; text: cstring; position: Vector2; size, spacing: cfloat; tint: Color): void {.cdecl.}
    MeasureTextEx*: proc(font: Font; text: cstring; size, spacing: cfloat): Vector2 {.cdecl.}
    InitAudioDevice*: proc(): void {.cdecl.}
    IsAudioDeviceReady*: proc(): bool {.cdecl.}
    CloseAudioDevice*: proc(): void {.cdecl.}
    LoadSound*: proc(fileName: cstring): Sound {.cdecl.}
    IsSoundValid*: proc(sound: Sound): bool {.cdecl.}
    UnloadSound*: proc(sound: Sound): void {.cdecl.}
    PlaySound*: proc(sound: Sound): void {.cdecl.}
    StopSound*: proc(sound: Sound): void {.cdecl.}
    IsSoundPlaying*: proc(sound: Sound): bool {.cdecl.}
    SetSoundVolume*: proc(sound: Sound; volume: cfloat): void {.cdecl.}
    SetSoundPitch*: proc(sound: Sound; pitch: cfloat): void {.cdecl.}
    LoadMusicStream*: proc(fileName: cstring): Music {.cdecl.}
    IsMusicValid*: proc(music: Music): bool {.cdecl.}
    UnloadMusicStream*: proc(music: Music): void {.cdecl.}
    PlayMusicStream*: proc(music: Music): void {.cdecl.}
    PauseMusicStream*: proc(music: Music): void {.cdecl.}
    ResumeMusicStream*: proc(music: Music): void {.cdecl.}
    StopMusicStream*: proc(music: Music): void {.cdecl.}
    UpdateMusicStream*: proc(music: Music): void {.cdecl.}
    IsMusicStreamPlaying*: proc(music: Music): bool {.cdecl.}
    SetMusicVolume*: proc(music: Music; volume: cfloat): void {.cdecl.}

proc loadRaylib*(): Raylib =
  when defined(windows):
    const names = ["raylib.dll"]
  elif defined(macosx):
    const names = ["libraylib.dylib", "libraylib.5.5.0.dylib"]
  else:
    const names = ["libraylib.so", "libraylib.so.550"]
  var candidates: seq[string]
  let override = getEnv("GZIM_RAYLIB")
  if override != "":
    candidates.add override
  else:
    for name in names: candidates.add getAppDir() / name
    for name in names: candidates.add getAppDir().parentDir / "lib" / name
    for name in names: candidates.add name
    when defined(macosx):
      candidates.add "/opt/homebrew/lib/libraylib.dylib"
  result = Raylib()
  for path in candidates:
    result.library = loadLib(path)
    if result.library != nil: break
  if result.library == nil:
    raise newException(ValueError, "rizzgame needs the native raylib 5.5 library beside gzim. Install the graphics-enabled release, build native/rizzgame, or set GZIM_RAYLIB to the library path. No Python is needed.")
  template bindProc(field: untyped) =
    result.field = cast[typeof(result.field)](symAddr(result.library, astToStr(field)))
    if result.field == nil:
      unloadLib(result.library)
      raise newException(ValueError, "rizzgame: incompatible raylib, missing " & astToStr(field))
  bindProc(SetTraceLogLevel)
  bindProc(SetConfigFlags)
  bindProc(InitWindow)
  bindProc(IsWindowReady)
  bindProc(CloseWindow)
  bindProc(WindowShouldClose)
  bindProc(SetWindowTitle)
  bindProc(SetExitKey)
  bindProc(GetScreenWidth)
  bindProc(GetScreenHeight)
  bindProc(BeginDrawing)
  bindProc(EndDrawing)
  bindProc(ClearBackground)
  bindProc(BeginTextureMode)
  bindProc(EndTextureMode)
  bindProc(BeginMode2D)
  bindProc(EndMode2D)
  bindProc(GetKeyPressed)
  bindProc(IsKeyDown)
  bindProc(IsKeyReleased)
  bindProc(GetCharPressed)
  bindProc(GetMousePosition)
  bindProc(IsMouseButtonPressed)
  bindProc(IsMouseButtonReleased)
  bindProc(IsMouseButtonDown)
  bindProc(GetMouseWheelMove)
  bindProc(DrawRectangleRec)
  bindProc(DrawRectangleLinesEx)
  bindProc(DrawCircleV)
  bindProc(DrawCircleLinesV)
  bindProc(DrawLineEx)
  bindProc(DrawTriangle)
  bindProc(DrawTexturePro)
  bindProc(LoadTexture)
  bindProc(IsTextureValid)
  bindProc(UnloadTexture)
  bindProc(LoadRenderTexture)
  bindProc(IsRenderTextureValid)
  bindProc(UnloadRenderTexture)
  bindProc(SetTextureFilter)
  bindProc(LoadImageFromTexture)
  bindProc(LoadImageFromScreen)
  bindProc(ImageFlipVertical)
  bindProc(UnloadImage)
  bindProc(ExportImage)
  bindProc(GetImageColor)
  bindProc(LoadTextureFromImage)
  bindProc(GetFontDefault)
  bindProc(LoadFontEx)
  bindProc(IsFontValid)
  bindProc(UnloadFont)
  bindProc(ImageTextEx)
  bindProc(DrawTextEx)
  bindProc(MeasureTextEx)
  bindProc(InitAudioDevice)
  bindProc(IsAudioDeviceReady)
  bindProc(CloseAudioDevice)
  bindProc(LoadSound)
  bindProc(IsSoundValid)
  bindProc(UnloadSound)
  bindProc(PlaySound)
  bindProc(StopSound)
  bindProc(IsSoundPlaying)
  bindProc(SetSoundVolume)
  bindProc(SetSoundPitch)
  bindProc(LoadMusicStream)
  bindProc(IsMusicValid)
  bindProc(UnloadMusicStream)
  bindProc(PlayMusicStream)
  bindProc(PauseMusicStream)
  bindProc(ResumeMusicStream)
  bindProc(StopMusicStream)
  bindProc(UpdateMusicStream)
  bindProc(IsMusicStreamPlaying)
  bindProc(SetMusicVolume)
  result.SetTraceLogLevel(4) # warnings and errors only
