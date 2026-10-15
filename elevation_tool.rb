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
require 'json'
require 'tmpdir'
module InteriorPro
  module ElevationTool
    remove_const(:USE_KITCHEN_SHEET_GRID) if const_defined?(:USE_KITCHEN_SHEET_GRID, false)
    USE_KITCHEN_SHEET_GRID = true
    remove_const(:USE_KITCHEN_AUTO_DEPTH) if const_defined?(:USE_KITCHEN_AUTO_DEPTH, false)
    USE_KITCHEN_AUTO_DEPTH = true
    remove_const(:USE_KITCHEN_ISLAND_VIEWS) if const_defined?(:USE_KITCHEN_ISLAND_VIEWS, false)
    USE_KITCHEN_ISLAND_VIEWS = true
    remove_const(:USE_KITCHEN_UPPER_DASHES) if const_defined?(:USE_KITCHEN_UPPER_DASHES, false)
    USE_KITCHEN_UPPER_DASHES = true
    remove_const(:USE_KITCHEN_CABINET_PLAN) if const_defined?(:USE_KITCHEN_CABINET_PLAN, false)
    USE_KITCHEN_CABINET_PLAN = true
    remove_const(:USE_KITCHEN_PLAN_DIMS) if const_defined?(:USE_KITCHEN_PLAN_DIMS, false)
    USE_KITCHEN_PLAN_DIMS = true
    remove_const(:USE_KITCHEN_BODY_HEIGHTS) if const_defined?(:USE_KITCHEN_BODY_HEIGHTS, false)
    USE_KITCHEN_BODY_HEIGHTS = true
    USE_ELEVATIONS = true unless const_defined?(:USE_ELEVATIONS, false)
    # A fixture made of parts (a shower set: head, valve, hand shower - measured on his model,
    # debug_fixture_parts.rb 13:42) is measured part by part, each at its MIDDLE: the height of
    # the middle from the floor and where the middle stands along the wall (his words 13:41:
    # "רק את הגובה של כל דבר והמרחק מהקיר הצדדי", and "1" = to the middle). Off = the whole set
    # as one box, its width in the chain and its bottom and top at the side, as before.
    USE_PART_MIDDLES = true unless const_defined?(:USE_PART_MIDDLES, false)
    # 13:54, his words: "שהקווים יגעו בנקודה שאליו הוא מתייחס" - a part's lines run TO its
    # middle: the chain's line up from under the floor, the height's line across from the
    # side ('r' on a chain dimension, 'u0' on a height). Off = they stop at the floor and at
    # the corner, as at 13:50.
    USE_PART_REACH = true unless const_defined?(:USE_PART_REACH, false)
    # 14:00, after a picture of a sheet with the room's four walls in a row ("ניראה מעולה"):
    # all the walls of a room go onto ONE picture sheet, each in a box of its own, side by side
    # at one scale, in the top half of the sheet (the rest is his: pictures, another room). A box
    # he already moved stays where he put it. Off = one sheet a wall, as before.
    USE_ONE_SHEET = true unless const_defined?(:USE_ONE_SHEET, false)
    # 15:57, after a Chief Architect sheet of his: "רק צריך מידה אחת או שתיים לכל דבר כדי שיהיה קריא
    # ונקי, וגם לפזר את המידות וגם לכתוב ליד הדבר עצמו". Each thing gets one or two numbers, by
    # the wall NEARER to it (the heights in a column on that side, the distance from that wall
    # written at the thing itself); under the floor only the whole wall (and a tub's width).
    # The tiles get none. Off = the long chain and every height on the right, as at 14:30.
    USE_CLEAN_DIMS = true unless const_defined?(:USE_CLEAN_DIMS, false)
    # 16:10, the next of his list (the room's sheet he okayed at 14:00 had it on the left): the room
    # seen from above - a parallel camera looking down, a section plane PLAN_CUT over the floor (the
    # walls cut, dark, as a plan draws them), the same 12 px an inch as the walls so it stands at
    # their scale; it is the FIRST picture of the room's sheet. Off = the walls only, as at 16:08.
    USE_TOP_VIEW = true unless const_defined?(:USE_TOP_VIEW, false)
    PLAN_CUT = 48.0 unless const_defined?(:PLAN_CUT, false)
    # (16:14: "צריך להראות את הביוב, הטייל, הסכר, השירותים וכל שאר הדברים") - from above only what is
    # OVER the room is put aside; the floor, the shower pan, its drain and curb are the picture
    remove_const(:TOP_ASIDE) if const_defined?(:TOP_ASIDE, false)
    TOP_ASIDE = %w[ceiling roof dormer skylight downspout plan2d sketch2d room].freeze
    NICHE_UNDER = 6.0 unless const_defined?(:NICHE_UNDER, false)       # inches under a niche for its width
    ON_WALL = 3.0 unless const_defined?(:ON_WALL, false)               # a fixture this close to a wall stands on it
    WORDS_APART = 8.0 unless const_defined?(:WORDS_APART, false)       # two distances closer than this: the lower one's words go under its line
    USE_TYPED_DIMS = true unless const_defined?(:USE_TYPED_DIMS, false) # 16:25: a set's numbers are the ones he typed
    # ELECTRIC ON THE ELEVATION GETS ITS NUMBERS (2026-10-14 17:29, his "עכשיו צריך רק את המידות"): an outlet, a switch or
    # a wall light on this wall gets the numbers he TYPED in the electrical tool - its height from the floor (height_in,
    # to its middle) by the nearer wall and its distance from that wall along the face (u_in) at that height - on the
    # ELECTRIC layer (g 'electric'), so they go off with the plates. A ceiling kind has no wall: nothing.
    USE_ELEC_DIMS = true unless const_defined?(:USE_ELEC_DIMS, false)
    ELEC_ROW = 4.0 unless const_defined?(:ELEC_ROW, false)
    # ONLY THIS ROOM IN ITS PICTURES (2026-10-14 17:47, his "למה הוא מראה חלקים מחוץ לחדר, תוריד אותם"): the camera's air past
    # the corner walls showed the next room's vanity. Every Interior Pro thing whose middle lies outside the room's outline
    # (walls, doors and windows excepted - the cut walls must show) is put aside for the room's shots, like the floors are.
    # Kill switch: false = as before.
    USE_ROOM_ONLY = true unless const_defined?(:USE_ROOM_ONLY, false)
    # 19:51, his words: "הוא עדיין מסרטט לי חלקים מחוץ לחדר הנבחר... הוא חייב לעצור בגבול החדר הנבחר" - measured
    # (debug_room_only.rb): what was left outside were the walls, doors and windows of the NEXT room, kept as the
    # frame. Now only this room's own walls (its bounding_wall_ids) stay, and only the doors and windows that sit on its
    # outline (their middle within FRAME_NEAR of a side, inside that side's length). Off = every wall/door/window stays.
    USE_ROOM_ONLY_FRAME = true unless const_defined?(:USE_ROOM_ONLY_FRAME, false)
    FRAME_NEAR = 8.0 unless const_defined?(:FRAME_NEAR, false)
    # 20:05, his "עדיין קיים" - measured (debug_room_only2.rb): what was left by the corner was the KITCHEN (the hood, its
    # cover, the range's backsplash) - KitchenLab groups, no Interior Pro type, so collect never saw them. A kitchen group
    # (dictionary KITCHEN_DICT, any kind) whose middle lies outside the room is put aside too. Off = kitchen untouched.
    USE_ROOM_ONLY_KITCHEN = true unless const_defined?(:USE_ROOM_ONLY_KITCHEN, false)
    KITCHEN_DICT = 'KitchenLab' unless const_defined?(:KITCHEN_DICT, false)
    # ONLY WHAT IS ON THE WALL IN ITS PICTURE (2026-10-15 10:06, his "יותר נקי ורק את הדברים שעל הקיר", approved on the
    # kitchen rendering 10:11): for each wall's shot, every thing of ours (not wall/door/window) and every top-level
    # kitchen group whose box starts more than ON_WALL_PIC off that wall's face is put aside - the pendants, the island,
    # a sconce on the next wall. A whole kitchen unit decides, not its parts (the hood's cover). Off = as before.
    USE_ON_WALL_ONLY = true unless const_defined?(:USE_ON_WALL_ONLY, false)
    # (2026-10-15 13:00, his "מזה התמונה השלישית שניראת נורא" - measured south_black_report.txt): the continuous backsplash is
    # ONE kitchen group over the whole L, its box touches South, so it stayed - and the section plane cut its far piece (out
    # 104.5..214.5) into a big black shape. The PIECES of a worktop group that stand off this wall are put aside too (back
    # right after, never erased). Off = the whole group decides, as before.
    USE_WORKTOP_PIECES = true unless const_defined?(:USE_WORKTOP_PIECES, false)
    ON_WALL_PIC = 3.0 unless const_defined?(:ON_WALL_PIC, false)
    # "Kitchen" in the Elevations list (10:48) - see make_kitchen!
    USE_KITCHEN_PICK = true unless const_defined?(:USE_KITCHEN_PICK, false)
    KITCHEN_LABEL = 'Kitchen' unless const_defined?(:KITCHEN_LABEL, false)
    PLAN_NO_FLOOR = %w[floor floor_pattern floor_patch subfloor underlay].freeze unless const_defined?(:PLAN_NO_FLOOR, false)
    KITCHEN_WALL_KINDS = %w[kitchen_unit cabinet].freeze unless const_defined?(:KITCHEN_WALL_KINDS, false)
    # KITCHEN WALLS BY THE WAY THE CABINETS FACE (2026-10-15 12:26, measured kitchen_dims_report: every cabinet carries the
    # letter A, so the letter picked ONE wall and West went missing; his words "לא אות אלא כיווני שמים" and "כל קבינט שקשור
    # לחדר המטבח הוא חלק ממנו"): a wall is a kitchen wall when a cabinet stands on it with its BACK (KitchenLab builds a
    # cabinet with its back at local y = 0 and its front at -depth: +y looks at the wall). A corner cabinet stands on both.
    # Off = by letter, as at 11:49.
    USE_KITCHEN_FACING = true unless const_defined?(:USE_KITCHEN_FACING, false)
    # THE KITCHEN'S NUMBERS (12:17, his "אין מידות לארונות"): on the wall's picture, orange (g 'kitchen'): the base cabinets'
    # widths in a chain under the floor, the upper ones' over the ceiling, the heights by the nearer wall (the counter, the
    # uppers, a tall one). A cabinet's width is its box's (an appliance's 35 15/16 = 36 at the half inch). Off = none.
    USE_KITCHEN_DIMS = true unless const_defined?(:USE_KITCHEN_DIMS, false)
    UPPER_Z = 30.0 unless const_defined?(:UPPER_Z, false)     # a cabinet starting this high is an upper one
    TALL_Z = 80.0 unless const_defined?(:TALL_Z, false)       # a base one reaching this high is a tall one
    # ROWS OF ELECTRIC DISTANCES NEVER ON EACH OTHER (12:16, his "המידות מבולגנות", measured kitchen_dims_report: on West the
    # rows of the plates at 42" and at 48" stood 6" apart, their words on each other): the rows of one half of the wall
    # stand past ALL the plates of that half, ELEC_STACK apart. Off = each row by its own plates, as before.
    USE_ELEC_STACK = true unless const_defined?(:USE_ELEC_STACK, false)
    ELEC_STACK = 10.0 unless const_defined?(:ELEC_STACK, false)
    ROOM_ONLY_KEEP = %w[wall door window].freeze   # 17:39 ("המידות צריכות לבוא או מלמעלה או מלמטה ולא על המוצר"): the row of
                                                             # distances runs this far above the plates' top (upper half) or under their bottom
    USE_WINDOW_MIDCUT = true unless const_defined?(:USE_WINDOW_MIDCUT, false) # 18:56: from above a window is cut at its own middle; off = not cut (seen whole), as before
    USE_LEAF_FACE = true unless const_defined?(:USE_LEAF_FACE, false) # 19:01: a white face under a door's leaf too, not only under its swing; off = the swing alone, as before
    USE_SWING_FACE = false unless const_defined?(:USE_SWING_FACE, false) # 19:16: no white under the swing's quarter circle - the leaf only
    # 19:19, his words: "תאפשר לי גם להשתמש בכל הכלים... גם על האליווישין... חייב להינעל על פינות וסופי קווים" - a
    # picture has no lines, so each wall's picture gets its lines as numbers beside it (<picture>.snaps.json,
    # shares of the picture like the automatic dimensions), only the ones the picture really shows
    # (measured 19:21, debug_elev_snaps.rb: North 10,315 lines in front of the wall, some never drawn).
    USE_ELEV_SNAPS = true unless const_defined?(:USE_ELEV_SNAPS, false)
    # 2026-10-09, his law: "TILE , PLUMING , ELECTRIC בתוכניות חייבים להיות כשכבות" - and he chose to start with the
    # elevations. A picture is ONE picture, so each wall (and the view from above) is also taken once for every
    # mix of those things switched off that stands in front of it - without the tiles, without the plumbing,
    # without both... - each beside the picture (<picture>__no_plumbing+tile.png), named in <picture>.layers.json
    # ({cats, files}). The sheet shows the one his groups ask for (PlanCanvas.pic_shown), so what is behind a
    # toilet is really there when the toilet is off - not a hole. Off = one picture a wall, as before.
    USE_ELEV_LAYERS = true unless const_defined?(:USE_ELEV_LAYERS, false)
    # the pictures without a layer are taken smoothed (antialias) like the whole one; false = not (faster? measured
    # by debug_elev_time.rb before it is ever switched)
    VARIANT_AA = true unless const_defined?(:VARIANT_AA, false)
    # 10:17, measured (debug_elev_time.rb, Room 2): the button took 23 s - 12 of them the 15 pictures without a layer
    # (0.8 s each), most of which he never looks at. So the button only WRITES DOWN which layers stand in front of
    # each wall (layers.json, no files yet) and a picture without a layer is taken the first time he switches that
    # layer off with the picture on his sheet, or prints it (PlanSheetDialog.ensure_layer_pictures! ->
    # ensure_variants!, the same shot again: shoot! only:). Off = all of them taken by the button, as at 09:28.
    USE_LAZY_LAYERS = true unless const_defined?(:USE_LAZY_LAYERS, false)
    remove_const(:CAT_TYPES) if const_defined?(:CAT_TYPES, false)
    CAT_TYPES = { 'tile' => %w[tile_wall tile_niche floor_pattern shower_pattern],
                  'plumbing' => %w[fixture],
                  # 'electrical' is what the electrical tool really writes (ElectricalLibrary.place! / place_on_ceiling!, measured
                  # 2026-10-13 mep_2d_report: cat_of('electrical') -> nil, so the ELECTRIC layer never caught an outlet, a switch or
                  # a light); the old names stay in case something older wrote them (2026-10-14, his pick "1": electric on the elevation)
                  'electric' => %w[electrical electric outlet switch light lighting] }.freeze
    SNAP_SEEN = 0.6 unless const_defined?(:SNAP_SEEN, false)   # a line is kept when this share of it lies on drawn pixels
    DIM_STEP = 2 unless const_defined?(:DIM_STEP, false)               # 16:33 ("סליחה, רק חצי"): numbers to the half inch, no finer (16 = the sixteenth, as before)
    ROW_GAP = 0.4 unless const_defined?(:ROW_GAP, false)   # paper inches between two walls, past their heights
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

      # a window's own entities: a group's, or a component's definition's (a window is turned into
      # a component when it is built - window_tool.rb, 'Window To Component'). nil = neither.
      def window_entities(ent)
        return ent.entities if ent.respond_to?(:entities)
        return ent.definition.entities if ent.respond_to?(:definition) && ent.definition.respond_to?(:entities)
        nil
      end

      # where a window is cut from above (USE_WINDOW_MIDCUT): the middle of its own height, from
      # the bottom_z / top_z it carries (world inches); without them, PLAN_CUT over the floor
      def window_mid_z(ent, base_z)
        z0 = ent.get_attribute(D, 'bottom_z')
        z1 = ent.get_attribute(D, 'top_z')
        return (z0.to_f + z1.to_f) / 2.0 if z0 && z1 && z1.to_f > z0.to_f
        base_z + PLAN_CUT
      end

      # ---- the lines of a picture, as numbers (USE_ELEV_SNAPS) ------------------

      # the file beside a picture that holds its lines
      def snaps_file(path)
        path.to_s.sub(/\.png\z/i, '') + '.snaps.json'
      end

      # every edge that is drawn: not hidden, not soft, its tag on, its group not put aside
      # (the things set aside for the shot are hidden by then). World points.
      def model_edges(ents, xf = Geom::Transformation.new, out = [], depth = 0)
        ents.each do |e|
          if e.is_a?(Sketchup::Edge)
            next if e.hidden? || e.soft? || !e.layer.visible?
            out << [e.start.position.transform(xf), e.end.position.transform(xf)]
          elsif e.is_a?(Sketchup::Group) || (defined?(Sketchup::ComponentInstance) && e.is_a?(Sketchup::ComponentInstance))
            next if e.hidden? || !e.layer.visible? || depth > 8
            kids = e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
            model_edges(kids, xf * e.transformation, out, depth + 1)
          end
        end
        out
      end

      # the edges in front of one wall, within its cut, laid on its picture: [u1, v1, u2, v2] -
      # u from the picture's left (side.b), v from its bottom, as dims_for lays them. Pure.
      def side_segs(side, cut, wall_h, base_z, edges)
        len = side.len.to_f
        wh = wall_h.to_f
        dir = Geom::Vector3d.new(side.b.x - side.a.x, side.b.y - side.a.y, 0)
        dir.normalize!
        n = side.inward
        pw = len + 2 * MARGIN
        ph = wh + 2 * MARGIN
        out = []
        edges.each do |p, q|
          ip = (p.x - side.a.x) * n.x + (p.y - side.a.y) * n.y
          iq = (q.x - side.a.x) * n.x + (q.y - side.a.y) * n.y
          next if [ip, iq].max < -0.5 || [ip, iq].min > cut.to_f
          ap = (p.x - side.a.x) * dir.x + (p.y - side.a.y) * dir.y
          aq = (q.x - side.a.x) * dir.x + (q.y - side.a.y) * dir.y
          next if [ap, aq].max < -0.5 || [ap, aq].min > len + 0.5
          zp = p.z - base_z
          zq = q.z - base_z
          next if [zp, zq].max < -0.5 || [zp, zq].min > wh + 0.5
          next if (ap - aq).abs < 0.05 && (zp - zq).abs < 0.05     # seen end-on: a point
          out << [(MARGIN + len - ap) / pw, (MARGIN + zp) / ph, (MARGIN + len - aq) / pw, (MARGIN + zq) / ph].map { |x| x.round(5) }
        end
        out.uniq
      end

      # Only the lines the picture really shows: five points along each, each looked up in the
      # picture (a dark pixel within 2 px). The rows may run either way - both are tried, the
      # better kept, and the trace says which. Returns [kept, 'rows top-down 96%'].
      def seen_segs(path, segs)
        return [segs, 'no picture reader'] unless defined?(Sketchup::ImageRep)
        rep = Sketchup::ImageRep.new
        rep.load_file(path)
        w = rep.width
        h = rep.height
        bpp = rep.bits_per_pixel / 8
        return [segs, "#{bpp * 8} bit picture, not read"] unless bpp >= 3
        row = w * bpp + rep.row_padding.to_i
        data = rep.data
        dark = lambda do |x, y|
          return false if x < 0 || y < 0 || x >= w || y >= h
          o = y * row + x * bpp
          bs = data.byteslice(o, bpp).bytes.sort
          (bs[0] + bs[1] + bs[2]) < 3 * 128
        end
        near = ->(x, y) { [-2, 0, 2].any? { |dx| [-2, 0, 2].any? { |dy| dark.call(x + dx, y + dy) } } }
        score = lambda do |seg, down|
          u1, v1, u2, v2 = seg
          (0...5).count do |k|
            t = (k + 0.5) / 5.0
            u = u1 + (u2 - u1) * t
            v = v1 + (v2 - v1) * t
            y = down ? ((1.0 - v) * h).floor : (v * h).floor
            near.call((u * w).floor, y)
          end
        end
        need = (5 * SNAP_SEEN).ceil
        sample = segs.each_slice([segs.size / 300, 1].max).map(&:first)
        down = sample.count { |sg| score.call(sg, true) >= need } >= sample.count { |sg| score.call(sg, false) >= need }
        kept = segs.select { |sg| score.call(sg, down) >= need }
        pct = segs.empty? ? 0 : (100.0 * kept.size / segs.size).round
        [kept, "rows #{down ? 'top-down' : 'bottom-up'} #{pct}%"]
      end

      def set_aside?(type)
        SET_ASIDE.include?(type.to_s)
      end

      # ---- the layers of a picture (USE_ELEV_LAYERS) ----------------------------

      def layers_file(path)
        path.to_s.sub(/\.png\z/i, '') + '.layers.json'
      end

      # the name of the picture taken with those things off: <picture>__no_plumbing+tile.png
      def variant_key(cats)
        cats.map(&:to_s).sort.join('+')
      end

      def variant_file(path, cats)
        path.to_s.sub(/\.png\z/i, '') + "__no_#{variant_key(cats)}.png"
      end

      # every mix of the categories, one at least: [[a], [b], [a, b]] (sorted, small first). Pure.
      def cat_mixes(cats)
        cs = cats.map(&:to_s).sort
        (1..cs.size).flat_map { |n| cs.combination(n).to_a }
      end

      def cat_of(type)
        CAT_TYPES.each { |c, ts| return c if ts.include?(type.to_s) }
        nil
      end

      # the things of each category that stand in front of one wall (within its cut) - a box test. SketchUp.
      def side_cats(side, cut, all)
        dir = Geom::Vector3d.new(side.b.x - side.a.x, side.b.y - side.a.y, 0)
        dir.normalize!
        n = side.inward
        out = Hash.new { |h, k| h[k] = [] }
        all.each do |t|
          c = cat_of(t.type)
          next unless c
          next if set_aside?(t.type)
          pts = world_box(t) rescue nil
          next unless pts
          ins = pts.map { |p| (p.x - side.a.x) * n.x + (p.y - side.a.y) * n.y }
          als = pts.map { |p| (p.x - side.a.x) * dir.x + (p.y - side.a.y) * dir.y }
          next if ins.max < -1.0 || ins.min > cut.to_f
          next if als.max <= 0 || als.min >= side.len
          out[c] << t
        end
        out
      end

      # the things of each category inside the room's outline (the view from above)
      def room_cats(poly, all)
        out = Hash.new { |h, k| h[k] = [] }
        all.each do |t|
          c = cat_of(t.type)
          next unless c
          next if TOP_ASIDE.include?(t.type)
          w = world_centre(t)
          out[c] << t if w && inside?(poly, w.x, w.y)
        end
        out
      end

      # The same shot again with each mix of the categories hidden, and the file that names them.
      # The view, the plane and everything else stay as they are. Returns how many were written.
      # mixes: only these (shoot! only:, USE_LAZY_LAYERS) - added to what the file already names; nil = every mix.
      # meta: what it takes to take the same shot again later (room, side, cut, style).
      def shoot_variants!(view, path, w_px, h_px, cats, mixes = nil, meta = {})
        return 0 unless USE_ELEV_LAYERS
        lf = layers_file(path)
        present = cats.keys.select { |c| cats[c].any? }.sort
        if present.empty?
          File.delete(lf) if File.file?(lf)
          return 0
        end
        old = read_layers(path) || {}
        files = mixes ? (old['files'].is_a?(Hash) ? old['files'].dup : {}) : {}
        ms = []
        want = mixes ? mixes.map { |m| m.map(&:to_s).sort } & cat_mixes(present) : cat_mixes(present)
        want.each do |mix|
          gone = mix.flat_map { |c| cats[c] }.map(&:ent).select { |e| e.respond_to?(:hidden=) && !e.hidden? }
          t0 = Time.now
          gone.each { |e| e.hidden = true }
          begin
            t1 = Time.now
            view.refresh
            t2 = Time.now
            vp = variant_file(path, mix)
            ok = view.write_image(vp, w_px, h_px, VARIANT_AA)
            t3 = Time.now
            files[variant_key(mix)] = File.basename(vp) if ok
            ms << "#{variant_key(mix)} hide #{((t1 - t0) * 1000).round} refresh #{((t2 - t1) * 1000).round} write #{((t3 - t2) * 1000).round}"
          ensure
            gone.each { |e| e.hidden = false if e.valid? }
          end
        end
        view.refresh
        keep = old.select { |k, _| %w[room room_pid side cut style].include?(k) }.merge(meta)
        File.write(lf, JSON.generate(keep.merge('cats' => present, 'files' => files)))
        trace("#{File.basename(path)}: layers #{present.join(', ')} - #{ms.size} pictures without them (ms: #{ms.join('; ')})")
        ms.size
      rescue StandardError => e
        trace("#{File.basename(path)}: layers NOT taken - #{e.class}: #{e.message}")
        0
      end

      def read_layers(path)
        lf = layers_file(path)
        File.file?(lf) ? JSON.parse(File.read(lf)) : nil
      rescue StandardError
        nil
      end

      # USE_LAZY_LAYERS: the button only writes down which layers stand in front of the picture, and how to take it
      # again - no pictures; the ones of the shot before go (they show the room as it WAS).
      def write_layers_index!(path, cats, meta)
        return 0 unless USE_ELEV_LAYERS
        lf = layers_file(path)
        old = read_layers(path)
        dir = File.dirname(path.to_s)
        Array(old && old['files'] && old['files'].values).each do |f|
          fp = File.join(dir, f.to_s)
          File.delete(fp) if File.file?(fp)
        end
        present = cats.keys.select { |c| cats[c].any? }.sort
        if present.empty?
          File.delete(lf) if File.file?(lf)
          return 0
        end
        File.write(lf, JSON.generate(meta.merge('cats' => present, 'files' => {})))
        trace("#{File.basename(path)}: layers #{present.join(', ')} written down - their pictures when they are switched off")
        present.size
      rescue StandardError => e
        trace("#{File.basename(path)}: layers NOT written down - #{e.class}: #{e.message}")
        0
      end

      # The pictures without a layer that are wanted and not there: need = [[picture path, [cats]]]. Each room is taken
      # again with shoot! only: - its own walls, its own cut, only those mixes. Returns how many were taken.
      def ensure_variants!(need, model = Sketchup.active_model)
        made = 0
        rs = nil
        need.group_by { |p, _| (read_layers(p) || {})['room'].to_s }.each do |rn, items|
          info = read_layers(items.first[0]) || {}
          rs ||= rooms(model)
          room = rs.find { |r| info['room_pid'] && r.ent.respond_to?(:persistent_id) && r.ent.persistent_id == info['room_pid'] } ||
                 rs.find { |r| room_name(r) == rn }
          unless room
            trace("layers: room #{rn.inspect} not found - #{items.size} pictures not taken")
            next
          end
          only = Hash.new { |h, k| h[k] = [] }
          cuts = {}
          style = 'lines'
          items.each do |p, mix|
            inf = read_layers(p) || {}
            sd = inf['side'].to_s
            next if sd.empty?
            m = Array(mix).map(&:to_s).sort
            only[sd] << m unless only[sd].include?(m)
            cuts[sd] = inf['cut'] if inf['cut']
            style = inf['style'].to_s unless inf['style'].to_s.empty?
          end
          next if only.empty?
          t0 = Time.now
          shoot!(room, cut: { 'walls' => cuts }, style: style, model: model, only: only, label: (rn == KITCHEN_LABEL ? KITCHEN_LABEL : nil))
          n = only.values.map(&:size).sum
          made += n
          trace("layers: #{rn} - #{n} pictures taken on demand (#{only.map { |k, v| "#{k}: #{v.map { |x| x.join('+') }.join(', ')}" }.join('; ')}) in #{((Time.now - t0) * 1000).round} ms")
        end
        made
      end

      # A white face under each swinging leaf's quarter circle (18:12: "הטקסטורה של הרצפה לא עוברת
      # דרכה") - the same hinge, latch and sweep plan_generator draws the arc with. SketchUp only.
      def swing_faces(pg, ents, d, bodies)
        bodies.each do |b|
          kind = pg.send(:door_kind, b)
          next unless %i[single double].include?(kind)
          span = pg.send(:opening_span, d, b)
          next unless span
          x1, x2 = span
          # (19:10, measured - debug_swing_faces.rb: JAMB_W is written inside PlanGenerator's `class << self`,
          # so reading it off the module raised NameError and the rescue below swallowed it: no white face was ever made)
          jw = pg.singleton_class.const_defined?(:JAMB_W) ? pg.singleton_class::JAMB_W : 1.5
          ss = pg.send(:swing_sign, b)
          edge = ss > 0 ? d[:off_pos] : d[:off_neg]
          leaves = if kind == :double
                     xm = (x1 + x2) / 2.0
                     [[x1 + jw, xm], [x2 - jw, xm]]
                   elsif b[:swing] == 'right'
                     [[x2 - jw, x1 + jw]]
                   else
                     [[x1 + jw, x2 - jw]]
                   end
          leaves.each do |hx, lx|
            len = (lx - hx).abs
            next if len < 4.0
            hinge = pg.send(:lpt, d, hx, edge)
            latch = pg.send(:lpt, d, lx, edge)
            v0 = latch - hinge
            leaf_end = hinge.offset(d[:n], ss * len)
            v1 = leaf_end - hinge
            sweep = Math.atan2(v0.x * v1.y - v0.y * v1.x, v0.x * v1.x + v0.y * v1.y)
            pts = [hinge] + (0..14).map do |i|
              a = sweep * i / 14
              Geom::Point3d.new(hinge.x + v0.x * Math.cos(a) - v0.y * Math.sin(a), hinge.y + v0.x * Math.sin(a) + v0.y * Math.cos(a), 0)
            end
            world = pts.map { |q| pg.send(:flat_world, q, d[:xform]) }
            # (19:16, his picture: "ביקשתי רק בדלת עצמה") - only the leaf is white; the floor shows inside the
            # swing (USE_SWING_FACE off; on = white under the quarter circle too)
            faces = USE_SWING_FACE ? [world] : []
            # (19:01, his picture: a grout line ran through the leaf itself) - the leaf's own rectangle,
            # the one draw_swing_leaf outlines (1.5" along the wall from the hinge, the leaf's length
            # into the room), gets a white face too (USE_LEAF_FACE)
            if USE_LEAF_FACE
              dir = lx > hx ? 1.0 : -1.0
              ua, ub = [hx, hx + dir * 1.5].minmax
              faces << [[ua, edge], [ub, edge], [ub, edge + ss * len], [ua, edge + ss * len]].map { |a, o| pg.send(:flat_world, pg.send(:lpt, d, a, o), d[:xform]) }
            end
            faces.each do |corners|
              f = ents.add_face(corners) rescue nil
              next unless f
              white = Sketchup.active_model.materials['InteriorPro_Plan_White'] || Sketchup.active_model.materials.add('InteriorPro_Plan_White')
              white.color = Sketchup::Color.new(255, 255, 255)
              f.material = white
              f.back_material = white
            end
          end
        end
      rescue StandardError => e
        puts "[Elevation] swing faces: #{e.message}"
        trace("swing faces NOT made - #{e.class}: #{e.message}")
      end

      # Where the camera and the plane stand for the view from above (USE_TOP_VIEW). Pure.
      # North (the green axis) is up the picture, as on the plan.
      # (16:27: "זה חייב להיות מגובה התקרה למטה ולא כמו הקירות") - the cut is just under the ceiling,
      # so everything in the room is seen: wall_h is the room's height; nil = PLAN_CUT, the old way
      def top_shot(poly, base_z, wall_h = nil)
        xs = poly.map(&:x)
        ys = poly.map(&:y)
        w = xs.max - xs.min
        d = ys.max - ys.min
        cx = (xs.max + xs.min) / 2.0
        cy = (ys.max + ys.min) / 2.0
        z = base_z + (wall_h.to_f > 1.0 ? wall_h.to_f - 0.5 : PLAN_CUT)
        w_px = ((w + 2 * MARGIN) * PX_PER_IN).round
        h_px = ((d + 2 * MARGIN) * PX_PER_IN).round
        if [w_px, h_px].max > MAX_PX
          f = MAX_PX / [w_px, h_px].max.to_f
          w_px = (w_px * f).round
          h_px = (h_px * f).round
        end
        { eye: Geom::Point3d.new(cx, cy, z - 0.5), target: Geom::Point3d.new(cx, cy, base_z),
          up: Geom::Vector3d.new(0, 1, 0), plane_pt: Geom::Point3d.new(cx, cy, z), normal: Geom::Vector3d.new(0, 0, -1),
          height: d + 2 * MARGIN, w_px: w_px, h_px: h_px }
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
      def side_items(side, cut, all, base_z, kitchen = nil)
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
          when 'electrical'
            next unless USE_ELEC_DIMS
            it = elec_point(t, all, al, inn, side.len, base_z)
            out << it if it
          when 'fixture', 'tile_wall'
            pts = world_box(t)
            next unless pts
            ins = pts.map { |p| inn.call(p) }
            als = pts.map { |p| al.call(p) }
            if t.type == 'fixture'
              next if ins.max < -1.0 || ins.min > cut
              # (16:05, measured: the shower set on the North wall got numbers on the East wall,
              # seen side-on 16" in) - clean numbers belong to the wall the thing stands on
              next if USE_CLEAN_DIMS && ins.min > ON_WALL
              # 16:25, his words: "תעשה במידות מספרים שלמים כמו המידות שאני מכניס בגבהים בכלי" - a set's
              # numbers are the ones he TYPED (its height a part, its line from the corner), read off the
              # fixture itself and its wall; the box's middles only when they cannot be read
              typed = USE_PART_MIDDLES && USE_TYPED_DIMS ? typed_parts(t, all, al, inn, side.len, base_z) : nil
              if typed
                out.concat(typed)
                next
              end
              parts = USE_PART_MIDDLES ? part_boxes(t) : nil
              if parts
                names = part_names(t)
                parts.each_with_index do |pp, pi|
                  am = pp.map { |p| al.call(p) }
                  am = (am.min + am.max) / 2.0
                  next if am <= 0 || am >= side.len
                  zm = (pp.map(&:z).min + pp.map(&:z).max) / 2.0 - base_z
                  out << { kind: 'part', a0: am, a1: am, z0: zm, z1: zm, fix: t.ent.object_id, name: names[pi].to_s }
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
        out.concat(kitchen_items(side, kitchen, base_z)) if USE_KITCHEN_DIMS && kitchen
        out
      end

      def safely_items(side, cut, all, base_z, kitchen = nil)
        side_items(side, cut, all, base_z, kitchen)
      rescue StandardError => e
        puts "[Elevation] dimensions skipped on #{side.name}: #{e.class}: #{e.message}"
        []
      end

      # the frame of a side's face, as ElectricalLibrary.box_in_frame takes it
      def side_frame(side, base_z)
        { ox: side.a.x, oy: side.a.y, ux: (side.b.x - side.a.x) / side.len, uy: (side.b.y - side.a.y) / side.len,
          nx: side.inward.x, ny: side.inward.y, floor_z: base_z }
      end

      # the cabinet group of a kitchen unit (the unit itself when it is one)
      def kitchen_cab(e)
        return e if e.get_attribute(KITCHEN_DICT, 'kind').to_s == 'cabinet'
        kids = e.respond_to?(:entities) ? e.entities : (e.respond_to?(:definition) ? e.definition.entities : [])
        kids.find { |k| k.respond_to?(:get_attribute) && k.get_attribute(KITCHEN_DICT, 'kind').to_s == 'cabinet' }
      rescue StandardError
        nil
      end

      # which way a kitchen unit's BACK looks, flat, in the world (its cabinet's +y); nil = a corner one (both walls) or none
      def kitchen_back(e, wxf)
        c = kitchen_cab(e)
        return nil unless c
        d = (JSON.parse(c.get_attribute(KITCHEN_DICT, 'data').to_s) rescue {})
        return nil if d.is_a?(Hash) && d['kind'].to_s.start_with?('corner')
        xf = c.equal?(e) ? wxf : wxf * c.transformation
        v = Geom::Vector3d.new(0, 1, 0).transform(xf)
        l = Math.hypot(v.x, v.y)
        l > 0.5 ? Geom::Vector3d.new(v.x / l, v.y / l, 0) : nil
      rescue StandardError
        nil
      end

      # a kitchen unit standing ON this side: its box at the face and along it, and (USE_KITCHEN_FACING) its back to it.
      # [u0, u1, z0, z1] in the side's numbers; nil = not on it. PURE apart from the box.
      def kitchen_on(side, e, wxf, fr)
        u0, u1, z0, z1, o0, = InteriorPro::ElectricalLibrary.box_in_frame(e, wxf, fr)
        return nil unless o0 <= ON_WALL_PIC && o0 > -ON_WALL_PIC
        return nil if [u1, side.len].min - [u0, 0.0].max <= 0
        if USE_KITCHEN_FACING
          b = kitchen_back(e, wxf)
          return nil if b && b.x * side.inward.x + b.y * side.inward.y > -0.7
        end
        [u0, u1, z0, z1]
      end

      # Body dimensions exclude crown and accessories; compound appliance surrounds keep their envelope.
      def kitchen_body_heights(e, wxf, fr, fallback)
        return fallback unless USE_KITCHEN_BODY_HEIGHTS
        c = kitchen_cab(e)
        return fallback unless c
        d = JSON.parse(c.get_attribute(KITCHEN_DICT, 'data').to_s)
        return fallback unless %w[doors drawers sink tall wall glass_wall corner_upper corner_base].include?(d['kind'].to_s)
        h = Float(d['height'])
        return fallback unless h.finite? && h > 0
        xf = c.equal?(e) ? wxf : wxf * c.transformation
        zs = [0.0, h].map { |z| Geom::Point3d.new(0, 0, z).transform(xf).z - fr[:floor_z] }
        zs.minmax
      rescue StandardError
        fallback
      end

      # Top-plan symbols only; caller's aborted capture operation restores all geometry/visibility.
      def kitchen_upper_outline(d)
        return [] unless %w[wall glass_wall corner_upper].include?(d['kind'].to_s)
        return [] if d['surround_part'] || d['z'].to_f < UPPER_Z
        w = d['width'].to_f; depth = d['depth'].to_f
        return [] unless w.finite? && depth.finite? && w > 0 && depth > 0
        d['kind'] == 'corner_upper' ? [[0,0],[w,0],[w,-depth],[depth,-depth],[depth,-w],[0,-w]] :
          [[0,0],[w,0],[w,-depth],[0,-depth]]
      end

      def kitchen_dash_ranges(length, dash = 2.0, gap = 1.0)
        return [] unless length.finite? && length > 0 && dash > 0 && gap > 0
        out = []; pos = 0.0
        while pos < length - 0.001
          out << [pos, [pos + dash, length].min]
          pos += dash + gap
        end
        out
      end

      # Cabinet footprints, independent of the worktop skin that covers base units.
      # Plan dimensions use the same editable vector dimension shapes as the elevations.
      # Inner chain = base/tall units; outer chain = upper cabinets and hood.
      def kitchen_plan_dimension_rows(poly, kitchen, base_z)
        return [] unless USE_KITCHEN_PLAN_DIMS
        xs=poly.map(&:x);ys=poly.map(&:y)
        x0=xs.min-MARGIN;y0=ys.min-MARGIN
        w=xs.max-xs.min+2*MARGIN;h=ys.max-ys.min+2*MARGIN
        uv=->(p){[(p.x-x0)/w,(p.y-y0)/h]}
        views=sides(poly)+kitchen_island_views(poly,kitchen,base_z).select{|s|s.name =~ /Island(?:Front|Right)/}
        out=[]
        views.each do |side|
          fr=side_frame(side,base_z)
          # The current plan renderer's dimensions are horizontal or vertical.
          next unless fr[:ux].abs<0.001 || fr[:uy].abs<0.001
          levels={'base'=>[],'upper'=>[]}
          kitchen.each do |e,k,xf|
            next unless KITCHEN_WALL_KINDS.include?(k.to_s)
            if kitchen_island?(side)
              next unless side.instance_variable_get(:@kitchen_island)[:ids].include?(e.persistent_id)
              box=InteriorPro::ElectricalLibrary.box_in_frame(e,xf,fr)
            else
              box=kitchen_on(side,e,xf,fr);next unless box
            end
            c=kitchen_cab(e);next unless c
            d=JSON.parse(c.get_attribute(KITCHEN_DICT,'data').to_s) rescue nil
            next unless d.is_a?(Hash)
            level=%w[wall glass_wall corner_upper hood].include?(d['kind'].to_s) ? 'upper' : 'base'
            a,b=box
            levels[level]<<[[a,0].max,[b,side.len].min]
          end
          levels.each_with_index do |(level,intervals),row|
            stops=intervals.flatten.sort.each_with_object([]){|x,a|a<<x if a.empty? || x-a.last>0.125}
            next if stops.size<2
            offset=18.0+row*18.0
            stops.each_cons(2) do |a,b|
              next if b-a<0.5
              pa=Geom::Point3d.new(side.a.x+fr[:ux]*a,side.a.y+fr[:uy]*a,base_z)
              pb=Geom::Point3d.new(side.a.x+fr[:ux]*b,side.a.y+fr[:uy]*b,base_z)
              line=pa.offset(side.inward,-offset)
              aa=uv.call(pa);bb=uv.call(pb);ll=uv.call(line)
              horizontal=fr[:uy].abs<0.001
              out<<{'k'=>'f','p'=>aa+bb,'o'=>horizontal ? 'h' : 'v','at'=>ll[horizontal ? 1 : 0],
                    't'=>fmt_in(b-a),'g'=>'kitchen','cabinet_level'=>level,'wall'=>side.name}
            end
          end
        end
        out
      end

      def kitchen_plan_outline(d)
        w = d['width'].to_f; depth = d['depth'].to_f
        return [] unless w.finite? && depth.finite? && w > 0 && depth > 0
        return [] unless %w[doors drawers sink wall glass_wall tall fridge oven wall_oven dishwasher oven_tower micro_tower fridge_surround filler corner hood microwave corner_base corner_upper corner_lazy pullout_spice pullout_waste pullout_storage].include?(d['kind'].to_s)
        %w[corner_base corner_lazy corner_upper].include?(d['kind'].to_s) ?
          [[0,0],[w,0],[w,-depth],[depth,-depth],[depth,-w],[0,-w]] :
          [[0,0],[w,0],[w,-depth],[0,-depth]]
      end

      def kitchen_cabinet_plan!(model, kitchen, draw_z)
        return kitchen_upper_plan!(model, kitchen, draw_z) unless USE_KITCHEN_CABINET_PLAN
        count = 0
        Array(kitchen).each do |e, kind, wxf|
          next unless e.valid? && !e.hidden? && KITCHEN_WALL_KINDS.include?(kind.to_s)
          c = kitchen_cab(e); next unless c
          d = JSON.parse(c.get_attribute(KITCHEN_DICT, 'data').to_s) rescue nil
          next unless d.is_a?(Hash)
          points = kitchen_plan_outline(d); next if points.empty?
          upper = %w[wall glass_wall corner_upper hood].include?(d['kind'].to_s)
          xf = c.equal?(e) ? wxf : wxf * c.transformation
          points = points.map { |x,y| p = Geom::Point3d.new(x,y,0).transform(xf); Geom::Point3d.new(p.x,p.y,draw_z) }
          g = model.entities.add_group
          g.name = upper ? 'Kitchen upper plan outline (temporary)' : 'Kitchen base plan outline (temporary)'
          (points + [points.first]).each_cons(2) do |a,b|
            if upper
              vec = b - a
              kitchen_dash_ranges(vec.length.to_f).each { |p,q| g.entities.add_line(a.offset(vec,p), a.offset(vec,q)) }
            else
              g.entities.add_line(a,b)
            end
          end
          # Upper cabinets and hood covers must not occlude base units, sink or range.
          e.hidden = true if upper
          count += 1
        end
        count
      end

      def kitchen_upper_plan!(model, kitchen, draw_z)
        return 0 unless USE_KITCHEN_UPPER_DASHES
        count = 0
        Array(kitchen).each do |e, _kind, wxf|
          next unless e.valid? && !e.hidden?
          c = kitchen_cab(e); next unless c
          d = JSON.parse(c.get_attribute(KITCHEN_DICT, 'data').to_s) rescue nil
          next unless d.is_a?(Hash)
          points = kitchen_upper_outline(d); next if points.empty?
          xf = c.equal?(e) ? wxf : wxf * c.transformation
          points = points.map { |x,y| p = Geom::Point3d.new(x,y,0).transform(xf); Geom::Point3d.new(p.x,p.y,draw_z) }
          g = model.entities.add_group; g.name = 'Kitchen upper plan outline (temporary)'
          (points + [points.first]).each_cons(2) do |a,b|
            vec = b - a; length = vec.length.to_f
            kitchen_dash_ranges(length).each { |p,q| g.entities.add_line(a.offset(vec,p), a.offset(vec,q)) }
          end
          e.hidden = true
          count += 1
        end
        count
      end

      # the kitchen on this side (USE_KITCHEN_DIMS): every cabinet standing on it ('cabinet', w = its box's width) and the
      # countertop's top ('counter')
      def kitchen_items(side, kitchen, base_z)
        return [] unless defined?(InteriorPro::ElectricalLibrary) && InteriorPro::ElectricalLibrary.respond_to?(:box_in_frame)
        fr = side_frame(side, base_z)
        out = []
        Array(kitchen).each do |e, k, wxf|
          next unless e.valid?
          if KITCHEN_WALL_KINDS.include?(k.to_s)
            r = kitchen_on(side, e, wxf, fr)
            next unless r
            u0, u1, z0, z1 = r
            z0, z1 = kitchen_body_heights(e, wxf, fr, [z0, z1])
            out << { kind: 'cabinet', a0: [u0, 0.0].max, a1: [u1, side.len].min, z0: z0, z1: z1, w: u1 - u0, name: e.name.to_s }
          elsif e.name.to_s =~ /countertop/i
            u0, u1, _z0, z1, o0, = InteriorPro::ElectricalLibrary.box_in_frame(e, wxf, fr)
            next unless o0 <= ON_WALL_PIC && o0 > -ON_WALL_PIC && [u1, side.len].min - [u0, 0.0].max > 0
            out << { kind: 'counter', a0: [u0, 0.0].max, a1: [u1, side.len].min, z0: z1, z1: z1 }
          end
        end
        out
      rescue StandardError => e
        puts "[Elevation] kitchen_items: #{e.class}: #{e.message}"
        []
      end

      # the kitchen's numbers (USE_KITCHEN_DIMS) into out: the chains of widths - the base cabinets under the floor, the
      # upper ones over the ceiling ('up'), from corner to corner (a cabinet's own width, the real distance between) - and
      # the columns of heights by the nearer wall: each set of uppers floor -> counter -> bottom -> top, a tall one floor ->
      # top, the counter's own when no upper column on that side carries it. Returns the rows it took under the floor. PURE.
      def kitchen_dims!(out, items, len, wh, near, col, ux, vz)
        cabs = items.select { |it| it[:kind] == 'cabinet' }
        return 0 if cabs.empty?
        bases = cabs.select { |it| it[:z0].to_f < UPPER_Z }
        ups = cabs.select { |it| it[:z0].to_f >= UPPER_Z }
        chain = lambda do |list|
          stops = [0.0, len]
          list.each { |it| stops << it[:a0].to_f << it[:a1].to_f }
          run = []
          stops.map { |a| [[a, 0.0].max, len].min }.sort.each { |a| run << a if run.empty? || a - run.last > DIM_MIN }
          run[-1] = len
          run.each_cons(2).map do |p, q|
            [p, q, list.find { |c| (c[:a0].to_f - p).abs <= DIM_MIN && (c[:a1].to_f - q).abs <= DIM_MIN }]
          end
        end
        rows = 0
        if bases.any?
          rows = 1
          chain.call(bases).reverse.each do |p, q, it|      # left to right as the picture shows it
            out << { 'k' => 'h', 'row' => 1, 'u' => [ux.call(q), ux.call(p)], 'v' => vz.call(0.0),
                     't' => fmt_in(it ? it[:w] : q - p), 'g' => 'kitchen' }
          end
        end
        if ups.any?
          top = lambda do |a|
            zs = ups.select { |c| (c[:a0].to_f - a).abs <= DIM_MIN || (c[:a1].to_f - a).abs <= DIM_MIN }.map { |c| c[:z1].to_f }
            zs.empty? ? nil : vz.call(zs.max)
          end
          chain.call(ups).reverse.each do |p, q, it|
            d = { 'k' => 'h', 'row' => 1, 'up' => true, 'u' => [ux.call(q), ux.call(p)], 'v' => vz.call(wh),
                  't' => fmt_in(it ? it[:w] : q - p), 'g' => 'kitchen' }
            r = [top.call(q), top.call(p)]
            d['r'] = r if r.any?
            out << d
          end
        end
        mid = ->(cs) { cs.sum { |c| (c[:a0].to_f + c[:a1].to_f) / 2.0 } / cs.size }
        ctop = items.select { |it| it[:kind] == 'counter' }.map { |it| it[:z1].to_f }.max
        ctop ||= bases.reject { |c| c[:z1].to_f >= TALL_Z }.map { |c| c[:z1].to_f }.max
        used = {}
        ups.group_by { |c| [c[:z0].to_f.round(1), c[:z1].to_f.round(1)] }.each do |(z0, z1), cs|
          sd = near.call(mid.call(cs))
          zs = ctop && ctop < z0 - DIM_MIN ? [0.0, ctop, z0, z1] : [0.0, z0, z1]
          col.call(sd, zs, nil, 'kitchen')
          used[sd] = true if ctop && zs.include?(ctop)
        end
        bases.select { |c| c[:z1].to_f >= TALL_Z }.group_by { |c| c[:z1].to_f.round(1) }.each do |z1, cs|
          col.call(near.call(mid.call(cs)), [0.0, z1], nil, 'kitchen')
        end
        if ctop && bases.any?
          sd = near.call(mid.call(bases))
          col.call(sd, [0.0, ctop], nil, 'kitchen') unless used[sd]
        end
        rows
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

      # A set's parts at the numbers he typed (USE_TYPED_DIMS): each part that is on, at its pipe
      # point - `h` up from the floor, `u_in` + its `side` along the wall's face. nil when the
      # fixture carries no such numbers or its wall is not in the room.
      def typed_parts(t, all, al, inn, len, base_z)
        return nil unless defined?(InteriorPro::FixtureLibrary) && defined?(InteriorPro::TileWall)
        cfg = JSON.parse(t.ent.get_attribute(D, 'cfg_json').to_s) rescue nil
        return nil unless cfg.is_a?(Hash) && cfg['parts'].is_a?(Hash)
        wid = t.ent.get_attribute(D, 'host_wall_id').to_s
        w = all.find { |x| x.type == 'wall' && x.ent.get_attribute(D, 'id').to_s == wid }
        return nil unless w
        fr = InteriorPro::TileWall.frame_for(w.ent, t.ent.get_attribute(D, 'side').to_s)
        return nil unless fr
        outer = w.xf * w.ent.transformation.inverse
        u = t.ent.get_attribute(D, 'u_in').to_f
        out = []
        cfg['parts'].each do |k, pc|
          next unless pc.is_a?(Hash) && pc['on']
          p = Geom::Point3d.new(*InteriorPro::TileWall.world(fr, u + pc['side'].to_f, pc['h'].to_f)).transform(outer)
          next unless inn.call(p).abs <= ON_WALL
          a = al.call(p)
          next if a <= 0 || a >= len
          z = p.z - base_z
          out << { kind: 'part', a0: a, a1: a, z0: z, z1: z, fix: t.ent.object_id, name: k.to_s }
        end
        out.empty? ? nil : out
      end

      # The things that are NOT in this room (USE_ROOM_ONLY): their middle outside its outline. Walls, doors and
      # windows are never put aside (the corner walls are the picture's frame). PURE apart from the boxes.
      def outside_room(poly, all, wall_ids = nil)
        ids = Array(wall_ids)
        all.reject do |t|
          next true if TOP_ASIDE.include?(t.type) || set_aside?(t.type)
          if ROOM_ONLY_KEEP.include?(t.type)
            next true unless USE_ROOM_ONLY_FRAME
            next !foreign_frame?(poly, t, ids)
          end
          c = world_centre(t)
          c.nil? || inside?(poly, c.x, c.y)
        end
      end

      # the things NOT on this wall (USE_ON_WALL_ONLY): our Things (walls, doors, windows and the ones already aside
      # excepted) and the top-level kitchen groups whose box starts more than ON_WALL_PIC off the wall's face. Returns
      # entities. PURE apart from the boxes.
      def off_wall(side, all, kitchen, base_z)
        return [] unless defined?(InteriorPro::ElectricalLibrary) && InteriorPro::ElectricalLibrary.respond_to?(:box_in_frame)
        ux = (side.b.x - side.a.x) / side.len
        uy = (side.b.y - side.a.y) / side.len
        fr = { ox: side.a.x, oy: side.a.y, ux: ux, uy: uy, nx: side.inward.x, ny: side.inward.y, floor_z: base_z }
        pairs = all.reject { |t| ROOM_ONLY_KEEP.include?(t.type) || TOP_ASIDE.include?(t.type) || set_aside?(t.type) }
                   .map { |t| [t.ent, t.xf] }
        pairs += Array(kitchen).map { |e, _k, wxf| [e, wxf] }
        out = pairs.select do |e, wxf|
          next false unless e.valid?
          o0 = InteriorPro::ElectricalLibrary.box_in_frame(e, wxf, fr)[4]
          o0 > ON_WALL_PIC
        end.map(&:first)
        if USE_WORKTOP_PIECES
          Array(kitchen).each do |e, k, wxf|
            next unless k.to_s == 'worktop' && e.valid? && !out.include?(e)
            kids = e.respond_to?(:definition) ? e.definition.entities : e.entities
            kids.each do |c|
              next unless c.respond_to?(:bounds) && c.respond_to?(:transformation) && c.respond_to?(:hidden=)
              next if c.respond_to?(:valid?) && !c.valid?
              next if defined?(Sketchup::Edge) && c.is_a?(Sketchup::Edge)
              next if defined?(Sketchup::Face) && c.is_a?(Sketchup::Face)
              out << c if InteriorPro::ElectricalLibrary.box_in_frame(c, wxf * c.transformation, fr)[4] > ON_WALL_PIC
            end
          end
        end
        out
      rescue StandardError => e
        puts "[Elevation] off_wall: #{e.class}: #{e.message}"
        []
      end

      # the top-level kitchen groups with their world transformation: [[ent, kind, xf], ...]
      # Keep wall elevations large; each island gets its own four-view sheet.
      def kitchen_add_sheets!(paths, dims)
        island, walls = paths.partition { |p| File.basename(p).match?(/_Island(?:Front|Right|Back|Left)\d+_/) }
        count = walls.empty? ? 0 : add_room_sheet!(walls, KITCHEN_LABEL, dims.slice(*walls))
        island.group_by { |p| File.basename(p)[/_Island[A-Za-z]+(\d+)_/, 1] }.each do |id, views|
          count += add_room_sheet!(views, "#{KITCHEN_LABEL} - Island #{id}", dims.slice(*views))
        end
        count
      end

      def kitchen_world_points(e, xf)
        outer = xf * e.transformation.inverse
        (0..7).map { |i| e.bounds.corner(i).transform(outer) }
      end

      # Ceiling and pendant dimensions can share the ceiling clamp in the room renderer.
      # Give their separate heights separate rows on island views only.
      def kitchen_island_dims(side, wall_h, items)
        dims = dims_for(side, wall_h, items)
        rows = dims.select { |d| d['k'] == 'hi' && d['g'] == 'electric' }
        rows.group_by { |d| d['v'] }.each_value do |same_height|
          same_height.group_by { |d| d['from'] }.values.each_with_index do |row, i|
            row.each { |d| d['v'] -= i * 10.0 / (wall_h + 2 * MARGIN) }
          end
        end
        dims
      end

      def kitchen_island?(side)
        !!side.instance_variable_get(:@kitchen_island)
      end

      # Cabinet groups with no back on a room wall form independent island runs.
      def kitchen_island_views(poly, kit, base_z)
        return [] unless USE_KITCHEN_ISLAND_VIEWS
        wall_sides = sides(poly)
        free = kit.select do |e,k,xf|
          next false unless KITCHEN_WALL_KINDS.include?(k.to_s)
          c = e.bounds.center.transform(xf * e.transformation.inverse)
          next false unless inside?(poly,c.x,c.y)
          kitchen_wall_tag(e) == 'I' || wall_sides.none? { |s| kitchen_on(s,e,xf,side_frame(s,base_z)) }
        end
        clusters = []
        until free.empty?
          run = [free.shift]
          loop do
            near,far = free.partition do |e,k,xf|
              p = kitchen_world_points(e,xf)
              run.any? do |g,_,gx|
                q = kitchen_world_points(g,gx)
                [p.map(&:x).min-q.map(&:x).max,q.map(&:x).min-p.map(&:x).max].max <= 6 &&
                  [p.map(&:y).min-q.map(&:y).max,q.map(&:y).min-p.map(&:y).max].max <= 6
              end
            end
            break if near.empty?
            run.concat(near); free=far
          end
          clusters << run
        end
        clusters.sort_by { |run| run.map { |e,_,_| e.persistent_id }.min }.each_with_index.flat_map do |run,index|
          e,_,xf = run.first; c=kitchen_cab(e); cx=c.equal?(e) ? xf : xf*c.transformation
          axis=cx.xaxis; angle=Math.atan2(axis.y,axis.x)
          basis=Geom::Transformation.rotation(ORIGIN,Z_AXIS,angle); inv=basis.inverse
          pts=run.flat_map { |g,_,gx| kitchen_world_points(g,gx).map { |p| p.transform(inv) } }
          x0,x1=pts.map(&:x).minmax; y0,y1=pts.map(&:y).minmax
          x0-=1.5;x1+=1.5;y0-=1.5;y1+=1.5 # countertop overhang
          rect=[[x0,y1],[x1,y1],[x1,y0],[x0,y0]]
          %w[Front Right Back Left].each_with_index.map do |name,j|
            a=Geom::Point3d.new(*rect[j],base_z).transform(basis)
            b=Geom::Point3d.new(*rect[(j+1)%4],base_z).transform(basis)
            v=b-a; n=Geom::Vector3d.new(v.y,-v.x,0);n.normalize!
            depth=j.even? ? y1-y0 : x1-x0
            s=Side.new("Island#{name}#{index+1}",a,b,a.distance(b),n,depth+4)
            s.instance_variable_set(:@kitchen_island,{ids:run.map { |g,_,_| g.persistent_id },basis:basis,rect:[x0,x1,y0,y1],depth:depth})
            s
          end
        end
      end

      def kitchen_view_sides(poly,kit,base_z)
        sides(poly) + kitchen_island_views(poly,kit,base_z)
      end

      def kitchen_view_cut(side,kit,base_z,requested)
        chosen=cut_for(requested,side.name).to_f
        return chosen if chosen.finite? && chosen>0
        island=side.instance_variable_get(:@kitchen_island)
        return island[:depth]+2 if island
        return nil unless USE_KITCHEN_AUTO_DEPTH
        fr=side_frame(side,base_z)
        depths=kit.filter_map do |e,k,xf|
          next unless KITCHEN_WALL_KINDS.include?(k.to_s) && kitchen_on(side,e,xf,fr)
          InteriorPro::ElectricalLibrary.box_in_frame(e,xf,fr)[5]
        end
        return nil if depths.empty?
        [(depths.max+2).ceil.to_f,side.depth.to_f-0.5].min
      end

      def kitchen_island_contains?(side,e,xf)
        d=side.instance_variable_get(:@kitchen_island);return false unless d
        p=e.bounds.center.transform(xf*e.transformation.inverse).transform(d[:basis].inverse)
        x0,x1,y0,y1=d[:rect]
        p.x>=x0-0.1 && p.x<=x1+0.1 && p.y>=y0-0.1 && p.y<=y1+0.1
      end

      # Isolation is temporary: the existing shoot! transaction restores every hidden entity.
      def kitchen_island_aside(side,all,kit)
        out=all.filter_map do |t|
          keep=%w[electrical fixture].include?(t.type) && kitchen_island_contains?(side,t.ent,t.xf)
          t.ent unless keep
        end
        kit.each do |e,k,xf|
          if k.to_s=='worktop'
            kids=e.entities.grep(Sketchup::Group)
            if kids.empty?
              out<<e unless kitchen_island_contains?(side,e,xf)
            else
              kids.each { |c| out<<c unless kitchen_island_contains?(side,c,xf*c.transformation) }
            end
          elsif !side.instance_variable_get(:@kitchen_island)[:ids].include?(e.persistent_id)
            out<<e
          end
        end
        out.uniq
      end

      def kitchen_island_items(side,kit,all,base_z)
        fr=side_frame(side,base_z);out=[]
        ids=side.instance_variable_get(:@kitchen_island)[:ids]
        kit.each do |e,k,xf|
          next unless ids.include?(e.persistent_id) || (e.name.to_s =~ /countertop/i && kitchen_island_contains?(side,e,xf))
          a,b,z0,z1=InteriorPro::ElectricalLibrary.box_in_frame(e,xf,fr)
          if k.to_s=='worktop'
            out<<{kind:'counter',a0:a,a1:b,z0:z1,z1:z1}
          else
            z0,z1=kitchen_body_heights(e,xf,fr,[z0,z1])
            out<<{kind:'cabinet',a0:[a,0].max,a1:[b,side.len].min,z0:z0,z1:z1,w:b-a,name:e.name}
          end
        end
        all.each do |t|
          next unless %w[electrical fixture].include?(t.type) && kitchen_island_contains?(side,t.ent,t.xf)
          a,b,z0,z1 = InteriorPro::ElectricalLibrary.box_in_frame(t.ent,t.xf,fr)
          mid=(a+b)/2.0; z=(z0+z1)/2.0
          next unless mid.between?(0,side.len)
          if t.type=='electrical'
            out << {kind:'elec',a0:mid,a1:mid,z0:z,z1:z,name:t.ent.get_attribute(D,'kind').to_s,lo:z0,hi:z1,l:a,r:b}
          else
            out << {kind:'part',a0:mid,a1:mid,z0:z,z1:z,fix:t.ent.object_id,name:t.ent.name.to_s}
          end
        end
        out
      end


      def kitchen_tops(model)
        return [] unless defined?(InteriorPro::ElectricalLibrary) && InteriorPro::ElectricalLibrary.respond_to?(:kitchen_pieces)
        InteriorPro::ElectricalLibrary.kitchen_pieces(model).select { |e, _k, _x| e.parent.is_a?(Sketchup::Model) }
      rescue StandardError
        []
      end

      # the kitchen groups (USE_ROOM_ONLY_KITCHEN) whose middle lies outside the room: walks like collect, into plain
      # groups and into kitchen groups that stay (a run of backsplash may cross the line; its parts outside go). Returns
      # Things. PURE apart from the model.
      def outside_kitchen(poly, ents, outer = nil, depth = 0, out = [])
        ents.each do |e|
          next unless e.is_a?(Sketchup::Group) ||
                      (defined?(Sketchup::ComponentInstance) && e.is_a?(Sketchup::ComponentInstance))
          next unless e.valid?
          next if e.get_attribute(D, 'type')                      # ours: outside_room's business
          next if e.respond_to?(:hidden?) && e.hidden?
          xf = outer ? outer * e.transformation : e.transformation
          if e.get_attribute(KITCHEN_DICT, 'kind')
            c = e.bounds.center.transform(outer || Geom::Transformation.new)
            unless inside?(poly, c.x, c.y)
              out << Thing.new(e, xf, 'kitchen')
              next
            end
          end
          next if depth >= NEST_DEPTH
          kids = defined?(Sketchup::ComponentInstance) && e.is_a?(Sketchup::ComponentInstance) ? e.definition.entities : e.entities
          outside_kitchen(poly, kids, xf, depth + 1, out)
        end
        out
      rescue StandardError => e
        puts "[Elevation] outside_kitchen: #{e.class}: #{e.message}"
        out
      end

      # a wall, door or window that is NOT this room's (USE_ROOM_ONLY_FRAME): a wall not among its bounding walls (no
      # list = every wall is kept); a door or window whose middle is farther than FRAME_NEAR from the room's sides
      # (measured to the side itself, not its line - one on the same long wall past the corner is not on it). PURE.
      def foreign_frame?(poly, t, ids)
        if t.type == 'wall'
          return false if ids.empty? || !t.ent.respond_to?(:get_attribute)
          return !ids.include?(t.ent.get_attribute(D, 'id'))
        end
        c = world_centre(t)
        return false if c.nil?
        outline_gap(poly, c.x, c.y) > FRAME_NEAR
      end

      # the distance from a point to the nearest side of the outline (to the side, its ends clamped). PURE.
      def outline_gap(poly, x, y)
        poly.each_with_index.map do |a, i|
          b = poly[(i + 1) % poly.size]
          dx = b.x - a.x
          dy = b.y - a.y
          l2 = dx * dx + dy * dy
          k = l2 > 0 ? [[((x - a.x) * dx + (y - a.y) * dy) / l2, 0.0].max, 1.0].min : 0.0
          Math.hypot(x - (a.x + k * dx), y - (a.y + k * dy))
        end.min
      end

      # The rows of electric distances (USE_ELEC_DIMS, 17:39): the plates at one height, sorted from the wall nearer to
      # the first of them, chained - the wall to the first, the first to the second... Their row runs ELEC_ROW over the
      # tallest plate's top when they sit in the upper half of the wall, else ELEC_ROW under the lowest bottom. PURE.
      def elec_rows(items, len, wh, near, wall_a, ux, vz)
        out = []
        groups = []
        items.sort_by { |it| it[:z1].to_f }.each do |it|
          g = groups.find { |gr| (gr[:z] - it[:z1].to_f).abs <= DIM_MIN }
          g ? g[:items] << it : groups << { z: it[:z1].to_f, items: [it] }
        end
        # USE_ELEC_STACK (2026-10-15): the rows of one half stand past ALL its plates, ELEC_STACK apart - the nearest
        # height nearest the plates
        stack = {}
        if USE_ELEC_STACK
          ups = groups.select { |gr| gr[:z] > wh / 2.0 }.sort_by { |gr| gr[:z] }
          dns = groups.reject { |gr| gr[:z] > wh / 2.0 }.sort_by { |gr| -gr[:z] }
          top = ups.flat_map { |gr| gr[:items].map { |it| (it[:hi] || it[:z1]).to_f } }.max
          bot = dns.flat_map { |gr| gr[:items].map { |it| (it[:lo] || it[:z0]).to_f } }.min
          ups.each_with_index { |gr, i| stack[gr.object_id] = top + ELEC_ROW + i * ELEC_STACK }
          dns.each_with_index { |gr, i| stack[gr.object_id] = bot - ELEC_ROW - i * ELEC_STACK }
        end
        groups.each do |gr|
          its = gr[:items].sort_by { |it| it[:a0].to_f }
          sd = near.call(its.first[:a0].to_f)
          w_a = wall_a.call(sd)
          its = its.reverse if sd == 'L'      # from that wall outward
          zrow = if stack[gr.object_id]
                   stack[gr.object_id]
                 elsif gr[:z] > wh / 2.0
                   its.map { |it| (it[:hi] || it[:z1]).to_f }.max + ELEC_ROW
                 else
                   its.map { |it| (it[:lo] || it[:z0]).to_f }.min - ELEC_ROW
                 end
          zrow = [[zrow, DIM_MIN].max, wh - DIM_MIN].min
          above = gr[:z] > wh / 2.0
          prev = w_a
          its.each do |it|
            am = it[:a0].to_f
            next if (am - prev).abs <= DIM_MIN
            # the witness line starts at the plate's edge (its top for a row over it, its bottom for a row under it) -
            # never through the plate; the words go UNDER a row that runs under the plates (19:40)
            from = above ? (it[:hi] || it[:z1]).to_f : (it[:lo] || it[:z1]).to_f
            d = { 'k' => 'hi', 'u' => [ux.call(prev), ux.call(am)].sort, 'v' => vz.call(zrow), 'from' => vz.call(from),
                  't' => fmt_in((am - prev).abs), 'g' => 'electric' }
            d['below'] = true unless above
            out << d
            prev = am
          end
        end
        out
      end

      # An outlet / switch / wall light at the numbers he typed (USE_ELEC_DIMS): `height_in` up from the floor, `u_in`
      # along its wall's face (ElectricalLibrary.place! writes host_wall_id, side, u_in, height_in, mount). nil for a
      # ceiling kind, a wall not in the room, or a point off this side. PURE apart from the frame.
      def elec_point(t, all, al, inn, len, base_z)
        return nil unless defined?(InteriorPro::TileWall)
        return nil if t.ent.get_attribute(D, 'mount').to_s == 'ceiling'
        wid = t.ent.get_attribute(D, 'host_wall_id').to_s
        w = all.find { |x| x.type == 'wall' && x.ent.get_attribute(D, 'id').to_s == wid }
        return nil unless w
        fr = InteriorPro::TileWall.frame_for(w.ent, t.ent.get_attribute(D, 'side').to_s)
        return nil unless fr
        outer = w.xf * w.ent.transformation.inverse
        p = Geom::Point3d.new(*InteriorPro::TileWall.world(fr, t.ent.get_attribute(D, 'u_in').to_f, t.ent.get_attribute(D, 'height_in').to_f)).transform(outer)
        return nil unless inn.call(p).abs <= ON_WALL
        a = al.call(p)
        return nil if a <= 0 || a >= len
        z = p.z - base_z
        pts = world_box(t)
        zs = pts ? pts.map { |q| q.z - base_z } : [z, z]
        as = pts ? pts.map { |q| al.call(q) } : [a, a]
        # a0/a1 = its line (the typed point); l/r = the plate's edges along the wall, lo/hi = its bottom / top - so no
        # line of a number is ever drawn INTO the plate (19:40, his "שהמוצרים יישארו נקיים שלא ייכנסו אליהם קווים")
        { kind: 'elec', a0: a, a1: a, z0: z, z1: z, name: t.ent.get_attribute(D, 'kind').to_s, lo: zs.min, hi: zs.max, l: as.min, r: as.max }
      rescue StandardError => e
        puts "[Elevation] elec_point: #{e.class}: #{e.message}"
        nil
      end

      # the names of the same parts, in the same order (a shower set: ..._head, ..._valve, ..._hand)
      def part_names(t)
        ents = defined?(Sketchup::ComponentInstance) && t.ent.is_a?(Sketchup::ComponentInstance) ? t.ent.definition.entities : t.ent.entities
        ents.select do |k|
          (k.is_a?(Sketchup::Group) || (defined?(Sketchup::ComponentInstance) && k.is_a?(Sketchup::ComponentInstance))) &&
            !(k.respond_to?(:hidden?) && k.hidden?)
        end.map { |k| n = k.name.to_s; n.empty? && k.respond_to?(:definition) ? k.definition.name.to_s : n }
      rescue StandardError
        []
      end

      # the eight corners of a thing's box, in the world
      def world_box(t)
        ents = defined?(Sketchup::ComponentInstance) && t.ent.is_a?(Sketchup::ComponentInstance) ? t.ent.definition.entities : t.ent.entities
        bb = Geom::BoundingBox.new
        ents.each { |k| bb.add(k.bounds) if k.respond_to?(:bounds) }
        return nil if bb.empty?
        (0..7).map { |i| bb.corner(i).transform(t.xf) }
      end

      # 87.125 -> 87"   (16:32: "אני רוצה שיהיה עגול, אולי חצי, אבל לא יותר מזה" - to the half inch;
      # DIM_STEP 16 = to the sixteenth, the way it was)
      def fmt_in(v)
        s16 = ((v.to_f * DIM_STEP).round * 16 / DIM_STEP)
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
        return dims_clean(side, wall_h, items) if USE_CLEAN_DIMS
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
        parts = items.select { |it| it[:kind] == 'part' }
        # how high the line from a stop of the chain reaches: the highest part's middle on it
        reach = lambda do |a|
          zs = parts.select { |it| (it[:a0].to_f - a).abs <= DIM_MIN }.map { |it| [[it[:z1].to_f, 0.0].max, wall_h.to_f].min }
          zs.empty? ? nil : vz.call(zs.max)
        end
        if run.size > 2
          run.reverse.each_cons(2) do |q, p|     # left to right as the picture shows it
            dd = { 'k' => 'h', 'row' => 1, 'u' => [ux.call(q), ux.call(p)], 'v' => vz.call(0.0), 't' => fmt_in(q - p) }
            if USE_PART_REACH
              r = [reach.call(q), reach.call(p)]
              dd['r'] = r if r.any?
            end
            out << dd
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
            dd = { 'k' => 'v', 'col' => col, 'v' => [vz.call(0.0), vz.call(zm)], 'u' => ux.call(0.0), 't' => fmt_in(zm) }
            dd['u0'] = ux.call(it[:a0].to_f) if USE_PART_REACH
            out << dd
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

      # USE_CLEAN_DIMS (15:57). The same shares as dims_for, and two more kinds:
      #   'k' => 'v' with 'side' => 'L' | 'R': the column stands by that wall of the picture
      #   'k' => 'hi': a run INSIDE the picture at the height 'v' - 'u' => [u1, u2]; 'from' =>
      #               where its witness lines start (a niche's bottom), none = the line is the thing's

      def dims_clean(side, wall_h, items)
        len = side.len.to_f
        wh = wall_h.to_f
        pw = len + 2 * MARGIN
        ph = wh + 2 * MARGIN
        ux = ->(a) { (MARGIN + len - a) / pw }
        vz = ->(z) { (MARGIN + [[z, 0.0].max, wh].min) / ph }
        out = []
        cols = { 'L' => 0, 'R' => 0 }
        # the picture's left wall is side.b (a = len), its right wall side.a (a = 0)
        near = ->(a) { len - a < a ? 'L' : 'R' }
        wall_a = ->(sd) { sd == 'L' ? len : 0.0 }
        # a column of heights: numbered at the end, the lowest nearest the wall and the highest
        # farthest from it (16:15: "המדידה הכי נמוכה צריכה להיות קרובה לבית והגבוהה רחוקה")
        stacks = []
        # g (2026-10-09): the layer a number belongs to - 'tile' (a niche) or 'plumbing' (a fixture, a part), so it
        # goes off with them on the sheet (PlanCanvas.shape_group); none = the wall's own (its length, its height)
        col = lambda do |sd, zs, u0 = nil, g = nil|
          cols[sd] += 1
          ds = []
          zs.each_cons(2) do |p, q|
            next if q - p <= DIM_MIN
            d = { 'k' => 'v', 'side' => sd, 'col' => cols[sd], 'v' => [vz.call(p), vz.call(q)], 'u' => ux.call(wall_a.call(sd)), 't' => fmt_in(q - p) }
            d['g'] = g if g
            d['u0'] = ux.call(u0) if u0 && USE_PART_REACH && q == zs.last
            out << d
            ds << d
          end
          stacks << [sd, zs.last.to_f, ds]
        end
        row1 = []
        said = []     # the parts' distances already written: [a, z]
        said_e = []   # the electric distances already written: [a, z, d] (USE_ELEC_DIMS)
        # 16:13, his North wall ("זה הכי מבולגן בעולם"): a set made of parts gets ONE distance from the
        # wall - to its valve (the plumber's point), else to its middle part - not one a part
        anchor = {}
        items.select { |it| it[:kind] == 'part' && it[:fix] }.group_by { |it| it[:fix] }.each do |f, ps|
          v = ps.find { |it| it[:name].to_s =~ /valve/i }
          v ||= ps.sort_by { |it| it[:z1].to_f }[ps.size / 2]
          anchor[f] = v
        end
        items.sort_by { |it| [it[:a0].to_f, it[:z1].to_f] }.each do |it|
          case it[:kind]
          when 'niche'
            a0, a1 = it[:a0].to_f, it[:a1].to_f
            sd = near.call((a0 + a1) / 2.0)
            z0 = it[:z0].to_f
            z1 = it[:z1].to_f
            col.call(sd, z0 > DIM_MIN ? [0.0, z0, z1] : [0.0, z1], nil, 'tile')
            # its width just under it, from the nearer wall
            w_a = wall_a.call(sd)
            e_a = sd == 'L' ? a1 : a0
            v = vz.call(z0 - NICHE_UNDER)
            if (w_a - e_a).abs > DIM_MIN
              out << { 'k' => 'hi', 'u' => [ux.call(w_a), ux.call(e_a)].sort, 'v' => v, 'from' => vz.call(z0), 't' => fmt_in((w_a - e_a).abs), 'g' => 'tile' }
            end
            out << { 'k' => 'hi', 'u' => [ux.call(a1), ux.call(a0)], 'v' => v, 'from' => vz.call(z0), 't' => fmt_in(a1 - a0), 'g' => 'tile' }
          when 'part'
            am = it[:a0].to_f
            zm = it[:z1].to_f
            next if zm <= DIM_MIN
            sd = near.call(am)
            col.call(sd, [0.0, zm], am, 'plumbing')
            w_a = wall_a.call(sd)
            # one distance for parts that stand on one line (the valve and the head over it), at the lower;
            # one close under another writes its words under its line (16:05: 21 3/16 on 30 7/8)
            one = it[:fix].nil? || anchor[it[:fix]].equal?(it)
            if one && (w_a - am).abs > DIM_MIN && said.none? { |a, _| (a - am).abs <= DIM_MIN }
              d = { 'k' => 'hi', 'u' => [ux.call(w_a), ux.call(am)].sort, 'v' => vz.call(zm), 't' => fmt_in((w_a - am).abs), 'g' => 'plumbing' }
              out << d
              said << [am, zm, d]
            end
          when 'fixture'
            a0, a1 = [[it[:a0].to_f, 0.0].max, len].min, [[it[:a1].to_f, 0.0].max, len].min
            sd = near.call((a0 + a1) / 2.0)
            col.call(sd, [0.0, it[:z1].to_f], nil, 'plumbing')
            row1 << [a0, a1]
          when 'elec'                # an outlet / switch / wall light: its height (one column for all at one height)
            am = it[:a0].to_f
            zm = it[:z1].to_f
            next if zm <= DIM_MIN
            sd = near.call(am)
            unless said_e.any? { |a, z, _| (z - zm).abs <= DIM_MIN && near.call(a) == sd }
              # the height's line reaches the plate NEAREST that wall, not the farthest (17:46: "הקו של הגובה צריך להיפסק במוצר הראשון"),
              # and stops at its EDGE, not its middle (19:40: the plate stays clean)
              w_a = wall_a.call(sd)
              first = items.select { |o| o[:kind] == 'elec' && (o[:z1].to_f - zm).abs <= DIM_MIN && near.call(o[:a0].to_f) == sd }
                           .min_by { |o| (o[:a0].to_f - w_a).abs } || it
              edge = sd == 'L' ? (first[:r] || first[:a0]).to_f : (first[:l] || first[:a0]).to_f
              col.call(sd, [0.0, zm], edge, 'electric')
            end
            said_e << [am, zm, nil]
          end
        end
        # one close under another writes its words under its line (16:05: 21 3/16 on 30 7/8)
        said.sort_by { |x| x[1] }.each_cons(2) { |lo, hi| lo[2]['below'] = true if hi[1] - lo[1] < WORDS_APART }
        # the electric distances: a CHAIN per height from the nearer wall - wall to the first, first to the next... - in a
        # row ABOVE the plates (upper half of the wall) or UNDER them (lower half), never on them (17:39); witness lines
        # from the plate's middle to the row
        out.concat(elec_rows(items.select { |it| it[:kind] == 'elec' }, len, wh, near, wall_a, ux, vz))
        # the kitchen's chains and heights (USE_KITCHEN_DIMS); its chain under the floor is the first row
        rown = USE_KITCHEN_DIMS ? kitchen_dims!(out, items, len, wh, near, col, ux, vz) : 0
        if row1.any?
          rown += 1
          stops = ([0.0, len] + row1.flatten).sort
          run = []
          stops.each { |a| run << a if run.empty? || a - run.last > DIM_MIN }
          run[-1] = len
          run.reverse.each_cons(2) do |q, p|
            out << { 'k' => 'h', 'row' => rown, 'u' => [ux.call(q), ux.call(p)], 'v' => vz.call(0.0), 't' => fmt_in(q - p), 'g' => 'plumbing' }
          end
        end
        out << { 'k' => 'h', 'row' => rown + 1, 'u' => [ux.call(len), ux.call(0.0)], 'v' => vz.call(0.0), 't' => fmt_in(len) }
        col.call('R', [0.0, wh])
        %w[L R].each do |sd|
          stacks.select { |x| x[0] == sd }.sort_by { |x| x[1] }.each_with_index do |(_, _, ds), i|
            ds.each { |d| d['col'] = i + 1 }
          end
        end
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
      # only (USE_LAZY_LAYERS): { side name or 'Plan' => [[cats], ...] } - take ONLY those pictures without a layer,
      # with everything else exactly as the button sets it up; nothing else is written. nil = the button.
      # sides (USE_KITCHEN_PICK): the names of the walls to take, nil = all; label: the name the pictures and the sheet
      # carry instead of the room's ("Kitchen")
      def shoot!(room, cut: nil, style: 'lines', model: Sketchup.active_model, only: nil, sides: nil, label: nil)
        raise 'Elevations are switched off (USE_ELEVATIONS)' unless USE_ELEVATIONS
        poly = room_poly(room)
        raise 'this room has no outline' unless poly
        view = model.active_view
        wall_h = room_height(room, model)
        base_z = poly.first.z
        dir = out_dir(model)
        FileUtils.mkdir_p(dir)
        name = label || room_name(room)
        paths = []
        cam0 = view.camera
        keep = [cam0.eye, cam0.target, cam0.up, cam0.perspective?, (cam0.perspective? ? cam0.fov : cam0.height)]
        ro = model.rendering_options
        saved = {}
        RENDER_KEYS.each { |k| saved[k] = ro[k] }
        hidden = []
        last_dims.clear unless only
        model.start_operation('Elevations', true)
        begin
          all = []
          collect(model.entities, nil, 0, all)
          all.each do |t|
            next unless set_aside?(t.type) && t.ent.respond_to?(:hidden=) && !t.ent.hidden?
            t.ent.hidden = true
            hidden << t.ent
          end
          if USE_ROOM_ONLY
            outside_room(poly, all, room.ent.get_attribute(D, 'bounding_wall_ids')).each do |t|
              next unless t.ent.respond_to?(:hidden=) && !t.ent.hidden?
              t.ent.hidden = true
              hidden << t.ent
            end
            if USE_ROOM_ONLY_KITCHEN
              outside_kitchen(poly, model.entities).each do |t|
                next unless t.ent.respond_to?(:hidden=) && !t.ent.hidden?
                t.ent.hidden = true
                hidden << t.ent
              end
            end
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
          lines_drawn = []
          snap_edges = nil
          kitchen = USE_ON_WALL_ONLY ? kitchen_tops(model) : []
          # the kitchen for its numbers (USE_KITCHEN_DIMS) - read HERE, before any wall puts its far cabinets aside (12:44,
          # measured: read inside the loop it lost what West had put aside, and South got no cabinet)
          kit_d = USE_KITCHEN_DIMS ? (USE_ON_WALL_ONLY ? kitchen : kitchen_tops(model)) : nil
          capture_sides = label == KITCHEN_LABEL ? kitchen_view_sides(poly, kitchen, base_z) : sides(poly)
          capture_sides.each do |side|
            next if only && !only.key?(side.name)
            next if sides && !sides.include?(side.name)
            depth = label == KITCHEN_LABEL ? kitchen_view_cut(side, kitchen, base_z, cut) : cut_for(cut, side.name)
            s = shot(side, wall_h, depth, base_z)
            # only what is on this wall (USE_ON_WALL_ONLY): aside for this side's pictures, back right after
            aside = []
            if USE_ON_WALL_ONLY
              snap_edges ||= model_edges(model.entities) if USE_ELEV_SNAPS   # the lines of everything, before any goes
              put_aside = kitchen_island?(side) ? kitchen_island_aside(side, all, kitchen) : off_wall(side, all, kitchen, base_z)
              put_aside.each do |e|
                next unless e.respond_to?(:hidden=) && !e.hidden?
                e.hidden = true
                aside << e
              end
              trace("#{name} side #{side.name}: #{aside.size} things not on the wall put aside")
            end
            sp = model.entities.add_section_plane([s[:plane_pt], s[:normal]])
            sp.activate
            # the floor and the ceiling as one straight line each, whatever stands at the foot
            # of the wall (12:12 - "אני רוצה שזה יהיה קו ישר"): two edges half an inch into
            # the room, from corner to corner, that go with the aborted operation
            n = side.inward
            [base_z, base_z + wall_h].each do |z|
              pa = Geom::Point3d.new(side.a.x + n.x * 0.5, side.a.y + n.y * 0.5, z)
              pb = Geom::Point3d.new(side.b.x + n.x * 0.5, side.b.y + n.y * 0.5, z)
              ln = model.entities.add_line(pa, pb)
              lines_drawn << ln if ln
            end
            cam = Sketchup::Camera.new(s[:eye], s[:target], Geom::Vector3d.new(0, 0, 1), false)
            cam.height = s[:height]
            view.camera = cam
            view.refresh
            path = file_for(dir, name, side.name, style)
            meta = { 'room' => name, 'room_pid' => (room.ent.respond_to?(:persistent_id) ? room.ent.persistent_id : nil),
                     'side' => side.name, 'cut' => (label == KITCHEN_LABEL ? s[:cut] : cut_for(cut, side.name)), 'style' => style }
            if only
              # on demand: the pictures without a layer, only - the whole one is already there
              shoot_variants!(view, path, s[:w_px], s[:h_px], side_cats(side, s[:cut], all), only[side.name], meta) if File.file?(path)
              sp.erase!
              aside.each { |e| e.hidden = false if e.valid? }
              next
            end
            tw = Time.now
            ok = view.write_image(path, s[:w_px], s[:h_px], true)
            trace("#{name} side #{side.name}: the whole picture in #{((Time.now - tw) * 1000).round} ms")
            # and once for every mix of tiles / plumbing / electric off (USE_ELEV_LAYERS) - or only written down (USE_LAZY_LAYERS)
            if ok
              if USE_LAZY_LAYERS
                write_layers_index!(path, side_cats(side, s[:cut], all), meta)
              else
                shoot_variants!(view, path, s[:w_px], s[:h_px], side_cats(side, s[:cut], all), nil, meta)
              end
            end
            # the automatic dimensions of this wall (2026-10-08), for the sheet to draw over it
            if ok
              its = kitchen_island?(side) ? kitchen_island_items(side, kit_d || [], all, base_z) : safely_items(side, s[:cut], all, base_z, kit_d)
              last_dims[path.tr('\\', '/')] = kitchen_island?(side) ? kitchen_island_dims(side, wall_h, its) : dims_for(side, wall_h, its)
              trace("#{name} side #{side.name}: dims #{its.map { |i| "#{i[:kind]} #{i[:a0].round(2)}..#{i[:a1].round(2)} z #{i[:z0].round(2)}..#{i[:z1].round(2)}" }.join('; ')}")
              if USE_ELEV_SNAPS
                begin
                  t0 = Time.now
                  snap_edges ||= model_edges(model.entities)
                  segs = side_segs(side, s[:cut], wall_h, base_z, snap_edges)
                  kept, how = seen_segs(path, segs)
                  File.write(snaps_file(path), JSON.generate('segs' => kept, 'w_in' => side.len.to_f + 2 * MARGIN, 'h_in' => wall_h.to_f + 2 * MARGIN))
                  trace("#{name} side #{side.name}: snaps #{kept.size} of #{segs.size} lines kept (#{how}), #{(Time.now - t0).round(2)} s")
                rescue StandardError => e
                  trace("#{name} side #{side.name}: snaps NOT written - #{e.class}: #{e.message}")
                end
              end
            end
            sp.erase!
            aside.each { |e| e.hidden = false if e.valid? }
            trace("#{name} side #{side.name}: #{side.len.round(1)}\" long, cut #{s[:cut].round(1)}\", " \
                  "#{s[:w_px]}x#{s[:h_px]} -> #{File.basename(path)} #{ok ? 'written' : 'NOT written'}")
            paths << path if ok
          end
          # the room from above, first on its sheet (USE_TOP_VIEW, 16:10)
          if USE_TOP_VIEW && USE_ONE_SHEET && (!only || only.key?('Plan'))
            # the walls' floor and ceiling lines would lie along the walls seen from above
            gone = lines_drawn.select { |e| e.respond_to?(:valid?) && e.valid? }
            model.entities.erase_entities(gone) unless gone.empty?
            # and the floor, the tiles, the drain, the curb come back for it - not the floors on the Kitchen sheet
            # (11:22, his "קבוצת הרצפות ... אני רוצה להעלים אותה")
            keep_down = label == KITCHEN_LABEL ? PLAN_NO_FLOOR : []
            hidden.each do |e|
              next unless e.valid?
              ty = e.get_attribute(D, 'type').to_s
              e.hidden = false unless TOP_ASIDE.include?(ty) || keep_down.include?(ty)
            end
            # the tile lines of the floor and the shower pan are SOFT + HIDDEN edges (measured 16:39,
            # debug_top_shot.rb: 57 of 57) so the texture draws clean - a line drawing shows none of
            # them. Shown for the shot; the aborted operation puts them back.
            shown = 0
            all.each do |t|
              next unless %w[floor_pattern shower_pattern].include?(t.type)
              c = world_centre(t)
              next unless c && inside?(poly, c.x, c.y)
              ents = t.ent.respond_to?(:entities) ? t.ent.entities : t.ent.definition.entities
              ents.grep(Sketchup::Edge).each do |ed|
                # not the diagonals (17:58): an edge between two faces of one flat piece with the same
                # material is a fold of the drawing, not a grout line
                fs = ed.respond_to?(:faces) ? ed.faces : []
                if fs.size == 2
                  same_mat = (fs[0].material && fs[0].material.name) == (fs[1].material && fs[1].material.name)
                  flat = fs[0].normal.parallel?(fs[1].normal) rescue false
                  next if same_mat && flat
                end
                ed.hidden = false if ed.hidden?
                ed.soft = false if ed.soft?
                ed.smooth = false if ed.smooth?
                shown += 1
              end
            end
            trace("#{name} from above: #{shown} tile lines shown for the shot")
            s = top_shot(poly, base_z, wall_h)
            sp = model.entities.add_section_plane([s[:plane_pt], s[:normal]])
            sp.activate
            # the WALLS alone are cut at PLAN_CUT, as a plan cuts them, so the door and the window
            # show as openings in them (18:01: "שיראו את הדלת והחלון אפילו שהחיתוך גבוה מהם") - a
            # section plane inside each wall group cuts only that wall; everything else is seen
            # whole from under the ceiling. They go with the aborted operation.
            cutw = 0
            # (18:12, his Revit page: the window stays inside the wall, the door is its symbol) - the
            # door bodies are put away for the shot and the plan's symbol stands for them; a window is
            # cut with its wall, so its frame shows inside the wall and nothing sticks out of it
            # (18:18, his own cut of the window: the frame inside the wall is right as it is) - a window
            # is CUT with its wall and gets no symbol; what stuck out at 18:16 was the plan's casement
            # swing, not the cut. The doors are put away; the plan's symbol stands for them.
            all.each do |t|
              next unless t.type == 'door' && t.ent.respond_to?(:hidden=) && !t.ent.hidden?
              t.ent.hidden = true
              hidden << t.ent
            end
            all.each do |t|
              next unless t.type == 'wall' && t.ent.respond_to?(:entities)
              begin
                inv = t.xf.inverse
                lp = Geom::Point3d.new(s[:eye].x, s[:eye].y, base_z + PLAN_CUT).transform(inv)
                ln = Geom::Vector3d.new(0, 0, -1).transform(inv)
                wsp = t.ent.entities.add_section_plane([lp, ln])
                wsp.activate
                cutw += 1
              rescue StandardError => e
                puts "[Elevation] wall not cut for the view from above: #{e.message}"
              end
            end
            # (18:56, measured - debug_top_window.rb: a window is a COMPONENT, so the cut above never
            # reached one, and Room 2's window stands at 68..80, over the 48" cut - from under the
            # ceiling its top showed as a white block past the wall; "מעולה" on top_window_E_midcut.png)
            # - every window is cut inside its own definition at ITS OWN middle height, whatever the
            # walls are cut at, so a thin frame shows inside the wall (USE_WINDOW_MIDCUT).
            cutwin = 0
            if USE_WINDOW_MIDCUT
              all.each do |t|
                next unless t.type == 'window'
                ents = window_entities(t.ent)
                next unless ents
                begin
                  inv = t.xf.inverse
                  lp = Geom::Point3d.new(s[:eye].x, s[:eye].y, window_mid_z(t.ent, base_z)).transform(inv)
                  ln = Geom::Vector3d.new(0, 0, -1).transform(inv)
                  wsp = ents.add_section_plane([lp, ln])
                  wsp.activate
                  cutwin += 1
                rescue StandardError => e
                  puts "[Elevation] window not cut for the view from above: #{e.message}"
                end
              end
            end
            trace("#{name} from above: #{cutw} walls cut at #{PLAN_CUT}\", #{cutwin} windows cut at their own middle")
            # the door's leaf and swing, the jambs, the window - the plan's own symbols (plan_generator,
            # the ones the 2D plan prints), drawn under the cut for the shot (18:04: "חיתוך של הדלת,
            # פתיחה, פריים"). A group of their own that goes with the aborted operation.
            begin
              pg = InteriorPro::PlanGenerator
              doors, windows = pg.send(:hosted_bodies, model)
              ids = Array(room.ent.get_attribute(D, 'bounding_wall_ids')).map(&:to_s)
              sym = model.entities.add_group
              drawn = 0
              all.each do |t|
                next unless t.type == 'wall'
                next unless ids.empty? || ids.include?(t.ent.get_attribute(D, 'id').to_s)
                d = pg.send(:wall_attrs, t.ent)
                next unless d
                mine = doors.select { |b| b[:host] == d[:id] }
                pg.send(:draw_door_symbols, sym.entities, d, mine)
                swing_faces(pg, sym.entities, d, mine)
                drawn += 1
              end
              # the symbols are drawn at PLAN_Z over the ground: lifted to just under the cut, in the world
              sym.transformation = Geom::Transformation.new(Geom::Vector3d.new(0, 0, base_z + PLAN_CUT - 0.5 - pg::PLAN_Z)) * sym.transformation
              trace("#{name} from above: door/window symbols on #{drawn} walls (#{doors.size} doors, #{windows.size} windows in the model)")
            rescue StandardError => e
              trace("#{name} from above: symbols NOT drawn - #{e.class}: #{e.message}")
              puts "[Elevation] door/window symbols: #{e.message}"
            end
            kitchen_cabinet_plan!(model, kitchen, s[:eye].z - 0.25) if label == KITCHEN_LABEL
            cam = Sketchup::Camera.new(s[:eye], s[:target], s[:up], false)
            cam.height = s[:height]
            view.camera = cam
            view.refresh
            path = file_for(dir, name, 'Plan', style)
            last_dims[path.tr('\\', '/')] = kitchen_plan_dimension_rows(poly, kitchen, base_z) if label == KITCHEN_LABEL && !only
            meta = { 'room' => name, 'room_pid' => (room.ent.respond_to?(:persistent_id) ? room.ent.persistent_id : nil),
                     'side' => 'Plan', 'style' => style }
            if only
              ok = false
              shoot_variants!(view, path, s[:w_px], s[:h_px], room_cats(poly, all), only['Plan'], meta) if File.file?(path)
            else
              ok = view.write_image(path, s[:w_px], s[:h_px], true)
              if ok
                if USE_LAZY_LAYERS
                  write_layers_index!(path, room_cats(poly, all), meta)
                else
                  shoot_variants!(view, path, s[:w_px], s[:h_px], room_cats(poly, all), nil, meta)
                end
              end
            end
            sp.erase!
            trace("#{name} from above: cut #{(s[:plane_pt].z - base_z).round(1)}\", #{s[:w_px]}x#{s[:h_px]} -> #{File.basename(path)} #{ok ? 'written' : 'NOT written'}") unless only
            paths.unshift(path) if ok
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
        onp = Array(st['pics']).map { |r| r.is_a?(Hash) ? r['path'].to_s.tr('\\', '/') : nil }
        st['image_dims'] = dd.select { |p, _| st['images'].include?(p) || onp.include?(p) }
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

      # ---- one sheet for the room (USE_ONE_SHEET, 2026-10-08 14:00) ---------------
      #
      # The first wall OWNS the sheet (st['images']), the others are pictures added to it
      # (st['pics'], on 'image:N'). Each gets a box only if it has none yet - so after he
      # moves or resizes one, taking the pictures again leaves it there.

      # Boxes for pictures in a row, at one scale, in the top half of area [x, y, w, h].
      # sizes: [[w_px, h_px]]; cols: how many columns of heights stand right of each - or
      # [left, right] since the heights stand by both walls (USE_CLEAN_DIMS, 15:57).
      def row_boxes(area, sizes, cols, up = 0)
        ax, ay, aw, ah = area.map(&:to_f)
        er = defined?(InteriorPro::PlanCanvas::ELEV_ROW) ? InteriorPro::PlanCanvas::ELEV_ROW : 0.45
        lr = cols.map { |c| c.is_a?(Array) ? [c[0].to_i, c[1].to_i] : [0, c.to_i] }
        lead = lr.first[0] * er
        gaps = lr.each_with_index.map { |(_, r), i| (r + (lr[i + 1] ? lr[i + 1][0] : 0)) * er + ROW_GAP }
        ax += lead
        aw -= lead
        room_w = aw - gaps[0...-1].sum - gaps.last.to_f
        wpx = sizes.sum { |s| s[0].to_f }
        hpx = sizes.map { |s| s[1].to_f }.max
        k = [room_w / wpx, (ah * 0.5 - 3 * er - up * er) / hpx].min     # paper inches a pixel; up = rows over the pictures
        x = ax
        sizes.each_with_index.map do |s, i|
          w = s[0].to_f * k
          h = s[1].to_f * k
          b = [x, ay + ah - h - up * er, w, h]
          x += w + gaps[i]
          b
        end
      end

      # Kitchen only: small reference plan + large elevations in two columns.
      # All elevations share a scale; space outside each box is reserved for dimension rows.
      def kitchen_boxes(area, sizes, cols, up = 0, plan: true)
        return row_boxes(area, sizes, cols, up) unless USE_KITCHEN_SHEET_GRID && sizes.size > 1
        ax, ay, aw, ah = area.map(&:to_f)
        er = defined?(InteriorPro::PlanCanvas::ELEV_ROW) ? InteriorPro::PlanCanvas::ELEV_ROW : 0.45
        rows = (sizes.size / 2.0).ceil
        cw = aw / 2.0; ch = ah / rows
        pads = sizes.each_index.map do |i|
          c = cols[i]; left, right = c.is_a?(Array) ? c : [0, c.to_i]
          [0.35 + left.to_i * er, 0.35 + right.to_i * er, 3 * er + 0.35, up * er + 0.35]
        end
        scales = sizes.each_with_index.filter_map do |s, i|
          next if i.zero? && plan
          l,r,b,t = pads[i]
          [(cw-l-r)/s[0].to_f, (ch-b-t)/s[1].to_f].min
        end
        scale = scales.min
        return row_boxes(area, sizes, cols, up) unless scale && scale > 0
        sizes.each_with_index.map do |s,i|
          l,r,b,t = pads[i]
          x = ax + (i % 2) * cw; y = ay + ah - (i / 2 + 1) * ch
          k = i.zero? && plan ? [(cw * 0.65)/s[0].to_f, (ch * 0.78)/s[1].to_f, scale].min : scale
          w = s[0].to_f*k; h = s[1].to_f*k
          [x+l+(cw-l-r-w)/2.0, y+b+(ch-b-t-h)/2.0, w, h]
        end
      end

      def add_room_sheet!(paths, sheet_title, dims = {})
        return 0 if paths.empty?
        psd = InteriorPro::PlanSheetDialog
        pc = InteriorPro::PlanCanvas
        fresh = paths.map { |p| p.to_s.tr('\\', '/') }
        main = fresh.first
        rest = fresh[1..-1]
        st = psd.load_state
        # a wall that had a sheet of its own (before this, or taken one by one) gives it up
        Array(st['images']).map { |p| p.to_s.tr('\\', '/') }.each_with_index.select { |p, _| rest.include?(p) }.map(&:last).reverse.each do |i|
          st['images'] = Array(st['images']).each_with_index.reject { |_, j| j == i }.map(&:first)
          st['pdf_skip'] = psd.send(:shift_image_keys, st['pdf_skip'], i) if st['pdf_skip']
          st['page_order'] = psd.send(:shift_image_keys, st['page_order'], i) if st['page_order'].is_a?(Array)
          psd.send(:shift_pics!, st, i)
        end
        have = Array(st['images']).map { |p| p.to_s.tr('\\', '/') }
        st['images'] = have.include?(main) ? have : have + [main]
        n = st['images'].index(main)
        on = "image:#{n}"
        tt = st['image_titles'].is_a?(Hash) ? st['image_titles'] : {}
        tt[main] = sheet_title.to_s
        st['image_titles'] = tt
        pics = Array(st['pics']).select { |r| r.is_a?(Hash) }
        # a wall of this sheet that is NOT taken this time leaves it (11:56, his Kitchen sheet kept the walls of the
        # first run under the new ones): the pictures on this page from the same room (file name prefix) not among
        # the fresh ones go
        pre = File.basename(main)[/\A(.*)_[A-Za-z]+\d*_[a-z]+\.png\z/, 1]
        if pre
          pics = pics.reject do |r|
            rp = r['path'].to_s.tr('\\', '/')
            r['on'].to_s == on && !fresh.include?(rp) && File.basename(rp).start_with?("#{pre}_")
          end
        end
        rest.each { |p| pics << { 'path' => p, 'on' => on } unless pics.any? { |r| r['path'].to_s.tr('\\', '/') == p && r['on'].to_s == on } }
        st['pics'] = pics
        dd = st['image_dims'].is_a?(Hash) ? st['image_dims'] : {}
        dims.each { |p, d| dd[p.to_s.tr('\\', '/')] = d }
        st['image_dims'] = dd
        psd.save_state(st)
        # the boxes: only the ones he has not placed
        geo = st['image_geo'].is_a?(Hash) ? st['image_geo'] : {}
        mine = fresh.map { |p| p == main ? geo[n.to_s] : pics.find { |r| r['path'].to_s.tr('\\', '/') == p && r['on'].to_s == on } }
        # a box is laid again while it is still the one laid here ('auto' true - also one from before
        # 15:57, which carries no mark); one he moved (the window writes auto false) stays
        need = mine.each_with_index.map do |g, i|
          i.zero? ? !(g.is_a?(Hash) && g['box']) || g['auto'] == true : (!g['box'] || g['auto'] != false)
        end
        # the first time the room is put on one sheet (or a row laid before the mark existed),
        # the wall that owns it is laid in the row too; the window writes a moved one without the mark
        need[0] = true if need.size > 1 && mine[1..-1].none? { |g| g.key?('auto') }
        if need.any?
          psd.instance_variable_set(:@doc, nil)
          pg = psd.document.pages.find { |q| q.kind.to_s == 'image' && q.ref.to_i == n }
          if pg
            sizes = fresh.map { |p| pc.pic_size(p) || [1333, 1440] }
            cols = fresh.map do |p|
              vs = Array(dd[p]).select { |x| x['k'] == 'v' }
              [vs.select { |x| x['side'] == 'L' }.map { |x| x['col'].to_i }.max.to_i,
               vs.reject { |x| x['side'] == 'L' }.map { |x| x['col'].to_i }.max.to_i]
            end
            # the kitchen's uppers' row stands over the ceiling (USE_KITCHEN_DIMS): room for it over the row of pictures
            ups = fresh.map { |p| Array(dd[p]).select { |x| x['up'] }.map { |x| x['row'].to_i }.max.to_i }.max.to_i
            boxes = row_boxes(pc.pic_area(pg), sizes, cols, ups)
            boxes = kitchen_boxes(pc.pic_area(pg), sizes, cols, ups) if sheet_title == KITCHEN_LABEL
        boxes = kitchen_boxes(pc.pic_area(pg), sizes, cols, ups, plan: false) if sheet_title.to_s.start_with?("#{KITCHEN_LABEL} - Island ")
            fresh.each_with_index do |p, i|
              next unless need[i]
              if i.zero?
                geo[n.to_s] = { 'box' => boxes[i], 'rot' => 0.0, 'crop' => [0.0, 0.0, 0.0, 0.0], 'auto' => true }
              else
                mine[i]['auto'] = true
                mine[i]['box'] = boxes[i]
                mine[i]['rot'] = 0.0
                mine[i]['crop'] = [0.0, 0.0, 0.0, 0.0]
              end
            end
            st['image_geo'] = geo
            psd.save_state(st)
          end
        end
        begin
          dlg = psd.instance_variable_get(:@dialog)
          psd.instance_variable_set(:@doc, nil)
          psd.send(:push_all, dlg) if dlg
        rescue StandardError => e
          puts "[Elevation] sheet window not refreshed: #{e.message}"
        end
        trace("one sheet: #{File.basename(main)} owns image:#{n}, #{rest.size} beside it, #{need.count(true)} boxes laid")
        fresh.size
      end

      # the whole job from the panel: shoot, then onto the sheet
      def make!(room, cut: nil, style: 'lines', sides: nil, label: nil)
        paths = shoot!(room, cut: cut, style: style, sides: sides, label: label)
        dims = paths.each_with_object({}) { |p, h| d = last_dims[p.to_s.tr('\\', '/')]; h[p] = d if d }
        title = label || room_name(room)
        if USE_ONE_SHEET && title == KITCHEN_LABEL && paths.any? { |p| File.basename(p).include?('_Island') }
          n = kitchen_add_sheets!(paths, dims)
        else
        n = USE_ONE_SHEET ? add_room_sheet!(paths, title, dims) : add_to_sheet!(paths, titles_for(room, paths), dims)
        end
        trace("#{title}: #{paths.size} pictures, #{n} onto the sheet")
        paths
      end

      # ---- "Kitchen" in the list (USE_KITCHEN_PICK, 2026-10-15 10:48, his words: "הוא מראה לי אופציה של חדר, אתה לא חושב
      # שהוא צריך להראות לי אופציה של מטבח? ... אני לא רוצה שהסלון יהיה באליוויישן"): the room that holds the kitchen, but
      # ONLY the walls with kitchen on them - its sheet is "Kitchen". Off = the rooms alone, as before.

      # the room whose outline holds a top-level kitchen group's middle; nil = no kitchen
      def kitchen_room(model = Sketchup.active_model)
        kit = kitchen_tops(model)
        return nil if kit.empty?
        rooms(model).find do |r|
          poly = room_poly(r)
          kit.any? do |e, _k, wxf|
            c = e.bounds.center.transform(wxf * e.transformation.inverse)
            inside?(poly, c.x, c.y)
          end
        end
      rescue StandardError => e
        puts "[Elevation] kitchen_room: #{e.class}: #{e.message}"
        nil
      end

      # the names of the room's walls that have kitchen ON them. Measured 11:49 (debug_kitchen_sides.rb): a box touches
      # more walls than it stands on - the tall cabinet in the corner touched the short wall with its SIDE, and the one
      # microwave base on the far wall made a third. So: every top-level kitchen CABINET group (kitchen_unit / cabinet -
      # not the run of countertop or backsplash) goes with the kitchen's own wall letter (KitchenLab data 'wall': A, B,
      # I = island), and each letter's cabinets stand on the ONE wall they touch most (their contact along it, summed).
      # No letter = the wall that one touches most. PURE apart from the boxes.
      def kitchen_sides(poly, kitchen, base_z)
        return [] unless defined?(InteriorPro::ElectricalLibrary) && InteriorPro::ElectricalLibrary.respond_to?(:box_in_frame)
        if USE_KITCHEN_FACING
          on = sides(poly).select do |side|
            fr = side_frame(side, base_z)
            Array(kitchen).any? { |e, k, wxf| KITCHEN_WALL_KINDS.include?(k.to_s) && kitchen_on(side, e, wxf, fr) }
          end
          return on.map(&:name)
        end
        all_sides = sides(poly)
        frames = all_sides.map do |side|
          ux = (side.b.x - side.a.x) / side.len
          uy = (side.b.y - side.a.y) / side.len
          [side, { ox: side.a.x, oy: side.a.y, ux: ux, uy: uy, nx: side.inward.x, ny: side.inward.y, floor_z: base_z }]
        end
        contact = Hash.new { |h, k| h[k] = Hash.new(0.0) }     # letter => { side name => inches of contact }
        Array(kitchen).each do |e, k, wxf|
          next unless KITCHEN_WALL_KINDS.include?(k.to_s)
          tag = kitchen_wall_tag(e)
          frames.each do |side, fr|
            u0, u1, _z0, _z1, o0, = InteriorPro::ElectricalLibrary.box_in_frame(e, wxf, fr)
            next unless o0 <= ON_WALL_PIC && o0 > -ON_WALL_PIC
            len = [u1, side.len].min - [u0, 0.0].max
            next if len <= 0
            contact[tag || e.object_id][side.name] += len
          end
        end
        picked = contact.values.map { |by_side| by_side.max_by { |_n, l| l }&.first }.compact.uniq
        all_sides.map(&:name).select { |n| picked.include?(n) }
      end

      # the kitchen's own wall letter of a unit (A, B, I...): from the 'data' of the unit itself or of a cabinet in it
      def kitchen_wall_tag(ent)
        cands = [ent]
        kids = ent.respond_to?(:entities) ? ent.entities : (ent.respond_to?(:definition) ? ent.definition.entities : [])
        kids.each { |k| cands << k if (k.is_a?(Sketchup::Group) || (defined?(Sketchup::ComponentInstance) && k.is_a?(Sketchup::ComponentInstance))) && k.get_attribute('KitchenLab', 'kind') == 'cabinet' }
        cands.each do |c|
          raw = c.get_attribute('KitchenLab', 'data')
          next unless raw.is_a?(String) && !raw.empty?
          d = JSON.parse(raw)
          w = d['wall'].to_s
          return w unless w.empty?
        end
        nil
      rescue StandardError
        nil
      end

      # the kitchen's pictures onto its own sheet: the kitchen walls of its room. [] = no kitchen.
      def make_kitchen!(cut: nil, style: 'lines', model: Sketchup.active_model)
        room = kitchen_room(model)
        return [] unless room
        poly = room_poly(room)
        kit = kitchen_tops(model)
        names = kitchen_sides(poly, kit, poly.first.z)
        names += kitchen_island_views(poly, kit, poly.first.z).map(&:name)
        trace("Kitchen walls #{names.inspect} (#{USE_KITCHEN_FACING ? 'by the way the cabinets face' : 'by letter'}): " +
              kit.select { |_e, k, _x| KITCHEN_WALL_KINDS.include?(k.to_s) }
                 .map { |e, _k, x| b = kitchen_back(e, x); "#{e.name.to_s.sub('Kitchen / ', '')[0, 20]} back #{b ? compass(b) : 'corner/none'}" }.join(', '))
        return [] if names.empty?
        InteriorPro::PlanPDF.forget_images! if defined?(InteriorPro::PlanPDF) && InteriorPro::PlanPDF.respond_to?(:forget_images!)
        make!(room, cut: cut, style: style, sides: names, label: KITCHEN_LABEL)
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
