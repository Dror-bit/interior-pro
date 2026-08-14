// t39 - the angle at every corner (2026-08-14).
//
// The user: "a lot of the time I think I am pointing in the right direction,
// and then I do the 3D and see the walls are not straight - I have to see the
// degrees on the drawing, and be able to set them."
//
// This is the first half: SEEING. Every corner where two walls meet says what
// angle it is, all the time - he asked for always, not only when a wall is
// picked, because the whole point is to notice a crooked corner without going
// looking for it. A round angle is written small and grey; anything else is
// red, because that is the one worth catching.
//
// Right-click on empty paper hides them once he has finished checking.

const fs = require('fs');
const path = require('path');

const JS = fs.readFileSync(path.join(__dirname, 'out.js'), 'utf8');

let fails = 0;
function ok(n, c, x) {
  console.log((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : '   << ' + JSON.stringify(x)));
  if (!c) fails++;
}

// Lift the maths out of the editor and run the real thing.
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
const ROUND = JS.match(/var ANGLE_ROUND = (\[[^\]]*\]);/);
const TOL = JS.match(/var ANGLE_TOL = ([\d.]+);/);
ok('the list of round angles is there', !!ROUND, 'ANGLE_ROUND is missing');
ok('and a tolerance to go with it', !!TOL, 'ANGLE_TOL is missing');
const ANGLE_ROUND = eval(ROUND[1]);
const ANGLE_TOL = parseFloat(TOL[1]);
eval(lift('wallCorners(all)'));
eval(lift('isRoundAngle(deg)'));
eval(lift('fmtAngle(deg)'));

const W = (sx, sy, ex, ey) => ({ sx, sy, ex, ey, th: 5 });

// ------------------------------------------------------------ a square room
let c = wallCorners([W(0, 0, 120, 0), W(120, 0, 120, 96),
                     W(120, 96, 0, 96), W(0, 96, 0, 0)]);
ok('a four wall room has four corners', c.length === 4, c.length);
ok('and every one of them is ninety degrees',
   c.every(x => Math.abs(x.deg - 90) < 1e-6), c.map(x => x.deg));
ok('each corner is counted once, not once per wall',
   new Set(c.map(x => x.x + ',' + x.y)).size === 4, c.map(x => [x.x, x.y]));

// ------------------------------------------------ the thing he is looking for
c = wallCorners([W(0, 0, 120, 0), W(120, 0, 122, 96)]);
ok('a wall two inches out of square reads as not quite ninety',
   Math.abs(c[0].deg - 90) > 1 && Math.abs(c[0].deg - 90) < 2, c[0].deg);
ok('and it is NOT called a round angle', !isRoundAngle(c[0].deg), c[0].deg);

c = wallCorners([W(0, 0, 120, 0), W(120, 0, 120.5, 96)]);
ok('even half an inch out is caught', !isRoundAngle(c[0].deg), c[0].deg);
ok('while a true right angle is left alone', isRoundAngle(90));

// the angles a drawing is allowed to have
[0, 15, 22.5, 30, 45, 60, 90, 120, 135, 150, 180].forEach(function (a) {
  ok(a + ' degrees is a round angle', isRoundAngle(a));
});
[89.4, 91, 44, 46.5, 100, 133].forEach(function (a) {
  ok(a + ' degrees is not', !isRoundAngle(a));
});
ok('the tolerance is tighter than a hand can draw',
   ANGLE_TOL <= 0.25, ANGLE_TOL);

// ------------------------------------------------------------- odd shapes
c = wallCorners([W(0, 0, 120, 0), W(120, 0, 240, 0)]);
ok('two walls in a straight line read as 180, not as a corner',
   c.length === 1 && Math.abs(c[0].deg - 180) < 1e-6, c.map(x => x.deg));
ok('and the drawing leaves a straight run alone',
   /if \(c\.deg < 0\.5 \|\| c\.deg > 179\.5\) continue;/.test(JS),
   'a straight run would be drawn as a corner');

c = wallCorners([W(0, 0, 120, 0), W(0, 0, 0, 96)]);
ok('two walls starting at the same point are still a corner',
   c.length === 1 && Math.abs(c[0].deg - 90) < 1e-6, c.map(x => x.deg));

c = wallCorners([W(0, 0, 120, 0), W(120, 0, 0, 0)]);
ok('a wall folded back on itself reads as zero', Math.abs(c[0].deg) < 1e-6, c[0].deg);

c = wallCorners([W(0, 0, 120, 0), W(200, 0, 320, 0)]);
ok('walls that do not touch make no corner', c.length === 0, c.length);

c = wallCorners([W(0, 0, 120, 0), W(120.9, 0, 120.9, 96)]);
ok('within an inch still counts as the same corner', c.length === 1, c.length);
c = wallCorners([W(0, 0, 120, 0), W(122, 0, 122, 96)]);
ok('two inches apart does not', c.length === 0, c.length);

c = wallCorners([W(0, 0, 0.2, 0), W(0.2, 0, 0.2, 96)]);
ok('a wall too short to have a direction is skipped, not divided by zero',
   c.length === 0, c);

// a three way junction: three walls, three pairs, three angles
c = wallCorners([W(0, 0, 100, 0), W(100, 0, 100, 100), W(100, 0, 200, 0)]);
ok('three walls at one point give three angles', c.length === 3, c.length);
ok('and they add up the way angles round a point do',
   Math.abs(c.reduce((s, x) => s + x.deg, 0) - 360) < 1e-6,
   c.map(x => x.deg));

// ------------------------------------------------------------- how it reads
ok('a whole number of degrees is written without a decimal point',
   fmtAngle(90) === '90°', fmtAngle(90));
ok('and a fraction of one keeps a single place',
   fmtAngle(88.76) === '88.8°', fmtAngle(88.76));

// ------------------------------------------------------ always on, and hideable
ok('the angles are on by default', /var showAngles = true;/.test(JS));
ok('they are drawn with the walls, not only with a selection',
   /drawCornerAngles\(all\);/.test(JS) &&
   JS.indexOf('drawCornerAngles(all);') < JS.indexOf('function drawSelection()'),
   'drawCornerAngles is not in the main wall pass');
ok('a round corner is grey and a crooked one is red',
   /var col = round \? '#8a8f98' : '#e0392b';/.test(JS));
ok('and the crooked one is drawn heavier, so it catches the eye',
   /ctx\.lineWidth = round \? 1 : 1\.8;/.test(JS));
ok('the right button offers to hide them',
   /showMenu\(ev\.offsetX, ev\.offsetY\)/.test(JS) && /function toggleAngles\(\)/.test(JS));
ok('but while something is being drawn it still ends the chain',
   /if \(busy\) \{ endChain\(\); return; \}/.test(JS),
   'right-click no longer ends a wall chain');
ok('and the menu goes away when you click elsewhere',
   /if \(el && el\.style\.display === 'block' && !el\.contains\(ev\.target\)\) hideMenu\(\);/.test(JS));

console.log(fails ? `\n*** ${fails} FAILED ***` : '\nALL PASS');
process.exit(fails ? 1 : 0);
