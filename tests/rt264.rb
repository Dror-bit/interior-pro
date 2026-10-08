# encoding: utf-8
# rt264 - the window and the paper put the plan in the SAME place (2026-10-07).
#
# The user threw the plan sheet away on a landscape job (6 Bronco Ln - renders
# only, not one wall of ours in the model). Later he wanted the yard on paper:
# brought the plan sheet back, pressed "add what is selected", the window said
# 21,276 lines were on the sheet - and the sheet was white.
#
# debug_sheet_site.rb measured it on his model instead of guessing:
#
#   state origin  = 399.5, 671.2          <- remembered from an older drawing
#   canvas bounds = [-1296.7, -3097.8, 2287.5, -361.8]
#   view origin   = 495.4, -1729.8        <- layout_pages! went back to the middle
#   SITE LINES INSIDE THE WINDOW = 26780 of 42552
#
# So Ruby was right and the PDF would have had the yard on it. But the window
# does not draw from the view - it draws from STATE.origin_x / origin_y, and
# nobody told it the paper had moved. Two answers to "where is the plan" is
# the one thing this file set exists to prevent.
#
# THE RULE THIS SUITE PINS: whenever the whole sheet is sent to the window, the
# place in the state it is sent IS the place the plan view was laid out at.
#
# Through the real road - the window's own callbacks - not a helper on its own.
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
SRC = File.read('./plan_sheet_dialog.rb', encoding: 'UTF-8')

# His yard, in small: every line sits around x 500, y -1700 (model inches).
YARD = (0...40).map do |i|
  [[300.0 + i * 10.0, -1900.0], [300.0 + i * 10.0, -1500.0]]
end
# His numbers: the place the state remembered, 200 feet north of the yard.
FAR = [399.5108346470929, 671.2323724180566].freeze

def fresh!(origin)
  Sketchup.active_model.delete_attribute('InteriorPro', 'sheet_state')
  st = PSD.default_state
  if origin
    st['origin_x'] = origin[0]
    st['origin_y'] = origin[1]
  end
  PSD.save_state(st)
  PSD.site_lines = YARD
  PSD.site_dropped = []
  PSD.show
  PSD.instance_variable_get(:@dialog)
end

# What the window was last handed, read back exactly as the window reads it.
def last_sheet(dlg)
  s = dlg.scripts.reverse.find { |x| x.start_with?('loadSheet(') }
  s && JSON.parse(s[/\AloadSheet\((.*)\)\z/m, 1])
end

def plan_view(sheet)
  pg = sheet['doc']['pages'].find { |p| p['kind'] == 'plan' }
  pg && pg['views'].first
end

# The window's own arithmetic (sheetSVG / toPaper): how many of the yard's
# lines land inside the view frame when it draws from the STATE's origin.
def seen_by_window(sheet)
  v  = plan_view(sheet)
  sf = InteriorPro::PlanDoc.scale_factor(sheet['state']['scale'])
  ox = sheet['state']['origin_x'].to_f
  oy = sheet['state']['origin_y'].to_f
  hw = v['w'].to_f / 2.0 / sf
  hh = v['h'].to_f / 2.0 / sf
  YARD.count do |a, b|
    [a[0], b[0]].max >= ox - hw && [a[0], b[0]].min <= ox + hw &&
      [a[1], b[1]].max >= oy - hh && [a[1], b[1]].min <= oy + hh
  end
end

# ---------------------------------------------------------------------------
# 0. the window really does draw from the state - the reason any of this matters
# ---------------------------------------------------------------------------
ok('the window draws the plan from STATE.origin (if this changes, re-read this suite)',
   SRC.include?('ox=(dOx===null) ? STATE.origin_x : dOx') && SRC.include?('(mx-ox)*sf') && SRC.include?('(my-oy)*sf'))   # (since 2026-10-07 an editor drawing's sheet has an origin of its own, dOx)

# ---------------------------------------------------------------------------
# 1. HIS CASE: a remembered place that shows nothing, window opened
# ---------------------------------------------------------------------------
dlg = fresh!(FAR)
dlg.callbacks['sheet_ready'].call(nil)
sh = last_sheet(dlg)
v  = plan_view(sh)

ok('the sheet was sent', !sh.nil?)
ok('the paper went back to the middle of the yard',
   (v['origin_x'].to_f - 495.0).abs < 1.0 && (v['origin_y'].to_f + 1700.0).abs < 1.0,
   [v['origin_x'], v['origin_y']])
ok('AND THE WINDOW IS TOLD THE SAME PLACE  <<< THE RULE',
   (sh['state']['origin_x'].to_f - v['origin_x'].to_f).abs < 0.001 &&
   (sh['state']['origin_y'].to_f - v['origin_y'].to_f).abs < 0.001,
   [sh['state']['origin_x'], sh['state']['origin_y'], v['origin_x'], v['origin_y']])
