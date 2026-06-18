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
