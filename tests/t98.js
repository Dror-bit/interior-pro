// t98 - PLACE PLUMBING FROM THE DRAWING (2026-10-14, his pick "1"): the Plumbing button asks Ruby for his window;
// armed with a plumbing product the ghost is the product's sign; a click on a wall face sends place_plumb (not
// place_elec), a number + Enter sends the distance; Escape leaves; an outlet still goes to place_elec.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };
const K = global.__listeners.__win.keydown[0];
const key = (k) => K({ key: k, code: '', target: { tagName: 'CANVAS' }, preventDefault() {}, stopPropagation() {} });
const click = (x, y) => global.fire('cv', 'mousedown', { button: 0, offsetX: c('sx', x), offsetY: c('sy', y), shiftKey: false, preventDefault() {} });
const move = (x, y) => c('handleMove', c('sx', x), c('sy', y));
const calls = (n) => global.__calls.filter(k => k[0] === n).map(k => JSON.parse(k[1]));

s('pages', []); s('activePage', 0); s('homeStash', null);
c('loadWalls', [{ id: 'w1', sx: 0, sy: 0, ex: 400, ey: 0, th: 5, ha: 'center', syms: [] }]);
c('loadRooms', []);
c('elecEnable', true, true, true, true, true);
c('placeElecBtn');
const pb = global.document.getElementById('modePlumb');
ok('a Plumbing button is on the rail', !!pb, pb);
global.__calls.length = 0;
c('plumbStart');
ok('it asks Ruby for his Plumbing window', global.__calls.some(k => k[0] === 'plumb_pick'), global.__calls);
c('elecArmed', { kind: 'plumb', plumb: true, fkind: 'toilet', product: 'TOTO', sign: 'toilet', hw: 10, bo: 0, a0: 0, a1: 28, height: 15, hh: 15 });
ok('armed = elec mode, a plumbing one', g('mode') === 'elec' && c('elecPlumb') === true, g('mode'));
s('scale', 4);
move(100, 1.5);
let err = null; try { c('draw'); } catch (e) { err = String(e); }
ok('the ghost draws without an error', !err, err);
ok('the mouse is on the wall face, green', g('elecHover') && g('elecHover').ok === true, g('elecHover'));
global.__calls.length = 0;
click(100, 1.5);
let pl = calls('place_plumb');
ok('a click sends place_plumb with the wall and the point', pl.length === 1 && pl[0].wall_id === 'w1' && pl[0].dist === null, pl);
ok('and NOT place_elec', calls('place_elec').length === 0, calls('place_elec'));
global.__calls.length = 0;
move(100, 1.5); key('2'); key('4'); key('Enter');
pl = calls('place_plumb');
ok('24 + Enter sends the distance from the nearer corner', pl.length === 1 && pl[0].dist === 24, pl);
c('elecResult', false, 'only on a tiled wall');
ok('a refusal is kept to show', g('elecMsg') === 'only on a tiled wall', g('elecMsg'));
key('Escape');
ok('Escape leaves the mode', g('mode') !== 'elec', g('mode'));
// an outlet still goes its own way
c('elecArmed', { kind: 'outlet', gangs: 1, height: 18, hw: 1.4, hh: 2.25 });
global.__calls.length = 0;
click(150, 1.5);
ok('an outlet click still sends place_elec', calls('place_elec').length === 1 && calls('place_plumb').length === 0, global.__calls);
console.log(fails ? `\n${fails} FAILED` : '\nALL PASS');
process.exit(fails ? 1 : 0);
