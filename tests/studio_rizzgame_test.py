"""Exercise Studio's browser adapter with a small fake Canvas bridge."""
import asyncio
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
from types import ModuleType
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Bridge:
    stopped = False

    def __init__(self):
        self.commands = []
        self.polls = 0
        self.next_surface = 1

    def command(self, source):
        self.commands.append(json.loads(source))

    def createSurface(self, width, height):
        value = self.next_surface
        self.next_surface += 1
        return value

    def pollEvents(self):
        self.polls += 1
        return json.dumps([{"type": 768, "key": 256}] if self.polls == 3 else [])

    def pressed(self):
        return json.dumps([65])

    def mouseState(self):
        return json.dumps({"pos": [12, 20], "buttons": []})


class StudioRizzgameTest(unittest.TestCase):
    def setUp(self):
        self.bridge = Bridge()
        js = ModuleType("js")
        js.rizzgameBridge = self.bridge
        sys.modules["js"] = js
        spec = importlib.util.spec_from_file_location("rizzgame", ROOT / "studio" / "rizzgame.py")
        self.game = importlib.util.module_from_spec(spec)
        sys.modules["rizzgame"] = self.game
        spec.loader.exec_module(self.game)

    def tearDown(self):
        sys.modules.pop("rizzgame", None)
        sys.modules.pop("js", None)

    def test_slang_game_loop_draws_frames_and_handles_input(self):
        source = '''import rizzgame as rg
screen = rg.display.pull_up([320, 180])
clock = rg.time.Clock()
player = rg.Rect(10, 10, 20, 20)
running = True
while running:
    dt = clock.keep_up(60) / 1000
    for event in rg.event.catch_vibes():
        if event.type == rg.KEYDOWN and event.key == rg.K_ESCAPE:
            running = False
    if rg.key.check_the_vibe()[rg.K_a]:
        player.x += 10 * dt
    screen.glow_up([10, 20, 30])
    rg.draw.flex_rect(screen, [255, 0, 0], player)
    rg.draw.yap_text(screen, "hi", [0, 0])
    rg.display.show_off()
rg.dip_out()
'''
        asyncio.run(self.game.run_source(source))
        operations = [item["op"] for item in self.bridge.commands]
        self.assertEqual(operations.count("mode"), 1)
        self.assertEqual(operations.count("fill"), 3)
        self.assertEqual(operations.count("rect"), 3)
        self.assertEqual(operations.count("text"), 3)
        self.assertEqual(self.bridge.polls, 3)
        self.assertEqual(self.bridge.commands[0]["width"], 320)

    def test_nested_frame_presentation_is_rejected_clearly(self):
        with self.assertRaisesRegex(RuntimeError, "top-level game loop"):
            asyncio.run(self.game.run_source("import rizzgame as rg\ndef frame():\n    rg.display.show_off()\nframe()\n"))

    def test_from_import_display_alias_and_for_loop(self):
        asyncio.run(self.game.run_source('''from rizzgame import display as screen_api
screen = screen_api.pull_up([320, 180])
for frame in range(2):
    screen.glow_up([10, 20, 30])
    screen_api.show_off()
'''))
        self.assertEqual(sum(item['op'] == 'fill' for item in self.bridge.commands), 2)

    def test_native_neon_arena_demo_runs_in_browser_adapter(self):
        script = '''const fs=require("fs"),vm=require("vm");const c=vm.createContext({console});
vm.runInContext(fs.readFileSync("studio/transpiler.js","utf8"),c);
c.source=fs.readFileSync("examples/rizzgame/neon_arena.gzim","utf8");
process.stdout.write(vm.runInContext("compileGzim(source)",c));'''
        compiled = subprocess.run(["node", "-e", script], cwd=ROOT, check=True,
                                  capture_output=True, text=True)
        result = json.loads(compiled.stdout)
        self.assertTrue(result["ok"], result.get("error"))
        asyncio.run(self.game.run_source(result["code"]))
        operations = [item["op"] for item in self.bridge.commands]
        self.assertIn("sprite", operations)
        self.assertIn("camera_begin", operations)
        self.assertIn("blit", operations)
        self.assertGreater(operations.count("circle"), 10)


if __name__ == "__main__":
    unittest.main()
