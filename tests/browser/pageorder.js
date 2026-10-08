// pageorder.js SHEET.html - dragging a row of the page list, in a real browser (real mouse, real keyboard)
const { chromium } = require('playwright'); const path = require('path');
(async () => {
  const browser = await chromium.launch(); let bad = 0; const ok = (c, m) => { if (!c) bad++; console.log((c ? '  ok   ' : '  FAIL ') + m); };
  const page = await browser.newPage({ viewport: { width: 1500, height: 950 } });
  page.on('pageerror', e => { bad++; console.log('PAGEERROR', e.message); });
  await page.addInitScript(() => { window.__sent = []; window.sketchup = new Proxy({}, { get: (t, name) => function (arg) { window.__sent.push([name, arg]); } }); });
  await page.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
  await page.evaluate(() => {
    const pg = (name, kind, ref, num, mark) => ({ name, width: 36, height: 24, kind, ref, sheet_number: num, views: [],
      layers: [{ name: 'TITLE', visible: true, shapes: [{ type: 'text', text: num + '  ' + name, x: 30, y: 1, h: 0.4, h0: 0.4 },
        { type: 'text', text: mark, x: 18, y: 12, h: 3, h0: 3, align: 'center' }] }] });
    loadSheet({ doc: { canvases: [{ name: 'MODEL', layers: [{ name: 'WALLS', visible: true, shapes: [{ type: 'line', x1: 0, y1: 0, x2: 200, y2: 100, weight: 0.02 }] }] }],
      pages: [pg('FLOOR PLAN', 'plan', null, 'A-101', 'PLAN'), pg('RENDERING 1', 'image', 0, 'A-102', 'R1'), pg('RENDERING 2', 'image', 1, 'A-103', 'R2'), pg('RENDERING 3', 'image', 2, 'A-104', 'R3')] },
      state: { size: 'ARCH D', orientation: 'landscape', scale: '1/4"', hidden: [], origin_x: 0, origin_y: 0, active: 0, marks: [], images: ['a', 'b', 'c'], open: {}, strip: true,
               text_scale: { dims: 100, rooms: 100, tags: 100, tables: 100 }, text_marks: {}, site_count: 0, site_dropped: 0, pics: [], image_geo: {}, texts: [] },
      page_sizes: ['ARCH D'], scales: ['1/4"'], images: [], logo: null, bounds: [0, 0, 200, 100] });
  });
  await page.waitForTimeout(500);
  const st = () => page.evaluate(() => ({ keys: DOC.pages.map(pageKey), order: STATE.page_order, active: STATE.active, undo: UNDO.length,
    sent: window.__sent.filter(m => m[0] === 'set_state').length, cls: Array.from(document.querySelectorAll('#pages .pg')).map(r => r.className),
    rows: Array.from(document.querySelectorAll('#pages .pg span')).map(r => r.textContent), strip: Array.from(document.querySelectorAll('#strip .thumb .cap span')).map(r => r.textContent.trim()),
    drag: PGDRAG }));
  const row = i => page.evaluate(k => { const r = document.querySelectorAll('#pages .pg')[k].getBoundingClientRect(); return [r.left + 60, r.top + r.height / 2, r.height]; }, i);
  let a = await st();
  ok(a.rows.join('|') === 'FLOOR PLAN|RENDERING 1|RENDERING 2|RENDERING 3', 'the list, the old order: ' + a.rows.join(' | '));
  // drag RENDERING 3 to the top, in 8 steps, and time the steps
  let r3 = await row(3), r0 = await row(0);
  await page.mouse.move(r3[0], r3[1]); await page.mouse.down();
  const t0 = Date.now();
  for (let k = 1; k <= 8; k++) await page.mouse.move(r3[0], r3[1] + (r0[1] - r0[2] / 2 + 3 - r3[1]) * k / 8);
  const ms = (Date.now() - t0) / 8;
  a = await st();
  ok(/drag/.test(a.cls[3]) && /dropb/.test(a.cls[0]) && a.sent === 0, 'while dragging: the row faded, the yellow line over the first row, nothing sent (' + ms.toFixed(1) + ' ms a step)');
  await page.screenshot({ path: 'order_dragging.png' });
  await page.mouse.up(); await page.waitForTimeout(150);
  a = await st();
  ok(a.keys.join(',') === 'image:2,plan,image:0,image:1' && a.rows[0] === 'RENDERING 3', 'LET GO: RENDERING 3 is first in the list: ' + a.rows.join(' | '));
  ok(a.strip[0].indexOf('RENDERING 3') >= 0, 'and first in the strip of little sheets: ' + a.strip.join(' | '));
  ok(a.sent === 1 && a.order.join(',') === 'image:2,plan,image:0,image:1', 'Ruby told once, with the order');
  ok(a.active === 1 && a.keys[a.active] === 'plan', 'the open sheet is still the plan (the click after the drag did not open another)');
  ok(a.cls.every(c => !/drop|drag/.test(c)), 'no line left behind');
  await page.screenshot({ path: 'order_after.png' });
  // a plain click still opens a sheet
  let rr = await row(3); await page.mouse.click(rr[0], rr[1]); await page.waitForTimeout(120); a = await st();
  ok(a.active === 3 && a.keys.join(',') === 'image:2,plan,image:0,image:1' && a.sent === 2, 'a plain click on a row opens that sheet, the order stays');
  // Escape mid-drag (the list has the focus now)
  rr = await row(2); r0 = await row(0);
  await page.mouse.move(rr[0], rr[1]); await page.mouse.down(); await page.mouse.move(rr[0], rr[1] - 15); await page.mouse.move(rr[0], r0[1] - 5);
  await page.keyboard.press('Escape'); await page.waitForTimeout(80); a = await st();
  ok(a.drag === null && a.cls.every(c => !/drop|drag/.test(c)), 'Escape mid-drag drops it');
  await page.mouse.up(); await page.waitForTimeout(120); a = await st();
  ok(a.keys.join(',') === 'image:2,plan,image:0,image:1', 'letting go after Escape changes nothing');
  // Ctrl+Z with the list in focus
  await page.keyboard.press('Control+z'); await page.waitForTimeout(120); a = await st();
  ok(a.keys.join(',') === 'plan,image:0,image:1,image:2' && a.order === null && a.rows[0] === 'FLOOR PLAN', 'CTRL+Z: the old order back: ' + a.rows.join(' | '));
  ok(a.keys[a.active] === 'image:1', 'and the sheet that was open (RENDERING 2) is still open: ' + a.keys[a.active]);
  // the x is not a handle
  const n0 = (await st()).sent;
  const x = await page.evaluate(() => { const b = document.querySelectorAll('#pages .pg button')[1].getBoundingClientRect(); return [b.left + b.width / 2, b.top + b.height / 2]; });
  await page.mouse.move(x[0], x[1]); await page.mouse.down(); r0 = await row(0); await page.mouse.move(x[0], r0[1] - 5); await page.mouse.up(); await page.waitForTimeout(100); a = await st();
  ok(a.keys.join(',') === 'plan,image:0,image:1,image:2' && a.drag === null, 'a press on the x is not a drag');
  console.log(bad ? '*** ' + bad + ' FAILED' : 'all ok');
  await browser.close();
})();
