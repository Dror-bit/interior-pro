# encoding: utf-8
# rt248 - THE CUT LINES THAT CUT NOTHING ARE HIDDEN (2026-10-02).
#
# His picture of the garage roof running into the house roof: "להוריד את
# הקווים האלו". Measured on his model (valley_skin_report.txt): seven edges
# between two faces of the SAME plane - two diagonals 118" and 120" long
# across the garage's slopes, two on the house roof, three short ones on
# the house's rake soffit. None of them is a crease. They are what the two
# valley sweeps leave behind: each splits every face that crosses the cut
# plane right across, outline to outline, and takes out only the pieces
# inside the cut region. Outside it both halves stay, with the line between.
#
# Pinned: the sweeps write down the lines they draw; at the end of the build
# a line with a face on both sides, on one plane, is softened; a line that
# is a real edge of the cut is left alone; the kill switch leaves them all.
ENV['REAL_ROOMS'] = '1'
require 'stringio'
require './sketchup_stub'
require './room_manager'
require './level_manager'
require './arc_math'
require './roof_tile_math'
require './roof_tile_parts'
require './roof_tile_place'
require './roof_manager'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

def quiet
  old = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = old
end

RF = InteriorPro::RoofManager
P = Geom::Point3d
V = Geom::Vector3d
def set_const(name, val)
  RF.send(:remove_const, name) if RF.const_defined?(name, false)
  RF.const_set(name, val)
end
ok('the code is loaded', RF.respond_to?(:valley_hide_cut_lines!) && RF.respond_to?(:valley_note_cut_line) && RF.respond_to?(:valley_cut_lines))

# ---- 1. which lines are hidden ---------------------------------------------------
FF = Struct.new(:normal)
def edge_between(*faces)
  e = Sketchup::Edge.new(P.new(0, 0, 0), P.new(1, 0, 0))
  e.faces = faces
  e
end
if RF.respond_to?(:valley_hide_cut_lines!)
  up = V.new(-0.25, 0.0, 1.0).normalize
  other = V.new(0.25, 0.0, 1.0).normalize
  seam = edge_between(FF.new(up), FF.new(up))            # a face on each side, one plane
  flip = edge_between(FF.new(up), FF.new(V.new(0.25, 0.0, -1.0).normalize)) # ...one of them born facing down
  cut = edge_between(FF.new(up))                         # the cut's own edge: one face left
  crease = edge_between(FF.new(up), FF.new(other))       # two planes: a real line
  bare = edge_between                                    # nothing left on it
  RF.valley_cut_lines.clear
  [seam, flip, cut, crease, bare, seam, nil].each { |e| RF.valley_note_cut_line(e) }
  ok('the list keeps what it is handed, and never a nil', RF.valley_cut_lines.length == 6, RF.valley_cut_lines.length)
  n = RF.valley_hide_cut_lines!
  ok('a line with a face on BOTH sides, on one plane, is softened', seam.soft? && seam.smooth?)
  ok('...also when one of the two faces looks the other way', flip.soft? && flip.smooth?)
  ok('...and it is counted once however often it was written down', n == 2, n)
  ok('the cut\'s own edge - a face on one side only - is left alone', !cut.soft? && !cut.smooth?)
  ok('a real crease between two planes is left alone', !crease.soft?)
  ok('a line with no face at all is left alone', !bare.soft?)
  ok('the list is empty afterwards', RF.valley_cut_lines.empty?)
  ok('a second call has nothing to do', RF.valley_hide_cut_lines!.zero?)
end

# ---- 2. the two sweeps write their lines down -----------------------------------
# The stub's faces have no loops and cannot be erased; give them just enough
# for the sweeps to walk (this file only).
module Sketchup
  class Face
    OL = Struct.new(:vertices) unless const_defined?(:OL, false)
    def outer_loop; OL.new(vertices); end
    def edges; []; end
    def erase!; @gone = true; end
    def valid?; !@gone; end
  end
end

def group_with(*faces)
  Sketchup.reset_model!
  g = Sketchup.active_model.entities.add_group
  [g, faces.map { |pts| g.entities.add_face(pts.map { |x, y, z| P.new(x, y, z) }) }]
end

# His garage's east skin (z = -0.25x + 68.89) against the house's deck plane
# (z = 0.25y - 14.125): they meet on x + y = 332.06. The cut region is the
# small triangle inside the house, already taken out of the skin by the deck
# cut; the skin face itself runs 280" down to the front of the garage.
SKIN = [[-192.5, 201.0], [-50.5, 201.0], [-50.5, 481.5], [-134.0, 481.5], [-134.0, 464.5], [-151.5, 481.5], [-192.5, 481.5]]
       .map { |x, y| [x, y, -0.25 * x + 68.375 + 0.5154] }.freeze
HP = [0.0, 0.25, -14.125].freeze
REGION = [[-134.0, 464.5, 0.0], [-134.0, 481.5, 0.0], [-151.5, 481.5, 0.0]].freeze
grp, = group_with(SKIN)
RF.valley_cut_lines.clear
quiet { RF.valley_sweep_under!(grp, { poly: REGION, hp: HP, wall: [-134.0, 464.5], inw: [0.0, 1.0] }) }
ls = RF.valley_cut_lines
ok('valley_sweep_under! writes down the line it draws across the skin', ls.length == 1, ls.length)
if ls.length == 1
  ends = [ls[0].start.position, ls[0].end.position].map { |p| [p.x.to_f.round(2), p.y.to_f.round(2)] }.sort
  ok('...the very line measured on his model: (-134, 466.06) down to the eave at (-50.5, 382.56), 120" long',
     ends == [[-134.0, 466.06], [-50.5, 382.56]], ends)
