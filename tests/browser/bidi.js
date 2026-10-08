// bidi.js PAIRS.json - does Chromium lay a run of Hebrew the way PlanPDF.visual orders its letters for the PDF?
// PAIRS: {"original": "visual"} written by Ruby (tests/browser/gen_bidi.rb). Each original is drawn the browser's way;
// the visual order is drawn forced letter by letter (bidi-override). The two pictures must be the same.
const { chromium } = require('playwright'); const fs = require('fs');
(async () => {
  const pairs = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const browser = await chromium.launch(); const page = await browser.newPage({ viewport: { width: 900, height: 120 } });
  let bad = 0;
  for (const s of Object.keys(pairs)) {
    const v = pairs[s], e = x => x.replace(/&/g, '&amp;').replace(/</g, '&lt;');
    await page.setContent(`<html><body style="margin:0;background:#fff"><div style="font:28px 'DejaVu Sans';white-space:pre;padding:8px" id="a">${e(s)}</div><div style="font:28px 'DejaVu Sans';white-space:pre;padding:8px;direction:ltr;unicode-bidi:bidi-override" id="b">${e(v)}</div></body></html>`);
    await page.waitForTimeout(60);
    const ab = await page.locator('#a').screenshot(), bb = await page.locator('#b').screenshot();
    const [diff, n] = await page.evaluate(async ([a, b]) => { const load = d => new Promise(r => { const im = new Image(); im.onload = () => r(im); im.src = 'data:image/png;base64,' + d; });
      const ia = await load(a), ib = await load(b); if (ia.width !== ib.width || ia.height !== ib.height) return [1e9, 1];
      const c = document.createElement('canvas'); c.width = ia.width; c.height = ia.height; const g = c.getContext('2d');
      g.drawImage(ia, 0, 0); const da = g.getImageData(0, 0, c.width, c.height).data; g.clearRect(0, 0, c.width, c.height); g.drawImage(ib, 0, 0); const db = g.getImageData(0, 0, c.width, c.height).data;
      let d = 0; for (let i = 0; i < da.length; i += 4) if (Math.abs(da[i] - db[i]) > 60) d++; return [d, c.width * c.height]; }, [ab.toString('base64'), bb.toString('base64')]);
    const ok = diff < n * 0.004;   // a few pixels of kerning are not a different order
    if (!ok) bad++;
    console.log((ok ? '  ok   ' : '  DIFF ') + JSON.stringify(s) + '  ->  ' + JSON.stringify(v) + '  (' + diff + ' px)');
  }
  await browser.close(); console.log(bad ? ('*** ' + bad + ' differ') : 'all the same as the browser');
})();
