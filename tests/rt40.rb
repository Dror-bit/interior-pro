# encoding: utf-8
# rt40 - the plan lands in the drawing document (plan_canvas.rb), 2026-08-12.
#
# The rule this suite exists to protect: there is only ONE plan drawing in the
# project. plan_canvas.rb must not carry its own copy of poche, swings or
# dimension chains - it hands plan_generator a fake "entities" and lets the
# code the user already tests in SketchUp do the drawing.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
module InteriorPro
  module WallTool
    def self.read_door_openings(w)
      (w.get_attribute('InteriorPro', 'door_openings') || []).map do |o|
        { t: o[0].to_f, width: o[1].to_f, height: o[2].to_f }
      end
    end
  end
end
require './door_library'
require './plan_generator'
require './plan_doc'
require './plan_canvas'
require './plan_pdf'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

PD = InteriorPro::PlanDoc
PC = InteriorPro::PlanCanvas
PG = InteriorPro::PlanGenerator

# --------------------------------------------- it CALLS the plan, never copies
src = File.read(File.join(File.dirname(__FILE__), 'plan_canvas.rb'))
%w[draw_wall_plan draw_door_symbols draw_window_symbols draw_wall_dim
   draw_dim_chains draw_room_labels].each do |m|
  ok("it calls plan_generator's #{m}", src.include?(":#{m}"))
end
code = src.lines.reject { |l| l.strip.start_with?('#') }.join
ok('it has no drawing maths of its own - no swings, no jambs, no poche',
   !code.downcase.include?('swing') && !code.downcase.include?('jamb') &&
   !code.include?('seg_points'))
ok('it never draws into the SketchUp model',
   !code.include?('start_operation') && !code.include?('entities.add'))
ok('the poche colours are read from the material names, not re-decided',
   src.include?('InteriorPro_Plan_Exterior'))

# ------------------------------------------------------------- a small house
Sketchup.reset_model!
m = Sketchup.active_model

def wall(m, id, sx, sy, ex, ey, cat = 'exterior', th = 6.0, openings = nil)
  g = m.entities.add_group
  g.set_attribute('InteriorPro', 'type', 'wall')
  g.set_attribute('InteriorPro', 'id', id)
  g.set_attribute('InteriorPro', 'start_x', sx)
  g.set_attribute('InteriorPro', 'start_y', sy)
  g.set_attribute('InteriorPro', 'end_x', ex)
  g.set_attribute('InteriorPro', 'end_y', ey)
  g.set_attribute('InteriorPro', 'thickness', th)
  g.set_attribute('InteriorPro', 'anchor', 'bottom-left')
  g.set_attribute('InteriorPro', 'wall_category', cat)
  g.set_attribute('InteriorPro', 'door_openings', openings) if openings
  g
end

def hosted(m, type, host, t, w, extra = {})
  g = m.entities.add_group
  g.set_attribute('InteriorPro', 'type', type)
  g.set_attribute('InteriorPro', 'host_wall_id', host)
  g.set_attribute('InteriorPro', 'position_along_wall_in', t)
  g.set_attribute('InteriorPro', 'width_in', w)
  g.set_attribute('InteriorPro', 'height_in', 84.0)
  g.set_attribute('InteriorPro', 'clicked_side', 1)
  extra.each { |k, v| g.set_attribute('InteriorPro', k.to_s, v) }
  g
end

# 30' x 20' box, a front door in the south wall, a window in the north one
wall(m, 'w1',   0.0,   0.0, 360.0,   0.0, 'exterior', 6.0, [[120.0, 36.0, 84.0]])
wall(m, 'w2', 360.0,   0.0, 360.0, 240.0)
wall(m, 'w3', 360.0, 240.0,   0.0, 240.0, 'exterior', 6.0, [[180.0, 48.0, 48.0]])
wall(m, 'w4',   0.0, 240.0,   0.0,   0.0)
wall(m, 'w5', 180.0,   0.0, 180.0, 240.0, 'interior', 4.0)
hosted(m, 'door',   'w1', 120.0, 36.0, door_type: 'Single', door_category: 'exterior',
                                       swing_direction: 'left', front_config: 'single')
hosted(m, 'window', 'w3', 180.0, 48.0, window_type: 'Single Hung', header_height_in: 80.0)

doc = PD::Document.new('Test House')
cv  = PC.build(m, doc, 'MODEL')

ok('a canvas came back', cv.is_a?(PD::Canvas) && cv.name == 'MODEL')
ok('the walls got their own layer', cv.layer?('WALLS'))
ok('the doors got their own layer', cv.layer?('DOORS'))
ok('the windows got their own layer', cv.layer?('WINDOWS'))
ok('the dimensions got their own layer', cv.layer?('DIMENSIONS'))

walls_layer = cv.layer('WALLS')
ok('every wall drew poche', walls_layer.shapes.count { |s| s[:type] == :polygon } >= 5,
   walls_layer.shapes.count { |s| s[:type] == :polygon })
ok('poche is filled, not an empty outline',
   walls_layer.shapes.select { |s| s[:type] == :polygon }.all? { |s| s[:fill].is_a?(Array) })
ok('an exterior wall is dark and an interior one is light',
   walls_layer.shapes.map { |s| s[:fill] }.uniq.length >= 2,
   walls_layer.shapes.map { |s| s[:fill] }.uniq)
