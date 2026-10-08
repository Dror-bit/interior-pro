# encoding: utf-8
# gen_67.rb BRIDGE - a sheet set with an editor drawing on a sheet of its own and writing in Hebrew / in a lettering: the payload for the window and the PDF Ruby prints (2026-10-08)
ENV['REAL_ROOMS'] = '1'
require 'json'
require './sketchup_stub'
module InteriorPro; module WallTool; def self.read_door_openings(w); []; end; end; end
require './door_library'; require './plan_generator'; require './plan_doc'; require './plan_tables'
require './plan_geometry'; require './plan_canvas'; require './plan_pdf'; require './plan_sheet_dialog'
PD = InteriorPro::PlanDoc; PC = InteriorPro::PlanCanvas; PSD = InteriorPro::PlanSheetDialog; PP = InteriorPro::PlanPDF
bridge = ARGV[0]
fam = ARGV[1] || 'Suez One'
PP.font_dir = ARGV[2] || File.join(bridge, 'work/FONTS')    # the fonts that ship with the plugin, copied beside the payload
Sketchup.reset_model!
draft = { 'pending' => [], 'sketches' => [], 'pages' => [
  { 'name' => 'שרטוט 1',
    'pending' => [{ 'sx' => 0, 'sy' => 0, 'ex' => 300, 'ey' => 0, 'th' => 6, 'ha' => 'left', 'cat' => 'exterior' },
                  { 'sx' => 300, 'sy' => 0, 'ex' => 300, 'ey' => 200, 'th' => 6, 'ha' => 'left', 'cat' => 'exterior' },
                  { 'sx' => 300, 'sy' => 200, 'ex' => 0, 'ey' => 200, 'th' => 6, 'ha' => 'left', 'cat' => 'exterior' },
                  { 'sx' => 0, 'sy' => 200, 'ex' => 0, 'ey' => 0, 'th' => 6, 'ha' => 'left', 'cat' => 'exterior' },
                  { 'sx' => 150, 'sy' => 6, 'ex' => 150, 'ey' => 194, 'th' => 4, 'ha' => 'center', 'cat' => 'interior' }],
    'sketches' => [{ 'pts' => [40, 40, 110, 40, 110, 90, 40, 90], 'closed' => true, 'weight' => 1 }, { 'pts' => [180, 30, 280, 170], 'weight' => 2 }],
    'dims' => [{ 'x1' => 0, 'y1' => 0, 'x2' => 300, 'y2' => 0, 'off' => -30 }, { 'x1' => 300, 'y1' => 0, 'x2' => 300, 'y2' => 200, 'off' => -30 }] } ] }
Sketchup.active_model.set_attribute('InteriorPro', 'plan_draft', JSON.generate(draft))
%i[@site_lines @site_owner @site_owner_path @doc].each { |iv| PSD.instance_variable_set(iv, nil) }
PSD.show
dlg = PSD.instance_variable_get(:@dialog)
dlg.callbacks['sheet_ready'].call(nil)
st = PSD.load_state
st['drawn'] = [{ 'src' => 'draft:0' }]
st['texts'] = [
  { 'text' => "חדר שינה ראשי\nמידות לפי התוכנית", 'on' => 'plan', 'box' => [20.0, 14.0, 7.0, 1.0], 'rot' => 0.0, 'pt' => 40 },
  { 'text' => "Pool deck 12'", 'on' => 'plan', 'box' => [20.0, 10.0, 6.0, 1.0], 'rot' => 0.0, 'pt' => 40, 'font' => fam, 'bold' => true, 'color' => '#c0392b' },
  { 'text' => "קיר חוץ 6\" (A)", 'on' => 'drawing:0', 'box' => [4.0, 17.0, 8.0, 1.0], 'rot' => 0.0, 'pt' => 36, 'font' => fam, 'underline' => true }
]
st['text_marks'] = { 'ROOMS|ROOM 1|1' => { 'font' => fam, 'bold' => true } }
PSD.save_state(st)
PSD.instance_variable_set(:@doc, nil)
d = PSD.document
# a house on the plan (the stub model has none): a few walls and a room name
cv = d.canvas('MODEL')
cv.layer('WALLS').polygon([[0.0, 0.0], [400.0, 0.0], [400.0, 6.0], [0.0, 6.0]], fill: [64, 64, 64], weight: 0.012)
cv.layer('WALLS').polygon([[394.0, 0.0], [400.0, 0.0], [400.0, 300.0], [394.0, 300.0]], fill: [64, 64, 64], weight: 0.012)
cv.layer('WALLS').polyline([[0.0, 300.0], [400.0, 300.0]], weight: 0.02)
cv.layer('ROOMS').text('ROOM 1', 200.0, 150.0, h: 7.0, align: :center, rotation: 0.0)
PC.name_texts!(cv.layer('ROOMS')) if PC.respond_to?(:name_texts!)
PSD.apply_state!(d, st)
PSD.push_all(dlg)
pay = JSON.parse(dlg.scripts.reverse.find { |x| x.start_with?('loadSheet(') }[/\AloadSheet\((.*)\)\z/m, 1])
File.write(File.join(bridge, 'perf_payload_67.json'), JSON.generate(pay))
PP.export(PSD.document, File.join(bridge, 'perf_67.pdf'))
puts "pages: " + PSD.document.pages.map { |pg| "#{PSD.page_key(pg)}=#{pg.sheet_number}/#{pg.name}" }.join('  ')
puts "fonts offered: #{pay['text_rules']['fonts'].keys.inspect}, heb #{pay['text_rules']['heb']}, drafts #{pay['drafts'].inspect}"
puts 'ok'
