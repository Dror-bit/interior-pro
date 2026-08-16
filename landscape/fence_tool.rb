# encoding: utf-8
# Landscape Pro - Fence Tool (2026-08-15)
#
#   click 1 = where the fence starts
#   click 2 = where the fence ends
#
# WHAT THIS FILE IS AND IS NOT
#
# It is the HANDS. Every number it draws with comes from landscape/fence_math.rb,
# which is pure and proved green by tests/rt56.rb before this file ever runs.
# There is no second dialect of fence arithmetic in here: no post spacing worked
# out locally, no height added up by hand. If a fence comes out wrong, the
# question is which of the two files is wrong, and rt56 answers that in the
# cloud without opening SketchUp.
#
# WHY IT IS NOT A WallTool SUBCLASS
#
# A wall is one box with a flat top. A fence is posts and bays, and its top
# follows the ground. Inheriting from WallTool would drag in siding, board and
# batten, mitred corners and the opening code - none of which a fence has - and
# would tie the walls the user already trusts to a brand new file. So the fence
# stands on its own and BORROWS the one wall behaviour that is genuinely shared:
# WallTool.apply_axis_magnet, the guard that lands a nearly-straight run exactly
# on the axis. Borrowed by calling it, not by copying it.
#
# THE GROUND
#
# ground_start / ground_end are ordinary numbers in inches, and today the user
# types them (0 and 0 means level, and a level fence is bit-for-bit what it was
# before the slope code existed). The day terrain exists it fills those two
# numbers in and NOTHING here changes. That is why there are two of them and
# not one: a single ground height can never slope.
#
# STORAGE
#
# Everything lands in its own 'LandscapePro' attribute dictionary, NOT in
# 'InteriorPro'. Nothing that walks the walls, rooms, floors, roofs or the 2D
# plan can trip over a fence, and nothing here can be mistaken for a wall.

require_relative 'fence_math.rb'

