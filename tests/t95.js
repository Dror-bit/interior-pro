// t95 - MOVE A CEILING LIGHT IN THE DRAWING (2026-10-13 20:00, his "איך אני מזיז אותה" / "שתי מנורות שונות... באותו הקו"):
// in Select the sign is dragged; it locks onto another light's x or y (magenta) and onto a guide line; Escape mid-drag puts
// it back; a number + Enter on a picked light = that far from the nearest wall; the model is told once (move_light).
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };
const K = global.__listeners.__win.keydown[0];
const key = (k) => K({ key: k, code: '', target: { tagName: 'CANVAS' }, preventDefault() {}, stopPropagation() {} });
const down = (x, y) => global.fire('cv', 'mousedown', { button: 0, offsetX: c('sx', x), offsetY: c('sy', y), shiftKey: false, preventDefault() {} });
const calls = (n) => global.__calls.filter(k => k[0] === n).map(k => k[1] ? JSON.parse(k[1]) : null);

s('pages', []); s('activePage', 0); s('homeStash', null);
ok('no drag until Ruby says so (kill switch)', g('USE_LIGHT_DRAG') === false);
c('elecEnable', true, true, true);
c('loadWalls', [{ id: 'w1', sx: 0, sy: 0, ex: 0, ey: 240, th: 5, ha: 'center', syms: [] }]);
c('loadRooms', [{ id: 'r1', name: 'Room', pts: [0, 0, 200, 0, 200, 150, 0, 150] }]);
c('loadElec', [
  { id: 'a', kind: 'recessed', x: 60, y: 40, d: 5.12, hd: 4 },
  { id: 'b', kind: 'ceiling_light', x: 140, y: 100, d: 12, hd: 8.4 },
  { id: 'e', kind: 'outlet', x: 0, y: 70, nx: 1, ny: 0 }]);
s('guides', []);
c('setMode', 'sel'); s('scale', 4); c('draw');

// drag b until its x is nearly a's x: it locks there
down(140, 100);
ok('mousedown on the sign starts a drag', g('dragLight') && g('dragLight').id === 'b', g('dragLight'));
c('handleMove', c('sx', 61.2), c('sy', 100));
ok('within 8 px of the other light\'s x it locks onto it (same line)', g('elecItems')[1].x === 60 && g('elecItems')[1].y === 100, g('elecItems')[1]);
ok('the lock is drawn', g('dragLight').lock.length === 1 && g('dragLight').lock[0].kind === 'light');
global.__calls.length = 0;
c('finishDrag');
const mv = calls('move_light');
ok('the model is told once, the locked point', mv.length === 1 && mv[0].id === 'b' && mv[0].x === 60 && mv[0].y === 100, mv);
ok('one step of the model\'s undo', g('editHist').slice(-1)[0].what === 'move_light');

// Escape mid-drag puts it back
down(60, 100);
c('handleMove', c('sx', 90), c('sy', 120));
ok('it follows the mouse', g('elecItems')[1].x === 90 && g('elecItems')[1].y === 120, g('elecItems')[1]);
global.__calls.length = 0;
key('Escape');
ok('Escape mid-drag: back where it was, nothing sent', !g('dragLight') && g('elecItems')[1].x === 60 && g('elecItems')[1].y === 100 && calls('move_light').length === 0);

// a guide line
s('guides', [{ x1: 0, y1: 30, x2: 200, y2: 30 }]);
down(60, 100);
c('handleMove', c('sx', 120), c('sy', 31));
ok('near a guide line it locks onto it', g('elecItems')[1].y === 30 && g('dragLight').lock[0].kind === 'guide', g('elecItems')[1]);
key('Escape');

// a number + Enter on the picked light = that far from the nearest wall (the bottom wall at y 0: a is 40 from it)
down(60, 40); c('finishDrag');
ok('a plain click keeps it picked, nothing sent', g('elecSel') === 'a' && calls('move_light').length === 0);
global.__calls.length = 0;
key('2'); key('4'); key('Enter');
const mv2 = calls('move_light');
ok('24 + Enter: 24 in from the nearest wall, straight in', mv2.length === 1 && mv2[0].id === 'a' && mv2[0].x === 60 && mv2[0].y === 24, mv2);
ok('an outlet sign is never dragged', (down(0, 70), !g('dragLight')));
console.log(fails ? `\n${fails} FAILED` : '\nALL PASS');
process.exit(fails ? 1 : 0);
