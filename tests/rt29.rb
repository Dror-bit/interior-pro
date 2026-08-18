# encoding: utf-8
# rt29 — curved walls in the 2D EDITOR (2026-08-12).
# The canvas must show the same arc the model builds, a pending wall may be
# drawn with a bow, and the panel bends a model wall through the ONE entry
# point (set_wall_sag!). Plus the sign bug: flipping a wall's faces swaps
# start/end, so the stored bow must flip sign with it.
require './sketchup_stub'

module InteriorPro
  module WallTool
    class StubInstance
      def wall_data(_g); nil; end
    end
    def self.new; StubInstance.new; end
    # The real curve helpers, so walls_payload can be exercised for real.
    def self.wall_sag(w)
      v = w.get_attribute('InteriorPro', 'arc_sag')
      v.nil? ? 0.0 : v.to_f
    end
    def self.curved_footprint_xy(sx, sy, ex, ey, th, _ha, sag, _tol = 0.125, _ops = nil)
      # a stand-in ring: 3 points a side, enough to prove the wiring
      [[sx, sy + th / 2.0], [(sx + ex) / 2.0, sy + sag + th / 2.0], [ex, ey + th / 2.0],
       [ex, ey - th / 2.0], [(sx + ex) / 2.0, sy + sag - th / 2.0], [sx, sy - th / 2.0]]
    end
    def self.read_door_openings(_w); []; end
  end
end

require './plan_editor'

$fails = 0
def ok(n, c, x = nil); puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}")); $fails += 1 unless c; end
PE = InteriorPro::PlanEditor

Sketchup.reset_model!
m = Sketchup.active_model

def mk_wall(m, id, sag)
  w = m.entities.add_group
  w.set_attribute('InteriorPro', 'type', 'wall')
  w.set_attribute('InteriorPro', 'id', id)
  w.set_attribute('InteriorPro', 'start_x', 0.0); w.set_attribute('InteriorPro', 'start_y', 0.0)
  w.set_attribute('InteriorPro', 'end_x', 240.0); w.set_attribute('InteriorPro', 'end_y', 0.0)
  w.set_attribute('InteriorPro', 'thickness', 6.0)
  w.set_attribute('InteriorPro', 'height', 96.0)
  w.set_attribute('InteriorPro', 'anchor', 'bottom-left')
  w.set_attribute('InteriorPro', 'arc_sag', sag) unless sag.zero?
  w
end

straight = mk_wall(m, 'pw1', 0.0)
curved   = mk_wall(m, 'pw2', 18.0)

rows = PE.send(:walls_payload)
ok('both walls reach the canvas', rows.length == 2, rows.length)
r_st = rows.find { |r| r['id'] == 'pw1' }
r_cu = rows.find { |r| r['id'] == 'pw2' }

# ---- the payload carries the curve ----
ok('a straight wall says sag 0', r_st['sag'] == 0.0, r_st['sag'])
ok('and ships no outline (the straight band draws it)', r_st['fp'].nil?)
ok('a curved wall says its bow', r_cu['sag'] == 18.0, r_cu['sag'])
ok('and ships a real outline', r_cu['fp'].is_a?(Array) && r_cu['fp'].length >= 8, r_cu['fp']&.length)
ok('the outline is flat numbers, ready for the canvas',
   r_cu['fp'].all? { |v| v.is_a?(Numeric) })
ok('the outline actually bows', r_cu['fp'].each_slice(2).any? { |_x, y| y > 10.0 })

# ---- the source wiring ----
src = File.read('plan_editor.rb', encoding: 'UTF-8')
ok('a pending wall may carry a bow into apply_walls',
   src.include?("r['sag'].to_f.abs >= 0.0625"))
ok('and it lands through the ONE entry point',
   src.include?("InteriorPro::WallTool.set_wall_sag!(g, r['sag'].to_f, wrap_operation: false)"))
ok('the panel has a set_wall_sag callback', src.include?("add_action_callback('set_wall_sag')"))
ok('which also goes through the one entry point',
   src.include?("InteriorPro::WallTool.set_wall_sag!(wall, r['sag'].to_f)"))
ok('and refreshes the canvas afterwards',
   src =~ /add_action_callback\('set_wall_sag'\)[\s\S]{0,600}?push_walls\(dlg\)/)

# ---- the JS side ----
js = src
ok('the canvas can sample one side of an arc', js.include?('function arcSidePts('))
ok('a curved wall draws its real outline, not the straight band',
   js.include?('function curvedOutline(w)'))
