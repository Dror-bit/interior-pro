# encoding: utf-8
# Interior Pro - roof_tile_place.rb  (2026-08-19)
#
# WHERE the tile pieces go. Step 4 of ROOF_TILES_PROPOSAL.md: the eave course,
# and nothing else yet.
#
# THIS FILE BUILDS NO GEOMETRY. Not one face. roof_tile_parts.rb owns the four
# definitions, roof_manager.rb owns the roof, roof_tile_math.rb owns the
# spacing. All that is left here is arithmetic - a Geom::Transformation per
# slot - and one call to add_instance.
#
# WHY THAT MATTERS, in the user's own words: avoid thousands of unique groups.
# Instant Roof's 63x59ft roof carries 408 instances of ONE single-face
# definition (valiroof_report.txt). Everything below exists so our eave reads
# the same way: one definition, a few hundred instances.
#
# THE FRAME. RoofTileMath.plane_frame gives every roof plane its own axes -
# u across the slope, v up it, n out of it - and roof_tile_parts models each
# piece in exactly that frame (+X across, +Y up, +Z out, origin on the roof
# plane at the middle of the piece's lower edge). So placing one is
# Geom::Transformation.axes(origin, u, v, n) and there is no world-axis
# assumption anywhere in this file.
#
# THE HEIGHT, and this one is a real trap. RoofManager.roof_edges reads its z
# from `zmap`, which is the UNDERSIDE of the slab - that is what the fascia and
# the rake boards are hung from, deliberately. The tiles have to sit on the
# TOP. So the z of a slot is NOT taken from the edge: the edge gives x and y,
# and the height is solved on the plane of the roof face itself. Match the
# plane in PLAN, take the height from the plane.

