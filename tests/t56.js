// t56 - עיגון קומה לראשית הצירים.
//
// He draws each floor somewhere else on the same sheet, then on each floor
// picks the SAME corner and the SAME direction; the blue drawing is moved so
// that corner sits on (0,0) and that direction runs along +X. Two floors
// drawn far apart and turned differently must then land exactly on top of
// each other. Rigid: lengths, thicknesses and openings unchanged.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };
const close = (a, b, tol) => Math.abs(a - b) < (tol || 0.01);

s('walls', []); s('ghosts', []); s('sketches', []); s('pendingSketches', []);
s('pendingRooms', []); s('guides', []); s('mode', 'sel');

// The same 240 x 180 floor, drawn twice: once flat at (500,500), once at
// (-900, 300) turned 37 degrees. Same corner, same direction on both.
function floor(ox, oy, deg) {
  const a = deg * Math.PI / 180, ca = Math.cos(a), sa = Math.sin(a);
  const P = (x, y) => ({ x: ox + x * ca - y * sa, y: oy + x * sa + y * ca });
  const k = [[0, 0], [240, 0], [240, 180], [0, 180]];
  const out = [];
  for (let i = 0; i < 4; i++) {
    const p = P(k[i][0], k[i][1]), q = P(k[(i + 1) % 4][0], k[(i + 1) % 4][1]);
    out.push({ sx: p.x, sy: p.y, ex: q.x, ey: q.y, th: 8, ha: 'left',
               cat: 'exterior', ops: [[40, 30]] });
  }
  return out;
}
const lens = (ws) => ws.map(w => Math.hypot(w.ex - w.sx, w.ey - w.sy));

// --- floor 1: flat, far from the origin
const f1 = floor(500, 500, 0);
const len1 = lens(f1);
s('pending', f1);
c('alignPendingToOrigin', { x: f1[0].sx, y: f1[0].sy }, { x: f1[0].ex, y: f1[0].ey });
const a1 = g('pending');
ok('the picked corner sits on (0,0)', close(a1[0].sx, 0) && close(a1[0].sy, 0),
   [a1[0].sx, a1[0].sy]);
ok('the picked direction runs along +X', close(a1[0].ey, 0) && a1[0].ex > 0,
   [a1[0].ex, a1[0].ey]);

// --- floor 2: somewhere else entirely, and turned
const f2 = floor(-900, 300, 37);
s('pending', f2);
c('alignPendingToOrigin', { x: f2[0].sx, y: f2[0].sy }, { x: f2[0].ex, y: f2[0].ey });
const a2 = g('pending');

ok('the two floors land exactly on top of each other',
   a1.every((w, i) => close(w.sx, a2[i].sx, 0.001) && close(w.sy, a2[i].sy, 0.001) &&
                      close(w.ex, a2[i].ex, 0.001) && close(w.ey, a2[i].ey, 0.001)),
   a1.map((w, i) => [[w.sx, w.sy], [a2[i].sx, a2[i].sy]]));

// --- it is a RIGID move: nothing is stretched or resized
ok('every wall keeps its length', lens(a2).every((L, i) => close(L, len1[i], 0.001)),
   [lens(a2), len1]);
ok('thickness and openings are untouched',
   a2.every(w => w.th === 8 && w.ops.length === 1 && w.ops[0][0] === 40 && w.ops[0][1] === 30),
   a2.map(w => [w.th, w.ops]));

// --- a pending shape travels with the walls
s('pending', floor(500, 500, 0));
s('pendingSketches', [{ pts: [500, 500, 740, 500], closed: false }]);
c('alignPendingToOrigin', { x: 500, y: 500 }, { x: 740, y: 500 });
const sk = g('pendingSketches')[0];
ok('a pending shape is carried along', close(sk.pts[0], 0) && close(sk.pts[1], 0) &&
   close(sk.pts[2], 240) && close(sk.pts[3], 0), sk.pts);

// --- THE WALLS ALREADY IN THE MODEL GO TOO (2026-09-24) ------------------
// A click on the door/window button runs Apply by itself, so by the time he
// anchors, most of the floor is in the model. Moving only the blue walls
// "sent each floor somewhere different". Ruby gets the same corner + turn.
s('pending', []);
s('pendingSketches', []);
s('walls', [{ id: 'm1', sx: 500, sy: 500, ex: 740, ey: 500, th: 8, ha: 'left', cat: 'exterior', ops: [] },
            { id: 'm2', sx: 740, sy: 500, ex: 740, ey: 680, th: 8, ha: 'left', cat: 'exterior', ops: [] }]);
