# encoding: utf-8
# rt297 - the layers list is his groups (2026-10-09, PlanCanvas::USE_LAYER_GROUPS): st['hide'] = groups off; every
# shape of a group off is marked :off (apply_visibility!) and the PDF leaves it out; a door's name is writing, a
# hand dimension a dimension; a layer he had switched off before becomes its group; the switch.
ENV['REAL_ROOMS'] = '1'
require 'json'
require 'fileutils'
require 'tmpdir'
require './sketchup_stub'
module InteriorPro
  module WallTool
    def self.read_door_openings(w)
      []
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
require './tile_niche'
require './elevation_tool'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
PC = InteriorPro::PlanCanvas
psd = InteriorPro::PlanSheetDialog
P1 = '/e/Room_2_North_lines.png'

st = psd.load_state
st['hidden'] = []
st['hide'] = []
st['marks'] = [{ 't' => 'dim', 'x1' => 0, 'y1' => 0, 'x2' => 60, 'y2' => 0, 'off' => 12 },
               { 't' => 'note', 'x' => 40, 'y' => 40, 'kx' => 30, 'ky' => 40, 'lx' => 20, 'ly' => 30, 'text' => 'Tile here' }]
psd.save_state(st)
psd.instance_variable_set(:@doc, nil)
doc = psd.document
cv = doc.canvas('MODEL')
mk = cv.layer(PC::MARK_LAYER)
dimsh = mk.shapes.select { |s| s[:mdim] }
ok('a hand dimension\'s every line and its number say they are a dimension', dimsh.count { |s| s[:type] == :text } == 1 && dimsh.count { |s| s[:type] == :line } >= 3, dimsh.size)
ok('the note\'s shapes do not', mk.shapes.select { |s| s[:note] || (s[:type] == :text && s[:text] == 'Tile here') }.none? { |s| s[:mdim] })
ok('groups: a door\'s name is writing, the door a door; a hand dimension a dimension, a note a note; the title none',
   PC.shape_group('DOORS', { type: :text }) == 'text' && PC.shape_group('DOORS', { type: :line }) == 'doors' &&
   PC.shape_group('NOTES', { type: :line, mdim: true }) == 'dims' && PC.shape_group('NOTES', { type: :text }) == 'notes' &&
   PC.shape_group('TITLE', { type: :text }).nil? && PC.shape_group('ELEV_DIMS', { type: :text }) == 'dims' &&
   PC.shape_group('PLUMBING', { type: :line }) == 'plumbing')

st['hide'] = ['text', 'dims']
psd.save_state(st)
ok('the groups off survive save_state', psd.load_state['hide'] == ['text', 'dims'])
psd.instance_variable_set(:@doc, nil)
doc = psd.document
all = (doc.canvases + doc.pages).flat_map { |h| h.layers.flat_map { |l| l.shapes.map { |s| [l.name, s] } } }
off = all.select { |_, s| s[:off] }
ok('every shape of a group off is marked off, and only those', all.all? { |n, s| !!s[:off] == %w[text dims].include?(PC.shape_group(n, s).to_s) }, off.size)
ok('the hand dimension among them', off.any? { |n, s| n == PC::MARK_LAYER && s[:mdim] })
ok('the note is not', all.select { |n, s| n == PC::MARK_LAYER && !s[:mdim] }.none? { |_, s| s[:off] })
stream = InteriorPro::PlanPDF.page_stream(doc.pages.first, doc)
st['hide'] = []
psd.save_state(st)
psd.instance_variable_set(:@doc, nil)
doc2 = psd.document
stream2 = InteriorPro::PlanPDF.page_stream(doc2.pages.first, doc2)
ok('the PDF leaves them out', stream.length < stream2.length, [stream.length, stream2.length])
ok('nothing off: nothing marked', (doc2.canvases + doc2.pages).all? { |h| h.layers.all? { |l| l.shapes.none? { |s| s[:off] } } })

# a layer he had switched off before: its group
raw = JSON.generate(st.merge('hidden' => %w[DOORS SCHEDULES ELEV_DIMS TITLE], 'hide' => []))
Sketchup.active_model.set_attribute(psd::ATTR_DICT, psd::ATTR_STATE, raw)
ls = psd.load_state
ok('a layer switched off before is its group switched off; SCHEDULES stays; TITLE just comes back',
   ls['hide'] == %w[doors dims] && ls['hidden'] == ['SCHEDULES'], [ls['hide'], ls['hidden']])

PC.send(:remove_const, :USE_LAYER_GROUPS)
PC.const_set(:USE_LAYER_GROUPS, false)
st['hide'] = ['text']
psd.save_state(st)
psd.instance_variable_set(:@doc, nil)
d3 = psd.document
ok('switched off: st[hide] is ignored', (d3.canvases + d3.pages).all? { |h| h.layers.all? { |l| l.shapes.none? { |s| s[:off] } } })

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
