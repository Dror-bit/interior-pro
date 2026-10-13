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

    # The boxes it is made of: [x0, x1, y0, y1, z0, z1, material key].
    # x along the wall (0 = its middle), y out of the wall (0 = its back),
    # z up (0 = its middle). Each box goes in its OWN group - the crash law
    # (CLAUDE.md 2026-09-12). PURE.
    def self.boxes(kind, gangs)
      kind = kind_ok(kind)
      w = plate_w(gangs)
      out = [[-w / 2.0, w / 2.0, 0.0, PLATE_T, -PLATE_H / 2.0, PLATE_H / 2.0, :plate]]
      if kind == 'outlet'
        [0.75, -0.75].each do |dz|
          f = PLATE_T
          out << [-0.65, 0.65, f, f + 0.12, dz - 0.6, dz + 0.6, :plate]
          # two upright slots and the round ground under them (a square
          # stand-in for the round hole - it reads the same at plan size)
          out << [-0.34, -0.26, f + 0.12, f + 0.14, dz + 0.05, dz + 0.42, :dark]
          out << [0.26, 0.34, f + 0.12, f + 0.14, dz + 0.05, dz + 0.42, :dark]
          out << [-0.1, 0.1, f + 0.12, f + 0.14, dz - 0.42, dz - 0.2, :dark]
        end
      else
        gangs_ok(kind, gangs).times do |i|
          cx = -w / 2.0 + PLATE_W / 2.0 + i * GANG
          out << [cx - 0.17, cx + 0.17, PLATE_T, PLATE_T + 0.08, -0.45, 0.45, :plate]
          # the toggle, up
          out << [cx - 0.12, cx + 0.12, PLATE_T + 0.08, PLATE_T + 0.45, 0.0, 0.35, :plate]
        end
      end
      out
    end

    def self.def_name(kind, gangs)
      kind = kind_ok(kind)
      kind == 'switch' ? "InteriorPro_Elec_switch_#{gangs_ok(kind, gangs)}" : "InteriorPro_Elec_#{kind}"
    end

    def self.material(model, key)
      name, rgb = key == :dark ? ['InteriorPro_Elec_Dark', [40, 40, 40]] : ['InteriorPro_Elec_White', [245, 245, 242]]
      m = model.materials[name] || model.materials.add(name)
      m.color = Sketchup::Color.new(*rgb) if m.respond_to?(:color=)
      m
    end

    def self.definition_for(model, kind, gangs)
      dn = def_name(kind, gangs)
      d = model.definitions[dn]
      return d if d && (!d.respond_to?(:valid?) || d.valid?) && !d.entities.to_a.empty?
      d ||= model.definitions.add(dn)
      boxes(kind, gangs).each do |x0, x1, y0, y1, z0, z1, mk|
        add_box(d.entities.add_group.entities, x0, x1, y0, y1, z0, z1, material(model, mk))
      end
      d
    end

    # A box from its floor face, pushed up. The points go clockwise seen
    # from above, so the face looks DOWN and the pushpull goes up.
    def self.add_box(ents, x0, x1, y0, y1, z0, z1, mat)
      pts = [[x0, y0], [x0, y1], [x1, y1], [x1, y0]].map { |x, y| Geom::Point3d.new(x, y, z0) }
      f = ents.add_face(pts)
      return if f.nil?
      f.reverse! if f.normal.z > 0 && f.respond_to?(:reverse!)
      f.pushpull(-(z1 - z0))
      ents.grep(Sketchup::Face).each { |fc| fc.material = mat }
    end

    # What the plumbing tool works with: ONE part, its line = its middle,
    # its height = the window's number to its middle.
    def self.layout(model, cfg)
      kind = kind_ok(cfg['kind'])
      g = gangs_ok(kind, cfg['gangs'])
      d = definition_for(model, kind, g)
      w = plate_w(g)
      depth = boxes(kind, g).map { |b| b[3] }.max
      [{ part: nil, defn: d, du: 0.0, h: cfg['height'].to_f, ax: 0.0, az: 0.0, gap: 0.0,
         minx: -w / 2.0, maxx: w / 2.0, miny: 0.0, maxy: depth, minz: -PLATE_H / 2.0, maxz: PLATE_H / 2.0 }]
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
      grp.name = kind == 'switch' ? "InteriorPro_Switch_#{g}" : 'InteriorPro_Outlet'
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
        'type' => 'electrical', 'kind' => kind, 'gangs' => g, 'height_in' => cfg['height'].to_f,
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
