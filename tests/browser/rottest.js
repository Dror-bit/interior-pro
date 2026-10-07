// rottest.js SHEET.html PAYLOAD.json [PAYLOAD_TURNED_BY_RUBY.json] - turning the drawing, in a real browser, on his drawing
const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const payload = fs.readFileSync(process.argv[3], 'utf8');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1900, height: 1200 } });
  page.on('pageerror', e => console.log('PAGEERROR', e.message));
  await page.addInitScript(() => { window.__sent = []; window.sketchup = new Proxy({}, { get: (t, name) => function (arg) { window.__sent.push([name, arg]); } }); });
  await page.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
  await page.evaluate(p => { const q = JSON.parse(p); q.state.strip = false; q.rotate = true; loadSheet(q); }, payload);
  await page.waitForTimeout(400);
  const st = () => page.evaluate(() => ({ rot: STATE.rotation, zoom: ZOOM, sl: document.getElementById('stage').scrollLeft, st: document.getElementById('stage').scrollTop, mode: MODE, undo: UNDO.length,
    handle: document.getElementById('rothandle').className, deg: document.getElementById('rotdeg').textContent, rotating: !!ROT }));
  const hb = async () => { const b = await page.locator('#rothandle').boundingBox(); return [b.x + b.width / 2, b.y + b.height / 2]; };
  const mid = () => page.evaluate(() => { const r = document.querySelector('#sheetWrap svg').getBoundingClientRect(); return [r.left + VIEW.cx * VIEW.k, r.top + (PAGE.height - VIEW.cy) * VIEW.k]; });
  console.log('opened               ', JSON.stringify(await st()));
  await page.screenshot({ path: 'rot_0.png' });
  await page.evaluate(() => { window.__rd = []; const rr = render; window.render = function (m) { const a = performance.now(); rr(m); document.getElementById('sheetWrap').getBoundingClientRect(); window.__rd.push(performance.now() - a); }; });
  let h = await hb(), c = await mid();
  const a0 = Math.atan2(-(h[1] - c[1]), h[0] - c[0]), R = Math.hypot(h[0] - c[0], h[1] - c[1]);
  const at = d => [c[0] + R * Math.cos(a0 + d * Math.PI / 180), c[1] - R * Math.sin(a0 + d * Math.PI / 180)];
  await page.mouse.move(h[0], h[1]); await page.mouse.down();
  for (let d = 1; d <= 35; d++) { const p = at(-d); await page.mouse.move(p[0], p[1]); }
  await page.waitForTimeout(60);
  console.log('held, swept -35       ', JSON.stringify(await st()));
  await page.screenshot({ path: 'rot_drag.png' });
  await page.mouse.up(); await page.waitForTimeout(100);
  console.log('let go                ', JSON.stringify(await st()), '| sent', JSON.stringify(await page.evaluate(() => window.__sent.filter(m => !/sheet_/.test(m[0])).map(m => m[0] + ' ' + m[1]))));
  const t = await page.evaluate(() => window.__rd);
  console.log('drawing the sheet per step of the turn:', t.length, 'times, average', (t.reduce((x, y) => x + y, 0) / t.length).toFixed(0), 'ms, worst', Math.max.apply(null, t).toFixed(0), 'ms');
  // a second turn, Escape in the middle
  h = await hb(); await page.mouse.move(h[0], h[1]); await page.mouse.down();
  for (let d = 1; d <= 20; d++) { const p = at(-35 - d); await page.mouse.move(p[0], p[1]); }
  console.log('second turn, held     ', JSON.stringify(await st()));
  await page.keyboard.press('Escape'); await page.mouse.up(); await page.waitForTimeout(80);
  console.log('Escape                ', JSON.stringify(await st()));
  await page.keyboard.press('Control+z'); await page.waitForTimeout(80);
  console.log('Ctrl+Z                ', JSON.stringify(await st()), '| sent', JSON.stringify(await page.evaluate(() => window.__sent.filter(m => /set_rotation/.test(m[0])).map(m => m[1]))));
  // the sheet as RUBY turned it (the writing decided), to lay beside the PDF
  if (process.argv[4]) {
    await page.evaluate(p => { const q = JSON.parse(p); loadSheet(q); }, fs.readFileSync(process.argv[4], 'utf8'));
    await page.waitForTimeout(300);
    const r = await page.evaluate(() => { const b = document.querySelector('#sheetWrap svg').getBoundingClientRect(); return [b.left, b.top, b.width, b.height]; });
    await page.screenshot({ path: 'rot_window.png', clip: { x: r[0], y: r[1], width: r[2], height: r[3] } });
    console.log('ruby-turned sheet drawn', JSON.stringify(await st()), 'sheet', r.map(Math.round));
    // close in on the house, 4x, for the writing
    await page.setViewportSize({ width: 1900, height: 1200 });
    await page.evaluate(() => { setZoom(4); });
    await page.waitForTimeout(200);
    await page.locator('#sheetWrap svg').screenshot({ path: 'rot_window_big.png' });
  }
  await browser.close();
})();
