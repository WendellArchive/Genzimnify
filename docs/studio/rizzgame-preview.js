/* Browser canvas backend for the rizzgame subset used by Studio. */
class RizzgamePreview {
  constructor(canvas, stage, state) {
    this.canvas = canvas;
    this.stage = stage;
    this.state = state;
    this.surfaces = new Map([[0, canvas]]);
    this.nextSurface = 1;
    this.events = [];
    this.keys = new Set();
    this.buttons = new Set();
    this.mouse = [0, 0];
    this.stopped = false;
    this.camera = null;
    canvas.addEventListener("keydown", (event) => {
      const key = this.keyCode(event);
      if (key) { event.preventDefault(); this.keys.add(key); this.events.push({ type: 768, key }); }
    });
    canvas.addEventListener("keyup", (event) => {
      const key = this.keyCode(event);
      if (key) { event.preventDefault(); this.keys.delete(key); this.events.push({ type: 769, key }); }
    });
    canvas.addEventListener("blur", () => this.keys.clear());
    canvas.addEventListener("pointermove", (event) => {
      const next = this.position(event);
      this.events.push({ type: 1024, pos: next, rel: [next[0] - this.mouse[0], next[1] - this.mouse[1]] });
      this.mouse = next;
    });
    canvas.addEventListener("pointerdown", (event) => {
      canvas.focus();
      this.buttons.add(event.button + 1);
      this.events.push({ type: 1025, pos: this.position(event), button: event.button + 1 });
    });
    canvas.addEventListener("pointerup", (event) => {
      this.buttons.delete(event.button + 1);
      this.events.push({ type: 1026, pos: this.position(event), button: event.button + 1 });
    });
  }
  keyCode(event) {
    const special = { Space: 32, Escape: 256, Enter: 257, Tab: 258, Backspace: 259,
      ArrowRight: 262, ArrowLeft: 263, ArrowDown: 264, ArrowUp: 265 };
    return special[event.code] || (/^Key[A-Z]$/.test(event.code) ? event.code.charCodeAt(3) : 0);
  }
  position(event) {
    const bounds = this.canvas.getBoundingClientRect();
    return [Math.round((event.clientX - bounds.left) * this.canvas.width / bounds.width),
      Math.round((event.clientY - bounds.top) * this.canvas.height / bounds.height)];
  }
  reset() {
    this.stopped = false;
    this.camera = null;
    this.events = [];
    this.keys.clear();
    this.buttons.clear();
    this.surfaces = new Map([[0, this.canvas]]);
    this.nextSurface = 1;
    this.stage.classList.remove("has-game");
    this.state.textContent = "Ready";
  }
  stop() { this.stopped = true; this.state.textContent = "Stopped"; }
  createSurface(width, height) {
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.floor(width));
    canvas.height = Math.max(1, Math.floor(height));
    const id = this.nextSurface++;
    this.surfaces.set(id, canvas);
    return id;
  }
  pollEvents() { const events = this.events.splice(0); return JSON.stringify(events); }
  pressed() { return JSON.stringify([...this.keys]); }
  mouseState() { return JSON.stringify({ pos: this.mouse, buttons: [...this.buttons] }); }
  color(value) {
    if (typeof value === "string") return value;
    const [r, g, b, a = 255] = value;
    return `rgba(${r},${g},${b},${Math.max(0, Math.min(1, a / 255))})`;
  }
  command(json) {
    const cmd = JSON.parse(json);
    if (cmd.op === "mode") {
      this.canvas.width = Math.max(1, Math.floor(cmd.width));
      this.canvas.height = Math.max(1, Math.floor(cmd.height));
      this.stage.classList.add("has-game");
      this.state.textContent = `${this.canvas.width} × ${this.canvas.height}`;
      return;
    }
    if (cmd.op === "caption") { this.canvas.setAttribute("aria-label", cmd.title); return; }
    if (cmd.op === "unload") { if (cmd.id !== 0) this.surfaces.delete(cmd.id); return; }
    if (cmd.op === "camera_begin") { this.camera = cmd; return; }
    if (cmd.op === "camera_end") { this.camera = null; return; }
    const target = this.surfaces.get(cmd.id);
    if (!target) throw new Error("rizzgame surface is unavailable");
    const ctx = target.getContext("2d");
    const camera = this.camera && cmd.op !== "fill";
    if (camera) {
      ctx.save();
      ctx.rotate((this.camera.rotation || 0) * Math.PI / 180);
      ctx.scale(this.camera.zoom || 1, this.camera.zoom || 1);
      ctx.translate(-this.camera.x, -this.camera.y);
    }
    if (cmd.op === "fill") {
      ctx.save(); ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.fillStyle = this.color(cmd.color); ctx.fillRect(0, 0, target.width, target.height); ctx.restore();
    } else if (cmd.op === "rect") {
      const [x, y, w, h] = cmd.rect;
      ctx.beginPath(); ctx.rect(x, y, w, h);
      if (cmd.width > 0) { ctx.strokeStyle = this.color(cmd.color); ctx.lineWidth = cmd.width; ctx.stroke(); }
      else { ctx.fillStyle = this.color(cmd.color); ctx.fill(); }
    } else if (cmd.op === "circle") {
      ctx.beginPath(); ctx.arc(cmd.center[0], cmd.center[1], Math.max(0, cmd.radius), 0, Math.PI * 2);
      if (cmd.width > 0) { ctx.strokeStyle = this.color(cmd.color); ctx.lineWidth = cmd.width; ctx.stroke(); }
      else { ctx.fillStyle = this.color(cmd.color); ctx.fill(); }
    } else if (cmd.op === "line") {
      ctx.beginPath(); ctx.moveTo(...cmd.start); ctx.lineTo(...cmd.end);
      ctx.strokeStyle = this.color(cmd.color); ctx.lineWidth = cmd.width || 1; ctx.stroke();
    } else if (cmd.op === "text") {
      ctx.fillStyle = this.color(cmd.color); ctx.font = `${Math.max(1, cmd.size)}px sans-serif`;
      ctx.textBaseline = "top"; ctx.fillText(cmd.text, ...cmd.position);
    } else if (cmd.op === "blit") {
      const source = this.surfaces.get(cmd.source);
      if (!source) throw new Error("rizzgame source surface is unavailable");
      ctx.save(); ctx.translate(...cmd.position); ctx.rotate((cmd.rotation || 0) * Math.PI / 180);
      ctx.scale(cmd.scale || 1, cmd.scale || 1); ctx.drawImage(source, 0, 0); ctx.restore();
    } else if (cmd.op === "sprite") {
      const source = this.surfaces.get(cmd.source);
      if (!source) throw new Error("rizzgame sprite surface is unavailable");
      ctx.save(); ctx.translate(...cmd.position); ctx.rotate((cmd.rotation || 0) * Math.PI / 180);
      ctx.scale(cmd.scale || 1, cmd.scale || 1);
      ctx.drawImage(source, ...cmd.frame, 0, 0, cmd.frame[2], cmd.frame[3]); ctx.restore();
    }
    if (camera) ctx.restore();
  }
}
window.RizzgamePreview = RizzgamePreview;
