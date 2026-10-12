# encoding: utf-8
# rt298 - an elevation in layers (2026-10-09, ElevationTool::USE_ELEV_LAYERS): each wall is also taken once for every
# mix of tiles / plumbing / electric switched off that stands in front of it (<picture>__no_plumbing+tile.png, named
# in <picture>.layers.json); the sheet shows the one his groups ask for (PlanCanvas.pic_shown - :show, which the PDF
# prints); a niche's numbers go with the tiles, a fixture's with the plumbing (dims 'g' -> :grp).
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
ET = InteriorPro::ElevationTool
PC = InteriorPro::PlanCanvas
psd = InteriorPro::PlanSheetDialog

ok('the switch is on', ET::USE_ELEV_LAYERS == true)
ok('every mix, small first', ET.cat_mixes(%w[tile plumbing]) == [['plumbing'], ['tile'], %w[plumbing tile]], ET.cat_mixes(%w[tile plumbing]))
ok('three make seven', ET.cat_mixes(%w[a b c]).size == 7)
ok('the files beside the picture', ET.variant_file('/e/Room_2_North_lines.png', %w[tile plumbing]) == '/e/Room_2_North_lines__no_plumbing+tile.png' &&
   ET.layers_file('/e/Room_2_North_lines.png') == '/e/Room_2_North_lines.layers.json')
ok('a tile, a fixture, an outlet - each its own; a wall none', ET.cat_of('tile_wall') == 'tile' && ET.cat_of('tile_niche') == 'tile' &&
   ET.cat_of('fixture') == 'plumbing' && ET.cat_of('outlet') == 'electric' && ET.cat_of('wall').nil?)

# the shots: a stand-in for the view writes a file per shot and remembers what was hidden at that moment
dir = Dir.mktmpdir('elev_layers')
path = File.join(dir, 'Room_2_North_lines.png')
File.write(path, 'full')
Ent = Struct.new(:hidden, :name) do
  def hidden?; hidden; end
  def valid?; true; end
end
tile = Ent.new(false, 'tile')
loo = Ent.new(false, 'toilet')
seen = {}
view = Object.new
view.define_singleton_method(:refresh) { nil }
view.define_singleton_method(:write_image) do |p, _w, _h, _aa|
  seen[File.basename(p)] = [tile.hidden?, loo.hidden?]
  File.write(p, 'x')
  true
end
TH = Struct.new(:ent, :xf, :type)
cats = { 'tile' => [TH.new(tile, nil, 'tile_wall')], 'plumbing' => [TH.new(loo, nil, 'fixture')], 'electric' => [] }
n = ET.shoot_variants!(view, path, 100, 80, cats)
ok('three pictures: without the plumbing, without the tiles, without both', n == 3 && seen.keys.sort == %w[Room_2_North_lines__no_plumbing+tile.png Room_2_North_lines__no_plumbing.png Room_2_North_lines__no_tile.png], seen)
ok('each taken with exactly those hidden', seen['Room_2_North_lines__no_plumbing.png'] == [false, true] && seen['Room_2_North_lines__no_tile.png'] == [true, false] &&
   seen['Room_2_North_lines__no_plumbing+tile.png'] == [true, true], seen)
ok('and everything is back on after', !tile.hidden? && !loo.hidden?)
lj = JSON.parse(File.read(ET.layers_file(path)))
ok('the file names the layers and their pictures (electric: nothing in front of it, no layer)', lj['cats'] == %w[plumbing tile] && lj['files'].size == 3, lj)
none = ET.shoot_variants!(view, File.join(dir, 'Bare_East_lines.png'), 10, 10, { 'tile' => [] })
ok('a wall with none of them: no pictures, no file', none.zero? && !File.file?(File.join(dir, 'Bare_East_lines.layers.json')))

