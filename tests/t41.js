// t41 - the OTHER half of the corner angles: setting them (2026-08-14).
//
// He asked for two things and got one:
//
//   "I want to be able to EDIT them, because right now I specifically want
//    them all to be 90 - and of course I cannot."
//   "if I press the green arrow I want to be able to stretch the wall by hand"
//
// Both were written. Neither could be reached, for two separate reasons, and
// t39 did not notice because it only read the source for the DRAWING half.
//
//   1. draw() emptied the clickable-box list AFTER drawCornerAngles had
//      filled it. Every angle box was thrown away in the same frame it was
//      made, so pressing a number hit nothing.
//   2. hitWallEnd started with `sel.type !== 'wall' -> null`. A blue wall (one
//      not applied to the model yet) is sel.type 'pending', so grabbing its
//      green dot returned null and no drag ever began - even though the green
//      dot is drawn on blue walls exactly as on grey ones.
//
// This suite runs both hit-tests for real.

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

// ------------------------------------------------- 1. the list is emptied first
const drawSrc = lift('draw()');
ok('draw() empties the clickable boxes exactly once',
   (drawSrc.match(/dimTags = \[\];/g) || []).length === 1,
   (drawSrc.match(/dimTags = \[\];/g) || []).length);
ok('and it empties them BEFORE the corner angles are drawn, not after',
   drawSrc.indexOf('dimTags = [];') < drawSrc.indexOf('drawCornerAngles(all);') &&
   drawSrc.indexOf('dimTags = [];') > 0,
   { clear: drawSrc.indexOf('dimTags = [];'),
     angles: drawSrc.indexOf('drawCornerAngles(all);') });
ok('the selection is still drawn after the list is emptied, so its boxes live',
   drawSrc.indexOf('dimTags = [];') < drawSrc.indexOf('drawSelection();'));

// ------------------------------------- the angle box really survives a draw
const box = {
  console,
  showAngles: true,
  dimTags: [],
  walls: [], pending: [],
  ctx: {
    strokeStyle: '', fillStyle: '', lineWidth: 0, font: '',
    textAlign: '', textBaseline: '',
    beginPath() {}, arc() {}, stroke() {}, fillText() {}, save() {}, restore() {}
  },
  sx(v) { return v; },
  sy(v) { return -v; }
};
vm.createContext(box);
['wallCorners(all)', 'isRoundAngle(deg)', 'fmtAngle(deg)', 'drawCornerAngles(all)',
 'hitDimTag(px, py)', 'hitWallEnd(px, py)'].forEach(function (sig) {
  const src = lift(sig);
  ok('the editor still has ' + sig.split('(')[0], !!src, sig);
  vm.runInContext(src, box);
});
vm.runInContext('var ANGLE_ROUND = [0,15,22.5,30,45,60,90,120,135,150,180];' +
                'var ANGLE_TOL = 0.15;', box);

// an L that is 1.2 degrees out - his drawing, near enough
const L = [{ id: 'a', sx: 0, sy: 0, ex: 120, ey: 0, th: 5 },
           { id: 'b', sx: 120, sy: 0, ex: 122, ey: 96, th: 5 }];
box.walls = L;
vm.runInContext('dimTags = []; drawCornerAngles(walls);', box);
ok('drawing the corner leaves a clickable box behind',
   box.dimTags.length === 1, box.dimTags);
const tag = box.dimTags[0];
ok('and the box is an angle box, carrying both walls and which end each meets by',
   tag && tag.kind === 'angle' && tag.data.wa && tag.data.wb &&
   !!tag.data.ea && !!tag.data.eb, tag && tag.kind);
ok('pressing the middle of the number finds it',
   vm.runInContext('hitDimTag(' + (tag.x + tag.w / 2) + ',' + (tag.y + tag.h / 2) + ')', box)
     !== null);
ok('pressing far away finds nothing',
   vm.runInContext('hitDimTag(4000, 4000)', box) === null);
ok('and a pressed angle box is sent off to be edited, not to be renamed',
   /if \(t\.kind === 'angle'\) \{ editAngle\(t\.data\); return; \}/.test(lift('editDimTag(t)')));

// ------------------------------------------- 2. the green handle on a blue wall
box.pending = [{ id: null, sx: 0, sy: 0, ex: 240, ey: 0, th: 5 }];
box.walls = [{ id: 'w1', sx: 0, sy: 300, ex: 240, ey: 300, th: 5 }];

vm.runInContext("sel = { type:'wall', w: walls[0] };", box);
ok('the green handle on a grey wall works as it always did',
   vm.runInContext('hitWallEnd(240, -300)', box) === 'end',
   vm.runInContext('hitWallEnd(240, -300)', box));

vm.runInContext("sel = { type:'pending', i:0 };", box);
ok('and now it works on a BLUE wall too - which is the one he was pulling',
   vm.runInContext('hitWallEnd(240, 0)', box) === 'end',
   vm.runInContext('hitWallEnd(240, 0)', box));
ok('its other end answers too',
   vm.runInContext('hitWallEnd(0, 0)', box) === 'start',
   vm.runInContext('hitWallEnd(0, 0)', box));
ok('and the middle of the wall is not an end',
   vm.runInContext('hitWallEnd(120, 0)', box) === null);

vm.runInContext("sel = { type:'pending', i:9 };", box);
ok('a selection pointing at a wall that is gone does not crash it',
   vm.runInContext('hitWallEnd(0, 0)', box) === null);
vm.runInContext('sel = null;', box);
ok('nor does no selection at all',
   vm.runInContext('hitWallEnd(0, 0)', box) === null);

// --------------------------------- and the drag really starts from that hit
const md = JS.slice(JS.indexOf("cv.addEventListener('mousedown'"));
ok('grabbing the end of a blue wall starts a drag, with its index kept',
   /dragEnd = \{ w:w0, b:b0, len:b0\.len, start:b0\.len, moved:false,\s*\n?\s*pi:\(sel\.type === 'pending' \? sel\.i : null\) \};/.test(md),
   'the mousedown no longer arms dragEnd the same way');
ok('letting go of a blue wall changes it on the canvas, not in the model',
   /if \(d\.pi != null\) \{ setPendingLength\(d\.pi, d\.len\); return; \}/.test(lift('finishEndDrag()')));
ok('and that change goes on the undo list like everything else',
   /histLocal\(/.test(lift('setPendingLength(idx, len)')));

console.log(fails ? `\n*** ${fails} FAILED ***` : '\nALL PASS');
process.exit(fails ? 1 : 0);
