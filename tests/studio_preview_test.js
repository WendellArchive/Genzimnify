const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '..');

const compiler = vm.createContext({ console });
vm.runInContext(fs.readFileSync(path.join(root, 'studio/transpiler.js'), 'utf8'), compiler);
const app = fs.readFileSync(path.join(root, 'studio/app.js'), 'utf8');
vm.runInContext(app.slice(0, app.indexOf('const REFERENCE')) + '\nglobalThis.sample = EXAMPLES["rizzgame-starter.gzim"];', compiler);
const compiled = JSON.parse(vm.runInContext('compileGzim(sample)', compiler));
assert.equal(compiled.ok, true, compiled.error);
assert.match(compiled.code, /Genzimnify 2\.0\.6/);
assert.match(compiled.code, /rg\.display\.pull_up/);
assert.match(compiled.code, /rg\.display\.show_off/);

// Exercise the shipped browser compiler, then execute its Python output.
compiler.slangSample = `yap("a", "b", glue="/", micdrop="!")
yap()
yap(ranked([1, 3, 2], uno_reverse=nocap))
pull up luck
luck.manifest(42)
let first be luck.random()
luck.manifest(42)
yap(first == luck.random())`;
const slang = JSON.parse(vm.runInContext('compileGzim(slangSample)', compiler));
assert.equal(slang.ok, true, slang.error);
const execution = require('node:child_process').spawnSync('python3', ['-c', slang.code], { encoding: 'utf8' });
assert.equal(execution.status, 0, execution.stderr);
assert.equal(execution.stdout, 'a/b!\n[3, 2, 1]\nTrue\n');
compiler.chainSample = 'yap(3 < 2 < 1)';
const chain = JSON.parse(vm.runInContext('compileGzim(chainSample)', compiler));
assert.equal(chain.ok, false);
assert.match(chain.error, /split comparisons with 'both'/);

const operations = [];
function makeCanvas() {
  const context = Object.fromEntries(['save', 'restore', 'setTransform', 'fillRect', 'beginPath',
    'rect', 'stroke', 'fill', 'arc', 'moveTo', 'lineTo', 'fillText', 'translate', 'rotate',
    'scale', 'drawImage'].map((name) => [name, (...args) => operations.push([name, ...args])]));
  return { width: 320, height: 180, addEventListener() {}, setAttribute() {},
    getContext: () => context, getBoundingClientRect: () => ({ left: 0, top: 0, width: 160, height: 90 }) };
}
const window = {};
const stage = { classList: { add() {}, remove() {} } };
const context = vm.createContext({ window, document: { createElement: makeCanvas } });
vm.runInContext(fs.readFileSync(path.join(root, 'studio/rizzgame-preview.js'), 'utf8'), context);
const preview = new window.RizzgamePreview(makeCanvas(), stage, { textContent: '' });
assert.equal(preview.keyCode({ code: 'KeyA' }), 65);
assert.equal(preview.keyCode({ code: 'ArrowLeft' }), 263);
assert.deepEqual(Array.from(preview.position({ clientX: 80, clientY: 45 })), [160, 90]);
preview.command(JSON.stringify({ op: 'mode', width: 640, height: 360 }));
preview.command(JSON.stringify({ op: 'fill', id: 0, color: [10, 20, 30] }));
preview.command(JSON.stringify({ op: 'rect', id: 0, color: [255, 0, 0], rect: [1, 2, 3, 4], width: 0 }));
assert.equal(preview.canvas.width, 640);
assert.ok(operations.some(([name]) => name === 'fillRect'));
assert.ok(operations.some(([name]) => name === 'rect'));
console.log('Studio rizzgame compiler and Canvas bridge passed');
