# Vanity — development slice, 2026-10-16

Independent `InteriorPro::Vanity`; data is `InteriorPro::Cabinetry` / `vanity:<assembly_id>`.
Pantry stays Kitchen. No Kitchen, Storage, Laundry, plumbing or shared-core source edits.
No Git commands. Each generated board/front member is its own group/solid.

Implemented in the new vanity files:
- Floor or floating cabinets; optional legs on floor cabinets, configurable leg height.
- Editable dimensions, placement and horizontal rotation; shaker/slab fronts, finishes, handles.
- One/two basin door-bay layouts. **No installed basin, faucet, countertop or cutout.**
  Unknown sink/faucet IDs are rejected; verified bathroom fixtures and installation
  clearances are still required. Two-basin minimum width is a layout guard, not
  a manufacturer's installation specification.
- Makeup cabinet with an optional drawer and knee space.
- Local gallery: copy one selected group/component definition into a new SKP plus
  metadata without modifying the source; place a separate copy. Imported assets
  retain fixed geometry/dimensions and require correctly prepared local axes.
- Editor placement, edit, move, delete and reopen; domain/assembly/role filtered
  synchronization for native Move, horizontal Rotate and Eraser.
- `USE_VANITY` is the geometry kill switch; `USE_VANITY_MENU` controls menu
  registration and `USE_FINISH_REFERENCES` controls retained finish references.
- One coordinated `main.rb` entry loads `vanity/tool.rb` and registers Extensions
  > Vanity. This remains a cabinet/editor preview, with fixtures pending.

Validation:
- `test_domain.rb` passes: product combinations, rejected fixture IDs, placement
  constraints, rotated cabinet collision and atomic rejection.
- Shared `cabinetry/test_core.rb` passes; its three source files match production.
- Ruby and editor JS syntax checks pass.
- Native QA artifacts are in the development workspace `Kitchen Plugin/vanity/`.
  `native-report.json` records the full strict native gate; `dialog-report.json`
  records actual HtmlDialog callbacks. Only reports for the current QA process
  are accepted by `install_verified.py`.
- Current verified run: 22 strict native checks and 12 real HtmlDialog checks
  passed with V-Ray active, including Undo/Redo, build-failure rollback, gallery
  callbacks and native Move after reopening. The live Extensions > Vanity menu
  was registered without changing the user's source documents or 98 entities.
- The full existing suite ran from a workspace copy. Missing icon/texture/kitchen
  fixtures were then copied in and only affected suites rerun. Baseline failures
  remain; this is not an all-green existing suite. Logs: `regression/`.
- SHA256 snapshot of 263 Kitchen/Laundry/shared source files remained unchanged.

**Native Undo/Redo gate resolved in Vanity only.**
The earlier failure is retained in `native-report-before-finish-references.json`.
V-Ray normalized slash-containing material names; palette-only preparation also
left materials without persistent references when Undo removed the last cabinet.
Vanity now uses stable material names and small material-reference faces in a
domain-owned, uninstantiated definition. It adds no scene instance. Resource
initialization is separate from each single source/geometry edit. No V-Ray or
shared MaterialIds implementation was changed or disabled. Root cabinet groups
survive edits. Purge unused may remove the definition; the next edit prepares it.
Existing imported geometry can be moved/deleted even when its gallery file is
unavailable; rebuilding/importing the asset still requires that file.
Native observers reattach after model reopen, including reused Model wrappers.

Remaining: verified bathroom sink/faucet adapters; countertops and actual sink
cutouts; gallery thumbnails and richer asset editing. Native copy/paste, manual
board edits and nested group edits are not supported design commands. Collision
validation covers only Vanity cabinets in the same assembly, not the whole room.
Never save or test Undo in the user's working model.
