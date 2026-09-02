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

    # Methods, not constants: a constant is not re-read by reload!.
    def self.default_width;  30.0; end   # across the slope
    def self.default_height; 46.0; end   # up the slope
    def self.lip_height;      1.0; end   # how far the frame stands above the roof
    def self.glass_drop;      1.0; end   # how far the glass sits below the roof face
    def self.curb_height;    lip_height; end   # old name, same number
    def self.frame_width;     2.0; end   # the border round the glass
    def self.default_color;  '#ffffff'; end
    def self.min_size;       12.0; end
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
      grp.set_attribute('InteriorPro', 'created_at', Time.now.to_s)
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
        back += 1 unless place_on_roof!(roof, d[:x], d[:y], d[:spec]).nil?
      end
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
