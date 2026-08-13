# encoding: utf-8
# rt39 - the drawing document (plan_doc.rb), 2026-08-12.
#
# The middle layer between "what the plugin knows" and "what gets printed":
#   Document -> canvases (real model inches) and pages (paper inches)
#   page -> views, and the SCALE lives on the view, not on the page.
#
# The point of this suite is that NOTHING is decided for the user. Page size,
# orientation and scale are values he sets; fit_scale only reports.
#
# plan_doc.rb has no SketchUp API in it, so there is no stub to load here.
require './plan_doc'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end

PD = InteriorPro::PlanDoc

# ------------------------------------------------- no SketchUp API in there
src = File.read(File.join(File.dirname(__FILE__), 'plan_doc.rb'))
code = src.lines.reject { |l| l.strip.start_with?('#') }.join
ok('the document never touches SketchUp', code !~ /Sketchup|Geom::/)

# ------------------------------------------------------------- paper sizes
ok('the four sizes the user asked for are there',
   PD.page_size_names.sort == ['ARCH C', 'ARCH D', 'LETTER', 'TABLOID'],
   PD.page_size_names)
ok('ARCH D landscape is 36 wide by 24 tall',
   PD.page_size('ARCH D') == [36.0, 24.0], PD.page_size('ARCH D'))
ok('ARCH D portrait is 24 wide by 36 tall',
   PD.page_size('ARCH D', :portrait) == [24.0, 36.0],
   PD.page_size('ARCH D', :portrait))
ok('Tabloid is 17 by 11', PD.page_size('TABLOID') == [17.0, 11.0])
ok('Letter is 11 by 8.5', PD.page_size('LETTER') == [11.0, 8.5])
ok('lower case is fine too', PD.page_size('arch c') == [24.0, 18.0])
ok('a size the user types by hand is taken as is',
   PD.page_size([30.0, 42.0]) == [42.0, 30.0], PD.page_size([30.0, 42.0]))
begin
  PD.page_size('ARCH Z')
  ok('an unknown size is refused', false)
rescue ArgumentError
  ok('an unknown size is refused', true)
end

# ------------------------------------------------------------------ scales
ok('the whole scale list is there', PD.scale_labels.length == 16, PD.scale_labels.length)
ok('the list runs big to small', PD.scale_labels.first == '12"' && PD.scale_labels.last == '1/128"')
ok('the usual four are in it',
   ['1/4"', '3/8"', '1/2"', '3/4"'].all? { |s| PD.scale_labels.include?(s) })
# 1/4" = 1'-0" means one foot of building is a quarter inch of paper.
ok('a quarter inch scale turns 12 model inches into 0.25 paper inches',
   (PD.scale_factor('1/4"') * 12.0 - 0.25).abs < 1e-12, PD.scale_factor('1/4"') * 12.0)
ok('3/4 inch scale is three times a quarter inch',
   (PD.scale_factor('3/4"') / PD.scale_factor('1/4"') - 3.0).abs < 1e-12)
ok('a 1 inch scale is 1:12', (PD.scale_factor('1"') - 1.0 / 12.0).abs < 1e-12)
ok('the printed scale text reads like the drawings he already makes',
   PD.scale_text('3/4"') == %(3/4" = 1'-0"), PD.scale_text('3/4"'))
begin
  PD.scale_factor('7/9"')
  ok('an unknown scale is refused', false)
rescue ArgumentError
  ok('an unknown scale is refused', true)
end

# ------------------------------------------------------- layers and shapes
doc = PD::Document.new('Test House')
cv  = doc.canvas('MODEL')
ok('a canvas is made once', doc.canvas('MODEL').equal?(cv))
ok('a second canvas is a different one', !doc.canvas('TILE').equal?(cv))

walls = cv.layer('WALLS')
ok('a layer is made once', cv.layer('WALLS').equal?(walls))
ok('a new layer starts empty', walls.empty?)
walls.line(0, 0, 120, 0)
walls.polygon([[0, 0], [120, 0], [120, 96], [0, 96]], fill: true)
walls.text('KITCHEN', 60, 48, h: 6.0)
ok('three shapes went in', walls.shapes.length == 3)
ok('a shape carries its type', walls.shapes[0][:type] == :line)
ok('a polygon is closed', walls.shapes[1][:closed] == true)
ok('extra options are kept', walls.shapes[1][:fill] == true)
begin
  walls.add(:spaghetti, {})
  ok('an unknown shape is refused', false)
rescue ArgumentError
  ok('an unknown shape is refused', true)
end

ok('the canvas measures itself', cv.layer('WALLS') && cv.bounds == [0.0, 0.0, 120.0, 96.0], cv.bounds)
hidden = cv.layer('HIDDEN')
hidden.line(-500, -500, -500, -500)
hidden.visible = false
ok('a hidden layer is left out of the measurement', cv.bounds == [0.0, 0.0, 120.0, 96.0], cv.bounds)
ok('an empty canvas measures nothing', doc.canvas('EMPTY').bounds.nil?)

# ------------------------------------------------------------------- pages
page = doc.add_page('FLOOR PLAN', 'ARCH D', :landscape)
ok('the page took the size', [page.width, page.height] == [36.0, 24.0])
ok('pages are numbered from one', page.number == 1)
ok('the margin leaves a frame inside the sheet',
   page.frame == [0.5, 0.5, 35.0, 23.0], page.frame)
page.resize!('TABLOID', :portrait)
ok('changing the page size changes the sheet', [page.width, page.height] == [11.0, 17.0])
page.resize!('ARCH D', :landscape)

# --------------------------------------------------------------- the view
v = page.add_view('PLAN', 1.0, 2.0, 30.0, 20.0, 'MODEL', '1/4"')
ok('the view knows its scale', v.scale == '1/4"')
ok('the view knows which canvas it shows', v.canvas == 'MODEL')
ok('the scale sits on the VIEW, not on the page', !page.respond_to?(:scale))

