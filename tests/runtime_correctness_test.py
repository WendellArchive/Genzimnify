"""Runtime correctness and native/Python parity regression checks."""
import subprocess
import sys
import tempfile
import unittest
import time
from pathlib import Path

GZIM = str(Path(sys.argv.pop(1)).resolve())


class RuntimeCorrectnessTests(unittest.TestCase):
    def run_code(self, code):
        return subprocess.run([GZIM, 'eval', code], capture_output=True, text=True, timeout=15)

    def parity(self, code, expected):
        result = self.run_code(code)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, expected)
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'case.gzim'
            source.write_text(code, encoding='utf-8')
            converted = subprocess.run([GZIM, 'convert', str(source), '--to', 'py'], capture_output=True, text=True)
            self.assertEqual(converted.returncode, 0, converted.stderr)
            exported = subprocess.run([sys.executable, str(source.with_suffix('.py'))], capture_output=True, text=True, timeout=15)
            self.assertEqual(exported.returncode, 0, exported.stderr)
            self.assertEqual(exported.stdout, expected)

    def test_integer_precision_and_mixed_comparisons(self):
        self.parity('''yap(9007199254740992 == 9007199254740993)
yap(9007199254740993 > 9007199254740992)
yap(9007199254740993 == 9007199254740992.0)
yap(9007199254740993 > 9007199254740992.0)
yap(9223372036854775807 < 9223372036854775808.0)
yap(9007199254740993 // 1, 9007199254740993 % 2)
yap(-7 // 3, -7 % 3, 7 // -3, 7 % -3)
yap(-7 // -3, -7 % -3)
yap(1 < 1.5, 1.5 > 1, -1 > -1.5, -1.5 < -1)
yap(nocap == 1, cap == 0)
''', 'False\nTrue\nFalse\nTrue\nTrue\n9007199254740993 1\n-3 2 -3 -2\n2 -1\nTrue True True True\nTrue True\n')

    def test_nonfinite_comparisons(self):
        self.parity('''let n be drip("nan")
yap(n == 1, n < 1, n <= 1, 1 >= n)
yap(drip("inf") > 9223372036854775807)''', 'False False False False\nTrue\n')

    def test_int64_boundary(self):
        result = self.run_code('''let low be -9223372036854775807 - 1
yap(low % -1)
f_around:
    yap(low // -1)
find_out BadVibe:
    yap("overflow caught")''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '0\noverflow caught\n')

    def test_exact_integer_powers(self):
        self.parity('''yap(3 ** 34)
yap((-2) ** 63)
yap(0 ** 0, 0 ** 100, 1 ** 9223372036854775807)
yap((-1) ** 9223372036854775807)
yap(2 ** -2)''', '16677181699666569\n-9223372036854775808\n1 0 1\n-1\n0.25\n')

    def test_overflows_are_catchable(self):
        expressions = ['9223372036854775807 + 1', '-9223372036854775807 - 2',
                       '9223372036854775807 * 2', '(-9223372036854775807 - 1) * -1',
                       '2 ** 63', '-(-9223372036854775807 - 1)',
                       'positive(-9223372036854775807 - 1)', 'num(drip("inf"))',
                       'num(drip("nan"))']
        for expression in expressions:
            with self.subTest(expression=expression):
                result = self.run_code('f_around:\n    yap(' + expression + ')\nfind_out BadVibe:\n    yap("caught")')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, 'caught\n')

    def test_generated_helper_names_cannot_be_shadowed(self):
        self.parity('''let _gzim_yap be 1
let _gzim__ranked be 2
let _gzim___builtins be 3
let _GzimLuck be 4
cook show(_gzim_Luck):
    yap(ranked([3, 1, 2]))
show(5)
pull up luck
luck.manifest(42)
let first be luck.random()
luck.manifest(42)
yap(first == luck.random())''', '[1, 2, 3]\nTrue\n')

    def test_sleep_and_monotonic(self):
        started = time.monotonic()
        result = self.run_code('''pull up clock
let before be clock.monotonic()
clock.sleep(0.03)
yap(clock.monotonic() - before >= 0.025)
f_around:
    clock.sleep(-1)
find_out BadVibe:
    yap("negative caught")''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'True\nnegative caught\n')
        self.assertGreaterEqual(time.monotonic() - started, 0.025)
        self.parity('''pull up timing
pull up clock
on timing cook main():
    let before be clock.monotonic()
    wait up timing.sleep(0.01)
    yap(clock.monotonic() - before >= 0.005)
timing.run(main())''', 'True\n')

    def test_new_standard_library_utilities(self):
        self.parity('''pull up math
pull up luck
yap(math.isfinite(9223372036854775807), math.isfinite(drip("inf")))
yap(math.isnan(drip("nan")), math.isinf(drip("-inf")))
let values be [1, 2, 3, 4, 5]
luck.manifest(42)
luck.shuffle(values)
yap(ranked(values))
let before be stack(values)
let selected be luck.sample(values, 3)
yap(how many(selected), how many(squad(selected)), values == before)
yap(luck.sample(values, 0))
f_around:
    luck.sample(values, 6)
find_out BadVibe:
    yap("count caught")''', 'True False\nTrue True\n[1, 2, 3, 4, 5]\n3 3 True\n[]\ncount caught\n')

    def test_file_readline_preserves_newline_and_handles_eof(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'lines.txt'
            path.write_text('first\nlast', encoding='utf-8')
            self.parity(f'''roll with unlock({str(path)!r}) as file:
    yap(file.readline() == "first\\n")
    yap(file.readline() == "last")
    yap(file.readline() == "")''', 'True\nTrue\nTrue\n')

    def test_file_readline_normalizes_windows_and_legacy_newlines(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'lines.txt'
            path.write_bytes(b'first\r\nsecond\rlast')
            self.parity(f'''roll with unlock({str(path)!r}) as file:
    yap(file.readline() == "first\\n")
    yap(file.readline() == "second\\n")
    yap(file.read() == "last")
    yap(file.readline() == "")''', 'True\nTrue\nTrue\nTrue\n')

    def test_call_stack_preserves_imported_function_location(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'helper.gzim').write_text('cook fail():\n    send it 1 / 0\n')
            main = root / 'main.gzim'
            main.write_text('pull up helper\ncook outer():\n    helper.fail()\nouter()\n')
            result = subprocess.run([GZIM, str(main)], capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 1)
            self.assertIn('Call stack (outermost first):', result.stderr)
            self.assertIn('helper.gzim:2:', result.stderr)
            self.assertIn('in outer', result.stderr)
            self.assertIn('in fail', result.stderr)
            self.assertLess(result.stderr.index('in outer'), result.stderr.index('in fail'))

    def test_set_equality_and_distinct_large_values(self):
        self.parity('''yap({1, 2} == {2, 1})
yap({1, 2} == {1, 3})
yap([1, 2] == [2, 1])
yap(call up how many({9007199254740992, 9007199254740993}) yo)
''', 'True\nFalse\nFalse\n2\n')

    def test_finally_on_unhandled_and_handler_errors(self):
        for body in ['throw shade BadVibe("first")', 'throw shade WrongType("first")\n    find_out WrongType:\n        throw shade BadVibe("second")']:
            code = 'f_around:\n    f_around:\n        ' + body + '\n    no_matter_what:\n        yap("cleanup")\nfind_out BadVibe:\n    yap("caught")'
            self.parity(code, 'cleanup\ncaught\n')

    def test_finally_overrides_return_and_exception(self):
        self.parity('''cook answer():
    f_around:
        throw shade BadVibe("oops")
    no_matter_what:
        send it 42
cook other():
    f_around:
        send it 1
    no_matter_what:
        send it 2
yap(answer(), other())
''', '42 2\n')

    def test_nested_handlers_restore_active_exception(self):
        self.parity('''f_around:
    f_around:
        throw shade BadVibe("outer")
    find_out BadVibe:
        f_around:
            throw shade WrongType("inner")
        find_out WrongType:
            yap("inner caught")
        throw shade
find_out BadVibe:
    yap("outer caught")
''', 'inner caught\nouter caught\n')

    def test_finally_on_else_error_and_loop_control(self):
        self.parity('f_around:\n    f_around:\n        yap("body")\n    find_out BadVibe:\n        deadass\n    otherwise:\n        throw shade BadVibe("else")\n    no_matter_what:\n        yap("cleanup")\nfind_out BadVibe:\n    yap("caught")\nfor real i up in vibes(2):\n    f_around:\n        next\n    no_matter_what:\n        yap(i)\nf_around:\n    f_around:\n        throw shade BadVibe("first")\n    no_matter_what:\n        throw shade WrongType("replacement")\nfind_out WrongType:\n    yap("replacement caught")\n', 'body\ncleanup\ncaught\n0\n1\nreplacement caught\n')

    def test_ancestor_keywords(self):
        self.parity('clique Base:\n    cook new(fam, value):\n        fam.value be value\nclique Child(Base):\n    cook new(fam, value):\n        call up ancestor.new(fam, value=value) yo\nlet c be Child(value=7)\nyap(c.value)\n', '7\n')

    def test_slang_options_aliases_unpacking_and_seed(self):
        self.parity('''yap("a", "b", glue="/", micdrop="!")
yap()
let say be yap
call up say("x", "y", **{"glue": "-", "micdrop": "?"}) yo
yap()
let scores be [3, 1, 2]
yap(call up ranked(scores, uno_reverse=nocap) yo)
yap(scores)
let sortit be ranked
yap(call up sortit(scores, **{"uno_reverse": nocap}) yo)
pull up luck as rng
call up rng.manifest(42) yo
let first be [rng.random(), rng.randint(1, 100), rng.choice([1, 2, 3])]
call up rng.manifest(42) yo
yap(first == [rng.random(), rng.randint(1, 100), rng.choice([1, 2, 3])])
outta luck pull up manifest as reset
call up reset(42) yo
yap(first == [rng.random(), rng.randint(1, 100), rng.choice([1, 2, 3])])
''', 'a/b!\nx-y?\n[3, 2, 1]\n[3, 1, 2]\n[3, 2, 1]\nTrue\nTrue\n')

    def test_export_helpers_allow_builtin_shadowing(self):
        self.parity('let str be 1\nlet bool be 2\nlet int be 3\nlet isinstance be 4\nlet getattr be 5\nyap("ok")\nyap(ranked([2, 1]))\npull up luck\nluck.manifest(0)', 'ok\n[1, 2]\n')

    def test_invalid_keywords_and_types(self):
        for code, message in [
            ('yap("a", end="!")', 'unexpected argument'),
            ('yap("a", glue=1)', 'expects text'),
            ('ranked([1], uno_reverse=1)', 'expects nocap or cap'),
            ('num("1", surprise=1)', 'unexpected argument'),
            ('call up yap("a", **{"glue": "-"}, glue="/") yo', 'multiple values'),
            ('pull up luck\nluck.manifest(1.5)', 'integer seed'),
            ('clique Empty:\n    deadass\nEmpty(x=1)', 'takes no arguments'),
        ]:
            with self.subTest(code=code):
                result = self.run_code(code)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)

    def test_comparison_chain_diagnostic(self):
        for code in ['yap(3 < 2 < 1)', 'yap(1 == 1 == 1)', 'yap(1 up in [1] == nocap)']:
            result = self.run_code(code)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("split comparisons with 'both'", result.stderr)
        self.parity('yap((3 < 2) < 1)\nyap(3 < 2 both 2 < 1)', 'True\nFalse\n')


if __name__ == '__main__':
    unittest.main()
