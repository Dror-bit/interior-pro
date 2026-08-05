// --- minimal DOM / Canvas stub -------------------------------------------
const listeners = {};
function mkEl(id) {
  return {
    id, value: '', innerHTML: '', textContent: '', className: '',
    style: {}, dataset: {}, checked: false, width: 900, height: 700, clientWidth: 900, clientHeight: 700, offsetWidth: 900, offsetHeight: 700,
    children: [], options: [],
    appendChild(c){ this.children.push(c); },
    setAttribute(){}, removeAttribute(){}, focus(){}, blur(){},
    getContext(){ return ctxStub; },
    getBoundingClientRect(){ return {left:0, top:0, width:900, height:700}; },
    addEventListener(t, f){ const m = listeners[id] = listeners[id] || {}; (m[t] = m[t] || []).push(f); },
    setPointerCapture(){}, releasePointerCapture(){},
    querySelectorAll(){ return []; },
  };
}
global.__draw = [];
const ctxStub = new Proxy({}, {
  get(_, k) {
    if (k === 'measureText') return () => ({ width: 40 });
    if (k === 'fillText') return (t, x, y) => { global.__draw.push({ t, x, y, rot: global.__rot, tx: global.__tx, ty: global.__ty }); };
    if (k === 'rotate') return (a) => { global.__rot = a; };
    if (k === 'stroke') return () => { global.__lines = (global.__lines || 0) + 1; };
    if (k === 'save') return () => { global.__rotStack = global.__rotStack || []; global.__rotStack.push(global.__rot); };
    if (k === 'restore') return () => { global.__rot = (global.__rotStack || []).pop(); };
    if (k === 'translate') return (x, y) => { global.__tx = x; global.__ty = y; };
    if (k === 'canvas') return { width: 900, height: 700 };
    if (typeof k === 'string' && ['fillStyle','strokeStyle','lineWidth','font','textAlign','globalAlpha','lineJoin','lineCap'].includes(k)) return '';
    return () => {};
  },
  set() { return true; }
});
const els = {};
global.document = {
  getElementById(id) { return els[id] || (els[id] = mkEl(id)); },
  addEventListener(t, f) { const m = listeners.__doc = listeners.__doc || {}; (m[t] = m[t] || []).push(f); },
  createElement(t) { return mkEl('new-' + t); },
  querySelectorAll() { return []; },
  body: mkEl('body'),
};
global.window = {
  addEventListener(t, f) { const m = listeners.__win = listeners.__win || {}; (m[t] = m[t] || []).push(f); },
  devicePixelRatio: 1,
};
global.navigator = { userAgent: 'stub' };
global.Image = function(){
  const self = this; this.onload = null; this.width = 1000; this.height = 800;
  Object.defineProperty(this, 'src', {
    set(v){ self._src = v; if (self.onload) self.onload(); },
    get(){ return self._src; }
  });
};
global.confirm = () => true;
global.alert = () => {};
global.prompt = () => null;
global.ResizeObserver = function(){ this.observe = () => {}; };
global.requestAnimationFrame = (f) => f();
global.sketchup = new Proxy({}, {
  get(_, k) { return (...a) => { calls.push([k, ...a]); }; }
});
const calls = [];
global.__calls = calls;
global.__listeners = listeners;
global.__els = els;

global.fire = (id, type, ev) => ((listeners[id] || {})[type] || []).forEach(f => f(ev));
