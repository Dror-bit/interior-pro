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
    # Over this many pieces the roof keeps the texture alone and says so -
    # the same brake, and the same manners, as MAX_RIDGE_CAP_PIECES.
    #
    # Raised from 4000 on 2026-08-21 for metal tile, which is pressed into
    # courses and so needs a piece per rib PER COURSE rather than one per rib.
    # It is not the cost it looks like: every one of them is an instance of the
    # same ten-face definition, so the model stores one pipe and draws it many
    # times. The brake is here for a runaway, not for a big house.
    # Raised to 16000 on 2026-08-21. At 8000 the brake fired on his own roof
    # the moment Spanish Tile shrank, and a brake that fires in NORMAL use is
    # not a brake - it is a roof with no tiles on it and no visible reason why.
    # It is still here for a runaway; it is no longer here for a big house.
    def self.max_instances
      16_000
    end

    def self.eave_tag
      'InteriorPro_RoofTiles_Edge'
    end

    def self.field_tag
      'InteriorPro_RoofTiles_Field'
    end

    # Where the folds of a SHEET sit across a plane. Unlike edge_slots, which
    # refuses a partial tile at either end, a sheet has to reach the rake: a
    # fold that stops half a pitch short leaves a bare stripe down the edge of
    # the roof. So it runs one past each end and lets the plane outline do the
    # cutting, which it already does for every other piece.
    def self.sheet_slots(u_span, pitch)
      return [] if pitch <= 1.0e-9 || u_span <= 1.0e-9
      n = (u_span / pitch).ceil + 1
      (0..n).map { |k| (k * pitch) - (pitch / 2.0) }
    end

    # Cut one run into courses. `exposure` of 0 means the material is not
    # pressed into courses at all, and the run comes back whole - which is what
    # clay does, and why there is no branch for it anywhere else.
    #
    # The courses are spread EVENLY over the span rather than stepped off the
    # nominal exposure, so a slope never ends in a sliver at the ridge: the
    # step is adjusted by a fraction of an inch instead, which is what a real
    # roofer does with the last course. `overlap` laps each piece over the one
    # above it so the joint is covered, exactly like real pressed metal.
    def self.course_pieces(v1, v2, exposure, overlap = 1.08, min_len = 0.0)
      span = v2 - v1
      return [] if span < min_len || span <= 1.0e-9
      return [[v1, span]] if exposure.nil? || exposure <= 1.0e-9
      n = [(span / exposure.to_f).round, 1].max
      step = span / n.to_f
      (0...n).map do |k|
        a = v1 + (k * step)
        [a, [step * overlap, v2 - a].min]
      end
    end

    # The top of the stretch of roof that contains height `v_at`, at across-
    # slope position `u`. nil means there is no roof there at that height -
    # which is a real answer, not a failure: it is how a tile finds out that
    # one of its edges has walked off a hip or into a valley.
    def self.span_top_at(poly, u, v_at)
      InteriorPro::RoofTileMath.v_spans_at(poly, u, 0.0).each do |(lo, hi)|
        return hi if v_at >= lo - 1.0e-6 && v_at < hi + 1.0e-6
      end
      nil
    end

    # The valley lines, turned into clip lines in ONE plane's own u/v.
    #
    # Each entry that comes back is [a', b', seg]: the line to clip against
    # (already pushed `setback` INTO the plane, so clip_left keeps the tile
    # side and the cleared strip is exactly one channel edge wide) and the
    # original segment, used only to ask "is this tile anywhere near it".
    # A line whose endpoints do not lie on this plane belongs to some other
    # valley and is dropped.
    def self.flat_valley_clips(pu, valleys, setback)
      return [] if valleys.nil? || valleys.empty? || setback <= 1.0e-9
      pc = [pu[:poly].sum { |p| p[0] } / pu[:poly].length,
            pu[:poly].sum { |p| p[1] } / pu[:poly].length]
      out = []
      valleys.each do |(ka, za, kb, zb, _sides)|
        a2 = world_to_uv(pu, [ka[0], ka[1], za])
        b2 = world_to_uv(pu, [kb[0], kb[1], zb])
        next if a2.nil? || b2.nil?
        # orient a -> b so the plane's inside is on the LEFT, then push the
        # line left by the setback - clip_left keeps the left side.
        cr = ((b2[0] - a2[0]) * (pc[1] - a2[1])) -
             ((b2[1] - a2[1]) * (pc[0] - a2[0]))
        a2, b2 = b2, a2 if cr.negative?
        dx = b2[0] - a2[0]
        dy = b2[1] - a2[1]
        ln = Math.hypot(dx, dy)
        next if ln < 1.0
        nx = -dy / ln
        ny = dx / ln
        out << [[a2[0] + (nx * setback), a2[1] + (ny * setback)],
                [b2[0] + (nx * setback), b2[1] + (ny * setback)], [a2, b2]]
      end
      out
    end

    # WHERE ANOTHER ROOF PLANE PASSES OVERHEAD, THE TILES STOP (2026-08-21c).
    #
    # drop_covered_planes handles a face that is buried WHOLE - the hip case,
    # where the shell's valley intersection splits the buried tongue into its
    # own face. A GABLE junction makes no valley, so nothing splits: the main
    # slope stays ONE face whose far end runs in under the wing's roof, its
    # centre sits in daylight, and the whole face - buried tongue included -
    # was tiled. Seen through the wing's open gable end: "אם אני משנה את הגג
    # לגיבל היא חוזרת".
    #
    # A face cannot be half-erased, but tiles can be cut - and the boundary
    # of the buried region is simply where the two PLANES intersect in 3D.
    # For each plane Q that might cover P, this returns Q's plan footprint
    # plus that intersection line mapped into P's own u/v; the tile loop
    # clips any tile whose middle lies under Q's footprint against it,
    # keeping the daylight side. Outside Q's footprint nothing changes, so
    # the slope's open stretches keep every tile they had.
    def self.cover_clips(pl, pu, planes)
      out = []
      np = pl[:n]
      (planes || []).each do |q|
        next if q.equal?(pl)
        nq = q[:n]
        next if nq[2].abs < 0.2
        qplan = q[:points].map { |p| [p[0], p[1]] }
        d = [(np[1] * nq[2]) - (np[2] * nq[1]),
             (np[2] * nq[0]) - (np[0] * nq[2]),
             (np[0] * nq[1]) - (np[1] * nq[0])]
        dl = Math.sqrt((d[0]**2) + (d[1]**2) + (d[2]**2))
        if dl < 1.0e-6
          # parallel planes never meet: a tile under Q is either wholly in
          # daylight or wholly buried - the tile loop decides by height.
          out << { plan: qplan, q: q, line: nil }
          next
        end
        d = d.map { |x| x / dl }
        p0 = pl[:points][0]
        q0 = q[:points][0]
        o = pu[:origin]
        l0 = solve3(np, (np[0] * p0[0]) + (np[1] * p0[1]) + (np[2] * p0[2]),
                    nq, (nq[0] * q0[0]) + (nq[1] * q0[1]) + (nq[2] * q0[2]),
                    d, (d[0] * o[0]) + (d[1] * o[1]) + (d[2] * o[2]))
        next if l0.nil?
        a2 = world_to_uv(pu, l0)
        b2 = world_to_uv(pu, [l0[0] + (d[0] * 100.0), l0[1] + (d[1] * 100.0),
                              l0[2] + (d[2] * 100.0)])
        next if a2.nil? || b2.nil?
        # orient so clip_left keeps the DAYLIGHT side: probe a step to the
        # left of the line, lift it back to world on P, and ask which plane
        # is higher there.
        dx = b2[0] - a2[0]
        dy = b2[1] - a2[1]
        ln = Math.hypot(dx, dy)
        next if ln < 1.0e-6
        m = [((a2[0] + b2[0]) / 2.0) - (dy / ln * 2.0),
             ((a2[1] + b2[1]) / 2.0) + (dx / ln * 2.0)]
        w = InteriorPro::RoofTileMath.unproject(m, pu[:origin], pu[:u], pu[:v])
        zq = z_on_plane(q, w[0], w[1])
        a2, b2 = b2, a2 if !zq.nil? && zq > w[2] + 1.0e-6
        out << { plan: qplan, q: q, line: [a2, b2] }
      end
      out
    end

    # Cramer's rule for the one 3x3 system cover_clips needs.
    def self.solve3(r1, b1, r2, b2, r3, b3)
      det = (r1[0] * ((r2[1] * r3[2]) - (r2[2] * r3[1]))) -
            (r1[1] * ((r2[0] * r3[2]) - (r2[2] * r3[0]))) +
            (r1[2] * ((r2[0] * r3[1]) - (r2[1] * r3[0])))
      return nil if det.abs < 1.0e-9
      dx = (b1 * ((r2[1] * r3[2]) - (r2[2] * r3[1]))) -
           (r1[1] * ((b2 * r3[2]) - (r2[2] * b3))) +
           (r1[2] * ((b2 * r3[1]) - (r2[1] * b3)))
      dy = (r1[0] * ((b2 * r3[2]) - (r2[2] * b3))) -
           (b1 * ((r2[0] * r3[2]) - (r2[2] * r3[0]))) +
           (r1[2] * ((r2[0] * b3) - (b2 * r3[0])))
      dz = (r1[0] * ((r2[1] * b3) - (b2 * r3[1]))) -
           (r1[1] * ((r2[0] * b3) - (b2 * r3[0]))) +
           (b1 * ((r2[0] * r3[1]) - (r2[1] * r3[0])))
      [dx / det, dy / det, dz / det]
    end

    # A world point in one plane's u/v - or nil if it does not LIE on that
    # plane, which is how a valley line finds the two planes it belongs to.
    def self.world_to_uv(pu, w)
      o = pu[:origin]
      d = [w[0] - o[0], w[1] - o[1], w[2] - o[2]]
      off = (d[0] * pu[:n][0]) + (d[1] * pu[:n][1]) + (d[2] * pu[:n][2])
      return nil if off.abs > 0.75
      [(d[0] * pu[:u][0]) + (d[1] * pu[:u][1]) + (d[2] * pu[:u][2]),
       (d[0] * pu[:v][0]) + (d[1] * pu[:v][1]) + (d[2] * pu[:v][2])]
    end

    # THE FLAT TILE LAYS ITSELF OUT COURSE BY COURSE (2026-08-21c).
    #
    # Every other layout here walks the COLUMNS on the outside and cuts each
    # one into courses on the inside. That cannot stagger: the shift is half a
    # tile ACROSS the slope and it depends on which COURSE you are in, so the
    # course has to be the outer loop. The user asked for it after seeing the
    # straight version - "אני רוצה שזה יהיה סטאגרן" - and course_phase, which
    # has been sitting in RoofTileMath unused since the texture grid was
    # written, is exactly the number it needs.
    #
    # Two other things fall out of walking courses first, and both were real
    # defects in the straight version, found by rendering the actual output:
    #
    #   COURSE LINES STAY STRAIGHT. course_pieces spreads its courses EVENLY
    #   over whatever span it is handed, which is right for a pipe. Here every
    #   column asked the outline for its own span, and next to a hip that span
    #   shortens column by column - so each column divided a DIFFERENT length,
    #   the step came out slightly different in each, and the course lines
    #   broke into a staircase. Now the courses ARE the grid: 0, E, 2E ... from
    #   the plane's eave, the same for every column on the plane.
    #
    #   A TILE AT A HIP IS CUT, not dropped. The course band is clipped to the
    #   span the outline gives at that column, which is what a roofer does with
    #   a tile at a hip - and it is why the last piece in a column is short.
    #
    # Returns exactly what run_slots returns, so place_runs! cannot tell which
    # of the two built the list.
    def self.flat_slots(planes, shape_name, opts = {})
      s = InteriorPro::RoofTileMath.shape(shape_name)
      return [] if s.nil?
      pitch = (opts[:pitch] || InteriorPro::RoofTileParts.run_pitch(s)).to_f
      exposure = (opts[:exposure] || s[:exposure]).to_f
      return [] if pitch <= 1.0e-9 || exposure <= 1.0e-9
      min_len = (opts[:min_len] || min_run_len).to_f
      # CUT AT THE EAVE, NOT HUNG OVER IT (2026-08-21c, second pass).
      # eave_overhang is 1.25" and every other material uses it, because a clay
      # pipe hanging past the edge reads as a real tile. A flat tile does not:
      # each one is a separate plate with a joint down each side, so 1.25" of
      # them past the deck came out as a row of loose teeth with daylight
      # between them and nothing underneath - "תראה שהטייל לא נגמר באיב, הוא
      # צריך להיחתך שמה". Zero here means the bottom course ends exactly on
      # the eave line. The default is stated, not inherited, so nothing else
      # moved.
      overhang = (opts[:overhang] || 0.0).to_f
      setback = if opts.key?(:setback)
                  opts[:setback].to_f
                else
                  InteriorPro::RoofTileParts.ridge_setback(s)
                end
      stagger = s[:stagger] == true
      # HALF THE TILE AS IT IS DRAWN - the number the span is measured with
      # below. flat_tile builds the plate one joint in from the pitch on each
      # side, so this is its real half width and not half the spacing.
      half_w = (pitch / 2.0) - InteriorPro::RoofTileParts.flat_joint
      out = []
      (planes || []).each do |pl|
        pu = InteriorPro::RoofTileMath.plane_uv(pl[:points], pl[:n])
        next if pu.nil? || pu[:flat]
        next if pu[:u_span].to_f < pitch
        # NOT `top`: the inner loop below has its own `top` for the tile's own
        # cut, and a block shares this scope - naming both the same silently
        # rewrote the loop bound with the first tile's cut and the plane came
        # out with a single course on it.
        v_max = pu[:v_span].to_f
        # THE VALLEY PULL-BACK (2026-08-21c, fourth pass). The tiles were cut
        # exactly ON the valley line from both sides, and the bare meeting
        # read as a ragged seam - "אני לא מבין למה אתה לא מסדר את הפינות
        # במפגש שלהם בוואלי". Now the valley carries the same flat channel
        # the metal roof has, and each tile stops HALF A CHANNEL short of the
        # line, so it butts the channel's edge exactly - same idea as the
        # seam's ribs, done by moving each tile's own clip line instead of
        # its foot, because a valley cuts these tiles on their SIDE.
        #
        # From this plane's side of the roof a valley is just one more
        # outline edge, and a hip is too - only roof_manager can tell them
        # apart, which is why the lines arrive from outside (opts[:valleys],
        # from ridge_lines(valleys: true)) instead of being guessed here.
        vclips = flat_valley_clips(pu, opts[:valleys],
                                   InteriorPro::RoofTileParts.cap_w(s) / 2.0)
        cclips = cover_clips(pl, pu, planes)
        # THE DORMERS STANDING ON THIS PLANE (2026-09-03), in its own u/v.
        # The run materials subtract them from the run's span; a plate is not
        # a span, so it is clipped instead - see clip_outside_poly.
        holes_uv = (pl[:holes] || []).map do |h|
          h.map do |q|
            pr = InteriorPro::RoofTileMath.project(q, pu[:origin], pu[:u], pu[:v])
            [pr[0], pr[1]]
          end
        end
        # The columns are the same list every course; only the phase moves.
        cols = sheet_slots(pu[:u_span].to_f, pitch)
        k = 0
        while (k * exposure) < v_max
          phase = InteriorPro::RoofTileMath.course_phase(k, pitch, stagger)
          a = k * exposure
          b = (k + 1) * exposure
          cols.each do |c0|
            c = c0 + phase
            # THE OUTLINE IS THE ONLY THING THAT CUTS (2026-08-21c, fifth
            # pass, and this line is where two rounds of valley trouble
            # lived). The tile used to be truncated FIRST at the height
            # v_spans_at gave for its CENTRE line - a HORIZONTAL cut - and
            # only then clipped on the outline. Against a diagonal the
            # diagonal never got to cut what the horizontal cut had already
            # thrown away, and the valley line wore a staircase of bare
            # wedges, up to half a tile wide. Measured with plain Ruby on an
            # L-roof: 6.2" of bare deck at the worst point; 0.0 after this.
            #
            # So the tile is its FULL course rectangle, and the outline cuts
            # it - horizontal at a ridge, diagonal at a hip or a valley,
            # vertical at a rake, all the same clip.
            rect = [[c - half_w, a], [c + half_w, a],
                    [c + half_w, b], [c - half_w, b]]
            poly = InteriorPro::RoofTileMath.clip_to_poly(rect, pu[:poly])
            next if poly.length < 3
            # ...and pulled back off any valley when the channel is wanted -
            # see vclips above. The cut line is INFINITE, so only a tile
            # actually near the segment is clipped by it.
            vclips.each do |(va2, vb2, seg)|
              cx = poly.sum { |p| p[0] } / poly.length
              cy = poly.sum { |p| p[1] } / poly.length
              next if InteriorPro::RoofTileMath.seg_dist(seg[0], seg[1],
                                                         [cx, cy]) > pitch + exposure
              poly = InteriorPro::RoofTileMath.clean_poly(
                InteriorPro::RoofTileMath.clip_left(poly, va2, vb2)
              )
              break if poly.length < 3
            end
            next if poly.length < 3
            # ...and cut where another roof plane passes overhead - see
            # cover_clips. The gate is ANY buried point, not the middle: a
            # tile straddling the covering plane's edge with only one corner
            # in the dark was slipping through on the centre test, and that
            # corner is the strip right at the open gable wall - exactly
            # where the user is looking.
            cclips.each do |cc|
              buried = poly.any? do |q2|
                w = InteriorPro::RoofTileMath.unproject(q2, pu[:origin],
                                                        pu[:u], pu[:v])
                next false unless InteriorPro::RoofTileMath.poly_contains?(
                  cc[:plan], [w[0], w[1]]
                )
                zq = z_on_plane(cc[:q], w[0], w[1])
                !zq.nil? && zq > w[2] + 0.05
              end
              next unless buried
              if cc[:line].nil?
                poly = []
              else
                poly = InteriorPro::RoofTileMath.clean_poly(
                  InteriorPro::RoofTileMath.clip_left(poly, cc[:line][0],
                                                      cc[:line][1])
                )
              end
              break if poly.length < 3
            end
            next if poly.length < 3
            # ...and cut out of any dormer standing on this plane. A tile
            # wholly inside one is gone; one on its edge keeps only the part
            # outside it, so the field STOPS at the dormer wall instead of
            # running under it.
            holes_uv.each do |h|
              poly = InteriorPro::RoofTileMath.clip_outside_poly(poly, h)
              break if poly.length < 3
            end
            next if poly.length < 3
            cut_area = InteriorPro::RoofTileMath.poly_area(poly).abs
            # A dropped sliver is a notch of bare deck ON the line, and the
            # line is exactly where the user is looking. clean_poly already
            # refuses true degenerates.
            next if cut_area < 1.0
            whole = cut_area >= (2.0 * half_w * (b - a)) - 0.01
            # A CUT tile carries its footprint and is built where it lies as
            # the same wedge, clipped - see build_flat_cut!.
            unless whole
              out << { origin: InteriorPro::RoofTileMath.unproject(
                         [c, a], pu[:origin], pu[:u], pu[:v]
                       ),
                       u: pu[:u], v: pu[:v], n: pu[:n], length: b - a,
                       cut: poly, pu_origin: pu[:origin], v0: a,
                       # the COURSE window, so the cut wedge keeps exactly
                       # its neighbours' slope
                       cv0: a, clen: exposure }
              next
            end
            o = InteriorPro::RoofTileMath.unproject([c, a - overhang],
                                                    pu[:origin], pu[:u], pu[:v])
            out << { origin: o, u: pu[:u], v: pu[:v], n: pu[:n],
                     length: (b - a) + overhang }
          end
          k += 1
          break if k > 10_000
        end
      end
      out
    end

    # THE RIBS FACE EACH OTHER ACROSS THE RIDGE (2026-08-21).
    #
    # Every plane laid its ribs out from its OWN left edge, so the two slopes
    # of one ridge arrived at it on unrelated spacings and the ribs did not
    # meet - "אני רוצה שהם יהיו אחד מול השני". A real standing seam roof is one
    # panel folded over the ridge, so the two sides ARE the same line.
    #
    # This is a PHASE, not a new layout: it slides the existing grid so that
    # every rib lands on one grid in WORLD space, measured along the plane's
    # own across-slope direction from the world origin. Two opposite slopes
    # have anti-parallel u, so that is the same set of lines for both and they
    # meet exactly. A hip plane runs across the other axis and keeps its own
    # grid - there is nothing over there for it to line up with.
    #
    # `u_off` is where the piece sits inside its slot (see run_slots), so the
    # grid is measured on the RIB, not on the slot's origin.
    #
    # It also stops asking edge_slots for a WHOLE CELL. edge_slots refuses a
    # partial tile at either end, which is right for a bird stop but wrong
    # here: the two slopes reach the rake at different phases, so one of them
    # threw its last rib away and the ridge lost a pair. A rib is 2" wide -
    # if its line crosses the plane, the rib is there.
    #
    # Returns SLOT positions (where an instance's origin goes), so the caller
    # is unchanged; the rib itself lands at slot + u_off.
    def self.seam_slots(u_span, pitch, u_off, d0)
      return [] if pitch <= 1.0e-9 || u_span <= 1.0e-9
      out = []
      # One line past each end, and let the plane OUTLINE do the cutting -
      # the same manners as sheet_slots. Stopping the loop at the u_span
      # instead put a rib on the rake of one slope and not of the other,
      # purely because their origins sit at opposite corners.
      #
      # A line landing exactly ON the u range is dropped at BOTH ends. The
      # scanline's half-open rule already drops it at the top end only, and
      # that one-sided rule is what put a rib on one slope's rake and not on
      # the other's - the two slopes read the same edge from opposite corners.
      r = ((-d0) % pitch) - pitch
      while r <= u_span + pitch + 1.0e-9
        out << (r - u_off) if r > 1.0e-6 && r < u_span - 1.0e-6
        r += pitch
        break if out.length > 20_000
      end
      out
    end

    # A run shorter than this is a sliver at the tip of a hip. It gets nothing:
    # half a pipe poking out of a corner looks worse than a bare stretch of
    # texture, which is the same call edge_slots already makes across the eave.
    # Dropped from 6" to 3" on 2026-08-21, when the Spanish Tile module shrank
    # to 7": a course is now about seven inches long, and a 6" floor threw away
    # every short course at a hip.
    def self.min_run_len
      3.0
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
    # THE OUTLINE IS THE ROOF, EACH INNER LOOP IS A DORMER (2026-09-02B).
    # face_points hands back the HOLE vertices mixed in with the outline's -
    # the landmine this project has hit before - so a slope with a dormer on
    # it came out as a polygon that is not the roof at all. Now the outline
    # comes off the outer loop and the holes travel with the plane, so a run
    # crossing one stops instead of shooting through the dormer
    # ("תיראה שמבתוכו הוא לא חתך את הפאנלים").
    def self.planes_from_faces(faces)
      out = []
      (faces || []).each do |f|
        pts = face_outline(f)
        next if pts.nil? || pts.length < 3
        nrm = face_normal(f)
        next if nrm.nil?
        fr = InteriorPro::RoofTileMath.plane_frame(nrm)
        next if fr.nil? || fr[:flat]
        out << { points: pts, normal: fr[:n], u: fr[:u], v: fr[:v], n: fr[:n],
                 holes: face_holes(f) }
      end
      out
    end

    def self.face_outline(f)
      if f.respond_to?(:outer_loop) && f.outer_loop
        return to_xyz(f.outer_loop.vertices.map(&:position))
      end
      face_points(f)
    rescue StandardError
      face_points(f)
    end

    def self.face_holes(f)
      return [] unless f.respond_to?(:loops)
      f.loops.reject(&:outer?)
       .map { |lp| to_xyz(lp.vertices.map(&:position)) }
       .compact.select { |h| h.length >= 3 }
    rescue StandardError
      []
    end

    def self.to_xyz(pts)
      pts.map { |p| p.respond_to?(:x) ? [p.x.to_f, p.y.to_f, p.z.to_f] : p.map(&:to_f) }
    rescue StandardError
      nil
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

    # THE RUNS - the long half pipes, ridge to eave (2026-08-20).
    #
    # One entry per pipe: where it starts, the plane's frame, and HOW LONG it
    # is. The length is the only new number, and it is the reason the whole
    # roof costs about ten unique faces - roof_tile_parts models the pipe one
    # inch long and place_runs! stretches that one definition to each length.
    #
    # THE SHAPE OF A PLANE IS NOT A RECTANGLE, and that is the real work here.
    # A hip face is a triangle, a plane with a dormer has a bite out of it. So
    # every pipe asks the outline directly: at across-slope position u = c,
    # which stretches of v are inside? RoofTileMath.v_spans_at is the same
    # scanline the courses use, turned 90 degrees, so a hip cuts the runs short
    # for free and a dormer splits one run into two with no special case.
    #
    # The pipes are spaced by edge_slots, the same spacing the eave course
    # uses, so a run and an eave piece can never disagree about the pitch.
    #
    # Returns [{ origin: [x, y, z], u:, v:, n:, length: }, ...].
    # A PLANE HIDING UNDER ANOTHER ROOF GETS NO TILES (2026-08-21c).
    #
    # Where one wing's roof runs in under another - the shell intersects on
    # the valleys, so the buried continuation is its own face - that face has
    # always been built and painted, and the flat texture kept it invisible.
    # Real 3D tiles do not stay invisible: they filled the hidden strip and
    # poked out through the covering roof, in plain view through the open
    # gable end - "הגג ממשיך מתחת לגג השני ולא נחתך".
    #
    # A face is covered when its own middle sits in PLAN inside another
    # plane's outline AND that plane passes above it there. The shell's
    # intersection is what splits faces on the meeting lines, so a covered
    # face is covered as a WHOLE - one point answers for all of it.
    def self.drop_covered_planes(planes)
      list = planes || []
      return list if list.length < 2
      # SAMPLED, NOT JUST THE CENTRE (2026-08-21c, gable pass). Two planes
      # that CROSS - each one's far lobe under the other - can both have
      # their centres in the buried lobe, and the centre-only test threw
      # both away and left a bare roof. A face goes only when the centre AND
      # the midpoint toward every corner are all covered: that is a face
      # with no daylight on it anywhere that matters. A partly-covered face
      # stays, and cover_clips trims its tiles at the meeting line instead.
      list.reject do |pl|
        pts = pl[:points]
        cx = pts.sum { |p| p[0] } / pts.length
        cy = pts.sum { |p| p[1] } / pts.length
        cz = pts.sum { |p| p[2] } / pts.length
        samples = [[cx, cy, cz]] + pts.map do |p|
          [(cx + p[0]) / 2.0, (cy + p[1]) / 2.0, (cz + p[2]) / 2.0]
        end
        samples.all? do |(sx, sy, sz)|
          list.any? do |q|
            next false if q.equal?(pl)
            next false unless InteriorPro::RoofTileMath.poly_contains?(
              q[:points].map { |p| [p[0], p[1]] }, [sx, sy]
            )
            zq = z_on_plane(q, sx, sy)
            !zq.nil? && zq > sz + 0.1
          end
        end
      end
    end

    def self.run_slots(planes, shape_name, opts = {})
      return [] unless InteriorPro::RoofTileMath.runs?(shape_name)
      planes = drop_covered_planes(planes)
      # The flat tile has its own layout - courses on the outside so they can
      # stagger. Everything below this line is untouched by it.
      if InteriorPro::RoofTileMath.respond_to?(:run_flat?) &&
         InteriorPro::RoofTileMath.run_flat?(shape_name)
        return flat_slots(planes, shape_name, opts)
      end
      s = InteriorPro::RoofTileMath.shape(shape_name)
      # The RUN pitch, not the material's tile pitch. The pipe is allowed to be
      # finer than the tile the texture draws, and it is (2026-08-21): six inch
      # pipes on a 13" Roman tile, spaced by their own width plus a narrow pan.
      # If his own tile is on disk, ITS pitch wins - measured off the copies in
      # his file, never assumed. Assuming it is what put a 1.5" GAP between the
      # pipes where his overlap by 2.36".
      asset = opts[:asset]
      pitch = (opts[:pitch] || (asset && asset[:pitch]) ||
               InteriorPro::RoofTileParts.run_pitch(s)).to_f
      return [] if pitch <= 1.0e-9
      min_len = (opts[:min_len] || min_run_len).to_f
      overhang = if opts.key?(:overhang)
                   opts[:overhang].to_f
                 else
                   InteriorPro::RoofTileParts.eave_overhang
                 end
      margin = (opts[:margin] || 0.0).to_f
      # How far short of the ridge or hip a run stops - see the comment where
      # it is applied. Pass 0.0 to get the old ridge-to-eave run back.
      setback = if opts.key?(:setback)
                  opts[:setback].to_f
                else
                  InteriorPro::RoofTileParts.ridge_setback(s)
                end
      # Clay is one unbroken pipe from ridge to eave. Pressed metal is a row of
      # short ones with a step between them - that is the whole visible
      # difference between the user's two references, and it is one flag.
      exposure = if InteriorPro::RoofTileMath.run_courses?(shape_name)
                   (opts[:exposure] || s[:exposure]).to_f
                 else
                   0.0
                 end
      # A pipe course laps over the one below to hide the joint. A SHEET does
      # not: it carries its own step, so the pieces butt end to end and the
      # nose of one sits on the field of the next.
      overlap = (opts[:course_overlap] ||
                 (InteriorPro::RoofTileMath.run_courses?(shape_name) ? 1.0 : 1.08)).to_f
      # MEASURE THE PIECE WHERE IT IS DRAWN, NOT WHERE ITS ORIGIN IS
      # (2026-08-21).
      #
      # A slot's u is where the instance's ORIGIN lands. The profile is free to
      # sit somewhere else inside that frame, and the seam rib does:
      # RoofTileParts.seam_profile centres it on run_pitch/2 - half a pitch to
      # the +u side - because the deck underneath it already is the pan.
      # The length, though, was still cut off the outline at the ORIGIN's u, so
      # on a hip every rib was measured 14" away from where it was drawn.
      # Measured on the user's own roof: 6 ribs 10.8" SHORT of the hip on one
      # side, 6 ribs 9.5" PAST it on the other, the middle of the roof exact.
      #
      # Only the seam has an offset profile, so only the seam gets an offset
      # here - every other material still measures on its own centre line, the
      # same number it always did.
      u_off = if InteriorPro::RoofTileMath.seam?(shape_name)
                InteriorPro::RoofTileParts.run_pitch(s) / 2.0
              else
                0.0
              end
      out = []
      (planes || []).each do |pl|
        pu = InteriorPro::RoofTileMath.plane_uv(pl[:points], pl[:n])
        next if pu.nil? || pu[:flat]
        next if pu[:u_span].to_f < pitch
        slots_u = if InteriorPro::RoofTileMath.run_courses?(shape_name)
                    sheet_slots(pu[:u_span].to_f, pitch)
                  elsif InteriorPro::RoofTileMath.seam?(shape_name)
                    # Only the seam shares a grid between planes; every other
                    # material keeps the per-plane layout it always had.
                    seam_slots(pu[:u_span].to_f, pitch, u_off,
                               InteriorPro::RoofTileMath.vdot(pu[:origin],
                                                              pu[:u]))
                  else
                    InteriorPro::RoofTileMath.edge_slots(0.0, pu[:u_span].to_f,
                                                         pitch, margin: margin)
                  end
        # the dormers standing on THIS plane, in its own u/v
        holes_uv = (pl[:holes] || []).map do |h|
          h.map { |p| InteriorPro::RoofTileMath.project(p, pu[:origin], pu[:u], pu[:v]) }
        end
        slots_u.each do |c|
          uu = c + u_off
          spans = InteriorPro::RoofTileMath.v_spans_at(pu[:poly], uu, min_len)
          cuts = []
          unless holes_uv.empty?
            cuts = holes_uv.flat_map do |h|
              InteriorPro::RoofTileMath.v_spans_at(h, uu, 0.0)
            end
            spans = InteriorPro::RoofTileMath.spans_minus(spans, cuts, min_len)
          end
          spans.each do |(v1, vtop)|
            # A DORMER IS NOT A RIDGE (2026-09-02B). The setback below
            # exists to hide a cut UNDER the ridge cap or the valley
            # channel. A dormer has neither: the panel runs up to it and
            # the dormer's own wall covers the joint, which is the user's
            # standing law - boards MEET, they never stop short and they
            # never run inside each other. Pulling back here left a bare
            # patch of deck all round the dormer: "הוא נחתך יותר מדי".
            top_at_dormer = cuts.any? { |(clo, _hi)| (clo - vtop).abs < 0.01 }
            bot_at_dormer = cuts.any? { |(_lo, chi)| (chi - v1).abs < 0.01 }
            # STOP SHORT OF THE RIDGE AND THE HIP (2026-08-21).
            #
            # v_spans_at cuts the run's CENTRE LINE at the outline, but a tile
            # has width - so on a diagonal hip the far side of every roll stuck
            # out past the hip line and the corner came out as a row of broken
            # half tiles. "הפינה צריכה להיות נקייה."
            #
            # Pulling every span's top back by the cap's half width lands the
            # cut under the cap, which is exactly the piece that is there to
            # cover it. The eave end is untouched - it still hangs over.
            v2 = vtop - (top_at_dormer ? 0.0 : setback)
            next if (v2 - v1) < min_len
            course_pieces(v1, v2, exposure, overlap, min_len).each do |(a, len)|
              v0 = a
              plen = len
              # Only a piece that really starts at the eave hangs past it. One
              # cut short by a hip or a dormer, or a course higher up the
              # slope, starts in mid-slope and must not grow a nose out of
              # nothing.
              #
              # EXCEPT THE SEAM (2026-08-21, second pass): its ribs ran down
              # through the eave bar - "הברזלים צריכים לעצור לפני המסגרת".
              # The bar sits ON the deck at the very edge, one run_height
              # deep, so the rib is trimmed to BUTT its inner face instead of
              # hanging over. Every other material still hangs exactly as it
              # did.
              if a < 0.5
                if InteriorPro::RoofTileMath.seam?(shape_name)
                  bar = InteriorPro::RoofTileParts.run_height(s)
                  v0 = a + bar
                  plen -= bar
                  next if plen < min_len
                else
                  v0 = a - overhang
                  plen += overhang
                end
              elsif InteriorPro::RoofTileMath.seam?(shape_name)
                # A rib that STARTS mid-slope was cut by a VALLEY. Its foot
                # hides under the valley channel exactly the way its head
                # hides under the ridge cap - the same stated setback, from
                # the other end. "זה לא מכסה זה יותר מוליך מים" - the channel
                # lies flat, so a rib touching it would sit ON it; stopping
                # short keeps the water path clear.
                # A DORMER is the exception: nothing lies flat there, so the
                # rib runs right up to it (see top_at_dormer above).
                step = (bot_at_dormer && (a - v1).abs < 0.01) ? 0.0 : setback
                if step.positive?
                  v0 = a + step
                  plen -= step
                  next if plen < min_len
                end
              end
              o = InteriorPro::RoofTileMath.unproject([c, v0], pu[:origin],
                                                      pu[:u], pu[:v])
              out << { origin: o, u: pu[:u], v: pu[:v], n: pu[:n], length: plen }
            end
          end
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

    # The field of long pipes. Same manners as place_eaves!: one definition,
    # one instance per run, a tag on each, and the brake rather than a flood.
    def self.place_runs!(grp, planes, shape_name, opts = {})
      return 0 if grp.nil?
      model0 = opts[:model] || Sketchup.active_model
      opts = opts.merge(asset: InteriorPro::RoofTileParts.asset_tile(model0, shape_name)) unless opts.key?(:asset)
      slots = run_slots(planes, shape_name, opts)
      return 0 if slots.empty?
      cap = (opts[:max] || max_instances).to_i
      if slots.length > cap
        puts "[RoofTiles] #{slots.length} runs is over the #{cap} budget " \
             '- leaving the field with its texture only'
        return 0
      end
      model = opts[:model] || Sketchup.active_model
      # HIS tile if the file is there, the generated one if it is not.
      asset = opts.key?(:asset) ? opts[:asset] : InteriorPro::RoofTileParts.asset_tile(model, shape_name)
      # run_flat is asked FIRST: a flat tile is also pressed into courses, so
      # it would otherwise fall into the sheet branch and come out as a folded
      # metal panel.
      defn = if asset
               asset[:defn]
             elsif InteriorPro::RoofTileMath.respond_to?(:run_flat?) &&
                   InteriorPro::RoofTileMath.run_flat?(shape_name)
               InteriorPro::RoofTileParts.flat_tile(model, shape_name)
             elsif InteriorPro::RoofTileMath.run_courses?(shape_name)
               InteriorPro::RoofTileParts.sheet(model, shape_name)
             else
               InteriorPro::RoofTileParts.run(model, shape_name)
             end
      if defn.nil?
        puts "[RoofTiles] no run definition for #{shape_name}"
        return 0
      end
      tag = opts[:tag] || field_tag
      mat = opts[:material]
      made = 0
      cut = 0
      slots.each do |s|
        # A tile that a hip or a valley cut is not the shared definition any
        # more - it is built where it lies. See build_cut_tile!.
        if s[:cut]
          cut += 1 if build_cut_tile!(grp, s, shape_name, mat, tag)
          next
        end
        tr = asset ? asset_transform_for(s, asset) : run_transform_for(s)
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
      puts "[RoofTiles] runs: #{made} instances of #{defn.name}" \
           "#{cut.positive? ? " + #{cut} cut on a hip or valley" : ''}"
      made + cut
    end

    # RE-LAY THE FIELD ON ONE ROOF (2026-09-02B). A dormer just cut into a
    # slope - or just lifted off it - changes the shape the runs have to fit,
    # and the runs were laid long before that happened. This throws the old
    # ones away and lays them again off the faces as they are NOW: the same
    # thing a full rebuild does, but for this one roof and without touching
    # anything else standing on it.
    # WHICH PIECES ARE THE FIELD (2026-09-03).
    #
    # This threw away every instance whose DEFINITION NAME starts with
    # IP_TileRun - which is only the generated pipe. A flat tile's definition
    # is IP_TileFlatWedge, pressed metal is IP_TileSheet, and the user's own
    # Spanish tile is a component out of HIS file with a name of its own. On
    # those three nothing was erased at all: the new field was laid on top of
    # the old one, and both things he reported on 2026-09-03 follow from that
    # single line - twice the tile round a gable, and no hole where the dormer
    # stands, because the tiles covering it are the OLD ones, laid before the
    # dormer existed ("שלא נוצר חור ברעפים בספניש ובטיל המרובעים... הספאניש
    # מכפיל את כמות הטיל מסביב לגמלון").
    #
    # Every generated piece stamps its own `part` on its DEFINITION, so ask
    # that instead of the name. The asset tile carries no stamp - it is his
    # file, not ours - so it is matched by identity.
    #
    # A METHOD, not a constant: a list that grows has to survive reload!.
    def self.field_parts
      %w[tile_run tile_sheet tile_flat]
    end

    def self.field_part?(part)
      field_parts.include?(part.to_s)
    end

    # THE EAVE BAR AND THE RIDGE CAP ARE NOT THE FIELD. The bar's definition
    # is stamped 'tile_edge' and the cap is a group, and relay_runs! does not
    # lay either of them again - erasing them would leave the roof without the
    # frame the panels die into.
    def self.field_piece?(defn, asset = nil)
      return false if defn.nil?
      return true if asset && asset[:defn] && defn.equal?(asset[:defn])
      return true if field_part?(defn.get_attribute('InteriorPro', 'part'))
      defn.name.to_s.start_with?('IP_TileRun')
    rescue StandardError
      false
    end

    def self.relay_runs!(roof, opts = {})
      return 0 if roof.nil? || !roof.respond_to?(:entities)
      name = (opts[:shape] ||
              roof.get_attribute('InteriorPro', 'roof_material')).to_s
      return 0 if name.empty?
      return 0 unless InteriorPro::RoofTileMath.runs?(name)
      ents = roof.entities
      faces = ents.grep(Sketchup::Face).select { |f| f.normal.z > 0.2 }
      return 0 if faces.empty?
      mat = opts[:material] || faces.max_by(&:area).material
      asset = InteriorPro::RoofTileParts.asset_tile(
        opts[:model] || Sketchup.active_model, name
      )
      old = ents.grep(Sketchup::ComponentInstance).select do |i|
        field_piece?(i.definition, asset)
      end
      old += ents.grep(Sketchup::Group).select do |g|
        g.get_attribute('InteriorPro', 'part').to_s == 'tile_flat_cut'
      end
      ents.erase_entities(old) unless old.empty?
      faces = ents.grep(Sketchup::Face).select { |f| f.normal.z > 0.2 }
      place_runs!(roof, planes_from_faces(faces), name,
                  model: opts[:model], material: mat)
    rescue StandardError => e
      puts "[RoofTiles] relay_runs!: #{e.message}"
      0
    end

    # One tile that a boundary cut, built as its own little group from the
    # clipped footprint the slot is carrying. Only the edge of the roof pays
    # for this; the field is still instances of one definition.
    def self.build_cut_tile!(grp, s, shape_name, mat, tag)
      sh = InteriorPro::RoofTileMath.shape(shape_name)
      return false if sh.nil?
      h = InteriorPro::RoofTileParts.run_height(sh)
      o = s[:pu_origin]
      u = s[:u]
      v = s[:v]
      n = s[:n]
      sub = grp.entities.add_group
      sub.name = 'InteriorPro_FlatTileCut'
      sub.set_attribute('InteriorPro', 'part', 'tile_flat_cut')
      made = InteriorPro::RoofTileParts.build_flat_cut!(
        sub.entities, s[:cut], (s[:cv0] || s[:v0]).to_f,
        (s[:clen] || s[:length]).to_f, h, mat
      ) do |uu, vv, zz|
        p = InteriorPro::RoofTileMath.unproject([uu, vv], o, u, v)
        Geom::Point3d.new(p[0] + (n[0] * zz), p[1] + (n[1] * zz),
                          p[2] + (n[2] * zz))
      end
      if made.zero?
        begin
          sub.erase!
        rescue StandardError
          nil
        end
        return false
      end
      InteriorPro.assign_tag(sub, tag)
      true
    rescue StandardError => e
      puts "[RoofTiles] cut tile: #{e.message}"
      false
    end

    # ---------------------------------------------------------- THE EAVE BAR
    #
    # One square bar per roof plane, laid ALONG the eave - the border the metal
    # panels die into. It reuses the run machinery whole: the piece is modelled
    # an inch long and stretched, and the only difference is which way round
    # the frame is handed to it.
    #
    # u and v are SWAPPED, because the bar runs across the slope while a run
    # goes up it. The first axis is -v, not v: (-v) x u = n, so the frame stays
    # right handed and the piece is never mirrored. Handing over (v, u, n)
    # instead would flip it, which measures the same and looks wrong.
    def self.eave_bar_slots(planes, shape_name, opts = {})
      return [] unless InteriorPro::RoofTileMath.respond_to?(:seam?) &&
                       InteriorPro::RoofTileMath.seam?(shape_name)
      # (the eave_overhang it used to read is gone on purpose - the bar sits
      # flush with the edge now, see the comment below)
      s0 = InteriorPro::RoofTileMath.shape(shape_name)
      mid = InteriorPro::RoofTileParts.run_height(s0) / 2.0
      out = []
      (planes || []).each do |pl|
        pu = InteriorPro::RoofTileMath.plane_uv(pl[:points], pl[:n])
        next if pu.nil? || pu[:flat]
        # ON THE DECK, FLUSH WITH THE EDGE (2026-08-21, second pass). The bar
        # hung 1.25" past the eave, floating in the air with a 0.25" gap back
        # to the roof - the red line the user marked: "תסגור את החלק בין
        # המסגרת לסוף הגג." Its outer face now sits exactly ON the roof edge
        # (v = 0) and its body on the deck, so there is nothing to close - and
        # at a hip corner the two eaves' bars meet at the same corner point
        # instead of two floating ends missing each other.
        #
        # AND ONLY WHERE THE EAVE ACTUALLY IS (2026-08-21, third pass). The
        # length used to be u_span - the width of the WHOLE plane. Next to a
        # valley the plane widens higher up, far past the inner corner, so
        # the bar ran on along the eave line into the house, over nothing:
        # "הקווים של המסגרת בולטים פנימה לתוך הבית ואסור שזה יקרה." The
        # outline is asked directly - the same scanline the ribs use, at the
        # bar's own half height - so the bar covers exactly the stretches
        # where roof exists, and a split eave simply gets two bars.
        InteriorPro::RoofTileMath.spans_at(pu[:poly], mid, 1.0).each do |(u1, u2)|
          o = InteriorPro::RoofTileMath.unproject([u1, 0.0],
                                                  pu[:origin], pu[:u], pu[:v])
          out << { origin: o,
                   u: [-pu[:v][0], -pu[:v][1], -pu[:v][2]],
                   v: pu[:u], n: pu[:n], length: u2 - u1 }
        end
      end
      out
    end

    # Two bars that share a corner are MITRED into each other (2026-08-21,
    # second pass). As plain stretched boxes each ended in a square cut, so at
    # a hip corner the two ends crossed with a wedge of air above them -
    # "שתי המסגרות שנפגשות בפינה שיראו כאילו הם מחוברות בצורה ישרה". Each end
    # that meets another bar's end is now cut on the vertical plane that
    # bisects the two eaves in plan - the classic picture-frame joint. The two
    # planes carry the same pitch, so the two cut faces are mirror images and
    # land on each other EXACTLY: no gap, no overlap, one straight seam.
    #
    # The cost: a mitred end cannot come from stretching one shared box, so
    # every bar is built as its own six-face group. A roof has one bar per
    # eave - a handful of faces, not a flood.
    def self.place_eave_bars!(grp, planes, shape_name, opts = {})
      return 0 if grp.nil?
      slots = eave_bar_slots(planes, shape_name, opts)
      return 0 if slots.empty?
      s0 = InteriorPro::RoofTileMath.shape(shape_name)
      prof = InteriorPro::RoofTileParts.edge_bar_profile(s0)
      return 0 if prof.empty?
      tag = opts[:tag] || field_tag
      mat = opts[:material]
      # Which ends meet? Two bars sharing an endpoint (in plan) share a
      # corner. tol is generous - both points come from the same polygon.
      pts_of = lambda do |sl|
        p0 = sl[:origin]
        p1 = [p0[0] + sl[:v][0] * sl[:length],
              p0[1] + sl[:v][1] * sl[:length],
              p0[2] + sl[:v][2] * sl[:length]]
        [p0, p1]
      end
      near = lambda { |a, b| Math.hypot(a[0] - b[0], a[1] - b[1]) < 1.5 }
      made = 0
      slots.each_with_index do |sl, i|
        ends = pts_of.call(sl)
        # For each of my two ends: the matching end of some OTHER bar, if any.
        cut = [nil, nil]
        slots.each_with_index do |ot, j|
          next if j == i
          oe = pts_of.call(ot)
          2.times do |a|
            2.times do |b|
              next unless near.call(ends[a], oe[b])
              c = [(ends[a][0] + oe[b][0]) / 2.0, (ends[a][1] + oe[b][1]) / 2.0]
              # plan directions AWAY from the corner, into each bar
              d1 = a.zero? ? [sl[:v][0], sl[:v][1]] : [-sl[:v][0], -sl[:v][1]]
              d2 = b.zero? ? [ot[:v][0], ot[:v][1]] : [-ot[:v][0], -ot[:v][1]]
              n1 = Math.hypot(d1[0], d1[1])
              n2 = Math.hypot(d2[0], d2[1])
              next if n1 < 1.0e-9 || n2 < 1.0e-9
              d1 = [d1[0] / n1, d1[1] / n1]
              d2 = [d2[0] / n2, d2[1] / n2]
              # ONLY AN OUTER CORNER IS MITRED (2026-08-21, third pass). At
              # the INNER corner of an L the same slide runs the other way -
              # it EXTENDED each bar past the corner and the ends poked into
              # the house: "הקווים של המסגרת בולטים פנימה לתוך הבית ואסור
              # שזה יקרה". Convex or concave is one dot product: at an outer
              # corner the OTHER bar runs off toward my roof side (along my
              # up-slope), at an inner corner it runs away from it. Concave
              # ends stay square at the corner - the notch between the two
              # square ends sits inside the building where no one can see it.
              ina = [-sl[:u][0], -sl[:u][1]]
              inn = Math.hypot(ina[0], ina[1])
              next if inn < 1.0e-9
              next if (d2[0] * ina[0] + d2[1] * ina[1]) / inn < 1.0e-6
              # the mitre plane's plan normal: perpendicular to the bisector
              nm = [d1[0] - d2[0], d1[1] - d2[1]]
              nn = Math.hypot(nm[0], nm[1])
              next if nn < 0.2   # nearly straight-through: no corner to cut
              cut[a] = { c: c, nm: [nm[0] / nn, nm[1] / nn] }
            end
          end
        end
        made += 1 if build_bar!(grp, sl, prof, cut, mat, tag)
      end
      puts "[RoofTiles] eave bar: #{made} mitred bars"
      made
    end

    # One bar, six faces, ends cut where `cut` says. Each end-section vertex
    # is slid along the bar until its PLAN position lands on the mitre plane,
    # so the cut is straight in plan and follows the bar's own lean in 3D.
    def self.build_bar!(grp, sl, prof, cut, mat, tag)
      o = sl[:origin]
      u = sl[:u]
      v = sl[:v]
      n = sl[:n]
      at = lambda do |t, x, y|
        [o[0] + u[0] * x + v[0] * t + n[0] * y,
         o[1] + u[1] * x + v[1] * t + n[1] * y,
         o[2] + u[2] * x + v[2] * t + n[2] * y]
      end
      dv = [v[0], v[1]]
      sec = lambda do |t_end, cc|
        prof.map do |(x, y)|
          t = t_end
          if cc
            p = at.call(t_end, x, y)
            s = (p[0] - cc[:c][0]) * cc[:nm][0] + (p[1] - cc[:c][1]) * cc[:nm][1]
            k = dv[0] * cc[:nm][0] + dv[1] * cc[:nm][1]
            t = t_end - s / k if k.abs > 0.1
          end
          pt = at.call(t, x, y)
          Geom::Point3d.new(pt[0], pt[1], pt[2])
        end
      end
      a = sec.call(0.0, cut[0])
      b = sec.call(sl[:length], cut[1])
      m = prof.length
      sub = grp.entities.add_group
      sub.name = 'InteriorPro_EaveBar'
      sub.set_attribute('InteriorPro', 'part', 'tile_edge')
      polys = [a, b.reverse]
      (0...m).each { |i| polys << [a[i], a[(i + 1) % m], b[(i + 1) % m], b[i]] }
      polys.each do |pp|
        f = sub.entities.add_face(pp)
        next if f.nil? || mat.nil?
        f.material = mat
        f.back_material = mat
      end
      InteriorPro.assign_tag(sub, tag)
      true
    rescue StandardError => e
      puts "[RoofTiles] eave bar: #{e.message}"
      false
    end

    def self.transform_for(s)
      o = Geom::Point3d.new(s[:origin][0], s[:origin][1], s[:origin][2])
      Geom::Transformation.axes(o, vec(s[:u]), vec(s[:v]), vec(s[:n]))
    rescue StandardError => e
      puts "[RoofTiles] transform: #{e.message}"
      nil
    end

    # The frame, then the stretch. The pipe is modelled ONE INCH long up its
    # own +Y, so scaling Y by the run length is what makes one definition serve
    # every run on the roof. The point form of scaling is used because that is
    # the form both SketchUp and the test stub implement.
    # HIS PIECE, OUR ROOF. In his file the pipe lies along X, is `wide` in Z and
    # stands `high` in Y. Our frame is u across the slope, v up it, n out of it.
    # So his X goes to v - stretched from the length he modelled to the length
    # this run actually needs - his Z goes to u, and his Y goes to n.
    #
    # cross(v, n) = u whenever u x v = n, so the frame stays right handed and
    # the piece is never mirrored. A mirrored tile passes every measurement and
    # still looks wrong, which is the one failure this ordering prevents.
    def self.asset_transform_for(s, asset)
      len = s[:length].to_f
      modelled = asset[:len].to_f
      return nil if len <= 1.0e-9 || modelled <= 1.0e-9
      k = len / modelled
      o = Geom::Point3d.new(s[:origin][0], s[:origin][1], s[:origin][2])
      vv = vec(s[:v])
      Geom::Transformation.axes(o,
                                Geom::Vector3d.new(vv.x * k, vv.y * k, vv.z * k),
                                vec(s[:n]), vec(s[:u]))
    rescue StandardError => e
      puts "[RoofTiles] asset transform: #{e.message}"
      nil
    end

    def self.run_transform_for(s)
      len = s[:length].to_f
      return nil if len <= 1.0e-9
      o = Geom::Point3d.new(s[:origin][0], s[:origin][1], s[:origin][2])
      Geom::Transformation.axes(o, vec(s[:u]), vec(s[:v]), vec(s[:n])) *
        Geom::Transformation.scaling(Geom::Point3d.new(0, 0, 0), 1.0, len, 1.0)
    rescue StandardError => e
      puts "[RoofTiles] run transform: #{e.message}"
      nil
    end

    def self.vec(a)
      Geom::Vector3d.new(a[0], a[1], a[2])
    end
  end
end
