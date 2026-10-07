# encoding: utf-8
ENV['REAL_ROOMS'] = '1'
require 'json'
require './sketchup_stub'
module InteriorPro; module WallTool; def self.read_door_openings(w); []; end; end; end
require './door_library'; require './plan_generator'; require './plan_doc'; require './plan_tables'
require './plan_geometry'; require './plan_canvas'; require './plan_pdf'; require './plan_sheet_dialog'
PSD = InteriorPro::PlanSheetDialog
bridge = ARGV[0]
yard = JSON.parse(File.read(File.join(bridge, 'house_lines.json')))['yard'].map { |a, b, c, d| [[a, b], [c, d]] }
plan = JSON.parse(File.read(File.join(bridge, 'nested_plan_doc.json')))
st = PSD.default_state.merge('scale' => '3/32"', 'strip' => true, 'origin_x' => 495.39, 'origin_y' => -1729.83,
                             'images' => (1..10).map { |i| "C:/x/render #{i}.jpg" }, 'address' => '6 Bronco Ln')
PSD.save_state(st)
PSD.site_lines = yard
PSD.show
dlg = PSD.instance_variable_get(:@dialog)
dlg.callbacks['sheet_ready'].call(nil)
s = dlg.scripts.reverse.find { |x| x.start_with?('loadSheet(') }
pay = JSON.parse(s[/\AloadSheet\((.*)\)\z/m, 1])
cv = pay['doc']['canvases'].find { |c| c['name'] == 'MODEL' }
cv['layers'] = plan['layers'].reject { |l| l['shapes'].empty? } + cv['layers']
puts cv['layers'].map { |l| "#{l['name']}:#{l['shapes'].length}" }.join(' ')
File.write(File.join(bridge, 'perf_payload.json'), JSON.generate(pay))
File.write(File.join(bridge, 'perf_sheet.html'), PSD.html)
puts 'ok'
