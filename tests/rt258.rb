# encoding: utf-8
# rt258 - A MARK ON ANOTHER ROOF'S WALL IS NOT THIS ROOF'S TO REPORT (2026-10-04).
#
# The last open line of the roof audit he ran with ChatGPT. MEASURED on his
# Aetna model (cross_wall_report.txt, code md5 78d952ce...): the model carries
# ONE gable mark, on 68ea3160 - the wall the gable in the middle of the HOUSE
# roof stands on - and the GARAGE roof printed
#   [Roof] ignoring 1 stale/off-loop gable mark(s)
# about it on every build. Nothing was stale and nothing was ignored: the
# marks are one list for the whole model, and every roof spoke about all of it.
#
# WHAT IS PINNED HERE:
#   * the pure rule: which dropped marks another standing roof answers for;
#   * the real path, on his walls: the garage roof says nothing about the
#     house roof's mark, and the two roofs are the roofs they were;
#   * a mark on a wall that no longer exists is still reported, by every roof;
#   * a mark on a roof's OWN wall that has no edge is still reported by that
#     roof (the gable in the middle switched off) - and only by that roof.
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
RF = InteriorPro::RoofManager

# his walls, as in rt257
WALLS = [
  ['gW', -322.5, 464.5, -322.5, 213.0, 5.0, -18, 'exterior'],
  ['gE',  -62.5, 213.0,  -62.5, 470.0, 5.0, -18, 'exterior'],
  ['gS', -322.5, 213.0,  -62.5, 213.0, 5.0, -18, 'exterior'],
  ['gN',  -62.5, 470.0, -146.0, 470.0, 5.0, -18, 'exterior'],
  ['h1', -452.5, 499.5, -407.0, 499.5, 5.0, 0, 'exterior'],
  ['h2', -737.0, 810.5, -737.0, 464.5, 5.0, 0, 'exterior'],
  ['h3', -452.5, 464.5, -452.5, 499.5, 5.0, 0, 'exterior'],
  ['h4', -737.0, 464.5, -452.5, 464.5, 5.0, 0, 'exterior'],
  ['h5', -407.0, 464.5, -322.5, 464.5, 5.0, 0, 'exterior'],   # his 68ea3160
  ['h6', -407.0, 499.5, -407.0, 464.5, 5.0, 0, 'exterior'],
  ['h7', -146.0, 470.0, -146.0, 810.5, 5.0, 0, 'exterior'],
  ['h8', -146.0, 810.5, -737.0, 810.5, 5.0, 0, 'exterior'],
  ['div', -317.5, 465.0, -151.0, 465.0, 4.5, 0, 'interior']   # his 4743a286
].freeze

def quiet
  old = $stdout
  $stdout = StringIO.new
  begin
    yield
    $stdout.string
  ensure
    $stdout = old
  end
end

def build(marks)
  Sketchup.reset_model!
  WALLS.each do |id, sx, sy, ex, ey, th, bz, cat|
    g = Sketchup.active_model.entities.add_group
    { 'type' => 'wall', 'id' => id, 'start_x' => sx, 'start_y' => sy, 'end_x' => ex, 'end_y' => ey,
      'thickness' => th, 'base_z' => bz.to_f, 'height' => 96.0, 'level' => 1,
      'wall_category' => cat, 'anchor' => 'bottom-left' }.each { |k, v| g.set_attribute('InteriorPro', k, v) }
  end
  Sketchup.active_model.set_attribute('InteriorPro', 'roof_gable_wall_ids', marks)
  quiet { RF.build_roof!(level: 1, style: 'gable', pitch: 3.0) }
end

def house
  RF.roof_of_wall_id('h2')
end

def garage
  RF.roof_of_wall_id('gS')
end

# the log cut into one piece per roof built: [[:house | :garage, text], ...]
def by_roof(log)
  out = []
  cur = []
  log.lines.each do |l|
    cur << l
    next unless l =~ /over level 1: eave ([0-9.]+)/
    out << [Regexp.last_match(1).to_f > 100.0 ? :house : :garage, cur.join]
    cur = []
  end
  out
end

