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
    # The room side of every dormer wall. A colour, not a material name -
    # WallTool.load_or_create_material reads a leading '#' as a colour,
    # which is the same trick the house's own interior_material uses.
    DEFAULT_INTERIOR_COLOR = '#ffffff' unless
      const_defined?(:DEFAULT_INTERIOR_COLOR, false)
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
    USE_DORMER_HEEL = true unless const_defined?(:USE_DORMER_HEEL, false)

    # How far the gablet's own eave tail falls below the wall it stands
    # on: its overhang times ITS OWN pitch. A shed's pitch is its own
    # (default: half the roof's); a flat gablet has none at all.
    def self.dormer_heel(overhang, style, pitch, slope, spec)
      return 0.0 unless USE_DORMER_HEEL
      # A flat gablet has no pitch and so no falling tail - but its fascia
      # still hangs below its deck, so it gets the drop like everyone else.
      # (That is also what keeps flat identical to a shed at zero pitch,
      # which rt101 pins.)
      p = if style.to_s == 'flat'
            0.0
          elsif style.to_s == 'shed'
            spec.key?(:pitch) ? spec[:pitch].to_f : slope.to_f / 2.0
          else
            pitch.to_f
          end
      # ITS OWN FASCIA DEPTH, AND ONLY THAT (2026-09-06). Same number and
      # same reason as the house roof: the gablet's eave hangs that far
      # below its deck, so standing the roof that far over its walls lands
      # the underside of the eave ON them. He confirmed the gablet already
      # reads right - "עובד מעולה בדורמר" - and this keeps it that way.
      # Nothing changes size or shape; the roof simply sits higher.
      l = fascia_depth(spec).to_f
      l > 0.0 ? l : 0.0
    end

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
      # A FLAT GABLET HAS NO PITCH, ON PURPOSE (2026-09-06). shed_frame
      # zeroes it for `flat`, build_dormer! saves that zero on the group
      # and dormer_spec hands it straight back - so EVERY rebuild of a
      # flat gablet came back through here with pitch 0 and was thrown
      # away: the replant after any roof rebuild (which is when he saw
      # it - "גגון שטוח נעלם כששמים אותו על גג ברזל ואז מחליפים
      # לשינגלס"), and Edit and Move as well. Measured: gable and shed
      # store their real pitch and survive; only flat stored a zero.
      return warn_nil('the dormer roof has no pitch') if
        pitch <= 0.0 && spec.fetch(:style, 'gable').to_s != 'flat'
      return warn_nil('setback cannot be negative') if setback < 0.0

      # THE HEIGHT DRIVES THE LENGTH (2026-09-02). He cares about the
      # wall - a window goes in it - and not about how far the gablet
      # reaches into the roof, so a typed height turns into the length
      # that produces it. Nothing else changes: the gablet still dies
      # into the roof at the end of that length.
      style_now = spec.fetch(:style, 'gable').to_s
      if spec[:height].to_f > 0.0
        h = spec[:height].to_f
        length = if style_now == 'flat'
                   h / slope
                 elsif style_now == 'shed'
                   p2 = spec.key?(:pitch) ? spec[:pitch].to_f : slope / 2.0
                   p2 < slope ? h / (slope - p2) : 0.0
                 else
                   (h + (width / 2.0) * pitch) / slope
                 end
        return warn_nil('that height cannot be built on this roof') if
          length <= 0.0
      end

      # THE RAISED HEEL, ON THE GABLET TOO (2026-09-06). Same complaint,
      # same fix as the house roof: the gablet's own eave tail hung
      # overhang x pitch BELOW the wall top and ate into the front wall.
      # The roof rides up by exactly that much - one extra step of length,
      # because a gablet's roof has to keep dying into the main roof - and
      # the walls grow with it, which is where the window gets its room.
      #
      # HE CHOSE WHAT THE PANEL'S NUMBER MEANS (2026-09-06): "העקב נוסף
      # למספר" - type 33 on a 6" eave at 5:12 and the front wall comes out
      # 35.5. That deliberately replaces the older rule that a typed height
      # came back untouched and that the overhang never moved z_eave
      # (rt97/rt99/rt102); those suites now switch the heel off and rt119
      # pins the new behaviour.
      #
      # A FLAT gablet has no pitch and no tail, so it gets no heel.
      # Kill switch: InteriorPro::DormerManager::USE_DORMER_HEEL = false.
      #
      # ONE EXTRA STEP OF LENGTH, MEASURED IN THE RIGHT UNITS. A gable's
      # front wall grows length x slope, a SHED's grows length x (slope -
      # its own pitch) - so the step that buys `heel` of wall is not the
      # same number for the two. Measured: dividing a shed by the roof
      # slope bought only 4.6" of the 9.25" it was owed.
      #
      # THE LENGTH THAT WAS ASKED FOR (2026-09-07). The heel step below
      # makes `length` LONGER, and build_dormer! used to save that longer
      # number on the group. dormer_spec handed it straight back as the
      # next rebuild's typed length, which added the heel to it AGAIN -
      # so every Edit, Move, replant or Apply grew the gablet. Measured
      # on a 5:12 roof with a 6" eave: a typed 120 came back 139.2,
      # 158.4, 177.6, 196.8, and the front wall climbed 45.5 -> 53.5 ->
      # 61.5 -> 69.5 until the gablet hit the ridge and refused to build
      # ("too long for this roof - it would reach the ridge"). He saw it
      # as the window panel failing; the window had nothing to do with it.
      #
      # `length_asked` is what was typed. The geometry still uses the
      # heeled `length` - not one number of it changed - and the GROUP
      # remembers the asked one, so the heel is added exactly once.
      length_asked = length
      heel = dormer_heel(oh, style_now, pitch, slope, spec)
      if heel > 0.0
        den = if style_now == 'shed'
                p2 = spec.key?(:pitch) ? spec[:pitch].to_f : slope / 2.0
                slope - p2
              else
                slope
              end
        length += heel / den if den > 0.0001
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
      return warn_nil('unknown gablet style') unless
        %w[gable hip shed flat].include?(style)
      if style == 'shed' || style == 'flat'
        sfr = shed_frame(spec, z0, slope, setback, width, length, th, rt, oh,
                         half, s_front, s_ridge, z_front, z_ridge, style)
        sfr[:length_asked] = length_asked if sfr
        return sfr
      end
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
      # A HIP HAS NO RAKE (2026-09-02). All three open edges are level
      # eaves, so the deck runs past every one of them by a metal edge
      # and no more - the fascia hangs inside the line on all three.
      hip = style == 'hip'
      d_side      = deck_over_eave
      d_front     = hip ? deck_over_eave : deck_over_rake
      w_deck      = w_edge + d_side
      s_deck      = s_rake - d_front
      z_deck_edge = z_ridge - w_deck * pitch
      s_valley_d  = (z_deck_edge - z0) / slope

      # THE HIP POINT: with one pitch on all three planes the hip lines
      # run at 45 degrees in plan, so the ridge starts one half width
      # back from the front eave. Past the die-in there is no ridge left
      # to start - that is a pyramid, not a dormer.
      s_hip = s_rake + w_edge
      return warn_nil(format('too wide for its length - the hip would reach ' \
                             'the roof before it reaches a ridge (needs about ' \
                             '%.0f" more length)', s_hip + 12.0 - s_ridge)) if
        hip && s_hip > s_ridge - 12.0

      { z0: z0, slope: slope, pitch: pitch, setback: setback, style: style,
        s_hip: s_hip,
        width: width, length: length, length_asked: length_asked,
        half: half, overhang: oh,
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
    #
    # A FLAT GABLET IS A SHED WITH NO PITCH AT ALL (2026-09-02). Every
    # line of this holds with pitch 0 - the deck is level, the height is
    # length x slope, the back edge is still one straight line - so flat
    # is not a fourth builder, it is this one with the number zeroed.
    def self.shed_frame(spec, z0, slope, setback, width, length, th, rt, oh,
                        half, s_front, s_ridge, z_front, z_ridge,
                        style = 'shed')
      flat = style == 'flat'
      pitch = if flat
                0.0
              else
                spec.key?(:pitch) ? spec[:pitch].to_f : slope / 2.0
              end
      return warn_nil('a shed gablet needs a pitch, flatter than the roof') if
        !flat && pitch <= 0.0
      return warn_nil(format('a shed gablet must be FLATTER than the roof ' \
                             '(%.2f:12 against %.2f:12)', pitch * 12.0,
                             slope * 12.0)) if !flat && pitch >= slope - 0.0001
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
      { z0: z0, slope: slope, pitch: pitch, setback: setback, style: style,
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
        place_mode:   g.call('dormer_place_mode', 'free').to_s,
        window:       g.call('dormer_window', true) ? true : false,
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
      m.set_attribute('InteriorPro', 'dormer_place_mode',
                      s[:place_mode].nil? ? 'free' : s[:place_mode].to_s)
      m.set_attribute('InteriorPro', 'dormer_window', s[:window] ? true : false)
      s
    end

    # Panel numbers -> a frame() spec. The two "follow the house" cases
    # are a ZERO in the panel, never a blank: pitch12 0 = the roof's own
    # pitch, fascia_depth 0 = the house's own fascia.
    def self.spec_from_settings(s = nil)
      s ||= settings
      spec = { width: s[:width].to_f, length: s[:length].to_f,
               setback: s[:setback].to_f, overhang: s[:overhang].to_f,
               place_mode: s[:place_mode].to_s,
               window: s[:window] ? true : false,
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
        s = click_spec(spec, rf)
        fr = frame(s)
        return nil if fr.nil?
        at = at_lambda(s)
        return nil unless fits_on_face?(fr, at, rf[:face])
        rt = fr[:roof_thickness]
        half = fr[:half]
        if shed_like?(fr)
          w = fr[:w_deck]
          loops = [[[fr[:s_deck], -w], [fr[:s_deck], w],
                    [fr[:s_ridge], w], [fr[:s_ridge], -w]]
                   .map { |ss, ww| at.call(ss, ww, deck_z(fr, ss, ww)) }]
          loops << [at.call(fr[:s_front], -half, fr[:z_front]),
                    at.call(fr[:s_front], half, fr[:z_front]),
                    at.call(fr[:s_front], half, shed_top(fr, fr[:s_front])),
                    at.call(fr[:s_front], -half, shed_top(fr, fr[:s_front]))]
        elsif fr[:style] == 'hip'
          loops = hip_planes(fr).map do |plan|
            plan.map { |ss, ww| at.call(ss, ww, deck_z(fr, ss, ww)) }
          end
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
      return fr[:z_ridge] - (fr[:s_ridge] - s) * fr[:pitch] if shed_like?(fr)
      # A HIP climbs away from whichever eave is nearest - the front one
      # or the side one - which is what makes the two meet on a 45.
      if fr[:style] == 'hip'
        d = [fr[:w_edge] - w.abs, s - fr[:s_rake]].min
        return fr[:z_edge] + d * fr[:pitch]
      end
      top_z(fr, w)
    end

    # Shed and flat share one body, one set of boards and one hole - flat
    # is the same shape with the pitch zeroed.
    def self.shed_like?(fr)
      fr[:style] == 'shed' || fr[:style] == 'flat'
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
      # EVERYTHING NEEDED TO REBUILD IT LATER (2026-09-02). Edit, Move and
      # Delete all start from these: with the frame numbers AND the frame
      # itself - where the eave line is, which way is up the slope, how
      # high and how steep the roof under it is - dormer_spec can hand
      # frame() the exact same question the placing click asked.
      grp.set_attribute('InteriorPro', 'style', fr[:style])
      %i[setback width length pitch thickness roof_thickness overhang
         z0 slope height].each do |k|
        grp.set_attribute('InteriorPro', k.to_s, fr[k])
      end
      # THE ASKED LENGTH, NOT THE HEELED ONE (2026-09-07) - see frame().
      # Saving the heeled length here is what made every rebuild grow the
      # gablet. rt122 pins that a rebuild changes nothing.
      grp.set_attribute('InteriorPro', 'length',
                        (fr[:length_asked] || fr[:length]).to_f)
      grp.set_attribute('InteriorPro', 'base_xy', [base[0], base[1]])
      grp.set_attribute('InteriorPro', 'along_xy', along)
      grp.set_attribute('InteriorPro', 'into_xy', into)
      grp.set_attribute('InteriorPro', 'fascia_depth', fascia_depth(spec))
      # THE MODE IT WAS PLACED IN (2026-09-06). Without this a built dormer
      # forgot whether its setback was clicked, typed or flush: Edit could
      # not re-apply a typed depth, and Move always ran free.
      pm = spec[:place_mode].to_s
      grp.set_attribute('InteriorPro', 'place_mode',
                        %w[free depth flush].include?(pm) ? pm : 'free')
      grp.set_attribute('InteriorPro', 'window', spec[:window] ? true : false)
      # THE WINDOW'S OWN NUMBERS (2026-09-07). They live on the dormer,
      # not on the window group, because Edit and Move rebuild the whole
      # dormer from these attributes - exactly like the setback and the
      # place mode above. Nothing typed means "as big as it may be".
      grp.set_attribute('InteriorPro', 'window_type', window_type_of(spec))
      grp.set_attribute('InteriorPro', 'window_w', spec[:window_w].to_f) if
        spec[:window_w].to_f > 0.0
      grp.set_attribute('InteriorPro', 'window_h', spec[:window_h].to_f) if
        spec[:window_h].to_f > 0.0
      # the ceiling this roof face gave it, so an EDIT is held to the
      # same limit the placing click was - without it a typed height
      # could push a built dormer straight through the ridge.
      grp.set_attribute('InteriorPro', 'z_top', spec[:z_top].to_f) if spec[:z_top]

      wall = nil
      if shed_like?(fr)
        wall = build_shed_wall!(grp, fr, at, spec[:wall_names])
        [1.0, -1.0].each { |sg| build_shed_cheek!(grp, fr, at, sg, spec[:wall_names]) }
        build_shed_roof!(grp, fr, at, spec[:roof_material])
        build_shed_trim!(grp, fr, at, spec) if USE_DORMER_TRIM
      elsif fr[:style] == 'hip'
        # the front wall leans its top with the front plane, exactly as a
        # shed's does; the cheeks are the gable's, level under a side
        # plane that only varies across the width.
        wall = build_shed_wall!(grp, fr, at, spec[:wall_names])
        [1.0, -1.0].each { |sg| build_cheek!(grp, fr, at, sg, spec[:wall_names]) }
        build_hip_roof!(grp, fr, at, spec[:roof_material])
        build_hip_trim!(grp, fr, at, spec) if USE_DORMER_TRIM
      else
        wall = build_front_wall!(grp, fr, at, spec[:wall_names])
        [1.0, -1.0].each { |sg| build_cheek!(grp, fr, at, sg, spec[:wall_names]) }
        [1.0, -1.0].each { |sg| build_roof_plane!(grp, fr, at, sg, spec[:roof_material]) }
        build_trim!(grp, fr, at, spec) if USE_DORMER_TRIM
      end
      # THE WINDOW: the hole first, then the body that fills it. Both
      # live INSIDE the dormer group, so they move, are erased and come
      # back with it (rt117, rt120).
      if spec[:window] && wall
        wr = window_rect(fr, spec[:window_w], spec[:window_h])
        if wr
          punch_window!(wall, fr, at, wr)
          build_window_body!(grp, fr, at, wr, spec)
          # WHAT WAS BUILT, NOT WHAT WAS ASKED (2026-09-07). A request the
          # wall cannot hold is pulled back, and the panel has to show the
          # real number - he typed 30 and the wall gave 24, and the stored
          # 30 made the panel say something that was not on the roof.
          grp.set_attribute('InteriorPro', 'window_w', wr[:width])
          grp.set_attribute('InteriorPro', 'window_h', wr[:height])
        end
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
        # EAVE LINE -> HOUSE WALL FACE (2026-09-02B). The roof's eave
        # polygon is built at the wall face plus the overhang, so this
        # distance IS the roof's own overhang - measured off the roof,
        # never typed and never guessed. `flush` placing uses it.
        wall_s: roof.get_attribute('InteriorPro', 'overhang_in').to_f,
        # HOW FAR UP THE SLOPE HE CLICKED. With `follow_click` this
        # becomes the setback, so the ghost walks up and down the roof
        # with the mouse instead of sitting at one typed number - which
        # is what he expected of a placing tool, and what made the limit
        # look arbitrary when it fired (2026-09-02: "לא נותן לי לקרב את
        # הגג... אני לא מבין למה").
        s_click: s_click,
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
      plan = if shed_like?(fr)
               w = fr[:w_deck]
               [[fr[:s_deck], -w], [fr[:s_deck], w],
                [fr[:s_ridge], w], [fr[:s_ridge], -w]]
             elsif fr[:style] == 'hip'
               hip_planes(fr).flatten(1)
             else
               roof_plan(fr, 1.0) + roof_plan(fr, -1.0)
             end
      plan.map { |ss, ww| at.call(ss, ww, 0.0) }
    end

    # THE EAVE IS NOT ONE OF THOSE EDGES (2026-09-02B). Above the ridge
    # or past a hip there is no roof left to die into, so 12" of clear
    # roof is a real rule. The EAVE is the opposite case: reaching it,
    # or hanging over it, is what a dormer flush with the house wall
    # does - the same thing the house's own eave does. So the clearance
    # is measured against every edge EXCEPT the eave, and a corner that
    # is outside the face is allowed when the eave is the edge it went
    # out through.
    def self.eave_edges(pts)
      zmin = pts.map(&:z).min
      n = pts.length
      (0...n).select do |i|
        (pts[i].z - zmin).abs < 0.25 && (pts[(i + 1) % n].z - zmin).abs < 0.25
      end
    end

    def self.nearest_edge(ring, x, y)
      best = nil
      best_i = 0
      n = ring.length
      n.times do |i|
        d = seg_distance(ring[i], ring[(i + 1) % n], x, y)
        if best.nil? || d < best
          best = d
          best_i = i
        end
      end
      best_i
    end

    def self.fits_on_face?(fr, at, face, margin = RIDGE_CLEARANCE)
      return true if face.nil?
      pts = face_points(face)
      return true if pts.nil? || pts.length < 3
      ring = pts.map { |p| [p.x, p.y] }
      eave = eave_edges(pts)
      deck_corners(fr, at).each do |q|
        next if ring_distance(ring, q.x, q.y, eave) >= margin &&
                (point_in_ring?(ring, q.x, q.y) ||
                 eave.include?(nearest_edge(ring, q.x, q.y)))
        warn_nil(format('it would reach the edge of this roof slope - keep ' \
                        '%.0f" clear of the ridge and the hips. Move it, make ' \
                        'it smaller, or change the gablet', margin))
        return false
      end
      true
    end

    # The spec the click actually builds: the panel's numbers, the roof's
    # own frame, and - when the caller is the placing tool - the setback
    # taken from where the mouse is rather than from the panel.
    def self.click_spec(spec, rf)
      s = spec.merge(rf)
      case place_mode(s)
      when 'flush'
        # HIS THIRD OPTION (2026-09-02B): the front wall lands in the
        # plane of the house wall, which is exactly one roof overhang
        # up the slope from the eave line.
        w = wall_setback(rf)
        # no wall under this slope - keep the setback we were handed
        # rather than snapping the dormer down to the eave.
        s[:setback] = w > 0.01 ? w : spec[:setback].to_f
      when 'depth'
        s[:setback] = spec[:setback].to_f
      else
        # 'free' still needs a placing tool behind it. A caller that
        # never set follow_click - Edit, Move, replant, every rt suite -
        # keeps the setback it handed in, exactly as before the modes
        # existed.
        s[:setback] = rf[:s_click].to_f if s[:follow_click] && rf[:s_click]
      end
      s[:setback] = 0.0 if s[:setback].to_f < 0.0
      s
    end

    # free  - the click sets how far up the slope it sits
    # depth - a typed distance from the fascia; the mouse only slides it
    #         sideways ("אם אני קובע עומק הוא רץ רק על העומק")
    # flush - hard against the house wall
    # The old `follow_click` flag still decides for callers written
    # before the modes existed, so nothing that used to work changes.
    def self.place_mode(s)
      m = s[:place_mode].to_s
      return m if %w[free depth flush].include?(m)
      s[:follow_click] ? 'free' : 'depth'
    end

    def self.wall_setback(rf)
      w = rf[:wall_s].to_f
      w > 0.01 ? w : 0.0
    end

    # Put one dormer on a real roof, at (x, y) in plan.
    def self.place_on_roof!(roof, x, y, spec = {})
      rf = roof_frame(roof, x, y)
      return nil if rf.nil?
      s = click_spec(spec, rf)
      fr = frame(s)
      return nil if fr.nil?
      return nil unless fits_on_face?(fr, at_lambda(s), rf[:face])
      s[:roof_material] = rf[:roof_mat] if s[:roof_material].nil?
      if s[:wall_names].nil?
        wm = house_wall_material
        s[:wall_names] = [wm] if wm
      end
      g = add_dormer!(roof.entities, s)
      relay_runs!(roof) unless g.nil? || spec[:no_relay]
      g
    end

    # THE PANELS HAVE TO KNOW (2026-09-02B). He looked up at a dormer from
    # inside the attic and the standing seam ran straight through it -
    # "תיראה שמבתוכו הוא לא חתך את הפאנלים". cut_roof! opens the deck; the
    # runs were laid before the hole existed and nobody told them. So every
    # place, every delete and every replant lays the field again on that
    # roof, off the faces as they are now - and planes_from_faces now hands
    # the tile machine the holes, so a run that crosses one is split.
    def self.relay_runs!(roof)
      return 0 unless defined?(InteriorPro::RoofTilePlace) &&
                      InteriorPro::RoofTilePlace.respond_to?(:relay_runs!)
      InteriorPro::RoofTilePlace.relay_runs!(roof)
    rescue StandardError => e
      puts "[Dormer] relay_runs!: #{e.message}"
      0
    end

    # THE DORMER WEARS THE SAME ROOF AS THE HOUSE (2026-09-05).
    #
    # Until today a dormer roof got the house roof's MATERIAL and nothing
    # else - the texture was right and the standing seam ribs, the pressed
    # panels, the clay pipes simply were not there ("הגגון יקבל את אותם
    # רעפים כמו הגג שהוא ממוקם עליו - לא רק את הצבע").
    #
    # The same machine lays them: one plane per dormer_roof sub-group, into
    # THAT sub-group's own entities - so the pieces travel with the dormer
    # on a move and go with it on a delete, and no transformation has to be
    # carried anywhere. The roof group is asked for the shape NAME, which is
    # what `roof_material` holds on a roof (the material itself comes off
    # the face, which already carries the house's).
    #
    # THE EAVE BAR COMES TOO (he chose it, 2026-09-05): the same 0.57"
    # square bar the main roof's panels die into, sitting on the deck flush
    # with the edge, over the metal edge that is already there.
    def self.place_tiles!(g)
      return 0 unless defined?(InteriorPro::RoofTilePlace) &&
                      InteriorPro::RoofTilePlace.respond_to?(:place_runs!)
      roof = dormer_roof_group(g)
      return 0 if roof.nil?
      name = roof.get_attribute('InteriorPro', 'roof_material').to_s
      return 0 if name.empty?
      made = 0
      # THE FIELD IS ONLY FOR A MATERIAL THAT HAS ONE. Shingles are drawn by
      # the texture, so there are no pieces to lay - but the RIDGE still has
      # a cap, exactly as the house's shingle roof does. That is why the cap
      # sits outside this guard (2026-09-05: "בגגון בשינגלס תוסיף רידג׳
      # קאפ").
      runs = InteriorPro::RoofTileMath.runs?(name)
      g.entities.grep(Sketchup::Group).each do |sub|
        next unless runs
        next unless sub.get_attribute('InteriorPro', 'part').to_s == 'dormer_roof'
        f = top_skin(sub)
        next if f.nil?
        planes = InteriorPro::RoofTilePlace.planes_from_faces([f])
        next if planes.empty?
        mat = f.material
        made += InteriorPro::RoofTilePlace.place_runs!(
          sub, planes, name, material: mat, min_len: stub_len(name)
        ).to_i
        next unless InteriorPro::RoofTilePlace.respond_to?(:place_eave_bars!)
        made += InteriorPro::RoofTilePlace.place_eave_bars!(
          sub, planes, name, material: mat,
          u_range: metal_edge_u(g, sub, planes.first)
        ).to_i
      end
      made += place_ridge_cap!(g, name, cap_material(g))
      puts "[Dormer] tiles on the dormer: #{made}"
      made
    rescue StandardError => e
      puts "[Dormer] place_tiles!: #{e.message}"
      0
    end

    # THE TOP SKIN OF ONE SLAB - BY POSITION, NOT BY NORMAL. The underside
    # of a slab is written with the opposite winding and its normal points
    # UP too, so a normal test hands back both faces and a second field is
    # laid underneath where nobody can see it. The slab has exactly one top
    # and one bottom that are not vertical; the higher one is the roof.
    def self.top_skin(sub)
      fs = sub.entities.grep(Sketchup::Face).reject do |f|
        f.normal.z.abs < 0.05
      end
      return nil if fs.empty?
      fs.max_by { |f| face_mid_z(f) }
    rescue StandardError
      nil
    end

    # The average height of a face's own corners. Its bounding box would do
    # the same job in SketchUp and does not exist in the test stub.
    def self.face_mid_z(f)
      zs = f.vertices.map { |v| v.position.z.to_f }
      zs.empty? ? 0.0 : zs.inject(:+) / zs.length
    rescue StandardError
      0.0
    end

    # A ROOF FACE REDUCED TO WHAT ridge_lines ASKS FOR: its outline and its
    # normal. The two dormer slopes live in two SEPARATE sub-groups, so the
    # cap walk cannot be handed the faces themselves - it would compare two
    # sets of local coordinates and find no shared edge at all. Each face is
    # lifted into the dormer group's own space first, and RoofManager reads
    # `pts` and `normal` off this exactly as it reads them off a real face.
    class CapFace
      attr_reader :pts, :normal

      def initialize(pts, normal)
        @pts = pts
        @normal = normal
      end
    end

    # THE SAME RIDGE CAP THE HOUSE WEARS (2026-09-05). The dormer's two
    # slopes meet on one line - w = 0, from the back where it dies into the
    # main roof out to the front over its own gable - and that line is a
    # ridge by exactly the test the house's own ridges pass: two planes, one
    # each side, both descending away from it.
    #
    # RIDGE_CAP_OVERSHOOT is 0, so the cap ends precisely where the ridge
    # line does and runs neither into the main roof at the back nor past the
    # rake at the front. Boards meet; they never run inside each other.
    #
    # A SHED dormer has one slope and no ridge, so ridge_lines hands back
    # nothing and this quietly lays none - the same answer build_roof! gives
    # a shed roof.
    def self.place_ridge_cap!(g, shape_name, mat)
      rm = roof_manager
      return 0 if rm.nil? || !rm.respond_to?(:build_ridge_caps!) ||
                  !rm.respond_to?(:ridge_lines)
      faces = []
      g.entities.grep(Sketchup::Group).each do |sub|
        next unless sub.get_attribute('InteriorPro', 'part').to_s == 'dormer_roof'
        f = top_skin(sub)
        next if f.nil?
        tr = sub.transformation
        n = f.normal.transform(tr)
        n = n.reverse if n.z < 0
        faces << CapFace.new(f.vertices.map { |v| v.position.transform(tr) }, n)
      end
      return 0 if faces.length < 2
      lines = rm.ridge_lines(faces)
      return 0 if lines.empty?
      lines = trim_cap_lines(g, lines, faces, cap_half(rm, shape_name))
      before = ridge_cap_count(g)
      rm.build_ridge_caps!(g, lines, nil, mat, shape_name)
      ridge_cap_count(g) - before
    rescue StandardError => e
      puts "[Dormer] place_ridge_cap!: #{e.message}"
      0
    end

    # WHERE THE METAL EDGE ACTUALLY ENDS, in this plane's own u
    # (2026-09-05: "הוא יוצא החוצה הוא מעבר למטל אדג").
    #
    # The deck is built to run a little past the boards under it, and at the
    # valley corner that little shows: measured in his model the eave bar
    # finished at 92.36 while the metal edge stopped at 90.80 - 1.56" of bar
    # hanging over the main roof with nothing under it. THE BOARD IT LANDS
    # ON is the measure, not the deck, so the metal edge is asked directly
    # and the bar is cut where it ends. Measured, never assumed: a different
    # overhang or a different valley answers for itself.
    def self.metal_edge_u(g, sub, plane)
      return nil if plane.nil?
      pu = InteriorPro::RoofTileMath.plane_uv(plane[:points], plane[:n])
      return nil if pu.nil?
      inv = sub.transformation.inverse
      us = []
      g.entities.grep(Sketchup::Group).each do |d|
        next unless d.get_attribute('InteriorPro', 'part').to_s == 'dormer_drip'
        t = inv * d.transformation
        d.entities.grep(Sketchup::Face).each do |f|
          f.vertices.each do |v|
            q = v.position.transform(t)
            us << InteriorPro::RoofTileMath.project(
              [q.x.to_f, q.y.to_f, q.z.to_f], pu[:origin], pu[:u], pu[:v]
            )[0]
          end
        end
      end
      return nil if us.empty?
      [us.min, us.max]
    rescue StandardError
      nil
    end

    # NO STUB IN THE BACK CORNER (2026-09-05, he circled it on the dormer:
    # "הבעיה לא היתה בקאפ אלא באחד הפאנלים בסוף הגג").
    #
    # A dormer slope is a TRAPEZOID that closes to nothing at the back, so
    # the last seam line before the valley crosses only a sliver of roof.
    # Measured in his model: five ribs 26.87" long and one 4.00" long, alone
    # in the corner, reading as a loose tab hanging over the main roof.
    #
    # RoofTilePlace already has the rule - min_run_len, "a sliver at the tip
    # of a hip gets nothing, half a pipe poking out of a corner looks worse
    # than a bare stretch of texture". Its 3" was set for the clay tile's
    # short courses on a house roof. On a dormer the measure is the cap: a
    # run no longer than the ridge cap is wide is a scrap in the corner the
    # cap and the valley already close, not a panel. Nothing on the house
    # roof changes - this number is handed to the dormer's runs only.
    def self.stub_len(shape_name)
      rm = roof_manager
      w = rm.respond_to?(:cap_width_for) ? rm.cap_width_for(shape_name).to_f : 0.0
      d = if defined?(InteriorPro::RoofTilePlace) &&
             InteriorPro::RoofTilePlace.respond_to?(:min_run_len)
            InteriorPro::RoofTilePlace.min_run_len.to_f
          else
            0.0
          end
      [w, d].max
    rescue StandardError
      0.0
    end

    # THE CAP CANNOT END ON A NEEDLE (2026-09-05, he circled it: "תראה
    # שאחת הקצוות יוצאות החוצה").
    #
    # A gable dormer's two slopes are TRAPEZOIDS, not rectangles: at the
    # front they are the full deck width, and they close to NOTHING at the
    # back, where the dormer dies into the main roof. The ridge line runs
    # the whole way, so a cap laid along all of it runs past the valleys
    # in the last few inches and its corners hang in the air over the main
    # roof. Measured in his model: 3.54" out at the back end, which is
    # exactly half the cap on a 45 degree valley.
    #
    # So each end is walked INWARDS until the roof under it can carry the
    # cap's full width - both edges, not just the centre line. The front
    # end is already full width and does not move at all. The number is
    # never assumed: it is asked of the outline, so a shallower valley or
    # a wider cap answers for itself.
    def self.trim_cap_lines(g, lines, faces, half)
      polys = faces.map { |cf| cf.pts.map { |q| [q.x.to_f, q.y.to_f] } }
      return lines if polys.empty? || half <= 0.0
      lines.map do |(ka, za, kb, zb, sides)|
        len = Math.hypot(kb[0] - ka[0], kb[1] - ka[1])
        next [ka, za, kb, zb, sides] if len < 1.0e-6
        d = [(kb[0] - ka[0]) / len, (kb[1] - ka[1]) / len]
        u = [-d[1], d[0]]
        a = die_in?(g, ka, za) ? cap_end_in(ka, d, u, half, polys, len) : ka
        b = die_in?(g, kb, zb) ? cap_end_in(kb, [-d[0], -d[1]], u, half, polys, len) : kb
        [a, za, b, zb, sides]
      end
    end

    # ONLY AN END THAT DIES INTO THE HOUSE ROOF IS PULLED BACK (2026-09-05).
    #
    # The first cut of this walked BOTH ends in, and on a HIP dormer that
    # ate the caps on the two diagonals: "שהיפ הוא לא יושב עד הסופ
    # באלכסונים". A hip's lower end is the dormer's own outer corner - the
    # roof narrows to a point there just as it does at a valley, and a cap
    # running out to that corner is what every hip on the house does.
    #
    # The end that must be pulled back is the other kind: the one that lands
    # ON the main roof's surface, where the dormer dies into it and the cap
    # would otherwise hang over the house. One test tells them apart, and it
    # is a measurement: is this end at the height the house roof has at that
    # spot? The dormer carries the roof plane it was placed on - z0, slope,
    # base and along - so the answer is exact.
    def self.die_in?(g, k, z)
      z0 = g.get_attribute('InteriorPro', 'z0').to_f
      sl = g.get_attribute('InteriorPro', 'slope').to_f
      base = Array(g.get_attribute('InteriorPro', 'base_xy')).map(&:to_f)
      # `s` RUNS ALONG `into`, NOT ALONG `along` - see at_lambda: the frame
      # is base + into*s + along*w. Reading the wrong one measured the
      # ridge's die-in across the dormer instead of up the slope and the
      # test came back false everywhere.
      into = Array(g.get_attribute('InteriorPro', 'into_xy')).map(&:to_f)
      along = Array(g.get_attribute('InteriorPro', 'along_xy')).map(&:to_f)
      into = [-along[1], along[0]] if into.length < 2 && along.length >= 2
      return false if base.length < 2 || into.length < 2
      s = ((k[0] - base[0]) * into[0]) + ((k[1] - base[1]) * into[1])
      (z.to_f - (z0 + (s * sl))).abs < 2.0
    rescue StandardError
      false
    end

    # Walk one end in until BOTH edges of the cap land on roof. Gives the
    # end back untouched when nothing on the way in carries it, so a shape
    # this was never written for keeps exactly the cap it had.
    def self.cap_end_in(k, d, u, half, polys, len)
      t = 0.0
      step = 0.25
      while t <= len / 2.0
        p = [k[0] + (d[0] * t), k[1] + (d[1] * t)]
        carried = [-1.0, 1.0].all? do |sg|
          q = [p[0] + (u[0] * half * sg), p[1] + (u[1] * half * sg)]
          polys.any? { |pl| InteriorPro::RoofTileMath.poly_contains?(pl, q) }
        end
        return [p[0], p[1]] if carried
        t += step
      end
      k
    end

    def self.cap_half(rm, shape_name)
      return 0.0 unless rm.respond_to?(:cap_width_for)
      rm.cap_width_for(shape_name).to_f / 2.0
    rescue StandardError
      0.0
    end

    def self.ridge_cap_count(g)
      g.entities.grep(Sketchup::Group).count do |s|
        s.get_attribute('InteriorPro', 'part').to_s == 'ridge_cap'
      end
    rescue StandardError
      0
    end

    # The cap rides on the roof, so it wears the roof's material - read off
    # the dormer's own slab, which already carries the house's.
    def self.cap_material(g)
      g.entities.grep(Sketchup::Group).each do |sub|
        next unless sub.get_attribute('InteriorPro', 'part').to_s == 'dormer_roof'
        f = top_skin(sub)
        return f.material unless f.nil? || f.material.nil?
      end
      nil
    rescue StandardError
      nil
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
      place_tiles!(grp) unless spec[:no_tiles]
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
      into, = frame_dirs(at)
      paint_wall!(sub, names, [-into[0], -into[1], 0.0])
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
      _, along = frame_dirs(at)
      paint_wall!(sub, names, [along[0] * sign, along[1] * sign, 0.0])
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

    # ---------- A WINDOW IN THE FRONT WALL (2026-09-06) -----------------
    #
    # His rule, in his words: 48 x 24 is the MAXIMUM - "אפשרי להתחיל עם
    # אופציה 2 זה יהיה המקסימום" - and on a smaller gablet the window
    # simply keeps 6" clear on every side. It may never run into the
    # thickness of the cheeks ("שלא יוכל להיכנס לתוך עובי הקירות"), so
    # the width is measured off the INSIDE faces, not the outside ones.
    # It is punched into the front wall INSIDE the dormer group, so it
    # travels with the dormer and is erased with it, exactly like the
    # tiles (rt109).
    #
    # Methods, not constants: a constant is not re-read by reload!.
    def self.window_max_w; 48.0; end
    def self.window_max_h; 24.0; end
    def self.window_margin; 6.0; end
    def self.window_min_w; 18.0; end
    def self.window_min_h; 12.0; end

    # The top of the front wall over a window whose own half-width is hw -
    # the LOWEST point of it, so a gable's slope never eats the head.
    def self.wall_top_over(fr, hw)
      return shed_top(fr, fr[:s_front]) if shed_like?(fr) || fr[:style] == 'hip'
      top_z(fr, hw) - fr[:roof_thickness].to_f
    end

    # THE MOST THE WALL ITSELF ALLOWS. His original rule, unchanged: 6"
    # of wall clear on every side, and never nearer than an inch to the
    # INSIDE faces of the cheeks - "שלא יוכל להיכנס לתוך עובי הקירות".
    def self.window_cap_w(fr)
      clear_w = 2.0 * (fr[:half].to_f - fr[:thickness].to_f)
      [2.0 * fr[:half].to_f - 2.0 * window_margin, clear_w - 2.0].min
    end

    # The head is measured AFTER the width is settled, because a narrower
    # window sits under a higher part of a gable's slope.
    def self.window_cap_h(fr, width)
      wall_top_over(fr, width / 2.0) - fr[:z_front].to_f - 2.0 * window_margin
    end

    # Where the window sits, in the dormer's own frame: w across the wall,
    # z in the world. nil - and a reason - when nothing fits.
    #
    # NOTHING TYPED is exactly what rt117 pinned: 48 x 24, or 6" of wall
    # all round on a gablet too small for that. That is the default and it
    # has not moved a digit.
    #
    # A TYPED SIZE IS CAPPED BY THE WALL, NOT BY 48 x 24 (2026-09-07). He
    # typed 30 for the height, got 24 without a word, and said the panel
    # did nothing. Asked what the ceiling should be once the panel can
    # type, he chose: "כמה שהקיר מרשה". So 48 x 24 stays the DEFAULT and
    # the wall is the limit - his front wall is 72" tall and there was no
    # reason it could not hold a taller window.
    def self.window_rect(fr, want_w = nil, want_h = nil)
      cap_w = window_cap_w(fr)
      return warn_nil('the gablet is too narrow for a window') if
        cap_w < window_min_w
      width = if want_w.to_f > 0.0
                [[want_w.to_f, window_min_w].max, cap_w].min
              else
                [window_max_w, cap_w].min
              end
      cap_h = window_cap_h(fr, width)
      return warn_nil('the front wall is too short for a window') if
        cap_h < window_min_h
      height = if want_h.to_f > 0.0
                 [[want_h.to_f, window_min_h].max, cap_h].min
               else
                 [window_max_h, cap_h].min
               end
      # centred in the clear wall: the two margins come out equal, which
      # is what he drew back at me.
      { w: 0.0, width: width, height: height,
        z: (fr[:z_front].to_f + wall_top_over(fr, width / 2.0)) / 2.0 }
    end

    # The hole itself: the rectangle is drawn on the outer face and on the
    # inner face, both small faces are erased so each loop becomes a hole,
    # and four reveal faces close the gap between them - so the wall stays
    # a closed solid with a window-shaped tunnel through it.
    def self.punch_window!(sub, fr, at, rect = nil)
      r = rect || window_rect(fr)
      return nil if r.nil? || sub.nil? || !sub.valid?
      s_o = fr[:s_front]
      s_i = fr[:s_front] + fr[:thickness]
      w0 = r[:w] - r[:width] / 2.0
      w1 = r[:w] + r[:width] / 2.0
      z0 = r[:z] - r[:height] / 2.0
      z1 = r[:z] + r[:height] / 2.0
      box = [[w0, z0], [w1, z0], [w1, z1], [w0, z1]]
      outer = box.map { |w, z| at.call(s_o, w, z) }
      inner = box.map { |w, z| at.call(s_i, w, z) }
      # Drawing the rectangle on a face SPLITS it; erasing the small face
      # leaves its loop behind as a HOLE. (The cloud stub has no face
      # splitting and no Face#erase!, so it just gets the reveal faces -
      # the real hole is only ever seen on his machine.)
      [outer, inner].each do |ring|
        f = add_face!(sub, ring)
        next unless f.respond_to?(:erase!)
        f.erase! if !f.respond_to?(:valid?) || f.valid?
      end
      4.times do |i|
        j = (i + 1) % 4
        add_face!(sub, [outer[i], outer[j], inner[j], inner[i]])
      end
      sub.set_attribute('InteriorPro', 'window_w', r[:width])
      sub.set_attribute('InteriorPro', 'window_h', r[:height])
      r
    rescue StandardError => e
      puts "[Dormer] punch_window!: #{e.class}: #{e.message}"
      nil
    end

    # ---------- THE WINDOW BODY (2026-09-07) ----------------------------
    #
    # HIS INSTRUCTION, IN HIS WORDS: "תעתיק את הקוד של החלון ... מהחלונות
    # שכבר קיימים ברשימת החלונות." So the gablet window is not a second
    # window builder - it IS the house window. Everything here does is
    # put an empty group in the hole, point it the right way, and hand it
    # to WindowTool#casement_body!, which is the same call every window
    # in a wall goes through.
    #
    # That is why the split in window_tool.rb was needed: the dormer is
    # built inside its own start_operation, and nesting SketchUp
    # operations is not safe. `casement_body!` is the geometry with the
    # operation taken off it.
    #
    # Three types. The fixed window he picked first, and the two he asked
    # to have as choices beside it.
    #
    # THE THIRD ONE CHANGED (2026-09-07, after he saw it): the drawing
    # offered two casements swinging out, and he said no - "אני רוצה
    # שהסוג חלון השלישי יהיה חלון שנפתח מלמעלה למטה, לא צריך דאבל
    # קייסמנט." A hung window it is: one rail across the middle, the
    # sashes run up and down. WindowTool already builds exactly that
    # (window_grid -> [1, 2], build_hung_panes).
    def self.window_types
      ['Picture', 'Slider XO', 'Double Hung']
    end

    def self.window_type_of(spec)
      t = if spec.is_a?(Hash)
            spec[:window_type] || spec['window_type']
          else
            spec
          end
      window_types.include?(t.to_s) ? t.to_s : window_types.first
    end

    def self.window_sash_depth; 2.0; end
    def self.window_jamb_in;    1.0; end

    # WHERE THE BODY GOES, PURE. WindowTool builds around the group's
    # ORIGIN with u along the wall and v into it, so the origin is the
    # centre of the hole ON THE OUTSIDE FACE, u is the dormer's `along`
    # and v is its `into` - which is why clicked_side is -1: for the
    # window tool, -n is outdoors.
    #
    # The jamb runs `interior_depth` past the sash, and on a thin gablet
    # wall that is cut back so it can never stand out into the room.
    def self.window_place(fr, at, r)
      into, along = frame_dirs(at)
      th = fr[:thickness].to_f
      { origin: at.call(fr[:s_front].to_f, r[:w].to_f, r[:z].to_f),
        unit: along, n: into, clicked_side: -1, thickness: th,
        interior_depth: [window_jamb_in, [th - window_sash_depth, 0.25].max].min }
    end

    def self.build_window_body!(grp, fr, at, rect = nil, spec = {})
      r = rect || window_rect(fr)
      return nil if r.nil? || grp.nil? || !grp.valid?
      return warn_nil('the window tool is not loaded') unless
        defined?(InteriorPro::WindowTool) && InteriorPro::WindowTool.respond_to?(:new)

      type = window_type_of(spec)
      pl   = window_place(fr, at, r)
      win  = new_part!(grp, 'InteriorPro_DormerWindow', 'dormer_window')

      # THE EDIT TOOL FINDS IT BY THIS (2026-09-07). WindowManager picks
      # the deepest thing in the click path with type == 'window', so a
      # gablet window answers to Edit Window exactly like a house window;
      # `dormer_window` is how the panel knows to show the short form.
      win.set_attribute('InteriorPro', 'type', 'window')
      win.set_attribute('InteriorPro', 'dormer_window', true)
      win.set_attribute('InteriorPro', 'window_type', type)
      win.set_attribute('InteriorPro', 'width_in', r[:width].to_f)
      win.set_attribute('InteriorPro', 'height_in', r[:height].to_f)
      win.set_attribute('InteriorPro', 'interior_depth_in', pl[:interior_depth])
      win.set_attribute('InteriorPro', 'frame_width_in', 1.0)
      win.set_attribute('InteriorPro', 'area_sqft',
                        (r[:width].to_f * r[:height].to_f) / 144.0)
      win.set_attribute('InteriorPro', 'window_w', r[:width].to_f)
      win.set_attribute('InteriorPro', 'window_h', r[:height].to_f)

      win.entities.add_cpoint(Geom::Point3d.new(0, 0, 0)) if
        win.entities.respond_to?(:add_cpoint)
      win.transformation = Geom::Transformation.new(pl[:origin]) if
        win.respond_to?(:transformation=)

      tool = InteriorPro::WindowTool.new
      tool.window_type           = type
      tool.preset_name           = type
      tool.width                 = r[:width].to_f
      tool.height                = r[:height].to_f
      tool.interior_depth        = pl[:interior_depth]
      tool.arch_rise             = 0.0
      tool.glass_grid_style      = 'none'
      tool.exterior_casing_style = 'none'
      tool.interior_casing_style = 'none'
      tool.casement_body!(win,
                          Geom::Vector3d.new(pl[:unit][0], pl[:unit][1], 0.0),
                          Geom::Vector3d.new(pl[:n][0], pl[:n][1], 0.0),
                          pl[:thickness], pl[:clicked_side])
      win
    rescue StandardError => e
      puts "[Dormer] build_window_body!: #{e.class}: #{e.message}"
      nil
    end

    # The Edit Window panel's way in.
    #
    # IT REBUILDS THE FRONT WALL AND THE WINDOW, AND NOTHING ELSE
    # (2026-09-07). It used to go through replace_dormer!, which erases
    # the whole gablet and builds it again - and that heals the roof hole,
    # RELAYS THE ENTIRE TILE FIELD and cuts the hole afresh. On his metal
    # roof he watched a panel come back under the window and said the
    # thing "affects other stuff instead of the window". Measured in his
    # own model: one window change relaid 44 runs across the whole roof.
    #
    # So now only the two parts that actually carry the window are erased
    # and built again, inside the dormer that is standing. The roof, the
    # cheeks, the trim, the ridge cap and every tile are left untouched.
    def self.set_window!(dormer, settings = {})
      return nil if dormer.nil? || !dormer.respond_to?(:valid?) || !dormer.valid?
      spec = dormer_spec(dormer)
      return warn_nil('this gablet cannot be read') if spec.nil?
      fr = frame(spec)
      return nil if fr.nil?
      at = at_lambda(spec)

      pick = lambda { |k| settings[k].nil? ? settings[k.to_sym] : settings[k] }
      type = window_type_of(pick.call('window_type'))
      r = window_rect(fr, pick.call('width').to_f, pick.call('height').to_f)
      return nil if r.nil?

      # the paint it is WEARING, read off the wall that is standing, so
      # rebuilding one wall cannot repaint the gablet by accident.
      names = wall_names_of(dormer) || begin
        wm = house_wall_material
        wm ? [wm] : nil
      end

      dormer.entities.grep(Sketchup::Group).to_a.each do |sub|
        next unless sub.respond_to?(:valid?) && sub.valid?
        part = sub.get_attribute('InteriorPro', 'part').to_s
        sub.erase! if %w[dormer_front dormer_window].include?(part)
      end

      wall = if shed_like?(fr) || fr[:style] == 'hip'
               build_shed_wall!(dormer, fr, at, names)
             else
               build_front_wall!(dormer, fr, at, names)
             end
      return warn_nil('the front wall could not be rebuilt') if wall.nil?
      punch_window!(wall, fr, at, r)
      build_window_body!(dormer, fr, at, r, spec.merge(window_type: type))

      dormer.set_attribute('InteriorPro', 'window', true)
      dormer.set_attribute('InteriorPro', 'window_type', type)
      dormer.set_attribute('InteriorPro', 'window_w', r[:width])
      dormer.set_attribute('InteriorPro', 'window_h', r[:height])
      dormer
    rescue StandardError => e
      puts "[Dormer] set_window!: #{e.class}: #{e.message}"
      nil
    end

    # The wall materials this gablet is actually wearing - the exterior
    # texture and the interior colour - read off the front wall before it
    # is erased. Same idea as cap_material for the roof slab.
    def self.wall_names_of(dormer)
      sub = dormer.entities.grep(Sketchup::Group).find do |s|
        s.respond_to?(:valid?) && s.valid? &&
          s.get_attribute('InteriorPro', 'part').to_s == 'dormer_front'
      end
      return nil if sub.nil?
      names = sub.entities.grep(Sketchup::Face)
                 .map { |f| f.material && f.material.name }.compact.uniq
      ext = names.find { |n| !n.to_s.start_with?('#') }
      int = names.find { |n| n.to_s.start_with?('#') }
      return nil if ext.nil? && int.nil?
      [ext, int]
    rescue StandardError
      nil
    end

    # What the Edit Window panel is allowed to ask for on THIS gablet:
    # the biggest window its front wall has room for, and the smallest
    # window we build at all. Typing outside that is pulled back in.
    def self.window_limits(dormer)
      spec = dormer_spec(dormer)
      return nil if spec.nil?
      fr = frame(spec)
      return nil if fr.nil?
      cap_w = window_cap_w(fr)
      return nil if cap_w < window_min_w
      # the head is measured at the width this window actually has, so a
      # narrow window is told about the extra height it may take.
      now_w = spec[:window_w].to_f > 0.0 ?
              [[spec[:window_w].to_f, window_min_w].max, cap_w].min :
              [window_max_w, cap_w].min
      cap_h = window_cap_h(fr, now_w)
      return nil if cap_h < window_min_h
      { max_w: cap_w, max_h: cap_h,
        min_w: window_min_w, min_h: window_min_h }
    rescue StandardError
      nil
    end

    # The window group inside a dormer, when there is one.
    def self.window_of(dormer)
      return nil if dormer.nil? || !dormer.respond_to?(:entities)
      # AN ERASED PART IS NOT A PART. set_window! erases the old window
      # and builds a new one in the same dormer, and an erased group can
      # still be sitting in the entity list - so the answer is the LIVE
      # one, never the first one that happens to be there.
      dormer.entities.grep(Sketchup::Group).find do |s|
        s.respond_to?(:valid?) && s.valid? &&
          s.get_attribute('InteriorPro', 'part').to_s == 'dormer_window'
      end
    rescue StandardError
      nil
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
      into, = frame_dirs(at)
      paint_wall!(sub, names, [-into[0], -into[1], 0.0])
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
      _, along = frame_dirs(at)
      paint_wall!(sub, names, [along[0] * sign, along[1] * sign, 0.0])
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

    # ---------- THE HIP GABLET (2026-09-02, style 4 of 4) ---------------
    #
    # Three planes at one pitch: a triangle over the front and a quad
    # down each side, meeting on two 45 degree hips. The ridge starts
    # where those hips meet - one half width back from the front eave -
    # and runs back to the same die-in point every other style uses.
    #
    # EVERY OPEN EDGE IS A LEVEL EAVE at one height, which is what makes
    # the trim simple: one band across the front, mitred at both corners,
    # and a board down each side cut on the roof at the back with a
    # matching 45 at the front. No rake anywhere.
    def self.hip_planes(fr)
      wd = fr[:w_deck]
      sd = fr[:s_deck]
      s_hipd = sd + wd
      front = [[sd, -wd], [sd, wd], [s_hipd, 0.0]]
      sides = [1.0, -1.0].map do |sg|
        [[sd, wd * sg], [fr[:s_valley_deck], wd * sg],
         [fr[:s_ridge], 0.0], [s_hipd, 0.0]]
      end
      [front] + sides
    end

    def self.build_hip_roof!(grp, fr, at, mat)
      rt = fr[:roof_thickness]
      hip_planes(fr).each do |plan|
        sub = new_part!(grp, 'InteriorPro_DormerRoof', 'dormer_roof')
        top = plan.map { |ss, ww| at.call(ss, ww, deck_z(fr, ss, ww)) }
        bot = plan.map { |ss, ww| at.call(ss, ww, deck_z(fr, ss, ww) - rt) }
        ring!(sub, top, bot, plan.length)
        next unless mat
        sub.entities.grep(Sketchup::Face).each do |f|
          f.material = mat
          f.back_material = mat
        end
      end
      true
    end

    # The same five-corner outline the gable uses, but the front edge is
    # an EAVE here, not a gable end.
    def self.hip_ring(fr, at)
      we = fr[:w_edge]
      sw = [[[fr[:s_rake], -we], 'eave'], [[fr[:s_rake], we], 'side'],
            [[fr[:s_valley], we], 'valley'], [[fr[:s_ridge], 0.0], 'valley'],
            [[fr[:s_valley], -we], 'side']]
      pts = sw.map { |(ss, ww), _| q = at.call(ss, ww, 0.0); [q.x, q.y] }
      labs = sw.map(&:last)
      n = pts.length
      if signed_area(pts) < 0.0
        pts = pts.reverse
        labs = (0...n).map { |i| labs[(n - 2 - i) % n] }
      end
      { poly: pts, labels: labs,
        # everything but the front edge is built by hand or not at all
        gable_flags: labs.map { |l| l != 'eave' } }
    end

    # One side board, mitred 45 at the front corner and cut on the roof
    # at the back. `k_out` / `k_in` are the two faces measured OUTWARD
    # from the side line, and the mitre is simply the fact that a corner
    # of a band offset by k sits k along BOTH edges - so the face at k
    # starts at s_rake - k.
    def self.build_hip_side!(sub, fr, at, depth, k_out, k_in, hang = 0.0)
      z_top = fr[:z_edge] - fr[:roof_thickness] - hang
      p_out = eave_profile(fr, z_top, depth, fr[:s_rake] - k_out)
      p_in  = eave_profile(fr, z_top, depth, fr[:s_rake] - k_in)
      return nil if p_out.nil? || p_in.nil? || p_out.length != p_in.length
      [1.0, -1.0].each do |sg|
        extrude_sz2!(sub, p_out, p_in, at,
                     (fr[:w_edge] + k_out) * sg, (fr[:w_edge] + k_in) * sg)
      end
      sub
    end

    def self.build_hip_trim!(grp, fr, at, spec = {})
      dep = fascia_depth(spec)
      return false if dep <= 0.0
      rm = roof_manager
      return false if rm.nil?
      ft = rm::FASCIA_THICK
      dt = rm::DRIP_THICK
      dd = rm::DRIP_DEPTH
      mat = trim_material(trim_color(spec))
      ring = hip_ring(fr, at)
      poly = ring[:poly]
      band_top = fr[:z_edge] - fr[:roof_thickness]

      # THE FRONT: RoofManager's own band, mitred at both hip corners -
      # a level board meeting a level board at 90 degrees, which is what
      # a mitre is for. It never meets the main roof, so nothing is cut.
      fas = new_part!(grp, 'InteriorPro_DormerFascia', 'dormer_fascia')
      rm.build_band!(fas, poly, -ft, 0.0, band_top, band_top - dep,
                     ring[:gable_flags], nil)
      # THE SIDES: level too, but the roof climbs into them, so they are
      # built here with the diagonal end - and with the matching 45 at
      # the front, so fascia meets fascia on one seam.
      build_hip_side!(fas, fr, at, dep, 0.0, -ft)
      paint!(fas, mat)

      drip = new_part!(grp, 'InteriorPro_DormerDrip', 'dormer_drip')
      rm.build_band!(drip, poly, 0.0, dt, band_top, band_top - dd,
                     ring[:gable_flags], nil)
      build_hip_side!(drip, fr, at, dd, dt, 0.0)
      paint!(drip, mat)

      style, sloped = soffit_choice(spec)
      if style != 'none' && fr[:overhang] >= 1.0
        scol = trim_material(soffit_color(spec, style))
        sof = new_part!(grp, 'InteriorPro_DormerSoffit', 'dormer_soffit')
        sb = rm.soffit_band(fr[:overhang], dep, true, band_top)
        rise = sloped ? fr[:pitch] * fr[:overhang] : 0.0
        if sb
          rm.build_band!(sof, poly, sb[:k_in], sb[:k_out], sb[:z_top], sb[:z_bot],
                         ring[:gable_flags], nil, nil, 0.0, rise)
        end
        thick = soffit_thick
        oh = fr[:overhang]
        p_out = eave_soffit_profiles(fr, band_top, dep, fr[:s_rake] + ft,
                                     thick, 0.0)
        p_in  = eave_soffit_profiles(fr, band_top, dep, fr[:s_rake] + oh,
                                     thick, rise)
        if p_out && p_in && p_out[0].length == p_in[1].length
          [1.0, -1.0].each do |sg|
            extrude_sz2!(sof, p_out[0], p_in[1], at,
                         (fr[:w_edge] - ft) * sg, fr[:half] * sg)
          end
        end
        paint!(sof, scol)
      end
      true
    rescue StandardError => e
      puts "[Dormer] build_hip_trim!: #{e.class}: #{e.message}"
      puts e.backtrace.first(4) if e.backtrace
      false
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
            # ...and the wedge that closes the step between that board
            # and the flat eave soffit under it (2026-09-09, see
            # build_rake_return!). A sloped soffit has no such step.
            build_rake_return!(rs, fr, at, dep, z_top) unless sloped
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
    # A cross-section in (w, z) - across the dormer and up - swept along
    # s. extrude_sz!'s twin, for a piece whose shape changes ACROSS the
    # dormer instead of along it.
    def self.extrude_wz!(sub, prof, at, s_a, s_b)
      a = prof.map { |w, z| at.call(s_a, w, z) }
      b = prof.map { |w, z| at.call(s_b, w, z) }
      add_face!(sub, a)
      add_face!(sub, b.reverse)
      prof.length.times do |i|
        j = (i + 1) % prof.length
        add_face!(sub, [a[i], a[j], b[j], b[i]])
      end
      sub
    end

    # THE BOX RETURN AT THE GABLE CORNER (2026-09-09, the user with a
    # photo: "יש רווח בין האיבס לפשייה, תסגור אותו כמו בגגות").
    #
    # WHAT WAS OPEN. The rake soffit is pulled back one overhang at the
    # corner (rake_meet_span), so its near end stands at |w| = w_edge -
    # overhang - and there its underside is overhang x pitch ABOVE the
    # flat eave soffit's top face. Measured on his dormer: eave soffit
    # top 234.01, rake soffit underside 235.76 - a 1.75" slot you could
    # see straight into, running from that end out to where the climbing
    # rake finally drops to the eave soffit's own level.
    #
    # WHAT CLOSES IT. The same wedge a real boxed eave has: a triangle
    # in (w, z) between the eave soffit's TOP and the rake board's
    # UNDERSIDE, swept the overhang's depth from the rake plane inward -
    # exactly the span the rake soffit covers. It ends where the rake
    # underside meets the soffit top, w_edge - thick/pitch, so it never
    # runs past the corner or inside the boards it meets (BOARDS MEET).
    #
    # NOT for a SLOPED soffit: there the board tilts with the roof and
    # there is no step to close - it is left exactly as it was.
    # ROOF_MANAGER IS NOT TOUCHED: this is dormer geometry, built here.
    def self.build_rake_return!(sub, fr, at, dep, z_top)
      oh = fr[:overhang].to_f
      pitch = fr[:pitch].to_f
      we = fr[:w_edge].to_f
      thick = soffit_thick
      return false if oh < 1.0 || pitch <= 0.0 || dep <= 0.0
      z_bot = z_top - dep                 # the fascia's bottom line
      z_e = z_bot + thick                 # the flat eave soffit's TOP
      z_r = z_bot + oh * pitch            # the rake soffit's underside
      return false if z_r - z_e < 0.05    # nothing to close
      reach = thick / pitch               # where the rake meets that top
      return false if reach >= oh - 0.05  # ...already past the return
      w1 = we - oh
      w2 = we - reach
      s0 = fr[:s_rake].to_f
      [1.0, -1.0].each do |sg|
        prof = [[w1 * sg, z_e], [w2 * sg, z_e], [w1 * sg, z_r]]
        extrude_wz!(sub, prof, at, s0, s0 + oh)
      end
      true
    rescue StandardError => e
      puts "[Dormer] build_rake_return!: #{e.message}"
      false
    end

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

    # ---------- EDIT, MOVE, DELETE (2026-09-02) -------------------------
    #
    # All three start here: read a built dormer back into the spec that
    # made it, so frame() gives the identical numbers and the hole can be
    # found again to the thousandth.
    def self.dormer_spec(g)
      return nil unless g.respond_to?(:get_attribute) &&
                        g.get_attribute('InteriorPro', 'type') == 'dormer'
      a = lambda { |k| g.get_attribute('InteriorPro', k) }
      base  = Array(a.call('base_xy')).map(&:to_f)
      along = Array(a.call('along_xy')).map(&:to_f)
      into  = Array(a.call('into_xy')).map(&:to_f)
      return nil if base.length < 2 || along.length < 2
      spec = { z0: a.call('z0').to_f, slope: a.call('slope').to_f,
               setback: a.call('setback').to_f, width: a.call('width').to_f,
               length: a.call('length').to_f, pitch: a.call('pitch').to_f,
               thickness: a.call('thickness').to_f,
               roof_thickness: a.call('roof_thickness').to_f,
               overhang: a.call('overhang').to_f,
               style: a.call('style').to_s,
               base: base, along: along }
      spec[:into] = into if into.length >= 2
      fd = a.call('fascia_depth')
      spec[:fascia_depth] = fd.to_f unless fd.nil?
      pm = a.call('place_mode').to_s
      spec[:place_mode] = pm if %w[free depth flush].include?(pm)
      wi = a.call('window')
      spec[:window] = (wi == true || wi.to_s == 'true') unless wi.nil?
      wt = a.call('window_type').to_s
      spec[:window_type] = wt if window_types.include?(wt)
      ww = a.call('window_w')
      spec[:window_w] = ww.to_f if ww.to_f > 0.0
      wh = a.call('window_h')
      spec[:window_h] = wh.to_f if wh.to_f > 0.0
      zt = a.call('z_top')
      spec[:z_top] = zt.to_f unless zt.nil?
      spec
    end

    # The roof GROUP itself, when the entities are not enough - relaying the
    # tile field needs the group, not its entity list.
    def self.dormer_roof_group(g)
      InteriorPro::RoofManager.roofs.find do |r|
        r.respond_to?(:valid?) && r.valid? && r.entities.to_a.include?(g)
      end
    rescue StandardError
      nil
    end

    # The roof group a dormer is standing in - it was built into that
    # group's entities, so its parent IS its roof.
    def self.dormer_roof(g)
      par = begin
        g.parent
      rescue StandardError
        nil
      end
      return par.entities if par.respond_to?(:entities) && par.entities
      # Fallback, and the one the test stub needs: find the roof group
      # whose own entities hold this dormer.
      model = Sketchup.active_model
      found = nil
      walk = lambda do |ents, depth|
        ents.grep(Sketchup::Group).each do |grp|
          if grp.get_attribute('InteriorPro', 'type') == 'roof'
            found = grp.entities if grp.entities.to_a.include?(g)
          end
          walk.call(grp.entities, depth + 1) if found.nil? && depth < 2
          break if found
        end
      end
      walk.call(model.entities, 0)
      found
    rescue StandardError
      nil
    end

    # THE INVERSE OF cut_roof!. Erase whatever is still standing in the
    # opening (the rim between the two skins) and lay each skin back over
    # it, on its own plane - measured off the roof's own faces, not
    # assumed, because the slab's thickness is the roof's business.
    def self.heal_roof!(ents, fr, at, mat = nil)
      plan = opening_plan(fr)
      return 0 if plan.nil?
      flat = plan.map { |ss, w| at.call(ss, w, 0.0) }
      cx = flat.map(&:x).inject(:+) / flat.length
      cy = flat.map(&:y).inject(:+) / flat.length

      # EVERY SKIN PLANE THAT IS ACTUALLY OVER THIS HOLE - and no other
      # (2026-09-02B). Without the covers_point? test this collected a
      # plane from every sloping face in the whole roof group: on a hip
      # roof that is four slopes, so healing one dormer laid a patch on
      # each of them and left slabs hanging in mid-air over the house
      # (the user: "יש כל מיני שכבות צפות באוויר מעל"), while the hole
      # it was asked to close stayed open. cut_roof! has always tested
      # this; heal_roof! is its inverse and has to test the same thing.
      zs = []
      ents.grep(Sketchup::Face).each do |f|
        next if f.normal.z.abs < 0.2
        next unless covers_point?(f, cx, cy)
        z_at = plane_z_lambda(f)
        next if z_at.nil?
        z = z_at.call(cx, cy)
        next if zs.any? { |(zz, _)| (zz - z).abs < 0.01 }
        zs << [z, z_at]
        mat ||= f.material
      end
      return 0 if zs.empty?

      # THE HOLE THAT IS REALLY THERE (2026-09-02B). Everything below
      # used to compute the ring again from the frame and hand it to
      # add_face. Three things were measured wrong with that, in his own
      # model, after he saw the opening survive both Delete and Move:
      #   * ents.add_face(ring) on a ring that is already an inner loop
      #     RETURNS THE SURROUNDING FACE and creates nothing - it
      #     reported "2 skin(s) back" over a hole you could see through.
      #     Edge#find_faces is the call that skins a loop already there.
      #   * The RIM - the slab's cut sides - has to go AFTER the skin,
      #     not before: find_faces rebuilds every face those edges can
      #     bound, the rim included (measured: rim 5, skinned +5).
      #   * The SEAM between the new skin and the slope is two coplanar
      #     faces with an edge between them, and that edge draws as a
      #     line on the roof ("אבל עדיין רואים אותו בגג"). Erased, the
      #     two merge into one face and the roof is whole again.
      # So: find the loops that ARE in the opening, then skin, rim, seam.
      real = []
      if ents.grep(Sketchup::Face).first.respond_to?(:loops)
        ents.grep(Sketchup::Face).each do |f|
          next if f.normal.z.abs < 0.2 || f.loops.length < 2
          f.loops.each do |lp|
            next if lp.outer?
            pts = lp.vertices.map(&:position)
            next unless pts.all? { |p| in_plan?(plan, at, p.x, p.y, 0.5) }
            real << [lp, f]
          end
        end
      end
      unless real.empty?
        done = 0
        real.each { |lp, host| done += 1 if close_loop!(ents, lp, host, mat) }
        # AND ANY SCRATCH LEFT ANYWHERE OVER THIS OPENING. A rim face that
        # was already gone - erased by an earlier pass, or by the user -
        # left its uprights behind with nothing holding them. They are only
        # ever inside the opening, so the plan test is the whole safety net.
        stray = ents.grep(Sketchup::Edge).select do |e|
          next false unless e.valid? && e.faces.empty?
          in_plan?(plan, at, e.start.position.x, e.start.position.y, 0.5) &&
            in_plan?(plan, at, e.end.position.x, e.end.position.y, 0.5)
        end
        ents.erase_entities(stray) unless stray.empty?
        puts "[Dormer] hole closed: #{done} opening(s) skinned and merged" \
             "#{stray.empty? ? '' : ", #{stray.length} bare line(s) erased"}"
        return done
      end

      # FALLBACK, and the only path the cloud stub can run: it has no
      # loops, no edges and no find_faces, so there the ring is still
      # drawn by hand. tests/rt104.rb pins the one thing that path can
      # still get wrong - laying a patch on a slope the hole is not in.
      doomed = ents.grep(Sketchup::Face).select do |f|
        pts = face_points(f)
        next false if pts.nil? || pts.length < 3
        pts.all? { |p| in_plan?(plan, at, p.x, p.y, -0.05) }
      end
      doomed.each { |f| f.erase! if f.respond_to?(:erase!) && f.valid? }

      made = 0
      zs.each do |(_z, z_at)|
        ring = plan.map do |ss, w|
          q = at.call(ss, w, 0.0)
          at.call(ss, w, z_at.call(q.x, q.y))
        end
        begin
          f = ents.add_face(ring)
          next if f.nil?
          made += 1
          next unless mat
          f.material = mat
          f.back_material = mat
        rescue StandardError
          next
        end
      end
      puts "[Dormer] hole closed: #{doomed.length} piece(s) removed, #{made} skin(s) back"
      made
    rescue StandardError => e
      puts "[Dormer] heal_roof!: #{e.class}: #{e.message}"
      0
    end

    # CLOSE ONE OPENING. Lifted out of heal_roof! unchanged (2026-09-05) so
    # the delete can run it again on anything the frame walk missed - see
    # heal_box!. Skin, then rim, then seam, in that order: find_faces
    # rebuilds every face those edges can bound, the rim included.
    def self.close_loop!(ents, lp, host, mat)
      return false unless lp.respond_to?(:valid?) && lp.valid?
      m = mat || (host && host.valid? ? host.material : nil)
      skinned = lp.edges.any? do |e|
        e.valid? && e.faces.count { |f| f.valid? && f.normal.z.abs > 0.2 } >= 2
      end
      lp.edges.each { |e| e.find_faces if e.valid? } unless skinned
      rim = []
      lp.edges.each do |e|
        next unless e.valid?
        e.faces.each { |f| rim << f if f.valid? && f.normal.z.abs < 0.2 }
      end
      rim.uniq!
      # THE EDGES THE RIM WAS MADE OF, KEPT BEFORE IT GOES (2026-09-05).
      # Erasing a face does NOT take its edges: the four upright corners of
      # the cut had nothing left to bound and stayed in the model as bare
      # lines drawn on the roof - "הוא משאיר סימן של הקווים של החור".
      bare = rim.flat_map { |f| f.respond_to?(:edges) ? f.edges : [] }.uniq
      ents.erase_entities(rim) unless rim.empty?
      bare = bare.select { |e| e.valid? && e.faces.empty? }
      ents.erase_entities(bare) unless bare.empty?
      return false unless lp.valid?
      seam = lp.edges.select do |e|
        next false unless e.valid?
        fs = e.faces.select(&:valid?)
        fs.length == 2 && fs[0].normal.dot(fs[1].normal).abs > 0.999
      end
      seam.each do |e|
        e.faces.each do |f|
          next unless f.valid? && m
          f.material = m
          f.back_material = m
        end
      end
      ents.erase_entities(seam) unless seam.empty?
      true
    rescue StandardError => e
      puts "[Dormer] close_loop!: #{e.message}"
      false
    end

    # THE DORMER'S OWN FOOTPRINT IN PLAN, grown a little. Not the frame -
    # the GEOMETRY that is standing there. See heal_box!.
    def self.dormer_plan_box(g, grow = 1.0)
      xs = []
      ys = []
      walk = lambda do |ents, tr|
        ents.grep(Sketchup::Face).each do |f|
          f.vertices.each do |v|
            q = v.position.transform(tr)
            xs << q.x.to_f
            ys << q.y.to_f
          end
        end
        ents.grep(Sketchup::Group).each { |sub| walk.call(sub.entities, tr * sub.transformation) }
      end
      walk.call(g.entities, g.transformation)
      return nil if xs.empty?
      [xs.min - grow, xs.max + grow, ys.min - grow, ys.max + grow]
    rescue StandardError
      nil
    end

    # THE SAFETY NET UNDER DELETE AND MOVE (2026-09-05).
    #
    # heal_roof! closes the opening it can REBUILD from the dormer's saved
    # numbers. When that rebuild does not land exactly on the hole that is
    # really there - a frame that comes back nil, a roof rebuilt underneath
    # it, a shed whose length was re-derived - remove_dormer! erased the
    # dormer anyway and the hole stayed open. Measured in his model: three
    # dormers standing and four holes ("נישאר חור בגג").
    #
    # So after the dormer is gone, anything still open INSIDE THE FOOTPRINT
    # IT OCCUPIED is closed too. The footprint is the geometry's own, not a
    # recomputed frame, and two dormers never share one - so this can only
    # ever close the hole the deleted dormer left. Every style goes through
    # here: gable, hip, shed and flat all delete through remove_dormer!.
    def self.heal_box!(ents, box, mat = nil)
      return 0 if box.nil?
      inb = lambda do |p|
        p.x.to_f >= box[0] && p.x.to_f <= box[1] &&
          p.y.to_f >= box[2] && p.y.to_f <= box[3]
      end
      real = []
      ents.grep(Sketchup::Face).each do |f|
        next if f.normal.z.abs < 0.2
        next unless f.respond_to?(:loops) && f.loops.length > 1
        f.loops.each do |lp|
          next if lp.outer?
          next unless lp.vertices.map(&:position).all? { |p| inb.call(p) }
          real << [lp, f]
        end
      end
      done = 0
      real.each { |lp, host| done += 1 if close_loop!(ents, lp, host, mat) }
      stray = ents.grep(Sketchup::Edge).select do |e|
        e.valid? && e.faces.empty? &&
          inb.call(e.start.position) && inb.call(e.end.position)
      end
      ents.erase_entities(stray) unless stray.empty?
      unless done.zero? && stray.empty?
        puts "[Dormer] left over and closed: #{done} hole(s), #{stray.length} bare line(s)"
      end
      done
    rescue StandardError => e
      puts "[Dormer] heal_box!: #{e.message}"
      0
    end

    # Delete a dormer AND close the hole it cut. One operation, so one
    # Ctrl+Z puts the whole thing back.
    #
    # ONE RELAY, AND ONLY AFTER THE NEW HOLE IS CUT (2026-09-08). A delete
    # on its own still lays the field again here - the hole is closed and
    # nothing else is coming. But when this is the FIRST half of an Edit or
    # a Move, laying it now is both wasted and wrong: measured, an Edit
    # relaid the whole roof while no dormer stood on it and then cut the
    # new hole with nobody to tell, and a Move relaid twice. So those two
    # pass no_relay and do it once themselves, at the end.
    def self.remove_dormer!(g, opts = {})
      spec = dormer_spec(g)
      return false if spec.nil?
      ents = dormer_roof(g)
      roof = dormer_roof_group(g)
      fr = frame(spec)
      box = dormer_plan_box(g)
      heal_roof!(ents, fr, at_lambda(spec)) if ents && fr
      g.erase! if g.valid?
      heal_box!(ents, box) if ents
      relay_runs!(roof) if roof && !@no_relay && !opts[:no_relay]
      true
    rescue StandardError => e
      puts "[Dormer] remove_dormer!: #{e.class}: #{e.message}"
      false
    end

    # Rebuild one dormer with some numbers changed - that is Edit - or at
    # a different place - that is Move. The old one and its hole go, and
    # a new one is built from the merged spec. Returns the new group.
    def self.replace_dormer!(g, changes = {})
      spec = dormer_spec(g)
      return nil if spec.nil?
      ents = dormer_roof(g)
      return nil if ents.nil?
      merged = spec.merge(changes)
      # a nil is "unset it", not "set it to nothing" - that is how the
      # panel says "follow the roof's own pitch" on an edit.
      merged.reject! { |_k, v| v.nil? }
      merged.delete(:length) if changes.key?(:height) && changes[:height]
      return nil if frame(merged).nil?
      # THE MATERIALS ARE NOT IN THE SPEC (2026-09-05). dormer_spec saves
      # numbers - the materials were never attributes, they were handed in
      # by place_on_roof! off the roof and off the house wall. So an EDIT,
      # which rebuilds straight through add_dormer!, put back a dormer with
      # a bare roof and white walls: "אני לוחץ על עריכת כל גמלון הגג שלו
      # מאבד את הצבע". Asked off the dormer that is standing here, before
      # it goes - the roof's own skin is the truest answer there is.
      merged[:roof_material] = cap_material(g) if merged[:roof_material].nil?
      if merged[:wall_names].nil?
        wm = house_wall_material
        merged[:wall_names] = [wm] if wm
      end
      # the roof group has to be asked BEFORE the dormer goes - it is found
      # by looking for the group that holds it.
      roof = dormer_roof_group(g)
      remove_dormer!(g, no_relay: true)
      out = add_dormer!(ents, merged)
      relay_runs!(roof) if roof && !@no_relay
      out
    rescue StandardError => e
      puts "[Dormer] replace_dormer!: #{e.class}: #{e.message}"
      nil
    end

    # ---------- SURVIVING A ROOF REBUILD (2026-09-02) -------------------
    #
    # A dormer is built INTO its roof's group, and RoofManager rebuilds a
    # roof by erasing that whole group - so before today every Apply in
    # the roof panel quietly took the dormers with it.
    #
    # `harvest` reads them off a roof that is about to go: the sizes, and
    # the plan point they stood over. `replant!` puts them back on the
    # NEW roof by PLACING them again at that point - so the frame is
    # measured off the roof that exists now. Change the pitch and the
    # dormers come back sitting on the new slope, not floating over where
    # the old one used to be.
    def self.harvest(groups)
      saved = []
      Array(groups).each do |r|
        next unless r.respond_to?(:entities) && r.valid?
        collect_dormers(r.entities, saved, 0)
      end
      saved
    rescue StandardError => e
      puts "[Dormer] harvest: #{e.message}"
      []
    end

    def self.collect_dormers(ents, saved, depth)
      ents.grep(Sketchup::Group).each do |g|
        if g.get_attribute('InteriorPro', 'type') == 'dormer'
          sp = dormer_spec(g)
          next if sp.nil?
          # the point it stood over: the middle of its own footprint,
          # measured in its own frame and turned into plan.
          at = at_lambda(sp)
          q = at.call(sp[:setback].to_f + sp[:length].to_f / 2.0, 0.0, 0.0)
          # IT KEEPS ITS HEIGHT, NOT ITS LENGTH (2026-09-02, the user:
          # "אם אני משנה זווית לגג הוא נעלם, אני צריך שהוא יישאר איך
          # שהוא"). What he looks at is the front wall - a window goes
          # in it - and how far the gablet reaches into the roof is
          # whatever that height needs on the NEW pitch. Carrying the
          # old length instead is what made a steeper roof throw it away.
          h = g.get_attribute('InteriorPro', 'height').to_f
          if h > 0.0
            sp[:height] = h
            sp.delete(:length)
          end
          # the frame keys go: the new roof supplies its own.
          %i[z0 slope base along into z_top].each { |k| sp.delete(k) }
          saved << { spec: sp, x: q.x, y: q.y }
        elsif depth < 2
          collect_dormers(g.entities, saved, depth + 1)
        end
      end
    end

    def self.replant!(roof, saved)
      return 0 if roof.nil? || saved.nil? || saved.empty?
      back = 0
      cut = 0
      lost = 0
      @no_relay = true
      saved.each do |d|
        g, h = replant_one!(roof, d[:x], d[:y],
                            d[:spec].merge(no_relay: true))
        if g.nil?
          lost += 1
          next
        end
        back += 1
        next if h.nil? || d[:spec][:height].nil?
        cut += 1 if (h - d[:spec][:height].to_f).abs > 0.5
      end
      puts "[Dormer] #{back} dormer(s) put back on the new roof" if back.positive?
      puts "[Dormer] #{cut} of them had to come down to fit the new roof" if
        cut.positive?
      puts "[Dormer] #{lost} dormer(s) could not be put back at all" if
        lost.positive?
      @no_relay = false
      relay_runs!(roof) if back.positive?
      back
    rescue StandardError => e
      @no_relay = false
      puts "[Dormer] replant!: #{e.message}"
      0
    end

    # KEEP IT, EVEN IF IT HAS TO COME DOWN. First try the dormer exactly
    # as it was. If the new roof cannot take that, find the tallest front
    # wall it CAN take - by halving the gap, not by guessing - and put it
    # back at that height. Only a roof that cannot hold even the shortest
    # dormer loses it.
    def self.replant_one!(roof, x, y, spec)
      g = place_on_roof!(roof, x, y, spec)
      return [g, spec[:height]] unless g.nil?
      want = spec[:height].to_f
      return [nil, nil] if want <= MIN_FACE_HEIGHT
      lo = MIN_FACE_HEIGHT
      hi = want
      best = nil
      20.times do
        mid = (lo + hi) / 2.0
        if fits_here?(roof, x, y, spec.merge(height: mid))
          best = mid
          lo = mid
        else
          hi = mid
        end
        break if hi - lo < 0.25
      end
      return [nil, nil] if best.nil?
      [place_on_roof!(roof, x, y, spec.merge(height: best)), best]
    end

    def self.fits_here?(roof, x, y, spec)
      !preview(roof, x, y, spec).nil?
    end

    # ---------- STEP 2: the hole in the main roof -----------------------
    #
    # THE ROUGH OPENING, in (s, w), inside the walls: the front wall's
    # inner face, the two cheeks' inner faces, and at the back the VALLEY
    # itself - the line where the dormer's roof dies into the main one.
    # Past that line there is no dormer above the hole any more, so that
    # is exactly where the hole has to stop.
    # THE OUTER FACE, NOT THE ROUGH OPENING (2026-09-03). It used to be the
    # INSIDE faces of the three walls, one thickness in from the outside, so
    # the deck ran on under every wall and its cut edge showed as a lip all
    # round the opening - "השכבה שמתחת לרעפים/שינגלס צריכה להיחתך בקצה
    # החיצוני של הקיר ולא בפנים הבית". Now the deck stops on the OUTSIDE of
    # the walls, where the tiles above it already stop, and the wall closes
    # the edge instead of standing on it. The back is untouched: there is no
    # wall there, only the valley where the two roofs meet, and that is
    # exactly where the hole has to stop.
    def self.opening_plan(fr)
      hw = fr[:half]
      return nil if hw <= 0.5
      if shed_like?(fr)
        s0 = fr[:s_front]
        return nil if fr[:s_ridge] <= s0 + 0.5
        return [[s0, -hw], [s0, hw], [fr[:s_ridge], hw], [fr[:s_ridge], -hw]]
      end
      s0 = fr[:s_front]
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

    def self.seg_distance(a, b, x, y)
      ax, ay = a
      bx, by = b
      dx = bx - ax
      dy = by - ay
      len2 = dx * dx + dy * dy
      t = len2 < 1.0e-9 ? 0.0 : (((x - ax) * dx + (y - ay) * dy) / len2)
      t = 0.0 if t < 0.0
      t = 1.0 if t > 1.0
      Math.sqrt((x - (ax + dx * t))**2 + (y - (ay + dy * t))**2)
    end

    # `skip` = indices of edges this distance must ignore (the eave).
    def self.ring_distance(ring, x, y, skip = nil)
      best = nil
      n = ring.length
      n.times do |i|
        next if skip && skip.include?(i)
        d = seg_distance(ring[i], ring[(i + 1) % n], x, y)
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

    # THE OUTER LOOP, NOT EVERY VERTEX (2026-09-02). A roof face that
    # already has dormers in it has HOLES, and `face.vertices` hands back
    # the hole vertices mixed in with the outline's. Threading a ring
    # through that lot gives a shape that is not the roof at all - which
    # is why placing a second dormer kept being refused in places the
    # first one was allowed, and why it got worse with every one added
    # (the user: "אפילו יותר גרוע הוא מרחיק אותי יותר").
    def self.face_points(f)
      return Array(f.pts) if f.respond_to?(:pts) && f.pts
      if f.respond_to?(:outer_loop) && f.outer_loop
        return f.outer_loop.vertices.map(&:position)
      end
      f.vertices.map(&:position)
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

    # THE INSIDE IS WHITE (2026-09-02, the user: "שהאינטיריור הקירות
    # יהיו לבנים"). A dormer's walls are the house's walls seen from
    # outside and a ROOM seen from inside, and the house's own walls have
    # worked that way from the start - a texture out, a colour in.
    #
    # `outward` is the way this wall faces. The one face pointing the
    # other way is the room side and gets the interior colour; everything
    # else keeps the house's exterior material, exactly as before - the
    # top edge and the mitred ends are hidden anyway, and leaving them
    # bare would show as white slivers on a corner.
    def self.paint_wall!(sub, names, outward = nil)
      ext_name, int_name = Array(names)
      int_name = DEFAULT_INTERIOR_COLOR if int_name.nil? || int_name.to_s.empty?
      return unless defined?(InteriorPro::WallTool) &&
                    InteriorPro::WallTool.respond_to?(:new)
      wt = InteriorPro::WallTool.new
      ext = ext_name ? wt.load_or_create_material(ext_name) : nil
      int = wt.load_or_create_material(int_name)
      return if ext.nil? && int.nil?
      # WHICH SIDE IT SITS ON, NOT WHICH WAY IT LOOKS (2026-09-02B).
      # This used to read f.normal, and a face's normal is decided by the
      # winding add_face happened to get. The two cheeks are built from
      # the same point order at mirrored w, so the second one's skins
      # come out with their normals flipped - and the house texture went
      # on the INSIDE of that cheek while the white went outdoors (the
      # user: "הקירות מבחוץ ... מראים את הצבע של הפנים"). The measured
      # proof: on one cheek the 570 sq in skin was Stucco, on the other
      # the same 570 sq in skin was #ffffff.
      #
      # A face's POSITION cannot flip. The wall part is one slab; the
      # skin further along `outward` than the slab's own middle is the
      # outdoor one, the skin behind it is the indoor one, and the edges
      # that bridge them sit on the middle and stay outdoor - they are
      # the mitres and the top, hidden anyway, and leaving them bare
      # showed white stripes in the corner.
      mid = sub.bounds.center
      sub.entities.grep(Sketchup::Face).each do |f|
        inside = if outward.nil?
                   false
                 else
                   c = f.bounds.center
                   ((c.x - mid.x) * outward[0] + (c.y - mid.y) * outward[1] +
                    (c.z - mid.z) * outward[2]) < -0.05
                 end
        m = inside ? int : (ext || int)
        next if m.nil?
        f.material = m
        f.back_material = m
      end
    rescue StandardError => e
      puts "[Dormer] paint_wall!: #{e.message}"
    end

    # The dormer's two horizontal axes in the world, read off the same
    # placing lambda everything else uses: INTO the roof, and ALONG the
    # eave. A wall's outward direction is one of these, signed.
    def self.frame_dirs(at)
      o = at.call(0.0, 0.0, 0.0)
      i = at.call(1.0, 0.0, 0.0)
      a = at.call(0.0, 1.0, 0.0)
      [[i.x - o.x, i.y - o.y, 0.0], [a.x - o.x, a.y - o.y, 0.0]]
    end

    def self.unit(v)
      len = Math.sqrt(v[0].to_f**2 + v[1].to_f**2)
      len < 1.0e-9 ? [1.0, 0.0] : [v[0] / len, v[1] / len]
    end
  end
end
