// t37 - typing a measurement into the 2D editor (2026-08-14).
//
// The user, about a wall length: "I tried to enter the exact measurement and it
// only lets me write feet, not inches."
//
// The old reader knew three fixed spellings and returned nothing for anything
// else. Two things followed from that:
//
//   * a length copied off the drawing - where it is printed 11'-3.5" - has a
//     hyphen in it, matched nothing, and silently did nothing at all;
//   * a bare 11, which is how anyone asks for an eleven foot wall, was read as
//     eleven INCHES, so the wall collapsed to nothing and it looked like the
//     box refused inches.
//
// The bare number is the one real decision here and the user made it: for a
// WALL a lone number is feet; for an opening or a thickness it stays inches,
// because a 30 inch door is never typed as 2.5.

const fs = require('fs');
const path = require('path');

const JS = fs.readFileSync(path.join(__dirname, 'out.js'), 'utf8');

let fails = 0;
function ok(n, c, x) {
  console.log((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : '   << ' + JSON.stringify(x)));
  if (!c) fails++;
}

// lift the two routines out of the editor and run the real thing
function lift(name, sig) {
  const at = JS.indexOf('function ' + sig);
  if (at < 0) return null;
  let depth = 0, i = JS.indexOf('{', at);
  for (let j = i; j < JS.length; j++) {
    if (JS[j] === '{') depth++;
    if (JS[j] === '}') { depth--; if (!depth) return JS.slice(at, j + 1); }
  }
  return null;
}
const parseSrc = lift('parseLen', 'parseLen(s, bare)');
const fmtSrc = lift('fmtLen', 'fmtLen(v)');
ok('the reader takes a unit for a bare number', !!parseSrc,
   'parseLen(s, bare) is not there');
ok('the writer is still there', !!fmtSrc);
eval(parseSrc);
eval(fmtSrc);

function is(input, bare, want, why) {
  const got = parseLen(input, bare);
  const good = want === null ? got === null : Math.abs(got - want) < 1e-9;
  ok(why, good, { input: input, bare: bare, got: got, want: want });
}

// ------------------------------------------------------- the spellings
is('42', null, 42, 'a bare number is inches where inches are asked for');
is('42"', null, 42, 'inches with the mark');
is('42 in', null, 42, 'inches spelt out');
is("3'", null, 36, 'feet with the mark');
is('3 ft', null, 36, 'feet spelt out');
is("3' 6", null, 42, 'feet and inches');
is('3\'6"', null, 42, 'no space between them');
is('3\'-6"', null, 42, 'a hyphen between them - the way the drawing prints it');
is('3 6', null, 42, 'two numbers with a space');
is('3 ft 6 in', null, 42, 'both spelt out');
is('3 FT 6 IN', null, 42, 'shouted');
is('  3ft6in  ', null, 42, 'run together, with space around it');

// ------------------------------------------------------------ fractions
is('3 1/2"', null, 3.5, 'three and a half inches, not three feet and a half');
is('1/2', null, 0.5, 'half an inch on its own');
is('1/2"', null, 0.5, 'with the mark');
is('11\' 6 1/2"', null, 138.5, 'feet, inches and a fraction together');
is('1/2', 'ft', 0.5, 'a lone fraction is inches even where feet are asked for');
is('1/0', null, 0, 'nobody divides by nothing');

// ------------------------------------------- the bare number, per the user
is('11', 'ft', 132, 'a lone number is FEET when a wall length is asked for');
is('11', 'in', 11, 'and INCHES when an opening is');
is('11', null, 11, 'inches is what happens if nobody says');
is('11.5', 'ft', 138, 'half a foot works too');
is('30', 'in', 30, 'a thirty inch door is still thirty inches');
is('30', 'ft', 360, 'and thirty feet if that is really what was asked for');
is("11'", 'ft', 132, 'the mark and the setting agree');
is('11"', 'ft', 11, 'the mark wins over the setting - he said inches');
is('11 6', 'ft', 138, 'two numbers are always feet then inches');

// ------------------------------------------------------------- rubbish in
is('', null, null, 'nothing in, nothing out');
is('   ', null, null, 'and nothing but spaces');
is(null, null, null, 'and nothing at all');
is('abc', null, null, 'words are not a measurement');
is('3 x 6', null, null, 'nor is a multiplication');
is('-6', null, -6, 'a minus is kept - it is used for moving things back');
is("-3' 6", null, -42, 'on feet and inches too');

