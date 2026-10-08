# encoding: utf-8
# rt279 - the VISUALIZE by Dror logo ships with the plugin (2026-10-07), the Ruby side.
#
# The user: "תכניס את הלוגו הזה ואם אני ארצה להכניס לוגו שונה אני אכניס אבל זה
# צריך להיות הלוגו של VISUALIZE". So:
#   - a model with no logo picked prints assets/LOGO/visualize_by_dror.jpg in
#     the title block of every sheet, and the window is told it is the built-in
#     one (t36 pins what the window does with that);
#   - a logo he picks still wins; "back to VISUALIZE" brings the shipped one back;
#   - the file missing = the two words set in type, as before (no empty box);
#   - the PDF carries the picture;
#   - the switch puts the old behaviour back.
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

TMP = File.join(File.dirname(File.expand_path(__FILE__)), 'rt279_tmp')
FileUtils.rm_rf(TMP)
FileUtils.mkdir_p(TMP)
# the shipped file lives under the plugin folder, which in here is tests/
LOGO = File.join(PSD.plugin_dir, PSD::DEFAULT_LOGO)
HAD_LOGO = File.file?(LOGO)
at_exit do
  FileUtils.rm_rf(TMP)
  unless HAD_LOGO
    FileUtils.rm_f(LOGO)
    FileUtils.rm_rf(File.dirname(LOGO)) if Dir.exist?(File.dirname(LOGO)) && Dir.empty?(File.dirname(LOGO))
    up = File.dirname(File.dirname(LOGO))
    FileUtils.rm_rf(up) if Dir.exist?(up) && Dir.empty?(up)
  end
end

# a JPEG with nothing but the markers the reader walks
def jpg(path, w, h)
  FileUtils.mkdir_p(File.dirname(path))
  sof = [8, h, w, 3].pack('CnnC') + ("\x01\x11\x00".b * 3)
  out = +"\xFF\xD8".b
  out << "\xFF\xC0".b << [sof.bytesize + 2].pack('n') << sof
  out << "\xFF\xDA".b << [8].pack('n') << "\x01\x01\x00\x00\x3F\x00".b
  out << "\x12\x34".b << "\xFF\xD9".b
  File.binwrite(path, out)
  path.tr('\\', '/')
end
MINE = jpg(File.join(TMP, 'mine.jpg'), 400, 200)

ok('there is a switch for it, and it is on', PSD.const_defined?(:USE_DEFAULT_LOGO, false) && PSD::USE_DEFAULT_LOGO == true)
ok('the file is named under assets/LOGO', PSD::DEFAULT_LOGO == 'assets/LOGO/visualize_by_dror.jpg')

def title(doc); doc.pages.first.layer(PD::TITLE_LAYER).shapes; end
def logo_img(doc); title(doc).find { |s| s[:type] == :image }; end
def words(doc); title(doc).select { |s| s[:type] == :text }.map { |s| s[:text] }; end

def open!
  Sketchup.reset_model!
  %i[@site_lines @site_owner @site_owner_path @doc].each { |iv| PSD.instance_variable_set(iv, nil) }
  PSD.show
  dlg = PSD.instance_variable_get(:@dialog)
  dlg.callbacks['sheet_ready'].call(nil)
  dlg
end
def sheet(dlg); JSON.parse(dlg.scripts.reverse.find { |x| x.start_with?('loadSheet(') }[/\AloadSheet\((.*)\)\z/m, 1]); end

# 1. the file is not there (a plugin folder without it): the words in type, as before
FileUtils.rm_f(LOGO) unless HAD_LOGO
unless HAD_LOGO
  ok('THE FILE MISSING: no logo at all - not an empty box', PSD.default_logo.nil? && PSD.logo_path({}).nil? && PSD.logo_payload({}).nil?)
  dlg = open!
  ok('the title block sets the two words in type, as it always did', logo_img(PSD.document).nil? && words(PSD.document).include?('VISUALIZE') && sheet(dlg)['logo'].nil?, words(PSD.document))
end

# 2. the file is there: every sheet prints it
jpg(LOGO, 2576, 1202) unless HAD_LOGO
ok('the shipped file is found under the plugin folder', PSD.default_logo == LOGO.tr('\\', '/') || PSD.default_logo == LOGO, PSD.default_logo)
dlg = open!
d = PSD.document
img = logo_img(d)
ok('A MODEL WITH NO LOGO PICKED: the title block prints the shipped picture, in the logo corner',
   img && img[:path] == PSD.default_logo && img[:w] == 2.2 && img[:h] > 0 && !words(d).include?('VISUALIZE'), [img, words(d)])
ok('on every sheet', d.pages.all? { |pg| pg.layer(PD::TITLE_LAYER).shapes.any? { |s| s[:type] == :image && s[:path] == PSD.default_logo } })
pl = sheet(dlg)['logo']
ok('THE WINDOW IS TOLD: it is the built-in one, where the file is, by name',
   pl && pl['builtin'] == true && pl['path'] == PSD.default_logo && pl['there'] == true && pl['name'] == 'VISUALIZE by Dror' && pl['url'].start_with?('file:///'), pl)
ok('nothing is written on the model for it: st[logo] stays empty', PSD.load_state['logo'].nil?)

# 3. the PDF carries it
out = File.join(TMP, 'logo.pdf')
PP.export(d, out)
raw = File.binread(out)
ok('THE PDF HAS THE PICTURE (a JPEG image object)', raw.include?('/DCTDecode') && raw.include?('/Subtype /Image') && raw.include?('/Width 2576'), raw.scan(/\/Width \d+/).first(3))

# 4. a logo he picks wins, and the way back is the shipped one
st = PSD.load_state
st['logo'] = MINE
PSD.save_state(st)
PSD.instance_variable_set(:@doc, nil)
PSD.push_all(dlg)
ok('A LOGO HE PICKED WINS', logo_img(PSD.document)[:path] == MINE && sheet(dlg)['logo']['builtin'].nil? && sheet(dlg)['logo']['name'] == 'mine.jpg', sheet(dlg)['logo'])
dlg.callbacks['clear_logo'].call(nil)
ok('"back to VISUALIZE": the shipped one again', PSD.load_state['logo'].nil? && logo_img(PSD.document)[:path] == PSD.default_logo && sheet(dlg)['logo']['builtin'] == true)
st = PSD.load_state
st['logo'] = 'C:/gone/logo.png'
PSD.save_state(st)
PSD.instance_variable_set(:@doc, nil)
PSD.push_all(dlg)
ok('a picked logo whose file has moved is still his choice (the window says it is missing), not swapped for the shipped one',
   logo_img(PSD.document)[:path] == 'C:/gone/logo.png' && sheet(dlg)['logo']['there'] == false && sheet(dlg)['logo']['builtin'].nil?)

# 5. the switch
PSD.send(:remove_const, :USE_DEFAULT_LOGO)
PSD.const_set(:USE_DEFAULT_LOGO, false)
dlg = open!
ok('SWITCHED OFF: no logo picked = the two words in type, and the window is told of no logo', logo_img(PSD.document).nil? && words(PSD.document).include?('VISUALIZE') && sheet(dlg)['logo'].nil?)
PSD.send(:remove_const, :USE_DEFAULT_LOGO)
PSD.const_set(:USE_DEFAULT_LOGO, true)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
