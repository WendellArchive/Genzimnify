## Native pygame-style 2D API. Runtime values cross this boundary as plain data
## or typed object references, never via Python or subprocess graphics calls.
import std/[json, math, os, strutils, tables, times, monotimes, random, unicode]
import raylib_api

type
  GameKind* = enum gSurface, gRect, gVector, gClock, gFont, gSound, gCamera, gEmitter, gAnimation, gMusic
  Particle = object
    pos, velocity: Vector2
    life, total, radius: float
    color: Color
  GameObject* = ref object
    kind*: GameKind
    owner: GameContext
    alive, screen, renderTarget, defaultFont: bool
    texture: Texture
    target: RenderTexture
    rect: Rectangle
    vector: Vector2
    lastTick: MonoTime
    elapsed, fps: float
    font: Font
    fontSize: float
    sound: Sound
    music: Music
    camera: Camera2D
    shakeTime, shakeStrength: float
    shakeOffset: Vector2
    particles: seq[Particle]
    capacity: int
    source: GameObject
    frameWidth, frameHeight, frameCount, frame: int
    animationTime, animationFps: float
    looping, finished: bool
  GameValue* = object
    data*: JsonNode
    obj*: GameObject
  GameContext* = ref object
    api: Raylib
    initialized, window, audio, drawing, eventsRead: bool
    caption: string
    screen: GameObject
    resources: seq[GameObject]
    activeCamera: GameObject
    started: MonoTime
    mouse: Vector2
    rng: Rand

const GameSpecs* = [
  "init::0", "quit::0", "get_init::0", "get_backend::0",
  "dip_out::0", "display.pull_up:size,flags:1", "display.show_off::0",
  "event.catch_vibes::0", "key.check_the_vibe::0", "Clock.keep_up:self,fps:1",
  "Surface.glow_up:self,color:2", "draw.flex_rect:surface,color,rect,width:3",
  "draw.flex_circle:surface,color,center,radius,width:4",
  "draw.flex_line:surface,color,start,end,width:4",
  "draw.yap_text:surface,text,position,size,color:3",
  "display.set_mode:size,flags:1", "display.set_caption:title:1",
  "display.flip::0", "display.get_surface::0", "display.get_size::0",
  "event.get::0", "key.get_pressed::0", "mouse.get_pos::0", "mouse.get_pressed::0",
  "time.Clock::0", "time.get_ticks::0", "time.wait:milliseconds:1",
  "Rect:x,y,width,height:4", "Surface:size:1", "math.Vector2:x,y:0",
  "math.lerp:a,b,t:3", "math.clamp:value,low,high:3", "math.smoothstep:low,high,value:3",
  "math.ease:t,curve:1", "draw.rect:surface,color,rect,width:3",
  "draw.circle:surface,color,center,radius,width:4", "draw.line:surface,color,start,end,width:4",
  "draw.text:surface,text,position,size,color:3",
  "image.load:path:1", "image.save:surface,path:2",
  "font.Font:path,size,characters:2", "mixer.init::0", "mixer.Sound:path:1",
  "mixer.music.load:path:1", "Music.play:self:1", "Music.pause:self:1",
  "Music.resume:self:1", "Music.stop:self:1", "Music.update:self:1",
  "Music.get_busy:self:1", "Music.set_volume:self,volume:2", "Music.unload:self:1",
  "camera.Camera:x,y,zoom,rotation:0", "particles.Emitter:max_particles:0",
  "Surface.fill:self,color:2", "Surface.blit:self,source,dest,rotation,scale,tint:3",
  "Surface.get_size:self:1", "Surface.get_width:self:1", "Surface.get_height:self:1",
  "Surface.get_rect:self:1", "Surface.get_at:self,position:2", "Surface.unload:self:1",
  "Rect.colliderect:self,other:2", "Rect.collidepoint:self,point:2",
  "Rect.move:self,dx,dy:3", "Rect.inflate:self,dx,dy:3", "Rect.copy:self:1",
  "Vector2.length:self:1", "Vector2.normalize:self:1", "Vector2.rotate:self,degrees:2",
  "Vector2.dot:self,other:2", "Vector2.add:self,other:2", "Vector2.scale:self,factor:2",
  "Clock.tick:self,fps:1", "Clock.get_fps:self:1", "Clock.get_time:self:1",
  "Font.render:self,text,antialias,color:4", "Font.size:self,text:2", "Font.unload:self:1",
  "Sound.play:self:1", "Sound.stop:self:1", "Sound.get_busy:self:1",
  "Sound.set_volume:self,volume:2", "Sound.set_pitch:self,pitch:2", "Sound.unload:self:1",
  "Camera.begin:self:1", "Camera.end:self:1", "Camera.follow:self,position,smoothing,dt:2",
  "Camera.shake:self,strength,duration:3", "Camera.update:self,dt:2",
  "Camera.world_to_screen:self,position:2", "Camera.screen_to_world:self,position:2",
  "Emitter.burst:self,position,count,color,speed,lifetime,radius:3",
  "Emitter.update:self,dt,gravity:2", "Emitter.draw:self,surface:2", "Emitter.clear:self:1",
  "animation.SpriteSheet:surface,frame_width,frame_height,fps,loop:3",
  "Animation.update:self,dt:2", "Animation.reset:self:1",
  "Animation.draw:self,surface,position,rotation,scale,tint:3"
]

proc fail(message: string) {.noreturn.} =
  raise newException(ValueError, "rizzgame: " & message)
proc value(data: JsonNode): GameValue = GameValue(data: data)
proc value(obj: GameObject): GameValue = GameValue(obj: obj)
proc empty(): GameValue = value(newJNull())
proc kindName*(kind: GameKind): string =
  ["Surface", "Rect", "Vector2", "Clock", "Font", "Sound", "Camera", "Emitter", "Animation", "Music"][ord(kind)]
