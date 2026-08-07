// t32 - keyboard shortcuts and BricsCAD-style guides (2026-08-07)
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };

const L = global.__listeners.__win.keydown[0];
const key = (code, k) => L({ code: code, key: k || '', target: { tagName: 'BODY' }, preventDefault() {} });
const angEl = () => document.getElementById('guideAng');

// ---- mode shortcuts: S select, D door, W window, L line ----
key('KeyL', 'l'); ok('L opens the line tools', g('mode') === 'line', g('mode'));
key('KeyS', 's'); ok('S goes back to select', g('mode') === 'sel', g('mode'));
key('KeyD', 'd'); ok('D opens doors', g('mode') === 'door', g('mode'));
key('KeyW', 'w'); ok('W opens windows', g('mode') === 'win', g('mode'));

// a half-typed length must NOT jump modes (Hebrew layout types ' on KeyW)
c('setMode', 'line'); s('typed', '5'); key('KeyW', 'w');
ok('a half-typed length is never stolen by a shortcut', g('mode') === 'line', g('mode'));
s('typed', '');

// the older "count then S = polygon sides" habit still works
c('setMode', 'line'); c('setLineTool', 'hex'); s('typed', '6'); key('KeyS', 's');
ok('6 then S still sets the polygon side count', g('polySides') === 6, g('polySides'));
s('typed', '');

// ---- O arms and disarms the guide tool ----
c('setMode', 'sel');
if (g('guideMode')) c('toggleGuideMode');
key('KeyO', 'o'); ok('O arms the guide tool', g('guideMode') === true);
key('KeyO', 'o'); ok('O disarms it again', g('guideMode') === false);

// ---- M starts a move on the current selection ----
c('setMode', 'sel');
s('sketches', []); s('pendingSketches', []);
g('pendingSketches').push({ pts: [0, 0, 40, 0], closed: false, style: 'solid', weight: 1, shape: 'line' });
const shp = { type: 'sketch', sk: g('pendingSketches')[0], kind: 'pending', i: 0 };
s('selList', [shp]); s('sel', shp);
key('KeyM', 'm');
ok('M starts a move', g('moveOp') !== null);
c('moveCancel');

// ---- guides: one click per direction ----
s('guides', []); s('selList', []); s('sel', null);
c('setGuideAim', 'h'); c('guideClick', { x: 10, y: 20 });
ok('the direction button also arms guide mode', g('guideMode') === true);
ok('horizontal guide from ONE click',
   g('guides').length === 1 && Math.abs(g('guides')[0].y2 - g('guides')[0].y1) < 1e-9, g('guides'));

s('guides', []); c('setGuideAim', 'v'); c('guideClick', { x: 10, y: 20 });
ok('vertical guide from ONE click',
   g('guides').length === 1 && Math.abs(g('guides')[0].x2 - g('guides')[0].x1) < 1e-9, g('guides'));

// ---- typed degrees build the line; U flips to the other diagonal ----
s('guides', []); angEl().value = '45'; c('setGuideAim', 'ang');
c('guideClick', { x: 0, y: 0 });
let gd = g('guides')[0];
ok('45 deg guide climbs one to one', Math.abs((gd.y2 - gd.y1) - (gd.x2 - gd.x1)) < 1e-6, gd);

key('KeyU', 'u');
ok('U flips 45 to 135', Number(angEl().value) === 135, angEl().value);
s('guides', []); c('guideClick', { x: 0, y: 0 });
gd = g('guides')[0];
ok('135 deg guide falls one to one', Math.abs((gd.y2 - gd.y1) + (gd.x2 - gd.x1)) < 1e-6, gd);
key('KeyU', 'u');
ok('U flips back to 45', Number(angEl().value) === 45, angEl().value);

s('guides', []); angEl().value = '30'; c('setGuideAim', 'ang');
key('KeyU', 'u');
ok('U mirrors any angle: 30 -> 150', Number(angEl().value) === 150, angEl().value);

