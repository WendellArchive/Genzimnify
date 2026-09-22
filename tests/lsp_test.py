import json, subprocess, sys

p = subprocess.Popen(['/home/mattin/Documents/Projects/Genzimnify/build/gzim-lsp'],
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
print("INIT capabilities:", json.dumps(recv()["result"]["capabilities"])[:120])
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
send({"jsonrpc":"2.0","id":7,"method":"shutdown"})
recv()
send({"jsonrpc":"2.0","method":"exit"})
p.wait(timeout=5)
print("exit code:", p.returncode)
