# Storage — Wardrobe / Laundry — 2026-10-16

## Laundry catalog increment

Laundry now includes upper cabinets, fixed-dimension LG front/top-load washers,
matching electric dryers, a verified front-load stacked option and both side-by-side
presets. The common editor product chooser and 2D adapter handle all these products.
Upper bottom height/shelves are editable; 2D placement retains elevation. Uppers
draw dashed, machines show selected planning clearances, and Alt-click cycles
overlapping items. Manufacturer dimensions are locked and cannot leak into the
cabinet dimension limits when switching products. See ../laundry/STATUS.md and
../laundry/CATALOG.md for exact products, primary sources, tested gates and limits.

This supersedes the earlier Laundry-base-only and appliance-catalog-pending notes
below. Wardrobe, Kitchen, Vanity and the shared contract retain their behavior.

One combined Extensions entry; independent source namespaces and product adapters.
The existing loader uses storage/tool.rb. This increment does not edit main.rb,
Kitchen, pantry, Vanity, electrical or shared Cabinetry contracts.

## Toolbar and house plan — 2026-10-16

A dedicated Storage toolbar button opens the combined editor. The editor has
Open house plan, Place in 2D and Move in 2D buttons. Storage-owned runtime
adapters add wardrobe/laundry footprints to the existing house canvas without
editing plan_editor.rb or Kitchen. Drag moves, double-click edits, Delete removes;
Escape cancels placement/drag. Commands retain domain, assembly, cabinet ID and
revision and use the same service/3D geometry and native history. No duplicate
2D cabinet document is saved. No-op moves add no host history entry.

This slice supports floor placement on Level 1. Other levels, wall/opening snaps,
whole-room collisions and PDF/sheet export are not implemented. Existing
same-domain/assembly collision validation remains active. Fill distinguishes
wardrobes from laundry; the heavier edge marks the cabinet front.

USE_STORAGE_TOOLBAR and USE_STORAGE_2D are separate kill switches. The HtmlDialog
factory adapter binds callbacks only for the house editor before its HTML loads;
script injection is idempotent and retries on host refresh. Existing host keyboard,
draft and undo handlers are retained. The Storage toolbar follows SketchUp's
saved toolbar visibility after restart.

15 real house-canvas checks passed in scratch process 26772, including rotated
drag, source + geometry Undo/Redo, placement, delete/undo, correct editor routing,
stale edits, level filtering and cross-domain isolation, with no JS errors.
The actual toolbar was clicked and opened the editor; the real Place in 2D
callback armed the correct mode. Reports: plan-native-report.json and
plan-buttons-report.json. Pure plan projection and event tests passed. Full
legacy regression has 11 existing failures in this run, all in the previous
baseline; no new failures (plan-suite.log, plan-extra.log).

## Working products

Laundry retains its existing base cabinet, fronts, finishes and handles.
Wardrobe supports placement/edit/delete, shelves, hanging rods, drawer boxes,
open sections, single/double doors, slab/shaker fronts, finishes and handles.
Every board is a separate solid. Mode/assembly selections remain independent;
stale requests check domain, assembly and revision.

Wardrobe limits: width 12–48, height 48–108, depth 12–30 inches, eighth-inch
increments. Sections run bottom to top and must total height minus 5.5 inches
(4-inch toe and two 3/4-inch boards). Dimensions are never silently resized.
Hanging sections require nominal height 24 and depth 20 inches. Four nominal
7-inch drawer rows stay exact; face reveals and box deductions are separate.
Collision checks cover the same domain/assembly, not the whole room.

## Operations and interoperability

Design edits change source and geometry in one operation and abort both on build
failure. Root groups survive edits. Native floor Move, vertical Rotate and Eraser
synchronize source transparently into the native action. Scale, tilt, mirroring
and off-floor moves are restored. UI Undo/Redo use Sketchup.undo / Sketchup.redo;
observers only refresh after Undo/Redo. Observers reattach on model open even
when SketchUp reuses the Ruby Model wrapper.

Stable material names, in-operation MaterialIds stamping and persistent finish
references prevent V-Ray recreating materials after Undo. Each domain initializes
an uninstantiated definition containing small finish-reference faces; no scene
instance is added. Opening an editable mode may initialize these resources in
a separate operation before the first design edit. Purge unused can remove them;
the next edit initializes them again. V-Ray was not disabled or modified.
ConDoc's loader, folder and temporary backup were removed at the user's explicit
request. An older running SketchUp needs restart to unload it.

Kill switches: USE_STORAGE_TOOL, USE_NATIVE_SYNC, USE_WARDROBE_PRODUCTS,
Laundry::USE_FINISH_REFERENCES. Legacy USE_LAUNDRY_PILOT remains false.

## Verification

Fresh isolated SketchUp process 26772, ConDoc absent, V-Ray active: 40 native
checks passed across both modes, covering add/edit Undo/Redo, solids, finishes,
validation, build-failure rollback, native Move/Eraser Undo/Redo, scale rejection,
same-ID domain isolation and scratch save/reload. Native Move after reopening
also passed without manual observer installation. Ten real HtmlDialog checks
passed: save, Undo/Redo, validation, mode switching, placement cancellation and
delete/Undo. Development reports: wardrobe-native-report.json,
wardrobe-dialog-report.json, reopen-watch.json. Only scratch models were saved.

Pure checks passed: cabinetry/test_core.rb, laundry/test_domain.rb,
storage/test_wardrobe.rb, test_session.rb, test_editor.cjs. Full legacy regression
has the same 12 existing failures: t62, rt41, rt43, rt51, rt60, rt150, rt241,
rt246, rt287, rt289, rt294, rt329. No new failure in this run.

## Pending

Additional laundry products, verified appliance/sink catalogs and clearances,
countertops, backsplash, lighting/plumbing and PDF adapters. Native Copy/Paste,
nested group edits and manual board edits are not supported design commands.
The user's active model was not edited or saved; no Git commands were run.