module InteriorPro
  module RoofTilePlace
    # Over this many pieces the eave keeps the texture alone and says so -
    # the same brake, and the same manners, as MAX_RIDGE_CAP_PIECES.
    def self.max_instances
      4000
    end

    def self.eave_tag
      'InteriorPro_RoofTiles_Edge'
    end

    # How close, in plan, a roof face's own edge has to be to an eave segment
    # before we call them the same edge. They come from the same polygon, so
    # this is tight on purpose - a loose match would silently borrow the
    # neighbouring plane's slope.
    def self.plan_tol
      0.75
    end

    # ------------------------------------------------------------------ pure
    #
    # A roof face, reduced to the two things this file needs.
    # Faces that cannot carry a tile - vertical ones (the slab edge, a tear
    # face) and degenerate ones - drop out here rather than being special
    # cased three times below.
    def self.planes_from_faces(faces)
      out = []
      (faces || []).each do |f|
        pts = face_points(f)
        next if pts.nil? || pts.length < 3
        nrm = face_normal(f)
        next if nrm.nil?
        fr = InteriorPro::RoofTileMath.plane_frame(nrm)
        next if fr.nil? || fr[:flat]
        out << { points: pts, normal: fr[:n], u: fr[:u], v: fr[:v], n: fr[:n] }
      end
      out
    end

    def self.face_points(f)
      pts = if f.respond_to?(:pts) && f.pts
              f.pts
            elsif f.respond_to?(:vertices)
              f.vertices.map(&:position)
            end
      return nil if pts.nil?
      pts.map { |p| p.respond_to?(:x) ? [p.x.to_f, p.y.to_f, p.z.to_f] : p.map(&:to_f) }
    rescue StandardError
      nil
    end

    def self.face_normal(f)
      n = f.respond_to?(:normal) ? f.normal : nil
      return nil if n.nil?
      [n.x.to_f, n.y.to_f, n.z.to_f]
    rescue StandardError
      nil
    end

    # Distance in PLAN from point x to the segment p-q. Plan, not space:
    # see the header - the eave carries the underside height and the face
    # carries the top one, and they are a slab thickness apart.
    def self.plan_dist_to_segment(p, q, x)
      dx = q[0] - p[0]
      dy = q[1] - p[1]
      ll = (dx * dx) + (dy * dy)
      return Math.hypot(x[0] - p[0], x[1] - p[1]) if ll < 1.0e-12
      t = (((x[0] - p[0]) * dx) + ((x[1] - p[1]) * dy)) / ll
      t = 0.0 if t < 0.0
      t = 1.0 if t > 1.0
      Math.hypot(x[0] - (p[0] + (dx * t)), x[1] - (p[1] + (dy * t)))
    end

    # Which roof plane does this eave segment belong to? The plane whose own
    # outline carries it, in plan. Both ends must be on the SAME boundary
    # segment, so a plane that merely passes nearby is not accepted.
    def self.plane_for(planes, a, b, tol = plan_tol)
      (planes || []).each do |pl|
        pts = pl[:points]
        m = pts.length
        m.times do |i|
          p = pts[i]
          q = pts[(i + 1) % m]
          next if Math.hypot(q[0] - p[0], q[1] - p[1]) < 1.0e-6
          next if plan_dist_to_segment(p, q, a) > tol
          next if plan_dist_to_segment(p, q, b) > tol
          return pl
        end
      end
      nil
    end

    # The height of (x, y) ON a plane. nz can never be 0 here: plane_frame
    # already refused every vertical face.
    def self.z_on_plane(pl, x, y)
      p0 = pl[:points][0]
      n = pl[:n]
      return nil if n[2].abs < 1.0e-9
      p0[2] - (((n[0] * (x - p0[0])) + (n[1] * (y - p0[1]))) / n[2])
    end

    # THE PURE ANSWER: one entry per tile, before anything is placed.
    #
    #   planes  from planes_from_faces(top_shell)
    #   edges   from RoofManager.roof_edges
    #   shape   'barrel' / 'roman' / 'slate' / 'seam'
    #
    # Returns [{ origin: [x, y, z], u:, v:, n:, edge:, wall_id: }, ...].
    # A partial tile at either end of a run gets nothing - RoofTileMath
    # .edge_slots already refuses it, and half a tile poking past a corner
    # looks worse than none.
    def self.eave_slots(planes, edges, shape_name, opts = {})
      shape = InteriorPro::RoofTileMath.shape(shape_name)
      return [] if shape.nil?
      tile_w = shape[:tile_w].to_f
      return [] if tile_w <= 1.0e-9
      segs = (edges && edges[:eave]) || []
      margin = (opts[:margin] || 0.0).to_f
      out = []
      segs.each do |e|
        a = e[:a]
        b = e[:b]
        next if a.nil? || b.nil?
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        len = Math.hypot(dx, dy) # the eave is horizontal, so plan length IS length
        next if len < tile_w
        pl = plane_for(planes, a, b)
        next if pl.nil?
        ux = dx / len
        uy = dy / len
        InteriorPro::RoofTileMath.edge_slots(0.0, len, tile_w, margin: margin).each do |c|
          x = a[0] + (ux * c)
          y = a[1] + (uy * c)
          z = z_on_plane(pl, x, y)
          next if z.nil?
          out << { origin: [x, y, z], u: pl[:u], v: pl[:v], n: pl[:n],
                   edge: e[:edge], wall_id: e[:wall_id] }
        end
      end
      out
    end

    # ---------------------------------------------------------------- impure
    #
    # One add_instance per slot, into the ROOF group, so the next rebuild
    # replaces them exactly the way it replaces the ridge caps.
    # Returns how many pieces were placed.
    def self.place_eaves!(grp, planes, edges, shape_name, opts = {})
      return 0 if grp.nil?
      slots = eave_slots(planes, edges, shape_name, opts)
      return 0 if slots.empty?
      cap = (opts[:max] || max_instances).to_i
      if slots.length > cap
        puts "[RoofTiles] #{slots.length} eave pieces is over the #{cap} budget " \
             '- leaving the eave with its texture only'
        return 0
      end
      model = opts[:model] || Sketchup.active_model
      defn = InteriorPro::RoofTileParts.eave(model, shape_name)
      if defn.nil?
        puts "[RoofTiles] no eave definition for #{shape_name}"
        return 0
      end
      tag = opts[:tag] || eave_tag
      mat = opts[:material]
      made = 0
      slots.each do |s|
        tr = transform_for(s)
        next if tr.nil?
        inst = grp.entities.add_instance(defn, tr)
        next if inst.nil?
        begin
          inst.material = mat if mat
        rescue StandardError
          nil
        end
        InteriorPro.assign_tag(inst, tag)
        made += 1
      end
      puts "[RoofTiles] eave: #{made} instances of #{defn.name}"
      made
    end

    def self.transform_for(s)
      o = Geom::Point3d.new(s[:origin][0], s[:origin][1], s[:origin][2])
      Geom::Transformation.axes(o, vec(s[:u]), vec(s[:v]), vec(s[:n]))
    rescue StandardError => e
      puts "[RoofTiles] transform: #{e.message}"
      nil
    end

    def self.vec(a)
      Geom::Vector3d.new(a[0], a[1], a[2])
    end
  end
end
