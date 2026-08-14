// t36 - the page strip and the big sheet are drawn by ONE routine (2026-08-14).
//
// The user asked to see every page small, down the side, the way Rayon does it.
// The tempting way is to write a second, simpler drawing routine for the little
// pictures. That is exactly how a preview starts telling lies: it drifts from
// the real thing one small difference at a time, and this whole file exists to
// stop the window and the paper drifting apart.
//
// So sheetSVG draws both, and `live` is the only difference: the big one
// remembers how to get from the screen back to the house, shows the view frame
// and paints what is picked. A thumbnail shows the sheet and nothing else.
//
// This runs the window's real JavaScript in a sandbox with just enough browser
// under it to call the drawing routine.

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
function el() {
  return {
    className: '', innerHTML: '', textContent: '', value: '', disabled: false,
    style: {}, id: '',
    appendChild() {}, querySelector() { return null; },
    focus() {}, select() {}, addEventListener() {}, removeAttribute() { this.src = undefined; },
    getBoundingClientRect() { return { left: 0, top: 0, width: 800, height: 600 }; },
    clientWidth: 800, clientHeight: 600, firstChild: null
  };
}
const nodes = {};
const sandbox = {
  console,
  document: {
    getElementById(id) { return nodes[id] || (nodes[id] = el()); },
    createElement() { return el(); },
    addEventListener() {}
  },
  window: { addEventListener() {} },
  sketchup: new Proxy({}, { get: () => () => {} }),
  Image: function () {},
  FileReader: function () {},
  JSON, Math, Number, String, Array, Object, parseInt, parseFloat, setTimeout
};
sandbox.window.document = sandbox.document;
vm.createContext(sandbox);
vm.runInContext(js, sandbox);

ok('the window has one drawing routine, and it takes a page',
   typeof sandbox.sheetSVG === 'function', typeof sandbox.sheetSVG);

// ------------------------------------------------------------ a document
const PAGE_PLAN = {
  name: 'FLOOR PLAN', sheet_number: 'A-101', width: 36, height: 24,
  views: [{ name: 'PLAN', x: 1, y: 2, w: 30, h: 20, canvas: 'MODEL', scale: '1/4"' }],
  layers: [{ name: 'TITLE', visible: true, shapes: [
    { type: 'text', text: 'A-101 FLOOR PLAN', x: 20, y: 1, h: 0.1, align: 'left' },
    { type: 'line', x1: 0.5, y1: 1.6, x2: 35.5, y2: 1.6, weight: 0.03 }
  ] }]
};
const PAGE_IMG = {
  name: 'RENDERING 1', sheet_number: 'A-102', kind: 'image', ref: 0,
  width: 36, height: 24,
  views: [],
  layers: [{ name: 'IMAGES', visible: true, shapes: [
    { type: 'image', path: 'C:/r/1.jpg', x: 1, y: 2, w: 34, h: 20 }
  ] }]
};

sandbox.DOC = {
  pages: [PAGE_PLAN, PAGE_IMG],
  canvases: [{ name: 'MODEL', layers: [{ name: 'WALLS', visible: true, shapes: [
    { type: 'polyline', points: [[0, 0], [240, 0], [240, 180], [0, 180], [0, 0]], closed: true },
    { type: 'text', text: 'KITCHEN', x: 120, y: 90, h: 6, align: 'center' }
  ] }] }]
};
sandbox.STATE = { scale: '1/4"', hidden: [], origin_x: 120, origin_y: 90, active: 0, marks: [] };
sandbox.SF = { '1/4"': 0.25 / 12 };
sandbox.URLS = { 'C:/r/1.jpg': 'file:///C:/r/1.jpg' };
sandbox.PAGE = PAGE_PLAN;

const big = sandbox.sheetSVG(PAGE_PLAN, 20, true);
const SMALL_K = 520 / 36;   // the strip draws big and lets CSS shrink it
const small = sandbox.sheetSVG(PAGE_PLAN, SMALL_K, false);