def said(log, who)
  by_roof(log).select { |w, _| w == who }.map { |_, t| t.lines.grep(/ignoring \d+ stale/).map(&:strip) }.flatten
end

def faces(r)
  r.entities.grep(Sketchup::Face).map { |f| f.points.map { |p| [p.x.to_f.round(1), p.y.to_f.round(1), p.z.to_f.round(1)] }.sort }.sort
end

# ---- 1. the pure rule ---------------------------------------------------------------
ok('the code is loaded', RF.respond_to?(:foreign_marks))
if RF.respond_to?(:foreign_marks)
  log = build(%w[h5])
  gwalls = Sketchup.active_model.entities.grep(Sketchup::Group).select { |g| %w[gW gE gS gN].include?(g.get_attribute('InteriorPro', 'id')) }
  hwalls = Sketchup.active_model.entities.grep(Sketchup::Group).select { |g| g.get_attribute('InteriorPro', 'id').to_s =~ /\Ah[0-9]\z/ }
  ok('a mark on a wall the house roof stands on is not the garage roof s', RF.foreign_marks(%w[h5], gwalls, garage) == %w[h5],
     RF.foreign_marks(%w[h5], gwalls, garage))
  ok('a mark on a wall that does not exist is nobody s - it stays reported', RF.foreign_marks(%w[zzz], gwalls, garage) == [])
  ok('a mark on a wall no roof stands on stays reported', RF.foreign_marks(%w[div], gwalls, garage) == [])
  ok('a mark on one of the roof s OWN walls stays reported, whoever else claims it', RF.foreign_marks(%w[h5], hwalls, house) == [] &&
                                                                                 RF.foreign_marks(%w[h5], hwalls, nil) == [])
  ok('the roof being replaced does not answer for itself', RF.foreign_marks(%w[gS], [], garage) == [] &&
                                                         RF.foreign_marks(%w[gS], [], nil) == %w[gS])
  ok('nothing dropped: nothing asked', RF.foreign_marks([], gwalls, garage) == [])
end

# ---- 2. the real path, on his walls ---------------------------------------------------
log = build(%w[h5])
ok('both roofs are built, the garage after the house', by_roof(log).map(&:first).first(2) == %i[house garage], by_roof(log).map(&:first))
ok('the garage roof says nothing about the house roof s mark', said(log, :garage) == [], said(log, :garage))
ok('...and neither does the house roof: its gable stands', said(log, :house) == [] && log =~ /a gable in the middle of the roof/, said(log, :house))
ok('the garage still meets the gable above it', log =~ /stands a gable here/ && log =~ /set 2\.8[78]" lower/)
hf = faces(house)
gf = faces(garage)
ge = garage.get_attribute('InteriorPro', 'gable_edges')

# ---- 3. a mark on a wall that is gone is still reported ---------------------------------
log = build(%w[h5 zzz])
ok('a dead mark: every roof reports it, and only it',
   said(log, :garage).uniq == ['[Roof] ignoring 1 stale/off-loop gable mark(s)'] &&
   said(log, :house).uniq == ['[Roof] ignoring 1 stale/off-loop gable mark(s)'], [said(log, :house), said(log, :garage)])
ok('...and the roofs are face for face the roofs without it', faces(house) == hf && faces(garage) == gf)
ok('...the garage keeps its own gable ends', garage.get_attribute('InteriorPro', 'gable_edges') == ge, [ge, garage.get_attribute('InteriorPro', 'gable_edges')])

# ---- 4. a roof s OWN wall with no edge is still reported - by that roof alone ----------
RF.send(:remove_const, :USE_CROSS_GABLE)
RF.const_set(:USE_CROSS_GABLE, false)
log = build(%w[h5])
ok('the gable in the middle switched off: the house roof says its mark is dropped',
   said(log, :house).uniq == ['[Roof] ignoring 1 stale/off-loop gable mark(s)'], said(log, :house))
ok('...and the garage roof still has nothing to say about it', said(log, :garage) == [], said(log, :garage))
RF.send(:remove_const, :USE_CROSS_GABLE)
RF.const_set(:USE_CROSS_GABLE, true)

puts($fails.zero? ? 'ALL PASS' : "#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
