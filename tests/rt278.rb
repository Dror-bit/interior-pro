# encoding: utf-8
# rt278 - the sheets go into the PDF in the order he dragged them (2026-10-07), the Ruby side.
#
# The user: "להחליף את מיקום הסדר של הדפים בפידיאף ע"י גרירה". t79 pins the
# window (dragging a row of the page list, Escape, Ctrl+Z). This pins Ruby:
#   st['page_order'] = page keys ('plan', 'schedules', 'image:N')
#   - nothing saved = the old order and the old numbers, exactly;
#   - an order saved = the pages stand in it, and the sheet numbers run in it,
#     in the title blocks too (A-101 is whatever sheet is first);
#   - a sheet he never placed goes to the end; a key for a sheet that is not
#     there is ignored;
#   - throwing a picture sheet away renumbers the keys after it;
#   - set_state answers with the pages in the new order and writes a trace line;
#   - the PDF prints them in that order;
#   - the switch puts the old order back.
ENV['REAL_ROOMS'] = '1'
require 'json'
require 'fileutils'
require 'zlib'
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

PD  = InteriorPro::PlanDoc
PC  = InteriorPro::PlanCanvas
PP  = InteriorPro::PlanPDF
PSD = InteriorPro::PlanSheetDialog

TMP = File.join(File.dirname(File.expand_path(__FILE__)), 'rt278_tmp')
FileUtils.rm_rf(TMP)
FileUtils.mkdir_p(TMP)
at_exit { FileUtils.rm_rf(TMP) }

def png(name, w, h)
  path = File.join(TMP, name)
  chunk = ->(t, d) { [d.bytesize].pack('N') + t + d + [Zlib.crc32(t + d)].pack('N') }
  raw = ("\x00".b + "\xFF\x00\x00".b * w) * h
  out = "\x89PNG\r\n\x1A\n".b + chunk.call('IHDR'.b, [w, h, 8, 2, 0, 0, 0].pack('NNCCCCC')) +
        chunk.call('IDAT'.b, Zlib::Deflate.deflate(raw)) + chunk.call('IEND'.b, ''.b)
  File.binwrite(path, out)
  path.tr('\\', '/')
end
A = png('a.png', 20, 10)
B = png('b.png', 20, 10)
C = png('c.png', 20, 10)

def build_doc
  doc = PD::Document.new('t')
  doc.canvas('MODEL').layer('WALLS').polyline([[0.0, 0.0], [240.0, 0.0], [240.0, 120.0]], weight: 0.02)
  doc
end
def state(extra = {})
  { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"', 'hidden' => [],
    'origin_x' => 120.0, 'origin_y' => 60.0, 'marks' => [], 'images' => [A, B, C] }.merge(extra)
end
def laid(st); d = build_doc; PC.layout_pages!(d, st); d; end
def keys(d); d.pages.map { |pg| PSD.page_key(pg) }; end
def nums(d); d.pages.map(&:sheet_number); end
# every piece of writing on the sheet itself (the title block is there)
def words(pg); pg.layers.flat_map { |l| l.shapes }.select { |s| s[:type] == :text }.map { |s| s[:text].to_s }; end

ok('there is a switch for it, and it is on', PC.const_defined?(:USE_PAGE_ORDER, false) && PC::USE_PAGE_ORDER == true)
ok('a new model starts with no order of its own', PSD.default_state['page_order'] == [])

# 1. nothing saved = as before
d0 = laid(state)
ok('NOTHING SAVED: plan, then the pictures in his list, A-101 on', keys(d0) == %w[plan image:0 image:1 image:2] && nums(d0) == %w[A-101 A-102 A-103 A-104], [keys(d0), nums(d0)])
ok('an empty order is the same', keys(laid(state('page_order' => []))) == keys(d0) && nums(laid(state('page_order' => []))) == nums(d0))

# 2. an order saved
d1 = laid(state('page_order' => %w[image:2 plan image:0 image:1]))
ok('AN ORDER SAVED: the pages stand in it', keys(d1) == %w[image:2 plan image:0 image:1], keys(d1))
ok('and the sheet numbers run in it: the first sheet is A-101', nums(d1) == %w[A-101 A-102 A-103 A-104], nums(d1))
ok('the page numbers too, 1 2 3 4', d1.pages.map(&:number) == [1, 2, 3, 4], d1.pages.map(&:number))
ok('THE TITLE BLOCKS SAY IT: the render that went first prints A-101, the plan A-102',
   words(d1.pages[0]).grep(/A-10/) == [%q(A-101  RENDERING)] && words(d1.pages[1]).grep(/A-10/) == [%q(A-102  FLOOR PLAN)],
   [words(d1.pages[0]).grep(/A-1/), words(d1.pages[1]).grep(/A-1/)])
ok('each picture sheet still shows its own picture (the ref did not move)', d1.pages[0].kind == 'image' && d1.pages[0].ref == 2, d1.pages[0].ref)
ok('AND IS NAMED BY ITS PLACE: the picture dragged to the front is RENDERING 1, the others 2 and 3', d1.pages.map(&:name) == ['RENDERING 1', 'FLOOR PLAN', 'RENDERING 2', 'RENDERING 3'], d1.pages.map(&:name))
ok('nothing dragged: the names are as before', d0.pages.map(&:name) == ['FLOOR PLAN', 'RENDERING 1', 'RENDERING 2', 'RENDERING 3'], d0.pages.map(&:name))
ok('a typed sheet number is where the count starts, whatever sheet is first',
   nums(laid(state('sheet_number' => 'P-7', 'page_order' => %w[image:1]))) == %w[P-7 P-8 P-9 P-10] &&
   keys(laid(state('page_order' => %w[image:1]))) == %w[image:1 plan image:0 image:2])
