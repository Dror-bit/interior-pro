const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const payload = fs.readFileSync(process.argv[3], 'utf8');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1900, height: 1200 } });
  page.on('pageerror', e => console.log('PAGEERROR', e.message));
  await page.addInitScript(() => {
    window.__sent = []; window.__t = {};
    window.sketchup = new Proxy({}, { get: (t, name) => function (arg) {
      window.__sent.push(name);
      if (name === 'drop_site_line') {
        const m = JSON.parse(arg); window.__t.asked = performance.now(); window.__t.quiet = !!m.quiet;
        const gone = m.is || [m.i];
        const p = JSON.parse(window.__payload);
        const site = p.doc.canvases[0].layers.find(l => l.name === 'SITE');
        gone.sort((a, b) => b - a).forEach(i => site.shapes.splice(i, 1));
        p.state.site_count = site.shapes.length;
        window.__payload = JSON.stringify(p);
        if (m.quiet) { siteDropped(site.shapes.length, gone.length); }
        else {
          // the window's own share of the old road: taking the whole sheet in again
          // (Ruby's share - reading the model, building, 1.5 MB of JSON - is NOT in here)
          const a = performance.now(); loadSheet(JSON.parse(window.__payload)); siteDropped(site.shapes.length, gone.length);
          document.getElementById('sheetWrap').getBoundingClientRect(); window.__t.loadSheet = performance.now() - a;
        }
      }
    } });
  });
  await page.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
  await page.evaluate(p => { window.__payload = p; loadSheet(JSON.parse(p)); }, payload);
  await page.waitForTimeout(300);
  const x = 700, y = 500;
  await page.mouse.move(x, y);
  for (let i = 0; i < 8; i++) { await page.mouse.wheel(0, -100); await page.waitForTimeout(40); }
  await page.evaluate(() => { setMode('erase'); const real = eraseSweep; window.eraseSweep = function (l) { const a = performance.now(); real(l); document.getElementById('sheetWrap').getBoundingClientRect(); window.__t.sweep = performance.now() - a; }; });
  const n0 = await page.evaluate(() => DOC.canvases[0].layers.find(l => l.name === 'SITE').shapes.length);
  await page.mouse.down();
  for (let i = 1; i <= 25; i++) await page.mouse.move(x + i * 6, y + i * 3);
  await page.mouse.up();
  await page.waitForTimeout(500);
  const r = await page.evaluate(() => ({ t: window.__t, left: DOC.canvases[0].layers.find(l => l.name === 'SITE').shapes.length, zoom: +ZOOM.toFixed(2), mode: MODE }));
  console.log(process.argv[2], 'lines', n0, '->', r.left, '| quick road:', r.t.quiet, '| the window spent', Math.round(r.t.sweep), 'ms on the sweep' + (r.t.loadSheet ? ', of which ' + Math.round(r.t.loadSheet) + ' ms taking the whole sheet in again' : ''), '| zoom', r.zoom, r.mode);
  await browser.close();
})();
