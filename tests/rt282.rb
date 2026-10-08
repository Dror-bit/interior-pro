# encoding: utf-8
# rt282 - a lettering of its own, and Hebrew in the PDF (2026-10-07), the Ruby side.
#
# The user: "בהגדרות טקסט צריך לתת סוגים שונים של פונטים (כמו בסקצ'אפ לייאאוט)"
# and, on the list: "סוג כתב / עברית ב-PDF". So:
#   - a TrueType font file is read (cmap, hmtx, head, hhea, OS/2, post, name);
#   - the families on offer are the fonts that SHIP WITH THE PLUGIN (assets/FONTS), named by their own name table;
#   - a run with letters Helvetica has not got (Hebrew) is set in the Hebrew
#     family, laid right to left the way the browser lays it (visual);
#   - a run in a lettering he picked ('font') is set in that family, bold
#     and italic from its own files;
#   - the PDF writes the font in (Type0 / CIDFontType2, Identity-H, FontFile2,
#     a ToUnicode map, the widths of the glyphs used);
#   - Ruby measures by THE TABLE THE WINDOW IS GIVEN (text_rules['fonts']),
#     so the two break lines at the same places;
#   - Latin writing in no particular lettering: Helvetica, to the digit as before;
#   - the switch off: as before, Hebrew prints as spaces.
# t81 pins the window's side.
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
def near(a, b, tol = 1.0e-9); (a.to_f - b.to_f).abs < tol; end

PD  = InteriorPro::PlanDoc
PC  = InteriorPro::PlanCanvas
PP  = InteriorPro::PlanPDF
PSD = InteriorPro::PlanSheetDialog

TMP = File.join(File.dirname(File.expand_path(__FILE__)), 'rt282_tmp')
FileUtils.rm_rf(TMP)
FileUtils.mkdir_p(TMP)
at_exit { FileUtils.rm_rf(TMP) }

ok('there is a switch for it, and it is on', PP.const_defined?(:USE_TTF_FONTS, false) && PP::USE_TTF_FONTS == true && PC::USE_TEXT_FONT == true)

