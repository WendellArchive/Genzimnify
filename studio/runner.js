/* Background execution for ordinary Studio programs. Games use the Canvas adapter. */
class StudioRunner {
  constructor(onOutput, onStatus, workerFactory = () => new Worker("runtime-worker.js")) {
    this.onOutput = onOutput;
    this.onStatus = onStatus;
    this.workerFactory = workerFactory;
    this.worker = null;
    this.pending = null;
    this.nextId = 0;
  }

  run(code, { input = "", filename = "main.gzim", timeout = 10000 } = {}) {
    if (this.pending) return Promise.reject(new Error("A program is already running"));
    return new Promise((resolve, reject) => {
      const id = ++this.nextId;
      this.pending = { id, resolve, reject, timeout, timer: null };
      try {
        if (!this.worker) {
          this.worker = this.workerFactory();
          this.worker.onmessage = ({ data }) => this.receive(data);
          this.worker.onerror = () => this.finish(new Error("Could not start the background runtime. Serve Studio over HTTP and try again."), true);
        }
        this.onStatus("Loading runtime...");
        // Loading has its own deadline; program time starts after the runtime is ready.
        this.pending.timer = setTimeout(() => this.finish(new Error("Runtime loading timed out. Check your connection and run again."), true), 120000);
        this.worker.postMessage({ id, code, input, filename });
      } catch (error) { this.finish(error, true); }
    });
  }

  receive(data) {
    const pending = this.pending;
    if (!pending || data.id !== pending.id) return;
    if (data.type === "running") {
      clearTimeout(pending.timer);
      this.onStatus("Vibing...");
      pending.timer = pending.timeout > 0 ? setTimeout(() => {
        this.finish(new Error("Program timed out after " + pending.timeout / 1000 + " seconds."), true);
      }, pending.timeout) : null;
    } else if (data.type === "output") {
      this.onOutput(data.text, data.stderr ? "cap" : "");
    } else if (data.type === "error") {
      this.finish(new Error(data.message), true);
    } else if (data.type === "done") {
      this.finish();
    }
  }

  finish(error = null, discard = false, stopped = false) {
    const pending = this.pending;
    if (!pending) return;
    clearTimeout(pending.timer);
    this.pending = null;
    if (discard && this.worker) {
      this.worker.terminate();
      this.worker = null;
    }
    if (error) pending.reject(error);
    else pending.resolve({ stopped });
  }

  stop() { this.finish(null, true, true); }
}
