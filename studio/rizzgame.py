"""Canvas-backed rizzgame subset for Genzimnify Studio (Pyodide only)."""
import ast
import asyncio
import json
import math as _math
import random
import time as _time
from types import SimpleNamespace
from js import rizzgameBridge as _bridge

QUIT, KEYDOWN, KEYUP = 256, 768, 769
MOUSEMOTION, MOUSEBUTTONDOWN, MOUSEBUTTONUP = 1024, 1025, 1026
K_SPACE, K_ESCAPE, K_RETURN, K_TAB, K_BACKSPACE = 32, 256, 257, 258, 259
K_RIGHT, K_LEFT, K_DOWN, K_UP = 262, 263, 264, 265
K_a, K_d, K_s, K_w = 65, 68, 83, 87


def _send(op, **values):
    _bridge.command(json.dumps(dict(op=op, **values)))


def _point(value):
    return [float(value[0]), float(value[1])]


class Surface:
    def __init__(self, size, _id=None):
        self.width, self.height = int(size[0]), int(size[1])
        if self.width < 1 or self.height < 1:
            raise ValueError("surface dimensions must be positive")
        self.id = int(_id if _id is not None else _bridge.createSurface(self.width, self.height))

    def fill(self, color):
        _send("fill", id=self.id, color=color)

    glow_up = fill

    def blit(self, source, position, rotation=0, scale=1, tint=None):
        _send("blit", id=self.id, source=source.id, position=_point(position),
              rotation=float(rotation), scale=float(scale))

    def get_size(self): return [self.width, self.height]
    def get_width(self): return self.width
    def get_height(self): return self.height
    def get_rect(self): return Rect(0, 0, self.width, self.height)
    def unload(self): _send("unload", id=self.id)


class _Display:
    surface = None
    target_fps = 60

    def set_mode(self, size, flags=0):
        _send("mode", width=int(size[0]), height=int(size[1]))
        self.surface = Surface(size, 0)
        return self.surface

    def set_caption(self, title): _send("caption", title=str(title))
    pull_up = set_mode
    def get_surface(self): return self.surface
    def get_size(self): return self.surface.get_size() if self.surface else [0, 0]

    async def flip_async(self):
        if _bridge.stopped:
            raise _Stopped()
        await asyncio.sleep(1 / max(1, min(120, self.target_fps)))
        if _bridge.stopped:
            raise _Stopped()

    def flip(self):
        raise RuntimeError("Studio needs display.flip() at top level, inside the game loop")

    show_off = flip
    show_off_async = flip_async


display = _Display()


class _Clock:
    def __init__(self):
        self.last = _time.monotonic()
        self.elapsed = 0

    def tick(self, fps=0):
        now = _time.monotonic()
        self.elapsed = (now - self.last) * 1000
        self.last = now
        if fps:
            display.target_fps = int(fps)
        return max(1, self.elapsed)

    keep_up = tick

    def get_time(self): return self.elapsed
    def get_fps(self): return 1000 / self.elapsed if self.elapsed else 0


time = SimpleNamespace(Clock=_Clock, get_ticks=lambda: int(_time.monotonic() * 1000))


def _events():
    return [SimpleNamespace(**item) for item in json.loads(str(_bridge.pollEvents()))]


event = SimpleNamespace(get=_events, catch_vibes=_events)


class _Pressed:
    def __init__(self, values): self.values = set(values)
    def __getitem__(self, key): return key in self.values


key = SimpleNamespace(get_pressed=lambda: _Pressed(json.loads(str(_bridge.pressed()))),
                      check_the_vibe=lambda: _Pressed(json.loads(str(_bridge.pressed()))))
mouse = SimpleNamespace(get_pos=lambda: json.loads(str(_bridge.mouseState()))["pos"],
                        get_pressed=lambda: _Pressed(json.loads(str(_bridge.mouseState()))["buttons"]))


def _rect(surface, color, rect, width=0):
    _send("rect", id=surface.id, color=color, rect=list(rect), width=float(width))


def _circle(surface, color, center, radius, width=0):
    _send("circle", id=surface.id, color=color, center=_point(center),
          radius=float(radius), width=float(width))