ok('drawWallBand takes the curved path first',
   js =~ /function drawWallBand\(w[\s\S]{0,400}?curvedOutline\(w\)/)
ok('a pending wall with a bow is drawn as an arc too',
   js.include?('arcSidePts(w.sx, w.sy, w.ex, w.ey, w.sag'))
ok('the panel has a bow field', js.include?("id=\"selSag\""))
ok('with an apply that reads a SIGNED number', js.include?("parseFloat(document.getElementById('selSag').value)"))
ok('a pending selection stores the bow locally', js.include?('pw4.sag = v'))
ok('a model selection sends it to Ruby',
   js.include?("sketchup.set_wall_sag(JSON.stringify({ id: o.w.id, sag: v }))"))
ok('the field shows the current bow when a wall is picked',
   js.include?("(o.type === 'pending' ? (pending[o.i] || {}).sag : o.w.sag) || 0"))

# ---- flipping a wall flips its bow ----
wt = File.read('wall_tool.rb', encoding: 'UTF-8')
ok('flipping a wall negates its stored bow',
   wt.include?("wall.set_attribute('InteriorPro', 'arc_sag', -old_sag.to_f) unless old_sag.nil?"))
ok('but never invents one on a straight wall', wt.include?("unless old_sag.nil?"))

# ---- the panel got tidier (2026-08-12) ----

ok('the wall controls are folded away by default',
   src.include?("toggleFold('wlen')") && src.include?("toggleFold('wcorn')") &&
   src.include?("toggleFold('wth')"))
ok('and the new folds are registered',
   src.include?('wlen:false, wmove:false, wcorn:false, wth:false'))
ok('the bow lives inside the עובי·קשת fold', src =~ /wthBody[\s\S]{0,400}?id="selSag"/)
ok('a narrow window moves the panel to the bottom',
   src.include?('@media (max-width: 620px)') && src.include?('flex-direction:column'))

# ---- the main buttons are icons, not words ----
ok('the mode buttons are a grid of icons', src.include?('class="modebar"'))
%w[modeSel modeWall modeDoor modeWin modeLine].each do |id|
  ok("#{id} is still there and still switches mode", src.include?("id=\"#{id}\""))
end
ok('each mode button carries an svg icon',
   src.scan(/modebtn[^>]*>\s*<svg/).length >= 5, src.scan(/modebtn[^>]*>\s*<svg/).length)
ok('the words shrank to tiny labels under the icons',
   src.include?('<span>קיר</span>') && src.include?('<span>בחר</span>'))
ok('setMode is still wired to every button', src.scan(/onclick="setMode\(/).length >= 5)

# ---- draw a wall by aiming + typing an angle (2026-08-12) ----
ok('the VCB understands length<angle', src.include?('function parseTypedAngle('))
ok('and separates the length part from it', src.include?('function parseTypedLenPart('))
ok('currentEnd aims to an exact angle when one is typed',
   src.include?('var av = parseTypedAngle(typed)'))
ok('the angle separators are < / and @',
   src.include?('/[<\\/@]\\s*(-?') )
ok('typing lets those separators through in wall mode',
   src.include?("/^[0-9.'\"<\\/@ -]$/.test(ev.key)"))
# Was pinned to the raw "aDeg + '\u00b0'" this used to be built from. The label
# still shows the angle, but it goes through fmtAngle now (which rounds to a
# tenth of a degree and adds the \u00b0 itself), so the old spelling stopped
# matching and this went red while the feature was fine - found red on
# 2026-08-17, before that session touched anything. Pin the BEHAVIOUR: the
# live label carries an angle mark and a formatted angle.
ok('the live label shows the angle while drawing',
   src.include?("'  \u2220' + fmtAngle(aDeg)") &&
   src.include?("return (r % 1 === 0 ? r : r.toFixed(1)) + '\u00b0';"))

# ---- draw a curved wall directly, with an icon toggle ----
ok('the wall panel has a straight/arc shape toggle', src.include?('setWallShape('))
ok('with an icon for each', src.include?('id="wShapeArc"') && src.include?('id="wShapeStraight"'))
ok('arc mode holds the wall for a bow stage after the second click',
   src.include?('arcBow = { w: w, sx: w.sx'))
ok('a third click locks the bow in', src.include?('function commitArcBow('))
ok('the bow follows the mouse in arc mode',
   src.include?('arcBow.w.sag = bowOf(arcBow.sx'))
ok('a typed number sets the exact bow', src.include?('arcBow.w.sag = Math.abs(bv)'))
ok('the bowing wall is previewed on the canvas',
   src.include?("drawWallBand(arcBow.w, '#2f6bd8'"))
ok('Esc drops a half-drawn arc wall', src.include?('arcBow = null;'))
ok('bowOf uses the same left-positive convention as the model',
   src.include?('function bowOf(sxp, syp, exp, eyp, px, py)'))

# ---- clicking the ARC selects it, not the old chord line ----
ok('there is a point-in-polygon test', src.include?('function pointInPoly('))
ok('hitWall tests the curved outline for a curved wall',
   src.include?('if (pointInPoly(p.x, p.y, co)) {'))
ok('a straight wall still uses the band', src.include?('var b = bandQuad(w); if (!b) return;'))
ok('the arc preview does not double up with the straight rubber band',
   src.include?("mode === 'wall' && drawing && startPt && !arcBow"))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