// ---- a guide can be picked, moved, duplicated and deleted ----
s('guides', [{ x1: 0, y1: 50, x2: 1, y2: 50 }]);
if (g('guideMode')) c('toggleGuideMode');
c('setMode', 'sel');
const gh = c('hitGuide', { x: 80, y: 50 });
ok('a guide is pickable anywhere along it', gh && gh.type === 'guide', gh);
s('selList', [gh]); s('sel', gh);
c('startFreeMove'); c('moveApply', 0, 25);
ok('a guide moves with the selection', Math.abs(g('guides')[0].y1 - 75) < 1e-9, g('guides'));
c('moveCommit');
c('dupGuides');
ok('duplicate makes a second guide', g('guides').length === 2, g('guides').length);
c('moveCancel');
s('selList', [{ type: 'guide', g: g('guides')[0], i: 0 }]); s('sel', g('selList')[0]);
c('deleteSelected');
ok('delete removes just that guide', g('guides').length === 1, g('guides').length);
c('clearGuides');
ok('clear empties them all', g('guides').length === 0);

// ---- picking any tool ends whatever was running (no Escape first) ----
c('setGuideAim', 'h'); ok('guide tool armed', g('guideMode') === true);
c('setLineTool', 'line');
ok('picking a drawing tool drops guide mode on the spot',
   g('guideMode') === false && g('mode') === 'line', { gm: g('guideMode'), m: g('mode') });

s('pendingSketches', [{ pts: [0, 0, 40, 0], closed: false, style: 'solid', weight: 1, shape: 'line' }]);
const shp2 = { type: 'sketch', sk: g('pendingSketches')[0], kind: 'pending', i: 0 };
c('setMode', 'sel'); s('selList', [shp2]); s('sel', shp2);
c('startFreeMove'); ok('a move is running', g('moveOp') !== null);
c('setMode', 'line'); ok('switching tools cancels the move', g('moveOp') === null);

// R rotates the selection, the same way M moves it
c('setMode', 'sel'); s('selList', [shp2]); s('sel', shp2);
key('KeyR', 'r'); ok('R starts a rotate', g('rotOp') !== null);
c('rotCancel');

c('setGuideAim', 'v'); ok('guide armed again', g('guideMode') === true);
c('toggleGuideMode'); ok('the guide button still toggles off', g('guideMode') === false);
c('toggleGuideMode'); ok('and back on', g('guideMode') === true);
c('toggleGuideMode');

// ---- Apply to Model shows that it was pressed ----
c('applyBusy', true);
ok('apply button goes busy', document.getElementById('applyBtn').className === 'blue busy',
   document.getElementById('applyBtn').className);
c('applyBusy', false);
ok('apply button returns to normal',
   document.getElementById('applyBtn').className === 'blue' &&
   document.getElementById('applyBtn').textContent === 'Apply to Model');

// ---- single line vs polyline (2026-08-07) ----
s('scale', 1); s('walls', []); s('pending', []); s('sketches', []); s('guides', []);
s('pendingSketches', []); s('curLine', null);
c('setMode', 'line'); c('setLineTool', 'line');
c('addLinePoint', { x: 0, y: 0 });
c('addLinePoint', { x: 100, y: 0 });
c('addLinePoint', { x: 100, y: 60 });
ok('single-line tool: every click-pair is its own object',
   g('pendingSketches').length === 2, g('pendingSketches').map(function (q) { return q.pts; }));
ok('and the run keeps going from the last point',
   g('curLine') && g('curLine').pts.length === 1, g('curLine'));
c('undoLinePoint');
ok('undo walks back one segment', g('pendingSketches').length === 1, g('pendingSketches').length);
c('endLine');

s('pendingSketches', []); s('curLine', null);
c('setLineTool', 'poly');
c('addLinePoint', { x: 0, y: 0 });
c('addLinePoint', { x: 100, y: 0 });
c('addLinePoint', { x: 100, y: 60 });
ok('polyline keeps one growing object', g('curLine') && g('curLine').pts.length === 3, g('curLine'));
c('endLine');
ok('polyline lands as ONE object with 3 points',
   g('pendingSketches').length === 1 && g('pendingSketches')[0].pts.length === 6,
   g('pendingSketches'));

