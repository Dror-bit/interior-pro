# encoding: utf-8
# rt42 - the door and window schedules on the sheet (plan_tables.rb), 2026-08-12.
#
# The rule: the NUMBERS are plan_generator's - the same marks, widths and type
# names it already prints in SketchUp - and this file only lays them out on
# paper. So the table on the sheet can never disagree with the plan next to it.
ENV['REAL_ROOMS'] = '1'
require 'tmpdir'
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
require './plan_tables'
require './plan_canvas'
require './plan_pdf'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

PD = InteriorPro::PlanDoc
PT = InteriorPro::PlanTables
PC = InteriorPro::PlanCanvas

# ---------------------------------------- it asks plan_generator, never guesses
src  = File.read(File.join(File.dirname(__FILE__), 'plan_tables.rb'))
code = src.lines.reject { |l| l.strip.start_with?('#') }.join
ok("the type names come from plan_generator", code.include?(':door_type_label'))
ok('feet and inches are formatted by plan_generator', code.include?(':fmt_feet'))
ok('it invents no type names of its own',
   !code.include?("'SWING DOOR'") && !code.include?("'POCKET DOOR'"))

# --------------------------------------------------------------- a small house
Sketchup.reset_model!
m = Sketchup.active_model
def wall(m, id, sx, sy, ex, ey, cat = 'exterior', th = 6.0, op = nil)
  g = m.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex,
    'end_y' => ey, 'thickness' => th, 'anchor' => 'bottom-left',
    'wall_category' => cat }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  g.set_attribute('InteriorPro', 'door_openings', op) if op
  g
end
def hosted(m, type, host, t, w, extra = {})
  g = m.entities.add_group
  { 'type' => type, 'host_wall_id' => host, 'position_along_wall_in' => t,
    'width_in' => w, 'height_in' => 84.0, 'clicked_side' => 1 }
    .each { |k, v| g.set_attribute('InteriorPro', k, v) }
  extra.each { |k, v| g.set_attribute('InteriorPro', k.to_s, v) }
  g
end
wall(m, 'w1', 0.0, 0.0, 360.0, 0.0, 'exterior', 6.0, [[100.0, 36.0, 84.0], [240.0, 60.0, 48.0]])
wall(m, 'w2', 360.0, 0.0, 360.0, 240.0)
wall(m, 'w3', 360.0, 240.0, 0.0, 240.0)
wall(m, 'w4', 0.0, 240.0, 0.0, 0.0)
hosted(m, 'door',   'w1', 100.0, 36.0, door_type: 'Single', door_category: 'exterior',
                                       swing_direction: 'left', front_config: 'single')
hosted(m, 'door',   'w1', 300.0, 72.0, door_type: 'Pocket', door_category: 'interior')
hosted(m, 'window', 'w1', 240.0, 60.0, window_type: 'Single Hung', header_height_in: 80.0)

doc = PC.build_document(m, size: 'ARCH D', scale: '1/4"', address: 'Test',
                        sheet_number: 'A-101', tables_own_page: false)
page = doc.pages.first

