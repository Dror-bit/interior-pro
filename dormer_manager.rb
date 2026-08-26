# dormer_manager.rb - THE DORMER BODY (2026-09-01, step 1 of 5).
#
# STEP 1 IS THE BODY ONLY: a front wall, two cheek walls and the two
# roof planes of a GABLE dormer, built from numbers. It does NOT cut the
# main roof (step 2), it has no placing tool (step 3) and no dialog
# (step 4). Nothing in roof_manager.rb is touched.
#
# THE ONE RULE THAT FIXES EVERY HEIGHT
# The dormer dies INTO the main roof at the back of its own length:
#   ridge z = roof z at (setback + length)
# so the user types the two sizes he asked for - WIDTH across the roof
# and LENGTH into it - and the front wall height falls out of the maths
# instead of being a fourth number that can disagree with the other
# three. The dormer pitch defaults to the main roof's own pitch.
#
# BOARDS MEET, THEY NEVER RUN INSIDE EACH OTHER (CLAUDE.md).
# The roof slab owns the space from its underside up. Every wall - front
# and cheeks - stops exactly on that underside, so no two solids share a
# cubic inch. tests/rt95.rb pins it.
#
# THE FRAME
# All maths happens in the roof's own 2D frame and is turned into world
# points at the last moment:
#   s = distance from the EAVE LINE, horizontally, into the roof
#   w = distance from the dormer's centre line, along the eave
#   z = height. The main roof surface is z0 + s * slope.
module InteriorPro
  module DormerManager
    DEFAULT_SETBACK   = 36.0 unless const_defined?(:DEFAULT_SETBACK, false)
    DEFAULT_WIDTH     = 48.0 unless const_defined?(:DEFAULT_WIDTH, false)
    DEFAULT_LENGTH    = 96.0 unless const_defined?(:DEFAULT_LENGTH, false)
    DEFAULT_WALL_TH   =  5.0 unless const_defined?(:DEFAULT_WALL_TH, false)
    DEFAULT_ROOF_TH   =  0.5 unless const_defined?(:DEFAULT_ROOF_TH, false)
    # A face wall shorter than this has no room for a window, and a
    # dormer whose cheeks are shorter than this is a bump, not a dormer.
    MIN_FACE_HEIGHT   = 12.0 unless const_defined?(:MIN_FACE_HEIGHT, false)
    MIN_CHEEK_RUN     =  6.0 unless const_defined?(:MIN_CHEEK_RUN, false)

    # ---------- the maths (no SketchUp at all, so rt95 can read it) ----
    #
    # spec keys (inches, all optional except slope):
    #   z0:       roof surface height at the eave line
    #   slope:    main roof rise per 1 of run
    #   setback:  eave line -> dormer front wall (0 = flush with the wall)
    #   width:    across the roof, outside face to outside face
    #   length:   front wall -> where the RIDGE dies into the main roof
    #   pitch:    dormer roof rise per 1 of run (default: the main slope)
    #   thickness / roof_thickness
    #
    # Returns a hash of numbers, or nil when the sizes cannot make a
    # dormer (and says why, once, in the console).
    def self.frame(spec = {})
      slope = spec[:slope].to_f
      return warn_nil('the main roof has no slope') if slope <= 0.0

      z0      = spec.fetch(:z0, 0.0).to_f
      setback = spec.fetch(:setback, DEFAULT_SETBACK).to_f
      width   = spec.fetch(:width,   DEFAULT_WIDTH).to_f
      length  = spec.fetch(:length,  DEFAULT_LENGTH).to_f
      pitch   = spec.fetch(:pitch, slope).to_f
      th      = spec.fetch(:thickness, DEFAULT_WALL_TH).to_f
      rt      = spec.fetch(:roof_thickness, DEFAULT_ROOF_TH).to_f
      return warn_nil('width and length must both be positive') if
        width <= 0.0 || length <= 0.0
      return warn_nil('the dormer roof has no pitch') if pitch <= 0.0
      return warn_nil('setback cannot be negative') if setback < 0.0

      half     = width / 2.0
      s_front  = setback
      s_ridge  = setback + length          # the ridge dies here
      z_front  = z0 + s_front * slope      # roof surface at the front wall
      z_ridge  = z0 + s_ridge * slope
      z_eave   = z_ridge - half * pitch    # the dormer's own side eaves
      height   = z_eave - z_front          # front wall, what falls out

      return warn_nil(format('too short: the front wall comes out %.1f" - ' \
                             'make it longer, or the roof flatter', height)) if
        height < MIN_FACE_HEIGHT

      # where the side eave line (level, at z_eave) meets the main roof,
      # and where the cheek's TOP (the roof underside) meets it - the
      # cheek is the shorter of the two, because it stops under the slab.
      s_eave  = (z_eave - z0) / slope
      s_cheek = (z_eave - rt - z0) / slope
      return warn_nil('too long for its width: the cheeks never leave ' \
                      'the roof') if s_cheek - s_front < MIN_CHEEK_RUN

      { z0: z0, slope: slope, pitch: pitch, setback: setback,
        width: width, length: length, half: half,
        thickness: th, roof_thickness: rt,
        s_front: s_front, s_ridge: s_ridge, s_eave: s_eave, s_cheek: s_cheek,
        z_front: z_front, z_ridge: z_ridge, z_eave: z_eave, height: height }
    end

    def self.warn_nil(msg)
      puts "[Dormer] #{msg}"
      nil
    end

    # The main roof surface, and the height of the dormer roof's TOP
    # surface over the centre line offset w.
    def self.roof_z(fr, s);  fr[:z0] + s * fr[:slope]; end
    def self.top_z(fr, w);   fr[:z_ridge] - w.abs * fr[:pitch]; end

    # ---------- plan shapes, still pure --------------------------------
    #
    # One side of the dormer roof, in (s, w): front edge, out to the
    # eave, back along the VALLEY to the ridge die-in point. Both valley
    # ends sit exactly on the main roof surface, which is what makes the
    # cut in step 2 a straight line.
    def self.roof_plan(fr, sign)
      w = fr[:half] * sign
      [[fr[:s_front], 0.0], [fr[:s_front], w], [fr[:s_eave], w],
       [fr[:s_ridge], 0.0]]
    end

    # ---------- building it --------------------------------------------
    #
    # ents:   where the dormer group goes (a model's or a group's entities)
    # spec:   frame() spec, plus the placing:
    #   base:  [x, y] on the EAVE LINE, under the dormer's centre
    #   along: [dx, dy] unit vector along the eave
    #   into:  [dx, dy] unit vector into the roof (default: left of along)
    #   wall_names: [exterior, interior] material names, optional
    #   roof_material: a Sketchup material for the slab, optional
    def self.build_dormer!(ents, spec = {})
      fr = frame(spec)
      return nil if fr.nil?

      base  = spec.fetch(:base, [0.0, 0.0])
      along = unit(spec.fetch(:along, [1.0, 0.0]))
      into  = spec[:into] ? unit(spec[:into]) : [-along[1], along[0]]
      return warn_nil('along and into must not be parallel') if
        (along[0] * into[0] + along[1] * into[1]).abs > 0.001
      at = at_lambda(spec)

      grp = ents.add_group
      grp.name = 'InteriorPro_Dormer'
      grp.set_attribute('InteriorPro', 'type', 'dormer')
      grp.set_attribute('InteriorPro', 'style', 'gable')
      %i[setback width length pitch thickness roof_thickness].each do |k|
        grp.set_attribute('InteriorPro', k.to_s, fr[k])
      end
      grp.set_attribute('InteriorPro', 'base_xy', [base[0], base[1]])
      grp.set_attribute('InteriorPro', 'along_xy', along)
      grp.set_attribute('InteriorPro', 'height', fr[:height])

      build_front_wall!(grp, fr, at, spec[:wall_names])
      [1.0, -1.0].each { |sg| build_cheek!(grp, fr, at, sg, spec[:wall_names]) }
      [1.0, -1.0].each { |sg| build_roof_plane!(grp, fr, at, sg, spec[:roof_material]) }
      grp
    rescue StandardError => e
      puts "[Dormer] build_dormer!: #{e.class}: #{e.message}"
      puts e.backtrace.first(5) if e.backtrace
      nil
    end

    # Where a dormer point lands in the world. Kept public so the cut can
    # use the SAME placing the body was built with - one place, one frame.
    def self.at_lambda(spec)
      base  = spec.fetch(:base, [0.0, 0.0])
      along = unit(spec.fetch(:along, [1.0, 0.0]))
      into  = spec[:into] ? unit(spec[:into]) : [-along[1], along[0]]
      lambda do |s, w, z|
        Geom::Point3d.new(base[0] + into[0] * s + along[0] * w,
                          base[1] + into[1] * s + along[1] * w, z)
      end
    end

    # ---------- ON A REAL ROOF ------------------------------------------
    #
    # Everything above works in the dormer's own frame. This is what
    # turns a REAL roof into that frame: the roof plane itself is
    # measured off the deck face under the point, so the dormer inherits
    # the roof's true pitch and height with nothing typed in.
    #
    # roof: a RoofManager roof group. x, y: where on it, in plan.
    def self.roof_frame(roof, x, y)
      face = roof.entities.grep(Sketchup::Face).select do |f|
        f.normal.z > 0.2 && covers_point?(f, x, y)
      end.max_by { |f| face_points(f).map(&:z).max }
      return warn_nil('no roof surface under that point') if face.nil?

      n = face.normal
      # the plane falls fastest along (n.x, n.y); up the slope is the
      # other way about.
      gx = -n.x / n.z
      gy = -n.y / n.z
      slope = Math.sqrt(gx * gx + gy * gy)
      return warn_nil('that part of the roof is flat') if slope < 0.02
      into = [gx / slope, gy / slope]
      along = [-into[1], into[0]]

      # the eave line of this face: its lowest edge. The dormer's setback
      # is measured from there, which is how a builder measures it.
      pts = face_points(face)
      lowest = nil
      pts.each_with_index do |p, i|
        q = pts[(i + 1) % pts.length]
        avg = (p.z + q.z) / 2.0
        lowest = [avg, p, q] if lowest.nil? || avg < lowest[0]
      end
      e0 = lowest[1]
      # slide the click back onto that line, along the fall
      s_click = (x - e0.x) * into[0] + (y - e0.y) * into[1]
      base = [x - into[0] * s_click, y - into[1] * s_click]
      z_at = plane_z_lambda(face)
      { base: base, along: along, into: into,
        z0: z_at.call(base[0], base[1]), slope: slope }
    end

    # Put one dormer on a real roof, at (x, y) in plan.
    def self.place_on_roof!(roof, x, y, spec = {})
      rf = roof_frame(roof, x, y)
      return nil if rf.nil?
      add_dormer!(roof.entities, spec.merge(rf))
    end

    # One line for the console: a dormer in the middle of the biggest
    # slope of the first roof in the model.
    def self.demo_on_roof!(width: DEFAULT_WIDTH, length: DEFAULT_LENGTH,
                           setback: DEFAULT_SETBACK)
      model = Sketchup.active_model
      roof = InteriorPro::RoofManager.roofs.first
      return warn_nil('there is no roof in this model') if roof.nil?
      face = roof.entities.grep(Sketchup::Face)
                 .select { |f| f.normal.z > 0.2 }.max_by(&:area)
      return warn_nil('that roof has no sloping surface') if face.nil?
      pts = face_points(face)
      cx = pts.map(&:x).inject(:+) / pts.length
      cy = pts.map(&:y).inject(:+) / pts.length
      model.start_operation('Dormer', true)
      g = place_on_roof!(roof, cx, cy, width: width, length: length,
                                       setback: setback)
      model.commit_operation
      puts(g ? "[Dormer] placed on roof at (#{cx.round(1)}, #{cy.round(1)})"
             : '[Dormer] nothing was placed')
      g
    end

    # Body + hole in one call: what a placing tool will use.
    def self.add_dormer!(roof_ents, spec = {})
      fr = frame(spec)
      return nil if fr.nil?
      grp = build_dormer!(roof_ents, spec)
      return nil if grp.nil?
      cut = cut_roof!(roof_ents, fr, at_lambda(spec))
      grp.set_attribute('InteriorPro', 'roof_cut', cut)
      puts "[Dormer] roof skins cut: #{cut}"
      grp
    end

    # The gable face: a pentagon that stops on the UNDERSIDE of its own
    # roof - the slab owns everything above that line.
    def self.build_front_wall!(grp, fr, at, names)
      rt   = fr[:roof_thickness]
      half = fr[:half]
      s_o  = fr[:s_front]
      s_i  = fr[:s_front] + fr[:thickness]
      prof = [[-half, fr[:z_front]], [half, fr[:z_front]],
              [half, fr[:z_eave] - rt], [0.0, fr[:z_ridge] - rt],
              [-half, fr[:z_eave] - rt]]
      sub = new_part!(grp, 'InteriorPro_DormerWall', 'dormer_front')
      outer = prof.map { |w, z| at.call(s_o, w, z) }
      inner = prof.map { |w, z| at.call(s_i, w, z) }
      add_face!(sub, outer)
      add_face!(sub, inner.reverse)
      prof.length.times do |i|
        j = (i + 1) % prof.length
        add_face!(sub, [outer[i], outer[j], inner[j], inner[i]])
      end
      paint_wall!(sub, names)
      sub
    end

    # A cheek is a right triangle in section: the front edge stands, the
    # top runs level under the slab, the bottom rides the main roof up
    # until the two meet.
    def self.build_cheek!(grp, fr, at, sign, names)
      rt   = fr[:roof_thickness]
      w_o  = fr[:half] * sign
      w_i  = w_o - fr[:thickness] * sign
      z_top = fr[:z_eave] - rt
      tri = [[fr[:s_front], fr[:z_front]], [fr[:s_front], z_top],
             [fr[:s_cheek], z_top]]
      sub = new_part!(grp, 'InteriorPro_DormerWall', 'dormer_cheek')
      outer = tri.map { |s, z| at.call(s, w_o, z) }
      inner = tri.map { |s, z| at.call(s, w_i, z) }
      add_face!(sub, outer)
      add_face!(sub, inner.reverse)
      tri.length.times do |i|
        j = (i + 1) % tri.length
        add_face!(sub, [outer[i], outer[j], inner[j], inner[i]])
      end
      paint_wall!(sub, names)
      sub
    end

    # One slope of the dormer roof: a slab of roof_thickness measured
    # straight down, so its underside meets the main roof's underside on
    # the same valley line the top surfaces meet on.
    def self.build_roof_plane!(grp, fr, at, sign, mat)
      rt   = fr[:roof_thickness]
      plan = roof_plan(fr, sign)
      sub  = new_part!(grp, 'InteriorPro_DormerRoof', 'dormer_roof')
      top  = plan.map { |s, w| at.call(s, w, top_z(fr, w)) }
      bot  = plan.map { |s, w| at.call(s, w, top_z(fr, w) - rt) }
      add_face!(sub, top)
      add_face!(sub, bot.reverse)
      plan.length.times do |i|
        j = (i + 1) % plan.length
        add_face!(sub, [top[i], top[j], bot[j], bot[i]])
      end
      if mat
        sub.entities.grep(Sketchup::Face).each do |f|
          f.material = mat
          f.back_material = mat
        end
      end
      sub
    end

    # ---------- STEP 2: the hole in the main roof -----------------------
    #
    # THE ROUGH OPENING, in (s, w), inside the walls: the front wall's
    # inner face, the two cheeks' inner faces, and at the back the VALLEY
    # itself - the line where the dormer's roof dies into the main one.
    # Past that line there is no dormer above the hole any more, so that
    # is exactly where the hole has to stop.
    def self.opening_plan(fr)
      th = fr[:thickness]
      hw = fr[:half] - th
      return nil if hw <= 0.5
      s0 = fr[:s_front] + th
      # the valley in plan runs from the ridge die-in point straight out
      # to the eave die-in point at the full half width.
      s_v = lambda do |w|
        fr[:s_ridge] + (fr[:s_eave] - fr[:s_ridge]) * (w.abs / fr[:half])
      end
      return nil if s_v.call(hw) <= s0 + 0.5
      [[s0, -hw], [s0, hw], [s_v.call(hw), hw],
       [fr[:s_ridge], 0.0], [s_v.call(-hw), -hw]]
    end

    # Cut that opening through the roof slab the dormer stands on.
    #
    # ents: the entities the roof's own faces live in (the roof group's).
    # The slab is two skins - the deck on top and its underside - so the
    # same ring is dropped on BOTH, each on its own plane, the inner face
    # is erased, and the rim between the two rings is closed. Nothing
    # else in the roof is touched.
    #
    # Returns how many skins it cut (2 on a normal slab, 1 on a bare
    # surface, 0 when the dormer is not over this roof at all).
    def self.cut_roof!(ents, fr, at, mat = nil)
      plan = opening_plan(fr)
      return 0 if plan.nil?
      # the plan ring as flat world points, and its centre for the test
      flat = plan.map { |s, w| at.call(s, w, 0.0) }
      cx = flat.map(&:x).inject(:+) / flat.length
      cy = flat.map(&:y).inject(:+) / flat.length

      skins = ents.grep(Sketchup::Face).select do |f|
        next false if f.normal.z.abs < 0.2
        covers_point?(f, cx, cy)
      end
      return 0 if skins.empty?

      rings = []
      skins.each do |f|
        z_at = plane_z_lambda(f)
        next if z_at.nil?
        mat ||= f.material
        ring = plan.map { |s, w| q = at.call(s, w, 0.0); at.call(s, w, z_at.call(q.x, q.y)) }
        # drawing the ring on the skin SPLITS it - that is what makes the
        # hole possible. The piece inside is erased in the sweep below,
        # not here: SketchUp fills a closed coplanar loop again the
        # moment the rim edges arrive, so erasing early erases nothing
        # (the user, 2026-09-01: "אני לא רואה פתח").
        begin
          ents.add_face(ring)
        rescue StandardError
          next
        end
        rings << ring
      end
      return 0 if rings.empty?

      # close the slab's cut edge between the two skins
      if rings.length >= 2
        top, bot = rings.sort_by { |r| -r.map(&:z).max }
        top.length.times do |i|
          j = (i + 1) % top.length
          q = begin
            ents.add_face([top[i], top[j], bot[j], bot[i]])
          rescue StandardError
            nil
          end
          next unless q && mat
          q.material = mat
          q.back_material = mat
        end
      end

      # THE SWEEP. Anything flat still lying over the opening goes - the
      # pieces the ring cut out, and any face SketchUp healed back over
      # them while the rim was being built.
      doomed = ents.grep(Sketchup::Face).select do |f|
        next false if f.normal.z.abs < 0.2
        pts = face_points(f)
        next false if pts.length < 3
        pts.all? { |p| in_plan?(plan, at, p.x, p.y, -0.05) }
      end
      doomed.each { |f| f.erase! if f.respond_to?(:erase!) && f.valid? }
      left = ents.grep(Sketchup::Face).count do |f|
        f.valid? && f.normal.z.abs > 0.2 &&
          face_points(f).all? { |p| in_plan?(plan, at, p.x, p.y) }
      end
      puts "[Dormer] cut: #{rings.length} skin(s), #{doomed.length} piece(s) " \
           "removed, #{left} still over the hole"
      rings.length
    rescue StandardError => e
      puts "[Dormer] cut_roof!: #{e.class}: #{e.message}"
      0
    end

    # Is (x, y) inside the opening, seen from above? A point sitting ON
    # the ring counts as inside - the corners of the cut-out pieces are
    # exactly there - so `slack` is how far outside still counts.
    def self.in_plan?(plan, at, x, y, slack = -0.05)
      ring = plan.map { |s, w| q = at.call(s, w, 0.0); [q.x, q.y] }
      return true if point_in_ring?(ring, x, y)
      ring_distance(ring, x, y) <= slack.abs
    end

    def self.point_in_ring?(ring, x, y)
      inside = false
      n = ring.length
      n.times do |i|
        ax, ay = ring[i]
        bx, by = ring[(i + 1) % n]
        next if (ay > y) == (by > y)
        xx = (bx - ax) * (y - ay) / (by - ay) + ax
        inside = !inside if x < xx
      end
      inside
    end

    def self.ring_distance(ring, x, y)
      best = nil
      n = ring.length
      n.times do |i|
        ax, ay = ring[i]
        bx, by = ring[(i + 1) % n]
        dx = bx - ax
        dy = by - ay
        len2 = dx * dx + dy * dy
        t = len2 < 1.0e-9 ? 0.0 : (((x - ax) * dx + (y - ay) * dy) / len2)
        t = 0.0 if t < 0.0
        t = 1.0 if t > 1.0
        d = Math.sqrt((x - (ax + dx * t))**2 + (y - (ay + dy * t))**2)
        best = d if best.nil? || d < best
      end
      best || 1.0e9
    end

    # Is (x, y) inside this face, seen from above? Pure ray casting on
    # the face's own outline - no SketchUp classify call, so the stub can
    # run it too.
    def self.covers_point?(f, x, y)
      pts = face_points(f)
      return false if pts.length < 3
      inside = false
      n = pts.length
      n.times do |i|
        a = pts[i]
        b = pts[(i + 1) % n]
        next if (a.y > y) == (b.y > y)
        xx = (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x
        inside = !inside if x < xx
      end
      inside
    end

    def self.face_points(f)
      if f.respond_to?(:pts) && f.pts
        Array(f.pts)
      else
        f.vertices.map(&:position)
      end
    end

    # z of a face's plane at (x, y), or nil for a vertical face.
    def self.plane_z_lambda(f)
      n = f.normal
      return nil if n.z.abs < 1.0e-6
      p0 = face_points(f).first
      return nil if p0.nil?
      lambda do |x, y|
        p0.z - (n.x * (x - p0.x) + n.y * (y - p0.y)) / n.z
      end
    end

    # ---------- small helpers ------------------------------------------
    def self.new_part!(grp, name, part)
      sub = grp.entities.add_group
      sub.name = name
      sub.set_attribute('InteriorPro', 'part', part)
      sub
    end

    def self.add_face!(sub, pts)
      clean = []
      pts.each do |p|
        clean << p if clean.empty? || clean.last.distance(p) > 0.01
      end
      clean.pop while clean.length > 1 && clean.first.distance(clean.last) < 0.01
      return nil if clean.length < 3
      sub.entities.add_face(clean)
    rescue StandardError
      nil
    end

    def self.paint_wall!(sub, names)
      return if names.nil?
      ext_name, int_name = names
      return unless ext_name || int_name
      return unless defined?(InteriorPro::WallTool) &&
                    InteriorPro::WallTool.respond_to?(:new)
      wt = InteriorPro::WallTool.new
      m = wt.load_or_create_material(ext_name || int_name)
      return unless m
      sub.entities.grep(Sketchup::Face).each do |f|
        f.material = m
        f.back_material = m
      end
    rescue StandardError => e
      puts "[Dormer] paint_wall!: #{e.message}"
    end

    def self.unit(v)
      len = Math.sqrt(v[0].to_f**2 + v[1].to_f**2)
      len < 1.0e-9 ? [1.0, 0.0] : [v[0] / len, v[1] / len]
    end
  end
end