// ---- stretching a line by its end ----
s('pendingSketches', [{ pts: [0, 0, 100, 0], closed: false, style: 'solid', weight: 1, shape: 'line' }]);
const ln = { type: 'sketch', sk: g('pendingSketches')[0], kind: 'pending', i: 0 };
c('setMode', 'sel'); s('selList', [ln]); s('sel', ln);
const hv = c('hitSketchVertex', { x: 100, y: 0 });
ok('the end of a selected line is grabbable', hv && hv.i === 1, hv && { i: hv.i });
s('dragVert', { sk: ln.sk, i: 1, o: ln, pts: ln.sk.pts.slice(), moved: false });
c('handleMove', c('sx', 160), c('sy', 0));
ok('dragging the end stretches the line',
   Math.abs(g('pendingSketches')[0].pts[2] - 160) < 1, g('pendingSketches')[0].pts);
c('finishVertexDrag');
ok('the stretch ends cleanly', g('dragVert') === null);
c('undoAction');
ok('undo puts the old length back',
   Math.abs(g('pendingSketches')[0].pts[2] - 100) < 0.01, g('pendingSketches')[0].pts);

// ---- the measure tape locks to the axes (2026-08-07) ----
s('scale', 1); s('walls', []); s('pending', []); s('sketches', []);
s('pendingSketches', []); s('guides', []); s('measA', null); s('measB', null);
c('setMode', 'line'); c('setLineTool', 'measure');
c('lineToolClick', { x: 0, y: 0 });
s('cursor', { x: 100, y: 3 });
let mr = c('measureAim', { x: 100, y: 3 });
ok('a nearly flat tape locks flat', Math.abs(mr.y) < 1e-9 && g('measAxis') === 'x',
   { r: mr, ax: g('measAxis') });
s('cursor', { x: 2, y: 80 }); mr = c('measureAim', { x: 2, y: 80 });
ok('a nearly upright tape locks upright', Math.abs(mr.x) < 1e-9 && g('measAxis') === 'y',
   { r: mr, ax: g('measAxis') });
s('cursor', { x: 60, y: 60 }); mr = c('measureAim', { x: 60, y: 60 });
ok('a real diagonal is left alone', g('measAxis') === null, g('measAxis'));
s('shiftDown', true); mr = c('measureAim', { x: 60, y: 20 });
ok('Shift forces the stronger axis', Math.abs(mr.y) < 1e-9 && g('measAxis') === 'x',
   { r: mr, ax: g('measAxis') });
s('shiftDown', false);
s('cursor', { x: 100, y: 3 }); c('lineToolClick', { x: 100, y: 3 });
ok('the second click lands on the lock, not the raw cursor',
   Math.abs(g('measB').y) < 1e-9, g('measB'));

// ---- unapplied work survives closing the editor (2026-08-07) ----
s('pending', [{ sx: 0, sy: 0, ex: 100, ey: 0, th: 5, ha: 'left', cat: 'exterior' }]);
s('pendingSketches', [{ pts: [0, 0, 50, 50], closed: false, style: 'solid', weight: 1, shape: 'line' }]);
s('guides', [{ x1: 0, y1: 20, x2: 1, y2: 20 }]);
c('saveDraft', true);
const dcalls = global.__calls.filter(function (x) { return x[0] === 'save_draft'; });
ok('the draft is parked on the model', dcalls.length > 0);
const djson = dcalls[dcalls.length - 1][1];
s('pending', []); s('pendingSketches', []); s('guides', []);   // as if the editor closed
c('restoreDraft', djson);
ok('blue walls come back on reopen', g('pending').length === 1, g('pending'));
ok('unapplied shapes come back', g('pendingSketches').length === 1, g('pendingSketches'));
ok('helper lines come back', g('guides').length === 1, g('guides'));
ok('the wall keeps its numbers',
   g('pending')[0].ex === 100 && g('pending')[0].th === 5, g('pending')[0]);
c('applyDone', 1);
ok('applying empties the wall draft', g('pending').length === 0);
c('sketchesDone', 1);
ok('applying empties the shape draft', g('pendingSketches').length === 0);

console.log(fails ? '\n*** ' + fails + ' FAILED ***' : '\nALL PASS');
process.exit(fails ? 1 : 0);
