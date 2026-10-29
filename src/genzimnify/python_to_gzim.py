"""Embedded, parse-only Python -> Genzimnify preview. Never executes input."""
import ast
import json
import math
import re
import sys
import tokenize
import warnings


BUILTINS = {
    "print": "yap", "input": "yap back", "len": "how many", "range": "vibes",
    "int": "num", "float": "drip", "str": "text", "bool": "truth",
    "list": "stack", "dict": "map", "set": "squad", "tuple": "crew",
    "sum": "add up", "min": "least", "max": "most", "abs": "positive",
    "sorted": "ranked", "enumerate": "index up", "zip": "link",
}
RESERVED = set("""let lock nocap cap ghost both either nah literally vibecheck or
otherwise dip next deadass cook drop yo clique new fam ancestor outta as gives sus
fr worldwide localish cancel f_around find_out no_matter_what aint up same call for
send throw yap mini on fit pull roll vibe how add round index wait glow be args
__name__ num drip text truth stack map squad crew vibes least most positive ranked
link L BadVibe WrongType OutOfPocket Ghosted SplitByZero NoPullUp CapDetected
StopTheCap unlock""".split())
OPS = {ast.Add: "+", ast.Sub: "-", ast.Mult: "*", ast.Div: "/",
       ast.FloorDiv: "//", ast.Mod: "%", ast.Pow: "**"}
CMP = {ast.Eq: "==", ast.NotEq: "!=", ast.Lt: "<", ast.LtE: "<=",
       ast.Gt: ">", ast.GtE: ">=", ast.In: "up in", ast.NotIn: "aint up in"}
METHODS = {
    "append": (1, 1), "extend": (1, 1), "insert": (2, 2), "remove": (1, 1),
    "reverse": (0, 0), "pop": (0, 1), "get": (1, 2), "keys": (0, 0),
    "values": (0, 0), "items": (0, 0), "join": (1, 1),
    "startswith": (1, 1), "endswith": (1, 1), "replace": (2, 2),
}


class Unsupported(Exception):
    def __init__(self, node, message):
        super().__init__(message)
        self.line = getattr(node, "lineno", 1)
        self.column = getattr(node, "col_offset", 0)
        self.node = type(node).__name__


def fail(node, message):
    raise Unsupported(node, message)


def identifier(name, node):
    if not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", name):
        fail(node, "non-ASCII identifiers are not supported in conversion preview")
    # Escape the prefix too, so generated names never collide with source names.
    return "_py_" + name if name in RESERVED or name.startswith("_py_") else name


class Bindings(ast.NodeVisitor):
    def __init__(self):
        self.names = set()

    def visit_Name(self, node):
        if isinstance(node.ctx, ast.Store):
            self.names.add(node.id)

    def visit_FunctionDef(self, node):
        self.names.add(node.name)

    visit_AsyncFunctionDef = visit_FunctionDef
    visit_ClassDef = visit_FunctionDef


