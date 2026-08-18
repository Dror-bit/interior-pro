// t47 - Ctrl+Z has to work MORE THAN ONCE (2026-08-17).
//
// The user: "אני שוב מזיז קירות ואז לוחץ Z והם לא חוזרים למקום האחרון שזאת
// הפעולה האחרונה שעשיתי." (Ctrl+Z, confirmed - he was asked and was not
// impressed by the question.)
//
// HOW UNDO REACHES THIS WINDOW AT ALL. Ctrl combinations never arrive as key
// events in a SketchUp HtmlDialog - that was verified back in 2026-07-30. What
// DOES arrive is the browser's editing pipeline: a focused contenteditable
// holding one undoable edit turns Ctrl+Z into a 'beforeinput' of inputType
// 'historyUndo'. The editor cancels the text undo and runs its own instead.
//
// THE BUG. That only works while the hidden element still HAS an undoable edit
// of its own, and the arming was a one-time latch - dataset.armed was set on
// the first canvas click and never cleared. So the whole editor had exactly
// ONE undoable edit for as long as the window stayed open. Spend it, or lose
// it because the focus went to a side panel and came back, and Ctrl+Z stopped
// reaching the editor at all. Nothing threw. Nothing was logged. The walls
// simply stayed where they were.
//
// Repeated Ctrl+Z is how anybody undoes a mess. It has to keep working with no
// mouse click in between, which is the case this suite is really about.
const fs = require('fs');

let fails = 0;
function ok(name, cond, extra) {
  console.log((cond ? 'PASS  ' : 'FAIL  ') + name + (cond ? '' : '   << ' + JSON.stringify(extra)));
  if (!cond) fails++;
}

const src = fs.readFileSync('out.js', 'utf8');
const arm = src.slice(src.indexOf('function armHiddenUndo('),
                      src.indexOf('function armHiddenUndo(') + 900);
const hook = src.slice(src.indexOf("hu.addEventListener('beforeinput'"),
                       src.indexOf("hu.addEventListener('beforeinput'") + 700);

// ---------------------------------------------------------------- the latch
ok('the arming routine is still there', arm.indexOf('function armHiddenUndo(') === 0);
ok('THE ONE-TIME LATCH IS GONE  <<< the bug',
   !/dataset\.armed/.test(arm), arm.match(/.*dataset\.armed.*/g));
ok('arming always puts a fresh edit in',
   /execCommand\('insertText'/.test(arm), arm.slice(0, 200));
ok('and clears first, so the placeholder cannot grow',
   /textContent\s*=\s*''/.test(arm), arm.slice(0, 300));

// -------------------------------------------------- the second Ctrl+Z in a row
ok('the undo hook is still listening for historyUndo',
   /inputType === 'historyUndo'/.test(hook), hook.slice(0, 120));
ok('it still cancels the browser text undo', /preventDefault\(\)/.test(hook));
ok('it still runs the editor undo', /undoAction\(\)/.test(hook));
ok('AND RELOADS FOR THE NEXT PRESS  <<< without this, Ctrl+Z works exactly once',
   /armHiddenUndo/.test(hook), hook.slice(0, 400));

const uIdx = hook.indexOf('undoAction()');
const rIdx = hook.indexOf('armHiddenUndo');
ok('the reload happens after the undo, not before', uIdx >= 0 && rIdx > uIdx, [uIdx, rIdx]);

// Redo is still deliberately swallowed - there is no redo in this editor, and
// letting the browser redo the placeholder text would be worse than nothing.
ok('redo is still refused', /'historyRedo'/.test(hook) &&
   /historyRedo'\) \{ ev\.preventDefault\(\)/.test(hook.replace(/\s+/g, ' ')),
   hook.slice(-160));

// ------------------------------------------------- what undo must still do
// The order matters and is deliberate: half-finished things first (they are an
// action being typed, not an action), then the history, then SketchUp's stack.
const ua = src.slice(src.indexOf('function undoAction()'),
                     src.indexOf('function undoAction()') + 700);
['curLine', 'arcPts', 'circC', 'measB', 'measA', 'dimPlace', 'dimA', 'dragEnd']
  .forEach(function (half) {
    ok('undo still backs off a half-finished ' + half, ua.indexOf(half) > 0);
  });
ok('then the editor history', ua.indexOf('histUndo()') > 0);
ok('and only then SketchUp\'s own stack', ua.indexOf('sketchup.undo_model()') >
   ua.indexOf('histUndo()'));

// A wall move is a model action, so it has to be ON the history stack or the
// undo has nothing to pop and goes straight past it.
ok('moving a wall sideways is recorded before it is sent',
   /histModel\('move_wall'\);\s*\n\s*sketchup\.move_wall\(/.test(src),
   (src.match(/histModel\('move_wall'\);[\s\S]{0,60}/) || [])[0]);
ok('moving a selection is recorded before it is sent',
   /histModel\('move_selection'\);\s*\n\s*sketchup\.move_selection\(/.test(src),
   (src.match(/histModel\('move_selection'\);[\s\S]{0,60}/) || [])[0]);
ok('a model entry asks SketchUp to undo',
   /h\.kind === 'model'.*sketchup\.undo_model\(\)/.test(src.replace(/\s+/g, ' ')));

// The history is a stack with a cap, and popping is what undo does.
ok('the history is bounded so a long session cannot eat the window',
   /HIST_MAX/.test(src));
ok('undo pops the newest entry', /editHist\.pop\(\)/.test(src));

console.log(fails === 0 ? '\nALL PASS' : '\n*** ' + fails + ' FAILED ***');
process.exit(fails === 0 ? 0 : 1);
