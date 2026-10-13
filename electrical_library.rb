# encoding: utf-8
# Interior Pro - ELECTRICAL ON THE WALL (2026-10-12, step 1)
#
# His words: "חשמל אני רוצה שקעים של אוטלייט שאוכל לשים על הקיר כל מה
# שאני שם על הקיר אני צריך לקבוע לו את הגובה ... בקופסת רפאים", "מתגים
# עד 5 מחוברים". His picks: "1" = the classic look, and "שלושה חורים
# שקע אמריקאי" = a US duplex outlet, two slots and a round ground each.
#
# Step 1 = an OUTLET and a SWITCH plate of 1 to 5 switches, on the face of
# an Interior Pro wall, at a height he sets. The tool is the plumbing tool
# inherited (electrical_tool.rb); this file owns the parts and the placing.
#
# Sizes (found on the web 2026-10-12, Pro Tool Reviews / Leviton):
#   plate 2.75" x 4.5", every extra switch +1.8125" of width
#   outlet: 16" to the BOTTOM of the box = about 18" to its middle
#   switch: 48" to the middle
# The height in the window is ALWAYS to the MIDDLE of the plate.
#
# Not here yet (his list): ceiling lights, wall lights, the bathroom fan,
# the 240V outlet, the elevation and the 2D. Outside the house: not now -
# his words "כל מה שבחוץ אל תגע כרגע".
require 'json'
require 'fileutils'

