const { chromium } = require('playwright');
const fs = require('fs'); const path = require('path');
(async () => {
  const payload = fs.readFileSync(process.argv[3], 'utf8');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1900, height: 1200 } });
  page.on('pageerror', e => console.log('PAGEERROR', e.message));
  await page.addInitScript(() => {
    window.__calls = {};
    window.sketchup = new Proxy({}, { get: (t, name) => function () { window.__calls[name] = (window.__calls[name] || 0) + 1; } });
  });
  await page.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
  await page.evaluate(p => { loadSheet(JSON.parse(p)); }, payload);
  await page.waitForTimeout(400);
  // count real renders and the time spent inside them
  await page.evaluate(() => {
    window.__r = { n: 0, ms: 0 };
    const orig = window.render;
    window.render = function () { const a = performance.now(); const v = orig.apply(this, arguments); document.getElementById('sheetWrap').getBoundingClientRect(); window.__r.n++; window.__r.ms += performance.now() - a; return v; };
  });
  const reset = () => page.evaluate(() => { window.__r = { n: 0, ms: 0 }; });
  const stat = () => page.evaluate(() => ({ renders: window.__r.n, msInRender: Math.round(window.__r.ms), nodes: document.querySelectorAll('#sheetWrap svg *').length }));
  const mid = async () => page.evaluate(() => { const r = document.getElementById('stage').getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; });
  for (const strip of ['ON', 'OFF']) {
    const want = strip === 'ON' ? 'on' : '';
    if ((await page.evaluate(() => document.getElementById('strip').className)) !== want) await page.evaluate(() => toggleStrip());
    let c = await mid();
    // 1. Alt-drag: moving the drawing on the sheet
    await reset();
    const o0 = await page.evaluate(() => [STATE.origin_x, STATE.origin_y]);
    await page.mouse.move(c.x, c.y); await page.keyboard.down('Alt'); await page.mouse.down();
    let t0 = Date.now();
    for (let i = 1; i <= 40; i++) await page.mouse.move(c.x + i * 5, c.y + i * 2);
    let dt = Date.now() - t0;
    await page.mouse.up(); await page.keyboard.up('Alt');
    const o1 = await page.evaluate(() => [STATE.origin_x, STATE.origin_y]);
    console.log(`strip ${strip}  ALT-DRAG 40 steps: ${dt} ms = ${Math.round(dt / 40)} ms/step`, JSON.stringify(await stat()), 'moved', Math.round(o1[0] - o0[0]), Math.round(o1[1] - o0[1]));
    // 2. wheel zoom in 10 ticks then out 10
    await reset();
    t0 = Date.now();
    for (let i = 0; i < 10; i++) { await page.mouse.wheel(0, -100); await page.evaluate(() => new Promise(r => requestAnimationFrame(() => r()))); }
    dt = Date.now() - t0;
    console.log(`strip ${strip}  WHEEL 10 ticks in: ${dt} ms = ${Math.round(dt / 10)} ms/tick`, JSON.stringify(await stat()), 'zoom', await page.evaluate(() => ZOOM));
    await reset();
    t0 = Date.now();
    for (let i = 0; i < 10; i++) { await page.mouse.wheel(0, 100); await page.evaluate(() => new Promise(r => requestAnimationFrame(() => r()))); }
    dt = Date.now() - t0;
    console.log(`strip ${strip}  WHEEL 10 ticks out: ${dt} ms = ${Math.round(dt / 10)} ms/tick`, JSON.stringify(await stat()));
    // 3. shift-drag pan
    await reset();
    await page.mouse.move(c.x, c.y); await page.keyboard.down('Shift'); await page.mouse.down();
    t0 = Date.now();
    for (let i = 1; i <= 40; i++) await page.mouse.move(c.x - i * 3, c.y - i * 2);
    dt = Date.now() - t0;
    await page.mouse.up(); await page.keyboard.up('Shift');
    console.log(`strip ${strip}  SHIFT-PAN 40 steps: ${dt} ms = ${Math.round(dt / 40)} ms/step`, JSON.stringify(await stat()));
  }
  if (process.argv[4]) await page.screenshot({ path: process.argv[4] });
  await browser.close();
})();
