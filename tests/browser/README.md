# tests/browser - the sheet window in a REAL browser, with his drawing

Written 2026-10-07. The node suites (t*.js) run the window's script with a fake
DOM: they can prove what the code decides, not how long the browser takes or
where the sheet really ends up on the screen. Three bugs that day were only
visible in a real browser - 15,394 elements rebuilt per mouse step, the zoom
running off to one side, the view jumping back after a rub-out - and all three
were measured, fixed and measured again here before he was asked to look.

These run in the CLOUD container (Chromium + Playwright are installed there),
not on his machine.

1. On his machine, in a copy of the plugin (never in the live folder):
   `ruby gen_perf.rb <bridge folder>` writes `perf_payload.json` (his real yard:
   `house_lines.json` + `nested_plan_doc.json`, made by debug_house_lines.rb and
   debug_nested_plan.rb) and `perf_sheet.html`. After a change to the window,
   `ruby extract_sheet.rb` in tests/ writes the new page as `sheet.html`.
2. Stage both files to the cloud (device_stage_files), copy the html next to
   these scripts, and run, e.g.
   `NODE_PATH=/opt/npm-tools/node_modules node perf2.js sheet.html perf_payload.json`

| script        | what it measures                                                     |
|---------------|----------------------------------------------------------------------|
| perf2.js      | ms per step: Alt-drag, wheel, Shift-pan; strip on and off             |
| zoomtest2.js  | does the spot under the mouse stay there, in 5 places, in and out     |
| deepzoom.js   | wheel up to 200x: ms per click, spot under the mouse                  |
| erasetime.js  | one sweep of the eraser: ms in the window; does the view move         |
| undotest.js   | two sweeps, Escape mid-sweep, Ctrl+Z twice - real keyboard            |
| picktest.js   | click, Shift+click, Delete, Ctrl+Z, a rubber band over the whole view |
| drawtest.js   | the two drawing tools: ring on a real corner, ms per mouse move, clicks, Escape, Ctrl+Z |
| rottest.js    | turning the drawing by its handle: ms per step, Escape, Ctrl+Z; screenshots to lay beside the PDF |
| gen_rot.rb    | (runs on his machine, in a copy) his real plan TURNED: the payload for the window and the PDF Ruby prints |
| boxtest.js    | the drawing in a box of its own: a corner (box and drawing grow together), the grip (box moves), the margins, Escape, Ctrl+Z; ms per step |
| croptest.js   | a side of the box cuts the drawing: do the lines stay on their spot, ms per step, a turned drawing, the margins, Escape, Ctrl+Z; writes the state it ends on |
| pictest.js    | pictures in boxes of their own, with real picture files: pick, drag, corner, cut, turn, Escape, Ctrl+Z, the picture sheet; ms per step; writes the state it ends on. Needs a payload Ruby laid out with pictures in it (gen_box.rb, STATE_JSON naming files) and a folder with the same files |
| gen_box.rb    | (runs on his machine, in a copy) his real plan in a box (and turned): the payload for the window and the PDF Ruby prints. STATE_JSON=file lays a state the window saved over it, OUT_NAME=crop names the files, ALL_PAGES=1 prints every sheet |
| shot.js       | screenshots (fit and zoomed) to compare pixel for pixel before/after  |
| dbltest.js    | two quick presses on a dimension's number (hand-drawn: number and line; a wall's): the words open over it, typing, Enter, Escape, Ctrl+Z, slow presses, one press; the view does not move. `node dbltest.js sheet.html perf_payload_dbl.json text_rules.json` - a payload from gen_box.rb, and PlanCanvas.text_rules as JSON. On the window before 2026-10-07 18:10 it fails: the browser sends no double click at all |
| edpos.js      | where the words of a number open against the number itself: the angle of both and how far apart their middles are, strip on and off, on every payload given. `node edpos.js sheet.html text_rules.json payload...` - give it one with a TURNED drawing and picture sheets (gen_box.rb 90 with STATE_JSON naming pictures): that is his window |

`window.sketchup` is a stand-in in every script: Ruby's answers are played back
by hand where a script needs them. So these prove the WINDOW; Ruby's side is
rt266 / rt267, and his machine is `sheet_erase_trace.txt`.
