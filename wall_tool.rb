# Interior Pro - Wall Tool

module InteriorPro
  class WallTool
    USE_NATIVE_OPENINGS = true

    # ---- CURVED WALLS (2026-08-10) ---------------------------------------
    # Kill switch. Set to false and every wall builds dead straight again,
    # exactly as before, no matter what 'arc_sag' says. Nothing is deleted,
    # so flipping it back to true restores the curves.
    #   InteriorPro::WallTool::USE_CURVED_WALLS = false
    USE_CURVED_WALLS = true unless const_defined?(:USE_CURVED_WALLS, false)

    # How far the middle of the wall is pulled sideways off the straight line
    # between its two ends, in inches, SIGNED: positive = to the LEFT of
    # start -> end. Stored on the wall as 'arc_sag'. One number is enough to
    # rebuild the whole curve, and because the two ends are still plain
    # start/end attributes, every existing tool that moves a wall (move,
    # stretch, the 2D editor drag) keeps working untouched - the bow simply
    # follows the ends.
    #
    # Below this the wall is treated as straight. 1/16" of bow over a whole
    # wall is not a curve, it is noise.
    MIN_ARC_SAG = 0.0625 unless const_defined?(:MIN_ARC_SAG, false)

    # How far a flat facet may sag away from the true curve, in inches.
    CURVE_TOL = 0.125 unless const_defined?(:CURVE_TOL, false)

    # A strip of flat wall left either side of every opening, in inches, so
    # the hole is cut well inside its flat panel and never right on the seam
    # where the curve starts again.
    POCKET_PAD = 1.5 unless const_defined?(:POCKET_PAD, false)

    # Board and Batten: the real 3D strips on the outside of a wall.
    BATTEN_WIDTH   = 1.5  unless const_defined?(:BATTEN_WIDTH, false)
    BATTEN_DEPTH   = 0.75 unless const_defined?(:BATTEN_DEPTH, false)
    BATTEN_SPACING = 16.0 unless const_defined?(:BATTEN_SPACING, false)

    # Horizontal Siding: real lap boards. Each course shows EXPOSURE inches,
    # sticks out DEPTH_BOTTOM at its lower edge and tucks back to DEPTH_TOP at
    # its upper edge - that taper is what throws the shadow line that makes
    # lap siding read as lap siding instead of a flat wall with lines on it.
    HSIDING_EXPOSURE     = 6.0    unless const_defined?(:HSIDING_EXPOSURE, false)
    HSIDING_DEPTH_BOTTOM = 0.75   unless const_defined?(:HSIDING_DEPTH_BOTTOM, false)
    HSIDING_DEPTH_TOP    = 0.125  unless const_defined?(:HSIDING_DEPTH_TOP, false)

    # Corner boards: the vertical trim that closes off the siding at every
    # corner of the house. 3" on each face, standing a little proud of the
    # siding so the boards butt into it instead of running past it.
    SIDING_TRIM_WIDTH = 3.0 unless const_defined?(:SIDING_TRIM_WIDTH, false)
    SIDING_TRIM_DEPTH = 1.0 unless const_defined?(:SIDING_TRIM_DEPTH, false)

    # KILL SWITCH for all 3D siding. Set to false and walls go back to a flat
    # painted/textured face, instantly, with no geometry built at all:
    #   InteriorPro::WallTool.send(:remove_const, :USE_3D_SIDING)
    #   InteriorPro::WallTool::USE_3D_SIDING = false
    USE_3D_SIDING = true unless const_defined?(:USE_3D_SIDING, false)

    # Free-hand drawing (2026-08-12). Until now every wall was thrown onto
    # red or green - whichever was nearer - so an angled wall was impossible
    # to draw by hand. Now the cursor is only PULLED onto a direction when it
    # is genuinely close to one, and is left completely alone otherwise.
    #
    # Red and green get the wider pull, so they still win a tie. Widen or
    # narrow either one in a single line:
    #   InteriorPro::WallTool.send(:remove_const, :DRAW_SNAP_ORTHO_DEG)
    #   InteriorPro::WallTool::DRAW_SNAP_ORTHO_DEG = 10.0
    DRAW_SNAP_ORTHO_DEG = 8.0 unless const_defined?(:DRAW_SNAP_ORTHO_DEG, false)
    DRAW_SNAP_DIAG_DEG  = 5.0 unless const_defined?(:DRAW_SNAP_DIAG_DEG, false)

    # KILL SWITCH for the whole thing: true = the old behaviour, every wall
    # snapped to red or green and nothing else.
    DRAW_SNAP_ORTHO_ONLY = false unless const_defined?(:DRAW_SNAP_ORTHO_ONLY, false)

    # KILL SWITCH: doors and windows follow their wall when it is bowed.
    # False = the old behaviour, where the hole moved onto the arc and the
    # body stayed behind:
    #   InteriorPro::WallTool.send(:remove_const, :RESEAT_OPENINGS_ON_CURVE)
    #   InteriorPro::WallTool::RESEAT_OPENINGS_ON_CURVE = false
    RESEAT_OPENINGS_ON_CURVE = true unless const_defined?(:RESEAT_OPENINGS_ON_CURVE, false)

    # Hard ceiling on how many pieces one wall's siding may be built from.
    # Every piece is a little solid, and SketchUp will fall over long before
    # it runs out of patience. Over this, the wall keeps its flat face.
    MAX_SIDING_PIECES = 260 unless const_defined?(:MAX_SIDING_PIECES, false)

    # Siding on a curved wall is faceted far more coarsely than the wall body
    # itself. The wall needs 1/8" smoothness; the boards riding on it do not,
    # and at 1/8" a curved wall would need hundreds of them.
    SIDING_CURVE_TOL = 1.5 unless const_defined?(:SIDING_CURVE_TOL, false)

    # All siding lives in ONE sub-group inside the wall.
    #
    # This is what stopped SketchUp crashing (2026-08-11). Drawing a board
    # directly into the wall group puts its back edge ON the wall's own face,
    # which splits that face. Do that a few hundred times and SketchUp is
    # re-solving one face against hundreds of cuts, over and over, inside a
    # single operation - and it falls over. In its own group the siding never
    # touches the wall's geometry at all: no splitting, no re-solving, and
    # the whole lot can be painted and thrown away in one go.
    SIDING_GROUP_NAME = 'InteriorPro_Siding' unless const_defined?(:SIDING_GROUP_NAME, false)

    # A curved wall is really many flat panels side by side, so SketchUp draws
    # a seam line between every pair. Any seam whose two panels differ by less
    # than this angle is softened away, and the wall reads as one smooth
    # surface. Bigger than this is a real corner (the wall's own end) and stays
    # visible. Degrees.
    CURVE_SMOOTH_MAX_ANGLE = 60.0 unless const_defined?(:CURVE_SMOOTH_MAX_ANGLE, false)

    # Two walls that meet almost in line have no real corner to cut. Mitering
    # them anyway sends the cut racing off to where their two faces finally
    # cross - miles away - and the wall end blows out into a long spike.
    # A near half-circle arch does exactly this: its tangent at the spring
    # point runs straight down, the same way as the wall it springs from.
    # Under this many degrees of turn, both ends are simply squared off.
    COLLINEAR_CORNER_DEG = 3.0 unless const_defined?(:COLLINEAR_CORNER_DEG, false)

    # How far a corner's miter points may sit from the two wall ends, as a
    # multiple of the walls' COMBINED thickness, before a corner with a curve
    # in it gives up on the miter and squares both ends off instead. A right
    # angle reaches about 0.7 of the summed thickness and 45 degrees about
    # 1.2; shallower than ~30 degrees the reach explodes (the user's model:
    # 22" and 64" on 5" walls - the wall looked torn in 2D, and the same
    # stored corners broke the 3D build). Straight-to-straight corners never
    # come through this check.
    CURVE_MITER_REACH = 1.5 unless const_defined?(:CURVE_MITER_REACH, false)

    attr_accessor :height, :thickness, :exterior_material, :interior_material, :wall_type_name, :anchor, :wall_category, :side_a_color, :side_b_color

    # Set by the 3-click Arc tool before it calls create_wall. nil / 0 means
    # the ordinary straight wall, so the plain Wall tool is unaffected.
    attr_accessor :arc_sag

    def initialize
      @start_point = nil
      @end_point = nil
      @height = 96.0
      @thickness = 6.0
      @exterior_material = 'Stucco'
      @interior_material = 'Gypsum'
      @side_a_color = '#ffffff'
      @side_b_color = '#ffffff'
      @wall_type_name = 'Default'
      @anchor = 'bottom-center'
      @wall_category = 'exterior'
      @drawing = false
      @locked_axis = nil
      @locked_dir = nil
      @auto_snap = nil
      @raw_point = nil
      @length_input = ''
      @ip = nil
      @preview_group = nil
    end

    def activate
      @ip = Sketchup::InputPoint.new
      Sketchup.set_status_text('Click to start drawing a wall. Press Escape to cancel.', SB_PROMPT)
      view = Sketchup.active_model.active_view
      view.invalidate
    end

    def deactivate(view)
      clear_preview
      view.invalidate
    end

    def draw(view)
      @ip.draw(view) if @ip && @ip.display?
      return unless @drawing && @start_point && @locked_axis

      case @locked_axis
      when :x
        view.drawing_color = Sketchup::Color.new(255, 0, 0)
        p1 = Geom::Point3d.new(@start_point.x - 10000, @start_point.y, @start_point.z)
        p2 = Geom::Point3d.new(@start_point.x + 10000, @start_point.y, @start_point.z)
      when :diag
        # SketchUp's own colour for "on a line, but not on an axis".
        ux, uy = @locked_dir
        return if ux.nil?
        view.drawing_color = Sketchup::Color.new(255, 0, 255)
        p1 = Geom::Point3d.new(@start_point.x - ux * 10000, @start_point.y - uy * 10000, @start_point.z)
        p2 = Geom::Point3d.new(@start_point.x + ux * 10000, @start_point.y + uy * 10000, @start_point.z)
      else
        view.drawing_color = Sketchup::Color.new(0, 200, 0)
        p1 = Geom::Point3d.new(@start_point.x, @start_point.y - 10000, @start_point.z)
        p2 = Geom::Point3d.new(@start_point.x, @start_point.y + 10000, @start_point.z)
      end
      view.line_width = 1
      view.line_stipple = '_'
      view.draw(GL_LINES, [p1, p2])
      view.line_stipple = ''
    end

    def compute_wall_points
      return nil unless @start_point && @end_point
      dx = @end_point.x - @start_point.x
      dy = @end_point.y - @start_point.y
      len = Math.sqrt(dx**2 + dy**2)
      return nil if len < 0.1

      nx = -dy / len * @thickness / 2
      ny = dx / len * @thickness / 2

      if @anchor == 'center'
        v_anchor = 'center'
        h_anchor = 'center'
      else
        parts = @anchor.split('-')
        v_anchor = parts[0]
        h_anchor = parts[1] || 'center'
      end

      base = active_base
      case v_anchor
      when 'top'
        z1 = base - @height
        z2 = base
      when 'center'
        z1 = base - @height / 2.0
        z2 = base + @height / 2.0
      else
        z1 = base
        z2 = base + @height
      end

      case h_anchor
      when 'left'
        b1 = Geom::Point3d.new(@start_point.x, @start_point.y, z1)
        b2 = Geom::Point3d.new(@end_point.x, @end_point.y, z1)
        b3 = Geom::Point3d.new(@end_point.x + nx * 2, @end_point.y + ny * 2, z1)
        b4 = Geom::Point3d.new(@start_point.x + nx * 2, @start_point.y + ny * 2, z1)
      when 'right'
        b1 = Geom::Point3d.new(@start_point.x - nx * 2, @start_point.y - ny * 2, z1)
        b2 = Geom::Point3d.new(@end_point.x - nx * 2, @end_point.y - ny * 2, z1)
        b3 = Geom::Point3d.new(@end_point.x, @end_point.y, z1)
        b4 = Geom::Point3d.new(@start_point.x, @start_point.y, z1)
      else
        b1 = Geom::Point3d.new(@start_point.x + nx, @start_point.y + ny, z1)
        b2 = Geom::Point3d.new(@end_point.x + nx, @end_point.y + ny, z1)
        b3 = Geom::Point3d.new(@end_point.x - nx, @end_point.y - ny, z1)
        b4 = Geom::Point3d.new(@start_point.x - nx, @start_point.y - ny, z1)
      end

      { b: [b1, b2, b3, b4], z1: z1, z2: z2 }
    end

    def preview_material
      model = Sketchup.active_model
      mat = model.materials['InteriorPro_Preview']
      unless mat
        mat = model.materials.add('InteriorPro_Preview')
        mat.color = Sketchup::Color.new(200, 200, 200, 80)
      end
      mat.alpha = 0.5
      mat
    end

    def create_preview
      return unless @drawing
      pts = compute_wall_points
      return unless pts

      model = Sketchup.active_model
      model.start_operation('Preview Wall', true, false, true)
      begin
        @preview_group = model.active_entities.add_group
        @preview_group.set_attribute('InteriorPro', 'type', 'wall_preview')
        @preview_group.layer = Sketchup.active_model.layers['Untagged'] rescue nil
        ents = @preview_group.entities
        face = ents.add_face(*pts[:b])
        height = pts[:z2] - pts[:z1]
        dir = face.normal.z >= 0 ? 1 : -1
        face.pushpull(height * dir)
        @preview_group.material = preview_material
        model.commit_operation
      rescue => e
        model.abort_operation
        @preview_group = nil
        puts "[WallTool.create_preview] error: #{e.message}"
      end
    end

    def clear_preview
      return unless @preview_group && @preview_group.valid?
      model = Sketchup.active_model
      model.start_operation('Clear Preview', true, false, true)
      @preview_group.erase!
      model.commit_operation
      @preview_group = nil
    end

    def onMouseMove(flags, x, y, view)
      @preview_group.hidden = true if @preview_group && @preview_group.valid?
      @ip.pick(view, x, y)
      @preview_group.hidden = false if @preview_group && @preview_group.valid?
      if @drawing
        raw = raw_cursor_position(view, x, y)
        @raw_point = raw if raw          # what the cursor really points at
        pt = pick_point(view, x, y)
        pt = snap_start_to_wall_centerline(pt)
        if @auto_snap == :manual
          @end_point = snap_to_axis(pt)
        elsif snapped_to_geometry?
          detect_auto_snap(raw) if raw
          @end_point = snap_to_axis(pt)
        else
          detect_auto_snap(raw) if raw
          @end_point = snap_to_axis(pt)
        end
        clear_preview
        create_preview
      end
      view.invalidate
    end

    def snapped_to_geometry?
      !@ip.vertex.nil? || !@ip.edge.nil?
    end

    # Active-level working plane (2026-08-03): drawing happens AT the
    # active level's base height — preview, clicks, axis snapping and
    # typed lengths all live on that plane. Level 1 => base 0, exactly
    # the old behavior.
    def active_base
      return 0.0 unless defined?(InteriorPro::LevelManager)
      InteriorPro::LevelManager.level_base(InteriorPro::LevelManager.active_level)
    rescue StandardError
      0.0
    end

    # Cursor point for drawing: a snap to real geometry keeps its x/y;
    # a free point (ground-plane inference) is re-projected onto the
    # active level's plane, so the wall starts where the cursor VISUALLY
    # sits on that level — not on the ground far behind it.
    def pick_point(view, x, y)
      pt = @ip.position
      base = active_base
      return Geom::Point3d.new(pt.x, pt.y, base) if snapped_to_geometry? || (pt.z - base).abs < 0.5
      ray = view.pickray(x, y)
      hit = Geom.intersect_line_plane(ray, [Geom::Point3d.new(0, 0, base), Geom::Vector3d.new(0, 0, 1)])
      hit ? Geom::Point3d.new(hit.x, hit.y, base) : Geom::Point3d.new(pt.x, pt.y, base)
    end

    def onLButtonDown(flags, x, y, view)
      @preview_group.hidden = true if @preview_group && @preview_group.valid?
      @ip.pick(view, x, y)
      @preview_group.hidden = false if @preview_group && @preview_group.valid?
      if !@drawing
        pt = pick_point(view, x, y)
        sp = snap_start_to_wall_centerline(pt)
        @start_point = Geom::Point3d.new(sp.x, sp.y, active_base)
        @drawing = true
        @length_input = ''
        Sketchup.set_status_text('Click endpoint. Double-click or Escape to finish.', SB_PROMPT)
      else
        # ALWAYS use preview result
        pt = @end_point

        # Safety: if somehow nil, fallback once
        if pt.nil?
          raw = raw_cursor_position(view, x, y)
          pt_input = pick_point(view, x, y)
          detect_auto_snap(raw) if raw
          pt = snap_to_axis(pt_input)
        end

        @end_point = pt
        create_wall
        @start_point = @end_point
        @length_input = ''
      end
    end

    def onLButtonDoubleClick(flags, x, y, view)
      finish_drawing
    end

    def onKeyDown(key, repeat, flags, view)
      if key == 27
        finish_drawing
        return
      end
      if InteriorPro::WallTool.shift_key?(key) && @drawing && @start_point
        # Lock the axis the CURSOR is pointing at, not the one the preview
        # already snapped to (2026-08-10). @end_point has been flattened by
        # snap_to_axis, so when the auto-snap had guessed horizontal its dy
        # was already 0 and Shift could only ever re-confirm horizontal -
        # drawing downward and pressing Shift threw the wall sideways.
        ref = @raw_point || @end_point
        axis = ref ? InteriorPro::WallTool.axis_lock(ref.x - @start_point.x,
                                                     ref.y - @start_point.y) : nil
        return if axis.nil?
        @locked_axis = axis
        @locked_dir = nil
        @auto_snap = :manual
        Sketchup.set_status_text('Direction locked (hold Shift).', SB_PROMPT)
        view.invalidate
        return
      end

      return unless @drawing && @start_point

      if key >= 48 && key <= 57
        @length_input += (key - 48).to_s
        Sketchup.set_status_text("Length: #{@length_input}", SB_PROMPT)
        view.vcb_value = @length_input
      elsif key == 190 || key == 110 || key == 46
        @length_input += '.' unless @length_input.include?('.')
        Sketchup.set_status_text("Length: #{@length_input}", SB_PROMPT)
        view.vcb_value = @length_input
      elsif key == 222 || key == 39
        @length_input += "'"
        Sketchup.set_status_text("Length: #{@length_input}", SB_PROMPT)
        view.vcb_value = @length_input
      elsif key == 186 || key == 34
        @length_input += '"'
        Sketchup.set_status_text("Length: #{@length_input}", SB_PROMPT)
        view.vcb_value = @length_input
      elsif key == 8
        @length_input = @length_input[0...-1] if @length_input.length > 0
        Sketchup.set_status_text("Length: #{@length_input}", SB_PROMPT)
        view.vcb_value = @length_input
      elsif key == 13
        apply_length_input if @length_input.length > 0
      end
    end

    def apply_length_input
      return unless @start_point && @end_point
      length = @length_input.to_l
      @length_input = ''
      return if length <= 0
      dx = @end_point.x - @start_point.x
      dy = @end_point.y - @start_point.y
      cur_len = Math.sqrt(dx**2 + dy**2)
      return if cur_len < 0.001
      new_x = @start_point.x + dx / cur_len * length
      new_y = @start_point.y + dy / cur_len * length
      @end_point = Geom::Point3d.new(new_x, new_y, active_base)
      create_wall
      @start_point = @end_point
      Sketchup.set_status_text('Click endpoint. Double-click or Escape to finish.', SB_PROMPT)
    end

    def onKeyUp(key, repeat, flags, view)
      if InteriorPro::WallTool.shift_key?(key)
        @locked_axis = nil
        @locked_dir = nil
        @auto_snap = nil
        view.invalidate
      end
    end

    # Shift does NOT arrive with the same key code on both platforms.
    # onKeyDown reports 16 on Windows, but on the Mac it reports
    # CONSTRAIN_MODIFIER_KEY - which is the macOS Shift MASK, 131072
    # (verified on the user's SketchUp 2026, 2026-08-10). Hard-coding 16
    # meant the direction lock never fired on the Mac at all: the wall just
    # kept following the auto-guess, which is exactly the "Shift throws it
    # sideways" report. Compare against the constant, never the number, so
    # this keeps working if the value changes. The PC is unaffected -
    # there CONSTRAIN_MODIFIER_KEY == 16 already.
    def self.shift_key?(key)
      return true if key == 16
      defined?(CONSTRAIN_MODIFIER_KEY) && key == CONSTRAIN_MODIFIER_KEY
    end

    # Which axis a direction lock should take. Pure, so it is testable:
    # :x when the run is mostly sideways, :y when mostly up/down, nil when
    # there is no direction yet.
    def self.axis_lock(dx, dy)
      return nil if dx.abs < 0.001 && dy.abs < 0.001
      dx.abs > dy.abs ? :x : :y
    end

    # PURE: which direction the free hand should be pulled onto, if any.
    #
    #   :x                -> red      :y                -> green
    #   [:diag, ux, uy]   -> a 45     nil               -> leave it alone
    #
    # Red and green are tested FIRST and with the wider window, so on a tie
    # they win. Outside both windows nothing is snapped and the wall goes
    # exactly where the mouse is - which is the whole point (2026-08-12:
    # "there should be more options... and it must not limit me").
    def self.direction_snap(dx, dy,
                            ortho_deg = DRAW_SNAP_ORTHO_DEG,
                            diag_deg  = DRAW_SNAP_DIAG_DEG)
      dx = dx.to_f
      dy = dy.to_f
      return nil if Math.sqrt(dx * dx + dy * dy) < 0.1

      ang = Math.atan2(dy, dx) * 180.0 / Math::PI

      # red / green
      [0.0, 90.0, 180.0, -90.0].each do |cand|
        next unless angle_gap(ang, cand) <= ortho_deg.to_f
        return (cand.abs == 90.0 ? :y : :x)
      end
      return nil if DRAW_SNAP_ORTHO_ONLY

      # the four 45s
      [45.0, 135.0, -135.0, -45.0].each do |cand|
        next unless angle_gap(ang, cand) <= diag_deg.to_f
        r = cand * Math::PI / 180.0
        return [:diag, Math.cos(r), Math.sin(r)]
      end
      nil
    end

    # PURE: the smaller of the two ways round between two headings, degrees.
    def self.angle_gap(a, b)
      d = (a.to_f - b.to_f) % 360.0
      d -= 360.0 if d > 180.0
      d.abs
    end

    def detect_auto_snap(pt)
      return unless @start_point
      dir = InteriorPro::WallTool.direction_snap(pt.x - @start_point.x,
                                                 pt.y - @start_point.y)
      if dir.nil?
        # Not near anything: free hand. The old code could never land here -
        # it always picked the nearer axis - and that is what made an angled
        # wall impossible to draw.
        @locked_axis = nil
        @locked_dir = nil
        @auto_snap = nil
      elsif dir.is_a?(Array)
        @locked_axis = :diag
        @locked_dir = [dir[1], dir[2]]
        @auto_snap = :auto
      else
        @locked_axis = dir
        @locked_dir = nil
        @auto_snap = :auto
      end
    end

    def snap_to_axis(pt)
      base = active_base
      return Geom::Point3d.new(pt.x, pt.y, base) unless @drawing && @start_point
      case @locked_axis
      when :x
        Geom::Point3d.new(pt.x, @start_point.y, base)
      when :y
        Geom::Point3d.new(@start_point.x, pt.y, base)
      when :diag
        ux, uy = @locked_dir
        return Geom::Point3d.new(pt.x, pt.y, base) if ux.nil?
        # slide along the 45, as far as the cursor has gone down it
        d = (pt.x - @start_point.x) * ux + (pt.y - @start_point.y) * uy
        Geom::Point3d.new(@start_point.x + ux * d, @start_point.y + uy * d, base)
      else
        Geom::Point3d.new(pt.x, pt.y, base)
      end
    end

    # Cursor position from the screen pickray, ignoring all geometry inference.
    # Used so the user's screen-direction (not the inferred snap target) drives
    # axis detection while drawing — fixes axis lock being hijacked when the
    # cursor passes over previous wall edges.
    def raw_cursor_position(view, x, y)
      ray = view.pickray(x, y)
      Geom.intersect_line_plane(ray, [Geom::Point3d.new(0, 0, active_base), Geom::Vector3d.new(0, 0, 1)])
    end

    def snap_start_to_wall_centerline(pt)
      best = nil
      best_d = 1000000.0 # inches - distance from projection to logical endpoint
      perp_tol = 15.0 # inches - max perpendicular distance from logical line
      flat = Geom::Point3d.new(pt.x, pt.y, 0.0)
      Sketchup.active_model.active_entities.grep(Sketchup::Group).each do |g|
        next unless g.valid?
        next unless g.get_attribute('InteriorPro', 'type') == 'wall'
        sx = g.get_attribute('InteriorPro', 'start_x')
        sy = g.get_attribute('InteriorPro', 'start_y')
        ex = g.get_attribute('InteriorPro', 'end_x')
        ey = g.get_attribute('InteriorPro', 'end_y')
        next unless sx && sy && ex && ey
        sp = Geom::Point3d.new(sx, sy, 0)
        ep = Geom::Point3d.new(ex, ey, 0)
        line_vec = ep - sp
        seg_len = line_vec.length
        next if seg_len < 0.001
        line_vec.normalize!
        thickness = g.get_attribute('InteriorPro', 'thickness').to_f
        tol = (thickness / 2.0) + 0.5

        # Cross-category (butt model, 2026-07-16): an interior wall starting
        # on an exterior wall (or vice versa) snaps to the NEAREST FACE of
        # that wall at the cursor position — not to its endpoints — so the
        # new wall begins exactly at the face and never inside the body.
        my_cat = (@wall_category || 'exterior').to_s
        g_cat  = (g.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s
        if g_cat != my_cat
          n_hat = Geom::Vector3d.new(-line_vec.y, line_vec.x, 0)
          ha = (g.get_attribute('InteriorPro', 'anchor') || 'bottom-center').to_s
          ha = ha == 'center' ? 'center' : (ha.split('-')[1] || 'center')
          face_offs = case ha
                      when 'left'  then [0.0, thickness]
                      when 'right' then [0.0, -thickness]
                      else [-thickness / 2.0, thickness / 2.0]
                      end
          face_offs.each do |o|
            base = sp.offset(n_hat, o)
            tt = (flat - base).dot(line_vec)
            tt = 0.0 if tt < 0.0
            tt = seg_len if tt > seg_len
            fp = base.offset(line_vec, tt)
            d = flat.distance(fp)
            if d < tol && d < best_d
              best_d = d
              best = fp
            end
          end
          next
        end

        # Same category: legacy endpoint snap (feeds the corner miter).
        to_pt = flat - sp
        t = to_pt.dot(line_vec)
        proj = sp.offset(line_vec, t)
        perp_d = flat.distance(proj)
        next if perp_d > perp_tol
        d_start = proj.distance(sp)
        d_end = proj.distance(ep)
        if d_start < tol && d_start < best_d
          best_d = d_start
          best = sp
        end
        if d_end < tol && d_end < best_d
          best_d = d_end
          best = ep
        end
      end
      best || pt
    end

    def create_wall
      return unless @start_point && @end_point
      return if @start_point.distance(@end_point) < 0.1

      clear_preview

      model = Sketchup.active_model
      model.start_operation('Create Wall', true)

      attrs = current_attrs
      Sketchup.set_status_text("anchor=#{@anchor} t=#{@thickness} h=#{@height}", SB_PROMPT)

      group = build_wall_group(@start_point, @end_point, attrs, model)
      # Active level (2026-08-03): the new wall lands on the level the user
      # is working on — BEFORE join_corners, so miters only see its level.
      if group && defined?(InteriorPro::LevelManager)
        InteriorPro::LevelManager.place_wall_on_active_level!(group)
      end
      # The 3-click Arc tool builds the wall straight first and bends it here,
      # so a curved wall is created by exactly the same path as a straight one
      # (same attributes, same materials, same level). set_wall_sag! resets
      # the ends and joins the corners itself, which is why it replaces the
      # plain join_corners call rather than following it.
      if group && @arc_sag && @arc_sag.to_f.abs >= InteriorPro::WallTool::MIN_ARC_SAG
        InteriorPro::WallTool.set_wall_sag!(group, @arc_sag.to_f, wrap_operation: false)
      elsif group
        join_corners(group, model)
      end

      model.commit_operation

      begin
        InteriorPro::RoomManager.sync_rooms! if group && defined?(InteriorPro::RoomManager)
      rescue StandardError => e
        puts "[Rooms] sync after wall create: #{e.message}"
      end
      # Molding follows new walls automatically (no-op when the model has no
      # molding). Runs AFTER the rooms sync so side selection uses fresh
      # room polygons.
      begin
        InteriorPro::MoldingManager.refresh! if group && defined?(InteriorPro::MoldingManager)
      rescue StandardError => e
        puts "[Molding] refresh after wall create: #{e.message}"
      end
      # Levels (2026-08-04): a wall drawn above level 1 builds/refreshes the
      # structure between the levels automatically (walls rise + subfloor).
      begin
        if group && defined?(InteriorPro::LevelManager) && InteriorPro::LevelManager.active_level > 1
          InteriorPro::LevelManager.ensure_structure_below!
        end
      rescue StandardError => e
        puts "[Levels] structure after wall create: #{e.message}"
      end
      group
    end

    def current_attrs
      {
        thickness: @thickness,
        height: @height,
        anchor: @anchor,
        wall_type: @wall_type_name,
        exterior_material: @exterior_material,
        interior_material: @interior_material,
        side_a_color: @side_a_color,
        side_b_color: @side_b_color,
        wall_category: @wall_category
      }
    end

    # ---- the axis magnet (2026-08-14) ----------------------------------
    #
    # He drew a building at 179.7666 degrees. Every corner was a perfect 90,
    # the label on screen said a round 180, and nothing anywhere said the
    # whole plan was a quarter of a degree off the red and green axes. Two
    # inches of drift over forty-one feet. He only found it much later, by
    # eye, and the floors he built on top of it inherited it.
    #
    # A wall that is very nearly on an axis was meant to be on it. Nobody
    # draws a wall two tenths of a degree off on purpose - 30, 45 and 60 are
    # what people mean, and those are nowhere near this window. So it lands
    # on the axis, at the moment it is built, and the crooked frame never
    # forms in the first place.
    #
    # This sits in build_wall_group because that is the ONE door every wall
    # comes through: the SketchUp wall tool via create_wall, the 3-click arc
    # tool (which calls create_wall), and Apply to Model in the 2D editor,
    # which calls build_wall_group directly. One guard, no gaps.
    #
    # The one thing it must not do is break a corner. If a wall's end is
    # already sitting on another wall's end, moving it would tear that corner
    # open - so a pinned end is left exactly where it is and the OTHER end
    # swings instead. With both ends pinned the wall is left completely
    # alone: the model is already committed to that direction, and one wall
    # cannot be straightened out of a frame on its own. That is what the
    # whole-building rotation is for.
    AXIS_MAGNET_DEG = 1.0 unless const_defined?(:AXIS_MAGNET_DEG, false)
    AXIS_PIN_TOL    = 1.0 unless const_defined?(:AXIS_PIN_TOL, false)   # inches

    # Signed degrees from the nearest quarter turn, folded into -45..45.
    def self.off_axis_deg(dx, dy)
      deg = Math.atan2(dy, dx) * 180.0 / Math::PI
      o = deg % 90.0
      o -= 90.0 if o > 45.0
      o
    end

    # Is this point already sitting on the end of a wall that exists?
    def self.end_is_pinned?(pt, model)
      model.active_entities.grep(Sketchup::Group).each do |g|
        next unless g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall'
        t = g.transformation
        %w[start end].each do |k|
          x = g.get_attribute('InteriorPro', "#{k}_x")
          y = g.get_attribute('InteriorPro', "#{k}_y")
          next unless x && y
          p = Geom::Point3d.new(x.to_f, y.to_f, 0).transform(t)
          dx = p.x - pt.x
          dy = p.y - pt.y
          return true if Math.sqrt(dx * dx + dy * dy) < AXIS_PIN_TOL
        end
      end
      false
    rescue StandardError
      false      # never let the magnet stop a wall from being built
    end

    # Returns [start, end] - either untouched, or with ONE end swung onto the
    # nearest axis. Pure enough to test: give it a model of nil and nothing
    # counts as pinned.
    def self.apply_axis_magnet(start_pt, end_pt, model = nil)
      dx = end_pt.x - start_pt.x
      dy = end_pt.y - start_pt.y
      len = Math.sqrt(dx * dx + dy * dy)
      return [start_pt, end_pt] if len < 0.001

      off = off_axis_deg(dx, dy)
      return [start_pt, end_pt] if off.abs < 1.0e-9        # already exact
      return [start_pt, end_pt] if off.abs > AXIS_MAGNET_DEG

      rad = -off * Math::PI / 180.0
      c = Math.cos(rad)
      s = Math.sin(rad)

      start_pinned = model ? end_is_pinned?(start_pt, model) : false
      end_pinned   = model ? end_is_pinned?(end_pt,   model) : false
      return [start_pt, end_pt] if start_pinned && end_pinned

      if end_pinned
        # swing the START about the pinned end, the other way round
        vx = start_pt.x - end_pt.x
        vy = start_pt.y - end_pt.y
        nsx = end_pt.x + vx * c - vy * s
        nsy = end_pt.y + vx * s + vy * c
        [Geom::Point3d.new(nsx, nsy, start_pt.z), end_pt]
      else
        nex = start_pt.x + dx * c - dy * s
        ney = start_pt.y + dx * s + dy * c
        [start_pt, Geom::Point3d.new(nex, ney, end_pt.z)]
      end
    end

    def build_wall_group(start_pt, end_pt, attrs, model)
      return nil if start_pt.distance(end_pt) < 0.1

      # Land on the axis before a single number is worked out from these two
      # points, so the attributes, the geometry and the miters all agree.
      start_pt, end_pt =
        InteriorPro::WallTool.apply_axis_magnet(start_pt, end_pt, model)

      dx = end_pt.x - start_pt.x
      dy = end_pt.y - start_pt.y
      len = Math.sqrt(dx**2 + dy**2)
      return nil if len < 0.001

      thickness = attrs[:thickness]
      height = attrs[:height]
      nx = -dy / len * thickness / 2
      ny = dx / len * thickness / 2

      if attrs[:anchor] == 'center'
        v_anchor = 'center'
        h_anchor = 'center'
      else
        parts = attrs[:anchor].split('-')
        v_anchor = parts[0]
        h_anchor = parts[1] || 'center'
      end

      case v_anchor
      when 'top'
        z_offset = -height
      when 'center'
        z_offset = -height / 2.0
      else
        z_offset = 0
      end

      case h_anchor
      when 'left'
        pt1 = Geom::Point3d.new(start_pt.x, start_pt.y, z_offset)
        pt2 = Geom::Point3d.new(end_pt.x, end_pt.y, z_offset)
        pt3 = Geom::Point3d.new(end_pt.x + nx * 2, end_pt.y + ny * 2, z_offset)
        pt4 = Geom::Point3d.new(start_pt.x + nx * 2, start_pt.y + ny * 2, z_offset)
      when 'right'
        pt1 = Geom::Point3d.new(start_pt.x - nx * 2, start_pt.y - ny * 2, z_offset)
        pt2 = Geom::Point3d.new(end_pt.x - nx * 2, end_pt.y - ny * 2, z_offset)
        pt3 = Geom::Point3d.new(end_pt.x, end_pt.y, z_offset)
        pt4 = Geom::Point3d.new(start_pt.x, start_pt.y, z_offset)
      else
        pt1 = Geom::Point3d.new(start_pt.x + nx, start_pt.y + ny, z_offset)
        pt2 = Geom::Point3d.new(end_pt.x + nx, end_pt.y + ny, z_offset)
        pt3 = Geom::Point3d.new(end_pt.x - nx, end_pt.y - ny, z_offset)
        pt4 = Geom::Point3d.new(start_pt.x - nx, start_pt.y - ny, z_offset)
      end

      group = model.active_entities.add_group
      group.name = 'InteriorPro_Wall'
      InteriorPro.assign_tag(group, 'IP/Walls')
      group.set_attribute('InteriorPro', 'type', 'wall')
      group.set_attribute('InteriorPro', 'wall_type', attrs[:wall_type])
      group.set_attribute('InteriorPro', 'height', height)
      group.set_attribute('InteriorPro', 'thickness', thickness)
      group.set_attribute('InteriorPro', 'exterior_material', attrs[:exterior_material])
      group.set_attribute('InteriorPro', 'interior_material', attrs[:interior_material])
      group.set_attribute('InteriorPro', 'side_a_color', attrs[:side_a_color])
      group.set_attribute('InteriorPro', 'side_b_color', attrs[:side_b_color])
      group.set_attribute('InteriorPro', 'anchor', attrs[:anchor])
      group.set_attribute('InteriorPro', 'start_x', start_pt.x.to_f)
      group.set_attribute('InteriorPro', 'start_y', start_pt.y.to_f)
      group.set_attribute('InteriorPro', 'end_x', end_pt.x.to_f)
      group.set_attribute('InteriorPro', 'end_y', end_pt.y.to_f)

      length_in = len.to_f
      gross_area_sqft = (length_in * height.to_f) / 144.0
      volume_cuft = (length_in * height.to_f * thickness.to_f) / 1728.0
      group.set_attribute('InteriorPro', 'id', generate_wall_id)
      group.set_attribute('InteriorPro', 'mark', '')
      group.set_attribute('InteriorPro', 'length_in', length_in)
      group.set_attribute('InteriorPro', 'gross_area_sqft', gross_area_sqft)
      group.set_attribute('InteriorPro', 'volume_cuft', volume_cuft)
      group.set_attribute('InteriorPro', 'wall_category', @wall_category)
      group.set_attribute('InteriorPro', 'created_at', Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
      group.set_attribute('InteriorPro', 'plugin_version', '0.1')

      w_ents = group.entities
      pts = [pt1, pt2, pt3, pt4].uniq { |p| [p.x.round(4), p.y.round(4), p.z.round(4)] }
      if pts.length < 3
        group.erase!
        return nil
      end
      face = w_ents.add_face(pts)
      unless face
        group.erase!
        return nil
      end
      face.pushpull(-height)
      # Paint with the SAME painter every rebuild uses (fixed 2026-07-18):
      # the old apply_materials painted the base face, so a wall only looked
      # right after a corner rebuild — a standalone wall (or a collinear
      # split piece, which never miters) stayed white.
      if attrs[:wall_category] == 'interior'
        paint_wall_long_faces!(group, attrs[:side_a_color], attrs[:side_b_color])
      else
        paint_wall_long_faces!(group, attrs[:exterior_material], attrs[:interior_material])
      end

      perp_corners = perpendicular_corners_xy(start_pt, end_pt, thickness, h_anchor)
      save_corners_attr(group, perp_corners) if perp_corners

      add_exterior_siding(group, attrs[:exterior_material])

      group
    end

    def apply_materials(face, exterior_material, interior_material)
      mats = Sketchup.active_model.materials
      ext_mat = load_or_create_material(exterior_material)
      int_mat = load_or_create_material(interior_material)
      face.material = int_mat
      face.back_material = ext_mat
    end

    def load_or_create_material(name)
      mats = Sketchup.active_model.materials
      mat = mats[name]
      return mat if mat
      mat = mats.add(name)
      if name.start_with?('#')
        # Hex color (e.g. '#ffffff') — flat color material
        mat.color = Sketchup::Color.new(name)
      else
        # Named material — try to load texture from textures folder
        plugin_dir = File.dirname(__FILE__)
        texture_file = File.join(plugin_dir, 'textures', "#{name.downcase.gsub(' ', '_')}.jpg")
        if File.exist?(texture_file)
          mat.texture = texture_file
          mat.texture.size = 48 if mat.texture # 48 inches = 4 feet repeat
        end
      end
      mat
    end

    # Adds vertical batten boxes to the exterior face of a wall group.
    # Battens are 1.5" wide along the wall, 0.75" protruding outward, full wall
    # height, centered every 16" along the exterior face length. Painted white.
    # Z range is read from group.bounds so this works for both build paths
    # (build_wall_group extrudes down; build_geometry_in_group extrudes up).
    # The one door into 3D siding. Flat-texture materials fall straight
    # through and nothing is built.
    def add_exterior_siding(group, ext_mat)
      return unless USE_3D_SIDING
      case ext_mat
      when 'Board and Batten' then add_board_and_batten(group)
      when 'Horizontal Siding' then add_horizontal_siding(group)
      end
    rescue StandardError => e
      puts "[WallTool] add_exterior_siding: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    end

    # Real 3D lap siding: a stack of boards up the outside of the wall, each
    # one sticking out at its bottom edge and tucking back at its top, so it
    # throws a shadow line. Boards stop either side of every window and door
    # instead of running across the glass.
    def add_horizontal_siding(group)
      return unless group&.valid?

      poly = InteriorPro::WallTool.exterior_face_polyline(group, SIDING_CURVE_TOL)
      return if poly.nil? || poly.length < 2

      # Painted siding: white by default, like the trim.
      board_mat = load_or_create_material('#ffffff')
      if InteriorPro::WallTool.curved_wall?(group)
        paint_curved_exterior_white!(group, board_mat)
      else
        u = [poly[1][0] - poly[0][0], poly[1][1] - poly[0][1]]
        ul = Math.sqrt(u[0]**2 + u[1]**2)
        return if ul < 0.001
        outward = Geom::Vector3d.new(u[1] / ul, -u[0] / ul, 0)
        group.entities.grep(Sketchup::Face).each do |f|
          n = f.normal
          next if n.z.abs > 0.5
          next if n.dot(outward) < 0.5
          f.material = board_mat
          f.back_material = nil
        end
      end

      z_min = group.bounds.min.z
      z_max = group.bounds.max.z
      return if (z_max - z_min) < 0.5

      total_t = poly.last[2]
      openings = InteriorPro::WallTool.read_door_openings(group)
      trim_on, trim_w = InteriorPro::WallTool.corner_trim_settings(group)
      inset = trim_on ? InteriorPro::WallTool.trim_inset(total_t, trim_w) : 0.0
      ext0 = InteriorPro::WallTool.wall_end_neighbor?(group, :start) ? SIDING_TRIM_DEPTH : 0.0
      ext1 = InteriorPro::WallTool.wall_end_neighbor?(group, :end) ? SIDING_TRIM_DEPTH : 0.0
      courses = InteriorPro::WallTool.siding_courses(z_min, z_max, HSIDING_EXPOSURE)

      # Work out the cost BEFORE building anything. A wall that would need
      # more pieces than SketchUp can comfortably hold keeps its flat face
      # instead of taking the whole model down with it.
      runs = []
      courses.each do |z0, z1|
        InteriorPro::WallTool.clear_t_intervals(total_t, openings, z0, z1, z_min, inset).each do |ta, tb|
          r = InteriorPro::WallTool.polyline_between(poly, ta, tb)
          runs << [r, z0, z1] if r && r.length >= 2
        end
      end
      pieces = runs.sum { |r, _z0, _z1| r.length - 1 }
      trim_runs = trim_on ? InteriorPro::WallTool.corner_trim_runs(poly, total_t, trim_w, ext0, ext1) : []
      pieces += trim_runs.sum { |r| r.length - 1 }
      if pieces > MAX_SIDING_PIECES
        puts "[WallTool] siding skipped: this wall would need #{pieces} boards (limit #{MAX_SIDING_PIECES}). The flat face is kept."
        return
      end

      sub = siding_group(group)
      return unless sub

      begin
        runs.each do |run, z0, z1|
          run.each_cons(2) do |a, b|
            build_siding_board!(sub, a, b, z0, z1,
                                HSIDING_DEPTH_BOTTOM, HSIDING_DEPTH_TOP)
          end
        end
        trim_runs.each do |run|
          run.each_cons(2) do |a, b|
            build_siding_board!(sub, a, b, z_min, z_max,
                                SIDING_TRIM_DEPTH, SIDING_TRIM_DEPTH)
          end
        end
      rescue StandardError => e
        puts "[WallTool] siding build failed, removing it: #{e.message}"
        sub.erase! if sub.valid?
        return
      end

      # One material on the whole sub-group - no face-by-face painting at all.
      if sub.valid? && sub.entities.length.zero?
        sub.erase!
      elsif sub.valid?
        sub.material = board_mat
      end
    end

    # A clean, empty sub-group to build this wall's siding in. Any previous
    # one is thrown away first, so a rebuild never stacks siding on siding.
    def siding_group(group)
      group.entities.grep(Sketchup::Group).each do |g|
        g.erase! if g.valid? && g.name == SIDING_GROUP_NAME
      end
      sub = group.entities.add_group
      sub.name = SIDING_GROUP_NAME
      sub
    rescue StandardError => e
      puts "[WallTool] siding_group: #{e.message}"
      nil
    end

    # Paint whatever has no material yet. Used once, after all the siding is
    # built, so nothing has to diff the face list per board.
    def paint_unpainted_faces!(group, mat)
      return unless group&.valid? && mat
      group.entities.grep(Sketchup::Face).each do |f|
        next unless f.valid?
        f.material = mat if f.material.nil?
        f.back_material = mat if f.back_material.nil? && f.material == mat
      end
    rescue StandardError => e
      puts "[WallTool] paint_unpainted_faces!: #{e.message}"
    end

    # The vertical corner boards at both ends of the wall. Where two walls
    # meet, each contributes one, so the corner reads as a 3"-per-face trim -
    # the way siding is actually finished.
    def add_corner_trim(holder, poly, total_t, z_min, z_max)
      InteriorPro::WallTool.corner_trim_runs(poly, total_t).each do |run|
        run.each_cons(2) do |a, b|
          build_siding_board!(holder, a, b, z_min, z_max,
                              SIDING_TRIM_DEPTH, SIDING_TRIM_DEPTH)
        end
      end
    end

    # The two stretches of wall the corner boards cover. ext_start/ext_end
    # push the board PAST the wall end - by the trim depth - so the two boards
    # meeting at a corner overlap into one closed 90-degree L instead of two
    # separate planks with a notch between them (user photo, 2026-08-11).
    # A free end (no neighbour) gets no extension and stays flush.
    def self.corner_trim_runs(poly, total_t, w = SIDING_TRIM_WIDTH, ext_start = 0.0, ext_end = 0.0)
      inset = trim_inset(total_t, w)
      return [] if inset <= 0.0
      runs = []
      r0 = polyline_between(poly, 0.0, inset)
      if r0 && r0.length >= 2
        if ext_start > 0.0
          dx = r0[1][0] - r0[0][0]
          dy = r0[1][1] - r0[0][1]
          l = Math.sqrt(dx * dx + dy * dy)
          r0 = [[r0[0][0] - dx / l * ext_start, r0[0][1] - dy / l * ext_start]] + r0 if l > 1e-9
        end
        runs << r0
      end
      r1 = polyline_between(poly, total_t - inset, total_t)
      if r1 && r1.length >= 2
        if ext_end > 0.0
          dx = r1[-1][0] - r1[-2][0]
          dy = r1[-1][1] - r1[-2][1]
          l = Math.sqrt(dx * dx + dy * dy)
          r1 = r1 + [[r1[-1][0] + dx / l * ext_end, r1[-1][1] + dy / l * ext_end]] if l > 1e-9
        end
        runs << r1
      end
      runs
    end

    # Per-wall corner-trim setting, ONE attribute: 'corner_trim_width'.
    #   missing -> the default 3"    0 -> no corner boards    2/3/4... -> that width
    def self.corner_trim_settings(group)
      v = group&.valid? ? group.get_attribute('InteriorPro', 'corner_trim_width') : nil
      return [true, SIDING_TRIM_WIDTH] if v.nil?
      w = v.to_f
      w > 0.0 ? [true, w] : [false, 0.0]
    rescue StandardError
      [true, SIDING_TRIM_WIDTH]
    end

    # PURE: how wide the corner board may be on this wall. A wall too short
    # to carry two of them plus something in between gets none at all.
    def self.trim_inset(total_t, w = SIDING_TRIM_WIDTH)
      w = w.to_f
      return 0.0 if w <= 0.0
      return 0.0 if total_t.to_f < (w * 2.0) + 6.0
      w
    end

    # Does another wall end at this wall's start/end point? Decides whether a
    # corner board should wrap round the corner (there is a neighbour to meet)
    # or stop flush at the end (a free-standing wall end).
    def self.wall_end_neighbor?(group, side)
      return false unless group&.valid?
      key = side == :start ? %w[start_x start_y] : %w[end_x end_y]
      px = group.get_attribute('InteriorPro', key[0]).to_f
      py = group.get_attribute('InteriorPro', key[1]).to_f
      Sketchup.active_model.entities.grep(Sketchup::Group).any? do |g|
        next false if g == group
        next false unless g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall'
        [%w[start_x start_y], %w[end_x end_y]].any? do |kx, ky|
          qx = g.get_attribute('InteriorPro', kx)
          qy = g.get_attribute('InteriorPro', ky)
          qx && qy && Math.sqrt((qx.to_f - px)**2 + (qy.to_f - py)**2) < 1.5
        end
      end
    rescue StandardError
      false
    end

    # One straight piece of one lap board, between two points on the wall's
    # outside face. Built as its end profile, then pushed along the wall.
    def build_siding_board!(holder, a, b, z0, z1,
                            depth_bottom = HSIDING_DEPTH_BOTTOM,
                            depth_top = HSIDING_DEPTH_TOP)
      dx = b[0] - a[0]
      dy = b[1] - a[1]
      len = Math.sqrt(dx * dx + dy * dy)
      return if len < 0.05
      ux = dx / len
      uy = dy / len
      nx = uy       # outward = right of travel along the exterior face
      ny = -ux

      profile = [
        Geom::Point3d.new(a[0], a[1], z0),
        Geom::Point3d.new(a[0] + nx * depth_bottom, a[1] + ny * depth_bottom, z0),
        Geom::Point3d.new(a[0] + nx * depth_top, a[1] + ny * depth_top, z1),
        Geom::Point3d.new(a[0], a[1], z1)
      ]

      face = begin
        holder.entities.add_face(profile)
      rescue StandardError
        nil
      end
      return unless face && face.valid?

      along = Geom::Vector3d.new(ux, uy, 0)
      sign = face.normal.dot(along) >= 0 ? 1.0 : -1.0
      begin
        face.pushpull(len * sign)
      rescue StandardError => e
        puts "[WallTool] siding board: #{e.message}"
      end
    end

    # PURE: the courses of lap siding up a wall, bottom to top. The last one
    # is trimmed to the top of the wall, and a sliver is dropped.
    def self.siding_courses(z_min, z_max, exposure)
      return [] if exposure <= 0.0
      out = []
      z = z_min.to_f
      while z < z_max - 0.25
        top = [z + exposure, z_max].min
        out << [z, top] if (top - z) > 0.25
        z += exposure
      end
      out
    end

    # PURE: the stretches of wall a board at this height may actually cross -
    # everything except the openings it would run over. Distances along the
    # wall, in inches from the start.
    def self.clear_t_intervals(total_t, openings, z0, z1, floor_z, inset = 0.0)
      lo = inset.to_f
      hi = total_t.to_f - inset.to_f
      return [] if hi - lo < 0.25
      gaps = []
      (openings || []).each do |o|
        next unless o
        ot = (o[:t] || o['t']).to_f
        ow = (o[:width] || o['width']).to_f
        next if ow <= 0.0
        zb = floor_z.to_f + (o[:floor_offset] || o['floor_offset']).to_f
        zt = zb + (o[:height] || o['height']).to_f
        next if zt <= z0 + 1e-9 || zb >= z1 - 1e-9    # this board misses it
        gaps << [ot - (ow / 2.0), ot + (ow / 2.0)]
      end
      return [[lo, hi]] if gaps.empty?

      gaps.sort_by!(&:first)
      out = []
      cursor = lo
      gaps.each do |g0, g1|
        stop = [g0, hi].min
        out << [cursor, stop] if stop - cursor > 0.25
        cursor = [cursor, g1].max
      end
      out << [cursor, hi] if hi - cursor > 0.25
      out
    end

    # The wall's outside face as a list of [x, y, t] - t being how far along
    # the wall (measured on its CENTRE line, the same ruler openings use).
    # A straight wall is two points; a curved one follows its curve.
    def self.exterior_face_polyline(group, tol = CURVE_TOL)
      corners = InteriorPro::WallTool.new.read_corners_attr(group)
      return nil unless corners

      unless curved_wall?(group)
        s_neg = corners[3]
        e_neg = corners[2]
        len = Math.sqrt((e_neg[0] - s_neg[0])**2 + (e_neg[1] - s_neg[1])**2)
        return nil if len < 0.001
        return [[s_neg[0], s_neg[1], 0.0], [e_neg[0], e_neg[1], len]]
      end

      sx = group.get_attribute('InteriorPro', 'start_x').to_f
      sy = group.get_attribute('InteriorPro', 'start_y').to_f
      ex = group.get_attribute('InteriorPro', 'end_x').to_f
      ey = group.get_attribute('InteriorPro', 'end_y').to_f
      thickness = group.get_attribute('InteriorPro', 'thickness').to_f
      anchor = (group.get_attribute('InteriorPro', 'anchor') || 'bottom-center').to_s
      h_anchor = anchor.split('-')[1] || 'center'

      am = InteriorPro::ArcMath
      arc = am.from_chord_and_sag(sx, sy, ex, ey, wall_sag(group))
      return nil unless arc
      _o_pos, o_neg = anchor_side_offsets(thickness, h_anchor)
      face = am.offset(arc, o_neg)
      return nil unless face

      to_center = arc[:r] / face[:r]
      stations = curved_wall_stations(arc, tol, read_door_openings(group))
      return nil unless stations
      stations.map do |t_center|
        d_face = t_center / to_center
        p = am.point_at_distance(face, d_face)
        [p[0], p[1], t_center]
      end
    rescue StandardError => e
      puts "[WallTool] exterior_face_polyline: #{e.message}"
      nil
    end

    # PURE: the piece of a polyline between two distances along it, with the
    # two ends interpolated so a board can stop exactly at a window jamb.
    def self.polyline_between(poly, ta, tb)
      return nil if poly.nil? || poly.length < 2
      ta = ta.to_f
      tb = tb.to_f
      return nil if tb - ta < 0.05
      out = []
      out << point_on_polyline(poly, ta)
      poly.each { |p| out << [p[0], p[1]] if p[2] > ta + 1e-6 && p[2] < tb - 1e-6 }
      out << point_on_polyline(poly, tb)
      out.compact
    end

    def self.point_on_polyline(poly, t)
      return [poly.first[0], poly.first[1]] if t <= poly.first[2]
      return [poly.last[0], poly.last[1]] if t >= poly.last[2]
      poly.each_cons(2) do |a, b|
        next unless t >= a[2] && t <= b[2]
        span = b[2] - a[2]
        f = span < 1e-9 ? 0.0 : (t - a[2]) / span
        return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f]
      end
      [poly.last[0], poly.last[1]]
    end

    def add_board_and_batten(group)
      return unless group&.valid?

      sx = group.get_attribute('InteriorPro', 'start_x')
      sy = group.get_attribute('InteriorPro', 'start_y')
      ex = group.get_attribute('InteriorPro', 'end_x')
      ey = group.get_attribute('InteriorPro', 'end_y')
      return unless sx && sy && ex && ey

      corners = read_corners_attr(group)
      return unless corners

      # Exterior corners (right perpendicular of drawn start->end direction).
      s_neg = corners[3]
      e_neg = corners[2]

      dx = e_neg[0] - s_neg[0]
      dy = e_neg[1] - s_neg[1]
      straight_length = Math.sqrt(dx**2 + dy**2)
      return if straight_length < 0.001

      # Unit vector along the exterior face from s_neg toward e_neg.
      ux = dx / straight_length
      uy = dy / straight_length
      # Outward perpendicular (right of u) = away from wall body.
      rx = uy
      ry = -ux

      # On a CURVED wall the exterior face is not a straight run, so the
      # battens have to walk the curve instead: every one gets its own place
      # and its own direction.
      curved = InteriorPro::WallTool.curved_wall?(group)
      stations = batten_stations(group, s_neg, [ux, uy], [rx, ry], straight_length, curved)
      return if stations.nil? || stations.empty?

      white_mat = load_or_create_material('#ffffff')

      # Paint the wall's exterior long face white BEFORE adding battens, so
      # the boards (wall surface between battens) read as painted siding.
      # Doing this before the loop guarantees the batten snapshot-diff sees
      # the painted wall face as pre-existing and doesn't repaint it.
      if curved
        paint_curved_exterior_white!(group, white_mat)
      else
        outward = Geom::Vector3d.new(rx, ry, 0)
        group.entities.grep(Sketchup::Face).each do |f|
          n = f.normal
          next if n.z.abs > 0.5         # skip top/bottom
          next if n.dot(outward) < 0.5  # skip interior face + end caps
          f.material = white_mat
          f.back_material = nil
        end
      end

      z_min = group.bounds.min.z
      z_max = group.bounds.max.z
      h = z_max - z_min
      return if h < 0.001

      half_width = BATTEN_WIDTH / 2.0
      openings = InteriorPro::WallTool.read_door_openings(group)

      # Board and batten gets the same corner boards as lap siding, and the
      # battens keep clear of them.
      poly = InteriorPro::WallTool.exterior_face_polyline(group, SIDING_CURVE_TOL)
      total_t = poly ? poly.last[2] : 0.0
      trim_on, trim_w = InteriorPro::WallTool.corner_trim_settings(group)
      inset = trim_on ? InteriorPro::WallTool.trim_inset(total_t, trim_w) : 0.0
      ext0 = InteriorPro::WallTool.wall_end_neighbor?(group, :start) ? SIDING_TRIM_DEPTH : 0.0
      ext1 = InteriorPro::WallTool.wall_end_neighbor?(group, :end) ? SIDING_TRIM_DEPTH : 0.0

      # Same ceiling lap siding has: never let one wall's trimmings bury
      # SketchUp. Every band of every batten is one little solid.
      planned = stations.sum do |_c, _u, _r, t|
        next 0 if inset > 0.0 && (t < inset + half_width || t > total_t - inset - half_width)
        InteriorPro::WallTool.batten_z_bands(t, half_width, z_min, z_max, openings, z_min).length
      end
      planned += InteriorPro::WallTool.corner_trim_runs(poly, total_t, trim_w, ext0, ext1).sum { |r| r.length - 1 } if poly && trim_on
      if planned > MAX_SIDING_PIECES
        puts "[WallTool] battens skipped: this wall would need #{planned} pieces (limit #{MAX_SIDING_PIECES}). The flat face is kept."
        return
      end

      sub = siding_group(group)
      return unless sub
      if poly && inset > 0.0
        InteriorPro::WallTool.corner_trim_runs(poly, total_t, trim_w, ext0, ext1).each do |run|
          run.each_cons(2) do |a, b|
            build_siding_board!(sub, a, b, z_min, z_max,
                                SIDING_TRIM_DEPTH, SIDING_TRIM_DEPTH)
          end
        end
      end

      stations.each do |c, u, r, t|
        next if inset > 0.0 && (t < inset + half_width || t > total_t - inset - half_width)
        # A batten must not run straight across a window or a door. Break it
        # into the pieces that miss the opening - a stub above the head, a
        # stub below the sill - exactly like real siding.
        bands = InteriorPro::WallTool.batten_z_bands(t, half_width, z_min, z_max,
                                                     openings, z_min)
        bands.each do |zb, zt|
          band_h = zt - zb
          next if band_h < 0.25

          p1 = Geom::Point3d.new(c[0] - u[0] * half_width, c[1] - u[1] * half_width, zb)
          p2 = Geom::Point3d.new(c[0] + u[0] * half_width, c[1] + u[1] * half_width, zb)
          p3 = Geom::Point3d.new(c[0] + u[0] * half_width + r[0] * BATTEN_DEPTH,
                                 c[1] + u[1] * half_width + r[1] * BATTEN_DEPTH, zb)
          p4 = Geom::Point3d.new(c[0] - u[0] * half_width + r[0] * BATTEN_DEPTH,
                                 c[1] - u[1] * half_width + r[1] * BATTEN_DEPTH, zb)

          face = begin
            sub.entities.add_face(p1, p2, p3, p4)
          rescue StandardError
            nil
          end
          next unless face && face.valid?

          sign = face.normal.z >= 0 ? 1 : -1
          begin
            face.pushpull(band_h * sign)
          rescue StandardError => e
            puts "[WallTool] batten: #{e.message}"
          end
        end
      end

      if sub.valid? && sub.entities.length.zero?
        sub.erase!
      elsif sub.valid?
        sub.material = white_mat
      end
    end

    # PURE: the vertical pieces of ONE batten once the openings it crosses are
    # taken out of it. A batten clear of every opening comes back as one full
    # height piece; one that crosses a window comes back as two stubs.
    # t = how far along the wall this batten stands.
    def self.batten_z_bands(t, half_batten, z_min, z_max, openings, floor_z)
      bands = [[z_min, z_max]]
      (openings || []).each do |o|
        next unless o
        ot = (o[:t] || o['t']).to_f
        ow = (o[:width] || o['width']).to_f
        next if ow <= 0.0
        # Not in front of this opening at all - leave the batten alone.
        next if t < ot - (ow / 2.0) - half_batten
        next if t > ot + (ow / 2.0) + half_batten
        zb = floor_z + (o[:floor_offset] || o['floor_offset']).to_f
        zt = zb + (o[:height] || o['height']).to_f
        next if zt <= zb
        bands = bands.flat_map { |b0, b1| subtract_z_band(b0, b1, zb, zt) }
      end
      bands.select { |b0, b1| (b1 - b0) > 0.25 }
    end

    # PURE: what is left of the run b0..b1 once zb..zt is cut out of it.
    def self.subtract_z_band(b0, b1, zb, zt)
      return [[b0, b1]] if zt <= b0 || zb >= b1
      out = []
      out << [b0, zb] if zb > b0
      out << [zt, b1] if zt < b1
      out
    end

    # Where each batten goes: [centre point, direction along the wall, push
    # outward, distance along the wall], one per batten, evenly spaced along
    # the EXTERIOR face. A straight wall walks a straight line; a curved one
    # walks its curve, so every batten stands square to the wall right where
    # it is.
    def batten_stations(group, s_neg, u, r, straight_length, curved)
      half_width = BATTEN_WIDTH / 2.0

      unless curved
        out = []
        d = BATTEN_SPACING / 2.0
        while d + half_width <= straight_length
          out << [[s_neg[0] + u[0] * d, s_neg[1] + u[1] * d], u, r, d]
          d += BATTEN_SPACING
        end
        return out
      end

      InteriorPro::WallTool.curved_batten_stations(group)
    end

    # Battens on a curved wall, walked along the arc of the EXTERIOR face.
    def self.curved_batten_stations(group)
      sx = group.get_attribute('InteriorPro', 'start_x').to_f
      sy = group.get_attribute('InteriorPro', 'start_y').to_f
      ex = group.get_attribute('InteriorPro', 'end_x').to_f
      ey = group.get_attribute('InteriorPro', 'end_y').to_f
      thickness = group.get_attribute('InteriorPro', 'thickness').to_f
      anchor = (group.get_attribute('InteriorPro', 'anchor') || 'bottom-center').to_s
      h_anchor = anchor.split('-')[1] || 'center'
      sag = wall_sag(group)

      am = InteriorPro::ArcMath
      arc = am.from_chord_and_sag(sx, sy, ex, ey, sag)
      return [] unless arc

      # Exterior = the RIGHT side of start -> end, i.e. the negative offset.
      _o_pos, o_neg = anchor_side_offsets(thickness, h_anchor)
      face = am.offset(arc, o_neg)
      return [] unless face

      total = am.length(face)
      half_width = BATTEN_WIDTH / 2.0
      # Openings are measured along the wall's CENTRE line, battens along its
      # outside face. On a curve those two rulers run at different speeds, so
      # convert before comparing them.
      to_center = arc[:r] / face[:r]
      out = []
      d = BATTEN_SPACING / 2.0
      outward_sign = am.center_side(arc) > 0 ? 1.0 : -1.0
      while d + half_width <= total
        p = am.point_at_distance(face, d)
        t = am.tangent_at_distance(face, d)
        nx = -t[1] * outward_sign
        ny = t[0] * outward_sign
        out << [p, [t[0], t[1]], [nx, ny], d * to_center]
        d += BATTEN_SPACING
      end
      out
    rescue StandardError => e
      puts "[WallTool] curved_batten_stations: #{e.message}"
      []
    end

    # Paint the outward-facing side of a curved wall white, ready for battens.
    def paint_curved_exterior_white!(group, white_mat)
      sx = group.get_attribute('InteriorPro', 'start_x').to_f
      sy = group.get_attribute('InteriorPro', 'start_y').to_f
      ex = group.get_attribute('InteriorPro', 'end_x').to_f
      ey = group.get_attribute('InteriorPro', 'end_y').to_f
      am = InteriorPro::ArcMath
      arc = am.from_chord_and_sag(sx, sy, ex, ey, InteriorPro::WallTool.wall_sag(group))
      return unless arc
      ext_is_outer = am.center_side(arc) > 0
      group.entities.grep(Sketchup::Face).each do |f|
        next unless f.valid?
        n = f.normal
        next if n.z.abs > 0.5
        c = f.bounds.center
        rx = c.x - arc[:cx]
        ry = c.y - arc[:cy]
        len = Math.sqrt(rx * rx + ry * ry)
        next if len < 1e-6
        radial = ((n.x * rx) + (n.y * ry)) / len
        next if radial.abs < 0.5
        next unless (radial > 0) == ext_is_outer
        f.material = white_mat
        f.back_material = nil
      end
    rescue StandardError => e
      puts "[WallTool] paint_curved_exterior_white!: #{e.message}"
    end

    # Miter both ends of a newly-created wall against any existing wall whose
    # centerline endpoint is within tolerance. Geometry of BOTH walls in each
    # corner pair is rebuilt with the computed miter intersections.
    def join_corners(new_group, model, allow_centerline_fallback: false)
      return unless new_group&.valid?
      data = wall_data_world(new_group)
      return unless data

      [:start, :end].each do |side|
        break unless new_group.valid?
        corner = endpoint_pt(data, side)
        other  = find_neighbor_at(corner, new_group, model, allow_centerline_fallback: allow_centerline_fallback)
        # Nothing found within 0.001"? A neighbour a hair further away is a
        # corner the user meant and missed - close it and look again.
        if other.nil? && weld_drifted_end!(new_group, side, model)
          data = wall_data_world(new_group)
          break unless data
          corner = endpoint_pt(data, side)
          other = find_neighbor_at(corner, new_group, model, allow_centerline_fallback: allow_centerline_fallback)
        end
        next unless other
        butt_applied = apply_miter(new_group, side, other[:group], other[:side], model)
        next if butt_applied  # If butt joint was applied, skip further processing for this side.
        data = wall_data_world(new_group)
        break unless data
      end
    end

    # ---------- a corner that was MEANT, but missed by a hair -------------
    #
    # find_neighbor_at matches DRAWN ends within 0.001". That is right for
    # deciding how to cut a miter, and wrong as the only answer to "is there
    # a neighbour here": an end left 0.3" short is invisible to it, so no
    # miter is cut and the end keeps its plain square cap. Only the long
    # faces of a wall are painted, so that cap shows up as a white wedge -
    # which is exactly what the user reported on 2026-08-17, and what he
    # asked for here: "אם הם נכנסים אחד לתוך השני ואמורה להיות שם פינה
    # שיתקן וישלים אותה אוטומטית שהיא תיראה טוב".
    #
    # So: no exact neighbour, but one within a wall thickness on the SAME
    # storey and the SAME anchor side -> pull THIS wall's end onto it and
    # let the normal miter run. Moves at most one thickness, and only the
    # wall being joined - never the neighbour, which may be the one the
    # user carefully lined up over the storey below.
    #
    # Deliberately NOT welded:
    #   - a different storey: a wall below stands on the same footprint by
    #     definition, and dragging one onto the other is the 2026-08-17 bug
    #     all over again.
    #   - a different anchor side: two walls whose thickness sits on
    #     opposite sides of the line have drawn ends a full thickness apart
    #     even when the corner is perfect. Welding those BREAKS a good
    #     corner. (This is what made three of my own measurements wrong
    #     before I understood it.)
    #   - further than a thickness: that is a gap that was drawn on purpose.
    #
    # Kill switch: InteriorPro::WallTool::AUTO_WELD_ENDS = false
    AUTO_WELD_ENDS = true unless const_defined?(:AUTO_WELD_ENDS, false)

    def weld_drifted_end!(group, side, model)
      return false unless AUTO_WELD_ENDS
      return false unless group&.valid?
      data = wall_data_world(group)
      return false unless data
      mine = endpoint_pt(data, side)
      my_level = (group.get_attribute('InteriorPro', 'level') || 1).to_i
      my_anchor = data[:h_anchor]
      my_th = data[:thickness].to_f
      return false if my_th <= 0

      best = nil
      best_d = nil
      model.active_entities.grep(Sketchup::Group).each do |g|
        next if g == group
        next unless g.valid?
        next unless g.get_attribute('InteriorPro', 'type') == 'wall'
        next unless (g.get_attribute('InteriorPro', 'level') || 1).to_i == my_level
        od = wall_data_world(g)
        next unless od
        next unless od[:h_anchor] == my_anchor
        limit = [my_th, od[:thickness].to_f].max
        limit = 1.0 if limit < 1.0
        [:start, :end].each do |oside|
          d = mine.distance(endpoint_pt(od, oside))
          next if d <= 0.001 || d > limit
          if best_d.nil? || d < best_d
            best_d = d
            best = endpoint_pt(od, oside)
          end
        end
      end
      return false unless best

      # The stored ends are LOCAL to the group; the match was made in world.
      local = best.transform(group.transformation.inverse)
      if side == :start
        group.set_attribute('InteriorPro', 'start_x', local.x.to_f)
        group.set_attribute('InteriorPro', 'start_y', local.y.to_f)
      else
        group.set_attribute('InteriorPro', 'end_x', local.x.to_f)
        group.set_attribute('InteriorPro', 'end_y', local.y.to_f)
      end
      fresh_data = wall_data(group)
      return false unless fresh_data
      corners = compute_perpendicular_corners_from_data(fresh_data)
      return false unless corners
      save_corners_attr(group, corners)
      rebuild_wall_geometry(group, corners, fresh_data)
      puts format('[WallTool] closed a corner that missed by %.3f"', best_d)
      true
    rescue StandardError => e
      puts "[WallTool] weld_drifted_end!: #{e.message}"
      false
    end

    # Two-pass neighbor search:
    #
    #  Pass 1 (tight): the caller's `point` should coincide with a candidate's
    #  DRAWN endpoint within 0.001". Matches legacy behavior and handles
    #  freshly-drawn walls whose drawn lines actually meet (the common case
    #  for create_wall and the wall-edit dialog — unchanged from before).
    #
    #  Pass 2 (centerline fallback): if pass 1 finds nothing, treat `point`
    #  as a drawn endpoint and look for a candidate whose CENTERLINE endpoint
    #  lands within max(t_a, t_b)/2 + 0.001" of it. This handles the merge
    #  case where two walls meeting at the same physical corner can have
    #  drawn endpoints separated by up to (t_a + t_b)/2 when their h_anchors
    #  put the drawn lines on opposite sides of the centerlines.
    def find_neighbor_at(point, exclude_group, model, allow_centerline_fallback: false)
      # Level guard (2026-08-03): miters only between SAME-level walls.
      # All comparisons here are z-flattened, so a level-2 wall stacked
      # right above a level-1 wall would otherwise match its endpoints.
      # Filtering is by the 'level' attribute (NOT base_z), so the garage
      # (level 1 with a dropped base) keeps its mixed-base corners.
      excl_level = (exclude_group.get_attribute('InteriorPro', 'level') || 1).to_i
      candidates = []
      model.active_entities.grep(Sketchup::Group).each do |g|
        next if g == exclude_group
        next unless g.valid?
        next unless g.get_attribute('InteriorPro', 'type') == 'wall'
        next unless (g.get_attribute('InteriorPro', 'level') || 1).to_i == excl_level
        data = wall_data_world(g)
        next unless data
        candidates << [g, data]
      end

      # Pass 1: drawn-to-drawn, tol = 0.001
      tol = 0.001
      best = nil
      best_dist = tol
      candidates.each do |g, data|
        ws = Geom::Point3d.new(data[:drawn_start][0], data[:drawn_start][1], 0)
        we = Geom::Point3d.new(data[:drawn_end][0],   data[:drawn_end][1],   0)
        d_s = point.distance(ws)
        if d_s < best_dist
          best_dist = d_s
          best = { group: g, side: :start, data: data }
        end
        d_e = point.distance(we)
        if d_e < best_dist
          best_dist = d_e
          best = { group: g, side: :end, data: data }
        end
      end
      return best if best
      return nil unless allow_centerline_fallback

      # Pass 2: point-vs-centerline, tol scaled by thickness.
      thickness_a = exclude_group.get_attribute('InteriorPro', 'thickness').to_f
      excl_data = wall_data_world(exclude_group)
      excl_cl = excl_data &&
                [Geom::Point3d.new(excl_data[:cl_start][0], excl_data[:cl_start][1], 0),
                 Geom::Point3d.new(excl_data[:cl_end][0],   excl_data[:cl_end][1],   0)]
      best_dist_p2 = Float::INFINITY
      candidates.each do |g, data|
        tol_p2 = thickness_a + data[:thickness].to_f + 0.001

        # Guard: skip unless the two centerlines actually intersect within
        # 0.5" of `point` -- rejects walls that are merely near but not joined.
        next unless excl_cl
        cand_cl = [Geom::Point3d.new(data[:cl_start][0], data[:cl_start][1], 0),
                   Geom::Point3d.new(data[:cl_end][0],   data[:cl_end][1],   0)]
        cl_hit = Geom.intersect_line_line(excl_cl, cand_cl)
        next if cl_hit.nil? || cl_hit.distance(point) > [thickness_a, data[:thickness].to_f].max

        cs = Geom::Point3d.new(data[:cl_start][0], data[:cl_start][1], 0)
        ce = Geom::Point3d.new(data[:cl_end][0],   data[:cl_end][1],   0)
        d_cs = point.distance(cs)
        if d_cs < tol_p2 && d_cs < best_dist_p2
          best_dist_p2 = d_cs
          best = { group: g, side: :start, data: data }
        end
        d_ce = point.distance(ce)
        if d_ce < tol_p2 && d_ce < best_dist_p2
          best_dist_p2 = d_ce
          best = { group: g, side: :end, data: data }
        end
      end
      best
    end

    # Compute the 2 miter points (outside + inside) where two walls meet, and
    # rebuild both walls' geometry. Uses Geom.intersect_line_line on each pair
    # of side-edge lines.
    # All geometry math runs in world space so two walls living in different
    # group transformations meet correctly. The four world-space miter points
    # are then inverse-transformed back into each group's local frame before
    # being written to attributes / face geometry by apply_miter_to_wall.
    def apply_miter(group_a, side_a, group_b, side_b, model)
      # Returns true if butt joint was applied, false otherwise.
      data_a = wall_data_world(group_a)
      data_b = wall_data_world(group_b)
      return unless data_a && data_b

      cl_a_start = endpoint_pt(data_a, :start)
      cl_a_end   = endpoint_pt(data_a, :end)
      cl_b_start = endpoint_pt(data_b, :start)
      cl_b_end   = endpoint_pt(data_b, :end)

      u_a_nat = (cl_a_end - cl_a_start)
      u_b_nat = (cl_b_end - cl_b_start)
      return if u_a_nat.length < 0.001 || u_b_nat.length < 0.001
      u_a_nat.normalize!
      u_b_nat.normalize!

      # CURVED WALLS (2026-08-11): a curved wall does not run along the
      # straight line between its ends - at this corner it runs along the
      # TANGENT to its arc. Mitering against the straight line cut the
      # neighbour at the wrong angle and left a visible step. Straight walls
      # are untouched: corner_direction returns exactly the same vector, and
      # the centreline reference below is only swapped when a curve is
      # actually involved, so straight-to-straight corners stay bit-for-bit
      # what they were.
      curved_corner = InteriorPro::WallTool.curved_wall?(group_a) ||
                      InteriorPro::WallTool.curved_wall?(group_b)
      if curved_corner
        u_a_nat = InteriorPro::WallTool.corner_direction(group_a, data_a, side_a) || u_a_nat
        u_b_nat = InteriorPro::WallTool.corner_direction(group_b, data_b, side_b) || u_b_nat
      end

      # Direction INTO the corner (from A) and OUT of the corner (toward B).
      u_into = (side_a == :end)   ? u_a_nat : Geom::Vector3d.new(-u_a_nat.x, -u_a_nat.y, 0)
      u_out  = (side_b == :start) ? u_b_nat : Geom::Vector3d.new(-u_b_nat.x, -u_b_nat.y, 0)

      cross_z = u_into.x * u_out.y - u_into.y * u_out.x
      if cross_z.abs < 1e-6         # collinear -- no corner to cut
        # ...unless a curve is involved: an exact half-circle arrives dead
        # parallel to its neighbour (sag = half the chord) and still needs
        # its seam welded, or the end cap shows (2026-08-12).
        if curved_corner
          weld_corner!(group_a, side_a, group_b, side_b)
          return false
        end
        return
      end

      # A curve that runs smoothly into its neighbour has no corner to cut.
      # WELD the two ends onto one shared seam instead (two independent
      # square cuts sit at slightly different angles and leave a small step
      # at the joint - the user's screenshot, 2026-08-12). Guarded by
      # curved_corner so straight-to-straight corners are untouched.
      if curved_corner &&
         InteriorPro::WallTool.corner_too_straight?([u_into.x, u_into.y], [u_out.x, u_out.y])
        weld_corner!(group_a, side_a, group_b, side_b)
        return false
      end

      # Outward bisector at the corner (points to the convex/outside side).
      outside_dir = Geom::Vector3d.new(-u_into.x + u_out.x, -u_into.y + u_out.y, 0)
      return if outside_dir.length < 1e-6
      outside_dir.normalize!

      # +n perpendicular (left of natural start->end direction) for each wall.
      n_a = Geom::Vector3d.new(-u_a_nat.y, u_a_nat.x, 0)
      n_b = Geom::Vector3d.new(-u_b_nat.y, u_b_nat.x, 0)

      # Compute per-wall offsets from the drawn endpoint based on h_anchor.
      # For 'left': wall extends from drawn (offset 0) to +n*t (offset +t)
      # For 'right': wall extends from -n*t (offset -t) to drawn (offset 0)
      # For 'center' (default): wall extends from -n*t/2 to +n*t/2
      ha_a = data_a[:h_anchor]
      ha_b = data_b[:h_anchor]
      t_a_full = data_a[:thickness]
      t_b_full = data_b[:thickness]

      a_pos_off = (ha_a == 'left') ? t_a_full : ((ha_a == 'right') ? 0.0 : t_a_full / 2.0)
      a_neg_off = (ha_a == 'left') ? 0.0      : ((ha_a == 'right') ? -t_a_full : -t_a_full / 2.0)
      b_pos_off = (ha_b == 'left') ? t_b_full : ((ha_b == 'right') ? 0.0 : t_b_full / 2.0)
      b_neg_off = (ha_b == 'left') ? 0.0      : ((ha_b == 'right') ? -t_b_full : -t_b_full / 2.0)

      # A corner with a curve in it is ALWAYS welded (2026-08-12). The miter
      # math measures its face offsets from straight centrelines; on a
      # curved corner that lands the cut sideways and the whole wall face
      # tilts (the user's 11'x8'5" room, sag 20-30). The weld covers every
      # case cleanly: near-identical cuts snap onto one exact shared seam,
      # opposite-side bands get a small shoulder that hides the end cap.
      # Butt joints (interior meeting exterior) keep their own path below.
      # rt31 pins this; straight-to-straight corners never reach here.
      cat_wa = (group_a.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s
      cat_wb = (group_b.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s
      if curved_corner && cat_wa == cat_wb
        weld_corner!(group_a, side_a, group_b, side_b)
        return false
      end

      # Corner = intersection of the two centerlines; fall back to wall A's
      # endpoint if the lines are parallel and never cross.
      # For a straight wall the centreline runs through cl_a_start, so the two
      # forms below describe the SAME infinite line. For a curved wall only
      # the second one is right: its centreline at this corner is the tangent
      # through this end, not a line through its far end.
      if curved_corner
        ep_a = endpoint_pt(data_a, side_a)
        ep_b = endpoint_pt(data_b, side_b)
        off_a = InteriorPro::WallTool.centerline_offset(ha_a, t_a_full)
        off_b = InteriorPro::WallTool.centerline_offset(ha_b, t_b_full)
        line_a = [Geom::Point3d.new(ep_a.x + n_a.x * off_a, ep_a.y + n_a.y * off_a, 0), u_a_nat]
        line_b = [Geom::Point3d.new(ep_b.x + n_b.x * off_b, ep_b.y + n_b.y * off_b, 0), u_b_nat]
      else
        line_a = [cl_a_start, u_a_nat]
        line_b = [cl_b_start, u_b_nat]
      end
      cl_intersect = Geom.intersect_line_line(line_a, line_b)
      corner = cl_intersect || ((side_a == :end) ? cl_a_end : cl_a_start)

      # Interior wall meeting an exterior wall: butt joint, never a miter
      # (real-world framing; also keeps interior walls independent from the
      # exterior shell for move/delete). Same-category corners keep the miter.
      cat_a = (group_a.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s
      cat_b = (group_b.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s
      if cat_a != cat_b
        apply_butt_joint(group_a, side_a, group_b, side_b, data_a, data_b,
                         u_a_nat, u_b_nat, n_a, n_b, ha_a, ha_b,
                         t_a_full, t_b_full,
                         cl_a_start, cl_a_end, cl_b_start, cl_b_end, corner)
        return true
      end

      a_pos_line = [Geom::Point3d.new(corner.x + n_a.x * a_pos_off, corner.y + n_a.y * a_pos_off, 0), u_a_nat]
      a_neg_line = [Geom::Point3d.new(corner.x + n_a.x * a_neg_off, corner.y + n_a.y * a_neg_off, 0), u_a_nat]
      b_pos_line = [Geom::Point3d.new(corner.x + n_b.x * b_pos_off, corner.y + n_b.y * b_pos_off, 0), u_b_nat]
      b_neg_line = [Geom::Point3d.new(corner.x + n_b.x * b_neg_off, corner.y + n_b.y * b_neg_off, 0), u_b_nat]

      # Which side of each wall is on the convex (outside) of the corner.
      a_pos_outside = n_a.dot(outside_dir) > 0
      b_pos_outside = n_b.dot(outside_dir) > 0

      a_outside = a_pos_outside ? a_pos_line : a_neg_line
      a_inside  = a_pos_outside ? a_neg_line : a_pos_line
      b_outside = b_pos_outside ? b_pos_line : b_neg_line
      b_inside  = b_pos_outside ? b_neg_line : b_pos_line

      miter_outside = Geom.intersect_line_line(a_outside, b_outside)
      miter_inside  = Geom.intersect_line_line(a_inside,  b_inside)
      return unless miter_outside && miter_inside

      # Safety net only: same-category curved corners are welded above and
      # never reach this point; this guards any future path that does.
      if curved_corner
        ep_ra = endpoint_pt(data_a, side_a)
        ep_rb = endpoint_pt(data_b, side_b)
        if InteriorPro::WallTool.curve_miter_too_far?(
             [[miter_outside.x, miter_outside.y], [miter_inside.x, miter_inside.y]],
             [ep_ra.x, ep_ra.y], [ep_rb.x, ep_rb.y], t_a_full, t_b_full)
          weld_corner!(group_a, side_a, group_b, side_b)
          return false
        end
      end

      a_miter_pos = a_pos_outside ? miter_outside : miter_inside
      a_miter_neg = a_pos_outside ? miter_inside  : miter_outside
      b_miter_pos = b_pos_outside ? miter_outside : miter_inside
      b_miter_neg = b_pos_outside ? miter_inside  : miter_outside

      # Inverse-transform world miter points into each group's local frame
      # so apply_miter_to_wall writes attributes and face vertices that are
      # consistent with the group's own transformation. Pass the LOCAL
      # wall_data so the perpendicular-corner fallback inside
      # apply_miter_to_wall produces local-frame corners as well.
      xform_a_inv = group_a.transformation.inverse
      xform_b_inv = group_b.transformation.inverse
      apply_miter_to_wall(group_a, side_a,
                          a_miter_pos.transform(xform_a_inv),
                          a_miter_neg.transform(xform_a_inv),
                          wall_data(group_a))
      apply_miter_to_wall(group_b, side_b,
                          b_miter_pos.transform(xform_b_inv),
                          b_miter_neg.transform(xform_b_inv),
                          wall_data(group_b))
      false
    end

      def apply_butt_joint(group_a, side_a, group_b, side_b, data_a, data_b, u_a_nat, u_b_nat, n_a, n_b, ha_a, ha_b, t_a_full, t_b_full, cl_a_start, cl_a_end, cl_b_start, cl_b_end, corner)
        # The EXTERIOR wall is always the one kept intact ("thick"); the
        # INTERIOR wall is the one trimmed to its face ("thin") — decided by
        # category, NOT by thickness (walls are often equally thick).
        cat_a = (group_a.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s
        if cat_a == 'exterior'
          thick_group = group_a; thick_side = side_a; thick_data = data_a; thick_u = u_a_nat; thick_n = n_a; thick_ha = ha_a; thick_t = t_a_full; thick_cl_s = cl_a_start; thick_cl_e = cl_a_end
          thin_group = group_b; thin_side = side_b; thin_data = data_b; thin_u = u_b_nat; thin_n = n_b; thin_ha = ha_b; thin_t = t_b_full; thin_cl_s = cl_b_start; thin_cl_e = cl_b_end
        else
          thick_group = group_b; thick_side = side_b; thick_data = data_b; thick_u = u_b_nat; thick_n = n_b; thick_ha = ha_b; thick_t = t_b_full; thick_cl_s = cl_b_start; thick_cl_e = cl_b_end
          thin_group = group_a; thin_side = side_a; thin_data = data_a; thin_u = u_a_nat; thin_n = n_a; thin_ha = ha_a; thin_t = t_a_full; thin_cl_s = cl_a_start; thin_cl_e = cl_a_end
        end
        # The thin wall must stop at the face of the thick wall that FACES the
        # thin wall's body. The corner (centerline intersection) sits ON the
        # thick centerline, so the side is decided by where the thin wall's
        # far end lies relative to the thick centerline.
        thin_far = (thin_side == :start) ? thin_cl_e : thin_cl_s
        side_ref = Geom::Vector3d.new(thin_far.x - corner.x, thin_far.y - corner.y, 0)
        side_sign = (side_ref.dot(thick_n) >= 0) ? 1.0 : -1.0
        face_offset = side_sign * (thick_t / 2.0)
        face_pt = Geom::Point3d.new(thick_cl_s.x + thick_n.x * face_offset, thick_cl_s.y + thick_n.y * face_offset, 0)
        thick_face_line = [face_pt, thick_u]
        thin_pos_off = (thin_ha == 'left') ? thin_t : ((thin_ha == 'right') ? 0.0 : thin_t / 2.0)
        thin_neg_off = (thin_ha == 'left') ? 0.0 : ((thin_ha == 'right') ? -thin_t : -thin_t / 2.0)
        thin_pos_line = [Geom::Point3d.new(thin_cl_s.x + thin_n.x * thin_pos_off, thin_cl_s.y + thin_n.y * thin_pos_off, 0), thin_u]
        thin_neg_line = [Geom::Point3d.new(thin_cl_s.x + thin_n.x * thin_neg_off, thin_cl_s.y + thin_n.y * thin_neg_off, 0), thin_u]
        thin_pos_world = Geom.intersect_line_line(thin_pos_line, thick_face_line)
        thin_neg_world = Geom.intersect_line_line(thin_neg_line, thick_face_line)
        unless thin_pos_world && thin_neg_world
          return
        end
        thin_xform_inv = thin_group.transformation.inverse
        # Butt joint: ONLY the thin wall is trimmed to the thick wall's face.
        # The thick (exterior) wall keeps its own geometry and miters.
        apply_miter_to_wall(thin_group, thin_side, thin_pos_world.transform(thin_xform_inv), thin_neg_world.transform(thin_xform_inv), wall_data(thin_group))
      end

    # A wall's own plain cross-section at one end, in WORLD coordinates -
    # [pos, neg] as [x, y] pairs. What the end looks like with no neighbour.
    def natural_cut_world(group, side)
      data = wall_data(group)
      return nil unless data
      plain = compute_perpendicular_corners_from_data(data)
      return nil unless plain
      pts = side == :start ? [plain[0], plain[3]] : [plain[1], plain[2]]
      xf = group.transformation
      pts.map do |p|
        gp = Geom::Point3d.new(p[0].to_f, p[1].to_f, 0).transform(xf)
        [gp.x.to_f, gp.y.to_f]
      end
    rescue StandardError
      nil
    end

    # Put one end of a wall back to its own plain square cut, throwing away
    # any miter that was cut into it. For a straight wall that is square to
    # its length; for a curved one it is square to the curve's direction
    # there (radial). Used when a corner turns out not to be a corner.
    def square_corner!(group, side)
      return unless group&.valid?
      data = wall_data(group)
      return unless data
      plain = compute_perpendicular_corners_from_data(data)
      return unless plain
      corners = read_corners_attr(group) || plain
      if side == :start
        corners[0] = plain[0]
        corners[3] = plain[3]
      else
        corners[1] = plain[1]
        corners[2] = plain[2]
      end
      save_corners_attr(group, corners)
      rebuild_wall_geometry(group, corners, data)
    rescue StandardError => e
      puts "[WallTool] square_corner!: #{e.message}"
    end

    # ONE shared seam for a corner that cannot be mitered (a curve running
    # almost in line with its neighbour, or a miter that would fly off).
    # Two independent square cuts sit at slightly different angles and leave
    # a small step / sliver at the joint. Instead: the STRAIGHT wall keeps
    # its own plain square cut, and the curved wall's end is pulled onto
    # exactly that segment - both faces coincide, so there is no gap and no
    # step. With two curves, wall A's cut owns the seam. Never called for a
    # straight-to-straight corner.
    def weld_corner!(group_a, side_a, group_b, side_b)
      a_curved = InteriorPro::WallTool.curved_wall?(group_a)
      b_curved = InteriorPro::WallTool.curved_wall?(group_b)
      owner, o_side, guest, g_side =
        if a_curved && !b_curved
          [group_b, side_b, group_a, side_a]
        else
          [group_a, side_a, group_b, side_b]
        end
      o_data = wall_data(owner)
      g_data = wall_data(guest)
      return unless o_data && g_data

      plain = compute_perpendicular_corners_from_data(o_data)
      return unless plain
      square_corner!(owner, o_side)
      seam_local = (o_side == :start) ? [plain[0], plain[3]] : [plain[1], plain[2]]

      # The seam lives in the owner's local frame; carry it into the guest's.
      to_world = owner.transformation
      to_guest = guest.transformation.inverse
      seam = seam_local.map do |p|
        gp = Geom::Point3d.new(p[0].to_f, p[1].to_f, 0).transform(to_world).transform(to_guest)
        [gp.x.to_f, gp.y.to_f]
      end

      # Pair the seam's two points with the guest's own two cut points by
      # nearness, so the band is never written in crossed.
      g_plain = compute_perpendicular_corners_from_data(g_data)
      return unless g_plain
      g_pts = (g_side == :start) ? [g_plain[0], g_plain[3]] : [g_plain[1], g_plain[2]]
      dd = lambda { |p, q| Math.sqrt(((p[0] - q[0])**2) + ((p[1] - q[1])**2)) }
      straight_fit = dd.call(seam[0], g_pts[0]) + dd.call(seam[1], g_pts[1])
      crossed_fit  = dd.call(seam[0], g_pts[1]) + dd.call(seam[1], g_pts[0])
      map = straight_fit <= crossed_fit ? [0, 1] : [1, 0]   # seam index for each g index

      # TWO different geometries come here (verified by rendering the
      # user's exact rooms, 2026-08-12):
      # * SAME-SIDE bands (the near-parallel spring): the two cuts almost
      #   coincide - snap the guest's cut exactly onto the owner's. The
      #   points move under an inch; the seam becomes shared and exact.
      # * OPPOSITE-SIDE bands (the bodies sit on opposite sides of the
      #   drawn line): the cuts only share the drawn corner. Replacing the
      #   whole cut twists the band into a beak. Instead only the touching
      #   lip is pulled onto the owner's FAR lip, so the arc grows a small
      #   shoulder that covers the owner's exposed end face; the other
      #   side of the cut stays where the curve wants it.
      pair_d = [dd.call(seam[map[0]], g_pts[0]), dd.call(seam[map[1]], g_pts[1])]
      same_side = pair_d.max <= [o_data[:thickness], g_data[:thickness]].max * 1.2
      new_g = [nil, nil]
      if same_side
        new_g[0] = seam[map[0]]
        new_g[1] = seam[map[1]]
      else
        ti = pair_d[0] <= pair_d[1] ? 0 : 1      # the touching guest point
        new_g[ti] = seam[map[1 - ti]]            # -> the owner's far lip
        new_g[1 - ti] = g_pts[1 - ti]            # the other stays natural
      end

      corners = read_corners_attr(guest) || g_plain
      if g_side == :start
        corners[0] = new_g[0]
        corners[3] = new_g[1]
      else
        corners[1] = new_g[0]
        corners[2] = new_g[1]
      end
      save_corners_attr(guest, corners)
      rebuild_wall_geometry(guest, corners, g_data)
    rescue StandardError => e
      puts "[WallTool] weld_corner!: #{e.message}"
    end

    def apply_miter_to_wall(group, side, miter_pos, miter_neg, data)
      return unless group&.valid?
      corners = read_corners_attr(group) || compute_perpendicular_corners_from_data(data)
      return unless corners
      if side == :start
        corners[0] = [miter_pos.x, miter_pos.y]   # s_pos
        corners[3] = [miter_neg.x, miter_neg.y]   # s_neg
      else
        corners[1] = [miter_pos.x, miter_pos.y]   # e_pos
        corners[2] = [miter_neg.x, miter_neg.y]   # e_neg
      end
      save_corners_attr(group, corners)
      rebuild_wall_geometry(group, corners, data)
    end

    def compute_perpendicular_corners_from_data(data)
      # A curved wall's ends are cut radially, so its default corners are NOT
      # the ones a straight wall would get. Everything that resets a wall's
      # corners comes through here, so this is the single place that has to
      # know the difference.
      g = data[:group]
      if g && InteriorPro::WallTool.curved_wall?(g)
        rc = InteriorPro::WallTool.curved_end_corners_xy(
          data[:drawn_start][0], data[:drawn_start][1],
          data[:drawn_end][0],   data[:drawn_end][1],
          data[:thickness], data[:h_anchor], InteriorPro::WallTool.wall_sag(g)
        )
        return rc if rc
      end
      drawn_start = Geom::Point3d.new(data[:drawn_start][0], data[:drawn_start][1], 0)
      drawn_end   = Geom::Point3d.new(data[:drawn_end][0],   data[:drawn_end][1],   0)
      perpendicular_corners_xy(drawn_start, drawn_end, data[:thickness], data[:h_anchor])
    end

    def rebuild_wall_geometry(group, corners_xy, data)
      return unless group&.valid?

      # A CURVED wall with doors is built by the curved path below, which
      # cuts the holes itself. The native path builds a straight wall, so it
      # must not grab a curved one.
      if InteriorPro::WallTool::USE_NATIVE_OPENINGS &&
         !InteriorPro::WallTool.curved_wall?(group) &&
         !InteriorPro::WallTool.read_door_openings(group).empty?
        begin
          InteriorPro::WallTool.rebuild_wall_native_geometry!(group)
        rescue StandardError => e
          puts "[WallTool] rebuild_wall_geometry native: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
        end
        return
      end

      # A curved wall replaces the 4-corner footprint with a many-sided one.
      # Everything downstream (add_face + pushpull) is unchanged - it never
      # cared how many points the footprint had. nil = build straight.
      footprint = InteriorPro::WallTool.curved_footprint_for(group, data) || corners_xy

      group.entities.clear!
      build_geometry_in_group(group, footprint, data[:z_offset], data[:height],
                              data[:ext_mat], data[:int_mat])
    end

    def build_geometry_in_group(group, corners_xy, z_offset, height, ext_mat, int_mat)
      pts = corners_xy.map { |c| Geom::Point3d.new(c[0], c[1], z_offset) }
      uniq_pts = pts.uniq { |p| [p.x.round(4), p.y.round(4), p.z.round(4)] }
      return false if uniq_pts.length < 3
      face = group.entities.add_face(uniq_pts)
      return false unless face
      sign = face.normal.z >= 0 ? 1 : -1
      face.pushpull(height * sign)
      if InteriorPro::WallTool.curved_wall?(group)
        # Doors are cut BEFORE painting, so the painter sees the finished
        # shape. The faces inside a hole point sideways or up and down, so
        # the radial painter skips them on its own.
        InteriorPro::WallTool.punch_curved_openings!(group, z_offset)
        # A curved wall's long faces each point a different way, so the
        # straight painter (which classifies against ONE direction) would
        # leave some of them unpainted. Paint radially instead.
        InteriorPro::WallTool.paint_curved_wall_long_faces!(group, ext_mat, int_mat)
        InteriorPro::WallTool.smooth_curved_wall_edges!(group)
        add_exterior_siding(group, ext_mat)
      else
        paint_wall_long_faces!(group, ext_mat, int_mat)
        add_exterior_siding(group, ext_mat)
      end
      true
    end

    # Paint exterior/interior on the two long wall faces (skip top/bottom and end caps).
    def paint_wall_long_faces!(group, ext_mat, int_mat)
      return unless group&.valid?
      return unless ext_mat && int_mat

      sx = group.get_attribute('InteriorPro', 'start_x')
      sy = group.get_attribute('InteriorPro', 'start_y')
      ex = group.get_attribute('InteriorPro', 'end_x')
      ey = group.get_attribute('InteriorPro', 'end_y')
      return unless sx && sy && ex && ey

      dir = Geom::Vector3d.new(ex - sx, ey - sy, 0)
      return if dir.length <= 0.001

      dir.normalize!
      # Right perpendicular = exterior side (clockwise drawing convention)
      right = Geom::Vector3d.new(dir.y, -dir.x, 0)
      ext_material = load_or_create_material(ext_mat)
      int_material = load_or_create_material(int_mat)
      group.entities.grep(Sketchup::Face).each do |f|
        n = f.normal
        # Skip top and bottom faces (vertical normals)
        next if n.z.abs > 0.5
        # Skip end caps (normal parallel to wall direction)
        next if n.dot(dir).abs > 0.5
        # This is a long face - paint based on side
        if n.dot(right) > 0
          f.material = ext_material
          f.back_material = nil
        else
          f.material = int_material
          f.back_material = nil
        end
      end
    rescue StandardError => e
      puts "[WallTool] paint_wall_long_faces!: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    end

    def wall_data(group)
      return nil unless group&.valid?
      sx = group.get_attribute('InteriorPro', 'start_x')
      sy = group.get_attribute('InteriorPro', 'start_y')
      ex = group.get_attribute('InteriorPro', 'end_x')
      ey = group.get_attribute('InteriorPro', 'end_y')
      return nil unless sx && sy && ex && ey
      thickness = group.get_attribute('InteriorPro', 'thickness').to_f
      height    = group.get_attribute('InteriorPro', 'height').to_f
      anchor    = group.get_attribute('InteriorPro', 'anchor') || 'bottom-center'
      ext_mat   = group.get_attribute('InteriorPro', 'exterior_material')
      int_mat   = group.get_attribute('InteriorPro', 'interior_material')
      wall_category = group.get_attribute('InteriorPro', 'wall_category') || 'exterior'
      if wall_category == 'interior'
        side_a = group.get_attribute('InteriorPro', 'side_a_color') || '#ffffff'
        side_b = group.get_attribute('InteriorPro', 'side_b_color') || '#ffffff'
        ext_mat = side_a
        int_mat = side_b
      end
      v_anchor, h_anchor = parse_anchor(anchor)

      cl_offset = case h_anchor
                  when 'left'  then  thickness / 2.0
                  when 'right' then -thickness / 2.0
                  else 0.0
                  end
      dx = ex - sx
      dy = ey - sy
      len = Math.sqrt(dx**2 + dy**2)
      return nil if len < 0.001
      nx = -dy / len
      ny =  dx / len
      cl_start = [sx + nx * cl_offset, sy + ny * cl_offset]
      cl_end   = [ex + nx * cl_offset, ey + ny * cl_offset]

      {
        group:       group,
        drawn_start: [sx, sy],
        drawn_end:   [ex, ey],
        cl_start:    cl_start,
        cl_end:      cl_end,
        thickness:   thickness,
        height:      height,
        anchor:      anchor,
        v_anchor:    v_anchor,
        h_anchor:    h_anchor,
        z_offset:    z_offset_for(v_anchor, height),
        ext_mat:     ext_mat,
        int_mat:     int_mat
      }
    end

    # Same shape as wall_data, but with the four point fields transformed by
    # the group's transformation so they live in the parent's (world) frame.
    # Scalar fields (thickness, height, anchors, materials, z_offset) are
    # frame-independent and pass through unchanged. Used by the miter pipeline
    # so endpoints from two groups with different transformations can be
    # compared and intersected in a single coordinate system.
    def wall_data_world(group)
      data = wall_data(group)
      return nil unless data
      xform = group.transformation
      return data if xform.identity?
      s  = Geom::Point3d.new(data[:drawn_start][0], data[:drawn_start][1], 0).transform(xform)
      e  = Geom::Point3d.new(data[:drawn_end][0],   data[:drawn_end][1],   0).transform(xform)
      cs = Geom::Point3d.new(data[:cl_start][0],    data[:cl_start][1],    0).transform(xform)
      ce = Geom::Point3d.new(data[:cl_end][0],      data[:cl_end][1],      0).transform(xform)
      data.merge(
        drawn_start: [s.x,  s.y],
        drawn_end:   [e.x,  e.y],
        cl_start:    [cs.x, cs.y],
        cl_end:      [ce.x, ce.y]
      )
    end

    def endpoint_pt(data, side)
      arr = side == :start ? data[:drawn_start] : data[:drawn_end]
      Geom::Point3d.new(arr[0], arr[1], 0)
    end

    def parse_anchor(anchor)
      return ['center', 'center'] if anchor == 'center'
      parts = anchor.to_s.split('-')
      [parts[0] || 'bottom', parts[1] || 'center']
    end

    def z_offset_for(v_anchor, height)
      case v_anchor
      when 'top'    then -height
      when 'center' then -height / 2.0
      else 0.0
      end
    end

    # 4 floor-plane corners in canonical order: [s_pos, e_pos, e_neg, s_neg]
    # where +n is the left perpendicular of the natural start->end direction.
    def perpendicular_corners_xy(start_pt, end_pt, thickness, h_anchor)
      dx = end_pt.x - start_pt.x
      dy = end_pt.y - start_pt.y
      len = Math.sqrt(dx**2 + dy**2)
      return nil if len < 0.001
      half = thickness / 2.0
      nx = -dy / len * half
      ny =  dx / len * half

      case h_anchor
      when 'left'
        s_pos = [start_pt.x + nx * 2, start_pt.y + ny * 2]
        e_pos = [end_pt.x   + nx * 2, end_pt.y   + ny * 2]
        e_neg = [end_pt.x,            end_pt.y]
        s_neg = [start_pt.x,          start_pt.y]
      when 'right'
        s_pos = [start_pt.x,                start_pt.y]
        e_pos = [end_pt.x,                  end_pt.y]
        e_neg = [end_pt.x   - nx * 2,       end_pt.y   - ny * 2]
        s_neg = [start_pt.x - nx * 2,       start_pt.y - ny * 2]
      else
        s_pos = [start_pt.x + nx, start_pt.y + ny]
        e_pos = [end_pt.x   + nx, end_pt.y   + ny]
        e_neg = [end_pt.x   - nx, end_pt.y   - ny]
        s_neg = [start_pt.x - nx, start_pt.y - ny]
      end
      [s_pos, e_pos, e_neg, s_neg]
    end

    def save_corners_attr(group, corners_xy)
      group.set_attribute('InteriorPro', 'corners_xy', corners_xy.flatten)
    end

    def read_corners_attr(group)
      flat = group.get_attribute('InteriorPro', 'corners_xy')
      return nil unless flat && flat.length == 8
      [[flat[0], flat[1]], [flat[2], flat[3]], [flat[4], flat[5]], [flat[6], flat[7]]]
    end

    def generate_wall_id
      require 'securerandom'
      SecureRandom.uuid
    rescue StandardError
      "wall-#{Time.now.to_f}-#{rand(1_000_000)}"
    end

    # ---------- two walls, one identity (2026-08-18) ----------------------
    #
    # Copy a wall with SketchUp's own Copy/Paste or Ctrl+Move and the copy
    # arrives carrying every attribute of the original - including its `id`.
    # Nothing in the plugin ever checked whether an id was already taken, so
    # the model ends up with two walls answering to the same name. Found on
    # the user's model: three pairs (a level-1 wall with an identity
    # transformation, and its copy translated 84.1", 124.6").
    #
    # It matters because the plugin finds walls BY id - find_wall, delete,
    # move, a room's bounding_wall_ids, a door's host_wall_id. Ask for that
    # wall and you may get its twin.
    #
    # WHO KEEPS THE NAME: the wall that has not been moved (an identity
    # transformation). SketchUp gives a pasted copy a transformation; the
    # original keeps none. If that does not single one out, the first found
    # keeps it - at that point either choice is as good.
    #
    # WHAT IS DELIBERATELY LEFT ALONE: a duplicated id that some door or
    # window still points at through host_wall_id. Both twins answer to that
    # name, so there is no honest way to tell whose opening it is, and a
    # wrong guess would orphan a door. Those are reported and skipped, never
    # renamed behind the user's back.
    def self.ensure_unique_ids!(model = Sketchup.active_model, wrap_operation: true)
      walls = model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall'
      end
      by_id = {}
      walls.each do |g|
        wid = g.get_attribute('InteriorPro', 'id')
        next if wid.nil? || wid.to_s.empty?
        (by_id[wid.to_s] ||= []) << g
      end
      dups = by_id.select { |_k, v| v.length > 1 }
      return [0, 0] if dups.empty?

      # Any id an opening still points at is untouchable.
      hosted = {}
      model.entities.grep(Sketchup::Group).each do |g|
        next unless g.valid?
        h = g.get_attribute('InteriorPro', 'host_wall_id')
        hosted[h.to_s] = true unless h.nil?
      end

      renamed = 0
      skipped = 0
      model.start_operation('InteriorPro Fix Duplicate Wall Ids', true) if wrap_operation
      begin
        tool = new
        dups.each do |wid, list|
          if hosted[wid]
            skipped += list.length
            puts "[WallTool] duplicate id #{wid} on #{list.length} walls has a door or window on it - left alone"
            next
          end
          keeper = list.find { |g| g.transformation.identity? } || list.first
          list.each do |g|
            next if g == keeper
            g.set_attribute('InteriorPro', 'id', tool.generate_wall_id)
            renamed += 1
          end
        end
        model.commit_operation if wrap_operation
      rescue StandardError => e
        model.abort_operation if wrap_operation
        puts "[WallTool] ensure_unique_ids!: #{e.message}"
        return [0, 0]
      end
      puts "[WallTool] duplicate wall ids: #{renamed} renamed, #{skipped} left alone"
      [renamed, skipped]
    rescue StandardError => e
      puts "[WallTool] ensure_unique_ids!: #{e.message}"
      [0, 0]
    end

    def self.read_door_openings(wall)
      raw = wall.get_attribute('InteriorPro', 'door_openings')
      case raw
      when Array
        if raw.empty?
          []
        elsif raw.first.is_a?(Array)
          raw.compact.map { |row| normalize_door_opening(row) }.compact
        else
          raw.compact.map { |o| normalize_door_opening(o) }.compact
        end
      when String
        require 'json'
        JSON.parse(raw).map { |o| normalize_door_opening(o) }.compact
      else
        []
      end
    rescue StandardError => e
      puts "[WallTool] read_door_openings: #{e.message}"
      []
    end

    def self.normalize_door_opening(o)
      return nil if o.nil?

      if o.is_a?(Array) && o.length >= 4
        return {
          t: o[0].to_f,
          width: o[1].to_f,
          height: o[2].to_f,
          floor_offset: o[3].to_f,
          # 5th element (optional) = arch rise in inches. 0 / missing => rectangular.
          arch_rise: (o.length >= 5 ? o[4].to_f : 0.0)
        }
      end

      return nil unless o.is_a?(Hash)

      t = o[:t] || o['t']
      width = o[:width] || o['width']
      height = o[:height] || o['height']
      floor_offset = o[:floor_offset] || o['floor_offset']
      arch_rise = o[:arch_rise] || o['arch_rise']
      return nil if width.nil? || height.nil?

      {
        t: t.to_f,
        width: width.to_f,
        height: height.to_f,
        floor_offset: floor_offset.to_f,
        arch_rise: arch_rise.to_f
      }
    rescue StandardError
      nil
    end

    def self.persist_door_openings!(wall, openings)
      rows = openings.compact.map { |o| normalize_door_opening(o) }.compact.map do |o|
        [o[:t], o[:width], o[:height], o[:floor_offset], o[:arch_rise].to_f]
      end
      wall.set_attribute('InteriorPro', 'door_openings', rows)
    end

    def self.append_door_opening!(wall, opening)
      entry = normalize_door_opening(opening)
      unless entry
        puts '[WallTool] append_door_opening!: skipped invalid opening'
        return false
      end

      openings = read_door_openings(wall)
      puts "[WallTool] door_opening append: #{entry.inspect}"
      openings << entry
      persist_door_openings!(wall, openings)
      true
    rescue StandardError => e
      puts "[WallTool] append_door_opening!: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      false
    end

    def self.wall_side_material_names(group)
      ext_mat = group.get_attribute('InteriorPro', 'exterior_material')
      int_mat = group.get_attribute('InteriorPro', 'interior_material')
      wall_category = group.get_attribute('InteriorPro', 'wall_category') || 'exterior'
      if wall_category == 'interior'
        ext_mat = group.get_attribute('InteriorPro', 'side_a_color') || '#ffffff'
        int_mat = group.get_attribute('InteriorPro', 'side_b_color') || '#ffffff'
      end
      [ext_mat, int_mat]
    rescue StandardError
      [nil, nil]
    end

    def self.paint_wall_long_faces!(group, ext_mat, int_mat)
      InteriorPro::WallTool.new.paint_wall_long_faces!(group, ext_mat, int_mat)
    end

    def self.join_corners(wall, model, allow_centerline_fallback: false)
      InteriorPro::WallTool.new.join_corners(wall, model, allow_centerline_fallback: allow_centerline_fallback)
    end

    # Per-wall base height (2026-07-18, garage unit): the wall group is
    # TRANSLATED vertically via its transformation, so every internal build
    # path stays untouched — geometry, openings (local frame) and the
    # world-aware miter pipeline (XY unaffected by a Z translation) all
    # follow automatically. Hosted door/window BODIES are separate top-level
    # entities, so they are translated by the same delta.
    def self.set_wall_base!(wall, base_z)
      return false unless wall&.valid?
      return false unless wall.get_attribute('InteriorPro', 'type') == 'wall'
      cur = wall.get_attribute('InteriorPro', 'base_z').to_f
      dz = base_z.to_f - cur
      return true if dz.abs < 0.001
      tr = Geom::Transformation.translation(Geom::Vector3d.new(0, 0, dz))
      wall.transformation = tr * wall.transformation
      wall.set_attribute('InteriorPro', 'base_z', base_z.to_f)
      wall_id = wall.get_attribute('InteriorPro', 'id')
      moved = 0
      Sketchup.active_model.entities.to_a.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        t = e.get_attribute('InteriorPro', 'type')
        next unless t == 'door' || t == 'window'
        next unless e.get_attribute('InteriorPro', 'host_wall_id') == wall_id
        e.transform!(tr)
        %w[bottom_z top_z].each do |k|
          v = e.get_attribute('InteriorPro', k)
          e.set_attribute('InteriorPro', k, v.to_f + dz) unless v.nil?
        end
        moved += 1
      end
      puts "[WallTool] base_z=#{base_z.to_f} (#{moved} opening body(ies) moved)"
      true
    rescue StandardError => e
      puts "[WallTool] set_wall_base!: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      false
    end

    # ==== CURVED WALLS ====================================================
    # A curved wall is an ordinary wall with one extra attribute, 'arc_sag'.
    # Straight walls do not have it, so every straight wall keeps taking the
    # exact same code path it always did.

    # The stored bow, in inches. 0.0 when the wall is straight.
    def self.wall_sag(wall)
      return 0.0 unless wall&.valid?
      v = wall.get_attribute('InteriorPro', 'arc_sag')
      v.nil? ? 0.0 : v.to_f
    rescue StandardError
      0.0
    end

    def self.curved_wall?(wall)
      return false unless USE_CURVED_WALLS
      wall_sag(wall).abs >= MIN_ARC_SAG
    end

    # Does this wall have anything cut into it?
    #
    # Doors register in the wall's own 'door_openings' list, so a rebuild puts
    # their holes back. WINDOWS DO NOT: window_tool cuts the hole straight
    # into the wall's faces and nothing records it, so any rebuild of the wall
    # wipes that hole out. Bending a wall rebuilds it - so a wall hosting a
    # window has to be refused just as firmly as one with a door, or the
    # window would end up buried in solid wall.
    def self.wall_has_openings?(wall)
      return false unless wall&.valid?
      return true unless read_door_openings(wall).empty?
      hosted_opening_count(wall) > 0
    rescue StandardError
      true    # if we cannot tell, assume yes and refuse - never destroy work
    end

    def self.hosted_opening_count(wall, kinds = %w[window door])
      wid = wall.get_attribute('InteriorPro', 'id')
      return 0 unless wid
      n = 0
      Sketchup.active_model.entities.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        next unless e.valid?
        next unless kinds.include?(e.get_attribute('InteriorPro', 'type').to_s)
        n += 1 if e.get_attribute('InteriorPro', 'host_wall_id') == wid
      end
      n
    rescue StandardError
      0
    end

    # Windows only. This is the one that still blocks a curve, because a
    # window's hole is not recorded anywhere and a rebuild would erase it.
    def self.hosted_window_count(wall)
      return 0 unless wall&.valid?
      hosted_opening_count(wall, %w[window])
    rescue StandardError
      1     # cannot tell -> assume there is one and refuse
    end

    # The two side offsets, measured along the LEFT perpendicular of
    # start -> end. Deliberately identical to what perpendicular_corners_xy
    # does for a straight wall, so a curve and a straight line put their two
    # faces in exactly the same places relative to the drawn line.
    def self.anchor_side_offsets(thickness, h_anchor)
      t = thickness.to_f
      case h_anchor
      when 'left'  then [t,       0.0]
      when 'right' then [0.0,     -t]
      else              [t / 2.0, -t / 2.0]
      end
    end

    # PURE: numbers in, numbers out. The floor footprint of a curved wall, as
    # a closed ring of [x, y] points - the outer side walked start -> end,
    # then the inner side walked back. Returns nil when the wall should stay
    # straight (kill switch off, bow too small, or the curve is so tight that
    # the inner face would swallow its own centre).
    def self.curved_footprint_xy(sx, sy, ex, ey, thickness, h_anchor, sag,
                                 tol = CURVE_TOL, openings = nil)
      return nil unless USE_CURVED_WALLS
      return nil if sag.nil? || sag.to_f.abs < MIN_ARC_SAG

      am = InteriorPro::ArcMath
      arc = am.from_chord_and_sag(sx.to_f, sy.to_f, ex.to_f, ey.to_f, sag.to_f)
      return nil unless arc

      stations = curved_wall_stations(arc, tol, openings)
      return nil unless stations

      o_pos, o_neg = anchor_side_offsets(thickness, h_anchor)
      pos = stations.map { |d| am.offset_point_at_distance(arc, d, o_pos) }
      neg = stations.map { |d| am.offset_point_at_distance(arc, d, o_neg) }
      return nil if pos.any?(&:nil?) || neg.any?(&:nil?)

      pos + neg.reverse
    rescue StandardError => e
      puts "[WallTool] curved_footprint_xy: #{e.message}"
      nil
    end

    # PURE: the distances along the arc where the wall's outline gets a point.
    #
    # Without openings these are just even steps, fine enough that the wall
    # reads as smooth. WITH openings, the stretch a door occupies gets NO
    # points in the middle - only its two ends - so that stretch comes out as
    # one straight FLAT PANEL. A door frame is a straight thing; it needs
    # something straight to sit in. Real builders do the same.
    #
    # The flat panel is sized so that its straight width is exactly the door's
    # width. A door measured straight across eats slightly MORE wall when the
    # wall is curved, and half_arc_for_chord is what accounts for that.
    #
    # Returns nil when the openings cannot fit: too wide for the curve, off
    # the end of the wall, or overlapping each other.
    def self.curved_wall_stations(arc, tol, openings)
      am = InteriorPro::ArcMath
      total = am.length(arc)
      n = am.segment_count(arc, tol)
      even = (0..n).map { |i| total * i / n.to_f }

      list = (openings || []).map { |o| normalize_pocket(o) }.compact
      return even if list.empty?

      pockets = []
      list.each do |t, width|
        half = padded_half_arc(arc, t, width, total)
        return nil unless half
        d0 = t - half
        d1 = t + half
        return nil if d0 < -1e-6 || d1 > total + 1e-6
        pockets << [d0, d1]
      end
      pockets.sort_by!(&:first)
      pockets.each_cons(2) { |a, b| return nil if b[0] < a[1] - 1e-6 }

      inside = ->(d) { pockets.any? { |p| d > p[0] + 1e-6 && d < p[1] - 1e-6 } }
      stations = even.reject { |d| inside.call(d) }
      pockets.each { |p| stations << p[0] << p[1] }
      stations << 0.0 << total
      stations.sort!

      out = []
      stations.each { |d| out << d if out.empty? || (d - out.last).abs > 1e-6 }
      out
    end

    # Half the arc length the FLAT PANEL takes up: the opening itself plus a
    # strip of flat wall either side of it.
    #
    # The strip matters. Without it the hole's edges would land exactly on the
    # panel's own edges, and cutting a hole whose sides are shared with the
    # curve either side of it is asking for trouble. With it, the hole sits
    # comfortably inside a flat panel - which is also how the wall would
    # really be built.
    #
    # The strip shrinks, down to nothing, rather than let a panel run off the
    # end of the wall.
    def self.padded_half_arc(arc, t, width, total)
      am = InteriorPro::ArcMath
      bare = am.half_arc_for_chord(arc, width)
      return nil unless bare
      pad = POCKET_PAD
      while pad > 1e-6
        half = am.half_arc_for_chord(arc, width + 2.0 * pad)
        if half && (t - half) >= -1e-6 && (t + half) <= total + 1e-6
          return half
        end
        pad /= 2.0
      end
      bare
    end

    # Openings arrive as symbol hashes from read_door_openings, but string
    # keys turn up too (attributes round-tripped through JSON). Take both.
    def self.normalize_pocket(o)
      return nil unless o
      t = o[:t] || o['t']
      w = o[:width] || o['width']
      return nil if t.nil? || w.nil?
      w = w.to_f
      return nil if w <= 0.0
      [t.to_f, w]
    end

    # PURE: where an opening's flat panel actually lands on a curved wall.
    # This is what a door body will need in order to sit square in its hole:
    # the panel's two ends, its middle, and the direction it runs.
    #
    # A straight wall answers with the straight equivalent, so a caller never
    # needs to ask whether the wall is curved.
    # t = distance along the wall from the start; width = the opening width.
    # PURE: the two END cross-sections of a curved wall, in the same order the
    # straight builder uses - [s_pos, e_pos, e_neg, s_neg]. A curved wall's
    # ends are cut RADIALLY (square to the wall's own direction there), not
    # square to the straight line between its ends, so these are NOT the same
    # four points perpendicular_corners_xy would give.
    def self.curved_end_corners_xy(sx, sy, ex, ey, thickness, h_anchor, sag, tol = CURVE_TOL)
      fp = curved_footprint_xy(sx, sy, ex, ey, thickness, h_anchor, sag, tol)
      return nil unless fp
      n = fp.length / 2
      [fp[0], fp[n - 1], fp[n], fp[(2 * n) - 1]]
    end

    # PURE: which way the wall actually RUNS at one of its ends, as a unit
    # [dx, dy] in the natural start -> end sense.
    #
    # This is the whole fix for "the curve does not meet its neighbours". A
    # curved wall does not run along the straight line between its ends - at
    # its end it runs along the TANGENT to its arc. Mitering the neighbour
    # against the straight line cuts it at the wrong angle and leaves a step.
    # For a straight wall the tangent IS that line, so nothing changes.
    def self.corner_direction_xy(sx, sy, ex, ey, sag, side)
      chord = Math.sqrt((ex - sx)**2 + (ey - sy)**2)
      return nil if chord < 0.001
      straight = [(ex - sx) / chord, (ey - sy) / chord]
      return straight unless USE_CURVED_WALLS
      return straight if sag.nil? || sag.to_f.abs < MIN_ARC_SAG

      am = InteriorPro::ArcMath
      arc = am.from_chord_and_sag(sx, sy, ex, ey, sag.to_f)
      return straight unless arc
      d = side == :start ? 0.0 : am.length(arc)
      t = am.tangent_at_distance(arc, d)
      len = Math.sqrt(t[0]**2 + t[1]**2)
      len < 1e-9 ? straight : [t[0] / len, t[1] / len]
    end

    # PURE: how far along the wall a clicked point is, in inches from the
    # start. On a straight wall that is the plain projection onto the wall.
    # On a curved one it is measured ALONG THE CURVE, which is the only
    # measurement doors and windows ever use. A click past either end is
    # pulled back to that end rather than wrapping round the circle.
    def self.t_from_point_xy(sx, sy, ex, ey, sag, px, py)
      sx = sx.to_f; sy = sy.to_f; ex = ex.to_f; ey = ey.to_f
      chord = Math.sqrt((ex - sx)**2 + (ey - sy)**2)
      return nil if chord < 0.001
      straight = (((px - sx) * (ex - sx)) + ((py - sy) * (ey - sy))) / chord
      return straight unless USE_CURVED_WALLS
      return straight if sag.nil? || sag.to_f.abs < MIN_ARC_SAG

      am = InteriorPro::ArcMath
      arc = am.from_chord_and_sag(sx, sy, ex, ey, sag.to_f)
      return straight unless arc

      th = Math.atan2(py - arc[:cy], px - arc[:cx])
      dir = arc[:ccw] ? 1.0 : -1.0
      swept = am.norm_angle((th - arc[:a0]) * dir)
      d = arc[:r] * swept
      total = am.length(arc)
      return d if d <= total
      # Past the far end: snap to whichever end is nearer the long way round.
      circumference = arc[:r] * am::TWO_PI
      (d - total) <= (circumference - d) ? total : 0.0
    rescue StandardError
      nil
    end

    # PURE: is this corner too close to straight to be worth cutting?
    # u_into = the direction arriving at the corner, u_out = the direction
    # leaving it, both unit [x, y]. Returns true for a near-straight run AND
    # for a hairpin - neither has a miter that means anything.
    def self.corner_too_straight?(u_into, u_out, max_deg = COLLINEAR_CORNER_DEG)
      cross = (u_into[0] * u_out[1]) - (u_into[1] * u_out[0])
      dot   = (u_into[0] * u_out[0]) + (u_into[1] * u_out[1])
      turn  = Math.atan2(cross.abs, dot) * 180.0 / Math::PI   # 0..180
      turn < max_deg || turn > (180.0 - max_deg)
    end

    # PURE: is this miter so far from the wall ends it would read as a tear?
    # miter_pts = the two candidate corner points, ep_a / ep_b = the two
    # walls' drawn endpoints at this corner, all plain [x, y]. The cap
    # scales with the combined thickness (see CURVE_MITER_REACH). Only
    # corners with a curve in them are ever asked.
    def self.curve_miter_too_far?(miter_pts, ep_a, ep_b, t_a, t_b, factor = CURVE_MITER_REACH)
      cap = (t_a.to_f + t_b.to_f) * factor.to_f
      return true if cap <= 0.0
      miter_pts.any? do |m|
        [ep_a, ep_b].any? do |e|
          Math.sqrt(((m[0] - e[0])**2) + ((m[1] - e[1])**2)) > cap
        end
      end
    end

    # PURE: how far a wall's centreline sits off its DRAWN line, given the
    # anchor. Same rule wall_data uses; pulled out so the corner code can
    # rebuild a centreline reference point at either end.
    def self.centerline_offset(h_anchor, thickness)
      case h_anchor
      when 'left'  then thickness.to_f / 2.0
      when 'right' then -thickness.to_f / 2.0
      else 0.0
      end
    end

    # Wall-group flavour of corner_direction_xy. Returns a Geom::Vector3d.
    def self.corner_direction(group, data, side)
      d = corner_direction_xy(data[:drawn_start][0], data[:drawn_start][1],
                              data[:drawn_end][0],   data[:drawn_end][1],
                              curved_wall?(group) ? wall_sag(group) : 0.0, side)
      return nil unless d
      Geom::Vector3d.new(d[0], d[1], 0)
    rescue StandardError
      nil
    end

    def self.opening_pocket(sx, sy, ex, ey, sag, t, width)
      sx = sx.to_f; sy = sy.to_f; ex = ex.to_f; ey = ey.to_f
      t = t.to_f; width = width.to_f
      return nil if width <= 0.0
      chord = Math.sqrt((ex - sx)**2 + (ey - sy)**2)
      return nil if chord < 0.001

      am = InteriorPro::ArcMath
      arc = (USE_CURVED_WALLS && !sag.nil? && sag.to_f.abs >= MIN_ARC_SAG) ?
              am.from_chord_and_sag(sx, sy, ex, ey, sag.to_f) : nil

      unless arc
        u = [(ex - sx) / chord, (ey - sy) / chord]
        return nil if t - width / 2.0 < -1e-6 || t + width / 2.0 > chord + 1e-6
        pad = [POCKET_PAD, t - width / 2.0, chord - (t + width / 2.0)].min
        pad = 0.0 if pad < 0.0
        c = [sx + u[0] * t, sy + u[1] * t]
        return { d0: t - width / 2.0, d1: t + width / 2.0,
                 panel_d0: t - width / 2.0 - pad, panel_d1: t + width / 2.0 + pad,
                 panel_p0: [sx + u[0] * (t - width / 2.0 - pad), sy + u[1] * (t - width / 2.0 - pad)],
                 panel_p1: [sx + u[0] * (t + width / 2.0 + pad), sy + u[1] * (t + width / 2.0 + pad)],
                 p0: [c[0] - u[0] * width / 2.0, c[1] - u[1] * width / 2.0],
                 p1: [c[0] + u[0] * width / 2.0, c[1] + u[1] * width / 2.0],
                 center: c, dir: u, width: width, curved: false }
      end

      bare = am.half_arc_for_chord(arc, width)
      return nil unless bare
      total = am.length(arc)
      return nil if t - bare < -1e-6 || t + bare > total + 1e-6

      half = padded_half_arc(arc, t, width, total)
      return nil unless half
      pd0 = t - half
      pd1 = t + half
      pp0 = am.point_at_distance(arc, pd0)
      pp1 = am.point_at_distance(arc, pd1)
      dx = pp1[0] - pp0[0]
      dy = pp1[1] - pp0[1]
      len = Math.sqrt(dx * dx + dy * dy)
      return nil if len < 1e-9
      u = [dx / len, dy / len]
      # The opening sits in the MIDDLE of its flat panel, and its two ends lie
      # ON that panel - not on the curve - so the hole is cut in flat wall.
      c = [(pp0[0] + pp1[0]) / 2.0, (pp0[1] + pp1[1]) / 2.0]
      { d0: t - bare, d1: t + bare,
        panel_d0: pd0, panel_d1: pd1, panel_p0: pp0, panel_p1: pp1,
        p0: [c[0] - u[0] * width / 2.0, c[1] - u[1] * width / 2.0],
        p1: [c[0] + u[0] * width / 2.0, c[1] + u[1] * width / 2.0],
        center: c, dir: u, width: width, curved: true }
    end

    # The footprint for a real wall group, or nil to build it straight.
    def self.curved_footprint_for(group, data)
      return nil unless data && group&.valid?
      return nil unless curved_wall?(group)

      fp = curved_footprint_xy(data[:drawn_start][0], data[:drawn_start][1],
                               data[:drawn_end][0],   data[:drawn_end][1],
                               data[:thickness], data[:h_anchor], wall_sag(group),
                               CURVE_TOL, read_door_openings(group))
      return nil unless fp
      apply_corner_overrides(fp, group)
    end

    # Pull the four END points of the footprint from corners_xy, so a curved
    # wall gets mitered into its neighbours exactly like a straight one. All
    # the points in between - the curve itself - are untouched.
    #
    # corners_xy always holds the truth for the two ends: with no neighbour it
    # holds the plain radial cut (see compute_perpendicular_corners_from_data),
    # and after a corner join it holds the miter.
    def self.apply_corner_overrides(fp, group)
      flat = group.get_attribute('InteriorPro', 'corners_xy')
      return fp unless flat.is_a?(Array) && flat.length == 8
      return fp unless flat.all? { |v| v.is_a?(Numeric) }
      n = fp.length / 2
      return fp if n < 2
      out = fp.dup
      out[0]           = [flat[0], flat[1]]   # s_pos
      out[n - 1]       = [flat[2], flat[3]]   # e_pos
      out[n]           = [flat[4], flat[5]]   # e_neg
      out[(2 * n) - 1] = [flat[6], flat[7]]   # s_neg
      out
    rescue StandardError => e
      puts "[WallTool] apply_corner_overrides: #{e.message}"
      fp
    end

    # Paint a curved wall's two long sides. The straight painter classifies
    # every face against ONE wall direction; on a curve each facet points a
    # different way, so instead we ask each facet whether it looks AWAY from
    # the arc centre (outer side) or TOWARDS it (inner side). End caps look
    # sideways and are skipped, top and bottom look up/down and are skipped.
    def self.paint_curved_wall_long_faces!(group, ext_mat, int_mat)
      return unless group&.valid? && ext_mat && int_mat

      sx = group.get_attribute('InteriorPro', 'start_x')
      sy = group.get_attribute('InteriorPro', 'start_y')
      ex = group.get_attribute('InteriorPro', 'end_x')
      ey = group.get_attribute('InteriorPro', 'end_y')
      return unless sx && sy && ex && ey

      am = InteriorPro::ArcMath
      arc = am.from_chord_and_sag(sx.to_f, sy.to_f, ex.to_f, ey.to_f, wall_sag(group))
      return unless arc

      # Exterior stays the RIGHT side of start -> end, same rule as a straight
      # wall. Right = the negative offset side, which is the far-from-centre
      # side exactly when the centre lies to the left of travel.
      ext_is_outer = am.center_side(arc) > 0

      inst = InteriorPro::WallTool.new
      ext_material = inst.load_or_create_material(ext_mat)
      int_material = inst.load_or_create_material(int_mat)

      group.entities.grep(Sketchup::Face).each do |f|
        n = f.normal
        next if n.z.abs > 0.5                       # top / bottom
        c = f.bounds.center
        rx = c.x - arc[:cx]
        ry = c.y - arc[:cy]
        len = Math.sqrt(rx * rx + ry * ry)
        next if len < 1e-6
        radial = (n.x * rx + n.y * ry) / len
        next if radial.abs < 0.5                    # end cap
        outer = radial > 0
        f.material = (outer == ext_is_outer) ? ext_material : int_material
        f.back_material = nil
      end
    rescue StandardError => e
      puts "[WallTool] paint_curved_wall_long_faces!: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    end

    # Cut every door opening through a curved wall.
    #
    # The curved wall is one solid, built by pushing its floor outline
    # upwards. Each opening already has a FLAT panel waiting for it in that
    # outline, so the hole is simply drawn on that panel and pushed straight
    # through to the far side. The panel is a little wider than the hole, so
    # the cut never lands on the seam where the curve starts again.
    #
    # Returns how many holes were cut.
    def self.punch_curved_openings!(group, z_offset)
      return 0 unless group&.valid?
      openings = read_door_openings(group)
      return 0 if openings.empty?

      sx = group.get_attribute('InteriorPro', 'start_x').to_f
      sy = group.get_attribute('InteriorPro', 'start_y').to_f
      ex = group.get_attribute('InteriorPro', 'end_x').to_f
      ey = group.get_attribute('InteriorPro', 'end_y').to_f
      thickness = group.get_attribute('InteriorPro', 'thickness').to_f
      anchor = (group.get_attribute('InteriorPro', 'anchor') || 'bottom-center').to_s
      h_anchor = anchor.split('-')[1] || 'center'
      sag = wall_sag(group)
      return 0 if thickness <= 0.0

      am = InteriorPro::ArcMath
      arc = am.from_chord_and_sag(sx, sy, ex, ey, sag)
      return 0 unless arc
      o_pos, o_neg = anchor_side_offsets(thickness, h_anchor)
      cut = 0

      openings.each do |o|
        pk = opening_pocket(sx, sy, ex, ey, sag, o[:t], o[:width])
        next unless pk

        z1 = z_offset.to_f + o[:floor_offset].to_f
        z2 = z1 + o[:height].to_f
        next if (z2 - z1) < 0.01

        # The panel's own two faces, taken straight from the wall outline so
        # the hole is drawn EXACTLY on the face and never a hair inside it.
        a = am.offset_point_at_distance(arc, pk[:panel_d0], o_pos)
        b = am.offset_point_at_distance(arc, pk[:panel_d1], o_pos)
        a2 = am.offset_point_at_distance(arc, pk[:panel_d0], o_neg)
        next unless a && b && a2

        ux = b[0] - a[0]
        uy = b[1] - a[1]
        ul = Math.sqrt(ux * ux + uy * uy)
        next if ul < 0.01
        ux /= ul
        uy /= ul
        nx = -uy
        ny = ux

        # How deep to push: the straight distance from this face to the one
        # behind it. On a curve that is a touch less than the wall thickness,
        # and pushing the wrong amount would either miss or poke out the back.
        depth = ((a2[0] - a[0]) * nx) + ((a2[1] - a[1]) * ny)
        next if depth.abs < 0.01

        # The opening sits in the middle of the panel face.
        mx = (a[0] + b[0]) / 2.0
        my = (a[1] + b[1]) / 2.0
        hw = o[:width].to_f / 2.0
        next if hw <= 0.0 || (2.0 * hw) > (ul - 0.02)
        p1x = mx - ux * hw
        p1y = my - uy * hw
        p2x = mx + ux * hw
        p2y = my + uy * hw

        rect = [Geom::Point3d.new(p1x, p1y, z1),
                Geom::Point3d.new(p2x, p2y, z1),
                Geom::Point3d.new(p2x, p2y, z2),
                Geom::Point3d.new(p1x, p1y, z2)]
        face = begin
          group.entities.add_face(rect)
        rescue StandardError
          nil
        end
        next unless face && face.valid?

        pushv = Geom::Vector3d.new(nx * depth, ny * depth, 0)
        sign = face.normal.dot(pushv) >= 0 ? 1.0 : -1.0
        begin
          face.pushpull(depth.abs * sign)
          cut += 1
        rescue StandardError => e
          puts "[WallTool] punch_curved_openings!: #{e.message}"
        end
      end
      cut
    rescue StandardError => e
      puts "[WallTool] punch_curved_openings!: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      0
    end

    # LOOK ONLY (2026-08-11). Draws the outline a curved wall WOULD have once
    # its doors and windows get their flat panels, as loose lines in their own
    # group. Nothing about the real wall is touched - this is here so the
    # shape can be checked before any hole is cut. Delete the group when done,
    # or call clear_pocket_preview!.
    PREVIEW_GROUP_NAME = 'InteriorPro_PocketPreview' unless const_defined?(:PREVIEW_GROUP_NAME, false)

    def self.clear_pocket_preview!
      model = Sketchup.active_model
      gone = 0
      model.entities.to_a.each do |e|
        next unless e.is_a?(Sketchup::Group) && e.valid?
        next unless e.name == PREVIEW_GROUP_NAME
        e.erase!
        gone += 1
      end
      puts "[WallTool] removed #{gone} pocket preview(s)"
      gone
    end

    def self.preview_pockets!(wall)
      unless wall&.valid? && wall.get_attribute('InteriorPro', 'type') == 'wall'
        puts '[WallTool] select an Interior Pro wall first'
        return false
      end
      sag = wall_sag(wall)
      if sag.abs < MIN_ARC_SAG
        puts '[WallTool] that wall is straight - bow it first, then preview'
        return false
      end
      sx = wall.get_attribute('InteriorPro', 'start_x').to_f
      sy = wall.get_attribute('InteriorPro', 'start_y').to_f
      ex = wall.get_attribute('InteriorPro', 'end_x').to_f
      ey = wall.get_attribute('InteriorPro', 'end_y').to_f
      thickness = wall.get_attribute('InteriorPro', 'thickness').to_f
      anchor = (wall.get_attribute('InteriorPro', 'anchor') || 'bottom-center').to_s
      h_anchor = anchor.split('-')[1] || 'center'
      openings = read_door_openings(wall)
      if openings.empty?
        puts '[WallTool] that wall has no doors or windows - nothing to pocket'
        return false
      end

      fp = curved_footprint_xy(sx, sy, ex, ey, thickness, h_anchor, sag, CURVE_TOL, openings)
      unless fp
        puts '[WallTool] those openings do not fit on this curve (too wide, off the end, or overlapping)'
        return false
      end

      model = Sketchup.active_model
      model.start_operation('InteriorPro Pocket Preview', true)
      begin
        clear_pocket_preview!
        z = wall.bounds.min.z + 0.25
        grp = model.entities.add_group
        grp.name = PREVIEW_GROUP_NAME
        pts = fp.map { |c| Geom::Point3d.new(c[0], c[1], z) }
        pts.each_with_index { |p, i| grp.entities.add_line(p, pts[(i + 1) % pts.length]) }
        # Mark each flat panel with a line across it, so it is obvious which
        # stretch went straight.
        openings.each do |o|
          pk = opening_pocket(sx, sy, ex, ey, sag, o[:t], o[:width])
          next unless pk
          grp.entities.add_line(Geom::Point3d.new(pk[:p0][0], pk[:p0][1], z),
                                Geom::Point3d.new(pk[:p1][0], pk[:p1][1], z))
        end
        model.commit_operation
      rescue StandardError => e
        model.abort_operation
        puts "[WallTool] preview_pockets!: #{e.message}"
        return false
      end
      puts "[WallTool] preview drawn: #{fp.length} outline points, #{openings.length} flat panel(s)"
      true
    end

    # Hide the seams between the flat panels so a curved wall looks like one
    # smooth surface instead of a folded paper fan.
    #
    # Only the UPRIGHT seams are touched, and only where the two panels either
    # side of them are nearly in line. The wall's own end corners, where the
    # panels meet at a real angle, are left alone - otherwise the wall would
    # lose its edges and look like a smudge.
    def self.smooth_curved_wall_edges!(group)
      return unless group&.valid?
      cos_limit = Math.cos(CURVE_SMOOTH_MAX_ANGLE * Math::PI / 180.0)
      softened = 0
      group.entities.grep(Sketchup::Edge).each do |e|
        faces = e.faces
        next unless faces.length == 2
        v = e.line[1]
        len = v.length
        next if len < 1e-9
        next if (v.z.abs / len) < 0.9          # not an upright seam
        next if faces[0].normal.dot(faces[1].normal) < cos_limit   # a real corner
        e.soft = true
        e.smooth = true
        softened += 1
      end
      softened
    rescue StandardError => e
      puts "[WallTool] smooth_curved_wall_edges!: #{e.message}"
      0
    end

    # THE ONE ENTRY POINT for curving a wall. Both things the user asked for
    # end here: dragging a wall's middle, and the 3-click arc tool.
    # sag is signed, in inches, positive = left of start -> end.
    # Pass 0 to straighten the wall again.
    def self.set_wall_sag!(wall, sag, wrap_operation: true)
      return false unless wall&.valid?
      return false unless wall.get_attribute('InteriorPro', 'type') == 'wall'

      sag = sag.to_f
      straight = sag.abs < MIN_ARC_SAG

      sx = wall.get_attribute('InteriorPro', 'start_x').to_f
      sy = wall.get_attribute('InteriorPro', 'start_y').to_f
      ex = wall.get_attribute('InteriorPro', 'end_x').to_f
      ey = wall.get_attribute('InteriorPro', 'end_y').to_f
      thickness = wall.get_attribute('InteriorPro', 'thickness').to_f
      height = wall.get_attribute('InteriorPro', 'height').to_f
      anchor = wall.get_attribute('InteriorPro', 'anchor') || 'bottom-center'
      _v_anchor, h_anchor = InteriorPro::WallTool.new.parse_anchor(anchor)

      # Refuse BEFORE touching the model if the curve cannot be built, so a
      # bad number can never leave a wall half-rebuilt.
      unless straight
        if curved_footprint_xy(sx, sy, ex, ey, thickness, h_anchor, sag,
                               CURVE_TOL, read_door_openings(wall)).nil?
          puts "[WallTool] a bow of #{sag}\" is too tight for a #{thickness}\" wall here. Nothing changed."
          return false
        end

      end

      # The wall the doors and windows are still standing on. Read it BEFORE
      # anything changes - it is the "from" half of the move that carries them
      # onto the new shape (2026-08-12).
      old_geo = begin
        RESEAT_OPENINGS_ON_CURVE ? InteriorPro::DoorManager.wall_geometry(wall) : nil
      rescue StandardError
        nil
      end

      model = Sketchup.active_model
      model.start_operation('InteriorPro Curve Wall', true) if wrap_operation
      begin
        if straight
          wall.delete_attribute('InteriorPro', 'arc_sag')
        else
          wall.set_attribute('InteriorPro', 'arc_sag', sag)
        end

        # Keep the schedule numbers honest: a curved wall is longer than the
        # straight line between its ends.
        chord = Math.sqrt((ex - sx)**2 + (ey - sy)**2)
        arc = straight ? nil : InteriorPro::ArcMath.from_chord_and_sag(sx, sy, ex, ey, sag)
        length_in = arc ? InteriorPro::ArcMath.length(arc) : chord
        wall.set_attribute('InteriorPro', 'length_in', length_in)
        wall.set_attribute('InteriorPro', 'gross_area_sqft', (length_in * height) / 144.0)
        wall.set_attribute('InteriorPro', 'volume_cuft', (length_in * height * thickness) / 1728.0)

        inst = InteriorPro::WallTool.new
        data = inst.wall_data(wall)
        raise 'wall_data unavailable' unless data

        # Throw away the old end cuts and start from this wall's own square
        # ends - a miter cut for a straight wall is wrong once it bends, and
        # vice versa.
        corners = inst.compute_perpendicular_corners_from_data(data)
        raise 'could not work out the wall ends' unless corners
        inst.save_corners_attr(wall, corners)
        inst.rebuild_wall_geometry(wall, corners, data)

        # Bring the doors and windows across NOW, while old_geo still
        # describes the wall they are standing on. It has to happen before
        # align_curve_lanes!, because that can move a body sideways again -
        # and swap_wall_side! does its own reseat for that. Each change
        # reseats straight after itself, so nothing is ever moved twice.
        if old_geo
          begin
            InteriorPro::DoorManager.reseat_hosted_openings!(wall, old_geo)
          rescue StandardError => e
            puts "[WallTool] set_wall_sag! reseat: #{e.message}"
          end
        end

        # A curve can only weld cleanly onto a neighbour whose body sits on
        # the SAME side of the drawn line. Re-seat whoever needs it - the
        # user draws, the plugin sorts the sides out (2026-08-12).
        align_curve_lanes!(wall, model) unless straight

        # Now re-cut the corners against the neighbours. This is what makes a
        # curved wall meet the walls it grew out of instead of leaving a step.
        inst.join_corners(wall, model, allow_centerline_fallback: true)

        model.commit_operation if wrap_operation
      rescue StandardError => e
        model.abort_operation if wrap_operation
        puts "[WallTool] set_wall_sag!: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
        return false
      end
      true
    end

    def self.native_floor_z(v_anchor, height)
      case v_anchor
      when 'top' then -height
      when 'center' then -height / 2.0
      else 0.0
      end
    end

    # Spine offset along DoorManager n and pushpull distance to match build_geometry_in_group footprint.
    def self.native_spine_offset_and_pull(h_anchor, thickness)
      case h_anchor
      when 'left'
        [0.0, -thickness]
      when 'right'
        [thickness, -thickness]
      else
        [-thickness / 2.0, thickness]
      end
    end

    def self.rebuild_wall_native_geometry!(wall)
      return false unless wall&.valid?

      sx = wall.get_attribute('InteriorPro', 'start_x')
      sy = wall.get_attribute('InteriorPro', 'start_y')
      ex = wall.get_attribute('InteriorPro', 'end_x')
      ey = wall.get_attribute('InteriorPro', 'end_y')
      thickness = wall.get_attribute('InteriorPro', 'thickness')
      height = wall.get_attribute('InteriorPro', 'height')
      return false unless sx && sy && ex && ey && thickness && height

      anchor = wall.get_attribute('InteriorPro', 'anchor') || 'bottom-center'
      v_anchor, h_anchor = InteriorPro::DoorManager.parse_anchor(anchor)

      thickness_f = thickness.to_f
      height_f = height.to_f
      drawn_start = Geom::Point3d.new(sx.to_f, sy.to_f, 0)
      drawn_end = Geom::Point3d.new(ex.to_f, ey.to_f, 0)
      wall_vec = drawn_end - drawn_start
      return false if wall_vec.length < 0.1

      unit = wall_vec.clone
      unit.normalize!
      n = InteriorPro::DoorManager.horizontal_perpendicular(unit)

      spine_offset, thickness_pull = native_spine_offset_and_pull(h_anchor, thickness_f)
      spine_start = drawn_start.offset(n, spine_offset)
      spine_end = drawn_end.offset(n, spine_offset)
      z_base = native_floor_z(v_anchor, height_f)

      openings = read_door_openings(wall)
      wall.entities.clear!
      build_wall_with_openings_oriented(
        wall.entities,
        [spine_start.x, spine_start.y, z_base],
        [spine_end.x, spine_end.y, z_base],
        height_f,
        thickness_pull,
        openings
      )
      apply_native_miter_corners!(wall, drawn_start, drawn_end, thickness_f, h_anchor)
      ext_mat, int_mat = wall_side_material_names(wall)
      paint_wall_long_faces!(wall, ext_mat, int_mat)
      # Board and Batten is real 3D strips, and this rebuild wiped them out
      # along with everything else. Put them back, or the wall ends up as a
      # blank slab wearing an empty material. (2026-08-11: this is what turned
      # a shed wall black the moment a window went into it.)
      InteriorPro::WallTool.new.add_exterior_siding(wall, ext_mat)
      true
    rescue StandardError => e
      puts "[WallTool] rebuild_wall_native_geometry!: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      false
    end

    # Flip which side of a wall is EXTERIOR (2026-08-06: the 2D->3D
    # generator produced one flipped wall on the user's Mac; right-click
    # fix). Swaps the drawn direction (start<->end), mirrors h_anchor and
    # door positions, rebuilds in place. The body stays exactly where it
    # was - only exterior/interior swap sides.
    def self.flip_wall_faces!(wall, wrap_operation: true)
      return false unless wall&.valid? &&
                          wall.get_attribute('InteriorPro', 'type') == 'wall'
      sx = wall.get_attribute('InteriorPro', 'start_x').to_f
      sy = wall.get_attribute('InteriorPro', 'start_y').to_f
      ex = wall.get_attribute('InteriorPro', 'end_x').to_f
      ey = wall.get_attribute('InteriorPro', 'end_y').to_f
      model = Sketchup.active_model
      model.start_operation('InteriorPro Flip Wall', true) if wrap_operation
      wall.set_attribute('InteriorPro', 'start_x', ex)
      wall.set_attribute('InteriorPro', 'start_y', ey)
      wall.set_attribute('InteriorPro', 'end_x', sx)
      wall.set_attribute('InteriorPro', 'end_y', sy)
      # A bow is signed relative to start->end. Swapping the ends flips the
      # frame, so the sign must flip with it or the wall jumps to the other
      # side of its own line (found wiring the 2D editor, 2026-08-12).
      old_sag = wall.get_attribute('InteriorPro', 'arc_sag')
      wall.set_attribute('InteriorPro', 'arc_sag', -old_sag.to_f) unless old_sag.nil?
      anchor = (wall.get_attribute('InteriorPro', 'anchor') || 'bottom-center').to_s
      parts = anchor.split('-')
      if parts.length == 2
        mirrored = { 'left' => 'right', 'right' => 'left' }[parts[1]]
        wall.set_attribute('InteriorPro', 'anchor', "#{parts[0]}-#{mirrored}") if mirrored
      end
      len = Math.sqrt((ex - sx)**2 + (ey - sy)**2)
      openings = read_door_openings(wall)
      unless openings.empty?
        openings.each { |o| o[:t] = len - o[:t] }
        persist_door_openings!(wall, openings)
      end
      ok = rebuild_wall_native!(wall)
      if wrap_operation
        ok ? model.commit_operation : model.abort_operation
      end
      puts "[WallTool] flip_wall_faces!: #{ok ? 'flipped' : 'FAILED'}"
      ok
    rescue StandardError => e
      if wrap_operation
        begin
          model.abort_operation
        rescue StandardError
          nil
        end
      end
      puts "[WallTool] flip_wall_faces!: #{e.message}"
      false
    end

    # Flip SEVERAL walls at once (user 2026-08-12: "if I select a few walls
    # together I should be able to turn their faces to the other side, all
    # together"). One undo step for the whole lot; anything in the selection
    # that is not a wall is quietly ignored. Each wall goes through the very
    # same flip_wall_faces! the single-wall menu item uses, so there is only
    # one flip behaviour to maintain.
    def self.flip_wall_faces_multi!(entities)
      walls = Array(entities).select do |e|
        e.respond_to?(:get_attribute) && e.valid? &&
          e.get_attribute('InteriorPro', 'type') == 'wall'
      end
      return 0 if walls.empty?
      return (flip_wall_faces!(walls.first) ? 1 : 0) if walls.length == 1

      model = Sketchup.active_model
      model.start_operation('InteriorPro Flip Walls', true)
      n = 0
      walls.each { |w| n += 1 if flip_wall_faces!(w, wrap_operation: false) }
      model.commit_operation
      puts "[WallTool] flip_wall_faces_multi!: #{n}/#{walls.length} walls flipped"
      n
    rescue StandardError => e
      begin
        Sketchup.active_model.abort_operation
      rescue StandardError
        nil
      end
      puts "[WallTool] flip_wall_faces_multi!: #{e.message}"
      0
    end

    # ==== AUTOMATIC LANE ALIGNMENT (2026-08-12) ==========================
    # THE BUG (user, rightly annoyed): draw walls, bend one - and the corner
    # comes out with a 5" tooth. Cause: a curve can only weld cleanly onto a
    # neighbour whose BODY sits on the same side of the drawn line, and the
    # plugin happily let them sit on opposite sides. The user should never
    # need a button for that - so bending a wall now aligns the sides by
    # itself, inside the same undo step. The manual right-click tool stays
    # for exotic cases, but the normal flow never needs it.

    MIRROR_H = { 'left' => 'right', 'right' => 'left' }.freeze unless const_defined?(:MIRROR_H, false)

    def self.wall_h_anchor(wall)
      a = (wall.get_attribute('InteriorPro', 'anchor') || 'bottom-center').to_s
      a == 'center' ? 'center' : (a.split('-')[1] || 'center')
    end

    # The two lips of a wall's end cut, from attributes alone (pure trial -
    # nothing is touched), optionally pretending the anchor were mirrored.
    def self.end_cuts_xy(wall, side, h_override = nil)
      sx = wall.get_attribute('InteriorPro', 'start_x').to_f
      sy = wall.get_attribute('InteriorPro', 'start_y').to_f
      ex = wall.get_attribute('InteriorPro', 'end_x').to_f
      ey = wall.get_attribute('InteriorPro', 'end_y').to_f
      th = wall.get_attribute('InteriorPro', 'thickness').to_f
      h  = h_override || wall_h_anchor(wall)
      c = if curved_wall?(wall)
            curved_end_corners_xy(sx, sy, ex, ey, th, h, wall_sag(wall))
          else
            new.perpendicular_corners_xy(Geom::Point3d.new(sx, sy, 0),
                                         Geom::Point3d.new(ex, ey, 0), th, h)
          end
      return nil unless c
      side == :start ? [c[0], c[3]] : [c[1], c[2]]
    rescue StandardError
      nil
    end

    # Would this corner take weld_corner!'s EXACT-SEAM branch? Same test the
    # weld itself runs: pair the four lips by nearness, both pairs within
    # 1.2 x the fatter thickness.
    def self.corner_snaps?(wa, sa, wb, sb, ha_override: nil, hb_override: nil)
      a = end_cuts_xy(wa, sa, ha_override)
      b = end_cuts_xy(wb, sb, hb_override)
      return false unless a && b
      dd = ->(p, q) { Math.hypot(p[0] - q[0], p[1] - q[1]) }
      st = dd.call(a[0], b[0]) + dd.call(a[1], b[1])
      cr = dd.call(a[0], b[1]) + dd.call(a[1], b[0])
      pair = st <= cr ? [[a[0], b[0]], [a[1], b[1]]] : [[a[0], b[1]], [a[1], b[0]]]
      thr = [wa.get_attribute('InteriorPro', 'thickness').to_f,
             wb.get_attribute('InteriorPro', 'thickness').to_f].max * 1.2
      pair.all? { |p, q| dd.call(p, q) <= thr }
    rescue StandardError
      false
    end

    # Align the body sides around a curved wall so every corner can weld to
    # one exact seam. Preference order: first re-seat the CURVE itself (it is
    # the thing that just changed), then any straight neighbour that still
    # clashes - but only a neighbour that is safe to move (not curved, not
    # center-anchored, hosts no window, same category). Runs inside the
    # caller's operation; returns how many walls were re-seated.
    def self.align_curve_lanes!(wall, model = Sketchup.active_model)
      return 0 unless curved_wall?(wall)
      return 0 unless MIRROR_H[wall_h_anchor(wall)]
      cat = (wall.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s

      walls = model.active_entities.grep(Sketchup::Group).select do |g|
        g.valid? && g != wall && g.get_attribute('InteriorPro', 'type') == 'wall' &&
          (g.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s == cat
      end
      ends = []
      [[:start, 'start_x', 'start_y'], [:end, 'end_x', 'end_y']].each do |side, kx, ky|
        px = wall.get_attribute('InteriorPro', kx).to_f
        py = wall.get_attribute('InteriorPro', ky).to_f
        nb = nil
        nb_side = nil
        walls.each do |o|
          break if nb
          [[:start, 'start_x', 'start_y'], [:end, 'end_x', 'end_y']].each do |os, okx, oky|
            next if nb
            d = Math.hypot(o.get_attribute('InteriorPro', okx).to_f - px,
                           o.get_attribute('InteriorPro', oky).to_f - py)
            if d < 1.0
              nb = o
              nb_side = os
            end
          end
        end
        ends << [side, nb, nb_side] if nb
      end
      return 0 if ends.empty?

      snap_now = ends.count { |s, nb, ns| corner_snaps?(wall, s, nb, ns) }
      return 0 if snap_now == ends.length

      mirrored = MIRROR_H[wall_h_anchor(wall)]
      snap_sw = ends.count { |s, nb, ns| corner_snaps?(wall, s, nb, ns, ha_override: mirrored) }

      swapped = []
      # Re-seat the curve when that helps - or on a tie, because the curve is
      # the newcomer and its spring wall is usually the cheaper thing to move.
      if snap_sw > snap_now || (snap_sw == snap_now && snap_now < ends.length)
        swapped << wall if swap_wall_side!(wall, wrap_operation: false)
      end
      ends.each do |side, nb, nb_side|
        next if corner_snaps?(wall, side, nb, nb_side)
        next if curved_wall?(nb)
        nbh = wall_h_anchor(nb)
        next unless MIRROR_H[nbh]
        next if hosted_window_count(nb) > 0
        next unless corner_snaps?(wall, side, nb, nb_side, hb_override: MIRROR_H[nbh])
        swapped << nb if swap_wall_side!(nb, wrap_operation: false)
      end
      unless swapped.empty?
        inst = new
        touched = ([wall] + ends.map { |_s, nb, _ns| nb }).uniq
        2.times { touched.each { |w| inst.join_corners(w, model) } }
        puts "[WallTool] align_curve_lanes!: re-seated #{swapped.length} wall(s) so the curve corners weld clean"
      end
      swapped.length
    rescue StandardError => e
      puts "[WallTool] align_curve_lanes!: #{e.message}"
      0
    end

    # Move a wall's BODY to the other side of its drawn line (user
    # 2026-08-12, after the left arc corner): the line the user drew stays
    # exactly where it is; only the thickness changes sides, by mirroring
    # the anchor (left <-> right). This is NOT flip_wall_faces! - flip keeps
    # the body in place and swaps which face is exterior; this MOVES the
    # body. It exists because two walls whose bodies sit on opposite sides
    # of the same corner can only ever meet with a shoulder - putting both
    # bodies on the same side is what makes the seam exact.
    #
    # A wall hosting a WINDOW is refused: moving the body rebuilds the wall
    # and a window's hole is not recorded anywhere (see wall_has_openings?),
    # so the rebuild would bury it. Doors re-cut themselves and are fine.
    # A center-anchored wall has no "other side" and is skipped.
    def self.swap_wall_side!(wall, wrap_operation: true)
      return false unless wall&.valid? &&
                          wall.get_attribute('InteriorPro', 'type') == 'wall'
      anchor = (wall.get_attribute('InteriorPro', 'anchor') || 'bottom-center').to_s
      parts = anchor.split('-')
      mirrored = { 'left' => 'right', 'right' => 'left' }[parts.last]
      unless mirrored
        puts '[WallTool] swap_wall_side!: center anchor has no other side'
        return false
      end
      if hosted_window_count(wall) > 0
        UI.messagebox('This wall hosts a window - move the window first.')
        return false
      end

      model = Sketchup.active_model
      model.start_operation('InteriorPro Wall Body Side', true) if wrap_operation

      # The body is about to jump a full thickness sideways. The doors on it
      # are separate groups and were being left standing where the wall used
      # to be - so a door on a perfectly straight wall ended up inside the
      # house, exactly one wall thickness off (measured 6.000" on a 6" wall,
      # 2026-08-12). Read the wall they are still standing on first.
      old_geo = begin
        RESEAT_OPENINGS_ON_CURVE ? InteriorPro::DoorManager.wall_geometry(wall) : nil
      rescue StandardError
        nil
      end

      wall.set_attribute('InteriorPro', 'anchor',
                         parts.length == 2 ? "#{parts[0]}-#{mirrored}" : mirrored)
      tool = new
      data = tool.wall_data(wall)
      fresh = tool.compute_perpendicular_corners_from_data(data)
      raise 'could not recompute corners' unless fresh
      tool.save_corners_attr(wall, fresh)
      tool.rebuild_wall_geometry(wall, fresh, data)
      if old_geo
        begin
          InteriorPro::DoorManager.reseat_hosted_openings!(wall, old_geo)
        rescue StandardError => e
          puts "[WallTool] swap_wall_side! reseat: #{e.message}"
        end
      end
      model.commit_operation if wrap_operation
      puts '[WallTool] swap_wall_side!: body moved to the other side'
      true
    rescue StandardError => e
      begin
        model.abort_operation if wrap_operation
      rescue StandardError
        nil
      end
      puts "[WallTool] swap_wall_side!: #{e.message}"
      false
    end

    # The multi-wall wrapper, one undo step, then every corner is re-joined
    # (fix_corners_once pattern - proven): a moved body changes which cuts
    # meet at each of its corners, and its NEIGHBOURS' cuts have to follow.
    def self.swap_wall_side_multi!(entities)
      walls = Array(entities).select do |e|
        e.respond_to?(:get_attribute) && e.valid? &&
          e.get_attribute('InteriorPro', 'type') == 'wall'
      end
      return 0 if walls.empty?
      model = Sketchup.active_model
      model.start_operation('InteriorPro Wall Body Side', true)
      n = 0
      walls.each { |w| n += 1 if swap_wall_side!(w, wrap_operation: false) }
      if n > 0
        tool = new
        all = model.active_entities.grep(Sketchup::Group).select do |g|
          g.valid? && g.get_attribute('InteriorPro', 'type') == 'wall'
        end
        2.times { all.each { |w| tool.join_corners(w, model) } }
      end
      model.commit_operation
      puts "[WallTool] swap_wall_side_multi!: #{n}/#{walls.length} walls moved"
      n
    rescue StandardError => e
      begin
        Sketchup.active_model.abort_operation
      rescue StandardError
        nil
      end
      puts "[WallTool] swap_wall_side_multi!: #{e.message}"
      0
    end

    # Which walls in a closed exterior loop are drawn against the loop?
    # Pure geometry (testable): segs = [[sx, sy, ex, ey], ...] in any
    # order/direction. Returns the indices whose stored start->end runs
    # against the counter-clockwise traversal - the orientation where the
    # RIGHT side of start->end (this plugin's exterior side) faces out.
    # Returns [] when the segments do not form one clean closed loop.
    def self.reversed_loop_segments(segs, tol = 0.75)
      return [] if segs.nil? || segs.length < 3
      pts = segs.map { |g| [[g[0].to_f, g[1].to_f], [g[2].to_f, g[3].to_f]] }
      same = lambda do |a, b|
        (a[0] - b[0]).abs < tol && (a[1] - b[1]).abs < tol
      end
      order = [0]
      fwd = [true]
      used = { 0 => true }
      cur = pts[0][1]
      while order.length < segs.length
        nxt = nil
        dir = nil
        pts.each_with_index do |p, i|
          next if used[i]
          if same.call(p[0], cur)
            nxt = i
            dir = true
            break
          elsif same.call(p[1], cur)
            nxt = i
            dir = false
            break
          end
        end
        return [] if nxt.nil?
        used[nxt] = true
        order << nxt
        fwd << dir
        cur = dir ? pts[nxt][1] : pts[nxt][0]
      end
      return [] unless same.call(cur, pts[0][0]) # the loop must close
      verts = order.each_with_index.map { |i, k| fwd[k] ? pts[i][0] : pts[i][1] }
      area = 0.0
      verts.each_with_index do |p, k|
        q = verts[(k + 1) % verts.length]
        area += p[0] * q[1] - q[0] * p[1]
      end
      fwd = fwd.map { |d| !d } if area < 0.0 # force counter-clockwise
      order.each_with_index.reject { |_, k| fwd[k] }.map(&:first).sort
    rescue StandardError => e
      puts "[WallTool] reversed_loop_segments: #{e.message}"
      []
    end

    # 2D->3D (2026-08-06): the editor passes each wall's DRAWN direction
    # through as-is, and exterior is always the right side of start->end,
    # so a wall the user happened to draw backwards came out inside-out
    # (the user's Mac plan, wall a4a2ed66). Flip whoever disagrees with
    # the loop. Silently does nothing when the walls are not one closed
    # loop. Caller owns the model operation.
    def self.normalize_exterior_orientation!(walls)
      walls = (walls || []).select do |w|
        w&.valid? && w.get_attribute('InteriorPro', 'type') == 'wall' &&
          (w.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s == 'exterior'
      end
      return 0 if walls.length < 3
      segs = walls.map do |w|
        [w.get_attribute('InteriorPro', 'start_x').to_f,
         w.get_attribute('InteriorPro', 'start_y').to_f,
         w.get_attribute('InteriorPro', 'end_x').to_f,
         w.get_attribute('InteriorPro', 'end_y').to_f]
      end
      bad = reversed_loop_segments(segs)
      return 0 if bad.empty?
      n = 0
      bad.each { |i| n += 1 if flip_wall_faces!(walls[i], wrap_operation: false) }
      puts "[WallTool] normalize_exterior_orientation!: flipped #{n} backwards wall(s)"
      n
    rescue StandardError => e
      puts "[WallTool] normalize_exterior_orientation!: #{e.message}"
      0
    end

    def self.rebuild_wall_native!(wall)
      return false unless rebuild_wall_native_geometry!(wall)

      begin
        join_corners(wall, Sketchup.active_model)
      rescue StandardError => e
        puts "[WallTool] rebuild_wall_native! join_corners: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      end
      true
    rescue StandardError => e
      puts "[WallTool] rebuild_wall_native!: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      false
    end

    def self.build_wall_with_openings_test(ents, length, height, thickness, openings)
      floor_ops  = openings.select { |o| o[:floor_offset].to_f <= 0.001 }.sort_by { |o| o[:t] }
      raised_ops = openings.reject { |o| o[:floor_offset].to_f <= 0.001 }

      pts = [[0.0, 0.0]]
      floor_ops.each do |o|
        x1 = o[:t] - o[:width] / 2.0
        x2 = o[:t] + o[:width] / 2.0
        h  = o[:height].to_f
        pts << [x1, 0.0] << [x1, h] << [x2, h] << [x2, 0.0]
      end
      pts << [length, 0.0] << [length, height] << [0.0, height]

      face = ents.add_face(pts.map { |x, z| Geom::Point3d.new(x, 0, z) })
      return nil unless face

      raised_ops.each do |o|
        x1 = o[:t] - o[:width] / 2.0
        x2 = o[:t] + o[:width] / 2.0
        z1 = o[:floor_offset].to_f
        z2 = z1 + o[:height].to_f
        rect = [[x1, z1], [x2, z1], [x2, z2], [x1, z2]].map { |x, z| Geom::Point3d.new(x, 0, z) }
        hole = ents.add_face(rect)
        hole.erase! if hole
      end

      wall_face = ents.grep(Sketchup::Face).max_by(&:area)
      wall_face.pushpull(thickness) if wall_face
      wall_face
    end

    def self.build_wall_with_openings_oriented(ents, start_pt, end_pt, height, thickness, openings)
      openings = openings.compact.map { |o| normalize_door_opening(o) }.compact

      sp = Geom::Point3d.new(*start_pt)
      ep = Geom::Point3d.new(*end_pt)
      u = ep - sp
      length = u.length
      return nil if length < 1e-3
      u.normalize!
      up = Geom::Vector3d.new(0, 0, 1)
      n = u.cross(up)
      return nil if n.length < 1e-3
      n.normalize!
      pt = ->(s, z) { sp.offset(u, s).offset(up, z) }

      floor_ops  = openings.select { |o| o[:floor_offset].to_f <= 0.001 }.sort_by { |o| o[:t] }
      raised_ops = openings.reject { |o| o[:floor_offset].to_f <= 0.001 }

      outline = [pt.call(0.0, 0.0)]
      floor_ops.each do |o|
        x1 = o[:t] - o[:width] / 2.0
        x2 = o[:t] + o[:width] / 2.0
        h  = o[:height].to_f
        rise = o[:arch_rise].to_f
        if rise > 0.01
          # Arched door: up the left jamb, smooth arc across the top, down the
          # right jamb. Arc points sampled left-spring -> apex -> right-spring.
          outline << pt.call(x1, 0.0)
          outline.concat(arched_floor_top_points(pt, x1, x2, h, rise))
          outline << pt.call(x2, 0.0)
        else
          outline << pt.call(x1, 0.0) << pt.call(x1, h) << pt.call(x2, h) << pt.call(x2, 0.0)
        end
      end
      outline << pt.call(length, 0.0) << pt.call(length, height) << pt.call(0.0, height)

      face = ents.add_face(outline)
      return nil unless face

      raised_ops.each do |o|
        x1 = o[:t] - o[:width] / 2.0
        x2 = o[:t] + o[:width] / 2.0
        z1 = o[:floor_offset].to_f
        z2 = z1 + o[:height].to_f
        rise = o[:arch_rise].to_f
        if rise > 0.01
          cut_arched_opening_hole!(ents, pt, u, n, x1, x2, z1, z2, rise)
        else
          rect = [pt.call(x1, z1), pt.call(x2, z1), pt.call(x2, z2), pt.call(x1, z2)]
          hole = ents.add_face(rect)
          hole.erase! if hole
        end
      end

      wall_face = ents.grep(Sketchup::Face).max_by(&:area)
      wall_face.pushpull(thickness) if wall_face
      wall_face
    end

    # Cut a smooth arched hole (rectangular sides + circular arc top) into the
    # wall face at plane(pt). z2 = top of the arch apex; the arch springs from
    # z_spring = z2 - rise on both sides. rise is clamped to [0, half-width] so
    # the widest arch is a clean semicircle.
    #
    # IMPORTANT: built EXACTLY like the rectangular hole — one array of points to
    # a single add_face, then erase — just with arc points sampled across the top
    # instead of two corners. No add_arc / edge-by-edge building (that splits the
    # wall face into pieces and breaks the solid), and NO soft/smooth (that merges
    # the flat wall face with the reveal and breaks push/pull). Hard chords at 48
    # segments read as a smooth curve while keeping the wall a clean solid.
    ARCH_SEGMENTS = 48 unless const_defined?(:ARCH_SEGMENTS, false)
    def self.cut_arched_opening_hole!(ents, pt, u, n, x1, x2, z1, z2, rise)
      xc = (x1 + x2) / 2.0
      a  = (x2 - x1) / 2.0
      return if a <= 0.01
      rise = a if rise > a                       # clamp to semicircle
      z_spring = z2 - rise
      z_spring = z1 if z_spring < z1             # arch springs no lower than sill
      r  = (a * a + rise * rise) / (2.0 * rise)  # circle radius through springs+apex
      zc = z_spring + rise - r                   # circle center height (in s,z)
      th_r = Math.atan2(r - rise, a)             # right spring angle
      th_l = Math::PI - th_r                     # left spring angle

      # Same polygon the rectangle builds, but the top edge is the sampled arc.
      pts = [pt.call(x1, z1), pt.call(x2, z1)]   # sill: bottom-left, bottom-right
      (0..ARCH_SEGMENTS).each do |i|             # right spring -> apex -> left spring
        th = th_r + (th_l - th_r) * i / ARCH_SEGMENTS.to_f
        s  = xc + r * Math.cos(th)
        z  = zc + r * Math.sin(th)
        pts << pt.call(s, z)
      end

      hole = ents.add_face(pts)
      hole.erase! if hole
    rescue StandardError => e
      puts "[WallTool] cut_arched_opening_hole!: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    end

    # Arc points for an arched FLOOR opening (door): the curved top edge only,
    # sampled left-spring -> apex -> right-spring (inclusive). h = top of the
    # opening (apex height); the arch springs from h - rise. Returned as world
    # Point3d via the pt(s, z) lambda so they drop straight into the outline.
    def self.arched_floor_top_points(pt, x1, x2, h, rise, segs = ARCH_SEGMENTS)
      xc = (x1 + x2) / 2.0
      a  = (x2 - x1) / 2.0
      return [pt.call(x1, h), pt.call(x2, h)] if a <= 0.01
      rise = a if rise > a
      spring = h - rise
      spring = 0.0 if spring < 0.0
      r  = (a * a + rise * rise) / (2.0 * rise)
      zc = spring + rise - r
      th_r = Math.atan2(r - rise, a)          # right spring angle
      th_l = Math::PI - th_r                  # left spring angle
      (0..segs).map do |i|
        th = th_l + (th_r - th_l) * i / segs.to_f   # sweep left -> right
        pt.call(xc + r * Math.cos(th), zc + r * Math.sin(th))
      end
    end

    # Move the 4 end columns (8 vertices) of a freshly-built native (opening)
    # wall to the mitered corner positions stored in corners_xy, so a wall WITH
    # openings miters at corners exactly like a wall without openings. Opening
    # vertices in the middle are untouched. No-op when there is no miter or no
    # corners_xy. Runs as part of the build, so the miter survives every rebuild.
    def self.apply_native_miter_corners!(wall, drawn_start, drawn_end, thickness_f, h_anchor)
      return unless wall&.valid?
      flat = wall.get_attribute('InteriorPro', 'corners_xy')
      return unless flat && flat.length == 8
      mit = [[flat[0], flat[1]], [flat[2], flat[3]], [flat[4], flat[5]], [flat[6], flat[7]]]

      dx = drawn_end.x - drawn_start.x
      dy = drawn_end.y - drawn_start.y
      len = Math.sqrt(dx * dx + dy * dy)
      return if len < 0.001
      half = thickness_f / 2.0
      nx = -dy / len * half
      ny =  dx / len * half
      case h_anchor
      when 'left'
        perp = [[drawn_start.x + nx * 2, drawn_start.y + ny * 2],
                [drawn_end.x   + nx * 2, drawn_end.y   + ny * 2],
                [drawn_end.x,            drawn_end.y],
                [drawn_start.x,          drawn_start.y]]
      when 'right'
        perp = [[drawn_start.x,          drawn_start.y],
                [drawn_end.x,            drawn_end.y],
                [drawn_end.x   - nx * 2, drawn_end.y   - ny * 2],
                [drawn_start.x - nx * 2, drawn_start.y - ny * 2]]
      else
        perp = [[drawn_start.x + nx, drawn_start.y + ny],
                [drawn_end.x   + nx, drawn_end.y   + ny],
                [drawn_end.x   - nx, drawn_end.y   - ny],
                [drawn_start.x - nx, drawn_start.y - ny]]
      end

      tol = 0.01
      verts = wall.entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq
      move_verts = []
      move_vecs  = []
      perp.each_with_index do |(px, py), i|
        mx, my = mit[i]
        next if (mx - px).abs < tol && (my - py).abs < tol
        verts.each do |v|
          pos = v.position
          next unless (pos.x - px).abs < tol && (pos.y - py).abs < tol
          move_verts << v
          move_vecs  << Geom::Vector3d.new(mx - px, my - py, 0)
        end
      end
      return if move_verts.empty?
      wall.entities.transform_by_vectors(move_verts, move_vecs)
    rescue StandardError => e
      puts "[WallTool] apply_native_miter_corners!: #{e.message}"
    end

    def finish_drawing
      clear_preview
      @drawing = false
      @start_point = nil
      @end_point = nil
      Sketchup.active_model.select_tool(nil)
    end
  end
end
