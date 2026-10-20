# Laundry product mode — 2026-10-16

Laundry stays inside the shared Storage editor and house-plan 2D adapter. The old
standalone pilot remains disabled. Existing laundry:<assembly_id> documents and
base cabinets are preserved; no migration or Kitchen/Vanity state swap is used.

## Available

- Existing base cabinets and new upper cabinets, with editable bottom height and
  0–6 shelves. Defaults: 30 × 30 × 12, bottom 66 inches, two shelves. Native rigid
  upper Move can change mounting height in eighths; floor products stay on floor.
- LG front-load WM4000HWA washer and DLEX4000W electric dryer.
- LG top-load WT7400CW washer and DLE7400WE matching electric dryer. Both dryers
  load from the front; top loading applies to the washer.
- One verified front-load stacked product, with KSTK4 kit requirement, and two
  side-by-side presets (front-load pair or top-load washer + matching dryer).
  Individual machines also remain available. Catalog machines cannot be resized
  or manually elevated into an unverified stack.
- Catalog dimensions, source URLs, clearances and limitations: CATALOG.md.
  Geometry is a dimensioned schematic, not imported manufacturer CAD. No asset
  is stretched. Side-by-side preset dimensions are derived from the fixed parts
  and a shared one-inch gap.

## Validation and rendering

Every cabinet board is a separate solid. Appliance leaf components are separate
solids; composed presets retain a single owned root for source/native history.
Product/model identity, fixed dimensions, side/rear/open-door/lid/overhead planning
space and rotated/vertical collisions are validated before source/geometry edits.
The planning profile is open-front/rear-vented and checks the current Laundry
design. It does not approve house walls, ceilings, closet ventilation, anchoring,
plumbing, electrical, exhaust duct routing or the installation site.

The 2D adapter preserves upper mounting height, draws uppers dashed, shows machine
labels and selected service zones, and permits Alt-click to cycle overlapping
upper/lower items. Existing mode/assembly/revision checks and native history stay
in use. The product chooser locks machine dimensions and resets cabinet limits
when changing back to furniture. Wardrobe controls remain independent.

USE_UPPER_PRODUCTS and USE_APPLIANCE_PRODUCTS are new kill switches. Finish assets
remain uninstantiated per-domain definitions, with the extra appliance palette
only in Laundry. V-Ray is not modified or disabled; ConDoc is absent in fresh QA.

## Verification

Development artifacts are under Kitchen Plugin/laundry/catalog-qa. Native reports
guard process and scratch-model identity. The native gate covers all seven LG
products/presets and upper cabinets: fixed bounds, solid leaf components, create
Undo/Redo, rejected scaling, rotated/elevated edits, native Move/Eraser Undo/Redo,
Wardrobe root/source preservation, Kitchen source isolation, height-aware fit,
2D mounting height and scratch save/reload. Real HtmlDialog and house-canvas tests
cover catalog choices, upper dimensions/shelves, Undo/Redo, stack and side-by-side
placements, 2D upper elevation, mode isolation and JS errors. See native-report.json
and dialog-report.json for the actual pass and process ID.
Latest gates: 78 native assertions, 9 real UI assertions, and 7 additional history/
rollback checks passed in process 32488. History was cycled three times on a fresh
successful upper edit after an injected failed appliance rebuild. All artifacts
and snapshots belong to the disposable catalog-qa models.

Pure domain, catalog, core, session, plan, editor and product-switch tests pass.
Full legacy suite has no new failure; the 12 known environment failures remain:
t62, rt41, rt43, rt51, rt60, rt150, rt241, rt246, rt287, rt289, rt294, rt329.
No Git command ran. Only scratch models were saved/undone. No Kitchen, Vanity,
electrical, shared Cabinetry contract, main.rb or plan_editor.rb source was edited.

## Remaining scope

Sink/tall units, countertops, backsplash, hosted utilities, verified importable CAD,
additional brands, pedestal/alternative vent profiles and PDF/sheet adapters.