# ----------------------------------------------------------------- the rows
s = doc.schedules
ok('the document carries the rows', s.is_a?(Hash) && s['doors'] && s['windows'], s.class)
ok('two doors were listed', s['doors'].length == 2, s['doors'].length)
ok('one window was listed', s['windows'].length == 1, s['windows'].length)
d0 = s['doors'].first
ok('a door row is mark, width, height, type, function', d0.length == 5, d0)
ok('the mark is the plan mark', d0[0] =~ /^(D|IN)1\d\d$/, d0[0])
ok('the width reads in feet and inches', d0[1] =~ /'/, d0[1])
ok('the rows are sorted by mark', s['doors'].map(&:first) == s['doors'].map(&:first).sort)
kinds = s['doors'].map { |r| r[3] }
ok('a pocket door is called a pocket door', kinds.include?('POCKET DOOR'), kinds)
ok('the swing door is a swing door', kinds.include?('SWING DOOR'), kinds)
funcs = s['doors'].map { |r| r[4] }.sort
ok('inside and outside are told apart', funcs == %w[EXTERIOR INTERIOR], funcs)
w0 = s['windows'].first
ok('the window type is printed', w0[3] == 'SINGLE HUNG', w0)

# ------------------------------------------------------------ on the paper
lay = page.layer(PT::LAYER)
ok('the tables are on their own layer', !lay.empty?)
tabs = lay.shapes.select { |x| x[:type] == :table }
ok('two tables - windows and doors', tabs.length == 2, tabs.length)
titles = lay.shapes.select { |x| x[:type] == :text }.map { |x| x[:text] }
ok('each one is titled', titles.include?('DOOR SCHEDULE') && titles.include?('WINDOW SCHEDULE'), titles)
ok('the table rows are the document rows',
   tabs.map { |t| t[:rows].length }.sort == [1, 2], tabs.map { |t| t[:rows].length })

fx, fy, fw, fh = page.frame
ok('the tables sit inside the paper',
   tabs.all? do |t|
     wsum = t[:col_widths].inject(0.0) { |a, b| a + b }
     t[:x] >= fx - 1e-9 && t[:x] + wsum <= fx + fw + 1e-9 &&
       t[:y] <= fy + fh + 1e-9
   end, tabs.map { |t| [t[:x], t[:y]] })
ok('they do not sit on top of each other',
   (tabs[0][:y] - tabs[1][:y]).abs > 0.3, tabs.map { |t| t[:y] })

# ------------------------------------------------- the plan makes room for them
v = page.views.first
ok('the plan window stops before the tables',
   v.x + v.w <= fx + fw - PT::WIDTH + 1e-9, [v.x + v.w, fx + fw - PT::WIDTH])
ok('the plan window is still worth having', v.w > 20.0, v.w)

# with nothing to list, the plan gets the whole page back
Sketchup.reset_model!
m2 = Sketchup.active_model
wall(m2, 'q1', 0.0, 0.0, 240.0, 0.0)
wall(m2, 'q2', 240.0, 0.0, 240.0, 120.0)
doc2 = PC.build_document(m2, size: 'ARCH D', scale: '1/4"')
ok('no doors, no windows -> no tables', doc2.pages.first.layer(PT::LAYER).empty?)
ok('and nothing is reserved', PT.reserved_width(doc2) == 0.0)
ok('so the plan gets the wide window',
   doc2.pages.first.views.first.w > doc.pages.first.views.first.w,
   [doc2.pages.first.views.first.w, doc.pages.first.views.first.w])

# turning the layer off gives the room back too
ok('a hidden schedules layer reserves nothing',
   PT.reserved_width(doc, [PT::LAYER]) == 0.0)

# ------------------------------------------------- a sheet of their own
# (the user asked for this on 2026-08-12: the tables belong on their own page)
two = PC.build_document(m, size: 'ARCH D', scale: '1/4"', address: 'Test',
                        sheet_number: 'A-101')
ok('by default the tables get a second sheet', two.pages.length == 2, two.pages.length)
plan_pg, sched_pg = two.pages
ok('the first sheet is the plan', !plan_pg.views.empty? && plan_pg.layer(PT::LAYER).empty?)
ok('the second sheet is the tables', sched_pg.views.empty? && !sched_pg.layer(PT::LAYER).empty?)
ok('the plan gets the whole width back',
   plan_pg.views.first.w > page.views.first.w,
   [plan_pg.views.first.w, page.views.first.w])
ok('the second sheet is the same paper', [sched_pg.width, sched_pg.height] == [36.0, 24.0])
stexts = sched_pg.layer(PD::TITLE_LAYER).shapes.select { |s| s[:type] == :text }.map { |s| s[:text] }
ok('the second sheet is numbered A-102', stexts.any? { |t| t.include?('A-102') }, stexts)
ok('and it says SCHEDULES', stexts.any? { |t| t.include?('SCHEDULES') }, stexts)
ok('the tables are bigger when they have a sheet to themselves',
   sched_pg.layer(PT::LAYER).shapes.find { |s| s[:type] == :table }[:row_h] >
     page.layer(PT::LAYER).shapes.find { |s| s[:type] == :table }[:row_h])
ok('A-101 turns into A-102', PC.next_sheet_number('A-101') == 'A-102')
ok('A-109 turns into A-110', PC.next_sheet_number('A-109') == 'A-110')
ok('a name with no number still gets one', PC.next_sheet_number('PLAN') == 'PLAN-2')

# turning the layer off drops the whole extra sheet
PC.layout_pages!(two, 'size' => 'ARCH D', 'orientation' => 'landscape',
                 'scale' => '1/4"', 'hidden' => [PT::LAYER],
                 'tables_own_page' => true, 'sheet_number' => 'A-101')
ok('hiding the tables removes their sheet', two.pages.length == 1, two.pages.length)

# ------------------------------------------------------------------- to PDF
out = File.join(Dir.tmpdir, 'rt42.pdf')
File.delete(out) if File.exist?(out)
InteriorPro::PlanPDF.export(doc, out)
body = File.binread(out)
ok('the table headings are printed', body.include?('MARK') && body.include?('FUNCTION'))
ok('the door mark is printed', body =~ /\(D1\d\d\)/, body[/\(D1\d\d\)/])
ok('the pocket door is printed', body.include?('POCKET DOOR'))
ok('the window schedule is printed', body.include?('WINDOW SCHEDULE'))

# ------------------------------------------------ both sheets reach the PDF
out2 = File.join(Dir.tmpdir, 'rt42_two.pdf')
File.delete(out2) if File.exist?(out2)
two2 = PC.build_document(m, size: 'ARCH D', scale: '1/4"', address: 'Test',
                         sheet_number: 'A-101')
InteriorPro::PlanPDF.export(two2, out2)
b2 = File.binread(out2)
ok('the PDF really has two sheets in it',
   b2.scan(%r{/Type /Page[^s]}).length == 2, b2.scan(%r{/Type /Page[^s]}).length)
ok('the door schedule is printed on one of them', b2.include?('DOOR SCHEDULE'))
ok('and the plan is on the other', b2.include?('FLOOR PLAN'))

# ------------------------- a remembered position from an older model
# The user hit this: he deleted some far-off walls, reopened the window and
# the sheet came up blank because the old centre was still stored.
far = PC.build_document(m, size: "ARCH D", scale: "1/4\"", sheet_number: "A-101")
PC.layout_pages!(far, "size" => "ARCH D", "orientation" => "landscape",
                 "scale" => "1/4\"", "hidden" => [], "sheet_number" => "A-101",
                 "origin_x" => 900_000.0, "origin_y" => 900_000.0)
fv = far.pages.first.views.first
fb = far.canvas("MODEL").bounds
ok("a stale position that leaves the page empty is dropped",
   PC.overlaps?(fv.model_window, fb), [fv.origin_x, fv.origin_y])

# but a position that still shows the drawing is left exactly alone
near = (fb[0] + fb[2]) / 2.0 + 12.0
PC.layout_pages!(far, "size" => "ARCH D", "orientation" => "landscape",
                 "scale" => "1/4\"", "hidden" => [], "sheet_number" => "A-101",
                 "origin_x" => near, "origin_y" => (fb[1] + fb[3]) / 2.0)
ok("a position he chose himself is respected",
   (far.pages.first.views.first.origin_x - near).abs < 1e-9,
   far.pages.first.views.first.origin_x)
ok("two boxes that miss each other do not overlap",
   !PC.overlaps?([0, 0, 1, 1], [5, 5, 6, 6]))
ok("two boxes that touch do overlap", PC.overlaps?([0, 0, 5, 5], [4, 4, 9, 9]))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
