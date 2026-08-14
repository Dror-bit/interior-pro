// t38 - Escape always ends up in Select (2026-08-14).
//
// The user: "if I press ESC it should automatically go to SELECT - Select
// should be the default of every state, unless it is in some other defined
// state."
//
// So Escape backs out one step at a time and Select is the floor it lands on.
// Whatever is half-done IS that other defined state and gets cancelled first;
// once nothing is half-done, the tool itself is put down.
//
// Before this, Escape ended the chain and left him standing in Wall mode, and
// the only way back was the Select button or the S key.
//
// This suite runs the editor's real key handler with the surrounding state
// faked, and watches which way it goes.

const fs = require('fs');
const path = require('path');

const JS = fs.readFileSync(path.join(__dirname, 'out.js'), 'utf8');

let fails = 0;
function ok(n, c, x) {
  console.log((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : '   << ' + JSON.stringify(x)));
  if (!c) fails++;
}

// The Escape arm of the key handler, lifted whole.
const at = JS.indexOf("if (ev.key === 'Escape') {");
ok('the Escape handler is where it was', at > 0);
let depth = 0, end = -1;
for (let i = JS.indexOf('{', at); i < JS.length; i++) {
  if (JS[i] === '{') depth++;
  if (JS[i] === '}') { depth--; if (!depth) { end = i; break; } }
}
const ESC = JS.slice(at, end + 1);

// Run it with everything around it faked, and report where it went.
function press(state) {
  const s = Object.assign({
    guideMode: false, rotOp: null, moveOp: null, offOp: null,
    ghostCopy: null, ghostOpen: null, dimPlace: null,
    typed: '', drawing: false, curLine: null, dragEnd: null,
    arcPts: [], circC: null, measA: null,
    mode: 'sel', rubber: { x0: 1 }, dragSym: { id: 1 }, sel: { id: 1 }
  }, state);
  const did = [];
  const fn = new Function('ev', 'S', 'did', `
    with (S) {
      var toggleGuideMode = function(){ did.push('guide off'); };
      var rotCancel = function(){ did.push('rotate cancelled'); };
      var moveCancel = function(){ did.push('move cancelled'); };
      var offCancel = function(){ did.push('offset cancelled'); };
      var cancelDimPlace = function(){ did.push('dim cancelled'); };
      var cancelEndDrag = function(){
        if (!dragEnd) return false;
        did.push('stretch cancelled'); return true;
      };
      var setStatusHint = function(){};
      var updateVcb = function(){ did.push('number forgotten'); };
      var endChain = function(){ did.push('chain ended'); };
      var setMode = function(m){ did.push('mode ' + m); };
      var setSel = function(v){ if (v === null) did.push('selection dropped'); };
      var updateSelPanel = function(){};
      var draw = function(){};
      ${ESC}
    }
  `);
  fn({ key: 'Escape' }, s, did);
  return did;
}

function went(state, want, why) {
  const did = press(state);
  ok(why, did.indexOf(want) >= 0, { did: did, want: want });
}
function didNot(state, unwanted, why) {
  const did = press(state);
  ok(why, did.indexOf(unwanted) < 0, { did: did, unwanted: unwanted });
}

// -------------------------------------------- the half-done things go first
went({ guideMode: true, mode: 'wall' }, 'guide off', 'a guide being aimed is put away first');
didNot({ guideMode: true, mode: 'wall' }, 'mode sel', 'and the tool is left alone that time');
went({ rotOp: {}, mode: 'sel' }, 'rotate cancelled', 'a rotate in progress is cancelled');
went({ moveOp: {}, mode: 'sel' }, 'move cancelled', 'so is a move');
went({ offOp: {}, mode: 'sel' }, 'offset cancelled', 'so is an offset');
went({ dimPlace: {}, mode: 'sel' }, 'dim cancelled', 'so is a dimension being placed');
went({ dragEnd: { len: 100 }, mode: 'sel' }, 'stretch cancelled',
     'a wall being pulled by its green handle is let go of');
didNot({ dragEnd: { len: 100 }, mode: 'sel' }, 'selection dropped',
       'and the wall stays picked, so it can be pulled again');
went({ typed: "11'", mode: 'wall' }, 'number forgotten', 'a half typed number is forgotten');
didNot({ typed: "11'", mode: 'wall' }, 'mode sel', 'and that alone does not put the tool down');

// ------------------------------------------------ then the chain, then the tool
went({ drawing: true, mode: 'wall' }, 'chain ended', 'a wall being drawn ends its chain');
didNot({ drawing: true, mode: 'wall' }, 'mode sel',
       'and stays in the wall tool - one Escape does one thing');
went({ curLine: { pts: [{ x: 0, y: 0 }] }, mode: 'line' }, 'chain ended',
     'a line being drawn ends its chain too');
went({ arcPts: [{ x: 0, y: 0 }], mode: 'line' }, 'chain ended', 'and an arc');
went({ circC: { x: 0, y: 0 }, mode: 'line' }, 'chain ended', 'and a circle');
went({ measA: { x: 0, y: 0 }, mode: 'sel' }, 'chain ended', 'and the tape measure');

// ------------------------------------------- with nothing half-done: Select
['wall', 'door', 'win', 'line'].forEach(function (m) {
  went({ mode: m }, 'mode sel', 'Escape in ' + m + ' mode goes back to Select');
});
went({ mode: 'wall', curLine: { pts: [] } }, 'mode sel',
     'an empty line is not a chain, so it goes straight to Select');

// ------------------------------------------------ and Select drops the selection
went({ mode: 'sel' }, 'selection dropped', 'Escape in Select drops what is picked');
didNot({ mode: 'sel' }, 'mode sel', 'it does not switch to the mode it is already in');

// ------------------------------------------- twice out of a chain lands in Select
const twice = press({ drawing: true, mode: 'wall' })
  .concat(press({ drawing: false, mode: 'wall' }));
ok('two Escapes while drawing a wall: chain first, then Select',
   twice.indexOf('chain ended') === 0 && twice.indexOf('mode sel') > 0, twice);

// ------------------------------------------------- and it OPENS in Select
// "When I open the drawing I want it to be on Select by default."
//
// It said setMode('sel') and then setLineTool('line') to arm a default shape -
// and setLineTool jumps into Line mode on purpose, so a drawing tool can be
// clicked straight out of Select. The editor therefore opened with the Line
// tool live. The three lines have to run in this order.
const boot = JS.slice(JS.lastIndexOf("setLineTool('line');"));
ok('the editor opens in Select, not with a drawing tool armed',
   boot.indexOf("setMode('sel');") > 0 &&
   boot.indexOf("setMode('sel');") > boot.indexOf("setLinePreset('solid');"),
   boot.slice(0, 160));
ok('and the default shape is still set up for when he wants it',
   /setLineTool\('line'\);\s*\n\s*setLinePreset\('solid'\);/.test(JS));

// The Select button and the S key must still work - Escape is an addition,
// not a replacement.
ok('the Select button is still there', JS.includes("document.getElementById('modeSel')"));
ok('and the S shortcut still works', /ev\.code === 'KeyS'[\s\S]{0,80}mk = 'sel'/.test(JS));

console.log(fails ? `\n*** ${fails} FAILED ***` : '\nALL PASS');
process.exit(fails ? 1 : 0);