# two windows on ONE page at two different scales - the whole reason the
# scale lives on the view
v2 = page.add_view('DETAIL', 1.0, 2.0, 8.0, 8.0, 'MODEL', '3/4"')
ok('one page can hold two scales at once',
   page.view('PLAN').scale != page.view('DETAIL').scale)
ok('a view is found by name', page.view('DETAIL').equal?(v2))
page.views.delete(v2)

# the model point at the origin lands in the middle of the window
v.origin_x = 0.0
v.origin_y = 0.0
cx, cy = v.centre
ok('the origin lands in the middle of the window',
   v.model_to_paper(0, 0) == [cx, cy], v.model_to_paper(0, 0))
# one foot to the right is a quarter inch to the right on paper
px, = v.model_to_paper(12.0, 0.0)
ok('a foot of building is a quarter inch of paper', (px - cx - 0.25).abs < 1e-12, px - cx)
# and back again
mx, my = v.paper_to_model(px, cy)
ok('paper back to model comes home', (mx - 12.0).abs < 1e-9 && my.abs < 1e-9, [mx, my])

v.centre_on!([0.0, 0.0, 120.0, 96.0])
ok('centring puts the middle of the drawing in the middle of the window',
   [v.origin_x, v.origin_y] == [60.0, 48.0], [v.origin_x, v.origin_y])
w = v.model_window
ok('the window is 30 paper inches wide, so 120 feet of building',
   ((w[2] - w[0]) - 30.0 * 48.0).abs < 1e-9, w[2] - w[0])

# ------------------------------------------ fitting: REPORTS, never changes
small = [0.0, 0.0, 600.0, 400.0]     # 50' x 33'-4"
big   = [0.0, 0.0, 6000.0, 4000.0]   # 500' x 333'
ok('a normal house fits at a quarter inch', v.fits?(small))
ok('a huge one does not', !v.fits?(big))
before = v.scale
v.fit_scale(big)
ok('asking what would fit does NOT change the scale', v.scale == before, v.scale)
ok('it names a scale that really does fit',
   begin
     v.scale = v.fit_scale(big)
     r = v.fits?(big)
     v.scale = before
     r
   end)
ok('with nothing drawn it stays quiet', v.fit_scale(nil) == v.scale)

# ------------------------------------------------------------- title block
doc.job_address = 'Master Bathroom'
doc.date        = '2026-08-12'
lay = PD.build_title_block!(page, doc, sheet_number: 'A-101', sheet_title: 'FLOOR PLAN')
ok('the title block went on its own layer', lay.name == 'TITLE')
ok('the title block is not empty', !lay.empty?)
texts = lay.shapes.select { |s| s[:type] == :text }.map { |s| s[:text] }
ok('the job address is printed', texts.include?('Master Bathroom'), texts)
ok('the scale is printed the way he writes it',
   texts.include?(%(1/4" = 1'-0")), texts)
ok('the sheet number and name are printed',
   texts.any? { |t| t.include?('A-101') && t.include?('FLOOR PLAN') }, texts)
ok('the date is printed', texts.include?('2026-08-12'), texts)
ok('the logo is printed', texts.include?('VISUALIZE'), texts)
ok('everything sits inside the paper',
   lay.shapes.all? do |s|
     xs = case s[:type]
          when :line then [s[:x1], s[:x2]]
          when :text then [s[:x]]
          when :image then [s[:x], s[:x] + s[:w]]
          else [] end
     xs.all? { |x| x >= 0 && x <= page.width + 1e-9 }
   end)

# the printed scale follows the view, so changing the view changes the text
v.scale = '1/8"'
PD.build_title_block!(page, doc)
t2 = lay.shapes.select { |s| s[:type] == :text }.map { |s| s[:text] }
ok('changing the view scale changes the printed scale',
   t2.include?(%(1/8" = 1'-0")) && !t2.include?(%(1/4" = 1'-0")), t2)
ok('rebuilding does not stack two title blocks on top of each other',
   t2.count { |t| t == 'VISUALIZE' } == 1, t2)

# a logo image replaces the drawn words
doc.logo_path = 'C:/logo.png'
PD.build_title_block!(page, doc)
ok('a logo file is used when there is one',
   lay.shapes.any? { |s| s[:type] == :image && s[:path] == 'C:/logo.png' })
doc.logo_path = nil

# ------------------------------------------------------- a ready-made sheet
doc2  = PD::Document.new('House 2')
doc2.job_address = 'Bathroom_2'
sheet = PD.new_sheet(doc2, 'PLAN 1', size: 'ARCH D', scale: '3/4"')
ok('a ready sheet has one window', sheet.views.length == 1)
ok('a ready sheet has a title block', sheet.layer?(PD::TITLE_LAYER))
ok('the window sits above the title block',
   sheet.views.first.y >= sheet.frame[1] + PD::TITLE_HEIGHT - 1e-9)
ok('the window stays inside the frame',
   sheet.views.first.x >= sheet.frame[0] &&
   sheet.views.first.x + sheet.views.first.w <= sheet.frame[0] + sheet.frame[2] + 1e-9)
ok('the ready sheet took the scale asked for', sheet.views.first.scale == '3/4"')

# ------------------------------------------------------------ it all packs
h = doc.to_h
ok('the whole document turns into plain data', h.is_a?(Hash) && h[:version] == PD::VERSION)
ok('the canvases come with it', h[:canvases].map { |c| c[:name] }.include?('MODEL'))
ok('the pages come with it', h[:pages].first[:views].first[:scale] == '1/8"')
ok('plain data means no objects left inside',
   Marshal.dump(h).bytesize > 0)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
