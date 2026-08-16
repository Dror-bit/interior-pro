// t43 - the drawing angle must not round away the truth (2026-08-14).
//
// He drew his building and the screen said a calm, round 180 degrees. It was
// 179.7666. He believed the number, and the whole plan was saved a quarter of
// a degree off the axis - four perfect 90 corners, and two inches of drift
// over forty-one feet. Measured, not guessed: axis_report.txt.
//
// His words: "a program that tells me 180 when it is 178 is a tragic mistake."
// He is right. The cause was one Math.round() on the label.
//
// So this suite pins the two things that make it impossible again:
//   - the number is shown to a tenth of a degree, never rounded to a whole one
//   - a direction that is NOT a round angle is drawn in the warning colour
//
// The tolerance is the same ANGLE_TOL the corner angles already use, on
// purpose: a direction and a corner must never disagree about what is square.

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

const box = { console };
vm.createContext(box);
['isRoundAngle(deg)', 'isRoundBearing(deg)', 'fmtAngle(deg)'].forEach(function (sig) {
  const src = lift(sig);
  ok('the editor has ' + sig.split('(')[0], !!src, sig);
  vm.runInContext(src, box);
});
vm.runInContext('var ANGLE_ROUND = [0,15,22.5,30,45,60,90,120,135,150,180];' +
                'var ANGLE_TOL = 0.15;', box);

const A = (d) => vm.runInContext('fmtAngle(' + d + ')', box);
const R = (d) => vm.runInContext('isRoundBearing(' + d + ')', box);

// ------------------------------------------------- 1. HIS number, exactly
ok('179.7666 is written out, not rounded to 180', A(179.7666) === '179.8°', A(179.7666));
ok('and it is NOT accepted as a round direction', R(179.7666) === false);
ok('89.7666 - his other two walls - is not accepted either', R(89.7666) === false);
ok('the interior wall at 90.0003 IS accepted, it really was straight',
   R(90.0003) === true);
ok('179.6708 - the short interior wall - is not accepted', R(179.6708) === false);

// ---------------------------------------------------- 2. the label tells the truth
ok('a whole number still reads clean', A(90) === '90°', A(90));
ok('a tenth is shown', A(45.3) === '45.3°', A(45.3));
ok('a hundredth is rounded to a tenth, not to a whole degree',
   A(179.96) === '180°' && A(179.9) === '179.9°', [A(179.96), A(179.9)]);
ok('half a degree out is visible in the text', A(180.5) === '180.5°', A(180.5));

// ------------------------------------------- 3. what counts as a round direction
[0, 15, 22.5, 30, 45, 60, 90, 120, 135, 150, 180].forEach(function (r) {
  ok('exactly ' + r + ' is round', R(r) === true);
  ok('and its mirror ' + (360 - r) + ' is round too', R(360 - r) === true);
  ok('and ' + (180 + r) + ' round as well', R(180 + r) === true);
});
ok('270 - straight down - is round', R(270) === true);
ok('359.99 wraps round to 0 and is round', R(359.99) === true);
ok('0.14 is inside the tolerance', R(0.14) === true);
ok('0.16 is outside it', R(0.16) === false);
ok('a direction the corner rule rejects is rejected here too, at every quarter',
   [10, 70, 100, 170, 200, 260].every(function (d) {
     return R(d) === false && vm.runInContext('isRoundAngle(' + (d % 180) + ')', box) === false;
   }));

// ------------------------------------ 4. ACCESSIBILITY - is any of this on screen?
//
// The whole reason to write this file. Proving isRoundBearing returns false
// proves nothing about what he sees while he is drawing a wall.
const drawSrc = lift('draw()');
ok('the drawing label no longer rounds the angle to a whole degree',
   !/Math\.round\(\(Math\.atan2\(startPt\.y/.test(drawSrc),
   'Math.round is back on the drawing angle');
ok('the drawing label asks fmtAngle for the text',
   /ctx\.fillText\(fmtLen\(dd\) \+ '  ∠' \+ fmtAngle\(aDeg\)/.test(drawSrc),
   drawSrc.slice(drawSrc.indexOf('var aDeg'), drawSrc.indexOf('var aDeg') + 400));
ok('it asks isRoundBearing whether to warn',
   /var aOk = isRoundBearing\(aDeg\);/.test(drawSrc));
ok('and a direction that is not round is painted the warning red, not the calm blue',
   /ctx\.fillStyle = aOk \? '#1a6ee0' : '#e0392b';/.test(drawSrc));
ok('the warning red is the same red the corner angles already use',
   (JS.match(/#e0392b/g) || []).length > 1);

console.log(fails ? `\n*** ${fails} FAILED ***` : '\nALL PASS');
process.exit(fails ? 1 : 0);
