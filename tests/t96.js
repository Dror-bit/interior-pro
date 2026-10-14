// t96 - MOVE AND EDIT AN OUTLET / SWITCH IN THE DRAWING (2026-10-13 20:26, his "להזיז אותו ממקום למקום וגם לערוך אותו... וגם
// על המתגים"): in Select the sign is dragged along its wall or onto another wall with the same green / red as placing, and
// let go = move_elec (one undo step); on red nothing; Escape drops it; two presses on it ask for his window (elec_edit).
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };
const K = global.__listeners.__win.keydown[0];
const key = (k) => K({ key: k, code: '', target: { tagName: 'CANVAS' }, preventDefault() {}, stopPropagation() {} });
const down = (x, y) => global.fire('cv', 'mousedown', { button: 0, offsetX: c('sx', x), offsetY: c('sy', y), shiftKey: false, preventDefault() {} });
const calls = (n) => global.__calls.filter(k => k[0] === n).map(k => k[1] ? JSON.parse(k[1]) : null);

s('pages', []); s('activePage', 0); s('homeStash', null);
ok('no drag until Ruby says so (kill switch)', g('USE_ELEC_DRAG') === false);
c('elecEnable', true, true, true, true);
// two walls: w1 up the left (x 0), w2 along the top (y 200); a window on w1 at t 150, sill 44
c('loadWalls', [
  { id: 'w1', sx: 0, sy: 0, ex: 0, ey: 200, th: 5, ha: 'center', syms: [{ kind: 'window', body: 'window', t: 150, w: 36, header: 80, h: 36 }] },
  { id: 'w2', sx: 0, sy: 200, ex: 300, ey: 200, th: 5, ha: 'center', syms: [] }]);
c('loadRooms', []);
c('loadElec', [
  { id: 'o1', kind: 'outlet', x: 2.5, y: 40, nx: 1, ny: 0, gangs: 1, h: 18 },
  { id: 's1', kind: 'switch', x: 2.5, y: 80, nx: 1, ny: 0, gangs: 2, h: 48 }]);
c('setMode', 'sel'); s('scale', 4); c('draw');
const sh = g('elecShown');
const o1 = sh.find(o => o.id === 'o1'), s1 = sh.find(o => o.id === 's1');

down(o1.x, o1.y);
ok('mousedown on the outlet sign starts its drag', g('dragElec') && g('dragElec').id === 'o1', g('dragElec'));
c('handleMove', c('sx', 1.5), c('sy', 100));
ok('along the wall: the face under the mouse, green, at t 100', g('dragElec').h && g('dragElec').h.ok && Math.abs(g('dragElec').h.t - 100) < 1e-6, g('dragElec').h);
global.__calls.length = 0;
c('finishDrag');
const mv = calls('move_elec');
ok('let go: move_elec with the wall and the point on its face', mv.length === 1 && mv[0].id === 'o1' && mv[0].wall_id === 'w1' && Math.abs(mv[0].py - 100) < 1e-6, mv);
ok('one step of the model\'s undo', g('editHist').slice(-1)[0].what === 'move_elec');

// the switch at 48" onto the window (sill 44): red, nothing sent
down(s1.x, s1.y);
c('handleMove', c('sx', 1.5), c('sy', 150));
ok('a switch at 48 over the window (sill 44): red, says why', g('dragElec').h && g('dragElec').h.ok === false && /window/.test(g('dragElec').h.why), g('dragElec').h);
global.__calls.length = 0;
c('finishDrag');
ok('let go on red: nothing moved', calls('move_elec').length === 0);

// onto ANOTHER wall ("ממקום למקום")
down(s1.x, s1.y);
c('handleMove', c('sx', 120), c('sy', 198.5));
ok('onto the other wall: green there', g('dragElec').h && g('dragElec').h.ok && g('dragElec').h.w.id === 'w2', g('dragElec').h);
global.__calls.length = 0;
c('finishDrag');
ok('let go: move_elec to w2', calls('move_elec').length === 1 && calls('move_elec')[0].wall_id === 'w2', calls('move_elec'));

