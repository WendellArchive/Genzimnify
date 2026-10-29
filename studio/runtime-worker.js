/* Each worker owns its Python runtime; termination also stops infinite loops. */
importScripts("https://cdn.jsdelivr.net/pyodide/v0.26.4/full/pyodide.js");
let runtimePromise = null;
let busy = false;
const OUTPUT_LIMIT = 100000;

self.onmessage = async ({ data }) => {
  if (busy) return;
  busy = true;
  const { id, code, filename, input } = data;
  const send = (type, values = {}) => self.postMessage({ id, type, ...values });
  let scope = null;
  let outputSize = 0;
  let outputLimited = false;
  let chunks = [];
  let chunkSize = 0;
  let flushTimer = null;
  // Batch frequent output to avoid flooding the page's message queue.
  const flush = () => {
    clearTimeout(flushTimer);
    flushTimer = null;
    for (const chunk of chunks) send("output", chunk);
    chunks = [];
    chunkSize = 0;
  };
  const stream = (text, stderr = false) => {
    if (outputLimited) throw new Error("Console output limit reached (100,000 characters).");
    const remaining = OUTPUT_LIMIT - outputSize;
    const truncated = text.length > remaining;
    text = text.slice(0, remaining);
    outputSize += text.length;
    const previous = chunks[chunks.length - 1];
    if (previous && previous.stderr === stderr) previous.text += text;
    else chunks.push({ text, stderr });
    chunkSize += text.length;
    if (chunkSize >= 4096) flush();
    else if (!flushTimer) flushTimer = setTimeout(flush, 20);
    if (truncated) {
      outputLimited = true;
      flush();
      throw new Error("Console output limit reached (100,000 characters).");
    }
  };
  try {
    runtimePromise ||= loadPyodide({ indexURL: "https://cdn.jsdelivr.net/pyodide/v0.26.4/full/" });
    const runtime = await runtimePromise;
    const inputs = input === "" ? [] : input.replace(/\r\n?/g, "\n").split("\n");
    if (inputs.length > 1 && inputs[inputs.length - 1] === "") inputs.pop();
    let inputIndex = 0;
    runtime.setStdin({ stdin: () => inputIndex < inputs.length ? inputs[inputIndex++] : null });
    runtime.setStdout({ batched: (text) => stream(text + "\n") });
    runtime.setStderr({ batched: (text) => stream(text + "\n", true) });
    scope = runtime.runPython("dict(__name__='__main__', __builtins__=__builtins__, args=[])");
    send("running");
    const value = await runtime.runPythonAsync(code, { globals: scope, filename });
    if (value && typeof value.destroy === "function") value.destroy();
    runtime.runPython("import sys; sys.stdout.flush(); sys.stderr.flush()");
    flush();
    if (outputLimited) send("error", { message: "Console output limit reached (100,000 characters)." });
    else send("done");
  } catch (error) {
    flush();
    send("error", { message: outputLimited ? "Console output limit reached (100,000 characters)." : String(error.message || error) });
  } finally {
    if (scope) scope.destroy();
    busy = false;
  }
};
