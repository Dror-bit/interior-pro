# Project Rules for Claude

This project is a SketchUp interior design plugin. Your work is **restricted to doors only**.

## What you MAY do

- You may ONLY create and edit door-related files (e.g. `door_tool.rb`, `door_library.rb`, `door_library_dialog.rb`).
- You may make MINIMAL additive edits to `main.rb` and `toolbar.rb` ONLY to register the new door tool. Never change existing wall or window logic there.

## What you must NEVER edit

You must NEVER edit these files (you may READ them to learn patterns, but never modify):

- `wall_tool.rb`
- `wall_edit_tool.rb`
- `wall_move_tool.rb`
- `wall_merge_tool.rb`
- `wall_library.rb`
- `wall_library_dialog.rb`
- `window_tool.rb`
- `window_library.rb`
- `window_library_dialog.rb`
- `ui_dialogs.rb`

## Refusal rule

If asked to change wall or window behavior, refuse and say you are restricted to doors.

---

# UI rules (added 2026-08-07, set by the user)

## No duplicate ways to do the same thing

**Rotation covers flipping. Never build both.** Flip / mirror buttons
(left-right, up-down) and a rotation control are the same idea wearing a
different hat. Build the ROTATION only - a typed angle plus a quarter-turn
button - and leave flips out.

More generally: before adding a second control, ask whether an existing one
already does that job. If it does, do not add it. Fewer buttons, fewer
clicks. This is the user's standing preference for the whole plugin.

## Fewer clicks, always

- Clicking any tool button immediately runs that tool. No Escape first, no
  cancelling the previous mode by hand - the click itself cancels it.
- Panels stay open when the mode changes; the user must never reopen a panel
  to reach the tool they just used.
- Every action worth reaching for gets a single-letter keyboard shortcut.
  Current map: S select, D door, W window, L line, O guide line, M move,
  R rotate, U flip the guide angle to the other diagonal.
- Icons over words in dense panels: a dashed horizontal line beats the word
  "horizontal".

## Feedback

- A button that was pressed must LOOK pressed (Apply to Model shows a busy
  state until the model is built).
- The mouse cursor becomes the tool's own icon while move / rotate / offset
  are running, so the active mode is always visible.
