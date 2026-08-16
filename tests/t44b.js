// t44 (file t44b to dodge the rt44 name) - right-click: wall angle vs the
// RED AXIS (2026-08-14).
//
// His ask, verbatim: "if I mark the wall and right-click it gives me the
// option to choose how many degrees the wall will be" - measured against the
// red axis (his choice from the options).
//
// The lesson this project keeps re-learning: written is not reachable. So
// this file walks the whole path - the right-click builds a menu row, the row
// runs setWallAxisAngle, the prompt's number becomes an aim point, and the
// aim point goes to the ONE door (set_wall_aim for a grey wall, a local swing
// for a blue one). And the degrees here must mean what the drawing label
// means, or 90 typed here and 90 watched while drawing would be two angles.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const JS = fs.readFileSync(path.join(__dirname, 'out.js'), 'utf8');

let fails = 0;
function ok(n, c, x) {
  console.log((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : '   << ' + JSON.stringify(x)));
  if (!c) fails++;
}
function near(a, b, tol) { return Math.abs(a - b) <= (tol === undefined ? 0.01 : tol); }

function lift(sig) {
  const at = JS.indexOf('function ' + sig);
  if (at < 0) return '';
  let d = 0;
  for (let i = JS.indexOf('{', at); i < JS.length; i++) {
    if (JS[i] === '{') d++;
    if (JS[i] === '}') { d--; if (!d) return JS.slice(at, i + 1); }
  }
  return '';
}

// ------------------------------------------------ a tiny live sandbox
const sent = [];
const box = {
  console,
  walls: [], pending: [],
  sel: null, selList: [],
  movingEnd: 'end',
  keepCorners: true,
  keepSel: null,
  promptAnswer: null,
  alerts: [],
  prompt(q, cur) { box.lastPromptDefault = cur; return box.promptAnswer; },
  alert(m) { box.alerts.push(m); },
  histLocal() { box.localHist = (box.localHist || 0) + 1; },
  histModel(w) { box.modelHist = w; },
  updateSelPanel() {}, updateStatus() {}, draw() {},
  fixedEndName() { return box.movingEnd === 'end' ? 'start' : 'end'; },
  sketchup: { set_wall_aim(json) { sent.push(JSON.parse(json)); } }
};
vm.createContext(box);
['wallScreenBearing(w)', 'setWallAxisAngle()'].forEach(function (sig) {
  const src = lift(sig);
  ok('the editor has ' + sig.split('(')[0], !!src, sig);
  vm.runInContext(src, box);
});

// ---------------------------------------- 1. the degrees mean what the label means
// The label writes aDeg = atan2(start.y - end.y, end.x - start.x). A wall
// drawn to the RIGHT is 0; drawn UP on screen (y decreasing) is 90.
box.walls = [{ id: 'w1', sx: 0, sy: 0, ex: 100, ey: 0, th: 5 }];
ok('a wall pointing right reads 0 against the red axis',
   near(vm.runInContext('wallScreenBearing(walls[0])', box), 0),
   vm.runInContext('wallScreenBearing(walls[0])', box));
box.walls = [{ id: 'w1', sx: 0, sy: 0, ex: 0, ey: -100, th: 5 }];
ok('and the label convention holds - the same formula, the same numbers',
   near(vm.runInContext('wallScreenBearing(walls[0])', box), 90),
   vm.runInContext('wallScreenBearing(walls[0])', box));

// ---------------------------------------- 2. a GREY wall goes through the door
box.walls = [{ id: 'w1', sx: 0, sy: 0, ex: 100, ey: 3, th: 5 }];   // 1.7 deg off
box.sel = { type: 'wall', w: box.walls[0] };
box.promptAnswer = '0';
sent.length = 0;
vm.runInContext('setWallAxisAngle()', box);
ok('typing 0 sends ONE message to the model', sent.length === 1, sent);
const m = sent[0];
ok('to the right wall', m && m.wall_id === 'w1', m);
ok('with the pinned end named, same as the length box',
   m && m.fixed === 'start', m && m.fixed);
ok('and the corner choice he set (Keep/Detach) rides along',
   m && m.keep === true, m && m.keep);