module InteriorPro
  module ElectricalLibrary
    # Kill switch: false = the Electrical button does nothing, nothing placed.
    USE_ELECTRICAL = true unless const_defined?(:USE_ELECTRICAL, false)

    PLATE_W = 2.75 unless const_defined?(:PLATE_W, false)
    PLATE_H = 4.5 unless const_defined?(:PLATE_H, false)
    PLATE_T = 0.25 unless const_defined?(:PLATE_T, false)
    GANG = 1.8125 unless const_defined?(:GANG, false)
    MAX_GANGS = 5 unless const_defined?(:MAX_GANGS, false)

    # A method, not a guarded constant, so reload! sees changes.
    def self.kinds
      {
        'outlet' => { label: 'Outlet', height: 18.0 },
        'switch' => { label: 'Switch', height: 48.0, gangs: true }
      }
    end

    # HIS OWN FILES (2026-10-12, his words: "תפתח תיקיה שאליה אני יעלה את
    # המוצרים"). Like the plumbing: one .skp a product, in
    #   assets/ELECTRICAL/OUTLETS/<name>.skp
    #   assets/ELECTRICAL/SWITCHES/<name>.skp
    # picked from a list with pictures, "+ Add new" copies any .skp in, and
    # "Save selected" saves a group from the model as a new product. How a
    # file is placed: its BACK (lowest green) on the wall face, the middle
    # of its width on the line, the middle of its height at the height he
    # typed. The built-in boxes ('Simple') show only while a folder is empty.
    SIMPLE = 'Simple' unless const_defined?(:SIMPLE, false)

    def self.dir_for(kind)
      sub = kind_ok(kind) == 'switch' ? 'SWITCHES' : 'OUTLETS'
      File.join(InteriorPro::PLUGIN_DIR, 'assets', 'ELECTRICAL', sub)
    end

    def self.file_for(kind, name)
      File.join(dir_for(kind), "#{name}.skp")
    end

    def self.names(kind)
      dir = dir_for(kind)
      return [] unless Dir.exist?(dir)
      Dir.glob(File.join(dir, '*.skp')).map { |f| File.basename(f, '.skp') }.sort
    end

    def self.products(kind)
      n = names(kind)
      n.empty? ? [SIMPLE] : n
    end

    def self.simple?(name)
      name.to_s.empty? || name.to_s == SIMPLE
    end

    def self.thumb_path(kind, name)
      File.join(dir_for(kind), 'thumbs', "#{name}.png")
    end

    def self.ensure_thumb(model, kind, name)
      return nil if simple?(name)
      tp = thumb_path(kind, name)
      return tp if File.exist?(tp)
      d = definition_for(model, kind, 1, name)
      return nil unless d
      FileUtils.mkdir_p(File.dirname(tp))
      d.save_thumbnail(tp) ? tp : nil
    rescue StandardError => e
      puts "[Electrical] no picture for #{kind}/#{name}: #{e.message}"
      nil
    end

    def self.add_file!(kind, src)
      return nil unless src && File.exist?(src) && src.downcase.end_with?('.skp')
      dir = dir_for(kind)
      FileUtils.mkdir_p(dir)
      name = InteriorPro::FixtureLibrary.clean_name(File.basename(src, '.*'), names(kind) + [SIMPLE])
      FileUtils.cp(src, File.join(dir, "#{name}.skp"))
      puts "[Electrical] added #{kind}/#{name} from #{src}"
      ensure_thumb(Sketchup.active_model, kind, name)
      name
    rescue StandardError => e
      puts "[Electrical] could not add #{src}: #{e.message}"
      nil
    end

    def self.save_selected!(kind, ent, name)
      return nil unless InteriorPro::FixtureLibrary.saveable?(ent)
      dir = dir_for(kind)
      FileUtils.mkdir_p(dir)
      nm = InteriorPro::FixtureLibrary.clean_name(name, names(kind) + [SIMPLE])
      path = File.join(dir, "#{nm}.skp")
      d = ent.respond_to?(:definition) ? ent.definition : nil
      ok = d && d.respond_to?(:save_as) ? d.save_as(path) : false
      unless ok
        puts "[Electrical] could not save #{nm}"
        return nil
      end
      puts "[Electrical] saved #{kind}/#{nm}"
      ensure_thumb(Sketchup.active_model, kind, nm)
      nm
    rescue StandardError => e
      puts "[Electrical] could not save #{name}: #{e.message}"
      nil
    end

    def self.kind_ok(kind)
      kinds.key?(kind.to_s) ? kind.to_s : kinds.keys.first
    end

    def self.default_height(kind)
      kinds[kind_ok(kind)][:height]
    end

    # 1..5 for a switch plate, always 1 for an outlet. PURE.
    def self.gangs_ok(kind, n)
      return 1 unless kinds[kind_ok(kind)][:gangs]
      g = n.to_i
      g = 1 if g < 1
      g = MAX_GANGS if g > MAX_GANGS
      g
    end

    # The plate is 2.75" wide for one, +1.8125" for every one more. PURE.
    def self.plate_w(gangs)
      PLATE_W + (gangs.to_i - 1) * GANG
    end

    # THE LOOK (2026-10-12). His picks on electrical_look2.png: "המתגים
    # צריכים להיות יותר מודרנים" = flat rocker switches (Decora). Then he
    # sent a photo of a real two-rocker plate: "ככה זה צריך להיראות" - a wide
    # bevelled edge, a thin frame round each rocker, the rocker TILTED (one
    # end pressed in, the other standing out), and two screws a switch, above
    # and below it. The photo wins over his earlier "בלי" (no screws).
    # The outlet keeps the real US shape: a face with flat sides and round
    # top and bottom, a short slot, a long slot, the D-shaped ground under
    # them, and one screw between the two.
    #
    # The pieces: [:slab, x0, x1, z0, z1, y0, y1, inset, material, y1_top]
    # = a slab whose front is `inset` smaller all round (the bevelled edge);
    # with y1_top its front leans - y1 at the bottom, y1_top at the top (the
    # tilted rocker). [:prism, [[x, z], ...], y0, y1, material] = an outline
    # pushed out of the wall. x along the wall (0 = its middle), y out of
    # the wall (0 = its back), z up (0 = its middle). Each piece goes in its
    # OWN group - the crash law (CLAUDE.md 2026-09-12). PURE.
    BEVEL = 0.2 unless const_defined?(:BEVEL, false)
    SCREW_Z = 1.69 unless const_defined?(:SCREW_Z, false)

    def self.pieces(kind, gangs)
      kind = kind_ok(kind)
      w = plate_w(gangs)
      t = PLATE_T
      out = [plate_loft(w, PLATE_H, t)]
      if kind == 'outlet'
        [0.95, -0.95].each do |dz|
          out << [:prism, round_rect(0.0, dz, 1.24, 1.32, 0.5), t, t + 0.08, :face]
          f = t + 0.08
          out << [:prism, rect(-0.36, dz + 0.02, -0.29, dz + 0.29), f, f + 0.01, :dark] # short slot
          out << [:prism, rect(0.29, dz + 0.02, 0.36, dz + 0.35), f, f + 0.01, :dark]   # long slot
          out << [:prism, d_shape(0.0, dz - 0.28, 0.11, 0.14), f, f + 0.01, :dark]       # ground
        end
        out.concat(screw(0.0, 0.0, t))
      else
        gangs_ok(kind, gangs).times do |i|
          cx = -w / 2.0 + PLATE_W / 2.0 + i * GANG
          out << [:slab, cx - 0.66, cx + 0.66, -1.31, 1.31, t, t + 0.02, 0.0, :frame]
          # the rocker: bottom end out, top end in, as in his photo
          out << [:slab, cx - 0.6, cx + 0.6, -1.25, 1.25, t + 0.02, t + 0.2, 0.02, :face, t + 0.06]
          out.concat(screw(cx, SCREW_Z, t))
          out.concat(screw(cx, -SCREW_Z, t))
        end
      end
      out
    end

    # THE PLATE IS ROUND AT ITS EDGE (2026-10-12, his words: "הקצוות של
    # הקופסא מסביב הם בעיגול כזה לא פינות חדות"): round corners seen from
    # the front, and the bevel itself a curve, not one slope. Rings of the
    # same outline, smaller as they come off the wall, on a quarter curve.
    # [:loft, [[y, outline], ...], material]. PURE.
    PLATE_R = 0.18 unless const_defined?(:PLATE_R, false)
    def self.plate_loft(w, h, t, steps = 4)
      rings = (0..steps).map do |k|
        a = (Math::PI / 2.0) * k / steps
        inset = BEVEL * (1.0 - Math.cos(a))
        y = t * Math.sin(a)
        [y, round_rect(0.0, 0.0, w - 2.0 * inset, h - 2.0 * inset, PLATE_R)]
      end
      [:loft, rings, :plate]
    end

    # A screw head on the plate face: a low round head with a slot.
    def self.screw(cx, cz, t)
      [[:prism, circle(cx, cz, 0.14, 12), t, t + 0.03, :face],
       [:prism, rect(cx - 0.018, cz - 0.11, cx + 0.018, cz + 0.11), t + 0.03, t + 0.035, :frame]]
    end

    def self.circle(cx, cz, r, n)
      (0...n).map { |k| a = 2.0 * Math::PI * k / n; [cx + r * Math.cos(a), cz + r * Math.sin(a)] }
    end

    def self.rect(x0, z0, x1, z1)
      [[x0, z0], [x1, z0], [x1, z1], [x0, z1]]
    end

    # A rectangle with round corners of radius r, 4 steps a corner. PURE.
    def self.round_rect(cx, cz, w, h, r, steps = 4)
      r = [r, w / 2.0, h / 2.0].min
      corners = [[cx + w / 2.0 - r, cz + h / 2.0 - r, 0.0], [cx - w / 2.0 + r, cz + h / 2.0 - r, 90.0],
                 [cx - w / 2.0 + r, cz - h / 2.0 + r, 180.0], [cx + w / 2.0 - r, cz - h / 2.0 + r, 270.0]]
      corners.flat_map do |x, z, a0|
        (0..steps).map do |k|
          a = (a0 + 90.0 * k / steps) * Math::PI / 180.0
          [x + r * Math.cos(a), z + r * Math.sin(a)]
        end
      end
    end

    # The US ground hole: round on top, flat on the bottom. PURE.
    def self.d_shape(cx, cz, r, h, steps = 8)
      top = (0..steps).map do |k|
        a = Math::PI * k / steps
        [cx + r * Math.cos(a), cz + h - r + r * Math.sin(a)]
      end
      top + [[cx - r, cz], [cx + r, cz]]
    end

    # A new name for the new look: a definition already in his model is
    # reused by name (CLAUDE.md: an old component in his model wins over the
    # code), so the first look's plates stay as they are and new ones get
    # the new look.
    def self.def_name(kind, gangs, name = nil)
      kind = kind_ok(kind)
      return "InteriorPro_Elec_#{kind}_#{name}" unless simple?(name)
      kind == 'switch' ? "InteriorPro_Elec4_switch_#{gangs_ok(kind, gangs)}" : "InteriorPro_Elec4_#{kind}"
    end

    COLORS = { plate: [248, 247, 243], face: [252, 251, 248], frame: [233, 231, 225], dark: [43, 43, 43] }.freeze unless const_defined?(:COLORS, false)

    def self.material(model, key)
      name = "InteriorPro_Elec_#{key.to_s.capitalize}"
      m = model.materials[name] || model.materials.add(name)
      m.color = Sketchup::Color.new(*COLORS[key]) if m.respond_to?(:color=) && COLORS[key]
      m
    end

    # His file (or the stand-in). CAUTION (CLAUDE.md): an old definition in
    # the model wins over the file - after changing a file, purge first.
    def self.definition_for(model, kind, gangs, name = nil)
      dn = def_name(kind, gangs, name)
      d = model.definitions[dn]
      unless simple?(name)
        if d && d.valid?
          InteriorPro::FixtureLibrary.strip_hidden!(d)
          return d
        end
        path = file_for(kind, name)
        unless File.exist?(path)
          puts "[Electrical] file not found: #{path}"
          return nil
        end
        d = model.definitions.load(path, allow_newer: true)
        if d && d.valid?
          d.name = dn
          InteriorPro::FixtureLibrary.strip_hidden!(d)
        end
        return d
      end
      return d if d && (!d.respond_to?(:valid?) || d.valid?) && !d.entities.to_a.empty?
      d ||= model.definitions.add(dn)
      pieces(kind, gangs).each do |pc|
        ents = d.entities.add_group.entities
        if pc[0] == :loft
          add_loft(ents, pc[1], material(model, pc[2]))
        elsif pc[0] == :slab
          _, x0, x1, z0, z1, y0, y1, inset, mk, y1_top = pc
          add_slab(ents, x0, x1, z0, z1, y0, y1, inset, material(model, mk), y1_top)
        else
          _, outline, y0, y1, mk = pc
          add_prism(ents, outline, y0, y1, material(model, mk))
        end
      end
      d
    end

    def self.pt(x, y, z)
      Geom::Point3d.new(x.to_f, y.to_f, z.to_f)
    end

    # A slab with a bevelled front: the back is the full rectangle, the
    # front is `inset` smaller all round, four sloped sides between them.
    def self.add_slab(ents, x0, x1, z0, z1, y0, y1, inset, mat, y1_top = nil)
      yt = y1_top || y1
      b = [pt(x0, y0, z0), pt(x1, y0, z0), pt(x1, y0, z1), pt(x0, y0, z1)]
      f = [pt(x0 + inset, y1, z0 + inset), pt(x1 - inset, y1, z0 + inset),
           pt(x1 - inset, yt, z1 - inset), pt(x0 + inset, yt, z1 - inset)]
      # (x right, z up) in this order looks into the wall: right for the
      # back, turned round for the front
      ents.add_face(b)
      ents.add_face(f.reverse)
      4.times do |i|
        j = (i + 1) % 4
        ents.add_face([b[i], b[j], f[j], f[i]])
      end
      paint(ents, mat)
    end

    # Both sides of every face, so a face SketchUp turned round never shows
    # the default blue.
    def self.paint(ents, mat)
      ents.grep(Sketchup::Face).each do |fc|
        fc.material = mat
        fc.back_material = mat if fc.respond_to?(:back_material=)
      end
    end

    # Rings of the same number of points, joined side by side; the back
    # and the front ring closed with a face. The edges round the curve are
    # softened, so it reads as ONE round edge, not steps.
    def self.add_loft(ents, rings, mat)
      pts = rings.map { |y, outline| outline.map { |x, z| pt(x, y, z) } }
      ents.add_face(pts.first)
      ents.add_face(pts.last.reverse)
      pts.each_cons(2) do |r0, r1|
        n = r0.length
        n.times do |i|
          j = (i + 1) % n
          ents.add_face([r0[i], r0[j], r1[j], r1[i]])
        end
      end
      paint(ents, mat)
      soften(ents)
    end

    # Soft + smooth every edge between two faces that meet at under 40
    # degrees - the facets of a curve, not a real corner.
    def self.soften(ents)
      return unless defined?(Sketchup::Edge)
      ents.grep(Sketchup::Edge).each do |e|
        next unless e.respond_to?(:faces) && e.faces.length == 2
        ang = e.faces[0].normal.angle_between(e.faces[1].normal)
        next if ang > 40.0 * Math::PI / 180.0
        e.soft = true
        e.smooth = true
      end
    rescue StandardError => er
      puts "[Electrical] soften: #{er.message}"
    end

    # An outline on the plane y0, pushed out of the wall to y1.
    def self.add_prism(ents, outline, y0, y1, mat)
      fc = ents.add_face(outline.map { |x, z| pt(x, y0, z) })
      return if fc.nil?
      # the face must look INTO the wall (-y) so the pushpull goes out
      fc.reverse! if fc.normal.y > 0 && fc.respond_to?(:reverse!)
      fc.pushpull(-(y1 - y0))
      paint(ents, mat)
    end

    # What the plumbing tool works with: ONE part, its line = its middle,
    # its height = the window's number to its middle.
    def self.layout(model, cfg)
      kind = kind_ok(cfg['kind'])
      g = gangs_ok(kind, cfg['gangs'])
      name = cfg['product']
      d = definition_for(model, kind, g, name)
      if d.nil?
        puts "[Electrical] nothing to place - #{kind}/#{name} could not be loaded"
        return []
      end
      if simple?(name)
        w = plate_w(g)
        depth = pieces(kind, g).map { |pc| pc[0] == :loft ? pc[1].last[0] : (pc[0] == :slab ? [pc[6], pc[9].to_f].max : pc[3]) }.max
        minx, maxx, miny, maxy, minz, maxz = -w / 2.0, w / 2.0, 0.0, depth, -PLATE_H / 2.0, PLATE_H / 2.0
      else
        b = InteriorPro::FixtureLibrary.visible_bounds(d)
        minx, maxx, miny, maxy, minz, maxz = b.min.x.to_f, b.max.x.to_f, b.min.y.to_f, b.max.y.to_f, b.min.z.to_f, b.max.z.to_f
      end
      # the line = the middle of its width, the height = the middle of its height
      [{ part: nil, defn: d, du: 0.0, h: cfg['height'].to_f, ax: (minx + maxx) / 2.0, az: (minz + maxz) / 2.0, gap: 0.0,
         minx: minx, maxx: maxx, miny: miny, maxy: maxy, minz: minz, maxz: maxz }]
    end

    # Does the plate cover a hole (door, window, niche)? Only ON it - a wire
    # can run past a window, unlike a pipe. PURE.
    def self.on_hole?(u0, u1, z0, z1, holes, eps = 1.0e-6)
      Array(holes).any? do |h|
        u0.to_f < h[2].to_f - eps && u1.to_f > h[0].to_f + eps &&
          z0.to_f < h[3].to_f - eps && z1.to_f > h[1].to_f + eps
      end
    end

    # ONE CHECK for the tool: does it fit with its middle at u?
    # { ok:, lo:, hi:, outs:, rects:, on_hole:, outside: }
    def self.check(wall, side, fr, u, parts, wall_h)
      lo, hi = InteriorPro::TileWall.face_limits(wall, fr, u)
      holes = InteriorPro::FixtureLibrary.holes_on(wall, fr, side)
      res = { ok: !parts.empty?, lo: lo, hi: hi, outs: [], rects: [], on_hole: false, no_tile: false }
      parts.each do |p|
        u0, u1, z0, z1 = InteriorPro::FixtureLibrary.part_rect(p, u)
        res[:rects] << [u0, u1, z0, z1]
        res[:ok] = false if u0 < lo - 1.0e-6 || u1 > hi + 1.0e-6 || z0 < -1.0e-6 || z1 > wall_h.to_f + 1.0e-6
        res[:on_hole] = true if on_hole?(u0, u1, z0, z1, holes)
        # on a tiled backsplash it stands on the tile, not inside it
        t = InteriorPro::FixtureLibrary.tile_under(wall, side, u0, u1, z0, z1)
        res[:outs] << (t ? t[:out].to_f : 0.0)
      end
      res[:outside] = InteriorPro::FixtureLibrary.outside?(wall, side)
      res[:ok] = false if res[:on_hole] || res[:outside]
      res
    end

    # Put it on the face: ONE group with the plate inside. ONE undo step.
    def self.place!(wall:, side:, fr:, u:, cfg:, parts:, outs:, op: true)
      model = Sketchup.active_model
      model.start_operation('Place Electrical', true) if op
      kind = kind_ok(cfg['kind'])
      g = gangs_ok(kind, cfg['gangs'])
      grp = model.entities.add_group
      grp.name = simple?(cfg['product']) ? (kind == 'switch' ? "InteriorPro_Switch_#{g}" : 'InteriorPro_Outlet') : "InteriorPro_#{kind.capitalize}_#{cfg['product']}"
      parts.each_with_index do |p, i|
        shift = Geom::Transformation.translation(Geom::Vector3d.new(-p[:ax], -p[:miny], -p[:az]))
        x, y, zz = InteriorPro::TileWall.world(fr, u + p[:du], p[:h], outs[i].to_f)
        face = Geom::Transformation.axes(Geom::Point3d.new(x, y, zz),
                                         Geom::Vector3d.new(fr[:ux], fr[:uy], 0),
                                         Geom::Vector3d.new(fr[:nx], fr[:ny], 0),
                                         Geom::Vector3d.new(0, 0, 1))
        grp.entities.add_instance(p[:defn], face * shift)
      end
      {
        'type' => 'electrical', 'kind' => kind, 'gangs' => g, 'product' => cfg['product'].to_s, 'height_in' => cfg['height'].to_f,
        'u_in' => u.to_f, 'side' => side.to_s, 'host_wall_id' => wall.get_attribute('InteriorPro', 'id').to_s,
        'level' => (wall.get_attribute('InteriorPro', 'level') || 1).to_i,
        'id' => "elec-#{Time.now.to_i.to_s(36)}-#{rand(10_000)}", 'created_at' => Time.now.to_s
      }.each { |k, v| grp.set_attribute('InteriorPro', k, v) }
      InteriorPro.assign_tag(grp, 'IP/Electrical') if InteriorPro.respond_to?(:assign_tag)
      model.commit_operation if op
      puts "[Electrical] placed #{kind}#{kind == 'switch' ? " x#{g}" : ''} at #{cfg['height'].to_f.round(2)}\" " \
           "on wall #{wall.get_attribute('InteriorPro', 'id')} side #{side} u #{u.to_f.round(2)}"
      grp
    rescue StandardError => e
      model&.abort_operation if op
      puts "[Electrical] place failed: #{e.message}"
      nil
    end

    def self.electrical?(e)
      (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && e.valid? &&
        e.get_attribute('InteriorPro', 'type') == 'electrical'
    end

    # MEASURE, DO NOT GUESS: every click writes one line next to the code.
    def self.trace(line)
      File.open(File.join(__dir__, 'electrical_trace.txt'), 'a:UTF-8') do |f|
        f.puts "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')} #{line}"
      end
    rescue StandardError => e
      puts "[Electrical] trace failed: #{e.message}"
    end
  end
end