def _line(surface, color, start, end, width=1):
    _send("line", id=surface.id, color=color, start=_point(start), end=_point(end), width=float(width))


def _text(surface, text, position, size=20, color=(255, 255, 255)):
    _send("text", id=surface.id, text=str(text), position=_point(position), size=int(size), color=color)


draw = SimpleNamespace(rect=_rect, circle=_circle, line=_line, text=_text,
                       flex_rect=_rect, flex_circle=_circle, flex_line=_line, yap_text=_text)


class Rect:
    def __init__(self, x, y, width, height):
        self.x, self.y, self.width, self.height = float(x), float(y), float(width), float(height)

    @property
    def left(self): return self.x
    @left.setter
    def left(self, value): self.x = value
    @property
    def top(self): return self.y
    @top.setter
    def top(self, value): self.y = value
    @property
    def right(self): return self.x + self.width
    @right.setter
    def right(self, value): self.x = value - self.width
    @property
    def bottom(self): return self.y + self.height
    @bottom.setter
    def bottom(self, value): self.y = value - self.height
    @property
    def center(self): return [self.x + self.width / 2, self.y + self.height / 2]
    @center.setter
    def center(self, value): self.x, self.y = value[0] - self.width / 2, value[1] - self.height / 2
    @property
    def size(self): return [self.width, self.height]
    @size.setter
    def size(self, value): self.width, self.height = value
    def __iter__(self): return iter((self.x, self.y, self.width, self.height))
    def copy(self): return Rect(*self)
    def move(self, dx, dy): return Rect(self.x + dx, self.y + dy, self.width, self.height)
    def inflate(self, dx, dy): return Rect(self.x - dx / 2, self.y - dy / 2, self.width + dx, self.height + dy)
    def collidepoint(self, point): return self.left <= point[0] < self.right and self.top <= point[1] < self.bottom
    def colliderect(self, other): return self.left < other.right and other.left < self.right and self.top < other.bottom and other.top < self.bottom


math = SimpleNamespace(clamp=lambda value, lo, hi: max(lo, min(hi, value)),
                       lerp=lambda a, b, t: a + (b - a) * t,
                       smoothstep=lambda a, b, t: 0 if a == b else (lambda x: x * x * (3 - 2 * x))(max(0, min(1, (t - a) / (b - a)))))


class _Camera:
    def __init__(self, x=0, y=0, zoom=1, rotation=0):
        self.x, self.y, self.zoom, self.rotation = float(x), float(y), float(zoom), float(rotation)
        self._shake = 0
        self._duration = 0

    def follow(self, position, smoothing=0, dt=1/60):
        factor = 1 if smoothing == 0 else 1 - _math.exp(-smoothing * dt)
        self.x += (position[0] - self.x) * factor
        self.y += (position[1] - self.y) * factor

    def shake(self, strength, duration):
        self._shake, self._duration = float(strength), float(duration)

    def update(self, dt):
        self._duration = max(0, self._duration - dt)

    def begin(self):
        strength = self._shake if self._duration > 0 else 0
        _send("camera_begin", x=self.x + random.uniform(-strength, strength),
              y=self.y + random.uniform(-strength, strength), zoom=self.zoom, rotation=self.rotation)

    def end(self): _send("camera_end")


camera = SimpleNamespace(Camera=_Camera)


class _Emitter:
    def __init__(self, max_particles=1000):
        self.capacity = max(1, int(max_particles))
        self._particles = []

    @property
    def count(self): return len(self._particles)

    def burst(self, position, count, color=(255, 255, 255), speed=100, lifetime=1, radius=3):
        count = min(int(count), self.capacity - len(self._particles))
        for _ in range(count):
            angle = random.random() * 2 * _math.pi
            velocity = random.random() * speed
            self._particles.append([float(position[0]), float(position[1]),
                                    _math.cos(angle) * velocity, _math.sin(angle) * velocity,
                                    float(lifetime), float(lifetime), list(color), float(radius)])
        return count

    def update(self, dt, gravity=0):
        for particle in self._particles:
            particle[0] += particle[2] * dt
            particle[1] += particle[3] * dt
            particle[3] += gravity * dt
            particle[4] -= dt
        self._particles = [particle for particle in self._particles if particle[4] > 0]

    def draw(self, surface):
        for x, y, _, _, life, total, color, radius in self._particles:
            tint = color[:3] + [int(255 * life / total)]
            _circle(surface, tint, [x, y], radius)

    def clear(self): self._particles.clear()


