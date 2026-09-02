# Interior Pro - Skylight (2026-09-14)
#
# What he asked for, in his words: "משהו שהוא כמו חלון תמונה רק להחליף
# צבעים... הוא גם צריך להיכנס ולעשות חור בתקרה שעובר עד לגג... צריך שיהיה
# אפשר לבחור לו צבע אבל החלון עצמו פשוט".
#
# So: click a slope, a rectangle is cut clean through the roof slab, a low
# curb with one sheet of glass stands in it, and the SAME rectangle is cut
# through the ceiling under it with four white walls - the light shaft -
# running from the ceiling up to the roof. Size and colour come from the
# panel (SkylightDialog); nothing else is typed.
#
# It owns no roof maths of its own. The frame under the click comes from
# DormerManager.roof_frame - the same one the dormer uses - so a skylight
# inherits the roof's true pitch and height with nothing typed in.
#
# SKYLIGHTS SURVIVE A ROOF REBUILD the way dormers do: build_roof! asks
# `harvest` for them before the old roof goes and `replant!` puts them
# back on the new one at the same plan point.
#
# Kill switches:
#   InteriorPro::SkylightManager::USE_SKYLIGHTS      = false  (all of it)
#   InteriorPro::SkylightManager::USE_SKYLIGHT_SHAFT = false  (roof only,
#                                                    the ceiling untouched)
module InteriorPro
  module SkylightManager
    USE_SKYLIGHTS      = true unless const_defined?(:USE_SKYLIGHTS, false)
    USE_SKYLIGHT_SHAFT = true unless const_defined?(:USE_SKYLIGHT_SHAFT, false)
    USE_SKYLIGHT_FLASHING = false unless const_defined?(:USE_SKYLIGHT_FLASHING, false) # OFF: he saw it and said no (2026-09-14)

    # Methods, not constants: a constant is not re-read by reload!.
    def self.default_width;  30.0; end   # across the slope
    def self.default_height; 46.0; end   # up the slope
    def self.lip_height;      1.0; end   # how far the frame stands above the roof
    def self.glass_drop;      1.0; end   # how far the glass sits below the roof face
    def self.curb_height;    lip_height; end   # old name, same number
    def self.frame_width;     2.0; end   # the border round the glass
    def self.default_color;  '#ffffff'; end
    def self.min_size;       12.0; end
    def self.flashing_apron;  4.0; end   # up and down the slope, past the frame
    def self.flashing_side;   6.0; end   # across the slope when the roof has no tile pitch
    def self.flashing_lift;   0.06; end  # a hair off the deck, so it does not fight it
    def self.max_size;      120.0; end

    def self.last_reason; @last_reason; end

    def self.warn_nil(msg)
      @last_reason = msg
      puts "[Skylight] #{msg}"
      nil
    end

    # ---------- THE PANEL'S NUMBERS ------------------------------------
    def self.settings
      @settings ||= { width: default_width, height: default_height,
                      color: default_color }
      @settings.dup
    end

    # PURE: what the panel sends, made safe. A size outside the limits is
    # pulled back to them; a colour that is not #rrggbb becomes white.
    def self.clean_spec(spec)
      s = spec || {}
      w = s[:width].to_f
      h = s[:height].to_f
      w = default_width  if w <= 0.0
      h = default_height if h <= 0.0
      w = [[w, min_size].max, max_size].min
      h = [[h, min_size].max, max_size].min
      { width: w, height: h, color: color_of(s) }
    end

    def self.save_settings!(spec)
      @settings = clean_spec(spec)
      @settings.dup
    end

    def self.color_of(spec)
      c = (spec || {})[:color].to_s
      c =~ /\A#[0-9a-fA-F]{6}\z/ ? c.downcase : default_color
    end

    # ---------- PURE GEOMETRY ------------------------------------------

    # The opening as [s, w] corners in the roof frame, around a click that
    # sits s_click up the slope from the eave line. s runs UP the slope, w
    # across it, exactly as the dormer measures them.
    def self.plan_rect(s_click, width, height)
      w = width.to_f
      h = height.to_f
      return nil if w < min_size || h < min_size
      hw = w / 2.0
      s0 = s_click.to_f - h / 2.0
      s1 = s_click.to_f + h / 2.0
      [[s0, -hw], [s0, hw], [s1, hw], [s1, -hw]]
    end

    # Is the opening clear of the roof face it is being cut into? Every
    # corner has to sit on the same face, or the hole runs off the edge of
    # the slope and the cut leaves a notch in the fascia.
    def self.corners_on_face?(face, at, plan)
      return false if face.nil? || plan.nil?
      plan.all? do |s, w|
        q = at.call(s, w, 0.0)
        InteriorPro::DormerManager.covers_point?(face, q.x, q.y)
      end
    end

    # The same plan ring dropped on a LEVEL plane at z - the ceiling.
    def self.ring_at_z(plan, at, z)
      plan.map do |s, w|
        q = at.call(s, w, 0.0)
        Geom::Point3d.new(q.x, q.y, z.to_f)
      end
    end

    # The four walls of the shaft: each edge of the ceiling ring straight
    # up to the matching edge of the roof's underside ring. Same corner
    # order in both, so the quads do not twist.
    def self.shaft_quads(low, high)
      return [] if low.nil? || high.nil? || low.length != high.length || low.length < 3
      n = low.length
      (0...n).map do |i|
        j = (i + 1) % n
        [low[i], low[j], high[j], high[i]]
      end
    end

    # PURE: the ring pulled in by `d` along BOTH edges at every corner - an
    # exact inset for a rectangle, however long and narrow. Pulling each
    # corner toward the centre instead insets the short side more than the
    # long one. nil when the ring is too small to inset at all.
    def self.inset_ring(ring, d)
      n = ring.length
      return nil if n < 3
      out = (0...n).map do |i|
        p = ring[i]
        a = ring[(i + 1) % n] - p
        b = ring[(i - 1) % n] - p
        return nil if a.length < 2.0 * d || b.length < 2.0 * d
        a.normalize!
        b.normalize!
        p.offset(a, d).offset(b, d)
      end
      out
    end

    # ---------- MATERIALS ----------------------------------------------
    def self.get_material(model, name, color, alpha = nil)
      m = model.materials[name]
      return m if m
      m = model.materials.add(name)
      m.color = color
      m.alpha = alpha if alpha
      m
    end

    # ---------- PLACING ------------------------------------------------

    # Place one skylight on a roof, at (x, y) in plan. Returns the group.
    def self.place_on_roof!(roof, x, y, spec = {})
      return warn_nil('skylights are switched off') unless USE_SKYLIGHTS
      return warn_nil('no roof') if roof.nil? || !roof.valid?
      fr = InteriorPro::DormerManager.roof_frame(roof, x, y)
      return warn_nil('no roof surface under that point') if fr.nil?

      sp = clean_spec(spec)
      plan = plan_rect(fr[:s_click], sp[:width], sp[:height])
      return warn_nil('that skylight is too small') if plan.nil?

      at = InteriorPro::DormerManager.at_lambda(fr)
      return warn_nil('runs off the edge of this slope - try further in') unless
        corners_on_face?(fr[:face], at, plan)

      model = Sketchup.active_model
      face = fr[:face]
      n = face.normal.normalize
      z_at = InteriorPro::DormerManager.plane_z_lambda(face)
      return warn_nil('that part of the roof is not a plane') if z_at.nil?

      rings = cut_rect!(roof.entities, plan, at, face.material)
      return warn_nil('nothing was cut - the roof has no skin there') if rings.empty?
      top_ring = rings.max_by { |r| r.map(&:z).max }
      under_ring = rings.min_by { |r| r.map(&:z).max }

      grp = roof.entities.add_group
      grp.name = 'InteriorPro_Skylight'
      build_body!(grp, top_ring, under_ring, n, sp[:color], model)
      build_flashing!(grp, plan, at, z_at, n, sp[:color], model, roof, face) if USE_SKYLIGHT_FLASHING

      shaft = 0
      if USE_SKYLIGHT_SHAFT
        shaft = build_shaft!(grp, plan, at, under_ring, model)
      end

      grp.set_attribute('InteriorPro', 'type', 'skylight')
      grp.set_attribute('InteriorPro', 'width', sp[:width])
      grp.set_attribute('InteriorPro', 'height', sp[:height])
      grp.set_attribute('InteriorPro', 'color', sp[:color])
      grp.set_attribute('InteriorPro', 'curb', curb_height)
      grp.set_attribute('InteriorPro', 'at_xy', [x.to_f, y.to_f])
      grp.set_attribute('InteriorPro', 'shaft', shaft)
      grp.set_attribute('InteriorPro', 'plan_xy',
                        top_ring.flat_map { |p| [p.x.to_f, p.y.to_f] })
      grp.set_attribute('InteriorPro', 'created_at', Time.now.to_s)
      # THE TILES ARE LAID AGAIN AROUND THE HOLE (2026-09-14, the user:
      # "הוא לא חוצה את הגגות האחרים אלא רק את השינגלס"). Shingles are a
      # texture on the deck, so cutting the deck cut them. Clay, metal and
      # every other run material is real pieces standing ON the deck, and
      # those stayed put over the opening. The dormer has the same problem
      # and the same answer: RoofTilePlace.relay_runs! reads the deck's
      # holes and lays the field again around them.
      relay_tiles!(roof) unless (spec || {})[:no_relay]
      puts "[Skylight] placed #{sp[:width].round}\" x #{sp[:height].round}\" " \
           "#{sp[:color]} (#{rings.length} skin(s) cut, shaft to " \
           "#{shaft} ceiling(s))"
      grp
    rescue StandardError => e
      puts "[Skylight] place_on_roof!: #{e.class}: #{e.message}"
      puts e.backtrace.first(5) if e.backtrace
      nil
    end

    # THE WINDOW SITS INSIDE THE HOLE (2026-09-14, the user: "צריך ליצור
    # את החלון בתוך החור"). The first cut stood a 4" curb ON the roof
    # around the opening; now the frame lines the opening like a jamb in
    # a wall - from the underside of the slab up to a 1" lip above the
    # roof face - and the glass sits 1" below the roof face inside it.
    #
    # Every ring here is the hole's own ring pulled in by the frame width
    # (inset_ring), or pushed along the roof's normal, so the frame stays
    # square to the slope. Rings, not faces with holes: each band is four
    # quads, so nothing has an inner loop SketchUp could heal shut.
    def self.build_body!(grp, top_ring, under_ring, n, hex, model)
      frame_mat = get_material(model, "InteriorPro_Skylight_#{hex.delete('#')}",
                               Sketchup::Color.new(hex))
      glass_mat = get_material(model, 'InteriorPro_Glass',
                               Sketchup::Color.new(180, 180, 180), 0.4)
      under_ring = top_ring if under_ring.nil? || under_ring.length != top_ring.length
      inner_top   = inset_ring(top_ring, frame_width)
      inner_under = inset_ring(under_ring, frame_width)
      return false if inner_top.nil? || inner_under.nil?
      lip_outer = top_ring.map   { |p| p.offset(n, lip_height) }
      lip_inner = inner_top.map  { |p| p.offset(n, lip_height) }
      # never below the slab's own underside - on a thin roof the glass
      # would hang in the shaft
      depth = (top_ring[0] - under_ring[0]) % n
      drop = depth > 0.2 ? [glass_drop, depth * 0.5].min : 0.0
      glass     = inner_top.map  { |p| p.offset(n, -drop) }

      band = lambda do |a, b, mat|
        a.length.times do |i|
          j = (i + 1) % a.length
          f = begin
            grp.entities.add_face([a[i], a[j], b[j], b[i]])
          rescue StandardError
            nil
          end
          next unless f && f.valid?
          f.material = mat
          f.back_material = mat
        end
      end

      band.call(top_ring, lip_outer, frame_mat)     # the lip's outer side
      band.call(lip_outer, lip_inner, frame_mat)    # the top of the frame
      band.call(lip_inner, inner_under, frame_mat)  # the reveal, lip to underside
      band.call(under_ring, inner_under, frame_mat) # the frame's underside

      pane = begin
        grp.entities.add_face(glass)
      rescue StandardError
        nil
      end
      return true unless pane && pane.valid?
      pane.material = glass_mat
      pane.back_material = glass_mat
      true
    end

    # PURE: how far the flashing reaches past the hole, [up/down, across].
    # Across the slope it reaches one tile PITCH: a run that had to come
    # out because the frame took a bite of it leaves bare deck up to the
    # next run, and that is exactly the strip a real flashing apron hides
    # (2026-09-14, his Roman roof: a 14" run with 6" under the window went
    # whole, and he asked for flashing before a lengthwise cut).
    def self.flashing_reach(shape)
      side = flashing_side
      if shape.is_a?(Hash)
        p = shape[:run_pitch].to_f
        p = shape[:tile_w].to_f if p <= 0.0
        side = [p, side].max if p > 0.0
      end
      [flashing_apron, side]
    end

    # PURE: the plan ring grown by [apron, side] in the roof frame.
    def self.grow_plan(plan, apron, side)
      s0 = plan.map(&:first).min - apron
      s1 = plan.map(&:first).max + apron
      w0 = plan.map(&:last).min - side
      w1 = plan.map(&:last).max + side
      [[s0, w0], [s0, w1], [s1, w1], [s1, w0]]
    end

    # A flat apron round the frame, lying on the deck, in the frame's
    # colour. Four quads between the hole ring and the grown ring - a
    # band, not a face with a hole - lifted a hair off the deck.
    def self.build_flashing!(grp, plan, at, z_at, n, hex, model, roof, face = nil)
      shape = nil
      if roof && defined?(InteriorPro::RoofTileMath)
        name = roof.get_attribute('InteriorPro', 'roof_material').to_s
        shape = InteriorPro::RoofTileMath.shape(name) rescue nil
      end
      apron, side = flashing_reach(shape)
      # the apron must stay on this same slope - past its edge it would
      # float in the air. Halved until it fits; nothing at all if even a
      # thin one runs off.
      outer_plan = nil
      6.times do
        try = grow_plan(plan, apron, side)
        if face.nil? || corners_on_face?(face, at, try)
          outer_plan = try
          break
        end
        apron /= 2.0
        side /= 2.0
      end
      return false if outer_plan.nil? || (apron < 0.5 && side < 0.5)
      ring = lambda do |pl|
        pl.map do |sq, wq|
          q = at.call(sq, wq, 0.0)
          Geom::Point3d.new(q.x, q.y, z_at.call(q.x, q.y)).offset(n, flashing_lift)
        end
      end
      inner = ring.call(plan)
      outer = ring.call(outer_plan)
      mat = get_material(model, "InteriorPro_Skylight_#{hex.delete('#')}",
                         Sketchup::Color.new(hex))
      made = 0
      inner.length.times do |i|
        j = (i + 1) % inner.length
        f = begin
          grp.entities.add_face([inner[i], inner[j], outer[j], outer[i]])
        rescue StandardError
          nil
        end
        next unless f && f.valid?
        f.material = mat
        f.back_material = mat
        made += 1
      end
      made.positive?
    rescue StandardError => e
      puts "[Skylight] build_flashing!: #{e.class}: #{e.message}"
      false
    end

    # THE HOLE IN THE CEILING AND THE SHAFT UP TO THE ROOF. The ceiling
    # directly under the skylight - the highest one that is still below
    # the roof there - gets the same rectangle cut through it, and four
    # white walls run from that hole straight up to the roof's underside
    # ring. Returns how many ceilings were cut (0 or 1).
    def self.build_shaft!(grp, plan, at, under_ring, model)
      return 0 if under_ring.nil? || under_ring.empty?
      flat = plan.map { |s, w| at.call(s, w, 0.0) }
      cx = flat.map(&:x).sum / flat.length
      cy = flat.map(&:y).sum / flat.length
      z_roof = under_ring.map(&:z).min

      ceil = ceiling_under(model, cx, cy, z_roof)
      return 0 if ceil.nil?
      c_grp, c_z = ceil

      c_ring = ring_at_z(plan, at, c_z)
      cut = cut_level!(c_grp.entities, plan, at)
      return 0 if cut.zero?

      white = InteriorPro::CeilingManager.respond_to?(:ceiling_material) ?
                InteriorPro::CeilingManager.ceiling_material(model) :
                get_material(model, 'InteriorPro_Ceiling', Sketchup::Color.new(255, 255, 255))
      shaft_quads(c_ring, under_ring).each do |q|
        f = begin
          grp.entities.add_face(q)
        rescue StandardError
          nil
        end
        next unless f && f.valid?
        f.material = white
        f.back_material = white
      end
      1
    rescue StandardError => e
      puts "[Skylight] build_shaft!: #{e.class}: #{e.message}"
      0
    end

    # The ceiling group under (x, y) that sits highest while still below
    # z_roof, with the z of its face there. nil when there is none.
    def self.ceiling_under(model, x, y, z_roof)
      best = nil
      model.entities.grep(Sketchup::Group).each do |g|
        next unless g.valid? && g.get_attribute('InteriorPro', 'type') == 'ceiling'
        g.entities.grep(Sketchup::Face).each do |f|
          next if f.normal.z.abs < 0.9
          next unless InteriorPro::DormerManager.covers_point?(f, x, y)
          z = InteriorPro::DormerManager.face_points(f).map(&:z).min
          next if z >= z_roof - 1.0
          best = [g, z] if best.nil? || z > best[1]
        end
      end
      best
    end

    # Cut the rectangle through a LEVEL slab (the ceiling): the ring is
    # drawn on every level face covering the centre, the rim between two
    # skins is closed, and only then is everything lying inside swept.
    def self.cut_level!(ents, plan, at)
      flat = plan.map { |s, w| at.call(s, w, 0.0) }
      cx = flat.map(&:x).sum / flat.length
      cy = flat.map(&:y).sum / flat.length
      skins = ents.grep(Sketchup::Face).select do |f|
        f.normal.z.abs > 0.9 && InteriorPro::DormerManager.covers_point?(f, cx, cy)
      end
      return 0 if skins.empty?
      rings = []
      mat = nil
      skins.each do |f|
        z = InteriorPro::DormerManager.face_points(f).map(&:z).min
        mat ||= f.material
        ring = ring_at_z(plan, at, z)
        begin
          ents.add_face(ring)
        rescue StandardError
          next
        end
        rings << ring
      end
      return 0 if rings.empty?
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
      doomed = ents.grep(Sketchup::Face).select do |f|
        next false if f.normal.z.abs < 0.9
        pts = InteriorPro::DormerManager.face_points(f)
        pts.length >= 3 &&
          pts.all? { |p| InteriorPro::DormerManager.in_plan?(plan, at, p.x, p.y, -0.05) }
      end
      doomed.each { |f| f.erase! if f.respond_to?(:erase!) && f.valid? }
      puts "[Skylight] ceiling cut: #{rings.length} skin(s), #{doomed.length} piece(s) removed"
      rings.length
    rescue StandardError => e
      puts "[Skylight] cut_level!: #{e.class}: #{e.message}"
      0
    end

    # Cut the rectangle clean through the roof slab. Same sequence the
    # dormer's cut_roof! uses and for the same reasons: the ring is dropped
    # on BOTH skins, the rim between them is closed, and only THEN is
    # everything still lying over the hole swept away - erasing earlier
    # erases nothing, because SketchUp heals a closed coplanar loop the
    # moment the rim edges arrive. Returns the rings it cut (one per skin).
    def self.cut_rect!(ents, plan, at, mat = nil)
      flat = plan.map { |s, w| at.call(s, w, 0.0) }
      cx = flat.map(&:x).sum / flat.length
      cy = flat.map(&:y).sum / flat.length

      skins = ents.grep(Sketchup::Face).select do |f|
        next false if f.normal.z.abs < 0.2
        InteriorPro::DormerManager.covers_point?(f, cx, cy)
      end
      return [] if skins.empty?

      rings = []
      skins.each do |f|
        z_at = InteriorPro::DormerManager.plane_z_lambda(f)
        next if z_at.nil?
        mat ||= f.material
        ring = plan.map do |s, w|
          q = at.call(s, w, 0.0)
          Geom::Point3d.new(q.x, q.y, z_at.call(q.x, q.y))
        end
        begin
          ents.add_face(ring)
        rescue StandardError
          next
        end
        rings << ring
      end
      return [] if rings.empty?

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

      doomed = ents.grep(Sketchup::Face).select do |f|
        next false if f.normal.z.abs < 0.2
        pts = InteriorPro::DormerManager.face_points(f)
        next false if pts.length < 3
        pts.all? { |p| InteriorPro::DormerManager.in_plan?(plan, at, p.x, p.y, -0.05) }
      end
      doomed.each { |f| f.erase! if f.respond_to?(:erase!) && f.valid? }
      puts "[Skylight] cut: #{rings.length} skin(s), #{doomed.length} piece(s) removed"
      rings
    rescue StandardError => e
      puts "[Skylight] cut_rect!: #{e.class}: #{e.message}"
      []
    end

    # WHICH HOLES ARE OURS (2026-09-14). The tile machine grows a dormer's
    # hole out to the wall face and lets a run hide under the wall; a
    # skylight's frame stands ON the deck's own edge, so its hole must
    # not grow and nothing may cross it. This answers 0.0 for a hole whose
    # centre is a skylight's click point, nil for anything else - see
    # RoofTilePlace.hole_th_for. Pure apart from reading the attributes.
    def self.hole_th_proc(roof)
      pts = skylight_points(roof)
      lambda do |hole|
        next nil if pts.empty? || hole.nil? || hole.length < 3
        cx = hole.map { |p| p.x.to_f }.sum / hole.length
        cy = hole.map { |p| p.y.to_f }.sum / hole.length
        near = pts.any? { |x, y| Math.sqrt((x - cx)**2 + (y - cy)**2) <= hole_match_tol }
        near ? 0.0 : nil
      end
    end

    def self.hole_match_tol
      3.0
    end

    # the click points of every skylight standing on this roof
    def self.skylight_points(roof)
      return [] if roof.nil? || !roof.respond_to?(:entities)
      roof.entities.grep(Sketchup::Group).map do |g|
        next nil unless g.get_attribute('InteriorPro', 'type') == 'skylight'
        xy = g.get_attribute('InteriorPro', 'at_xy')
        xy.is_a?(Array) && xy.length == 2 ? [xy[0].to_f, xy[1].to_f] : nil
      end.compact
    rescue StandardError
      []
    end

    def self.relay_tiles!(roof)
      return 0 unless defined?(InteriorPro::RoofTilePlace) &&
                      InteriorPro::RoofTilePlace.respond_to?(:relay_runs!)
      InteriorPro::RoofTilePlace.relay_runs!(roof)
    rescue StandardError => e
      puts "[Skylight] relay_tiles!: #{e.message}"
      0
    end

    # ---------- EDIT / MOVE / DELETE -----------------------------------

    # The roof group this skylight stands in.
    def self.roof_of(g)
      return nil if g.nil? || !g.valid?
      Sketchup.active_model.entities.grep(Sketchup::Group).find do |r|
        r.valid? && r.get_attribute('InteriorPro', 'type') == 'roof' &&
          r.entities.include?(g)
      end
    rescue StandardError
      nil
    end

    def self.spec_of(g)
      clean_spec(width: g.get_attribute('InteriorPro', 'width'),
                 height: g.get_attribute('InteriorPro', 'height'),
                 color: g.get_attribute('InteriorPro', 'color'))
    end

    # The hole's own ring in plan, as it was cut - saved on the group so
    # Delete closes the hole that is really there, not one recomputed
    # from a roof that may have changed since.
    def self.plan_xy_of(g)
      flat = g.get_attribute('InteriorPro', 'plan_xy')
      return nil unless flat.is_a?(Array) && flat.length >= 6
      flat.each_slice(2).map { |x, y| [x.to_f, y.to_f] }
    end

    # PURE: is (x, y) inside the ring, or within `slack` of it?
    def self.in_ring?(ring, x, y, slack = 0.5)
      return true if InteriorPro::DormerManager.point_in_ring?(ring, x, y)
      InteriorPro::DormerManager.ring_distance(ring, x, y) <= slack
    end

    # THE INVERSE OF THE CUT. Every inner loop lying inside the ring, on a
    # face of the right kind, is skinned again and its rim taken down -
    # through the dormer's own close_loop!, which is where the three hard
    # lessons of 2026-09-02B live (find_faces not add_face; rim after
    # skin; erase the seam). Returns how many openings were closed.
    def self.heal_ring!(ents, ring, level_only)
      return 0 if ents.nil? || ring.nil?
      found = []
      ents.grep(Sketchup::Face).each do |f|
        next unless f.valid? && f.respond_to?(:loops)
        nz = f.normal.z.abs
        next if level_only ? nz < 0.9 : nz < 0.2
        next if f.loops.length < 2
        f.loops.each do |lp|
          next if lp.outer?
          pts = lp.vertices.map(&:position)
          next unless pts.all? { |p| in_ring?(ring, p.x, p.y, 0.5) }
          found << [lp, f]
        end
      end
      done = 0
      found.each do |lp, host|
        done += 1 if InteriorPro::DormerManager.close_loop!(ents, lp, host, nil)
      end
      stray = ents.grep(Sketchup::Edge).select do |e|
        next false unless e.valid? && e.faces.empty?
        in_ring?(ring, e.start.position.x, e.start.position.y, 0.5) &&
          in_ring?(ring, e.end.position.x, e.end.position.y, 0.5)
      end
      ents.erase_entities(stray) unless stray.empty?
      done
    rescue StandardError => e
      puts "[Skylight] heal_ring!: #{e.class}: #{e.message}"
      0
    end

    # Take one skylight out and close the holes it cut - in the roof and
    # in the ceiling under it. Returns true when the group is gone.
    def self.remove!(g, opts = {})
      return false if g.nil? || !g.valid?
      return false unless g.get_attribute('InteriorPro', 'type') == 'skylight'
      roof = roof_of(g)
      ring = plan_xy_of(g)
      model = Sketchup.active_model
      g.erase! if g.valid?
      closed = 0
      if ring
        closed += heal_ring!(roof.entities, ring, false) if roof
        model.entities.grep(Sketchup::Group).each do |c|
          next unless c.valid? && c.get_attribute('InteriorPro', 'type') == 'ceiling'
          closed += heal_ring!(c.entities, ring, true)
        end
      end
      puts "[Skylight] removed, #{closed} opening(s) closed"
      relay_tiles!(roof) if roof && !opts[:no_relay]
      true
    rescue StandardError => e
      puts "[Skylight] remove!: #{e.class}: #{e.message}"
      false
    end

    # Edit: the same place, new numbers. Returns the new group.
    def self.replace!(g, spec)
      roof = roof_of(g)
      xy = g.get_attribute('InteriorPro', 'at_xy')
      return warn_nil('that skylight has no place saved on it') unless
        roof && xy.is_a?(Array) && xy.length == 2
      sp = clean_spec(spec)
      return nil unless remove!(g, no_relay: true)
      place_on_roof!(roof, xy[0].to_f, xy[1].to_f, sp)
    end

    # Move: the same numbers, a new place. Returns the new group.
    def self.move!(g, x, y)
      roof = roof_of(g)
      return warn_nil('that skylight is not on a roof') if roof.nil?
      sp = spec_of(g)
      return nil unless remove!(g, no_relay: true)
      place_on_roof!(roof, x.to_f, y.to_f, sp)
    end

    # ---------- SURVIVING A ROOF REBUILD ------------------------------

    # Every skylight on these roofs, as {x:, y:, spec:} - enough to put it
    # back on a new roof at the same plan point with the same numbers.
    def self.harvest(groups)
      saved = []
      Array(groups).each do |r|
        next unless r.respond_to?(:entities) && r.valid?
        r.entities.grep(Sketchup::Group).each do |g|
          next unless g.get_attribute('InteriorPro', 'type') == 'skylight'
          xy = g.get_attribute('InteriorPro', 'at_xy')
          next unless xy.is_a?(Array) && xy.length == 2
          saved << { x: xy[0].to_f, y: xy[1].to_f,
                     spec: clean_spec(width: g.get_attribute('InteriorPro', 'width'),
                                      height: g.get_attribute('InteriorPro', 'height'),
                                      color: g.get_attribute('InteriorPro', 'color')) }
        end
      end
      saved
    rescue StandardError => e
      puts "[Skylight] harvest: #{e.message}"
      []
    end

    def self.replant!(roof, saved)
      return 0 if roof.nil? || saved.nil? || saved.empty?
      back = 0
      saved.each do |d|
        back += 1 unless place_on_roof!(roof, d[:x], d[:y],
                                        d[:spec].merge(no_relay: true)).nil?
      end
      # one relay for all of them, after every hole is cut
      relay_tiles!(roof) if back.positive?
      lost = saved.length - back
      puts "[Skylight] #{back} skylight(s) put back on the new roof" if back.positive?
      puts "[Skylight] #{lost} skylight(s) could not be put back" if lost.positive?
      back
    rescue StandardError => e
      puts "[Skylight] replant!: #{e.message}"
      0
    end
  end
end
