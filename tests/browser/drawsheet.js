// drawsheet.js SHEET.html PAYLOAD.json - an editor drawing on a sheet of its own, and writing in Hebrew / in a lettering, in a real browser (2026-10-08). PAYLOAD from tests/browser/gen_67.rb; the PDF it prints (perf_67.pdf) is laid beside the screenshots.
const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const payload = fs.readFileSync(process.argv[3] || 'payload.json', 'utf8');
  const browser = await chromium.launch(); let bad = 0; const ok = (c, m) => { if (!c) bad++; console.log((c ? '  ok   ' : '  FAIL ') + m); };
  const page = await browser.newPage({ viewport: { width: 1700, height: 1000 } });
  page.on('pageerror', e => { bad++; console.log('PAGEERROR', e.message); });
  await page.addInitScript(() => { window.__sent = []; window.sketchup = new Proxy({}, { get: (t, name) => function (arg) { window.__sent.push([name, arg]); } }); });
  await page.goto('file://' + path.resolve(process.argv[2] || 'sheet.html'), { waitUntil: 'load' });
  await page.evaluate(p => { const q = JSON.parse(p); q.state.strip = true; q.state.open = { pages: true, text: true }; loadSheet(q); }, payload);
  await page.waitForTimeout(600);
  const st = () => page.evaluate(() => ({ active: STATE.active, kind: PAGE.kind, key: pageKey(PAGE), view: !!VIEW, draw: document.getElementById('drawadd').style.display, opts: Array.from(document.getElementById('drawsrc').options).map(o => o.textContent),
    fonts: Array.from(document.getElementById('txfont').options).map(o => o.value), rows: Array.from(document.querySelectorAll('#pages .pg span')).map(r => r.textContent),
    texts: Array.from(document.querySelectorAll('#sheetWrap svg text')).filter(t => /חדר|Pool|קיר|ROOM 1/.test(t.textContent)).map(t => [t.textContent, t.getAttribute('font-family'), t.getAttribute('font-weight')]) }));
  let a = await st();
  ok(a.draw === '' && a.opts.join() === 'שרטוט 1', 'the drawings box offers the editor\'s drawing: ' + JSON.stringify(a.opts));
  ok(a.fonts.join('|') === '|DejaVu Sans|Liberation Sans', 'the letterings on offer: ' + JSON.stringify(a.fonts));
  ok(a.rows.join('|') === 'FLOOR PLAN|שרטוט 1', 'the page list: ' + a.rows.join(' | '));
  ok(a.texts.some(t => /חדר/.test(t[0]) && /DejaVu Sans/.test(t[1])) && a.texts.some(t => /Pool/.test(t[0]) && /DejaVu Sans/.test(t[1]) && t[2] === '700') && a.texts.some(t => t[0] === 'ROOM 1' && /DejaVu/.test(t[1])), 'THE PLAN SHEET: the Hebrew box in the Hebrew family, the Pool box in the lettering picked, the ROOM label too: ' + JSON.stringify(a.texts));
  await page.screenshot({ path: 'plan_67.png' });
  const box = await page.evaluate(() => { const r = document.querySelector('#sheetWrap svg').getBoundingClientRect(); return { left: r.left, top: r.top, w: r.width, h: r.height }; });
  await page.screenshot({ path: 'plan_67_sheet.png', clip: { x: box.left, y: box.top, width: box.w, height: box.h } });
  // the drawing sheet
  await page.evaluate(() => goToPage(1)); await page.waitForTimeout(300);
  a = await st();
  ok(a.kind === 'drawing' && a.key === 'drawing:0' && a.view === false, 'the drawing sheet opens: seen, not worked on (no VIEW): ' + JSON.stringify([a.kind, a.key, a.view]));
  const hs = await page.evaluate(() => ['boxc-nw', 'boxmove', 'rothandle'].map(id => document.getElementById(id).className));
  ok(hs.every(c => !/\bon\b/.test(c)), 'no handles on it: ' + JSON.stringify(hs));
  const b2 = await page.evaluate(() => { const r = document.querySelector('#sheetWrap svg').getBoundingClientRect(); return { left: r.left, top: r.top, w: r.width, h: r.height, polys: document.querySelectorAll('#sheetWrap svg polygon').length, texts: Array.from(document.querySelectorAll('#sheetWrap svg text')).map(t => t.textContent).slice(0, 12) }; });
  ok(b2.polys >= 5, 'the walls of the drawing are bands: ' + b2.polys + ' polygons; writing: ' + JSON.stringify(b2.texts));
  await page.screenshot({ path: 'drawing_67.png' });
  await page.screenshot({ path: 'drawing_67_sheet.png', clip: { x: b2.left, y: b2.top, width: b2.w, height: b2.h } });
  // a press on it pans
  await page.mouse.move(b2.left + 400, b2.top + 300); await page.mouse.down(); await page.mouse.move(b2.left + 500, b2.top + 350); 
  const dr = await page.evaluate(() => ({ drag: DRAG && DRAG.pan, band: !!BAND, boxd: !!BOXD })); await page.mouse.up();
  ok(dr.drag === true && !dr.band && !dr.boxd, 'a press on the drawing sheet pans it: ' + JSON.stringify(dr));
  console.log(bad ? '*** ' + bad + ' FAILED' : 'all ok');
  await browser.close();
})();