# ---------------------------------------------------------------------------
# 1. the letters in the order they are printed
# ---------------------------------------------------------------------------
ok('Latin: untouched', PP.visual('Pool deck 12') == 'Pool deck 12')
ok('HEBREW READS RIGHT TO LEFT: the letters are written the other way round', PP.visual('שלום') == 'םולש')
ok('a number inside Hebrew keeps its own order, the Hebrew round it turns', PP.visual('חדר 12 גדול') == 'לודג 12 רדח', PP.visual('חדר 12 גדול'))
ok('Latin before and after a Hebrew stretch stays put', PP.visual('Room שלום 12 עולם (A) end') == 'Room םלוע 12 םולש (A) end', PP.visual('Room שלום 12 עולם (A) end'))
ok('brackets inside the Hebrew are mirrored', PP.visual('(שלום)') == '(םולש)', PP.visual('(שלום)'))
# every one of these was held against Chromium, picture to picture (tests/browser/bidi.js, 2026-10-08)
{ '[א] פריט 3.5' => '[א] 3.5 טירפ', '(חדר) 2' => '(רדח) 2', 'שלום (world) עולם' => 'םולש (world) םלוע', '(12) חדרים' => '(12) םירדח',
  'קיר חוץ 6" (A)' => '6 ץוח ריק" (A)', 'שלום, עולם!' => 'םלוע ,םולש!', 'מידות לפי התוכנית 2026-10-07' => '2026-10-07 תינכותה יפל תודימ',
  'A-102  שרטוט 1' => 'A-102  1 טוטרש', 'חדר שינה ראשי' => 'ישאר הניש רדח', %q(מפלס 2: גובה 9'-6") => %q(6-'9 הבוג :2 סלפמ"),
  'בית (דרור) 12/3' => '12/3 (רורד) תיב', 'טלפון 050-1234567' => '050-1234567 ןופלט', 'ROOM 2 (חדר)' => 'ROOM 2 (רדח)',
  'דלת D101 בקיר' => 'תלד D101 ריקב', 'שטח 42 SF' => '42 חטש SF', %q(1/4" = 1'-0" קנה מידה) => %q(1/4" = 1'-0" הדימ הנק) }.each do |run, want|
  ok("AS THE BROWSER LAYS IT: #{run}", PP.visual(run) == want, PP.visual(run))
end

# ---------------------------------------------------------------------------
# 2. the fonts that ship with the plugin (here: a folder of the test's own,
#    with DejaVu Sans copied in - plain and bold - as if they were shipped)
# ---------------------------------------------------------------------------
PP.font_dir = File.join(TMP, 'nofonts')
ok('an empty folder (or none): no lettering on offer, no Hebrew family, and nothing blows up', PP.families_present == [] && PP.hebrew_family.nil? && PP.font_tables == {} && PP.font_file('DejaVu Sans').nil?)
SRC = Dir.glob('/usr/share/fonts/truetype/dejavu/DejaVuSans{,-Bold}.ttf')
FDIR = File.join(TMP, 'FONTS')
FileUtils.mkdir_p(FDIR)
SRC.each { |f| FileUtils.cp(f, FDIR) }
File.write(File.join(FDIR, 'junk.ttf'), 'not a font')
PP.font_dir = FDIR
fams = PP.families_present
puts "      (fonts in the test's folder: #{fams.inspect}; Hebrew in #{PP.hebrew_family.inspect})"
ok('THE FAMILIES ON OFFER ARE THE FILES IN THE FOLDER, named by the font itself; a file that is not a font is skipped', (SRC.empty? ? fams == [] : fams == ['DejaVu Sans']), fams)
unless SRC.empty?
  sf = PP.shipped_fonts['DejaVu Sans']
  ok('its faces by their subfamily: Book = plain, Bold = bold', File.basename(sf[:plain]) == 'DejaVuSans.ttf' && File.basename(sf[:bold].to_s) == 'DejaVuSans-Bold.ttf', sf)
  ok('a face that is missing falls back to the plain one (italic), bold italic to bold', PP.font_file('DejaVu Sans', false, true) == sf[:plain] && PP.font_file('DejaVu Sans', true, true) == sf[:bold])
  ok('what the window is given: the table, the files, and whether it has Hebrew', (t = PC.text_rules['fonts']['DejaVu Sans']) && t['path'] == sf[:plain] && t['pathb'] == sf[:bold] && t['heb'] == true && t['w'].is_a?(Hash) && t['dw'] > 0 && PC.text_rules['heb'] == 'DejaVu Sans', PC.text_rules['fonts'])
end
ok('a family that is not there is not offered, and has no file', !fams.include?('Nonsense') && PP.font_file('Nonsense').nil?)
ok('a run in no lettering, Latin: Helvetica, to the digit', near(PP.text_width('Pool', 72), 2.001 * 72) && PP.family_for('Pool', nil).nil? && PP.ttf_for('Pool', nil).nil?)
ok('a lettering that is not on offer: Helvetica too', PP.family_for('Pool', 'Nonsense').nil?)

if fams.empty?
  puts '      (no TrueType font found on this machine: the embedding is not checked here)'
else
  fam = fams.first
  t = PP.ttf(PP.font_file(fam))
  ok("THE FONT FILE IS READ (#{fam}): a name, glyphs, widths, the numbers a descriptor needs",
     t.ps_name =~ /\A[A-Za-z0-9\-]+\z/ && t.nglyphs > 100 && t.gid('A'.ord) > 0 && t.width_of('A'.ord) > 300 && t.ascent > 0 && t.descent < 0 && t.bbox.length == 4 && t.cap_height > 0,
     [t.ps_name, t.nglyphs, t.gid(65), t.width_of(65), t.ascent, t.descent, t.cap_height])
  ok('a letter the font has not got is glyph 0', t.gid(0x10FFFF) == 0 && !t.has?(0x10FFFF))
  tab = PP.width_table(fam)
  ok('THE TABLE RUBY MEASURES BY is the one the window is given', PC.text_rules['fonts'][fam]['w'] == tab[:w] && PC.text_rules['fonts'][fam]['dw'] == tab[:dw] && tab[:w][65] == t.width_of(65).round)
  ok('the font says its own family and face', t.family == 'DejaVu Sans' && t.subfamily == 'Book' && t.face == :plain && PP.ttf(PP.font_file(fam, true)).face == :bold)
  ok('a run in that lettering is measured by it, not by Helvetica', near(PP.text_width('Pool', 72, false, fam), %w[P o o l].sum { |c| tab[:w][c.ord] } / 1000.0 * 72) && PC.text_width_in('Pool', 72, false, fam) == PP.text_width('Pool', 72, false, fam) / 72.0)
  ok('bold in that lettering: wider by BOLD_BUMP, as the window counts it', near(PP.text_width('Pool', 72, true, fam), PP.text_width('Pool', 72, false, fam) * PP::BOLD_BUMP))
  ok('a letter outside the table counts at the default width', near(PP.text_width("☃", 72, false, fam), tab[:dw] / 1000.0 * 72))
  heb = PP.hebrew_family
  if heb
    ok('HEBREW IN NO LETTERING is set in the Hebrew family, and measured by its table',
       PP.family_for('שלום', nil) == heb && near(PP.text_width('שלום', 72), 'שלום'.each_char.sum { |c| PP.width_table(heb)[:w][c.ord] } / 1000.0 * 72))
    ok('and the window agrees on where a box breaks: text_wrap takes the font', PC.text_wrap('שלום עולם גדול מאוד', 1.0, 24).length >= 2)
  end
  # a lettering of his own on a box of writing, and on a label
  sty = PC.text_style('font' => fam, 'bold' => true)
  ok("text_style keeps the lettering: #{sty.inspect}", sty == { bold: true, font: fam })
  ok('a nameless lettering, or too long a one, is not kept', PC.text_style('font' => '  ') == {} && PC.text_style('font' => 'x' * 41) == {})
  doc = PD::Document.new('t')
  doc.canvas('MODEL').layer('WALLS').polyline([[0.0, 0.0], [240.0, 0.0], [240.0, 120.0]], weight: 0.02)
  doc.canvas('MODEL').layer('ROOMS').text('ROOM 1', 100.0, 65.0, h: 7.0, align: :center, rotation: 0.0)
  st = { 'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"', 'hidden' => [], 'origin_x' => 120.0, 'origin_y' => 60.0, 'marks' => [],
         'texts' => [{ 'text' => 'Pool deck', 'on' => 'plan', 'box' => [10.0, 8.0, 3.0, 0.75], 'rot' => 0.0, 'pt' => 36, 'font' => fam, 'italic' => true },
                     { 'text' => 'שלום עולם', 'on' => 'plan', 'box' => [10.0, 12.0, 4.0, 0.75], 'rot' => 0.0, 'pt' => 36 }],
         'text_marks' => { 'ROOMS|ROOM 1|1' => { 'font' => fam, 'bold' => true } } }
  PC.layout_pages!(doc, st)
  pg = doc.pages[0]
  lines = pg.layers.find { |l| l.name == PC::TEXT_LAYER }.shapes.select { |s| s[:type] == :text }
  ok('THE LINES OF THE BOX CARRY THE LETTERING, and so does the box the window is told of',
     lines.any? { |s| s[:text] == 'Pool deck' && s[:font] == fam && s[:italic] } && pg.text_boxes.any? { |b| b[:font] == fam }, lines.map { |s| [s[:text], s[:font]] })
  room = doc.canvas('MODEL').layers.find { |l| l.name == 'ROOMS' }.shapes.find { |s| s[:text] == 'ROOM 1' }
  ok('A LABEL\'S OWN LETTERING (text_marks) lands on the label', room[:font] == fam && room[:bold] == true)
  # the PDF
  out = File.join(TMP, 'fonts.pdf')
  PP.export(doc, out)
  raw = File.binread(out)
  n_t0 = raw.scan('/Subtype /Type0').size
  ok("THE PDF WRITES THE FONTS IN: Type0 fonts, with their files, maps and widths (#{n_t0} faces)",
     n_t0 >= 2 && raw.scan('/FontFile2').size == n_t0 && raw.scan('/ToUnicode').size == n_t0 && raw.include?('/CIDToGIDMap /Identity') && raw.include?('/Encoding /Identity-H'), n_t0)
  body = raw.scan(/stream\r?\n(.*?)endstream/m).map { |m| (Zlib::Inflate.inflate(m[0]) rescue m[0]) }.join("\n")
  ok('the words are shown by glyph id (hex), in a /F4-on font, not in Helvetica', body =~ %r{/F[4-9]\d* [\d.]+ Tf[^\n]*\n[^\n]*\n<[0-9A-F]{8,}> Tj}m)
  ok('the Hebrew box too, and its glyphs are not glyph 0', body.scan(/<([0-9A-F]+)> Tj/).flatten.none? { |h| h.scan(/.{4}/).include?('0000') })
  ok('a Latin label in no lettering is still Helvetica (/F1), as it always was', body =~ %r{/F1 [\d.]+ Tf[^\n]*\n[^\n]*\n\(Scale :\) Tj}m || body.include?('(Scale :) Tj'))
  ok('the font files are deflated, with their true length', raw =~ %r{/Length1 \d+ /Filter /FlateDecode})
  # the switch
  PP.send(:remove_const, :USE_TTF_FONTS)
  PP.const_set(:USE_TTF_FONTS, false)
  PP.forget_fonts!
  ok('SWITCHED OFF: Helvetica only, Hebrew measured as before, no table for the window',
     PP.family_for('שלום', nil).nil? && near(PP.text_width('שלום', 72), 4 * 556 / 1000.0 * 72) && PC.text_rules['fonts'].nil?)
  out2 = File.join(TMP, 'off.pdf')
  PP.export(doc, out2)
  ok('and nothing is written in', !File.binread(out2).include?('/Subtype /Type0'))
  PP.send(:remove_const, :USE_TTF_FONTS)
  PP.const_set(:USE_TTF_FONTS, true)
  PP.forget_fonts!
end

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
