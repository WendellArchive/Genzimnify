"""End-to-end conversion checks; pass the compiled gzim executable as argv[1]."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


GZIM = str(Path(sys.argv.pop(1)).resolve())


class ConversionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gzim conversion ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def source(self, text, name="main.py"):
        path = self.root / name
        path.write_text(text, encoding="utf-8")
        return path

    def run_cli(self, *args, success=True):
        result = subprocess.run([GZIM, *map(str, args)], capture_output=True, encoding="utf-8")
        if success:
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def python_output(self, path):
        result = subprocess.run([sys.executable, "-X", "utf8", str(path)], capture_output=True, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def compare(self, source):
        path = self.source(source)
        expected = self.python_output(path)
        self.run_cli("convert", path, "--to", "gzim")
        converted = path.with_suffix(".gzim")
        self.run_cli("check", converted)
        self.assertEqual(self.run_cli("run", converted).stdout, expected)
        exported = self.root / "roundtrip.py"
        self.run_cli("convert", converted, "--to", "py", "-o", exported)
        self.assertEqual(self.python_output(exported), expected)
        self.assertEqual(path.read_text(encoding="utf-8"), source)
        return converted.read_text(encoding="utf-8")

    def test_control_flow_functions_and_collections(self):
        self.compare('''def fizzbuzz(limit, prefix=""):
    values = []
    for i in range(1, limit + 1):
        if i % 15 == 0:
            values.append(prefix + "FizzBuzz")
        elif i % 3 == 0:
            values.append("Fizz")
        elif i % 5 == 0:
            values.append("Buzz")
        else:
            values.append(str(i))
    return values
print(fizzbuzz(16, prefix="!"))
x = 0
while x < 5:
    x += 1
    if x == 2:
        continue
    if x == 4:
        break
    print(x)
d = {"a": 1, "b": 2}
d["a"] = 7
d["a"] += 2
print(d["a"], len(d), (1,), [])
print(True and not False, None, 2 ** 3, -(-4), 7 // 2)
''')

    def test_shadowed_builtins_and_reserved_names(self):
        generated = self.compare('''def print(value):
    return value + 1
yap = print(4)
_py_yap = 9
fam = 2
def compute(cap=3):
    return cap + fam + yap + _py_yap
result = compute(cap=7)
def report():
    pass
report()
''')
        self.assertIn("cook print(", generated)
        self.assertIn("_py_yap", generated)
        self.assertIn("_py__py_yap", generated)
        self.assertIn("_py_cap be 7", generated)

    def test_scoped_builtin_shadow(self):
        self.compare('''def compute(len):
    return len + 1
print(compute(4), len([1, 2]))
def maker(x):
    def inner(y=2):
        return x + y
    return inner()
print(maker(3))
''')

    def test_strings_and_builtin_names_are_not_text_replaced(self):
        self.compare('print("你好 print let\\nline\\t\\\\", "café", "\\u263a")\nprint(3 < 4 and 4 < 5)\n')

    def test_empty_source(self):
        self.compare("# comments are intentionally not preserved\n")

    def test_builtin_constructors_and_common_calls(self):
        self.compare('''print(list(), tuple(), dict(), int(), float(), str(), bool())
print(len(set()), len(set([1, 1, 2])))
print(sum([1, 2, 3]), min([3, 1]), max([3, 1]), abs(-2))
print(sorted([3, 1, 2]), list(zip([1, 2], [3, 4])))
print(list(enumerate([8, 9], 2)))
print(1 in [1, 2], 3 not in [1, 2], False or 9)
''')

    def test_parsing_never_executes_source(self):
        path = self.source('while True:\n    pass\n')
        result = subprocess.run([GZIM, "convert", str(path), "--to", "gzim"],
                                capture_output=True, encoding="utf-8", timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_python_syntax_and_native_validation_errors(self):
        for source, line in [("x = 1\nif :\n    pass\n", 2),
                             ("x = 1\ny += 2\n", 2)]:
            path = self.source(source)
            result = self.run_cli("convert", path, "--to", "gzim", success=False)
            self.assertIn(str(path) + ":" + str(line) + ":", result.stderr)
            self.assertFalse(path.with_suffix(".gzim").exists())

    def test_reject_unsupported_without_output(self):
        cases = ["import math", "class C: pass", "async def f(): pass",
                 "x = [n for n in range(3)]", "print(1 < 2 < 3)",
                 "x = lambda a: a", "x: int = 1", "x = b'abc'",
                 "x = 1 << 2", "x = 2 ** 100\nprint(x is x)",
                 "x = 9223372036854775808", "print(unknown)",
                 "a = b = 1", "x, y = (1, 2)", "print('\\x00')",
                 "def f(*args): pass", "print(**{})", "return 1", "round(2.5)",
                 "print(1, end='')", "sorted([1, 2], reverse=True)", "f = print",
                 "min(1, 2)", "dict(a=1)", "'a'.replace(old='a', new='b')",
                 "x = [1]\nx.reverse(2)", "x = [1]\nf = x.append",
                 "x = [1, 2][:1]", "for i in []:\n    pass\nelse:\n    pass"]
        for source in cases:
            with self.subTest(source=source):
                path = self.source(source + "\n")
                result = self.run_cli("convert", path, "--to", "gzim", success=False)
                self.assertIn(str(path) + ":", result.stderr)
                self.assertFalse(path.with_suffix(".gzim").exists())

    def test_overwrite_and_failed_force_leave_existing_file_intact(self):
        path = self.source("print(1)\n")
        out = path.with_suffix(".gzim")
        out.write_text("sentinel", encoding="utf-8")
        self.assertIn("--force", self.run_cli("convert", path, "--to", "gzim", success=False).stderr)
        self.assertEqual(out.read_text(), "sentinel")
        self.source("import math\n")
        self.run_cli("convert", path, "--to", "gzim", "--force", success=False)
        self.assertEqual(out.read_text(), "sentinel")
        self.source("print(2)\n")
        self.run_cli("convert", path, "--to", "gzim", "--force")
        self.assertEqual(self.run_cli("run", out).stdout, "2\n")
        self.assertEqual(list(self.root.glob(".gzim-convert-*")), [])

    def test_output_path_and_source_protection(self):
        path = self.source("print(1)\n", "space 你好.py")
        out = self.root / "different name.gzim"
        self.run_cli("convert", path, "--to", "gzim", "--output", out)
        self.assertTrue(out.exists())
        self.run_cli("convert", path, "--to", "gzim", "-o", path, "--force", success=False)
        self.assertEqual(path.read_text(), "print(1)\n")
        self.run_cli("convert", path, "--to", "gzim", "-o", self.root, "--force", success=False)
        self.run_cli("convert", path, "--to", "gzim", "-o", self.root / "missing/out.gzim", success=False)

    @unittest.skipIf(os.name == "nt", "Windows symlink creation needs extra privileges")
    def test_aliases_cannot_overwrite_source(self):
        path = self.source("print(1)\n")
        for kind in ("symlink", "hardlink"):
            alias = self.root / (kind + ".gzim")
            if kind == "symlink":
                alias.symlink_to(path)
            else:
                os.link(path, alias)
            self.run_cli("convert", path, "--to", "gzim", "-o", alias, "--force", success=False)
            self.assertEqual(path.read_text(), "print(1)\n")

    def test_cli_validation(self):
        path = self.source("print(1)\n")
        for args in [[], [path], [path, "--to"], [path, "--to", "js"],
                     [path, "--to", "py"], [path, "--to", "gzim", "-o"],
                     [path, "--to", "gzim", "--unknown"],
                     [path, "--to", "gzim", "--to", "gzim"],
                     [self.root / "absent.py", "--to", "gzim"]]:
            with self.subTest(args=args):
                self.run_cli("convert", *args, success=False)
        self.assertIn("--to", self.run_cli("convert", "--help").stdout)

    def test_source_map_and_forward_conversion(self):
        path = self.source('yap("hello")\n', "main.gzim")
        self.run_cli("convert", path, "--to", "py", "--source-map")
        self.assertTrue(self.root.joinpath("main.py.gzmap").exists())
        self.run_cli("convert", path, "--to", "py", success=False)
        self.run_cli("convert", path, "--to", "py", "--force")
        self.assertEqual(self.python_output(path.with_suffix(".py")), "hello\n")

    def test_check_only_does_not_write_or_require_unused_destination(self):
        path = self.source("print(1)\n")
        output = path.with_suffix(".gzim")
        output.write_text("sentinel")
        self.run_cli("convert", path, "--to", "gzim", "--check")
        self.assertEqual(output.read_text(), "sentinel")
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), ["main.gzim", "main.py"])
        output.unlink()
        self.source("import math\n")
        error = self.run_cli("convert", path, "--to", "gzim", "--check", success=False).stderr
        self.assertIn("import math", error)
        self.assertIn("^", error)
        self.assertIn("hint:", error)
        self.assertFalse(output.exists())
        native = self.source('yap("ok")\n', "native.gzim")
        self.run_cli("convert", native, "--to", "py", "--check")
        self.assertFalse(native.with_suffix(".py").exists())
        for option in (["--force"], ["-o", str(output)], ["--source-map"]):
            self.run_cli("convert", native, "--to", "py", "--check", *option, success=False)

    def test_source_map_preflight_preserves_output(self):
        path = self.source('yap("ok")\n', "main.gzim")
        sidecar = self.source("sentinel", "main.py.gzmap")
        self.run_cli("convert", path, "--to", "py", "--source-map", success=False)
        self.assertFalse(path.with_suffix(".py").exists())
        self.assertEqual(sidecar.read_text(), "sentinel")
        self.run_cli("convert", path, "--to", "py", "--source-map", "--force")
        self.assertNotEqual(sidecar.read_text(), "sentinel")
        self.assertEqual(self.python_output(path.with_suffix(".py")), "ok\n")

    def test_removed_commands_explain_replacement(self):
        path = self.source('yap("ok")\n', "main.gzim")
        for command in ("build", "emit-python"):
            error = self.run_cli(command, path, success=False).stderr
            self.assertIn("gzim convert", error)
            self.assertFalse(path.with_suffix(".py").exists())

    def test_forward_syntax_error_leaves_existing_output(self):
        path = self.source("let x be\n", "main.gzim")
        out = self.source("sentinel\n", "main.py")
        self.run_cli("convert", path, "--to", "py", "--force", success=False)
        self.assertEqual(out.read_text(), "sentinel\n")

    @unittest.skipIf(os.name == "nt", "Windows process lookup also searches system paths")
    def test_python_dependency_is_only_for_reverse_conversion(self):
        path = self.source('yap("hello")\n', "main.gzim")
        environment = dict(os.environ, PATH=str(self.root))
        result = subprocess.run([GZIM, "convert", str(path), "--to", "py"],
                                env=environment, capture_output=True, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run([GZIM, "convert", str(path.with_suffix(".py")),
                                 "--to", "gzim", "--force"],
                                env=environment, capture_output=True, encoding="utf-8")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("needs Python 3.8+", result.stderr)
        self.assertEqual(path.read_text(), 'yap("hello")\n')


if __name__ == "__main__":
    unittest.main()
