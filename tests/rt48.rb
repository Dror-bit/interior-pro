# encoding: utf-8
# rt48 - one picture, one sheet (2026-08-14).
#
# What the user asked for, in his words: "the simplest thing in the world - a
# big picture over the whole page except the bottom, where the template is."
# So a render sheet is a page with exactly one image box filling everything
# above the title block, and the title block under it. Nothing else.
#
# This suite pins that shape, pins where the renders sit in the page order
# (after the plan and after the schedules, so A-101 never stops being the
# floor plan), and pins that a model with no pictures comes out byte for byte
# the way it did before this feature existed.
ENV['REAL_ROOMS'] = '1'
require 'json'
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
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

PD = InteriorPro::PlanDoc
PC = InteriorPro::PlanCanvas
PP = InteriorPro::PlanPDF

TMP = File.join(File.dirname(File.expand_path(__FILE__)), 'rt48_tmp')
require 'fileutils'
FileUtils.rm_rf(TMP)
FileUtils.mkdir_p(TMP)
at_exit { FileUtils.rm_rf(TMP) }

# a JPEG with nothing but the markers the reader walks - 16:9, like a render
def jpg(name, w = 3840, h = 2160)
  path = File.join(TMP, name)
  sof = [8, h, w, 3].pack('CnnC') + ("\x01\x11\x00".b * 3)
  out = +"\xFF\xD8".b
  out << "\xFF\xC0".b << [sof.bytesize + 2].pack('n') << sof
  out << "\xFF\xDA".b << [8].pack('n') << "\x01\x01\x00\x00\x3F\x00".b
  out << "\x12\x34".b << "\xFF\xD9".b
  File.binwrite(path, out)
  path
end

R1 = jpg('pool.jpg')
R2 = jpg('yard.jpg')

# ------------------------------------------------------------- the bare page
doc = PD::Document.new('t')
doc.job_address = '123 Elm'
pg = PD.new_image_sheet(doc, 'RENDERING 1', R1,
                        size: 'ARCH D', orientation: :landscape,
                        sheet_number: 'A-103', sheet_title: 'RENDERING')

img = pg.layer(PD::IMAGE_LAYER).shapes
ok('the sheet carries exactly one picture', img.length == 1, img.length)
ok('and it is a picture, not a drawing', img[0] && img[0][:type] == :image)
ok('it points at the file the user picked', img[0] && img[0][:path] == R1)
ok('a render sheet has no plan window on it', pg.views.empty?, pg.views.length)

fx, fy, fw, fh = pg.frame
pad = 0.25
tb  = PD::TITLE_HEIGHT
ok('the picture starts just above the title block',
   (img[0][:y] - (fy + tb + pad)).abs < 1e-9, [img[0][:y], fy + tb + pad])
ok('and reaches the top of the sheet',
   ((img[0][:y] + img[0][:h]) - (fy + fh - pad)).abs < 1e-9,
   [img[0][:y] + img[0][:h], fy + fh - pad])
ok('it spans the whole width of the sheet',
   (img[0][:x] - (fx + pad)).abs < 1e-9 &&
   (img[0][:w] - (fw - 2 * pad)).abs < 1e-9, [img[0][:x], img[0][:w]])
ok('the title block is under it', !pg.layer?(PD::TITLE_LAYER).nil? &&
   !pg.layer(PD::TITLE_LAYER).empty?)
ok('a sheet with no window is not to any scale',
   pg.layer(PD::TITLE_LAYER).shapes.any? { |s| s[:text] == 'N.T.S.' },
   pg.layer(PD::TITLE_LAYER).shapes.select { |s| s[:type] == :text }.map { |s| s[:text] })
ok('the sheet number reached the title block',
   pg.layer(PD::TITLE_LAYER).shapes.any? { |s| s[:text].to_s.include?('A-103') })

# rebuilding the same page must not stack two pictures on it
PD.place_image_full!(pg, doc, R2)
ok('building it again replaces the picture, never doubles it',
   pg.layer(PD::IMAGE_LAYER).shapes.length == 1 &&
   pg.layer(PD::IMAGE_LAYER).shapes[0][:path] == R2,
   pg.layer(PD::IMAGE_LAYER).shapes.map { |s| s[:path] })

# --------------------------------------------------------- where they land
Sketchup.reset_model!
m = Sketchup.active_model
def wall(m, id, sx, sy, ex, ey)
  g = m.entities.add_group
  { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy,
    'end_x' => ex, 'end_y' => ey, 'thickness' => 5.0,
    'anchor' => 'bottom-left', 'wall_category' => 'exterior' }
    .each { |k, v| g.set_attribute('InteriorPro', k, v) }
  g
end
[[0, 0, 240, 0], [240, 0, 240, 180], [240, 180, 0, 180], [0, 180, 0, 0]]
  .each_with_index { |(a, b, c, d), i| wall(m, "w#{i}", a, b, c, d) }

d2 = PC.build_document(m, size: 'ARCH D', scale: '1/4"', images: [R1, R2])
names = d2.pages.map(&:name)
ok('the floor plan is still the first sheet', names.first == 'FLOOR PLAN', names)
ok('the renders come last, one page each',
   names.last(2) == ['RENDERING 1', 'RENDERING 2'], names)

