// boxtest.js SHEET.html PAYLOAD.json [PAYLOAD_BOXED_BY_RUBY.json] - the drawing's box, in a real browser, on his drawing
const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const payload = fs.readFileSync(process.argv[3], 'utf8');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1900, height: 1200 } });
  page.on('pageerror', e => console.log('PAGEERROR', e.message));
  await page.addInitScript(() => { window.__sent = []; window.sketchup = new Proxy({}, { get: (t, name) => function (arg) { window.__sent.push([name, arg]); } }); });
  await page.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
  await page.evaluate(p => { const q = JSON.parse(p); q.state.strip = false; q.rotate = true; q.view_box = true; loadSheet(q); }, payload);
  await page.waitForTimeout(400);
  const r2 = n => Math.round(n * 100) / 100;
  const st = () => page.evaluate(() => { const v = PAGE.views[0]; const r = n => Math.round(n * 1000) / 1000;
    return { box: [r(v.x), r(v.y), r(v.w), r(v.h)], scale_f: STATE.scale_f ? r(STATE.scale_f * 1000) / 1000 : null, scale: STATE.scale, zoom: ZOOM, sl: document.getElementById('stage').scrollLeft, undo: UNDO.length,
      list: document.getElementById('scale').value, holding: !!BOXD }; });
  const mid = async id => { const b = await page.locator('#' + id).boundingBox(); return [b.x + b.width / 2, b.y + b.height / 2]; };
  const sent = () => page.evaluate(() => window.__sent.filter(m => m[0] === 'set_state').map(m => { const s = JSON.parse(m[1]); return [s.view_box && s.view_box.map(n => Math.round(n * 100) / 100), s.scale_f && Math.round(s.scale_f * 10000) / 10000]; }));
  console.log('opened              ', JSON.stringify(await st()));
  const se0 = await mid('boxc-se'), nw0 = await mid('boxc-nw');
  console.log('squares on screen: nw', nw0.map(r2), 'se', se0.map(r2));
  await page.evaluate(() => { window.__rd = []; const rr = render; window.render = function (m) { const a = performance.now(); rr(m); document.getElementById('sheetWrap').getBoundingClientRect(); window.__rd.push(performance.now() - a); }; });
  // the bottom right corner, pulled in
  await page.mouse.move(se0[0], se0[1]); await page.mouse.down();
  for (let i = 1; i <= 30; i++) await page.mouse.move(se0[0] - i * 18, se0[1] - i * 11.2);
  await page.waitForTimeout(60);
  console.log('corner held, pulled in', JSON.stringify(await st()));
  await page.mouse.up(); await page.waitForTimeout(100);
  console.log('let go               ', JSON.stringify(await st()), '| sent', JSON.stringify(await sent()));
  await page.screenshot({ path: 'box_small.png' });
  // moved by its grip
  const g = await mid('boxmove');
  await page.mouse.move(g[0], g[1]); await page.mouse.down();
  for (let i = 1; i <= 20; i++) await page.mouse.move(g[0] + i * 14, g[1] + i * 8);
  await page.mouse.up(); await page.waitForTimeout(100);
  console.log('moved by the grip    ', JSON.stringify(await st()), '| sent', JSON.stringify(await sent()));
  await page.screenshot({ path: 'box_moved.png' });
  const t = await page.evaluate(() => window.__rd);
  console.log('drawing the sheet per step:', t.length, 'times, average', (t.reduce((x, y) => x + y, 0) / t.length).toFixed(0), 'ms, worst', Math.max.apply(null, t).toFixed(0), 'ms');
  // pushed against the margins
  const g2 = await mid('boxmove');
  await page.mouse.move(g2[0], g2[1]); await page.mouse.down(); await page.mouse.move(g2[0] + 900, g2[1] - 700, { steps: 8 }); await page.mouse.move(g2[0] + 2500, g2[1] - 2500, { steps: 4 }); await page.mouse.up(); await page.waitForTimeout(80);
  const s3 = await st(); const area = await page.evaluate(() => boxArea());
  console.log('pushed at the margins', JSON.stringify(s3.box), 'area', JSON.stringify(area.map(r2)), 'inside:', s3.box[0] + s3.box[2] <= area[0] + area[2] + 1e-6 && s3.box[1] + s3.box[3] <= area[1] + area[3] + 1e-6);
  // Escape in the middle, then Ctrl+Z three times
  const c = await mid('boxc-nw');
  await page.mouse.move(c[0], c[1]); await page.mouse.down(); await page.mouse.move(c[0] + 120, c[1] + 80, { steps: 5 });
  console.log('second resize, held  ', JSON.stringify((await st()).box));
  await page.keyboard.press('Escape'); await page.mouse.up(); await page.waitForTimeout(60);
  console.log('Escape               ', JSON.stringify((await st()).box));
  for (let i = 0; i < 3; i++) { await page.keyboard.press('Control+z'); await page.waitForTimeout(60); console.log('Ctrl+Z               ', JSON.stringify(await st())); }
  if (process.argv[4]) {
    const p2 = await browser.newPage({ viewport: { width: 1900, height: 1200 }, deviceScaleFactor: 4 });
    await p2.addInitScript(() => { window.sketchup = new Proxy({}, { get: () => function () {} }); });
    await p2.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
    await p2.evaluate(p => { loadSheet(JSON.parse(p)); }, fs.readFileSync(process.argv[4], 'utf8'));
    await p2.waitForTimeout(400);
    const r = await p2.evaluate(() => { const b = document.querySelector('#sheetWrap svg').getBoundingClientRect(); return [b.left, b.top, b.width, b.height]; });
    await p2.screenshot({ path: 'box_window_big.png', clip: { x: r[0], y: r[1], width: r[2], height: r[3] } });
    await p2.screenshot({ path: 'box_window_ui.png' });
    console.log('ruby-boxed sheet drawn', JSON.stringify(await p2.evaluate(() => { const v = PAGE.views[0]; return [v.x, v.y, v.w, v.h, STATE.scale_f, document.getElementById('scale').value]; })));
  }
  await browser.close();
})();
