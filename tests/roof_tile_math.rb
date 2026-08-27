# encoding: utf-8
# Interior Pro - roof_tile_math.rb
#
# Pure geometry for laying tile COURSES on a roof plane. NO SketchUp API, NO
# Geom, no model access, no state. Plain numbers and plain arrays in and out,
# so the whole file runs (and is tested) under plain Ruby - exactly like
# arc_math.rb. Tested by tests/rt72.rb.
#
# WHY THIS FILE EXISTS (measured 2026-08-18)
# We probed a roof built by Instant Roof (Vali Architects) in the user's own
# project - 63ft x 59ft, `debug_valiroof.rb`, `valiroof_report.txt`. It does
# NOT model individual tiles. It builds:
#   * ~420 course strips, 5 faces each, one per row per plane
#   * 408 instances of ONE 1-face component at the eave (va_BirdStop)
#   * the tile pattern itself as a TEXTURE (Roofing Tile Spanish, 30 x 24.7")
# About 2,500 faces for a whole roof. The rule it follows:
#
#   BUILD 3D ONLY WHERE THE SILHOUETTE SHOWS. THE FIELD IS FLAT + TEXTURE.
#
# We follow the same rule and add two things it leaves flat: the rake (gable)
# edge, and a scalloped butt line on every course instead of a straight one.
#
# THE PLANE'S OWN 2D FRAME - the one idea to learn here
# A roof plane gets its own flat coordinate system:
#   u = ACROSS the slope, horizontal, along the eave
#   v = UP the slope, measured ALONG THE SURFACE (true length, not plan)
#   v = 0 sits at the lowest point of the plane, i.e. the eave
# Courses are laid from the eave UP, because that is how a roof is really
# laid and it puts the bottom course exactly on the eave every time.
#
# Because v is true length, `exposure` is the real distance up the roof
# between two course lines - the number a roofer would give you. Nothing in
# this file ever needs the pitch again once the frame is built.
#
# UNITS: inches everywhere, like the rest of the plugin.

