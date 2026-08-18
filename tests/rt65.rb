# encoding: utf-8
# rt65 - rubbing ONE line off the sheet (2026-08-17).
#
# The user sent two pictures of his own floor plan with three red circles on
# them: short lines crossing the path, and the seam running down the middle of
# the pool coping. His words: "אני רוצה למחוק אותם שהציור יהיה יותר נקי".
#
# Before this, the sheet window had exactly two settings for that geometry:
# every line, or none of them ("נקה גיאומטריה חופשית"). The layer list is the
# same all-or-nothing switch one level up. There was no way to lose one line.
#
# THE DECISION THIS SUITE PINS, and it is the whole design:
#
#   PlanGeometry.build! writes the free lines onto the SITE layer in the order
#   they sit in PlanSheetDialog's list, one polyline each. So shape number i on
#   the sheet IS site_lines[i]. The window sends a NUMBER; Ruby takes that
#   number out of the list. Nothing is matched by coordinate, so two lines
#   lying on top of each other can never be confused for one another.
#
# Break that ordering and the user deletes the wrong line - which he will read
# as the feature being broken, because from where he sits it is.
#
# AND: the model is not touched. The seam in the pool coping is a real edge
# between two real faces; it has to stay in SketchUp and only leave the paper.
ENV['REAL_ROOMS'] = '1'
require 'json'
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

PSD = InteriorPro::PlanSheetDialog
PG  = InteriorPro::PlanGeometry
PD  = InteriorPro::PlanDoc

# The window is full of Hebrew, so it has to be read as UTF-8 or every match
# below dies on "invalid byte sequence in US-ASCII".
SRC = File.read('./plan_sheet_dialog.rb', encoding: 'UTF-8')

def line(n)
  [[n * 100.0, 0.0], [n * 100.0, 50.0]]
end

FIVE = (1..5).map { |n| line(n) }

# ---------------------------------------------------------------------------
# 1. the ordering the whole feature stands on
# ---------------------------------------------------------------------------
doc = PD::Document.new('t')
cv  = doc.canvas('MODEL')
PG.build!(nil, cv, lines: FIVE)
lay = cv.layers.find { |l| l.name == PG::LAYER }

ok('the free lines land on their own layer', !lay.nil?, cv.layers.map(&:name))
ok('one shape per line, no merging', lay.shapes.length == 5, lay.shapes.length)

order_held = (0...5).all? do |i|
  pts = lay.shapes[i][:points] || lay.shapes[i]['points']
  pts && pts[0][0].to_f == FIVE[i][0][0]
end
ok('shape number i on the sheet IS line number i in the list  <<< THE RULE',
   order_held, lay.shapes.map { |s| (s[:points] || s['points'])[0][0] })

# A second build must not reorder or double up, or an index taken from the
# screen would point at the wrong line the moment anything is redrawn.
PG.build!(nil, cv, lines: FIVE)
lay2 = cv.layers.find { |l| l.name == PG::LAYER }
ok('rebuilding does not double the layer up', lay2.shapes.length == 5, lay2.shapes.length)
ok('and does not reorder it',
   (lay2.shapes[3][:points] || lay2.shapes[3]['points'])[0][0].to_f == FIVE[3][0][0])

# ---------------------------------------------------------------------------
# 2. the window's two new callbacks really exist and really work
# ---------------------------------------------------------------------------
PSD.show
DLG = PSD.instance_variable_get(:@dialog)

ok('the window can be told to rub out one line',
   DLG.callbacks.key?('drop_site_line'), DLG.callbacks.keys)
ok('and to put them all back',
   DLG.callbacks.key?('restore_site_lines'), DLG.callbacks.keys)

def drop!(i)
  DLG.callbacks['drop_site_line'].call(nil, JSON.generate('i' => i))
end

def restore!
  DLG.callbacks['restore_site_lines'].call(nil)
end

def firsts
  PSD.site_lines.map { |l| l[0][0].to_f }
end

PSD.site_lines   = FIVE
PSD.site_dropped = []
ok('nothing is waiting to come back to start with', PSD.site_dropped.empty?)

drop!(2)
ok('rubbing out leaves the other four', PSD.site_lines.length == 4, PSD.site_lines.length)
ok('it takes the one that was asked for, not a neighbour',
   firsts == [100.0, 200.0, 400.0, 500.0], firsts)
ok('and the survivors keep their order', firsts == firsts.sort, firsts)
ok('the one rubbed out is kept, ready to come back',
   PSD.site_dropped.length == 1 && PSD.site_dropped[0][0][0].to_f == 300.0,
   PSD.site_dropped)

# The index the window sends is a place in the list, so after one deletion the
# NEXT click sends a number in the shorter list. Deleting 2 then 2 again must
# take the 3rd and then the 4th original line - never the same one twice.
drop!(2)
ok('a second rub-out reads the shortened list, not the old one',
   firsts == [100.0, 200.0, 500.0], firsts)
ok('both are held', PSD.site_dropped.length == 2, PSD.site_dropped.length)

restore!
ok('putting them back restores every one', PSD.site_lines.length == 5, PSD.site_lines.length)
ok('and the waiting list empties', PSD.site_dropped.empty?, PSD.site_dropped)
ok('no line came back twice',
   PSD.site_lines.map { |l| l[0][0].to_f }.sort == [100.0, 200.0, 300.0, 400.0, 500.0],
   PSD.site_lines.map { |l| l[0][0].to_f }.sort)

# ---------------------------------------------------------------------------
# 3. the awkward numbers - the sheet is rebuilt under the mouse
# ---------------------------------------------------------------------------
PSD.site_lines   = FIVE
PSD.site_dropped = []