nums = d2.pages.map do |p|
  t = p.layer(PD::TITLE_LAYER)
  s = t && t.shapes.find { |x| x[:text].to_s =~ /\AA-\d/ }
  s && s[:text].to_s.split(' ').first
end
ok('every sheet gets its own number, in order',
   nums == nums.compact && nums.uniq.length == nums.length, nums)
ok('the plan keeps A-101', nums.first == 'A-101', nums)

# state, the way the window sends it back
st = { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"',
       'sheet_number' => 'A-101', 'sheet_title' => 'FLOOR PLAN',
       'tables_own_page' => true, 'hidden' => [], 'images' => [R1] }
PC.layout_pages!(d2, st)
ok('removing a picture removes its sheet', d2.pages.length ==
   d2.pages.count { true } && d2.pages.map(&:name).count { |n| n.start_with?('RENDERING') } == 1,
   d2.pages.map(&:name))

st['images'] = []
PC.layout_pages!(d2, st)
ok('no pictures means no render sheets at all',
   d2.pages.none? { |p| p.name.start_with?('RENDERING') }, d2.pages.map(&:name))
ok('and the plan sheet is untouched', d2.pages.first.views.length == 1)

st['images'] = ['', nil, R2]
PC.layout_pages!(d2, st)
ok('an empty path is skipped instead of making a blank sheet',
   d2.pages.count { |p| p.name.start_with?('RENDERING') } == 1,
   d2.pages.map(&:name))

st['images'] = [R1, R2]
st['image_title'] = 'PHOTO'
PC.layout_pages!(d2, st)
ok('the user can rename the render sheets',
   d2.pages.map(&:name).last(2) == ['PHOTO 1', 'PHOTO 2'], d2.pages.map(&:name))

# ------------------------------------------------------------------ the PDF
st['image_title'] = nil
st['images'] = [R1, R2]
PC.layout_pages!(d2, st)
PP.forget_images!
out = File.join(TMP, 'sheet.pdf')
PP.export(d2, out)
raw = File.binread(out)
ok('the PDF was written', File.size(out) > 0)
ok('both renders are inside it', raw.scan('/DCTDecode').length == 2,
   raw.scan('/DCTDecode').length)
ok('each render sheet paints its own picture',
   raw.scan('/Im1 Do').length == 2, raw.scan('/Im1 Do').length)
# ARCH D landscape is 36 x 24. Margin 0.5 and pad 0.25 leave a 34.5" wide box,
# 21.4" tall once the title block takes its 1.1". A 16:9 render is wider than
# that box is tall, so it fills the width and stops short at the top:
# 34.5 x 19.40625 paper inches, which is 2484 x 1397.25 points.
ok('a 16:9 render on a 36x24 sheet fills the width, not the height',
   raw.include?('2484.000 0 0 1397.250 '), raw[/[\d.]+ 0 0 [\d.]+ [\d.]+ [\d.]+ cm/])

# -------------------------------------------- nothing changed for a plain job
PP.forget_images!
st['images'] = []
PC.layout_pages!(d2, st)
plain = File.join(TMP, 'plain.pdf')
PP.export(d2, plain)
ok('a job with no renders still has no picture plumbing',
   !File.binread(plain).include?('/XObject'))

# ------------------------------------------------ one list of every sheet
# The side panel used to be a drop-down for pages plus a list of picture
# thumbnails. The user wanted it clean: ONE list of every sheet, with an x.
# For that the window has to know what each page IS, so it can ask Ruby the
# right thing when the x is pressed.
st2 = { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"',
        'sheet_number' => 'A-101', 'sheet_title' => 'FLOOR PLAN',
        'tables_own_page' => true, 'hidden' => [], 'images' => [R1, R2] }
PC.layout_pages!(d2, st2)

ok('every sheet says what it is',
   d2.pages.map(&:kind) == %w[plan image image], d2.pages.map(&:kind))
ok('and a render sheet says which picture it came from',
   d2.pages.map(&:ref) == [nil, 0, 1], d2.pages.map(&:ref))
ok('every sheet carries the number printed on it',
   d2.pages.map(&:sheet_number) == %w[A-101 A-102 A-103],
   d2.pages.map(&:sheet_number))
ok('and all of that reaches the window',
   d2.pages.map { |p| p.to_h[:kind] } == %w[plan image image] &&
   d2.pages[1].to_h[:ref] == 0 && d2.pages[1].to_h[:sheet_number] == 'A-102',
   d2.pages[1].to_h.select { |k, _| %i[kind ref sheet_number].include?(k) })

# pressing x on the FIRST render must remove that one, not the last one
st2['images'] = [R2]
PC.layout_pages!(d2, st2)
ok('deleting a render sheet removes that render',
   d2.pages.length == 2 &&
   d2.pages[1].layer(PD::IMAGE_LAYER).shapes[0][:path] == R2,
   d2.pages.map(&:name))
ok('and the sheet numbers close up behind it',
   d2.pages.map(&:sheet_number) == %w[A-101 A-102], d2.pages.map(&:sheet_number))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