ok('so the window shows the yard, not a white sheet',
   seen_by_window(sh) == YARD.length, seen_by_window(sh))

# ---------------------------------------------------------------------------
# 2. HIS ROAD: plan sheet thrown away, brought back with the button
# ---------------------------------------------------------------------------
dlg = fresh!(FAR)
dlg.callbacks['delete_page'].call(nil, JSON.generate('kind' => 'plan'))
st = PSD.load_state
# only the plan sheet exists in the stub model, so the x refuses - set the flag
# the way the x does, which is what his model had
st['drop_plan'] = true
st['images'] = ['C:/x/render 1.jpg']
PSD.save_state(st)
PSD.instance_variable_set(:@doc, nil)
dlg.callbacks['sheet_ready'].call(nil)
gone = last_sheet(dlg)
ok('with the plan sheet thrown away there is no plan page', plan_view(gone).nil?,
   gone['doc']['pages'].map { |p| p['kind'] })
ok('and the remembered place is left exactly as it was',
   gone['state']['origin_x'].to_f == FAR[0] && gone['state']['origin_y'].to_f == FAR[1],
   [gone['state']['origin_x'], gone['state']['origin_y']])

dlg.callbacks['restore_plan'].call(nil)
back = last_sheet(dlg)
bv   = plan_view(back)
ok('the button brings the plan sheet back', !bv.nil?)
ok('and the window is told where the paper put the yard',
   (back['state']['origin_x'].to_f - bv['origin_x'].to_f).abs < 0.001 &&
   (back['state']['origin_y'].to_f - bv['origin_y'].to_f).abs < 0.001,
   [back['state']['origin_x'], back['state']['origin_y'], bv['origin_x'], bv['origin_y']])
ok('so the yard is on the sheet he is looking at',
   seen_by_window(back) == YARD.length, seen_by_window(back))

# ---------------------------------------------------------------------------
# 3. what must NOT change
# ---------------------------------------------------------------------------
# A place he dragged the plan to himself, with the drawing still on the paper.
MINE = [700.0, -1600.0].freeze
dlg = fresh!(MINE)
dlg.callbacks['sheet_ready'].call(nil)
kept = last_sheet(dlg)
ok('a place that shows the drawing is HIS - it is not touched',
   kept['state']['origin_x'].to_f == MINE[0] && kept['state']['origin_y'].to_f == MINE[1],
   [kept['state']['origin_x'], kept['state']['origin_y']])
ok('and the paper agrees with it',
   plan_view(kept)['origin_x'].to_f == MINE[0] && plan_view(kept)['origin_y'].to_f == MINE[1])

# First time on a model: no place was ever chosen. The window sees "nothing
# chosen" and fits the drawing to the sheet itself - handing it a place here
# would switch that off.
dlg = fresh!(nil)
dlg.callbacks['sheet_ready'].call(nil)
first = last_sheet(dlg)
ok('first time: no place is invented for the window',
   first['state']['origin_x'].nil? && first['state']['origin_y'].nil?,
   [first['state']['origin_x'], first['state']['origin_y']])

# Nothing is written onto the model behind his back - the window saves the
# place itself the next time he touches anything.
dlg = fresh!(FAR)
dlg.callbacks['sheet_ready'].call(nil)
ok('the saved place on the model is not rewritten by looking at the sheet',
   PSD.load_state['origin_x'].to_f == FAR[0] && PSD.load_state['origin_y'].to_f == FAR[1],
   [PSD.load_state['origin_x'], PSD.load_state['origin_y']])

# ---------------------------------------------------------------------------
# 4. the switch
# ---------------------------------------------------------------------------
ok('there is a switch', PSD.const_defined?(:USE_ORIGIN_SYNC, false) && PSD::USE_ORIGIN_SYNC == true)
if PSD.const_defined?(:USE_ORIGIN_SYNC, false)
  PSD.send(:remove_const, :USE_ORIGIN_SYNC)
  PSD.const_set(:USE_ORIGIN_SYNC, false)
  dlg = fresh!(FAR)
  dlg.callbacks['sheet_ready'].call(nil)
  off = last_sheet(dlg)
  ok('switched off: the window is handed the remembered place, as before',
     off['state']['origin_x'].to_f == FAR[0] && off['state']['origin_y'].to_f == FAR[1],
     [off['state']['origin_x'], off['state']['origin_y']])
  PSD.send(:remove_const, :USE_ORIGIN_SYNC)
  PSD.const_set(:USE_ORIGIN_SYNC, true)
end

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