[-1, 5, 99].each do |bad|
  before = PSD.site_lines.length
  raised = begin
    drop!(bad)
    nil
  rescue StandardError => e
    e
  end
  ok("index #{bad} does not raise", raised.nil?, raised)
  ok("index #{bad} changes nothing", PSD.site_lines.length == before, PSD.site_lines.length)
end
ok('and nothing was quietly added to the waiting list', PSD.site_dropped.empty?,
   PSD.site_dropped)

restore!
ok('putting back with nothing to put back is harmless',
   PSD.site_lines.length == 5, PSD.site_lines.length)

PSD.site_lines   = []
PSD.site_dropped = []
ok('rubbing out on an empty sheet does not raise',
   begin
     drop!(0)
     true
   rescue StandardError => e
     e
   end)

# ---------------------------------------------------------------------------
# 4. THE MODEL IS NOT TOUCHED
# ---------------------------------------------------------------------------
# The user asked for this in the same sentence as the feature: the seam is a
# real edge and it stays. Deleting on paper must never reach the model.
model = Sketchup.active_model
kept  = model.entities.add_line(Geom::Point3d.new(0, 0, 0),
                                Geom::Point3d.new(100, 0, 0))
before_n = model.entities.length

PSD.site_lines   = FIVE
PSD.site_dropped = []
drop!(1)

ok('the edge in the model is still there after a rub-out',
   kept.respond_to?(:valid?) ? kept.valid? : true)
ok('and nothing was erased from the model',
   model.entities.length == before_n, [model.entities.length, before_n])

# Belt and braces: the callback body itself must not reach for the eraser.
body = SRC[/add_action_callback\('drop_site_line'\).*?\n        end\n/m].to_s
ok('the rub-out callback exists in the source', !body.empty?)
ok('it never erases anything', !body.match?(/erase!|\.delete\b|remove_/), body[0, 200])
ok('it only edits the list of lines', body.include?('self.site_lines ='))

# ---------------------------------------------------------------------------
# 5. a fresh read of the model starts the decision over
# ---------------------------------------------------------------------------
# Otherwise a line that came back with "add what is selected" would ALSO still
# be sitting in the waiting list, and "put them back" would draw it twice.
PSD.site_lines   = FIVE
PSD.site_dropped = []
drop!(0)
ok('there is something waiting before the list is cleared',
   PSD.site_dropped.length == 1)
DLG.callbacks['clear_selection'].call(nil)
ok('clearing the free geometry also clears what was waiting',
   PSD.site_dropped.empty?, PSD.site_dropped)
ok('the source resets it on a fresh read too',
   SRC[/add_action_callback\('add_selection'\).*?\n        end\n/m].to_s
      .include?('self.site_dropped = []'))

# ---------------------------------------------------------------------------
# 6. the window: the rubber is a mode like the others
# ---------------------------------------------------------------------------
ok('there is a rubber button', SRC.include?('id="terase"'))
ok('it is wired to its own mode', SRC.include?("$('terase').onclick"))
ok('and it joins the other tool buttons so only one lights up',
   SRC.include?("['thand','tdim','tnote','terase']"))
ok('the mode is spelled the same everywhere', SRC.include?("setMode('erase')"))
ok('picking any mode drops whatever the rubber was over',
   SRC.match?(/MODE=m; PEND=null; HOVER=null; ERA=null;/))

ok('clicking sends the number of the line, not a position',
   SRC.include?('sketchup.drop_site_line(JSON.stringify({i:hi}))'))
ok('there is a way to put them back', SRC.include?("$('undrop').onclick"))
ok('and a button for it', SRC.include?('id="undrop"'))
ok('the window is told how many are left and how many are waiting',
   SRC.include?('function siteDropped('))
ok('the put-back button is dead when there is nothing to put back',
   SRC.include?("$('undrop').disabled = !dropped"))

# ---------------------------------------------------------------------------
# 7. the rubber only touches the free geometry
# ---------------------------------------------------------------------------
# Walls, doors and windows are drawn from their attributes and are switched off
# by their own layer. Letting the rubber at them would delete from the MODEL,
# which is the one thing this feature must not do.
hit = SRC[/function siteLayer\(\).*?\n          \}/m].to_s
ok('the layer finder exists', !hit.empty?)
ok("it asks for SITE by name", hit.include?("l.name==='SITE'"))
%w[WALLS DOORS WINDOWS ROOMS DIMENSIONS].each do |other|
  ok("it does not reach the #{other} layer", !hit.include?(other))
end
ok('a switched-off SITE layer cannot be rubbed out',
   hit.include?("(STATE.hidden||[]).indexOf('SITE')>=0"))

# ---------------------------------------------------------------------------
# 8. the red line under the mouse does NOT redraw the sheet
# ---------------------------------------------------------------------------
# A real back yard is thousands of lines. render() rebuilds every one of them.
# Calling it on every mouse move would make the rubber feel stuck, so the
# highlight is one extra element pushed onto the drawing instead.
paint = SRC[/function paintErase\(\).*?\n          \}/m].to_s
ok('the highlight is painted by its own routine', !paint.empty?)
ok('and it never calls render()', !paint.include?('render()'), paint[0, 160])
ok('it adds exactly one element', paint.scan(/createElementNS/).length == 1)
ok('and takes the old one away first, so they cannot pile up',
   paint.include?("querySelector('#erahi')"))

move = SRC[/svg\.onmousemove=function\(e\)\{.*?\n            \};/m].to_s
ok('moving the mouse only repaints when the line under it changes',
   move.include?('if(h3!==ERA){ ERA=h3; paintErase(); }'), move[0, 240])

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
