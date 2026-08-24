# roof_manager.rb — parametric roof over the top level (2026-08-04, v3).
# Modeled on Revit's "roof by footprint": the footprint polygon is the TRUE
# outline of the top level's exterior walls (outer faces + overhang), and the
# roof surface is computed with a straight skeleton — every footprint edge
# carries a sloped plane, and hips/ridges/valleys fall out of where the
# planes meet. Styles: 'hip' (every edge slopes) and 'flat'. Per-edge gables
# (Revit's Defines Slope) are the next phase.
#
# v3 additions (user spec 2026-08-04): settings saved on the MODEL and
# edited from RoofDialog — style, pitch, overhang (0 = no eaves), fascia
# board, metal drip edge, roof color + fascia color.
module InteriorPro
  module RoofManager
    DEFAULT_PITCH     = 4.0  unless const_defined?(:DEFAULT_PITCH, false)     # rise per 12" run
    DEFAULT_OVERHANG  = 12.0 unless const_defined?(:DEFAULT_OVERHANG, false)  # inches, all sides
    # The roof is a pure SURFACE with zero thickness (user 2026-08-05:
    # "just a surface — the material on it will carry the thickness").
    DEFAULT_FASCIA_DEPTH = 8.0 unless const_defined?(:DEFAULT_FASCIA_DEPTH, false)
    FASCIA_THICK = 0.75 unless const_defined?(:FASCIA_THICK, false)
    DRIP_THICK   = 0.1  unless const_defined?(:DRIP_THICK, false)
    DRIP_DEPTH   = 2.0  unless const_defined?(:DRIP_DEPTH, false)
    # The boxed soffit board: the flat plate that closes the eave from
    # underneath (2026-08-24). OUTSIDE ONLY - it spans from the wall's
    # exterior face out to the fascia, so with no overhang there is
    # nothing to close and it is not built at all.
    SOFFIT_THICK = 0.75 unless const_defined?(:SOFFIT_THICK, false)
    # 'wood' and 'stucco' (2026-08-25) are the SAME board as 'boxed' - the
    # plate, the square gable corner and the rake twin are all shared, so
    # there is no second geometry path to keep in step. They differ only in
    # what the board is painted, which is what this project does everywhere
    # else too (USE_ROOF_TEXTURES = false: the colour is picked here, the
    # real material is done in Lumion). See soffit_colors.
    # DOCUMENTATION ONLY - nothing branches on this list, so the usual
    # const_defined? reload trap cannot bite here.
    # 'beams' (2026-08-25) is the one that is NOT the same board: there is
    # no board at all. Rafter tails cross the eave every 18" and the roof
    # deck is what you see between them.
    SOFFIT_STYLES = %w[none boxed wood stucco beams].freeze unless const_defined?(:SOFFIT_STYLES, false)
    # ...until 2026-08-10. A zero-thickness sheet has no edge to look at,
    # and worse: the gable wall rises to exactly the same plane, so the
    # wall showed THROUGH the shingles along the rake. The slab is now
    # thickened UPWARD - the underside stays where it always was, so the
    # fascia, the rake and the gable walls all still meet it, and the new
    # material sits on top and covers the wall.
    DEFAULT_ROOF_THICKNESS = 0.5 unless const_defined?(:DEFAULT_ROOF_THICKNESS, false)
    DEFAULT_ROOF_COLOR   = '#584e4a' unless const_defined?(:DEFAULT_ROOF_COLOR, false)
    DEFAULT_FASCIA_COLOR = '#ffffff' unless const_defined?(:DEFAULT_FASCIA_COLOR, false)

    EPS = 1e-9 unless const_defined?(:EPS, false)
    NODE_TOL = 0.05 unless const_defined?(:NODE_TOL, false) # skeleton graph merge, inches
    # How smoothly a CURVED eave is faceted, in inches of bulge between one
    # facet and the true arc. Deliberately coarser than a wall's own 1/8":
    # the roof is read from further away and every extra facet is another
    # edge the straight skeleton has to chew through (same reasoning as
    # SIDING_CURVE_TOL).
    ROOF_CURVE_TOL = 1.5 unless const_defined?(:ROOF_CURVE_TOL, false)


    # ---------- lookup ----------

    def self.roofs
      Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'roof'
      end
    end

    # Highest level that actually has walls.
    def self.top_level
      lvls = InteriorPro::LevelManager.all_walls.map do |w|
        (w.get_attribute('InteriorPro', 'level') || 1).to_i
      end
      lvls.empty? ? 1 : lvls.max
    end

    # The walls the roof sits on: exterior walls of the top level
    # (all of its walls if none is marked exterior).
    def self.top_walls
      ws = InteriorPro::LevelManager.walls_of_level(top_level)
      ext = ws.select do |w|
        (w.get_attribute('InteriorPro', 'wall_category') || 'exterior') == 'exterior'
      end
      ext.empty? ? ws : ext
    end

    # Where the roof underside starts: the highest wall top (base_z + height).
    def self.eave_z(walls)
      walls.map do |w|
        w.get_attribute('InteriorPro', 'base_z').to_f +
          w.get_attribute('InteriorPro', 'height').to_f
      end.max
    end

    # ---------- settings (saved on the model, edited by RoofDialog) ------

    def self.settings
      m = Sketchup.active_model
      g = lambda do |k, d|
        v = m.get_attribute('InteriorPro', k)
        v.nil? ? d : v
      end
      {
        style: g.call('roof_style', 'hip').to_s,
        pitch: g.call('roof_pitch', DEFAULT_PITCH).to_f,
        overhang: g.call('roof_overhang', DEFAULT_OVERHANG).to_f,
        fascia: g.call('roof_fascia', true) == true,
        fascia_depth: g.call('roof_fascia_depth', DEFAULT_FASCIA_DEPTH).to_f,
        drip: g.call('roof_drip', true) == true,
        soffit: g.call('roof_soffit', 'none').to_s,
        soffit_color: g.call('roof_soffit_color', '').to_s,
        roof_color: g.call('roof_color', DEFAULT_ROOF_COLOR).to_s,
        fascia_color: g.call('roof_fascia_color', DEFAULT_FASCIA_COLOR).to_s,
        roof_material: g.call('roof_material', 'color').to_s,
        thickness: g.call('roof_thickness', DEFAULT_ROOF_THICKNESS).to_f,
        ridge_cap: g.call('roof_ridge_cap', true) == true,
        gable_walls: g.call('roof_gable_walls', true) == true
      }
    end

    def self.save_settings!(s)
      m = Sketchup.active_model
      m.set_attribute('InteriorPro', 'roof_style', s[:style])
      m.set_attribute('InteriorPro', 'roof_pitch', s[:pitch])
      m.set_attribute('InteriorPro', 'roof_overhang', s[:overhang])
      m.set_attribute('InteriorPro', 'roof_fascia', s[:fascia])
      m.set_attribute('InteriorPro', 'roof_fascia_depth', s[:fascia_depth])
      m.set_attribute('InteriorPro', 'roof_drip', s[:drip])
      m.set_attribute('InteriorPro', 'roof_soffit', s[:soffit])
      m.set_attribute('InteriorPro', 'roof_soffit_color', s[:soffit_color])
      m.set_attribute('InteriorPro', 'roof_color', s[:roof_color])
      m.set_attribute('InteriorPro', 'roof_fascia_color', s[:fascia_color])
      m.set_attribute('InteriorPro', 'roof_material', s[:roof_material])
      m.set_attribute('InteriorPro', 'roof_thickness', s[:thickness])
      m.set_attribute('InteriorPro', 'roof_ridge_cap', s[:ridge_cap])
      m.set_attribute('InteriorPro', 'roof_gable_walls', s[:gable_walls])
      s
    end

    # ---------- materials ----------

    def self.hex_to_color(hex)
      h = hex.to_s.gsub('#', '')
      return Sketchup::Color.new(120, 120, 120) unless h =~ /\A[0-9a-fA-F]{6}\z/
      Sketchup::Color.new(h[0, 2].to_i(16), h[2, 2].to_i(16), h[4, 2].to_i(16))
    end

    def self.color_material(model, hex)
      name = "InteriorPro_Roof_#{hex.to_s.gsub('#', '').downcase}"
      m = model.materials[name]
      return m if m
      m = model.materials.add(name)
      m.color = hex_to_color(hex)
      m
    end

    # Roof surface families (2026-08-10). A flat colour never reads as a
    # roof from any distance - the courses are what the eye picks up. Each
    # family is ONE greyscale tile that the chosen roof colour COLORIZES,
    # so "shingles in colours" costs one file, not one file per colour.
    # size = the tile's REAL size in inches, [width, height]; the shingle
    # tile is 4 courses of 6" exposure across 4 tabs of 12".
    # Every tile texture is GREYSCALE on purpose - surface_material tints it
    # with the user's colour picker, so one file serves every colour.
    #
    # The sizes are not decoration: each is a whole number of tiles wide and
    # a whole number of courses tall, matching RoofTileMath::SHAPES. That is
    # what will let the 3D course steps land exactly on the texture's own
    # tile lines instead of drifting across them. tests/rt73.rb pins it.
    # A METHOD, NOT A CONSTANT - and this is the whole reason it is one.
    # `X = {...} unless const_defined?(:X)` is NOT re-read by
    # InteriorPro.reload!; the old value stays in memory and the new one is
    # never seen. That cost a round on 2026-08-14 (DEFAULT_STATE) and it bit
    # again on 2026-08-18: the four tile jpgs were on disk, the menu listed
    # them, and every roof still came out a flat colour because this table
    # in memory still had one entry. tests/rt73.rb fails if it goes back.
    def self.roof_textures
      {
        'shingle' => { file: 'roof_shingle.jpg',       size: [48.0, 24.0] },
        'barrel'  => { file: 'roof_barrel_tile.jpg',   size: [52.0, 42.0] },
        'roman'   => { file: 'roof_roman_tile.jpg',    size: [52.0, 42.0] },
        # 52 x 52 since 2026-08-21c: a whole 4 x 4 of the 13" flat tile. It was
        # 48 x 32, a 4 x 4 of the old 12 x 8 tile - the painted grid and the 3D
        # grid are ONE grid, and rt73 fails the moment they drift apart.
        'slate'   => { file: 'roof_flat_slate.jpg',    size: [52.0, 52.0] },
        'seam'    => { file: 'roof_standing_seam.jpg', size: [48.0, 16.0] },
        # 48 x 32 = 3 ribs of 16" across, 2 courses of 16" up. rt73 checks
        # both of those divide exactly, so the painted grid lands on the 3D one.
        # 21 x 14 = 3 modules of 7" across, 2 courses of 7" up.
        # 21 x 28 = 3 modules of 7" across, 2 courses of 14" up.
        'metaltile' => { file: 'roof_metal_tile.jpg',  size: [21.0, 28.0] }
      }
    end

    def self.texture_path(fname)
      File.join(File.dirname(__FILE__), 'textures', fname.to_s)
    end

    # What the roof SURFACE is painted with: a plain colour, or a textured
    # family tinted by that same colour. Falls back to the plain colour if
    # the family is unknown or its file is missing, so a bad setting can
    # never leave the roof unbuilt.
    # EVERY ROOF TAKES THE COLOUR PICKER (2026-08-21, "בכל הגגות תעשה את אותו
    # המנגנון של הצבע"). The photographed tile textures are still on disk and
    # still checked by rt73 - they are simply not painted on any more, because
    # the 3D now carries the pattern and the real materials get done in Lumion.
    #
    # Kill switch, CLAUDE.md convention: set this back to true and every
    # material returns to its texture, tinted by the colour exactly as before.
    # Spanish Tile stays flat either way - its own shape says so.
    USE_ROOF_TEXTURES = false unless const_defined?(:USE_ROOF_TEXTURES, false)

    # WHICH FAMILIES STILL GET THEIR PICTURE (2026-08-21, "תעשה טקסטורה נכון
    # לעכשיו רק בשינגלס").
    #
    # USE_ROOF_TEXTURES turned every roof over to the plain colour picker
    # earlier the same day, because the tile materials carry their pattern in
    # 3D now and a photographed tile under that is two patterns fighting.
    # Shingle has no 3D piece at all, so switching it off left it a flat
    # colour with nothing on it.
    #
    # A METHOD and a list, not another constant: a `const_defined?` constant is
    # not re-read by InteriorPro.reload! and needs a full SketchUp restart, so
    # adding or removing a family this way is one edit and a reload. The
    # USE_ROOF_TEXTURES switch still works and still wins - set it true and
    # EVERY family goes back to its texture, exactly as before.
    def self.textured_families
      ['shingle']
    end

    def self.textured?(name)
      USE_ROOF_TEXTURES || textured_families.include?(name.to_s)
    end

    def self.surface_material(model, s)
      # One place answers this, because the deck and the tile instances are
      # both painted from here and the user asked for both.
      return color_material(model, s[:roof_color]) unless textured?(s[:roof_material])
      if defined?(InteriorPro::RoofTileMath) &&
         InteriorPro::RoofTileMath.flat_color?(s[:roof_material])
        return color_material(model, s[:roof_color])
      end
      spec = roof_textures[s[:roof_material].to_s]
      return color_material(model, s[:roof_color]) if spec.nil?
      path = texture_path(spec[:file])
      unless File.exist?(path)
        puts "[Roof] texture missing: #{path} - falling back to colour"
        return color_material(model, s[:roof_color])
      end
      hex = s[:roof_color].to_s.gsub('#', '').downcase
      name = "InteriorPro_Roof_#{s[:roof_material]}_#{hex}"
      m = model.materials[name]
      return m if m
      m = model.materials.add(name)
      begin
        m.texture = path
        m.texture.size = spec[:size] if m.texture
      rescue StandardError => e
        puts "[Roof] texture #{spec[:file]}: #{e.message}"
      end
      m.color = hex_to_color(s[:roof_color]) # tints the greyscale tile
      m
    end

    # ---------- footprint: true outline + overhang ----------

    # Closed CCW loop of the walls' centerlines (RoomManager machinery),
    # offset OUTWARD to the exterior faces plus the overhang.
    # Returns { pts: [[x, y], ...], wall_ids: [id per edge] } or nil —
    # edge i runs pts[i] -> pts[i+1] and belongs to wall_ids[i].
    def self.eave_polygon(walls, overhang)
      rm = InteriorPro::RoomManager
      segs = walls.map { |w| rm.centerline(w) }.compact
      return nil if segs.length < 3
      nodes, edges = rm.build_graph(segs)
      faces = rm.trace_faces(nodes, edges)
      best = nil
      best_area = 144.0
      faces.each do |f|
        poly = f[:node_ids].map { |i| nodes[i] }
        sa = rm.signed_area(poly)
        next if sa <= best_area
        best = f
        best_area = sa
      end
      return nil unless best
      poly  = best[:node_ids].map { |i| nodes[i] }
      edata = best[:edge_ids].map { |i| edges[i] }
      out = outer_offset(poly, edata, overhang)
      return nil unless out
      pts = out.map { |p| [p[0].x.to_f, p[0].y.to_f] }
      ids = out.map { |p| p[1] }
      if polygon_area(pts) < 0 # skeleton wants CCW
        pts.reverse!
        ids = ids.reverse.rotate(1) # keep edge i -> wall alignment
      end
      { pts: pts, wall_ids: ids }
    end

    # Mirror of RoomManager.inner_boundary, offset to the OTHER side:
    # each loop edge moves outward by half its wall thickness + overhang.
    # Returns [[point, wall_id_of_the_edge_starting_here], ...].
    #
    # CURVED WALLS (2026-08-12). A bowed wall is no longer flattened to its
    # chord here. Its eave is the CONCENTRIC arc - the wall's centreline
    # circle pushed out by half the thickness plus the overhang - cut at both
    # ends against its neighbours' own eaves, then chopped into short straight
    # pieces. Every one of those pieces carries the SAME wall id, so the roof
    # downstream (fascia, gable marks, cells) still knows which wall it is
    # standing on. A straight wall runs the identical code it always did.
    def self.outer_offset(poly, loop_edges, overhang)
      n = poly.length
      rails = []
      n.times do |i|
        p = poly[i]
        q = poly[(i + 1) % n]
        ref = Geom::Vector3d.new(q.x - p.x, q.y - p.y, 0)
        return nil if ref.length < 0.01
        r = eave_rail(loop_edges[i], ref, p, overhang)
        return nil unless r
        rails << r
      end

      corners = Array.new(n) { |i| rail_corner(rails[(i - 1) % n], rails[i]) }
      return nil if corners.any?(&:nil?)

      out = []
      n.times do |i|
        edge = loop_edges[i]
        wid = edge && edge[:wall] ? edge[:wall].get_attribute('InteriorPro', 'id') : nil
        pts = if rails[i][:kind] == :arc
                facet_rail(rails[i][:arc], corners[i], corners[(i + 1) % n])
              else
                [corners[i]]
              end
        pts.each { |pt| out << [Geom::Point3d.new(pt[0], pt[1], 0), wid] }
      end
      dedup = []
      out.each { |p| dedup << p if dedup.empty? || dedup.last[0].distance(p[0]) > 0.01 }
      dedup.pop if dedup.length > 1 && dedup.first[0].distance(dedup.last[0]) < 0.01
      dedup.length < 3 ? nil : dedup
    end

    # The wall's CENTRELINE as an arc in world XY, or nil when the wall is
    # straight (no arc_sag), when the curve maths is not loaded, or when the
    # bow is so tight that the centreline would swallow its own centre.
    # Exactly what RoomManager.centerline describes - the drawn line pushed
    # sideways by the anchor - only kept as a circle instead of a chord.
    def self.wall_center_arc(wall)
      return nil unless wall && wall.valid?
      return nil unless defined?(InteriorPro::WallTool) && defined?(InteriorPro::ArcMath)
      wt = InteriorPro::WallTool
      am = InteriorPro::ArcMath
      return nil unless wt.curved_wall?(wall)

      t  = wall.transformation
      sx = wall.get_attribute('InteriorPro', 'start_x')
      sy = wall.get_attribute('InteriorPro', 'start_y')
      ex = wall.get_attribute('InteriorPro', 'end_x')
      ey = wall.get_attribute('InteriorPro', 'end_y')
      return nil if sx.nil? || ex.nil?
      s = Geom::Point3d.new(sx.to_f, sy.to_f, 0).transform(t)
      e = Geom::Point3d.new(ex.to_f, ey.to_f, 0).transform(t)

      arc = am.from_chord_and_sag(s.x, s.y, e.x, e.y, wt.wall_sag(wall))
      return nil unless arc

      th = wall.get_attribute('InteriorPro', 'thickness').to_f
      anchor = (wall.get_attribute('InteriorPro', 'anchor') || 'bottom-center').to_s
      h = anchor == 'center' ? 'center' : (anchor.split('-')[1] || 'center')
      o_pos, o_neg = wt.anchor_side_offsets(th, h)
      am.offset(arc, (o_pos + o_neg) / 2.0)
    rescue StandardError => e2
      puts "[Roof] wall_center_arc: #{e2.message}"
      nil
    end

    # One edge of the eave, ready to be crossed with its neighbours. A straight
    # wall gives a LINE, a curved one an ARC - both already pushed out by half
    # the thickness plus the overhang, and both already running the way the
    # loop runs. nil only when the edge is degenerate.
    def self.eave_rail(edge, ref, fallback_base, overhang)
      rm = InteriorPro::RoomManager
      wall = edge && edge[:wall]
      th = edge ? edge[:th].to_f : 0.0
      k = th / 2.0 + overhang.to_f

      arc = wall ? wall_center_arc(wall) : nil
      if arc
        am = InteriorPro::ArcMath
        sp = am.start_point(arc)
        ep = am.end_point(arc)
        along = ((ep[0] - sp[0]) * ref.x) + ((ep[1] - sp[1]) * ref.y)
        arc = am.reverse(arc) if along < 0.0     # walk it the loop's way
        pushed = am.offset(arc, -k)              # right of travel = exterior
        return { kind: :arc, arc: pushed } if pushed
      end

      seg = wall ? rm.centerline(wall) : nil
      if seg
        s = seg[:s]
        e = seg[:e]
        d = Geom::Vector3d.new(e.x - s.x, e.y - s.y, 0)
        d.reverse! if d % ref < 0
        base = s
      else
        d = ref
        base = fallback_base
      end
      len = d.length
      return nil if len < 1e-9
      off = Geom::Vector3d.new(d.y / len * k, -d.x / len * k, 0) # right = exterior
      { kind: :line, base: base + off, dir: d }
    end

    # Where two neighbouring eave rails cross, as [x, y].
    # Straight/straight is the plain line intersection the roof always used.
    # With a curve in it the maths stays closed-form - a line meets a circle,
    # or two circles meet - and the right root is simply the one nearest where
    # the rail already ends. No guessing, no tolerance fiddling.
    def self.rail_corner(prev, cur)
      return nil if prev.nil? || cur.nil?
      am = InteriorPro::ArcMath if defined?(InteriorPro::ArcMath)

      if prev[:kind] == :line && cur[:kind] == :line
        pt = Geom.intersect_line_line([prev[:base], prev[:dir]], [cur[:base], cur[:dir]])
        pt ||= cur[:base]
        return [pt.x, pt.y]
      end
      return nil unless am

      if prev[:kind] == :arc && cur[:kind] == :arc
        a = prev[:arc]
        b = cur[:arc]
        ref = am.end_point(a)
        hit = am.nearest_point(am.circle_circle(a[:cx], a[:cy], a[:r],
                                                b[:cx], b[:cy], b[:r]), ref[0], ref[1])
        return hit if hit
        # Two circles that never meet: halfway along the line of centres, at
        # each circle's own closest approach.
        d = am.dist(a[:cx], a[:cy], b[:cx], b[:cy])
        return ref if d < 1e-9
        ux = (b[:cx] - a[:cx]) / d
        uy = (b[:cy] - a[:cy]) / d
        return [((a[:cx] + ux * a[:r]) + (b[:cx] - ux * b[:r])) / 2.0,
                ((a[:cy] + uy * a[:r]) + (b[:cy] - uy * b[:r])) / 2.0]
      end

      arc  = prev[:kind] == :arc ? prev[:arc] : cur[:arc]
      line = prev[:kind] == :arc ? cur : prev
      ref  = prev[:kind] == :arc ? am.end_point(arc) : am.start_point(arc)
      hit = am.nearest_point(am.line_circle(line[:base].x, line[:base].y,
                                            line[:dir].x, line[:dir].y,
                                            arc[:cx], arc[:cy], arc[:r]), ref[0], ref[1])
      return hit if hit
      # A big bulge can carry the curve's eave circle clear PAST its
      # neighbour's eave line, so they never cross. The straight run must not
      # be tilted to chase it (that would slope a whole fascia board): the
      # straight eave stays exactly where it is and the corner is put at the
      # nearest point on it, which the curve then reaches for. Same rule the
      # wall corners use - the straight one owns the seam.
      am.closest_point_on_line(line[:base].x, line[:base].y,
                               line[:dir].x, line[:dir].y,
                               arc[:cx], arc[:cy])
    end

    # A curved eave as the short straight pieces the roof is really built from:
    # the arc cut back to its two corners, then sampled. The LAST sample is
    # dropped - it is the next edge's corner, and that edge emits it.
    def self.facet_rail(arc, c0, c1)
      am = InteriorPro::ArcMath
      cut = am.retrim(arc, c0, c1)
      return [c0] unless cut
      pts = am.chord_points(cut, ROOF_CURVE_TOL)
      return [c0] if pts.nil? || pts.length < 2
      pts[0] = c0            # sit exactly on the corner, not a rounded copy
      pts.pop
      pts
    rescue StandardError => e
      puts "[Roof] facet_rail: #{e.message}"
      [c0]
    end

    # ---------- tiny 2D vector helpers ([x, y] arrays) ----------

    def self.vsub(a, b); [a[0] - b[0], a[1] - b[1]]; end
    def self.vadd(a, b); [a[0] + b[0], a[1] + b[1]]; end
    def self.vmul(a, k); [a[0] * k, a[1] * k]; end
    def self.vdot(a, b); a[0] * b[0] + a[1] * b[1]; end
    def self.vcross(a, b); a[0] * b[1] - a[1] * b[0]; end
    def self.vlen(a); Math.sqrt(vdot(a, a)); end

    def self.vnorm(a)
      l = vlen(a)
      l < 1e-12 ? [0.0, 0.0] : [a[0] / l, a[1] / l]
    end

    def self.polygon_area(pts)
      a = 0.0
      pts.each_with_index do |p, i|
        q = pts[(i + 1) % pts.length]
        a += p[0] * q[1] - q[0] * p[1]
      end
      a / 2.0
    end

    # Offset a CCW polygon OUTWARD by k (straight miter at the corners).
    def self.offset_polygon(pts, k)
      n = pts.length
      lines = Array.new(n) do |i|
        d = vnorm(vsub(pts[(i + 1) % n], pts[i]))
        [vadd(pts[i], vmul([d[1], -d[0]], k)), d] # right = outward for CCW
      end
      out = []
      n.times do |i|
        p1, d1 = lines[(i - 1) % n]
        p2, d2 = lines[i]
        den = vcross(d1, d2)
        out << if den.abs < 1e-9
                 p2
               else
                 t = vcross(vsub(p2, p1), d2) / den
                 vadd(p1, vmul(d1, t))
               end
      end
      out
    end

    # ---------- straight skeleton (Felkel/Obdrzalek wavefront) ----------
    # Input: simple CCW polygon [[x,y],...] + optional per-edge speeds
    # (1.0 = normal sloped edge, 0.0 = gable edge whose line never moves).
    # Output: skeleton arcs [[[x,y],[x,y]], ...] or nil on failure.
    # Each vertex moves at the velocity b that solves b.n_left = s_left and
    # b.n_right = s_right, keeping it at offset s_e * t from each edge line.
    def self.straight_skeleton(pts, speeds = nil)
      n = pts.length
      return nil if n < 3
      edges = Array.new(n) do |i|
        p = pts[i]
        q = pts[(i + 1) % n]
        d = vnorm(vsub(q, p))
        { p: p, d: d, n: [-d[1], d[0]], s: speeds ? speeds[i].to_f : 1.0 }
      end

      make_vertex = lambda do |pt, t0, el, er|
        dl = edges[el][:d]
        dr = edges[er][:d]
        nl = edges[el][:n]
        nr = edges[er][:n]
        sl = edges[el][:s]
        sr = edges[er][:s]
        det = vcross(nl, nr)
        vel = if det.abs < 1e-9
                # collinear SAME-direction edges slide with their line;
                # ANTIPARALLEL (facing) edges are a degenerate ridge vertex
                # and must stay put (handled as a corridor annihilation).
                ((sl - sr).abs < 1e-9 && vdot(nl, nr) > 0.0) ? vmul(nl, sl) : [0.0, 0.0]
              else
                [(sl * nr[1] - sr * nl[1]) / det,
                 (nl[0] * sr - nr[0] * sl) / det]
              end
        { pt: pt, t0: t0, el: el, er: er, vel: vel,
          reflex: vcross(dl, dr) < -1e-9, alive: true, prev: nil, next: nil }
      end

      verts = Array.new(n) { |i| make_vertex.call(pts[i], 0.0, (i - 1) % n, i) }
      n.times do |i|
        verts[i][:next] = verts[(i + 1) % n]
        verts[i][:prev] = verts[(i - 1) % n]
      end

      # Tear junctions (2026-08-05, gable ending mid-wall): two COLLINEAR
      # edges with different speeds share a vertex no velocity satisfies.
      # Insert a zero-length VERTICAL virtual edge (speed 0) there: one
      # vertex stays put on the standing line, its twin climbs straight
      # inward along the tear — exactly where the mother gable ends and the
      # attached wing's slope takes over.
      n.times do |i|
        el = (i - 1) % n
        er = i
        next if (edges[el][:s] - edges[er][:s]).abs < 1e-9
        next unless vcross(edges[el][:d], edges[er][:d]).abs < 1e-9 &&
                    vdot(edges[el][:d], edges[er][:d]) > 0
        dirv = edges[el][:n]
        dirv = vmul(dirv, -1.0) if edges[er][:s] < edges[el][:s]
        edges << { p: pts[i], d: dirv, n: [-dirv[1], dirv[0]], s: 0.0 }
        virt = edges.length - 1
        vi = verts[i]
        va = make_vertex.call(pts[i], 0.0, el, virt)
        vb = make_vertex.call(pts[i], 0.0, virt, er)
        va[:prev] = vi[:prev]
        va[:next] = vb
        vb[:prev] = va
        vb[:next] = vi[:next]
        vi[:prev][:next] = va
        vi[:next][:prev] = vb
        vi[:alive] = false
        verts << va << vb
      end

      pos = lambda { |v, t| vadd(v[:pt], vmul(v[:vel], t - v[:t0])) }
      arcs = []
      emit = lambda do |a, b|
        arcs << [a, b] if vlen(vsub(a, b)) > NODE_TOL
      end

      # registry of every vertex ever created (for LAV walks)
      all_verts = verts.dup

      alive_cycles = lambda do
        visited = {}
        cycles = []
        all_verts.each do |v|
          next unless v[:alive]
          next if visited[v.object_id]
          cyc = []
          c = v
          guard = 0
          loop do
            visited[c.object_id] = true
            cyc << c
            c = c[:next]
            guard += 1
            break if c.equal?(v) || guard > 2000
          end
          cycles << cyc if guard <= 2000
        end
        cycles
      end

      close_small = lambda do |cyc|
        return false unless cyc.length <= 2
        if cyc.length == 2
          emit.call(cyc[0][:pt], cyc[1][:pt])
        end
        cyc.each { |v| v[:alive] = false }
        true
      end

      guard = 0
      loop do
        guard += 1
        return nil if guard > 400
        cycles = alive_cycles.call
        cycles = cycles.reject { |c| close_small.call(c) }
        break if cycles.empty?

        best = nil
        cycles.each do |cyc|
          # edge events between adjacent vertices
          cyc.each do |v|
            w = v[:next]
            e = v[:er]
            d = edges[e][:d]
            a0 = vdot(w[:pt], d) - w[:t0] * vdot(w[:vel], d) -
                 vdot(v[:pt], d) + v[:t0] * vdot(v[:vel], d)
            k = vdot(w[:vel], d) - vdot(v[:vel], d)
            next if k.abs < 1e-12
            t = -a0 / k
            tmin = [v[:t0], w[:t0]].max - 1e-9
            next if t < tmin
            next if k > 0 # the gap must be closing, not opening
            cand = { t: t, kind: :edge, v: v, w: w, i: pos.call(v, t), cyc: cyc }
            best = cand if best.nil? || t < best[:t] - 1e-9
          end
          # split events for reflex vertices
          cyc.each do |v|
            next unless v[:reflex]
            edges.each_index do |ei|
              next if ei == v[:el] || ei == v[:er]
              ne = edges[ei][:n]
              c = vdot(ne, v[:vel])
              den = edges[ei][:s] - c # opposite edge offsets at its own speed
              next if den.abs < 1e-9
              a = vdot(ne, vsub(v[:pt], edges[ei][:p]))
              t = (a - c * v[:t0]) / den
              next if t < v[:t0] + 1e-6
              bpt = pos.call(v, t)
              # the opposite edge's wavefront must actually contain B
              holder = cyc.find do |y|
                next false unless y[:alive] && y[:er] == ei && !y.equal?(v) && !y[:next].equal?(v)
                z = y[:next]
                de = edges[ei][:d]
                vdot(vsub(bpt, pos.call(y, t)), de) >= -0.01 &&
                  vdot(vsub(pos.call(z, t), bpt), de) >= -0.01
              end
              next unless holder
              cand = { t: t, kind: :split, v: v, i: bpt, e: ei, y: holder, cyc: cyc }
              best = cand if best.nil? || t < best[:t] - 1e-9
            end
          end
        end
        break if best.nil?

        if best[:kind] == :edge
          v = best[:v]
          w = best[:w]
          i = best[:i]
          cyc = best[:cyc]
          if cyc.length == 3
            cyc.each do |x|
              emit.call(x[:pt], i)
              x[:alive] = false
            end
          else
            emit.call(v[:pt], i)
            emit.call(w[:pt], i)
            u = make_vertex.call(i, best[:t], v[:el], w[:er])
            all_verts << u
            u[:prev] = v[:prev]
            u[:next] = w[:next]
            v[:prev][:next] = u
            w[:next][:prev] = u
            v[:alive] = false
            w[:alive] = false
            # Corridor annihilation (2026-08-05, the holes bug): if u's two
            # edges FACE each other (a wing collapsing into the body), the
            # zero-width corridor between the two touching fronts dies
            # along its midline right now, over the interval where they
            # overlap. That reaches the NEARER neighbour; if the far front
            # continues, a merged vertex carries on there — which can chain
            # into another facing pair, so keep resolving in a loop.
            cur = u
            ann_guard = 0
            loop do
              ann_guard += 1
              break if ann_guard > 60
              break unless cur[:alive]
              nl = edges[cur[:el]][:n]
              nr = edges[cur[:er]][:n]
              break unless vcross(nl, nr).abs < 1e-9 && vdot(nl, nr) < 0.0
              p = cur[:prev]
              q = cur[:next]
              if p.equal?(q)
                pp = pos.call(p, best[:t])
                emit.call(cur[:pt], pp)
                emit.call(p[:pt], pp)
                cur[:alive] = false
                p[:alive] = false
                break
              end
              pp = pos.call(p, best[:t])
              qq = pos.call(q, best[:t])
              dp = vlen(vsub(pp, cur[:pt]))
              dq = vlen(vsub(qq, cur[:pt]))
              if vlen(vsub(pp, qq)) < NODE_TOL * 10
                # both neighbours arrive together: 3-way merge
                emit.call(cur[:pt], pp)
                emit.call(p[:pt], pp)
                emit.call(q[:pt], pp)
                cur[:alive] = false
                p[:alive] = false
                q[:alive] = false
                break if p[:prev].equal?(q) # the whole LAV died here
                m2 = make_vertex.call(pp, best[:t], p[:el], q[:er])
                all_verts << m2
                m2[:prev] = p[:prev]
                m2[:next] = q[:next]
                p[:prev][:next] = m2
                q[:next][:prev] = m2
                cur = m2
                next
              end
              # one-sided: the corridor ends at the nearer neighbour and
              # the far front survives past it
              near_q = dq < dp
              tgt = near_q ? q : p
              tpos = near_q ? qq : pp
              axis = edges[cur[:el]][:d]
              dirv = vnorm(vsub(tpos, cur[:pt]))
              break if vcross(axis, dirv).abs > 0.05 # not along the corridor
              emit.call(cur[:pt], tpos)
              emit.call(tgt[:pt], tpos)
              cur[:alive] = false
              tgt[:alive] = false
              el2   = near_q ? cur[:el] : tgt[:el]
              er2   = near_q ? tgt[:er] : cur[:er]
              prev2 = near_q ? cur[:prev] : tgt[:prev]
              next2 = near_q ? tgt[:next] : cur[:next]
              w2 = make_vertex.call(tpos, best[:t], el2, er2)
              all_verts << w2
              w2[:prev] = prev2
              w2[:next] = next2
              prev2[:next] = w2
              next2[:prev] = w2
              cur = w2
            end
          end
        else # split
          v = best[:v]
          b = best[:i]
          y = best[:y]
          z = y[:next]
          emit.call(v[:pt], b)
          v1 = make_vertex.call(b, best[:t], v[:el], best[:e])
          v2 = make_vertex.call(b, best[:t], best[:e], v[:er])
          all_verts << v1
          all_verts << v2
          # LAV 1: v.prev -> v1 -> z ...
          v1[:prev] = v[:prev]
          v1[:next] = z
          v[:prev][:next] = v1
          z[:prev] = v1
          # LAV 2: y -> v2 -> v.next ...
          v2[:prev] = y
          v2[:next] = v[:next]
          y[:next] = v2
          v[:next][:prev] = v2
          v[:alive] = false
        end
      end
      arcs
    end

    # ---------- cells: polygon edges + arcs -> one face per eave edge ----

    # Returns [{ pts: [[x,y],...], eave: edge_index }, ...] or nil.
    # speeds: per-polygon-edge; a cell's eave must be a SLOPED edge (gable
    # arcs run along the gable edge itself, so polygon edges are split at
    # every node that lands on them and overlapping arcs dedupe away).
    def self.roof_cells(poly, arcs, speeds = nil)
      rm = InteriorPro::RoomManager
      npts = []
      node_of = lambda do |p|
        npts.each_with_index do |q, i|
          return i if vlen(vsub(q, p)) < NODE_TOL
        end
        npts << [p[0], p[1]]
        npts.length - 1
      end
      n = poly.length
      # every segment: polygon edges first (their eave tag wins on
      # overlaps), then the skeleton arcs
      segs = []
      n.times { |i| segs << [poly[i], poly[(i + 1) % n], i] }
      arcs.each { |a, b| segs << [a, b, nil] }
      segs.each do |a, b, _|
        node_of.call(a)
        node_of.call(b)
      end

      graph = []
      seen = {}
      add_edge = lambda do |a, b, tag|
        key = [a, b].sort
        return if a == b || seen[key]
        seen[key] = true
        graph << { a: a, b: b, eave: tag }
      end
      # EVERY segment is split at every node that sits on it — valley
      # arcs can legitimately run THROUGH an earlier skeleton node
      # (2026-08-05, the vanished-cell bug).
      segs.each do |a, b, tag|
        d = vnorm(vsub(b, a))
        len = vlen(vsub(b, a))
        next if len < NODE_TOL
        stops = []
        npts.each_with_index do |p, id|
          t = vdot(vsub(p, a), d)
          next if t < -NODE_TOL || t > len + NODE_TOL
          perp = vcross(d, vsub(p, a)).abs
          stops << [t, id] if perp < NODE_TOL
        end
        stops.sort_by!(&:first)
        stops.each_cons(2) { |(_, u), (_, v)| add_edge.call(u, v, tag) }
      end

      points = npts.map { |p| Geom::Point3d.new(p[0], p[1], 0) }
      faces = rm.trace_faces(points, graph)
      cells = []
      faces.each do |f|
        pts = f[:node_ids].map { |i| npts[i] }
        next if polygon_area(pts) < 1.0
        eave = f[:edge_ids].map { |i| graph[i][:eave] }.compact
                .find { |t| speeds.nil? || speeds[t].to_f > 0.5 }
        next if eave.nil? # the outer face / gable-only borders
        cells << { pts: pts, eave: eave }
      end
      cells.empty? ? nil : cells
    end

    # ---------- build / remove ----------

    # Build (or rebuild) the roof from the saved settings; keyword args
    # override AND update the saved settings. Console examples:
    #   InteriorPro::RoofManager.build_roof!(pitch: 6, overhang: 18)
    #   InteriorPro::RoofManager.build_roof!(style: 'flat')
    def self.build_roof!(style: nil, pitch: nil, overhang: nil,
                         fascia: nil, fascia_depth: nil, drip: nil,
                         roof_color: nil, fascia_color: nil,
                         roof_material: nil, thickness: nil, ridge_cap: nil,
                         gable_walls: nil, soffit: nil, soffit_color: nil)
      model = Sketchup.active_model
      s = settings
      s[:gable_walls] = (gable_walls == true) unless gable_walls.nil?
      s[:style] = style.to_s if style
      s[:pitch] = pitch.to_f if pitch
      s[:overhang] = overhang.to_f unless overhang.nil?
      s[:fascia] = (fascia == true) unless fascia.nil?
      s[:fascia_depth] = fascia_depth.to_f if fascia_depth && fascia_depth.to_f > 0.01
      s[:drip] = (drip == true) unless drip.nil?
      s[:soffit] = soffit.to_s if soffit
      s[:soffit_color] = soffit_color.to_s if soffit_color
      s[:roof_color] = roof_color.to_s if roof_color
      s[:fascia_color] = fascia_color.to_s if fascia_color
      s[:roof_material] = roof_material.to_s if roof_material
      s[:thickness] = thickness.to_f unless thickness.nil?
      s[:ridge_cap] = (ridge_cap == true) unless ridge_cap.nil?
      slope = s[:pitch] / 12.0

      walls = top_walls
      ep = walls.length >= 3 ? eave_polygon(walls, s[:overhang]) : nil
      if ep.nil?
        UI.messagebox('No closed loop of exterior walls to roof yet')
        return nil
      end
      poly = ep[:pts]
      wall_ids = ep[:wall_ids]
      cells = nil
      speeds = nil
      gables = []
      framed = nil
      unless s[:style] == 'flat'
        # Gable ends: walls the user marked with the Gable Ends tool win;
        # with no marks, the Gable style falls back to the two short ends.
        marked = gable_wall_ids
        clicks_by_id = {}
        gable_click_points.each_with_index do |pt, k|
          next if marked[k].nil? || pt[0].to_f > 1.0e8 # sentinel = no point
          clicks_by_id[marked[k]] = pt
        end
        # ignore marks whose wall no longer exists in this roof loop
        # (2026-08-05: a stale id after wall split/join blocked Gable style)
        loop_ids = wall_ids.compact
        dead = marked.reject { |id2| loop_ids.include?(id2) }
        puts "[Roof] ignoring #{dead.length} stale/off-loop gable mark(s)" unless dead.empty?
        marked -= dead
        # A CURVED wall never gables (2026-08-12B). toggle_gable_wall! refuses
        # to mark one, but a wall can be marked first and BENT afterwards, and
        # the Gable style picks its own ends with no marks at all. A bowed wall
        # reaches the roof as a run of facets sharing one id, so it is spotted
        # the same way facet_hip_points spots it.
        bowed = wall_ids.compact.tally.select { |_i, c| c > 1 }.keys
        unless bowed.empty?
          dropped = marked & bowed
          marked -= bowed
          puts "[Roof] #{dropped.length} gable mark(s) ignored - the wall is curved" unless dropped.empty?
        end
        gables = (0...poly.length).select { |i| wall_ids[i] && marked.include?(wall_ids[i]) }
        want_gable = !gables.empty? || s[:style] == 'gable'
        # Over-framing first (2026-08-05, the user's mock): a marked wall
        # gables its WHOLE wing, volumes intersect on valleys. The strip-
        # gable skeleton stays as fallback for non-rectilinear plans.
        framed = framed_plan(poly, wall_ids, marked, s[:style]) if want_gable
        if framed
          gables = framed[:edges]
        else
          puts '[Roof] plan not decomposable - strip-gable fallback' if want_gable
          if gables.empty? && s[:style] == 'gable'
            gables = pick_gable_edges(poly)
            # ...but never onto a bowed wall's facets.
            gables = gables.reject { |i| bowed.include?(wall_ids[i]) }
          end
          unless gables.empty?
            # A marked wall that runs past its own roof section (a wing
            # attaches along it) gets its gable only on ONE span: the strip
            # UNDER the user's click, or the deepest strip when no click was
            # saved (user 2026-08-05: the gable goes where I clicked).
            clicks_by_edge = {}
            gables.each do |i|
              c = wall_ids[i] && clicks_by_id[wall_ids[i]]
              clicks_by_edge[i] = c if c
            end
            poly, wall_ids, gables = split_gable_edges(poly, wall_ids, gables, clicks_by_edge)
            speeds = Array.new(poly.length, 1.0)
            gables.each { |i| speeds[i] = 0.0 }
          end
          arcs = straight_skeleton(poly, speeds)
          if arcs.nil?
            puts '[Roof] straight skeleton failed for this footprint'
            return nil
          end
          cells = roof_cells(poly, arcs, speeds)
          if cells.nil?
            puts '[Roof] could not form roof faces from the skeleton'
            return nil
          end
        end
      end

      save_settings!(s)
      z0 = eave_z(walls)
      lvl = top_level

      model.start_operation('InteriorPro Roof', true)
      roofs.each { |r| r.erase! if r.valid? } # rebuild replaces, never stacks
      grp = model.entities.add_group
      grp.name = 'InteriorPro_Roof'
      InteriorPro.assign_tag(grp, 'IP/Roofs')
      roof_mat = surface_material(model, s)
      trim_mat = color_material(model, s[:fascia_color]) # fascia + drip + underside
      gable_flags = Array.new(poly.length, false)
      gables.each { |i| gable_flags[i] = true }
      zmap = nil
      if s[:style] == 'flat'
        ridge = build_flat_geometry!(grp, poly, z0, roof_mat, trim_mat)
        band_top = z0
      elsif framed
        ridge, zmap = build_framed_geometry!(grp, framed, z0, slope, s[:overhang],
                                             roof_mat, trim_mat)
        band_top = z0 - slope * s[:overhang]
      else
        ridge, zmap = build_hip_geometry!(grp, poly, cells, z0, slope, s[:overhang],
                                          roof_mat, trim_mat)
        band_top = z0 - slope * s[:overhang] # the surface at the eave edge
      end
      if ridge.nil?
        grp.erase! if grp.valid?
        model.abort_operation
        puts '[Roof] roof geometry failed'
        return nil
      end

      # ---- give the slab a thickness (2026-08-10) -----------------------
      # The shell just built becomes the UNDERSIDE. An identical shell is
      # built dz higher and the two are closed along the footprint, so the
      # roof reads as a real slab and the gable wall - which stops at the
      # underside - is covered instead of poking through the shingles.
      # Everything downstream keeps using the UNDERSIDE zmap, so the
      # fascia, the rake and the gable walls do not move at all.
      dz = slab_lift(s[:thickness], s[:style] == 'flat' ? 0.0 : slope)
      shell_before = grp.entities.grep(Sketchup::Face)
      if dz > 0.001
        if s[:style] == 'flat'
          build_flat_geometry!(grp, poly, z0 + dz, roof_mat, roof_mat)
        elsif framed
          build_framed_geometry!(grp, framed, z0 + dz, slope, s[:overhang],
                                 roof_mat, roof_mat)
        else
          build_hip_geometry!(grp, poly, cells, z0 + dz, slope, s[:overhang],
                              roof_mat, roof_mat)
        end
        build_slab_edge!(grp, poly, zmap, dz, z0, roof_mat)
      end

      # ---- ridge cap (2026-08-10) --------------------------------------
      # Read off the TOP shell only, so the caps sit on the surface you
      # can actually see rather than inside the slab.
      # The TOP shell only, read once and shared: the ridge caps sit on it
      # and so do the tile courses. Sub-groups are not Faces, so taking this
      # before either of them runs is the same list either way - but reading
      # it once says out loud that they are talking about the same surface.
      top_shell = dz > 0.001 ? (grp.entities.grep(Sketchup::Face) - shell_before)
                             : shell_before
      # A SHELL FACE BURIED UNDER ANOTHER ROOF FACE IS ERASED (2026-08-21c).
      # Where one wing's roof runs in under another, the intersection leaves
      # the buried continuation as its own face. First its TILES were
      # suppressed and the user corrected the aim: the piece itself goes -
      # "אנחנו הסרנו אותה בעבר... עדיף שהיא לא תהיה שם". You can see it
      # through the open gable end, and open gables are a stated feature.
      # ...and the slab's UNDERSIDE twin of anything erased goes with it, or
      # the deck is still there to see through the open gable. See
      # drop_buried_twins! for why the underside cannot be tested directly.
      top_shell = drop_buried_faces!(top_shell, grp.entities,
                                     dz > 0.001 ? shell_before : nil)
      if s[:ridge_cap] && s[:style] != 'flat'
        cap_lines = drop_facet_hips(ridge_lines(top_shell), poly, wall_ids)
        # THE VALLEY CHANNEL (2026-08-21) - the metal roof only: "צריך משהו
        # שמכסה פה בוואלי... זה יותר מוליך מים". The same line walk with the
        # filter flipped hands back the valleys, and build_ridge_caps! lays a
        # flat strip IN each one - on the deck, no lift - see the `valley`
        # comment there. No other material grows one.
        # (The flat tile briefly grew one too, plus a pull-back, 2026-08-21c.
        # The user replaced both with the real answer: its tiles are WEDGES
        # now, and a wedge cut on the valley line meets the opposite wedge in
        # a clean intersection - nothing to cover. See build_flat_cut!.)
        if defined?(InteriorPro::RoofTileMath) &&
           InteriorPro::RoofTileMath.respond_to?(:seam?) &&
           InteriorPro::RoofTileMath.seam?(s[:roof_material])
          cap_lines += ridge_lines(top_shell, valleys: true)
        end
        build_ridge_caps!(grp, cap_lines, slope, roof_mat, s[:roof_material])
      end


      # Fascia + drip edge tuck UNDER the roof edge (user 2026-08-05: the
      # roof sits on them and ends at its own outer arris). Fascia outer
      # face is flush with the slab edge; the drip sticks 0.1" past it to
      # cover the seam. Both hang from the slab underside line.
      # gable ends stay OPEN - no white triangle fill (user 2026-08-05B:
      # the wall itself will rise to the roof shape later).
      # build_gable_wall_face! is kept unused for a quick revert.
      # Where each gabled edge actually RISES above the eave: that is the
      # stretch the rake owns and the flat fascia must skip. The rest of
      # the same edge is a plain eave and keeps its fascia (2026-08-09).
      surf = framed ? lambda { |cx, cy| framed_cover_z(framed, band_top, slope, cx, cy, nil) } : nil
      gable_spans = nil
      if zmap && !gables.empty?
        gable_spans = {}
        gables.each do |i|
          ch = edge_profile_chain(poly, i, zmap, surface: surf)
          next if ch.nil?
          gable_spans[i] = chain_regions_above(ch, band_top)
                           .map { |rg| [rg.first[0], rg.last[0]] }
        end
      end
      # ---- eave tiles (2026-08-19, ROOF_TILES_PROPOSAL.md step 4) -------
      # 3D ONLY WHERE THE SILHOUETTE SHOWS, and on a roof that is the eave.
      # The field above it is seen against the roof itself, where the texture
      # already does the work - a 3D step on every course cost 50,652 faces
      # when it was finally counted, and looked wrong on top of that.
      # Only the four TILE materials get pieces; shingle and a plain colour
      # have no tile shape and are left exactly as they were.
      # Kill switch: InteriorPro::RoofManager::USE_ROOF_TILE_EDGES = false
      # NOT THE FLAT TILE (2026-08-21c). Its own bottom course IS the eave -
      # the piece hangs over the edge and carries its own nose - so the old
      # separate eave bar would sit 1.2" tall in among 0.7" tiles and show as
      # a doubled edge. Every other material still gets exactly what it did.
      if USE_ROOF_TILE_EDGES && s[:style] != 'flat' &&
         defined?(InteriorPro::RoofTilePlace) &&
         InteriorPro::RoofTileMath.shape(s[:roof_material]) &&
         !(InteriorPro::RoofTileMath.respond_to?(:run_flat?) &&
           InteriorPro::RoofTileMath.run_flat?(s[:roof_material]))
        begin
          tile_edges = roof_edges(top_shell, poly, wall_ids, zmap,
                                  gables: gables, band_top: band_top,
                                  surface: surf)
          InteriorPro::RoofTilePlace.place_eaves!(
            grp, InteriorPro::RoofTilePlace.planes_from_faces(top_shell),
            tile_edges, s[:roof_material], model: model, material: roof_mat
          )
        rescue StandardError => e
          puts "[Roof] eave tiles skipped: #{e.message}"
        end
      end

      # ---- tile RUNS (2026-08-20) --------------------------------------
      # What replaced the eave course above. The user sent his own reference
      # (Roman Tiled Roof.skp) and the shape is not a tile per course at all:
      # it is one half pipe running the whole slope, ridge to eave, with the
      # flat pan between two pipes left as roof face wearing the texture.
      #
      # It is CHEAPER than what it replaces, not dearer. A sweep costs its
      # cross section and length is free, so the pipe is modelled one inch
      # long and stretched per run - about ten unique faces for any roof.
      #
      # RoofTileMath.runs? keeps this to the round materials: barrel and
      # roman. Slate and standing seam are not pipes and are untouched.
      # Kill switch: InteriorPro::RoofManager::USE_ROOF_TILE_RUNS = false
      if USE_ROOF_TILE_RUNS && s[:style] != 'flat' &&
         defined?(InteriorPro::RoofTilePlace) &&
         InteriorPro::RoofTilePlace.respond_to?(:place_runs!) &&
         InteriorPro::RoofTileMath.runs?(s[:roof_material])
        begin
          InteriorPro::RoofTilePlace.place_runs!(
            grp, InteriorPro::RoofTilePlace.planes_from_faces(top_shell),
            s[:roof_material], model: model, material: roof_mat
          )
        rescue StandardError => e
          puts "[Roof] tile runs skipped: #{e.message}"
        end
        # THE EAVE FRAME. Standing seam only - the border the metal panels die
        # into, asked for on 2026-08-21 off the user's own photograph. Nothing
        # else places it, so no other material grows an edge it did not have.
        begin
          if InteriorPro::RoofTilePlace.respond_to?(:place_eave_bars!)
            InteriorPro::RoofTilePlace.place_eave_bars!(
              grp, InteriorPro::RoofTilePlace.planes_from_faces(top_shell),
              s[:roof_material], model: model, material: roof_mat
            )
          end
        rescue StandardError => e
          puts "[Roof] eave bar skipped: #{e.message}"
        end
      end

      if s[:fascia]
        build_band!(grp, poly, -FASCIA_THICK, 0.0, band_top, band_top - s[:fascia_depth],
                    gable_flags, gable_spans)
        # rake boards: the fascia climbing the sloped edges of a gable end.
        # One per gabled POLY EDGE, clipped to that edge (2026-08-09) - the
        # z profile still comes from the whole end-plane line, so an apex
        # outside the edge still makes the board climb, but the board never
        # leaves the building outline.
        if zmap && framed
          owners = framed_line_owners(framed)
          gables.each do |i|
            key = line_key(poly, i)
            cov = lambda { |cx, cy| framed_cover_z(framed, band_top, slope, cx, cy, owners[key]) }
            build_rake_board!(grp, poly, i, zmap, s[:fascia_depth],
                              cover: cov, surface: surf)
          end
        elsif zmap
          gables.each { |i| build_rake_board!(grp, poly, i, zmap, s[:fascia_depth]) }
        end
      end
      if s[:drip]
        build_band!(grp, poly, 0.0, DRIP_THICK, band_top, band_top - DRIP_DEPTH,
                    gable_flags, gable_spans)
        # ...and the same thin strip climbing the gable rakes (user
        # 2026-08-24). build_band! skips a gabled edge entirely, so without
        # this the drip stopped dead at the corner. It rides on the rake
        # fascia's outer face when there is one, and on the poly line itself
        # when the fascia is switched off, so it never floats in mid air.
        # Same chain/runs machinery as the rake fascia - no new geometry.
        d_in = s[:fascia] ? FASCIA_THICK : 0.0
        if zmap && framed
          owners = framed_line_owners(framed)
          gables.each do |i|
            key = line_key(poly, i)
            cov = lambda { |cx, cy| framed_cover_z(framed, band_top, slope, cx, cy, owners[key]) }
            build_rake_board!(grp, poly, i, zmap, DRIP_DEPTH, cover: cov,
                              surface: surf, k_in: d_in, k_out: d_in + DRIP_THICK)
          end
        elsif zmap
          gables.each do |i|
            build_rake_board!(grp, poly, i, zmap, DRIP_DEPTH,
                              k_in: d_in, k_out: d_in + DRIP_THICK)
          end
        end
      end
      # The soffit closes the eave from below. It skips the gable rakes for
      # the same reason the fascia does - there the roof edge climbs, so
      # there is no horizontal underside to board over.
      if s[:soffit] != 'none'
        had = {}
        grp.entities.grep(Sketchup::Face).each { |f| had[f.object_id] = true }
        sb = soffit_band(s[:overhang], s[:fascia_depth], s[:fascia], band_top)
        # 'beams' is the one style with NO board. It borrows the board's own
        # k range so the tails start and stop exactly where the board would
        # have, and everything below - the square gable corner, the rake
        # twin, the seam softening - is board work and is skipped.
        beams = s[:soffit].to_s == 'beams'
        build_eave_beams!(grp, poly, sb[:k_in], sb[:k_out], band_top, gable_flags) if sb && beams
        if sb && !beams
          # square_flags = the gable edges: where the flat board meets a
          # rake it runs straight on across the corner square and ends in
          # a rectangle, no 45 degree diagonal (user 2026-08-24).
          build_band!(grp, poly, sb[:k_in], sb[:k_out], sb[:z_top], sb[:z_bot],
                      gable_flags, gable_spans, gable_flags)
        end
        # ...and the same board climbing the gable rakes, so the overhang
        # is closed all the way round and not only on the flat eaves
        # (user 2026-08-24: "צריך להיות גם באיב של הגייבל").
        if sb && !beams && zmap && !gables.empty?
          if framed
            owners = framed_line_owners(framed)
            gables.each do |i|
              key = line_key(poly, i)
              cov = lambda { |cx, cy| framed_cover_z(framed, band_top, slope, cx, cy, owners[key]) }
              build_rake_soffit!(grp, poly, i, zmap, s[:fascia_depth], s[:overhang],
                                 cover: cov, surface: surf)
            end
          else
            gables.each do |i|
              build_rake_soffit!(grp, poly, i, zmap, s[:fascia_depth], s[:overhang])
            end
          end
        end
        # LAST, after every soffit face exists. Every corner of the band is
        # mitered, and on a board you look straight up at, that miter reads
        # as a diagonal scratch across the ceiling (user 2026-08-24). It is
        # a joint between two flush boards, so it is softened away.
        # Softening BEFORE the gable boards went in did not hold: adding a
        # face on the same line splits that edge, and the new halves come
        # back hard.
        if sb && !beams
          soften_seams!(grp, band_corner_seams(poly, sb[:k_in], sb[:k_out],
                                               sb[:z_bot], sb[:z_top]))
        end
        # ...and then the general rule, over every face the soffit just
        # added: flush boards do not get a line between them.
        fresh = grp.entities.grep(Sketchup::Face).reject { |f| had[f.object_id] }
        soften_flush_seams!(fresh)
        # WHAT THE BOARD IS PAINTED (2026-08-25). 'boxed' is a painted board
        # and keeps taking the fascia colour off the fallback below, exactly
        # as it did - soffit_color returns nil for it and nothing here runs.
        # 'wood' and 'stucco' are the same board with a different finish, so
        # they carry their own colour.
        paint = soffit_paint(model, s)
        if paint
          fresh.each { |f| paint_soffit_face!(f, paint[:mat], paint[:size]) }
        end
      end
      # Real gable walls (2026-08-08): the wall itself rises into the
      # triangle - wall-thick prisms at the WALL line (overhang back from
      # the roof edge), painted with each wall's own sides. They live in
      # this group, so every roof rebuild replaces them. Kill switch:
      #   InteriorPro::RoofManager.build_roof!(gable_walls: false)
      if s[:gable_walls] && zmap && !gables.empty?
        build_gable_wall_tops!(grp, poly, gables, wall_ids, zmap, z0,
                               s[:overhang], framed, band_top, slope)
      end
      grp.entities.grep(Sketchup::Face).each do |f|
        next if f.material
        f.material = trim_mat
        f.back_material = trim_mat
      end

      grp.set_attribute('InteriorPro', 'type', 'roof')
      grp.set_attribute('InteriorPro', 'id',
                        format('roof-%s-%04d', Time.now.to_i.to_s(36), rand(10_000)))
      grp.set_attribute('InteriorPro', 'roof_style', s[:style])
      grp.set_attribute('InteriorPro', 'roof_material', s[:roof_material])
      grp.set_attribute('InteriorPro', 'level', lvl)
      grp.set_attribute('InteriorPro', 'pitch', s[:pitch])
      grp.set_attribute('InteriorPro', 'overhang_in', s[:overhang])
      grp.set_attribute('InteriorPro', 'thickness_in', 0.0)
      grp.set_attribute('InteriorPro', 'fascia', s[:fascia])
      grp.set_attribute('InteriorPro', 'soffit', s[:soffit])
      grp.set_attribute('InteriorPro', 'drip_edge', s[:drip])
      grp.set_attribute('InteriorPro', 'gable_edges', gables) unless gables.empty?
      grp.set_attribute('InteriorPro', 'eave_z', z0)
      grp.set_attribute('InteriorPro', 'ridge_z', ridge)
      grp.set_attribute('InteriorPro', 'footprint_xy', poly.flatten)
      grp.set_attribute('InteriorPro', 'created_at', Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
      grp.set_attribute('InteriorPro', 'plugin_version', '0.1')
      model.commit_operation
      puts format('[Roof] %s over level %d: eave %.1f", ridge %.1f" (pitch %s:12, overhang %.0f", fascia %s, drip %s)',
                  s[:style], lvl, z0, ridge, s[:pitch], s[:overhang],
                  s[:fascia] ? 'on' : 'off', s[:drip] ? 'on' : 'off')
      grp
    rescue StandardError => e
      model.abort_operation rescue nil
      puts "[Roof] build_roof! failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      nil
    end

    def self.paint!(f, mat)
      f.material = mat
      f.back_material = mat
      f
    end

    # A roof surface face: roof color on the TOP side, trim (white) on the
    # underside. add_face may come out facing down — flip it first.
    def self.paint_surface!(f, top_mat, under_mat)
      f.reverse! if f.respond_to?(:reverse!) && f.normal.z < 0
      f.material = top_mat
      f.back_material = under_mat
      f
    end

    # ONE sloped surface face per cell — zero thickness. Roof color on
    # top, trim (white) underneath.
    #
    # Heel rule (2026-08-05, "the roof must not cut into the ceiling"):
    # the surface is shifted by delta = -slope*overhang, so it meets the
    # wall top exactly at the wall's OUTER face and only rises from there
    # inward — inside the house it is always at or above the ceiling
    # plane. The dip below z0 remains only out in the overhang.
    # Returns the ridge (max) z, or nil.
    def self.build_hip_geometry!(grp, poly, cells, z0, slope, overhang,
                                 roof_mat, under_mat)
      n = poly.length
      delta = -slope * overhang.to_f
      lines = Array.new(n) do |i|
        p = poly[i]
        d = vnorm(vsub(poly[(i + 1) % n], poly[i]))
        { p: p, n: [-d[1], d[0]] }
      end
      lift = lambda do |pt, ei|
        d = vdot(lines[ei][:n], vsub(pt, lines[ei][:p]))
        d = 0.0 if d < 0.0
        z0 + delta + slope * d
      end
      ridge = z0
      # node [x,y] (rounded) -> HIGHEST surface z there. A strip-junction
      # node (a gable on part of a long wall) legitimately carries TWO
      # heights; the gable faces and rake boards follow the high profile
      # (2026-08-05: keeping only the last-written z made the strip-gable
      # chain degenerate to 2 eave points, so no triangle was built).
      zmap = {}
      # xy segment -> the 3D z-profile every cell puts on it, to close
      # vertical tears between roof sections that meet at different heights
      edge_zs = Hash.new { |h, k| h[k] = [] }
      cells.each do |cell|
        top = cell[:pts].map do |p|
          z = lift.call(p, cell[:eave])
          ridge = z if z > ridge
          key = [p[0].round(4), p[1].round(4)]
          zmap[key] = z if zmap[key].nil? || z > zmap[key]
          Geom::Point3d.new(p[0], p[1], z)
        end
        top.each_index do |i2|
          pa = top[i2]
          pb = top[(i2 + 1) % top.length]
          ka = [pa.x.round(4), pa.y.round(4)]
          kb = [pb.x.round(4), pb.y.round(4)]
          next if ka == kb
          if (ka <=> kb) <= 0
            edge_zs[[ka, kb]] << [pa.z, pb.z]
          else
            edge_zs[[kb, ka]] << [pb.z, pa.z]
          end
        end
        paint_surface!(grp.entities.add_face(top), roof_mat, under_mat)
      end
      # Vertical tear faces (2026-08-05): where a gable strip meets the
      # rest of its wall, two roof sections share an xy segment at
      # DIFFERENT heights. Without a closing face the roof shows white
      # triangular holes and "floating" edges. Painted trim white by the
      # catch-all pass in build_roof!.
      edge_zs.each do |(ka, kb), profiles|
        next if profiles.length < 2
        profiles.combination(2).each do |(za1, zb1), (za2, zb2)|
          next if (za1 - za2).abs < 0.01 && (zb1 - zb2).abs < 0.01
          pts = []
          [[ka, za1], [kb, zb1], [kb, zb2], [ka, za2]].each do |(k, z)|
            pt = Geom::Point3d.new(k[0], k[1], z)
            dup = pts.any? do |q|
              (q.x - pt.x).abs < 0.001 && (q.y - pt.y).abs < 0.001 &&
                (q.z - pt.z).abs < 0.001
            end
            pts << pt unless dup
          end
          grp.entities.add_face(pts) if pts.length >= 3
        end
      end
      [ridge, zmap]
    rescue StandardError => e
      puts "[Roof] build_hip_geometry!: #{e.message}"
      nil
    end

    # How far to lift the top shell so the slab is `thickness` thick
    # MEASURED PERPENDICULAR to the roof plane. A vertical lift of dz on a
    # plane of this slope gives a perpendicular thickness of dz*cos(angle),
    # so dz = t / cos = t * sqrt(1 + slope^2). Pure maths, tested.
    def self.slab_lift(thickness, slope)
      t = thickness.to_f
      return 0.0 if t <= 0.0
      t * Math.sqrt(1.0 + slope.to_f * slope.to_f)
    end

    # The slab's visible EDGE: a vertical ribbon along every footprint
    # edge, from the underside profile up to the top shell. Without it the
    # roof would be two sheets with a gap between them.
    # zmap nil (flat roof) -> a plain band at z_flat.
    def self.build_slab_edge!(grp, poly, zmap, dz, z_flat, mat)
      return if dz <= 0.001
      n = poly.length
      n.times do |i|
        j = (i + 1) % n
        chain = zmap ? edge_profile_chain(poly, i, zmap) : nil
        segs = if chain && chain.length >= 2
                 chain.each_cons(2).map { |(_t1, p1, z1), (_t2, p2, z2)| [p1, z1, p2, z2] }
               else
                 [[poly[i], z_flat, poly[j], z_flat]]
               end
        segs.each do |p1, z1, p2, z2|
          next if vlen(vsub(p2, p1)) < 1.0e-6
          pts = [Geom::Point3d.new(p1[0], p1[1], z1),
                 Geom::Point3d.new(p2[0], p2[1], z2),
                 Geom::Point3d.new(p2[0], p2[1], z2 + dz),
                 Geom::Point3d.new(p1[0], p1[1], z1 + dz)]
          f = grp.entities.add_face(pts)
          next if f.nil?
          f.material = mat
          f.back_material = mat
        end
      end
    rescue StandardError => e
      puts "[Roof] build_slab_edge!: #{e.message}"
    end

    # ---------- ridge cap ----------
    # Cap shingles bent over the ridge and down every hip. Real caps are
    # SEPARATE pieces, each one lapping the tail of the one before it, and
    # they sit ON the roof - the first attempt (2026-08-10) drew one long
    # tent whose skirts were sunk into the planes, so it read as a rail,
    # not as roofing.
    RIDGE_CAP_WIDTH    = 12.0 unless const_defined?(:RIDGE_CAP_WIDTH, false)
    RIDGE_CAP_THICK    = 0.45 unless const_defined?(:RIDGE_CAP_THICK, false)
    RIDGE_CAP_EXPOSURE = 12.0 unless const_defined?(:RIDGE_CAP_EXPOSURE, false)
    RIDGE_CAP_LENGTH   = 15.0 unless const_defined?(:RIDGE_CAP_LENGTH, false)
    # A real cap is ARCHED over the ridge, not creased like a tent
    # (user 2026-08-10, photos). CROWN is how high the middle of the arch
    # lifts off the crease; SEGMENTS is how many facets per side draw it.
    RIDGE_CAP_CROWN    = 1.0 unless const_defined?(:RIDGE_CAP_CROWN, false)
    RIDGE_CAP_SEGMENTS = 2   unless const_defined?(:RIDGE_CAP_SEGMENTS, false)
    # A free end is CUT FLUSH with the roof edge - hanging it over left
    # a cap floating in the air off the corner (user 2026-08-10).
    RIDGE_CAP_OVERSHOOT = 0.0 unless const_defined?(:RIDGE_CAP_OVERSHOOT, false)
    # At a junction one run passes OVER and the others stop short and
    # tuck under it, the way a ridge cap covers the tops of the hips.
    RIDGE_CAP_TUCK = 2.0 unless const_defined?(:RIDGE_CAP_TUCK, false)
    # At the bottom of a hip the roof narrows to a point, so a full-width
    # cap there hangs off the corner in mid-air (user 2026-08-10). The
    # last stretch is trimmed to a point instead, the way a roofer cuts it.
    RIDGE_CAP_END_TAPER = 9.0 unless const_defined?(:RIDGE_CAP_END_TAPER, false)
    # Above this many pieces the caps collapse into one continuous run.
    # A 200ft roof of 10" pieces is ~250 solids; a whole estate is not.
    MAX_RIDGE_CAP_PIECES = 1500 unless const_defined?(:MAX_RIDGE_CAP_PIECES, false)

    def self.face_points(f)
      return f.pts if f.respond_to?(:pts) && f.pts
      return f.vertices.map(&:position) if f.respond_to?(:vertices)
      nil
    rescue StandardError
      nil
    end

    # The uphill/downhill gradient of a roof face: dz per inch of travel
    # in xy. For a plane with upward normal n it is (-nx/nz, -ny/nz).
    def self.face_gradient(f)
      n = f.respond_to?(:normal) ? f.normal : nil
      return nil if n.nil?
      nz = n.z
      return nil if nz.abs < 0.2 # vertical: a tear face or the slab edge
      sgn = nz.negative? ? -1.0 : 1.0
      [-(n.x * sgn) / (nz * sgn), -(n.y * sgn) / (nz * sgn)]
    rescue StandardError
      nil
    end

    # WHICH SIDE of a shared edge a face actually lies on (2026-08-12B).
    #
    # The obvious answer - compare the face's CENTRE of gravity with the middle
    # of the edge - is wrong for the long L-shaped cells a hip roof grows over a
    # wing: the centre can sit past the edge's own line, the face is filed on
    # the wrong side, and a perfectly good ridge is thrown away as "both planes
    # on one side". That is exactly what left the user's wing ridge bare.
    #
    # Instead step a whisker off the middle of the edge, once each way, and ask
    # the face's own outline which step landed inside it. nil when neither or
    # both do (a face folded back on itself) - the caller then falls back to the
    # old centre-of-gravity guess.
    def self.face_side_of_edge(flat, mid, u, eps = 0.25)
      return nil if flat.nil? || flat.length < 3
      plus  = point_in_poly?(flat, mid[0] + u[0] * eps, mid[1] + u[1] * eps)
      minus = point_in_poly?(flat, mid[0] - u[0] * eps, mid[1] - u[1] * eps)
      return 1.0 if plus && !minus
      return -1.0 if minus && !plus
      nil
    end

    # Ridge AND hip lines, read straight off the faces that were built so
    # this works for every style without repeating the roof maths.
    #
    # An xy segment shared by two roof planes is a ridge/hip when the
    # surface DESCENDS as you walk off it into either plane, and a valley
    # when it climbs. The first version compared face centroid heights,
    # which is true for a hip END but exactly borderline for the long
    # slope beside it - so every hip on a real roof was skipped
    # (user 2026-08-10). Gradients decide it properly.
    #
    # Returns [ka, za, kb, zb, sides] where sides is one
    # [side(+1/-1), dz-per-inch walking into that face] per plane.
    # With valleys: true it returns the VALLEYS instead - the same walk, the
    # same sides, only the last filter flipped: a ridge falls away on both
    # sides, a valley climbs on both. Added 2026-08-21 for the metal roof's
    # valley cover; the default is exactly the method it always was.
    def self.ridge_lines(faces, tol = 0.05, valleys: false)
      edges = Hash.new { |h, k| h[k] = [] }
      faces.each do |f|
        pts = face_points(f)
        next if pts.nil? || pts.length < 3
        grad = face_gradient(f)
        next if grad.nil?
        cen = [pts.map(&:x).inject(:+) / pts.length.to_f,
               pts.map(&:y).inject(:+) / pts.length.to_f]
        pts.each_index do |i|
          a = pts[i]
          b = pts[(i + 1) % pts.length]
          ka = [a.x.round(3), a.y.round(3)]
          kb = [b.x.round(3), b.y.round(3)]
          next if ka == kb
          flat = pts.map { |q| [q.x.to_f, q.y.to_f] }
          if (ka <=> kb) <= 0
            edges[[ka, kb]] << [a.z, b.z, grad, cen, flat]
          else
            edges[[kb, ka]] << [b.z, a.z, grad, cen, flat]
          end
        end
      end
      out = []
      edges.each do |(ka, kb), recs|
        next if recs.length < 2
        za = recs[0][0]
        zb = recs[0][1]
        next unless recs.all? { |r| (r[0] - za).abs < tol && (r[1] - zb).abs < tol }
        seg = vsub(kb, ka)
        next if vlen(seg) < 1.0e-6
        d = vnorm(seg)
        u = [-d[1], d[0]]
        mid = [(ka[0] + kb[0]) / 2.0, (ka[1] + kb[1]) / 2.0]
        sides = recs.map do |(_za, _zb, grad, cen, flat)|
          s = face_side_of_edge(flat, mid, u)
          s ||= vdot(u, vsub(cen, mid)) >= 0.0 ? 1.0 : -1.0
          [s, (grad[0] * u[0] + grad[1] * u[1]) * s]
        end
        if valleys
          next unless sides.all? { |(_s, dz)| dz > 1.0e-6 }  # both sides climb
        else
          next unless sides.all? { |(_s, dz)| dz < -1.0e-6 } # a valley climbs
        end
        next unless sides.map(&:first).uniq.length >= 2    # one plane each side
        out << [ka, za, kb, zb, sides.uniq { |(s, _dz)| s }]
      end
      out
    end

    # Eave corners that are NOT real corners: the joins between two facets of
    # ONE curved wall. Edge i and edge i+1 carry the same wall id there, so the
    # vertex between them (poly[i + 1]) is a seam in the faceting, not a place
    # where two walls meet.
    def self.facet_hip_points(poly, wall_ids)
      return [] unless poly && wall_ids
      n = poly.length
      out = []
      n.times do |i|
        j = (i + 1) % n
        next if wall_ids[i].nil?
        out << poly[j] if wall_ids[i] == wall_ids[j]
      end
      out
    end

    # Every eave corner where a CURVED wall meets a different wall.
    #
    # The rule the user set, in his own words (2026-08-12B): "a cap on all the
    # ridges and on the descending diagonals, EXCEPT on the round part". So a
    # hip that lands anywhere the curve touches gets no cap, whatever angle the
    # two walls meet at. Two earlier tries measured that angle - first a flat 30
    # degrees, then half the curve's own facet turn - and both were wrong on his
    # house: his arcs run into their neighbours at 39.6 and 22.9 degrees, real
    # corners by any measure, and he still wants them bare. The round part is
    # read as one smooth surface, and a cap anywhere on it is a scar.
    #
    # A corner between two STRAIGHT walls is never returned here, so a plain
    # roof keeps every cap it ever had.
    def self.soft_hip_points(poly, wall_ids, _unused = nil)
      return [] unless poly && wall_ids
      n = poly.length
      return [] if n < 3
      faceted = wall_ids.compact.tally.select { |_id, c| c > 1 }.keys
      return [] if faceted.empty?
      out = []
      n.times do |i|
        j = (i + 1) % n
        next if wall_ids[i].nil? || wall_ids[j].nil?
        next if wall_ids[i] == wall_ids[j]                       # a facet seam
        next unless faceted.include?(wall_ids[i]) || faceted.include?(wall_ids[j])
        out << poly[j]
      end
      out
    end

    # Drop the ridge lines that are only there because a curve was faceted.
    #
    # A curved wall reaches the roof as a run of short straight pieces, and the
    # straight skeleton dutifully raises a hip between every neighbouring pair
    # - a fan of rays across what is really ONE smooth surface (user, seeing
    # the first curved hip roof: "on the round part I do not need all these
    # ridge caps, only where it joins the other roof"). Those rays are an
    # artefact of the faceting, so they get no cap. Since 2026-08-12B the
    # TANGENTIAL join at each end of the curve loses its cap too - see
    # soft_hip_points. Every hip between two walls that really do turn, and
    # every real ridge, is untouched.
    def self.drop_facet_hips(lines, poly, wall_ids, tol = 0.25)
      pts = facet_hip_points(poly, wall_ids) + soft_hip_points(poly, wall_ids)
      return lines if pts.empty?
      lines.reject do |line|
        ka = line[0]
        kb = line[2]
        pts.any? { |p| vlen(vsub(ka, p)) < tol || vlen(vsub(kb, p)) < tol }
      end
    end

    # ---------- ONE place that names the four kinds of roof edge ----------
    #
    # (2026-08-19, ROOF_TILES_PROPOSAL.md §3 - step 3 of the hybrid tile roof.)
    #
    # Every classifier used below ALREADY EXISTS and is already in production.
    # This is a thin WRAPPER over them, never a second opinion. A second
    # classifier that disagrees with the first is exactly the trap that cost
    # the window a whole round on 2026-08-19: two answers, and no way to tell
    # which one the geometry actually followed.
    #
    #   faces     the TOP shell only - build_roof! already reads it once into
    #             `top_shell`, and the ridge caps use that same list
    #   poly      the eave polygon, [[x, y], ...]; edge i runs poly[i]->poly[i+1]
    #   wall_ids  one wall id per poly edge (may be nil)
    #   zmap      node [x, y] -> z, from build_hip_/build_framed_geometry!
    #
    # opts:
    #   gables:    indices of the poly edges carrying a gable end
    #   band_top:  the roof surface height AT the eave - the line a rake rises
    #              above. The same number build_band! is handed.
    #   surface:   optional lambda(x, y) -> z for over-framed plans, passed
    #              straight through to edge_profile_chain
    #   ridge_tol: level-vs-sloped cut-off, inches
    #
    # Returns { eave: [...], rake: [...], ridge: [...], hip: [...] }; each entry
    #
    #   { kind: :eave, a: [x, y, z], b: [x, y, z], edge: i, wall_id: id }
    #
    # running a -> b, in inches, in the same world space as `poly`. ridge and
    # hip entries carry no :edge - they are not poly edges.
    #
    # The ONE new decision in this method is ridge vs hip, and it is a single
    # line: a level segment is a ridge, a sloped one is a hip (proposal §3).
    # A gabled edge is split exactly the way the fascia is already split - the
    # stretch that rises above band_top is the rake, the rest of the SAME edge
    # stays a plain eave (2026-08-09, build_band! + gable_spans).
    # Kill switch (CLAUDE.md convention): turn the 3D eave course off and the
    # roof goes back to texture-only, without deleting a line.
    # OFF since 2026-08-20: the user saw the eave course and rejected it.
    # The whole silhouette-only idea is being replaced by long half-pipe runs
    # (his own Roman-tile reference), so this stays off until that lands.
    # Nothing was deleted - flip it back to true to see the old course again.
    USE_ROOF_TILE_EDGES = false unless const_defined?(:USE_ROOF_TILE_EDGES, false)
    # The replacement, 2026-08-20: long half-pipe runs, ridge to eave, on the
    # ROUND materials only (barrel and roman). Off with
    # InteriorPro::RoofManager::USE_ROOF_TILE_RUNS = false.
    USE_ROOF_TILE_RUNS = true unless const_defined?(:USE_ROOF_TILE_RUNS, false)
    RIDGE_LEVEL_TOL = 1.0 unless const_defined?(:RIDGE_LEVEL_TOL, false)
    ROOF_EDGE_MIN_LEN = 0.5 unless const_defined?(:ROOF_EDGE_MIN_LEN, false)

    def self.roof_edges(faces, poly, wall_ids, zmap, opts = {})
      out = { eave: [], rake: [], ridge: [], hip: [] }
      return out if poly.nil? || poly.length < 3

      tol = (opts[:ridge_tol] || RIDGE_LEVEL_TOL).to_f
      drop_facet_hips(ridge_lines(faces || []), poly, wall_ids).each do |line|
        ka, za, kb, zb, = line
        kind = (za - zb).abs < tol ? :ridge : :hip
        out[kind] << { kind: kind, a: [ka[0], ka[1], za], b: [kb[0], kb[1], zb] }
      end

      gables   = opts[:gables] || []
      band_top = opts[:band_top]
      surface  = opts[:surface]
      n = poly.length
      n.times do |i|
        a = poly[i]
        b = poly[(i + 1) % n]
        seg = vsub(b, a)
        len = vlen(seg)
        next if len < ROOF_EDGE_MIN_LEN
        d = vnorm(seg)
        chain = nil
        if zmap && !zmap.empty?
          begin
            chain = edge_profile_chain(poly, i, zmap, surface: surface)
          rescue StandardError => e
            puts "[Roof] roof_edges: edge #{i} profile: #{e.message}"
            chain = nil
          end
        end
        rakes = []
        if gables.include?(i) && chain && band_top
          rakes = chain_regions_above(chain, band_top)
                  .map { |rg| [[rg.first[0], 0.0].max, [rg.last[0], len].min] }
                  .select { |(t0, t1)| t1 - t0 > ROOF_EDGE_MIN_LEN }
                  .sort_by(&:first)
        end
        add = lambda do |t0, t1, kind|
          out[kind] << { kind: kind, edge: i,
                         wall_id: wall_ids && wall_ids[i],
                         a: [a[0] + d[0] * t0, a[1] + d[1] * t0,
                             chain_z_at(chain, t0, band_top)],
                         b: [a[0] + d[0] * t1, a[1] + d[1] * t1,
                             chain_z_at(chain, t1, band_top)] }
        end
        rakes.each { |(t0, t1)| add.call(t0, t1, :rake) }
        cursor = 0.0
        rakes.each do |(t0, t1)|
          add.call(cursor, t0, :eave) if t0 - cursor > ROOF_EDGE_MIN_LEN
          cursor = t1 if t1 > cursor
        end
        add.call(cursor, len, :eave) if len - cursor > ROOF_EDGE_MIN_LEN
      end
      out
    end

    # z along an edge_profile_chain at distance t, linearly interpolated.
    # `dflt` is what a flat roof gets, where there is no zmap to read.
    def self.chain_z_at(chain, t, dflt = nil)
      return dflt if chain.nil? || chain.empty?
      return chain.first[2] if t <= chain.first[0]
      return chain.last[2] if t >= chain.last[0]
      j = chain.index { |c| c[0] >= t }
      return chain.last[2] if j.nil? || j.zero?
      t0, _, z0 = chain[j - 1]
      t1, _, z1 = chain[j]
      t1 - t0 < 1.0e-6 ? z1 : z0 + (z1 - z0) * (t - t0) / (t1 - t0)
    end

    # Lay the caps along one line as pieces that LAP each other. Each
    # piece is a bent plate: its tail lies on the two planes and its head
    # is lifted one thickness, so it rides on the tail of the piece before
    # it instead of sitting beside it (user 2026-08-10 - laid flat they
    # read as tiles in a row, not as roofing).
    #
    # Two more things the first version got wrong:
    #  - at a Y junction the runs stopped dead and left a notch, so a line
    #    whose end meets another line is extended half a cap past it and
    #    the three runs pile over each other the way a real cap does.
    #  - the last piece was cut off wherever the line ended, leaving a
    #    stub. Now the final piece is pulled BACK so it ends flush.
    # Where each piece begins, measured from the LOW end of the run. The
    # spacing is ALWAYS one exposure - the earlier version pulled the last
    # piece back to end flush, which broke the uniform lap and made that
    # piece cut into its neighbour. Now the last piece is simply CUT at
    # the end of the run (user 2026-08-10).
    def self.cap_starts(total, plen, expo)
      return [0.0] if total <= plen + 0.01
      out = []
      r = 0.0
      while r < total - 0.5
        out << r
        r += expo
      end
      out
    end

    # Endpoints where two or more ridge lines meet (a Y at the top of a
    # hip). Those ends get run past; an end that touches nothing is an
    # eave and must stop clean.
    def self.ridge_junctions(lines)
      seen = Hash.new(0)
      lines.each do |ka, _za, kb, _zb, _s|
        seen[[ka[0].round(2), ka[1].round(2)]] += 1
        seen[[kb[0].round(2), kb[1].round(2)]] += 1
      end
      seen.select { |_k, v| v > 1 }.keys
    end

    def self.junction?(js, p)
      js.include?([p[0].round(2), p[1].round(2)])
    end

    # At a junction ONE run passes over and the rest tuck under it, so the
    # corner reads as a cap wrapping the top instead of three arches piled
    # on each other (user 2026-08-10). The runner is the flattest line
    # there - on a hip roof that is the ridge, which is what really covers
    # the hip tops; on a pyramid apex, where nothing is flat, the longest
    # hip takes the job. Returns junction key -> index of the winning line.
    def self.junction_runners(lines, js)
      out = {}
      js.each do |k|
        best = nil
        lines.each_with_index do |(ka, za, kb, zb, _s), i|
          next unless junction?([k], ka) || junction?([k], kb)
          rank = [(za - zb).abs.round(2), -vlen(vsub(kb, ka))]
          best = [rank, i] if best.nil? || (rank <=> best[0]) < 0
        end
        out[k] = best[1] if best
      end
      out
    end

    # How high a piece rides on the one below it. For consecutive pieces
    # to meet EXACTLY - no gap, no biting in - the lift must be
    # thickness * length / exposure, not the thickness itself: both
    # undersides then fall at the same rate, so the upper one lies right
    # on the lower one's back the whole way along the lap. With a plain
    # thickness they crossed by 0.11" (user measured it, 2026-08-10).
    def self.cap_head_lift
      RIDGE_CAP_THICK * RIDGE_CAP_LENGTH / RIDGE_CAP_EXPOSURE
    end

    # The face-level half of the buried-plane rule (see build_roof!): a face
    # whose own middle sits in PLAN inside another shell face's outline while
    # that face passes ABOVE it there is not roof anyone can see - it is the
    # continuation of one wing's plane under another wing's roof. It is
    # erased, and the survivors are returned so everything downstream (cap
    # lines, tiles, edges) never hears about it. RoofTilePlace has the same
    # test for the planes it is handed directly, so both doors are closed.
    # Where a face is only PARTLY buried - the gable junction, which makes
    # no valley and so splits nothing - the intersection line of the two
    # PLANES is drawn onto the shell first. SketchUp splits both faces along
    # it, the buried half becomes its own face, and the erase pass below
    # takes it like any other buried face. "זה עדיין קיים בגייבל" was this
    # exact face: tiles clipped, deck tongue still there.
    def self.buried_split_segments(ci, qi)
      return [] unless defined?(InteriorPro::RoofTilePlace)
      np = ci[:n]
      nq = qi[:n]
      dv = [(np[1] * nq[2]) - (np[2] * nq[1]),
            (np[2] * nq[0]) - (np[0] * nq[2]),
            (np[0] * nq[1]) - (np[1] * nq[0])]
      dl = Math.sqrt((dv[0]**2) + (dv[1]**2) + (dv[2]**2))
      return [] if dl < 1.0e-6
      dv = dv.map { |x| x / dl }
      return [] if Math.hypot(dv[0], dv[1]) < 1.0e-6
      p0 = ci[:p0]
      q0 = qi[:p0]
      l0 = InteriorPro::RoofTilePlace.solve3(
        np, (np[0] * p0[0]) + (np[1] * p0[1]) + (np[2] * p0[2]),
        nq, (nq[0] * q0[0]) + (nq[1] * q0[1]) + (nq[2] * q0[2]),
        dv, (dv[0] * p0[0]) + (dv[1] * p0[1]) + (dv[2] * p0[2])
      )
      return [] if l0.nil?
      # every place the line's PLAN path crosses either outline, then keep
      # the stretches whose middle is inside BOTH - that is exactly where
      # the junction lives on the roof.
      ts = [-10_000.0, 10_000.0]
      [ci[:plan], qi[:plan]].each do |poly|
        n = poly.length
        n.times do |i2|
          ax, ay = poly[i2]
          bx, by = poly[(i2 + 1) % n]
          ex = bx - ax
          ey = by - ay
          den = (dv[0] * ey) - (dv[1] * ex)
          next if den.abs < 1.0e-9
          s = (((ax - l0[0]) * ey) - ((ay - l0[1]) * ex)) / den
          u2 = (((ax - l0[0]) * dv[1]) - ((ay - l0[1]) * dv[0])) / den
          ts << s if u2 >= -1.0e-6 && u2 <= 1.0 + 1.0e-6
        end
      end
      out = []
      ts.sort.each_cons(2) do |t1, t2|
        next if (t2 - t1) < 1.0
        tm = (t1 + t2) / 2.0
        m = [l0[0] + (dv[0] * tm), l0[1] + (dv[1] * tm)]
        next unless InteriorPro::RoofTileMath.poly_contains?(ci[:plan], m)
        next unless InteriorPro::RoofTileMath.poly_contains?(qi[:plan], m)
        out << [[l0[0] + (dv[0] * t1), l0[1] + (dv[1] * t1), l0[2] + (dv[2] * t1)],
                [l0[0] + (dv[0] * t2), l0[1] + (dv[1] * t2), l0[2] + (dv[2] * t2)]]
      end
      out
    end

    def self.face_cover_info(f)
      pts = if f.respond_to?(:vertices)
              f.vertices.map(&:position)
            elsif f.respond_to?(:points)
              f.points
            else
              f.pts
            end
      pts = pts.map { |p| [p.x.to_f, p.y.to_f, p.z.to_f] }
      n = f.normal
      { plan: pts.map { |p| [p[0], p[1]] },
        cx: pts.sum { |p| p[0] } / pts.length,
        cy: pts.sum { |p| p[1] } / pts.length,
        cz: pts.sum { |p| p[2] } / pts.length,
        p0: pts[0], n: [n.x.to_f, n.y.to_f, n.z.to_f] }
    rescue StandardError
      nil
    end

    # THE SLAB HAS TWO SKINS, AND ONLY THE TOP ONE IS TESTED (2026-08-23).
    # Erasing the top face of a buried tongue leaves its UNDERSIDE hanging
    # there, and through an open gable that underside IS the deck the user
    # kept seeing - "זה עדיין קיים בגייבל". The knife was never the problem:
    # measured in his own model, the buried top face was already gone and the
    # bottom one, f2, was the only face in the group with no twin.
    #
    # The underside CANNOT be run through the cover test above. Every
    # underside face is covered by its own top skin half an inch higher, so
    # the test calls the whole ceiling buried - measured the same day, it
    # flagged all seven. So nothing new is decided here: an underside face is
    # erased only because the face directly ABOVE it was already erased.
    # Matched in plan (same centre within an inch), same plane direction, and
    # strictly lower - a slab edge sharing a centre with its own top face has
    # the opposite normal and is left alone.
    #
    # Known gap: where the knife SPLITS a top face, the erased half has no
    # matching whole underside face and this pass finds nothing. His roofs
    # erase the tongue whole, so that case is still open.
    def self.drop_buried_twins!(gone_info, under, doomed_edges = nil)
      return 0 if under.nil?
      gone = (gone_info || []).compact
      return 0 if gone.empty?
      hit = 0
      Array(under).each do |f|
        next if f.respond_to?(:valid?) && !f.valid?
        ui = face_cover_info(f)
        next if ui.nil?
        next unless gone.any? do |gi|
          (gi[:cx] - ui[:cx]).abs < 1.0 &&
            (gi[:cy] - ui[:cy]).abs < 1.0 &&
            (gi[:n][2] - ui[:n][2]).abs < 0.01 &&
            ui[:cz] < gi[:cz] - 0.05
        end
        doomed_edges.concat(f.edges) if doomed_edges && f.respond_to?(:edges)
        begin
          f.erase!
          hit += 1
        rescue StandardError
          nil
        end
      end
      hit
    end

    def self.drop_buried_faces!(faces, ents = nil, under = nil)
      list = (faces || []).select do |f|
        !f.respond_to?(:valid?) || f.valid?
      end
      return list if list.length < 2
      info = list.map { |f| face_cover_info(f) }
      # FIRST, THE KNIFE (gable pass): draw the planes' intersection lines
      # onto the shell wherever two of these faces overlap in plan. SketchUp
      # splits the faces along them, a partly-buried tongue becomes a whole
      # buried face, and the erase pass below takes it. In the pure test
      # stub add_line splits nothing, so this is exercised in SketchUp and
      # the segment MATHS is what rt83 pins.
      if ents && ents.respond_to?(:add_line)
        added = []
        list.each_index do |i|
          ((i + 1)...list.length).each do |j|
            ci = info[i]
            qi = info[j]
            next if ci.nil? || qi.nil?
            next if ci[:n][2].abs < 0.2 || qi[:n][2].abs < 0.2
            buried_split_segments(ci, qi).each do |(w1, w2)|
              e = ents.add_line(Geom::Point3d.new(w1[0], w1[1], w1[2]),
                                Geom::Point3d.new(w2[0], w2[1], w2[2]))
              added << e unless e.nil?
            rescue StandardError
              nil
            end
          end
        end
        added.each do |e|
          next unless e.respond_to?(:faces)
          e.faces.each do |f|
            next unless f.respond_to?(:normal) && f.normal.z > 0.2
            list << f unless list.include?(f)
          end
        end
        list = list.select { |f| !f.respond_to?(:valid?) || f.valid? }
        info = list.map { |f| face_cover_info(f) }
      end
      buried = []
      buried_info = []
      list.each_index do |i|
        ci = info[i]
        next if ci.nil?
        # SAMPLED, NOT JUST THE CENTRE - same reason as the twin test in
        # RoofTilePlace.drop_covered_planes: two crossing planes can both
        # have their centres in each other's buried lobe, and erasing both
        # leaves a bare roof. Erased only when there is no daylight at the
        # centre NOR at the midpoint toward any corner.
        samples = [[ci[:cx], ci[:cy], ci[:cz]]] + ci[:plan].each_index.map do |k|
          [(ci[:cx] + ci[:plan][k][0]) / 2.0,
           (ci[:cy] + ci[:plan][k][1]) / 2.0, nil]
        end
        cover = samples.all? do |(sx, sy, sz0)|
          # a midpoint's own height on THIS plane
          sz = sz0 || (ci[:p0][2] -
               (((ci[:n][0] * (sx - ci[:p0][0])) +
                 (ci[:n][1] * (sy - ci[:p0][1]))) / ci[:n][2]))
          list.each_index.any? do |j|
            next false if j == i
            qi = info[j]
            # only a real roof plane can bury one - not a slab edge
            next false if qi.nil? || qi[:n][2].abs < 0.2
            next false unless InteriorPro::RoofTileMath.poly_contains?(
              qi[:plan], [sx, sy]
            )
            zq = qi[:p0][2] -
                 (((qi[:n][0] * (sx - qi[:p0][0])) +
                   (qi[:n][1] * (sy - qi[:p0][1]))) / qi[:n][2])
            zq > sz + 0.1
          end
        end
        if cover
          buried << list[i]
          buried_info << ci
        end
      end
      doomed_edges = []
      buried.each do |f|
        doomed_edges.concat(f.edges) if f.respond_to?(:edges)
      end
      buried.each do |f|
        f.erase!
      rescue StandardError
        nil
      end
      drop_buried_twins!(buried_info, under, doomed_edges)
      drop_orphan_edges!(doomed_edges)
      list - buried
    end

    # THE ORPHAN EDGES (2026-08-23, the two thin lines on the main slope).
    # Erasing a face does not erase its edges - each edge stays behind
    # wherever no other face holds it, and SketchUp draws a faceless edge
    # as a bare line, always. Measured in the user's gable model: the two
    # visible lines were two 344" free edges (deck top + underside, 0.5"
    # apart, faces=0) - the rim of the erased tongue along the junction.
    # Hiding the 4 coplanar knife edges did nothing; hiding these two made
    # the lines vanish. Only edges of the faces this pass itself erased are
    # swept, and only those left holding nothing - an edge with a surviving
    # face is a real boundary and is kept.
    def self.drop_orphan_edges!(edges)
      n = 0
      (edges || []).each do |e|
        next if e.respond_to?(:valid?) && !e.valid?
        next unless e.respond_to?(:faces) && e.faces.empty?
        begin
          e.erase!
          n += 1
        rescue StandardError
          nil
        end
      end
      n
    end

    def self.build_ridge_caps!(grp, lines, _slope = nil, mat = nil, shape_name = nil)
      return if lines.nil? || lines.empty?
      total_len = lines.sum { |l| vlen(vsub(l[2], l[0])) }
      # A metal ridge is drawn as one length whatever its size - see
      # cap_continuous_for. Everything else still switches to one run only when
      # the piece count would run away.
      cap_soft = !cap_continuous_for(shape_name)
      one_run = cap_continuous_for(shape_name) ||
                (total_len / RIDGE_CAP_EXPOSURE).ceil > MAX_RIDGE_CAP_PIECES
      if one_run
        puts format('[Roof] ridge cap: %d" of ridge - drawn as one run to stay light',
                    total_len.round)
      end
      js = ridge_junctions(lines)
      runners = junction_runners(lines, js)
      cap_w = cap_width_for(shape_name)
      cap_c = cap_crown_for(shape_name)
      cap_lift = cap_lift_for(shape_name)
      cap_round = cap_round_for(shape_name)
      half = cap_w / 2.0
      lift = cap_head_lift
      # Once, outside the loop - it depends on the material, not on the line.
      cap_flat = defined?(InteriorPro::RoofTileMath) &&
                 InteriorPro::RoofTileMath.respond_to?(:run_flat?) &&
                 InteriorPro::RoofTileMath.run_flat?(shape_name)
      lines.each_with_index do |(ka, za, kb, zb, sides), idx|
        len = vlen(vsub(kb, ka))
        next if len < 1.0
        next if sides.length < 2
        # A VALLEY, NOT A RIDGE (2026-08-21, metal roof only - build_roof!
        # only ever appends valley lines for the seam). Both its planes CLIMB.
        # The user: "צריך משהו שמכסה פה בוואלי... זה לא מכסה זה יותר מוליך
        # מים" - so this is a water CHANNEL, not a raised cap: the same flat
        # folded strip, but lying flat IN the V on the deck itself - no lift,
        # no skirt (nothing under it to hide), no corner mitre at its foot.
        valley = sides.all? { |(_sd, sdz)| sdz > 1.0e-6 }
        d = vnorm(vsub(kb, ka))
        # A valley strip is FLAT whatever the material's cap says. The seam's
        # crown is 0 so it never noticed; the flat tile's cap states 2.622",
        # and an ARCH in the bottom of a V would shed water sideways instead
        # of carrying it.
        prof = cap_profile([-d[1], d[0]], sides, cap_w,
                           valley ? 0.0 : cap_c, valley ? false : cap_round)
        tucked = {}
        adj = lambda do |p|
          k = [p[0].round(2), p[1].round(2)]
          next RIDGE_CAP_OVERSHOOT unless js.include?(k)
          next half if runners[k] == idx
          tucked[k] = true
          -RIDGE_CAP_TUCK
        end
        a0 = -adj.call(ka)
        b0 = len + adj.call(kb)
        span = b0 - a0
        next if span < 1.0
        # A run that tucks under another dips one thickness at that end,
        # so it passes BENEATH the covering run instead of crossing it.
        drop_a = tucked[[ka[0].round(2), ka[1].round(2)]] ? RIDGE_CAP_THICK : 0.0
        drop_b = tucked[[kb[0].round(2), kb[1].round(2)]] ? RIDGE_CAP_THICK : 0.0
        zadj = lambda do |q|
          # The whole cap rides on top of the tiles - see cap_lift_for.
          # A valley channel does not: it lies on the deck and the water
          # runs over it.
          # The flat tile's valley strip floats the same fifth of an inch its
          # cut tiles do, for the same reason: ON the deck it is coplanar
          # with it, SketchUp draws the deck instead, and the "channel" shows
          # as a bare stripe. The seam's stays exactly where it was approved.
          v = valley ? (cap_flat ? 0.2 : 0.0) : cap_lift
          v -= drop_a * [0.0, 1.0 - (q - a0) / RIDGE_CAP_LENGTH].max if drop_a > 0.0
          v -= drop_b * [0.0, 1.0 - (b0 - q) / RIDGE_CAP_LENGTH].max if drop_b > 0.0
          v
        end
        rising = zb >= za
        free_a = !js.include?([ka[0].round(2), ka[1].round(2)])
        free_b = !js.include?([kb[0].round(2), kb[1].round(2)])
        low_free = rising ? free_a : free_b
        # Only the BOTTOM of a slope needs trimming: that is the eave
        # corner, where the two planes pinch out. A level ridge ending at
        # a rake is full width right to the edge, so it is cut square.
        #
        # CLAY ONLY (2026-08-21). The taper pinched the metal hip cap to a
        # point that slid down over the eave corner - "אתה רואה שהוא יורד פה".
        # In the user's reference photo the folded strip stays FULL WIDTH all
        # the way down the hip and is cut square at the gutter line, so the
        # metal cap takes no taper at all. Clay keeps it exactly as it was.
        sloping = (za - zb).abs > 1.0
        # THE FLAT TILE TAKES THE METAL END, NOT THE CLAY ONE (2026-08-21c).
        # cap_soft is true for it - its cap is segmented and softened like
        # clay's - so it inherited the clay taper, and the user photographed
        # the result: the same pencil point sliding out over the eave corner
        # that the metal cap had before its fix. Square width to the line,
        # corner-mitred first piece, and a skirt closing the hollow under it.
        taper_lo = sloping && low_free && cap_soft && !cap_flat ? RIDGE_CAP_END_TAPER : 0.0
        wscale = lambda do |q|
          next 1.0 if taper_lo <= 0.0
          r = rising ? (q - a0) : (b0 - q)
          [[r / taper_lo, 1.0].min, 0.03].max
        end
        plen = one_run ? span : RIDGE_CAP_LENGTH
        starts = one_run ? [0.0] : cap_starts(span, plen, RIDGE_CAP_EXPOSURE)
        # The metal hip cap ends in a CORNER, not a square cut - see the
        # miter_lo comment in build_cap_piece!. Only the piece that actually
        # holds the eave corner (the first one, r runs from the low end), and
        # only on the metal roof - clay keeps its taper and its square ends.
        miter = (!cap_soft || cap_flat) && sloping && low_free && !valley ? 1.0 : 0.0
        starts.each_with_index do |r1, i|
          r2 = [r1 + plen, span].min
          next if r2 - r1 < 0.5
          # r runs from the LOW end of the line, so water always laps the
          # right way whichever way ridge_lines happened to order it.
          q1 = rising ? a0 + r1 : b0 - r1
          q2 = rising ? a0 + r2 : b0 - r2
          h = (one_run || (i.zero? && low_free)) ? 0.0 : lift
          build_cap_piece!(grp, ka, d, za, zb, len, q1, q2, prof, mat,
                           h, plen, zadj, wscale, cap_soft,
                           i.zero? ? miter : 0.0,
                           # the skirt that closes the hollow under a LIFTED
                           # metal cap - see the comment in build_cap_piece!.
                           # The valley channel lies flat on the deck, so it
                           # has no hollow and takes none.
                           # The flat tile's cap is lifted a tile height too,
                           # so it takes the same skirt - the dark slot the
                           # user saw each side of the hip was this hollow.
                           (cap_soft && !cap_flat) || valley ? 0.0 : cap_lift)
        end
      end
    rescue StandardError => e
      puts "[Roof] build_ridge_caps!: #{e.message}"
    end

    # The arch, as offsets from a point on the ridge: outer edge of one
    # plane, up over the crown, down to the outer edge of the other.
    # Each entry is [xy offset, z on the plane there, z added by the arch].
    # The arch is a parabola: nothing at the edges, CROWN in the middle,
    # so the cap lands flush on both planes and still reads as rounded.
    # THE CAP MATCHES ITS OWN TILE (2026-08-21, "תתאים את הרידג' קאפ לכל טייל
    # משלו"). A cap sized off a fixed constant sat on a 7" Spanish fold looking
    # like it came off a different roof. Now it is the tile's own crest, 15%
    # bigger so it laps rather than balances on top, and a material with no 3D
    # tile keeps the constants exactly as they were.
    # THE NUMBERS MOVED (2026-08-21). Both used to be worked out here off the
    # whole tile - run_cover_w * 1.15 and run_height * 1.15. Once Roman became
    # a 14" pan and roll that made a 16" cap sitting on an 8" roll, and it no
    # longer looked like the tile it caps. They now come from RoofTileParts,
    # which sizes the cap off the ROLL and never taller than it, so the cap and
    # the run setback can never disagree about the same number.
    def self.cap_width_for(shape_name)
      return RIDGE_CAP_WIDTH unless defined?(InteriorPro::RoofTileMath) &&
                                    InteriorPro::RoofTileMath.runs?(shape_name)
      s = InteriorPro::RoofTileMath.shape(shape_name)
      w = InteriorPro::RoofTileParts.cap_w(s)
      w > 1.0 ? w : RIDGE_CAP_WIDTH
    rescue StandardError
      RIDGE_CAP_WIDTH
    end

    def self.cap_crown_for(shape_name)
      return RIDGE_CAP_CROWN unless defined?(InteriorPro::RoofTileMath) &&
                                    InteriorPro::RoofTileMath.runs?(shape_name)
      s = InteriorPro::RoofTileMath.shape(shape_name)
      h = InteriorPro::RoofTileParts.cap_crown(s)
      # A stated crown stands as it is - a flat folded metal ridge states 0,
      # and 0 must not be read as "no answer" and replaced by the old arch.
      return h if InteriorPro::RoofTileParts.cap_crown_stated?(s)
      h > 0.25 ? h : RIDGE_CAP_CROWN
    rescue StandardError
      RIDGE_CAP_CROWN
    end

    # HOW HIGH THE CAP RIDES (2026-08-21, "הם נכנסים לתוך הרידג' קאפ").
    #
    # The cap's skirt is drawn ON the roof plane, and a pan-and-roll tile
    # stands 4" proud of it - so every Roman run came straight out through the
    # cap, worst of all on a hip where the skirt has already tapered away to
    # nothing. A real cap is bedded on TOP of the tile ends, so it is lifted by
    # exactly the height of the tile it is capping.
    #
    # ONLY a pan and roll lifts. This briefly lifted Spanish Tile too, by
    # 1.31", which was never asked for - "תחזיר אותו בדיוק למה שהוא היה רק
    # בספניש". Everything that is not Roman is drawn exactly where it was.
    def self.cap_lift_for(shape_name)
      return 0.0 unless defined?(InteriorPro::RoofTileMath) &&
                        InteriorPro::RoofTileMath.runs?(shape_name)
      s = InteriorPro::RoofTileMath.shape(shape_name)
      return 0.0 unless InteriorPro::RoofTileParts.pan_roll?(s)
      [InteriorPro::RoofTileParts.run_top_h(s), 0.0].max
    rescue StandardError
      0.0
    end

    # Does this material's cap take the half-round section? The SHAPE says so
    # in as many words - see RoofTileParts.cap_round?. It used to be inferred
    # from "is it a pan and roll", which quietly caught standing seam the
    # moment that grew a pan of its own; a metal roof does not want a round
    # clay cap. Only Roman says true.
    # ONE CONTINUOUS STRIP, WITH ITS LINES (2026-08-21). A clay cap is a row of
    # short pieces lapping each other, which is how clay is actually laid. A
    # metal ridge is a single folded length of sheet - "הרידג' קאפ לא צריך
    # להיות בחוליות אלא פס אחד רצוף, וגם שיראו את הקווים, אל תעדן את הצורה".
    # So the metal roof takes one piece per ridge line and keeps every edge.
    def self.cap_continuous_for(shape_name)
      return false unless defined?(InteriorPro::RoofTileMath)
      InteriorPro::RoofTileParts
        .seam?(InteriorPro::RoofTileMath.shape(shape_name))
    rescue StandardError
      false
    end

    def self.cap_round_for(shape_name)
      return false unless defined?(InteriorPro::RoofTileMath)
      InteriorPro::RoofTileParts
        .cap_round?(InteriorPro::RoofTileMath.shape(shape_name))
    rescue StandardError
      false
    end

    # How many chords per SIDE of the arch. A METHOD, not a constant, so
    # reload! actually re-reads it - RIDGE_CAP_SEGMENTS is behind a
    # const_defined? guard and needs a full restart to change.
    def self.cap_segments
      6
    end

    # A HALF PIPE, BUT ONLY WHERE IT WAS ASKED FOR (2026-08-21).
    #
    # `round` false is the ORIGINAL cap, unchanged to the last decimal: a
    # parabola, two chords a side, apex pinned to the RIDGE_CAP_CROWN constant.
    # Shingle, plain colour, slate, standing seam and Spanish Tile all come
    # through here and must come out exactly as they always did - the user
    # went looking at Spanish and shingle and thought their caps had been
    # deleted, and a shape he never asked to change is why.
    #
    # `round` true is the new one, asked for on Roman: "תעשה את הצורה חצי
    # צינור". Same curve the tiles use - points spread evenly by ANGLE,
    # x = half * cos(t), z = crown * sin(t) - and the apex takes the crown it
    # was handed instead of the constant, which is what made it read as a
    # folded chevron rather than a pipe.
    def self.cap_profile(u, sides, width = nil, crown = nil, round = false)
      width ||= RIDGE_CAP_WIDTH
      crown ||= RIDGE_CAP_CROWN
      half = width / 2.0
      return cap_profile_flat(u, sides, half, crown) unless round
      seg = [cap_segments, 1].max
      quarter = Math::PI / 2.0
      pt = lambda do |side, th|
        a = half * Math.cos(th)
        [[u[0] * side[0] * a, u[1] * side[0] * a], side[1] * a,
         crown * Math.sin(th)]
      end
      out = (0...seg).map { |i| pt.call(sides[0], quarter * i / seg) }
      out << [[0.0, 0.0], 0.0, crown]
      out + (1..seg).map { |i| pt.call(sides[1], quarter * (seg - i) / seg) }
    end

    # The original arch, moved word for word out of cap_profile so that the
    # half pipe above could be added without touching it.
    def self.cap_profile_flat(u, sides, half, crown)
      seg = [RIDGE_CAP_SEGMENTS, 1].max
      pt = lambda do |side, a|
        k = a / half
        [[u[0] * side[0] * a, u[1] * side[0] * a], side[1] * a,
         crown * (1.0 - k * k)]
      end
      out = (0...seg).map { |i| pt.call(sides[0], half * (seg - i).to_f / seg) }
      # The CREASE honours the stated crown (2026-08-21, second pass). It was
      # the constant, so a stated crown of 0 still bulged one inch in the
      # middle - a bump the user circled in red on the metal ridge, and a hump
      # in the middle of the valley CHANNEL, where water is supposed to run.
      # Clay states nothing, gets crown == RIDGE_CAP_CROWN, and does not move.
      out << [[0.0, 0.0], 0.0, crown]
      out + (1..seg).map { |i| pt.call(sides[1], half * i.to_f / seg) }
    end

    # q1 is the piece's LOW end and q2 its high end (q2 may be closer to
    # the start of the line - that is fine, the maths only cares which is
    # lower). head_lift tapers over the NOMINAL piece length, not over the
    # cut span, so a piece cut short still lines up with its neighbour.
    def self.build_cap_piece!(grp, ka, d, za, zb, len, q1, q2, prof, mat,
                              head_lift = 0.0, plen = nil, zadj = nil,
                              wscale = nil, soft = true, miter_lo = 0.0,
                              skirt = 0.0)
      plen = (q2 - q1).abs if plen.nil? || plen <= 0.0
      pt = lambda do |q, off, dz, arc|
        px = ka[0] + d[0] * q
        py = ka[1] + d[1] * q
        z = za + (zb - za) * (q / len)
        z += head_lift * [0.0, 1.0 - (q - q1).abs / plen].max if head_lift > 0.0
        z += zadj.call(q) if zadj
        w = wscale ? wscale.call(q) : 1.0
        Geom::Point3d.new(px + off[0] * w, py + off[1] * w,
                          z + (dz + arc) * w)
      end
      sec = lambda do |q|
        prof.map { |(off, dz, arc)| pt.call(q, off, dz, arc) }
      end
      # THE CORNER CUT (2026-08-21, second pass). A hip cap cut SQUARE at its
      # low end pokes both its side corners out past the two eave lines that
      # meet there - "תעשה פינה שלא יעבור את ה-90 מעלות של הגג". With
      # miter_lo on, the q1 end is cut per point instead: the centre line
      # still reaches the corner, and every point is pulled back up the hip
      # by miter_lo times its own PLAN offset from the hip line. A hip
      # bisects a square corner at 45 degrees, so miter_lo of 1.0 lands the
      # cut exactly on both eave lines.
      a = if miter_lo > 0.0
            dir = q2 >= q1 ? 1.0 : -1.0
            span = (q2 - q1).abs
            prof.map do |(off, dz, arc)|
              back = Math.sqrt(off[0] * off[0] + off[1] * off[1]) * miter_lo
              back = span - 0.5 if back > span - 0.5   # never cross the far end
              pt.call(q1 + dir * back, off, dz, arc)
            end
          else
            sec.call(q1)
          end
      b = sec.call(q2)
      up = lambda { |q| Geom::Point3d.new(q.x, q.y, q.z + RIDGE_CAP_THICK) }
      au = a.map { |q| up.call(q) }
      bu = b.map { |q| up.call(q) }
      m = prof.length
      sub = grp.entities.add_group
      sub.name = 'InteriorPro_RidgeCap'
      sub.set_attribute('InteriorPro', 'part', 'ridge_cap')
      polys = []
      (0...(m - 1)).each do |i|
        polys << [a[i], a[i + 1], b[i + 1], b[i]]
        polys << [au[i], au[i + 1], bu[i + 1], bu[i]]
      end
      polys << [a[0], b[0], bu[0], au[0]]
      polys << [a[m - 1], b[m - 1], bu[m - 1], au[m - 1]]
      polys << (a + au.reverse)
      polys << (b + bu.reverse)
      # CLOSED FROM OUTSIDE (2026-08-21, second pass). The metal cap rides a
      # rib height above the deck, and once the ribs stopped short of it the
      # slot underneath showed from the eave - "החלק הזה צריך לסגור מבחוץ שלא
      # יראה חלול". A skirt drops from the cap's whole bottom rim - both side
      # edges and both ends - straight down onto the deck, so there is no
      # angle left that looks into the hollow. Clay passes skirt = 0 and is
      # drawn exactly as before.
      if skirt > 0.05
        dn = lambda { |p| Geom::Point3d.new(p.x, p.y, p.z - skirt) }
        polys << [a[0], b[0], dn.call(b[0]), dn.call(a[0])]
        polys << [a[m - 1], b[m - 1], dn.call(b[m - 1]), dn.call(a[m - 1])]
        (0...(m - 1)).each do |i|
          polys << [a[i], a[i + 1], dn.call(a[i + 1]), dn.call(a[i])]
          polys << [b[i], b[i + 1], dn.call(b[i + 1]), dn.call(b[i])]
        end
      end
      polys.each do |pp|
        faces = begin
          [sub.entities.add_face(pp)]
        rescue ArgumentError
          # REAL SketchUp REFUSES A NON-PLANAR LOOP (2026-08-21, second
          # pass) - the stub does not, which is exactly how this shipped
          # broken: a mitred corner end meeting a tucked head bends the side
          # quads ~0.01" out of plane, SketchUp raised, and the whole piece
          # died half drawn - "רידג' קאפ המקביל לאדום ירד". A triangle is
          # always planar, so a refused loop is fanned into triangles, and
          # the seams the split invents are softened away - they are not
          # real folds, whatever the material's own soften rule says.
          tris = (1...(pp.length - 1)).map do |i|
            begin
              sub.entities.add_face([pp[0], pp[i], pp[i + 1]])
            rescue ArgumentError
              nil
            end
          end.compact
          begin
            tris.each do |tf|
              next unless tf.respond_to?(:edges)
              tf.edges.each do |e|
                next unless e.faces.length == 2 &&
                            e.faces.all? { |ff| tris.include?(ff) }
                e.soft = true
                e.smooth = true
              end
            end
          rescue StandardError
            nil
          end
          tris
        end
        next if mat.nil?
        faces.each do |f|
          next if f.nil?
          f.material = mat
          f.back_material = mat
        end
      end
      # NO LINES on the arch either - the same request as the tiles. Only edges
      # with a face on BOTH sides are softened, so the cap keeps its silhouette
      # and loses the chord lines across its back.
      begin
        if soft
          sub.entities.grep(Sketchup::Edge).each do |e|
            next unless e.faces.length == 2
            e.soft = true
            e.smooth = true
          end
        end
      rescue StandardError => se
        puts "[Roof] cap soften: #{se.message}"
      end
      sub
    rescue StandardError => e
      puts "[Roof] build_cap_piece!: #{e.message}"
      nil
    end

    # Flat roof: a single surface on the wall tops. Roof color on top,
    # trim (white) underneath. Returns the top z.
    def self.build_flat_geometry!(grp, poly, z0, roof_mat, under_mat)
      top = poly.map { |p| Geom::Point3d.new(p[0], p[1], z0) }
      paint_surface!(grp.entities.add_face(top), roof_mat, under_mat)
      z0
    rescue StandardError => e
      puts "[Roof] build_flat_geometry!: #{e.message}"
      nil
    end

    # ---------- gable-end marking (the Gable Ends click tool) ----------

    def self.gable_wall_ids
      Sketchup.active_model.get_attribute('InteriorPro', 'roof_gable_wall_ids') || []
    end

    # Every wall id that actually exists in the model right now.
    def self.live_wall_ids
      InteriorPro::LevelManager.all_walls.map do |w|
        w.get_attribute('InteriorPro', 'id')
      end.compact
    end

    # Click positions saved with the marks (aligned with gable_wall_ids).
    # [1e9, 1e9] = an old mark with no click point.
    def self.gable_click_points
      flat = Sketchup.active_model.get_attribute('InteriorPro', 'roof_gable_click_xy') || []
      flat.each_slice(2).to_a
    end

    # PURE-ish: is this wall one a gable end must be refused on? Only a bowed
    # wall is. Safe when the curve code is not loaded at all - then nothing is
    # curved and nothing is refused.
    def self.gable_refused?(wall)
      return false unless wall && wall.valid?
      return false unless defined?(InteriorPro::WallTool) &&
                          InteriorPro::WallTool.respond_to?(:curved_wall?)
      InteriorPro::WallTool.curved_wall?(wall)
    rescue StandardError
      false
    end

    # Toggle a wall's roof end between hip and gable; saved by wall id on
    # the model, so it survives every rebuild. The CLICK POINT is saved
    # too — on a long wall the gable applies to the roof section under the
    # click (user 2026-08-05: no guessing). Rebuilds the roof if one
    # exists. Called by RoofGableTool.
    def self.toggle_gable_wall!(wall, click = nil)
      return false unless wall && wall.valid? &&
                          wall.get_attribute('InteriorPro', 'type') == 'wall'
      id = wall.get_attribute('InteriorPro', 'id')
      return false if id.nil?
      # A CURVED wall cannot carry a gable end (2026-08-12B). A gable end is a
      # flat triangle standing on a straight line; over a bowed wall there is
      # no such line, and the over-framing maths would quietly build a twisted
      # roof instead of saying so. Marking one is refused here - politely, and
      # BEFORE anything is saved - exactly the way a wall with a door in it
      # refuses to bend. Un-marking a wall that was already marked and then
      # bent still works, so nobody gets stuck.
      if gable_refused?(wall) && !gable_wall_ids.include?(id)
        msg = 'A curved wall cannot have a gable end. Straighten it first, ' \
              'or leave this end as a hip.'
        puts "[Roof] gable refused on curved wall #{id}"
        begin
          UI.messagebox(msg)
        rescue StandardError
          nil
        end
        return false
      end
      ids = gable_wall_ids.dup
      pts = gable_click_points
      pts = pts.first(ids.length) + Array.new([ids.length - pts.length, 0].max, [1e9, 1e9])
      # Self-heal (2026-08-05): a split/join/delete gives the wall a NEW id
      # ('...A' -> '...AJ'), so stored marks can point at walls that no
      # longer exist. Dead marks did nothing AND blocked the Gable style.
      live = live_wall_ids
      stale = ids.reject { |i2| live.include?(i2) }
      unless stale.empty?
        stale.each do |s2|
          k = ids.index(s2)
          ids.delete_at(k)
          pts.delete_at(k)
        end
        puts "[Roof] dropped #{stale.length} stale gable mark(s)"
      end
      idx = ids.index(id)
      if idx
        ids.delete_at(idx)
        pts.delete_at(idx)
        on = false
      else
        ids.push(id)
        pts.push(click ? [click[0].to_f, click[1].to_f] : [1e9, 1e9])
        on = true
      end
      m = Sketchup.active_model
      m.set_attribute('InteriorPro', 'roof_gable_wall_ids', ids)
      m.set_attribute('InteriorPro', 'roof_gable_click_xy', pts.flatten)
      puts "[Roof] wall #{id}: #{on ? 'GABLE end' : 'hip end'} (#{ids.length} marked)"
      build_roof! unless roofs.empty?
      true
    end

    # The gable triangle: a vertical face closing the gable end, from the
    # eave-corner height up along the roof profile (eave - ridge - eave).
    # Painted trim white by the catch-all trim pass.
    def self.build_gable_wall_face!(grp, poly, i, zmap)
      a = poly[i]
      b = poly[(i + 1) % poly.length]
      d = vnorm(vsub(b, a))
      len = vlen(vsub(b, a))
      chain = []
      zmap.each do |(x, y), z|
        p = [x, y]
        t = vdot(vsub(p, a), d)
        next if t < -NODE_TOL || t > len + NODE_TOL
        next if vcross(d, vsub(p, a)).abs > NODE_TOL
        chain << [t, p, z]
      end
      chain.sort_by!(&:first)
      return if chain.length < 2
      pts = chain.map { |_, p, z| Geom::Point3d.new(p[0], p[1], z) }
      # Close the profile down to the eave line. On a full-wall gable the
      # two chain ends already sit at eave height and these are dropped as
      # duplicates; on a STRIP gable (2026-08-05) the junction end hangs
      # high and needs the vertical drop edge to close the triangle.
      base = chain.map { |c| c[2] }.min
      [[b, base], [a, base]].each do |(q, z)|
        pt = Geom::Point3d.new(q[0], q[1], z)
        dup = pts.any? do |p|
          (p.x - pt.x).abs < 0.01 && (p.y - pt.y).abs < 0.01 &&
            (p.z - pt.z).abs < 0.01
        end
        pts << pt unless dup
      end
      return if pts.length < 3
      grp.entities.add_face(pts)
    rescue StandardError => e
      puts "[Roof] build_gable_wall_face!: #{e.message}"
    end

    # ---------- real gable walls (2026-08-08) ----------
    # The wall itself rises into the gable triangle (user 2026-08-05B):
    # wall-thick prisms from the wall top up to the roof-edge silhouette,
    # sitting on the WALL line (overhang back from the roof edge) and
    # painted with that wall's own exterior/interior sides.

    def self.wall_by_id(id)
      return nil unless id
      InteriorPro::LevelManager.all_walls.find do |w|
        w.get_attribute('InteriorPro', 'id') == id
      end
    end

    # Which end-plane LINE a poly edge lies on: [:h|:v, coord.round(2)].
    def self.line_key(poly, i)
      a = poly[i]
      d = vnorm(vsub(poly[(i + 1) % poly.length], a))
      d[0].abs > d[1].abs ? [:h, a[1].round(2)] : [:v, a[0].round(2)]
    end

    # gable-end LINE -> which framed piece owns it (:main or wing index),
    # for framed_cover_z exclusion. Key: [:h|:v, coord.round(2)].
    def self.framed_line_owners(framed)
      owners = {}
      framed[:g].each do |sd, on|
        next unless on
        vert, c, = framed_end_line(framed[:main], sd)
        owners[[vert ? :v : :h, c.round(2)]] = :main
      end
      framed[:wings].each_with_index do |w2, wi|
        next unless w2[:gabled]
        vert, c, = framed_end_line(w2[:rect], OPP_SIDE[w2[:mouth]])
        owners[[vert ? :v : :h, c.round(2)]] = wi
      end
      owners
    end

    # Spans of a profile chain that rise ABOVE zbase, entry/exit points
    # interpolated AT zbase. chain = [[t, [x,y], z], ...] sorted.
    # Returns [[[t, z], ...], ...]. Pure geometry (testable).
    def self.chain_regions_above(chain, zbase, eps = 0.02)
      regions = []
      cur = nil
      cross = lambda do |t1, z1, t2, z2|
        t1 + (t2 - t1) * (zbase - z1) / (z2 - z1)
      end
      chain.each_cons(2) do |(t1, _, z1), (t2, _, z2)|
        next if t2 - t1 < 1.0e-6
        a_up = z1 > zbase + eps
        b_up = z2 > zbase + eps
        if a_up
          cur ||= [[t1, z1]]
          if b_up
            cur << [t2, z2]
          else
            cur << [(z1 - z2).abs < 1.0e-9 ? t2 : cross.call(t1, z1, t2, z2), zbase]
            regions << cur
            cur = nil
          end
        elsif b_up
          cur = [[(z1 - z2).abs < 1.0e-9 ? t1 : cross.call(t1, z1, t2, z2), zbase],
                 [t2, z2]]
        end
      end
      regions << cur if cur
      regions.select { |r| r.length >= 2 && r.last[0] - r.first[0] > 0.5 }
    end

    def self.build_gable_wall_tops!(grp, poly, gables, wall_ids, zmap, z0,
                                    overhang, framed, band_top, slope)
      owners = framed ? framed_line_owners(framed) : {}
      surf = framed ? lambda { |cx, cy| framed_cover_z(framed, band_top, slope, cx, cy, nil) } : nil
      gables.each do |i|
        a = poly[i]
        b = poly[(i + 1) % poly.length]
        d = vnorm(vsub(b, a))
        key = line_key(poly, i)
        wall = wall_by_id(wall_ids[i])
        next unless wall
        th = wall.get_attribute('InteriorPro', 'thickness').to_f
        next if th < 0.1
        wt_z = wall.get_attribute('InteriorPro', 'base_z').to_f +
               wall.get_attribute('InteriorPro', 'height').to_f
        zbase = wt_z > 1.0 ? wt_z : z0
        # clipped to THIS poly edge, and following the TRUE roof
        # silhouette (2026-08-09 - it used to run the whole end-plane
        # line and bridge straight over the wing roof, in mid-air).
        chain = edge_profile_chain(poly, i, zmap, surface: surf)
        next if chain.nil?
        cov = if framed
                lambda { |cx, cy| framed_cover_z(framed, band_top, slope, cx, cy, owners[key]) }
              end
        inw = [-d[1], d[0]] # inward for CCW
        names = InteriorPro::WallTool.respond_to?(:wall_side_material_names) ?
                InteriorPro::WallTool.wall_side_material_names(wall) : [nil, nil]
        chain_regions_above(chain, zbase).each do |prof|
          # Only the VISIBLE spans get a prism (dense sampling, same rule
          # as the rakes): where a wing roof covers this line the profile
          # coincides with (or dives under) the wing surface, and a wall
          # there would knife through the wing roof - that was the lower
          # half of the "green line" bug (2026-08-09).
          wall_visible_profile(prof, a, d, cov).each do |pp|
            build_gable_top_prism!(grp, a, d, inw, overhang, th, zbase, pp, names)
          end
        end
      end
    rescue StandardError => e
      puts "[Roof] build_gable_wall_tops!: #{e.message}"
    end

    # The visible sub-profiles of a wall-top region: each cons pair is
    # clipped by rake_visible_runs (6" sampling + bisection, shared with
    # the rake boards), then contiguous runs are merged back so a span
    # that stays visible across the apex still becomes ONE face.
    def self.wall_visible_profile(prof, a, d, cov)
      return [prof] if cov.nil?
      segs = []
      prof.each_cons(2) do |(t1, z1), (t2, z2)|
        next if t2 - t1 < 1.0e-6
        p1 = [a[0] + d[0] * t1, a[1] + d[1] * t1]
        p2 = [a[0] + d[0] * t2, a[1] + d[1] * t2]
        rake_visible_runs(t1, t2, z1, z2, p1, p2, cov).each do |ra, rb|
          fa = (ra - t1) / (t2 - t1)
          fb = (rb - t1) / (t2 - t1)
          segs << [[ra, z1 + (z2 - z1) * fa], [rb, z1 + (z2 - z1) * fb]]
        end
      end
      runs = []
      segs.each do |s|
        if runs.any? && (s[0][0] - runs.last.last[0]).abs < 0.02
          runs.last << s[1]
        else
          runs << s.dup
        end
      end
      runs
    end

    # One prism: the profile face on the wall's OUTER plane, push-pulled
    # one wall thickness inward. prof = [[t, z], ...] along the edge.
    def self.build_gable_top_prism!(grp, a, d, inw, overhang, th, zbase, prof, names)
      return if prof.length < 2
      return if prof.last[0] - prof.first[0] < 0.5
      return if prof.map { |_, z| z }.max < zbase + 0.1
      at = lambda do |t|
        [a[0] + d[0] * t + inw[0] * overhang.to_f,
         a[1] + d[1] * t + inw[1] * overhang.to_f]
      end
      pts = prof.map { |t, z| q = at.call(t); Geom::Point3d.new(q[0], q[1], z) }
      if prof.last[1] > zbase + 0.01
        q = at.call(prof.last[0])
        pts << Geom::Point3d.new(q[0], q[1], zbase)
      end
      if prof.first[1] > zbase + 0.01
        q = at.call(prof.first[0])
        pts << Geom::Point3d.new(q[0], q[1], zbase)
      end
      return if pts.length < 3
      sub = grp.entities.add_group
      sub.name = 'InteriorPro_GableWall'
      sub.set_attribute('InteriorPro', 'part', 'gable_wall_top')
      f = sub.entities.add_face(pts)
      return if f.nil?
      inw3 = Geom::Vector3d.new(inw[0], inw[1], 0)
      f.pushpull((f.normal % inw3) > 0 ? th : -th) if f.respond_to?(:pushpull)
      paint_gable_top!(sub, d, inw, names)
    rescue StandardError => e
      puts "[Roof] build_gable_top_prism!: #{e.message}"
    end

    # Exterior side gets the wall's exterior material, interior side the
    # interior one - the triangle reads as the same wall, not as trim.
    # EVERY face is painted on BOTH sides: push-pulled faces come out with
    # arbitrary orientation, and a material on the back side only renders
    # as the default WHITE from outside (the 2026-08-09 white triangle).
    def self.paint_gable_top!(sub, d, inw, names)
      ext_name, int_name = names
      unless ext_name || int_name
        puts '[Roof] gable wall top: no wall materials found - left unpainted'
        return
      end
      return unless InteriorPro::WallTool.respond_to?(:new)
      wt = InteriorPro::WallTool.new
      ext_m = ext_name ? wt.load_or_create_material(ext_name) : nil
      int_m = int_name ? wt.load_or_create_material(int_name) : nil
      dir3 = Geom::Vector3d.new(d[0], d[1], 0)
      out3 = Geom::Vector3d.new(-inw[0], -inw[1], 0)
      sub.entities.grep(Sketchup::Face).each do |fc|
        n = fc.normal
        inner = n.z.abs < 0.5 && (n % dir3).abs < 0.5 && (n % out3) < 0
        m = inner ? (int_m || ext_m) : (ext_m || int_m)
        next unless m
        fc.material = m
        fc.back_material = m
      end
    rescue StandardError => e
      puts "[Roof] paint_gable_top!: #{e.message}"
    end

    # Rake board: the fascia climbing the two sloped edges of a gable end.
    # One mitered-ish box per profile segment, FASCIA_THICK outward.
    # z of the framed-roof surface at (x, y) EXCLUDING one piece (:main
    # or a wing index). Used to clip that piece's rake where its profile
    # dives under a covering roof (2026-08-05B: the rake must END where
    # the other roof starts, not cross it).
    def self.framed_cover_z(plan, z0d, sl, x, y, exclude)
      best = nil
      unless exclude == :main
        x0, y0, x1, y1 = plan[:main]
        if x >= x0 - 0.01 && x <= x1 + 0.01 && y >= y0 - 0.01 && y <= y1 + 0.01
          g = plan[:g]
          axis = if g[:e] || g[:w]
                   :x
                 elsif g[:n] || g[:s]
                   :y
                 else
                   (x1 - x0) >= (y1 - y0) ? :x : :y
                 end
          if axis == :x
            d = [y - y0, y1 - y]
            d << (x - x0) unless g[:w]
            d << (x1 - x) unless g[:e]
          else
            d = [x - x0, x1 - x]
            d << (y - y0) unless g[:s]
            d << (y1 - y) unless g[:n]
          end
          z = z0d + sl * d.min
          best = z if best.nil? || z > best
        end
      end
      plan[:wings].each_with_index do |w, wi|
        next if exclude == wi
        x0, y0, x1, y1 = w[:rect]
        half = w[:mouth] == :n || w[:mouth] == :s ? (x1 - x0) / 2.0 : (y1 - y0) / 2.0
        ex0 = x0; ey0 = y0; ex1 = x1; ey1 = y1
        case w[:mouth]
        when :n then ey1 += half
        when :s then ey0 -= half
        when :e then ex1 += half
        when :w then ex0 -= half
        end
        next unless x >= ex0 - 0.01 && x <= ex1 + 0.01 && y >= ey0 - 0.01 && y <= ey1 + 0.01
        if w[:mouth] == :n || w[:mouth] == :s
          d = [x - x0, x1 - x]
          d << (w[:mouth] == :n ? y - y0 : y1 - y) unless w[:gabled]
        else
          d = [y - y0, y1 - y]
          d << (w[:mouth] == :e ? x - x0 : x1 - x) unless w[:gabled]
        end
        z = z0d + sl * d.min
        best = z if best.nil? || z > best
      end
      best
    end

    # Visible sub-runs of a rake segment: parts of the profile that sit
    # ABOVE the covering roofs. Boundaries refined by bisection.
    def self.rake_visible_runs(t1, t2, z1, z2, p1, p2, cover)
      seg = t2 - t1
      return [[t1, t2]] if seg < 1.0e-6
      vis = lambda do |t|
        f = (t - t1) / seg
        x = p1[0] + (p2[0] - p1[0]) * f
        y = p1[1] + (p2[1] - p1[1]) * f
        z = z1 + (z2 - z1) * f
        c = cover.call(x, y)
        c.nil? || z > c + 0.05
      end
      n = [(seg / 6.0).ceil, 1].max
      ts = (0..n).map { |k| t1 + seg * k / n }
      runs = []
      cur = nil
      ts.each_with_index do |t, k|
        v = vis.call(t)
        if v && cur.nil?
          cur = t
          if k > 0
            lo = ts[k - 1]
            hi = t
            10.times { |_| mid = (lo + hi) / 2.0; vis.call(mid) ? hi = mid : lo = mid }
            cur = hi
          end
        elsif !v && cur
          lo = ts[k - 1]
          hi = t
          10.times { |_| mid = (lo + hi) / 2.0; vis.call(mid) ? lo = mid : hi = mid }
          runs << [cur, lo]
          cur = nil
        end
      end
      runs << [cur, t2] if cur
      runs.select { |ra, rb| rb - ra > 1.0 }
    end

    # The roof-edge silhouette over poly edge i: [[t, [x,y], z], ...]
    # sorted along the edge, upper envelope only (a point sagging below
    # its neighbours' line - e.g. a wing eave corner sitting ON the
    # gable-end line - is not part of the silhouette). full: profile of
    # the whole INFINITE line (a gable plane can span several poly edges,
    # 2026-08-05B); otherwise clipped to this edge with interpolated z at
    # the ends. Returns nil when no usable profile. Shared by the rake
    # boards and the real gable walls (2026-08-08).
    def self.edge_profile_chain(poly, i, zmap, full: false, surface: nil)
      a = poly[i]
      b = poly[(i + 1) % poly.length]
      d = vnorm(vsub(b, a))
      len = vlen(vsub(b, a))
      chain = []
      zmap.each do |(x, y), z|
        p = [x, y]
        next if vcross(d, vsub(p, a)).abs > NODE_TOL
        chain << [vdot(vsub(p, a), d), p, z]
      end
      chain.sort_by!(&:first)
      return nil if chain.length < 2
      if surface
        # The TRUE silhouette (2026-08-09): keep a node when it really is
        # the top of the roof there, drop it when some other roof piece
        # runs above it. The old "upper envelope" rule guessed this from
        # the neighbours alone and deleted legitimate low corners - on a
        # wall running past the main body onto a wing it erased the
        # body's own eave corner, so the fascia bridged from the ridge
        # straight out over the wing, in mid-air.
        chain = chain.reject do |_t, p, z|
          sz = surface.call(p[0], p[1])
          sz && sz > z + 0.5
        end
        return nil if chain.length < 2
      else
        loop do
          k = (1...(chain.length - 1)).find do |j|
            t0, _, z0 = chain[j - 1]
            t1, _, z1 = chain[j]
            t2, _, z2 = chain[j + 1]
            span = t2 - t0
            span > 1.0e-6 && z1 < z0 + (z2 - z0) * (t1 - t0) / span - 0.01
          end
          break unless k
          chain.delete_at(k)
        end
      end
      unless full
        # clip the profile to THIS poly edge, interpolating z at the ends
        zat = lambda do |t|
          return chain.first[2] if t <= chain.first[0]
          return chain.last[2] if t >= chain.last[0]
          j = chain.index { |c| c[0] >= t }
          t0, _, z0 = chain[j - 1]
          t1, _, z1 = chain[j]
          t1 - t0 < 1.0e-6 ? z1 : z0 + (z1 - z0) * (t - t0) / (t1 - t0)
        end
        inner_pts = chain.select { |t, _, _| t > NODE_TOL && t < len - NODE_TOL }
        chain = [[0.0, a, zat.call(0.0)]] + inner_pts + [[len, b, zat.call(len)]]
        return nil if chain.length < 2
      end
      chain
    end

    # k_in / k_out are the board's two faces, measured OUTWARD from the poly
    # line (2026-08-25). The defaults 0..FASCIA_THICK are exactly where the
    # rake fascia has always stood, so every existing call is unchanged. The
    # gable DRIP passes FASCIA_THICK..FASCIA_THICK+DRIP_THICK, which lands its
    # thin strip on the fascia's outer face - the same place the flat eave
    # drip sits relative to the flat fascia.
    def self.build_rake_board!(grp, poly, i, zmap, depth, full: false, cover: nil,
                               surface: nil, k_in: 0.0, k_out: FASCIA_THICK)
      a = poly[i]
      b = poly[(i + 1) % poly.length]
      d = vnorm(vsub(b, a))
      nrm = [d[1], -d[0]]                              # outward for CCW
      ins = [nrm[0] * k_in, nrm[1] * k_in]
      out = [nrm[0] * (k_out - k_in), nrm[1] * (k_out - k_in)]
      chain = edge_profile_chain(poly, i, zmap, full: full, surface: surface)
      return if chain.nil?
      # full profile (framed path, 2026-08-05B): the rake runs the WHOLE
      # gable-end plane - over covering wings too - eave to apex to eave.
      # Flat eave-level leftovers on the same line are skipped.
      zmin = chain.map { |c| c[2] }.min
      chain.each_cons(2) do |(t1, p1, z1), (t2, p2, z2)|
        # A run that stays at eave level is a plain EAVE, not a rake -
        # build_band! already put fascia there (2026-08-09: this used to
        # be checked only in full mode, so a clipped profile that ran on
        # past the gable doubled the fascia along the wing).
        next if z1 < zmin + 0.02 && z2 < zmin + 0.02
        next if t2 - t1 < 1.0e-6
        runs = cover ? rake_visible_runs(t1, t2, z1, z2, p1, p2, cover) : [[t1, t2]]
        runs.each do |ra, rb|
          fa = (ra - t1) / (t2 - t1)
          fb = (rb - t1) / (t2 - t1)
          q1 = [p1[0] + (p2[0] - p1[0]) * fa, p1[1] + (p2[1] - p1[1]) * fa]
          q2 = [p1[0] + (p2[0] - p1[0]) * fb, p1[1] + (p2[1] - p1[1]) * fb]
          za = z1 + (z2 - z1) * fa
          zb = z1 + (z2 - z1) * fb
          inner = [
            Geom::Point3d.new(q1[0] + ins[0], q1[1] + ins[1], za),
            Geom::Point3d.new(q2[0] + ins[0], q2[1] + ins[1], zb),
            Geom::Point3d.new(q2[0] + ins[0], q2[1] + ins[1], zb - depth),
            Geom::Point3d.new(q1[0] + ins[0], q1[1] + ins[1], za - depth)
          ]
          outer = inner.map { |p| Geom::Point3d.new(p.x + out[0], p.y + out[1], p.z) }
          grp.entities.add_face(inner)
          grp.entities.add_face(outer)
          4.times do |k|
            j = (k + 1) % 4
            grp.entities.add_face([inner[k], inner[j], outer[j], outer[k]])
          end
        end
      end
    rescue StandardError => e
      puts "[Roof] build_rake_board!: #{e.message}"
    end

    # How far the INNER edge of a rake soffit is pulled along the rake at
    # each end (2026-08-24). PURE, pinned by tests/rt84.rb.
    #
    # WHY: at a gable corner the flat eave soffit already covers half of
    # the corner square - offset_polygon miters that corner, so the eave
    # board ends on a 45 degree diagonal. A plain rectangular rake soffit
    # would lie ON TOP of that triangle, two coplanar faces in one group,
    # which is exactly the buried-face mess of the 2026-08-21 sessions.
    # Pulling the inner edge forward by the overhang cuts the same 45
    # degree diagonal, so the two boards meet on one seam.
    # Positive = forward along the rake (start end), negative = back (far
    # end), 0 in the middle of the edge.
    def self.rake_soffit_miter(t, len, overhang)
      oh = overhang.to_f
      return oh if t <= NODE_TOL
      return -oh if t >= len.to_f - NODE_TOL
      0.0
    end

    # The four corners of one rake-soffit board, underside. PURE, pinned by
    # tests/rt84.rb - and pinned there because the first version of this was
    # NOT PLANAR and SketchUp threw the whole board away (2026-08-24,
    # measured in the user's console: "build_rake_soffit!: Points are not
    # planar", 0 faces built).
    #
    # THE TRAP: the mitered inner corners are pulled ALONG the rake, and the
    # rake CLIMBS. Leaving them at the outer corner's height tilted them out
    # of the board's own plane. Every point moved by m along the rake must
    # rise by m * the rake's gradient with it.
    # ACROSS its width the board stays level: a gable roof's height depends
    # only on the distance from the ridge, so going inward off the rake does
    # not change z.
    def self.rake_soffit_quad(q1, q2, za, zb, d, inw, m1, m2)
      span = vlen(vsub(q2, q1))
      grad = span < 1.0e-6 ? 0.0 : (zb - za) / span
      [[q1[0], q1[1], za],
       [q2[0], q2[1], zb],
       [q2[0] + inw[0] + d[0] * m2, q2[1] + inw[1] + d[1] * m2, zb + grad * m2],
       [q1[0] + inw[0] + d[0] * m1, q1[1] + inw[1] + d[1] * m1, za + grad * m1]]
    end

    # THE BOX RETURN (user 2026-08-24: "הקובייה צריכה להיסגר לא ב-45 מעלות
    # אלא ב-90"). PURE, pinned by tests/rt84.rb.
    #
    # Cutting the two soffits into each other on the corner diagonal left
    # the box closing at 45 degrees, which is not how a boxed eave is
    # built. A real one RETURNS: at the corner the rake soffit stays LEVEL
    # with the flat eave soffit for one overhang, and only then steps up
    # square onto the rake. The step face is perpendicular to the rake -
    # that is the 90 degree closure, and the level piece under it is the
    # little box itself.
    #
    # Splits one run into pieces [t_from, t_to, level?]. `level?` means
    # hold the corner's own height right across the piece.
    def self.rake_soffit_segments(ra, rb, len, overhang)
      oh = overhang.to_f
      segs = []
      a = ra.to_f
      b = rb.to_f
      # a return needs its own overhang PLUS something left to slope
      roomy = (b - a) > oh + 0.5
      head = roomy && a <= NODE_TOL                 # the run starts at a corner
      tail = roomy && b >= len.to_f - NODE_TOL      # ...or ends at one
      if head && tail && (b - a) <= 2 * oh + 0.5    # no room for both returns
        head = false
        tail = false
      end
      if head
        segs << [a, a + oh, true]
        a += oh
      end
      if tail
        b -= oh
      end
      segs << [a, b, false] if b - a > 1.0e-6
      segs << [b, b + oh, true] if tail
      segs
    end

    # Drop points that repeat their neighbour. PURE, pinned by rt84.
    #
    # WHY IT EXISTS: a 45 degree miter eaten over a piece exactly one
    # overhang long collapses the quad's two inner corners onto the same
    # point - the plan shape really is a TRIANGLE there. Handing SketchUp
    # four points, two of them identical, raises, the rescue swallows it,
    # and the WHOLE rake soffit of that edge is never built. Measured
    # 2026-08-24 in the cloud stub after the user reported the gable soffit
    # had vanished completely.
    def self.dedupe_ring(pts, tol = 0.001)
      out = []
      pts.each do |p|
        q = out.last
        next if q && (p[0] - q[0]).abs < tol && (p[1] - q[1]).abs < tol &&
                (p[2] - q[2]).abs < tol
        out << p
      end
      f = out.first
      l = out.last
      if out.length > 1 && (f[0] - l[0]).abs < tol && (f[1] - l[1]).abs < tol &&
         (f[2] - l[2]).abs < tol
        out.pop
      end
      out
    end

    # The OUTER face of the box return (2026-08-24, the user's yellow
    # triangle). PURE, pinned by rt84.
    #
    # The return is level but the rake board above it climbs, so along the
    # outside of the little box a triangle opens up between the two: zero
    # at the corner, and (rise - one board) high where the step is. The
    # corner end is not the corner itself but the point where the climbing
    # board finally clears the top of the return - before that they touch.
    def self.rake_return_skirt(p_cross, p_step, z_flat, z_rake)
      lo = z_flat.to_f + SOFFIT_THICK
      return nil if z_rake.to_f - lo < 0.01
      [[p_cross[0], p_cross[1], lo],
       [p_step[0], p_step[1], lo],
       [p_step[0], p_step[1], z_rake.to_f]]
    end

    # Where along the return the rake board clears the top of it - the apex
    # of that triangle. Pure. Never leaves the return.
    def self.rake_skirt_cross(t_corner, t_step, grad)
      g = grad.abs
      return t_step if g < 1.0e-9
      step = SOFFIT_THICK / g
      dir = t_step >= t_corner ? 1.0 : -1.0
      t = t_corner + dir * step
      dir.positive? ? [t, t_step].min : [t, t_step].max
    end

    # Every mitered corner of a band, as the seam line it draws: from the
    # outer corner straight in to the offset one, at both faces of the
    # board. PURE, pinned by rt84.
    def self.band_corner_seams(poly, k_in, k_out, z_bot, z_top)
      inner = k_in.abs < 1e-9 ? poly : offset_polygon(poly, k_in)
      outer = k_out.abs < 1e-9 ? poly : offset_polygon(poly, k_out)
      return [] if inner.nil? || outer.nil?
      seams = []
      poly.length.times do |i|
        [z_bot, z_top].each do |z|
          seams << [[outer[i][0], outer[i][1], z], [inner[i][0], inner[i][1], z]]
        end
      end
      seams
    end

    # Hide a seam between two faces that are flush - the user does not want
    # to see a line where the boards simply meet (2026-08-24, the diagonal
    # across the corner). Soft + smooth is how the rest of this file does
    # it. Silently does nothing in the cloud stub, which builds no edges.
    # Matching by ENDPOINTS is not enough: every face added on the same
    # line splits that edge, and the halves no longer start and end where
    # the seam does. So an edge counts if it simply LIES ON the seam.
    def self.on_segment?(x, p, q, tol)
      v = [q[0] - p[0], q[1] - p[1], q[2] - p[2]]
      l2 = v[0] * v[0] + v[1] * v[1] + v[2] * v[2]
      return false if l2 < 1.0e-9
      w = [x[0] - p[0], x[1] - p[1], x[2] - p[2]]
      t = (w[0] * v[0] + w[1] * v[1] + w[2] * v[2]) / l2
      return false if t < -0.001 || t > 1.001
      dx = w[0] - v[0] * t
      dy = w[1] - v[1] * t
      dz = w[2] - v[2] * t
      Math.sqrt(dx * dx + dy * dy + dz * dz) < tol
    end

    # ONE RULE instead of chasing seams one at a time (2026-08-24, after
    # three rounds of the user pointing at another diagonal): inside the
    # soffit, an edge with a face on each side and BOTH FACES IN THE SAME
    # PLANE is a joint between two boards that are flush. It is not a
    # corner, there is nothing there to see, and it is softened.
    #
    # Scoped deliberately to the faces this build just added - the roof
    # deck and the tiles have flush seams of their own and are none of
    # this method's business.
    def self.soften_flush_seams!(faces)
      mine = {}
      faces.each { |f| mine[f.object_id] = true if f.respond_to?(:edges) }
      return if mine.empty?
      seen = {}
      faces.each do |f|
        next unless f.respond_to?(:edges)
        f.edges.each do |e|
          next if seen[e.object_id]
          seen[e.object_id] = true
          pair = e.faces.select { |x| mine[x.object_id] }
          next unless pair.length == 2
          n1 = pair[0].normal
          n2 = pair[1].normal
          next if (n1.x * n2.x + n1.y * n2.y + n1.z * n2.z).abs < 0.9999
          e.soft = true
          e.smooth = true
        end
      end
    rescue StandardError => e
      puts "[Roof] soften_flush_seams!: #{e.message}"
    end

    def self.soften_seams!(grp, seams, tol = 0.01)
      return if seams.nil? || seams.empty?
      grp.entities.grep(Sketchup::Edge).each do |e|
        a = e.start.position
        b = e.end.position
        pa = [a.x.to_f, a.y.to_f, a.z.to_f]
        pb = [b.x.to_f, b.y.to_f, b.z.to_f]
        seams.each do |(p, q)|
          next unless on_segment?(pa, p, q, tol) && on_segment?(pb, p, q, tol)
          e.soft = true
          e.smooth = true
          break
        end
      end
    rescue StandardError => e
      puts "[Roof] soften_seams!: #{e.message}"
    end

    # Add one face, but ONLY if it is a face. SketchUp raises "Duplicate
    # points in array" on ANY repeat, and inside build_rake_soffit! one
    # raise costs the whole edge - the user saw the gable soffit disappear
    # twice this way (2026-08-24). So every ring goes through here, sides
    # and step included, not just the ones thought likely to collapse.
    def self.add_ring!(grp, pts)
      return nil if pts.nil?
      ring = dedupe_ring(pts)
      return nil if ring.length < 3
      # a repeat that is not adjacent is a pinched ring, not a face
      return nil if ring.uniq.length < ring.length
      grp.entities.add_face(ring.map { |p| Geom::Point3d.new(p[0], p[1], p[2]) })
    rescue StandardError => e
      puts "[Roof] soffit face skipped: #{e.message}"
      nil
    end

    # The square face that shuts the box where the level return steps up
    # onto the rake. Vertical, PERPENDICULAR to the rake, spanning the
    # whole width of the soffit. Returns nil when the step is too small to
    # leave anything open (a shallow pitch closes itself).
    def self.rake_soffit_step(q, inw, z_flat, z_rake)
      lo = z_flat.to_f + SOFFIT_THICK
      hi = z_rake.to_f
      return nil if hi - lo < 0.01
      [[q[0], q[1], lo],
       [q[0] + inw[0], q[1] + inw[1], lo],
       [q[0] + inw[0], q[1] + inw[1], hi],
       [q[0], q[1], hi]]
    end

    # The rake soffit: the board that closes the gable overhang from
    # underneath, the sloped twin of the flat eave soffit (2026-08-24).
    # It hangs from the bottom of the rake board (same `depth` the rake
    # board uses) and runs inward by the overhang to the gable wall face.
    # ACROSS its width it is LEVEL: a gable roof's height depends only on
    # the distance from the ridge, so moving inward off the rake does not
    # change z. It slopes only ALONG the rake.
    def self.build_rake_soffit!(grp, poly, i, zmap, depth, overhang,
                                cover: nil, surface: nil)
      oh = overhang.to_f
      return if oh < 1.0
      a = poly[i]
      b = poly[(i + 1) % poly.length]
      d = vnorm(vsub(b, a))
      len = vlen(vsub(b, a))
      # The rake board stands OUTSIDE the poly line (build_rake_board!
      # pushes it outward by FASCIA_THICK), so the soffit runs right up to
      # that line and meets its inner face - no inset, no gap under it.
      inw = [-d[1] * oh, d[0] * oh] # inward for CCW - the rake board goes the other way
      chain = edge_profile_chain(poly, i, zmap, surface: surface)
      return if chain.nil?
      seams = []
      zmin = chain.map { |c| c[2] }.min
      chain.each_cons(2) do |(t1, p1, z1), (t2, p2, z2)|
        next if z1 < zmin + 0.02 && z2 < zmin + 0.02 # a plain eave, not a rake
        next if t2 - t1 < 1.0e-6
        runs = cover ? rake_visible_runs(t1, t2, z1, z2, p1, p2, cover) : [[t1, t2]]
        runs.each do |ra, rb|
          span = rb - ra
          next if span < 0.5
          fa = (ra - t1) / (t2 - t1)
          fb = (rb - t1) / (t2 - t1)
          q1 = [p1[0] + (p2[0] - p1[0]) * fa, p1[1] + (p2[1] - p1[1]) * fa]
          q2 = [p1[0] + (p2[0] - p1[0]) * fb, p1[1] + (p2[1] - p1[1]) * fb]
          za = z1 + (z2 - z1) * fa - depth.to_f
          zb = z1 + (z2 - z1) * fb - depth.to_f
          grad = span < 1.0e-6 ? 0.0 : (zb - za) / span
          pt_at = lambda do |t|
            f = (t - ra) / span
            [q1[0] + (q2[0] - q1[0]) * f, q1[1] + (q2[1] - q1[1]) * f]
          end
          segs = rake_soffit_segments(ra, rb, len, oh)
          segs.each do |sa, sb, level|
            # A sliver shorter than SketchUp's own 1/1000" tolerance has
            # two ends it treats as ONE point, and the face it would make
            # raises "Duplicate points in array" (2026-08-24).
            next if sb - sa < 0.01
            p_a = pt_at.call(sa)
            p_b = pt_at.call(sb)
            # a level RETURN holds the corner's height right across itself;
            # the sloped piece follows the rake as usual
            head = sa <= ra + 1.0e-6
            corner_t = head ? sa : sb
            z_a = level ? za + grad * (corner_t - ra) : za + grad * (sa - ra)
            z_b = level ? z_a : za + grad * (sb - ra)
            # THE BOX IS THE EAVE BOARD'S NOW (2026-08-24). The level
            # return used to be built here as a mitered triangle, and the
            # flat eave board's own mitered corner filled the other half -
            # the 45 degree joint between them is the line the user asked
            # to be rid of. Instead the eave band is cut SQUARE at a gable
            # corner (build_band!'s square_flags) and owns the whole corner
            # square, so this builder skips the level piece and only closes
            # it: the step at its far end, and the skirt on its outside.
            unless level
              ring = dedupe_ring(rake_soffit_quad(p_a, p_b, z_a, z_b, d, inw, 0.0, 0.0))
              next if ring.length < 3
              bot = ring
              top = ring.map { |p| [p[0], p[1], p[2] + SOFFIT_THICK] }
              add_ring!(grp, bot)
              add_ring!(grp, top)
              bot.length.times do |k|
                j = (k + 1) % bot.length
                add_ring!(grp, [bot[k], bot[j], top[j], top[k]])
              end
            end
            next unless level
            # the square step where the return meets the rake
            step_t = head ? sb : sa
            z_step = za + grad * (step_t - ra)
            p_step = pt_at.call(step_t)
            add_ring!(grp, rake_soffit_step(p_step, inw, z_a, z_step))
            # ...and the outer face of the little box, under the climbing
            # rake board - the user's yellow triangle
            p_cross = pt_at.call(rake_skirt_cross(corner_t, step_t, grad))
            add_ring!(grp, rake_return_skirt(p_cross, p_step, z_a, z_step))
            # That triangle's long side lies exactly along the bottom of
            # the rake fascia, in the same plane. The user wants the two
            # read as ONE board, not as a board with a diagonal drawn
            # across it (2026-08-24) - so the joint between them goes.
            seams << [[p_cross[0], p_cross[1], z_a + SOFFIT_THICK],
                      [p_step[0], p_step[1], z_step]]
          end
        end
      end
      soften_seams!(grp, seams)
    rescue StandardError => e
      puts "[Roof] build_rake_soffit!: #{e.message}"
    end

    # ---------- gable only on the mother span of a long wall ----------

    # Distance from origin along dirv to the nearest polygon boundary
    # crossing (ignoring edge skip_i). Rectilinear ray-cast.
    def self.ray_depth(poly, skip_i, origin, dirv)
      n = poly.length
      best = 1.0e12
      n.times do |j|
        next if j == skip_i
        p = poly[j]
        q = poly[(j + 1) % n]
        e = vsub(q, p)
        den = vcross(dirv, e)
        next if den.abs < 1e-9
        sdist = vcross(vsub(p, origin), e) / den
        u = vcross(vsub(p, origin), dirv) / den
        next if sdist < 1.0 || u < -1e-6 || u > 1.0 + 1e-6
        best = sdist if sdist < best
      end
      best
    end

    # Depth strips of edge i: cut positions from the other corners
    # projected onto the edge, plus the plan depth behind each strip.
    # Returns [[t0, t1, depth], ...] sorted along the edge.
    def self.gable_strips(poly, i)
      n = poly.length
      a = poly[i]
      b = poly[(i + 1) % n]
      d = vnorm(vsub(b, a))
      len = vlen(vsub(b, a))
      nrm = [-d[1], d[0]] # inward for CCW
      cuts = [0.0, len]
      poly.each_with_index do |p, j|
        next if j == i || j == (i + 1) % n
        t = vdot(vsub(p, a), d)
        cuts << t if t > 1.0 && t < len - 1.0
      end
      cuts = cuts.sort.each_with_object([]) { |t, acc| acc << t if acc.empty? || t - acc.last > 1.0 }
      ivs = []
      cuts.each_cons(2) do |t0, t1|
        mid = vadd(a, vmul(d, (t0 + t1) / 2.0))
        ivs << [t0, t1, ray_depth(poly, i, mid, nrm)]
      end
      ivs
    end

    # Grow from strip k over the neighbours of (nearly) the same depth.
    def self.expand_strips(ivs, k)
      ref = ivs[k][2]
      lo = k
      lo -= 1 while lo > 0 && (ivs[lo - 1][2] - ref).abs < 1.0
      hi = k
      hi += 1 while hi < ivs.length - 1 && (ivs[hi + 1][2] - ref).abs < 1.0
      [ivs[lo][0], ivs[hi][1]]
    end

    # No click point (old marks / tests): the DEEPEST strip is the mother.
    def self.gable_subinterval(poly, i)
      ivs = gable_strips(poly, i)
      return nil if ivs.empty?
      dmax = ivs.map { |iv| iv[2] }.max
      expand_strips(ivs, ivs.index { |iv| (iv[2] - dmax).abs < 0.01 })
    end

    # With a click point: the gable goes to the strip UNDER the click.
    def self.gable_subinterval_at(poly, i, click)
      ivs = gable_strips(poly, i)
      return nil if ivs.empty?
      a = poly[i]
      b = poly[(i + 1) % poly.length]
      d = vnorm(vsub(b, a))
      tc = vdot(vsub([click[0].to_f, click[1].to_f], a), d)
      k = ivs.index { |iv| tc >= iv[0] - 0.5 && tc <= iv[1] + 0.5 }
      k ||= tc < ivs.first[0] ? 0 : ivs.length - 1
      expand_strips(ivs, k)
    end

    # Split every marked gable edge at its gable-span limits: the polygon
    # gains collinear vertices there, only that sub-edge stays gable.
    # clicks: edge index -> [x, y] click point (nil = no point saved).
    # Returns the new [poly, wall_ids, gable_indices].
    def self.split_gable_edges(poly, wall_ids, gables, clicks = {})
      n = poly.length
      new_pts = []
      new_ids = []
      flags = []
      n.times do |i|
        a = poly[i]
        b = poly[(i + 1) % n]
        d = vnorm(vsub(b, a))
        len = vlen(vsub(b, a))
        g = gables.include?(i)
        sub = nil
        if g
          c = clicks[i]
          sub = c ? gable_subinterval_at(poly, i, c) : gable_subinterval(poly, i)
        end
        if !g || sub.nil? || (sub[0] < 1.0 && sub[1] > len - 1.0)
          new_pts << a
          new_ids << wall_ids[i]
          flags << g
          next
        end
        stops = [0.0]
        stops << sub[0] if sub[0] > 1.0
        stops << sub[1] if sub[1] < len - 1.0
        stops << len
        stops.each_cons(2) do |t0, t1|
          new_pts << vadd(a, vmul(d, t0))
          new_ids << wall_ids[i]
          flags << (t0 >= sub[0] - 0.5 && t1 <= sub[1] + 0.5)
        end
      end
      [new_pts, new_ids, flags.each_index.select { |k2| flags[k2] }]
    end

    # ---------- gable over-framing (2026-08-05, the user's mock) ----------
    # "This is how you actually build a roof": every marked wall gets the
    # FULL gable volume of its own wing — ridge perpendicular to the wall,
    # triangle over the whole wall — and the volumes run into each other
    # like stick framing: the wing ridge dives into the parent roof by half
    # the wing width, so the planes meet on real 45-degree valleys.
    # Replaces the strip-gable skeleton path on rectilinear plans; the old
    # strip path remains as a fallback for tangled footprints.

    RECT_TOL = 0.05 unless const_defined?(:RECT_TOL, false)

    def self.rectilinear?(poly)
      n = poly.length
      poly.each_index.all? do |i|
        a = poly[i]
        b = poly[(i + 1) % n]
        (a[0] - b[0]).abs < RECT_TOL || (a[1] - b[1]).abs < RECT_TOL
      end
    end

    # Slabs between consecutive vertex lines along one axis; every
    # connected interval inside a slab is a rectangle. Stacked rects with
    # the same cross-span are merged back afterwards.
    def self.slab_rects(poly, axis)
      n = poly.length
      cuts = []
      poly.each { |p| c = axis == :y ? p[1] : p[0]; cuts << c unless cuts.any? { |x| (x - c).abs < RECT_TOL } }
      cuts.sort!
      rects = []
      cuts.each_cons(2) do |c0, c1|
        mid = (c0 + c1) / 2.0
        us = []
        n.times do |i|
          a = poly[i]
          b = poly[(i + 1) % n]
          if axis == :y
            next if (a[1] - b[1]).abs < RECT_TOL
            lo, hi = [a[1], b[1]].minmax
            us << a[0] if mid > lo && mid < hi
          else
            next if (a[0] - b[0]).abs < RECT_TOL
            lo, hi = [a[0], b[0]].minmax
            us << a[1] if mid > lo && mid < hi
          end
        end
        return nil if us.empty? || us.length.odd?
        us.sort!
        us.each_slice(2) do |u0, u1|
          rects << (axis == :y ? [u0, c0, u1, c1] : [c0, u0, c1, u1])
        end
      end
      merge_rects!(rects, axis)
    end

    def self.merge_rects!(rects, axis)
      loop do
        pair = nil
        rects.each_with_index do |r, i|
          rects.each_with_index do |q, j|
            next if i >= j
            if axis == :y
              same = (r[0] - q[0]).abs < RECT_TOL && (r[2] - q[2]).abs < RECT_TOL
              touch = (r[3] - q[1]).abs < RECT_TOL || (q[3] - r[1]).abs < RECT_TOL
            else
              same = (r[1] - q[1]).abs < RECT_TOL && (r[3] - q[3]).abs < RECT_TOL
              touch = (r[2] - q[0]).abs < RECT_TOL || (q[2] - r[0]).abs < RECT_TOL
            end
            pair = [i, j] if same && touch
            break if pair
          end
          break if pair
        end
        break unless pair
        i, j = pair
        r = rects[i]
        q = rects[j]
        nr = [[r[0], q[0]].min, [r[1], q[1]].min, [r[2], q[2]].max, [r[3], q[3]].max]
        rects.delete_at(j)
        rects.delete_at(i)
        rects << nr
      end
      rects
    end

    # Maximal-rectangle decomposition on the vertex grid (2026-08-05, the
    # user's third house): slab cuts on ONE axis lose when wings hang on
    # BOTH axes. Here: split the plan by every wall line into grid cells,
    # then repeatedly take the biggest all-inside uncovered rectangle —
    # the intuitive main body falls out first, wings after it.
    def self.grid_rects(poly)
      xs = []
      ys = []
      poly.each do |p|
        xs << p[0] unless xs.any? { |v| (v - p[0]).abs < RECT_TOL }
        ys << p[1] unless ys.any? { |v| (v - p[1]).abs < RECT_TOL }
      end
      xs.sort!
      ys.sort!
      nx = xs.length - 1
      ny = ys.length - 1
      return nil if nx < 1 || ny < 1 || nx * ny > 400
      inside = Array.new(nx) do |i|
        Array.new(ny) do |j|
          point_in_poly?(poly, (xs[i] + xs[i + 1]) / 2.0, (ys[j] + ys[j + 1]) / 2.0)
        end
      end
      covered = Array.new(nx) { Array.new(ny, false) }
      rects = []
      loop do
        best = nil
        (0...nx).each do |i0|
          (i0...nx).each do |i1|
            (0...ny).each do |j0|
              (j0...ny).each do |j1|
                good = true
                (i0..i1).each do |i|
                  (j0..j1).each { |j| good &&= inside[i][j] && !covered[i][j] }
                  break unless good
                end
                next unless good
                area = (xs[i1 + 1] - xs[i0]) * (ys[j1 + 1] - ys[j0])
                best = [area, i0, i1, j0, j1] if best.nil? || area > best[0]
              end
            end
          end
        end
        break if best.nil?
        _, i0, i1, j0, j1 = best
        (i0..i1).each { |i| (j0..j1).each { |j| covered[i][j] = true } }
        rects << [xs[i0], ys[j0], xs[i1 + 1], ys[j1 + 1]]
        return nil if rects.length > 8
      end
      (0...nx).each do |i|
        (0...ny).each { |j| return nil if inside[i][j] && !covered[i][j] }
      end
      rects.empty? ? nil : rects
    end

    def self.point_in_poly?(poly, x, y)
      n = poly.length
      c = false
      j = n - 1
      n.times do |i|
        yi = poly[i][1]
        yj = poly[j][1]
        if (yi > y) != (yj > y)
          xx = poly[i][0] + (y - yi) / (yj - yi) * (poly[j][0] - poly[i][0])
          c = !c if x < xx
        end
        j = i
      end
      c
    end

    # The side of wing rect w that touches parent rect p, or nil.
    def self.mouth_side(w, p)
      xov = [w[2], p[2]].min - [w[0], p[0]].max
      yov = [w[3], p[3]].min - [w[1], p[1]].max
      return :n if (w[3] - p[1]).abs < RECT_TOL && xov > 1.0
      return :s if (p[3] - w[1]).abs < RECT_TOL && xov > 1.0
      return :e if (w[2] - p[0]).abs < RECT_TOL && yov > 1.0
      return :w if (p[2] - w[0]).abs < RECT_TOL && yov > 1.0
      nil
    end

    # Is this rect side (a full end wall) marked gable? True when a marked
    # wall's polygon edge lies on the side's line and overlaps its span.
    def self.side_gabled?(rect, side, poly, wall_ids, marked)
      x0, y0, x1, y1 = rect
      vert = side == :w || side == :e
      line_c = { s: y0, n: y1, w: x0, e: x1 }[side]
      span = vert ? [y0, y1] : [x0, x1]
      n = poly.length
      poly.each_index.any? do |i|
        next false unless wall_ids[i] && marked.include?(wall_ids[i])
        a = poly[i]
        b = poly[(i + 1) % n]
        if vert
          next false unless (a[0] - b[0]).abs < RECT_TOL && (a[0] - line_c).abs < RECT_TOL
          lo, hi = [a[1], b[1]].minmax
        else
          next false unless (a[1] - b[1]).abs < RECT_TOL && (a[1] - line_c).abs < RECT_TOL
          lo, hi = [a[0], b[0]].minmax
        end
        [hi, span[1]].min - [lo, span[0]].max > 1.0
      end
    end

    OPP_SIDE = { n: :s, s: :n, e: :w, w: :e }.freeze unless const_defined?(:OPP_SIDE, false)

    # Choose the best rect decomposition and resolve which ends are
    # gabled. Returns { main:, g:, wings: [{rect:, mouth:, gabled:}],
    # edges: [poly edge indices on gabled ends] } or nil (fallback).
    def self.framed_plan(poly, wall_ids, marked, style)
      return nil unless rectilinear?(poly)
      rects = grid_rects(poly)
      return nil unless rects
      assemble_framed_plan(rects, poly, wall_ids, marked, style)
    end

    def self.assemble_framed_plan(rects, poly, wall_ids, marked, style)
      return nil if rects.empty? || rects.length > 8
      main_i = rects.each_index.max_by { |i| (rects[i][2] - rects[i][0]) * (rects[i][3] - rects[i][1]) }
      main = rects[main_i]
      # attach every other rect to the tree: parent = main or an already
      # attached wing (2026-08-05: chained wings are legal — a leg hanging
      # off another wing gables against ITS parent's plane the same way)
      known = [main_i]
      pending = (0...rects.length).to_a - [main_i]
      wings = []
      until pending.empty?
        pick = nil
        pending.each do |i|
          known.each do |k|
            m = mouth_side(rects[i], rects[k])
            next unless m
            pick = [i, m]
            break
          end
          break if pick
        end
        return nil unless pick # detached piece: fall back to the skeleton
        i, m = pick
        gab = side_gabled?(rects[i], OPP_SIDE[m], poly, wall_ids, marked)
        wings << { rect: rects[i], mouth: m, gabled: gab }
        known << i
        pending.delete(i)
      end
      g = {}
      [:n, :s, :e, :w].each { |sd| g[sd] = side_gabled?(main, sd, poly, wall_ids, marked) }
      if style == 'gable'
        # Gable style (2026-08-05, the user's mock: "make the WHOLE roof
        # gable"): every wing end gets its triangle automatically, and the
        # main gets its two short-end triangles — no clicks needed. Marks
        # add on top; Hip style gables marked walls only.
        wings.each { |w| w[:gabled] = true }
        # BOTH main ends gable, even when a leftover click marked only one
        # (2026-08-05C: one end stayed hip). Marks only pick the axis.
        if g[:e] || g[:w]
          g[:e] = g[:w] = true
        elsif g[:n] || g[:s]
          g[:n] = g[:s] = true
        elsif (main[2] - main[0]) >= (main[3] - main[1])
          g[:e] = g[:w] = true
        else
          g[:n] = g[:s] = true
        end
      end
      return nil unless g.values.any? || wings.any? { |w| w[:gabled] }
      # ridge sanity: a lone gable + hip end must still leave a ridge
      if g[:e] || g[:w]
        half = (main[3] - main[1]) / 2.0
        xw = g[:w] ? main[0] : main[0] + half
        xe = g[:e] ? main[2] : main[2] - half
        return nil if xe - xw < -0.5
      elsif g[:n] || g[:s]
        half = (main[2] - main[0]) / 2.0
        ys = g[:s] ? main[1] : main[1] + half
        yn = g[:n] ? main[3] : main[3] - half
        return nil if yn - ys < -0.5
      end
      score = g.values.count(true) + wings.count { |w| w[:gabled] }
      plan = { main: main, g: g, wings: wings, score: score, nrects: rects.length }
      plan[:edges] = framed_gable_edges(poly, plan)
      plan
    end

    def self.framed_end_line(rect, side)
      x0, y0, x1, y1 = rect
      case side
      when :s then [false, y0, x0, x1]
      when :n then [false, y1, x0, x1]
      when :w then [true, x0, y0, y1]
      when :e then [true, x1, y0, y1]
      end
    end

    # Polygon edges that lie on a gabled end wall (for fascia skip + rakes).
    def self.framed_gable_edges(poly, plan)
      ends = []
      plan[:g].each { |sd, on| ends << framed_end_line(plan[:main], sd) if on }
      plan[:wings].each do |w|
        ends << framed_end_line(w[:rect], OPP_SIDE[w[:mouth]]) if w[:gabled]
      end
      n = poly.length
      (0...n).select do |i|
        a = poly[i]
        b = poly[(i + 1) % n]
        ends.any? do |(vert, c, s0, s1)|
          if vert
            (a[0] - b[0]).abs < RECT_TOL && (a[0] - c).abs < RECT_TOL &&
              [[a[1], b[1]].max, s1].min - [[a[1], b[1]].min, s0].max > 1.0
          else
            (a[1] - b[1]).abs < RECT_TOL && (a[1] - c).abs < RECT_TOL &&
              [[a[0], b[0]].max, s1].min - [[a[0], b[0]].min, s0].max > 1.0
          end
        end
      end
    end

    # sloped face: lift the plan points, track ridge + zmap, paint
    def self.framed_face!(st, pts2, lift)
      pts = pts2.map { |p| Geom::Point3d.new(p[0], p[1], lift.call(p)) }
      pts.each do |p|
        key = [p.x.round(4), p.y.round(4)]
        st[:zmap][key] = p.z if st[:zmap][key].nil? || p.z > st[:zmap][key]
        st[:ridge] = p.z if p.z > st[:ridge]
      end
      paint_surface!(st[:grp].entities.add_face(pts), st[:roof_mat], st[:under_mat])
    end

    # gable end profile: records the heights (zmap/ridge) that the rake
    # boards and bands need. NO white triangle face any more (user
    # 2026-08-05B: the wall itself will rise to the roof shape later).
    def self.framed_tri!(st, pts3)
      pts3.each do |(x, y, z)|
        key = [x.round(4), y.round(4)]
        st[:zmap][key] = z if st[:zmap][key].nil? || z > st[:zmap][key]
        st[:ridge] = z if z > st[:ridge]
      end
    end

    # Main rectangle: plain prism — gable triangle on gabled ends, hip
    # plane on the others.
    def self.build_main_rect!(st, rect, g)
      x0, y0, x1, y1 = rect
      z0d = st[:z0] + st[:delta]
      sl = st[:slope]
      axis = if g[:e] || g[:w]
               :x
             elsif g[:n] || g[:s]
               :y
             else
               (x1 - x0) >= (y1 - y0) ? :x : :y
             end
      if axis == :x
        yr = (y0 + y1) / 2.0
        zr = z0d + sl * (yr - y0)
        xw = g[:w] ? x0 : x0 + (yr - y0)
        xe = g[:e] ? x1 : x1 - (yr - y0)
        framed_face!(st, [[x0, y0], [x1, y0], [xe, yr], [xw, yr]], ->(p) { z0d + sl * (p[1] - y0) })
        framed_face!(st, [[x1, y1], [x0, y1], [xw, yr], [xe, yr]], ->(p) { z0d + sl * (y1 - p[1]) })
        if g[:w]
          framed_tri!(st, [[x0, y0, z0d], [x0, y1, z0d], [x0, yr, zr]])
        else
          framed_face!(st, [[x0, y1], [x0, y0], [xw, yr]], ->(p) { z0d + sl * (p[0] - x0) })
        end
        if g[:e]
          framed_tri!(st, [[x1, y1, z0d], [x1, y0, z0d], [x1, yr, zr]])
        else
          framed_face!(st, [[x1, y0], [x1, y1], [xe, yr]], ->(p) { z0d + sl * (x1 - p[0]) })
        end
      else
        xr = (x0 + x1) / 2.0
        zr = z0d + sl * (xr - x0)
        ys = g[:s] ? y0 : y0 + (xr - x0)
        yn = g[:n] ? y1 : y1 - (xr - x0)
        framed_face!(st, [[x0, y1], [x0, y0], [xr, ys], [xr, yn]], ->(p) { z0d + sl * (p[0] - x0) })
        framed_face!(st, [[x1, y0], [x1, y1], [xr, yn], [xr, ys]], ->(p) { z0d + sl * (x1 - p[0]) })
        if g[:s]
          framed_tri!(st, [[x0, y0, z0d], [x1, y0, z0d], [xr, y0, zr]])
        else
          framed_face!(st, [[x0, y0], [x1, y0], [xr, ys]], ->(p) { z0d + sl * (p[1] - y0) })
        end
        if g[:n]
          framed_tri!(st, [[x1, y1, z0d], [x0, y1, z0d], [xr, y1, zr]])
        else
          framed_face!(st, [[x1, y1], [x0, y1], [xr, yn]], ->(p) { z0d + sl * (y1 - p[1]) })
        end
      end
    end

    # One wing side plane. The penetration wedge (beyond the mouth) forms
    # a true 45-degree valley when it is VISIBLE above the parent roof;
    # a wing whose mouth straddles the parent ridge dives fully UNDER the
    # parent (junk inside + coplanar z-fight, 2026-08-05B) - then the
    # plane is clipped at the mouth line instead.
    def self.wing_side_face!(st, quad, mouth_cut, tri, lift, cover)
      keep = true
      if cover
        cx = (tri[0][0] + tri[1][0] + tri[2][0]) / 3.0
        cy = (tri[0][1] + tri[1][1] + tri[2][1]) / 3.0
        cz = cover.call(cx, cy)
        keep = cz.nil? || lift.call([cx, cy]) > cz + 0.02
      end
      framed_face!(st, keep ? quad : mouth_cut, lift)
    end

    # A wing: ridge perpendicular to its mouth, gable (or hip) at the
    # outer end. The ridge dives PAST the mouth into the parent by half
    # the wing width, so the wing planes meet the parent plane exactly on
    # 45-degree valleys (same pitch everywhere).
    def self.build_wing_rect!(st, rect, mouth, gabled, cover = nil)
      x0, y0, x1, y1 = rect
      z0d = st[:z0] + st[:delta]
      sl = st[:slope]
      # a clipped wing tucks under the parent roof up to the WALL line
      # (the mouth line sits an overhang outside it, 2026-08-05C)
      tuck = sl > 1.0e-6 ? -st[:delta] / sl : 0.0
      if mouth == :n || mouth == :s
        xr = (x0 + x1) / 2.0
        half = (x1 - x0) / 2.0
        zr = z0d + sl * half
        if mouth == :n # wing extends down: mouth y1, outer end y0
          pen = y1 + half
          out_r = gabled ? y0 : y0 + half
          y1t = y1 + tuck
          wing_side_face!(st, [[x0, y1], [x0, y0], [xr, out_r], [xr, pen]],
                          [[x0, y1t], [x0, y0], [xr, out_r], [xr, y1t]],
                          [[x0, y1], [xr, y1], [xr, pen]],
                          ->(p) { z0d + sl * (p[0] - x0) }, cover)
          wing_side_face!(st, [[x1, y0], [x1, y1], [xr, pen], [xr, out_r]],
                          [[x1, y0], [x1, y1t], [xr, y1t], [xr, out_r]],
                          [[x1, y1], [xr, pen], [xr, y1]],
                          ->(p) { z0d + sl * (x1 - p[0]) }, cover)
          if gabled
            framed_tri!(st, [[x0, y0, z0d], [x1, y0, z0d], [xr, y0, zr]])
          else
            framed_face!(st, [[x0, y0], [x1, y0], [xr, out_r]], ->(p) { z0d + sl * (p[1] - y0) })
          end
        else # :s -> wing extends up: mouth y0, outer end y1
          pen = y0 - half
          out_r = gabled ? y1 : y1 - half
          y0t = y0 - tuck
          wing_side_face!(st, [[x0, y1], [x0, y0], [xr, pen], [xr, out_r]],
                          [[x0, y1], [x0, y0t], [xr, y0t], [xr, out_r]],
                          [[x0, y0], [xr, pen], [xr, y0]],
                          ->(p) { z0d + sl * (p[0] - x0) }, cover)
          wing_side_face!(st, [[x1, y0], [x1, y1], [xr, out_r], [xr, pen]],
                          [[x1, y0t], [x1, y1], [xr, out_r], [xr, y0t]],
                          [[x1, y0], [xr, y0], [xr, pen]],
                          ->(p) { z0d + sl * (x1 - p[0]) }, cover)
          if gabled
            framed_tri!(st, [[x1, y1, z0d], [x0, y1, z0d], [xr, y1, zr]])
          else
            framed_face!(st, [[x1, y1], [x0, y1], [xr, out_r]], ->(p) { z0d + sl * (y1 - p[1]) })
          end
        end
      else
        yr = (y0 + y1) / 2.0
        half = (y1 - y0) / 2.0
        zr = z0d + sl * half
        if mouth == :e # wing extends left: mouth x1, outer end x0
          pen = x1 + half
          out_r = gabled ? x0 : x0 + half
          x1t = x1 + tuck
          wing_side_face!(st, [[x0, y0], [x1, y0], [pen, yr], [out_r, yr]],
                          [[x0, y0], [x1t, y0], [x1t, yr], [out_r, yr]],
                          [[x1, y0], [pen, yr], [x1, yr]],
                          ->(p) { z0d + sl * (p[1] - y0) }, cover)
          wing_side_face!(st, [[x1, y1], [x0, y1], [out_r, yr], [pen, yr]],
                          [[x1t, y1], [x0, y1], [out_r, yr], [x1t, yr]],
                          [[x1, y1], [x1, yr], [pen, yr]],
                          ->(p) { z0d + sl * (y1 - p[1]) }, cover)
          if gabled
            framed_tri!(st, [[x0, y0, z0d], [x0, y1, z0d], [x0, yr, zr]])
          else
            framed_face!(st, [[x0, y1], [x0, y0], [out_r, yr]], ->(p) { z0d + sl * (p[0] - x0) })
          end
        else # :w -> wing extends right: mouth x0, outer end x1
          pen = x0 - half
          out_r = gabled ? x1 : x1 - half
          x0t = x0 - tuck
          wing_side_face!(st, [[x0, y0], [x1, y0], [out_r, yr], [pen, yr]],
                          [[x0t, y0], [x1, y0], [out_r, yr], [x0t, yr]],
                          [[x0, y0], [x0, yr], [pen, yr]],
                          ->(p) { z0d + sl * (p[1] - y0) }, cover)
          wing_side_face!(st, [[x1, y1], [x0, y1], [pen, yr], [out_r, yr]],
                          [[x1, y1], [x0t, y1], [x0t, yr], [out_r, yr]],
                          [[x0, y1], [x0, yr], [pen, yr]],
                          ->(p) { z0d + sl * (y1 - p[1]) }, cover)
          if gabled
            framed_tri!(st, [[x1, y1, z0d], [x1, y0, z0d], [x1, yr, zr]])
          else
            framed_face!(st, [[x1, y0], [x1, y1], [out_r, yr]], ->(p) { z0d + sl * (x1 - p[0]) })
          end
        end
      end
    end

    # Build the whole framed roof. Returns [ridge, zmap] or nil.
    def self.build_framed_geometry!(grp, plan, z0, slope, overhang,
                                    roof_mat, under_mat)
      st = { grp: grp, z0: z0, delta: -slope * overhang.to_f, slope: slope,
             roof_mat: roof_mat, under_mat: under_mat, ridge: z0, zmap: {} }
      build_main_rect!(st, plan[:main], plan[:g])
      plan[:wings].each_with_index do |w, wi|
        cov = lambda { |x, y| framed_cover_z(plan, st[:z0] + st[:delta], st[:slope], x, y, wi) }
        build_wing_rect!(st, w[:rect], w[:mouth], w[:gabled], cov)
      end
      [st[:ridge], st[:zmap]]
    rescue StandardError => e
      puts "[Roof] build_framed_geometry!: #{e.message}"
      nil
    end

    # Gable style: the two shortest non-adjacent edges become the gables.
    def self.pick_gable_edges(poly)
      n = poly.length
      lens = Array.new(n) { |i| vlen(vsub(poly[(i + 1) % n], poly[i])) }
      order = (0...n).sort_by { |i| lens[i] }
      first = order[0]
      second = order[1..].find { |j| j != (first + 1) % n && j != (first - 1) % n }
      [first, second].compact
    end

    # A rectangular band (fascia board / drip edge) around the eave
    # perimeter: between the outward offsets k_in and k_out of the polygon,
    # from z_top down to z_bot. One mitered box per edge, 6 faces each.
    # What is LEFT of 0..len once the spans are removed.
    def self.complement_spans(spans, len)
      out = []
      cur = 0.0
      spans.map { |a, b| [[a, 0.0].max, [b, len].min] }
           .reject { |a, b| b <= a }
           .sort_by(&:first)
           .each do |a, b|
        out << [cur, a] if a > cur
        cur = b if b > cur
      end
      out << [cur, len] if cur < len
      out
    end

    def self.lerp2(p, q, f)
      [p[0] + (q[0] - p[0]) * f, p[1] + (q[1] - p[1]) * f]
    end

    # One edge of `poly`, pushed sideways by k - the same offset
    # offset_polygon uses (right = outward for CCW). Returns [point, dir].
    # PURE.
    def self.offset_line(poly, i, k)
      n = poly.length
      d = vnorm(vsub(poly[(i + 1) % n], poly[i]))
      [vadd(poly[i], vmul([d[1], -d[0]], k)), d]
    end

    # Where two such lines cross, or nil when they are parallel. PURE.
    def self.line_cross(l1, l2)
      p1, d1 = l1
      p2, d2 = l2
      den = vcross(d1, d2)
      return nil if den.abs < 1e-9
      t = vcross(vsub(p2, p1), d2) / den
      vadd(p1, vmul(d1, t))
    end

    # THE SQUARE END (2026-08-24). PURE, pinned by tests/rt84.rb.
    #
    # A mitered corner ends the band on the 45 degree line from its inner
    # corner to its outer one, and the neighbour fills the other half of
    # the corner square - that diagonal is exactly the line the user kept
    # seeing across his soffit. A square end instead runs the band ACROSS
    # the whole corner square and cuts it off flat, perpendicular to
    # itself, on the neighbour's own OUTER line.
    #
    # `k_cut` is the neighbour's INNER FACE, the line the band has to reach
    # so nothing is left open under it. At a gable that neighbour is the
    # rake board, and build_rake_board! stands it OUTSIDE the poly line -
    # so k_cut is 0, the poly line itself. Cutting at the soffit's own
    # k_out instead left a FASCIA_THICK gap the user could see straight
    # through (2026-08-24).
    def self.band_square_corner(poly, edge, other, k_in, k_cut)
      line_cross(offset_line(poly, edge, k_in), offset_line(poly, other, k_cut))
    end

    # skip_flags[i]  - drop the fascia/drip on this whole edge (gable rake)
    # skip_spans[i]  - drop it only on these t ranges along the edge, and
    #                  keep the rest (2026-08-09). A marked wall can run
    #                  past its own gable onto a wing, where the roof is a
    #                  plain eave that still needs its fascia - flagging
    #                  the whole edge erased it.
    # square_flags[i] - the corner where THIS band meets edge i is cut
    #                   SQUARE instead of mitered, and the band runs on to
    #                   the far side of that edge's own outer line, so the
    #                   whole corner square belongs to this band (the boxed
    #                   soffit, user 2026-08-24: "מרובע בקצה במקום האלכסון
    #                   פלוס החתיכה שמשלימה אותה"). Only the soffit passes
    #                   it - the fascia and the drip stay mitered.
    # square_k       - the line to cut on, as an offset of the NEIGHBOUR's
    #                   edge. 0 = the poly line itself, which is where the
    #                   rake board's inner face stands.
    def self.build_band!(grp, poly, k_in, k_out, z_top, z_bot, skip_flags = nil,
                         skip_spans = nil, square_flags = nil, square_k = 0.0)
      inner = k_in.abs < 1e-9 ? poly : offset_polygon(poly, k_in)
      outer = offset_polygon(poly, k_out)
      return if inner.nil? || outer.nil?
      n = poly.length
      n.times do |i|
        j = (i + 1) % n
        spans = skip_spans && skip_spans[i]
        if spans
          len = vlen(vsub(poly[j], poly[i]))
          next if len < 1.0e-6
          complement_spans(spans, len).each do |(ta, tb)|
            next if tb - ta < 0.5
            fa = ta / len
            fb = tb / len
            quad = [lerp2(inner[i], inner[j], fa), lerp2(inner[i], inner[j], fb),
                    lerp2(outer[i], outer[j], fb), lerp2(outer[i], outer[j], fa)]
            add_prism!(grp.entities, quad, z_top, z_bot)
          end
          next
        end
        next if skip_flags && skip_flags[i] # no fascia/drip on gable rakes
        a_in = inner[i]
        b_in = inner[j]
        a_out = outer[i]
        b_out = outer[j]
        if square_flags
          prev = (i - 1) % n
          if square_flags[prev]
            a_in = band_square_corner(poly, i, prev, k_in, square_k) || a_in
            a_out = band_square_corner(poly, i, prev, k_out, square_k) || a_out
          end
          if square_flags[j]
            b_in = band_square_corner(poly, i, j, k_in, square_k) || b_in
            b_out = band_square_corner(poly, i, j, k_out, square_k) || b_out
          end
        end
        quad = [a_in, b_in, b_out, a_out]
        add_prism!(grp.entities, quad, z_top, z_bot)
      end
    rescue StandardError => e
      puts "[Roof] build_band!: #{e.message}"
    end

    # ---------- soffit: the flat plate under the eave (2026-08-24) -------
    #
    # PURE - no SketchUp API, so tests/rt84.rb can measure it directly.
    #
    # `poly` is already the EAVE outline: the wall's exterior face pushed
    # out by the overhang. So the plate runs from offset -overhang (back at
    # the wall) out to the INNER face of the fascia, and its underside sits
    # on the fascia's own bottom line - one flush edge, no lip.
    # Returns nil when there is nothing to close: no overhang, or an
    # overhang too shallow to fit a board between wall and fascia.
    def self.soffit_band(overhang, fascia_depth, fascia, band_top)
      oh = overhang.to_f
      return nil if oh < 1.0
      k_out = fascia ? -FASCIA_THICK : 0.0
      k_in  = -oh
      return nil if k_out - k_in < 0.5
      z_bot = band_top.to_f - fascia_depth.to_f
      { k_in: k_in, k_out: k_out, z_bot: z_bot, z_top: z_bot + SOFFIT_THICK }
    end

    # The soffit's default colour, per style (2026-08-25). nil = leave the
    # board to the trim colour, which is what a painted boxed soffit is and
    # what every roof built before this date did - so 'boxed' is untouched.
    #
    # A METHOD, NOT A CONSTANT, for the reason spelled out over roof_textures:
    # `X = {...} unless const_defined?(:X)` is not re-read by
    # InteriorPro.reload!, and that has already cost this project two rounds.
    def self.soffit_colors
      {
        'boxed'  => nil,        # painted board - follows the fascia
        'wood'   => '#8b5a2b',  # stained fir
        # 'beams' is deliberately NOT here (user 2026-08-25: "הקרשים צריכים
        # להיות בצבע של הפשייה"). nil drops the tails through to the trim
        # colour at the end of build_roof!, which IS the fascia colour - so
        # the two always match, even after the picker changes.
        'stucco' => '#efeae1'   # off white, same family as a stucco wall
      }
    end

    # nil = follow the fascia. A soffit_color set by hand always wins, so a
    # wood soffit can be re-stained without inventing a new style.
    def self.soffit_color(s)
      c = s[:soffit_color].to_s.strip
      return c if c.start_with?('#')
      soffit_colors[s[:soffit].to_s]
    end

    # THE SOFFIT WEARS A PICTURE, NOT A COLOUR (2026-08-25, user: "יש רק
    # צבע זה לא טקסטורה"). The roof SURFACE went to the colour picker on
    # 2026-08-21 because its tiles carry their pattern in 3D - two patterns
    # fighting. The soffit has no 3D pattern at all (the user chose a plain
    # board over modelled planks, same call the shingle got), so here the
    # texture IS the pattern and there is nothing for it to fight.
    #
    # size = the tile's real width in inches. soffit_wood.jpg is one square
    # of about 17 boards, so 72" puts a board at a touch over 4" - a normal
    # tongue and groove soffit board. Change the number here and nowhere else.
    #
    # A METHOD, NOT A CONSTANT - InteriorPro.reload! does not re-read a
    # `unless const_defined?` constant, the trap documented over roof_textures.
    def self.soffit_textures
      {
        'wood'   => { file: 'soffit_wood.jpg', size: 72.0 },
        'stucco' => { file: 'stucco.jpg',      size: 48.0 }
      }
    end

    # What the board is actually painted with. In order:
    #   1. a soffit_color picked by hand wins - it is an explicit override
    #   2. the style's texture, if its file is on disk
    #   3. the style's default colour
    #   4. nil -> the trim colour, which is what 'boxed' and 'none' get
    # A missing file can only ever cost the picture, never the roof.
    # Returns { mat:, size: } - size is the texture's tile width in inches
    # when a picture won, and nil when a flat colour did. The caller needs
    # BOTH: a colour has no direction, a picture has to be turned to line up
    # with the fascia. One method answers it so the two cannot drift apart.
    def self.soffit_paint(model, s)
      hand = s[:soffit_color].to_s.strip
      return { mat: color_material(model, hand), size: nil } if hand.start_with?('#')
      spec = soffit_textures[s[:soffit].to_s]
      if spec
        p = texture_path(spec[:file])
        if File.exist?(p)
          name = "InteriorPro_Soffit_#{s[:soffit]}"
          m = model.materials[name]
          return { mat: m, size: spec[:size] } if m
          m = model.materials.add(name)
          begin
            m.texture = p
            m.texture.size = spec[:size] if m.texture
            return { mat: m, size: spec[:size] }
          rescue StandardError => e
            puts "[Roof] soffit texture #{spec[:file]}: #{e.message}"
          end
        else
          puts "[Roof] soffit texture missing: #{p} - falling back to colour"
        end
      end
      c = soffit_color(s)
      c ? { mat: color_material(model, c), size: nil } : nil
    end

    # THE PLANKS RUN ALONG THE FASCIA (2026-08-25, user: "אני רוצה שזה תמיד
    # ילך לאורך הפשייה"). Left to itself SketchUp lays a texture out on the
    # world axes, so on any eave that is not dead square to red/green the
    # boards crossed it on a diagonal.
    #
    # No edge index has to be threaded through the four builders to fix it:
    # every soffit piece is a long board, so its own LONGEST edge already
    # points along the fascia. On a rake that same rule points it up the
    # slope, which is where the boards go there too.
    # Known small case: the little square box return at a gable corner is as
    # wide as it is long, so which way it reads is a coin toss. It is one
    # overhang across and hidden in the corner.
    #
    # PURE, pinned by rt84. 3D on purpose - a rake board is sloped, and a
    # direction that is not IN the face's plane cannot orient its texture.
    def self.ring_longest_dir(ring)
      return nil if ring.nil? || ring.length < 2
      best = nil
      bl = 0.0
      n = ring.length
      n.times do |i|
        a = ring[i]
        b = ring[(i + 1) % n]
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        dz = b[2] - a[2]
        l = Math.sqrt(dx * dx + dy * dy + dz * dz)
        next if l <= bl
        bl = l
        best = [dx / l, dy / l, dz / l]
      end
      bl > 1.0e-6 ? best : nil
    end

    # position_material with TWO pairs sets origin, rotation and scale in one
    # go, which is exactly the three things a lined-up board needs.
    # DEFENSIVE BY INTENT: the cloud stub has no position_material and a face
    # can refuse one, so every path ends with the face painted - at worst on
    # the world axes, the way it looked before this.
    def self.paint_soffit_face!(face, mat, size)
      done = false
      if size && face.respond_to?(:position_material) && face.respond_to?(:vertices)
        begin
          ring = face.vertices.map { |v| [v.position.x, v.position.y, v.position.z] }
          d = ring_longest_dir(ring)
          if d
            o = face.vertices.first.position
            u = Geom::Point3d.new(o.x + d[0] * size, o.y + d[1] * size, o.z + d[2] * size)
            pts = [o, Geom::Point3d.new(0, 0, 0), u, Geom::Point3d.new(1, 0, 0)]
            done = face.position_material(mat, pts, true) ? true : false
            face.position_material(mat, pts, false)
          end
        rescue StandardError => e
          puts "[Roof] soffit texture alignment: #{e.message}"
          done = false
        end
      end
      return if done
      face.material = mat
      face.back_material = mat
    end

    # EXPOSED RAFTER TAILS (2026-08-25, the user's numbers: 2x4 every 18").
    # Real 2x4: 1.5" across, 3.5" deep. A METHOD, not constants - the
    # reload! trap documented over roof_textures.
    def self.beam_spec
      { w: 1.5, h: 3.5, spacing: 18.0 }
    end

    # Where the beams sit along one eave, in inches from that edge's start.
    # PURE, pinned by rt84.
    #
    # `margin` is dead ground at BOTH ends, and it is not decoration - it is
    # where the wall stops. `poly` is the wall line pushed OUT by the
    # overhang, so at an outside corner the last overhang of each edge hangs
    # over thin air: the wall corner is that far back along the edge. A tail
    # placed there comes out of the fascia and touches nothing, which is
    # what the user saw on 2026-08-25: "יוצא מהפשייה ולא נוגע בקיר... נשאר
    # באוויר". So the caller passes overhang + half a beam and the last tail
    # lands exactly on the wall corner, never past it.
    # What is left over is shared evenly between the two ends, so the run
    # reads as centred instead of crowding one corner.
    def self.beam_centers(len, spacing, width, margin)
      l = len.to_f
      sp = spacing.to_f
      w = width.to_f
      mg = margin.to_f
      return [] if sp < w || w <= 0.0
      mg = w if mg < w
      usable = l - 2.0 * mg
      return [] if usable < 0.0
      n = (usable / sp).floor + 1
      start = mg + (usable - (n - 1) * sp) / 2.0
      (0...n).map { |i| start + i * sp }
    end

    # The four plan corners of one beam. PURE, pinned by rt84.
    # a = the edge's start, d = along the edge, nrm = outward from it.
    def self.beam_quad(a, d, nrm, t, half, k_in, k_out)
      at = lambda do |tt, k|
        [a[0] + d[0] * tt + nrm[0] * k, a[1] + d[1] * tt + nrm[1] * k]
      end
      [at.call(t - half, k_in), at.call(t + half, k_in),
       at.call(t + half, k_out), at.call(t - half, k_out)]
    end

    # The tails themselves. They run the same k range the flat board would
    # have covered - back at the wall, out to the fascia - and hang from the
    # slab underside, so nothing pokes through the deck: going inward the
    # roof only climbs away from them.
    # GABLED EDGES ARE SKIPPED, exactly as the fascia and the flat band skip
    # them. A rake wants sloped lookouts, which is its own round.
    def self.build_eave_beams!(grp, poly, k_in, k_out, band_top, skip_flags)
      spec = beam_spec
      half = spec[:w] / 2.0
      z_top = band_top.to_f
      z_bot = z_top - spec[:h]
      poly.each_index do |i|
        next if skip_flags && skip_flags[i]
        a = poly[i]
        b = poly[(i + 1) % poly.length]
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        len = Math.sqrt(dx * dx + dy * dy)
        next if len < 1.0e-6
        d = [dx / len, dy / len]
        nrm = [d[1], -d[0]] # outward for CCW
        # k_in IS -overhang (soffit_band builds it that way), so the wall
        # corner sits that far in from each end of this edge.
        margin = -k_in.to_f + half
        beam_centers(len, spec[:spacing], spec[:w], margin).each do |t|
          add_prism!(grp.entities, beam_quad(a, d, nrm, t, half, k_in, k_out),
                     z_top, z_bot)
        end
      end
    rescue StandardError => e
      puts "[Roof] build_eave_beams!: #{e.message}"
    end

    def self.add_prism!(ents, quad, z_top, z_bot)
      top = quad.map { |p| Geom::Point3d.new(p[0], p[1], z_top) }
      bot = quad.map { |p| Geom::Point3d.new(p[0], p[1], z_bot) }
      ents.add_face(top)
      ents.add_face(bot)
      4.times do |i|
        j = (i + 1) % 4
        ents.add_face([top[i], top[j], bot[j], bot[i]])
      end
    end

    def self.remove_all!
      model = Sketchup.active_model
      rs = roofs
      return 0 if rs.empty?
      model.start_operation('InteriorPro Remove Roof', true)
      rs.each { |r| r.erase! if r.valid? }
      model.commit_operation
      puts "[Roof] removed #{rs.length} roof(s)"
      rs.length
    rescue StandardError => e
      model.abort_operation rescue nil
      puts "[Roof] remove_all! failed: #{e.message}"
      0
    end
  end
end
