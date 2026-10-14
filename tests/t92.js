// t92 - RECESSED LIGHTS IN THE DRAWING (2026-10-13, his pick "רססד = עיגול בתוך עיגול"): two circles at the
// real size, picked in Select anywhere inside the trim, Delete sends delete_elec like an outlet.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };
const K = global.__listeners.__win.keydown[0];
const key = (k) => K({ key: k, code: '', target: { tagName: 'CANVAS' }, preventDefault() {}, stopPropagation() {} });
const click = (x, y) => global.fire('cv', 'mousedown', { button: 0, offsetX: c('sx', x), offsetY: c('sy', y), shiftKey: false, preventDefault() {} });

s('pages', []); s('activePage', 0); s('homeStash', null);
c('loadWalls', [{ id: 'w1', sx: 0, sy: 0, ex: 0, ey: 200, th: 5, ha: 'center', syms: [] }]);
c('loadElec', [{ id: 'r1', kind: 'recessed', x: 60, y: 100, d: 6.5, hd: 5.5 }, { id: 'e1', kind: 'outlet', x: -2.5, y: 50, nx: -1, ny: 0 }]);
c('setMode', 'sel');
c('draw');
const sh = g('elecShown');
const r = sh.find(o => o.kind === 'recessed');
ok('the recessed light is on the screen, at its middle', r && r.x === 60 && r.y === 100, sh);
ok('with the trim radius', r && r.r === 3.25, r);
ok('the outlet still drawn', sh.some(o => o.kind === 'outlet'), sh);
s('scale', 40); c('draw');
click(62.8, 100);
ok('a click inside the trim (not the middle) picks it', g('elecSel') === 'r1', g('elecSel'));
global.__calls.length = 0;
key('Delete');
const del = global.__calls.filter(k => k[0] === 'delete_elec').map(k => JSON.parse(k[1]));
ok('Delete sends its id to the model', del.length === 1 && del[0].id === 'r1', del);
ok('it goes at once', !g('elecItems').some(o => o.id === 'r1'), g('elecItems'));
console.log(fails ? `\n${fails} FAILED` : '\nALL PASS');
process.exit(fails ? 1 : 0);
