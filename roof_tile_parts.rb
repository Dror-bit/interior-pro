# encoding: utf-8
# Interior Pro - roof_tile_parts.rb  (2026-08-19)
#
# The four little 3D pieces a tiled roof needs, and NOTHING else. This file
# knows what a tile looks like. It does not know where roofs are, how they
# are shaped, or how many pieces to place - that is roof_tile_place.rb.
#
# WHY IT IS BUILT THIS WAY (measured, not chosen)
# Instant Roof's whole 63x59ft roof carries ONE repeated 3D piece:
# va_BirdStop - 408 instances of a definition holding a SINGLE face
# (valiroof_report.txt, 2026-08-18). That is the trick: one definition,
# hundreds of instances, and SketchUp draws it hundreds of times while
# storing it once.
#
# So every method here returns a Sketchup::ComponentDefinition, cached on
# the model by name. Ask for the same piece twice and you get the same
# definition back - the second call builds nothing. tests/rt77.rb fails if
# a second call adds geometry.
#
# THE BUDGET, and it is the whole point of the file:
#   4 shapes x 4 pieces x <= 8 faces = about 30 UNIQUE faces for any roof,
#   however big the house is. Everything else is instances.
#
# The pieces are modelled in a piece-local frame, so the placer can put them
# anywhere without knowing anything about them:
#
#   +X = ACROSS the slope (along the eave / along the ridge line)
#   +Y = UP the slope
#   +Z = out of the roof surface
#   origin = the middle of the piece's lower edge, ON the roof plane
#
# That is the same u / v / n frame RoofTileMath.plane_frame hands back, so
# placing one is Geom::Transformation.axes(point, u, v, n) and no more.

