# encoding: utf-8
# Landscape Pro - GARDEN WALL (חומה), step 1: the body.
# (2026-08-17)
#
# WHAT THIS IS
#
# A free-standing masonry site wall: a solid of a given thickness and height,
# drawn along a line with two clicks, faced in a stone/stucco finish. It is
# NOT a building wall and must never be mistaken for one.
#
# WHY IT IS NOT A SUBCLASS OF WallTool
#
# WallTool does far more than draw a box, and every extra thing it does is
# wrong out here:
#
#   * it stores under the 'InteriorPro' dictionary as type 'wall'. Everything
#     in the plugin that hunts for walls - RoomManager closing rooms,
#     FloorManager and FoundationManager building slabs under them,
#     MoldingManager running baseboard, RoofManager taking eaves off them,
#     plan_generator drawing them in the 2D plan, and the wall
#     Edit/Move/Stretch/Split/Merge/Delete tools - finds walls by exactly that
#     dictionary and that string. A garden wall tagged 'wall' would be dragged
#     into all of it.
#   * create_wall calls join_corners, which MITERS the new wall into any
#     building wall it touches.
#   * it pins the base to LevelManager.active_level, so the wall would follow
#     whichever storey happens to be active instead of sitting on the ground.
#   * it splits its faces into exterior_material / interior_material. A garden
#     wall has one finish on both sides.
#   * it is a legal host for doors and windows.
#
# So this file follows the FENCE precedent instead (landscape/fence_ref_tool.rb):
# its own dictionary key, its own group name, its own tag, and it calls into
# nothing. The ONE thing it borrows is WallTool.apply_axis_magnet, the same
# red/green axis snap the fence borrows, because the user expects a line he
# draws to straighten the same way everywhere.
#
# WHAT IS HERE AND WHAT IS NOT (step 1 of 4, his order)
#
#   1. body: thickness, height, finish   <-- THIS FILE, today
#   2. cap on top: size + its own material
#   3. bullnose at the end: yes / no
#   4. a line along the top of the BACK face, UNDER the cap, that follows the
#      wall when it curves or steps up and down, to pull an elevation off
#
# Do not start 2 before he has looked at 1 in SketchUp.

