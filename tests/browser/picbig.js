// picbig.js SHEET.html PAYLOAD.json IMG_DIR OUT_PREFIX - every sheet of a Ruby-made payload, drawn by the window, 2x
const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const dir = path.resolve(process.argv[4]);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1900, height: 1200 }, deviceScaleFactor: 2 });
  await page.addInitScript(() => { window.sketchup = new Proxy({}, { get: () => function () {} }); });
  await page.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
  const n = await page.evaluate(([p, d]) => { const q = JSON.parse(p); q.state.strip = false;
    const here = x => ({ path: x.path, url: 'file://' + d + '/' + x.path.split('/').pop(), there: true });
    q.images = (q.images || []).map(here); q.pics = (q.pics || []).map(here); loadSheet(q); setMode('dim'); return DOC.pages.length; }, [fs.readFileSync(process.argv[3], 'utf8'), dir]);
  for (let i = 0; i < n; i++) {
    await page.evaluate(k => { STATE.active = k; render(); }, i); await page.waitForTimeout(500);
    const r = await page.evaluate(() => { const b = document.querySelector('#sheetWrap svg').getBoundingClientRect(); return [b.left, b.top, b.width, b.height]; });
    await page.screenshot({ path: process.argv[5] + '_' + (i + 1) + '.png', clip: { x: r[0], y: r[1], width: r[2], height: r[3] } });
  }
  await browser.close();
})();
