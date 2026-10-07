const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const payload = fs.readFileSync(process.argv[3], 'utf8');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1900, height: 1200 } });
  await page.addInitScript(() => { window.sketchup = new Proxy({}, { get: () => function () {} }); });
  await page.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
  await page.evaluate(p => { loadSheet(JSON.parse(p)); }, payload);
  await page.waitForTimeout(400);
  await page.screenshot({ path: process.argv[4] + '_fit.png' });
  await page.evaluate(() => { setZoom(3); const st = document.getElementById('stage'); st.scrollLeft = 1500; st.scrollTop = 900; });
  await page.waitForTimeout(300);
  await page.screenshot({ path: process.argv[4] + '_zoom.png' });
  await browser.close();
})();
