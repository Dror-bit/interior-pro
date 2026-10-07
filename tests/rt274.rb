# encoding: utf-8
# rt274 - a picture sits in a box of its own (2026-10-07), the Ruby side.
#
# The user: "אני רוצה שתהיה אפשרות לסובב את השרטוט וגם את התמונות", "אני גם יכול
# לבחור מה יראו מהתמונה או מהשרטוט - חיתוך", "שיהיה אפשרי להוסיף כמה תמונות בדף,
# או תמונות גם בדף השרטוט אם אני רוצה". And: "הסקייל הוא רק לבחירה של שרטוטים,
# התמונות לא צריכות סקייל."
#
# t74 pins the window: picking a picture, dragging it, its corners, its sides,
# the round arrow, Delete, Escape, Ctrl+Z. This pins what Ruby does with what
# the window saves:
#   st['image_geo'] = { "0" => {box, crop, rot} }   the picture that owns picture sheet 0
#   st['pics']      = [ {path, on, box, crop, rot} ] pictures added ONTO a sheet
#
#   - nothing saved = every picture sheet exactly as before;
#   - a saved box is where the picture is, on the paper and in the PDF: clipped
#     to the box, cut by the crop, turned about its middle;
#   - a picture can be on the plan sheet, and there can be several on a sheet;
#   - every box is held on the sheet here, whatever was saved;
#   - throwing a picture sheet away takes its boxes with it and renumbers the rest.
ENV['REAL_ROOMS'] = '1'
require 'json'
require 'zlib'
require 'fileutils'
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
require './plan_geometry'
require './plan_canvas'
require './plan_pdf'
require './plan_sheet_dialog'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
def near(a, b, tol = 1.0e-9); (a.to_f - b.to_f).abs < tol; end
def near4(p, q, tol = 1.0e-9); p.each_with_index.all? { |v, i| near(v, q[i], tol) }; end

PD  = InteriorPro::PlanDoc
PC  = InteriorPro::PlanCanvas
PP  = InteriorPro::PlanPDF
PSD = InteriorPro::PlanSheetDialog

TMP = File.join(File.dirname(File.expand_path(__FILE__)), 'rt274_tmp')
FileUtils.rm_rf(TMP)
FileUtils.mkdir_p(TMP)
at_exit { FileUtils.rm_rf(TMP) }

# a JPEG with nothing but the markers the reader walks; pad = bytes of EXIF in front of the size
def jpg(name, w, h, pad = 0)
  path = File.join(TMP, name)
  sof = [8, h, w, 3].pack('CnnC') + ("\x01\x11\x00".b * 3)
  out = +"\xFF\xD8".b
  while pad > 0
    n = [pad, 60_000].min
    out << "\xFF\xE1".b << [n + 2].pack('n') << ("\x00".b * n)
    pad -= n
  end
  out << "\xFF\xC0".b << [sof.bytesize + 2].pack('n') << sof
  out << "\xFF\xDA".b << [8].pack('n') << "\x01\x01\x00\x00\x3F\x00".b
  out << "\x12\x34".b << "\xFF\xD9".b
  File.binwrite(path, out)
  path.tr('\\', '/')
end
# a real, tiny PNG
def png(name, w, h)
  path = File.join(TMP, name)
  chunk = ->(t, d) { [d.bytesize].pack('N') + t + d + [Zlib.crc32(t + d)].pack('N') }
  raw = ("\x00".b + "\xFF\x00\x00".b * w) * h
  out = "\x89PNG\r\n\x1A\n".b + chunk.call('IHDR'.b, [w, h, 8, 2, 0, 0, 0].pack('NNCCCCC')) +
        chunk.call('IDAT'.b, Zlib::Deflate.deflate(raw)) + chunk.call('IEND'.b, ''.b)
  File.binwrite(path, out)
  path.tr('\\', '/')
end
R1 = jpg('pool.jpg', 2000, 1000)          # 2 : 1
R2 = jpg('yard.jpg', 1200, 1600)          # 3 : 4, upright
R3 = png('logo.png', 40, 20)
BIG = jpg('exif.jpg', 3840, 2160, 150_000)

ok('there is a switch, and it is on', PC.const_defined?(:USE_PIC_BOX, false) && PC::USE_PIC_BOX == true)

