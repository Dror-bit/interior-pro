# Storage tool: wardrobes AND laundry rooms

Read CODEX_KITCHEN_BRIEF.md fully, cabinetry/README.md, core.rb, model_store.rb,
geometry.rb, and laundry/STATUS.md before changes. Latest user decision overrides
older handoffs: ONE tool for wardrobes and laundry; Vanity is separate; pantry
stays Kitchen. Own storage/ and laundry/. Do not modify vanity/, kitchen/,
electrical_library.rb or shared cabinetry contracts without coordination.

## First delivery

Build ONE entry point and editor shell with Wardrobe / Laundry product modes.
Use Cabinetry.domains_for_tool('storage'). Keep existing laundry:<id> and
wardrobe:<id> documents and ownership stamps; mode switches must not overwrite
another design. Scope selection, edits and observers by domain, assembly and ID.
Reuse the disabled laundry pilot as a starting point, not as a released tool.
First resolve native Undo/Redo in a clean scratch model: one action must undo
BOTH source and geometry and redo both. Read the known deferred MaterialIds
watcher issue in laundry/STATUS.md. Do not blindly undo the user's live model.
Keep the pilot disabled until this passes; coordinate replacing its main.rb
loader line with the combined tool rather than adding a second Laundry button.

Use pure plan/validation then ONE native operation for data, geometry and hosted
objects, with abort on failure. Test native Move and Eraser synchronization too;
UI move/delete alone is insufficient. Use explicit model/material inputs and
shared primitives; never copy the entire kitchen engine or borrow its globals.

## Product modes after the first working slice

Wardrobe: shelves, hanging rods, drawers, open/closed sections, single/double
doors, dimensions for sections and drawers, cabinet-specific finishes/handles.
Laundry: base/upper/tall storage, sink cabinets, washer/dryer bays and stacked
machines using available verified assets and installation clearances. Do not
invent product dimensions or stretch appliances. Confirm missing catalog choices.
Nominal drawer heights sum exactly (28 / 4 = 7), display eighths without long
floating decimals. Keep domain-specific defaults and fit validation separate.

Countertops, backsplash, lighting, plumbing and PDF are explicit later adapters,
not already implemented reuse. Coordinate shared work once. Preserve Kitchen and
Vanity settings/geometry. Test create/edit/reopen, rejected edits, rotated placement,
move/delete, native Undo/Redo, save/reload on a scratch copy, mode switching and
cross-domain isolation. Each board remains a separate solid group.
Report implemented vs pending honestly. Never save the user's model or run Git;
the user commits. Deliver one working slice before expanding the catalog.