// Escape mid-drag drops it
down(o1.x, o1.y);
c('handleMove', c('sx', 1.5), c('sy', 120));
global.__calls.length = 0;
key('Escape');
ok('Escape mid-drag: dropped, nothing sent', !g('dragElec') && calls('move_elec').length === 0);

// two presses: his window
global.__calls.length = 0;
global.fire('cv', 'dblclick', { offsetX: c('sx', s1.x), offsetY: c('sy', s1.y), preventDefault() {} });
const ed = calls('elec_edit');
ok('two presses on the switch ask for his window with its id', ed.length === 1 && ed[0].id === 's1', ed);
ok('a ceiling light is not edited this way', (c('loadElec', [{ id: 'r1', kind: 'recessed', x: 60, y: 60, d: 5.12, hd: 4 }]), c('draw'), global.__calls.length = 0, global.fire('cv', 'dblclick', { offsetX: c('sx', 60), offsetY: c('sy', 60), preventDefault() {} }), calls('elec_edit').length === 0));
// held by its circle, 6" off the wall (10:48, measured on his machine: "no wall under the mouse"): the wall is still found
c('loadElec', [{ id: 'o1', kind: 'outlet', x: 2.5, y: 40, nx: 1, ny: 0, gangs: 1, h: 18, w: 2.75, hh: 2.25 }]);
c('draw');
down(8.5, 40);
c('handleMove', c('sx', 8.5), c('sy', 100));
ok('the mouse 6 in from the wall still finds the wall face, at the mouse\'s t', g('dragElec').h && g('dragElec').h.w.id === 'w1' && Math.abs(g('dragElec').h.t - 100) < 1e-6, g('dragElec').h);
global.__calls.length = 0; c('finishDrag');
ok('and lets go there', calls('move_elec').length === 1 && Math.abs(calls('move_elec')[0].py - 100) < 1e-6, calls('move_elec'));
// a sign over a cabinet (09:32): the press is taken in CAPTURE, before the kitchen's own mousedown, and goes no further
const caps = (global.__listeners.cv || {});
const capList = (caps.mousedown || []).filter(f => String(f).includes('elecGrab(p, ev)') && String(f).includes('elecPick(p)'));
ok('there is a capture mousedown for the signs, before the kitchen hooks its own', capList.length === 1);
c('loadElec', [{ id: 'o1', kind: 'outlet', x: 2.5, y: 40, nx: 1, ny: 0, gangs: 1, h: 18, w: 2.75, hh: 2.25 }]);
c('draw');
let stopped = 0;
const evc = { button: 0, offsetX: c('sx', 2.5 + 6), offsetY: c('sy', 40), shiftKey: false, preventDefault() {}, stopImmediatePropagation() { stopped++; } };
capList[0](evc);
ok('a press on the sign is picked there and stopped (the kitchen never sees it)', g('elecSel') === 'o1' && !!g('dragElec') && stopped === 1, [g('elecSel'), stopped]);
stopped = 0; c('finishDrag');
capList[0]({ button: 0, offsetX: c('sx', 100), offsetY: c('sy', 100), shiftKey: false, preventDefault() {}, stopImmediatePropagation() { stopped++; } });
ok('a press on empty paper is left to everyone else', stopped === 0);
// a wall light is TALL (09:33, his "מנורת קיר לא יכולה להיות מול חלון"): red over the window where a plate was not
const hUnder = c('elecHit', { x: 1.5, y: 150 }, { kind: 'wall_light', height: 40, hw: 4, hh: 10 });
ok('a wall light at 40 with 10 of half height reaches the sill at 44: red', hUnder && hUnder.ok === false, hUnder);
const hPlate = c('elecHit', { x: 1.5, y: 150 }, { kind: 'outlet', height: 40, hw: 1.4, hh: 2.25 });
ok('a plate at 40 under the same window: green', hPlate && hPlate.ok === true, hPlate);
console.log(fails ? `\n${fails} FAILED` : '\nALL PASS');
process.exit(fails ? 1 : 0);
