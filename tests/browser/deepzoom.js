const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const payload = fs.readFileSync(process.argv[3], 'utf8');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1900, height: 1200 } });
  page.on('pageerror', e => console.log('PAGEERROR', e.message));
  await page.addInitScript(() => { window.sketchup = new Proxy({}, { get: () => function () {} }); });
  await page.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
  // lift the limit for the measurement only
  await page.evaluate(p => { loadSheet(JSON.parse(p)); }, payload);
  await page.evaluate(() => { const src = zoomAt.toString().replace('0.2), 14)', '0.2), 400)'); window.zoomAt = eval('(' + src + ')'); });
  const x = 790, y = 720;      // on the house wall
  await page.mouse.move(x, y);
  let last = Date.now();
  for (let i = 1; i <= 38; i++) {
    const t0 = Date.now();
    await page.evaluate(([x, y]) => { zoomAt(x, y, (ZOOM || 1) * 1.15); }, [x, y]);
    await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
    const dt = Date.now() - t0;
    const info = await page.evaluate(([x, y]) => { const r = document.querySelector('#sheetWrap svg').getBoundingClientRect(); const p = atMouse({ clientX: x, clientY: y }); const st = document.getElementById('stage');
      const p2 = atMouse({ clientX: x + 100, clientY: y });
      return { zoom: +ZOOM.toFixed(1), svgW: Math.round(r.width), under: p.map(v => +v.toFixed(1)), inchesAcross100px: +(p2[0] - p[0]).toFixed(2), scrollW: st.scrollWidth, scroll: Math.round(st.scrollLeft) }; }, [x, y]);
    if ([13, 19, 22, 25, 28, 31, 34, 38].includes(i)) { console.log('click', i, dt + 'ms', JSON.stringify(info)); if (process.argv[4] && [19, 28, 38].includes(i)) await page.screenshot({ path: process.argv[4] + '_' + i + '.png' }); }
  }
  await browser.close();
})();