# ---------------------------------------------------------------------------
# 0. how big a picture is, without reading all of it
# ---------------------------------------------------------------------------
ok('a JPEG says how many pixels it is', PP.image_size(R1) == [2000, 1000], PP.image_size(R1))
ok('a PNG too', PP.image_size(R3) == [40, 20], PP.image_size(R3))
ok('a JPEG whose size sits behind 150 KB of EXIF is still read', PP.image_size(BIG) == [3840, 2160], PP.image_size(BIG))
File.binwrite(File.join(TMP, 'junk.jpg'), 'not really a jpeg')
ok('a file that is not a picture, or is not there, has no size - and nothing blows up',
   PP.image_size(File.join(TMP, 'junk.jpg')).nil? && PP.image_size('C:/gone/x.jpg').nil? && PP.image_size('').nil?)
File.binwrite(R3, File.binread(png('other.png', 64, 48)))
ok('a file that changed on the disk is sized again', PP.image_size(R3) == [64, 48], PP.image_size(R3))
png('logo.png', 40, 20)

def build_doc
  doc = PD::Document.new('t')
  cv  = doc.canvas('MODEL')
  cv.layer('WALLS').polyline([[0.0, 0.0], [240.0, 0.0], [240.0, 120.0]], weight: 0.02)
  doc
end
def state(extra = {})
  { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"', 'hidden' => [],
    'origin_x' => 120.0, 'origin_y' => 60.0, 'marks' => [], 'images' => [R1] }.merge(extra)
end
def laid(st)
  d = build_doc
  PC.layout_pages!(d, st)
  d
end
def plan(doc); doc.pages.find { |pg| pg.kind == 'plan' }; end
def sheet_of(doc, i); doc.pages.find { |pg| pg.kind == 'image' && pg.ref == i }; end
def pics(pg); l = pg.layers.find { |x| x.name == PD::IMAGE_LAYER }; l ? l.shapes.select { |s| s[:type] == :image } : []; end
def rect(s); [s[:x], s[:y], s[:w], s[:h]]; end
AREA = [0.75, 1.85, 34.5, 21.4].freeze
# the room a turned box takes up: [min x, min y, max x, max y]
def hull(s)
  r = s[:rot].to_f * Math::PI / 180.0
  hw = (s[:w] * Math.cos(r).abs + s[:h] * Math.sin(r).abs) / 2.0
  hh = (s[:w] * Math.sin(r).abs + s[:h] * Math.cos(r).abs) / 2.0
  cx = s[:x] + s[:w] / 2.0
  cy = s[:y] + s[:h] / 2.0
  [cx - hw, cy - hh, cx + hw, cy + hh]
end
def on_sheet?(s)
  a = hull(s)
  a[0] >= AREA[0] - 1e-9 && a[1] >= AREA[1] - 1e-9 && a[2] <= AREA[0] + AREA[2] + 1e-9 && a[3] <= AREA[1] + AREA[3] + 1e-9
end

# ---------------------------------------------------------------------------
# 1. nothing saved: every picture sheet exactly as before
# ---------------------------------------------------------------------------
d0 = laid(state)
m0 = pics(sheet_of(d0, 0))
ok('NOTHING SAVED: the picture sheet carries its one picture, filling the sheet, as before',
   m0.length == 1 && near4(rect(m0[0]), AREA) && !m0[0][:placed] && m0[0][:path] == R1, m0)
ok('it is told its name and its size in pixels, so the window can put handles on it',
   m0[0][:pic] == 'm:0' && m0[0][:iw] == 2000.0 && m0[0][:ih] == 1000.0, m0[0])
ok('every sheet says which part the margins leave for a picture',
   d0.pages.all? { |pg| near4(pg.pic_area, AREA) } && near4(d0.pages[0].to_h[:pic_area], AREA), d0.pages.map(&:pic_area))
ok('and the plan sheet has no picture layer at all', pics(plan(d0)).empty? && !plan(d0).layer?(PD::IMAGE_LAYER))
old = PP.page_stream(sheet_of(d0, 0), d0, PP::ImageSet.new)
ok('its PDF is drawn the old way: fitted into the sheet, not clipped', old.include?('/Im1 Do') && !old.include?('re W n'), old.lines.first(6))

