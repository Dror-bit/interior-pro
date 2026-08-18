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
                      label: 'Roman Tile (flat pan)' },
        'slate'  => { tile_w: 12.0, exposure: 8.0,  relief: 0.6, scallop: 0.0,
                      stagger: true,  texture: 'roof_flat_slate.jpg',
                      label: 'Flat Slate Tile' },
        'seam'   => { tile_w: 16.0, exposure: 0.0,  relief: 1.0, scallop: 0.0,
                      stagger: false, texture: 'roof_standing_seam.jpg',
                      label: 'Standing Seam Metal' }
      }
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
      res[:courses].each do |c|
        c[:spans].each do |(a, b)|
          n = s[:scallop] > EPS ? ((b - a) / s[:tile_w] * segs).ceil : 1
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
