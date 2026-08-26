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
    # THE OVERHANG (2026-09-02, the user: "אני לא רואה בכלל אוברהנג").
    # The roof slab hangs this far PAST the walls on all three open
    # sides - out over the cheeks (the eaves) and forward past the front
    # wall (the rake) - which is what gives the fascia something to hang
    # off. 0 rebuilds the flush slab every dormer had before today.
    DEFAULT_OVERHANG  =  6.0 unless const_defined?(:DEFAULT_OVERHANG, false)
    # THE TRIM (2026-09-02). Same boards the main roof wears, same
    # sizes, so the dormer reads as part of the house. Kill switch:
    # InteriorPro::DormerManager::USE_DORMER_TRIM = false.
    USE_DORMER_TRIM   = true unless const_defined?(:USE_DORMER_TRIM, false)
    TRIM_THICK        = 0.75 unless const_defined?(:TRIM_THICK, false)
    TRIM_DRIP_THICK   = 0.1  unless const_defined?(:TRIM_DRIP_THICK, false)
    TRIM_DRIP_DEPTH   = 2.0  unless const_defined?(:TRIM_DRIP_DEPTH, false)
    DEFAULT_FASCIA_DEPTH = 8.0 unless const_defined?(:DEFAULT_FASCIA_DEPTH, false)
    DEFAULT_TRIM_COLOR   = '#ffffff' unless const_defined?(:DEFAULT_TRIM_COLOR, false)
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
      oh      = spec.fetch(:overhang, DEFAULT_OVERHANG).to_f
      oh      = 0.0 if oh < 0.0
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

      # THE OVERHANG. The slab keeps its own plane, so hanging it out
      # sideways only makes its outer edge LOWER (w_edge is further from
      # the ridge) and hanging it forward only moves its front edge. The
      # lower outer edge meets the main roof EARLIER - s_valley - which
      # is where the eave, and the fascia under it, have to stop.
      # An overhang wider than the dormer's own half width is not a roof
      # edge any more, it is a canopy - and on a flat-enough pitch it
      # never comes back down to the main roof at all.
      return warn_nil(format('the overhang %.1f" is too big for a %.1f" ' \
                             'wide dormer', oh, width)) if oh > half
      w_edge   = half + oh
      s_rake   = s_front - oh
      z_edge   = z_ridge - w_edge * pitch
      s_valley = (z_edge - z0) / slope
      return warn_nil(format('the overhang is too big: %.1f" of eave would ' \
                             'already be under the roof', oh)) if
        s_valley <= s_rake + 1.0

      # THE DECK COVERS ITS OWN BOARDS (2026-09-02, the user: "הגג שינגלס
      # צריך להגיע עד סוף המטל אדג כמו בצדדים"). The overhang the user
      # types is measured to the FASCIA - w_edge is the fascia's outer
      # face, exactly as a roof's eave polygon is. The shingle deck then
      # runs one fascia plus one metal edge FURTHER out, so it finishes
      # over the metal instead of stopping short of it, which is what
      # RoofManager's own rake_out does on the house.
      d_side      = deck_side
      d_front     = deck_front
      w_deck      = w_edge + d_side
      s_deck      = s_rake - d_front
      z_deck_edge = z_ridge - w_deck * pitch
      s_valley_d  = (z_deck_edge - z0) / slope

      { z0: z0, slope: slope, pitch: pitch, setback: setback,
        width: width, length: length, half: half, overhang: oh,
        thickness: th, roof_thickness: rt,
        s_front: s_front, s_ridge: s_ridge, s_eave: s_eave, s_cheek: s_cheek,
        s_rake: s_rake, s_valley: s_valley, w_edge: w_edge, z_edge: z_edge,
        deck_side: d_side, deck_front: d_front,
        w_deck: w_deck, s_deck: s_deck,
        s_valley_deck: s_valley_d, z_deck_edge: z_deck_edge,
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
      w = fr[:w_deck] * sign
      [[fr[:s_deck], 0.0], [fr[:s_deck], w], [fr[:s_valley_deck], w],
       [fr[:s_ridge], 0.0]]
    end

    # HOW FAR THE SHINGLE DECK RUNS PAST THE FASCIA LINE, so it always
    # finishes ON the metal edge's outer face and never short of it.
    # The two sides are NOT the same, because the boards are not:
    #   EAVE  - the fascia hangs INSIDE the line and only the metal edge
    #           is outside it, so the deck needs one metal thickness.
    #   GABLE - the rake board and its metal edge are both OUTSIDE the
    #           line, so the deck needs a fascia plus a metal edge.
    # That is RoofManager's own rake_out, the same number the house's
    # gables use.
    def self.deck_side
      rm = roof_manager
      rm.nil? ? TRIM_DRIP_THICK : rm::DRIP_THICK
    end

    def self.deck_front
      rm = roof_manager
      return TRIM_THICK + TRIM_DRIP_THICK if rm.nil?
      rm::FASCIA_THICK + rm::DRIP_THICK
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
      %i[setback width length pitch thickness roof_thickness overhang].each do |k|
        grp.set_attribute('InteriorPro', k.to_s, fr[k])
      end
      grp.set_attribute('InteriorPro', 'base_xy', [base[0], base[1]])
      grp.set_attribute('InteriorPro', 'along_xy', along)
      grp.set_attribute('InteriorPro', 'height', fr[:height])

      build_front_wall!(grp, fr, at, spec[:wall_names])
      [1.0, -1.0].each { |sg| build_cheek!(grp, fr, at, sg, spec[:wall_names]) }
      [1.0, -1.0].each { |sg| build_roof_plane!(grp, fr, at, sg, spec[:roof_material]) }
      build_trim!(grp, fr, at, spec) if USE_DORMER_TRIM
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
      roof_mat = face.material
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
      { base: base, along: along, into: into, roof_mat: roof_mat,
        z0: z_at.call(base[0], base[1]), slope: slope }
    end

    # THE DORMER WEARS THE HOUSE (2026-09-02, the user asked for "קירות
    # בטקסטורת קירות הבית" and the roof in the roof's own material).
    # Nothing is typed in: the slab it stands on hands over its own
    # material in roof_frame, and the walls take whatever exterior
    # material most of the house's walls are wearing.
    def self.house_wall_material(model = nil)
      model ||= Sketchup.active_model
      tally = Hash.new(0)
      count_walls(model.entities, tally, 0)
      best = tally.max_by { |_n, c| c }
      best && best.first
    rescue StandardError
      nil
    end

    def self.count_walls(ents, tally, depth)
      ents.grep(Sketchup::Group).each do |g|
        if g.get_attribute('InteriorPro', 'type') == 'wall'
          n = g.get_attribute('InteriorPro', 'exterior_material').to_s
          tally[n] += 1 unless n.empty?
        elsif depth < 2
          count_walls(g.entities, tally, depth + 1)
        end
      end
    end

    # Put one dormer on a real roof, at (x, y) in plan.
    def self.place_on_roof!(roof, x, y, spec = {})
      rf = roof_frame(roof, x, y)
      return nil if rf.nil?
      s = spec.merge(rf)
      s[:roof_material] = rf[:roof_mat] if s[:roof_material].nil?
      if s[:wall_names].nil?
        wm = house_wall_material
        s[:wall_names] = [wm] if wm
      end
      add_dormer!(roof.entities, s)
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

    # THE FRONT CORNERS ARE MITRED (2026-09-02, the user: "הקירות שוב
    # נכנסים אחת בתוך השני במקום ליצור פינות באלכסון"). Until today the
    # front wall ran the FULL width and each cheek ran the full length,
    # so both owned the same block of space at each front corner - the
    # thing CLAUDE.md forbids. Now each wall's INNER face is pulled back
    # by one thickness at that corner, so the two meet on the 45 degree
    # plane w + s = half + s_front and neither crosses it.
    #
    # The gable face: a pentagon that stops on the UNDERSIDE of its own
    # roof - the slab owns everything above that line.
    def self.build_front_wall!(grp, fr, at, names)
      rt   = fr[:roof_thickness]
      half = fr[:half]
      th   = fr[:thickness]
      hi   = half - th                      # the mitre pulls the inner
      return warn_nil('the walls are too thick for this width') if hi <= 0.5
      s_o  = fr[:s_front]
      s_i  = fr[:s_front] + th
      outer_p = [[-half, fr[:z_front]], [half, fr[:z_front]],
                 [half, fr[:z_eave] - rt], [0.0, fr[:z_ridge] - rt],
                 [-half, fr[:z_eave] - rt]]
      inner_p = [[-hi, fr[:z_front]], [hi, fr[:z_front]],
                 [hi, top_z(fr, hi) - rt], [0.0, fr[:z_ridge] - rt],
                 [-hi, top_z(fr, hi) - rt]]
      sub = new_part!(grp, 'InteriorPro_DormerWall', 'dormer_front')
      outer = outer_p.map { |w, z| at.call(s_o, w, z) }
      inner = inner_p.map { |w, z| at.call(s_i, w, z) }
      add_face!(sub, outer)
      add_face!(sub, inner.reverse)
      outer_p.length.times do |i|
        j = (i + 1) % outer_p.length
        add_face!(sub, [outer[i], outer[j], inner[j], inner[i]])
      end
      paint_wall!(sub, names)
      sub
    end

    # A cheek is a right triangle in section: the front edge stands, the
    # top runs level under the slab, the bottom rides the main roof up
    # until the two meet. Its FRONT edge is mitred against the front
    # wall - the inner face starts one thickness further back.
    def self.build_cheek!(grp, fr, at, sign, names)
      rt   = fr[:roof_thickness]
      th   = fr[:thickness]
      w_o  = fr[:half] * sign
      w_i  = w_o - th * sign
      z_top = fr[:z_eave] - rt
      s_i   = fr[:s_front] + th
      outer_p = [[fr[:s_front], fr[:z_front]], [fr[:s_front], z_top],
                 [fr[:s_cheek], z_top]]
      inner_p = [[s_i, roof_z(fr, s_i)], [s_i, z_top], [fr[:s_cheek], z_top]]
      sub = new_part!(grp, 'InteriorPro_DormerWall', 'dormer_cheek')
      outer = outer_p.map { |s, z| at.call(s, w_o, z) }
      inner = inner_p.map { |s, z| at.call(s, w_i, z) }
      add_face!(sub, outer)
      add_face!(sub, inner.reverse)
      outer_p.length.times do |i|
        j = (i + 1) % outer_p.length
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

    # ---------- STEP 3: THE TRIM (2026-09-02) ---------------------------
    #
    # A FASCIA under each eave, a RAKE BOARD up each gable edge, and the
    # METAL EDGE lapping over the top of both. Sizes come from the roof
    # dialog when it is loaded, so the dormer's boards are the house's
    # boards.
    #
    # BOARDS MEET, THEY NEVER RUN INSIDE EACH OTHER (CLAUDE.md).
    # THE RAKE OWNS THE FRONT CORNER. The rake board sits in the slice
    # s_rake-TRIM_THICK .. s_rake, and reaches TRIM_THICK sideways past
    # the slab so it covers the fascia's end grain. The eave fascia
    # therefore STOPS at s_rake - not one thousandth in front of it.
    # At the BACK the fascia is cut on the main roof surface itself: it
    # is a vertical board, the roof climbs into it, so its end is the
    # slanted line where the two planes cross. Nothing is buried.
    def self.fascia_depth(spec)
      d = spec[:fascia_depth]
      if d.nil? && defined?(InteriorPro::RoofManager) &&
         InteriorPro::RoofManager.respond_to?(:settings)
        begin
          d = InteriorPro::RoofManager.settings[:fascia_depth]
        rescue StandardError
          d = nil
        end
      end
      # 0 is a real answer - "no boards" - so only a MISSING depth falls
      # back to the house's own.
      d = DEFAULT_FASCIA_DEPTH if d.nil?
      d.to_f
    end

    def self.trim_color(spec)
      c = spec[:fascia_color]
      if c.nil? && defined?(InteriorPro::RoofManager) &&
         InteriorPro::RoofManager.respond_to?(:settings)
        begin
          c = InteriorPro::RoofManager.settings[:fascia_color]
        rescue StandardError
          c = nil
        end
      end
      c = DEFAULT_TRIM_COLOR if c.nil? || c.to_s.empty?
      c.to_s
    end

    # THE DORMER'S BOARDS ARE THE ROOF'S BOARDS (2026-09-02, the user:
    # "יש לך את התיכנון המדוייק של הפשיה בגייבל ובהיפ... תייסם אותם כמו
    # בגגות!!!"). The first version of this hand-rolled its own fascia
    # and its own corner rule, and got the corner the OTHER way round
    # from every roof in the plugin. Nothing here builds a board any
    # more: the dormer hands RoofManager an outline and a height map and
    # RoofManager's own build_band! and build_rake_board! do the work -
    # so the gable corner, the cut-back rake and the wrapping metal edge
    # are the same ones the house wears, and a fix to either fixes both.
    #
    # THE OUTLINE, in the dormer's own (s, w) frame:
    #   A(s_rake,-w) -> B(s_rake,+w)   the GABLE end (rake boards)
    #   B -> C(s_cut,+w)               the right EAVE  (fascia band)
    #   C -> D(s_ridge,0) -> E         the VALLEY, buried in the main
    #                                  roof: no boards, and no wrap
    #                                  either - exactly an ABUT edge.
    #   E(s_cut,-w) -> A               the left EAVE
    #
    # s_cut is where the climbing main roof reaches the BOTTOM of the
    # fascia. Past it the board would be buried, so it ends there -
    # square, like a roof's rake ends on a covering wing.
    def self.trim_ring(fr, at)
      we = fr[:w_edge]
      sw = [[[fr[:s_rake], -we], 'gable'], [[fr[:s_rake], we], 'eave'],
            [[fr[:s_valley], we], 'valley'], [[fr[:s_ridge], 0.0], 'valley'],
            [[fr[:s_valley], -we], 'eave']]
      pts = sw.map { |(s, w), _| q = at.call(s, w, 0.0); [q.x, q.y] }
      labs = sw.map(&:last)
      n = pts.length
      # build_rake_board! reads its outward normal off a CCW ring. Which
      # way round these five come out depends on the dormer's placing,
      # so measure and flip - carrying each label with its own EDGE, not
      # with a corner (reversing turns edge i into edge n-2-i).
      if signed_area(pts) < 0.0
        pts = pts.reverse
        labs = (0...n).map { |i| labs[(n - 2 - i) % n] }
      end
      { poly: pts, labels: labs, gable: labs.index('gable'),
        level: (0...n).select { |i| labs[i] == 'eave' } }
    end

    def self.signed_area(pts)
      a = 0.0
      n = pts.length
      n.times do |i|
        p = pts[i]
        q = pts[(i + 1) % n]
        a += p[0] * q[1] - q[0] * p[1]
      end
      a / 2.0
    end

    # The height map RoofManager reads the rake's climb from: the slab's
    # UNDERSIDE at every node of the ring, plus the one node that is not
    # a corner at all - the gable's APEX, halfway along the front edge.
    # Without it the front edge would look level and the rake board
    # would come out flat.
    def self.trim_zmap(fr, at)
      rt = fr[:roof_thickness]
      nodes = [[fr[:s_rake], -fr[:w_edge], fr[:z_edge] - rt],
               [fr[:s_rake], 0.0, fr[:z_ridge] - rt],
               [fr[:s_rake], fr[:w_edge], fr[:z_edge] - rt],
               [fr[:s_valley], fr[:w_edge], fr[:z_edge] - rt],
               [fr[:s_valley], -fr[:w_edge], fr[:z_edge] - rt],
               [fr[:s_ridge], 0.0, fr[:z_ridge] - rt]]
      map = {}
      nodes.each do |s, w, z|
        q = at.call(s, w, 0.0)
        map[[q.x, q.y]] = z
      end
      map
    end

    # PURE: one eave board seen from the side, in (s, z).
    #
    # THE BACK END IS A DIAGONAL (2026-09-02, the user: "הפשייה צריך
    # להגיע עד סוף הגג ולהיחתך באלכסון"). The board is vertical and the
    # main roof climbs into it, so the line where the two planes cross
    # is slanted. Cutting it square would either leave the last stretch
    # of eave bare or bury the board's foot in the shingles. This is the
    # one thing RoofManager's own band cannot do - its band is a prism
    # between two heights - so the eave boards are built here and only
    # the rake comes from RoofManager.
    #
    # THE FRONT END STOPS ON THE GABLE LINE (2026-09-02, the user:
    # "הגיבל צריך לבוא לפני האנכי"). THE RAKE OWNS THE CORNER: it runs
    # the full gable edge, out to the fascia's own outer face, and this
    # board dies behind it. The metal edge is the one exception - it
    # WRAPS the corner and finishes on the rake metal's outer face,
    # which is what the house's own drip does (wrap_flags).
    def self.eave_profile(fr, z_top, depth, s0)
      return nil if depth <= 0.0
      z_bot = z_top - depth
      s_t = (z_top - fr[:z0]) / fr[:slope]
      s_b = (z_bot - fr[:z0]) / fr[:slope]
      return nil if s_t <= s0 + 0.5
      return [[s0, z_top], [s_t, z_top], [s_b, z_bot]] if s_b <= s0
      [[s0, z_top], [s_t, z_top], [s_b, z_bot], [s0, z_bot]]
    end

    def self.build_trim!(grp, fr, at, spec = {})
      dep = fascia_depth(spec)
      return false if dep <= 0.0
      rm = roof_manager
      ft = rm ? rm::FASCIA_THICK : TRIM_THICK
      dt = rm ? rm::DRIP_THICK   : TRIM_DRIP_THICK
      dd = rm ? rm::DRIP_DEPTH   : TRIM_DRIP_DEPTH
      mat = trim_material(trim_color(spec))
      z_top = fr[:z_edge] - fr[:roof_thickness]
      we = fr[:w_edge]

      fas = new_part!(grp, 'InteriorPro_DormerFascia', 'dormer_fascia')
      prof = eave_profile(fr, z_top, dep, fr[:s_rake])
      [1.0, -1.0].each do |sg|
        extrude_sz!(fas, prof, at, (we - ft) * sg, we * sg)
      end unless prof.nil?
      paint!(fas, mat)

      drip = new_part!(grp, 'InteriorPro_DormerDrip', 'dormer_drip')
      dprof = eave_profile(fr, z_top, dd, fr[:s_rake] - ft - dt)
      [1.0, -1.0].each do |sg|
        extrude_sz!(drip, dprof, at, we * sg, (we + dt) * sg)
      end unless dprof.nil?

      # THE RAKE IS RoofManager's OWN BOARD - same climb, same cut-back
      # at the corner (rake_meet_span), same metal edge on its face.
      unless rm.nil?
        ring = trim_ring(fr, at)
        gi = ring[:gable]
        unless gi.nil?
          zmap = trim_zmap(fr, at)
          poly = ring[:poly]
          # NO rake_meet_span here: on the house the level fascia owns
          # the corner, on the dormer he wants it the other way about,
          # so the rake runs its WHOLE edge - right out to the eave
          # fascia's outer face - and covers that board's end.
          rake = new_part!(grp, 'InteriorPro_DormerRake', 'dormer_rake')
          rm.build_rake_board!(rake, poly, gi, zmap, dep)
          paint!(rake, mat)
          rm.build_rake_board!(drip, poly, gi, zmap, dd, k_in: ft, k_out: ft + dt)
        end
      end
      paint!(drip, mat)
      true
    rescue StandardError => e
      puts "[Dormer] build_trim!: #{e.class}: #{e.message}"
      puts e.backtrace.first(4) if e.backtrace
      false
    end

    # A profile in (s, z) swept across the width.
    def self.extrude_sz!(sub, prof, at, w_a, w_b)
      a = prof.map { |s, z| at.call(s, w_a, z) }
      b = prof.map { |s, z| at.call(s, w_b, z) }
      add_face!(sub, a)
      add_face!(sub, b.reverse)
      prof.length.times do |i|
        j = (i + 1) % prof.length
        add_face!(sub, [a[i], a[j], b[j], b[i]])
      end
      sub
    end

    def self.roof_manager
      return nil unless defined?(InteriorPro::RoofManager)
      rm = InteriorPro::RoofManager
      return nil unless rm.respond_to?(:build_band!) &&
                        rm.respond_to?(:build_rake_board!) &&
                        rm.respond_to?(:rake_meet_span)
      rm
    end

    def self.trim_material(color)
      return nil unless defined?(InteriorPro::WallTool) &&
                        InteriorPro::WallTool.respond_to?(:new)
      InteriorPro::WallTool.new.load_or_create_material(color)
    rescue StandardError
      nil
    end

    def self.paint!(sub, mat)
      return if mat.nil?
      sub.entities.grep(Sketchup::Face).each do |f|
        f.material = mat
        f.back_material = mat
      end
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
