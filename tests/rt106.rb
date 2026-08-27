# encoding: utf-8
# rt106 - A RE-LAY THROWS AWAY THE WHOLE FIELD, WHATEVER THE MATERIAL
# (2026-09-03).
#
# He put a dormer on a Spanish roof and on the square-tile roof and got no
# hole in the tiles, and twice the tile round the gable: "שלא נוצר חור
# ברעפים בספניש ובטיל המרובעים וגם הספאניש מכפיל את כמות הטיל מסביב
# לגמלון".
#
# One line did both. relay_runs! erased instances whose DEFINITION NAME
# starts with 'IP_TileRun' - the generated pipe, and nothing else. The flat
# tile is IP_TileFlatWedge, pressed metal is IP_TileSheet and his own
# Spanish tile is a component out of his own file. On those three the old
# field survived and the new one was laid on top of it, so the roof carried
# two fields - and the older one had been laid before the dormer existed,
# which is why the hole was not there.
#
# THE CLAIMS PINNED HERE
# 1. field_part? knows the three field stamps and only those.
# 2. field_piece? answers off the DEFINITION's stamp, not its name, and
#    still says yes to a legacy IP_TileRun that predates the stamp.
# 3. The eave bar ('tile_edge') is NOT the field. relay_runs! does not lay
#    it again, so erasing it would leave the roof without its frame.
# 4. The user's own asset tile - a foreign name and no stamp at all - is
#    matched by identity when the asset is known, and left alone when it
#    is not ours to erase.
#
# Against the old code claims 1-4 all fail: the two methods do not exist.
require './sketchup_stub'
require './roof_tile_math'
require './roof_tile_parts'
require './roof_tile_place'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

PLACE = InteriorPro::RoofTilePlace

# ---- 1. the stamps ---------------------------------------------------
ok('tile_run is the field',   PLACE.field_part?('tile_run'))
ok('tile_sheet is the field', PLACE.field_part?('tile_sheet'))
ok('tile_flat is the field',  PLACE.field_part?('tile_flat'))
ok('tile_edge is NOT the field',  !PLACE.field_part?('tile_edge'))
ok('ridge_cap is NOT the field',  !PLACE.field_part?('ridge_cap'))
ok('nothing at all is NOT the field', !PLACE.field_part?(nil))

# ---- the pieces, exactly as roof_tile_parts.rb stamps them -----------
def defn(name, part = nil)
  d = Sketchup::ComponentDefinition.new(name)
  d.set_attribute('InteriorPro', 'part', part) if part
  d
end

pipe  = defn('IP_TileRun_roman_14.00_3.84_0.33_10.00_8', 'tile_run')
sheet = defn('IP_TileSheet_metaltile_7.00_5.95_1.31_0.45_8', 'tile_sheet')
flat  = defn('IP_TileFlatWedge_slate_12.60_0.70', 'tile_flat')
bar   = defn('IP_TileEdgeDeck_seam_1.00', 'tile_edge')
eave  = defn('IP_TileEave_roman_14.00_3.84_4.00', 'tile_eave')
mine  = defn('Roman Tiled Roof#1')             # his own file: no stamp
legacy = defn('IP_TileRun_seamRib_29.00_1.00_0.33_28.00_8')  # stamped before

# ---- 2 and 3. what a re-lay may erase --------------------------------
ok('the generated pipe goes',        PLACE.field_piece?(pipe))
ok('pressed metal goes',             PLACE.field_piece?(sheet))
ok('the square tile goes',           PLACE.field_piece?(flat))
ok('a legacy IP_TileRun still goes', PLACE.field_piece?(legacy))
ok('the eave bar STAYS',             !PLACE.field_piece?(bar))
ok('the eave piece STAYS',           !PLACE.field_piece?(eave))
ok('nothing at all stays',           !PLACE.field_piece?(nil))

# ---- 4. his own tile --------------------------------------------------
ok('his own tile goes when it IS the asset',
   PLACE.field_piece?(mine, { defn: mine }))
ok('a foreign component we did not place STAYS',
   !PLACE.field_piece?(mine, { defn: flat }))
ok('a foreign component STAYS when there is no asset at all',
   !PLACE.field_piece?(mine))

# ---- the whole roof, one sweep ---------------------------------------
# A Spanish roof carrying his own tile, its eave pieces and a ridge cap.
model = Sketchup.active_model
roof  = model.entities.add_group
tr    = Geom::Transformation.new
6.times { roof.entities.add_instance(mine, tr) }
3.times { roof.entities.add_instance(eave, tr) }
2.times { roof.entities.add_instance(bar,  tr) }
cap = roof.entities.add_group
cap.set_attribute('InteriorPro', 'part', 'ridge_cap')

asset = { defn: mine }
doomed = roof.entities.grep(Sketchup::ComponentInstance)
              .select { |i| PLACE.field_piece?(i.definition, asset) }
ok('all six of his tiles are thrown away', doomed.length == 6, doomed.length)
kept = roof.entities.grep(Sketchup::ComponentInstance) - doomed
ok('the five edge pieces stay', kept.length == 5, kept.length)
groups = roof.entities.grep(Sketchup::Group)
              .reject { |g| g.is_a?(Sketchup::ComponentInstance) }
ok('the ridge cap is a group, not an instance, and is never in the sweep',
   groups.length == 1 && groups.first.get_attribute('InteriorPro', 'part') == 'ridge_cap',
   groups.length)

puts($fails.zero? ? 'rt106 OK' : "rt106 #{$fails} FAILURES")
exit($fails.zero? ? 0 : 1)
