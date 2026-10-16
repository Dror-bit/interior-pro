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
        'switch' => { label: 'Switch', height: 48.0, gangs: true },
        # WALL LIGHTS (2026-10-12, his files in WALL_LIGHTS): only his files,
        # no built-in stand-in. 66" to the middle - the bathroom rule of
        # thumb (60-66" each side of the mirror), hallway 60-72".
        'wall_light' => { label: 'Wall Light', height: 66.0, files_only: true, dir: 'WALL_LIGHTS', group: 'lighting' },
        # ON THE CEILING (2026-10-12, his pick "1": a click on the ceiling of
        # the room and it hangs there; the distances he sets later in 2D).
        # His file: the top (z 0) on the ceiling, its 0,0 under the click.
        'ceiling_light' => { label: 'Ceiling Light', height: 0.0, files_only: true, dir: 'CEILING_LIGHTS', group: 'lighting', mount: 'ceiling' },
        # RECESSED (2026-10-12, Codex's 4 files, 4"/6" round/square): hung
        # like a ceiling light - the trim on the ceiling, the can above it.
        # Its picture is seen FROM BELOW, or round and square look the same.
        'recessed' => { label: 'Recessed', height: 0.0, files_only: true, dir: 'RECESSED', group: 'lighting', mount: 'ceiling', thumb: :below, hole: true },
        # the fan's picture seen from above (his words: "את הצורה של המאוורר תעשה מלמעלה")
        'ceiling_fan' => { label: 'Ceiling Fan', height: 0.0, files_only: true, dir: 'CEILING_FANS', group: 'lighting', mount: 'ceiling', thumb: :below }
      }
    end

    # TWO WINDOWS, ONE BAR (2026-10-12, his words: "צריך להיות הבדל בין חשמל
    # לתאורה בגלריית הפתיחה הם אומנם באותו הסרגל אבל לא בגלריה"). The
    # Electrical button shows the 'electrical' kinds, the Lighting button the
    # 'lighting' ones. A kind with no :group is electrical.
    def self.group_of(kind)
      kinds[kind_ok(kind)][:group] || 'electrical'
    end

    def self.kinds_in(group)
      kinds.keys.select { |k| group_of(k) == group.to_s }
    end

    def self.ceiling?(kind)
      kinds[kind_ok(kind)][:mount] == 'ceiling'
    end

    # ---- ON THE CEILING ----------------------------------------------------
    # Kill switch: false = the ceiling kinds are not offered and nothing is
    # hung on a ceiling.
    USE_CEILING_MOUNT = true unless const_defined?(:USE_CEILING_MOUNT, false)

    # Is x,y inside the outline [[x, y], ...]? (even-odd) PURE.
    def self.inside_poly?(poly, x, y)
      inside = false
      j = poly.length - 1
      poly.each_with_index do |(xi, yi), i|
        xj, yj = poly[j]
        if (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi).to_f + xi
          inside = !inside
        end
        j = i
      end
      inside
    end

    # Every Interior Pro ceiling: { grp:, z: (its underside), poly: [[x, y]...], area: }
    def self.ceilings(model = Sketchup.active_model)
      model.entities.grep(Sketchup::Group).map do |g|
        next unless g.valid? && g.get_attribute('InteriorPro', 'type') == 'ceiling'
        fc = g.entities.grep(Sketchup::Face).min_by { |f| f.bounds.min.z }
        next if fc.nil?
        tr = g.transformation
        poly = fc.outer_loop.vertices.map { |v| p = v.position.transform(tr); [p.x.to_f, p.y.to_f] }
        { grp: g, z: g.bounds.min.z.to_f, poly: poly, area: fc.area.to_f }
      end.compact
    end

    # The ceiling the mouse ray meets first, and where: [ceiling, x, y] or
    # nil. Works from above (through the ceiling) and from below. PURE on
    # the list it is given.
    def self.ceiling_hit(list, eye, dir)
      best = nil
      list.each do |c|
        next if dir[2].abs < 1.0e-9
        t = (c[:z] - eye[2]) / dir[2].to_f
        next if t <= 0
        x = eye[0] + dir[0] * t
        y = eye[1] + dir[1] * t
        next unless inside_poly?(c[:poly], x, y)
        if best.nil? || t < best[3] - 1.0e-6 || ((t - best[3]).abs <= 1.0e-6 && c[:area] < best[0][:area])
          best = [c, x, y, t]
        end
      end
      best && best[0, 3]
    end

    # The ceiling right above x,y (the smallest one, if two overlap), for a
    # point the mouse locked onto. PURE on the list.
    def self.ceiling_over(list, x, y)
      list.select { |c| inside_poly?(c[:poly], x, y) }.min_by { |c| c[:area] }
    end

    # THE HOLE A RECESSED LIGHT NEEDS (his words: "זה צריך לעשות חור
    # בתקרה"): as wide as the part of his file that goes UP into the
    # ceiling (the can, z above 0). 0 = no hole. PURE on the lines.
    def self.hole_d_of(segs)
      xs = segs.select { |a, b| a[1] > 0.05 && b[1] > 0.05 }.flat_map { |a, b| [a[0], b[0]] }
      xs.empty? ? 0.0 : (xs.max - xs.min)
    end

    # Hang it: ONE group with his file inside, its 0,0,0 at x,y on the
    # underside of the ceiling. ONE undo step.
    def self.place_on_ceiling!(ceiling:, x:, y:, cfg:, op: true)
      model = Sketchup.active_model
      kind = kind_ok(cfg['kind'])
      d = definition_for(model, kind, 1, cfg['product'])
      if d.nil?
        puts "[Electrical] nothing to hang - #{kind}/#{cfg['product']} could not be loaded"
        return nil
      end
      model.start_operation('Place Light', true) if op
      grp = model.entities.add_group
      grp.name = "InteriorPro_#{kind.split('_').map(&:capitalize).join}_#{cfg['product']}"
      grp.entities.add_instance(d, Geom::Transformation.translation(Geom::Vector3d.new(x.to_f, y.to_f, ceiling[:z].to_f)))
      cg = ceiling[:grp]
      hole = kinds[kind][:hole] ? hole_d_of(front_segments(d)).round(3) : 0.0
      {
        'type' => 'electrical', 'kind' => kind, 'product' => cfg['product'].to_s, 'mount' => 'ceiling',
        'x_in' => x.to_f, 'y_in' => y.to_f, 'z_in' => ceiling[:z].to_f,
        'host_ceiling_id' => cg.get_attribute('InteriorPro', 'id').to_s, 'room_id' => cg.get_attribute('InteriorPro', 'room_id').to_s,
        'level' => (cg.get_attribute('InteriorPro', 'level') || 1).to_i, 'hole_d' => hole,
        'id' => "elec-#{Time.now.to_i.to_s(36)}-#{rand(10_000)}", 'created_at' => Time.now.to_s
      }.each { |k, v| grp.set_attribute('InteriorPro', k, v) }
      InteriorPro.assign_tag(grp, 'IP/Electrical') if InteriorPro.respond_to?(:assign_tag)
      # the ceiling is built again WITH the hole, in the same undo step
      if hole > 0.0 && defined?(InteriorPro::CeilingManager) && InteriorPro::CeilingManager::USE_CEILING_HOLES
        rid = cg.get_attribute('InteriorPro', 'room_id')
        room = InteriorPro::RoomManager.rooms_in_model.find { |r| r.get_attribute('InteriorPro', 'id') == rid }
        nc = room ? InteriorPro::CeilingManager.build_ceiling_for_room!(room) : nil
        trace("hole #{hole}\" for #{cfg['product']}: ceiling of #{rid} #{nc ? "built again (#{nc.get_attribute('InteriorPro', 'id')})" : 'NOT rebuilt - room not found'}")
        watch_holes!(model)
        hole_lights[grp.entityID] = rid
      end
      model.commit_operation if op
      grp
    rescue StandardError => e
      model&.abort_operation if op
      puts "[Electrical] hang failed: #{e.message}"
      nil
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
      k = kind_ok(kind)
      sub = kinds[k][:dir] || (k == 'switch' ? 'SWITCHES' : 'OUTLETS')
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
      return n if kinds[kind_ok(kind)][:files_only]
      n.empty? ? [SIMPLE] : n
    end

    def self.simple?(name)
      name.to_s.empty? || name.to_s == SIMPLE
    end

    # THE PICTURE STRAIGHT FROM THE FRONT (2026-10-12, his words: "למה
    # התמונות שלהם מופיעות באלכסון?"). save_thumbnail shoots from the camera
    # the file was saved with - at an angle. Now the picture is drawn here:
    # every hard edge of his file seen from the front (red = right, blue =
    # up), as lines in an .svg beside the file, drawn again whenever the
    # .skp is newer than the picture. Kill switch: false = the old .png.
    USE_FRONT_THUMB = true unless const_defined?(:USE_FRONT_THUMB, false)

    def self.thumb_path(kind, name)
      # a picture from above has its own name, so an old front picture is never shown for it
      top = USE_FRONT_THUMB && kinds[kind_ok(kind)][:thumb] == :below ? '.top' : ''
      File.join(dir_for(kind), 'thumbs', "#{name}#{top}.#{USE_FRONT_THUMB ? 'svg' : 'png'}")
    end

    def self.ensure_thumb(model, kind, name)
      return nil if simple?(name)
      tp = thumb_path(kind, name)
      if USE_FRONT_THUMB
        src = file_for(kind, name)
        return tp if File.exist?(tp) && (!File.exist?(src) || File.mtime(tp) >= File.mtime(src))
      elsif File.exist?(tp)
        return tp
      end
      d = definition_for(model, kind, 1, name)
      return nil unless d
      FileUtils.mkdir_p(File.dirname(tp))
      if USE_FRONT_THUMB
        segs = front_segments(d)
        # seen from below: x right, y up the picture (z dropped)
        segs = below_segments(d) if kinds[kind_ok(kind)][:thumb] == :below
        File.write(tp, front_svg(segs))
        trace("picture #{kind}/#{name}: front view, #{segs.length} lines -> #{File.basename(tp)}")
        return tp
      end
      d.save_thumbnail(tp) ? tp : nil
    rescue StandardError => e
      puts "[Electrical] no picture for #{kind}/#{name}: #{e.message}"
      nil
    end

    # Every hard edge in the file (nested groups too), seen from the front:
    # [[x, z], [x, z]] in the file's own inches. Soft, smooth and hidden
    # edges are left out - they are the curves and the insides.
    def self.front_segments(defn, tr = Geom::Transformation.new, out = [])
      defn.entities.each do |e|
        next if e.respond_to?(:hidden?) && e.hidden?
        next if e.respond_to?(:layer) && e.layer && !e.layer.visible?
        if e.is_a?(Sketchup::Edge)
          next if e.soft? || e.smooth?
          a = e.start.position.transform(tr)
          b = e.end.position.transform(tr)
          out << [[a.x.to_f, a.z.to_f], [b.x.to_f, b.z.to_f]]
        elsif e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          front_segments(e.definition, tr * e.transformation, out)
        end
      end
      out
    end

    # The same, seen from BELOW the ceiling: [[x, y], [x, y]]. PURE apart
    # from the walk.
    def self.below_segments(defn, tr = Geom::Transformation.new, out = [])
      defn.entities.each do |e|
        next if e.respond_to?(:hidden?) && e.hidden?
        next if e.respond_to?(:layer) && e.layer && !e.layer.visible?
        if e.is_a?(Sketchup::Edge)
          next if e.soft? || e.smooth?
          a = e.start.position.transform(tr)
          b = e.end.position.transform(tr)
          out << [[a.x.to_f, a.y.to_f], [b.x.to_f, b.y.to_f]]
        elsif e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          below_segments(e.definition, tr * e.transformation, out)
        end
      end
      out
    end

    # The lines as a picture: right = right, up = up, the same line twice
    # drawn once, a line seen end-on (it runs into the wall) dropped. PURE.
    def self.front_svg(segs)
      r = ->(v) { v.round(3) }
      seen = {}
      keep = []
      segs.each do |a, b|
        next if (a[0] - b[0]).abs < 1.0e-4 && (a[1] - b[1]).abs < 1.0e-4
        k = [[r.(a[0]), r.(a[1])], [r.(b[0]), r.(b[1])]].sort
        next if seen[k]
        seen[k] = true
        keep << k
      end
      return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"></svg>' if keep.empty?
      xs = keep.flat_map { |a, b| [a[0], b[0]] }
      zs = keep.flat_map { |a, b| [a[1], b[1]] }
      w = [xs.max - xs.min, 1.0e-3].max
      h = [zs.max - zs.min, 1.0e-3].max
      pad = 0.05 * [w, h].max
      vb = [xs.min - pad, -zs.max - pad, w + 2 * pad, h + 2 * pad].map { |v| r.(v) }.join(' ')
      d = keep.map { |a, b| "M#{a[0]} #{r.(-a[1])}L#{b[0]} #{r.(-b[1])}" }.join
      %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="#{vb}"><path d="#{d}" fill="none" stroke="#222" ) +
        %(stroke-width="#{r.([w, h].max / 140.0)}" stroke-linecap="round"/></svg>)
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
      ax = (minx + maxx) / 2.0
      az = (minz + maxz) / 2.0
      turn = turn_of(cfg)
      if turn == 90
        # TURNED (lying down): its width runs up the wall, its height along it
        hx = (maxx - minx) / 2.0
        hz = (maxz - minz) / 2.0
        minx, maxx, minz, maxz = ax - hz, ax + hz, az - hx, az + hx
      end
      [{ part: nil, defn: d, du: 0.0, h: cfg['height'].to_f, ax: ax, az: az, gap: 0.0, turn: turn,
         minx: minx, maxx: maxx, miny: miny, maxy: maxy, minz: minz, maxz: maxz }]
    end

    # LYING DOWN (2026-10-12, his list: "סימון לרוחב" - an outlet turned 90
    # degrees; his words: "אופציה בהתחלה של מאונך ומאוזן" = Vertical / Horizontal in the window).
    # Only an outlet turns. 'turn' = 0 or 90, saved on what is placed.
    # Kill switch: false = never turned.
    USE_TURN = true unless const_defined?(:USE_TURN, false)

    # COUNTERTOP OUTLET (2026-10-12, his list "Countertop outlet" and his
    # pick "2" = a tick box under the outlet). Ticked: 42" to its middle
    # (36" counter + 4" backsplash + 2"; the code allows up to 20" over the
    # counter), and the mark 'countertop' = true on what is placed - for the
    # elevation and the 2D later. Kill switch: false = no tick box.
    USE_COUNTERTOP = true unless const_defined?(:USE_COUNTERTOP, false)
    COUNTERTOP_H = 42.0 unless const_defined?(:COUNTERTOP_H, false)

    def self.countertop_of(cfg)
      USE_COUNTERTOP && kind_ok(cfg['kind']) == 'outlet' && cfg['countertop'] == true
    end

    def self.turn_of(cfg)
      return 0 unless USE_TURN && kind_ok(cfg['kind']) == 'outlet'
      cfg['turn'].to_i == 90 ? 90 : 0
    end

    # Does the plate cover a hole (door, window, niche)? Only ON it - a wire
    # can run past a window, unlike a pipe. PURE.
    def self.on_hole?(u0, u1, z0, z1, holes, eps = 1.0e-6)
      Array(holes).any? do |h|
        u0.to_f < h[2].to_f - eps && u1.to_f > h[0].to_f + eps &&
          z0.to_f < h[3].to_f - eps && z1.to_f > h[1].to_f + eps
      end
    end

    # ON THE KITCHEN BACKSPLASH TOO (2026-10-14 20:20, his words: "כל פלאג או שקע שיושב על באק ספלאש או טייל על קיר צריך
    # לעבור לקידמת הטיל ולא לשבת מאחוריו על הקיר או בתוכו"). Measured (debug_elec_front.rb): the outlet over the range
    # stood at 0 off the wall with the kitchen's backsplash pieces (KitchenLab worktop, 0.38" thick) over it. Now a thin
    # kitchen piece (worktop / backsplash, no more than KITCHEN_FRONT_MAX off the wall) over the plate's rectangle pushes
    # the plate out to its face, like an Interior Pro tile does. Off = the tile alone, as before.
    USE_KITCHEN_FRONT = true unless const_defined?(:USE_KITCHEN_FRONT, false)
    KITCHEN_FRONT_MAX = 3.0 unless const_defined?(:KITCHEN_FRONT_MAX, false)
    KITCHEN_FRONT_KINDS = %w[worktop backsplash].freeze unless const_defined?(:KITCHEN_FRONT_KINDS, false)
    # THE FACE BY A RAY (2026-10-15 14:26, his "המתגים והשקעים יושבים מאחורי הקאונטר טופ באק ספלאש"; measured
    # debug_elec_face.rb → elec_face_report.txt): the backsplash is now one L-shaped solid 1.5" thick - its BOX runs 145.9"
    # into the room, so kitchen_front threw it out and the outlet and the switch over the range stayed at 0.375, behind its
    # face. A ray from 12" in the room straight at the wall through the plate's middle and corners finds the real face: the
    # first kitchen worktop / backsplash it hits, no more than KITCHEN_FRONT_MAX off the wall (plates of ours are passed
    # through). The larger of the box rule and the ray wins. Off = the box rule alone, as before.
    USE_KITCHEN_RAY = true unless const_defined?(:USE_KITCHEN_RAY, false)

    # every kitchen group in the model, at any depth, with its world transformation: [[ent, kind, wxf], ...]
    def self.kitchen_pieces(model = Sketchup.active_model, ents = nil, xf = nil, depth = 0, out = [])
      ents ||= model.entities
      xf ||= Geom::Transformation.new
      ents.each do |e|
        next unless e.is_a?(Sketchup::Group) ||
                    (defined?(Sketchup::ComponentInstance) && e.is_a?(Sketchup::ComponentInstance))
        next unless e.valid?
        next if e.get_attribute('InteriorPro', 'type')
        next if e.respond_to?(:hidden?) && e.hidden?
        wxf = xf * e.transformation
        k = e.get_attribute('KitchenLab', 'kind')
        out << [e, k.to_s, wxf] if k
        next if depth >= 4
        kids = e.respond_to?(:definition) ? e.definition.entities : e.entities
        kitchen_pieces(model, kids, wxf, depth + 1, out)
      end
      out
    rescue StandardError => e
      puts "[Electrical] kitchen_pieces: #{e.class}: #{e.message}"
      out
    end

    # a group's box in the frame of the wall face: [u0, u1, z0, z1, out_min, out_max]. The box is in its container's
    # coordinates, so only what is OUTSIDE it is applied (wxf = outer * own). PURE.
    def self.box_in_frame(ent, wxf, fr)
      b = ent.bounds
      outer = wxf * ent.transformation.inverse
      mn = b.min
      mx = b.max
      pts = [mn.x, mx.x].product([mn.y, mx.y], [mn.z, mx.z]).map { |x, y, z| Geom::Point3d.new(x, y, z).transform(outer) }
      us = pts.map { |q| (q.x - fr[:ox]) * fr[:ux] + (q.y - fr[:oy]) * fr[:uy] }
      os = pts.map { |q| (q.x - fr[:ox]) * fr[:nx] + (q.y - fr[:oy]) * fr[:ny] }
      zs = pts.map { |q| q.z - fr[:floor_z] }
      [us.min, us.max, zs.min, zs.max, os.min, os.max]
    end

    # how far the face of a thin kitchen piece over [u0,u1]x[z0,z1] stands off the wall; 0.0 = none. boxes = the
    # pieces' [kind, u0, u1, z0, z1, o0, o1] (box_in_frame). PURE.
    def self.kitchen_front(u0, u1, z0, z1, boxes)
      best = 0.0
      Array(boxes).each do |k, bu0, bu1, bz0, bz1, bo0, bo1|
        next unless KITCHEN_FRONT_KINDS.include?(k.to_s)
        next unless bu0.to_f < u1.to_f && bu1.to_f > u0.to_f && bz0.to_f < z1.to_f && bz1.to_f > z0.to_f
        next if bo0.to_f < -0.5 || bo1.to_f > KITCHEN_FRONT_MAX          # a cabinet, or behind the face
        best = bo1.to_f if bo1.to_f > best
      end
      best
    end

    # how far the kitchen face over [u0,u1]x[z0,z1] stands off the wall, by rays (USE_KITCHEN_RAY); 0.0 = none
    def self.kitchen_face_ray(fr, u0, u1, z0, z1, model = Sketchup.active_model)
      return 0.0 unless model.respond_to?(:raytest)
      dir = Geom::Vector3d.new(-fr[:nx], -fr[:ny], 0)
      pts = [[(u0 + u1) / 2.0, (z0 + z1) / 2.0], [u0 + 0.1, z0 + 0.1], [u1 - 0.1, z0 + 0.1], [u0 + 0.1, z1 - 0.1], [u1 - 0.1, z1 - 0.1]]
      best = 0.0
      pts.each do |u, z|
        p = Geom::Point3d.new(fr[:ox] + fr[:ux] * u + fr[:nx] * 12.0, fr[:oy] + fr[:uy] * u + fr[:ny] * 12.0, fr[:floor_z].to_f + z)
        6.times do
          r = model.raytest([p, dir], true)
          break unless r
          path = Array(r[1])
          if path.any? { |x| x.respond_to?(:get_attribute) && x.get_attribute('InteriorPro', 'type').to_s == 'electrical' }
            p = r[0].offset(dir, 0.01)      # one of our plates: through it
            next
          end
          if path.any? { |x| x.respond_to?(:get_attribute) && KITCHEN_FRONT_KINDS.include?(x.get_attribute('KitchenLab', 'kind').to_s) }
            q = r[0]
            o = (q.x - fr[:ox]) * fr[:nx] + (q.y - fr[:oy]) * fr[:ny]
            best = o if o > best && o <= KITCHEN_FRONT_MAX + 1.0e-6
          end
          break
        end
      end
      best
    rescue StandardError => e
      puts "[Electrical] kitchen_face_ray: #{e.class}: #{e.message}"
      0.0
    end

    def self.kitchen_boxes(fr, model = Sketchup.active_model)
      kitchen_pieces(model).map { |e, k, wxf| [k] + box_in_frame(e, wxf, fr) }
    end

    # ONE CHECK for the tool: does it fit with its middle at u?
    # { ok:, lo:, hi:, outs:, rects:, on_hole:, outside: }
    def self.check(wall, side, fr, u, parts, wall_h)
      kboxes = USE_KITCHEN_FRONT ? kitchen_boxes(fr) : []
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
        out = t ? t[:out].to_f : 0.0
        kf = kitchen_front(u0, u1, z0, z1, kboxes)
        kf = [kf, kitchen_face_ray(fr, u0, u1, z0, z1)].max if USE_KITCHEN_FRONT && USE_KITCHEN_RAY
        out = kf if kf > out
        res[:outs] << out
      end
      res[:outside] = InteriorPro::FixtureLibrary.outside?(wall, side)
      res[:ok] = false if res[:on_hole] || res[:outside]
      res
    end

    # THE ONES ALREADY ON THE WALLS come out to the face too (20:20): every plate on a wall whose back does not stand
    # where the tile / backsplash face is, moved out (or back) along the wall's normal. ONE undo step. Returns how many.
    # op: false (2026-10-15 14:30, his "הם צריכים לעקוב אחריו אוטומטית") - called from inside the kitchen's own operation
    # (KitchenLab.worktops!, after the backsplash is built again): no operation of its own, so his one Ctrl+Z undoes both.
    def self.refront!(model = Sketchup.active_model, op: true)
      walls = {}
      model.entities.each do |e|
        next unless e.respond_to?(:get_attribute) && e.get_attribute('InteriorPro', 'type') == 'wall'
        walls[e.get_attribute('InteriorPro', 'id').to_s] = e
      end
      moved = 0
      model.start_operation('Electrical To The Face', true) if op
      model.entities.to_a.each do |e|
        next unless e.respond_to?(:get_attribute) && e.get_attribute('InteriorPro', 'type') == 'electrical'
        w = walls[e.get_attribute('InteriorPro', 'host_wall_id').to_s]
        next unless w
        side = e.get_attribute('InteriorPro', 'side').to_s
        fr = InteriorPro::TileWall.frame_for(w, side)
        next unless fr
        u0, u1, z0, z1, o0, = box_in_frame(e, e.transformation, fr)
        t = InteriorPro::FixtureLibrary.tile_under(w, side, u0, u1, z0, z1)
        want = t ? t[:out].to_f : 0.0
        kf = USE_KITCHEN_FRONT ? kitchen_front(u0, u1, z0, z1, kitchen_boxes(fr, model)) : 0.0
        kf = [kf, kitchen_face_ray(fr, u0, u1, z0, z1, model)].max if USE_KITCHEN_FRONT && USE_KITCHEN_RAY
        want = kf if kf > want
        d = want - o0.to_f
        next if d.abs < 0.01
        e.transform!(Geom::Transformation.translation(Geom::Vector3d.new(fr[:nx] * d, fr[:ny] * d, 0)))
        puts "[Electrical] #{e.name} on wall #{w.get_attribute('InteriorPro', 'id').to_s[0, 8]}: #{o0.round(3)} -> #{want.round(3)} off the wall"
        moved += 1
      end
      model.commit_operation if op
      puts "[Electrical] refront!: #{moved} moved to the face"
      moved
    rescue StandardError => e
      (model.abort_operation rescue nil) if op
      puts "[Electrical] refront!: #{e.class}: #{e.message}"
      0
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
        # turned: a quarter turn about the line out of the wall, through its middle
        shift = Geom::Transformation.rotation(ORIGIN, Y_AXIS, 90.degrees) * shift if p[:turn].to_i == 90
        x, y, zz = InteriorPro::TileWall.world(fr, u + p[:du], p[:h], outs[i].to_f)
        face = Geom::Transformation.axes(Geom::Point3d.new(x, y, zz),
                                         Geom::Vector3d.new(fr[:ux], fr[:uy], 0),
                                         Geom::Vector3d.new(fr[:nx], fr[:ny], 0),
                                         Geom::Vector3d.new(0, 0, 1))
        grp.entities.add_instance(p[:defn], face * shift)
      end
      {
        'type' => 'electrical', 'kind' => kind, 'gangs' => g, 'product' => cfg['product'].to_s, 'height_in' => cfg['height'].to_f,
        'turn' => turn_of(cfg), 'countertop' => countertop_of(cfg), 'u_in' => u.to_f, 'side' => side.to_s, 'host_wall_id' => wall.get_attribute('InteriorPro', 'id').to_s,
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

# THE HOLE GOES WITH THE LIGHT (2026-10-13, his words: "אם אני מוחק את המנורה
# החור נמחק איתה"). SketchUp's own Delete does not call the plugin, so the
# top level of the model is watched: when a light that has a hole is taken
# away, its room's ceiling is built again (without that hole) a moment
# later, as part of the same undo step as the Delete. The watcher only hands
# over; the work is in the module, so a reload changes it.
module InteriorPro
  module ElectricalLibrary
    USE_HOLE_FOLLOWS = true unless const_defined?(:USE_HOLE_FOLLOWS, false)

    # entityID of every hung light with a hole => its room id
    def self.hole_lights
      @hole_lights ||= {}
    end

    def self.scan_hole_lights!(model)
      model.entities.grep(Sketchup::Group).each do |g|
        next unless g.valid? && g.get_attribute('InteriorPro', 'type') == 'electrical'
        next unless g.get_attribute('InteriorPro', 'mount') == 'ceiling' && g.get_attribute('InteriorPro', 'hole_d').to_f > 0.0
        hole_lights[g.entityID] = g.get_attribute('InteriorPro', 'room_id').to_s
      end
    end

    def self.watch_holes!(model = Sketchup.active_model)
      return false unless USE_HOLE_FOLLOWS && model && defined?(HoleWatch)
      scan_hole_lights!(model)
      @hole_watched ||= {}
      return false if @hole_watched[model.object_id]
      model.entities.add_observer(HoleWatch.new)
      @hole_watched[model.object_id] = true
    rescue StandardError => e
      puts "[Electrical] watch_holes!: #{e.message}"
      false
    end

    def self.light_removed(eid)
      rid = hole_lights.delete(eid)
      return if rid.nil?
      UI.start_timer(0.05, false) { follow_hole!(rid) }
    end

    # How many holes the room's ceiling has now (inner loops of its faces).
    def self.ceiling_hole_count(rid)
      c = InteriorPro::CeilingManager.ceilings_in_model.find { |g| g.get_attribute('InteriorPro', 'room_id') == rid }
      c ? c.entities.grep(Sketchup::Face).sum { |f| f.loops.length - 1 } : 0
    end

    def self.follow_hole!(rid)
      model = Sketchup.active_model
      have = ceiling_hole_count(rid)
      want = InteriorPro::CeilingManager.holes_for(rid, model).length
      if have <= want
        trace("light removed: ceiling of #{rid} already has #{have} hole(s) for #{want} light(s) - nothing to do")
        return
      end
      room = InteriorPro::RoomManager.rooms_in_model.find { |r| r.get_attribute('InteriorPro', 'id') == rid }
      unless room
        trace("light removed: room #{rid} not found - the ceiling keeps its hole")
        return
      end
      # transparent: it joins the Delete, so one Ctrl+Z brings both back
      model.start_operation('Close Ceiling Hole', true, false, true)
      nc = InteriorPro::CeilingManager.build_ceiling_for_room!(room)
      model.commit_operation
      trace("light removed: ceiling of #{rid} built again, #{have} -> #{ceiling_hole_count(rid)} hole(s)#{nc ? '' : ' - BUILD FAILED'}")
    rescue StandardError => e
      model&.abort_operation
      trace("light removed: #{e.class} #{e.message}")
    end
  end
end

if defined?(Sketchup::EntitiesObserver) && !defined?(InteriorPro::ElectricalLibrary::HoleWatch)
  module InteriorPro
    module ElectricalLibrary
      class HoleWatch < Sketchup::EntitiesObserver
        def onElementRemoved(_entities, eid)
          InteriorPro::ElectricalLibrary.light_removed(eid)
        rescue StandardError
          nil
        end
      end

      class HoleAppWatch < Sketchup::AppObserver
        def onOpenModel(model)
          InteriorPro::ElectricalLibrary.watch_holes!(model)
        rescue StandardError
          nil
        end

        def onNewModel(model)
          InteriorPro::ElectricalLibrary.watch_holes!(model)
        rescue StandardError
          nil
        end
      end
    end
  end
  begin
    unless InteriorPro::ElectricalLibrary.instance_variable_get(:@hole_app_watched)
      Sketchup.add_observer(InteriorPro::ElectricalLibrary::HoleAppWatch.new)
      InteriorPro::ElectricalLibrary.instance_variable_set(:@hole_app_watched, true)
    end
  rescue StandardError => e
    puts "[Electrical] app observer: #{e.message}"
  end
end
begin
  InteriorPro::ElectricalLibrary.watch_holes!(Sketchup.active_model) if Sketchup.respond_to?(:active_model) && Sketchup.active_model
rescue StandardError => e
  puts "[Electrical] watch at load: #{e.message}"
end
