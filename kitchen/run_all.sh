#!/usr/bin/env bash
# Includes the real editor WITH kitchen/, unlike flattened host test fixtures.
set -u
KITCHEN="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$KITCHEN")"
SCRATCH="$(mktemp -d)" || exit 1
trap 'rm -rf -- "$SCRATCH"' EXIT
cp -R "$ROOT/tests" "$SCRATCH/tests" || exit 1
mkdir "$SCRATCH/kitchen" || exit 1
cp "$ROOT/plan_editor.rb" "$SCRATCH/plan_editor.rb" || exit 1
cp "$KITCHEN/"*.rb "$KITCHEN/"*.js "$KITCHEN/"*.mjs "$KITCHEN/"*.html "$KITCHEN/"*.json "$KITCHEN/"*.svg "$SCRATCH/kitchen/" || exit 1
cp -R "$KITCHEN/assets" "$SCRATCH/kitchen/assets" || exit 1
fail=0
bash "$SCRATCH/tests/run_all.sh" "$ROOT" || fail=1
cd "$SCRATCH/kitchen" || exit 1
for test in test_house_editor_startup.rb test_kitchen_host_contract.rb test_kitchen_startup.rb test_engine.rb test_house_catalog_preview.rb test_kitchen_house_attachment.rb test_house_appliance_catalog.rb; do
  ruby "$test" || fail=1
done
for test in test_kitchen_house_placement.mjs test_kitchen_canvas_symbols.mjs test_spatial.mjs test_host_undo.mjs; do
  node "$test" || fail=1
done
exit "$fail"
