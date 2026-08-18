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

      WOOD_MATERIAL  = 'LandscapePro_Fence_Wood' unless const_defined?(:WOOD_MATERIAL, false)
      GLASS_MATERIAL = 'LandscapePro_Fence_Glass' unless const_defined?(:GLASS_MATERIAL, false)
      DEFAULT_COLOR  = '#A1887F' unless const_defined?(:DEFAULT_COLOR, false)
      GLASS_COLOR    = '#BBDEFB' unless const_defined?(:GLASS_COLOR, false)
      GLASS_ALPHA    = 0.35 unless const_defined?(:GLASS_ALPHA, false)

      attr_accessor :height, :max_spacing, :post_size, :board_width,
                    :board_gap, :board_thickness, :ground_start, :ground_end,
                    :mode, :embed, :gap_below, :color,
                    # The anatomy, added 2026-08-16 after measuring six real
                    # fences the user had built elsewhere. Every one of these
                    # defaults to OFF, so a tool made with no library type
                    # behind it builds precisely the fence this file built
                    # yesterday - which is what keeps rt57 honest.
                    :infill, :rail_count, :rail_height, :rail_thickness,
                    :rail_bottom_z, :post_extra, :cap_size, :cap_height

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

        @infill          = 'boards'
        @rail_count      = 0
        @rail_height     = InteriorPro::Landscape::FenceMath::DEFAULT_RAIL_HEIGHT
        @rail_thickness  = InteriorPro::Landscape::FenceMath::DEFAULT_RAIL_THICKNESS
        @rail_bottom_z   = 0.0
        @post_extra      = 0.0
        @cap_size        = 0.0
        @cap_height      = 0.0
        reset
      end

      def fm
        InteriorPro::Landscape::FenceMath
      end

      # Everything fence_math needs to know about this fence, in ONE place.
      # Nothing else in this file may assemble an options hash: when a new
      # number has to reach the maths it gets wired in here once, and every
      # caller picks it up for free.
      def build_opts
        { height: @height, max_spacing: @max_spacing,
          z0: @ground_start, z1: @ground_end,
          mode: @mode, embed: @embed, gap_below: @gap_below,
          infill: @infill.to_s,
          board_width: @board_width, board_gap: @board_gap,
          post_size: @post_size,
          rail_count: @rail_count, rail_height: @rail_height,
          rail_bottom_z: @rail_bottom_z, post_extra: @post_extra,
          cap_size: @cap_size, cap_height: @cap_height }
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
        fm.layout(a.x, a.y, b.x, b.y, build_opts)
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
        # The anatomy (2026-08-16). Stored even when it is off, so a fence
        # built today can still be told apart from one built yesterday.
        group.set_attribute(DICT, 'infill', @infill.to_s)
        group.set_attribute(DICT, 'rail_count', @rail_count.to_i)
        group.set_attribute(DICT, 'rail_height', @rail_height.to_f)
        group.set_attribute(DICT, 'rail_thickness', @rail_thickness.to_f)
        group.set_attribute(DICT, 'rail_bottom_z', @rail_bottom_z.to_f)
        group.set_attribute(DICT, 'post_extra', @post_extra.to_f)
        group.set_attribute(DICT, 'cap_size', @cap_size.to_f)
        group.set_attribute(DICT, 'cap_height', @cap_height.to_f)
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
        @axes = [u, n]

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

      # EVERY part gets its own little group (2026-08-16).
      #
      # Before this, the whole fence was loose faces in one bag. Two boards
      # that touched became one welded solid, and a glass panel touching its
      # rail would drag the rail's colour with it, because paint! walks
      # all_connected. Nesting stops both, and it is also how the six real
      # fences that were measured are put together: post, rail and picket are
      # each their own object.
      def solid!(ents, name, pts, dir, amount, mat)
        amount = amount.to_f
        return nil if amount <= 0.0
        grp = ents.add_group
        grp.name = name
        face = grp.entities.add_face(pts)
        return nil unless face
        # Push whichever way the face happens to have been born facing.
        face.pushpull(face.normal.dot(dir) >= 0 ? amount : -amount)
        paint!(face, mat)
        grp
      rescue StandardError => e
        puts "[Fence] #{name}: #{e.message}"
        nil
      end

      # An upright square shaft: post or cap. Both are the same box, so both
      # come out of one place.
      def build_shaft(ents, name, x, y, z0, z1, size, mat)
        h = z1.to_f - z0.to_f
        s = size.to_f / 2.0
        return if h <= 0.0 || s <= 0.0
        u, n = @axes
        c = Geom::Point3d.new(x, y, z0)
        pts = [
          c.offset(u, -s).offset(n, -s),
          c.offset(u,  s).offset(n, -s),
          c.offset(u,  s).offset(n,  s),
          c.offset(u, -s).offset(n,  s)
        ]
        solid!(ents, name, pts, Geom::Vector3d.new(0, 0, 1), h, mat)
      end

      # The post, and its cap if the type has one. Both sizes come from
      # fence_math, so the cap can never end up floating or buried.
      def build_post(ents, p, u, n, mat)
        opts  = build_opts
        shaft = fm.post_shaft(p, opts)
        build_shaft(ents, 'Post', p[:x], p[:y], shaft[:z0], shaft[:z1],
                    @post_size, mat) if shaft
        cap = fm.post_cap(p, opts)
        return unless cap
        build_shaft(ents, 'Post Cap', cap[:x], cap[:y], cap[:z0], cap[:z1],
                    cap[:size], mat)
      rescue StandardError => e
        puts "[Fence] post #{p[:i]}: #{e.message}"
      end

      # One bay: its rails first, then whatever fills the space they left.
      # Neither list is worked out here - fence_math hands both of them over
      # already measured, which is why a raked bay needs no special case.
      def build_bay(ents, bay, a, b, u, n, mat)
        opts = build_opts

        fm.bay_rails(bay, opts).each do |r|
          plank!(ents, "Rail #{r[:kind]}", bay, a, b, n, r,
                 @rail_thickness, mat)
        end

        th = @board_thickness.to_f
        return if th <= 0.0
        # Through fm.infill_kind, so the tool cannot drift from the maths on
        # what an infill name means - the first version of this line said
        # 'bars' after fence_math had already renamed it 'spaced', and every
        # iron fence came out labelled as boards.
        kind  = fm.infill_kind(@infill)
        imat  = kind == 'glass' ? glass_material(Sketchup.active_model) : mat
        name  = case kind
                when 'glass'      then 'Glass'
                when 'spaced'     then 'Baluster'
                when 'horizontal' then 'Slat'
                else 'Board'
                end
        fm.bay_infill(bay, opts).each do |piece|
          plank!(ents, name, bay, a, b, n, piece, th, imat)
        end
      rescue StandardError => e
        puts "[Fence] bay #{bay[:i]}: #{e.message}"
      end

      # One flat slab standing on edge: a board, a baluster, a slat, a rail or
      # a sheet of glass. It reads its four corners straight off the piece, so
      # on a raked bay every one of them is a hair different from the last and
      # this code never learns what a slope is.
      def plank!(ents, name, _bay, a, b, n, piece, th, mat)
        t0 = piece[:t0].to_f
        t1 = piece[:t1].to_f
        x0, y0 = fm.point_at(a.x, a.y, b.x, b.y, t0)
        x1, y1 = fm.point_at(a.x, a.y, b.x, b.y, t1)
        zb0 = piece[:z0].to_f
        zt0 = piece[:z0_top].to_f
        zb1 = piece[:z1].to_f
        zt1 = piece[:z1_top].to_f
        return if zt0 - zb0 <= 0.0 || zt1 - zb1 <= 0.0

        half = th.to_f / 2.0
        pts = [
          Geom::Point3d.new(x0, y0, zb0).offset(n, -half),
          Geom::Point3d.new(x1, y1, zb1).offset(n, -half),
          Geom::Point3d.new(x1, y1, zt1).offset(n, -half),
          Geom::Point3d.new(x0, y0, zt0).offset(n, -half)
        ]
        solid!(ents, name, pts, n, th, mat)
      rescue StandardError => e
        puts "[Fence] #{name}: #{e.message}"
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

      # Glass gets its own material, and it is see-through. A glass railing
      # painted the same flat colour as the posts is the reason the first
      # attempt did not look like glass (2026-08-16).
      def glass_material(model)
        mats = model.materials
        m = mats[GLASS_MATERIAL]
        return m if m
        m = mats.add(GLASS_MATERIAL)
        m.color = Sketchup::Color.new(GLASS_COLOR)
        m.alpha = GLASS_ALPHA if m.respond_to?(:alpha=)
        m
      rescue StandardError => e
        puts "[Fence] glass material: #{e.message}"
        nil
      end

      # The colour is part of the NAME (2026-08-16). Looking a material up by a
      # fixed name and handing back whatever was found is the trap this project
      # has fallen into three times: the second fence, in a different colour,
      # silently came out in the first one's. A per-colour name cannot do that.
      def wood_material(model)
        mats = model.materials
        key  = "#{WOOD_MATERIAL}_#{@color.to_s.delete('#')}"
        m = mats[key]
        return m if m
        m = mats.add(key)
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