__calls.length = 0;
c('alignPendingToOrigin', { x: 500, y: 500 }, { x: 500, y: 680 });   // direction UP the side wall
let sent = __calls.filter(k => k[0] === 'align_walls');
ok('the model walls are sent to Ruby', sent.length === 1, __calls.map(k => k[0]));
let msg = sent.length ? JSON.parse(sent[0][1]) : {};
ok('with every wall of the level', msg.ids && msg.ids.length === 2 && msg.ids[0] === 'm1', msg.ids);
ok('the picked corner', msg.cx === 500 && msg.cy === 500, msg);
ok('and the turn that puts the picked direction on +X (a quarter turn here)',
   close(msg.ang, -Math.PI / 2, 1e-9), msg.ang);

// --- a second click that misses the wall by a hair does not turn the floor
__calls.length = 0;
c('alignPendingToOrigin', { x: 500, y: 500 }, { x: 740, y: 503 });   // 0.7 degrees off
sent = __calls.filter(k => k[0] === 'align_walls');
msg = sent.length ? JSON.parse(sent[0][1]) : {};
ok('a near-miss click gives an exact zero turn', msg.ang === 0 || Math.abs(msg.ang) < 1e-12, msg.ang);

// --- nothing in the model: nothing is sent
s('walls', []);
__calls.length = 0;
c('alignPendingToOrigin', { x: 500, y: 500 }, { x: 740, y: 500 });
ok('no model walls -> no Ruby call', __calls.filter(k => k[0] === 'align_walls').length === 0);

// --- A TARGET THAT IS NOT THE ORIGIN, AND ONLY THE SELECTED WALLS ---------
// (2026-09-24) A two-storey house and a two-storey ADU on the same sheet:
// the ADU's upper floor must land on the ADU's ground floor, not on (0,0),
// and the house next to it must not move. Corner + direction on the ADU,
// then corner + direction on the grey floor below.
s('pending', []); s('pendingSketches', []);
s('walls', [{ id: 'house', sx: 0, sy: 0, ex: 240, ey: 0, th: 8, ha: 'left', cat: 'exterior', ops: [] },
            { id: 'adu1',  sx: 900, sy: 900, ex: 900, ey: 1100, th: 8, ha: 'left', cat: 'exterior', ops: [] },
            { id: 'adu2',  sx: 900, sy: 1100, ex: 1000, ey: 1100, th: 8, ha: 'left', cat: 'exterior', ops: [] }]);
s('selList', [{ type: 'wall', w: g('walls')[1] }, { type: 'wall', w: g('walls')[2] }]);
__calls.length = 0;
// ADU drawn with its long wall going UP from (900,900); below, the ADU sits
// at (600,100) with that wall running along +X.
c('alignFloor', { x: 900, y: 900 }, { x: 900, y: 1100 }, { x: 600, y: 100 }, { x: 800, y: 100 });
sent = __calls.filter(k => k[0] === 'align_walls');
msg = sent.length ? JSON.parse(sent[0][1]) : {};
ok('only the SELECTED walls are sent', msg.ids && msg.ids.length === 2 && msg.ids.indexOf('house') < 0, msg.ids);
ok('the target corner travels with the message', msg.tx === 600 && msg.ty === 100, msg);
ok('and the turn is up -> right, a quarter turn', close(msg.ang, -Math.PI / 2, 1e-9), msg.ang);

// the same, for blue walls, checked end to end
s('walls', []); s('selList', []);
s('pending', [{ sx: 900, sy: 900, ex: 900, ey: 1100, th: 8, ha: 'left', cat: 'exterior', ops: [] },
              { sx: 900, sy: 1100, ex: 1000, ey: 1100, th: 8, ha: 'left', cat: 'exterior', ops: [] }]);
c('alignFloor', { x: 900, y: 900 }, { x: 900, y: 1100 }, { x: 600, y: 100 }, { x: 800, y: 100 });
const P = g('pending');
ok('the picked corner lands on the target corner', close(P[0].sx, 600) && close(P[0].sy, 100), P[0]);
ok('the picked direction runs along the target direction', close(P[0].ex, 800) && close(P[0].ey, 100), P[0]);
ok('and the next wall turned with it', close(P[1].sx, 800) && close(P[1].sy, 100) && close(P[1].ex, 800) && close(P[1].ey, 0), P[1]);