const L = Math.hypot(100, 3);
ok('the aim lands the far end ON the red axis at full length',
   m && near(m.ax, L, 1e-6) && near(m.ay, 0, 1e-6), m && [m.ax, m.ay]);
ok('the prompt offered the wall\'s CURRENT angle as the starting answer',
   /^358\.3$/.test(box.lastPromptDefault), box.lastPromptDefault);

// nearest-way-round: asking a left-pointing wall for 0 must not spin it
box.walls = [{ id: 'w2', sx: 0, sy: 0, ex: -100, ey: 2, th: 5 }];
box.sel = { type: 'wall', w: box.walls[0] };
sent.length = 0;
vm.runInContext('setWallAxisAngle()', box);
ok('a wall pointing LEFT asked for 0 stays pointing left (nearest way round)',
   sent.length === 1 && sent[0].ax < 0 && near(sent[0].ay, 0, 1e-6),
   sent[0] && [sent[0].ax, sent[0].ay]);

// cancel and nonsense must do nothing
sent.length = 0;
box.promptAnswer = null;
vm.runInContext('setWallAxisAngle()', box);
box.promptAnswer = 'abc';
vm.runInContext('setWallAxisAngle()', box);
ok('cancel or a non-number sends nothing at all', sent.length === 0, sent);

// ---------------------------------------- 3. a BLUE wall swings locally
box.pending = [{ sx: 0, sy: 0, ex: 200, ey: -5, th: 5 }];
box.sel = { type: 'pending', i: 0 };
box.promptAnswer = '90';
box.localHist = 0;
sent.length = 0;
vm.runInContext('setWallAxisAngle()', box);
const pw = box.pending[0];
const Lp = Math.hypot(200, 5);
ok('a blue wall is swung on the canvas, not sent to the model',
   sent.length === 0, sent);
ok('its pinned end stays put', pw.sx === 0 && pw.sy === 0, [pw.sx, pw.sy]);
ok('its moving end lands straight UP at full length',
   near(pw.ex, 0, 1e-6) && near(pw.ey, -Lp, 1e-6), [pw.ex, pw.ey]);
ok('and the swing went on the undo list first', box.localHist === 1, box.localHist);

// with the OTHER end pinned, the start swings instead
box.movingEnd = 'start';
box.pending = [{ sx: 0, sy: 0, ex: 200, ey: 0, th: 5 }];
box.sel = { type: 'pending', i: 0 };
box.promptAnswer = '0';
vm.runInContext('setWallAxisAngle()', box);
const pw2 = box.pending[0];
ok('with the red dot moved, the OTHER end is the one that swings',
   pw2.ex === 200 && pw2.ey === 0 && near(pw2.sy, 0, 1e-6), pw2);
box.movingEnd = 'end';

// ---------------------------------------- 4. ACCESSIBILITY - the menu path
const md = JS.slice(JS.indexOf("cv.addEventListener('mousedown'"));
const rc = md.slice(md.indexOf('if (ev.button === 2) {'),
                    md.indexOf('showMenu(ev.offsetX, ev.offsetY);'));
ok('the right-click hit-tests the wall under the cursor',
   /var hwR = hitWall\(pR\);/.test(rc) && /hitPending\(pR\)/.test(rc), rc.slice(0, 300));
ok('it SELECTS that wall before the menu opens',
   /setSel\(hwR \? \{ type:'wall', w:hwR\.w \} : \{ type:'pending', i:piR \}\);/.test(rc));
ok('and the menu row runs setWallAxisAngle',
   rc.indexOf('setWallAxisAngle') > -1, rc.indexOf('setWallAxisAngle'));
ok('showMenu grew an extra-rows argument for it',
   /function showMenu\(px, py, extra\)/.test(JS));
ok('the Ruby side has the set_wall_aim door',
   fs.readFileSync(path.join(__dirname, 'plan_editor.rb'), 'utf8')
     .includes("add_action_callback('set_wall_aim')"));
ok('and that door goes through stretch_wall!, not a second copy of it',
   /set_wall_aim.*?stretch_wall!\(wall, len, which, keep, aim\)/s.test(
     fs.readFileSync(path.join(__dirname, 'plan_editor.rb'), 'utf8')));

console.log(fails ? `\n*** ${fails} FAILED ***` : '\nALL PASS');
process.exit(fails ? 1 : 0);
