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
        d.set_attribute('InteriorPro', 'part', "tile_#{kind.downcase}")
        d.set_attribute('InteriorPro', 'coverage_w', run)
      end
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
    def self.profile(w, h, round)
      half = w / 2.0
      return [[-half, 0.0], [-half, h], [half, h], [half, 0.0]] unless round
      n = [arc_segments.to_i, 2].max
      (0..n).map do |i|
        a = Math::PI * i / n.to_f
        [-half * Math.cos(a), h * Math.sin(a)]
      end
    end

    # Sweep a profile from y0 to y1. Explicit faces, no pushpull: pushpull on
    # a tiny profile is where SketchUp starts inventing internal faces, and
    # "avoid unnecessary internal faces" is a stated requirement.
    def self.build_extrusion!(ents, prof, y0, y1)
      a = prof.map { |(x, z)| Geom::Point3d.new(x, y0, z) }
      b = prof.map { |(x, z)| Geom::Point3d.new(x, y1, z) }
      made = 0
      (0...(prof.length - 1)).each do |i|
        made += 1 if add_face(ents, [a[i], a[i + 1], b[i + 1], b[i]])
      end
      # The two ends. The underside is left OPEN on purpose: it sits on the
      # roof and is never seen, and leaving it out is one less face per
      # instance across the whole roof.
      made += 1 if add_face(ents, a)
      made += 1 if add_face(ents, b.reverse)
      made
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
