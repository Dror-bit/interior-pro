# Shared cabinetry foundation — phase 1

UPDATE: `geometry.rb` now provides explicit-input board and slab/shaker front
primitives. Laundry has an initial pilot; see `../laundry/STATUS.md` for tested
features and the unresolved native Undo/Redo gate. Its menu is disabled until
that gate passes. The original phase-1 scope below describes the foundation.

## Confirmed tool split — 2026-10-16

1. Existing Kitchen tool, INCLUDING pantry. Keep KitchenLab unchanged.
2. New standalone Vanity tool for bathroom cabinets.
3. ONE new Storage tool for BOTH wardrobes and laundry rooms, with two product modes.

Tool IDs: `storage`, `vanity`. Product/storage domains: `wardrobe`, `laundry`,
`vanity`. `domains_for_tool` and `tool_for_domain` define that mapping.
Laundry and wardrobe keep their existing storage keys for compatibility; they
must share one entry point and editor shell, not become two standalone tools.
Do not merge existing documents or reset them when switching product mode.
Vanity owns `vanity:<assembly_id>`; it is NOT part of KitchenLab. Pantry stays
entirely within the existing kitchen implementation.

This is a foundation, not two finished tools. `geometry.rb` has shared board and
front primitives; `laundry/` is a disabled legacy pilot with unresolved native
Undo/Redo. No wardrobe/vanity renderer, product catalog, PDF adapter or combined
Storage UI is implemented. No new menu is enabled by this change.

## Implemented contract

- `InteriorPro::Cabinetry.create(domain:, assembly_id:, settings: {})`
- `validate(document)`: JSON-compatible, independent copy; schema version 1,
  inches, nonnegative integer revision, finite dimensions and position.
- Each cabinet: `id`, `product_id`, `width`, `height`, `depth`,
  `position: {x,y,z,angle}`, `sections: []`. Angle in degrees; x/y/z in inches.
  Adopt kitchen coordinates: origin at back-left-bottom, +x right, -y front, +z up.
  A section has `id`, `kind`, `height`, ordered bottom to top; its nominal height
  includes reveals. Domain adapters must validate kinds and usable height after
  toe kicks, panel thickness and other construction deductions.
- `divide(height, count, step: 0.125)`: exact total, eighth-inch increments;
  28 / 4 => 7,7,7,7. Uneven divisions distribute eighths deterministically.
  No hidden rounding of custom dimensions; unsupported increments are rejected.
- `section_layout(sections, start: 0, reveal: 0.125)`: nominal dimension rows
  plus face offsets/heights; never show face deductions as nominal drawer sizes.
- `plan(source, commands, expected_revision:, validator:)`: pure atomic batch of
  `add`, `update`, `remove`, `settings`. Validator is mandatory and must check
  allowed products, construction constraints, appliance clearances and collisions.
  Generic core validation alone is NOT a placement or installation check.
  Update merges top-level keys; nested hashes are replaced, not deep-merged.
- `ModelStore.new(model)`: explicit model, no active-model/global dependency.
  `read(domain:, assembly_id:)` returns nil for missing designs.
  `write(document, expected_revision:)` uses optimistic revisions, nil for creation;
  create empty revision 0 first, then write planned revision 1. Identical no-op
  writes return unchanged. Keys are `laundry:<id>` / `wardrobe:<id>` / `vanity:<id>` under
  `InteriorPro::Cabinetry`, never `KitchenLab`.
- `stamp(group, document, cabinet_id, role: 'cabinet')` sets ownership under that
  same dictionary. Never use KitchenLab kinds for standalone tool groups.

## Transaction integration required in phase 2

Read -> plan/validate -> start ONE native operation -> revision-checked write ->
build/update only owned geometry -> commit. On ANY failure abort. Do not nest
operations. Native undo/redo owns both source attributes and generated geometry;
UI observers still need implementation and native verification by each tool.
Delete/move observers must filter domain AND assembly AND cabinet IDs.
Do not run whole-house or kitchen rebuilds from a new tool.

`ruby cabinetry/test_core.rb` runs without SketchUp. Test geometry, reload,
undo/redo, deletion, PDF layers and real product fit when implementing adapters.

## Shared-code ownership

The Storage chat owns new `storage/` files and the existing `laundry/` pilot;
wardrobe and laundry are handled in that SAME chat. The Vanity chat owns new
`vanity/` files. Both read `cabinetry/`; shared-core changes must be coordinated
with the coordinating chat to prevent conflicting edits. Do not clone KitchenLab
or swap its global state. No wholesale renderer migration is authorized here.

Read `HANDOFF_STORAGE.md` or `HANDOFF_VANITY.md`. Old handoff filenames are redirects
only. Inspect current `main.rb` before coordinating loader changes. Currently it
loads `laundry/tool.rb`, whose pilot flag remains false. Replace that entry only
when the combined Storage tool is ready and its regression gates pass.
