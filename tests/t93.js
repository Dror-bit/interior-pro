// t93 - ALL THE LIGHTS IN THE DRAWING + THE LIGHTING BUTTON (2026-10-13 15:08, his "תסיים איתו... גם עם מנורות הקיר
// וגם עם מנורות התקרה... שאת כולם יהיה אפשרי להציב גם בסירטוט"). Ceiling light / fan / wall light drawn and picked;
// a ceiling kind is placed with a click INSIDE a room (place_light), red outside; a wall light goes on a wall like an outlet.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };
const click = (x, y) => global.fire('cv', 'mousedown', { button: 0, offsetX: c('sx', x), offsetY: c('sy', y), shiftKey: false, preventDefault() {} });
const calls = (n) => global.__calls.filter(k => k[0] === n).map(k => k[1] ? JSON.parse(k[1]) : null);

s('pages', []); s('activePage', 0); s('homeStash', null);
ok('no Lighting until Ruby says so (kill switch)', g('USE_LIGHT_PLACE') === false);
c('elecEnable', true, true);
ok('Ruby turns both on', g('USE_ELEC_PLACE') === true && g('USE_LIGHT_PLACE') === true);
c('loadWalls', [{ id: 'w1', sx: 0, sy: 0, ex: 0, ey: 200, th: 5, ha: 'center', syms: [] }]);
c('loadRooms', [{ id: 'r1', name: 'Room', pts: [2.5, 0, 150, 0, 150, 200, 2.5, 200] }]);
c('loadElec', [
  { id: 'c1', kind: 'ceiling_light', x: 60, y: 100, d: 12, hd: 8.4 },
  { id: 'f1', kind: 'ceiling_fan', x: 100, y: 50, d: 52, hd: 36 },
  { id: 'l1', kind: 'wall_light', x: 2.5, y: 150, nx: 1, ny: 0, w: 8 }
]);
c('setMode', 'sel'); c('draw');
const sh = g('elecShown');
ok('three signs on the screen', sh.length === 3 && sh.map(o => o.kind).sort().join() === 'ceiling_fan,ceiling_light,wall_light', sh);
ok('the fan can be picked anywhere inside its blades', (click(118, 50), g('elecSel') === 'f1'), g('elecSel'));
click(-60, 100);

// a ceiling light from the drawing: his window chose, a click inside the room hangs it
c('elecArmed', { kind: 'ceiling_light', product: 'Schonbek', height: 0 });
ok('the mode is elec', g('mode') === 'elec');
global.__calls.length = 0;
click(-40, 100);
ok('outside a room: red, nothing sent', calls('place_light').length === 0 && g('elecHover') && g('elecHover').ok === false, g('elecHover'));
click(70, 120);
const pl = calls('place_light');
ok('inside the room: place_light with the point', pl.length === 1 && pl[0].x === 70 && pl[0].y === 120, pl);
ok('it is one step of the model\'s undo', g('editHist').slice(-1)[0].what === 'place_light');

// a wall light: on the wall face, like an outlet (place_elec)
c('elecArmed', { kind: 'wall_light', product: 'Hinkley', height: 66 });
global.__calls.length = 0;
click(3.5, 100);
const pe = calls('place_elec');
ok('a wall light goes through place_elec on the wall', pe.length === 1 && pe[0].wall_id === 'w1', pe);
ok('a ceiling kind never goes to a wall', calls('place_light').length === 0);
console.log(fails ? `\n${fails} FAILED` : '\nALL PASS');
process.exit(fails ? 1 : 0);
