// t49 - the page list: a tick for the PDF, an x for good (2026-08-19).
//
// The user asked for two things and said plainly they are two:
//   "אני רוצה את האופציה למחוק בכלל מהתוכנית, ואני רוצה את האופציה להשאיר
//    בתוכנית הכוללת אבל להוציא רק כמה דפים ל-PDF"
//
// TICK - the sheet stays in the set and in the window, and only stays out of
//        the print.
// X    - the sheet is thrown away, and since today that includes the floor
//        plan, which used to have no x at all.
//
// rt80 pins the Ruby half. This suite pins the half the user actually touches,
// by RUNNING the window's own script - never a copy of it. A copy is how a
// preview starts telling lies, which is the thing this whole file set exists
// to prevent (t36, same reason).
//
// The one thing worth stating out loud: pageKey() here and page_key() in
// plan_sheet_dialog.rb must agree, because a tick written by one is read by
// the other. If they ever disagree the user prints a set he never chose and
// nothing on screen says so.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const RB = path.join(__dirname, 'plan_sheet_dialog.rb');
const js = fs.readFileSync(RB, 'utf8').match(/<script>([\s\S]*?)<\/script>/)[1];

let fails = 0;
function ok(n, c, x) {
  console.log((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : '   << ' + JSON.stringify(x)));
  if (!c) fails++;
}

// ------------------------------------------------- just enough of a browser
//
// Richer than t36's: this suite reads the rows that were BUILT, so appendChild
// has to actually keep them.
function el(tag) {
  return {
    tag: tag || 'div',
    className: '', innerHTML: '', textContent: '', value: '', title: '',
    type: '', checked: false, disabled: false, style: {}, id: '',
    children: [],
    appendChild(c) { this.children.push(c); return c; },
    querySelector(sel) {
      const want = sel.replace(/^\./, '');
      const hit = this.children.find(c => (c.className || '').split(/\s+/).includes(want.split('.').pop()));
      return hit || null;
    },
    focus() {}, select() {}, addEventListener() {}, removeAttribute() {},
    getBoundingClientRect() { return { left: 0, top: 0, width: 800, height: 600 }; },
    clientWidth: 800, clientHeight: 600, firstChild: null
  };
}
const nodes = {};
const calls = [];
const sandbox = {
  console,
  document: {
    getElementById(id) {
      if (!nodes[id]) { nodes[id] = el(); nodes[id].id = id; }
      return nodes[id];
    },
    createElement(t) { return el(t); },
    addEventListener() {}
  },
  window: { addEventListener() {} },
  sketchup: new Proxy({}, {
    get: (_t, name) => (...a) => calls.push([name, a[0]])
  }),
  Image: function () {},
  FileReader: function () {},
  JSON, Math, Number, String, Array, Object, parseInt, parseFloat, setTimeout
};
sandbox.window.document = sandbox.document;
vm.createContext(sandbox);
vm.runInContext(js, sandbox);

// --------------------------------------------------------------- page keys

ok('the window knows how to name a page', typeof sandbox.pageKey === 'function',
   typeof sandbox.pageKey);
ok('the plan sheet is "plan"', sandbox.pageKey({ kind: 'plan' }) === 'plan');
ok('a page with no kind is still the plan sheet',
   sandbox.pageKey({}) === 'plan', sandbox.pageKey({}));
ok('the schedules are "schedules"',
   sandbox.pageKey({ kind: 'schedules' }) === 'schedules');
ok('a picture carries its place in the list - the SAME shape Ruby writes',
   sandbox.pageKey({ kind: 'image', ref: 2 }) === 'image:2',
   sandbox.pageKey({ kind: 'image', ref: 2 }));

// ------------------------------------------------------------ the page list

const PAGES = [
  { kind: 'plan', name: 'FLOOR PLAN', sheet_number: 'A-101' },
  { kind: 'schedules', name: 'SCHEDULES', sheet_number: 'A-102' },
  { kind: 'image', ref: 0, name: 'RENDERING 1', sheet_number: 'A-103' },
  { kind: 'image', ref: 1, name: 'RENDERING 2', sheet_number: 'A-104' }
];

function paint(state) {
  sandbox.DOC = { pages: PAGES, canvases: [] };
  sandbox.STATE = Object.assign({ active: 0, pdf_skip: [], drop_plan: false }, state);
  nodes.pages = el(); nodes.pages.id = 'pages';
  nodes.pagestag = el(); nodes.pagestag.id = 'pagestag';
  calls.length = 0;
  sandbox.fillPages();
  return nodes.pages.children;
}

