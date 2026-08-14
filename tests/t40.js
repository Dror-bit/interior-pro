// t40 - the last action is the last action (2026-08-14).
//
// The user drew some walls, changed one wall's LENGTH, pressed Ctrl+Z to put
// it back - and the editor deleted the wall instead. His words:
//
//   "I want you to make sure you are not only fixing this bug, but that every
//    time I move something or add something or change something, THAT is the
//    last action. In short: the last action should be the last action and
//    nothing else."
//
// He was describing the architecture, not a slip. undoAction was a fixed order
// of PREFERENCE, not a history: look for a shape transform, else delete the
// newest blue wall, else a sketch, else ask SketchUp. Nothing recorded a change
// to a blue wall's length at all, so it fell through to "delete a wall".
//
// Now there is ONE list, in the order things happened, and Undo takes what is
// on top of it. This suite is about that order.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const JS = fs.readFileSync(path.join(__dirname, 'out.js'), 'utf8');

let fails = 0;
function ok(n, c, x) {
  console.log((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : '   << ' + JSON.stringify(x)));
  if (!c) fails++;
}

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

// ------------------------------------------------ the history, run for real
const box = {
  console,
  pending: [], pendingSketches: [], dims: [],
  sel: null, selList: [], keepSel: null,
  asked: [],
  sketchup: { undo_model() { box.asked.push('undo_model'); },
              update_sketches() {}, move_selection() {} },
  updateSelPanel() {}, updateStatus() {}, draw() {}
};
vm.createContext(box);
['histPush(entry)', 'localSnap()', 'localRestore(s)', 'histLocal(what)',
 'histModel(what)', 'histUndo()'].forEach(function (sig) {
  const src = lift(sig);
  ok('the history has ' + sig.split('(')[0], !!src, sig);
  vm.runInContext(src, box);
});
vm.runInContext('var editHist = []; var HIST_MAX = 200;', box);

const H = (code) => vm.runInContext(code, box);

// ------------------------------------------------------- the user's own case
H("pending.push({id:null, sx:0, sy:0, ex:480, ey:0, th:5});");
H("pending.push({id:null, sx:480, sy:0, ex:480, ey:322, th:5});");
ok('two walls drawn', box.pending.length === 2);

// he changes the first wall's length
H("histLocal('wall length'); pending[0].ex = 476;");
ok('the wall really changed', box.pending[0].ex === 476);

H("histUndo();");
ok('Undo put the LENGTH back', box.pending[0].ex === 480, box.pending[0].ex);
ok('and did NOT delete a wall - which is what it used to do',
   box.pending.length === 2, box.pending.length);
ok('and it did not go bothering SketchUp either',
   box.asked.length === 0, box.asked);

// ------------------------------------------------- everything, in order
H("editHist.length = 0; pending.length = 0; asked.length = 0;");
H("histLocal('draw'); pending.push({id:null, sx:0, sy:0, ex:120, ey:0, th:5});");
H("histLocal('draw'); pending.push({id:null, sx:120, sy:0, ex:120, ey:96, th:5});");
H("histLocal('length'); pending[1].ey = 200;");
H("histModel('set_wall_length');");
H("histLocal('length'); pending[0].ex = 300;");

ok('five actions are on the list', H('editHist.length') === 5, H('editHist.length'));

H("histUndo();");
ok('undo 1 takes back the last length change', box.pending[0].ex === 120, box.pending[0].ex);
H("histUndo();");
ok('undo 2 asks SketchUp, because that is what happened next back',
   box.asked.length === 1, box.asked);
ok('and it left the canvas alone while doing it', box.pending.length === 2);
H("histUndo();");
ok('undo 3 takes back the other length change', box.pending[1].ey === 96, box.pending[1].ey);
H("histUndo();");
ok('undo 4 takes back the second wall', box.pending.length === 1, box.pending.length);
H("histUndo();");
ok('undo 5 takes back the first', box.pending.length === 0, box.pending.length);
ok('and the list is empty', H('editHist.length') === 0);
ok('one more undo says so, so the caller can pass it on to SketchUp',
   H('histUndo()') === false);

// ------------------------------------------------ the photograph is a copy
H("editHist.length = 0; pending.length = 0;");
H("pending.push({id:null, sx:0, sy:0, ex:120, ey:0, th:5, syms:[{id:'d1', t:60, w:36}]});");
H("histLocal('move opening'); pending[0].syms[0].t = 90;");
H("histUndo();");
ok('a door inside a wall is photographed too, not shared',
   box.pending[0].syms[0].t === 60, box.pending[0].syms[0].t);

H("editHist.length = 0; pendingSketches.length = 0;");
H("pendingSketches.push({id:null, pts:[0,0,100,0], closed:false});");
H("histLocal('edit shape'); pendingSketches[0].pts[2] = 250;");
H("histUndo();");
ok('a shape is photographed by value, so undo really puts the points back',
   box.pendingSketches[0].pts[2] === 100, box.pendingSketches[0].pts);

H("editHist.length = 0; dims.length = 0;");
H("histLocal('add dim'); dims.push({x1:0, y1:0, x2:100, y2:0});");
H("histUndo();");
ok('a dimension comes off the same way', box.dims.length === 0, box.dims.length);

// ------------------------------------------------------- it does not grow forever
H("editHist.length = 0;");
H("for (var i = 0; i < 260; i++) histLocal('x');");
ok('the history stops at a couple of hundred steps',
   H('editHist.length') === 200, H('editHist.length'));

// ----------------------------------------------- and every action records one
// The point of the whole change: if an action does not go on the list, Undo
// will reach past it and take something the user did not ask it to take.
const MODEL_CALLS = ['place_window', 'place_door', 'set_wall_sag', 'set_thickness',
                     'set_wall_length', 'move_wall', 'move_opening',
                     'edit_opening_size', 'move_selection', 'delete_many',
                     'delete_wall', 'delete_opening', 'set_corner_angle',
                     'set_opening_t', 'apply_walls'];
MODEL_CALLS.forEach(function (c) {
  ok('changing the model with ' + c + ' is recorded',
     JS.includes("histModel('" + c + "')"), c);
});
['setPendingLength', 'placeGhostCopy'].forEach(function (f) {
  ok(f + ' photographs the canvas before it changes it',
     /histLocal\(/.test(lift(f + (f === 'setPendingLength' ? '(idx, len)' : '()'))), f);
});
ok('drawing a wall is recorded', /histLocal\('draw wall'\)/.test(JS));
ok('so is a curved one', /histLocal\('draw curved wall'\)/.test(JS));

// histUndo must not record its own undoing, or Undo would never finish.
const undoSrc = lift('histUndo()');
ok('undoing does not itself go on the list',
   !undoSrc.includes('histModel(') && !undoSrc.includes('histLocal('),
   'histUndo records while it undoes');

// ---------------------------------------------- and the queue jumpers are gone
const act = lift('undoAction()');
ok('Undo no longer prefers deleting the newest wall over anything else',
   !act.includes('undoPending()'), act);
ok('it takes what is on top of the history',
   act.includes('if (histUndo()) return;'), act);
ok('and only asks SketchUp when nothing of ours is left',
   act.lastIndexOf('sketchup.undo_model();') > act.indexOf('if (histUndo()) return;'),
   act);
ok('a half-drawn chain still backs off a point at a time',
   act.indexOf('undoLinePoint();') < act.indexOf('if (histUndo()) return;'), act);

console.log(fails ? `\n*** ${fails} FAILED ***` : '\nALL PASS');
process.exit(fails ? 1 : 0);
