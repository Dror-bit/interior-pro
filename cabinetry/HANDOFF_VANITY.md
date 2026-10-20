# Standalone Vanity tool — bathroom cabinets

Read CODEX_KITCHEN_BRIEF.md fully, cabinetry/README.md, core.rb, model_store.rb
and geometry.rb before changes. User confirmed: Vanity is its own tool; Storage
combines wardrobes and laundry; pantry remains Kitchen. Older instructions placing
Vanity in Kitchen are superseded. Own new vanity/ files. Do not modify kitchen/,
storage/, laundry/, electrical_library.rb or shared contracts without coordination.

Use domain vanity and its isolated ModelStore key vanity:<assembly_id>, with
ownership stamps on generated groups. It is NOT a KitchenLab product family.
Reuse shared primitives and explicit gallery adapters; do not clone KitchenLab
or swap its model/settings globals. Coordinate one loader/menu registration.

First working slice: one vanity, editable width/depth/height, fronts/finish/handles,
compatible sink/faucet selection, placement/edit/move/delete/reopen and native
Undo/Redo. Confirm initial floor-standing or floating and basin configuration
with the user. Validate actual cabinet/sink clearances, not kitchen defaults;
use available verified gallery assets, never invented installation dimensions.
Floating units get no floor toe kick; do not inherit automatic kitchen crown.

Read laundry/STATUS.md for the unresolved native transaction issue; do not copy
that integration assuming Undo is verified. Use pure validation then ONE native
operation for source and geometry, abort on failure, and synchronize native Move
and Eraser. Test Undo/Redo in a separate scratch model without user edits.

Later variants: single/double basin, drawers/doors, countertop and sink cutouts,
plumbing adapters and plan/elevation/PDF with fixture dimensions on plumbing
layers. These are pending integrations, not existing foundation features.
Coordinate any plumbing/gallery or sheet call-site changes before editing.

Show nominal eighth-inch dimensions with exact drawer totals, not long decimals.
Test rejected edits, rotations, sink fit, reopen, move/delete, native Undo/Redo,
save/reload in a scratch copy, and Kitchen/Storage data and geometry unchanged.
Keep every board a separate solid. Never save the user's model or run Git.
Report exactly what works and what remains before expanding scope.
