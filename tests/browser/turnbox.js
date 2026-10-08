// turnbox.js SHEET.html PAYLOAD.json - the drawing's box turning as a whole, in a real browser, on his drawing
const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const payload = fs.readFileSync(process.argv[3], 'utf8');
  const browser = await chromium.launch(); let bad = 0; const ok = (c, m) => { if (!c) bad++; console.log((c ? '  ok   ' : '  FAIL ') + m); };
  const page = await browser.newPage({ viewport: { width: 1900, height: 1200 } });
  page.on('pageerror', e => { bad++; console.log('PAGEERROR', e.message); });
  await page.addInitScript(() => { window.__sent = []; window.sketchup = new Proxy({}, { get: (t, name) => function (arg) { window.__sent.push([name, arg]); } }); });
  await page.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
  await page.evaluate(p => { const q = JSON.parse(p); q.state.strip = false; q.rotate = true; q.view_box = true; q.box_crop = true; loadSheet(q); }, payload);
  await page.waitForTimeout(500);
  const st = () => page.evaluate(() => { const v = PAGE.views[0], r = viewRect(); const cp = document.querySelector('#sheetWrap svg clipPath rect');
    return { rot: STATE.rotation, box: [v.x, v.y, v.w, v.h].map(n => Math.round(n * 1000) / 1000), turns: boxTurns(), clipT: cp ? cp.getAttribute('transform') : null,
      hnw: document.getElementById('boxc-nw').style.transform, undo: UNDO.length, vb: STATE.view_box, sf: STATE.scale_f || null,
      sent: window.__sent.filter(m => /set_rotation|set_state/.test(m[0])).map(m => m[0] + ' ' + m[1].slice(0, 90)), spot: screenOf(0, 0).map(Math.round) }; });
  let a = await st();
  ok(a.turns && a.rot === 30 && a.clipT === 'rotate(-30,' + (await page.evaluate(() => ((PAGE.views[0].x + PAGE.views[0].w / 2) * VIEW.k).toFixed(2) + ',' + ((PAGE.height - PAGE.views[0].y - PAGE.views[0].h / 2) * VIEW.k).toFixed(2))) + ')' && a.hnw === 'rotate(-30deg)',
     'opened on HIS drawing in a box [6,4,24,15] turned 30: the clip is turned, the handles are turned: ' + JSON.stringify([a.rot, a.box, a.clipT, a.hnw]));
  await page.screenshot({ path: 'turn_30.png' });
  // the window against the PDF Ruby printed: the same box, the same angle
  const box = await page.evaluate(() => { const r = document.querySelector('#sheetWrap svg').getBoundingClientRect(); const v = PAGE.views[0];
    return { k: VIEW.k, left: r.left, top: r.top, w: r.width, h: r.height, vx: v.x, vy: v.y, vw: v.w, vh: v.h, ph: PAGE.height, pw: PAGE.width }; });
  console.log('  the sheet on the screen:', JSON.stringify(box));
  await page.screenshot({ path: 'turn_sheet.png', clip: { x: box.left, y: box.top, width: box.w, height: box.h } });
  // turn it further with the round arrow, and time the steps
  await page.evaluate(() => { window.__rd = []; const rr = render; window.render = function (m) { const a = performance.now(); rr(m); document.getElementById('sheetWrap').getBoundingClientRect(); window.__rd.push(performance.now() - a); }; });
  const hb = async () => { const b = await page.locator('#rothandle').boundingBox(); return [b.x + b.width / 2, b.y + b.height / 2]; };
  const mid = () => page.evaluate(() => { const r = document.querySelector('#sheetWrap svg').getBoundingClientRect(); return [r.left + VIEW.cx * VIEW.k, r.top + (PAGE.height - VIEW.cy) * VIEW.k]; });
  let h = await hb(), c = await mid();
  const a0 = Math.atan2(-(h[1] - c[1]), h[0] - c[0]), R = Math.hypot(h[0] - c[0], h[1] - c[1]);
  const at = d => [c[0] + R * Math.cos(a0 + d * Math.PI / 180), c[1] - R * Math.sin(a0 + d * Math.PI / 180)];
  await page.mouse.move(h[0], h[1]); await page.mouse.down();
  for (let d = 1; d <= 60; d++) { const p = at(d); await page.mouse.move(p[0], p[1]); }
  await page.waitForTimeout(60);
  a = await st();
  const t = await page.evaluate(() => window.__rd);
  ok(a.rot === 90 && a.box[2] < 24, 'swept +60 with the arrow: at the quarter turn (snapped) the box was made smaller to fit: ' + JSON.stringify([a.rot, a.box]) + ' - ' + t.length + ' redraws, average ' + (t.reduce((x, y) => x + y, 0) / t.length).toFixed(0) + ' ms, worst ' + Math.max.apply(null, t).toFixed(0) + ' ms');
  await page.screenshot({ path: 'turn_90_held.png' });
  await page.mouse.up(); await page.waitForTimeout(100);
  a = await st();
  ok(a.sent.length === 1 && /set_rotation/.test(a.sent[0]) && /"view_box":\[/.test(a.sent[0]) && a.undo === 1 && a.sf === null, 'let go: Ruby told once, the angle and the box; one step; the scale untouched: ' + JSON.stringify(a.sent));
  // Ctrl+Z
  await page.mouse.move(c[0], c[1] + 300); await page.keyboard.press('Control+z'); await page.waitForTimeout(100);
  a = await st();
  ok(a.rot === 30 && JSON.stringify(a.box) === JSON.stringify([7.724, 6.128, 20.552, 12.845]) && JSON.stringify(a.vb) === JSON.stringify([6, 4, 24, 15]) && a.sent.length === 2, 'Ctrl+Z: the angle and the box back (shown held at 30, as Ruby will answer; the saved box as it was): ' + JSON.stringify([a.rot, a.box]));
  // a side of the turned box cut: a spot of the house stays
  const spot0 = (await st()).spot;
  const e = await page.locator('#boxe-e').boundingBox(); const ex = e.x + e.width / 2, ey = e.y + e.height / 2;
  const tr = 30 * Math.PI / 180, dpx = 2 * box.k;  // two inches in, along the box's own x
  await page.mouse.move(ex, ey); await page.mouse.down();
  for (let i = 1; i <= 10; i++) await page.mouse.move(ex - dpx * Math.cos(tr) * i / 10, ey + dpx * Math.sin(tr) * i / 10);
  await page.waitForTimeout(60);
  a = await st();
  ok(Math.abs(a.box[2] - 18.552) < 0.05 && Math.abs(a.box[3] - 12.845) < 0.001 && a.rot === 30 && a.spot[0] === spot0[0] && a.spot[1] === spot0[1], 'the east side of the turned box pulled in 2 inches: 2 inches narrower, the house on its spot: ' + JSON.stringify([a.box, a.spot, spot0]));
  await page.screenshot({ path: 'turn_cut.png' });
  await page.keyboard.press('Escape'); await page.mouse.up(); await page.waitForTimeout(80);
  a = await st();
  ok(JSON.stringify(a.box) === JSON.stringify([7.724, 6.128, 20.552, 12.845]) && a.sent.length === 2, 'Escape mid-cut: the box back, Ruby told nothing more');
  console.log(bad ? '*** ' + bad + ' FAILED' : 'all ok');
  await browser.close();
})();
