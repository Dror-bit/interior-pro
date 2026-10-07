const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const payload = fs.readFileSync(process.argv[3], 'utf8');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1900, height: 1200 } });
  page.on('pageerror', e => console.log('PAGEERROR', e.message));
  await page.addInitScript(() => { window.__sent = []; window.sketchup = new Proxy({}, { get: (t, name) => function (arg) { window.__sent.push(name); } }); });
  await page.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
  await page.evaluate(p => { const q = JSON.parse(p); q.state.strip = false; loadSheet(q); }, payload);
  await page.waitForTimeout(300);
  const st = () => page.evaluate(() => ({ lines: DOC.canvases[0].layers.find(l => l.name === 'SITE').shapes.length, picked: SSEL.length, mode: MODE, undo: UNDO.length, blue: !!document.getElementById('sitepick'), info: document.getElementById('markinfo').textContent.slice(0, 40) }));
  // a spot ON a loose line: take line 5000's middle
  const on = n => page.evaluate(n => { const s = DOC.canvases[0].layers.find(l => l.name === 'SITE').shapes[n]; const a = s.points[0], b = s.points[1]; const q = screenOf((a[0] + b[0]) / 2, (a[1] + b[1]) / 2); const r = document.querySelector('#sheetWrap svg').getBoundingClientRect(); return [r.left + q[0], r.top + q[1]]; }, n);
  // zoom in on the pool so single lines can be told apart
  const c = await on(200); await page.mouse.move(c[0], c[1]);
  for (let i = 0; i < 14; i++) { await page.mouse.wheel(0, -100); await page.waitForTimeout(30); }
  let p = await on(200);
  await page.mouse.click(p[0], p[1]); await page.waitForTimeout(80);
  console.log('click on a line          ', JSON.stringify(await st()));
  let q = await on(203);
  await page.keyboard.down('Shift'); await page.mouse.click(q[0], q[1]); await page.keyboard.up('Shift'); await page.waitForTimeout(80);
  console.log('Shift+click another      ', JSON.stringify(await st()));
  await page.keyboard.press('Delete'); await page.waitForTimeout(100);
  console.log('Delete                   ', JSON.stringify(await st()));
  await page.keyboard.press('Control+z'); await page.waitForTimeout(100);
  console.log('Ctrl+Z                   ', JSON.stringify(await st()));
  // a rubber band over the whole window, right to left: how long does it take with thousands picked
  const sr = await page.evaluate(() => { const r = document.getElementById('stage').getBoundingClientRect(); return [r.left, r.top, r.width, r.height]; });
  await page.evaluate(() => { window.__t0 = 0; const real = pickInBand; window.pickInBand = function (b) { const a = performance.now(); real(b); window.__band = performance.now() - a; }; const rr = render; window.render = function (m) { const a = performance.now(); rr(m); document.getElementById('sheetWrap').getBoundingClientRect(); window.__render = performance.now() - a; }; });
  await page.mouse.move(sr[0] + sr[2] - 60, sr[1] + sr[3] - 60); await page.mouse.down();
  for (let i = 1; i <= 10; i++) await page.mouse.move(sr[0] + sr[2] - 60 - i * (sr[2] - 120) / 10, sr[1] + sr[3] - 60 - i * (sr[3] - 120) / 10);
  await page.mouse.up(); await page.waitForTimeout(150);
  console.log('band over the whole view ', JSON.stringify(await st()), '| picking took', Math.round(await page.evaluate(() => window.__band)), 'ms, drawing', Math.round(await page.evaluate(() => window.__render)), 'ms');
  await page.keyboard.press('Escape'); await page.waitForTimeout(80);
  console.log('Escape                   ', JSON.stringify(await st()), '| sent', JSON.stringify(await page.evaluate(() => window.__sent.filter(n => !/sheet_/.test(n)))));
  await browser.close();
})();
