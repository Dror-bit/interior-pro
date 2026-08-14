# encoding: utf-8
# rt41 - the sheet window (plan_sheet_dialog.rb), 2026-08-12.
#
# The window must never become a second opinion. It draws the SAME document
# the PDF is made from, and every control writes back into that document -
# so what the user sees on screen is what comes out of the printer.
#
# It also must not decide anything: the page size, the orientation and the
# scale are whatever the user picked, and "what would fit" is only ever
# reported.
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
require 'tmpdir'
require './plan_sheet_dialog'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

PD  = InteriorPro::PlanDoc
PSD = InteriorPro::PlanSheetDialog

# --------------------------------------------------------------- the house
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
wall(m, 'w1',   0.0,   0.0, 360.0,   0.0, 'exterior', 6.0, [[120.0, 36.0, 84.0]])
wall(m, 'w2', 360.0,   0.0, 360.0, 240.0)
wall(m, 'w3', 360.0, 240.0,   0.0, 240.0)
wall(m, 'w4',   0.0, 240.0,   0.0,   0.0)

# ---------------------------------------------------------------- the html
h = PSD.html
%w[sheet_ready set_state export_pdf rebuild].each do |cb|
  ok("the window can call Ruby's #{cb}", h.include?("sketchup.#{cb}"))
end
ok('the four page sizes are offered from Ruby, not hard-coded in the page',
   !h.include?('ARCH D 24'), nil)
ok('nothing is stored in the browser', !h.include?('localStorage') && !h.include?('sessionStorage'))
ok('there is an Export PDF button', h.include?('Export PDF'))
ok('the fit line reports what would fit', h.include?('הכי גדול שנכנס'))
# Pull one function out of the window's script by counting its braces.
#
# This used to be a regular expression that stopped at the first "}" alone on a
# line. That is fine until somebody puts an `if` inside the function - which
# happened on 2026-08-14 - and then it hands back half a function and the test
# fails for a reason that has nothing to do with what it is checking. Counting
# braces is duller and it does not lie.
def js_function(src, name)
  start = src.index("function #{name}")
  return '' unless start
  open = src.index('{', start)
  return '' unless open
  depth = 0
  i = open
  while i < src.length
    depth += 1 if src[i] == '{'
    depth -= 1 if src[i] == '}'
    return src[start..i] if depth.zero?
    i += 1
  end
  ''
end

# showFit() must never touch the scale. Only fitPlan(), which is a button the
# user presses himself, is allowed to change it.
show_fit = js_function(h, 'showFit()')
ok('the fit line changes nothing by itself',
   !show_fit.empty? && !show_fit.include?('STATE.scale='), show_fit[0, 120])
ok('a button he presses himself may fit it for him',
   h.include?('function fitPlan()') && h.include?("$('fitplan').onclick"))
# The very first time on a model nothing has been chosen yet, and a sheet that
# opens blank looks broken. So the first open fits; after that his choice wins.
load_fn = js_function(h, 'loadSheet(p)')
ok('the first open fits the plan to the sheet',
   load_fn.include?('if(first){ fitPlan(); return; }'), load_fn[-200, 200])
ok('and "first" means nothing was ever positioned',
   load_fn =~ /var first\s*=\s*\(STATE\.origin_x===undefined\|\|STATE\.origin_x===null\)/,
   load_fn[/var first.{0,80}/])
ok('dragging moves the plan', h.include?('mousedown') && h.include?('origin_x'))

# ------------------------------------------------------------ state on/off
Sketchup.active_model.delete_attribute('InteriorPro', 'sheet_state')
st = PSD.load_state
ok('with nothing saved it opens on Arch D', st['size'] == 'ARCH D', st['size'])
ok('and on a quarter inch', st['scale'] == '1/4"', st['scale'])
ok('and landscape', st['orientation'] == 'landscape')

PSD.save_state('size' => 'ARCH C', 'scale' => '1/8"', 'orientation' => 'portrait',
               'address' => 'Bathroom_2', 'hidden' => ['DIMENSIONS'],
               'origin_x' => 12.5, 'junk' => 'go away')
