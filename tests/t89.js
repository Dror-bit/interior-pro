// t89 - OUTLETS IN HIS DRAWING (2026-10-13, his pick: "השקעים כמו שאתה מציע (הסימנים)").
// The model sends the outlets (loadElec), the draw puts the sign on the house tab only:
// circle 6" off the wall, on the line out of the wall. A drawing page shows none.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };

s('pages', []); s('activePage', 0); s('homeStash', null);
c('loadWalls', [{ id: 'w1', sx: 0, sy: 0, ex: 0, ey: 200, th: 5, syms: [] }]);
c('loadElec', [{ id: 'e1', kind: 'outlet', x: 0, y: 38, nx: 1, ny: 0, turn: 0, ct: false }]);
c('draw');
let sh = g('elecShown');
ok('one outlet is drawn on the house tab', sh.length === 1, sh);
ok('its circle stands 6" off the wall, on the line out of it', sh.length === 1 && Math.abs(sh[0].x - 6) < 1e-9 && Math.abs(sh[0].y - 38) < 1e-9, sh);

c('loadElec', [{ id: 'e2', kind: 'outlet', x: 50, y: 100, nx: 0, ny: -1 }]);
c('draw');
sh = g('elecShown');
ok('a wall facing down: the circle goes down', sh.length === 1 && Math.abs(sh[0].x - 50) < 1e-9 && Math.abs(sh[0].y - 94) < 1e-9, sh);

c('loadElec', [{ id: 'e3', kind: 'switch', x: 0, y: 0, nx: 1, ny: 0, gangs: 2 }]);
c('draw');
ok('a switch is drawn too (S2 at 6" off the wall)', g('elecShown').length === 1 && g('elecShown')[0].kind === 'switch' && Math.abs(g('elecShown')[0].x - 6) < 1e-9, g('elecShown'));
c('loadElec', [{ id: 'e4', kind: 'wall_light', x: 0, y: 0, nx: 1, ny: 0 }]);
c('draw');
ok('a kind with no sign yet is not drawn', g('elecShown').length === 0, g('elecShown'));

c('loadElec', [{ id: 'e1', kind: 'outlet', x: 0, y: 38, nx: 1, ny: 0 }]);
c('newPage');
c('draw');
ok('a drawing page shows no outlets', g('activePage') === 1 && g('elecShown').length === 0, g('elecShown'));
c('goPage', 0);
c('draw');
ok('back on the house tab they are there again', g('elecShown').length === 1, g('elecShown'));

c('loadElec', null);
c('draw');
ok('nothing sent = nothing drawn, no crash', g('elecShown').length === 0);

console.log(fails ? `\n${fails} FAILED` : '\nALL PASS');
process.exit(fails ? 1 : 0);