// a selection of blue walls: the unselected blue wall stays
s('pending', [{ sx: 900, sy: 900, ex: 900, ey: 1100, th: 8, ha: 'left', cat: 'exterior', ops: [] },
              { sx: 0, sy: 0, ex: 240, ey: 0, th: 8, ha: 'left', cat: 'exterior', ops: [] }]);
s('selList', [{ type: 'pending', i: 0 }]);
c('alignFloor', { x: 900, y: 900 }, { x: 900, y: 1100 }, { x: 0, y: 0 }, { x: 1, y: 0 });
ok('an unselected blue wall does not move', g('pending')[1].sx === 0 && g('pending')[1].ex === 240, g('pending')[1]);
ok('the selected one did', close(g('pending')[0].ex, 200) && close(g('pending')[0].ey, 0), g('pending')[0]);
s('selList', []);

// --- TWO BUILDINGS ON ONE STOREY, NOTHING SELECTED (2026-09-24) ------------
// "When I added another building it undid the anchoring of the first and
// assembled the second." The corner he clicks names the building: every
// wall touching it (end to end, or an interior wall ending on the body of
// an exterior one) moves; the other building does not.
s('pending', []); s('pendingSketches', []); s('selList', []);
const house = [
  { id: 'h1', sx: 0, sy: 0, ex: 240, ey: 0 }, { id: 'h2', sx: 240, sy: 0, ex: 240, ey: 180 },
  { id: 'h3', sx: 240, sy: 180, ex: 0, ey: 180 }, { id: 'h4', sx: 0, sy: 180, ex: 0, ey: 0 },
  { id: 'h5', sx: 120, sy: 0, ex: 120, ey: 180 }];               // interior wall, T at both ends
const adu = [
  { id: 'a1', sx: 900, sy: 900, ex: 1100, ey: 900 }, { id: 'a2', sx: 1100, sy: 900, ex: 1100, ey: 1050 },
  { id: 'a3', sx: 1100, sy: 1050, ex: 900, ey: 1050 }, { id: 'a4', sx: 900, sy: 1050, ex: 900, ey: 900 }];
house.concat(adu).forEach(w => { w.th = 5; w.ha = 'left'; w.cat = 'exterior'; w.ops = []; });
s('walls', house.concat(adu));
__calls.length = 0;
c('alignFloor', { x: 900, y: 900 }, { x: 1100, y: 900 }, { x: 600, y: 100 }, { x: 800, y: 100 });
sent = __calls.filter(k => k[0] === 'align_walls');
msg = sent.length ? JSON.parse(sent[0][1]) : {};
ok('the corner names the building: only the ADU walls are sent',
   msg.ids && msg.ids.length === 4 && msg.ids.every(i => i[0] === 'a'), msg.ids);

// the corner on the house: the whole house including its interior wall
__calls.length = 0;
c('alignFloor', { x: 0, y: 0 }, { x: 240, y: 0 }, { x: 0, y: 0 }, { x: 1, y: 0 });
sent = __calls.filter(k => k[0] === 'align_walls');
msg = sent.length ? JSON.parse(sent[0][1]) : {};
ok('the house goes as one, T-joined interior wall included',
   msg.ids && msg.ids.length === 5 && msg.ids.indexOf('h5') >= 0 && msg.ids.every(i => i[0] === 'h'), msg.ids);

// the mitered OUTER corner is what he actually clicks - a thickness off the drawn end
__calls.length = 0;
c('alignFloor', { x: -5, y: -5 }, { x: 240, y: -5 }, { x: 0, y: 0 }, { x: 1, y: 0 });
sent = __calls.filter(k => k[0] === 'align_walls');
msg = sent.length ? JSON.parse(sent[0][1]) : {};
ok('the outer band corner still finds the building', msg.ids && msg.ids.length === 5, msg.ids);

// a corner on no wall at all: the whole level, as before
__calls.length = 0;
c('alignFloor', { x: 5000, y: 5000 }, { x: 5100, y: 5000 }, { x: 0, y: 0 }, { x: 1, y: 0 });
sent = __calls.filter(k => k[0] === 'align_walls');
msg = sent.length ? JSON.parse(sent[0][1]) : {};
ok('a point on no wall moves the whole level', msg.ids && msg.ids.length === 9, msg.ids);