// -------------------------------------------------------- both are real sheets
[['the big sheet', big], ['the thumbnail', small]].forEach(([what, out]) => {
  ok(what + ' is a finished svg',
     out.startsWith('<svg ') && out.endsWith('</svg>'), out.slice(0, 60));
  ok(what + ' has as many tags open as closed',
     (out.match(/<g[ >]/g) || []).length === (out.match(/<\/g>/g) || []).length,
     [(out.match(/<g[ >]/g) || []).length, (out.match(/<\/g>/g) || []).length]);
  ok(what + ' starts on white paper', out.includes('fill="#fff"'));
  ok(what + ' draws the walls', out.includes('<polygon') || out.includes('<polyline'));
  ok(what + ' draws the title block', out.includes('A-101 FLOOR PLAN'));
  ok(what + ' has no NaN anywhere in it', !/NaN/.test(out),
     (out.match(/[^ "]*NaN[^ "]*/) || [])[0]);
});

// ------------------------------------------------- and they differ only in live
ok('the thumbnail leaves out the working furniture', small.length < big.length);
ok('only the big one shows the dashed view frame',
   big.includes('stroke-dasharray="5 4"') && !small.includes('stroke-dasharray="5 4"'));
ok('the thumbnail is the right shape for the paper',
   small.includes('width="520"') && small.includes('height="347"'),
   small.slice(0, 120));

// Two sheets drawn small on the same page must not share a clip id, or the
// second one is clipped by the first one's window.
const s1 = sandbox.sheetSVG(PAGE_PLAN, 4, false);
sandbox.sheetSVG(PAGE_IMG, 4, false);
const otherPlan = Object.assign({}, PAGE_PLAN, { name: 'FLOOR PLAN 2' });
const s2 = sandbox.sheetSVG(otherPlan, 4, false);
const id1 = (s1.match(/clipPath id="([^"]+)"/) || [])[1];
const id2 = (s2.match(/clipPath id="([^"]+)"/) || [])[1];
ok('two thumbnails do not share a clip name', id1 && id2 && id1 !== id2, [id1, id2]);
ok('and neither of them steals the big sheet\'s name',
   id1 !== 'vclip' && id2 !== 'vclip', [id1, id2]);

// ------------------------------------------------- a picture page in miniature
const imgSmall = sandbox.sheetSVG(PAGE_IMG, SMALL_K, false);
ok('a render sheet shows its picture in the strip too',
   imgSmall.includes('<image ') && imgSmall.includes('file:///C:/r/1.jpg'),
   imgSmall.slice(0, 200));
ok('and it keeps the picture proportions, same as the paper does',
   imgSmall.includes('preserveAspectRatio="xMidYMid meet"'));

// ------------------------------------------------------- what is hidden stays hidden
sandbox.STATE.hidden = ['WALLS'];
const hidden = sandbox.sheetSVG(PAGE_PLAN, 20, false);
ok('a layer turned off is off in the strip as well',
   !hidden.includes('KITCHEN'), 'the hidden layer was drawn anyway');
sandbox.STATE.hidden = [];

// --------------------------------------------------------- the keys and the button
ok('up and down walk the page list',
   /\$\('pages'\)\.onkeydown[\s\S]{0,220}ArrowDown/.test(js));
ok('and they move by one page at a time',
   /goToPage\(\(STATE\.active\|\|0\)\+\(e\.key==='ArrowDown'\?1:-1\)\)/.test(js));
ok('Home and End jump to the ends',
   js.includes("e.key==='Home'") && js.includes("e.key==='End'"));
ok('the strip has a button of its own',
   js.includes("$('stripbtn').onclick=function(){ toggleStrip(); }"));
ok('and it is remembered between openings', js.includes('STATE.strip = on'));

// -------------------------------------------------- everything folds away now
// The user: "not everything needs to be on the screen - it should be in boxes
// that open, and the boxes have to be obvious and invite a click."
const html = fs.readFileSync(RB, 'utf8');
const side = html.match(/<div id="side">([\s\S]*?)\n            <\/div>\s*\n            <div id="curtain"/);
ok('the side is built out of boxes', !!side);
const keys = [...html.matchAll(/data-k="([a-z]+)"/g)].map(m => m[1]);
ok('every group has its own box',
   ['pages', 'paper', 'marks', 'layers', 'images', 'model', 'title', 'settings', 'help']
     .every(k => keys.includes(k)), keys);
ok('there is no heading left loose outside a box',
   !/\n\s*<h4>(?!<)/.test(side ? side[1] : ''), 'a bare <h4> is still there');