# ---------------------------------------------------------------------------
# 2. the picture that owns a sheet, in a box of its own
# ---------------------------------------------------------------------------
geo = { '0' => { 'box' => [5.0, 6.0, 12.0, 8.0], 'crop' => [0.1, 0.0, 0.3, 0.2], 'rot' => 30.0 } }
d1  = laid(state('image_geo' => geo))
m1  = pics(sheet_of(d1, 0))[0]
ok('A SAVED BOX IS WHERE THE PICTURE IS  <<< THE RULE', m1[:placed] == true && near4(rect(m1), [5.0, 6.0, 12.0, 8.0]), rect(m1))
ok('with its crop and its turn', near4(m1[:crop], [0.1, 0.0, 0.3, 0.2]) && near(m1[:rot], 30.0) && m1[:pic] == 'm:0', m1)
s1 = PP.page_stream(sheet_of(d1, 0), d1, PP::ImageSet.new).lines.map(&:strip)
n3 = ->(v) { format('%.3f', v.to_f) }
ok('THE PDF IS CLIPPED TO THE BOX', s1.include?("#{n3.(5 * 72)} #{n3.(6 * 72)} #{n3.(12 * 72)} #{n3.(8 * 72)} re W n"), s1.grep(/re W n/))
# the WHOLE picture on the paper: 12 / (1 - 0.1 - 0.3) wide, 8 / (1 - 0 - 0.2) tall, shoved left by the left crop
fw = 12.0 / 0.6
fh = 8.0 / 0.8
ok('THE WHOLE PICTURE IS LAID SO THAT THE PART LEFT BY THE CROP FILLS THE BOX',
   s1.include?("#{n3.(fw * 72)} 0 0 #{n3.(fh * 72)} #{n3.((5.0 - 0.1 * fw) * 72)} #{n3.(6.0 * 72)} cm"), s1.grep(/ cm\z/))
c30 = Math.cos(30 * Math::PI / 180)
s30 = Math.sin(30 * Math::PI / 180)
cx  = 11.0 * 72
cy  = 10.0 * 72
turn = "#{format('%.6f', c30)} #{format('%.6f', s30)} #{format('%.6f', -s30)} #{format('%.6f', c30)} #{n3.(cx - c30 * cx + s30 * cy)} #{n3.(cy - s30 * cx - c30 * cy)} cm"
ok('AND TURNED ABOUT THE MIDDLE OF THE BOX, before it is clipped', s1.include?(turn) && s1.index(turn) < s1.index { |l| l.end_with?('re W n') }, s1.grep(/ cm\z/))
ok('the turn leaves the middle of the box where it is', near(c30 * cx - s30 * cy + (cx - c30 * cx + s30 * cy), cx, 1e-6) && near(s30 * cx + c30 * cy + (cy - s30 * cx - c30 * cy), cy, 1e-6))
ok('whatever is drawn after the picture is not turned or clipped', s1.count('q') == s1.count('Q'))

# held on the sheet, whatever was saved
[[[-5.0, -3.0, 10.0, 5.0], 0.0], [[30.0, 20.0, 10.0, 5.0], 0.0], [[2.0, 2.0, 80.0, 40.0], 0.0],
 [[20.0, 15.0, 20.0, 6.0], 90.0], [[2.0, 3.0, 30.0, 18.0], 45.0], [[10.0, 10.0, 0.01, 0.01], 0.0]].each do |box, rot|
  d = laid(state('image_geo' => { '0' => { 'box' => box, 'rot' => rot } }))
  s = pics(sheet_of(d, 0))[0]
  ok("held on the sheet: #{box.inspect} turned #{rot}", on_sheet?(s) && s[:w] >= PC::PIC_MIN - 1e-9 && s[:h] >= PC::PIC_MIN - 1e-9 &&
     near(s[:w] / s[:h], [box[2], PC::PIC_MIN].max / [box[3], PC::PIC_MIN].max, 1e-9), [rect(s), hull(s)])
end
ok('a box already on the sheet is not touched', near4(rect(pics(sheet_of(laid(state('image_geo' => { '0' => { 'box' => [3.3, 4.4, 7.7, 5.5], 'rot' => 12.0 } })), 0))[0]), [3.3, 4.4, 7.7, 5.5]))
[nil, 'x', { 'box' => [1, 2, 3] }, { 'box' => [1, 2, 0, 4] }, { 'box' => [1, 2, 'a', 4] }, { 'box' => nil }].each do |bad|
  s = pics(sheet_of(laid(state('image_geo' => { '0' => bad })), 0))[0]
  ok("not a box, not used: #{bad.inspect[0, 24]}", !s[:placed] && near4(rect(s), AREA), rect(s))
