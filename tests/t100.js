// t100 - a flipped exterior loop keeps its corners closed (2026-10-16).
// His words: "כשאני מצייר אותם הם בסדר אבל שאני שולח אותם ל3D אז הפינות נישברות".
// Measured (wall_trace.txt 17:18): 4 walls of a rectangle flipped, every end 7.07" from its neighbour.
const fs = require('fs'), path = require('path'), vm = require('vm');
const src = fs.readFileSync(path.join(__dirname, 'plan_editor.rb'), 'utf8');
const grab = (name) => { const m = src.match(new RegExp('function ' + name + '\\([\\s\\S]*?\\n            \\}\\n')); if (!m) throw new Error('no ' + name); return m[0]; };
const ctx = { Math };
vm.createContext(ctx);
vm.runInContext('var REJOIN_FLIPPED_CORNERS = true;\n' + grab('lineInt') + grab('rejoinFlippedCorners'), ctx);
let fails = 0;
const ok = (n, c, x) => { console.log((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : '   << ' + JSON.stringify(x))); if (!c) fails++; };
// what Ruby received at 17:18 (after the flip) and what was drawn before it
const ext = [
  { sx: 496.5, sy: 497.0, ex: 297.5, ey: 497.0, th: 5 },
  { sx: 501.5, sy: 338.5, ex: 501.5, ey: 492.0, th: 5 },
  { sx: 297.5, sy: 333.5, ex: 496.5, ey: 333.5, th: 5 },
  { sx: 292.5, sy: 492.0, ex: 292.5, ey: 338.5, th: 5 }];
const orig = [
  { sx: 297.5, sy: 492.0, ex: 496.5, ey: 492.0 },
  { sx: 496.5, sy: 492.0, ex: 496.5, ey: 338.5 },
  { sx: 496.5, sy: 338.5, ex: 297.5, ey: 338.5 },
  { sx: 297.5, sy: 338.5, ex: 297.5, ey: 492.0 }];
const n = ctx.rejoinFlippedCorners(ext, orig, [0, 1, 2, 3]);
ok('all 4 corners rejoined', n === 4, n);
const pts = ext.map(w => [[w.sx, w.sy], [w.ex, w.ey]]).flat();
const meets = pts.every(p => pts.filter(q => Math.hypot(p[0] - q[0], p[1] - q[1]) < 1e-6).length === 2);
ok('every end now sits on exactly one other end', meets, pts);
ok('the walls run outer corner to outer corner', ext[0].sx === 501.5 && ext[0].sy === 497 && ext[0].ex === 292.5, ext[0]);
ok('the lines stay where the flip put them (outer face)', ext.every(w => [497, 501.5, 333.5, 292.5].includes(w.sy === w.ey ? w.sy : w.sx)));
// nothing flipped -> nothing moves
const e2 = JSON.parse(JSON.stringify(orig)).map(w => Object.assign(w, { th: 5 }));
ok('no flip = nothing touched', ctx.rejoinFlippedCorners(e2, orig, []) === 0 && JSON.stringify(e2.map(w => [w.sx, w.sy])) === JSON.stringify(orig.map(w => [w.sx, w.sy])));
// a straight run is left alone
const e3 = [{ sx: 100, sy: 5, ex: 0, ey: 5, th: 5 }, { sx: 100, sy: 0, ex: 200, ey: 0, th: 5 }];
const o3 = [{ sx: 0, sy: 0, ex: 100, ey: 0 }, { sx: 100, sy: 0, ex: 200, ey: 0 }];
ok('two walls in a straight line are not joined', ctx.rejoinFlippedCorners(e3, o3, [0]) === 0);
ok('the call is wired into autoOrientExterior', src.includes('var rejoined = rejoinFlippedCorners(ext, orig, flips);'));
console.log(fails ? '*** ' + fails + ' FAILED ***' : 'ALL PASS');
process.exit(fails ? 1 : 0);
