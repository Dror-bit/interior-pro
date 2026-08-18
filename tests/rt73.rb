# encoding: utf-8
# rt73 — the four new roof materials are WIRED UP, end to end.
#
# Step 2a of the 3D roof tiles (2026-08-18). No geometry yet: this suite only
# proves that choosing "Barrel Tile" in the dialog can actually reach a
# texture file on disk, and that the three files which have to agree about
# these materials do agree.
#
# The three files, and the thing that would silently break each one:
#   roof_tile_math.rb  SHAPES  ......  a material with no tile dimensions
#   roof_manager.rb    ROOF_TEXTURES   a texture name with no file behind it
#   roof_dialog.rb     mat_options ..  a material you cannot choose
#
# The most valuable assertion in here is the plain one: every texture file
# NAMED in the code EXISTS on disk. A missing jpg does not raise - it makes
# surface_material fall quietly back to a flat colour, and the user just sees
# "the tiles did not work" with nothing in any console.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_tile_math'
require './room_manager'
require './level_manager'
require './roof_manager'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

RTM = InteriorPro::RoofTileMath
RM  = InteriorPro::RoofManager
TEX = RM.roof_textures
NEW = %w[barrel roman slate seam].freeze

# Textures are NOT copied into tests/, so look in the source root first.
TEXDIR = ['../textures', './textures'].find { |d| File.directory?(d) }
SRC = ['../roof_dialog.rb', './roof_dialog.rb'].find { |f| File.file?(f) }
MAIN = ['../main.rb', './main.rb'].find { |f| File.file?(f) }

ok('the textures folder was found', !TEXDIR.nil?, TEXDIR)
ok('roof_dialog.rb was found', !SRC.nil?)
ok('main.rb was found', !MAIN.nil?)

# ------------------------------------------------- every material is known

NEW.each do |k|
  ok("#{k}: described in RoofTileMath::SHAPES", !RTM.shape(k).nil?)
  ok("#{k}: registered in ROOF_TEXTURES", TEX.key?(k), TEX.keys)
end
ok('the old Shingles option is untouched',
   TEX['shingle'] && TEX['shingle'][:file] == 'roof_shingle.jpg', TEX['shingle'])
ok('"Solid color" is NOT a texture - it must fall through to the colour path',
   !TEX.key?('color'))

# ------------------------------------------- the files are actually there

TEX.each do |k, spec|
  path = TEXDIR ? File.join(TEXDIR, spec[:file]) : spec[:file].to_s
  ok("#{k}: #{spec[:file]} exists on disk", File.file?(path), path)
  ok("#{k}: #{spec[:file]} is not an empty stub",
     File.file?(path) && File.size(path) > 2000, File.file?(path) ? File.size(path) : 0)
end

NEW.each do |k|
  ok("#{k}: SHAPES names the same file ROOF_TEXTURES loads",
     RTM.shape(k)[:texture] == TEX[k][:file], [RTM.shape(k)[:texture], TEX[k][:file]])
end

# --------------------------------- the texture grid matches the tile grid
# This is what will let the 3D steps of step 2b sit exactly on the painted
# tile lines. If someone re-crops a texture and forgets the sizes, the steps
# drift across the pattern and the roof looks wrong in a way that is very
# hard to trace back. So it is pinned here, now, before the steps exist.

NEW.each do |k|
  s = RTM.shape(k)
  w, h = TEX[k][:size]
  tiles = w / s[:tile_w]
  ok("#{k}: texture is a whole number of tiles wide (#{tiles.round(3)})",
     (tiles - tiles.round).abs < 1e-9 && tiles.round >= 1, [w, s[:tile_w]])
  next unless s[:exposure] > 0
  rows = h / s[:exposure]
  ok("#{k}: texture is a whole number of courses tall (#{rows.round(3)})",
     (rows - rows.round).abs < 1e-9 && rows.round >= 1, [h, s[:exposure]])
end
ok('standing seam has no courses, so no course height to match',
   !RTM.courses?('seam'))

# ------------------------------------------------- the dialog can reach it

dlg = File.read(SRC, encoding: 'UTF-8')
NEW.each do |k|
  ok("#{k}: appears in the Roof material menu", dlg.include?("'#{k}'"), k)
  ok("#{k}: the menu label matches SHAPES",
     dlg.include?(RTM.shape(k)[:label]), RTM.shape(k)[:label])
end
ok('Solid color is still first in the menu',
   dlg.index("'color'") < dlg.index("'barrel'"))
ok('Shingles is still there', dlg.include?("'Shingles'"))

# ------------------------------------------------------- load order

main = File.read(MAIN, encoding: 'UTF-8')
ok('main.rb loads roof_tile_math.rb', main.include?('roof_tile_math.rb'))
ok('...BEFORE roof_manager.rb, so the maths exists when the roof is built',
   main.index('roof_tile_math.rb') < main.index('roof_manager.rb'),
   [main.index('roof_tile_math.rb'), main.index('roof_manager.rb')])

# --------------------------------------------- nothing else moved

ok('still exactly one texture per material, no duplicates',
   TEX.values.map { |v| v[:file] }.uniq.length == TEX.length, TEX.values.map { |v| v[:file] })
ok('every registered size is a real pair of positive numbers',
   TEX.values.all? { |v| v[:size].is_a?(Array) && v[:size].length == 2 &&
                         v[:size].all? { |n| n.is_a?(Float) && n > 0 } })

# ------------------------------------- the reload trap, pinned so it stays shut
# `X = {...} unless const_defined?(:X)` survives InteriorPro.reload! untouched.
# On 2026-08-18 that made this exact feature look completely dead: the files
# were on disk, the menu listed them, and the roof still came out a flat
# colour, because the table in memory was the old one-entry version. Both
# tables are methods now. If either goes back to being a constant, this fails.
src_math = ['../roof_tile_math.rb', './roof_tile_math.rb'].find { |f| File.file?(f) }
src_mgr  = ['../roof_manager.rb', './roof_manager.rb'].find { |f| File.file?(f) }
mth = File.read(src_math, encoding: 'UTF-8')
mgr = File.read(src_mgr, encoding: 'UTF-8')
ok('SHAPES is a method, so reload! actually re-reads it',
   mth.include?('def self.shapes') && !mth.include?('SHAPES = {'), src_math)
ok('ROOF_TEXTURES is a method too',
   mgr.include?('def self.roof_textures') && !mgr.include?('ROOF_TEXTURES = {'), src_mgr)
ok('...and calling it twice gives equal tables, not a stale one',
   RM.roof_textures == RM.roof_textures && RTM.shapes == RTM.shapes)
ok('the table is rebuilt each call, so an edit can never be cached',
   !RM.roof_textures.equal?(RM.roof_textures))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
