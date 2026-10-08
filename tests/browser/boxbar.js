// boxbar.js SHEET.html PAYLOAD.json TEXT_RULES.json - the settings at the side on a box of writing, in a real browser
// PAYLOAD: one Ruby laid out with two boxes of writing on the plan sheet (gen_box.rb, STATE_JSON with 'texts'); t:1 is bold, underlined, red.
const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const browser = await chromium.launch(); let bad = 0; const ok = (c, m) => { if (!c) bad++; console.log((c ? '  ok   ' : '  FAIL ') + m); };
  const page = await browser.newPage({ viewport: { width: 1700, height: 1000 } });
  page.on('pageerror', e => { bad++; console.log('PAGEERROR', e.message); });
  await page.addInitScript(() => { window.__sent = []; window.sketchup = new Proxy({}, { get: (t, name) => function (arg) { window.__sent.push([name, arg]); } }); });
  await page.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
  await page.evaluate(([p, r, d]) => { const q = JSON.parse(p); q.state.strip = true; q.rotate = true; q.view_box = true; q.pic_box = true; q.text_box = true; q.text_words = true; q.text_style = true; q.text_rules = JSON.parse(r);
    q.images = (q.images || []).map(x => Object.assign({}, x, { url: 'file://' + d + '/' + x.path.split('/').pop(), there: true })); loadSheet(q); }, [fs.readFileSync(process.argv[3], 'utf8'), fs.readFileSync(process.argv[4], 'utf8'), path.resolve('.')]);
  await page.waitForTimeout(700);
  const mid = id => page.evaluate(i => { const e = pageTexts().find(q => q.pic === i), b = document.querySelector('#sheetWrap svg').getBoundingClientRect(); return [b.left + (e.x + e.w / 2) * LIVEK, b.top + (PAGE.height - e.y - e.h / 2) * LIVEK]; }, id);
  const st = () => page.evaluate(() => { const g = id => document.getElementById(id); const tx = STATE.texts; const el = Array.from(document.querySelectorAll('#sheetWrap svg text')).filter(t => /Grass/.test(t.textContent))[0];
    return { bar: g('textbar').className, unit: g('txunit').textContent, size: g('txsize').value, B: /on/.test(g('txbold').className), I: /on/.test(g('txitalic').className), U: /on/.test(g('txunder').className), color: g('txcolor').value, words: getComputedStyle(g('txwords')).display, what: g('txwhat').textContent,
      t0: JSON.stringify(tx[0]), BSEL: BSEL, TBED: !!TBED, undo: UNDO.length, focus: document.activeElement && document.activeElement.id, sent: window.__sent.filter(m => m[0] === 'set_state').length, marks: window.__sent.filter(m => m[0] === 'set_text_mark').length,
      svg: el ? { w: el.getAttribute('font-weight'), s: el.getAttribute('font-style'), d: el.getAttribute('text-decoration'), f: el.getAttribute('fill'), fs: el.getAttribute('font-size') } : null,
      ed: { w: g('tbedit').style.fontWeight, s: g('tbedit').style.fontStyle, d: g('tbedit').style.textDecoration, c: g('tbedit').style.color, cls: g('tbedit').className, v: g('tbedit').value }, zoom: ZOOM, open: g('textbar').closest('.sec').className }; });
  const press = async pt => { await page.mouse.move(pt[0], pt[1]); await page.mouse.down(); await page.mouse.up(); await page.waitForTimeout(120); };
  let a = await st();
  ok(a.bar === '' && a.unit === '%', 'nothing picked: the panel is grey, counting in %');
  ok(a.svg && a.svg.w === null && a.svg.f === '#000', 'the first box is plain black as Ruby laid it; the second came bold, underlined, red: ' + JSON.stringify(await page.evaluate(() => { const e = Array.from(document.querySelectorAll('#sheetWrap svg text')).filter(t => /PATIO/.test(t.textContent))[0]; return e && [e.getAttribute('font-weight'), e.getAttribute('text-decoration'), e.getAttribute('fill')]; })));
  // 1. pick the box
  await press(await mid('t:0')); a = await st();
  ok(a.BSEL === 't:0' && a.bar === 'on' && a.unit === 'pt' && a.size === '16' && !a.B && !a.I && !a.U && a.color === '#000000' && a.words === 'none' && /open/.test(a.open), 'A BOX OF WRITING PICKED: the panel is alive on it - 16 pt, nothing set, the words box put away, the section open: ' + JSON.stringify([a.bar, a.unit, a.size, a.what]));
  // 2. B
  const u0 = a.undo, s0 = a.sent;
  await page.click('#txbold'); await page.waitForTimeout(120); a = await st();
  ok(a.B && JSON.parse(a.t0).bold === true && a.svg.w === '700' && a.undo === u0 + 1 && a.sent === s0 + 1 && a.BSEL === 't:0', 'B: bold on the sheet at once, one step for Ctrl+Z, Ruby told once, the box still picked');
  await page.click('#txitalic'); await page.click('#txunder'); await page.waitForTimeout(120); a = await st();
  ok(a.I && a.U && a.svg.s === 'italic' && a.svg.d === 'underline', 'I and U the same way');
  // 3. the size
  await page.fill('#txsize', '32'); await page.keyboard.press('Enter'); await page.waitForTimeout(150); a = await st();
  const t0 = JSON.parse(a.t0);
  ok(t0.pt === 32 && Math.abs(t0.box[2] - 4.2 * 2) < 1e-6 && a.size === '32', 'THE SIZE, in points: 32 - twice the letters, twice the width (' + t0.box.map(n => Math.round(n * 100) / 100) + ')');
  // 4. colour
  await page.evaluate(() => { const c = document.getElementById('txcolor'); c.value = '#1f6feb'; c.onchange(); }); await page.waitForTimeout(120); a = await st();
  ok(JSON.parse(a.t0).color === '#1f6feb' && a.svg.f === '#1f6feb', 'the colour');
  await page.screenshot({ path: 'style_picked.png' });
  // 5. Ctrl+Z, a step at a time
  await page.mouse.move(900, 60); await page.evaluate(() => document.activeElement && document.activeElement.blur());
  await page.keyboard.press('Control+z'); await page.waitForTimeout(120); a = await st();
  ok(JSON.parse(a.t0).color === undefined && JSON.parse(a.t0).pt === 32, 'Ctrl+Z: the colour goes back, nothing else');
  await page.keyboard.press('Control+z'); await page.waitForTimeout(120); a = await st();
  ok(JSON.parse(a.t0).pt === 16 && Math.abs(JSON.parse(a.t0).box[2] - 4.2) < 1e-6, 'again: the size goes back, and the width with it');
  for (let i = 0; i < 3; i++) { await page.keyboard.press('Control+z'); await page.waitForTimeout(80); } a = await st();
  ok(JSON.parse(a.t0).bold === undefined && JSON.parse(a.t0).italic === undefined && JSON.parse(a.t0).underline === undefined && a.svg.w === null, 'three more: plain again');
  // 6. while typing
  let c = await mid('t:0'); await press(c); await page.mouse.down({ clickCount: 2 }); await page.mouse.up({ clickCount: 2 }); await page.waitForTimeout(200); a = await st();
  ok(a.TBED && a.focus === 'tbedit' && a.bar === 'on' && a.unit === 'pt', 'TYPING IN THE BOX: the panel stays alive (it was grey in his picture)');
  const u1 = a.undo, s1 = a.sent;
  await page.click('#txbold'); await page.waitForTimeout(120); a = await st();
  ok(a.TBED && a.focus === 'tbedit' && a.ed.w === '700' && a.svg.w === '700' && a.undo === u1, 'B while typing: the letters are bold on the sheet and in the editor, the keyboard is back in the box, no step yet');
  await page.keyboard.type(' X'); await page.waitForTimeout(80);
  await page.fill('#txsize', '24'); await page.keyboard.press('Enter'); await page.waitForTimeout(150); a = await st();
  ok(a.TBED && a.focus === 'tbedit' && JSON.parse(a.t0).pt === 24 && /X$/.test(JSON.parse(a.t0).text), 'the size while typing: 24 pt, the words kept, back in the box (' + a.ed.v.slice(-12).replace(/\n/g, ' / ') + ')');
  await page.screenshot({ path: 'style_typing.png' });
  await page.mouse.move(700, 880); await page.mouse.down(); await page.mouse.up(); await page.waitForTimeout(150); a = await st();
  ok(!a.TBED && JSON.parse(a.t0).bold === true && JSON.parse(a.t0).pt === 24 && a.undo === u1 + 1 && a.sent === s1 + 1, 'a press on the sheet keeps it all: ONE step for Ctrl+Z, Ruby told once');
  await page.keyboard.press('Control+z'); await page.waitForTimeout(120); a = await st();
  ok(JSON.parse(a.t0).bold === undefined && JSON.parse(a.t0).pt === 16 && !/X$/.test(JSON.parse(a.t0).text), 'Ctrl+Z takes the words, the bold and the size back together');
  // 7. Escape while typing
  c = await mid('t:0'); await press(c); await page.mouse.down({ clickCount: 2 }); await page.mouse.up({ clickCount: 2 }); await page.waitForTimeout(200);
  await page.click('#txitalic'); await page.waitForTimeout(100); await page.keyboard.press('Escape'); await page.waitForTimeout(120); a = await st();
  ok(!a.TBED && JSON.parse(a.t0).italic === undefined, 'Escape while typing drops the setting with the words');
  // 8. let go
  await page.mouse.move(700, 880); await page.mouse.down(); await page.mouse.up(); await page.waitForTimeout(150); a = await st();
  ok(a.BSEL === null && a.bar === '' && a.unit === '%', 'the box let go: the panel is grey again, and counts in % again');
  ok((await st()).zoom === null, 'through all of that the view never moved');
  // 9. a label still has its own road
  const labAt = () => page.evaluate(() => { const r = document.getElementById('sheetWrap').firstChild.getBoundingClientRect(); let best = null; eachText(function (s, paper) { if (paper || !/^DIMENSIONS\|/.test(s.key)) return; const b = textBox(s, paper), cc = [r.left + b.x + b.w / 2, r.top + b.y + b.h / 2]; if (cc[0] > 400 && cc[0] < 1200 && cc[1] > 150 && cc[1] < 800 && !hitMark({ clientX: cc[0], clientY: cc[1] }) && !hitPic({ clientX: cc[0], clientY: cc[1] }) && (!best || b.w > best.w)) best = { c: cc, w: b.w }; }); return best && best.c; });
  // (at the zoom that shows the whole sheet a wall's number is a pixel and a half tall: get closer first, as he would)
  let lab = await labAt(); await page.mouse.move(lab[0], lab[1]); for (let i = 0; i < 12; i++) { await page.mouse.wheel(0, -120); await page.waitForTimeout(25); } await page.waitForTimeout(200); lab = await labAt();
  const z9 = (await st()).zoom;
  await press(lab); a = await st(); const m0 = a.marks;
  ok(a.bar === 'on' && a.unit === '%' && a.words !== 'none', 'A LABEL PICKED: the panel is its own, in %, with the words box');
  await page.click('#txbold'); await page.waitForTimeout(100); a = await st();
  ok(a.marks === m0 + 1, 'B on a label goes to Ruby under its key, as before');
  ok(a.zoom === z9, 'and the zoom is where he left it');
  await browser.close();
  console.log(bad ? ('\n' + bad + ' FAILED') : '\nall ok'); process.exit(bad ? 1 : 0);
})();
