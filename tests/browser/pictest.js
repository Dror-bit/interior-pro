// pictest.js SHEET.html PAYLOAD.json IMG_DIR [STATE_OUT.json] - pictures in boxes of their own, in a real browser, on his drawing
// PAYLOAD is one Ruby laid out (gen_box.rb with STATE_JSON naming pictures); IMG_DIR holds the same picture files here.
const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const payload = fs.readFileSync(process.argv[3], 'utf8'); const dir = path.resolve(process.argv[4]);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1900, height: 1200 } });
  page.on('pageerror', e => console.log('PAGEERROR', e.message));
  await page.addInitScript(() => { window.__sent = []; window.sketchup = new Proxy({}, { get: (t, name) => function (arg) { window.__sent.push([name, arg]); } }); });
  await page.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
  await page.evaluate(([p, d]) => { const q = JSON.parse(p); q.state.strip = false; q.rotate = true; q.view_box = true; q.pic_box = true;
    const here = x => ({ path: x.path, url: 'file://' + d + '/' + x.path.split('/').pop(), there: true });
    q.images = (q.images || []).map(here); q.pics = (q.pics || []).map(here); loadSheet(q); }, [payload, dir]);
  await page.waitForTimeout(600);
  const r3 = n => Math.round(n * 1000) / 1000;
  const pic = id => page.evaluate(i => { let f = null; PAGE.layers.forEach(l => l.shapes.forEach(s => { if (s.pic === i) f = s; })); if (!f) return null; const r = picRect(f); const q = n => Math.round(n * 1000) / 1000;
    return { box: [q(r.x), q(r.y), q(r.w), q(r.h)], rot: r.rot, crop: r.crop.map(q), placed: !!f.placed }; }, id);
  // a spot of the picture FILE (u across, v up) -> the pixel of the screen it is drawn on
  const spot = (id, u, v) => page.evaluate(([i, u, v]) => { let f = null; PAGE.layers.forEach(l => l.shapes.forEach(s => { if (s.pic === i) f = s; })); const r = picRect(f), c = r.crop, fw = r.w / (1 - c[0] - c[2]), fh = r.h / (1 - c[1] - c[3]);
    const lx = -r.w / 2 + (u - c[0]) * fw, ly = -r.h / 2 + (v - c[1]) * fh, t = r.rot * Math.PI / 180; const px = r.x + r.w / 2 + lx * Math.cos(t) - ly * Math.sin(t), py = r.y + r.h / 2 + lx * Math.sin(t) + ly * Math.cos(t);
    const b = document.querySelector('#sheetWrap svg').getBoundingClientRect(); return [b.left + px * LIVEK, b.top + (PAGE.height - py) * LIVEK]; }, [id, u, v]);
  const mid = async id => { const b = await page.locator('#' + id).boundingBox(); return [b.x + b.width / 2, b.y + b.height / 2]; };
  const sent = () => page.evaluate(() => window.__sent.filter(m => m[0] === 'set_state').length);
  const st = () => page.evaluate(() => ({ bsel: BSEL, undo: UNDO.length, zoom: ZOOM, holding: !!BOXD || !!ROT }));
  const drag = async (from, dx, dy, steps, keep) => { await page.mouse.move(from[0], from[1]); await page.mouse.down();
    for (let i = 1; i <= steps; i++) await page.mouse.move(from[0] + dx * i / steps, from[1] + dy * i / steps); await page.waitForTimeout(40); if (!keep) { await page.mouse.up(); await page.waitForTimeout(60); } };
  const near = (a, b) => Math.abs(a[0] - b[0]) < 0.6 && Math.abs(a[1] - b[1]) < 0.6;
  console.log('pictures on the plan sheet', JSON.stringify(await page.evaluate(() => pagePics().map(s => s.pic))), '| natural sizes loaded:',
    JSON.stringify(await page.evaluate(() => Array.from(document.querySelectorAll('#sheetWrap svg svg image')).map(i => { const im = new Image(); im.src = i.getAttribute('href'); return im.width + 'x' + im.height; }))));
  await page.screenshot({ path: 'pics_open.png' });
  console.log('x:0 as Ruby placed it ', JSON.stringify(await pic('x:0')));
  console.log('x:1 as saved          ', JSON.stringify(await pic('x:1')));
  await page.evaluate(() => { window.__rd = []; const rr = render; window.render = function (m) { const a = performance.now(); rr(m); document.getElementById('sheetWrap').getBoundingClientRect(); window.__rd.push(performance.now() - a); }; });
  // pick x:0 by clicking its middle, drag it
  const c0 = await spot('x:0', 0.5, 0.5);
  await page.mouse.move(c0[0], c0[1]); await page.mouse.down(); await page.mouse.up(); await page.waitForTimeout(50);
  console.log('clicked               ', JSON.stringify(await st()), '| sent', await sent(), '| square on its corner:', near(await mid('boxc-nw'), await spot('x:0', 0, 1)));
  await drag(c0, -260, 120, 20);
  console.log('dragged               ', JSON.stringify(await pic('x:0')), '| sent', await sent());
  // a corner, then the right side in, then the top in
  await drag(await mid('boxc-se'), 120, 160, 15);
  console.log('corner pulled out     ', JSON.stringify(await pic('x:0')));
  const k1 = await spot('x:0', 0.3, 0.5);
  await drag(await mid('boxe-e'), -110, 0, 15);
  await drag(await mid('boxe-n'), 0, 90, 15);
  console.log('cut right and top     ', JSON.stringify(await pic('x:0')), '| picture stayed:', near(await spot('x:0', 0.3, 0.5), k1));
  // the round arrow
  const rh = await mid('rothandle'), cc = await spot('x:0', 0.5 * 1, 0.5);
  await page.mouse.move(rh[0], rh[1]); await page.mouse.down();
  const pc = await page.evaluate(i => { let f = null; PAGE.layers.forEach(l => l.shapes.forEach(s => { if (s.pic === i) f = s; })); const r = picRect(f); const b = document.querySelector('#sheetWrap svg').getBoundingClientRect(); return [b.left + (r.x + r.w / 2) * LIVEK, b.top + (PAGE.height - r.y - r.h / 2) * LIVEK]; }, 'x:0');
  const a0 = Math.atan2(rh[1] - pc[1], rh[0] - pc[0]), rad = Math.hypot(rh[0] - pc[0], rh[1] - pc[1]);
  for (let i = 1; i <= 25; i++) { const a = a0 - (35 * Math.PI / 180) * i / 25; await page.mouse.move(pc[0] + rad * Math.cos(a), pc[1] + rad * Math.sin(a)); }
  await page.waitForTimeout(40);
  console.log('turning, held         ', JSON.stringify(await pic('x:0')), '| label', await page.evaluate(() => document.getElementById('rotdeg').textContent));
  await page.mouse.up(); await page.waitForTimeout(60);
  console.log('turned                ', JSON.stringify(await pic('x:0')), '| sent', await sent(), '| square on its turned corner:', near(await mid('boxc-ne'), await spot('x:0', 1 - (await pic('x:0')).crop[2], 1 - (await pic('x:0')).crop[3])));
  const k2 = await spot('x:0', 0.3, 0.5);
  await drag(await mid('boxe-w'), 40, -25, 10);
  console.log('turned, left side cut ', JSON.stringify(await pic('x:0')), '| picture stayed:', near(await spot('x:0', 0.3, 0.5), k2));
  const t = await page.evaluate(() => window.__rd);
  console.log('drawing the sheet per step:', t.length, 'times, average', (t.reduce((x, y) => x + y, 0) / t.length).toFixed(0), 'ms, worst', Math.max.apply(null, t).toFixed(0), 'ms');
  await page.screenshot({ path: 'pics_worked.png' });
  // Escape in the middle; Ctrl+Z once
  const cm = await spot('x:0', 0.3, 0.5);
  await drag(cm, 200, 0, 5, true); await page.keyboard.press('Escape'); await page.mouse.up(); await page.waitForTimeout(50);
  console.log('Escape mid-drag       ', JSON.stringify((await pic('x:0')).box), JSON.stringify(await st()));
  await page.keyboard.press('Control+z'); await page.waitForTimeout(50);
  console.log('Ctrl+Z (the last cut) ', JSON.stringify(await pic('x:0')));
  // the drawing's own box still works with pictures on the sheet
  await page.mouse.click(300, 300); await page.waitForTimeout(40);
  await drag(await mid('boxe-e'), -200, 0, 8);
  console.log('drawing cut, no picture picked:', JSON.stringify(await page.evaluate(() => { const v = PAGE.views[0]; return [v.x, v.y, v.w, v.h].map(n => Math.round(n * 1000) / 1000); })), '| x:0 untouched', JSON.stringify((await pic('x:0')).box));
  // the picture sheet
  await page.evaluate(() => goToPage(1)); await page.waitForTimeout(300);
  console.log('picture sheet, opened ', JSON.stringify(await pic('m:0')), '| pictures', JSON.stringify(await page.evaluate(() => pagePics().map(s => s.pic))), '| handles on it:', near(await mid('boxc-nw'), await spot('m:0', 0, 1)));
  await drag(await mid('boxc-se'), -500, -310, 15);
  await drag(await mid('boxe-w'), 150, 0, 10);
  const mrh = await mid('rothandle');
  await drag(mrh, -60, -160, 12);
  console.log('its picture: sized, cut, turned', JSON.stringify(await pic('m:0')));
  const c2 = await spot('x:2', 0.5, 0.5);
  await drag(c2, 380, -150, 12);
  console.log('the one added beside it, dragged', JSON.stringify(await pic('x:2')), JSON.stringify(await st()));
  await page.screenshot({ path: 'pics_sheet2.png' });
  if (process.argv[5]) fs.writeFileSync(process.argv[5], await page.evaluate(() => JSON.stringify({ pics: STATE.pics, image_geo: STATE.image_geo, images: STATE.images, view_box: STATE.view_box || null, origin_x: STATE.origin_x, origin_y: STATE.origin_y })));
  await browser.close();
})();