// --- NUMBERED ANCHORS, his design (2026-09-24): "like a walkie-talkie" -----
// Click a corner, type a number, Enter. A new number = this corner becomes
// anchor N (nothing moves). An existing number = the building under the
// corner goes to anchor N. 0 is always the origin.
s('anchors', {}); s('selList', []); s('pending', []); s('pendingSketches', []);
s('walls', house.concat(adu));
__calls.length = 0;
let r = c('anchorCommit', '1', { x: 900, y: 900 });      // ADU ground floor names its corner "1"
ok('a new number defines the anchor and moves nothing', r === 'set' && __calls.filter(k => k[0] === 'align_walls').length === 0, [r, __calls.map(k => k[0])]);
ok('the anchor is remembered', g('anchors')['1'] && g('anchors')['1'].x === 900 && g('anchors')['1'].y === 900, g('anchors'));

// "floor 2" of the ADU, drawn somewhere else: same corner, same number
s('pending', [{ sx: 3000, sy: 3000, ex: 3200, ey: 3000, th: 5, ha: 'left', cat: 'exterior', ops: [] },
              { sx: 3200, sy: 3000, ex: 3200, ey: 3150, th: 5, ha: 'left', cat: 'exterior', ops: [] }]);
__calls.length = 0;
r = c('anchorCommit', '1', { x: 3000, y: 3000 });
ok('an existing number moves the building under the corner', r === 'moved', r);
ok('  onto the anchor, as a straight shift', close(g('pending')[0].sx, 900) && close(g('pending')[0].sy, 900) && close(g('pending')[1].ey, 1050), g('pending'));
ok('  and the house on the level was not sent', __calls.filter(k => k[0] === 'align_walls').length === 0, __calls.map(k => k[0]));

// 0 is the origin without anyone defining it
s('pending', [{ sx: 3000, sy: 3000, ex: 3200, ey: 3000, th: 5, ha: 'left', cat: 'exterior', ops: [] }]);
r = c('anchorCommit', '0', { x: 3000, y: 3000 });
ok('0 is always the origin', r === 'moved' && close(g('pending')[0].sx, 0) && close(g('pending')[0].sy, 0), g('pending')[0]);

// the same corner again: nothing to do
r = c('anchorCommit', '1', { x: 900, y: 900 });
ok('a corner already on its anchor is left alone', r === 'same', r);

// anchors survive closing the editor: they ride in the draft
const dj = JSON.parse(c('draftJson'));
ok('the draft carries the anchors', dj.anchors && dj.anchors['1'] && dj.anchors['1'].x === 900, dj.anchors);
s('anchors', {});
c('restoreDraft', JSON.stringify({ pending: [], sketches: [], guides: [], dims: [], anchors: { '2': { x: 10, y: 20 } } }));
ok('and come back on reopen', g('anchors')['2'] && g('anchors')['2'].y === 20, g('anchors'));

// --- THE REAL PATH: button, click, keyboard (2026-09-24) -------------------
// The pure function passed and the tool did nothing: the number check was
// written /^\\d+$/ inside a Ruby heredoc, which eats the backslash, so "1"
// was never a number. His words: "it does nothing". So: the real keys.
const K = global.__listeners.__win.keydown[0];
const key = (k) => K({ key: k, target: { tagName: 'CANVAS' }, preventDefault() {} });
s('walls', [{ id: 'k1', sx: 0, sy: 0, ex: 240, ey: 0, th: 5, ha: 'left', cat: 'exterior', ops: [] }]);
s('pending', []); s('anchors', {}); s('selList', []); s('typed', '');
c('toggleOriginMode');
ok('the button arms the tool', g('originMode') === true);
c('originClick', { x: 0, y: 0 });
key('1');
ok('a digit is taken as the anchor number', g('typed') === '1', g('typed'));
key('Enter');
ok('Enter defines the anchor', g('anchors')['1'] && g('anchors')['1'].x === 0, g('anchors'));
ok('and the tool is put down', g('originMode') === false);
// floor 2: the same corner elsewhere, "1", Enter
s('pending', [{ sx: 3000, sy: 3000, ex: 3240, ey: 3000, th: 5, ha: 'left', cat: 'exterior', ops: [] }]);
c('toggleOriginMode'); c('originClick', { x: 3000, y: 3000 }); key('1'); key('Enter');
ok('Enter with an existing number moves the building', close(g('pending')[0].sx, 0) && close(g('pending')[0].sy, 0), g('pending')[0]);
ok('and leaves a message saying so', !!g('anchorMsg') && g('anchorMsg').indexOf('1') >= 0, g('anchorMsg'));

process.exit(fails ? 1 : 0);
