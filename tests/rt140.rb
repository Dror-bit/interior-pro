# encoding: utf-8
# rt140 - THE BLACK GABLET (2026-09-13).
#
# He set the house walls to Board and Batten and the dormer came out
# black: "הפיניש של הקירות מבחוץ לדורמר צריך להיות כמו הקירות".
#
# MEASURED on his model (dormer_finish_report.txt): the material named
# "Board and Batten" is rgb(0,0,0) with NO texture - there is no
# board_and_batten.jpg, because those are real boards and not a picture
# of them - and all three dormer walls wore it. It is exactly the bug
# the gable triangle had (rt137), one file over.
#
# WHAT IS PINNED HERE:
# 1. a 3D-siding name paints the dormer wall WHITE, never by its name;
# 2. a plain texture name is untouched - Stucco still goes on as Stucco;
# 3. the real name is written on the part, so wall_names_of still knows
#    what the gablet is wearing after it has been painted white. Without
#    that, the next window rebuild would read white faces and the gablet
#    would stay white for ever.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'
require './dormer_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

DM = InteriorPro::DormerManager

# ---- 1. which names are boards ---------------------------------------
ok('Board and Batten is known to be boards', DM.siding_3d?('Board and Batten'))
ok('Horizontal Siding is known to be boards', DM.siding_3d?('Horizontal Siding'))
ok('Stucco is NOT', !DM.siding_3d?('Stucco'))
ok('Brick is NOT', !DM.siding_3d?('Brick'))
ok('nil is NOT', !DM.siding_3d?(nil))

# ---- 2. the painter itself ------------------------------------------
# The stub's WallTool has no load_or_create_material, so the paint cannot
# be run here - rt137 pins the same rule on the roof by reading the
# source, and this does the same for the dormer.
src = File.read('dormer_manager.rb', encoding: 'UTF-8')
paint = src[/def self\.paint_wall!.*?\n    end/m].to_s
ok('paint_wall! sends a 3D-siding name to WHITE, not to its own name',
   paint.include?("face_name = siding_3d?(ext_name) ? '#ffffff' : ext_name") &&
   paint.include?('ext = face_name ? wt.load_or_create_material(face_name) : nil'),
   nil)
ok('a texture name still goes on by name (the same one line does both)',
   !paint.include?("wt.load_or_create_material(ext_name)"), nil)
ok('and it writes down what the wall was told to wear',
   paint.include?("sub.set_attribute('InteriorPro', 'ext_name', ext_name.to_s)"),
   nil)

Sketchup.reset_model!

# ---- 3. the name survives the white paint ----------------------------
dormer = Sketchup.active_model.entities.add_group
dormer.set_attribute('InteriorPro', 'type', 'dormer')
w = dormer.entities.add_group
w.set_attribute('InteriorPro', 'part', 'dormer_front')
w.entities.add_face([Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(10, 0, 0),
                     Geom::Point3d.new(10, 0, 10), Geom::Point3d.new(0, 0, 10)])
DM.paint_wall!(w, ['Board and Batten', '#ffffff'], nil)
ok('wall_names_of gives back the REAL name, not the white it was painted',
   DM.wall_names_of(dormer) == ['Board and Batten', '#ffffff'],
   DM.wall_names_of(dormer))

puts($fails.zero? ? 'ALL OK' : "*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