module InteriorPro
  module RoofTileMath
    EPS = 1e-9 unless const_defined?(:EPS, false)

    # How each material is laid. Kept HERE, in the pure file, so the numbers
    # are covered by the test suite instead of buried in the builder.
    #
    #   tile_w   width of one tile across the slope
    #   exposure how much of each course is left showing, measured up-slope
    #   relief   how far the course butt stands proud of the plane
    #   scallop  amplitude of the wavy butt line (0 = a straight step)
    #   stagger  true = every other course shifts half a tile
    #   texture  the field texture that goes with it
    #
    # A METHOD, NOT A CONSTANT - and this is not a style choice.
    # `X = {...} unless const_defined?(:X)` is NOT re-read by
    # InteriorPro.reload!: the old value simply stays in memory and the new
    # one is never seen. That pattern cost a whole round on 2026-08-14
    # (DEFAULT_STATE) and it bit again on 2026-08-18 - four materials were on
    # disk, the menu offered them, and the roof kept coming out a flat colour.
    # Any table a person will edit must be a method. tests/rt73.rb fails if
    # this one turns back into a constant.
    def self.shapes
      {
        'barrel' => { tile_w: 13.0, exposure: 14.0, relief: 1.6, scallop: 1.1,
                      stagger: false, texture: 'roof_barrel_tile.jpg',
                      label: 'Barrel Tile (Spanish S)' },
        'roman'  => { tile_w: 13.0, exposure: 14.0, relief: 1.0, scallop: 0.45,
                      stagger: false, texture: 'roof_roman_tile.jpg',
                      label: 'Roman Tile (flat pan)',
                      # A PAN AND A ROLL, sized by the user (2026-08-21).
                      #
                      # First it was measured off his own ROMAN_TILED_ROOF.skp:
                      # a 10.63" tile on an 8.27" pitch. He looked at the built
                      # roof and asked for a fatter roll and less flat pan
                      # showing between two of them: "תצמצם את הרווחים ביניהם
                      # נגיד ל-2 ואז חצי העיגול לעשות 8".
                      #
                      #   roll 8" + gap 2"  ->  10" between centres
                      #   the roll overhangs the pan by half itself, so the
                      #   whole tile is 10 + 4 = 14" wide
                      #
                      # Written as fractions of the run pitch because that is
                      # what run_cover_w / run_height take. run_cover is over
                      # 1.0 on purpose: the tile is WIDER than its spacing -
                      # that overhang is what laps the joint.
                      run_pitch: 10.0, run_cover: 14.0 / 10.0,
                      # The roll keeps the PROPORTION he has been looking at -
                      # 2.28" tall on a 4.72" roll - so the bigger roll is the
                      # same shape, only larger: 0.48 * 8" = 3.84". He left the
                      # height to us and asked only for whatever is lightest;
                      # height costs nothing, the segment count does, and that
                      # is untouched. The wider pitch is the real saving - it
                      # puts about 17% fewer pieces on the same roof.
                      run_rise: 3.84 / 14.0,
                      # THE RIDGE CAP IS STATED, NOT DERIVED (2026-08-21).
                      # 13" across and 1.42" of arch - his numbers: the crown
                      # came down 3" off the 4.42" it had, the width went to
                      # 10" and then to 13" once he saw it: "אני רוצה להרחיב
                      # אותו ל-13, אבל לא להגביה אותו רק להרחיב." So the arch
                      # stays exactly where it is and only the span grows.
                      # Stating them here is the point: the cap stops following
                      # the tile around, which is what kept changing it behind
                      # his back. Roman is the ONLY material that names them,
                      # so nothing else moved.
                      cap_w: 13.0, cap_crown: 1.42, cap_round: true },
        # FLAT TILE - given real geometry on 2026-08-21c, from the user's
        # photograph of a flat concrete tile roof.
        #
        # Until now it had NONE. `scallop` is the "profile is curved" flag and
        # a flat tile is not curved, so runs? said no, place_runs! returned
        # nothing, and the roof came out as a smooth coloured deck with the
        # photograph painted on it - exactly the hole standing seam was in
        # before 2026-08-21. `run_flat` is its way in: a FLAT plate, not a
        # roll and not a rib.
        #
        # THE TILES SIT ON EACH OTHER, and that is the whole shape. The user
        # asked the one question that mattered - "האם הם יושבים אחד על השני?"
        # - after seeing a mockup where each course was a separate slab lying
        # on the deck, and that mockup read as a tiled FLOOR. On a real roof
        # the NOSE of every tile rests on the HEAD of the one below it; the
        # raised nose is what casts the shadow line at every course, and it is
        # the only thing that makes it read as a roof. See
        # RoofTileParts.flat_tile - the piece carries its own nose, ramp and
        # flat field, so nothing stacks: every head lies on the deck.
        #
        # 13 x 13 is his approved size, 0.7" step. The texture is 52 x 52 to
        # stay a whole 4 x 4 of them - rt73 fails if the painted grid and the
        # 3D grid ever drift apart.
        #
        # STAGGERED, half a tile on every other course. It was built straight
        # first, off his photograph, and he looked at the result and asked for
        # the broken bond instead: "אני רוצה שזה יהיה סטאגרן". `stagger` and
        # course_phase had been sitting here unused since the texture grid was
        # written; RoofTilePlace.flat_slots is what finally reads them, and it
        # walks the COURSES on the outside so it can.
        #
        # THE CAP IS STATED SO IT CANNOT MOVE. cap_w / cap_crown are written
        # out at exactly the numbers the old derivation produced (6.0 * 1.15
        # and 2.28 * 1.15): adding run_* would otherwise have swelled the cap
        # from 6.9" to 14.95" behind his back, which is the trap cap_crown_
        # stated? exists to shut. He asked for tiles, not for a new cap.
        # Its LIFT does follow the tiles - a cap floating 2.28" over a 0.7"
        # tile would show daylight underneath - see cap_lift_for.
        'slate'  => { tile_w: 13.0, exposure: 13.0, relief: 0.6, scallop: 0.0,
                      stagger: true, texture: 'roof_flat_slate.jpg',
                      label: 'Flat Slate Tile',
                      run_flat: true, run_courses: true,
                      run_pitch: 13.0, run_cover: 1.0,
                      run_rise: 0.7 / 13.0,
                      # SETBACK 0: the boundary tiles are CUT on the line now, so pulling
                      # them back as well would only re-open the gap the cutting
                      # closed. Stated, so nothing derives one.
                      # crown 1.0 is HIS number, set in two steps: "מקסימום
                      # 2" brought it from the derived 2.622 to 2.0, and then
                      # "תוריד את הגובה שלו ב-1 אחד נוסף" - the cap also
                      # rides a tile height (0.7) above the deck, so the
                      # crown alone under-states what the eye sees.
                      cap_w: 6.9, cap_crown: 1.0, ridge_setback: 0.0 },
        # STANDING SEAM - given a real 3D shape on 2026-08-21. Until then it
        # had none at all: `scallop` is the "profile is curved" flag and a
        # standing seam is not curved, so runs? said no and the roof came out
        # as a flat coloured surface with nothing on it. `run_seam` is its own
        # way in - a SQUARE rib, not a round roll.
        #
        # The shape, from the drawing the user approved:
        #   seam a rectangle 2" thick standing 1" proud, centred on the joint
        #        between two pans - "אני רוצה שזה יהיה רוחב 2 וגובה של 1",
        #        after seeing the first build at 1" x 1.75"
        #   gap  26" of flat pan showing BETWEEN two ribs - "תעשה בין
        #        הבליטות מרווח של 26 אינץ'"
        # so the pans are 2 + 26 = 28" centre to centre, the panel is 28 + 1 =
        # 29" across, and the run is 12 faces however wide it gets.
        #
        # AND IT KEEPS ITS LINES. Every other piece is softened so its chords
        # disappear; this one is not, because the user asked for the opposite
        # here: "אני רוצה שכן יראו את הקווים ואת הפינות - רק בגג הזה". Sharp
        # arrises are what a folded metal panel looks like.
        #
        # THE RIDGE IS A FOLDED PLATE, NOT AN ARCH (2026-08-21). From the
        # photograph the user sent of a real one: "רידג' אחיד שמקופל לשני
        # הצדדים של הגג, כל צד בערך 5". So 5" down each slope - a 10" cap -
        # and a crown of ZERO, which is what makes it a fold instead of a
        # barrel. It still lifts to the ribs' height so it lands on top of
        # them, exactly like the flashing in his picture.
        # THE RIBS STOP UNDER THE CAP (2026-08-21, second pass). setback was 0
        # - "the cap rides on the rib tops, so they can run right up to the
        # line" - and the user saw exactly that: the rib ends slide in under
        # the hovering cap and show. "הברזלים נכנסים לתוך הרידג' קאפ וזה לא
        # נראה טוב... שזה יחתך איפה שהרידג' מתחיל." The cap covers 5" down
        # each slope (cap_w 10), so a rib cut 4" short of the line hides its
        # end a clear inch inside the cap. STATED here, like the cap numbers,
        # so no other number can move it.
        'seam'   => { tile_w: 16.0, exposure: 0.0,  relief: 1.0, scallop: 0.0,
                      stagger: false, texture: 'roof_standing_seam.jpg',
                      label: 'Standing Seam Metal',
                      run_seam: true,
                      run_pitch: 28.0, run_cover: 29.0 / 28.0,
                      run_rise: 1.0 / 29.0,
                      cap_w: 10.0, cap_crown: 0.0, ridge_setback: 4.0 },
        # METAL ROOF TILES - the user's second reference (Metal Roof Tiles.skp,
        # a Trimble parametric component, 2026-08-20). It is NOT standing seam
        # and 'seam' above is left exactly as it was: standing seam runs in one
        # unbroken sheet, this one is pressed into TILES, so it has both ribs
        # across the slope and a step up it every course.
        #
        # run_* are this material's own pipe numbers, and they are what makes
        # it read as pressed metal rather than as clay:
        #   run_pitch   16" rib spacing, the panel's own module
        #   run_cover   a wide crest - 85% of the pitch, a narrow valley
        #   run_rise    and a SHALLOW one; metal is pressed, not moulded
        #   run_courses the step every course, which clay does not have
        # SPANISH TILE. Built as pressed metal tile and renamed by the user on
        # 2026-08-21 once he saw it - the folded sheet with a step every course
        # is the shape he wanted all along, and Barrel Tile left the menu the
        # same day because this replaces it.
        #
        # Shrunk from a 16" module to 7" at his measurement ("תקטין את הטייל
        # ל-7 זה כרגע יותר מידי גדול"). tile_w, exposure and run_pitch move
        # together on purpose: the painted grid and the 3D grid are the same
        # grid, and rt73 fails if they drift apart. The texture is 3 modules
        # wide by 2 tall, so its size follows to 21 x 14.
        # THE COURSE STAYED LONG. "תקטין את הטייל ל-7" is the tile's WIDTH -
        # a real Spanish tile is about seven inches across and twice that up
        # the slope. Shrinking BOTH to seven took the piece count from 2,278
        # to 11,960 on his own roof, over the safety brake, so the roof built
        # with no tiles at all and looked like they had been deleted.
        'metaltile' => { tile_w: 7.0, exposure: 14.0, relief: 1.0, scallop: 0.5,
                         stagger: false, texture: 'roof_metal_tile.jpg',
                         label: 'Spanish Tile',
                         # run_cover and run_rise are UNCHANGED from the shape
                         # he approved. Only the module shrank. run_rise was
                         # briefly "improved" to 0.34 on the same edit and he
                         # caught it: he asked for a size and a name, and a
                         # third change he did not ask for is a bug even when
                         # the number looks better on paper.
                         run_pitch: 7.0, run_cover: 0.85, run_rise: 0.22,
                         run_courses: true,
                         # PAINT IT FLAT (2026-08-21). The fold now carries the
                         # whole pattern in 3D, so a photographed tile texture
                         # under it is two patterns fighting - the user asked
                         # for the colour picker alone, on the tiles AND on the
                         # deck beneath them. The texture stays registered and
                         # on disk so rt73 keeps checking the grid, it is just
                         # not painted on any more.
                         flat_color: true }
      }
    end

    # Is this material pressed into courses, so a run is a row of short pieces
    # with a step between them rather than one unbroken pipe? Clay is not;
    # metal tile is. The flag is explicit because `exposure` is set on the clay
    # materials too - it drives their TEXTURE grid, not their geometry, and
    # reading it as "make steps" is exactly the mistake that produced the
    # 50,652-face roof on 2026-08-19.
    # Does this material want the plain colour instead of its texture?
    def self.flat_color?(name)
      s = shape(name)
      !s.nil? && s[:flat_color] == true
    end

    def self.run_courses?(name)
      s = shape(name)
      !s.nil? && s[:run_courses] == true && s[:exposure].to_f > EPS
    end

    # exposure 0 means "this material has no courses at all" - standing seam
    # runs in one unbroken sheet from ridge to eave, so it gets ribs across
    # the slope instead of steps up it. Asking for its courses is not an
    # error, it is simply an empty list.
    def self.shape(name)
      shapes[name.to_s]
    end

    def self.courses?(name)
      s = shape(name)
      !s.nil? && s[:exposure] > EPS
    end

    # Does this material run as ONE long half-pipe from ridge to eave?
    #
    # The user's own reference settled this on 2026-08-20 (Roman Tiled Roof.skp,
    # material `ceramicrooftile`): a Spanish/Roman roof reads as an unbroken
    # half round per run over the whole slope, NOT as a tile per course. That
    # is also why it is cheap - a run's face count is its cross section, so a
    # 30ft run and a 3ft run cost exactly the same.
    #
    # Only the ROUND materials work that way. `scallop` is already the "this
    # profile is curved" flag, so barrel and roman answer true while flat slate
    # and standing seam answer false and keep the flat treatment they have.
    # `run_seam` joins `scallop` here (2026-08-21). Standing seam runs exactly
    # like the clay pipes - one long piece from ridge to eave, priced by its
    # cross section - it simply is not ROUND, and scallop only ever meant
    # "curved". Slate and shingle answer false as before.
    def self.runs?(name)
      s = shape(name)
      return false if s.nil? || s[:tile_w].to_f <= EPS
      s[:scallop].to_f > EPS || s[:run_seam] == true || s[:run_flat] == true
    end

    # A square rib instead of a round roll.
    def self.seam?(name)
      s = shape(name)
      !s.nil? && s[:run_seam] == true
    end

    # A FLAT plate - no roll, no rib, no fold. The third way in to runs?, and
    # the reason it exists is written on the slate entry above: a flat tile is
    # a real 3D piece even though nothing about it is curved, and `scallop`
    # alone can never say so.
    def self.run_flat?(name)
      s = shape(name)
      !s.nil? && s[:run_flat] == true
    end

    # Where the vertical scanline lives. spans_at answers "at height v = c,
    # which u stretches are inside the plane?" - a COURSE question. A run is
    # the same question turned 90 degrees: "at u = c, which v stretches are
    # inside?". Swapping the pair is the whole difference, so there is one
    # scanline in this file and not two that can disagree.
    def self.flip_uv(poly)
      return [] if poly.nil?
      poly.map { |p| [p[1], p[0]] }
    end

    # The v spans of the plane at across-slope position u = c, bottom to top.
    def self.v_spans_at(poly, c, min_len = 0.0)
      spans_at(flip_uv(poly), c, min_len)
    end

    # ------------------------------------------------------------ vectors

    def self.vlen(a)
      Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
    end

    def self.vnorm(a)
      l = vlen(a)
      return nil if l < EPS
      [a[0] / l, a[1] / l, a[2] / l]
    end

    def self.vsub(a, b)
      [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
    end

    def self.vadd(a, b)
      [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
    end

    def self.vmul(a, k)
      [a[0] * k, a[1] * k, a[2] * k]
    end

    def self.vdot(a, b)
      a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
    end

    def self.vcross(a, b)
      [a[1] * b[2] - a[2] * b[1],
       a[2] * b[0] - a[0] * b[2],
       a[0] * b[1] - a[1] * b[0]]
    end

    # -------------------------------------------------------------- frame

    # The plane's own axes, from its normal.
    #
    # Returns { u:, v:, n:, flat:, pitch: } or nil if the normal is degenerate
    # or VERTICAL (a wall, not a roof - nothing to lay tiles on).
    #
    #   n     the normal, flipped to point UP so a face's winding never
    #         changes the answer
    #   v     straight up the slope, in the plane
    #   u     across the slope, horizontal, and u x v = n (right handed)
    #   flat  true when the plane is dead level; then v is arbitrary (+Y) and
    #         the caller has to choose a direction itself
    #   pitch rise per 12 of run, the number the dialog already speaks
    def self.plane_frame(normal)
      n = vnorm(normal)
      return nil if n.nil?
      n = vmul(n, -1.0) if n[2] < 0.0            # always look at the top face
      return nil if n[2].abs < EPS               # vertical: not a roof plane

      if (1.0 - n[2]).abs < 1e-9                 # dead flat
        return { u: [1.0, 0.0, 0.0], v: [0.0, 1.0, 0.0], n: [0.0, 0.0, 1.0],
                 flat: true, pitch: 0.0 }
      end

      # the in-plane direction closest to straight up = up the slope
      v = vnorm(vsub([0.0, 0.0, 1.0], vmul(n, n[2])))
      return nil if v.nil?
      u = vnorm(vcross(v, n))
      return nil if u.nil?
      # rise per 12 of run: the slope of v itself
      run = Math.sqrt(v[0] * v[0] + v[1] * v[1])
      pitch = run < EPS ? 0.0 : (v[2] / run) * 12.0
      { u: u, v: v, n: n, flat: false, pitch: pitch }
    end

    def self.project(pt, origin, u, v)
      d = vsub(pt, origin)
      [vdot(d, u), vdot(d, v)]
    end

    def self.unproject(uv, origin, u, v)
      vadd(origin, vadd(vmul(u, uv[0]), vmul(v, uv[1])))
    end

    # Take a roof face's 3D outline and hand back everything the rest of this
    # file needs. The origin is chosen so that v = 0 lands exactly on the
    # LOWEST point of the plane - the eave - and u = 0 on its left edge.
    #
    # Returns nil for a vertical or degenerate face.
    def self.plane_uv(points, normal)
      fr = plane_frame(normal)
      return nil if fr.nil?
      return nil if points.nil? || points.length < 3
      o = points[0]
      raw = points.map { |p| project(p, o, fr[:u], fr[:v]) }
      umin = raw.map { |p| p[0] }.min
      vmin = raw.map { |p| p[1] }.min
      poly = raw.map { |p| [p[0] - umin, p[1] - vmin] }
      origin = unproject([umin, vmin], o, fr[:u], fr[:v])
      { poly: poly, origin: origin, u: fr[:u], v: fr[:v], n: fr[:n],
        flat: fr[:flat], pitch: fr[:pitch],
        u_span: poly.map { |p| p[0] }.max,
        v_span: poly.map { |p| p[1] }.max }
    end

    # ------------------------------------------------------------ clipping
    #
    # Added 2026-08-21c for the flat tile. A tile at a hip or a valley has to
    # be CUT on the line - "שייחתכו במדויק" - and an instance cannot be cut,
    # so the boundary tiles are built as their own little groups from the
    # clipped footprint. Everything here is plain 2D polygon work in a plane's
    # own u/v; no SketchUp, and nothing else in the plugin calls it yet.
    def self.poly_area(poly)
      return 0.0 if poly.nil? || poly.length < 3
      a = 0.0
      n = poly.length
      n.times do |i|
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        a += (x1 * y2) - (x2 * y1)
      end
      a / 2.0
    end

    def self.poly_ccw(poly)
      poly_area(poly).negative? ? poly.reverse : poly
    end

    # Keep the part of `poly` on the LEFT of the directed line a -> b.
    def self.clip_left(poly, a, b)
      return [] if poly.nil? || poly.length < 3
      out = []
      n = poly.length
      n.times do |i|
        cur = poly[i]
        nxt = poly[(i + 1) % n]
        dc = ((b[0] - a[0]) * (cur[1] - a[1])) - ((b[1] - a[1]) * (cur[0] - a[0]))
        dn = ((b[0] - a[0]) * (nxt[1] - a[1])) - ((b[1] - a[1]) * (nxt[0] - a[0]))
        out << cur if dc >= -1.0e-9
        next unless (dc > 0) != (dn > 0)
        t = dc / (dc - dn)
        out << [cur[0] + ((nxt[0] - cur[0]) * t), cur[1] + ((nxt[1] - cur[1]) * t)]
      end
      out
    end

    # Cut `rect` down to the part of it inside `region`.
    #
    # ONLY THE EDGES THAT ACTUALLY REACH IT are used, and that is the whole
    # trick: clipping by every edge of the region is the textbook algorithm and
    # it is only correct for a CONVEX region, while a roof plane with a dormer
    # or a light well punched out of it is not convex. An edge that runs
    # nowhere near this tile cannot be the one cutting it, so leaving it out
    # keeps the answer exact for the cases that matter - a hip, a valley, a
    # rake, the side of a dormer - and stops a far-away concave edge from
    # eating a tile in the middle of the roof.
    def self.clip_to_poly(rect, region, reach = nil)
      return [] if rect.nil? || rect.length < 3 || region.nil? || region.length < 3
      cx = rect.map { |p| p[0] }.sum / rect.length.to_f
      cy = rect.map { |p| p[1] }.sum / rect.length.to_f
      r = reach || (rect.map { |p| Math.hypot(p[0] - cx, p[1] - cy) }.max + 0.01)
      rr = poly_ccw(region)
      out = rect
      n = rr.length
      n.times do |i|
        a = rr[i]
        b = rr[(i + 1) % n]
        next if Math.hypot(b[0] - a[0], b[1] - a[1]) < 1.0e-9
        next if seg_dist(a, b, [cx, cy]) > r
        out = clip_left(out, a, b)
        return [] if out.length < 3
      end
      out = clean_poly(out)
      return [] if out.empty?
      # AND THE RESULT MUST ACTUALLY LIE INSIDE (2026-08-21c, fifth pass).
      # The reach filter above skips edges far from the tile - which also
      # means a tile floating entirely OUTSIDE the region, far from every
      # edge, sails through unclipped and comes back whole. One did: a full
      # phantom column of tiles off the rake of a hip plane, found by the
      # plain-Ruby measurement. The centroid test costs one point-in-polygon
      # and closes that door for good.
      ox = out.sum { |p| p[0] } / out.length
      oy = out.sum { |p| p[1] } / out.length
      poly_contains?(rr, [ox, oy]) ? out : []
    end

    # Plain ray-cast point-in-polygon, boundary points counted by the same
    # half-open rule the scanline uses.
    def self.poly_contains?(poly, pt)
      x, y = pt
      hit = false
      n = poly.length
      n.times do |i|
        ax, ay = poly[i]
        bx, by = poly[(i + 1) % n]
        next if (ay > y) == (by > y)
        xx = ax + ((y - ay) * (bx - ax) / (by - ay))
        hit = !hit if x < xx
      end
      hit
    end

    # Keep the slice of `poly` between two heights. Used to split a cut tile
    # into its nose, its ramp and its flat field - three planar faces, because
    # one face over the whole thing would be bent and SketchUp refuses those.
    def self.clip_band(poly, va, vb)
      out = clip_left(poly, [0.0, va], [1.0, va])
      return [] if out.length < 3
      clean_poly(clip_left(out, [1.0, vb], [0.0, vb]))
    end

    # EVERY CLIPPED POLYGON GOES THROUGH HERE, and skipping it is what put the
    # bare stripes on the user's roof (2026-08-21c, the hard way). When a tile
    # corner lies exactly ON the clip line - and at the eave line every tile
    # does - clip_left keeps the corner AND emits the intersection point, which
    # is the same point again. The test stub's add_face swallowed the
    # duplicate; real SketchUp raises, the whole cut tile died, and every hip,
    # valley and rake grew a bare stripe of deck where its cut tiles should
    # be. §0 of the 2026-08-21b handoff, learned twice now: geometry that only
    # passed the lenient stub has not passed anything.
    def self.clean_poly(poly, tol = 1.0e-3)
      return [] if poly.nil? || poly.length < 3
      out = []
      poly.each do |p|
        out << [p[0], p[1]] if out.empty? ||
                               Math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) > tol
      end
      out.pop while out.length > 2 &&
                    Math.hypot(out[0][0] - out[-1][0],
                               out[0][1] - out[-1][1]) <= tol
      return [] if out.length < 3 || poly_area(out).abs < 0.25
      out
    end

    def self.seg_dist(p, q, x)
      dx = q[0] - p[0]
      dy = q[1] - p[1]
      ll = (dx * dx) + (dy * dy)
      return Math.hypot(x[0] - p[0], x[1] - p[1]) if ll < 1.0e-12
      t = (((x[0] - p[0]) * dx) + ((x[1] - p[1]) * dy)) / ll
      t = 0.0 if t < 0.0
      t = 1.0 if t > 1.0
      Math.hypot(x[0] - (p[0] + (dx * t)), x[1] - (p[1] + (dy * t)))
    end

    # ----------------------------------------------------------- scanline

    # Where does the horizontal line v = c lie INSIDE the polygon?
    # Returns a list of [u1, u2] spans, left to right, never overlapping.
    #
    # This is what cuts a course at a hip, a valley, or a rake. A plane with
    # a dormer punched out of it simply comes back as two spans on the
    # courses that meet the dormer, and one span everywhere else - no special
    # case anywhere.
    #
    # Vertices exactly on the line are handled by the half-open rule
    # (v1 <= c < v2), so a course line that grazes a hip apex gives a zero
    # length span rather than a doubled crossing.
    def self.spans_at(poly, c, min_len = 0.0)
      return [] if poly.nil? || poly.length < 3
      xs = []
      n = poly.length
      n.times do |i|
        a = poly[i]
        b = poly[(i + 1) % n]
        va = a[1]
        vb = b[1]
        next if (va - vb).abs < EPS               # horizontal edge: skip
        lo, hi = va < vb ? [va, vb] : [vb, va]
        next unless c >= lo - EPS && c < hi - EPS
        t = (c - va) / (vb - va)
        xs << (a[0] + (b[0] - a[0]) * t)
      end
      return [] if xs.length < 2
      xs.sort!
      out = []
      (0...(xs.length - 1)).step(2) do |i|
        u1 = xs[i]
        u2 = xs[i + 1]
        out << [u1, u2] if (u2 - u1) > min_len + EPS
      end
      out
    end

    # SUBTRACT WHAT IS NOT ROOF ANY MORE (2026-09-02B). A dormer standing on
    # a slope is a HOLE in it, and a run crossing that hole has to become two
    # runs - one below it, one above - exactly the way a valley already splits
    # one. Both lists are [lo, hi] pairs on the same axis; the cuts need not
    # be sorted and may overlap each other.
    def self.spans_minus(spans, cuts, min_len = 0.0)
      return Array(spans) if cuts.nil? || cuts.empty?
      out = []
      Array(spans).each do |(lo, hi)|
        pieces = [[lo, hi]]
        cuts.each do |(clo, chi)|
          next if clo.nil? || chi.nil? || chi <= clo
          nxt = []
          pieces.each do |(a, b)|
            if chi <= a + EPS || clo >= b - EPS
              nxt << [a, b]
              next
            end
            nxt << [a, clo] if clo - a > EPS
            nxt << [chi, b] if b - chi > EPS
          end
          pieces = nxt
        end
        pieces.each { |(a, b)| out << [a, b] if (b - a) > min_len + EPS }
      end
      out.sort_by { |p| p[0] }
    end

    # ------------------------------------------------------------ courses

    # The v of every course butt line, from the eave up.
    #
    # `first` shifts the bottom course; leave it 0 and the bottom course sits
    # exactly on the eave, which is what a real roof does.
    #
    # `max_courses` is a safety valve, not a preference: a silly exposure on
    # a huge roof must not try to build a million strips. When it bites, the
    # list is truncated and `courses` reports it - it is never silent.
    def self.course_vs(v_span, exposure, first = 0.0, max_courses = 400)
      return [] if exposure.nil? || exposure <= EPS
      return [] if v_span.nil? || v_span <= EPS
      out = []
      k = 0
      loop do
        c = first + k * exposure
        break if c >= v_span - EPS
        out << c
        k += 1
        break if k > max_courses
      end
      out
    end

    # Every course on one plane, already cut to the plane's outline.
    #
    #   [{ index:, v:, spans: [[u1, u2], ...] }, ...]
    #
    # Courses whose spans all came out shorter than `min_len` are dropped
    # entirely, so the tip of a hip does not collect a crowd of slivers.
    def self.courses(plane, shape_name, opts = {})
      s = shape(shape_name)
      return { courses: [], truncated: false } if s.nil?
      exposure = (opts[:exposure] || s[:exposure]).to_f
      return { courses: [], truncated: false } if exposure <= EPS

      max_c = (opts[:max_courses] || 400).to_i
      min_len = (opts[:min_len] || 1.0).to_f
      vs = course_vs(plane[:v_span], exposure, (opts[:first] || 0.0).to_f, max_c)
      truncated = vs.length > max_c
      vs = vs.first(max_c)

      out = []
      vs.each_with_index do |c, i|
        spans = spans_at(plane[:poly], c, min_len)
        next if spans.empty?
        out << { index: i, v: c, spans: spans }
      end
      { courses: out, truncated: truncated }
    end

    # ------------------------------------------------------------ scallop

    # The wavy butt line of one course span, as [[u, drop], ...].
    #
    # `drop` is how far below the course line that point hangs, always >= 0.
    # A crest (the cover tile) hangs the full amplitude; a trough (the pan)
    # hangs nothing. amp = 0 gives a plain straight step, which is exactly
    # what slate and standing seam want.
    #
    # `phase` is a GLOBAL u offset, not a per-span one. Two spans of the same
    # course either side of a dormer therefore keep the same wave rhythm, and
    # so does the course above - the tiles line up down the whole roof.
    def self.scallop(u1, u2, tile_w, amp, opts = {})
      return [[u1, 0.0], [u2, 0.0]] if amp.nil? || amp <= EPS ||
                                       tile_w.nil? || tile_w <= EPS
      segs = [(opts[:segments] || 4).to_i, 2].max
      phase = (opts[:phase] || 0.0).to_f
      step = tile_w.to_f / segs
      out = []
      k = ((u1 - phase) / step).floor
      loop do
        x = phase + k * step
        k += 1
        next if x <= u1 + EPS
        break if x >= u2 - EPS
        out << [x, drop_at(x, tile_w, amp, phase)]
        break if out.length > 20_000
      end
      pts = [[u1, drop_at(u1, tile_w, amp, phase)]] + out +
            [[u2, drop_at(u2, tile_w, amp, phase)]]
      pts
    end

    # 0 at the pan, `amp` at the crest of the cover tile.
    def self.drop_at(x, tile_w, amp, phase = 0.0)
      t = ((x - phase) % tile_w) / tile_w
      amp * (0.5 + 0.5 * Math.cos(2.0 * Math::PI * t))
    end

    # -------------------------------------------------------- edge pieces

    # Where the real 3D pieces go along an eave or a rake: the centre u of
    # every whole tile that fits inside [u1, u2], on the same global grid as
    # the scallop so a piece always sits under a crest.
    #
    # A partial tile at either end gets NO piece. Half a bird stop poking out
    # past the corner of the roof looks worse than none.
    def self.edge_slots(u1, u2, tile_w, opts = {})
      return [] if tile_w.nil? || tile_w <= EPS || u2 - u1 < tile_w - EPS
      phase = (opts[:phase] || 0.0).to_f
      margin = (opts[:margin] || 0.0).to_f
      lo = u1 + margin
      hi = u2 - margin
      out = []
      k = ((lo - phase) / tile_w).floor
      loop do
        c = phase + (k + 0.5) * tile_w
        k += 1
        next if c - tile_w / 2.0 < lo - EPS
        break if c + tile_w / 2.0 > hi + EPS
        out << c
        break if out.length > 20_000
      end
      out
    end

    # Half a tile of shift on every other course, for slate. Returns the u
    # phase to use for course `index`.
    def self.course_phase(index, tile_w, stagger)
      return 0.0 unless stagger
      index.odd? ? tile_w / 2.0 : 0.0
    end

    # ------------------------------------------------ how wavy is a course

    # The wave is what you see in SILHOUETTE - and only the bottom course has
    # a silhouette, against the sky at the eave. Every course above it is seen
    # against the roof itself, where the field texture already draws the wave.
    #
    # This is the rule the whole file is built on, applied once more:
    # BUILD 3D ONLY WHERE THE SILHOUETTE SHOWS.
    #
    # It is not a style choice, it is arithmetic. On the user's own roof
    # (63ft eave, 4:12, barrel tile) a wavy butt on EVERY course costs about
    # 13,000 faces per plane - roughly 50,000 for the roof, which is the
    # number I was wrong by 16x about on 2026-08-18 before measuring. On the
    # bottom course only it is about 600 per plane, i.e. Vali's ~2,500 for the
    # whole roof - the thing we measured and liked.
    #
    #   scallop_courses = 1   the default: the eave course waves, the rest step
    #   scallop_courses = nil every course waves (what it cost above)
    #   scallop_courses = 0   nothing waves; plain steps, exactly like Vali
    def self.scallop_amp(index, shape, scallop_courses = 1)
      return 0.0 if shape.nil?
      amp = shape[:scallop].to_f
      return amp if scallop_courses.nil?
      index.to_i < scallop_courses.to_i ? amp : 0.0
    end

    # ---------------------------------------------------------- reporting

    # How much geometry a plane is about to cost, BEFORE any of it is built.
    # The builder uses this to decide whether to fall back to a plain step,
    # the same way build_ridge_caps! falls back to one run.
    def self.estimate(plane, shape_name, opts = {})
      s = shape(shape_name)
      return { courses: 0, faces: 0, edge_pieces: 0 } if s.nil?
      res = courses(plane, shape_name, opts)
      segs = [(opts[:segments] || 4).to_i, 2].max
      faces = 0
      sc = opts.key?(:scallop_courses) ? opts[:scallop_courses] : 1
      # `rows` = how many courses from the eave get a 3D step at all. The
      # builder's own policy (RoofManager::TILE_COURSE_ROWS) has to be handed
      # in here too, or the budget stops describing what is actually built.
      rows = opts.key?(:rows) ? opts[:rows] : nil
      res[:courses].each do |c|
        next unless rows.nil? || c[:index] < rows.to_i
        amp = scallop_amp(c[:index], s, sc)
        c[:spans].each do |(a, b)|
          n = amp > EPS ? ((b - a) / s[:tile_w] * segs).ceil : 1
          faces += 2 * n + 3          # top + face strip, plus the two ends
        end
      end
      { courses: res[:courses].length, faces: faces, truncated: res[:truncated],
        edge_pieces: res[:courses].empty? ? 0 :
                     res[:courses].first[:spans].sum { |(a, b)|
                       edge_slots(a, b, s[:tile_w]).length } }
    end
  end
end