class Converter:
    def __init__(self):
        self.scopes = []
        self.lines = []
        self.maps = []
        self.depth = 0

    def line(self, text, node):
        self.lines.append("    " * self.depth + text)
        self.maps.append(getattr(node, "lineno", 1))

    def scope(self, body, params=()):
        bindings = Bindings()
        for stmt in body:
            bindings.visit(stmt)
        self.scopes.append(bindings.names | set(params))

    def is_builtin(self, node):
        return (isinstance(node, ast.Name) and node.id in BUILTINS and
                not any(node.id in scope for scope in self.scopes))

    def name(self, node, callee=False):
        if any(node.id in scope for scope in reversed(self.scopes)):
            return identifier(node.id, node)
        if node.id in BUILTINS:
            if not callee:
                fail(node, "builtin function references are not supported; call " + node.id + " directly")
            return BUILTINS[node.id]
        if node.id == "__name__":
            return node.id
        fail(node, "unsupported or unbound name: " + node.id)

    def expr(self, node, callee=False):
        if isinstance(node, ast.Name):
            return self.name(node)
        if isinstance(node, ast.Constant):
            value = node.value
            if value is None:
                return "ghost"
            if isinstance(value, bool):
                return "nocap" if value else "cap"
            if isinstance(value, int):
                if not -(2**63) < value < 2**63:
                    fail(node, "integer outside the native signed 64-bit literal range")
                return str(value)
            if isinstance(value, float) and math.isfinite(value):
                return repr(value)
            if isinstance(value, str):
                if any((ord(c) < 32 and c not in "\n\r\t") or 0xD800 <= ord(c) <= 0xDFFF for c in value):
                    fail(node, "unsupported control character or surrogate in string")
                return json.dumps(value, ensure_ascii=False)
            fail(node, "unsupported literal: " + type(value).__name__)
        if isinstance(node, (ast.List, ast.Tuple, ast.Set)):
            values = ", ".join(self.expr(e) for e in node.elts)
            if isinstance(node, ast.List):
                return "[" + values + "]"
            if isinstance(node, ast.Set):
                return "{" + values + "}"
            return "(" + values + ("," if len(node.elts) == 1 else "") + ")"
        if isinstance(node, ast.Dict):
            if None in node.keys:
                fail(node, "dictionary unpacking is not supported in conversion preview")
            return "{" + ", ".join(self.expr(k) + ": " + self.expr(v)
                                    for k, v in zip(node.keys, node.values)) + "}"
        if isinstance(node, ast.BinOp) and type(node.op) in OPS:
            return "(" + self.expr(node.left) + " " + OPS[type(node.op)] + " " + self.expr(node.right) + ")"
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.Not, ast.USub, ast.UAdd)):
            op = {ast.Not: "aint ", ast.USub: "-", ast.UAdd: "+"}[type(node.op)]
            return "(" + op + self.expr(node.operand) + ")"
        if isinstance(node, ast.BoolOp):
            op = " both " if isinstance(node.op, ast.And) else " either "
            return "(" + op.join(self.expr(v) for v in node.values) + ")"
        if isinstance(node, ast.Compare):
            if len(node.ops) != 1:
                fail(node, "chained comparisons are not supported; use explicit comparisons with and")
            if type(node.ops[0]) not in CMP:
                fail(node, "identity comparisons are not supported in conversion preview")
            return "(" + self.expr(node.left) + " " + CMP[type(node.ops[0])] + " " + self.expr(node.comparators[0]) + ")"
        if isinstance(node, ast.Subscript):
            subscript = node.slice
            if isinstance(subscript, ast.Index):  # Python 3.8 AST wrapper
                subscript = subscript.value
            if isinstance(subscript, ast.Slice):
                fail(node, "slices are not supported in conversion preview")
            return self.expr(node.value) + "[" + self.expr(subscript) + "]"
        if isinstance(node, ast.Attribute):
            if node.attr not in METHODS:
                fail(node, "unsupported attribute in conversion preview: " + node.attr)
            if not callee:
                fail(node, "method references are not supported; call the method directly")
            return self.expr(node.value) + "." + node.attr
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Attribute):
                if node.keywords:
                    fail(node, "method keyword arguments are not supported in conversion preview")
                if node.func.attr in METHODS:
                    low, high = METHODS[node.func.attr]
                    if not low <= len(node.args) <= high:
                        fail(node, "unsupported method argument count in conversion preview: " + node.func.attr)
            if self.is_builtin(node.func):
                name = node.func.id
                if node.keywords:
                    fail(node, "builtin keyword arguments are not supported in conversion preview: " + name)
                count = len(node.args)
                low, high = {"print": (0, None), "input": (0, 1), "range": (1, 3),
                             "zip": (0, None), "enumerate": (1, 2), "dict": (0, 0),
                             "list": (0, 1), "tuple": (0, 1), "set": (0, 1),
                             "int": (0, 1), "float": (0, 1), "str": (0, 1),
                             "bool": (0, 1)}.get(name, (1, 1))
                if count < low or (high is not None and count > high):
                    fail(node, "unsupported builtin argument count in conversion preview: " + name)
                if count == 0 and name in ("list", "tuple", "dict", "int", "float", "str", "bool"):
                    return {"list": "[]", "tuple": "()", "dict": "{}", "int": "0",
                            "float": "0.0", "str": '""', "bool": "cap"}[name]
                if count == 0 and name == "set":
                    return "call up squad([]) yo"
            parts = [self.expr(a) for a in node.args]
            for kw in node.keywords:
                if kw.arg is None:
                    fail(node, "keyword unpacking is not supported in conversion preview")
                parts.append(identifier(kw.arg, node) + " be " + self.expr(kw.value))
            function = self.name(node.func, callee=True) if isinstance(node.func, ast.Name) else self.expr(node.func, callee=True)
            return "call up " + function + "(" + ", ".join(parts) + ") yo"
        fail(node, "unsupported Python expression: " + type(node).__name__)

    def block(self, body):
        self.depth += 1
        for node in body:
            self.stmt(node)
        self.depth -= 1

    def stmt(self, node):
        if isinstance(node, ast.Assign):
            if len(node.targets) != 1 or not isinstance(node.targets[0], (ast.Name, ast.Subscript)):
                fail(node, "only single-name or subscript assignment is supported in conversion preview")
            target = node.targets[0]
            prefix = "let " if isinstance(target, ast.Name) else ""
            self.line(prefix + self.expr(target) + " be " + self.expr(node.value), node)
        elif isinstance(node, ast.AugAssign):
            if not isinstance(node.target, (ast.Name, ast.Subscript)) or type(node.op) not in OPS:
                fail(node, "unsupported augmented assignment")
            self.line(self.expr(node.target) + " be" + OPS[type(node.op)] + " " + self.expr(node.value), node)
        elif isinstance(node, ast.Expr):
            self.line(self.expr(node.value), node)
        elif isinstance(node, ast.If):
            self.line("vibecheck " + self.expr(node.test) + ":", node)
            self.block(node.body)
            if node.orelse:
                self.line("otherwise:", node)
                self.block(node.orelse)
        elif isinstance(node, (ast.For, ast.While)):
            if node.orelse:
                fail(node, "loop else is not supported in conversion preview")
            if isinstance(node, ast.For):
                if not isinstance(node.target, ast.Name):
                    fail(node, "loop target must be a single name in conversion preview")
                header = "for real " + self.expr(node.target) + " up in " + self.expr(node.iter)
            else:
                header = "vibe " + self.expr(node.test)
            self.line(header + ":", node)
            self.block(node.body)
        elif isinstance(node, ast.FunctionDef):
            args = node.args
            if (node.decorator_list or node.returns or getattr(node, "type_params", []) or
                    args.posonlyargs or args.kwonlyargs or args.vararg or args.kwarg or
                    any(a.annotation for a in args.args)):
                fail(node, "decorators, annotations, and advanced function parameters are not supported in conversion preview")
            params = [identifier(a.arg, a) for a in args.args]
            for i, default in enumerate(args.defaults, len(params) - len(args.defaults)):
                params[i] += " be " + self.expr(default)
            self.line("cook " + identifier(node.name, node) + "(" + ", ".join(params) + "):", node)
            self.scope(node.body, [a.arg for a in args.args])
            self.block(node.body)
            self.scopes.pop()
        elif isinstance(node, ast.Return):
            self.line("send it" + (" " + self.expr(node.value) if node.value else ""), node)
        elif isinstance(node, (ast.Break, ast.Continue, ast.Pass)):
            self.line({ast.Break: "dip", ast.Continue: "next", ast.Pass: "deadass"}[type(node)], node)
        else:
            fail(node, "unsupported Python statement: " + type(node).__name__)

    def convert(self, tree):
        self.scope(tree.body)
        for node in tree.body:
            self.stmt(node)
        return {"code": "\n".join(self.lines) + "\n", "lines": self.maps}


