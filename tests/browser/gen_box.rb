# encoding: utf-8
# gen_box.rb BRIDGE ANGLE X Y W H SCALE_F - his real plan in a box of its own (and turned): the payload for the window and the PDF Ruby prints
ENV['REAL_ROOMS'] = '1'
require 'json'
require './sketchup_stub'
module InteriorPro; module WallTool; def self.read_door_openings(w); []; end; end; end
require './door_library'; require './plan_generator'; require './plan_doc'; require './plan_tables'
require './plan_geometry'; require './plan_canvas'; require './plan_pdf'; require './plan_sheet_dialog'
PD = InteriorPro::PlanDoc; PC = InteriorPro::PlanCanvas
bridge = ARGV[0]; ang = ARGV[1].to_f
yard = JSON.parse(File.read(File.join(bridge, 'house_lines.json')))['yard'].map { |a, b, c, d| [[a, b], [c, d]] }
plan = JSON.parse(File.read(File.join(bridge, 'nested_plan_doc.json')))
pay  = JSON.parse(File.read(File.join(bridge, 'perf_payload.json')))
doc = PD::Document.new('6 Bronco Ln')
doc.job_address = '6 Bronco Ln'
cv = doc.canvas('MODEL')
sym = lambda do |h|
  o = {}
  h.each { |k, v| o[k.to_sym] = v }
  o[:type]  = o[:type].to_sym
  o[:align] = o[:align].to_sym if o[:align].is_a?(String)
  o
end
plan['layers'].each do |l|
  next if l['shapes'].empty?
  lay = cv.layer(l['name'])
  l['shapes'].each { |s| lay.shapes << lay.numbers!(sym.call(s)) }
end
site = cv.layer('SITE')
yard.each { |pts| site.polyline(pts, weight: 0.010) }
st = pay['state'].merge('rotation' => ang, 'images' => [], 'strip' => false, 'view_box' => ARGV[2, 4].map(&:to_f), 'scale_f' => (ARGV[6] ? ARGV[6].to_f : nil),
                        'marks' => [{ 't' => 'dim', 'x1' => 300.0, 'y1' => -2100.0, 'x2' => 620.0, 'y2' => -2100.0, 'off' => -40.0 },
                                    { 't' => 'note', 'x' => 900.0, 'y' => -1500.0, 'kx' => 820.0, 'ky' => -1500.0, 'lx' => 700.0, 'ly' => -1600.0, 'text' => 'NEW PATIO' }])
# a whole state the window saved (croptest.js writes one): STATE_JSON=file, laid over the rest
st = st.merge(JSON.parse(File.read(ENV['STATE_JSON']))) if ENV['STATE_JSON']
out = ENV['OUT_NAME'] || 'box'
t0 = Time.now
PC.layout_pages!(doc, st)
puts "layout #{((Time.now - t0) * 1000).round} ms, view rotation #{doc.pages[0].views.first.rotation}"
pay['doc'] = JSON.parse(JSON.generate(doc.to_h))
pay['state'] = st
pay['bounds'] = cv.bounds
pay['rotate'] = true; pay['view_box'] = true
pay['images'] = InteriorPro::PlanSheetDialog.image_payload(st); pay['pics'] = InteriorPro::PlanSheetDialog.pic_payload(st)
File.write(File.join(bridge, "perf_payload_#{out}.json"), JSON.generate(pay))
InteriorPro::PlanPDF.export(doc, File.join(bridge, "perf_#{out}.pdf"), pages: (ENV['ALL_PAGES'] ? doc.pages : [doc.pages[0]]))
puts "texts: " + cv.layers.map { |l| "#{l.name}:#{l.shapes.count { |s| s[:type] == :text }}" }.join(' ')
puts 'ok'