module InteriorPro
  module Landscape
    class GardenWallTool

      DICT = 'LandscapePro' unless const_defined?(:DICT, false)
      TYPE = 'garden_wall'  unless const_defined?(:TYPE, false)

      GROUP_NAME = 'LandscapePro_GardenWall' unless const_defined?(:GROUP_NAME, false)
      CAP_NAME   = 'LandscapePro_GardenWallCap' unless const_defined?(:CAP_NAME, false)
      CAP_UNIT_NAME = 'LandscapePro_CapUnit'    unless const_defined?(:CAP_UNIT_NAME, false)
      TAG        = 'LP/Walls'                unless const_defined?(:TAG, false)

      GHOST = [120, 120, 120].freeze unless const_defined?(:GHOST, false)
      DOT   = [40, 90, 200].freeze   unless const_defined?(:DOT, false)

      MIN_LEN = 1.0 unless const_defined?(:MIN_LEN, false)

      # His list, not the house walls' list (he was explicit, 2026-08-17:
      # "לא חייב את אותה רשימה של הקירות... זאת רשימה בפני עצמה"). He is
      # sending the full one; these three are what he named. Adding to this
      # array is the whole job of adding a finish.
      MATERIALS = ['Stucco', 'Stack Stone', 'Block Wall'].freeze unless const_defined?(:MATERIALS, false)

      # A finish with no texture file yet still has to LOOK like something -
      # an unpainted material comes out flat white and reads as a bug. These
      # are stand-ins until the real .jpg lands in textures/.
      FALLBACK_COLOR = {
        'Stucco'      => '#d8d2c4',
        'Stack Stone' => '#8d8477',
        'Block Wall'  => '#b9b6ae'
      }.freeze unless const_defined?(:FALLBACK_COLOR, false)

      DEFAULT_THICKNESS = 8.0  unless const_defined?(:DEFAULT_THICKNESS, false)
      DEFAULT_HEIGHT    = 36.0 unless const_defined?(:DEFAULT_HEIGHT, false)

      # THE CAP (step 2, 2026-08-17). He was explicit about how to ask for it:
      # not an overhang, a WIDTH - "כמה הוא גדול מצד לצד, האם זה פיט אחד או 6"
      # או 4"". So cap_width is the finished width of the coping, side to
      # side, and the overhang each side falls out of it: (cap - wall) / 2.
      # A cap NARROWER than the wall is allowed on purpose - a recessed
      # coping is a real detail, not a mistake to guard against.
      #
      # cap_height 0 (or less) means NO cap. That is the off switch; there is
      # no separate checkbox, because a checkbox plus a size is two controls
      # for one decision (his standing UI rule: no duplicate ways to say the
      # same thing).
      DEFAULT_CAP_WIDTH  = 12.0 unless const_defined?(:DEFAULT_CAP_WIDTH, false)
      DEFAULT_CAP_HEIGHT = 2.0  unless const_defined?(:DEFAULT_CAP_HEIGHT, false)

      # A CAP IS EITHER ONE STRIP OR MANY STONES (2026-08-17, his words: "הקאפ
      # יכול להיות יחידה אחת שרצה אבל הוא גם יכול להיות מפוצל כמו בריקס או
      # פייברס שיושבים על החומה וכל אחת מהם נפרד מהשני - זה יהיה לנו גם
      # בקופינג של בריכות"). So the same code has to serve pool coping, which
      # is what the split mode is really for.
      #
      #   CONTINUOUS - one slab the whole length. One face, one pushpull.
      #   SPLIT      - a stone every (unit + joint), each in its OWN group so
      #                he can grab one, and so their faces cannot merge into
      #                one another and lose the joint.
      #
      # The last stone is CUT SHORT (he chose this over dividing evenly: "תעשה
      # את האחרונה נחתכת" - it is what happens on site).
      CAP_CONTINUOUS = 'Continuous' unless const_defined?(:CAP_CONTINUOUS, false)
      CAP_SPLIT      = 'Split'      unless const_defined?(:CAP_SPLIT, false)
      CAP_MODES      = [CAP_CONTINUOUS, CAP_SPLIT].freeze unless const_defined?(:CAP_MODES, false)

      DEFAULT_CAP_UNIT  = 24.0 unless const_defined?(:DEFAULT_CAP_UNIT, false)
      DEFAULT_CAP_JOINT = 0.25 unless const_defined?(:DEFAULT_CAP_JOINT, false)

      # A stone thinner than this at the end is not a stone, it is a chip -
      # drop it rather than leave a crumb standing on the wall.
      MIN_CAP_PIECE = 0.125 unless const_defined?(:MIN_CAP_PIECE, false)

      # THE BULLNOSE (step 3, 2026-08-17). He asked for one control that says
      # off / one side / two sides ("אפשרי לעשות אופציה של סימון וי עם בול נוז
      # או בלי, ובצד אחד או שתי צדדים") - so it is ONE dropdown, not a
      # checkbox plus a side picker. Two controls for one decision is exactly
      # what his standing UI rule forbids.
      #
      # ONE SIDE means the RIGHT-hand side of the way he draws it: start ->
      # end, right is the side your right hand falls on. To put the nose on
      # the other face he draws the wall the other way round. That is the same
      # answer the plugin already gives for wall faces, and it beats adding a
      # left/right control he then has to think about.
      #
      # The radius is NOT a field: a bullnose IS a half-round, so it is always
      # half the cap thickness. A "radius" smaller than that is an eased edge,
      # a different detail, and it can have its own option if he asks.
      BULLNOSE_NONE = 'None'      unless const_defined?(:BULLNOSE_NONE, false)
      BULLNOSE_ONE  = 'One side'  unless const_defined?(:BULLNOSE_ONE, false)
      BULLNOSE_BOTH = 'Both sides' unless const_defined?(:BULLNOSE_BOTH, false)
      BULLNOSE_MODES = [BULLNOSE_NONE, BULLNOSE_ONE, BULLNOSE_BOTH].freeze unless const_defined?(:BULLNOSE_MODES, false)

      # How many straight pieces stand in for each half-round. 8 is smooth at
      # the sizes a coping actually is, and cheap enough to put on every stone
      # of a hundred-foot wall.
      BULLNOSE_SEGMENTS = 12 unless const_defined?(:BULLNOSE_SEGMENTS, false)

      # WHICH SIDE THE CAP HANGS OVER (2026-08-17, after he looked at it: "שאני
      # בוחר אוברהנג צריכה להיות האפשרות לבחור רק צד אחד יבלוט החוצה, כי לא
      # תמיד ובדרך כלל לא שניהם יבלטו החוצה, הרבה פעמים יושב פלאש עם הקו של
      # החומה").
      #
      #   BOTH - the coping is centred, so it hangs over equally each side.
      #   ONE  - it is FLUSH with the left face of the wall and all of the
      #          overhang lands on the right.
      #
      # Right is the same right as the bullnose: the right hand of start ->
      # end. That is on purpose - the face that shows is the face that gets
      # both the nose and the overhang, and drawing the wall the other way
      # flips the two of them together.
      OVERHANG_BOTH = 'Both sides' unless const_defined?(:OVERHANG_BOTH, false)
      OVERHANG_ONE  = 'One side'   unless const_defined?(:OVERHANG_ONE, false)
      OVERHANG_MODES = [OVERHANG_BOTH, OVERHANG_ONE].freeze unless const_defined?(:OVERHANG_MODES, false)

      # SketchUp draws a line on every facet of the half-round, and on a
      # coping that reads as a ribbed edge instead of a smooth one - he saw it
      # in the first screenshot. Every edge whose two faces are nearly in line
      # gets softened and smoothed; a real corner is 90 degrees and is left
      # alone. At 12 segments a half-round facet turns 15 degrees, so 30 is
      # comfortably above the arc and far below any corner.
      SOFTEN_DEGREES = 30.0 unless const_defined?(:SOFTEN_DEGREES, false)

      attr_accessor :thickness, :height, :material, :ground_start, :ground_end
      attr_accessor :cap_width, :cap_height, :cap_material
      attr_accessor :cap_mode, :cap_unit, :cap_joint
      attr_accessor :bullnose, :overhang

      def initialize(thickness = DEFAULT_THICKNESS, height = DEFAULT_HEIGHT,
                     material = MATERIALS.first,
                     cap_width = DEFAULT_CAP_WIDTH, cap_height = DEFAULT_CAP_HEIGHT,
                     cap_material = MATERIALS.first,
                     cap_mode = CAP_CONTINUOUS,
                     cap_unit = DEFAULT_CAP_UNIT, cap_joint = DEFAULT_CAP_JOINT,
                     bullnose = BULLNOSE_NONE, overhang = OVERHANG_BOTH)
        @thickness    = thickness.to_f
        @height       = height.to_f
        @material     = material.to_s
        @cap_width    = cap_width.to_f
        @cap_height   = cap_height.to_f
        @cap_material = cap_material.to_s
        @cap_mode     = CAP_MODES.include?(cap_mode.to_s) ? cap_mode.to_s : CAP_CONTINUOUS
        @cap_unit     = cap_unit.to_f
        @cap_joint    = cap_joint.to_f
        @bullnose     = BULLNOSE_MODES.include?(bullnose.to_s) ? bullnose.to_s : BULLNOSE_NONE
        @overhang     = OVERHANG_MODES.include?(overhang.to_s) ? overhang.to_s : OVERHANG_BOTH
        @ground_start = 0.0
        @ground_end   = 0.0
        reset
      end

      # Split only counts as split if there is a real stone length to split
      # into - otherwise it would loop forever laying zero-length stones.
      def split_cap?
        cap? && @cap_mode == CAP_SPLIT && @cap_unit.to_f > 0.0
      end

      def bullnose?
        cap? && @bullnose != BULLNOSE_NONE
      end

      # How far the whole coping is slid sideways off the wall's centre line.
      # Zero when it hangs over both sides; enough to sit FLUSH with the left
      # face when he asked for one side, which puts every inch of the overhang
      # on the right.
      #
      # A coping narrower than the wall shifts the other way by the same rule
      # and ends up flush left, inset right - which is the correct reading of
      # "flush on one side" for a recessed cap too.
      def cap_shift
        return 0.0 unless @overhang == OVERHANG_ONE
        (@cap_width.to_f - @thickness.to_f) / 2.0
      end

      # THE CAP'S CROSS-SECTION, as plain [across, up] pairs. Pure, so the
      # shape of a bullnose can be checked to the thousandth without SketchUp.
      #
      # `across` runs from -width/2 (LEFT of the direction he drew) to
      # +width/2 (RIGHT). `up` runs 0 (sitting on the wall) to height.
      # Counter-clockwise, so the face it makes has a predictable normal.
      #
      # A nosed side is a true half-round of radius height/2: the flat top and
      # bottom stop one radius short, and the arc bulges out to the full
      # width. So a bullnose does NOT make the coping wider than the number he
      # typed - it eats into it, which is what a real stone does.
      def cap_profile(width = @cap_width, height = @cap_height, nose = @bullnose)
        w = width.to_f
        h = height.to_f
        return [] unless w > 0.0 && h > 0.0
        r = h / 2.0
        left  = nose == BULLNOSE_BOTH
        right = nose == BULLNOSE_BOTH || nose == BULLNOSE_ONE

        # A half-round is a fixed shape: radius = half the thickness. On a cap
        # too thin for it the nose simply does not fit, and squashing it to
        # something that does would be a chamfer wearing a bullnose's name.
        # So it falls back to a square edge instead - one nose needs h <= 2w,
        # two need h <= w, because each eats h/2 off its own end.
        #
        # This is the 2" wide x 40" tall case rt64 pins: without the fallback
        # the arc came out a 1"-radius bump on a 40" slab and the section
        # folded over itself.
        room = left && right ? w : w * 2.0
        if h > room + 1e-9
          left = false
          right = false
        end
        left &&= r > 0.0
        right &&= r > 0.0

        pts = []
        pts << [-w / 2.0, 0.0] unless left            # bottom-left corner
        pts << [w / 2.0 - (right ? r : 0.0), 0.0]     # along the bottom
        if right
          arc_into(pts, w / 2.0 - r, r, r, -90.0, 90.0)
        end
        pts << [w / 2.0, h] unless right              # top-right corner
        pts << [-w / 2.0 + (left ? r : 0.0), h]       # back along the top
        if left
          arc_into(pts, -w / 2.0 + r, r, r, 90.0, 270.0)
        end
        # Drop a duplicated closing point if the arc landed back on the start.
        pts.pop if pts.length > 2 && close_pt?(pts.first, pts.last)
        pts
      end

      def close_pt?(a, b)
        (a[0] - b[0]).abs < 1e-9 && (a[1] - b[1]).abs < 1e-9
      end

      # Half a circle as straight pieces, appended in order. The first point
      # is skipped: whoever called us has already put it in.
      def arc_into(pts, cx, cy, r, from_deg, to_deg)
        n = BULLNOSE_SEGMENTS
        (1..n).each do |i|
          a = (from_deg + (to_deg - from_deg) * i / n.to_f) * Math::PI / 180.0
          pts << [cx + r * Math.cos(a), cy + r * Math.sin(a)]
        end
      end

      # WHERE EACH STONE STARTS AND ENDS, as plain numbers along the run.
      # Pure, so a test can check the joints and the cut end without SketchUp,
      # and so the preview and the builder can never lay them differently.
      #
      # Stone, joint, stone, joint... and the last stone is whatever is left.
      def cap_runs(length)
        len = length.to_f
        return [] unless len > 0.0
        return [[0.0, len]] unless split_cap?
        unit  = @cap_unit.to_f
        joint = [@cap_joint.to_f, 0.0].max
        runs  = []
        d = 0.0
        # The guard is the run length, not a counter: every pass advances by
        # at least `unit`, which split_cap? has already proved is positive.
        while d < len - MIN_CAP_PIECE
          e = [d + unit, len].min
          runs << [d, e] if (e - d) >= MIN_CAP_PIECE
          d = e + joint
        end
        runs
      end

      # Is there a cap at all? One question, one place, so the builder, the
      # preview and the stamp can never disagree about it.
      def cap?
        @cap_height.to_f > 0.0 && @cap_width.to_f > 0.0
      end

      # ------------------------------------------------------------ settings
      #
      # A plain inputbox, the same fallback shape the fence uses. The proper
      # HTML panel arrives when there are enough fields to need one; a window
      # full of controls that do nothing yet is worse than no window.
      #
      # Cap thickness 0 = no cap, and the field says so, because that is the
      # only place he would look for the off switch.
      def self.prompt!
        res = UI.inputbox(
          ['Thickness', 'Height', 'Finish',
           'Cap width (side to side)', 'Cap thickness (0 = no cap)', 'Cap finish',
           'Cap units', 'Stone length (Split only)', 'Joint gap (Split only)',
           'Bullnose', 'Cap overhang'],
          [Sketchup.format_length(DEFAULT_THICKNESS),
           Sketchup.format_length(DEFAULT_HEIGHT),
           MATERIALS.first,
           Sketchup.format_length(DEFAULT_CAP_WIDTH),
           Sketchup.format_length(DEFAULT_CAP_HEIGHT),
           MATERIALS.first,
           CAP_CONTINUOUS,
           Sketchup.format_length(DEFAULT_CAP_UNIT),
           Sketchup.format_length(DEFAULT_CAP_JOINT),
           BULLNOSE_NONE, OVERHANG_BOTH],
          ['', '', MATERIALS.join('|'), '', '', MATERIALS.join('|'),
           CAP_MODES.join('|'), '', '', BULLNOSE_MODES.join('|'),
           OVERHANG_MODES.join('|')],
          'Landscape Pro - Garden Wall'
        )
        return nil unless res
        t = parse_length(res[0])
        h = parse_length(res[1])
        return UI.messagebox("Thickness #{res[0].inspect} is not a length.") && nil if t.nil? || t <= 0.0
        return UI.messagebox("Height #{res[1].inspect} is not a length.") && nil if h.nil? || h <= 0.0
        # The cap is optional, so a blank or a zero is an answer, not an
        # error - only nonsense is.
        cw = parse_length(res[3]) || 0.0
        ch = parse_length(res[4]) || 0.0
        cw = 0.0 if cw < 0.0
        ch = 0.0 if ch < 0.0
        mode = res[6].to_s
        unit = parse_length(res[7]) || 0.0
        joint = parse_length(res[8]) || 0.0
        unit = 0.0 if unit < 0.0
        joint = 0.0 if joint < 0.0
        # Split with no stone length is a contradiction, and it is the one
        # way a user can ask for an endless row of nothing. Say so instead of
        # quietly building a continuous cap he did not ask for.
        if mode == CAP_SPLIT && unit <= 0.0 && ch > 0.0 && cw > 0.0
          UI.messagebox('Split cap needs a stone length. Set one, or choose Continuous.')
          return nil
        end
        new(t, h, res[2], cw, ch, res[5], mode, unit, joint, res[9], res[10])
      rescue StandardError => e
        puts "[GardenWall] prompt: #{e.class}: #{e.message}"
        nil
      end

      def self.parse_length(text)
        s = text.to_s.strip
        return nil if s.empty?
        begin
          return s.to_l.to_f
        rescue StandardError
          f = s.to_f
          return f.zero? ? nil : f
        end
      end

      # ------------------------------------------------------------- tool API

      def activate
        @ip = Sketchup::InputPoint.new
        reset
        status
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        view.invalidate
      end

      def enableVCB?
        true
      end

      def onCancel(_reason, view)
        reset
        status
        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        return unless key == 27
        reset
        status
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        @cursor = flat_point(view, x, y)
        if @p1
          Sketchup.vcb_label = 'Length'
          Sketchup.vcb_value = Sketchup.format_length(@cursor.distance(@p1))
          refresh_ghost
        end
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        pt = flat_point(view, x, y)
        if @p1.nil?
          @p1 = pt
        else
          return if pt.distance(@p1) < MIN_LEN
          @p2 = pt
          build_it(view)
        end
        status
        view.invalidate
      end

      def onLButtonDoubleClick(_flags, _x, _y, _view); end

      def onUserText(text, view)
        return unless @p1 && @cursor
        v = self.class.parse_length(text)
        return UI.messagebox("Invalid length: #{text.inspect}") if v.nil?
        return if v.abs < MIN_LEN
        dir = @cursor - @p1
        return if dir.length < 1e-6
        dir.normalize!
        @p2 = @p1.offset(dir, v.abs)
        build_it(view)
        status
        view.invalidate
      end

      def draw(view)
        @ip.draw(view) if @ip && @ip.display?
        view.line_width = 2
        view.line_stipple = '-'
        view.drawing_color = Sketchup::Color.new(*GHOST)
        if @ghost
          @ghost.each { |seg| view.draw(GL_LINES, seg) }
        elsif @p1 && @cursor
          view.draw(GL_LINES, [@p1, @cursor])
        end
        view.line_stipple = ''
        [@p1, @p2].compact.each do |pt|
          view.draw_points([pt], 8, 2, Sketchup::Color.new(*DOT))
        end
      rescue StandardError
        nil
      end

      def getExtents
        bb = Geom::BoundingBox.new
        bb.add(@p1) if @p1
        bb.add(@cursor) if @cursor
        @ghost&.each { |seg| seg.each { |p| bb.add(p) } }
        bb
      end

      # ------------------------------------------------- the shape, as numbers
      #
      # Pure: two points in, the four floor corners out, going round. Split
      # out from the builder so a test can check WHERE the wall lands without
      # SketchUp, and so the preview and the real thing can never disagree -
      # they call this same method.
      #
      # The wall is CENTRED on the line he draws: half the thickness each
      # side. (An anchor - draw on the left edge / right edge - is a wall-tool
      # idea; out here he is walking the centre of a garden wall. If he asks
      # for it later it goes in here and nowhere else.)
      def footprint(a, b, thickness = @thickness)
        u, n = self.class.axes(a, b)
        return nil unless u
        half = thickness.to_f / 2.0
        # Counter-clockwise seen from above, so the face SketchUp makes out of
        # them points UP. It still gets asked which way it faces before the
        # pushpull (a face can be flipped by geometry it merges with), but
        # starting the right way up means the ordinary case never relies on
        # that safety net.
        [a.offset(n, -half),
         b.offset(n, -half),
         b.offset(n,  half),
         a.offset(n,  half)]
      end

      # Run direction and the left-hand perpendicular, or nil for a zero line.
      def self.axes(a, b)
        dx = b.x - a.x
        dy = b.y - a.y
        len = Math.sqrt(dx * dx + dy * dy)
        return [nil, nil] if len < 1e-9
        u = Geom::Vector3d.new(dx / len, dy / len, 0)
        n = Geom::Vector3d.new(-u.y, u.x, 0)
        [u, n]
      end

      # ------------------------------------------------------------- private

      private

      def reset
        @p1 = nil
        @p2 = nil
        @cursor = nil
        @ghost = nil
      end

      def status
        msg = if @p1.nil?
                format('Garden wall %s x %s, %s%s (1/2): click where it starts. Esc = cancel.',
                       Sketchup.format_length(@thickness),
                       Sketchup.format_length(@height), @material,
                       cap? ? ", cap #{Sketchup.format_length(@cap_width)}" : ', no cap')
              else
                'Garden wall (2/2): click where it ends, or type a length.'
              end
        Sketchup.set_status_text(msg, SB_PROMPT)
      end

      def flat_point(view, x, y)
        p = view.inputpoint(x, y).position
        Geom::Point3d.new(p.x, p.y, 0)
      end

      # The dashed box he sees before he commits: the floor rectangle and the
      # four uprights, from the SAME footprint the builder will use.
      def refresh_ghost
        @ghost = nil
        return unless @p1 && @cursor
        len = @cursor.distance(@p1)
        return if len < MIN_LEN
        corners = footprint(@p1, @cursor)
        return unless corners
        up = Geom::Vector3d.new(0, 0, 1)
        segs = []
        corners.each_with_index do |c, i|
          d = corners[(i + 1) % corners.length]
          segs << [c, d]
          segs << [c.offset(up, @height), d.offset(up, @height)]
          segs << [c, c.offset(up, @height)]
        end
        if cap?
          # One dashed box per stone, so the joints are visible BEFORE he
          # commits - the whole point of choosing a stone length is seeing how
          # it lands, and where the cut one falls.
          u, nrm = self.class.axes(@p1, @cursor)
          shift = cap_shift
          cap_runs(len).each do |(d0, d1)|
            cc = footprint(@p1.offset(u, d0), @p1.offset(u, d1), @cap_width)
            next unless cc
            cc = cc.map { |c| c.offset(nrm, shift) } unless shift.zero?
            lo = cc.map { |c| c.offset(up, @height) }
            hi = cc.map { |c| c.offset(up, @height + @cap_height) }
            lo.each_with_index do |c, i|
              j = (i + 1) % lo.length
              segs << [c, lo[j]]
              segs << [hi[i], hi[j]]
              segs << [c, hi[i]]
            end
          end
        end
        @ghost = segs
        Sketchup.set_status_text(
          format("Garden wall | %.2f' long | %s thick | %s high | %s%s",
                 len / 12.0, Sketchup.format_length(@thickness),
                 Sketchup.format_length(@height), @material,
                 cap? ? format(' | cap %s x %s %s%s',
                               Sketchup.format_length(@cap_width),
                               Sketchup.format_length(@cap_height),
                               @cap_material,
                               split_cap? ? ", #{cap_runs(len).length} stones" : ', continuous') +
                      (bullnose? ? " | bullnose #{@bullnose.downcase}" : '')
                      : ' | no cap'), SB_PROMPT)
      rescue StandardError => e
        puts "[GardenWall] preview: #{e.class}: #{e.message}"
        @ghost = nil
      end

      # ----------------------------------------------------------- building

      def build_it(view)
        model = Sketchup.active_model
        a = @p1
        b = @p2
        return reset_and_redraw(view) unless a && b

        # The same red/green straightening the fence and the wall tool use.
        # Borrowed, not copied - if he retunes the magnet it retunes here too.
        begin
          if defined?(InteriorPro::WallTool) &&
             InteriorPro::WallTool.respond_to?(:apply_axis_magnet)
            a, b = InteriorPro::WallTool.apply_axis_magnet(a, b, model)
          end
        rescue StandardError => e
          puts "[GardenWall] axis magnet skipped: #{e.message}"
        end

        if a.distance(b) < MIN_LEN
          UI.messagebox('That wall is too short to build.')
          return reset_and_redraw(view)
        end

        model.start_operation('Create Garden Wall', true)
        begin
          group = build!(a, b, model)
          model.commit_operation
          if group
            puts format('[GardenWall] built %.1f" long, %.1f" thick, %.1f" high, %s',
                        a.distance(b), @thickness, @height, @material)
          end
        rescue StandardError => e
          model.abort_operation
          puts "[GardenWall] build failed: #{e.class}: #{e.message}\n" +
               Array(e.backtrace).first(6).join("\n")
          UI.messagebox("Could not build the wall: #{e.message}")
        end
        reset_and_redraw(view)
      end

      def reset_and_redraw(view)
        reset
        view.invalidate
        nil
      end

      # One group, one solid, its own dictionary. Public so a test (and a
      # future edit tool) can build one without driving the mouse.
      public

      def build!(a, b, model = Sketchup.active_model)
        corners = footprint(a, b)
        return nil unless corners

        group = model.active_entities.add_group
        group.name = GROUP_NAME
        begin
          InteriorPro.assign_tag(group, TAG)
        rescue StandardError
          nil
        end

        face = group.entities.add_face(corners)
        return nil unless face
        # pushpull runs along the face normal, and which way a new face faces
        # depends on the order its corners came out in - which flips with the
        # direction he drew. Ask the face, do not assume: a wall built
        # downwards is invisible under the ground and reads as "nothing
        # happened".
        face.pushpull(face.normal.z < 0 ? -@height : @height)
        body_faces = group.entities.grep(Sketchup::Face)
        paint!(body_faces, @material)

        # The cap goes in its OWN nested group. Two reasons, both learned the
        # hard way elsewhere in this plugin: a cap sitting loose in the same
        # entities would merge its faces into the wall's the moment they touch
        # (so the wall's finish and the cap's finish fight over the seam), and
        # a later edit that rebuilds the cap has to be able to erase it
        # without touching the body.
        if cap?
          cap_group = build_cap!(group, a, b)
          # The coping is extruded from a SECTION, so its one starting face
          # stands on end - none of its faces point down and the skip that
          # protects the wall's underside would do nothing here anyway. Passed
          # explicitly so nobody has to work that out again.
          paint!(cap_faces(cap_group), @cap_material, false) if cap_group
        end

        stamp!(group, a, b)
        group
      end

      # The coping: cap_width across, cap_height tall, sitting ON the top of
      # the wall and centred on the same line. Always its own group so a later
      # step can find it and rebuild it without touching the body.
      #
      # Continuous = one slab. Split = one nested group per stone, because a
      # stone he cannot select on its own is not a stone, and because faces
      # left loose in one group would weld across the joints.
      def build_cap!(parent, a, b)
        u, = self.class.axes(a, b)
        return nil unless u
        len = a.distance(b)
        runs = cap_runs(len)
        return nil if runs.empty?

        cap = parent.entities.add_group
        cap.name = CAP_NAME

        _, n = self.class.axes(a, b)
        if split_cap?
          runs.each_with_index do |(d0, d1), i|
            stone = cap.entities.add_group
            stone.name = "#{CAP_UNIT_NAME}_#{i + 1}"
            slab!(stone.entities, a.offset(u, d0), a.offset(u, d1), u, n)
          end
        else
          slab!(cap.entities, a, b, u, n)
        end
        cap
      rescue StandardError => e
        puts "[GardenWall] cap: #{e.class}: #{e.message}"
        nil
      end

      # One piece of coping between two points on the run.
      #
      # Built as its CROSS-SECTION extruded along the wall, not as a plate
      # pushed upwards. That is the only way a bullnose can exist: the nose is
      # a shape in the section, and every inch of the stone has the same
      # section. It also means a plain square cap and a nosed one come out of
      # exactly one code path, so they cannot drift apart.
      def slab!(ents, p0, p1, u, n)
        prof = cap_profile
        return nil if prof.length < 3
        up = Geom::Vector3d.new(0, 0, 1)
        base = p0.offset(up, @height)
        shift = cap_shift
        face = ents.add_face(prof.map { |(across, high)|
          base.offset(n, across + shift).offset(up, high)
        })
        return nil unless face
        len = p0.distance(p1)
        return nil if len <= 0.0
        # Extrude ALONG the wall. Which way the section face ended up looking
        # depends on the direction he drew, so ask it rather than assume - the
        # same trap as the body, and here it would bury the coping inside the
        # wall instead of under the ground.
        face.pushpull(face.normal.dot(u) < 0 ? -len : len)
        smooth_arc!(ents)
        face
      end

      # Take the facet lines off the half-round. Anything where the two faces
      # meeting at an edge are nearly in line is the arc; a real corner is
      # 90 degrees and keeps its line.
      def smooth_arc!(ents)
        return unless bullnose?
        ents.grep(Sketchup::Edge).each do |e|
          fs = e.faces
          next unless fs.length == 2
          next unless self.class.soften?(fs[0].normal, fs[1].normal)
          e.soft = true
          e.smooth = true
        end
      rescue StandardError => e
        puts "[GardenWall] smooth: #{e.class}: #{e.message}"
      end

      # Pure, so the rule can be checked without SketchUp: are these two faces
      # near enough in line that the edge between them is a facet, not a
      # corner?
      def self.soften?(a, b)
        return false if a.nil? || b.nil?
        d = a.dot(b).to_f
        d = 1.0 if d > 1.0
        d = -1.0 if d < -1.0
        (Math.acos(d) * 180.0 / Math::PI) < SOFTEN_DEGREES
      end

      private

      # One finish over a set of faces, skipping whatever points straight down
      # - the wall's underside is against the ground and the cap's underside
      # is against the wall. Neither is ever seen, and painting them wastes a
      # texture on every wall in the model.
      #
      # The wall's TOP face is still painted even when a cap covers it: a cap
      # narrower than the wall leaves a shoulder of it showing.
      # Every face of the coping, whether it is one slab or fifty stones one
      # group down.
      def cap_faces(cap)
        return [] unless cap
        own = cap.entities.grep(Sketchup::Face)
        nested = cap.entities.grep(Sketchup::Group).flat_map { |g| g.entities.grep(Sketchup::Face) }
        own + nested
      end

      def paint!(faces, name, skip_down = true)
        mat = self.class.finish_material(name)
        return unless mat
        Array(faces).each do |f|
          next if skip_down && f.normal.z < -0.5
          f.material = mat
          f.back_material = nil
        end
      rescue StandardError => e
        puts "[GardenWall] paint: #{e.class}: #{e.message}"
      end

      # Its own material lookup, deliberately NOT WallTool's: that one is an
      # instance method of the wall tool and its list is the house finishes.
      # Same shape though - a texture if there is one, a stand-in colour if
      # there is not.
      def self.finish_material(name)
        model = Sketchup.active_model
        mats = model.materials
        key = "LandscapePro_#{name}"
        existing = mats[key]
        return existing if existing

        mat = mats.add(key)
        file = File.join(InteriorPro::PLUGIN_DIR, 'textures',
                         "#{name.to_s.downcase.gsub(' ', '_')}.jpg")
        if File.exist?(file)
          mat.texture = file
          mat.texture.size = 48 if mat.texture
        else
          hex = FALLBACK_COLOR[name] || '#c0bab0'
          mat.color = Sketchup::Color.new(hex)
        end
        mat
      rescue StandardError => e
        puts "[GardenWall] material #{name.inspect}: #{e.class}: #{e.message}"
        nil
      end

      # Everything a later tool needs to rebuild or edit this wall, under
      # LandscapePro - never InteriorPro. start/end are WORLD points, because
      # the group is created at the top level with an identity transformation
      # and the fence stores them the same way.
      def stamp!(group, a, b)
        group.set_attribute(DICT, 'type', TYPE)
        group.set_attribute(DICT, 'thickness', @thickness.to_f)
        group.set_attribute(DICT, 'height', @height.to_f)
        group.set_attribute(DICT, 'material', @material.to_s)
        group.set_attribute(DICT, 'cap_width', cap? ? @cap_width.to_f : 0.0)
        group.set_attribute(DICT, 'cap_height', cap? ? @cap_height.to_f : 0.0)
        group.set_attribute(DICT, 'cap_material', cap? ? @cap_material.to_s : '')
        group.set_attribute(DICT, 'cap_mode', cap? ? @cap_mode.to_s : '')
        group.set_attribute(DICT, 'cap_unit', split_cap? ? @cap_unit.to_f : 0.0)
        group.set_attribute(DICT, 'cap_joint', split_cap? ? [@cap_joint.to_f, 0.0].max : 0.0)
        group.set_attribute(DICT, 'bullnose', cap? ? @bullnose.to_s : BULLNOSE_NONE)
        group.set_attribute(DICT, 'overhang', cap? ? @overhang.to_s : '')
        # Total height including the coping - what a schedule or an elevation
        # actually wants, and a number nobody should have to add up by hand.
        group.set_attribute(DICT, 'overall_height',
                            @height.to_f + (cap? ? @cap_height.to_f : 0.0))
        group.set_attribute(DICT, 'start_x', a.x.to_f)
        group.set_attribute(DICT, 'start_y', a.y.to_f)
        group.set_attribute(DICT, 'end_x', b.x.to_f)
        group.set_attribute(DICT, 'end_y', b.y.to_f)
        group.set_attribute(DICT, 'length_in', a.distance(b).to_f)
        # Terrain, filled in when it arrives - the fence carries the same two
        # numbers so both can be lifted onto a slope by the same code.
        group.set_attribute(DICT, 'ground_start', @ground_start.to_f)
        group.set_attribute(DICT, 'ground_end', @ground_end.to_f)
        group.set_attribute(DICT, 'created_at', Time.now.to_i)
      rescue StandardError => e
        puts "[GardenWall] stamp: #{e.class}: #{e.message}"
      end

    end
  end
end
