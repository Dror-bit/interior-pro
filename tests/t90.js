// t90 - ELECTRICAL FROM THE DRAWING (2026-10-13, his "מעולה" on editor_mock2.png).
// The button sits at the end of the tool rail; his window answers (elecArmed); the green sign follows
// the wall face with its distance from the nearer corner; a click or a number + Enter goes to Ruby
// (place_elec) with a point an inch off the face he is on; red on a door; Esc goes back to Select.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };
const sent = () => global.__calls.filter(k => k[0] === 'place_elec').map(k => JSON.parse(k[1]));

s('pages', []); s('activePage', 0); s('homeStash', null);
// a wall up the Y axis, 5" thick, centred; its left face (+n = -X) at x = -2.5, corners as the model sends them
c('loadWalls', [{ id: 'w1', sx: 0, sy: 0, ex: 0, ey: 200, th: 5, ha: 'center', syms: [],
                  corners: [2.5, 0, -2.5, 0, -2.5, 200, 2.5, 200] }]);

ok('no button until Ruby says so (kill switch)', g('USE_ELEC_PLACE') === false);
c('elecEnable', true, true);
const rail = global.__els['kp-tool-rail'];
ok('the Electrical button is at the end of the tool rail, after a line (Lighting under it since 15:08)',
   rail && rail.children.length >= 3 && rail.children[rail.children.length - 1].id === 'modeLight' &&
   rail.children[rail.children.length - 2].id === 'modeElec' &&
   rail.children[rail.children.length - 3].id === 'elecSep', rail && rail.children.map(x => x.id));
Object.defineProperty(rail, 'lastElementChild', { get() { return this.children[this.children.length - 1]; } });
c('placeElecBtn');
ok('asked again, it is not doubled', rail.children.filter(x => x.id === 'modeElec').length === 1, rail.children.map(x => x.id));

c('elecArmed', { kind: 'outlet', height: 18, product: 'Simple' });
ok('his window answered: the tool is on', g('mode') === 'elec', g('mode'));

let h = c('elecHit', { x: -4, y: 50 });
ok('the mouse by the left face: that face, 50" from the nearer corner, green', h && h.ns === 1 && Math.abs(h.foff - 2.5) < 1e-9 && Math.abs(h.dist - 50) < 1e-9 && h.ok === true, h);
h = c('elecHit', { x: 4, y: 170 });
ok('the other face: 30" from the nearer (top) corner', h && h.ns === -1 && Math.abs(h.dist - 30) < 1e-9, h);

global.__calls.length = 0;
s('elecHover', c('elecHit', { x: -4, y: 50 }));
c('elecSend', g('elecHover'), null);
let ps = sent();
ok('a click sends the wall and a point an inch off the face he is on', ps.length === 1 && ps[0].wall_id === 'w1' &&
   Math.abs(ps[0].px + 3.5) < 1e-9 && Math.abs(ps[0].py - 50) < 1e-9 && ps[0].dist === null, ps);
ok('it is one step of the editor\'s undo (the model\'s)', g('editHist').slice(-1)[0].what === 'place_elec', g('editHist').slice(-1));

// typed: 2 4 Enter
const K = global.__listeners.__win.keydown[0];
const key = (k) => K({ key: k, code: '', target: { tagName: 'CANVAS' }, preventDefault() {}, stopPropagation() {} });
global.__calls.length = 0;
key('2'); key('4');
ok('the number shows while typed', g('typed') === '24', g('typed'));
key('Enter');
ps = sent();
ok('a number + Enter: placed that far from the nearer corner', ps.length === 1 && ps[0].dist === 24, ps);
ok('and the number is cleared', g('typed') === '', g('typed'));

// on a door: red, a click sends nothing
c('loadWalls', [{ id: 'w1', sx: 0, sy: 0, ex: 0, ey: 200, th: 5, ha: 'center', syms: [{ t: 50, w: 32, kind: 'door' }],
                  corners: [2.5, 0, -2.5, 0, -2.5, 200, 2.5, 200] }]);
h = c('elecHit', { x: -4, y: 50 });
ok('on a door: red', h && h.ok === false, h);
// under a window (sill at 36", outlet at 18"): green; at 48" (on the glass): red
c('loadWalls', [{ id: 'w1', sx: 0, sy: 0, ex: 0, ey: 200, th: 5, ha: 'center',
                  syms: [{ t: 120, w: 36, body: 'window', kind: 'window', h: 44, header: 80 }],
                  corners: [2.5, 0, -2.5, 0, -2.5, 200, 2.5, 200] }]);
h = c('elecHit', { x: -4, y: 120 });
ok('UNDER a window: green (his 13:39)', h && h.ok === true, h);
s('elecCfg', { kind: 'outlet', height: 48 });
h = c('elecHit', { x: -4, y: 120 });
ok('on the glass: red', h && h.ok === false, h);
s('elecCfg', { kind: 'outlet', height: 18 });

c('elecResult', false, 'outside of the house');
ok('a refusal from Ruby is kept to show by the sign', g('elecMsg') === 'outside of the house', g('elecMsg'));
s('elecHover', c('elecHit', { x: -4, y: 120 }));
c('draw');
ok('the draw with the ghost does not crash', true);

key('Escape');
ok('Esc: back to Select, the ghost gone', g('mode') === 'sel' && g('elecHover') === null, [g('mode'), g('elecHover')]);

console.log(fails ? `\n${fails} FAILED` : '\nALL PASS');
process.exit(fails ? 1 : 0);