proc newGameContext*(): GameContext =
  GameContext(caption: "rizzgame", started: getMonoTime(), rng: initRand())
proc number(node: JsonNode): float =
  if node == nil or node.kind notin {JInt, JFloat}: fail("expected a finite number")
  result = node.getFloat()
  if result.classify in {fcNan, fcInf, fcNegInf} or abs(result) > 1.0e9:
    fail("number must be finite and within +/- 1 billion")
proc num(args: seq[GameValue], i: int, default = 0.0): float =
  if i >= args.len or (args[i].obj == nil and args[i].data == nil):
    return default
  number(args[i].data)
proc text(args: seq[GameValue], i: int): string =
  if i >= args.len or args[i].data == nil or args[i].data.kind != JString: fail("expected text")
  result = args[i].data.getStr()
  if '\0' in result: fail("text cannot contain NUL")
proc obj(args: seq[GameValue], i: int, kind: GameKind): GameObject =
  if i >= args.len or args[i].obj == nil or args[i].obj.kind != kind: fail("expected " & kind.kindName)
  args[i].obj
proc sequence(node: JsonNode, lengths: set[uint8]) =
  if node == nil or node.kind != JArray or node.len > 255 or node.len.uint8 notin lengths:
    fail("expected a coordinate/color sequence of the documented length")
