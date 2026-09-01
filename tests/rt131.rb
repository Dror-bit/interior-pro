# encoding: utf-8
# rt131 - A GRAIN, NOT A PATTERN (2026-09-11).
#
# WHY
# The user asked for it right after picking the default colours: "אולי
# אפילו אפשר לייצר טקסטור שיתאים לספניש ולריבועים של הטיל. משהו כמו בטון
# כזה או סטאקו". The photographed TILE pictures were switched off on
# 2026-08-21 because a picture of tiles under a modelled tile is two
# patterns fighting (see rt18). A grain is the opposite: no grid at all,
# so the only pattern on the roof is still the 3D one.
#
# WHAT IS PINNED HERE
# Which families wear it, that they share ONE file, that the file really
# ships in textures/, that the material it makes is a TEXTURE tinted by
# the style's colour, and - the part that protects rt18's rule - that a
# family without a grain is untouched.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'
require 'fileutils'

RF = InteriorPro::RoofManager

FAILS = []
def ok(name, cond, extra = nil)
  if cond
    puts "PASS  #{name}"
  else
    puts "FAIL  #{name}#{extra.nil? ? '' : "   << #{extra.inspect}"}"
    FAILS << name
  end
end

# --- the map ---------------------------------------------------------
ok('Spanish tile wears the grain', RF.roof_grain.key?('metaltile'))
ok('the square flat tile wears it too', RF.roof_grain.key?('slate'))
ok('and nothing else does', RF.roof_grain.keys.sort == %w[metaltile slate],
   RF.roof_grain.keys)
ok('both share ONE file',
   RF.roof_grain['metaltile'][:file] == RF.roof_grain['slate'][:file],
   RF.roof_grain.values.map { |v| v[:file] })
ok('sized in real inches, big enough not to repeat on a 7in module',
   RF.roof_grain['slate'][:size] == [36.0, 36.0], RF.roof_grain['slate'][:size])

# --- the file really ships -------------------------------------------
fname = RF.roof_grain['slate'][:file]
shipped = File.join(File.dirname(__FILE__), '..', 'textures', fname)
ok('the grain is shipped in the plugin textures/ folder', File.exist?(shipped),
   shipped)

# the suites run on a COPY of roof_manager.rb inside tests/, so stand the
# file up next to the test the way rt18 does before exercising the path
path = RF.texture_path(fname)
unless File.exist?(path)
  FileUtils.mkdir_p(File.dirname(path))
  FileUtils.cp(shipped, path) if File.exist?(shipped)
end
have = File.exist?(path)

# --- what it paints --------------------------------------------------
model = Sketchup.active_model
if have
  m = RF.surface_material(model, { roof_material: 'metaltile', roof_color: '' })
  ok('Spanish gets a real texture, not a flat colour', !m.texture.nil?)
  ok('...tinted by the style colour, not left grey', !m.color.nil?)
  ok('...and the material name says grain, family and colour',
     m.name == "InteriorPro_Roof_grain_metaltile_#{RF.roof_colors['metaltile'].delete('#')}",
     m.name)
  m2 = RF.surface_material(model, { roof_material: 'slate', roof_color: '' })
  ok('the flat tile gets it too', !m2.texture.nil?)
  ok('a different colour is a different material', m.name != m2.name,
     [m.name, m2.name])
  m3 = RF.surface_material(model, { roof_material: 'metaltile', roof_color: '#123456' })
  ok('a hand-picked colour still reaches the grain',
     m3.name.include?('123456'), m3.name)
end

# --- families with no grain are untouched (rt18's rule) --------------
%w[roman barrel].each do |fam|
  ok("#{fam} has no grain and still takes the flat colour",
     RF.surface_material(model, { roof_material: fam, roof_color: '#584e4a' })
       .texture.nil?)
end

if FAILS.empty?
  puts 'ALL OK'
else
  puts "*** #{FAILS.length} FAILED ***"
  exit 1
end
