# encoding: utf-8
# rt80 - choosing which sheets go into the PDF, and throwing a sheet away for
# good - the plan sheet included (2026-08-19).
#
# The user asked for two different things and was explicit that they ARE two
# different things:
#   "אני רוצה את האופציה למחוק בכלל מהתוכנית, ואני רוצה את האופציה להשאיר
#    בתוכנית הכוללת אבל להוציא רק כמה דפים ל-PDF"
#
#   TICK - the sheet stays in the set and in the window; it only stays OUT of
#          the print. Nothing is destroyed.
#   X    - the sheet is gone from the plan set altogether, and that now
#          includes the floor plan, which used to refuse.
#
# THE TRAP THIS SUITE EXISTS FOR
# A tick has to be attached to something that does not move. Sheet NUMBER and
# position in the list both shift the moment a sheet is added or removed, so a
# tick pinned to either would quietly slide onto the next sheet - the user
# would print a set he never chose and there would be nothing on screen to say
# so. Hence page_key, and hence shift_image_keys when a picture leaves.
#
# The other half is that a page set must never come out empty: the window would
# draw nothing and PlanPDF.export refuses to print. Two guards, both pinned.
ENV['REAL_ROOMS'] = '1'
require 'json'
require 'tmpdir'
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
require './plan_canvas'
require './plan_pdf'
require './plan_sheet_dialog'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

PD  = InteriorPro::PlanDoc
PC  = InteriorPro::PlanCanvas
PP  = InteriorPro::PlanPDF
PSD = InteriorPro::PlanSheetDialog

# Dir.tmpdir, NOT a folder beside the suite. rt51/rt52 delete a temp file next
# to themselves and fail in the cloud because the shared drive refuses unlink
# (HANDOFF 2026-08-19). Nothing is gained by joining them.
TMP = Dir.mktmpdir('rt80')
at_exit { FileUtils.rm_rf(TMP) }

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

R1 = jpg('a.jpg')
R2 = jpg('b.jpg')
R3 = jpg('c.jpg')

# ------------------------------------------------------------------ page keys

class FakePage
  attr_accessor :kind, :ref
  def initialize(kind, ref = nil); @kind = kind; @ref = ref; end
end

ok('the plan sheet answers to "plan"',
   PSD.page_key(FakePage.new('plan')) == 'plan')
ok('a page with no kind at all is still the plan sheet',
   PSD.page_key(FakePage.new(nil)) == 'plan')
ok('the schedules answer to "schedules"',
   PSD.page_key(FakePage.new('schedules')) == 'schedules')
ok('a picture carries its place in the list',
   PSD.page_key(FakePage.new('image', 2)) == 'image:2')

# THE TRAP: picture 1 of [0,1,2] leaves, so 2 has to become 1.
sk = PSD.shift_image_keys(%w[plan image:0 image:1 image:2 schedules], 1)
ok('one tick fewer - the deleted picture no longer has one',
   sk.length == 4 && sk.count { |k| k.start_with?('image:') } == 2, sk)
ok('a picture BEFORE it keeps its number', sk.include?('image:0'), sk)
ok('the picture keys stay contiguous from 0 - image:2 became image:1',
   sk.select { |k| k.start_with?('image:') }.sort == %w[image:0 image:1], sk)
# and this is the whole reason the method exists: the tick that WAS on
# image:2 is now on image:1, which is the same picture it was always on.
ok('nothing is left pointing past the end of the list',
   sk.select { |k| k.start_with?('image:') }
     .map { |k| k.split(':').last.to_i }.max < 2, sk)
ok('the sheets that are not pictures are left alone',
   sk.include?('plan') && sk.include?('schedules'), sk)
ok('removing the first picture renumbers every one after it',
   PSD.shift_image_keys(%w[image:0 image:1 image:2], 0).sort ==
     %w[image:0 image:1], PSD.shift_image_keys(%w[image:0 image:1 image:2], 0))

# ------------------------------------------------------ the settings default

ds = PSD.default_state
ok('a fresh model prints every sheet', ds['pdf_skip'] == [], ds['pdf_skip'])
ok('and has its plan sheet', ds['drop_plan'] == false, ds['drop_plan'])
# rt49's rule: a new setting must be in default_state or save_state throws it
# away on the way to the model.
ok('both new settings survive save_state',
   (PSD.default_state.keys & %w[pdf_skip drop_plan]).length == 2)

# ------------------------------------------------------------- a real set

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

doc = PC.build_document(m, size: 'ARCH D', scale: '1/4"')
BASE = { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"',
         'sheet_number' => 'A-101', 'sheet_title' => 'FLOOR PLAN',
         'tables_own_page' => true, 'hidden' => [],
         'images' => [R1, R2, R3] }.freeze

