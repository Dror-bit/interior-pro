// t91 - DELETE AN OUTLET FROM THE DRAWING (2026-10-13, his "אני לא יכול למחוק את הנקודת חשמל מהתוכנת סירטוט").
// In Select a click on the sign picks it (blue), Delete / Backspace sends delete_elec with its id - one
// step of the model's undo - and the sign goes at once; a click elsewhere or Esc lets it go.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };
const K = global.__listeners.__win.keydown[0];
const key = (k) => K({ key: k, code: '', target: { tagName: 'CANVAS' }, preventDefault() {}, stopPropagation() {} });
const click = (x, y) => global.fire('cv', 'mousedown', { button: 0, offsetX: c('sx', x), offsetY: c('sy', y), shiftKey: false, preventDefault() {} });

s('pages', []); s('activePage', 0); s('homeStash', null);
c('loadWalls', [{ id: 'w1', sx: 0, sy: 0, ex: 0, ey: 200, th: 5, ha: 'center', syms: [] }]);
c('loadElec', [{ id: 'e1', kind: 'outlet', x: -2.5, y: 50, nx: -1, ny: 0 }, { id: 'e2', kind: 'switch', x: -2.5, y: 150, nx: -1, ny: 0, gangs: 1 }]);
c('setMode', 'sel');
c('draw');
const sh = g('elecShown');
ok('both signs are on the screen', sh.length === 2, sh);

click(sh[0].x, sh[0].y);
ok('a click on the outlet sign picks it', g('elecSel') === 'e1', g('elecSel'));
ok('and no wall is picked with it', g('sel') === null, g('sel'));

click(-60, 100);
ok('a click on empty paper lets it go', g('elecSel') === null, g('elecSel'));

click(sh[0].x, sh[0].y);
global.__calls.length = 0;
key('Delete');
const del = global.__calls.filter(k => k[0] === 'delete_elec').map(k => JSON.parse(k[1]));
ok('Delete sends that one id to the model', del.length === 1 && del[0].id === 'e1', del);
ok('it is one step of the editor\'s undo (the model\'s)', g('editHist').slice(-1)[0].what === 'delete_elec', g('editHist').slice(-1));
ok('the sign goes at once, the other stays', g('elecItems').length === 1 && g('elecItems')[0].id === 'e2', g('elecItems'));
ok('nothing stays picked', g('elecSel') === null);

c('draw');
click(g('elecShown')[0].x, g('elecShown')[0].y);
ok('the switch can be picked too', g('elecSel') === 'e2', g('elecSel'));
key('Escape');
ok('Esc lets it go', g('elecSel') === null, g('elecSel'));
global.__calls.length = 0;
key('Delete');
ok('then Delete deletes nothing', global.__calls.filter(k => k[0] === 'delete_elec').length === 0);

console.log(fails ? `\n${fails} FAILED` : '\nALL PASS');
process.exit(fails ? 1 : 0);
