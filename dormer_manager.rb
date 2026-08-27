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
    # HOW CLOSE TO THE HOUSE RIDGE THE GABLET MAY DIE (2026-09-02, the
    # user: "האורך לתוך הגג לא רלוונטי לי... הוא צריך לעצור אותי נגיד
    # פוט אחד לפני הגובה של הגג"). He types the WALL HEIGHT he wants for
    # the window and the length falls out of it - but a tall enough wall
    # would push the die-in point over the ridge, and there is no roof
    # left up there to die into. One foot of roof stays above it.
    RIDGE_CLEARANCE   = 12.0 unless const_defined?(:RIDGE_CLEARANCE, false)

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

      # THE HEIGHT DRIVES THE LENGTH (2026-09-02). He cares about the
      # wall - a window goes in it - and not about how far the gablet
      # reaches into the roof, so a typed height turns into the length
      # that produces it. Nothing else changes: the gablet still dies
      # into the roof at the end of that length.
      style_now = spec.fetch(:style, 'gable').to_s
      if spec[:height].to_f > 0.0
        h = spec[:height].to_f
        length = if style_now == 'shed'
                   p2 = spec.key?(:pitch) ? spec[:pitch].to_f : slope / 2.0
                   p2 < slope ? h / (slope - p2) : 0.0
                 else
                   (h + (width / 2.0) * pitch) / slope
                 end
        return warn_nil('that height cannot be built on this roof') if
          length <= 0.0
      end

      half     = width / 2.0
      s_front  = setback
      s_ridge  = setback + length          # the ridge dies here
      cap = ridge_cap_check(spec, z0, slope, setback, half, pitch, s_ridge,
                            style_now, width)
      return nil unless cap.nil?
      z_front  = z0 + s_front * slope      # roof surface at the front wall
      z_ridge  = z0 + s_ridge * slope
      style    = style_now
      return shed_frame(spec, z0, slope, setback, width, length, th, rt, oh,
                        half, s_front, s_ridge, z_front, z_ridge) if style == 'shed'
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

      { z0: z0, slope: slope, pitch: pitch, setback: setback, style: 'gable',
        width: width, length: length, half: half, overhang: oh,
        thickness: th, roof_thickness: rt,
        s_front: s_front, s_ridge: s_ridge, s_eave: s_eave, s_cheek: s_cheek,
        s_rake: s_rake, s_valley: s_valley, w_edge: w_edge, z_edge: z_edge,
        deck_side: d_side, deck_front: d_front,
        w_deck: w_deck, s_deck: s_deck,
        s_valley_deck: s_valley_d, z_deck_edge: z_deck_edge,
        z_front: z_front, z_ridge: z_ridge, z_eave: z_eave, height: height }
    end

    # ---------- THE SHED GABLET (2026-09-02) ---------------------------
    #
    # One plane, falling the SAME way the main roof falls but flatter, so
    # it climbs out of the roof instead of into it. Everything the gable
    # rule says still holds - the gablet dies into the roof at the end of
    # its own length, so the front wall height is a RESULT:
    #
    #   height = length * (roof slope - gablet pitch)
    #
    # which is why the pitch must be flatter than the roof's. At the same
    # pitch it never leaves the roof; steeper, and it dives under it.
    #
    # The edges swap roles against the gable, and every board follows:
    #   FRONT is now the level EAVE (the fascia runs across it)
    #   THE TWO SIDES are the RAKES (they climb with the plane)
    #   THE BACK is the valley, buried in the roof - no boards.
    # The back is a straight line at s_ridge across the whole width,
    # because both planes depend on s alone.
    def self.shed_frame(spec, z0, slope, setback, width, length, th, rt, oh,
                        half, s_front, s_ridge, z_front, z_ridge)
      pitch = spec.key?(:pitch) ? spec[:pitch].to_f : slope / 2.0
      return warn_nil('a shed gablet needs a pitch, flatter than the roof') if
        pitch <= 0.0
      return warn_nil(format('a shed gablet must be FLATTER than the roof ' \
                             '(%.2f:12 against %.2f:12)', pitch * 12.0,
                             slope * 12.0)) if pitch >= slope - 0.0001
      return warn_nil('the overhang is too big for this width') if oh > half

      z_top_front = z_ridge - length * pitch    # the plane at the front wall
      height = z_top_front - z_front
      return warn_nil(format('too short: the front wall comes out %.1f" - ' \
                             'make it longer, or the gablet flatter', height)) if
        height < MIN_FACE_HEIGHT

      # the cheek's TOP is the deck underside; it meets the roof one roof
      # thickness before the deck's own back edge does.
      s_cheek = s_ridge - rt / (slope - pitch)
      return warn_nil('too long for its pitch: the cheeks never leave ' \
                      'the roof') if s_cheek - s_front < MIN_CHEEK_RUN

      w_edge  = half + oh                       # the RAKE line, each side
      s_rake  = s_front - oh                    # the EAVE line, at the front
      z_edge  = z_top_front - oh * pitch        # the deck there
      # the deck finishes ON the metal edge: over an eave that is one
      # metal thickness, over a rake a fascia plus a metal thickness.
      w_deck  = w_edge + deck_over_rake
      s_deck  = s_rake - deck_over_eave
      { z0: z0, slope: slope, pitch: pitch, setback: setback, style: 'shed',
        width: width, length: length, half: half, overhang: oh,
        thickness: th, roof_thickness: rt,
        s_front: s_front, s_ridge: s_ridge, s_eave: s_rake, s_cheek: s_cheek,
        s_rake: s_rake, s_valley: s_ridge, w_edge: w_edge, z_edge: z_edge,
        deck_side: deck_over_eave, deck_front: deck_over_rake,
        w_deck: w_deck, s_deck: s_deck,
        s_valley_deck: s_ridge, z_deck_edge: z_edge,
        z_front: z_front, z_ridge: z_ridge, z_eave: z_top_front,
        z_top_front: z_top_front, height: height }
    end

    # THE HOUSE RIDGE IS THE CEILING. `z_top` is the highest point of the
    # roof face the dormer stands on - roof_frame measures it off the
    # face itself - and the gablet must die at least RIDGE_CLEARANCE
    # below it. Returns nil when it fits, and otherwise says the biggest
    # wall height that WOULD fit, because "too big" without a number is
    # not much help at a mouse.
    def self.ridge_cap_check(spec, z0, slope, setback, half, pitch, s_ridge,
                             style, width)
      z_top = spec[:z_top]
      return nil if z_top.nil?
      ceiling = z_top.to_f - RIDGE_CLEARANCE
      z_ridge = z0 + s_ridge * slope
      return nil if z_ridge <= ceiling + 0.001
      room = ceiling - z0 - setback * slope
      h_max = if style == 'shed'
                p2 = spec.key?(:pitch) ? spec[:pitch].to_f : slope / 2.0
                slope > 0 ? room * (slope - p2) / slope : 0.0
              else
                room - half * pitch
              end
      # warn_nil returns nil, and nil is this method's "it fits" - so say
      # refused out loud instead of leaning on the return value.
      warn_nil(format('too long for this roof - it would reach the ridge. ' \
                      'The tallest front wall that fits here is %.0f"', h_max))
      :refused
    end

    def self.last_reason
      @last_reason
    end

    def self.warn_nil(msg)
      @last_reason = msg
      puts "[Dormer] #{msg}" unless @quiet
      nil
    end

    # The placing tool asks frame() a question on every mouse move, and
    # most of those questions have no answer yet ("not over a roof",
    # "too short here"). Without this the console fills with one line per
    # pixel travelled.
    def self.quietly
      old = @quiet
      @quiet = true
      yield
    ensure
      @quiet = old
    end

    # ---------- what the panel remembers (2026-09-02) -------------------
    #
    # Saved on the MODEL, exactly like RoofManager.settings, so the next
    # dormer in this file starts from the last one's numbers.
    # pitch12 is the panel's own "rise : 12"; 0 means FOLLOW THE ROOF,
    # which is the default the user agreed to.
    def self.settings
      m = Sketchup.active_model
      g = lambda do |k, d|
        v = m.get_attribute('InteriorPro', k)
        v.nil? ? d : v
      end
      { width:        g.call('dormer_width',   DEFAULT_WIDTH).to_f,
        length:       g.call('dormer_length',  DEFAULT_LENGTH).to_f,
        setback:      g.call('dormer_setback', DEFAULT_SETBACK).to_f,
        overhang:     g.call('dormer_overhang', DEFAULT_OVERHANG).to_f,
        height:       g.call('dormer_height', 0.0).to_f,
        pitch12:      g.call('dormer_pitch12', 0.0).to_f,
        fascia_depth: g.call('dormer_fascia_depth', 0.0).to_f,
        style:        g.call('dormer_style', 'gable').to_s }
    end

    def self.save_settings!(s)
      m = Sketchup.active_model
      m.set_attribute('InteriorPro', 'dormer_width', s[:width].to_f)
      m.set_attribute('InteriorPro', 'dormer_length', s[:length].to_f)
      m.set_attribute('InteriorPro', 'dormer_setback', s[:setback].to_f)
      m.set_attribute('InteriorPro', 'dormer_overhang', s[:overhang].to_f)
      m.set_attribute('InteriorPro', 'dormer_height', s[:height].to_f)
      m.set_attribute('InteriorPro', 'dormer_pitch12', s[:pitch12].to_f)
      m.set_attribute('InteriorPro', 'dormer_fascia_depth', s[:fascia_depth].to_f)
      m.set_attribute('InteriorPro', 'dormer_style', s[:style].to_s)
      s
    end

    # Panel numbers -> a frame() spec. The two "follow the house" cases
    # are a ZERO in the panel, never a blank: pitch12 0 = the roof's own
    # pitch, fascia_depth 0 = the house's own fascia.
    def self.spec_from_settings(s = nil)
      s ||= settings
      spec = { width: s[:width].to_f, length: s[:length].to_f,
               setback: s[:setback].to_f, overhang: s[:overhang].to_f,
               style: s[:style].to_s }
      # a typed height wins: the length is then whatever produces it.
      spec[:height] = s[:height].to_f if s[:height].to_f > 0.01
      spec[:pitch] = s[:pitch12].to_f / 12.0 if s[:pitch12].to_f > 0.01
      spec[:fascia_depth] = s[:fascia_depth].to_f if s[:fascia_depth].to_f > 0.01
      spec
    end

    # ---------- the ghost (2026-09-02) ---------------------------------
    #
    # What the placing tool draws under the cursor: the two roof planes
    # of the dormer, its front wall, and the hole it will cut - all in
    # world points, all from the SAME frame the build will use, so what
    # he sees is what he gets. nil when there is no dormer to place here.
    def self.preview(roof, x, y, spec = {})
      quietly do
        rf = roof_frame(roof, x, y)
        return nil if rf.nil?
        s = spec.merge(rf)
        fr = frame(s)
        return nil if fr.nil?
        at = at_lambda(s)
        return nil unless fits_on_face?(fr, at, rf[:face])
        rt = fr[:roof_thickness]
        half = fr[:half]
        if fr[:style] == 'shed'
          w = fr[:w_deck]
          loops = [[[fr[:s_deck], -w], [fr[:s_deck], w],
                    [fr[:s_ridge], w], [fr[:s_ridge], -w]]
                   .map { |ss, ww| at.call(ss, ww, deck_z(fr, ss, ww)) }]
          loops << [at.call(fr[:s_front], -half, fr[:z_front]),
                    at.call(fr[:s_front], half, fr[:z_front]),
                    at.call(fr[:s_front], half, shed_top(fr, fr[:s_front])),
                    at.call(fr[:s_front], -half, shed_top(fr, fr[:s_front]))]
        else
          loops = [1.0, -1.0].map do |sg|
            roof_plan(fr, sg).map { |ss, w| at.call(ss, w, top_z(fr, w)) }
          end
          loops << [[-half, fr[:z_front]], [half, fr[:z_front]],
                    [half, fr[:z_eave] - rt], [0.0, fr[:z_ridge] - rt],
                    [-half, fr[:z_eave] - rt]]
                   .map { |w, z| at.call(fr[:s_front], w, z) }
        end
        op = opening_plan(fr)
        loops << op.map { |ss, w| at.call(ss, w, roof_z(fr, ss)) } if op
        loops
      end
    end

    # The main roof surface, and the height of the dormer roof's TOP
    # surface over the centre line offset w.
    def self.roof_z(fr, s);  fr[:z0] + s * fr[:slope]; end
    def self.top_z(fr, w);   fr[:z_ridge] - w.abs * fr[:pitch]; end

    # The deck's TOP surface. A gable falls sideways off its ridge, a
    # shed falls forward off the line where it dies into the roof - so
    # one of the two arguments is always the one that matters.
    def self.deck_z(fr, s, w)
      return fr[:z_ridge] - (fr[:s_ridge] - s) * fr[:pitch] if fr[:style] == 'shed'
      top_z(fr, w)
    end

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
      deck_over_eave
    end

    # Over an EAVE the fascia hangs inside the line and only the metal
    # edge is outside it; over a RAKE both boards are outside.
    def self.deck_over_eave
      rm = roof_manager
      rm.nil? ? TRIM_DRIP_THICK : rm::DRIP_THICK
    end

    def self.deck_over_rake
      rm = roof_manager
      return TRIM_THICK + TRIM_DRIP_THICK if rm.nil?
      rm::FASCIA_THICK + rm::DRIP_THICK
    end

    def self.deck_front
      deck_over_rake
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

      if fr[:style] == 'shed'
        build_shed_wall!(grp, fr, at, spec[:wall_names])
        [1.0, -1.0].each { |sg| build_shed_cheek!(grp, fr, at, sg, spec[:wall_names]) }
        build_shed_roof!(grp, fr, at, spec[:roof_material])
        build_shed_trim!(grp, fr, at, spec) if USE_DORMER_TRIM
      else
        build_front_wall!(grp, fr, at, spec[:wall_names])
        [1.0, -1.0].each { |sg| build_cheek!(grp, fr, at, sg, spec[:wall_names]) }
        [1.0, -1.0].each { |sg| build_roof_plane!(grp, fr, at, sg, spec[:roof_material]) }
        build_trim!(grp, fr, at, spec) if USE_DORMER_TRIM
      end
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
      z_top = pts.map(&:z).max
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
      { base: base, along: along, into: into, roof_mat: roof_mat, face: face,
        z_top: z_top, z0: z_at.call(base[0], base[1]), slope: slope }
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

    # ---------- IT HAS TO FIT ON THIS SLOPE (2026-09-02) ---------------
    #
    # The user, after watching one hang over the ridge: "אני לא רוצה
    # שיהיה אפשר להניח את הגגון אם הוא נוגע ברידג גם של הצדדים לא רק של
    # הגובה... חייבת להיות מגבלה."
    #
    # The height cap (ridge_cap_check) only watches the way the gablet
    # CLIMBS. This watches the other two directions: every corner of the
    # deck has to sit inside the roof face it is standing on, and keep
    # RIDGE_CLEARANCE clear of that face's own edges - the ridge above,
    # the hips beside it, the eave below. Off the face there is no roof
    # to die into and no roof to cut.
    def self.deck_corners(fr, at)
      plan = if fr[:style] == 'shed'
               w = fr[:w_deck]
               [[fr[:s_deck], -w], [fr[:s_deck], w],
                [fr[:s_ridge], w], [fr[:s_ridge], -w]]
             else
               roof_plan(fr, 1.0) + roof_plan(fr, -1.0)
             end
      plan.map { |ss, ww| at.call(ss, ww, 0.0) }
    end

    def self.fits_on_face?(fr, at, face, margin = RIDGE_CLEARANCE)
      return true if face.nil?
      pts = face_points(face)
      return true if pts.nil? || pts.length < 3
      ring = pts.map { |p| [p.x, p.y] }
      deck_corners(fr, at).each do |q|
        next if point_in_ring?(ring, q.x, q.y) &&
                ring_distance(ring, q.x, q.y) >= margin
        warn_nil(format('it would reach the edge of this roof slope - keep ' \
                        '%.0f" clear of the ridge and the hips. Move it, make ' \
                        'it smaller, or change the gablet', margin))
        return false
      end
      true
    end

    # Put one dormer on a real roof, at (x, y) in plan.
    def self.place_on_roof!(roof, x, y, spec = {})
      rf = roof_frame(roof, x, y)
      return nil if rf.nil?
      s = spec.merge(rf)
      fr = frame(s)
      return nil if fr.nil?
      return nil unless fits_on_face?(fr, at_lambda(s), rf[:face])
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

    # ---------- THE SHED BODY (2026-09-02) ------------------------------
    #
    # Same three walls and the same law: every wall stops on the UNDERSIDE
    # of the deck, and the front corners are mitred on the 45 degree
    # plane so no two walls own the same block.
    #
    # The one difference from the gable is that the deck falls along s
    # and not across w, so the front wall's top is not level: its outer
    # face is one wall thickness of fall LOWER than its inner face, and
    # the two corners of each cheek follow the same line.
    def self.shed_top(fr, s)
      deck_z(fr, s, 0.0) - fr[:roof_thickness]
    end

    def self.build_shed_wall!(grp, fr, at, names)
      th   = fr[:thickness]
      half = fr[:half]
      hi   = half - th
      return warn_nil('the walls are too thick for this width') if hi <= 0.5
      s_o = fr[:s_front]
      s_i = fr[:s_front] + th
      outer = [at.call(s_o, -half, fr[:z_front]), at.call(s_o, half, fr[:z_front]),
               at.call(s_o, half, shed_top(fr, s_o)),
               at.call(s_o, -half, shed_top(fr, s_o))]
      inner = [at.call(s_i, -hi, fr[:z_front]), at.call(s_i, hi, fr[:z_front]),
               at.call(s_i, hi, shed_top(fr, s_i)),
               at.call(s_i, -hi, shed_top(fr, s_i))]
      sub = new_part!(grp, 'InteriorPro_DormerWall', 'dormer_front')
      ring!(sub, outer, inner, 4)
      paint_wall!(sub, names)
      sub
    end

    def self.build_shed_cheek!(grp, fr, at, sign, names)
      th  = fr[:thickness]
      w_o = fr[:half] * sign
      w_i = w_o - th * sign
      s_i = fr[:s_front] + th
      outer_p = [[fr[:s_front], fr[:z_front]],
                 [fr[:s_front], shed_top(fr, fr[:s_front])],
                 [fr[:s_cheek], shed_top(fr, fr[:s_cheek])]]
      inner_p = [[s_i, roof_z(fr, s_i)], [s_i, shed_top(fr, s_i)],
                 [fr[:s_cheek], shed_top(fr, fr[:s_cheek])]]
      sub = new_part!(grp, 'InteriorPro_DormerWall', 'dormer_cheek')
      outer = outer_p.map { |ss, z| at.call(ss, w_o, z) }
      inner = inner_p.map { |ss, z| at.call(ss, w_i, z) }
      ring!(sub, outer, inner, 3)
      paint_wall!(sub, names)
      sub
    end

    # One plane, from the front eave line back to where it dies into the
    # roof, hanging out over its own boards on all three open sides.
    def self.build_shed_roof!(grp, fr, at, mat)
      rt = fr[:roof_thickness]
      w  = fr[:w_deck]
      plan = [[fr[:s_deck], -w], [fr[:s_deck], w],
              [fr[:s_ridge], w], [fr[:s_ridge], -w]]
      sub = new_part!(grp, 'InteriorPro_DormerRoof', 'dormer_roof')
      top = plan.map { |ss, ww| at.call(ss, ww, deck_z(fr, ss, ww)) }
      bot = plan.map { |ss, ww| at.call(ss, ww, deck_z(fr, ss, ww) - rt) }
      ring!(sub, top, bot, plan.length)
      if mat
        sub.entities.grep(Sketchup::Face).each do |f|
          f.material = mat
          f.back_material = mat
        end
      end
      sub
    end

    # THE SHED'S BOARDS. The roles swap with the edges: the FRONT is the
    # level eave, so RoofManager's own band runs across it with nothing
    # to cut - it never meets the main roof. The two SIDES are rakes and
    # climb, so they are RoofManager's rake board, clipped by `cover` -
    # the roof's own answer to "this board must END where the other roof
    # starts" - which is what stops them burying themselves at the back.
    #
    # THE RAKE COMES IN FRONT OF THE PERPENDICULAR, the rule he set on
    # the gable: the side boards run their whole edge and cover the front
    # fascia's ends, so the front fascia stops on the rake line.
    def self.shed_ring(fr, at)
      we = fr[:w_edge]
      sw = [[[fr[:s_rake], -we], 'eave'], [[fr[:s_rake], we], 'gable'],
            [[fr[:s_ridge], we], 'valley'], [[fr[:s_ridge], -we], 'gable']]
      # edge i runs from corner i to corner i+1:
      #   0: front, -w -> +w   the EAVE
      #   1: +w, front -> back the RAKE
      #   2: back              the VALLEY
      #   3: -w, back -> front the RAKE
      pts = sw.map { |(ss, ww), _| q = at.call(ss, ww, 0.0); [q.x, q.y] }
      labs = sw.map(&:last)
      n = pts.length
      if signed_area(pts) < 0.0
        pts = pts.reverse
        labs = (0...n).map { |i| labs[(n - 2 - i) % n] }
      end
      { poly: pts, labels: labs,
        eave: labs.index('eave'),
        rakes: (0...n).select { |i| labs[i] == 'gable' },
        gable_flags: labs.map { |l| l != 'eave' },
        # THE METAL EDGE WRAPS EVERY CORNER (the house's rule, 2026-08-26).
        # It may wrap onto a RAKE, where there is a rake metal edge out
        # there to land on - never onto the buried valley, where there is
        # nothing but shingles.
        wrap_flags: labs.map { |l| l == 'gable' } }
    end

    def self.shed_zmap(fr, at)
      rt = fr[:roof_thickness]
      nodes = [[fr[:s_rake], -fr[:w_edge]], [fr[:s_rake], fr[:w_edge]],
               [fr[:s_ridge], fr[:w_edge]], [fr[:s_ridge], -fr[:w_edge]]]
      map = {}
      nodes.each do |ss, ww|
        q = at.call(ss, ww, 0.0)
        map[[q.x, q.y]] = deck_z(fr, ss, ww) - rt
      end
      map
    end

    # PURE: the deck's UNDERSIDE along a shed, and the two s values where
    # a board hung under it crosses the main roof - the top edge first,
    # the bottom edge earlier. Between them is the DIAGONAL the user
    # asked for (2026-09-02: "הפשייה והמטל אדג והאיבס צריך להיגמר
    # בשיפוע של הגג"): a shed's side boards climb slower than the roof
    # does, so the roof eats them from below, and a square end either
    # leaves the last stretch bare or buries the board's foot.
    def self.shed_under_z(fr, s)
      deck_z(fr, s, 0.0) - fr[:roof_thickness]
    end

    def self.shed_meet_s(fr, drop)
      a0 = fr[:z_ridge] - fr[:s_ridge] * fr[:pitch] - fr[:roof_thickness]
      (a0 - drop - fr[:z0]) / (fr[:slope] - fr[:pitch])
    end

    # One side board in (s, z): along under the deck from the front, then
    # cut on the roof's own plane.  `hang` is how far under the deck its
    # TOP sits (0 for the fascia and the metal edge, one fascia depth for
    # the soffit), `depth` how deep the board is.
    def self.shed_side_profile(fr, s0, hang, depth)
      return nil if depth <= 0.0
      s_t = shed_meet_s(fr, hang)
      s_b = shed_meet_s(fr, hang + depth)
      return nil if s_t <= s0 + 0.5
      top = lambda { |ss| shed_under_z(fr, ss) - hang }
      bot = lambda { |ss| shed_under_z(fr, ss) - hang - depth }
      return [[s0, top.call(s0)], [s_t, top.call(s_t)], [s_b, bot.call(s_b)]] if
        s_b <= s0
      [[s0, top.call(s0)], [s_t, top.call(s_t)],
       [s_b, bot.call(s_b)], [s0, bot.call(s0)]]
    end

    def self.build_shed_trim!(grp, fr, at, spec = {})
      dep = fascia_depth(spec)
      return false if dep <= 0.0
      rm = roof_manager
      return false if rm.nil?
      ft = rm::FASCIA_THICK
      dt = rm::DRIP_THICK
      dd = rm::DRIP_DEPTH
      mat = trim_material(trim_color(spec))
      ring = shed_ring(fr, at)
      poly = ring[:poly]
      band_top = fr[:z_edge] - fr[:roof_thickness]
      we = fr[:w_edge]
      s0 = fr[:s_rake]

      # THE FRONT is a level eave that never meets the roof, so it is
      # RoofManager's own band with nothing to cut.
      # ...and it ends SQUARE at both corners, on the rake line, not on a
      # 45 degree mitre. The soffit under it already runs square out to
      # that line, so a mitred fascia left a triangle of open sky between
      # the two (2026-09-02: "פשיה אחד הוא אלכסון ואחד הוא מרובע -
      # תסתום את הפינה"). Square against square closes it, and the rake
      # board stands outside the line, so nothing overlaps.
      fas = new_part!(grp, 'InteriorPro_DormerFascia', 'dormer_fascia')
      rm.build_band!(fas, poly, -ft, 0.0, band_top, band_top - dep,
                     ring[:gable_flags], nil, ring[:wrap_flags], 0.0)
      paint!(fas, mat)
      # ...and the metal edge over it, running SQUARE past both corners
      # onto the side metal's own outer face instead of stopping short
      # of it in a mitre.
      drip = new_part!(grp, 'InteriorPro_DormerDrip', 'dormer_drip')
      rm.build_band!(drip, poly, 0.0, dt, band_top, band_top - dd,
                     ring[:gable_flags], nil, ring[:wrap_flags], ft + dt)

      # THE TWO SIDES climb, and the roof climbs faster - so they are
      # built here, ending on the roof's own plane. The rake starts at
      # the eave line and covers the front fascia's end: the gable rule
      # he set, kept.
      rake = new_part!(grp, 'InteriorPro_DormerRake', 'dormer_rake')
      rprof = shed_side_profile(fr, s0, 0.0, dep)
      dprof = shed_side_profile(fr, s0, 0.0, dd)
      [1.0, -1.0].each do |sg|
        extrude_sz!(rake, rprof, at, we * sg, (we + ft) * sg) if rprof
        extrude_sz!(drip, dprof, at, (we + ft) * sg,
                    (we + ft + dt) * sg) if dprof
      end
      paint!(rake, mat)
      paint!(drip, mat)

      style, sloped = soffit_choice(spec)
      if style != 'none' && fr[:overhang] >= 1.0
        scol = trim_material(soffit_color(spec, style))
        sof = new_part!(grp, 'InteriorPro_DormerSoffit', 'dormer_soffit')
        sb = rm.soffit_band(fr[:overhang], dep, true, band_top)
        if sb
          # the front board, lifted at its inner edge so it lies parallel
          # to the deck above it - the house's own sloped soffit rule.
          rise = sloped ? fr[:pitch] * fr[:overhang] : 0.0
          rm.build_band!(sof, poly, sb[:k_in], sb[:k_out], sb[:z_top], sb[:z_bot],
                         ring[:gable_flags], nil, ring[:gable_flags], 0.0, rise)
        end
        # THE FRONT BOARD OWNS THE CORNER SQUARE, and the side board is
        # pulled back a whole overhang onto its inner edge - the house's
        # own rake_meet_span rule (CLAUDE.md). Without it both boards
        # built into the same corner block and the user saw the bite
        # they leave (2026-09-02, red circle on the underside).
        #
        # They meet EXACTLY: the front board's inner edge is lifted by
        # pitch x overhang, which is the deck's own climb across that
        # overhang - so at s_front the two are the same height.
        # A RAKE BOARD STANDS OUTSIDE ITS LINE, so the soffit under it
        # runs right up to that line and meets the board's INNER face -
        # no inset (RoofManager.build_rake_soffit! says the same in the
        # same words). Insetting it by a board thickness, the way an
        # EAVE soffit is inset because its fascia hangs INSIDE the line,
        # left a slot of daylight the whole length of the side
        # (2026-09-02: "יש רווח בין הפשייה לאיבס תסתום אותו").
        thick = soffit_thick
        sprof = shed_side_profile(fr, fr[:s_front], dep - thick, thick)
        if sprof && we - fr[:half] > 0.5
          [1.0, -1.0].each do |sg|
            extrude_sz!(sof, sprof, at, we * sg, fr[:half] * sg)
          end
        end
        paint!(sof, scol)
      end
      true
    rescue StandardError => e
      puts "[Dormer] build_shed_trim!: #{e.class}: #{e.message}"
      puts e.backtrace.first(4) if e.backtrace
      false
    end

    # The main roof's height at a world point, in the dormer's own frame -
    # what RoofManager's rake clipper calls `cover`.
    def self.roof_cover_z(fr, at, x, y)
      o = at.call(0.0, 0.0, 0.0)
      d = at.call(1.0, 0.0, 0.0)
      ix = d.x - o.x
      iy = d.y - o.y
      s = (x - o.x) * ix + (y - o.y) * iy
      roof_z(fr, s)
    rescue StandardError
      nil
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

      # THE EAVES ARE CLOSED (2026-09-02, the user: "עכשיו רק איבס
      # וסיימנו"). The soffit board sits exactly where RoofManager's
      # soffit_band puts it - from the wall face out to the fascia's
      # inner face, at the fascia's bottom line, one SOFFIT_THICK thick -
      # and it tilts with the roof when the house's boards do.
      # Its BACK end is cut on the main roof like the fascia's, and
      # because a tilted board's inner edge is higher, that edge reaches
      # further back before the roof catches it: the cut is a diagonal
      # in plan, not a square end.
      build_eave_soffit!(grp, fr, at, spec, dep, z_top)

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
          # ...and the gable's own soffit, RoofManager's board again.
          # It is pulled back a whole overhang where it meets the eave
          # soffit, so the two boards meet instead of crossing.
          style, sloped = soffit_choice(spec)
          if style != 'none' && fr[:overhang] >= 1.0 &&
             rm.respond_to?(:build_rake_soffit!)
            rs = new_part!(grp, 'InteriorPro_DormerSoffit', 'dormer_soffit')
            rm.build_rake_soffit!(rs, poly, gi, zmap, dep, fr[:overhang],
                                  sloped: sloped,
                                  reach: rm.rake_meet_span(poly, gi, ring[:level],
                                                           fr[:overhang]))
            paint!(rs, trim_material(soffit_color(spec, style)))
          end
        end
      end
      paint!(drip, mat)
      true
    rescue StandardError => e
      puts "[Dormer] build_trim!: #{e.class}: #{e.message}"
      puts e.backtrace.first(4) if e.backtrace
      false
    end

    # The soffit style and tilt: whatever the house is wearing, unless
    # the caller says otherwise.
    def self.soffit_choice(spec)
      st = spec[:soffit]
      sl = spec[:soffit_slope]
      rm = roof_manager
      if (st.nil? || sl.nil?) && rm && rm.respond_to?(:settings)
        begin
          set = rm.settings
          st = set[:soffit] if st.nil?
          sl = set[:soffit_slope] if sl.nil?
        rescue StandardError
          nil
        end
      end
      [st.nil? ? 'boxed' : st.to_s, sl == true]
    end

    def self.soffit_color(spec, style)
      c = spec[:soffit_color]
      rm = roof_manager
      if c.nil? && rm && rm.respond_to?(:settings)
        c = begin
          rm.settings[:soffit_color]
        rescue StandardError
          nil
        end
      end
      c = nil if c.to_s.empty?
      if c.nil? && rm && rm.respond_to?(:soffit_colors)
        c = rm.soffit_colors[style]
      end
      c.nil? ? trim_color(spec) : c.to_s
    end

    def self.soffit_thick
      rm = roof_manager
      rm.nil? ? 0.75 : rm::SOFFIT_THICK
    end

    # PURE: one eave soffit board, as two profiles in (s, z) - the OUTER
    # one against the fascia and the INNER one against the wall. The
    # inner one is `rise` higher (that is the tilt) and therefore ends
    # further back, which is what makes the cut a diagonal.
    def self.eave_soffit_profiles(fr, z_top, depth, s0, thick, rise)
      z_bot = z_top - depth
      cut = lambda { |z| (z - fr[:z0]) / fr[:slope] }
      out_end = cut.call(z_bot)
      in_end  = cut.call(z_bot + rise)
      return nil if out_end <= s0 + 0.5 || in_end <= s0 + 0.5
      [[[s0, z_bot + thick], [out_end, z_bot + thick], [out_end, z_bot], [s0, z_bot]],
       [[s0, z_bot + rise + thick], [in_end, z_bot + rise + thick],
        [in_end, z_bot + rise], [s0, z_bot + rise]]]
    end

    def self.build_eave_soffit!(grp, fr, at, spec, depth, z_top)
      style, sloped = soffit_choice(spec)
      return nil if style == 'none' || fr[:overhang] < 1.0
      rm = roof_manager
      ft = rm ? rm::FASCIA_THICK : TRIM_THICK
      thick = soffit_thick
      # the same number soffit_rise gives a roof, measured on the
      # DORMER's own pitch - that is the fall across this board.
      rise = sloped ? fr[:pitch] * fr[:overhang] : 0.0
      prof = eave_soffit_profiles(fr, z_top, depth, fr[:s_rake], thick, rise)
      return nil if prof.nil?
      w_out = fr[:w_edge] - ft
      w_in  = fr[:half]
      return nil if w_out - w_in < 0.5
      sub = new_part!(grp, 'InteriorPro_DormerSoffit', 'dormer_soffit')
      [1.0, -1.0].each do |sg|
        extrude_sz2!(sub, prof[0], prof[1], at, w_out * sg, w_in * sg)
      end
      paint!(sub, trim_material(soffit_color(spec, style)))
      sub
    end

    # Two profiles, one at each end of the sweep - the tilted twin of
    # extrude_sz!.
    def self.extrude_sz2!(sub, prof_a, prof_b, at, w_a, w_b)
      a = prof_a.map { |s, z| at.call(s, w_a, z) }
      b = prof_b.map { |s, z| at.call(s, w_b, z) }
      add_face!(sub, a)
      add_face!(sub, b.reverse)
      prof_a.length.times do |i|
        j = (i + 1) % prof_a.length
        add_face!(sub, [a[i], a[j], b[j], b[i]])
      end
      sub
    end

    # Two matching loops closed into a solid: the outer face, the inner
    # face, and a quad per pair of corners.
    def self.ring!(sub, a, b, n)
      add_face!(sub, a)
      add_face!(sub, b.reverse)
      n.times do |i|
        j = (i + 1) % n
        add_face!(sub, [a[i], a[j], b[j], b[i]])
      end
      sub
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
      if fr[:style] == 'shed'
        s0 = fr[:s_front] + th
        return nil if fr[:s_ridge] <= s0 + 0.5
        return [[s0, -hw], [s0, hw], [fr[:s_ridge], hw], [fr[:s_ridge], -hw]]
      end
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
