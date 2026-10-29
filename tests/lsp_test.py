import json, os, subprocess
from pathlib import Path

server = os.environ.get(
    'GZIM_LSP_BIN',
    str(Path(__file__).resolve().parents[1] / 'build' / 'gzim-lsp'),
)
expected_version = (Path(__file__).resolve().parents[1] / "src/genzimnify/version.nim").read_text().split('"')[1]
version_result = subprocess.run([server, '--version'], capture_output=True, text=True, timeout=5)
assert version_result.returncode == 0
assert version_result.stdout.strip() == 'gzim-lsp ' + expected_version
help_result = subprocess.run([server, '--help'], capture_output=True, text=True, timeout=5)
assert help_result.returncode == 0 and 'usage:' in help_result.stdout
assert subprocess.run([server, '--invalid'], capture_output=True, timeout=5).returncode == 1
p = subprocess.Popen([str(server)],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE)

def send(msg):
    body = json.dumps(msg)
    p.stdin.write(f"Content-Length: {len(body)}\r\n\r\n{body}".encode())
    p.stdin.flush()

def recv():
    headers = {}
    while True:
        line = p.stdout.readline().decode().strip()
        if not line:
            break
        k, v = line.split(':', 1)
        headers[k.lower()] = v.strip()
    n = int(headers['content-length'])
    return json.loads(p.stdout.read(n).decode())

send({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"rootUri":None}})
init = recv()["result"]
assert init["serverInfo"]["version"] == expected_version
print("INIT capabilities:", json.dumps(init["capabilities"])[:120])
send({"jsonrpc":"2.0","method":"initialized","params":{}})

text = '''lock PI be 3
PI be 4
cook add(a, b):
    send it a + b

yap(call up add(2, 3) yo)
'''
send({"jsonrpc":"2.0","method":"textDocument/didOpen","params":{
    "textDocument":{"uri":"file:///x/v.gzim","languageId":"genzimnify","version":1,"text":text}}})
d = recv()
print("DIAGS:", json.dumps(d["params"]["diagnostics"]))
# hover on 'add' in `call up add(2, 3)` (line 5, char 13)
send({"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///x/v.gzim"},"position":{"line":5,"character":13}}})
print("HOVER:", recv()["result"]["contents"]["value"])
# definition of PI at line 1 char 1
send({"jsonrpc":"2.0","id":3,"method":"textDocument/definition","params":{"textDocument":{"uri":"file:///x/v.gzim"},"position":{"line":1,"character":1}}})
print("DEF:", recv()["result"])
# completion
send({"jsonrpc":"2.0","id":4,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///x/v.gzim"},"position":{"line":1,"character":1}}})
r = recv()["result"]
print("COMPLETION items:", len(r["items"]), "sample:", [i["label"] for i in r["items"][:5]], "+", [i["label"] for i in r["items"][-3:]])
# document symbols
send({"jsonrpc":"2.0","id":5,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":"file:///x/v.gzim"}}})
print("SYMBOLS:", [s["name"] for s in recv()["result"]])
# hover keyword 'lock' (line 0 char 1)
send({"jsonrpc":"2.0","id":6,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///x/v.gzim"},"position":{"line":0,"character":1}}})
print("HOVER kw:", recv()["result"]["contents"]["value"])
# Partially typed strings must report errors and leave the server alive.
send({"jsonrpc":"2.0","method":"textDocument/didChange","params":{
    "textDocument":{"uri":"file:///x/v.gzim","version":2},
    "contentChanges":[{"text":'let x be "'}]}})
assert recv()["params"]["diagnostics"], 'unclosed string should produce a diagnostic'
send({"jsonrpc":"2.0","method":"textDocument/didChange","params":{
    "textDocument":{"uri":"file:///x/v.gzim","version":3},
    "contentChanges":[{"text":'let x be "fixed"'}]}})
assert recv()["params"]["diagnostics"] == []
send({"jsonrpc":"2.0","id":8,"method":"textDocument/completion","params":{
    "textDocument":{"uri":"file:///x/v.gzim"},"position":{"line":0,"character":1}}})
assert any(item['label'] == 'x' for item in recv()['result']['items'])
send({"jsonrpc":"2.0","method":"textDocument/didClose","params":{
    "textDocument":{"uri":"file:///x/v.gzim"}}})
assert recv()['params']['diagnostics'] == []
send({"jsonrpc":"2.0","id":7,"method":"shutdown"})
recv()
send({"jsonrpc":"2.0","method":"exit"})
p.wait(timeout=5)
print("exit code:", p.returncode)
