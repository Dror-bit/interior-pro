# encoding: utf-8
# Interior Pro - Elevations (2026-10-08)
#
# Four elevations of a room - one per wall - taken straight off the model:
# a parallel camera inside the room looking at the wall, with a section
# plane `cut` inches from the wall so only what stands between the plane and
# the wall is seen (the user: "אני יוכל לבחור מה המרחק מהקיר שהוא יראה").
# Every piece in the room draws as itself - the toilet, the shower head, the
# vanity, the tiles - because it IS the model, in hidden-line.
#
# Measured on his model (debug_elevation.rb, 2026-10-08):
#   - a room's `boundary_xy` is written in the coordinates of the room group's
#     CONTAINER (the world at the top level); the group itself only carries
#     the label. So only what is outside the group is applied to it.
#   - SketchUp KEEPS what is on the side a section plane's normal points to.
#     The normal points at the wall, away from the eye.
#   - the eye must stand INSIDE the room: half an inch inside the far wall it
#     saw only that wall.
#
# Each elevation is a picture file beside the model
# (<model folder>/InteriorPro_sheet/elevations/) and goes onto the Sheet
# window as a picture sheet of its own, exactly like a dropped render, so the
# box, the crop, the turn and the PDF all work on it with nothing new.
# Dimensions and layers come later, one step at a time.
#
# Kill switch: USE_ELEVATIONS = false - the button says so and does nothing.
require 'fileutils'
require 'tmpdir'
module InteriorPro
  module ElevationTool
    USE_ELEVATIONS = true unless const_defined?(:USE_ELEVATIONS, false)
    # A fixture made of parts (a shower set: head, valve, hand shower - measured on his model,
    # debug_fixture_parts.rb 13:42) is measured part by part, each at its MIDDLE: the height of
    # the middle from the floor and where the middle stands along the wall (his words 13:41:
    # "רק את הגובה של כל דבר והמרחק מהקיר הצדדי", and "1" = to the middle). Off = the whole set
    # as one box, its width in the chain and its bottom and top at the side, as before.
    USE_PART_MIDDLES = true unless const_defined?(:USE_PART_MIDDLES, false)
    D = 'InteriorPro' unless const_defined?(:D, false)
    NEST_DEPTH = 4 unless const_defined?(:NEST_DEPTH, false)
    MARGIN = 12.0 unless const_defined?(:MARGIN, false)         # inches of air round the wall
    PX_PER_IN = 12.0 unless const_defined?(:PX_PER_IN, false)   # picture resolution
    MAX_PX = 4800 unless const_defined?(:MAX_PX, false)
    OUT_DIR = 'InteriorPro_sheet/elevations' unless const_defined?(:OUT_DIR, false)
    TRACE = 'elevation_trace.txt' unless const_defined?(:TRACE, false)

    # Put aside for the shot (2026-10-08, after his Revit page): the floor and the ceiling are a
    # LINE in an elevation, not a slab seen edge-on, and the roof is not there at all. The walls
    # stay (cut, dark), and so does whatever hangs in the room - a lamp, a vent, the shower pan.
    # 'room' (12:39, measured): the room group only carries its name, lying flat 1/4" over the floor -
    # edge-on it was the broken dashes on the floor line.
    # Re-read on every reload (2026-10-08, measured on his model: the list loaded at 12:18 was the
    # first one, without the shower_* types - `unless const_defined?` kept it, so the shower pan
    # stayed in the picture as a dark strip under the tiles).
    remove_const(:SET_ASIDE) if const_defined?(:SET_ASIDE, false)
    SET_ASIDE = %w[floor floor_pattern floor_patch subfloor underlay foundation ceiling roof dormer
                   skylight downspout plan2d sketch2d
                   shower_floor shower_pattern shower_drain shower_curb room].freeze

    Thing = Struct.new(:ent, :xf, :type) unless const_defined?(:Thing, false)
    Side = Struct.new(:name, :a, :b, :len, :inward, :depth) unless const_defined?(:Side, false)

    class << self
      # ---- rooms ---------------------------------------------------------

      # every room of ours, also inside a plain group (the house in one group)
      # the rooms with plumbing or tile in them FIRST (2026-10-08: he made the empty
      # Room 1 before he found Room 2 in the list), then the rest in model order
      def rooms(model = Sketchup.active_model)
        out = []
        collect(model.entities, nil, 0, out)
        rs = out.select { |t| t.type == 'room' && room_poly(t) }
        wet = out.select { |t| WET_TYPES.include?(t.type) }
        rs.each_with_index.sort_by { |r, i| [holds_wet?(r, wet) ? 0 : 1, i] }.map(&:first)
      end

      # how many of the (sorted) rooms hold plumbing or tile - they stand first
      def wet_count(rooms, model = Sketchup.active_model)
        out = []
        collect(model.entities, nil, 0, out)
        wet = out.select { |t| WET_TYPES.include?(t.type) }
        rooms.count { |r| holds_wet?(r, wet) }
      end

      WET_TYPES = %w[fixture tile_wall tile_niche shower_floor].freeze unless const_defined?(:WET_TYPES, false)

      # does one of the wet things stand inside this room's outline
      def holds_wet?(room, wet)
        poly = room_poly(room)
        return false unless poly
        wet.any? do |w|
          c = world_centre(w)
          c && inside?(poly, c.x, c.y)
        end
      rescue StandardError
        false
      end

      # the middle of a thing in the world: its box is given in its container's
      # coordinates, so only what is OUTSIDE it is applied (as for a room's outline)
      def world_centre(th)
        outer = th.xf * th.ent.transformation.inverse
        th.ent.bounds.center.transform(outer)
      rescue StandardError
        nil
      end

      def inside?(poly, px, py)
        c = false
        j = poly.size - 1
        poly.each_with_index do |p, i|
          q = poly[j]
          c = !c if (p.y > py) != (q.y > py) && px < (q.x - p.x) * (py - p.y) / (q.y - p.y) + p.x
          j = i
        end
        c
      end

      def collect(ents, outer, depth, out)
        ents.each do |e|
          next unless e.is_a?(Sketchup::Group) ||
                      (defined?(Sketchup::ComponentInstance) && e.is_a?(Sketchup::ComponentInstance))
          next unless e.valid?
          t = e.get_attribute(D, 'type')
          if t
            xf = outer ? outer * e.transformation : e.transformation
            out << Thing.new(e, xf, t.to_s)
            next
          end
          next if depth >= NEST_DEPTH
          next if e.respond_to?(:hidden?) && e.hidden?
          kids = defined?(Sketchup::ComponentInstance) && e.is_a?(Sketchup::ComponentInstance) ? e.definition.entities : e.entities
          collect(kids, outer ? outer * e.transformation : e.transformation, depth + 1, out)
        end
      rescue StandardError => e
        puts "[Elevation] collect: #{e.class}: #{e.message}"
      end

      def room_name(th)
        n = th.ent.get_attribute(D, 'name').to_s
        n.empty? ? "Room #{th.ent.get_attribute(D, 'number')}" : n
      end

      # the room's floor outline in the WORLD (see the note at the top)
      def room_poly(th)
        flat = th.ent.get_attribute(D, 'boundary_xy')
        return nil unless flat.is_a?(Array) && flat.size >= 6
        outer = th.xf * th.ent.transformation.inverse
        pts = flat.each_slice(2).map { |x, y| Geom::Point3d.new(x.to_f, y.to_f, 0).transform(outer) }
        pts.size >= 3 ? pts : nil
      rescue StandardError
        nil
      end

      def room_height(th, model = Sketchup.active_model)
        ids = Array(th.ent.get_attribute(D, 'bounding_wall_ids'))
        hs = []
        collect(model.entities, nil, 0, (all = []))
        all.each do |t|
          next unless t.type == 'wall' && ids.include?(t.ent.get_attribute(D, 'id'))
          h = t.ent.get_attribute(D, 'height').to_f
          hs << h if h > 0
        end
        hs.empty? ? 96.0 : hs.max
      end

      # ---- geometry (pure) -------------------------------------------------

      def signed_area(poly)
        a = 0.0
        poly.each_with_index { |p, i| q = poly[(i + 1) % poly.size]; a += p.x * q.y - q.x * p.y }
        a / 2.0
      end

      # One Side per edge of the outline, A, B, C... - its length, the way INTO
      # the room, and how deep the room is behind it. Edges under 12" are skipped.
      def sides(poly)
        ccw = signed_area(poly) > 0
        out = []
        poly.each_with_index do |a, i|
          b = poly[(i + 1) % poly.size]
          len = a.distance(b)
          next if len < 12.0
          dir = Geom::Vector3d.new(b.x - a.x, b.y - a.y, 0).normalize
          left = Geom::Vector3d.new(-dir.y, dir.x, 0)
          inward = ccw ? left : left.reverse
          depth = poly.map { |p| (p.x - a.x) * inward.x + (p.y - a.y) * inward.y }.max
          out << Side.new(compass(inward.reverse), a, b, len, inward, depth)
        end
        # two walls facing the same way (an L-shaped room): North, North2
        seen = Hash.new(0)
        out.each do |sd|
          seen[sd.name] += 1
          sd.name = "#{sd.name}#{seen[sd.name]}" if seen[sd.name] > 1
        end
        out
      end

      # the wall's name is the way it FACES (his rule, 2026-10-08: "קירות לפי כיווני שמיים"):
      # the north wall of a room is the one you look north at. Green axis = north.
      def compass(outward)
        ang = Math.atan2(outward.y, outward.x) * 180.0 / Math::PI
        ang += 360.0 if ang < 0
        names = %w[East NorthEast North NorthWest West SouthWest South SouthEast]
        names[((ang + 22.5) / 45.0).floor % 8]
      end

      # Where the camera and the plane stand for one side. cut = inches from
      # the wall that are seen; nil or 0 = the whole room.
      def shot(side, wall_h, cut = nil, base_z = 0.0)
        c = cut.to_f
        c = side.depth - 0.5 if c <= 0 || c > side.depth - 0.5
        c = 1.0 if c < 1.0
        mid = Geom::Point3d.new((side.a.x + side.b.x) / 2.0, (side.a.y + side.b.y) / 2.0, base_z + wall_h / 2.0)
        n = side.inward
        plane_pt = Geom::Point3d.new(mid.x + n.x * c, mid.y + n.y * c, mid.z)
        eye = Geom::Point3d.new(mid.x + n.x * (c - 0.5), mid.y + n.y * (c - 0.5), mid.z)
        h_px = ((wall_h + 2 * MARGIN) * PX_PER_IN).round
        w_px = ((side.len + 2 * MARGIN) * PX_PER_IN).round
        if w_px > MAX_PX
          h_px = (h_px * MAX_PX / w_px.to_f).round
          w_px = MAX_PX
        end
        { eye: eye, target: mid, plane_pt: plane_pt, normal: n.reverse, cut: c,
          height: wall_h + 2 * MARGIN, w_px: w_px, h_px: h_px }
      end

      def set_aside?(type)
        SET_ASIDE.include?(type.to_s)
      end

      # ---- automatic dimensions (2026-10-08) --------------------------------
      #
      # His words: "נכניס מידות למיקומים אוטומטים", shown a picture of his own
      # Room 2 - North with a chain under the floor and heights at the side
      # ("ניראה טוב"), and: "צריך גם את הניץ גובה מהריצפה גובה הניץ ורוחב".
      #
      # The NUMBERS come from the model, never from the picture: a niche from
      # the wall's own `niches` row, a fixture and a tiled area from their box.
      # Measured on his model (debug_elev_items.rb, 12:57): the niche on the
      # East wall is 36 x 18 at 42" up, 17 1/8" from the corner.
      #
      # The sheet draws them OVER the picture as lines and words of its own
      # (PlanCanvas.place_elev_dims!), so they are sharp in the PDF and the
      # writing is the size of writing, whatever size the picture is.

      DIM_MIN = 1.0 unless const_defined?(:DIM_MIN, false)   # two stops closer than this are one (a tile's thickness is not a dimension)

      def last_dims
        @last_dims ||= {}
      end

      # What one wall's dimensions measure, in the side's own numbers:
      # [{ kind:, a0:, a1:, z0:, z1: }] - a along the side from side.a, z up from the floor.
      #   niche     - on a wall face looking INTO the room, on this side's line
      #   fixture   - its box reaches into the `cut` in front of the wall
      #   tile_wall - a tiled area lying ON this wall (thin, at the face): along only
      def side_items(side, cut, all, base_z)
        dir = Geom::Vector3d.new(side.b.x - side.a.x, side.b.y - side.a.y, 0)
        dir.normalize!
        n = side.inward
        al = ->(p) { (p.x - side.a.x) * dir.x + (p.y - side.a.y) * dir.y }
        inn = ->(p) { (p.x - side.a.x) * n.x + (p.y - side.a.y) * n.y }
        cut = cut.to_f > 0 ? cut.to_f : side.depth.to_f
        out = []
        all.each do |t|
          case t.type
          when 'wall'
            next unless defined?(InteriorPro::TileNiche) && defined?(InteriorPro::TileWall)
            outer = t.xf * t.ent.transformation.inverse
            InteriorPro::TileNiche.read(t.ent).each do |ni|
              fr = InteriorPro::TileWall.frame_for(t.ent, ni[:side])
              next unless fr
              nv = Geom::Vector3d.new(fr[:nx], fr[:ny], 0).transform(outer)
              next unless nv.length > 0.5 && (nv.x * n.x + nv.y * n.y) / nv.length > 0.9
              p0 = Geom::Point3d.new(*InteriorPro::TileWall.world(fr, ni[:u0], ni[:z0])).transform(outer)
              p1 = Geom::Point3d.new(*InteriorPro::TileWall.world(fr, ni[:u0] + ni[:w], ni[:z0] + ni[:h])).transform(outer)
              next unless inn.call(p0).abs < 1.5
              a0, a1 = [al.call(p0), al.call(p1)].minmax
              next if a1 <= 0 || a0 >= side.len
              out << { kind: 'niche', a0: [a0, 0.0].max, a1: [a1, side.len].min,
                       z0: [p0.z, p1.z].min - base_z, z1: [p0.z, p1.z].max - base_z }
            end
          when 'fixture', 'tile_wall'
            pts = world_box(t)
            next unless pts
            ins = pts.map { |p| inn.call(p) }
            als = pts.map { |p| al.call(p) }
            if t.type == 'fixture'
              next if ins.max < -1.0 || ins.min > cut
              parts = USE_PART_MIDDLES ? part_boxes(t) : nil
              if parts
                parts.each do |pp|
                  am = pp.map { |p| al.call(p) }
                  am = (am.min + am.max) / 2.0
                  next if am <= 0 || am >= side.len
                  zm = (pp.map(&:z).min + pp.map(&:z).max) / 2.0 - base_z
                  out << { kind: 'part', a0: am, a1: am, z0: zm, z1: zm }
                end
                next
              end
            else
              next unless ins.min > -0.5 && ins.max < 2.0
            end
            next if als.max <= 0 || als.min >= side.len
            zs = pts.map(&:z)
            out << { kind: t.type, a0: [als.min, 0.0].max, a1: [als.max, side.len].min,
                     z0: zs.min - base_z, z1: zs.max - base_z }
          end
        end
        out
      end

      def safely_items(side, cut, all, base_z)
        side_items(side, cut, all, base_z)
      rescue StandardError => e
        puts "[Elevation] dimensions skipped on #{side.name}: #{e.class}: #{e.message}"
        []
      end

      # The parts a fixture is made of (USE_PART_MIDDLES): the eight corners of each part's
      # box in the world, or nil when it is not made of two parts or more (a tub, a toilet).
      def part_boxes(t)
        ents = defined?(Sketchup::ComponentInstance) && t.ent.is_a?(Sketchup::ComponentInstance) ? t.ent.definition.entities : t.ent.entities
        kids = ents.select do |k|
          (k.is_a?(Sketchup::Group) || (defined?(Sketchup::ComponentInstance) && k.is_a?(Sketchup::ComponentInstance))) &&
            !(k.respond_to?(:hidden?) && k.hidden?)
        end
        return nil if kids.size < 2
        boxes = kids.map { |k| world_box(Thing.new(k, t.xf * k.transformation, 'part')) }.compact
        boxes.size >= 2 ? boxes : nil
      end

      # the eight corners of a thing's box, in the world
      def world_box(t)
        ents = defined?(Sketchup::ComponentInstance) && t.ent.is_a?(Sketchup::ComponentInstance) ? t.ent.definition.entities : t.ent.entities
        bb = Geom::BoundingBox.new
        ents.each { |k| bb.add(k.bounds) if k.respond_to?(:bounds) }
        return nil if bb.empty?
        (0..7).map { |i| bb.corner(i).transform(t.xf) }
      end

      # 87.125 -> 87 1/8"   (to the sixteenth, the way he reads a tape)
      def fmt_in(v)
        s16 = (v.to_f * 16).round
        i = s16 / 16
        f = s16 % 16
        return "#{i}\"" if f.zero?
        g = f.gcd(16)
        i.zero? ? "#{f / g}/#{16 / g}\"" : "#{i} #{f / g}/#{16 / g}\""
      end

      # The dimensions of one picture, in shares of the WHOLE picture (u from its
      # left, v from its bottom) - the way the sheet places a picture (box + crop).
      # The picture looks AT the wall from inside the room: side.b is on its left.
      #   'k' => 'h': a run under the floor; 'u' => [u1, u2], 'v' => the floor, 'row' => 1 (the
      #              chain: corner, every edge of every thing, corner) or 2 (the whole wall)
      #   'k' => 'v': a run at the right; 'v' => [v1, v2], 'u' => the right corner, 'col' => 1..
      #              one column a niche / fixture (floor -> bottom -> top), the wall's height last
      # 't' => the words. Pure.
      def dims_for(side, wall_h, items)
        len = side.len.to_f
        pw = len + 2 * MARGIN
        ph = wall_h.to_f + 2 * MARGIN
        ux = ->(a) { (MARGIN + len - a) / pw }
        vz = ->(z) { (MARGIN + z) / ph }
        out = []
        stops = [0.0, len]
        items.each { |it| stops << it[:a0].to_f << it[:a1].to_f }
        stops = stops.map { |a| [[a, 0.0].max, len].min }.sort
        run = []
        stops.each { |a| run << a if run.empty? || a - run.last > DIM_MIN }
        run[-1] = len
        if run.size > 2
          run.reverse.each_cons(2) do |q, p|     # left to right as the picture shows it
            out << { 'k' => 'h', 'row' => 1, 'u' => [ux.call(q), ux.call(p)], 'v' => vz.call(0.0), 't' => fmt_in(q - p) }
          end
        end
        out << { 'k' => 'h', 'row' => (run.size > 2 ? 2 : 1), 'u' => [ux.call(len), ux.call(0.0)],
                 'v' => vz.call(0.0), 't' => fmt_in(len) }
        col = 0
        items.reject { |it| it[:kind] == 'tile_wall' }.sort_by { |it| it[:a0].to_f }.each do |it|
          if it[:kind] == 'part'     # one height: the floor to the part's middle
            zm = [[it[:z1].to_f, 0.0].max, wall_h.to_f].min
            next if zm <= DIM_MIN
            col += 1
            out << { 'k' => 'v', 'col' => col, 'v' => [vz.call(0.0), vz.call(zm)], 'u' => ux.call(0.0), 't' => fmt_in(zm) }
            next
          end
          z0 = [[it[:z0].to_f, 0.0].max, wall_h.to_f].min
          z1 = [[it[:z1].to_f, 0.0].max, wall_h.to_f].min
          next if z1 - z0 <= DIM_MIN
          zs = z0 > DIM_MIN ? [0.0, z0, z1] : [0.0, z1]
          col += 1
          zs.each_cons(2) do |p, q|
            out << { 'k' => 'v', 'col' => col, 'v' => [vz.call(p), vz.call(q)], 'u' => ux.call(0.0), 't' => fmt_in(q - p) }
          end
        end
        out << { 'k' => 'v', 'col' => col + 1, 'v' => [vz.call(0.0), vz.call(wall_h.to_f)], 'u' => ux.call(0.0),
                 't' => fmt_in(wall_h.to_f) }
        out
      end

      # ---- files -------------------------------------------------------------

      def model_dir(model = Sketchup.active_model)
        p = model.path.to_s.tr('\\', '/')
        p.empty? ? nil : File.dirname(p)
      end

      def out_dir(model = Sketchup.active_model)
        tmp = Sketchup.respond_to?(:temp_dir) ? Sketchup.temp_dir.to_s.tr('\\', '/') : Dir.tmpdir
        base = model_dir(model) || File.join(tmp, 'InteriorPro')
        File.join(base, OUT_DIR)
      end

      def slug(name)
        s = name.to_s.gsub(/[^A-Za-z0-9\u0590-\u05FF]+/, '_').gsub(/\A_+|_+\z/, '')
        s.empty? ? 'room' : s
      end

      def file_for(dir, room_name, side_name, style)
        File.join(dir, "#{slug(room_name)}_#{side_name}_#{style}.png")
      end

      # ---- the shot itself (SketchUp only) ---------------------------------

      RENDER_KEYS = %w[RenderMode DrawHorizon DrawGround BackgroundColor DisplaySectionPlanes
                       SectionCutFilled DisplayText DisplayDims DisplaySketchAxes
                       EdgeDisplayMode DrawSilhouettes ExtendLines
                       DisplaySectionCuts].freeze unless const_defined?(:RENDER_KEYS, false)

      # Takes every side of the room. Returns the picture paths, in A, B, C
      # order. style: 'lines' (hidden line) or 'shaded' (as he sees it).
      def shoot!(room, cut: nil, style: 'lines', model: Sketchup.active_model)
        raise 'Elevations are switched off (USE_ELEVATIONS)' unless USE_ELEVATIONS
        poly = room_poly(room)
        raise 'this room has no outline' unless poly
        view = model.active_view
        wall_h = room_height(room, model)
        base_z = poly.first.z
        dir = out_dir(model)
        FileUtils.mkdir_p(dir)
        name = room_name(room)
        paths = []
        cam0 = view.camera
        keep = [cam0.eye, cam0.target, cam0.up, cam0.perspective?, (cam0.perspective? ? cam0.fov : cam0.height)]
        ro = model.rendering_options
        saved = {}
        RENDER_KEYS.each { |k| saved[k] = ro[k] }
        hidden = []
        last_dims.clear
        model.start_operation('Elevations', true)
        begin
          all = []
          collect(model.entities, nil, 0, all)
          all.each do |t|
            next unless set_aside?(t.type) && t.ent.respond_to?(:hidden=) && !t.ent.hidden?
            t.ent.hidden = true
            hidden << t.ent
          end
          ro['DrawHorizon'] = false
          ro['DrawGround'] = false
          ro['BackgroundColor'] = Sketchup::Color.new(255, 255, 255)
          ro['DisplaySectionPlanes'] = false
          ro['DisplaySectionCuts'] = true
          ro['SectionCutFilled'] = true
          ro['DisplayText'] = false
          ro['DisplayDims'] = false
          ro['DisplaySketchAxes'] = false
          ro['RenderMode'] = (style == 'shaded' ? 3 : 1)
          sides(poly).each do |side|
            s = shot(side, wall_h, cut_for(cut, side.name), base_z)
            sp = model.entities.add_section_plane([s[:plane_pt], s[:normal]])
            sp.activate
            # the floor and the ceiling as one straight line each, whatever stands at the foot
            # of the wall (12:12 - "אני רוצה שזה יהיה קו ישר"): two edges half an inch into
            # the room, from corner to corner, that go with the aborted operation
            n = side.inward
            [base_z, base_z + wall_h].each do |z|
              pa = Geom::Point3d.new(side.a.x + n.x * 0.5, side.a.y + n.y * 0.5, z)
              pb = Geom::Point3d.new(side.b.x + n.x * 0.5, side.b.y + n.y * 0.5, z)
              model.entities.add_line(pa, pb)
            end
            cam = Sketchup::Camera.new(s[:eye], s[:target], Geom::Vector3d.new(0, 0, 1), false)
            cam.height = s[:height]
            view.camera = cam
            view.refresh
            path = file_for(dir, name, side.name, style)
            ok = view.write_image(path, s[:w_px], s[:h_px], true)
            # the automatic dimensions of this wall (2026-10-08), for the sheet to draw over it
            if ok
              its = safely_items(side, s[:cut], all, base_z)
              last_dims[path.tr('\\', '/')] = dims_for(side, wall_h, its)
              trace("#{name} side #{side.name}: dims #{its.map { |i| "#{i[:kind]} #{i[:a0].round(2)}..#{i[:a1].round(2)} z #{i[:z0].round(2)}..#{i[:z1].round(2)}" }.join('; ')}")
            end
            sp.erase!
            trace("#{name} side #{side.name}: #{side.len.round(1)}\" long, cut #{s[:cut].round(1)}\", " \
                  "#{s[:w_px]}x#{s[:h_px]} -> #{File.basename(path)} #{ok ? 'written' : 'NOT written'}")
            paths << path if ok
          end
        ensure
          hidden.each { |e| e.hidden = false if e.valid? }
          model.abort_operation
          saved.each { |k, v| ro[k] = v unless v.nil? }
          begin
            cam = Sketchup::Camera.new(keep[0], keep[1], keep[2], keep[3])
            keep[3] ? cam.fov = keep[4] : cam.height = keep[4]
            view.camera = cam
          rescue StandardError => e
            puts "[Elevation] camera not put back: #{e.message}"
          end
        end
        paths
      end

      # ---- onto the sheet ----------------------------------------------------

      # Each picture becomes a picture sheet of its own in the Sheet window,
      # exactly as a dropped render does (st['images']). If the window is open
      # it is told to draw again.
      # titles: path => the name the sheet carries ("Room 2 - A"); st['image_titles']
      # dims: path => the automatic dimensions of that picture (dims_for); st['image_dims']
      def add_to_sheet!(paths, titles = {}, dims = {})
        return 0 if paths.empty?
        psd = InteriorPro::PlanSheetDialog
        st = psd.load_state
        have = Array(st['images']).map { |p| p.to_s.tr('\\', '/') }
        fresh = paths.map { |p| p.to_s.tr('\\', '/') }
        st['images'] = have.reject { |p| fresh.include?(p) } + fresh
        tt = st['image_titles'].is_a?(Hash) ? st['image_titles'] : {}
        titles.each { |p, t| tt[p.to_s.tr('\\', '/')] = t.to_s }
        st['image_titles'] = tt.select { |p, _| st['images'].include?(p) }
        dd = st['image_dims'].is_a?(Hash) ? st['image_dims'] : {}
        dims.each { |p, d| dd[p.to_s.tr('\\', '/')] = d }
        st['image_dims'] = dd.select { |p, _| st['images'].include?(p) }
        psd.save_state(st)
        begin
          dlg = psd.instance_variable_get(:@dialog)
          if dlg
            psd.instance_variable_set(:@doc, nil)
            psd.send(:push_all, dlg)
          end
        rescue StandardError => e
          puts "[Elevation] sheet window not refreshed: #{e.message}"
        end
        fresh.size
      end

      # the whole job from the panel: shoot, then onto the sheet
      def make!(room, cut: nil, style: 'lines')
        paths = shoot!(room, cut: cut, style: style)
        dims = paths.each_with_object({}) { |p, h| d = last_dims[p.to_s.tr('\\', '/')]; h[p] = d if d }
        n = add_to_sheet!(paths, titles_for(room, paths), dims)
        trace("#{room_name(room)}: #{paths.size} pictures, #{n} onto the sheet")
        paths
      end

      # several rooms in one go (2026-10-08): every picture of every room, in order
      # cuts (2026-10-08, his rule: "מרחק לכל הבית, לכל חדר, ולכל קיר"): one number for
      # all, or a Hash { 'house' => 60, 'room' => 24, 'walls' => { 'A' => 12 } } -
      # the wall's own number wins, then the room's, then the house's; nothing = the whole room.
      def cut_for(cut, side_name)
        return cut unless cut.is_a?(Hash)
        w = cut['walls'].is_a?(Hash) ? cut['walls'][side_name.to_s] : nil
        [w, cut['room'], cut['house']].each do |v|
          f = v.to_s.strip.empty? ? 0.0 : v.to_f
          return f if f > 0
        end
        nil
      end

      # rooms: the Things; cuts: one number for all, or an Array of Hashes, one a room
      def make_all!(rooms, cut: nil, style: 'lines')
        rooms.each_with_index.flat_map do |r, i|
          c = cut.is_a?(Array) ? cut[i] : cut
          make!(r, cut: c, style: style)
        end
      end

      # "Room 2 - A" from the file name's side letter
      def titles_for(room, paths)
        name = room_name(room)
        paths.each_with_object({}) do |p, h|
          side = File.basename(p, '.png')[/_([A-Za-z]+\d*)_[a-z]+\z/, 1] || '?'
          h[p] = "#{name} - #{side}"
        end
      end

      def trace(line)
        dir = (ENV['IP_PROBE_DIR'] || 'C:/Users/rordt/OneDrive/InteriorPro')
        return unless File.directory?(dir)
        File.open(File.join(dir, TRACE), 'a:UTF-8') { |f| f.puts "#{Time.now.strftime('%H:%M:%S')} #{line}" }
      rescue StandardError
        nil
      end
    end
  end
end