st = BASE.dup
PC.layout_pages!(doc, st)
kinds = doc.pages.map { |p| PSD.page_key(p) }
ok('the whole set is there to start with',
   kinds.first == 'plan' && kinds.count { |k| k.start_with?('image:') } == 3,
   kinds)
FULL = doc.pages.length

# ---------------------------------------------------- x on the PLAN sheet

st = BASE.merge('drop_plan' => true)
PC.layout_pages!(doc, st)
kinds = doc.pages.map { |p| PSD.page_key(p) }
ok('the plan sheet really goes', !kinds.include?('plan'), kinds)
ok('and it takes exactly one sheet with it', doc.pages.length == FULL - 1,
   [doc.pages.length, FULL])
ok('every other sheet is untouched',
   kinds.count { |k| k.start_with?('image:') } == 3, kinds)
ok('no sheet is left holding a plan window',
   doc.pages.none? { |p| p.kind == 'plan' }, doc.pages.map(&:kind))
ok('and the numbering closes up - no hole in front of A-101',
   doc.pages.first.sheet_number == 'A-101', doc.pages.map(&:sheet_number))
ok('the numbers still run on, one per sheet',
   doc.pages.map(&:sheet_number).uniq.length == doc.pages.length,
   doc.pages.map(&:sheet_number))

# put it back
st = BASE.merge('drop_plan' => false)
PC.layout_pages!(doc, st)
ok('clearing the flag brings the plan sheet back',
   doc.pages.first.kind == 'plan' && doc.pages.length == FULL,
   [doc.pages.first.kind, doc.pages.length])
ok('and it has its drawing window again', doc.pages.first.views.length == 1)

# ------------------------------------- the set can never come out empty

st = { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"',
       'sheet_number' => 'A-101', 'sheet_title' => 'FLOOR PLAN',
       'tables_own_page' => true,
       'hidden' => [InteriorPro::PlanTables::LAYER],
       'images' => [], 'drop_plan' => true }
PC.layout_pages!(doc, st)
ok('drop everything and the plan sheet comes back rather than a blank set',
   doc.pages.length == 1 && doc.pages.first.kind == 'plan',
   doc.pages.map(&:kind))
ok('so the window always has something to draw', !doc.pages.empty?)

# --------------------------------------------------- the tick, in the PDF

st = BASE.dup
PC.layout_pages!(doc, st)
all = doc.pages.map { |p| PSD.page_key(p) }

# THE code that ships, not a copy of it. A copy would go on passing on the day
# the export callback stopped calling it (HANDOFF 2026-08-19 §3א).
pick = lambda do |skip|
  PSD.pages_for_pdf(doc, st.merge('pdf_skip' => skip))
end

ok('no ticks touched -> every sheet prints', pick.call([]).length == doc.pages.length)
ok('un-tick the plan and the plan does not print',
   pick.call(['plan']).none? { |p| p.kind == 'plan' },
   pick.call(['plan']).map(&:kind))
ok('but the plan sheet is STILL in the set - a tick deletes nothing',
   doc.pages.any? { |p| p.kind == 'plan' }, doc.pages.map(&:kind))
ok('un-tick two pictures and two fewer sheets print',
   pick.call(%w[image:0 image:2]).length == doc.pages.length - 2,
   pick.call(%w[image:0 image:2]).map { |p| PSD.page_key(p) })
ok('and it is the RIGHT two that are left out',
   pick.call(%w[image:0 image:2]).map { |p| PSD.page_key(p) }.include?('image:1'),
   pick.call(%w[image:0 image:2]).map { |p| PSD.page_key(p) })
ok('un-tick everything and there is nothing to print - the window must say so',
   pick.call(all).empty?, pick.call(all).length)

# and the PDF really is shorter. This is the part that would have gone
# unnoticed: PlanPDF.export has always taken opts[:pages] and nobody used it.
PP.forget_images!
full_path = File.join(TMP, 'full.pdf')
PP.export(doc, full_path)
full_n = File.binread(full_path)[/\/Type \/Pages \/Count (\d+)/, 1].to_i
ok('the whole set prints every page', full_n == doc.pages.length,
   [full_n, doc.pages.length])

PP.forget_images!
some_path = File.join(TMP, 'some.pdf')
chosen = pick.call(%w[plan image:1])
PP.export(doc, some_path, pages: chosen)
some_n = File.binread(some_path)[/\/Type \/Pages \/Count (\d+)/, 1].to_i
ok('and a chosen few print only those', some_n == chosen.length,
   [some_n, chosen.length])
ok('which really is fewer than the whole set', some_n < full_n, [some_n, full_n])

PP.forget_images!
begin
  PP.export(doc, File.join(TMP, 'none.pdf'), pages: [])
  ok('printing nothing at all is refused', false, 'no exception')
rescue ArgumentError
  ok('printing nothing at all is refused', true)
end

puts($fails.zero? ? 'rt80 ALL PASS' : "rt80 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
