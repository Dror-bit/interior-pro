// t45 - Apply to Model may not throw the drawing away (2026-08-15).
//
// WHAT HAPPENED
// The user traced a whole site over a photo, saved, came back the next day,
// and pressed "Apply to Model". The build produced nothing. sketchesDone()
// cleared the canvas anyway - it never looked at the count Ruby sent back -
// and then saveDraft(true) wrote the now-empty draft over the good one. The
// work and its only copy went in the same instant, with no message.
//
// This suite RUNS both callbacks. Reading the source would not do: the whole
// bug was one line that ran when it should not have.

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

function box() {
  const b = {
    console,
    pendingSketches: [{ pts: [0, 0, 10, 0] }, { pts: [0, 0, 0, 10] }],
    pending: [{ id: null, sx: 0, sy: 0, ex: 120, ey: 0 }],
    editHist: [],
    drafts: [],
    alerts: [],
    busy: [],
    drawn: 0,
    applyBusy(on) { b.busy.push(on); },
    saveDraft(force) { b.drafts.push(force); },
    updateStatus() {},
    draw() { b.drawn++; },
    alert(m) { b.alerts.push(m); }
  };
  vm.createContext(b);
  ['sketchesDone(n)', 'applyDone(n)'].forEach(function (sig) {
    const src = lift(sig);
    ok('the editor still has ' + sig.split('(')[0], !!src, sig);
    vm.runInContext(src, b);
  });
  return b;
}

// ------------------------------------------------- shapes: the build failed

let b = box();
vm.runInContext('sketchesDone(0)', b);
ok('SHAPES: a failed build does NOT clear the drawing',
   b.pendingSketches.length === 2, b.pendingSketches.length);
ok('SHAPES: and it does NOT write a draft over the good one',
   b.drafts.length === 0, b.drafts);
ok('SHAPES: the user is told, instead of nothing happening',
   b.alerts.length === 1, b.alerts);
ok('SHAPES: the busy button is released so he can try again',
   b.busy[b.busy.length - 1] === false, b.busy);

// Ruby can also answer with nothing at all if something went very wrong.
b = box();
vm.runInContext('sketchesDone(undefined)', b);
ok('SHAPES: no answer at all counts as a failure, not a success',
   b.pendingSketches.length === 2 && b.drafts.length === 0,
   [b.pendingSketches.length, b.drafts.length]);
b = box();
vm.runInContext('sketchesDone(null)', b);
ok('SHAPES: a null answer likewise', b.pendingSketches.length === 2);

// ------------------------------------------------- shapes: the build worked

b = box();
vm.runInContext('sketchesDone(2)', b);
ok('SHAPES: a full success DOES clear the drawing',
   b.pendingSketches.length === 0, b.pendingSketches.length);
ok('SHAPES: and saves the draft', b.drafts.length === 1, b.drafts);
ok('SHAPES: silently - a success needs no popup', b.alerts.length === 0, b.alerts);

// ------------------------------------------------- shapes: only some got in

b = box();
vm.runInContext('sketchesDone(1)', b);
ok('SHAPES: a partial success is SAID OUT LOUD', b.alerts.length === 1, b.alerts);
ok('SHAPES: the message names both numbers',
   /1/.test(b.alerts[0]) && /2/.test(b.alerts[0]), b.alerts[0]);

// -------------------------------------------------------------- walls

b = box();
vm.runInContext('applyDone(0)', b);
ok('WALLS: a failed build leaves the blue walls alone',
   b.pending.length === 1, b.pending.length);
ok('WALLS: and writes no draft', b.drafts.length === 0, b.drafts);
ok('WALLS: and says so', b.alerts.length === 1, b.alerts);

b = box();
vm.runInContext('applyDone(1)', b);
ok('WALLS: a success clears them', b.pending.length === 0, b.pending.length);
ok('WALLS: and saves the draft', b.drafts.length === 1, b.drafts);
ok('WALLS: with no popup', b.alerts.length === 0, b.alerts);

// ------------------------------------------------------------- the shape of it
//
// The order matters as much as the condition: clearing before saving is what
// makes an empty draft. If the clear ever moves back above the guard, the bug
// is back even if the guard is still there.
const s = lift('sketchesDone(n)');
ok('the guard comes BEFORE the line that clears the drawing',
   s.indexOf('n <= 0') > 0 && s.indexOf('n <= 0') < s.indexOf('pendingSketches = []'),
   { guard: s.indexOf('n <= 0'), clear: s.indexOf('pendingSketches = []') });
const a = lift('applyDone(n)');
ok('same for the walls',
   a.indexOf('n <= 0') > 0 && a.indexOf('n <= 0') < a.indexOf('pending = []'),
   { guard: a.indexOf('n <= 0'), clear: a.indexOf('pending = []') });

console.log(fails === 0 ? '\nALL PASS' : '\n*** ' + fails + ' FAILED ***');
process.exit(fails === 0 ? 0 : 1);