proc vec(v: GameValue): Vector2 =
  if v.obj != nil and v.obj.kind == gVector: return v.obj.vector
  sequence(v.data, {2'u8})
  Vector2(x: number(v.data[0]).cfloat, y: number(v.data[1]).cfloat)
proc rectangle(v: GameValue): Rectangle =
  if v.obj != nil and v.obj.kind == gRect: return v.obj.rect
  sequence(v.data, {4'u8})
  result = Rectangle(x: number(v.data[0]).cfloat, y: number(v.data[1]).cfloat,
    width: number(v.data[2]).cfloat, height: number(v.data[3]).cfloat)
  if result.width < 0 or result.height < 0: fail("rectangle size must be nonnegative")
proc color(v: GameValue): Color =
  sequence(v.data, {3'u8, 4'u8})
  var channels = [0'u8, 0, 0, 255]
  for i in 0..<v.data.len:
    let n = number(v.data[i])
    if n < 0 or n > 255 or n != floor(n): fail("color channels must be integers in 0..255")
    channels[i] = n.uint8
  Color(r: channels[0], g: channels[1], b: channels[2], a: channels[3])
proc tint(args: seq[GameValue], i: int): Color =
  if i >= args.len or args[i].data == nil or args[i].data.kind == JNull: Color(r: 255, g: 255, b: 255, a: 255)
  else: color(args[i])
proc positive(n: float, label: string, maximum = 16384.0): float =
  if n <= 0 or n > maximum: fail(label & " must be in (0, " & $maximum & "]")
  n
proc dimensions(v: GameValue): Vector2 =
  result = vec(v)
  discard positive(result.x, "width", 8192)
  discard positive(result.y, "height", 8192)
  if result.x != floor(result.x) or result.y != floor(result.y): fail("surface dimensions must be integers")
  if result.x * result.y > 16777216: fail("surface exceeds 16 million pixels")
proc vectorValue(v: Vector2): JsonNode = %*[v.x, v.y]
proc newObject(ctx: GameContext, kind: GameKind): GameObject =
  GameObject(kind: kind, owner: ctx, alive: true)
proc rectValue(ctx: GameContext, r: Rectangle): GameValue =
  let o = ctx.newObject(gRect); o.rect = r; value(o)
proc vectorObject(ctx: GameContext, v: Vector2): GameValue =
  let o = ctx.newObject(gVector); o.vector = v; value(o)

proc hasProperty*(o: GameObject, name: string): bool =
  case o.kind
  of gRect: name in ["x", "y", "width", "height", "left", "top", "right", "bottom", "center", "size"]
  of gVector: name in ["x", "y"]
  of gCamera: name in ["x", "y", "zoom", "rotation", "offset"]
  of gEmitter: name == "count"
  of gAnimation: name in ["frame", "frame_count", "finished"]
  else: false
proc getProperty*(o: GameObject, name: string): GameValue =
  case o.kind
  of gRect:
    case name
    of "x", "left": return value(%o.rect.x)
    of "y", "top": return value(%o.rect.y)
    of "width": return value(%o.rect.width)
    of "height": return value(%o.rect.height)
    of "right": return value(%(o.rect.x + o.rect.width))
    of "bottom": return value(%(o.rect.y + o.rect.height))
    of "center": return value(%*[o.rect.x + o.rect.width/2, o.rect.y + o.rect.height/2])
    of "size": return value(%*[o.rect.width, o.rect.height])
    else: discard
  of gVector:
    if name == "x": return value(%o.vector.x)
    if name == "y": return value(%o.vector.y)
  of gCamera:
    case name
    of "x": return value(%o.camera.target.x)
    of "y": return value(%o.camera.target.y)
    of "zoom": return value(%o.camera.zoom)
    of "rotation": return value(%o.camera.rotation)
    of "offset": return value(vectorValue(o.camera.offset))
    else: discard
  of gEmitter:
    if name == "count": return value(%o.particles.len)
  of gAnimation:
    if name == "frame": return value(%o.frame)
    if name == "frame_count": return value(%o.frameCount)
    if name == "finished": return value(%o.finished)
  else: discard
  fail("unknown property: " & name)
proc setProperty*(o: GameObject, name: string, v: GameValue) =
  if o.kind == gRect:
    if name == "center":
      let p = vec(v); o.rect.x = p.x-o.rect.width/2; o.rect.y = p.y-o.rect.height/2; return
    if name == "size":
      let p = vec(v)
      if p.x < 0 or p.y < 0: fail("rectangle size must be nonnegative")
      o.rect.width = p.x; o.rect.height = p.y; return
    let n = number(v.data).cfloat
    case name
    of "x", "left": o.rect.x = n
    of "y", "top": o.rect.y = n
    of "width", "height":
      if n < 0: fail("rectangle size must be nonnegative")
      if name == "width": o.rect.width = n
      else: o.rect.height = n
    of "right": o.rect.x = n-o.rect.width
    of "bottom": o.rect.y = n-o.rect.height
    else: fail("unknown Rect property: " & name)
  elif o.kind == gVector and name in ["x", "y"]:
    let n = number(v.data).cfloat
    if name == "x": o.vector.x = n
    else: o.vector.y = n
  elif o.kind == gCamera:
    if name == "offset": o.camera.offset = vec(v); return
    let n = number(v.data).cfloat
    case name
    of "x": o.camera.target.x = n
    of "y": o.camera.target.y = n
    of "zoom": o.camera.zoom = positive(n, "zoom", 1000).cfloat
    of "rotation": o.camera.rotation = n
    else: fail("unknown Camera property: " & name)
  else: fail("property is read-only or does not exist: " & name)

let signatures = block:
  var table = initTable[string, tuple[params: seq[string], required: int]]()
  for spec in GameSpecs:
    let parts = spec.split(':')
    table[parts[0]] = ((if parts[1] == "": @[] else: parts[1].split(',')), parseInt(parts[2]))
  table

proc signature(name: string): tuple[params: seq[string], required: int] =
  if not signatures.hasKey(name): fail("unknown function: " & name)
  signatures[name]
proc hasMethod*(o: GameObject, name: string): bool =
  signatures.hasKey(o.kind.kindName & "." & name)
proc arguments(name: string, positional: seq[GameValue], kwargs: seq[tuple[name: string, val: GameValue]]): seq[GameValue] =
  let spec = signature(name)
  if positional.len > spec.params.len: fail(name & " received too many arguments")
  result = positional
  var used: seq[int]
  for kw in kwargs:
    let at = spec.params.find(kw.name)
    if at < 0: fail(name & " has no argument '" & kw.name & "'")
    if at < positional.len or at in used: fail("duplicate argument: " & kw.name)
    if result.len <= at: result.setLen(at+1)
    result[at] = kw.val
    used.add at
  for i in 0..<spec.required:
    if i >= result.len or (result[i].data == nil and result[i].obj == nil): fail(name & " needs " & spec.params[i])

proc ensureApi(ctx: GameContext) =
  if ctx.api == nil: ctx.api = loadRaylib()
proc requireWindow(ctx: GameContext) =
  if not ctx.window: fail("call display.set_mode before using graphics")
proc requireAlive(ctx: GameContext, o: GameObject) =
  if o.owner != ctx or not o.alive: fail("resource was unloaded or belongs to another session")
proc beginFrame(ctx: GameContext) =
  ctx.requireWindow()
  if not ctx.drawing:
    ctx.api.BeginDrawing(); ctx.drawing = true
proc flip(ctx: GameContext) =
  ctx.beginFrame()
  ctx.api.EndDrawing(); ctx.drawing = false; ctx.eventsRead = false
proc register(ctx: GameContext, o: GameObject): GameValue =
  if ctx.resources.len >= 4096: fail("too many live resources; unload unused surfaces, fonts, or sounds")
  ctx.resources.add o
  value(o)
proc release(ctx: GameContext, o: GameObject) =
  if not o.alive: return
  case o.kind
  of gSurface:
    if o.screen: fail("screen cannot be unloaded; use quit()")
    if o.renderTarget: ctx.api.UnloadRenderTexture(o.target)
    else: ctx.api.UnloadTexture(o.texture)
  of gFont:
    if not o.defaultFont: ctx.api.UnloadFont(o.font)
  of gSound: ctx.api.UnloadSound(o.sound)
  of gMusic: ctx.api.UnloadMusicStream(o.music)
  else: fail("object has no native resource to unload")
  o.alive = false
  for i in countdown(ctx.resources.high, 0):
    if ctx.resources[i] == o: ctx.resources.delete(i)
proc close*(ctx: GameContext) =
  if ctx == nil: return
  if ctx.drawing:
    ctx.api.EndDrawing(); ctx.drawing = false
  while ctx.resources.len > 0: ctx.release(ctx.resources[^1])
  if ctx.audio: ctx.api.CloseAudioDevice(); ctx.audio = false
  if ctx.window: ctx.api.CloseWindow(); ctx.window = false
  if ctx.screen != nil: ctx.screen.alive = false
  ctx.screen = nil; ctx.activeCamera = nil; ctx.initialized = false; ctx.eventsRead = false
proc requireAudio(ctx: GameContext) =
  ctx.ensureApi()
  if not ctx.audio:
    ctx.api.InitAudioDevice()
    ctx.audio = ctx.api.IsAudioDeviceReady()
    if not ctx.audio: fail("audio device could not be opened")
proc cameraView(ctx: GameContext): Camera2D =
  result = ctx.activeCamera.camera
  result.offset.x += ctx.activeCamera.shakeOffset.x
  result.offset.y += ctx.activeCamera.shakeOffset.y
proc beginTarget(ctx: GameContext, surface: GameObject, camera = true) =
  ctx.requireAlive(surface)
  ctx.beginFrame()
  if not surface.screen:
    if not surface.renderTarget: fail("loaded images are read-only; blit onto a Surface to edit")
    ctx.api.BeginTextureMode(surface.target)
  if camera and ctx.activeCamera != nil: ctx.api.BeginMode2D(ctx.cameraView())
proc endTarget(ctx: GameContext, surface: GameObject, camera = true) =
  if camera and ctx.activeCamera != nil: ctx.api.EndMode2D()
  if not surface.screen: ctx.api.EndTextureMode()
proc readSurface(ctx: GameContext, surface: GameObject): Image =
  ctx.requireWindow(); ctx.requireAlive(surface)
  if surface.screen: fail("read/save an offscreen Surface; screen capture is not supported in this version")
  result = ctx.api.LoadImageFromTexture(surface.texture)
  if result.data == nil: fail("cannot read surface pixels")
  if surface.renderTarget: ctx.api.ImageFlipVertical(addr result)

proc gameConstants*(): seq[tuple[name: string, value: int]] =
  result = @[("QUIT", 256), ("KEYDOWN", 768), ("KEYUP", 769), ("TEXTINPUT", 771),
    ("MOUSEMOTION", 1024), ("MOUSEBUTTONDOWN", 1025), ("MOUSEBUTTONUP", 1026), ("MOUSEWHEEL", 1027),
    ("RESIZABLE", 4), ("FULLSCREEN", 2), ("HIDDEN", 128), ("VSYNC", 64),
    ("K_SPACE", 32), ("K_ESCAPE", 256), ("K_RETURN", 257), ("K_TAB", 258),
    ("K_BACKSPACE", 259), ("K_RIGHT", 262), ("K_LEFT", 263), ("K_DOWN", 264), ("K_UP", 265),
    ("K_LSHIFT", 340), ("K_LCTRL", 341), ("K_RSHIFT", 344), ("K_RCTRL", 345)]
  for ch in 'a'..'z': result.add ("K_" & $ch, ord(ch.toUpperAscii()))
  for ch in '0'..'9': result.add ("K_" & $ch, ord(ch))

proc call*(ctx: GameContext, name: string, positional: seq[GameValue],
           kwargs: seq[tuple[name: string, val: GameValue]] = @[]): GameValue =
  let canonical = case name
    of "dip_out": "quit"
    of "display.pull_up": "display.set_mode"
    of "display.show_off": "display.flip"
    of "event.catch_vibes": "event.get"
    of "key.check_the_vibe": "key.get_pressed"
    of "Clock.keep_up": "Clock.tick"
    of "Surface.glow_up": "Surface.fill"
    of "draw.flex_rect": "draw.rect"
    of "draw.flex_circle": "draw.circle"
    of "draw.flex_line": "draw.line"
    of "draw.yap_text": "draw.text"
    else: name
  if canonical != name: return ctx.call(canonical, positional, kwargs)
  let a = arguments(name, positional, kwargs)
  result = empty()
  if name in ["Surface", "image.load", "font.Font", "mixer.Sound", "mixer.music.load", "Font.render"] and ctx.resources.len >= 4096:
    fail("too many live resources; unload unused surfaces, fonts, or sounds")
  case name
  of "init":
    ctx.ensureApi(); ctx.initialized = true
    return value(%*[1, 0])
  of "get_init": return value(%ctx.initialized)
  of "get_backend": return value(%"raylib 5.5 / native GPU 2D")
  of "quit": ctx.close()
  of "Rect":
    let r = Rectangle(x: num(a,0).cfloat, y: num(a,1).cfloat, width: num(a,2).cfloat, height: num(a,3).cfloat)
    if r.width < 0 or r.height < 0: fail("rectangle size must be nonnegative")
    return rectValue(ctx, r)
  of "math.Vector2": return vectorObject(ctx, Vector2(x: num(a,0).cfloat, y: num(a,1).cfloat))
  of "math.lerp": return value(%(num(a,0)+(num(a,1)-num(a,0))*num(a,2)))
  of "math.clamp":
    let low = num(a,1); let high = num(a,2)
    if low > high: fail("clamp low must not exceed high")
    return value(%clamp(num(a,0),low,high))
  of "math.smoothstep":
    let low = num(a,0); let high = num(a,1)
    if high <= low: fail("smoothstep high must exceed low")
    let t = clamp((num(a,2)-low)/(high-low),0,1)
    return value(%(t*t*(3-2*t)))
  of "math.ease":
    let t = clamp(num(a,0),0,1)
    let curve = if a.len > 1: text(a,1) else: "in_out_cubic"
    case curve
    of "linear": return value(%t)
    of "in_quad": return value(%(t*t))
    of "out_quad": return value(%(1-(1-t)*(1-t)))
    of "in_out_cubic": return value(%(if t < 0.5: 4*t*t*t else: 1-pow(-2*t+2,3)/2))
    of "out_back":
      let u = t-1; return value(%(1+2.70158*u*u*u+1.70158*u*u))
    else: fail("unknown easing curve: " & curve)
  of "Rect.copy", "Rect.move", "Rect.inflate", "Rect.colliderect", "Rect.collidepoint":
    let r = obj(a,0,gRect).rect
    case name
    of "Rect.copy": return rectValue(ctx,r)
    of "Rect.move": return rectValue(ctx,Rectangle(x: r.x+num(a,1).cfloat, y: r.y+num(a,2).cfloat,width: r.width,height: r.height))
    of "Rect.inflate":
      let w = r.width+num(a,1).cfloat; let h = r.height+num(a,2).cfloat
      if w < 0 or h < 0: fail("inflated rectangle size must be nonnegative")
      return rectValue(ctx,Rectangle(x:r.x-num(a,1).cfloat/2,y:r.y-num(a,2).cfloat/2,width:w,height:h))
    of "Rect.colliderect":
      let b = rectangle(a[1])
      return value(%(r.width > 0 and r.height > 0 and b.width > 0 and b.height > 0 and
        r.x < b.x+b.width and r.x+r.width > b.x and r.y < b.y+b.height and r.y+r.height > b.y))
    else:
      let p = vec(a[1]); return value(%(p.x >= r.x and p.x < r.x+r.width and p.y >= r.y and p.y < r.y+r.height))
  of "Vector2.length", "Vector2.normalize", "Vector2.rotate", "Vector2.dot", "Vector2.add", "Vector2.scale":
    let p = obj(a,0,gVector).vector
    case name
    of "Vector2.length": return value(%hypot(p.x.float,p.y.float))
    of "Vector2.normalize":
      let length = hypot(p.x.float,p.y.float)
      if length == 0: fail("cannot normalize a zero vector")
      return vectorObject(ctx,Vector2(x:(p.x/length).cfloat,y:(p.y/length).cfloat))
    of "Vector2.rotate":
      let radians = degToRad(num(a,1))
      return vectorObject(ctx,Vector2(x:(p.x*cos(radians)-p.y*sin(radians)).cfloat,y:(p.x*sin(radians)+p.y*cos(radians)).cfloat))
    of "Vector2.dot":
      let b = vec(a[1]); return value(%(p.x*b.x+p.y*b.y))
    of "Vector2.add":
      let b = vec(a[1]); return vectorObject(ctx,Vector2(x:p.x+b.x,y:p.y+b.y))
    else: return vectorObject(ctx,Vector2(x:(p.x*num(a,1)).cfloat,y:(p.y*num(a,1)).cfloat))
  of "time.Clock":
    let o = ctx.newObject(gClock); o.lastTick = getMonoTime(); return value(o)
  of "Clock.tick":
    let o = obj(a,0,gClock)
    let target = num(a,1)
    if target < 0 or target > 1000: fail("fps must be in 0..1000")
    var elapsed = (getMonoTime()-o.lastTick).inNanoseconds.float/1e6
    if target > 0 and elapsed < 1000/target:
      sleep(ceil(1000/target-elapsed).int)
      elapsed = (getMonoTime()-o.lastTick).inNanoseconds.float/1e6
    o.lastTick = getMonoTime(); o.elapsed = elapsed
    o.fps = if elapsed > 0: 1000/elapsed else: 0
    return value(%elapsed)
  of "Clock.get_fps": return value(%obj(a,0,gClock).fps)
  of "Clock.get_time": return value(%obj(a,0,gClock).elapsed)
  of "time.get_ticks": return value(%((getMonoTime()-ctx.started).inNanoseconds.float/1e6))
  of "time.wait":
    let ms = num(a,0)
    if ms < 0 or ms > 60000: fail("wait must be in 0..60000 milliseconds")
    sleep(ms.int); return value(%ms)
  of "camera.Camera":
    let o = ctx.newObject(gCamera)
    o.camera = Camera2D(target: Vector2(x:num(a,0).cfloat,y:num(a,1).cfloat),zoom:positive(num(a,2,1),"zoom",1000).cfloat,rotation:num(a,3).cfloat)
    return value(o)
  of "Camera.begin": ctx.activeCamera = obj(a,0,gCamera)
  of "Camera.end":
    if ctx.activeCamera == obj(a,0,gCamera): ctx.activeCamera = nil
  of "Camera.follow":
    let o = obj(a,0,gCamera); let p = vec(a[1])
    let smoothing = num(a,2,0); let dt = num(a,3,1.0/60)
    if smoothing < 0 or dt < 0: fail("smoothing and dt must be nonnegative")
    let t = if smoothing == 0: 1.0 else: 1-exp(-smoothing*dt)
    o.camera.target.x += ((p.x-o.camera.target.x)*t).cfloat
    o.camera.target.y += ((p.y-o.camera.target.y)*t).cfloat
  of "Camera.shake":
    let o = obj(a,0,gCamera)
    o.shakeStrength = positive(num(a,1),"shake strength",1000)
    o.shakeTime = positive(num(a,2),"shake duration",60)
  of "Camera.update":
    let o = obj(a,0,gCamera); let dt = num(a,1)
    if dt < 0: fail("dt must be nonnegative")
    o.shakeTime = max(0,o.shakeTime-dt)
    if o.shakeTime > 0:
      o.shakeOffset = Vector2(x:ctx.rng.rand(-o.shakeStrength..o.shakeStrength).cfloat,
                              y:ctx.rng.rand(-o.shakeStrength..o.shakeStrength).cfloat)
    else:
      o.shakeOffset = Vector2()
  of "Camera.world_to_screen", "Camera.screen_to_world":
    let c = obj(a,0,gCamera).camera; let p = vec(a[1])
    let angle = degToRad(c.rotation.float)
    var v: Vector2
    if name == "Camera.world_to_screen":
      let x = (p.x-c.target.x)*c.zoom; let y = (p.y-c.target.y)*c.zoom
      v = Vector2(x:(x*cos(angle)-y*sin(angle)+c.offset.x).cfloat,y:(x*sin(angle)+y*cos(angle)+c.offset.y).cfloat)
    else:
      let x = p.x-c.offset.x; let y = p.y-c.offset.y
      v = Vector2(x:((x*cos(angle)+y*sin(angle))/c.zoom+c.target.x).cfloat,y:((-x*sin(angle)+y*cos(angle))/c.zoom+c.target.y).cfloat)
    return value(vectorValue(v))
  of "particles.Emitter":
    let o = ctx.newObject(gEmitter)
    o.capacity = positive(num(a,0,1000),"max_particles",100000).int
    return value(o)
  of "Emitter.burst":
    let o = obj(a,0,gEmitter); let p = vec(a[1]); let count = num(a,2)
    if count < 0 or count > 100000 or count != floor(count): fail("particle count must be an integer in 0..100000")
    let c = tint(a,3); let speed = num(a,4,100)
    let lifetime = positive(num(a,5,1),"lifetime",3600)
    let radius = positive(num(a,6,3),"radius",512)
    if speed < 0: fail("particle speed must be nonnegative")
    let emitted = min(count.int,o.capacity-o.particles.len)
    for i in 0..<emitted:
      let angle = ctx.rng.rand(2*PI); let velocity = speed*ctx.rng.rand(0.3..1.0)
      o.particles.add Particle(pos:p,velocity:Vector2(x:(cos(angle)*velocity).cfloat,y:(sin(angle)*velocity).cfloat),life:lifetime,total:lifetime,radius:radius,color:c)
    return value(%emitted)
  of "Emitter.update":
    let o = obj(a,0,gEmitter); let dt = num(a,1); let gravity = num(a,2)
    if dt < 0: fail("dt must be nonnegative")
    var write = 0
    for i in 0..<o.particles.len:
      var p = o.particles[i]; p.life -= dt
      if p.life > 0:
        p.velocity.y += (gravity*dt).cfloat
        p.pos.x += (p.velocity.x*dt).cfloat; p.pos.y += (p.velocity.y*dt).cfloat
        o.particles[write] = p; inc write
    o.particles.setLen(write)
  of "Emitter.clear": obj(a,0,gEmitter).particles.setLen(0)
  of "animation.SpriteSheet":
    let source = obj(a,0,gSurface); ctx.requireAlive(source)
    if source.screen: fail("use an image or offscreen Surface for a sprite sheet")
    let w = positive(num(a,1),"frame width",8192)
    let h = positive(num(a,2),"frame height",8192)
    if w != floor(w) or h != floor(h): fail("frame size must be integers")
    if source.texture.width.int mod w.int != 0 or source.texture.height.int mod h.int != 0:
      fail("sprite sheet dimensions must be divisible by frame size")
    let o = ctx.newObject(gAnimation)
    o.source = source; o.frameWidth = w.int; o.frameHeight = h.int
    o.frameCount = (source.texture.width.int div w.int)*(source.texture.height.int div h.int)
    o.animationFps = positive(num(a,3,12),"animation fps",1000)
    o.looping = true
    if a.len > 4:
      if a[4].data == nil or a[4].data.kind != JBool: fail("loop must be a boolean")
      o.looping = a[4].data.getBool()
    return value(o)
  of "Animation.reset":
    let o = obj(a,0,gAnimation); o.frame = 0; o.animationTime = 0; o.finished = false
  of "Animation.update":
    let o = obj(a,0,gAnimation); let dt = num(a,1)
    if dt < 0: fail("dt must be nonnegative")
    o.animationTime += dt
    let duration = o.frameCount.float/o.animationFps
    if o.looping:
      o.animationTime = floorMod(o.animationTime,duration)
      o.frame = min(o.frameCount-1,floor(o.animationTime*o.animationFps).int)
    else:
      o.animationTime = min(o.animationTime,duration)
      o.frame = min(o.frameCount-1,floor(o.animationTime*o.animationFps).int)
      o.finished = o.animationTime >= duration
  of "Animation.draw":
    let o = obj(a,0,gAnimation); let surface = obj(a,1,gSurface); ctx.requireAlive(o.source)
    let position = vec(a[2]); let rotation = num(a,3)
    let scale = positive(num(a,4,1),"scale",1000); let c = tint(a,5)
    let columns = o.source.texture.width.int div o.frameWidth
    let x = (o.frame mod columns)*o.frameWidth; let y = (o.frame div columns)*o.frameHeight
    let source = if o.source.renderTarget:
      Rectangle(x:x.cfloat,y:(o.source.texture.height.int-y-o.frameHeight).cfloat,width:o.frameWidth.cfloat,height:(-o.frameHeight).cfloat)
    else: Rectangle(x:x.cfloat,y:y.cfloat,width:o.frameWidth.cfloat,height:o.frameHeight.cfloat)
    let dest = Rectangle(x:position.x,y:position.y,width:(o.frameWidth.float*scale).cfloat,height:(o.frameHeight.float*scale).cfloat)
    ctx.beginTarget(surface)
    ctx.api.DrawTexturePro(o.source.texture,source,dest,Vector2(),rotation.cfloat,c)
    ctx.endTarget(surface)
  of "display.set_mode":
    if ctx.window: fail("a window already exists; call quit before changing mode")
    let size = dimensions(a[0]); let flags = num(a,1)
    if flags < 0 or flags != floor(flags) or (flags.int and not (4 or 2 or 128 or 64)) != 0: fail("unsupported display flags")
    ctx.ensureApi()
    ctx.api.SetConfigFlags(flags.cuint)
    ctx.api.InitWindow(size.x.cint,size.y.cint,ctx.caption.cstring)
    if not ctx.api.IsWindowReady(): fail("window creation failed; a graphical desktop or Xvfb is required")
    ctx.window = true; ctx.initialized = true; ctx.api.SetExitKey(0)
    let o = ctx.newObject(gSurface); o.screen = true
    o.texture.width = size.x.cint; o.texture.height = size.y.cint
    ctx.screen = o; return value(o)
  of "display.set_caption":
    ctx.caption = text(a,0)
    if ctx.window: ctx.api.SetWindowTitle(ctx.caption.cstring)
  of "display.flip": ctx.flip()
  of "display.get_surface":
    if ctx.screen != nil: return value(ctx.screen)
  of "display.get_size":
    ctx.requireWindow(); return value(%*[ctx.api.GetScreenWidth(),ctx.api.GetScreenHeight()])
  of "event.get":
    ctx.requireWindow()
    var events = newJArray()
    if ctx.eventsRead: return value(events)
    ctx.eventsRead = true
    if ctx.api.WindowShouldClose(): events.add %*{"$event":true,"type":256}
    var key = ctx.api.GetKeyPressed()
    while key != 0:
      events.add %*{"$event":true,"type":768,"key":key}
      key = ctx.api.GetKeyPressed()
    for k in 0..348:
      if ctx.api.IsKeyReleased(k.cint): events.add %*{"$event":true,"type":769,"key":k}
    var ch = ctx.api.GetCharPressed()
    while ch != 0:
      events.add %*{"$event":true,"type":771,"codepoint":ch}
      ch = ctx.api.GetCharPressed()
    let mouse = ctx.api.GetMousePosition()
    if mouse != ctx.mouse:
      events.add %*{"$event":true,"type":1024,"pos":[mouse.x,mouse.y],"rel":[mouse.x-ctx.mouse.x,mouse.y-ctx.mouse.y]}
    ctx.mouse = mouse
    for button in 0..2:
      # raylib uses left/right/middle; pygame uses left/middle/right.
      let mapped = [1,3,2][button]
      if ctx.api.IsMouseButtonPressed(button.cint): events.add %*{"$event":true,"type":1025,"button":mapped,"pos":[mouse.x,mouse.y]}
      if ctx.api.IsMouseButtonReleased(button.cint): events.add %*{"$event":true,"type":1026,"button":mapped,"pos":[mouse.x,mouse.y]}
    let wheel = ctx.api.GetMouseWheelMove()
    if wheel != 0: events.add %*{"$event":true,"type":1027,"y":wheel}
    return value(events)
  of "key.get_pressed":
    ctx.requireWindow(); var keys = newJArray()
    for key in 0..511: keys.add %ctx.api.IsKeyDown(key.cint)
    return value(keys)
  of "mouse.get_pos":
    ctx.requireWindow(); return value(vectorValue(ctx.api.GetMousePosition()))
  of "mouse.get_pressed":
    ctx.requireWindow(); return value(%*[ctx.api.IsMouseButtonDown(0),ctx.api.IsMouseButtonDown(2),ctx.api.IsMouseButtonDown(1)])
  of "Surface":
    ctx.requireWindow(); let size = dimensions(a[0])
    let o = ctx.newObject(gSurface); o.renderTarget = true
    o.target = ctx.api.LoadRenderTexture(size.x.cint,size.y.cint)
    if not ctx.api.IsRenderTextureValid(o.target): fail("could not allocate surface")
    o.texture = o.target.texture
    ctx.beginTarget(o,false); ctx.api.ClearBackground(Color()); ctx.endTarget(o,false)
    return ctx.register(o)
  of "image.load":
    ctx.requireWindow(); let path = text(a,0)
    if not fileExists(path): fail("image does not exist: " & path)
    let o = ctx.newObject(gSurface); o.texture = ctx.api.LoadTexture(path.cstring)
    if not ctx.api.IsTextureValid(o.texture): fail("unsupported or invalid image: " & path)
    return ctx.register(o)
  of "image.save":
    let surface = obj(a,0,gSurface); let path = text(a,1)
    let image = ctx.readSurface(surface)
    defer: ctx.api.UnloadImage(image)
    if not ctx.api.ExportImage(image,path.cstring): fail("cannot save image: " & path)
  of "Surface.get_size", "Surface.get_width", "Surface.get_height", "Surface.get_rect":
    let o = obj(a,0,gSurface); ctx.requireAlive(o)
    let w = if o.screen: ctx.api.GetScreenWidth() else: o.texture.width
    let h = if o.screen: ctx.api.GetScreenHeight() else: o.texture.height
    case name
    of "Surface.get_width": return value(%w)
    of "Surface.get_height": return value(%h)
    of "Surface.get_rect": return rectValue(ctx,Rectangle(width:w.cfloat,height:h.cfloat))
    else: return value(%*[w,h])
  of "Surface.get_at":
    let o = obj(a,0,gSurface); let p = vec(a[1])
    if p.x < 0 or p.y < 0 or p.x >= o.texture.width.cfloat or p.y >= o.texture.height.cfloat: fail("pixel out of bounds")
    let image = ctx.readSurface(o)
    defer: ctx.api.UnloadImage(image)
    let c = ctx.api.GetImageColor(image,p.x.cint,p.y.cint)
    return value(%*[c.r,c.g,c.b,c.a])
  of "Surface.fill":
    let o = obj(a,0,gSurface); let c = color(a[1])
    ctx.beginTarget(o,false); ctx.api.ClearBackground(c); ctx.endTarget(o,false)
  of "Surface.blit":
    let o = obj(a,0,gSurface); let src = obj(a,1,gSurface)
    ctx.requireAlive(src)
    if src.screen or src == o: fail("cannot blit the screen or a surface onto itself")
    let position = if a[2].obj != nil and a[2].obj.kind == gRect: Vector2(x:a[2].obj.rect.x,y:a[2].obj.rect.y) else: vec(a[2])
    let rotation = num(a,3); let scale = positive(num(a,4,1),"scale",1000); let c = tint(a,5)
    let dest = Rectangle(x:position.x,y:position.y,width:(src.texture.width.float*scale).cfloat,height:(src.texture.height.float*scale).cfloat)
    let source = Rectangle(width:src.texture.width.cfloat,height:(if src.renderTarget: -src.texture.height else: src.texture.height).cfloat)
    ctx.beginTarget(o); ctx.api.DrawTexturePro(src.texture,source,dest,Vector2(),rotation.cfloat,c); ctx.endTarget(o)
    return rectValue(ctx,dest)
  of "draw.rect", "draw.circle", "draw.line", "draw.text":
    let surface = obj(a,0,gSurface)
    # Validate every argument before entering a render target.
    if name == "draw.rect":
      let c = color(a[1]); let r = rectangle(a[2]); let width = num(a,3)
      if width < 0: fail("outline width must be nonnegative")
      ctx.beginTarget(surface)
      if width == 0: ctx.api.DrawRectangleRec(r,c)
      else: ctx.api.DrawRectangleLinesEx(r,width.cfloat,c)
    elif name == "draw.circle":
      let c = color(a[1]); let center = vec(a[2]); let radius = positive(num(a,3),"radius"); let width = num(a,4)
      if width notin [0.0,1.0]: fail("circle outline width must be 0 (fill) or 1")
      ctx.beginTarget(surface)
      if width == 0: ctx.api.DrawCircleV(center,radius.cfloat,c)
      else: ctx.api.DrawCircleLinesV(center,radius.cfloat,c)
    elif name == "draw.line":
      let c = color(a[1]); let start = vec(a[2]); let finish = vec(a[3]); let width = positive(num(a,4,1),"line width")
      ctx.beginTarget(surface); ctx.api.DrawLineEx(start,finish,width.cfloat,c)
    else:
      let label = text(a,1); let position = vec(a[2]); let size = positive(num(a,3,20),"font size",512); let c = tint(a,4)
      ctx.beginTarget(surface); ctx.api.DrawTextEx(ctx.api.GetFontDefault(),label.cstring,position,size.cfloat,1,c)
    ctx.endTarget(surface)
  of "font.Font":
    ctx.requireWindow(); let size = positive(num(a,1),"font size",512)
    let o = ctx.newObject(gFont); o.fontSize = size
    if a[0].data != nil and a[0].data.kind == JNull:
      o.font = ctx.api.GetFontDefault(); o.defaultFont = true
    else:
      let path = text(a,0)
      if not fileExists(path): fail("font does not exist: " & path)
      var codepoints: seq[cint]
      if a.len > 2 and a[2].data != nil:
        let characters = text(a,2)
        for code in 32..126: codepoints.add code.cint
        for rune in characters.runes:
          if rune.cint notin codepoints: codepoints.add rune.cint
        if codepoints.len > 4096: fail("font character set exceeds 4096 glyphs")
      o.font = ctx.api.LoadFontEx(path.cstring,size.cint,
        (if codepoints.len == 0: nil else: addr codepoints[0]),codepoints.len.cint)
      if not ctx.api.IsFontValid(o.font): fail("font could not be loaded: " & path)
      # raylib falls back to the default font on some invalid files.
      if o.font.texture.id == ctx.api.GetFontDefault().texture.id: fail("font could not be decoded: " & path)
    return ctx.register(o)
  of "Font.render", "Font.size":
    let o = obj(a,0,gFont); ctx.requireAlive(o); let label = text(a,1)
    if label.len > 16384: fail("text is too long")
    if name == "Font.size": return value(vectorValue(ctx.api.MeasureTextEx(o.font,label.cstring,o.fontSize.cfloat,1)))
    if a[2].data == nil or a[2].data.kind != JBool: fail("antialias must be a boolean")
    let c = color(a[3])
    let size = ctx.api.MeasureTextEx(o.font,label.cstring,o.fontSize.cfloat,1)
    discard dimensions(value(%*[ceil(size.x.float),ceil(size.y.float)]))
    let image = ctx.api.ImageTextEx(o.font,label.cstring,o.fontSize.cfloat,1,c)
    if image.data == nil: fail("could not render text")
    defer: ctx.api.UnloadImage(image)
    let surface = ctx.newObject(gSurface); surface.texture = ctx.api.LoadTextureFromImage(image)
    if not ctx.api.IsTextureValid(surface.texture): fail("could not allocate text surface")
    ctx.api.SetTextureFilter(surface.texture,if a[2].data.getBool(): 1 else: 0)
    return ctx.register(surface)
  of "mixer.init": ctx.requireAudio()
  of "mixer.Sound":
    let path = text(a,0)
    if not fileExists(path): fail("sound does not exist: " & path)
    ctx.requireAudio()
    let o = ctx.newObject(gSound); o.sound = ctx.api.LoadSound(path.cstring)
    if not ctx.api.IsSoundValid(o.sound): fail("unsupported or invalid sound: " & path)
    return ctx.register(o)
  of "mixer.music.load":
    let path = text(a,0)
    if not fileExists(path): fail("music does not exist: " & path)
    ctx.requireAudio()
    let o = ctx.newObject(gMusic); o.music = ctx.api.LoadMusicStream(path.cstring)
    if not ctx.api.IsMusicValid(o.music): fail("unsupported or invalid music: " & path)
    return ctx.register(o)
  of "Music.play", "Music.pause", "Music.resume", "Music.stop", "Music.update", "Music.get_busy", "Music.set_volume":
    let o = obj(a,0,gMusic); ctx.requireAlive(o)
    case name
    of "Music.play": ctx.api.PlayMusicStream(o.music)
    of "Music.pause": ctx.api.PauseMusicStream(o.music)
    of "Music.resume": ctx.api.ResumeMusicStream(o.music)
    of "Music.stop": ctx.api.StopMusicStream(o.music)
    of "Music.update": ctx.api.UpdateMusicStream(o.music)
    of "Music.get_busy": return value(%ctx.api.IsMusicStreamPlaying(o.music))
    else:
      let volume = num(a,1)
      if volume < 0 or volume > 1: fail("volume must be in 0..1")
      ctx.api.SetMusicVolume(o.music,volume.cfloat)
  of "Sound.play", "Sound.stop", "Sound.get_busy", "Sound.set_volume", "Sound.set_pitch":
    let o = obj(a,0,gSound); ctx.requireAlive(o)
    case name
    of "Sound.play": ctx.api.PlaySound(o.sound)
    of "Sound.stop": ctx.api.StopSound(o.sound)
    of "Sound.get_busy": return value(%ctx.api.IsSoundPlaying(o.sound))
    of "Sound.set_volume":
      let v = num(a,1)
      if v < 0 or v > 1: fail("volume must be in 0..1")
      ctx.api.SetSoundVolume(o.sound,v.cfloat)
    else: ctx.api.SetSoundPitch(o.sound,positive(num(a,1),"pitch",8).cfloat)
  of "Surface.unload", "Font.unload", "Sound.unload", "Music.unload":
    if a[0].obj == nil or a[0].obj.owner != ctx: fail("invalid resource")
    ctx.release(a[0].obj)
  of "Emitter.draw":
    let o = obj(a,0,gEmitter); let surface = obj(a,1,gSurface)
    ctx.beginTarget(surface)
    for p in o.particles:
      var c = p.color; c.a = (c.a.float*clamp(p.life/p.total,0,1)).uint8
      ctx.api.DrawCircleV(p.pos,(p.radius*(p.life/p.total)).cfloat,c)
    ctx.endTarget(surface)
  else: fail("unimplemented function: " & name)
