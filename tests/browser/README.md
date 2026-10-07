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
| shot.js       | screenshots (fit and zoomed) to compare pixel for pixel before/after  |

`window.sketchup` is a stand-in in every script: Ruby's answers are played back
by hand where a script needs them. So these prove the WINDOW; Ruby's side is
rt266 / rt267, and his machine is `sheet_erase_trace.txt`.