ok('one handler opens and shuts all of them',
   js.includes('function buildSections()') && js.includes('function openSection('));
ok('and which ones are open is remembered', js.includes('STATE.open[key]=!!on'));
ok('only the page list starts open',
   /OPEN_AT_FIRST\s*=\s*\{pages:true\}/.test(js), (js.match(/OPEN_AT_FIRST.{0,40}/) || [])[0]);

// The tables checkbox belongs with the layers - the user said so, it was
// sitting outside the list on its own.
const layersBox = html.match(/data-k="layers"([\s\S]*?)<\/div>\s*<\/div>/);
ok('the schedules checkbox sits inside the layers box',
   layersBox && layersBox[1].includes('id="ownpage"'),
   layersBox && layersBox[1].slice(0, 200));

// Export must never be behind a fold: it is the point of the whole window.
ok('Export PDF stays out in the open',
   side && /<\/div>\s*\n\s*<button id="pdf" class="go">/.test(side[1]),
   'the export button ended up inside a box');

// ------------------------------------------------- the headings say what is inside
sandbox.STATE.hidden = ['SITE', 'NOTES'];
sandbox.layerCount();
ok('the layers heading says how many are switched off',
   nodes.laycount.textContent.indexOf('2') >= 0, nodes.laycount.textContent);
sandbox.STATE.hidden = [];
sandbox.layerCount();
ok('and says nothing at all when they are all on',
   nodes.laycount.textContent === '', nodes.laycount.textContent);

sandbox.STATE.marks = [{ t: 'dim' }, { t: 'note' }];
sandbox.STATE.size = 'ARCH D';
sandbox.headings();
ok('the marks heading counts what is on the sheet',
   nodes.markstag.textContent.indexOf('2') >= 0, nodes.markstag.textContent);
ok('the paper heading shows the size and the scale',
   nodes.papertag.textContent.indexOf('ARCH D') >= 0 &&
   nodes.papertag.textContent.indexOf('1/4"') >= 0, nodes.papertag.textContent);
ok('the pictures heading counts the render sheets',
   nodes.imgtag.textContent.indexOf('1') >= 0, nodes.imgtag.textContent);
sandbox.STATE.marks = [];

// ------------------------------------------------------------------ the logo
ok('there is a settings box with a logo picker',
   html.includes('id="logopick"') && js.includes('sketchup.choose_logo()'));
ok('and a way back to the built-in one', html.includes('id="logoclear"'));
sandbox.showLogo({ path: 'C:/a/logo.png', name: 'logo.png',
                   url: 'file:///C:/a/logo.png', there: true });
ok('a chosen logo is shown in the box',
   nodes.logoshow.className === 'on' && nodes.logoshow.src === 'file:///C:/a/logo.png',
   [nodes.logoshow.className, nodes.logoshow.src]);
ok('and its heading says so', nodes.settag.textContent !== '', nodes.settag.textContent);
sandbox.showLogo({ path: 'C:/gone/logo.png', name: 'logo.png',
                   url: 'file:///C:/gone/logo.png', there: false });
ok('a logo whose file has moved says so instead of showing nothing',
   nodes.logoinfo.textContent.indexOf('logo.png') >= 0, nodes.logoinfo.textContent);
sandbox.showLogo(null);
ok('no logo means an empty box, not a broken picture',
   nodes.logoshow.className === '', nodes.logoshow.className);

// A layer switched off and then hidden behind a fold is how a sheet comes out
// missing something and nobody can see why. The heading has to say so.
sandbox.STATE.hidden = ['SITE', 'NOTES'];
sandbox.layerCount();
ok('the heading says how many layers are switched off',
   nodes.laycount.textContent.indexOf('2') >= 0, nodes.laycount.textContent);
sandbox.STATE.hidden = [];
sandbox.layerCount();
ok('and says nothing at all when they are all on',
   nodes.laycount.textContent === '', nodes.laycount.textContent);
ok('turning one off updates that count straight away',
   /layerCount\(\); render\(\); push\(\);/.test(js));

console.log(fails ? `\n*** ${fails} FAILED ***` : '\nALL PASS');
process.exit(fails ? 1 : 0);
