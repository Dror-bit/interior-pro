const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const payload = fs.readFileSync(process.argv[3], 'utf8');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1900, height: 1200 } });
  page.on('pageerror', e => console.log('PAGEERROR', e.message));
  await page.addInitScript(() => {
    window.__sent = [];
    window.sketchup = new Proxy({}, { get: (t, name) => function (arg) { window.__sent.push(name); } });
  });
  await page.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
  await page.evaluate(p => { loadSheet(JSON.parse(p)); }, payload);
  await page.waitForTimeout(300);
  const st = () => page.evaluate(() => { const s = document.getElementById('stage'); return { lines: DOC.canvases[0].layers.find(l => l.name === 'SITE').shapes.length, mode: MODE, zoom: ZOOM && +ZOOM.toFixed(2), scroll: [Math.round(s.scrollLeft), Math.round(s.scrollTop)], undo: UNDO.length }; });
  const x = 700, y = 500;
  await page.mouse.move(x, y);
  for (let i = 0; i < 8; i++) { await page.mouse.wheel(0, -100); await page.waitForTimeout(40); }
  await page.evaluate(() => setMode('erase'));
  console.log('start                    ', JSON.stringify(await st()));
  await page.mouse.down(); for (let i = 1; i <= 25; i++) await page.mouse.move(x + i * 6, y + i * 3); await page.mouse.up();
  await page.waitForTimeout(150);
  console.log('after sweep 1            ', JSON.stringify(await st()));
  await page.mouse.move(x + 300, y - 100);
  await page.mouse.down(); for (let i = 1; i <= 20; i++) await page.mouse.move(x + 300 + i * 5, y - 100 + i * 5); await page.mouse.up();
  await page.waitForTimeout(150);
  console.log('after sweep 2            ', JSON.stringify(await st()));
  // Escape in the middle of a third sweep
  await page.mouse.move(x - 200, y + 150);
  await page.mouse.down(); for (let i = 1; i <= 20; i++) await page.mouse.move(x - 200 + i * 6, y + 150 - i * 2);
  await page.keyboard.press('Escape');
  await page.mouse.up();
  await page.waitForTimeout(150);
  console.log('Escape mid-sweep 3       ', JSON.stringify(await st()));
  await page.keyboard.press('Control+z'); await page.waitForTimeout(150);
  console.log('Ctrl+Z (real keyboard)   ', JSON.stringify(await st()));
  await page.keyboard.press('Control+z'); await page.waitForTimeout(150);
  console.log('Ctrl+Z again             ', JSON.stringify(await st()));
  await page.keyboard.press('Control+z'); await page.waitForTimeout(150);
  console.log('Ctrl+Z with nothing left ', JSON.stringify(await st()), '| sent to Ruby:', JSON.stringify(await page.evaluate(() => window.__sent.filter(n => n !== 'sheet_probe' && n !== 'sheet_ready'))));
  await browser.close();
})();