ok('a key for a sheet that is not there is ignored, and one said twice counts once',
   keys(laid(state('page_order' => %w[image:9 schedules image:1 image:1 plan]))) == %w[image:1 plan image:0 image:2])
d2 = laid(state('page_order' => %w[image:1 image:0 plan], 'drop_plan' => true))
ok('with the plan sheet thrown away the first sheet still takes A-101', keys(d2) == %w[image:1 image:0 image:2] && nums(d2) == %w[A-101 A-102 A-103], [keys(d2), nums(d2)])
snap = ->(d) { JSON.generate(d.pages.map(&:to_h)) }
one = snap.call(d1)
3.times { PC.layout_pages!(d1, state('page_order' => %w[image:2 plan image:0 image:1])) }
ok('laid out again and again, nothing creeps', snap.call(d1) == one)

# 3. the PDF prints them in that order
out = File.join(TMP, 'order.pdf')
PP.export(d1, out)
raw = File.binread(out)
body = raw.scan(/stream\r?\n(.*?)endstream/m).map { |m| (Zlib::Inflate.inflate(m[0]) rescue m[0]) }
at = ->(n) { body.index { |b| b.include?("(#{n} ") } }
ok('THE PDF: A-101 is printed before A-102, before A-103', at.call('A-101') && at.call('A-102') && at.call('A-101') < at.call('A-102') && at.call('A-102') < at.call('A-103'),
   %w[A-101 A-102 A-103].map { |n| at.call(n) })

# 4. the window's side
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
ok('the window is told the switch', sheet(dlg)['page_order'] == true)
st = PSD.load_state
st['images'] = [A, B, C]
PSD.save_state(st)
PSD.instance_variable_set(:@doc, nil)
st = PSD.load_state
st['page_order'] = %w[image:2 plan image:0 image:1]
trace = File.join(PSD.plugin_dir, 'sheet_erase_trace.txt')
tsize = File.exist?(trace) ? File.size(trace) : 0
dlg.callbacks['set_state'].call(nil, JSON.generate(st))
ok('SAVED ON THE MODEL', PSD.load_state['page_order'] == %w[image:2 plan image:0 image:1], PSD.load_state['page_order'])
ans = dlg.scripts.last
pages = JSON.parse('[' + ans[/\AapplyPages\((.*)\)\z/m, 1].to_s + ']')[0]
ok('the answer is the pages in the new order, numbered in it',
   ans.start_with?('applyPages(') && pages.map { |p| [p['kind'], p['ref']] } == [['image', 2], ['plan', nil], ['image', 0], ['image', 1]] &&
   pages.map { |p| p['sheet_number'] } == %w[A-101 A-102 A-103 A-104], pages.map { |p| [p['kind'], p['ref'], p['sheet_number']] })
tl = File.exist?(trace) ? File.read(trace, encoding: 'UTF-8')[tsize..-1].to_s : ''
ok('a trace line says the new order', tl.include?('page order: image:2=A-101  plan=A-102  image:0=A-103  image:1=A-104'), tl)
tsize = File.size(trace)
dlg.callbacks['set_state'].call(nil, JSON.generate(PSD.load_state))
ok('nothing changed, no trace line', File.read(trace, encoding: 'UTF-8')[tsize..-1].to_s.empty?)
ok('the PDF gets that order too (pages_for_pdf)', PSD.pages_for_pdf(PSD.document, PSD.load_state).map { |pg| PSD.page_key(pg) } == %w[image:2 plan image:0 image:1])

# a picture sheet thrown away: the keys after it move down
dlg.callbacks['delete_page'].call(nil, JSON.generate('kind' => 'image', 'ref' => 0))
st = PSD.load_state
ok('A PICTURE SHEET THROWN AWAY: its key goes, the ones after it move down one', st['images'] == [B, C] && st['page_order'] == %w[image:1 plan image:0], st['page_order'])
ok('so the sheets stay in his order', PSD.document.pages.map { |pg| PSD.page_key(pg) } == %w[image:1 plan image:0] && PSD.document.pages[0].name == 'RENDERING 1',
   PSD.document.pages.map { |pg| [PSD.page_key(pg), pg.name] })

# a picture added after: at the end
st['images'] = [B, C, A]
dlg.callbacks['set_state'].call(nil, JSON.generate(st))
ok('a picture added after the drag goes to the end', PSD.document.pages.map { |pg| PSD.page_key(pg) } == %w[image:1 plan image:0 image:2])

# 5. the switch
PC.send(:remove_const, :USE_PAGE_ORDER)
PC.const_set(:USE_PAGE_ORDER, false)
doff = laid(state('page_order' => %w[image:2 plan image:0 image:1]))
ok('SWITCHED OFF: the old order and the old numbers, whatever was saved', keys(doff) == %w[plan image:0 image:1 image:2] && nums(doff) == %w[A-101 A-102 A-103 A-104])
ok('and the old names', doff.pages.map(&:name) == ['FLOOR PLAN', 'RENDERING 1', 'RENDERING 2', 'RENDERING 3'])
PC.send(:remove_const, :USE_PAGE_ORDER)
PC.const_set(:USE_PAGE_ORDER, true)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
