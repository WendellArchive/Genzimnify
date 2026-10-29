"""Native rizzgame integration; graphics opt in via GZIM_RIZZGAME_GRAPHICS_TEST=1."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

GZIM = str(Path(sys.argv.pop(1)).resolve())

class RizzgameTests(unittest.TestCase):
    def run_game(self, code, success=True, env=None):
        with tempfile.TemporaryDirectory(prefix="rizzgame test ") as root:
            path = Path(root) / "main.gzim"
            path.write_text(code, encoding="utf-8")
            result = subprocess.run([GZIM, str(path)], cwd=root, env=env,
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
            return result

    def test_pure_geometry_and_keywords_without_graphics_library(self):
        result = self.run_game('''pull up rizzgame as rg
let box be call up rg.Rect(10, 20, 30, 40) yo
yap(box.center)
box.right be 90
box.center be [30, 40]
yap(box.x, box.y, box.right, box.bottom)
yap(call up box.collidepoint([30, 40]) yo)
yap(call up box.collidepoint([45, 60]) yo)
yap(call up box.colliderect([40, 30, 20, 20]) yo)
let shifted be call up box.move(10, -10) yo
yap(shifted.center, box.center)
let vector be call up rg.math.Vector2(y be 4, x be 3) yo
yap(call up vector.length() yo)
yap(call up rg.math.lerp(10, 20, 0.5) yo)
yap(call up rg.math.ease(0.5) yo)
yap(call up rg.get_init() yo)
''', env=dict(os.environ, PATH="", GZIM_RAYLIB="/missing/raylib"))
        self.assertEqual(result.stdout.splitlines(), ["[25.0, 40.0]", "15.0 20.0 45.0 60.0",
            "True", "False", "True", "[40.0, 30.0] [30.0, 40.0]", "5.0", "15.0", "0.5", "False"])

    def test_camera_particle_lifecycle_and_real_clock(self):
        result = self.run_game('''pull up rizzgame as rg
let camera be call up rg.camera.Camera(10, 20, 2) yo
camera.offset be [100, 100]
yap(call up camera.world_to_screen([20, 30]) yo)
yap(call up camera.screen_to_world([120, 120]) yo)
let particles be call up rg.particles.Emitter(10) yo
yap(call up particles.burst([0, 0], 30, lifetime be 0.5) yo)
yap(particles.count)
call up particles.update(1) yo
yap(particles.count)
let timer be call up rg.time.Clock() yo
let ms be call up timer.keep_up(50) yo
yap(ms >= 19)
yap(call up timer.get_fps() yo > 0)
''')
        self.assertEqual(result.stdout.splitlines(), ["[120.0, 120.0]", "[20.0, 30.0]", "10", "10", "0", "True", "True"])

    def test_invalid_calls_fail_cleanly(self):
        for source in [
            'call up rg.Rect(0, 0, -1, 1) yo',
            'let zero be call up rg.math.Vector2(0, 0) yo\ncall up zero.normalize() yo',
            'call up rg.math.Vector2(1, x be 2) yo',
            'call up rg.math.ease(0.5, "missing") yo',
            'call up rg.display.flip() yo',
            'call up rg.camera.Camera(zoom be 0) yo',
            'call up rg.math.clamp(1, 3, 2) yo',
            'call up rg.Rect(0, 0, 1, 1, 2) yo',
            'call up rg.math.Vector2(z be 1) yo',
        ]:
            with self.subTest(source=source):
                result = self.run_game('pull up rizzgame as rg\n' + source + '\n', success=False)
                self.assertIn("rizzgame:", result.stderr)
                self.assertNotIn("SIGSEGV", result.stderr)

    def test_submodule_import(self):
        result = self.run_game('''pull up rizzgame.math as gm
let v be call up gm.Vector2(3, 4) yo
yap(call up v.length() yo)
''')
        self.assertEqual(result.stdout, "5.0\n")

    @unittest.skipUnless(os.getenv("GZIM_RIZZGAME_GRAPHICS_TEST") == "1", "requires a desktop or Xvfb")
    def test_real_gpu_surfaces_images_fonts_and_resource_invalidation(self):
        result = self.run_game('''pull up rizzgame as rg
call up rg.init() yo
let screen be call up rg.display.pull_up([160, 120], rg.HIDDEN) yo
let canvas be call up rg.Surface([80, 60]) yo
call up canvas.glow_up([10, 20, 30]) yo
call up rg.draw.flex_rect(canvas, [240, 60, 90], [10, 10, 20, 20]) yo
yap(call up canvas.get_at([15, 15]) yo)
yap(call up canvas.get_at([0, 0]) yo)
call up rg.image.save(canvas, "scene.png") yo
let image be call up rg.image.load("scene.png") yo
yap(call up image.get_size() yo)
call up screen.glow_up([0, 0, 0]) yo
call up screen.blit(image, [0, 0], scale be 2) yo
let sheet be call up rg.Surface([20, 10]) yo
call up sheet.fill([0, 0, 0]) yo
call up rg.draw.rect(sheet, [255, 0, 0], [0, 0, 10, 10]) yo
call up rg.draw.rect(sheet, [0, 255, 0], [10, 0, 10, 10]) yo
let animation be call up rg.animation.SpriteSheet(sheet, 10, 10, 2, cap) yo
let stage be call up rg.Surface([20, 10]) yo
call up animation.draw(stage, [0, 0]) yo
yap(call up stage.get_at([5, 5]) yo)
call up animation.update(0.6) yo
call up animation.draw(stage, [10, 0]) yo
yap(call up stage.get_at([15, 5]) yo)
call up animation.update(0.6) yo
yap(animation.frame, animation.finished)
let font be call up rg.font.Font(ghost, 16) yo
let label be call up font.render("Native!", nocap, [255, 255, 255]) yo
yap(call up label.get_width() yo > 0)
call up screen.blit(label, [5, 90]) yo
let camera be call up rg.camera.Camera(10, 0, 1) yo
call up camera.begin() yo
call up rg.draw.rect(canvas, [0, 255, 0], [50, 0, 10, 10]) yo
call up camera.end() yo
yap(call up canvas.get_at([42, 2]) yo)
call up rg.draw.flex_circle(screen, [30, 40, 50], [60, 60], 5) yo
call up rg.draw.flex_line(screen, [30, 40, 50], [0, 0], [10, 10]) yo
call up rg.draw.yap_text(screen, "slay", [0, 0]) yo
call up rg.display.show_off() yo
call up label.unload() yo
call up font.unload() yo
call up image.unload() yo
call up rg.dip_out() yo
yap(call up rg.get_init() yo)
call up rg.display.set_mode([100, 100], rg.HIDDEN) yo
call up rg.quit() yo
''')
        for line in ["[240, 60, 90, 255]", "[10, 20, 30, 255]", "[80, 60]", "[0, 255, 0, 255]", "[255, 0, 0, 255]", "1 True", "True", "False"]:
            self.assertIn(line, result.stdout.splitlines())
        result = self.run_game('''pull up rizzgame as rg
let screen be call up rg.display.set_mode([100, 100], rg.HIDDEN) yo
let surface be call up rg.Surface([10, 10]) yo
call up rg.quit() yo
call up surface.fill([0, 0, 0]) yo
''', success=False)
        self.assertIn("resource was unloaded", result.stderr)

if __name__ == "__main__":
    unittest.main()