module InteriorPro
  module Landscape
    class FenceTool

      DICT = 'LandscapePro' unless const_defined?(:DICT, false)

      GHOST = [120, 120, 120].freeze unless const_defined?(:GHOST, false)
      DOT   = [40, 90, 200].freeze   unless const_defined?(:DOT, false)

      WOOD_MATERIAL = 'LandscapePro_Fence_Wood' unless const_defined?(:WOOD_MATERIAL, false)
      DEFAULT_COLOR = '#A1887F' unless const_defined?(:DEFAULT_COLOR, false)

      attr_accessor :height, :max_spacing, :post_size, :board_width,
                    :board_gap, :board_thickness, :ground_start, :ground_end,
                    :mode, :embed, :gap_below, :color

      def initialize
        @height          = InteriorPro::Landscape::FenceMath::DEFAULT_HEIGHT
        @max_spacing     = InteriorPro::Landscape::FenceMath::DEFAULT_SPACING
        @post_size       = InteriorPro::Landscape::FenceMath::DEFAULT_POST_SIZE
        @board_width     = InteriorPro::Landscape::FenceMath::DEFAULT_BOARD_W
        @board_gap       = InteriorPro::Landscape::FenceMath::DEFAULT_BOARD_GAP
        @board_thickness = InteriorPro::Landscape::FenceMath::DEFAULT_BOARD_T
        @ground_start    = 0.0
        @ground_end      = 0.0
        @mode            = :rake
        @embed           = 0.0
        @gap_below       = 0.0
        @color           = DEFAULT_COLOR
        reset
      end

      def fm
        InteriorPro::Landscape::FenceMath
      end

      # ------------------------------------------------------------ settings
      #
      # A plain SketchUp inputbox on purpose. The HTML library dialog comes
      # with the fence TYPES; until there are types to pick from, a window
      # would be six fields wearing a costume.
      def prompt_settings!
        titles = ['Height (in)', 'Post spacing max (in)', 'Post size (in)',
                  'Board width (in)', 'Gap between boards (in)',
                  'Board thickness (in)',
                  'Ground at start (in)', 'Ground at end (in)',
                  'On a slope']
        defaults = [@height, @max_spacing, @post_size, @board_width,
                    @board_gap, @board_thickness,
                    @ground_start, @ground_end,
                    (@mode == :step ? 'Step' : 'Rake')]
        lists = ['', '', '', '', '', '', '', '', 'Rake|Step']
        res = UI.inputbox(titles, defaults, lists, 'Landscape Pro - Fence')
        return false unless res

        @height          = res[0].to_f
        @max_spacing     = res[1].to_f
        @post_size       = res[2].to_f
        @board_width     = res[3].to_f
        @board_gap       = res[4].to_f
        @board_thickness = res[5].to_f
        @ground_start    = res[6].to_f
        @ground_end      = res[7].to_f
        @mode            = (res[8].to_s == 'Step' ? :step : :rake)
        true
      rescue StandardError => e
        puts "[Fence] settings: #{e.class}: #{e.message}"
        false
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
          return if pt.distance(@p1) < InteriorPro::Landscape::FenceMath::MIN_LEN
          @p2 = pt
          build_it(view)
        end
        status
        view.invalidate
      end

      def onLButtonDoubleClick(_flags, _x, _y, _view); end

      # Typed length while the second point is being placed.
      def onUserText(text, view)
        return unless @p1 && @cursor
        v = parse_length(text)
        return UI.messagebox("Invalid length: #{text.inspect}") if v.nil?
        return if v.abs < InteriorPro::Landscape::FenceMath::MIN_LEN
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
                'Fence (1/2): click where the fence starts. Esc = cancel.'
              else
                'Fence (2/2): click where it ends, or type a length.'
              end
        Sketchup.set_status_text(msg, SB_PROMPT)
      end

      def flat_point(view, x, y)
        p = view.inputpoint(x, y).position
        Geom::Point3d.new(p.x, p.y, 0)
      end

      # Feet-and-inches, the same spellings the rest of the plugin accepts.
      # A bare number falls back to inches rather than refusing outright.
      def parse_length(text)
        s = text.to_s.strip
        return nil if s.empty?
        begin
          return s.to_l.to_f
        rescue StandardError
          f = s.to_f
          return f.zero? ? nil : f
        end
      end

      # The preview: the top line of every bay plus a stroke for every post.
      # Cheap, and it shows the ONE thing worth seeing before committing -
      # where the posts land and how the top follows the ground.
      def refresh_ghost
        @ghost = nil
        return unless @p1 && @cursor
        lay = layout_for(@p1, @cursor)
        return unless lay
        segs = []
        lay[:bays].each do |b|
          segs << [Geom::Point3d.new(b[:x0], b[:y0], b[:z_top0]),
                   Geom::Point3d.new(b[:x1], b[:y1], b[:z_top1])]
          segs << [Geom::Point3d.new(b[:x0], b[:y0], b[:z_bottom0]),
                   Geom::Point3d.new(b[:x1], b[:y1], b[:z_bottom1])]
        end
        lay[:posts].each do |p|
          segs << [Geom::Point3d.new(p[:x], p[:y], p[:z_base]),
                   Geom::Point3d.new(p[:x], p[:y], p[:z_top])]
        end
        @ghost = segs
        Sketchup.set_status_text(fm.describe(lay), SB_PROMPT)
      rescue StandardError => e
        puts "[Fence] preview: #{e.class}: #{e.message}"
        @ghost = nil
      end

      def layout_for(a, b)
        fm.layout(a.x, a.y, b.x, b.y,
                  height: @height, max_spacing: @max_spacing,
                  z0: @ground_start, z1: @ground_end,
                  mode: @mode, embed: @embed, gap_below: @gap_below)
      end

      # ------------------------------------------------------------ building

      def build_it(view)
        model = Sketchup.active_model
        a = @p1
        b = @p2
        return reset_and_redraw(view) unless a && b

        # The same axis guard every wall goes through, called - not copied.
        begin
          if defined?(InteriorPro::WallTool) &&
             InteriorPro::WallTool.respond_to?(:apply_axis_magnet)
            a, b = InteriorPro::WallTool.apply_axis_magnet(a, b, model)
          end
        rescue StandardError => e
          puts "[Fence] axis magnet skipped: #{e.message}"
        end

        lay = layout_for(a, b)
        unless lay
          UI.messagebox('That fence is too short to build.')
          return reset_and_redraw(view)
        end

        model.start_operation('Create Fence', true)
        begin
          group = build_fence_group(a, b, lay, model)
          model.commit_operation
          puts "[Fence] built: #{fm.describe(lay)}" if group
        rescue StandardError => e
          model.abort_operation
          puts "[Fence] build failed: #{e.class}: #{e.message}\n" +
               Array(e.backtrace).first(6).join("\n")
          UI.messagebox("Could not build the fence: #{e.message}")
        end

        reset_and_redraw(view)
      end

      def reset_and_redraw(view)
        reset
        view.invalidate
        nil
      end

      def build_fence_group(a, b, lay, model)
        group = model.active_entities.add_group
        group.name = 'LandscapePro_Fence'
        begin
          InteriorPro.assign_tag(group, 'LP/Fences')
        rescue StandardError
          nil
        end

        # Everything needed to rebuild this fence from scratch, and nothing
        # that can be worked out from those numbers.
        group.set_attribute(DICT, 'type', 'fence')
        group.set_attribute(DICT, 'start_x', a.x.to_f)
        group.set_attribute(DICT, 'start_y', a.y.to_f)
        group.set_attribute(DICT, 'end_x', b.x.to_f)
        group.set_attribute(DICT, 'end_y', b.y.to_f)
        group.set_attribute(DICT, 'ground_start', @ground_start.to_f)
        group.set_attribute(DICT, 'ground_end', @ground_end.to_f)
        group.set_attribute(DICT, 'height', @height.to_f)
        group.set_attribute(DICT, 'max_spacing', @max_spacing.to_f)
        group.set_attribute(DICT, 'post_size', @post_size.to_f)
        group.set_attribute(DICT, 'board_width', @board_width.to_f)
        group.set_attribute(DICT, 'board_gap', @board_gap.to_f)
        group.set_attribute(DICT, 'board_thickness', @board_thickness.to_f)
        group.set_attribute(DICT, 'embed', @embed.to_f)
        group.set_attribute(DICT, 'gap_below', @gap_below.to_f)
        group.set_attribute(DICT, 'slope_mode', @mode.to_s)
        group.set_attribute(DICT, 'color', @color.to_s)
        group.set_attribute(DICT, 'length_in', lay[:length])
        group.set_attribute(DICT, 'bays', lay[:bays].length)
        group.set_attribute(DICT, 'posts', lay[:posts].length)
        group.set_attribute(DICT, 'id', new_id)
        group.set_attribute(DICT, 'created_at',
                            Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
        group.set_attribute(DICT, 'plugin_version', '0.1')

        ents = group.entities
        mat  = wood_material(model)

        u, n = axes(a, b)

        lay[:posts].each { |p| build_post(ents, p, u, n, mat) }
        lay[:bays].each  { |bay| build_bay(ents, bay, a, b, u, n, mat) }

        group
      end

      # Unit vector along the run, and the horizontal unit vector across it.
      def axes(a, b)
        dx = b.x - a.x
        dy = b.y - a.y
        len = Math.sqrt(dx * dx + dy * dy)
        u = Geom::Vector3d.new(dx / len, dy / len, 0)
        n = Geom::Vector3d.new(-u.y, u.x, 0)
        [u, n]
      end

      def build_post(ents, p, u, n, mat)
        h = p[:z_top].to_f - p[:z_base].to_f
        return if h <= 0.0
        s = @post_size.to_f / 2.0
        return if s <= 0.0
        c = Geom::Point3d.new(p[:x], p[:y], p[:z_base])
        pts = [
          c.offset(u, -s).offset(n, -s),
          c.offset(u,  s).offset(n, -s),
          c.offset(u,  s).offset(n,  s),
          c.offset(u, -s).offset(n,  s)
        ]
        face = ents.add_face(pts)
        return unless face
        # Push UP whichever way the face happens to have been born facing.
        face.pushpull(face.normal.z >= 0 ? h : -h)
        paint!(face, mat)
      rescue StandardError => e
        puts "[Fence] post #{p[:i]}: #{e.message}"
      end

      # One bay = its boards. Each board is a flat slab standing on edge, its
      # top taken from fence_math - so on a raked bay every board is a hair
      # shorter than the one before it, and on a stepped bay they are all
      # equal, without this code knowing which case it is in.
      def build_bay(ents, bay, a, b, u, n, mat)
        runs = fm.board_runs(bay, @board_width, @board_gap, @post_size)
        th = @board_thickness.to_f
        return if th <= 0.0
        runs.each do |(t0, t1)|
          build_board(ents, bay, a, b, u, n, t0, t1, th, mat)
        end
      end

      def build_board(ents, bay, a, b, u, n, t0, t1, th, mat)
        x0, y0 = fm.point_at(a.x, a.y, b.x, b.y, t0)
        x1, y1 = fm.point_at(a.x, a.y, b.x, b.y, t1)
        zb0 = fm.bottom_at(bay, t0)
        zb1 = fm.bottom_at(bay, t1)
        zt0 = fm.top_at(bay, t0)
        zt1 = fm.top_at(bay, t1)
        return if zt0 - zb0 <= 0.0 || zt1 - zb1 <= 0.0

        half = th / 2.0
        pts = [
          Geom::Point3d.new(x0, y0, zb0).offset(n, -half),
          Geom::Point3d.new(x1, y1, zb1).offset(n, -half),
          Geom::Point3d.new(x1, y1, zt1).offset(n, -half),
          Geom::Point3d.new(x0, y0, zt0).offset(n, -half)
        ]
        face = ents.add_face(pts)
        return unless face
        face.pushpull(face.normal.dot(n) >= 0 ? th : -th)
        paint!(face, mat)
      rescue StandardError => e
        puts "[Fence] board: #{e.message}"
      end

      # Paint every face of the solid the face belongs to, so a fence is one
      # colour whichever way its faces were born facing.
      def paint!(face, mat)
        return unless mat
        return unless face && face.valid?
        face.all_connected.grep(Sketchup::Face).each do |f|
          f.material = mat
          f.back_material = mat
        end
      rescue StandardError
        nil
      end

      def wood_material(model)
        mats = model.materials
        m = mats[WOOD_MATERIAL]
        return m if m
        m = mats.add(WOOD_MATERIAL)
        m.color = Sketchup::Color.new(@color.to_s)
        m
      rescue StandardError => e
        puts "[Fence] material: #{e.message}"
        nil
      end

      def new_id
        "fence-#{Time.now.to_i.to_s(36)}-#{rand(36**4).to_s(36)}"
      end

    end
  end
end
