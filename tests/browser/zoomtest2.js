const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const payload = fs.readFileSync(process.argv[3], 'utf8');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1900, height: 1200 } });
  page.on('pageerror', e => console.log('PAGEERROR', e.message));
  await page.addInitScript(() => { window.sketchup = new Proxy({}, { get: () => function () {} }); });
  await page.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
  await page.evaluate(p => { loadSheet(JSON.parse(p)); }, payload);
  await page.waitForTimeout(300);
  const under = (x, y) => page.evaluate(([x, y]) => { const p = atMouse({ clientX: x, clientY: y }); const st = document.getElementById('stage'); const r = document.querySelector('#sheetWrap svg').getBoundingClientRect();
    return { model: p && p.map(v => Math.round(v)), zoom: ZOOM && +ZOOM.toFixed(2), scroll: [Math.round(st.scrollLeft), Math.round(st.scrollTop)], svg: [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)], stage: [st.clientWidth, st.clientHeight, st.scrollWidth, st.scrollHeight] }; }, [x, y]);
  const st = await page.evaluate(() => { const r = document.getElementById('stage').getBoundingClientRect(); return [r.left, r.top, r.width, r.height]; });
  for (const [fx, fy, label] of [[0.3, 0.35, 'upper-left of sheet'], [0.7, 0.7, 'lower-right of sheet'], [0.5, 0.5, 'middle'], [0.22, 0.85, 'lower-left'], [0.8, 0.2, 'upper-right']]) {
    await page.evaluate(() => { const w = document.getElementById('sheetWrap'); w.style.margin = ''; setZoom(null); STATE.zoom = null; const s = document.getElementById('stage'); s.scrollLeft = 0; s.scrollTop = 0; render(); });
    const x = st[0] + st[2] * fx, y = st[1] + st[3] * fy;
    await page.mouse.move(x, y);
    console.log(label, 'mouse', Math.round(x), Math.round(y));
    console.log('   start ', JSON.stringify(await under(x, y)));
    for (let i = 1; i <= 6; i++) {
      await page.mouse.wheel(0, -100);
      await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
      if (i === 1 || i === 3 || i === 6) console.log('   tick', i, JSON.stringify(await under(x, y)));
    }
    for (let i = 1; i <= 12; i++) { await page.mouse.wheel(0, 100); await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))); if (i === 6 || i === 12) console.log('   out ', i, JSON.stringify(await under(x, y))); }
  }
  await browser.close();
})();