# the sheet reads them
lay = PC.pic_layers(path)
ok('the sheet reads the layers of a picture', lay && lay['cats'] == %w[plumbing tile] && lay['files']['tile'].end_with?('__no_tile.png'), lay)
ok('the picture shown: the whole one, or without what is off', PC.pic_shown(lay, []).nil? && PC.pic_shown(lay, %w[dims]).nil? &&
   PC.pic_shown(lay, %w[plumbing]).end_with?('__no_plumbing.png') && PC.pic_shown(lay, %w[tile plumbing walls]).end_with?('__no_plumbing+tile.png'))

st = psd.load_state
st['images'] = [path]
st['image_dims'] = { path.tr('\\', '/') => [{ 'k' => 'h', 'row' => 2, 'u' => [0.1, 0.9], 'v' => 0.1, 't' => '87"' },
                                            { 'k' => 'v', 'side' => 'L', 'col' => 1, 'v' => [0.1, 0.5], 'u' => 0.9, 't' => '30"', 'g' => 'plumbing' }] }
st['hide'] = ['plumbing']
psd.save_state(st)
psd.instance_variable_set(:@doc, nil)
pg = psd.document.pages.find { |p| p.kind == 'image' }
img = pg.layers.find { |l| l.name == InteriorPro::PlanDoc::IMAGE_LAYER }.shapes.find { |s| s[:type] == :image }
ok('plumbing off: the sheet shows the picture without it', img[:show].to_s.end_with?('__no_plumbing.png') && img[:layers]['cats'] == %w[plumbing tile], [img[:show], img[:layers]])
ed = pg.layers.find { |l| l.name == PC::ELEV_DIM_LAYER }.shapes
ok('a fixture\'s height goes off with the plumbing, the wall\'s length stays', ed.select { |s| s[:grp] == 'plumbing' }.all? { |s| s[:off] } &&
   ed.reject { |s| s[:grp] }.none? { |s| s[:off] } && ed.any? { |s| s[:grp] == 'plumbing' }, ed.map { |s| [s[:type], s[:grp], s[:off]] })
src = File.read('./plan_pdf.rb', encoding: 'utf-8')
ok('the PDF prints the picture shown', src.scan('imgs.name_for(s[:show] || s[:path])').size == 2)
st['hide'] = []
psd.save_state(st)
psd.instance_variable_set(:@doc, nil)
img2 = psd.document.pages.find { |p| p.kind == 'image' }.layers.find { |l| l.name == InteriorPro::PlanDoc::IMAGE_LAYER }.shapes.find { |s| s[:type] == :image }
ok('nothing off: the whole picture', img2[:show].nil?)
pay = psd.send(:image_payload, st)
ok('the window gets an address for each of them', pay[0]['variants'].size == 3 && pay[0]['variants'].all? { |v| v['url'].start_with?('file:///') })

# the numbers: a niche's go with the tiles, a set's with the plumbing, the wall's own with neither
side = ET::Side.new('North', Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, 0, 0), 100.0, Geom::Vector3d.new(0, 1, 0), 60.0)
items = [{ kind: 'niche', a0: 20.0, a1: 40.0, z0: 40.0, z1: 60.0 }, { kind: 'part', a0: 70.0, a1: 70.0, z0: 30.0, z1: 30.0, fix: 1, name: 'valve' },
         { kind: 'fixture', a0: 75.0, a1: 95.0, z0: 0.0, z1: 20.0 }]
ds = ET.dims_clean(side, 96.0, items)
whole = ds.find { |d| d['k'] == 'h' && d['t'] == '100"' }
hgt = ds.find { |d| d['t'] == '96"' }
ok('a niche\'s numbers are tiles\'', ds.select { |d| d['k'] == 'hi' && d['from'] }.all? { |d| d['g'] == 'tile' } && ds.any? { |d| d['g'] == 'tile' })
ok('a set\'s and a fixture\'s are plumbing\'s', ds.any? { |d| d['g'] == 'plumbing' && d['k'] == 'hi' } && ds.any? { |d| d['g'] == 'plumbing' && d['k'] == 'v' })
ok('the wall\'s length and height belong to neither', whole && hgt && !whole.key?('g') && !hgt.key?('g'), [whole, hgt])

