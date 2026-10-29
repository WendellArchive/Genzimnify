const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");
const messages = [];
let stdout, stderr, stdin, executions = 0, destroyed = 0;
const runtime = {
  setStdout(value) { stdout = value.batched; },
  setStderr(value) { stderr = value.batched; },
  setStdin(value) { stdin = value.stdin; },
  runPython(code) { if (code.startsWith("dict(")) return { destroy() { destroyed++; } }; },
  async runPythonAsync(code, options) {
    executions++;
    assert.equal(options.filename, "sample.gzim");
    if (code === "input") {
      assert.equal(stdin(), "one"); assert.equal(stdin(), "two"); assert.equal(stdin(), null);
      stdout("accepted"); stderr("warning");
    } else if (code === "flood") {
      for (let i = 0; i < 200; i++) stdout("x".repeat(1000));
    } else if (code === "failure") {
      throw new Error("runtime error");
    }
  },
};
const self = { postMessage(data) { messages.push(data); } };
const context = vm.createContext({ self, importScripts() {}, loadPyodide: async () => runtime, setTimeout, clearTimeout });
vm.runInContext(fs.readFileSync(path.join(__dirname, "../studio/runtime-worker.js"), "utf8"), context);
(async () => {
  await self.onmessage({ data: { id: 1, code: "input", input: "one\r\ntwo\n", filename: "sample.gzim" } });
  assert.deepEqual(messages.map((m) => m.type), ["running", "output", "output", "done"]);
  assert.equal(messages[1].text, "accepted\n");
  assert.equal(messages[2].stderr, true);
  messages.length = 0;
  await self.onmessage({ data: { id: 2, code: "flood", input: "", filename: "sample.gzim" } });
  assert.equal(messages.at(-1).type, "error");
  assert.match(messages.at(-1).message, /output limit/);
  assert.equal(messages.filter((m) => m.type === "output").reduce((n, m) => n + m.text.length, 0), 100000);
  assert.ok(messages.length < 30, "output should be batched");
  messages.length = 0;
  await self.onmessage({ data: { id: 3, code: "failure", input: "", filename: "sample.gzim" } });
  assert.equal(messages.at(-1).message, "runtime error");
  assert.equal(executions, 3);
  assert.equal(destroyed, 3);
  console.log("Studio worker input, stream batching, output limit, and scope cleanup passed");
})().catch((error) => { console.error(error); process.exitCode = 1; });