let rows = paint({});
const pgRows = rows.filter(r => (r.className || '').startsWith('pg'));
ok('one row per sheet', pgRows.length === 4, pgRows.length);

const first = pgRows[0];
const boxes = first.children.filter(c => c.type === 'checkbox');
ok('every row opens with a tick', boxes.length === 1, boxes.length);
ok('and it starts ticked - a fresh model prints everything',
   boxes[0] && boxes[0].checked === true, boxes[0] && boxes[0].checked);

const xs = r => r.children.filter(c => c.tag === 'button' && c.textContent === '×');
ok('THE CHANGE: the plan sheet has an x now', xs(pgRows[0]).length === 1,
   xs(pgRows[0]).length);
ok('and so does every other sheet',
   pgRows.every(r => xs(r).length === 1), pgRows.map(r => xs(r).length));

// pressing the x on the PLAN row must tell Ruby it was the plan
xs(pgRows[0])[0].onclick({ stopPropagation() {} });
const del = calls.filter(c => c[0] === 'delete_page');
ok('the x asks Ruby to delete', del.length === 1, calls.map(c => c[0]));
ok('and it says which sheet - the plan one',
   del[0] && JSON.parse(del[0][1]).kind === 'plan',
   del[0] && del[0][1]);

// and on a picture row it sends the picture's number, not its position
rows = paint({});
const picRows = rows.filter(r => (r.className || '').startsWith('pg'));
xs(picRows[3])[0].onclick({ stopPropagation() {} });
const d2 = calls.filter(c => c[0] === 'delete_page').map(c => JSON.parse(c[1]))[0];
ok('a picture row sends its kind and its ref',
   d2 && d2.kind === 'image' && d2.ref === 1, d2);

// --------------------------------------------------------------- the tick

rows = paint({});
const box0 = rows.filter(r => (r.className || '').startsWith('pg'))[0]
                 .children.filter(c => c.type === 'checkbox')[0];
box0.onclick({ stopPropagation() {} });
ok('un-ticking a sheet writes it into the settings',
   (sandbox.STATE.pdf_skip || []).indexOf('plan') >= 0, sandbox.STATE.pdf_skip);
ok('and the settings go back to Ruby straight away',
   calls.some(c => c[0] === 'set_state'), calls.map(c => c[0]));
ok('un-ticking DELETES NOTHING - no delete reaches Ruby',
   !calls.some(c => c[0] === 'delete_page'), calls.map(c => c[0]));
ok('and the sheet is still in the list', sandbox.DOC.pages.length === 4);

// ticking it again takes it back out of the skip list
calls.length = 0;
const again = nodes.pages.children.filter(r => (r.className || '').startsWith('pg'))[0]
                   .children.filter(c => c.type === 'checkbox')[0];
again.onclick({ stopPropagation() {} });
ok('ticking it again puts it back in the print',
   (sandbox.STATE.pdf_skip || []).indexOf('plan') < 0, sandbox.STATE.pdf_skip);

// ------------------------------------------------------- what the list says

rows = paint({ pdf_skip: ['plan', 'image:1'] });
const marked = rows.filter(r => (r.className || '').startsWith('pg'));
ok('a sheet left out of the print is greyed and struck through',
   marked[0].className.indexOf('off') >= 0, marked[0].className);
ok('its tick is empty',
   marked[0].children.filter(c => c.type === 'checkbox')[0].checked === false);
ok('a sheet that IS printing is not marked',
   marked[1].className.indexOf('off') < 0, marked[1].className);
ok('the right picture is the one marked',
   marked[3].className.indexOf('off') >= 0 &&
   marked[2].className.indexOf('off') < 0,
   [marked[2].className, marked[3].className]);
ok('and the heading says how many are printing',
   nodes.pagestag.textContent.indexOf('2') === 0,
   nodes.pagestag.textContent);

rows = paint({ pdf_skip: [] });
ok('with nothing left out the heading stays quiet',
   nodes.pagestag.textContent === '', nodes.pagestag.textContent);

// ------------------------------------------------- the way back to the plan

rows = paint({ drop_plan: false });
ok('while the plan sheet is there, no "bring it back" button',
   !rows.some(r => r.id === 'planback'), rows.map(r => r.id));

rows = paint({ drop_plan: true });
const back = rows.filter(r => r.id === 'planback');
ok('once it is gone, the way back appears', back.length === 1, back.length);
calls.length = 0;
back[0].onclick();
ok('and it asks Ruby to put the plan sheet back',
   calls.some(c => c[0] === 'restore_plan'), calls.map(c => c[0]));

console.log(fails === 0 ? 't49 ALL PASS' : 't49 ' + fails + ' FAILED');
process.exit(fails === 0 ? 0 : 1);
