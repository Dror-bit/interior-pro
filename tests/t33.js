// t33 - the bow (קשת) sign in the 2D editor.
//
// The user types the number the way a person thinks about it: PLUS = the wall
// bulges OUT of the house. Stored sag is positive to the LEFT of start->end,
// and this plugin's exterior side is the RIGHT of start->end, so the typed box
// is the negative of what gets stored. Dragging the middle is NOT affected -
// it already follows the mouse.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };

// --- the pure helpers ------------------------------------------------------
ok('a typed plus is stored as a minus', c('uiSagToModel', 60) === -60, c('uiSagToModel', 60));
ok('a typed minus is stored as a plus', c('uiSagToModel', -60) === 60, c('uiSagToModel', -60));
ok('a stored minus shows as a plus', c('modelSagToUi', -60) === 60, c('modelSagToUi', -60));
ok('zero is still zero', c('uiSagToModel', 0) === 0, c('uiSagToModel', 0));
ok('the two directions undo each other', c('modelSagToUi', c('uiSagToModel', 37.5)) === 37.5,
   c('modelSagToUi', c('uiSagToModel', 37.5)));

// --- the wiring: what actually reaches Ruby --------------------------------
function sendTyped(txt, sagNow) {
  s('sketches', []); s('pendingSketches', []); s('walls', []); s('pending', []);
  s('pendingRooms', []); s('mode', 'sel');
  s('selList', [{ type: 'wall', w: { id: 'w1', sag: sagNow || 0, sx: 0, sy: 0, ex: 120, ey: 0, th: 5 } }]);
  document.getElementById('selSag').value = txt;
  global.__calls.length = 0;
  c('applySelSag');
  const hit = global.__calls.filter(a => a[0] === 'set_wall_sag').pop();
  return hit ? JSON.parse(hit[1]) : null;
}

let sent = sendTyped('60');
ok('typing 60 asks Ruby for -60, i.e. bow OUTWARD', sent && sent.sag === -60, sent);
sent = sendTyped('-60');
ok('typing -60 asks Ruby for +60, i.e. bow INWARD', sent && sent.sag === 60, sent);
sent = sendTyped('0');
ok('typing 0 straightens the wall', sent && sent.sag === 0, sent);
ok('and it is the selected wall that gets it', sent && sent.id === 'w1', sent);
ok('rubbish in the box sends nothing', sendTyped('abc') === null, sendTyped('abc'));

// --- a pending (not yet applied) wall keeps the same rule ------------------
s('sketches', []); s('pendingSketches', []); s('walls', []); s('pendingRooms', []); s('mode', 'sel');
s('pending', [{ sx: 0, sy: 0, ex: 120, ey: 0, th: 5, sag: 0 }]);
s('selList', [{ type: 'pending', i: 0 }]);
document.getElementById('selSag').value = '24';
c('applySelSag');
ok('a pending wall stores -24 too', g('pending')[0].sag === -24, g('pending')[0].sag);

console.log(fails ? '\n*** ' + fails + ' FAILED ***' : '\nALL PASS');
process.exit(fails ? 1 : 0);
