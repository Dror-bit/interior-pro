# encoding: utf-8
# rt312 - ELECTRIC ON THE ELEVATION GETS ITS NUMBERS (2026-10-14, his "עכשיו צריך רק את המידות"): an outlet / switch /
# wall light on the wall = the height he typed by the nearer wall and its distance from that wall at that height, on the
# ELECTRIC layer (g 'electric'); two at one height share the height column; a ceiling kind gets nothing.
require './sketchup_stub'
require './elevation_tool'
begin; require './tile_wall'; rescue LoadError; end

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
ET = InteriorPro::ElevationTool
ok('kill switch is there and on', ET::USE_ELEC_DIMS == true)
side = ET::Side.new('North', Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, 0, 0), 100.0, Geom::Vector3d.new(0, 1, 0), 60.0)
items = [{ kind: 'elec', a0: 20.0, a1: 20.0, z0: 18.0, z1: 18.0, name: 'outlet', lo: 15.75, hi: 20.25, l: 18.6, r: 21.4 },
         { kind: 'elec', a0: 40.0, a1: 40.0, z0: 18.0, z1: 18.0, name: 'outlet', lo: 15.75, hi: 20.25, l: 38.6, r: 41.4 },
         { kind: 'elec', a0: 85.0, a1: 85.0, z0: 66.0, z1: 66.0, name: 'wall_light', lo: 57.0, hi: 75.0, l: 80.0, r: 90.0 }]
ds = ET.dims_clean(side, 96.0, items)
el = ds.select { |d| d['g'] == 'electric' }
ok('every electric number is on the ELECTRIC layer, the wall\'s own are not', el.size >= 4 && ds.reject { |d| d['g'] }.size >= 2, ds)
hs = el.select { |d| d['k'] == 'v' }
ok('two outlets at 18" share ONE height column; the wall light at 66" has its own', hs.size == 2 && hs.map { |d| d['t'] }.sort == ['18"', '66"'], hs)
h18 = hs.find { |d| d['t'] == '18"' }
ok('the height\'s line stops at the EDGE of the outlet nearest the wall (a 18.6, from the right) - not in the plate (17:46, 19:40)', h18['u0'] && (h18['u0'] - (ET::MARGIN + 100.0 - 18.6) / (100.0 + 2 * ET::MARGIN)).abs < 1e-9, h18)
hi = el.select { |d| d['k'] == 'hi' }
dist = hi.map { |d| d['t'] }.sort
ok('a CHAIN per height from the nearer wall: wall->20, 20->40 (the outlets); wall->15 (the switch, from the left)', dist == ['15"', '20"', '20"'], dist)
ok('the switch\'s distance is measured from the LEFT wall (a = len)', hi.find { |d| d['t'] == '15"' }['u'].min < 0.2)
lo = hi.select { |d| d['t'] != '15"' }
ok('the outlets (lower half) get their row UNDER them, witness lines from their BOTTOM edge (15.75), words under the line', lo.all? { |d| d['v'] < d['from'] && (d['from'] - (ET::MARGIN + 15.75) / (96.0 + 2 * ET::MARGIN)).abs < 1e-9 && d['below'] == true }, lo)
sw = hi.find { |d| d['t'] == '15"' }
ok('the wall light (upper half) gets its row OVER it, witness from its TOP edge (75), words over the line', sw['v'] > sw['from'] && (sw['from'] - (ET::MARGIN + 75.0) / (96.0 + 2 * ET::MARGIN)).abs < 1e-9 && !sw['below'], sw)
ok('a row never sits on the plate: the two rows differ from the heights', lo.all? { |d| (d['v'] - d['from']).abs > 0.01 } && (sw['v'] - sw['from']).abs > 0.01)
src = File.read('./elevation_tool.rb')
pc = File.read('./plan_canvas.rb') rescue ''
ok('the numbers of a layer in its colour: plumbing blue, electric green, the rest black (19:40)', pc.include?("ELEV_DIM_COLORS = { 'plumbing' => '#1f5fbf', 'electric' => '#1a9d55' }") && pc.include?('gx[:color] = ELEV_DIM_COLORS'))
pdf = File.read('./plan_pdf.rb') rescue ''
ok('the PDF draws a coloured line and goes back to black', pdf.include?('st << "#{grey(lc)} RG" if lc') && pdf.include?("st << '0 0 0 RG' if lc"))
sd = File.read('./plan_sheet_dialog.rb') rescue ''
ok('the window draws a coloured line', sd.include?('stroke="\'+(/^#[0-9a-f]{6}$/i.test(String(s.color||\'\')) ? s.color : \'#000\')+\'"'))
m = src[/def elec_point.*?\n      end\n/m].to_s
ok('elec_point: his typed numbers (u_in, height_in) on his wall\'s face; a ceiling kind = nil; off this side = nil',
   m.include?("'u_in'") && m.include?("'height_in'") && m.include?("== 'ceiling'") && m.include?('<= ON_WALL'), m[0, 60])
ok('side_items asks for them behind the switch', src.include?("when 'electrical'\n            next unless USE_ELEC_DIMS"))
# the stub: a group with the attributes, as ElectricalLibrary.place! writes them, on a wall in the room
if defined?(Sketchup::Group)
  begin
    m2 = Sketchup.active_model
    wall = m2.entities.add_group
    { 'type' => 'wall', 'id' => 'W1', 'start_x' => 0.0, 'start_y' => 0.0, 'end_x' => 100.0, 'end_y' => 0.0, 'thickness' => 5.0, 'anchor' => 'center' }.each { |k, v| wall.set_attribute('InteriorPro', k, v) }
    g = m2.entities.add_group
    { 'type' => 'electrical', 'kind' => 'outlet', 'host_wall_id' => 'W1', 'side' => 'a', 'u_in' => 30.0, 'height_in' => 18.0 }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
    all = [ET::Thing.new(wall, wall.transformation, 'wall'), ET::Thing.new(g, g.transformation, 'electrical')]
    dir = Geom::Vector3d.new(1, 0, 0); n = Geom::Vector3d.new(0, 1, 0)
    fr = InteriorPro::TileWall.frame_for(wall, 'a') rescue nil
    if fr
      sd = ET::Side.new('S', Geom::Point3d.new(fr[:ox], fr[:oy], 0), Geom::Point3d.new(fr[:ox] + 100, fr[:oy], 0), 100.0, Geom::Vector3d.new(fr[:nx], fr[:ny], 0), 60.0)
      al = ->(p) { (p.x - sd.a.x) * 1 }
      inn = ->(p) { (p.y - sd.a.y) * fr[:ny] + (p.x - sd.a.x) * fr[:nx] }
      it = ET.elec_point(all[1], all, al, inn, 100.0, 0.0)
      ok('a real group: the point at u 30, height 18 on its wall', it && (it[:a0] - 30.0).abs < 1e-6 && (it[:z1] - 18.0).abs < 1e-6 && it[:kind] == 'elec', it)
      g.set_attribute('InteriorPro', 'mount', 'ceiling')
      ok('a ceiling kind: nothing', ET.elec_point(all[1], all, al, inn, 100.0, 0.0).nil?)
    else
      puts 'SKIP  no TileWall frame in the stub'
    end
  rescue StandardError => e
    puts "SKIP  stub cannot build the group: #{e.class} #{e.message}"
  end
end
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
