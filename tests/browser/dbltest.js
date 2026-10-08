// dbltest.js SHEET.html PAYLOAD.json TEXT_RULES.json - two quick presses on a dimension's number, in a real browser, on his drawing
const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const payload = fs.readFileSync(process.argv[3], 'utf8'); const rules = fs.readFileSync(process.argv[4], 'utf8');
  const browser = await chromium.launch();
  console.log('browser', browser.version());
  let bad = 0; const ok = (c, m) => { if (!c) bad++; console.log((c ? '  ok   ' : '  FAIL ') + m); };
  const run = async (label, zoomSteps) => {
    const page = await browser.newPage({ viewport: { width: 1700, height: 1000 } });
    page.on('pageerror', e => { bad++; console.log('PAGEERROR', e.message); });
    await page.addInitScript(() => { window.__sent = []; window.__ev = [];
      window.sketchup = new Proxy({}, { get: (t, name) => function (arg) { window.__sent.push([name, arg]); } });
      ['click', 'dblclick'].forEach(n => document.addEventListener(n, e => window.__ev.push(n + '@' + (e.target.id || e.target.tagName)), true)); });
    await page.goto('file://' + path.resolve(process.argv[2]), { waitUntil: 'load' });
    await page.evaluate(([p, r]) => { const q = JSON.parse(p); q.state.strip = false; q.rotate = true; q.view_box = true; q.pic_box = true; q.text_box = true; q.text_words = true; q.text_rules = JSON.parse(r); loadSheet(q); }, [payload, rules]);
    await page.waitForTimeout(700);
    const targets = () => page.evaluate(() => { const r = document.getElementById('sheetWrap').firstChild.getBoundingClientRect(); const out = {};
      const m = marks()[0], lab = dimLabelXY(m), ls = screenOf(lab[0], lab[1]); out.handNumber = [r.left + ls[0], r.top + ls[1]];
      const L = dimLine(m), a = screenOf(L[0], L[1]), b = screenOf(L[2], L[3]); out.handLine = [r.left + a[0] * 0.8 + b[0] * 0.2, r.top + a[1] * 0.8 + b[1] * 0.2];
      let best = null; eachText(function (s, paper) { if (paper || !s.key || !/^DIMENSIONS\|/.test(s.key)) return; const bx = textBox(s, paper); const c = [r.left + bx.x + bx.w / 2, r.top + bx.y + bx.h / 2]; if (c[0] > 300 && c[0] < 1400 && c[1] > 100 && c[1] < 900 && Math.hypot(c[0] - out.handNumber[0], c[1] - out.handNumber[1]) > 150 && distToSeg(c[0] - r.left, c[1] - r.top, a, b) > 60 && !(PICON && hitPic({ clientX: c[0], clientY: c[1] })) && (!best || bx.w > best.w)) best = { c: c, key: s.key }; });
      out.wallNumber = best ? best.c : null; out.wallKey = best ? best.key : null;
      const n = marks()[1], nc = screenOf(n.x, n.y); out.note = [r.left + nc[0], r.top + nc[1]]; return out; });
    const st = () => page.evaluate(() => ({ LED: LED ? LED.kind : null, editor: document.getElementById('tbedit').className, value: document.getElementById('tbedit').value, TSEL: TSEL ? TSEL.key : null, dim: TSEL ? TSEL.dim : null, focus: document.activeElement && document.activeElement.id, CARRY: !!CARRY, TCARRY: !!TCARRY, SEL: SEL, zoom: ZOOM, sl: document.getElementById('stage').scrollLeft, st_: document.getElementById('stage').scrollTop, mark0: JSON.stringify(marks()[0]), notebar: document.getElementById('notebar').className, ev: window.__ev.join(' ') }));
    const press = async (pt, gap) => { await page.mouse.move(pt[0], pt[1]); await page.mouse.down(); await page.mouse.up(); await page.waitForTimeout(gap); await page.mouse.down({ clickCount: 2 }); await page.mouse.up({ clickCount: 2 }); await page.waitForTimeout(150); };
    const reset = async () => { await page.keyboard.press('Escape'); await page.waitForTimeout(60); await page.evaluate(() => { document.activeElement && document.activeElement.blur && document.activeElement.blur(); escapeAll(); window.__ev = []; window.__sent = []; }); await page.waitForTimeout(60); };
    let t = await targets();
    if (zoomSteps) { await page.mouse.move(t.handNumber[0], t.handNumber[1]); for (let i = 0; i < zoomSteps; i++) { await page.mouse.wheel(0, -120); await page.waitForTimeout(30); } await page.waitForTimeout(200); }
    console.log('\n' + label);
    // 1. the hand dimension's number
    await reset(); t = await targets(); const before = await st();
    await press(t.handNumber, 90); let a = await st();
    ok(a.LED === 'label' && a.editor === 'on one' && a.focus === 'tbedit', 'hand dimension, its NUMBER: two presses open the words (editor "' + a.editor + '", focus ' + a.focus + ', value "' + a.value + '")');
    ok(a.dim === 0 && !a.CARRY, 'it is the mark\'s own number and nothing is being carried');
    ok(a.mark0 === before.mark0, 'the dimension did not move');
    ok(a.zoom === before.zoom && a.sl === before.sl && a.st_ === before.st_, 'the view did not move');
    await page.keyboard.type('12 V.I.F.'); await page.keyboard.press('Enter'); await page.waitForTimeout(120);
    a = await st(); const lab = await page.evaluate(() => marks()[0].label);
    ok(lab === '12 V.I.F.' && a.LED === null && a.editor === '', 'typed and Enter: the words are on the mark ("' + lab + '") and the editor is shut');
    ok(await page.evaluate(() => window.__sent.some(m => m[0] === 'set_state')), 'Ruby was told');
    await page.keyboard.press('Control+z'); await page.waitForTimeout(120);
    ok(await page.evaluate(() => marks()[0].label === undefined), 'Ctrl+Z takes the words back');
    // 2. Escape
    await reset(); t = await targets(); await press(t.handNumber, 90); await page.keyboard.type('zzz'); await page.keyboard.press('Escape'); await page.waitForTimeout(100);
    a = await st(); ok(a.LED === null && a.editor === '' && await page.evaluate(() => marks()[0].label === undefined), 'Escape drops what was typed');
    // 3. its line
    await reset(); t = await targets(); await press(t.handLine, 90); a = await st();
    ok(a.LED === 'label' && a.dim === 0, 'hand dimension, its LINE: two presses open its number');
    // 4. a wall dimension
    await reset(); t = await targets();
    if (t.wallNumber) { await press(t.wallNumber, 90); a = await st();
      ok(a.LED === 'label' && a.TSEL === t.wallKey && a.focus === 'tbedit' && !a.TCARRY, 'wall dimension ' + t.wallKey + ': two presses open the words (value "' + a.value + '")');
      await page.keyboard.type('ABC'); await page.keyboard.press('Enter'); await page.waitForTimeout(100);
      ok(await page.evaluate(k => window.__sent.some(m => m[0] === 'set_text_mark' && JSON.parse(m[1]).key === k && JSON.parse(m[1]).text === 'ABC'), t.wallKey), 'typed and Enter: Ruby gets the words under the label\'s key'); }
    // 5. two SLOW presses are still pick up / put down
    await reset(); t = await targets(); await press(t.handNumber, 650); a = await st();
    ok(a.LED === null && a.editor === '' && !a.CARRY, 'two slow presses (650 ms): picked up and put down, nothing opens');
    // 6. one press still picks it up (a while after the last press: three quick ones in a row are not tested here)
    await reset(); await page.waitForTimeout(600); t = await targets(); await page.mouse.move(t.handNumber[0], t.handNumber[1]); await page.mouse.down(); await page.mouse.up(); await page.waitForTimeout(120); a = await st();
    ok(a.CARRY && a.SEL === 0 && a.LED === null, 'one press: the dimension is picked up, as before');
    // 7. a note is left alone
    await reset(); t = await targets(); await press(t.note, 90); a = await st();
    console.log('  note  two presses on a note: notebar "' + a.notebar + '", editor "' + a.editor + '", events: ' + a.ev);
    ok(a.LED === null, 'a note does not open the label editor');
    if (!zoomSteps) { await reset(); t = await targets(); await press(t.handNumber, 90); await page.screenshot({ path: 'dbl_open.png', clip: { x: Math.max(0, t.handNumber[0] - 260), y: Math.max(0, t.handNumber[1] - 130), width: 520, height: 260 } }); }
    await page.close();
  };
  await run('[whole sheet]', 0);
  await run('[zoomed in, 8 clicks of the wheel]', 8);
  await browser.close();
  console.log(bad ? ('\n' + bad + ' FAILED') : '\nall ok');
  process.exit(bad ? 1 : 0);
})();
