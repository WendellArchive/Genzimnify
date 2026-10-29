const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");
const timers = new Map();
let nextTimer = 0;
const context = vm.createContext({
  setTimeout(fn, ms) { const id = ++nextTimer; timers.set(id, { fn, ms }); return id; },
  clearTimeout(id) { timers.delete(id); },
});
vm.runInContext(fs.readFileSync(path.join(__dirname, "../studio/runner.js"), "utf8") + "\nglobalThis.Runner = StudioRunner;", context);

(async () => {
  const workers = [], output = [], statuses = [];
  const runner = new context.Runner((...values) => output.push(values), (text) => statuses.push(text), () => {
    const worker = { terminated: false, postMessage(data) { this.last = data; }, terminate() { this.terminated = true; } };
    workers.push(worker);
    return worker;
  });
  const first = runner.run("print('hello')", { input: "one\ntwo", filename: "sample.gzim", timeout: 30 });
  const worker = workers[0], id = worker.last.id;
  assert.equal(worker.last.input, "one\ntwo");
  assert.equal(worker.last.filename, "sample.gzim");
  await assert.rejects(runner.run("another"), /already running/);
  worker.onmessage({ data: { id, type: "running" } });
  assert.equal([...timers.values()][0].ms, 30);
  worker.onmessage({ data: { id: id - 1, type: "output", text: "stale" } });
  worker.onmessage({ data: { id, type: "output", text: "hello\n" } });
  worker.onmessage({ data: { id, type: "done" } });
  assert.equal((await first).stopped, false);
  assert.deepEqual(output, [["hello\n", ""]]);
  assert.equal(timers.size, 0);

  const stopped = runner.run("while True: pass");
  runner.stop();
  assert.equal((await stopped).stopped, true);
  assert.equal(worker.terminated, true);
  const timed = runner.run("while True: pass", { timeout: 100 });
  workers[1].onmessage({ data: { id: workers[1].last.id, type: "running" } });
  const rejected = assert.rejects(timed, /timed out after 0.1 seconds/);
  [...timers.values()][0].fn();
  await rejected;
  assert.equal(workers[1].terminated, true);
  assert.equal(timers.size, 0);

  const recovery = runner.run("print('recovered')", { timeout: 0 });
  const recoveredWorker = workers[2];
  recoveredWorker.onmessage({ data: { id: recoveredWorker.last.id, type: "running" } });
  assert.equal(timers.size, 0);
  recoveredWorker.onmessage({ data: { id: recoveredWorker.last.id, type: "done" } });
  await recovery;
  assert.ok(statuses.includes("Vibing..."));
  console.log("Studio runner stop, timeout, input, stale messages, and recovery passed");
})().catch((error) => { console.error(error); process.exitCode = 1; });