end
s = pics(sheet_of(laid(state('image_geo' => { '0' => { 'box' => [5.0, 6.0, 12.0, 8.0], 'crop' => [0.6, 0.2, 0.6, 0.3], 'rot' => 400.0 } })), 0))[0]
ok('a crop that leaves nothing is not believed; 400 degrees is 40', near4(s[:crop], [0.0, 0.2, 0.0, 0.3]) && near(s[:rot], 40.0), [s[:crop], s[:rot]])

# ---------------------------------------------------------------------------
# 3. pictures ADDED to a sheet: the plan sheet, and beside another picture
# ---------------------------------------------------------------------------
added = [{ 'path' => R2, 'on' => 'plan', 'box' => [20.0, 8.0, 6.0, 8.0], 'crop' => [0.0, 0.25, 0.0, 0.0], 'rot' => -15.0 },
         { 'path' => R3, 'on' => 'plan' },
         { 'path' => R2, 'on' => 'image:0' },
         { 'path' => R3, 'on' => 'image:7' },
         { 'path' => '', 'on' => 'plan' }, 'junk']
d3 = laid(state('pics' => added))
pp3 = pics(plan(d3))
ok('A PICTURE ON THE PLAN SHEET  <<< THE RULE', pp3.length == 2 && pp3[0][:path] == R2 && pp3[0][:placed] == true && near4(rect(pp3[0]), [20.0, 8.0, 6.0, 8.0]) &&
   near4(pp3[0][:crop], [0.0, 0.25, 0.0, 0.0]) && near(pp3[0][:rot], -15.0), pp3)
ok('each one is named by its place in the list', pp3.map { |q| q[:pic] } == %w[x:0 x:1] && pics(sheet_of(d3, 0)).map { |q| q[:pic] } == %w[m:0 x:2], [pp3.map { |q| q[:pic] }, pics(sheet_of(d3, 0)).map { |q| q[:pic] }])
ok('the drawing is still on the plan sheet, in its own box', plan(d3).views.length == 1 && near4([plan(d3).views[0].x, plan(d3).views[0].y, plan(d3).views[0].w, plan(d3).views[0].h], AREA))
df = pp3[1]
ok('ONE WITH NO BOX YET IS GIVEN A PLACE: on the sheet, at its own proportions, two fifths of the width',
   df[:placed] == true && on_sheet?(df) && near(df[:w] / df[:h], 2.0, 1e-9) && near(df[:w], AREA[2] * 0.4) && near4(df[:crop], [0, 0, 0, 0]) && df[:rot] == 0.0, rect(df))
ok('SEVERAL PICTURES ON ONE SHEET: the one added to a picture sheet lies after the one that owns it',
   pics(sheet_of(d3, 0)).length == 2 && pics(sheet_of(d3, 0))[1][:path] == R2 && on_sheet?(pics(sheet_of(d3, 0))[1]))
ok('an upright picture is not made taller than the sheet allows', near(pics(sheet_of(d3, 0))[1][:w] / pics(sheet_of(d3, 0))[1][:h], 0.75, 1e-9) && near(pics(sheet_of(d3, 0))[1][:h], AREA[3] * 0.6))
ok('one for a sheet that is not there, one with no file, and junk, are left out without a word', d3.pages.sum { |pg| pics(pg).length } == 4)
three = laid(state('pics' => [{ 'path' => R3, 'on' => 'plan' }] * 3))
t3 = pics(plan(three))
ok('three added together do not hide each other', t3.map { |q| q[:x].round(3) }.uniq.length == 3 && t3.all? { |q| on_sheet?(q) }, t3.map { |q| rect(q) })
sp = PP.page_stream(plan(d3), d3, PP::ImageSet.new).lines.map(&:strip)
ok('THE PLAN SHEET PRINTS BOTH PICTURES, after the drawing, each clipped to its box',
   sp.count { |l| l =~ %r{\A/Im\d Do\z} } == 2 && sp.count { |l| l.end_with?('re W n') } == 3 &&
   sp.include?("#{n3.(20 * 72)} #{n3.(8 * 72)} #{n3.(6 * 72)} #{n3.(8 * 72)} re W n"), sp.grep(/re W n|Do\z/))