particles = SimpleNamespace(Emitter=_Emitter)


class _SpriteSheet:
    def __init__(self, surface, frame_width, frame_height, fps=12, loop=True):
        self.surface = surface
        self.frame_width = int(frame_width)
        self.frame_height = int(frame_height)
        self.fps = float(fps)
        self.loop = bool(loop)
        self.columns = surface.width // self.frame_width
        self.frame_count = self.columns * (surface.height // self.frame_height)
        if self.frame_count < 1 or self.fps <= 0:
            raise ValueError("sprite sheet needs positive frames and fps")
        self.frame = 0
        self.elapsed = 0
        self.finished = False

    def update(self, dt):
        self.elapsed += dt
        count = int(self.elapsed * self.fps)
        self.frame = count % self.frame_count if self.loop else min(count, self.frame_count - 1)
        self.finished = not self.loop and count >= self.frame_count

    def reset(self):
        self.elapsed = 0
        self.frame = 0
        self.finished = False

    def draw(self, surface, position, rotation=0, scale=1, tint=None):
        _send("sprite", id=surface.id, source=self.surface.id, position=_point(position),
              frame=[(self.frame % self.columns) * self.frame_width,
                     (self.frame // self.columns) * self.frame_height,
                     self.frame_width, self.frame_height], rotation=float(rotation), scale=float(scale))


animation = SimpleNamespace(SpriteSheet=_SpriteSheet)


class _Stopped(Exception): pass


class _FlipTransformer(ast.NodeTransformer):
    def __init__(self):
        self.function_depth = 0
        self.display_aliases = set()
    def visit_ImportFrom(self, node):
        if node.module == "rizzgame":
            for alias in node.names:
                if alias.name == "display": self.display_aliases.add(alias.asname or "display")
                elif alias.name == "*": self.display_aliases.add("display")
        return node
    def visit_FunctionDef(self, node):
        self.function_depth += 1
        node = self.generic_visit(node)
        self.function_depth -= 1
        return node
    visit_AsyncFunctionDef = visit_FunctionDef
    def visit_While(self, node):
        node = self.generic_visit(node)
        if not self.function_depth:
            heartbeat = ast.Expr(value=ast.Await(value=ast.Call(
                func=ast.Name(id="_rizzgame_yield", ctx=ast.Load()), args=[], keywords=[])))
            node.body.insert(0, ast.copy_location(heartbeat, node))
        return node
    visit_For = visit_While
    def visit_Call(self, node):
        node = self.generic_visit(node)
        func = node.func
        if (isinstance(func, ast.Attribute) and func.attr in ("flip", "show_off") and
                ((isinstance(func.value, ast.Attribute) and func.value.attr == "display") or
                 (isinstance(func.value, ast.Name) and func.value.id in self.display_aliases))):
            if self.function_depth:
                raise RuntimeError("Studio preview supports display.flip() in the top-level game loop")
            func.attr = "flip_async" if func.attr == "flip" else "show_off_async"
            return ast.copy_location(ast.Await(value=node), node)
        return node


async def run_source(source):
    tree = _FlipTransformer().visit(ast.parse(source, filename="<studio>"))
    ast.fix_missing_locations(tree)
    code = compile(tree, "<studio>", "exec", flags=ast.PyCF_ALLOW_TOP_LEVEL_AWAIT)
    async def heartbeat():
        if _bridge.stopped:
            raise _Stopped()
        await asyncio.sleep(0)
    scope = {"__name__": "__main__", "__builtins__": __builtins__, "_rizzgame_yield": heartbeat,
             "args": []}
    try:
        result = eval(code, scope)
        if asyncio.iscoroutine(result):
            await result
    except _Stopped:
        pass


def init(): return None

def quit(): return None

dip_out = quit

def get_backend(): return "browser canvas"
