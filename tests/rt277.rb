# encoding: utf-8
# rt277 - one label: underline and colour, in the side panel like Word (2026-10-07).
#
# The user (2026-10-07): "אני לוחץ על טקסט מסוים ואז אני משנה את ההגדרות בחלון
# ההגדרות שכוללות גודל כיתוב, אפשרות להדגשה, קו מתחת, סוג כתב וצבע" - one place,
# like Word. The floating bar moved into the "גודל טקסט" box at the side, and
# two settings were added to it: underline and colour. Both reach the PDF.
ENV['REAL_ROOMS'] = '1'
require 'json'
require './sketchup_stub'
module InteriorPro
  module WallTool
    def self.read_door_openings(w)
      (w.get_attribute('InteriorPro', 'door_openings') || []).map { |o| { t: o[0].to_f, width: o[1].to_f, height: o[2].to_f } }
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
require 'fileutils'
$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
PD  = InteriorPro::PlanDoc
PC  = InteriorPro::PlanCanvas
PP  = InteriorPro::PlanPDF
PSD = InteriorPro::PlanSheetDialog
SRC = File.read('plan_sheet_dialog.rb', encoding: 'UTF-8')
KEY = 'ROOMS|ROOM 2|1'
def lay_with(text_marks)
  doc = PD::Document.new('t')
  doc.canvas('MODEL').layer('ROOMS').text('ROOM 2', 0, 0, h: 7.0)
  PC.layout_pages!(doc, { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"', 'hidden' => [], 'marks' => [], 'text_marks' => text_marks })
  doc
end
def room(doc); doc.canvas('MODEL').layers.find { |l| l.name == 'ROOMS' }.shapes[0]; end

r0 = room(lay_with({}))
ok('nothing set: no underline, no colour on the label', r0[:underline].nil? && r0[:color].nil?)
r1 = room(lay_with(KEY => { 'underline' => true, 'color' => '#C02020' }))
ok('UNDERLINE AND COLOUR SET ON ONE LABEL, under its key', r1[:underline] == true && r1[:color] == '#c02020', r1)
r2 = room(lay_with(KEY => { 'underline' => false, 'color' => '#000000' }))
ok('black is "no colour", and off is off', r2[:underline] == false && r2[:color].nil?, r2)
r3 = room(lay_with(KEY => { 'color' => 'red' }))
ok('a colour that is not #rrggbb is ignored', r3[:color].nil?)

# the PDF
TMP = File.join(File.dirname(File.expand_path(__FILE__)), 'rt277_tmp')
FileUtils.rm_rf(TMP); FileUtils.mkdir_p(TMP)
at_exit { FileUtils.rm_rf(TMP) }
d = lay_with(KEY => { 'underline' => true, 'color' => '#C02020' })
pdf = File.join(TMP, 'o.pdf')
PP.export(d, pdf, pages: [d.pages.first])
raw = File.binread(pdf)
ok('THE PDF PRINTS THE LABEL IN ITS COLOUR', raw =~ /0\.753 0\.125 0\.125 rg\n\/F1 [\d.]+ Tf\n[^\n]*Tm\n\(ROOM 2\) Tj\nET\n0 g/, raw[/0\.753[^)]*\)/])
ok('and a line under the words, in the same colour, as wide as the words', raw =~ /q\n1\.000 0\.000 -0\.000 1\.000 [\d.]+ [\d.]+ cm\n0\.753 0\.125 0\.125 RG\n[\d.]+ w\n-?[\d.]+ -?[\d.]+ m -?[\d.]+ -?[\d.]+ l S\nQ/, raw[/q\n1\.000 0\.000 -0\.000[^Q]*Q/])
d2 = lay_with({})
PP.export(d2, pdf, pages: [d2.pages.first])
raw2 = File.binread(pdf)
ok('with nothing set the PDF is what it always was: black, no line', raw2.include?("0 g\n/F1") && !raw2.include?(' RG') && raw2.scan(/ l S/).length == raw2.scan(/ l S/).length)

# the way in
ok('set_text_mark takes underline and colour, and black takes the colour away',
   SRC.include?("cur['underline'] = !!r['underline'] if r.key?('underline')") && SRC.include?("cur.delete('color')"))
%w[txunder txcolor].each { |id| ok("the side panel has #{id}", SRC.include?("id=\"#{id}\"")) }
ok('one click on a label opens its settings in the side panel', SRC.include?('openTextBar(ht, true);'))
ok('the sheet draws the colour and the line', SRC.include?(%q{text-decoration="underline"}) && SRC.include?(%q{test(String(s.color||'')) ? s.color : '#000'}))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
