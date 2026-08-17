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

      attr_accessor :thickness, :height, :material, :ground_start, :ground_end
      attr_accessor :cap_width, :cap_height, :cap_material
      attr_accessor :cap_mode, :cap_unit, :cap_joint

      def initialize(thickness = DEFAULT_THICKNESS, height = DEFAULT_HEIGHT,
                     material = MATERIALS.first,
                     cap_width = DEFAULT_CAP_WIDTH, cap_height = DEFAULT_CAP_HEIGHT,
                     cap_material = MATERIALS.first,
                     cap_mode = CAP_CONTINUOUS,
                     cap_unit = DEFAULT_CAP_UNIT, cap_joint = DEFAULT_CAP_JOINT)
        @thickness    = thickness.to_f
        @height       = height.to_f
        @material     = material.to_s
        @cap_width    = cap_width.to_f
        @cap_height   = cap_height.to_f
        @cap_material = cap_material.to_s
        @cap_mode     = CAP_MODES.include?(cap_mode.to_s) ? cap_mode.to_s : CAP_CONTINUOUS
        @cap_unit     = cap_unit.to_f
        @cap_joint    = cap_joint.to_f
        @ground_start = 0.0
        @ground_end   = 0.0
        reset
      end

      # Split only counts as split if there is a real stone length to split
      # into - otherwise it would loop forever laying zero-length stones.
      def split_cap?
        cap? && @cap_mode == CAP_SPLIT && @cap_unit.to_f > 0.0
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
           'Cap units', 'Stone length (Split only)', 'Joint gap (Split only)'],
          [Sketchup.format_length(DEFAULT_THICKNESS),
           Sketchup.format_length(DEFAULT_HEIGHT),
           MATERIALS.first,
           Sketchup.format_length(DEFAULT_CAP_WIDTH),
           Sketchup.format_length(DEFAULT_CAP_HEIGHT),
           MATERIALS.first,
           CAP_CONTINUOUS,
           Sketchup.format_length(DEFAULT_CAP_UNIT),
           Sketchup.format_length(DEFAULT_CAP_JOINT)],
          ['', '', MATERIALS.join('|'), '', '', MATERIALS.join('|'),
           CAP_MODES.join('|'), '', ''],
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
        new(t, h, res[2], cw, ch, res[5], mode, unit, joint)
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
          u, = self.class.axes(@p1, @cursor)
          cap_runs(len).each do |(d0, d1)|
            cc = footprint(@p1.offset(u, d0), @p1.offset(u, d1), @cap_width)
            next unless cc
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
                               split_cap? ? ", #{cap_runs(len).length} stones" : ', continuous')
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
          paint!(cap_faces(cap_group), @cap_material) if cap_group
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

        if split_cap?
          runs.each_with_index do |(d0, d1), i|
            stone = cap.entities.add_group
            stone.name = "#{CAP_UNIT_NAME}_#{i + 1}"
            slab!(stone.entities, a.offset(u, d0), a.offset(u, d1))
          end
        else
          slab!(cap.entities, a, b)
        end
        cap
      rescue StandardError => e
        puts "[GardenWall] cap: #{e.class}: #{e.message}"
        nil
      end

      # One piece of coping between two points on the run.
      def slab!(ents, p0, p1)
        corners = footprint(p0, p1, @cap_width)
        return nil unless corners
        up = Geom::Vector3d.new(0, 0, 1)
        f = ents.add_face(corners.map { |c| c.offset(up, @height) })
        return nil unless f
        f.pushpull(f.normal.z < 0 ? -@cap_height : @cap_height)
        f
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

      def paint!(faces, name)
        mat = self.class.finish_material(name)
        return unless mat
        Array(faces).each do |f|
          next if f.normal.z < -0.5
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