module InteriorPro
  module RoofTileParts
    # How far the eave piece reaches UP the slope. The user chose the short
    # nose (2026-08-19): it reads exactly like the photographs from any
    # normal camera angle, and a whole 14" tile only pays off when you look
    # at the roof from almost straight above.
    def self.eave_nose
      4.0
    end

    # How far a piece hangs out PAST the roof edge, like a real tile.
    def self.eave_overhang
      1.25
    end

    # Half-round profiles are the expensive part of a tile, so they get
    # exactly this many segments. 4 reads as round at any sane distance and
    # keeps a piece under 8 faces.
    def self.arc_segments
      4
    end

    # ---------------------------------------------------------------- cache
    #
    # Definitions live on the model, so a second roof in the same file reuses
    # the first one's pieces. The name carries the shape AND the sizes, so
    # changing a number gives a NEW definition instead of silently leaving
    # the old geometry in place - the reload! trap that cost us 2026-08-14
    # and again 2026-08-18, one level up.
    def self.definition(model, name)
      model.definitions[name]
    rescue StandardError
      nil
    end

    def self.fetch_or_build(model, name)
      d = definition(model, name)
      return d if d
      d = model.definitions.add(name)
      yield d
      d
    rescue StandardError => e
      puts "[RoofTiles] #{name}: #{e.message}"
      nil
    end

    def self.shape_of(shape_name)
      InteriorPro::RoofTileMath.shape(shape_name)
    end

    # --------------------------------------------------------------- pieces

    # THE EAVE PIECE - the one you actually see, 408 times on Vali's roof.
    #
    # Cross section, looking along the eave:
    #
    #        ___-- - --___          <- the barrel, `arc_segments` chords
    #      /              \
    #     |                |        <- the visible thickness
    #     +----------------+        <- sits on the roof plane
    #
    # It runs from y = -overhang (poking out past the roof edge, like a real
    # tile) to y = +nose. A flat material (slate, seam) gets a plain square
    # nose instead of a barrel - same face budget, right silhouette.
    def self.eave(model, shape_name)
      s = shape_of(shape_name)
      return nil if s.nil?
      w = s[:tile_w].to_f
      h = s[:relief].to_f * 2.0
      name = format('IP_TileEave_%s_%0.2f_%0.2f_%0.2f', shape_name, w, h, eave_nose)
      fetch_or_build(model, name) do |d|
        y0 = -eave_overhang
        y1 = eave_nose
        prof = profile(w, h, s[:scallop].to_f > 0.0)
        build_extrusion!(d.entities, prof, y0, y1)
        soften_all!(d.entities)
        d.set_attribute('InteriorPro', 'part', 'tile_eave')
        d.set_attribute('InteriorPro', 'coverage_w', w)
      end
    end

    # THE RAKE PIECE - the gable edge. Same idea turned 90 degrees: it runs
    # UP the slope instead of along the eave, and it laps the course below,
    # so its length is the exposure and not the tile width.
    def self.rake(model, shape_name)
      s = shape_of(shape_name)
      return nil if s.nil?
      w = s[:tile_w].to_f * 0.75
      h = s[:relief].to_f * 2.0
      run = s[:exposure].to_f > 0.0 ? s[:exposure].to_f : s[:tile_w].to_f
      name = format('IP_TileRake_%s_%0.2f_%0.2f_%0.2f', shape_name, w, h, run)
      fetch_or_build(model, name) do |d|
        prof = profile(w, h, s[:scallop].to_f > 0.0)
        build_extrusion!(d.entities, prof, -eave_overhang, run)
        soften_all!(d.entities)
        d.set_attribute('InteriorPro', 'part', 'tile_rake')
        d.set_attribute('InteriorPro', 'coverage_w', run)
      end
    end

    # THE RIDGE CAP - a half round laid ALONG the ridge, lapping the one
    # before it. The existing build_ridge_caps! already draws this shape
    # beautifully; what it does NOT do is reuse it, which is why a big roof
    # ends up with hundreds of unique groups. Same silhouette, one definition.
    def self.ridge(model, shape_name)
      cap(model, shape_name, 'Ridge')
    end

    # THE HIP CAP - the same piece. Kept as its own method (and its own
    # definition name) because a hip cap is tagged separately and may want a
    # narrower profile later; today they are identical on purpose.
    def self.hip(model, shape_name)
      cap(model, shape_name, 'Hip')
    end

    def self.cap(model, shape_name, kind)
      s = shape_of(shape_name)
      return nil if s.nil?
      w = s[:tile_w].to_f * 0.85
      h = s[:relief].to_f * 2.2
      run = s[:tile_w].to_f
      name = format('IP_Tile%s_%s_%0.2f_%0.2f_%0.2f', kind, shape_name, w, h, run)
      fetch_or_build(model, name) do |d|
        build_extrusion!(d.entities, profile(w, h, true), 0.0, run)
        soften_all!(d.entities)
        d.set_attribute('InteriorPro', 'part', "tile_#{kind.downcase}")
        d.set_attribute('InteriorPro', 'coverage_w', run)
      end
    end

    # THE RUN - the long half pipe, and the piece the user actually asked for
    # (2026-08-20, his own Roman Tiled Roof.skp): "חצי צינור שהולך מלמעלה למטה
    # בגג כחצי צינור ארוך".
    #
    # It is modelled ONE INCH LONG on purpose. The placer scales Y to the real
    # length of each run, so a 30ft run and a 3ft run are the same definition
    # and the whole roof carries about ten unique faces. That is the entire
    # answer to "will it be heavy" - a sweep's cost is its cross section, and
    # length is free.
    #
    # IT IS HOLLOW, and this is not a detail - it is what the user corrected on
    # 2026-08-21 after seeing the first build: "הקצה של מה ששלחתי הוא חלול
    # ועובי החצי עיגול הוא אולי אינץ' אבל חלול".
    #
    # A real clay tile is a SHELL. Modelled solid, the open end of every run
    # showed as a filled white half-moon sitting under the fascia - a row of
    # them along the whole eave, and the single worst thing in the first
    # screenshot. A shell ends in a thin crescent instead, which is what a
    # cut tile actually looks like.
    #
    # Cross section, looking up the slope:
    #
    #         _-- --_           <- outer arc, run_segments chords
    #       /  _- -_  \
    #      |  /     \  |        <- inner arc, one wall thickness in
    #      +--       --+        <- sits on the roof plane, belly open
    #
    # The cover is HALF the tile pitch and a true half round on top of it, so
    # a 13" Roman pitch gives a 6.5" pipe standing 3.25" proud - the flat pan
    # between two pipes is the roof face itself, wearing the tile texture.
    def self.run_segments
      8
    end

    # HOW WIDE ONE PIPE IS, as a fraction of the material's tile pitch.
    #
    # Three numbers, in the order the user gave them:
    #   0.5  first build - a narrow tube with an equally wide flat beside it.
    #        Next to his own reference it read as separate pipes on a slab.
    #   0.8  arches nearly touching. Right spacing, but he measured them:
    #        "רוחב של כל אחד זה 10 ואני רוצה שזה יהיה 6" (2026-08-21).
    #   6/13 six inches on the 13" Roman pitch, which is what he asked for.
    #
    # The pipes stay close together because the SPACING is no longer the tile
    # pitch - it is run_pitch, this width plus a narrow pan. Making the pipe
    # thinner now puts MORE of them on the roof instead of spreading them out.
    def self.run_cover_ratio
      0.8
    end

    # Centre to centre between two runs. NOT the material's tile pitch: that
    # number sizes the eave and cap pieces and the field texture, and the pipe
    # is free to be finer than it. Clay runs at 7.5" (six inch pipes with a
    # 1.5" pan) on a 13" Roman tile; pressed metal runs at its own 16" module.
    # A material may name its own in `run_pitch`.
    def self.run_pitch(s)
      p = s[:run_pitch].to_f if s && s[:run_pitch]
      return p if p && p > 1.0e-9
      7.5
    end

    # HOW TALL THE ARCH IS, as a fraction of its own width. 0.5 is a true half
    # circle. The reference arch is WIDER THAN IT IS ROUND - a flattened arch,
    # not a tube - so a wide cover needs a lower rise or the roof grows a row
    # of barrels.
    def self.run_rise_ratio
      0.38
    end

    # Both fractions are of the RUN pitch, and a material may override either.
    # Clay: a 6" pipe standing 2.28" on a 7.5" run pitch. Pressed metal: a wide
    # 13.6" crest standing only 3" on a 16" one - the same machinery, different
    # numbers, no second builder.
    def self.run_cover_w(s)
      f = s[:run_cover].to_f if s && s[:run_cover]
      f = run_cover_ratio unless f && f > 1.0e-9
      run_pitch(s) * f
    end

    def self.run_height(s)
      f = s[:run_rise].to_f if s && s[:run_rise]
      f = run_rise_ratio unless f && f > 1.0e-9
      run_cover_w(s) * f
    end

    # Wall thickness of the shell. A third of an inch, the user's own number
    # off his reference (2026-08-21) after the first build at a full inch read
    # too heavy on the cut end.
    def self.run_wall_t
      1.0 / 3.0
    end

    # ------------------------------------------------------- PAN AND ROLL
    #
    # THE PIPES WENT THROUGH EACH OTHER (2026-08-21). Once Roman was set to
    # the user's own measurements - a 10.63" tile on an 8.27" pitch - two
    # identical half pipes at the same height simply INTERSECTED, and the eave
    # filled up with crossed crescents. "הם נכנסים אחד לתוך השני."
    #
    # A real Roman tile is not a pipe. It is a flat PAN with a raised ROLL,
    # and the roll of one tile sits ON TOP of the joint with the next:
    #
    #        roll (2*lap wide, centred on the joint)
    #             _--_                    _--_
    #        ____/    \____ ____ ____ ___/    \___
    #       |   pan = one pitch  |   next pan     |
    #       0                   p/2               p
    #
    # Every number below comes from the two he measured, and nothing else:
    #   pan   is exactly one PITCH wide, so two pans butt - no gap, no overlap
    #   lap   = cover - pitch = 2.36", the part that hangs past the pan
    #   roll  = 2 * lap, which lands it exactly CENTRED on the butt joint
    #   total = pan/2 + (pan/2 + lap) = cover = 10.63", his width, unchanged
    # The roll springs from the pan's TOP face, so it passes above the next
    # tile's pan instead of through it. Height and wall thickness are the ones
    # he already approved - 2.28" and a third of an inch.
    def self.run_lap(s)
      run_cover_w(s) - run_pitch(s)
    end

    # Only a tile WIDER than its spacing is a pan and roll. Barrel is 6" on a
    # 7.5" pitch, so it keeps the plain half pipe it has always had and an old
    # model saved with it still builds exactly as before.
    def self.pan_roll?(s)
      run_lap(s) > 1.0e-9
    end

    def self.run_roll_w(s)
      2.0 * run_lap(s)
    end

    # How high the finished piece stands off the deck. The ridge cap needs this
    # to ride over the tiles instead of through them.
    def self.run_top_h(s)
      return run_height(s) if seam?(s) || !pan_roll?(s)
      run_wall_t + run_height(s)
    end

    # ------------------------------------------------- THE CAP, SIZED HERE
    #
    # The cap used to be sized in roof_manager off run_cover_w - the whole
    # TILE. That was fine when a tile was one bare pipe; once Roman became a
    # 14" pan and roll it made a 16" cap on an 8" roll, and the user asked why
    # its shape had changed: "הוא צריך להתאים לצורה החצי עגולה ולכסות את
    # הרעפים וגם לא להיות גבוה מדי."
    #
    # So the cap is the ROLL, 15% bigger across so it laps it, and NO taller
    # than the roll it covers. It lives here, next to the roll it copies, and
    # roof_manager and the run setback both read it - one number, not three
    # that can drift.
    def self.cap_lap
      1.15
    end

    # A MATERIAL MAY NAME ITS OWN CAP, and Roman now does (2026-08-21).
    #
    # Deriving it from the tile is what caused the trouble all day: every time
    # the tile grew the cap grew with it, unasked and unannounced, and the user
    # had to spot it - "אני לא מבין למה שינית את צורת הרידג' קאפ". A material
    # that states cap_w / cap_crown is immune to that: changing its tile can no
    # longer move its cap. Anything that does NOT state them keeps the old
    # derivation exactly.
    def self.cap_w(s)
      v = s[:cap_w].to_f if s && s[:cap_w]
      return v if v && v > 1.0e-9
      run_cover_w(s) * cap_lap
    end

    # A STATED crown is taken as it stands, ZERO INCLUDED (2026-08-21). A metal
    # ridge is not an arch at all - it is one folded plate, "רידג' אחיד שמקופל
    # לשני הצדדים של הגג" - so 0 has to mean flat and not "fall back to the old
    # constant". Only a material that states nothing gets the derived arch.
    def self.cap_crown_stated?(s)
      !s.nil? && s.key?(:cap_crown)
    end

    def self.cap_crown(s)
      return s[:cap_crown].to_f if cap_crown_stated?(s)
      run_height(s) * cap_lap
    end

    # Does this material's ridge cap take the half-round section? STATED on
    # the shape, never guessed - deriving it is what kept moving Roman's cap
    # behind the user's back. Only Roman says true.
    def self.cap_round?(s)
      !s.nil? && s[:cap_round] == true
    end

    # A run stops this far short of the ridge or the hip, so its cut end lands
    # under the cap instead of poking out past the line. It is measured off the
    # ROLL, not off the cap, ON PURPOSE: the corner is right and the cap's size
    # is a separate question, so changing one must not move the other.
    def self.ridge_setback(s)
      # A STATED setback stands as it is - the same rule as cap_crown. The
      # standing seam states 4.0 (2026-08-21, second pass): its setback WAS 0,
      # on the theory that the lifted cap rides on the rib tops so the ribs
      # may run right up to the line - and the user saw exactly what that
      # looks like: "הברזלים נכנסים לתוך הרידג' קאפ וזה לא נראה טוב." Now the
      # rib is cut where the cap starts and its end hides underneath it.
      return s[:ridge_setback].to_f if !s.nil? && s.key?(:ridge_setback)
      return 0.0 if seam?(s)
      (pan_roll?(s) ? run_roll_w(s) : run_cover_w(s)) * cap_lap / 2.0
    end

    # The flat pan, one pitch wide and one wall thick, centred on the slot.
    def self.pan_profile(p, t)
      half = p / 2.0
      [[-half, 0.0], [half, 0.0], [half, t], [-half, t]]
    end

    # The roll: the same hollow crescent the pipe always was, moved out to sit
    # over the joint and lifted onto the pan's top face.
    def self.roll_profile(s, segs = nil)
      dx = run_pitch(s) / 2.0
      dz = run_wall_t
      shell_profile(run_roll_w(s), run_height(s), run_wall_t, segs)
        .map { |(x, z)| [x + dx, z + dz] }
    end

    # ------------------------------------------------------- STANDING SEAM
    #
    # The same idea as the pan and roll, with the roll replaced by a square
    # RIB - "תעשה את הבליטה אינץ' ולא חצי". Two flat pans butt under it and the
    # rib covers the joint, which is exactly what a standing seam is.
    #
    #        rib, 1" thick, 1.75" proud
    #             ||                      ||
    #        _____||______________________||_____
    #       |   pan = one pitch   |   next pan   |
    #
    # Thickness comes from the lap the same way the roll's width does: the
    # panel is half a rib wider than its pitch, so lap * 2 is the rib. Nothing
    # here invents a number.
    def self.seam?(s)
      !s.nil? && s[:run_seam] == true
    end

    def self.seam_w(s)
      2.0 * run_lap(s)
    end

    # DOES THIS PIECE GET ITS EDGES SOFTENED? Everything does except the
    # standing seam (2026-08-21). soften_all! exists because the user did not
    # want chord lines running down a round clay tile; on folded metal he asked
    # for the exact opposite - "אני רוצה שכן יראו את הקווים ואת הפינות, רק בגג
    # הזה" - and a crisp arris is what makes it read as sheet metal.
    def self.soften_run?(s)
      !seam?(s)
    end

    # ------------------------------------------------------- THE EAVE FRAME
    #
    # How the metal roof ENDS (2026-08-21). The user sent a photograph of one
    # and asked for the border it dies into: "תראה איך הוא נגמר בסוף עם מסגרת
    # בגובה של הבליטות שהיה אינץ' על אינץ'."
    #
    # A square bar, one inch by one inch, standing on the pan's top face
    # exactly as high as the ribs, laid ALONG the eave so the panels and the
    # ribs both run into it. Both dimensions are run_height - his "בגובה של
    # הבליטות" - so if the rib height ever changes, the frame follows it and
    # cannot drift out of line with it.
    #
    # Modelled one inch long up its own +Y, the same trick the runs use, so one
    # definition of six faces serves every eave on the house.
    def self.edge_bar_profile(s)
      h = run_height(s)
      return [] if h <= 1.0e-9
      # ON THE DECK, like the ribs - see the note on seam_profile.
      [[-h, 0.0], [0.0, 0.0], [0.0, h], [-h, h]]
    end

    def self.edge_bar(model, shape_name)
      s = shape_of(shape_name)
      return nil if s.nil? || !seam?(s)
      prof = edge_bar_profile(s)
      return nil if prof.empty?
      # Same rule as the run above: the bar moved down onto the deck without
      # any of its numbers changing, so the name says which one it is.
      name = format('IP_TileEdgeDeck_%s_%0.2f', shape_name, run_height(s))
      fetch_or_build(model, name) do |d|
        build_extrusion!(d.entities, prof, 0.0, 1.0, true)
        # No softening here either - it is part of the same folded metal roof.
        d.set_attribute('InteriorPro', 'part', 'tile_edge')
        d.set_attribute('InteriorPro', 'unit_length', 1.0)
      end
    end

    # THE RIB ALONE - THERE IS NO PAN (2026-08-21).
    #
    # It was built as a pan plus a rib, the same as the clay tile. The user
    # looked at it and said the layer under the ribs reads as split panels:
    # "אל תעשה את זה ככה אלא שהכל יהיה משטח אחד גדול כמו השכבה מתחת."
    #
    # He is right, and it also fixes the mess at the hip. A pan is 28" wide,
    # but a run is cut to length by the plane outline at its CENTRE LINE - so
    # every pan overhung the hip by up to half its width, in a staircase, and
    # straight out through the ridge cap. A rib is 2" wide and does not.
    #
    # The roof deck is already one continuous surface, so it IS the pan. The
    # rib sits directly on it, z = 0 to its own height, and nothing is drawn
    # twice.
    def self.seam_profile(s)
      w = seam_w(s)
      return [] if w <= 1.0e-9
      dx = run_pitch(s) / 2.0
      h = run_height(s)
      half = w / 2.0
      [[dx - half, 0.0], [dx + half, 0.0], [dx + half, h], [dx - half, h]]
    end

    def self.run(model, shape_name)
      s = shape_of(shape_name)
      return nil if s.nil?
      w = run_cover_w(s)
      h = run_height(s)
      t = run_wall_t
      return nil if w <= 1.0e-9 || h <= 1.0e-9
      # THE NAME MUST CARRY THE SHAPE, NOT ONLY THE SIZES (2026-08-21).
      # Dropping the seam's pan changed no number here, so fetch_or_build kept
      # handing back the definition that still had one and the roof rebuilt
      # identical - "כלום לא השתנה". 'Rib' is what a pan-less seam is called;
      # it was 'Seam' while it still had one. Any future change to what a piece
      # IS has to move this string, the same way a size change moves a number.
      name = format('IP_TileRun_%s%s_%0.2f_%0.2f_%0.2f_%0.2f_%d',
                    shape_name, seam?(s) ? 'Rib' : '',
                    w, h, t, run_pitch(s), run_segments)
      fetch_or_build(model, name) do |d|
        if seam?(s)
          # No pan: the roof deck under it already is one. See seam_profile.
          build_extrusion!(d.entities, seam_profile(s), 0.0, 1.0, true)
        elsif pan_roll?(s)
          build_extrusion!(d.entities, pan_profile(run_pitch(s), t),
                           0.0, 1.0, true)
          build_extrusion!(d.entities, roll_profile(s, run_segments),
                           0.0, 1.0, true)
        else
          build_extrusion!(d.entities, shell_profile(w, h, t, run_segments),
                           0.0, 1.0, true)
        end
        soften_all!(d.entities) if soften_run?(s)
        d.set_attribute('InteriorPro', 'part', 'tile_run')
        d.set_attribute('InteriorPro', 'coverage_w', s[:tile_w].to_f)
        d.set_attribute('InteriorPro', 'unit_length', 1.0)
        d.set_attribute('InteriorPro', 'wall_t', t)
      end
    end

    # THE SHEET - pressed metal, and it is NOT a pipe (2026-08-21).
    #
    # The first metal build laid separate tubes on a flat deck. The user put
    # his own reference beside it and the difference was obvious: his is ONE
    # FOLDED SHEET. The crest and the flat pan next to it are the same
    # continuous surface, and each course LAPS OVER the one below - "אני רוצה
    # שהם ישבו אחד על השני".
    #
    # So the cross section runs a WHOLE PITCH, pan to pan, and two neighbouring
    # instances meet at the same height on the same line. There is no gap
    # between them to see, no open tube end, and nothing to catch the light
    # wrongly - the row of white crescents along the eave came from modelling
    # a tube where there is a fold.
    #
    #   ___                    ___                    ___
    #  /   \__________________/   \__________________/   \      <- one pitch
    #
    # Along the slope the piece carries its own step, so the pieces butt end to
    # end instead of overlapping: a raised nose for the first `sheet_nose` of
    # the course, a short ramp down, then flat to the top. That nose is what
    # sits on the course below.
    def self.sheet_lip
      0.45
    end

    # Fraction of one course taken by the raised nose, and by the ramp behind
    # it. Kept as fractions because the piece is modelled ONE unit long and
    # stretched to whatever the course really measures.
    def self.sheet_nose
      0.18
    end

    def self.sheet_ramp
      0.10
    end

    # A whole pitch of the fold, left pan to right pan, both ends at z = 0 so
    # two instances side by side make one unbroken surface.
    def self.sheet_profile(pitch, cover, h, segs = nil)
      half = pitch / 2.0
      c = [cover / 2.0, half].min
      n = [(segs || run_segments).to_i, 2].max
      pts = [[-half, 0.0]]
      (0..n).each do |i|
        a = Math::PI * i / n.to_f
        pts << [-c * Math.cos(a), h * Math.sin(a)]
      end
      pts << [half, 0.0]
      pts
    end

    # Sweep the fold along the slope in three bands - nose, ramp, field - so
    # the step is part of the piece and not a second object laid on top of it.
    # No end caps and no closing edge: a folded sheet has no belly and no cut
    # end to show.
    def self.build_sheet!(ents, prof, lip)
      y0 = 0.0
      y1 = sheet_nose
      y2 = sheet_nose + sheet_ramp
      made = 0
      made += band!(ents, prof, y0, lip, y1, lip)
      made += band!(ents, prof, y1, lip, y2, 0.0)
      made += band!(ents, prof, y2, 0.0, 1.0, 0.0)
      made
    end

    # One band of the sweep: the same cross section at two stations, each with
    # its own height above the roof plane.
    def self.band!(ents, prof, ya, za, yb, zb)
      a = prof.map { |(x, z)| Geom::Point3d.new(x, ya, z + za) }
      b = prof.map { |(x, z)| Geom::Point3d.new(x, yb, z + zb) }
      made = 0
      (0...(prof.length - 1)).each do |i|
        made += 1 if add_face(ents, [a[i], a[i + 1], b[i + 1], b[i]])
      end
      made
    end

    def self.sheet(model, shape_name)
      s = shape_of(shape_name)
      return nil if s.nil?
      pitch = run_pitch(s)
      cover = run_cover_w(s)
      h = run_height(s)
      return nil if pitch <= 1.0e-9 || h <= 1.0e-9
      name = format('IP_TileSheet_%s_%0.2f_%0.2f_%0.2f_%0.2f_%d',
                    shape_name, pitch, cover, h, sheet_lip, run_segments)
      fetch_or_build(model, name) do |d|
        build_sheet!(d.entities, sheet_profile(pitch, cover, h, run_segments),
                     sheet_lip)
        soften_all!(d.entities)
        d.set_attribute('InteriorPro', 'part', 'tile_sheet')
        d.set_attribute('InteriorPro', 'coverage_w', pitch)
        d.set_attribute('InteriorPro', 'unit_length', 1.0)
      end
    end

    # ------------------------------------------------- the user's own tiles
    #
    # 2026-08-21. Three builds were modelled by eye off a 256-pixel preview,
    # and all three were wrong in the same way. Measured off the real file, the
    # reason was one number:
    #
    #   his pipe   10.63" wide at an 8.27" pitch  -> they OVERLAP by 2.36"
    #   mine        6.00" wide at a  7.50" pitch  -> they sit 1.50" APART
    #
    # "שכאילו זה אחד בתוך השני". He said it twice before it was measured.
    #
    # So stop copying. SketchUp can load his .skp, and the plugin already does
    # exactly this for door casings and handles. What goes on the roof is HIS
    # component, not an imitation of it - and it is cheap for the same reason
    # everything else here is: one definition, many instances.
    #
    # HIS AXES ARE NOT OURS. In the file the pipe lies along X, is 10.63 wide
    # in Z, and stands 3.79 in Y. Our placement frame is X across, Y up the
    # slope, Z out of the roof. The remap lives in RoofTilePlace, in one place.
    def self.asset_dir
      File.join(File.dirname(__FILE__), 'assets', 'ROOF TILES')
    end

    def self.asset_file(name)
      File.join(asset_dir, "#{name}.skp")
    end

    # Which .skp backs which material. A material with no entry here builds the
    # generated pipe instead, so nothing breaks when the folder is missing -
    # and the test suite, which has no assets, keeps taking the built-in path.
    # NOTHING IS MAPPED TODAY, and that is a result, not an oversight.
    # Roman was wired to his ROMAN_TILED_ROOF here on 2026-08-21 and he asked
    # for it back the way it was, so it is unmapped again - the generated pipe
    # is what he approved. The loader stays because it works, and because the
    # measurement it produced is what corrected the geometry: his pipes are
    # 10.63" wide at an 8.27" pitch and therefore OVERLAP, which no amount of
    # squinting at a preview image was ever going to reveal.
    #
    # Map a material here and it uses his file instead. Nothing else changes.
    def self.asset_for(shape_name)
      {}[shape_name.to_s]
    end

    # The single repeating piece inside his file, plus the numbers needed to
    # lay it: how long it was modelled, how wide one piece is, and the pitch
    # its own copies were spaced at.
    #
    # The pitch is READ, never assumed: the file holds three copies of one pipe
    # and the gap between their origins is the answer. Assuming it is what put
    # a gap where his has an overlap.
    def self.asset_tile(model, shape_name)
      name = asset_for(shape_name)
      return nil if name.nil?
      path = asset_file(name)
      return nil unless File.file?(path)
      outer = model.definitions[name] || model.definitions.load(path)
      return nil if outer.nil?
      kids = outer.entities.grep(Sketchup::ComponentInstance)
      return nil if kids.empty?
      defn = kids.first.definition
      b = defn.bounds
      { defn: defn, len: b.width.to_f, high: b.depth.to_f, wide: b.height.to_f,
        pitch: asset_pitch(kids, b.height.to_f), origin: b.min }
    rescue StandardError => e
      puts "[RoofTiles] asset #{shape_name}: #{e.message}"
      nil
    end

    # Centre to centre, measured off the copies in his own file. One copy and
    # there is nothing to measure, so the piece's own width is the fallback -
    # pieces butted, never overlapped, because an invented overlap is exactly
    # the mistake this method exists to stop.
    def self.asset_pitch(kids, fallback)
      zs = kids.map { |k| k.transformation.origin.z.to_f }.sort
      return fallback if zs.length < 2
      gaps = zs.each_cons(2).map { |a, b| (b - a).abs }.reject { |g| g < 1.0e-6 }
      return fallback if gaps.empty?
      gaps.min
    end

    # ------------------------------------------------------------- geometry

    # The end profile, in the piece's own X/Z, left to right along the bottom.
    # `round` false gives a plain rectangle - slate and standing seam.
    # Both shapes run LEFT to RIGHT and both leave the UNDERSIDE out: the
    # piece sits on the roof, nobody ever sees its belly, and one less face
    # per instance is one less face a few hundred times over.
    #
    # The arc already begins at (-half, 0) and ends at (half, 0), so it needs
    # no start or end point bolted on - doing that gave two identical points
    # in a row, and add_face quietly refuses those (caught by rt77 before this
    # ever reached SketchUp).
    # `segs` overrides the segment count for one call. The little edge pieces
    # keep the cheap 4; a RUN is one definition for the whole roof, so it can
    # afford 8 without changing the budget by a single face per instance.
    def self.profile(w, h, round, segs = nil)
      half = w / 2.0
      return [[-half, 0.0], [-half, h], [half, h], [half, 0.0]] unless round
      n = [(segs || arc_segments).to_i, 2].max
      (0..n).map do |i|
        a = Math::PI * i / n.to_f
        [-half * Math.cos(a), h * Math.sin(a)]
      end
    end

    # A HOLLOW half round: the outer arc left to right, then the inner arc back
    # again, one closed crescent. Swept `closed`, the two ends come out as thin
    # crescents and the tube is open along its belly, exactly like a real tile
    # lying on the roof.
    #
    # A wall thicker than the pipe would turn the crescent inside out, so a
    # silly thickness falls back to the solid profile rather than building
    # rubbish. rt82 pins that.
    def self.shell_profile(w, h, t, segs = nil)
      half = w / 2.0
      return profile(w, h, true, segs) if t <= 0.0 || t >= half || t >= h
      outer = profile(w, h, true, segs)
      inner = profile(w - (2.0 * t), h - t, true, segs)
      outer + inner.reverse
    end

    # Sweep a profile from y0 to y1. Explicit faces, no pushpull: pushpull on
    # a tiny profile is where SketchUp starts inventing internal faces, and
    # "avoid unnecessary internal faces" is a stated requirement.
    #
    # `closed` joins the last point back to the first, which is what a hollow
    # crescent needs and what an open arc must NOT have. It defaults to false,
    # so every piece written before the runs behaves exactly as it did.
    def self.build_extrusion!(ents, prof, y0, y1, closed = false)
      a = prof.map { |(x, z)| Geom::Point3d.new(x, y0, z) }
      b = prof.map { |(x, z)| Geom::Point3d.new(x, y1, z) }
      made = 0
      last = closed ? prof.length : prof.length - 1
      (0...last).each do |i|
        j = (i + 1) % prof.length
        made += 1 if add_face(ents, [a[i], a[j], b[j], b[i]])
      end
      # The two ends. The underside is left OPEN on purpose: it sits on the
      # roof and is never seen, and leaving it out is one less face per
      # instance across the whole roof.
      made += 1 if add_face(ents, a)
      made += 1 if add_face(ents, b.reverse)
      made
    end

    # NO LINES. Every chord of the fold meets its neighbour at a shallow angle,
    # and SketchUp draws each of those joins as a black edge - which is what the
    # user saw: "תוריד את הקווים תעשה את הטיל יותר עגול ונקי בלי קווים".
    #
    # soft hides the line, smooth blends the shading across it, so eight flat
    # chords read as one round surface. Done on the DEFINITION, once, so it
    # costs nothing per instance.
    # Only an edge with a face on BOTH sides is softened. The silhouette - the
    # cut end of a tile, the outline of the fold - keeps its line, so the piece
    # still reads as an object and only the chords across its curve disappear.
    def self.soften_all!(ents)
      ents.grep(Sketchup::Edge).each do |e|
        next unless e.respond_to?(:faces) && e.faces.length == 2
        e.soft = true
        e.smooth = true
        e.hidden = false
      end
    rescue StandardError => e
      puts "[RoofTiles] soften: #{e.message}"
    end

    def self.add_face(ents, pts)
      f = ents.add_face(pts)
      !f.nil?
    rescue StandardError
      false
    end

    # Every piece for one material, built (or fetched) in one call.
    def self.all(model, shape_name)
      { eave: eave(model, shape_name), rake: rake(model, shape_name),
        ridge: ridge(model, shape_name), hip: hip(model, shape_name) }
    end
  end
end
