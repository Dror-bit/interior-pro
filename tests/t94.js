// t94 - SPREAD RECESSED LIGHTS IN THE DRAWING (2026-10-13 15:36): in Lighting with a ceiling kind, over a room, typing
// 2x3 shows the grid as ghosts and Enter sends place_lights with the points (one undo step); a plain number is not a grid;
// outside a room nothing is sent; a wall kind keeps the distance road.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };
const K = global.__listeners.__win.keydown[0];
const key = (k) => K({ key: k, code: '', target: { tagName: 'CANVAS' }, preventDefault() {}, stopPropagation() {} });
const move = (x, y) => global.fire('cv', 'mousemove', { buttons: 0, offsetX: c('sx', x), offsetY: c('sy', y), shiftKey: false, preventDefault() {} });
const calls = (n) => global.__calls.filter(k => k[0] === n).map(k => k[1] ? JSON.parse(k[1]) : null);

s('pages', []); s('activePage', 0); s('homeStash', null);
c('elecEnable', true, true);
c('loadWalls', [{ id: 'w1', sx: 0, sy: 0, ex: 0, ey: 240, th: 5, ha: 'center', syms: [] }]);
c('loadRooms', [{ id: 'r1', name: 'Room', pts: [0, 0, 120, 0, 120, 90, 0, 90] }]);
c('loadElec', []);
ok('2x3, 2 X 3, 2*3 are grids; 24 and 2.5 are not', c('spreadParse', '2x3').rows === 2 && c('spreadParse', '2 X 3').cols === 3 && c('spreadParse', '2*3').cols === 3 && c('spreadParse', '24') === null && c('spreadParse', '2.5') === null);
const pts = c('spreadPoints', g('rooms')[0], 3, 2);
ok('3x2 in a 120x90 room: the same gap, half to the walls', JSON.stringify(pts) === JSON.stringify([[30, 15], [90, 15], [30, 45], [90, 45], [30, 75], [90, 75]]), pts);

c('elecArmed', { kind: 'recessed', product: 'Recessed 4in Round White', height: 0 });
move(60, 45);
ok('over the room: green', g('elecHover') && g('elecHover').ok === true && g('elecHover').room && g('elecHover').room.id === 'r1', g('elecHover'));
global.__calls.length = 0;
key('2'); key('x'); key('3');
ok('the typing is kept (2x3)', g('typed') === '2x3', g('typed'));
key('Enter');
const pl = calls('place_lights');
ok('Enter sends place_lights with the 6 points, rows and cols', pl.length === 1 && pl[0].points.length === 6 && pl[0].rows === 2 && pl[0].cols === 3, pl);
ok('one step of the model\'s undo', g('editHist').slice(-1)[0].what === 'place_lights');
ok('the typing is cleared', g('typed') === '');
ok('no single light was sent with it', calls('place_light').length === 0);

global.__calls.length = 0;
move(-40, 45);
key('2'); key('x'); key('2'); key('Enter');
ok('outside a room: nothing sent', calls('place_lights').length === 0);

move(60, 45);
key('2'); key('4'); key('Enter');
ok('a plain number on a ceiling kind: no grid, nothing sent', calls('place_lights').length === 0 && calls('place_light').length === 0);

// rows x cols from HIS WINDOW (19:18): a plain click spreads; 1x1 = one light
const click = (x, y) => global.fire('cv', 'mousedown', { button: 0, offsetX: c('sx', x), offsetY: c('sy', y), shiftKey: false, preventDefault() {} });
c('elecArmed', { kind: 'recessed', product: 'Recessed 4in Round White', height: 0, rows: 2, cols: 2 });
move(60, 45); global.__calls.length = 0;
ok('the grid from the window shows as ghosts', c('elecGrid').rows === 2 && c('elecGrid').cols === 2);
click(60, 45);
ok('a click with 2x2 in the window spreads 4 (place_lights), not one', calls('place_lights').length === 1 && calls('place_lights')[0].points.length === 4 && calls('place_light').length === 0, calls('place_lights'));
key('3'); key('x'); key('1');
ok('typing wins over the window (3x1)', c('elecGrid').rows === 3 && c('elecGrid').cols === 1);
key('Escape'); s('typed', '');
c('elecArmed', { kind: 'recessed', product: 'Recessed 4in Round White', height: 0, rows: 1, cols: 1 });
move(60, 45); global.__calls.length = 0; click(60, 45);
ok('1x1 in the window: one light where he clicks', calls('place_light').length === 1 && calls('place_lights').length === 0);

c('elecArmed', { kind: 'wall_light', product: 'Hinkley', height: 66 });
move(1, 100);
global.__calls.length = 0;
key('2'); key('4'); key('Enter');
ok('a wall kind keeps the distance road (place_elec with typed 24)', calls('place_elec').length === 1 && calls('place_elec')[0].dist === 24, calls('place_elec'));
console.log(fails ? `\n${fails} FAILED` : '\nALL PASS');
process.exit(fails ? 1 : 0);