out = File.join(TMP, 'pics.pdf')
PP.forget_images!
PP.export(d3, out)
pdf = File.binread(out)
ok('and the PDF is written, with each picture file in it once per sheet', pdf.start_with?('%PDF') && pdf.scan('/Subtype /Image').length == 4, pdf.scan('/Subtype /Image').length)
gone = laid(state('pics' => [{ 'path' => File.join(TMP, 'gone.jpg'), 'on' => 'plan', 'box' => [20.0, 8.0, 6.0, 8.0] }]))
sg = PP.page_stream(plan(gone), gone, PP::ImageSet.new)
ok('a picture whose file has gone still has its box - an empty frame, never a lost sheet', pics(plan(gone)).length == 1 && sg.include?("#{n3.(20 * 72)} #{n3.(8 * 72)} #{n3.(6 * 72)} #{n3.(8 * 72)} re S") && !sg.include?('Do'))
dp = laid(state('drop_plan' => true, 'pics' => added))
ok('with the plan sheet thrown away its pictures wait, they are not drawn anywhere else', dp.pages.none? { |pg| pg.kind == 'plan' } && pics(sheet_of(dp, 0)).length == 2)

# laid out again and again, nothing creeps
snap = ->(d) { JSON.generate(d.pages.map(&:to_h)) }
one  = snap.call(d3)
3.times { PC.layout_pages!(d3, state('pics' => added)) }
ok('laid out again and again, nothing creeps and nothing doubles', snap.call(d3) == one)

# ---------------------------------------------------------------------------
# 4. the sheet window's side
# ---------------------------------------------------------------------------
def open!
  Sketchup.reset_model!
  %i[@site_lines @site_owner @site_owner_path].each { |iv| PSD.instance_variable_set(iv, nil) }
  PSD.show
  dlg = PSD.instance_variable_get(:@dialog)
  dlg.callbacks['sheet_ready'].call(nil)
  dlg
end
def sheet(dlg); JSON.parse(dlg.scripts.reverse.find { |x| x.start_with?('loadSheet(') }[/\AloadSheet\((.*)\)\z/m, 1]); end
dlg = open!
first = sheet(dlg)
ok('the window is told that pictures have boxes', first['pic_box'] == true)
ok('a model that never heard of them opens with none', first['state']['pics'] == [] && first['state']['image_geo'] == {} && first['pics'] == [], first['state'].select { |k, _| %w[pics image_geo].include?(k) })

# pictures carried across with "onto the open sheet" ticked
PSD.instance_variable_set(:@drop_list, [R1, R2])
dlg.callbacks['drop_finish'].call(nil, JSON.generate('on' => 'plan'))
st = PSD.load_state
ok('ADDED ONTO THE PLAN SHEET: they are in the list of added pictures, not sheets of their own',
   st['pics'] == [{ 'path' => R1, 'on' => 'plan' }, { 'path' => R2, 'on' => 'plan' }] && st['images'] == [], [st['pics'], st['images']])
after = sheet(dlg)
ok('the sheet that comes back has them on the plan sheet', after['doc']['pages'].length == 1 && after['doc']['pages'][0]['layers'].find { |l| l['name'] == 'IMAGES' }['shapes'].map { |q| q['pic'] } == %w[x:0 x:1])
ok('and an address for each, so the window can show them', after['pics'].map { |q| q['path'] } == [R1, R2] && after['pics'].all? { |q| q['url'].start_with?('file:///') && q['there'] == true }, after['pics'])
ok('the window is told how many came', dlg.scripts.last == 'imageReport(2, null)', dlg.scripts.last)
# with nothing said they are sheets of their own, as always
PSD.instance_variable_set(:@drop_list, [R3])
dlg.callbacks['drop_finish'].call(nil)
ok('with nothing said, a sheet of its own for each - as always', PSD.load_state['images'] == [R3] && PSD.load_state['pics'].length == 2, PSD.load_state['images'])
PSD.instance_variable_set(:@drop_list, [R3])
dlg.callbacks['drop_finish'].call(nil, JSON.generate('on' => '../../etc'))
ok('a sheet name that is not a sheet name is not believed', PSD.load_state['images'] == [R3, R3] && PSD.load_state['pics'].length == 2)