ok('the door leaves a gap in its wall - w1 came out in two pieces',
   walls_layer.shapes.count { |s| s[:type] == :polygon } > 5,
   walls_layer.shapes.count { |s| s[:type] == :polygon })

ok('the door drew a symbol', !cv.layer('DOORS').empty?)
ok('the window drew a symbol', !cv.layer('WINDOWS').empty?)

# marks: the badge is a circle turned into a ring of points plus a label
door_texts = cv.layer('DOORS').shapes.select { |s| s[:type] == :text }.map { |s| s[:text] }
ok('the door carries its mark', door_texts.any? { |t| t =~ /^D1\d\d$/ }, door_texts)
win_texts = cv.layer('WINDOWS').shapes.select { |s| s[:type] == :text }.map { |s| s[:text] }
ok('the window carries its mark', win_texts.any? { |t| t =~ /^W1\d\d$/ }, win_texts)

# text has to land SOMEWHERE - a label stuck at 0,0 is the classic bug
marked = cv.layer('DOORS').shapes.select { |s| s[:type] == :text && s[:text] =~ /^D1/ }
ok('the mark sits on its door, not at the origin',
   marked.any? { |s| s[:x].abs > 1.0 || s[:y].abs > 1.0 }, marked.map { |s| [s[:x], s[:y]] })
ok('the mark has a real text height', marked.all? { |s| s[:h].to_f > 0.5 }, marked.map { |s| s[:h] })

# empty text groups (the ones plan_generator throws away) must not survive
ok('no empty labels came through',
   cv.layers.all? { |l| l.shapes.none? { |s| s[:type] == :text && s[:text].to_s.empty? } })

# --------------------------------------------------------------- the bounds
b = cv.bounds
ok('the drawing holds the whole 30 by 20 foot house',
   b[0] <= 0.1 && b[1] <= 0.1 && b[2] >= 359.9 && b[3] >= 239.9, b)
# the dimension chains hang outside the walls, so the drawing is a bit bigger
ok('and the dimension chains stand off it, not miles away',
   (b[2] - b[0]) < 360.0 * 1.5 && (b[3] - b[1]) < 240.0 * 1.9,
   [b[2] - b[0], b[3] - b[1]])

# ------------------------------------------------- the model does not change
plan_groups = m.entities.grep(Sketchup::Group).count do |g|
  g.get_attribute('InteriorPro', 'type') == 'plan2d'
end
ok('building the document draws NOTHING into the SketchUp model', plan_groups.zero?)
ok('and it opens no undo operation', m.ops.empty?, m.ops)

# ------------------------------------------------------------- onto a sheet
doc2 = PC.build_document(m, size: 'ARCH D', scale: '1/4"', address: 'Test House',
                         sheet_number: 'A-101')
page = doc2.pages.first
v    = page.views.first
ok('the sheet is Arch D', [page.width, page.height] == [36.0, 24.0])
ok('the view kept the scale the user asked for', v.scale == '1/4"')
ok('the drawing is centred in the window',
   (v.origin_x - 180.0).abs < 20.0 && (v.origin_y - 120.0).abs < 20.0,
   [v.origin_x, v.origin_y])

# a 30' house at 1/4" is 7.5 paper inches - it must land inside the window
x1, y1 = v.model_to_paper(0.0, 0.0)
x2, y2 = v.model_to_paper(360.0, 240.0)
ok('30 feet comes out 7.5 inches on paper', ((x2 - x1) - 7.5).abs < 1e-9, x2 - x1)
ok('the whole house sits inside the window',
   x1 >= v.x && x2 <= v.x + v.w && y1 >= v.y && y2 <= v.y + v.h,
   [x1, y1, x2, y2, [v.x, v.y, v.w, v.h]])

fit = PC.report_fit(doc2)
ok('the fit report says it fits', fit[:fits] == true, fit)
ok('the fit report does not change the scale', v.scale == '1/4"')

# ------------------------------------------------------------------- to PDF
require 'tmpdir'
out = File.join(Dir.tmpdir, 'rt40_plan.pdf')
File.delete(out) if File.exist?(out)
InteriorPro::PlanPDF.export(doc2, out)
ok('a PDF file came out', File.exist?(out) && File.size(out) > 2000)
head = File.binread(out, 9)
ok('it really is a PDF', head.start_with?('%PDF-1.'), head)
body = File.binread(out)
ok('it is one page', body.scan('/Type /Page').length >= 1)
ok('the page is 36 by 24 inches of paper', body.include?('2592.000 1728.000'), body[/MediaBox[^\]]*\]/])
ok('it ends properly', body.strip.end_with?('%%EOF'))
ok('the title block text is in there', body.include?('Test House'))
ok('the scale is printed', body.include?("1/4"))

# text width, the thing that centres every label
w1 = InteriorPro::PlanPDF.text_width('D101', 10.0)
ok('a four letter label has a sensible width', w1.between?(20.0, 32.0), w1)
ok('a longer label is wider', InteriorPro::PlanPDF.text_width('KITCHEN', 10.0) > w1)
ok('brackets in a label cannot break the file',
   InteriorPro::PlanPDF.esc('a(b)c') == 'a\\(b\\)c', InteriorPro::PlanPDF.esc('a(b)c'))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