st2 = PSD.load_state
ok('the choice survives', st2['size'] == 'ARCH C' && st2['scale'] == '1/8"', st2)
ok('so does the address', st2['address'] == 'Bathroom_2')
ok('so does a hidden layer', st2['hidden'] == ['DIMENSIONS'], st2['hidden'])
ok('so does where the plan was dragged to', st2['origin_x'] == 12.5)
ok('junk is not kept', !st2.key?('junk'), st2.keys)

# ------------------------------------------------------- the document obeys
PSD.instance_variable_set(:@doc, nil)
Sketchup.active_model.delete_attribute('InteriorPro', 'sheet_state')
doc = PSD.document
page = doc.pages.first
ok('one page to start with', doc.pages.length == 1)
ok('it opened on Arch D landscape', [page.width, page.height] == [36.0, 24.0],
   [page.width, page.height])
ok('the plan really got drawn into it', !doc.canvas('MODEL').layer('WALLS').empty?)

PSD.apply_state!(doc, 'size' => 'TABLOID', 'orientation' => 'portrait',
                 'scale' => '1/8"', 'address' => 'My House',
                 'sheet_number' => 'A-102', 'sheet_title' => 'PLAN',
                 'origin_x' => 180.0, 'origin_y' => 120.0, 'hidden' => [])
# every page is rebuilt from the choices, so take a fresh hold of it
page = doc.pages.first
ok('the page changed size', [page.width, page.height] == [11.0, 17.0],
   [page.width, page.height])
v = page.views.first
ok('the window followed the new page - it stays inside the frame',
   v.x >= page.frame[0] - 1e-9 &&
   v.x + v.w <= page.frame[0] + page.frame[2] + 1e-9, [v.x, v.w, page.frame])
ok('and it stays above the title block',
   v.y >= page.frame[1] + PD::TITLE_HEIGHT - 1e-9, [v.y, page.frame[1]])
ok('the scale changed', v.scale == '1/8"')
ok('the plan sits where it was dragged', [v.origin_x, v.origin_y] == [180.0, 120.0])
texts = page.layer(PD::TITLE_LAYER).shapes.select { |s| s[:type] == :text }.map { |s| s[:text] }
ok('the title block followed the address', texts.include?('My House'), texts)
ok('the title block followed the scale', texts.include?(%(1/8" = 1'-0")), texts)
ok('the title block followed the sheet number', texts.any? { |t| t.include?('A-102') }, texts)

# turning a layer off really turns it off
PSD.apply_state!(doc, 'hidden' => %w[DIMENSIONS TITLE])
page = doc.pages.first
ok('a hidden layer is marked hidden', doc.canvas('MODEL').layer('DIMENSIONS').visible == false)
ok('the title block can be hidden too', page.layer(PD::TITLE_LAYER).visible == false)
ok('the walls stay on', doc.canvas('MODEL').layer('WALLS').visible == true)

# and a hidden layer must not reach the paper
out = File.join(Dir.tmpdir, 'rt41_hidden.pdf')
File.delete(out) if File.exist?(out)
InteriorPro::PlanPDF.export(doc, out)
body = File.binread(out)
ok('a hidden title block is not printed', !body.include?('VISUALIZE'))
PSD.apply_state!(doc, 'hidden' => [])
InteriorPro::PlanPDF.export(doc, out)
ok('and it comes back when it is turned on', File.binread(out).include?('VISUALIZE'))

# ------------------------------------------------------ same document, both
ok('the window and the PDF share one document',
   PSD.document.equal?(doc))
ok('rebuilding throws the old one away',
   begin
     PSD.instance_variable_set(:@doc, nil)
     !PSD.document.equal?(doc)
   end)

# ------------------------------------------------------------- file naming
ok('the saved file is named after the sheet',
   PSD.default_name('sheet_number' => 'A-101') == 'A-101.pdf',
   PSD.default_name('sheet_number' => 'A-101'))
ok('a silly sheet number cannot make a silly file name',
   PSD.default_name('sheet_number' => 'A/1 0:1') == 'A_1_0_1.pdf',
   PSD.default_name('sheet_number' => 'A/1 0:1'))
ok('no sheet number still gets a name',
   PSD.default_name('sheet_number' => '') == 'plan.pdf')

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
