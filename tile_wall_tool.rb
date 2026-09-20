# encoding: utf-8
# Interior Pro - TILE WALL TOOL (2026-09-17)
#
# Two clicks on a wall face mark the rectangle that gets tiled - the
# shower wall, the fireplace face, a backsplash. This is the tool Chief
# Architect calls a Wall Material Region, and it is what he picked:
# "מלבן בגרירה + ידיות מתיחה".
#
# THE POINT LAW (CLAUDE.md): a tool that takes a point from the mouse
# locks onto corners, ends, middles and edges - AND DRAWS WHERE IT
# LOCKED. Both the move and the click go through the SAME method here
# (face_point), so the ring he sees is the point he gets. That is the
# whole bug that rule exists to prevent.
#
# Green = a corner (the wall's own corner, or an opening's corner).
# Cyan  = a middle. Magenta = on an edge, one axis locked. No ring = the
# raw point on the face, nothing locked.
#
# The tool OWNS NO LAYOUT. It works out four numbers - where on the wall,
# how far up, how wide, how tall - and hands them to TileWall.build!,
# which reads the one grid in tile_grid.rb. Openings are taken out there,
# not here.
module InteriorPro
  class TileWallTool
    SNAP_PX = 10 unless const_defined?(:SNAP_PX, false)
    GREEN   = [0, 170, 60].freeze   unless const_defined?(:GREEN, false)
    CYAN    = [0, 160, 190].freeze  unless const_defined?(:CYAN, false)
    MAGENTA = [190, 0, 160].freeze  unless const_defined?(:MAGENTA, false)

    GROUTS   = ['0', '1/16"', '1/8"', '3/16"', '1/4"', '3/8"'].freeze unless const_defined?(:GROUTS, false)
    GROUT_IN = [0.0, 0.0625, 0.125, 0.1875, 0.25, 0.375].freeze unless const_defined?(:GROUT_IN, false)
    # 'Offset' on the dialog, his word (2026-09-17): how far each second
    # course is pushed along. Stack = every row lined up, 1/2 = brickwork.
    BONDS    = ['Stack', '1/2', '1/3', '1/4'].freeze unless const_defined?(:BONDS, false)
    BOND_V   = [0.0, 0.5, 1.0 / 3.0, 0.25].freeze unless const_defined?(:BOND_V, false)
    LINES_ONLY = '(lines only)' unless const_defined?(:LINES_ONLY, false)
    # How far the tile stands off the wall. His number: "ברוב המקלחות
    # הטיל הוא לפחות 5/8 בולט מהקיר" - so 5/8" is the default, and it is
    # what makes the joints real recesses instead of a drawn line.
    DEPTHS   = ['5/8"', '1/2"', '3/8"', '3/4"', '1/4"', '0 (flat)'].freeze unless const_defined?(:DEPTHS, false)
    DEPTH_IN = [0.625, 0.5, 0.375, 0.75, 0.25, 0.0].freeze unless const_defined?(:DEPTH_IN, false)
    # Tile by tile, or the photo repeated across the area so the pattern
    # IN the picture is the tile (star-and-cross, painted cement tiles, a
    # diagonal chequer). His idea, 2026-09-17.
    MODES  = ['Tile by tile', 'Whole image (pattern)'].freeze unless const_defined?(:MODES, false)
    MODE_V = %w[tiles image].freeze unless const_defined?(:MODE_V, false)
    # SET THE HEIGHT FIRST, THEN DRAW ONLY THE WIDTH (2026-09-18, his call:
    # "אני רוצה לסרטט את הקיר ולקבוע רק את הרוחב והגובה יהיה בהגדרות
    # שלפני"). And when asked where that height starts: "תמיד מהרצפה
    # למעלה". So a set height always sits on the wall's own floor, and the
    # two clicks only say how wide. 'Drag' is the old way, still there.
    HEIGHTS  = ['Drag it', 'Full wall', '96"', '84"', '72"', '60"', '48"', '36"'].freeze unless const_defined?(:HEIGHTS, false)
    HEIGHT_V = [nil, :full, 96.0, 84.0, 72.0, 60.0, 48.0, 36.0].freeze unless const_defined?(:HEIGHT_V, false)
    # WALL AFTER WALL (2026-09-18, his words: "בדיוק כמו ציור הקירות - אני
    # מצייר קיר אחד, מסיים לסרטט אותו ומיד ממשיך לקיר השני"). When an area
    # ends ON a corner, the tool hops round it by itself and the next click
    # only says how far along the next wall to go. Esc ends the run. On by
    # default, which is what he asked for; 'One wall only' is the off
    # switch, in the same dialog as everything else.
    RUNS  = ['Wall after wall', 'One wall only'].freeze unless const_defined?(:RUNS, false)
    RUN_V = [true, false].freeze unless const_defined?(:RUN_V, false)
    # AND WHAT THE PATTERN DOES AT THE CORNER (2026-09-18, his call:
    # "צריך להיות שתי האופציות, ברירת המחדל צריכה להיות 2 אבל יש גם
    # אופציה לאחד אם רוצים"). Default: every wall starts its own layout
    # with a whole tile. The other way is one run that wraps, so the tile
    # cut at the corner carries on as the first piece of the next wall.
    CORNERS  = ['Start fresh', 'Carry the pattern round'].freeze unless const_defined?(:CORNERS, false)
    CORNER_V = [false, true].freeze unless const_defined?(:CORNER_V, false)
    # CENTRE THE LAYOUT, FROM THE FIRST DRAWING (2026-09-18, his ask: "אם
    # זה צריך להיכנס גם בסרטוט ההתחלתי"). First WHAT sits on the middle -
    # a whole tile or a grout line - then WHICH WAY: both, only along the
    # wall, or only up it, because sometimes only the cut at the top or
    # the bottom matters. The same two choices as the edit window.
    # Simple (his call, 2026-09-18): Tile or Grout for what sits on the
    # middle, then Horizontal yes/no and Vertical yes/no. Neither = off.
    CENTRES  = %w[Tile Grout].freeze unless const_defined?(:CENTRES, false)
    CENTRE_V = [true, 'grout'].freeze unless const_defined?(:CENTRE_V, false)
    YESNO    = %w[No Yes].freeze unless const_defined?(:YESNO, false)

    # What he chose last time, so a second area on the same wall is two
    # clicks and no dialog.
    def self.last
      @last ||= { card: nil, grout: 0.125, bond: 0.0, color: 'light',
                  depth: InteriorPro::TileWall::DEFAULT_DEPTH, mode: 'tiles',
                  # 96" until he says otherwise (2026-09-18, his call).
                  height: 96.0, run: true, wrap: false, tile_txt: '',
                  # GROUT line on the middle, both ways (2026-09-18, his call:
                  # "אני רוצה סנטר של גראוט כברירת מחדל").
                  center: 'grout', cen_h: true, cen_v: true }
    end

    def activate
      @cfg = ask_settings
      if @cfg.nil?
        Sketchup.active_model.select_tool(nil)
        return
      end
      reset
      status
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

    def onMouseMove(_flags, x, y, view)
      @hover = face_point(view, x, y)
      if @hover
        if @first
          w = (@hover[:u] - @first[:u]).abs
          fh = fixed_height
          h = fh || (@hover[:z] - @first[:z]).abs
          Sketchup.vcb_label = fh ? 'Width' : 'Width , Height'
          Sketchup.vcb_value = fh ? Sketchup.format_length(w) : "#{Sketchup.format_length(w)} , #{Sketchup.format_length(h)}"
          view.tooltip = "#{Sketchup.format_length(w)} x #{Sketchup.format_length(h)}"
        else
          tip = begin
            @ip && @ip.valid? ? @ip.tooltip.to_s : ''
          rescue StandardError
            ''
          end
          view.tooltip = tip.empty? ? (@hover[:kind] ? @hover[:kind].to_s : '') : tip
        end
      end
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      p = face_point(view, x, y)
      trace_click(x, y, p)
      if p.nil?
        Sketchup.set_status_text('Tile Wall: click on the FACE of an Interior Pro wall.', SB_PROMPT)
        return
      end
      if @first.nil?
        @first = p
        @wall = p[:wall]
        @side = p[:side]
        @alt = p[:alt]
        puts "[TileWall] two walls meet here - drag along the one you want" if @alt
      else
        @alt = nil
        build!(@first, p, view)
      end
      status
      view.invalidate
    end

    # MEASURE, DO NOT GUESS (2026-09-18): every click writes one line to
    # tile_tool_trace.txt next to the code - which wall, which side, what
    # the inference point was, and what the tool remembered from the hover.
    # Read it instead of asking him to paste anything.
    TRACE_CLICKS = true unless const_defined?(:TRACE_CLICKS, false)
    def trace_click(x, y, p)
      return unless TRACE_CLICKS
      ip = @ip
      pos = ip&.position
      at = lambda { |g, k| g&.valid? ? g.get_attribute('InteriorPro', k) : nil }
      line = "#{Time.now.strftime('%H:%M:%S')} click #{x},#{y} " \
             "dof #{(ip.degrees_of_freedom rescue '?')} vertex #{(!!ip.vertex rescue '?')} " \
             "pos #{pos ? [pos.x.round(2), pos.y.round(2), pos.z.round(2)].inspect : 'nil'} | " \
             "hover_wall #{at.call(@hover_wall, 'id').to_s[0, 8]} side #{@hover_side.inspect} | " \
             "result #{p ? "wall #{at.call(p[:wall], 'id').to_s[0, 8]} side #{p[:side].inspect} u #{p[:u].round(2)} z #{p[:z].round(2)} kind #{p[:kind].inspect}" : 'NIL'} " \
             "| first #{@first ? 'set' : 'none'}"
      File.open(File.join(__dir__, 'tile_tool_trace.txt'), 'a:UTF-8') { |f| f.puts line }
    rescue StandardError => e
      puts "[TileWall] trace failed: #{e.message}"
    end

    # Typed size: "60,96" or "5' , 8'" - width then height, measured from
    # the first corner, in the direction the mouse is pointing.
    def onUserText(text, view)
      return if @first.nil?
      fh = fixed_height
      a, b = text.to_s.split(/[,;xX]/).map { |s| parse_len(s) }
      b = fh if b.nil? && fh
      if a.nil? || b.nil? || a <= 0.1 || b <= 0.1
        UI.messagebox(fh ? "Type how wide the area is, e.g.  60  or  5'" :
                            "Type width and height, e.g.  60,96  or  5',8'")
        return
      end
      du = @hover && @hover[:u] < @first[:u] ? -a : a
      dz = @hover && @hover[:z] < @first[:z] ? -b : b
      build!(@first, { u: @first[:u] + du, z: @first[:z] + dz }, view)
      status
      view.invalidate
    end

    # The height he set, in inches on THIS wall, or nil for the old way.
    def fixed_height
      v = @cfg && @cfg[:height]
      return nil if v.nil?
      return (@hgt.to_f > 0.1 ? @hgt.to_f : nil) if v == :full
      v.to_f > 0.1 ? v.to_f : nil
    end

    # THE TILE SIZE, TYPED (2026-09-18, his words: "אם יש לי את הטיל
    # שבתוסף שלי הוא 48 על 24 אבל אני יודע שיש אותו הצבע גם בגדלים
    # אחרים - אני רוצה שתהיה האפשרות לקבוע בנפרד את גודל האריח").
    # '48x24' - first number ALONG the wall, second UP it. One number is a
    # square tile. Empty, or 'From material', keeps the card's own size.
    # Two yes/no -> the stored axis. Horizontal = the horizontal LINES
    # (rows, 'v'), Vertical = the vertical LINES (columns, 'u') - see
    # TileWallEditDialog.axis_from. PURE.
    def self.axis_of(h, v)
      return 'uv' if h && v
      return 'v' if h
      return 'u' if v
      'uv'
    end

    def self.parse_tile(text)
      t = text.to_s.strip
      return nil if t.empty? || t =~ /material/i
      nums = t.split(/[xX*,]/).map do |q|
        q = q.to_s.strip.tr('״', '"')
        begin
          q.to_l.to_f
        rescue StandardError
          q.to_f
        end
      end
      a = nums[0]
      b = nums[1]
      return nil if a.nil? || a <= 0.25
      b = a if b.nil? || b <= 0.25
      [a, b]
    end

    def parse_len(s)
      t = s.to_s.strip.tr('׳', "'").tr('״', '"').tr(',', '.')
      return nil if t.empty?
      begin
        t.to_l.to_f
      rescue StandardError
        nil
      end
    end

    def draw(view)
      return unless @frame
      if @first && @hover
        fh = fixed_height
        pts = if fh
                rect_pts(@first[:u], 0.0, @hover[:u], fh)
              else
                rect_pts(@first[:u], @first[:z], @hover[:u], @hover[:z])
              end
        view.drawing_color = Sketchup::Color.new(60, 60, 60)
        view.line_stipple = '-'
        view.line_width = 2
        view.draw(GL_LINE_LOOP, pts)
      end
      [@first, @hover].compact.each { |p| draw_ring(view, p) }
      # SketchUp's own lock, drawn the way SketchUp draws it, on top of our
      # ring - so a corner he aims at is visibly caught.
      begin
        @ip.draw(view) if @ip && @ip.valid? && @ip.display?
      rescue StandardError
        nil
      end
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@wall.bounds) if @wall&.valid?
      [@first, @hover].compact.each { |p| bb.add(pt3(p[:u], p[:z])) }
      bb
    end

    # ---- the one point method: move AND click come through here --------

    def face_point(view, x, y)
      # ONE InputPoint THAT LIVES AS LONG AS THE TOOL (2026-09-18). A fresh
      # one made fresh on every move has no history, so SketchUp's own
      # inference never really engages and a corner does not catch. A
      # picked InputPoint that is kept holds onto what it locked, can be
      # DRAWN, and carries SketchUp's own tooltip - which is what makes
      # aiming at a corner feel like the rest of SketchUp.
      @ip ||= Sketchup::InputPoint.new
      ip = @ip
      begin
        ip.pick(view, x, y)
      rescue StandardError
        ip = view.inputpoint(x, y)
      end
      pos = ip.position
      return nil unless pos
      # Once the first corner is down the face is LOCKED: hovering over
      # another wall must not move the area onto it mid-rectangle.
      #
      # THE CORNER BELONGS TO THE WALL HE CAME FROM (2026-09-18, measured
      # with debug_tile_pick.rb: at the T corner the pick under the cursor
      # returns ONE path, the interior wall's face - the exterior face is
      # simply not under that pixel any more, so no rule about which face
      # can fix it). His words: "בגלל שהפינה הזאת נוצרת מקיר הפנים וקיר
      # החוץ יש לו המשך לצד השני הוא ננעל לי רק על קיר הפנים". So while the
      # inference point sits on an edge or a corner, the wall and the side
      # stay the ones the mouse was last sliding on freely - the way every
      # SketchUp tool keeps the face you came from when you reach its edge.
      on_point = on_edge_or_point?(ip)
      hint = nil
      eye = begin
        view.camera.eye
      rescue StandardError
        nil
      end
      mid = on_point && !@first ? wall_mid_face_at(pos, Sketchup.active_model, eye) : nil
      alt = nil
      if @first
        # BOTH WALLS MEET AT THAT CORNER, AND HE WANTS BOTH (2026-09-18,
        # his words: "צריך גם על קיר החוץ וגם על קיר הפנים"). The first
        # click cannot know which one; the way he then drags the mouse
        # does - along the exterior face or along the interior one. So
        # while the second corner is still open, the area follows the
        # face the mouse is on, and the first corner is re-measured on it.
        #
        # READ THE WALL AFTER THE SWAP, NEVER BEFORE (2026-09-20). The
        # local `wall` used to be taken first, and everything below then
        # rebuilt the frame for THAT wall and put @wall back - so the swap
        # was undone on the same move, while @first had already been
        # re-measured onto the other wall. First corner in the interior
        # wall's u, live point in the exterior wall's u: the area ran from
        # one to the other, straight past the corner into the next room.
        # That is the picture he sent.
        swap_to_alt!(pos) if @alt
        wall = @wall
      elsif mid
        # A POINT IN THE MIDDLE OF A FACE BELONGS TO THAT WALL (2026-09-18).
        # His picture: the purple dot is the END of the interior wall, and
        # the same spot is the MIDDLE of the exterior wall's face. The end
        # of one wall is never a reason to tile it - the wall whose face
        # runs on through that point is the one he means.
        wall = mid[:wall]
        hint = mid[:side]
        # The other wall is the one that ENDS at this point - found from
        # the geometry, not from the pixel, which at the corner can land on
        # either face and then the interior wall would be lost for good.
        other = wall_ending_at(pos, wall)
        alt = { wall: other, side: nil } if other
      elsif on_point && @hover_wall&.valid?
        wall = @hover_wall
        hint = @hover_side
      else
        wall = pick_wall(view, x, y) || @wall
      end
      return nil unless wall&.valid?
      fr = (@frame && @wall == wall) ? @frame : nil
      if fr.nil?
        # WHICH FACE, MEASURED OFF THE FACE THE RAY REALLY HIT (2026-09-18).
        # The inference point is asked only afterwards, as a fallback -
        # see side_from_face for why it cannot be trusted here.
        side = hint || side_from_face(view, x, y, wall) || side_of(wall, pos)
        return nil if side.nil?
        fr = InteriorPro::TileWall.frame_for(wall, side)
        return nil if fr.nil?
        @frame = fr
        @wall = wall
        @side = side
        @holes = InteriorPro::TileWall.openings_for(wall, fr)
        @len = fr[:len]
        @hgt = InteriorPro::TileWall.wall_height(wall)
      end
      # Remember the face he is sliding on freely, for the next corner.
      unless @first || on_point
        @hover_wall = wall
        @hover_side = @side
      end
      u = (pos.x - fr[:ox]) * fr[:ux] + (pos.y - fr[:oy]) * fr[:uy]
      z = pos.z - fr[:floor_z]
      tol = begin
        view.pixels_to_model(SNAP_PX, pos)
      rescue StandardError
        1.0
      end
      # A REAL POINT WINS (CLAUDE.md, 2026-09-18). If SketchUp's own
      # inference locked onto a vertex - a corner, the end of a line, on
      # another wall or anything else in the model - that point is
      # projected onto this face and used as it is. That is what makes it
      # possible to aim at a wall opposite and have the area reach it.
      if locked_point?(ip)
        return { u: u, z: z, kind: :corner, wall: wall, side: @side, pos: pos, alt: alt }
      end
      su, ku = snap(u, u_lines, tol)
      sz, kz = snap(z, z_lines, tol)
      kind = if ku && kz
               (ku == :mid || kz == :mid) ? :mid : :corner
             elsif ku || kz
               :edge
             end
      { u: su, z: sz, kind: kind, wall: wall, side: @side, pos: pos, alt: alt }
    end

    # The other wall at the first corner. While the second corner is open,
    # whichever of the two faces the mouse is on carries the area; the
    # first corner keeps its world position and is re-measured on the face
    # it moved to. Swapping is symmetric, so he can change his mind until
    # he clicks.
    def swap_to_alt!(pos)
      return unless @first && @alt && @alt[:wall]&.valid? && @first[:pos]
      cur = (pos.x - @frame[:ox]) * @frame[:nx] + (pos.y - @frame[:oy]) * @frame[:ny]
      sd = @alt[:side] || side_of(@alt[:wall], pos)
      fr = InteriorPro::TileWall.frame_for(@alt[:wall], sd)
      return if fr.nil?
      d = (pos.x - fr[:ox]) * fr[:nx] + (pos.y - fr[:oy]) * fr[:ny]
      return unless d.abs < cur.abs - 0.05 && d.abs <= 1.0
      was = { wall: @wall, side: @side }
      @wall = @alt[:wall]
      @side = sd
      @frame = fr
      @len = fr[:len]
      @hgt = InteriorPro::TileWall.wall_height(@wall)
      @holes = InteriorPro::TileWall.openings_for(@wall, fr)
      fp = @first[:pos]
      @first = @first.merge(
        u: (fp.x - fr[:ox]) * fr[:ux] + (fp.y - fr[:oy]) * fr[:uy],
        z: fp.z - fr[:floor_z], wall: @wall, side: @side
      )
      @alt = was
      puts "[TileWall] the area moved to the other wall at that corner (side '#{@side}')"
    rescue StandardError => e
      puts "[TileWall] could not move to the other wall: #{e.message}"
    end

    # Did SketchUp's own inference land on a real point, not just a spot on
    # a face? A vertex, or a point with no freedom left to move.
    def locked_point?(ip)
      return false if ip.nil?
      return true if ip.respond_to?(:vertex) && ip.vertex
      ip.respond_to?(:degrees_of_freedom) && ip.degrees_of_freedom.zero?
    rescue StandardError
      false
    end

    # Which wall has `pos` sitting in the MIDDLE of one of its long faces -
    # on the face plane, well inside its run (not at either end), within
    # its height. nil when no wall does. PURE apart from reading the walls.
    MID_FACE_TOL = 0.6 unless const_defined?(:MID_FACE_TOL, false)
    MID_FACE_END = 1.0 unless const_defined?(:MID_FACE_END, false)
    def wall_mid_face_at(pos, model = Sketchup.active_model, eye = nil)
      return nil if pos.nil?
      walls = InteriorPro::TileWall.walls_in_model(model).select(&:valid?)
      # First a point sitting ON a face. Then - his second picture, the
      # purple dot: the interior wall's corner vertex can stand INSIDE the
      # exterior wall's body, a couple of inches behind its face, because
      # the interior wall runs to the exterior wall's centre line. From a
      # step back that is the only point SketchUp offers. A point inside
      # a wall's body, mid-run, still belongs to that wall; u and z are
      # taken straight off the face. Inside the body both faces are near,
      # so the one FACING THE CAMERA wins - the face he is looking at.
      [false, true].each do |inside|
        found = []
        walls.each do |w|
          th = w.get_attribute('InteriorPro', 'thickness').to_f
          %w[a b].each do |sd|
            fr = InteriorPro::TileWall.frame_for(w, sd)
            next if fr.nil?
            d = (pos.x - fr[:ox]) * fr[:nx] + (pos.y - fr[:oy]) * fr[:ny]
            if inside
              next if d > MID_FACE_TOL || d < -(th + MID_FACE_TOL)
            else
              next if d.abs > MID_FACE_TOL
            end
            u = (pos.x - fr[:ox]) * fr[:ux] + (pos.y - fr[:oy]) * fr[:uy]
            next if u < MID_FACE_END || u > fr[:len] - MID_FACE_END
            z = pos.z - fr[:floor_z]
            next if z < -MID_FACE_TOL || z > InteriorPro::TileWall.wall_height(w) + MID_FACE_TOL
            facing = eye ? ((eye.x - fr[:ox]) * fr[:nx] + (eye.y - fr[:oy]) * fr[:ny] > 0.0) : true
            found << { wall: w, side: sd, u: u, inside: inside, d: d, facing: facing }
          end
        end
        next if found.empty?
        best = found.min_by { |c| [c[:facing] ? 0 : 1, c[:d].abs] }
        return best
      end
      nil
    rescue StandardError => e
      puts "[TileWall] which face the point is in the middle of could not be measured: #{e.message}"
      nil
    end

    # Which wall has one of its ENDS at `pos` (within its own thickness),
    # other than `not_this`. The interior wall at a T corner.
    def wall_ending_at(pos, not_this, model = Sketchup.active_model)
      return nil if pos.nil?
      best = nil
      InteriorPro::TileWall.walls_in_model(model).each do |w|
        next unless w.valid?
        next if not_this && w.equal?(not_this)
        th = w.get_attribute('InteriorPro', 'thickness').to_f
        [%w[start_x start_y], %w[end_x end_y]].each do |kx, ky|
          dx = pos.x - w.get_attribute('InteriorPro', kx).to_f
          dy = pos.y - w.get_attribute('InteriorPro', ky).to_f
          d = Math.sqrt(dx * dx + dy * dy)
          next if d > th + 1.0
          best = [w, d] if best.nil? || d < best[1]
        end
      end
      best && best[0]
    rescue StandardError => e
      puts "[TileWall] which wall ends here could not be measured: #{e.message}"
      nil
    end

    # On an edge or a corner (one degree of freedom or none) - the spots
    # where the pixel under the cursor no longer says which face he means.
    def on_edge_or_point?(ip)
      return false if ip.nil?
      return true if ip.respond_to?(:vertex) && ip.vertex
      ip.respond_to?(:degrees_of_freedom) && ip.degrees_of_freedom <= 1
    rescue StandardError
      false
    end

    def u_lines
      out = [[0.0, :corner], [@len, :corner], [@len / 2.0, :mid]]
      Array(@holes).each do |h|
        out << [h[0], :corner] << [h[2], :corner] << [(h[0] + h[2]) / 2.0, :mid]
      end
      out
    end

    def z_lines
      out = [[0.0, :corner], [@hgt, :corner], [@hgt / 2.0, :mid]]
      # The heights a tiler actually asks for, so he does not have to aim.
      [36.0, 48.0, 60.0, 72.0, 84.0, 96.0].each { |v| out << [v, :edge] if v < @hgt - 0.5 }
      Array(@holes).each do |h|
        out << [h[1], :corner] << [h[3], :corner] << [(h[1] + h[3]) / 2.0, :mid]
      end
      out
    end

    def snap(v, lines, tol)
      best = nil
      lines.each do |val, kind|
        d = (v - val).abs
        next if d > tol
        best = [val, kind, d] if best.nil? || d < best[2]
      end
      best ? [best[0], best[1]] : [v, nil]
    end

    def pick_wall(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        path.each do |e|
          next unless e.is_a?(Sketchup::Group)
          return e if e.get_attribute('InteriorPro', 'type') == 'wall'
        end
      end
      nil
    end

    # The wall's LEFT perpendicular - the same one TileWall.frame uses, so
    # 'a' here and 'a' there are the same face. PURE, nil for no length.
    def self.left_normal(sx, sy, ex, ey)
      dx = ex.to_f - sx.to_f
      dy = ey.to_f - sy.to_f
      len = Math.sqrt(dx * dx + dy * dy)
      return nil if len < 0.001
      [-dy / len, dx / len]
    end

    # A face's own normal decides the side: it points OUT of the wall, so
    # the face on the left of start -> end is 'a'. nil = this face is not
    # one of the two long ones (the top, or an end cap). PURE.
    def self.side_from_normal(nx, ny, fx, fy)
      d = nx.to_f * fx.to_f + ny.to_f * fy.to_f
      return nil if d.abs < 0.5
      d > 0 ? 'a' : 'b'
    end

    # WHICH FACE HE IS POINTING AT - MEASURED OFF THE FACE THE MOUSE RAY
    # REALLY HIT (2026-09-18, his picture: "סימנתי אותו מצד אחד של הקיר
    # והוא צייר לי אותו מהצד השני").
    #
    # The side used to be worked out from the INFERENCE point, and that
    # point is often a VERTEX - which is exactly what the point law asks
    # for everywhere else. But a wall corner carries vertices on BOTH of
    # its faces, and SketchUp hands back whichever one it locked. Aim at
    # the corner of the face in front of you and you can get the vertex
    # standing on the face behind it, 5 inches away - and the whole area
    # was built on the far side of the wall. The ray's own face cannot
    # lie, so it is asked first; the inference point stays as a fallback
    # for the case where the ray hit no face at all.
    def side_from_face(view, x, y, wall)
      n = self.class.left_normal(
        wall.get_attribute('InteriorPro', 'start_x'),
        wall.get_attribute('InteriorPro', 'start_y'),
        wall.get_attribute('InteriorPro', 'end_x'),
        wall.get_attribute('InteriorPro', 'end_y')
      )
      return nil if n.nil?
      ph = view.pick_helper
      ph.do_pick(x, y)
      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        # THIS wall, not any wall: a face belonging to something else
        # says nothing about which of ITS two sides he is on.
        next unless path.any? { |e| e.equal?(wall) }
        leaf = begin
          ph.leaf_at(i)
        rescue StandardError
          nil
        end
        next unless leaf.is_a?(Sketchup::Face)
        fn = leaf.normal
        begin
          tr = ph.transformation_at(i)
          fn = fn.transform(tr) if tr
        rescue StandardError
          nil
        end
        sd = self.class.side_from_normal(n[0], n[1], fn.x, fn.y)
        next if sd.nil?
        puts "[TileWall] the mouse is on face '#{sd}' of the wall - measured off that face"
        return sd
      end
      nil
    rescue StandardError => e
      puts "[TileWall] which face the mouse is on could not be measured: #{e.message}"
      nil
    end

    # Fallback: which of the two long faces the POINT is nearer to. Right
    # for a point that really sits on a face, wrong for a vertex that the
    # inference grabbed off the other one - which is why side_from_face
    # is asked first.
    def side_of(wall, pos)
      sx = wall.get_attribute('InteriorPro', 'start_x').to_f
      sy = wall.get_attribute('InteriorPro', 'start_y').to_f
      ex = wall.get_attribute('InteriorPro', 'end_x').to_f
      ey = wall.get_attribute('InteriorPro', 'end_y').to_f
      n = self.class.left_normal(sx, sy, ex, ey)
      return nil if n.nil?
      nx, ny = n
      off = (pos.x - sx) * nx + (pos.y - sy) * ny
      o_pos, o_neg = InteriorPro::TileWall.side_offsets(
        wall.get_attribute('InteriorPro', 'thickness').to_f,
        InteriorPro::TileWall.h_anchor_of(wall)
      )
      (off - o_pos).abs <= (off - o_neg).abs ? 'a' : 'b'
    end

    # ---- drawing helpers ----------------------------------------------

    def pt3(u, z, out = 0.25)
      x, y, zz = InteriorPro::TileWall.world(@frame, u, z, out)
      Geom::Point3d.new(x, y, zz)
    end

    def rect_pts(u1, z1, u2, z2)
      [pt3(u1, z1), pt3(u2, z1), pt3(u2, z2), pt3(u1, z2)]
    end

    def ring_color(kind)
      case kind
      when :corner then GREEN
      when :mid    then CYAN
      when :edge   then MAGENTA
      end
    end

    def draw_ring(view, p)
      c = ring_color(p[:kind])
      return if c.nil?
      centre = pt3(p[:u], p[:z])
      r = begin
        view.pixels_to_model(6, centre)
      rescue StandardError
        1.0
      end
      pts = (0..16).map do |i|
        a = i * 2.0 * Math::PI / 16.0
        pt3(p[:u] + Math.cos(a) * r, p[:z] + Math.sin(a) * r)
      end
      view.drawing_color = Sketchup::Color.new(*c)
      view.line_stipple = ''
      view.line_width = 3
      view.draw(GL_LINE_STRIP, pts)
    end

    # ---- the build -----------------------------------------------------

    def build!(a, b, view)
      # THE TILE CANNOT WALK THROUGH A WALL (2026-09-18, his picture: the
      # run drawn from the T corner went straight through the interior
      # wall into the next room). The same limits the stretch tool keeps:
      # the clear run of face between the walls standing on it, measured
      # around the middle of what he drew.
      # Measured from the first corner, a hair towards the second: the
      # first corner may itself stand on a wall's face, and the middle of
      # the drawn area may be inside that wall.
      ref = a[:u] + (b[:u] >= a[:u] ? 0.25 : -0.25)
      lo, hi = InteriorPro::TileWall.face_limits(@wall, @frame, ref)
      au = a[:u].clamp(lo, hi)
      bu = b[:u].clamp(lo, hi)
      if (au - a[:u]).abs > 1.0e-6 || (bu - b[:u]).abs > 1.0e-6
        puts "[TileWall] stopped at the wall standing on this face: #{a[:u].round(2)}..#{b[:u].round(2)} -> #{au.round(2)}..#{bu.round(2)}"
      end
      a = a.merge(u: au)
      b = b.merge(u: bu)
      u0 = [a[:u], b[:u]].min
      z0 = [a[:z], b[:z]].min
      w  = (b[:u] - a[:u]).abs
      h  = (b[:z] - a[:z]).abs
      fh = fixed_height
      if fh
        z0 = 0.0
        h = fh
      end
      if w < 1.0 || h < 1.0
        Sketchup.set_status_text('Tile Wall: that area is too small - click the other corner further away.', SB_PROMPT)
        return
      end
      grp = InteriorPro::TileWall.build!(
        wall: @wall, side: @side, u0: u0, z0: z0, w: w, h: h,
        card_id: @cfg[:card], grout: @cfg[:grout],
        grout_color: @cfg[:color], stagger: @cfg[:bond],
        depth: @cfg[:depth], mode: @cfg[:mode],
        tile_w: @cfg[:tile] && @cfg[:tile][0], tile_l: @cfg[:tile] && @cfg[:tile][1],
        ox: @carry_ox.to_f,
        centered: (@cfg[:cen_h] || @cfg[:cen_v]) ? @cfg[:center] : false,
        center_axis: InteriorPro::TileWallTool.axis_of(@cfg[:cen_h], @cfg[:cen_v])
      )
      remember_phase!(grp)
      # The neighbour that was laid before this area existed could not pull
      # back from it - lay it again, so the corner square is never lost.
      InteriorPro::TileWall.refresh_corner_neighbours!(grp) if grp
      if grp.nil?
        UI.messagebox('Nothing was tiled - see the Ruby Console for the reason.')
        reset_area
        view.invalidate
        return
      end
      lead = b[:u] >= a[:u] ? u0 + w : u0
      hop_to_next!(lead) ? nil : reset_area
      view.invalidate
    end

    # Where the next wall has to pick the pattern up, when he asked for one
    # run that wraps. Read off what was REALLY built, not off what he asked
    # for, because the corner square comes off first.
    def remember_phase!(grp)
      @carry_ox = 0.0
      return unless grp && @cfg && @cfg[:wrap]
      used = grp.get_attribute('InteriorPro', 'built_w').to_f
      tw   = grp.get_attribute('InteriorPro', 'tile_w').to_f
      g    = grp.get_attribute('InteriorPro', 'pattern_grout').to_f
      @carry_ox = InteriorPro::TileWall.carry_ox(used, tw, g)
      puts "[TileWall] the pattern carries round the corner - next wall starts #{@carry_ox.round(3)} in"
    rescue StandardError => e
      @carry_ox = 0.0
      puts "[TileWall] could not carry the pattern round: #{e.message}"
    end

    # ROUND THE CORNER AND CARRY ON. Only when the area he just drew
    # actually ENDS on a corner - stop halfway along a wall and the run
    # simply ends, which is what stopping halfway means. Returns false when
    # there is nothing to hop to, and then the tool starts over as before.
    def hop_to_next!(lead_u)
      return false unless @cfg && @cfg[:run]
      nb = InteriorPro::TileWall.neighbour_at(@wall, @frame, lead_u)
      return false if nb.nil?
      fr = InteriorPro::TileWall.frame_for(nb[:wall], nb[:side])
      return false if fr.nil?
      room = nb[:dir] > 0 ? nb[:len] - nb[:u_from] : nb[:u_from]
      if room < 1.0
        puts '[TileWall] the wall round the corner has no room left - the run ends here'
        return false
      end
      @wall = nb[:wall]
      @side = nb[:side]
      @frame = fr
      @len = fr[:len]
      @hgt = InteriorPro::TileWall.wall_height(nb[:wall])
      @holes = InteriorPro::TileWall.openings_for(nb[:wall], fr)
      @first = { u: nb[:u_from], z: 0.0, kind: :corner, wall: nb[:wall], side: nb[:side] }
      @hover = nil
      puts "[TileWall] carrying on round the corner onto wall " \
           "#{nb[:wall].get_attribute('InteriorPro', 'id')} side #{nb[:side]}"
      true
    rescue StandardError => e
      puts "[TileWall] could not carry on round the corner: #{e.message}"
      false
    end

    # ---- state ---------------------------------------------------------

    def reset
      @carry_ox = 0.0
      @wall = nil
      @side = nil
      @frame = nil
      @holes = nil
      @len = 0.0
      @hgt = 0.0
      reset_area
    end

    def reset_area
      @first = nil
      @hover = nil
      @hover_wall = nil
      @hover_side = nil
      @alt = nil
    end

    def status
      if @first && @first[:kind] == :corner && @cfg && @cfg[:run] && @hover.nil?
        Sketchup.set_status_text(
          'Tile Wall: carried on round the corner - click how far along this wall, or type it. Esc ends the run.', SB_PROMPT
        )
      elsif @first
        Sketchup.set_status_text(
          (fixed_height ?
            'Tile Wall: click the other end, or type how wide (60). The height comes from the dialog. Esc = start over.' :
            'Tile Wall: click the OPPOSITE corner, or type width,height (60,96). Esc = start over.'), SB_PROMPT
        )
      else
        Sketchup.set_status_text(
          'Tile Wall: click one corner of the area on a wall face. Green = corner, cyan = middle, magenta = on an edge.', SB_PROMPT
        )
      end
    end

    # ---- the one dialog ------------------------------------------------

    def ask_settings
      cards = begin
        InteriorPro::MaterialLibrary.cards
      rescue StandardError
        []
      end
      names = cards.map { |c| c['name'].to_s }
      last = InteriorPro::TileWallTool.last
      cur = cards.find { |c| c['id'].to_s == last[:card].to_s }
      defaults = [cur ? cur['name'].to_s : (names.first || LINES_ONLY),
                  GROUTS[GROUT_IN.index(last[:grout]) || 2],
                  BONDS[BOND_V.index(last[:bond]) || 0],
                  DEPTHS[DEPTH_IN.index(last[:depth]) || 0],
                  MODES[MODE_V.index(last[:mode].to_s) || 0],
                  HEIGHTS[HEIGHT_V.index(last[:height]) || 0],
                  RUNS[RUN_V.index(last[:run].nil? ? true : last[:run]) || 0],
                  CORNERS[CORNER_V.index(last[:wrap] ? true : false) || 0],
                  CENTRES[CENTRE_V.index(last[:center]) || 0],
                  YESNO[last[:cen_h] ? 1 : 0],
                  YESNO[last[:cen_v] ? 1 : 0],
                  last[:tile_txt].to_s.empty? ? 'From material' : last[:tile_txt].to_s]
      # The last list entry is EMPTY on purpose: an empty list makes the
      # row a plain text box, and the tile size is typed - 48x24.
      lists = [([LINES_ONLY] + names).join('|'), GROUTS.join('|'),
               BONDS.join('|'), DEPTHS.join('|'), MODES.join('|'),
               HEIGHTS.join('|'), RUNS.join('|'), CORNERS.join('|'),
               CENTRES.join('|'), YESNO.join('|'), YESNO.join('|'), '']
      res = UI.inputbox(['Material', 'Grout', 'Offset', 'Stand-off', 'Layout', 'Height', 'Carry on', 'Corner', 'Centre', 'Horizontal', 'Vertical', 'Tile size'],
                        defaults, lists, 'Tile Wall')
      return nil unless res
      card = cards.find { |c| c['name'].to_s == res[0].to_s }
      cfg = { card: card ? card['id'] : nil,
              grout: GROUT_IN[GROUTS.index(res[1].to_s) || 2],
              bond: BOND_V[BONDS.index(res[2].to_s) || 0],
              depth: DEPTH_IN[DEPTHS.index(res[3].to_s) || 0],
              mode: MODE_V[MODES.index(res[4].to_s) || 0],
              height: HEIGHT_V[HEIGHTS.index(res[5].to_s) || 0],
              run: RUN_V[RUNS.index(res[6].to_s) || 0],
              wrap: CORNER_V[CORNERS.index(res[7].to_s) || 0],
              center: CENTRE_V[CENTRES.index(res[8].to_s) || 0],
              cen_h: res[9].to_s == 'Yes',
              cen_v: res[10].to_s == 'Yes',
              tile: InteriorPro::TileWallTool.parse_tile(res[11]),
              tile_txt: res[11].to_s =~ /material/i ? '' : res[11].to_s,
              color: last[:color] }
      InteriorPro::TileWallTool.last.merge!(cfg)
      cfg
    end
  end
end
