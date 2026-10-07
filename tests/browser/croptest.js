// croptest.js SHEET.html PAYLOAD.json [STATE_OUT.json] - a side of the drawing's box cuts the drawing, in a real browser, on his drawing
const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const payload = fs.readFileSync(process.argv[3], 'utf8');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1900, height: 1200 } });
  page.on('pageerror', e => console.log('PAGEERROR', e.message));
  await page.addInitScript(() => { window.__sent = []; window.sketchup = new Proxy({}, { get: (t, name) => function (arg) { window.__sent.push([name, arg]); } }); });
  await page.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
  await page.evaluate(p => { const q = JSON.parse(p); q.state.strip = false; q.rotate = true; q.view_box = true; q.box_crop = true; loadSheet(q); }, payload);
  await page.waitForTimeout(400);
  const r2 = n => Math.round(n * 100) / 100;
  // four spots of his yard, and where each is on the screen
  const spots = await page.evaluate(() => { const b = BOUNDS; return [[(b[0] + b[2]) / 2, (b[1] + b[3]) / 2], [b[0] + (b[2] - b[0]) * 0.3, b[1] + (b[3] - b[1]) * 0.6], [b[0] + (b[2] - b[0]) * 0.7, b[1] + (b[3] - b[1]) * 0.4], [b[0], b[3]]]; });
  const where = () => page.evaluate(sp => sp.map(p => screenOf(p[0], p[1]).map(n => Math.round(n * 1000) / 1000)), spots);
  const st = () => page.evaluate(() => { const v = PAGE.views[0]; const r = n => Math.round(n * 1000) / 1000;
    return { box: [r(v.x), r(v.y), r(v.w), r(v.h)], origin: [r(STATE.origin_x), r(STATE.origin_y)], scale_f: STATE.scale_f || null, scale: STATE.scale, zoom: ZOOM, undo: UNDO.length, list: document.getElementById('scale').value, holding: !!BOXD }; });
  const mid = async id => { const b = await page.locator('#' + id).boundingBox(); return [b.x + b.width / 2, b.y + b.height / 2]; };
  const same = (a, b) => a.every((p, i) => Math.abs(p[0] - b[i][0]) < 0.01 && Math.abs(p[1] - b[i][1]) < 0.01);
  const sent = () => page.evaluate(() => window.__sent.filter(m => m[0] === 'set_state').length);
  const w0 = await where();
  console.log('opened               ', JSON.stringify(await st()));
  console.log('cursor on a side     ', await page.evaluate(() => [getComputedStyle(document.getElementById('boxe-e')).cursor, getComputedStyle(document.getElementById('boxe-n')).cursor]));
  await page.evaluate(() => { window.__rd = []; const rr = render; window.render = function (m) { const a = performance.now(); rr(m); document.getElementById('sheetWrap').getBoundingClientRect(); window.__rd.push(performance.now() - a); }; });
  const pull = async (id, dx, dy, steps, keep) => { const c = await mid(id); await page.mouse.move(c[0], c[1]); await page.mouse.down();
    for (let i = 1; i <= steps; i++) await page.mouse.move(c[0] + dx * i / steps, c[1] + dy * i / steps); await page.waitForTimeout(40); if (!keep) { await page.mouse.up(); await page.waitForTimeout(60); } };
  await pull('boxe-e', -420, 0, 30, true);
  console.log('right side held, in  ', JSON.stringify(await st()), '| lines stayed:', same(await where(), w0), '| sent so far', await sent());
  await page.mouse.up(); await page.waitForTimeout(80);
  console.log('let go               ', JSON.stringify(await st()), '| sent', await sent());
  await pull('boxe-w', 300, 0, 20);
  await pull('boxe-n', 0, 170, 20);
  await pull('boxe-s', 0, -140, 20);
  const s4 = await st();
  console.log('cut on all four sides', JSON.stringify(s4), '| lines stayed:', same(await where(), w0), '| sent', await sent());
  const t = await page.evaluate(() => window.__rd);
  console.log('drawing the sheet per step:', t.length, 'times, average', (t.reduce((x, y) => x + y, 0) / t.length).toFixed(0), 'ms, worst', Math.max.apply(null, t).toFixed(0), 'ms');
  await page.screenshot({ path: 'crop_cut.png' });
  if (process.argv[4]) fs.writeFileSync(process.argv[4], await page.evaluate(() => JSON.stringify({ view_box: STATE.view_box, origin_x: STATE.origin_x, origin_y: STATE.origin_y, scale: STATE.scale, scale_f: STATE.scale_f || null, rotation: STATE.rotation || 0 })));
  // a turned drawing: turn it, cut it, the lines stay
  await page.evaluate(() => { STATE.rotation = 25; render(); });
  const wt = await where();
  await pull('boxe-e', -90, 0, 8); await pull('boxe-n', 0, 60, 8);
  console.log('turned 25, two cuts  ', JSON.stringify((await st()).box), '| lines stayed:', same(await where(), wt));
  await page.screenshot({ path: 'crop_turned.png' });
  await page.keyboard.press('Control+z'); await page.keyboard.press('Control+z'); await page.waitForTimeout(60);
  await page.evaluate(() => { STATE.rotation = 0; render(); });
  console.log('two Ctrl+Z, unturned ', JSON.stringify((await st()).box), '| lines stayed:', same(await where(), w0));
  // the margins
  await pull('boxe-e', 3000, 0, 6); await pull('boxe-n', 0, -3000, 6);
  const s5 = await st(); const area = await page.evaluate(() => boxArea());
  console.log('pulled out past the margins', JSON.stringify(s5.box), 'area', JSON.stringify(area.map(r2)), '| lines stayed:', same(await where(), w0));
  // Escape in the middle, then Ctrl+Z all the way back
  await pull('boxe-s', 0, -200, 6, true);
  console.log('a cut, held          ', JSON.stringify((await st()).box));
  await page.keyboard.press('Escape'); await page.mouse.up(); await page.waitForTimeout(60);
  console.log('Escape               ', JSON.stringify((await st()).box), '| lines stayed:', same(await where(), w0));
  for (let i = 0; i < 7; i++) { await page.keyboard.press('Control+z'); await page.waitForTimeout(40); }
  console.log('Ctrl+Z x7            ', JSON.stringify(await st()), '| lines stayed:', same(await where(), w0));
  await browser.close();
})();