# the window saves where he put one
st = PSD.load_state
st['pics'][1] = st['pics'][1].merge('box' => [22.0, 9.0, 6.0, 8.0], 'rot' => 90.0, 'crop' => [0.0, 0.0, 0.5, 0.0])
st['image_geo'] = { '1' => { 'box' => [4.0, 4.0, 10.0, 5.0], 'rot' => 0.0, 'crop' => [0.0, 0.0, 0.0, 0.0] } }
dlg.callbacks['set_state'].call(nil, JSON.generate(st))
ok('THE BOXES ARE SAVED ON THE MODEL', PSD.load_state['pics'][1]['box'] == [22.0, 9.0, 6.0, 8.0] && PSD.load_state['image_geo']['1']['box'] == [4.0, 4.0, 10.0, 5.0], PSD.load_state.select { |k, _| %w[pics image_geo].include?(k) })
ans = dlg.scripts.last
pages = JSON.parse('[' + ans[/\AapplyPages\((.*)\)\z/m, 1].to_s + ']')[0]
got = pages[0]['layers'].find { |l| l['name'] == 'IMAGES' }['shapes'][1]
ok('the answer is the pages, with the picture where Ruby holds it', ans.start_with?('applyPages(') && near4(got.values_at('x', 'y', 'w', 'h'), [22.0, 9.0, 6.0, 8.0]) && got['rot'] == 90.0, got)
ok('the document Ruby is holding has it - the PDF will too', near4(rect(pics(PSD.document.pages[0])[1]), [22.0, 9.0, 6.0, 8.0]) && pics(PSD.document.pages[2])[0][:placed] == true)

# a picture sheet is thrown away: the boxes follow
st = PSD.load_state
st['pics'] += [{ 'path' => R1, 'on' => 'image:0' }, { 'path' => R1, 'on' => 'image:1', 'box' => [3.0, 3.0, 4.0, 2.0] }]
st['image_geo']['0'] = { 'box' => [9.0, 9.0, 4.0, 2.0] }
PSD.save_state(st)
PSD.instance_variable_set(:@doc, nil)
dlg.callbacks['delete_page'].call(nil, JSON.generate('kind' => 'image', 'ref' => 0))
st = PSD.load_state
ok('A PICTURE SHEET THROWN AWAY: its own box is forgotten, and the next sheet keeps ITS box under its new number',
   st['images'] == [R3] && st['image_geo'].keys == ['0'] && st['image_geo']['0']['box'] == [4.0, 4.0, 10.0, 5.0], st['image_geo'])
ok('the pictures that were added to it go with it; the others keep their sheets',
   st['pics'].map { |q| q['on'] } == %w[plan plan image:0] && st['pics'][2]['box'] == [3.0, 3.0, 4.0, 2.0], st['pics'])
ok('shift_pics! on a state with nothing in it does nothing', PSD.shift_pics!({ 'images' => [] }, 0) == { 'images' => [] })

# opened again
d2 = (PSD.show; x = PSD.instance_variable_get(:@dialog); x.callbacks['sheet_ready'].call(nil); x)
again = sheet(d2)
ok('the window opened again opens with every picture where he left it',
   again['state']['pics'].length == 3 && again['doc']['pages'][0]['layers'].find { |l| l['name'] == 'IMAGES' }['shapes'].length == 2 &&
   again['doc']['pages'].last['layers'].find { |l| l['name'] == 'IMAGES' }['shapes'].map { |q| q['pic'] } == %w[m:0 x:2])

# ---------------------------------------------------------------------------
# 5. the switch
# ---------------------------------------------------------------------------
PC.send(:remove_const, :USE_PIC_BOX)
PC.const_set(:USE_PIC_BOX, false)
off = laid(state('image_geo' => geo, 'pics' => added))
mo  = pics(sheet_of(off, 0))
ok('switched off: one picture to a sheet, filling it, and none on the plan sheet - as before',
   mo.length == 1 && !mo[0][:placed] && near4(rect(mo[0]), AREA) && mo[0][:pic].nil? && pics(plan(off)).empty?, [mo, pics(plan(off))])
PSD.instance_variable_set(:@drop_list, [R1])
before = PSD.load_state['pics'].length
d2.callbacks['drop_finish'].call(nil, JSON.generate('on' => 'plan'))
ok('switched off: a picture carried across gets a sheet of its own whatever the window says', PSD.load_state['pics'].length == before && PSD.load_state['images'].last == R1)
PC.send(:remove_const, :USE_PIC_BOX)
PC.const_set(:USE_PIC_BOX, true)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