HINTS = {
    "Import": "Convert code that does not import modules, or port the import manually using pull up py.<module>.",
    "ImportFrom": "Port this import manually using outta py.<module> pull up <name>.",
    "JoinedStr": "Replace the f-string with a string plus str(value), or port it manually to a glow string.",
    "ListComp": "Rewrite the comprehension as a loop with append().",
    "AnnAssign": "Remove the type annotation and use an ordinary assignment.",
    "ClassDef": "Classes require manual porting to clique in this conversion preview.",
    "AsyncFunctionDef": "Async functions require manual porting in this conversion preview.",
    "FunctionDef": "Use ordinary positional parameters without decorators or annotations.",
    "Compare": "Use separate comparisons joined by and; store expressions with side effects in a variable first.",
}


def diagnostic(path, source, line, column, message, hint):
    lines = source.splitlines()
    excerpt = lines[line - 1] if 0 < line <= len(lines) else ""
    return "{}:{}:{}: {}\n  {}\n  {}^\nhint: {}".format(
        path, line, column + 1, message, excerpt.expandtabs(4),
        " " * len(excerpt[:column].expandtabs(4)), hint)


def main():
    request = json.load(sys.stdin)
    path = request["path"]
    source = ""
    try:
        with tokenize.open(path) as source_file:
            source = source_file.read()
        tree = ast.parse(source, filename=path)
        # Also check contextual Python errors such as return/break outside a function/loop.
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            compile(tree, path, "exec")
        result = Converter().convert(tree)
        result["ok"] = True
    except SyntaxError as error:
        result = {"ok": False, "error": diagnostic(path, source, error.lineno or 1,
                  max(0, (error.offset or 1) - 1), error.msg, "Fix the Python syntax before converting.")}
    except Unsupported as error:
        lines = source.splitlines()
        excerpt = lines[error.line - 1] if 0 < error.line <= len(lines) else ""
        # Python AST columns are UTF-8 byte offsets, not display character offsets.
        column = len(excerpt.encode("utf-8")[:error.column].decode("utf-8", errors="ignore"))
        result = {"ok": False, "error": diagnostic(path, source, error.line, column,
                  str(error), HINTS.get(error.node, "Simplify this construct to the documented conversion subset, or port it manually."))}
    except (OSError, UnicodeError, ValueError, RecursionError) as error:
        result = {"ok": False, "error": path + ": " + str(error)}
    print(json.dumps(result, ensure_ascii=True))


if __name__ == "__main__":
    main()