// -------------------------------------------------- what is written, is read
// Whatever fmtLen prints on the drawing must read back as the same number.
[0.5, 6, 11.5, 42, 126, 135.5, 240, 372.5].forEach(function (v) {
  const printed = fmtLen(v);
  ok('the drawing prints ' + printed + ' and reads it back the same',
     Math.abs(parseLen(printed) - v) < 0.01, { printed: printed, back: parseLen(printed) });
});

// ----------------------------------------------- and the callers ask correctly
ok('the wall length box asks for feet',
   /function applyWallLen\(\)[\s\S]{0,400}parseLen\(document\.getElementById\('selLen'\)\.value, 'ft'\)/
     .test(JS), 'applyWallLen is not passing ft');
ok('the dimension a wall shows asks for feet, an opening for inches',
   JS.includes("parseLen(v, isWall ? 'ft' : 'in')"),
   'editDimTag is not choosing the unit');
ok('and the question on screen says which',
   /מספר לבד = רגל/.test(JS) && /מספר לבד = אינץ/.test(JS),
   'the prompt does not say what a lone number means');

// A door width must NOT become feet. This is the thing that would quietly
// ruin a drawing, so it is pinned.
ok('an opening width is still read in inches',
   /function openW\(\)[\s\S]{0,300}parseLen\(document\.getElementById\('dW'\)\.value\)/.test(JS),
   'openW started passing a unit and would turn a 30 inch door into 30 feet');
ok('so is the wall thickness',
   /parseLen\(document\.getElementById\('selTh'\)\.value\)/.test(JS));

// -------------------------------------------------- the green arrow is a button
ok('the arrow that says which end moves can be pressed to type a length',
   /dimTags\.push\(\{ x: ax - 13, y: ay - 13[\s\S]{0,160}kind: 'wallLen'/.test(JS),
   'the arrow head is not registered as clickable');
ok('and the corner is still grabbed first, so dragging it is untouched',
   JS.indexOf('var he = hitWallEnd(') < JS.indexOf('var dt = hitDimTag('),
   'the dimension tag is now tested before the corner');
ok('the arrow head sits clear of the corner grab',
   26 > 12 + 13 - 13, 'the arrow is 26px out and the corner is grabbed within 12');

// ------------------------------------- and the green handle can simply be pulled
// "It does not work if I hold the green one and try to move it." It never had:
// clicking a corner only ever CHOSE which end would move. Now the red one still
// chooses, and the green one stretches.
ok('grabbing the pinned end still just chooses which end moves',
   /if \(he !== movingEnd\) \{ setMovingEnd\(he\); return; \}/.test(JS),
   'the red end no longer switches the moving end');
ok('grabbing the green end starts a stretch',
   /dragEnd = \{ w:w0, b:b0, len:b0\.len, start:b0\.len/.test(JS),
   'the green end does not start a drag');
ok('the stretch only runs along the wall, so it cannot go crooked',
   /var alen = \(cursor\.x - fxp\.x\) \* dragEnd\.b\.ux \* sgn \+/.test(JS),
   'the drag is not projected onto the wall direction');
ok('a wall cannot be pulled shorter than six inches',
   (JS.match(/dragEnd\.len = Math\.max\(6,/g) || []).length >= 1);
ok('the model hears about it once, on release',
   /function finishEndDrag\(\)[\s\S]{0,700}sketchup\.set_wall_length/.test(JS),
   'the length is not committed when the mouse is let go');
ok('and not at all if it did not really move',
   /if \(!d\.moved \|\| Math\.abs\(d\.len - d\.start\) < 0\.05\) \{ draw\(\); return; \}/.test(JS));
ok('a blue pending wall is stretched too, without touching the model',
   /if \(d\.pi != null\) \{ setPendingLength\(d\.pi, d\.len\); return; \}/.test(JS));
ok('a length typed mid-pull is read in feet',
   /parseLen\(typed\.replace\('-', ''\), dragEnd \? 'ft' : 'in'\)/.test(JS),
   'typing during the stretch is not asking for feet');
ok('the drag handlers know a stretch counts as a drag',
   (JS.match(/&& !dragEnd\) return;/g) || []).length === 2,
   'pointermove or mousemove will stop firing mid-pull');
ok('and switching tools drops a half-pulled wall',
   /function cancelOps\(\)[\s\S]{0,600}dragEnd = null;/.test(JS));

console.log(fails ? `\n*** ${fails} FAILED ***` : '\nALL PASS');
process.exit(fails ? 1 : 0);
