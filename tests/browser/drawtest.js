// drawtest.js SHEET.html PAYLOAD.json [OUTPREFIX] - the two drawing tools in a real browser, on his drawing
const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const payload = fs.readFileSync(process.argv[3], 'utf8');
  const out = process.argv[4] || 'draw';
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1900, height: 1200 } });
  page.on('pageerror', e => console.log('PAGEERROR', e.message));
  await page.addInitScript(() => { window.__sent = []; window.sketchup = new Proxy({}, { get: (t, name) => function (arg) { window.__sent.push([name, arg]); } }); });
  await page.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
  await page.evaluate(p => { const q = JSON.parse(p); q.state.strip = false; q.state.open = { marks: true }; loadSheet(q); }, payload);
  await page.waitForTimeout(400);
  await page.screenshot({ path: out + '_side.png', clip: { x: 0, y: 0, width: 232, height: 520 } });
  const st = () => page.evaluate(() => ({ lines: DOC.canvases[0].layers.find(l => l.name === 'SITE').shapes.length, mode: MODE, pend: PEND && PEND.map(v => Math.round(v * 100) / 100),
    snap: DRAWSNAP && DRAWSNAP.kind, zoom: Math.round(ZOOM * 1000) / 1000, sl: document.getElementById('stage').scrollLeft, st: document.getElementById('stage').scrollTop,
    undo: UNDO.length, ring: (function () { const c = document.querySelector('#drawhi circle'); return c ? c.getAttribute('stroke') : null; })(), rubber: !!document.querySelector('#drawhi line') }));
  // zoom in on the front yard, the same spot as the picture he was shown
  await page.mouse.move(1000, 740);
  for (let i = 0; i < 7; i++) { await page.mouse.wheel(0, -100); await page.waitForTimeout(40); }
  await page.waitForTimeout(200);
  // time what runs on every move of the mouse, and what a click costs
  await page.evaluate(() => { window.__mv = []; window.__rd = [];
    const ds = drawSnap, pd = paintDraw, rr = render;
    let t0 = 0;
    window.drawSnap = function (p) { t0 = performance.now(); return ds(p); };
    window.paintDraw = function () { pd(); if (t0) { window.__mv.push(performance.now() - t0); t0 = 0; } };
    window.render = function (m) { const a = performance.now(); rr(m); document.getElementById('sheetWrap').getBoundingClientRect(); window.__rd.push(performance.now() - a); }; });
  await page.click('#tline');
  console.log('line button          ', JSON.stringify(await st()));
  // a real corner of his drawing, found from the drawing itself
  const corner = await page.evaluate(() => { const r = document.querySelector('#sheetWrap svg').getBoundingClientRect(); let best = null, bd = 1e9;
    DOC.canvases[0].layers.find(l => l.name === 'SITE').shapes.forEach(s => s.points.forEach(q => { const t = screenOf(q[0], q[1]); const X = r.left + t[0], Y = r.top + t[1]; const d = Math.hypot(X - 633, Y - 908); if (d < bd) { bd = d; best = [X, Y, q[0], q[1]]; } })); return best; });
  await page.mouse.move(corner[0] + 5, corner[1] - 4); await page.waitForTimeout(60);
  console.log('5 px off a corner    ', JSON.stringify(await st()), 'corner', corner.slice(2));
  await page.screenshot({ path: out + '_ring.png', clip: { x: corner[0] - 160, y: corner[1] - 120, width: 320, height: 240 } });
  await page.mouse.click(corner[0] + 5, corner[1] - 4); await page.waitForTimeout(60);
  // sweep the mouse about with a line half drawn: this is what he feels
  for (let i = 0; i <= 60; i++) await page.mouse.move(corner[0] + i * 6, corner[1] + 40 + 100 * Math.sin(i / 6));
  await page.waitForTimeout(80);
  console.log('half drawn, moving   ', JSON.stringify(await st()));
  await page.screenshot({ path: out + '_rubber.png', clip: { x: 430, y: 700, width: 900, height: 500 } });
  await page.mouse.click(corner[0], corner[1] + 190); await page.waitForTimeout(100);
  const s1 = await st();
  console.log('second click         ', JSON.stringify(s1), '| last', JSON.stringify(await page.evaluate(() => { const s = DOC.canvases[0].layers.find(l => l.name === 'SITE').shapes; return s[s.length - 1].points; })));
  // the running line: four clicks, ending on another real corner
  await page.click('#tchain');
  const P = [[corner[0], corner[1] + 190], [corner[0] + 300, corner[1] + 190], [corner[0] + 300, corner[1] + 120], [corner[0] + 420, corner[1] + 120]];
  for (const q of P) { await page.mouse.move(q[0], q[1]); await page.waitForTimeout(30); await page.mouse.click(q[0], q[1]); await page.waitForTimeout(60); }
  console.log('chain, four clicks   ', JSON.stringify(await st()));
  await page.mouse.move(P[3][0] + 80, P[3][1] - 60); await page.waitForTimeout(60);
  await page.screenshot({ path: out + '_chain.png', clip: { x: 430, y: 700, width: 900, height: 500 } });
  await page.keyboard.press('Escape'); await page.waitForTimeout(80);
  console.log('Escape               ', JSON.stringify(await st()));
  await page.keyboard.press('Control+z'); await page.waitForTimeout(80);
  console.log('Ctrl+Z               ', JSON.stringify(await st()));
  await page.keyboard.press('Control+z'); await page.waitForTimeout(80);
  console.log('Ctrl+Z               ', JSON.stringify(await st()));
  await page.screenshot({ path: out + '_after.png', clip: { x: 430, y: 700, width: 900, height: 500 } });
  const t = await page.evaluate(() => ({ mv: window.__mv, rd: window.__rd }));
  const avg = a => a.length ? (a.reduce((x, y) => x + y, 0) / a.length) : 0;
  console.log('every move of the mouse:', t.mv.length, 'moves, average', avg(t.mv).toFixed(2), 'ms, worst', Math.max.apply(null, t.mv).toFixed(2), 'ms');
  console.log('drawing the sheet after a click:', t.rd.length, 'times, average', avg(t.rd).toFixed(0), 'ms, worst', Math.max.apply(null, t.rd).toFixed(0), 'ms');
  console.log('sent to Ruby:', JSON.stringify(await page.evaluate(() => window.__sent.filter(m => !/sheet_/.test(m[0])).map(m => m[0] + (m[1] && m[1].length < 120 ? ' ' + m[1] : '')))));
  await browser.close();
})();
