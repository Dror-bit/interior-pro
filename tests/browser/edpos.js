// edpos.js SHEET.html TEXT_RULES.json PAYLOAD... - where the editor opens against the number it is opened on
const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const rules = fs.readFileSync(process.argv[3], 'utf8');
  const browser = await chromium.launch(); let shot = 0;
  for (const pf of process.argv.slice(4)) for (const strip of [false, true]) for (const which of ['hand', 'wall']) {
    const page = await browser.newPage({ viewport: { width: 1700, height: 1000 } });
    page.on('pageerror', e => console.log('PAGEERROR', e.message));
    await page.addInitScript(() => { window.sketchup = new Proxy({}, { get: () => function () {} }); });
    await page.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
    await page.evaluate(([p, r, strip]) => { const q = JSON.parse(p); q.state.strip = strip; q.rotate = true; q.view_box = true; q.pic_box = true; q.text_box = true; q.text_words = true; q.text_rules = JSON.parse(r); loadSheet(q); }, [fs.readFileSync(pf, 'utf8'), rules, strip]);
    await page.waitForTimeout(600);
    const find = () => page.evaluate((which) => { const r = document.getElementById('sheetWrap').firstChild.getBoundingClientRect();
      if (which === 'hand') { const m = marks()[0], lab = dimLabelXY(m), ls = screenOf(lab[0], lab[1]); return { pt: [r.left + ls[0], r.top + ls[1]] }; }
      let best = null; eachText(function (s, paper) { if (paper || !s.key || !/^DIMENSIONS\|/.test(s.key)) return; const p = screenOf(s.x, s.y); const c = [r.left + p[0], r.top + p[1]]; if (c[0] > 400 && c[0] < 1300 && c[1] > 150 && c[1] < 850 && (!best || String(s.text).length > best.n)) best = { pt: c, n: String(s.text).length }; }); return best; }, which);
    let t = await find(); if (!t) { console.log(pf, which, 'no target'); await page.close(); continue; }
    await page.mouse.move(t.pt[0], t.pt[1]); for (let i = 0; i < 14; i++) { await page.mouse.wheel(0, -120); await page.waitForTimeout(25); } await page.waitForTimeout(200);
    t = await find();
    await page.mouse.move(t.pt[0], t.pt[1]); await page.mouse.down(); await page.mouse.up(); await page.waitForTimeout(90); await page.mouse.down({ clickCount: 2 }); await page.mouse.up({ clickCount: 2 }); await page.waitForTimeout(200);
    const m = await page.evaluate(() => { const ed = document.getElementById('tbedit'); if (!LED || !TSEL) return { open: false };
      // the very <text> element the label is drawn as: same words, nearest to where the label should be
      const svg = document.getElementById('sheetWrap').firstChild, sr = svg.getBoundingClientRect(); const p = screenOf(TSEL.shape.x, TSEL.shape.y); let el = null, bd = 1e9;
      svg.querySelectorAll('text').forEach(x => { if (x.textContent !== String(TSEL.shape.text)) return; const d = Math.hypot(+x.getAttribute('x') - p[0], +x.getAttribute('y') - p[1]); if (d < bd) { bd = d; el = x; } });
      const tr = el ? (el.getAttribute('transform') || '') : ''; const ta = tr ? parseFloat(tr.replace('rotate(', '')) : 0; const tb = el.getBoundingClientRect();
      const et = ed.style.transform || ''; const ea = et ? parseFloat(et.replace('rotate(', '')) : 0; const eb = ed.getBoundingClientRect();
      return { open: true, turn: viewTurn().deg, VROT: VROT, textAngle: ta, editorAngle: ea, textMid: [Math.round(tb.left + tb.width / 2), Math.round(tb.top + tb.height / 2)], textSize: [Math.round(tb.width), Math.round(tb.height)],
               editorMid: [Math.round(eb.left + eb.width / 2), Math.round(eb.top + eb.height / 2)], editorSize: [Math.round(ed.offsetWidth), Math.round(ed.offsetHeight)], fontText: el.getAttribute('font-size'), fontEd: ed.style.fontSize }; });
    const off = m.open ? Math.round(Math.hypot(m.textMid[0] - m.editorMid[0], m.textMid[1] - m.editorMid[1])) : null;
    console.log(path.basename(pf).replace('perf_payload_', '').replace('.json', '') + ' strip ' + (strip ? 'ON ' : 'off') + ' ' + which + ': ' + (m.open ? ('angle text ' + m.textAngle + ' editor ' + m.editorAngle + ' (VROT ' + m.VROT + ', turn ' + m.turn + ') | middles ' + off + ' px apart | text ' + m.textSize + ' font ' + m.fontText + ' | editor ' + m.editorSize + ' font ' + m.fontEd) : 'DID NOT OPEN'));
    if (m.open) await page.screenshot({ path: 'ed_' + (shot++) + '.png', clip: { x: Math.max(0, t.pt[0] - 220), y: Math.max(0, t.pt[1] - 160), width: 440, height: 320 } });
    await page.close();
  }
  await browser.close();
})();