end

# the overhang strip: an upright face crossing the wall line inside the strip
STRIP = { poly: [[-334.5, 464.5, 0.0], [-334.5, 481.5, 0.0], [-322.5, 481.5, 0.0], [-322.5, 464.5, 0.0]],
          wall: [[-334.5, 464.5], [-322.5, 464.5]], along: [0.0, 1.0],
          inner: [[-322.5, 481.5], [-322.5, 464.5]], inw: [1.0, 0.0] }.freeze
grp, = group_with([[-334.5, 440.0, 81.0], [-334.5, 481.5, 81.0], [-334.5, 481.5, 81.52], [-334.5, 440.0, 81.52]])
RF.valley_cut_lines.clear
quiet { RF.valley_low_strip_sweep!(grp, STRIP) }
ok('valley_low_strip_sweep! writes its lines down too', RF.valley_cut_lines.length == 1, RF.valley_cut_lines.length)

# ---- 3. the builder starts clean and hides at the end ----------------------------
WALLS = [
  ['gW', -322.5, 464.5, -322.5, 213.0, 5.0, -18, 'exterior'],
  ['gE',  -62.5, 213.0,  -62.5, 470.0, 5.0, -18, 'exterior'],
  ['gS', -322.5, 213.0,  -62.5, 213.0, 5.0, -18, 'exterior'],
  ['gN',  -62.5, 470.0, -146.0, 470.0, 5.0, -18, 'exterior'],
  ['h1', -452.5, 499.5, -407.0, 499.5, 5.0, 0, 'exterior'],
  ['h2', -737.0, 810.5, -737.0, 464.5, 5.0, 0, 'exterior'],
  ['h3', -452.5, 464.5, -452.5, 499.5, 5.0, 0, 'exterior'],
  ['h4', -737.0, 464.5, -452.5, 464.5, 5.0, 0, 'exterior'],
  ['h5', -407.0, 464.5, -322.5, 464.5, 5.0, 0, 'exterior'],
  ['h6', -407.0, 499.5, -407.0, 464.5, 5.0, 0, 'exterior'],
  ['h7', -146.0, 470.0, -146.0, 810.5, 5.0, 0, 'exterior'],
  ['h8', -146.0, 810.5, -737.0, 810.5, 5.0, 0, 'exterior'],
  ['div', -317.5, 465.0, -151.0, 465.0, 4.5, 0, 'interior']
].freeze

def build
  Sketchup.reset_model!
  m = Sketchup.active_model
  WALLS.each do |id, sx, sy, ex, ey, th, bz, cat|
    g = m.entities.add_group
    { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey,
      'thickness' => th, 'base_z' => bz.to_f, 'height' => 96.0, 'level' => 1,
      'wall_category' => cat, 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  end
  quiet do
    RF.build_roof!(level: 1, style: 'gable', pitch: 3.0)
    2.times { RF.roofs.each { |r| RF.build_roof!(replace: r, pitch: 3) } }
  end
end

set_const(:USE_ROOF_VALLEY, true)
# every drawn line comes back with a face on both sides, on one plane - what a
# line across the middle of a flat sheet looks like in SketchUp
seen = []
RF.singleton_class.send(:alias_method, :__note, :valley_note_cut_line)
RF.define_singleton_method(:valley_note_cut_line) do |e|
  if e
    e.faces = [FF.new(V.new(0, 0, 1)), FF.new(V.new(0, 0, 1))]
    seen << e
  end
  __note(e)
end
RF.valley_cut_lines << Sketchup::Edge.new(P.new(9, 9, 9), P.new(8, 8, 8))   # a stale one from "before"
stale = RF.valley_cut_lines.last
log = build
ok('on his walls the sweeps draw cut lines', !seen.empty?, seen.length)
ok('every one of them left on a flat sheet is hidden by the end of the build', seen.all? { |e| e.soft? && e.smooth? },
   seen.count { |e| !e.soft? })
ok('the builder says how many', log =~ /valley: \d+ cut line\(s\) left across a flat surface hidden/, log.lines.grep(/hidden/))
ok('a line written down before this build is not carried into it', !stale.soft?)
ok('nothing is left in the list', RF.valley_cut_lines.empty?)

# ---- 4. the kill switch ---------------------------------------------------------
set_const(:USE_VALLEY_SEAM_HIDE, false)
seen.clear
lk = build
ok('kill switch: the lines are drawn as before...', !seen.empty?)
ok('kill switch: ...and none is softened', seen.none?(&:soft?), seen.count(&:soft?))
ok('kill switch: nothing is said', lk !~ /cut line\(s\) left across/)
ok('kill switch: the list is still emptied', RF.valley_cut_lines.empty?)

puts $fails.zero? ? 'ALL PASS' : "#{$fails} FAILED"
exit($fails.zero? ? 0 : 1)