# ---- on demand (USE_LAZY_LAYERS, 10:17 measured: 12 of the button's 23 s were these pictures)
ok('on demand is on', ET::USE_LAZY_LAYERS == true)
meta = { 'room' => 'Room 2', 'room_pid' => 77, 'side' => 'North', 'cut' => 48.0, 'style' => 'lines' }
before = Dir[File.join(dir, '*__no_*.png')].size
ET.write_layers_index!(path, cats, meta)
lj2 = JSON.parse(File.read(ET.layers_file(path)))
ok('the button only writes down the layers and how to take them again', lj2['cats'] == %w[plumbing tile] && lj2['files'] == {} &&
   lj2['side'] == 'North' && lj2['cut'] == 48.0 && lj2['room_pid'] == 77, lj2)
ok('and the pictures of the shot before go (they show the room as it was)', before == 3 && Dir[File.join(dir, '*__no_*.png')].empty?)
seen.clear
ET.shoot_variants!(view, path, 100, 80, cats, [['plumbing']], meta)
lj3 = JSON.parse(File.read(ET.layers_file(path)))
ok('on demand: only the one asked for, added to the file, the rest kept', seen.keys == ['Room_2_North_lines__no_plumbing.png'] &&
   lj3['files'].keys == ['plumbing'] && lj3['side'] == 'North', [seen, lj3])
ET.shoot_variants!(view, path, 100, 80, cats, [%w[tile plumbing]], meta)
ok('and the next one is added beside it', JSON.parse(File.read(ET.layers_file(path)))['files'].keys.sort == ['plumbing', 'plumbing+tile'])

# the sheet asks for what is missing: one room taken again, only those walls and mixes
calls = []
RoomT = Struct.new(:ent)
rent = Object.new
rent.define_singleton_method(:persistent_id) { 77 }
ET.define_singleton_method(:rooms) { |*_| [RoomT.new(rent)] }
ET.define_singleton_method(:room_name) { |_r| 'Room 2' }
ET.define_singleton_method(:shoot!) { |room, **kw| calls << kw; [] }
n2 = ET.ensure_variants!([[path, ['tile']], [path, %w[plumbing tile]]])
ok('the room is found by its id and taken again with only: those mixes, its own cut', n2 == 2 && calls.size == 1 &&
   calls[0][:only] == { 'North' => [['tile'], %w[plumbing tile]] } && calls[0][:cut] == { 'walls' => { 'North' => 48.0 } }, calls)
calls.clear
PC.instance_variable_set(:@pic_layers, {})
st['hide'] = ['tile']
pg3 = psd.document.pages.find { |p| p.kind == 'image' }
asked = nil
ET.define_singleton_method(:ensure_variants!) { |need, *_| asked = need; need.size }
said = []
psd.define_singleton_method(:erase_trace) { |t| said << t }
k = psd.send(:ensure_layer_pictures!, [pg3], st)
ok('tile off over a picture never taken without it: the sheet asks for it, once', k == 1 && asked == [[path, ['tile']]], [k, asked])
ok('and says so in the trace', said.any? { |t| t.include?('layers: 1 pictures taken without tile') }, said)
asked = nil
st['hide'] = ['plumbing']
k2 = psd.send(:ensure_layer_pictures!, [pg3], st)
ok('a picture already taken is not taken again', k2.zero? && asked.nil?, asked)
st['hide'] = []
ok('nothing off: nothing asked', psd.send(:ensure_layer_pictures!, [pg3], st).zero?)
src = File.read('./plan_sheet_dialog.rb', encoding: 'utf-8')
ok('switching a layer off and printing both ask', src.include?('if act && ensure_layer_pictures!([act], st) > 0') && src.include?('if ensure_layer_pictures!(pages, st) > 0'))

ET.send(:remove_const, :USE_ELEV_LAYERS)
ET.const_set(:USE_ELEV_LAYERS, false)
ok('switched off: one picture a wall, as before', ET.shoot_variants!(view, File.join(dir, 'Off_lines.png'), 1, 1, cats).zero?)
FileUtils.rm_rf(dir)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
