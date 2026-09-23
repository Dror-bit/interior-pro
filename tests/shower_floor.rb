# encoding: utf-8
# Interior Pro - THE SHOWER FLOOR (2026-09-22, step 1: the outline)
#
# HIS CALL (2026-09-22): the shower floor is drawn CORNER BY CORNER and
# closed, not a rectangle in two clicks - "נגיד יש לי מקלחת שהיא 90
# מעלות לקיר ואני רוצה לסגור את הריצפה ולביו מקלחת שיש לה 5 דפנות".
# So the loop is a polygon of any shape, like drawing a line.
#
# What this file owns: the NUMBERS of that loop (pure), and the one
# builder that turns them into a pad. The slope, the drain and the curb
# are the next steps - this one only puts the shape on the floor so he
# can see it and correct it.
#
# THE POINT LAW (CLAUDE.md): the tool locks on corners and ends, and the
# LENGTH comes from the point while the DIRECTION comes from the axis -
# a shower floor never comes out at 89.9 degrees. `ortho_point` is that
# law, pure and tested (tests/rt198.rb).
#
# Kill switch: InteriorPro::ShowerFloor::USE_SHOWER_FLOOR = false - no
# pad is built and nothing standing is touched.
module InteriorPro
  module ShowerFloor
    USE_SHOWER_FLOOR = true unless const_defined?(:USE_SHOWER_FLOOR, false)
    # Kill switch: false = "Same as the room floor" is one plain face again,
    # no real tiles on the shower (2026-09-22).
    USE_SHOWER_TILES = true unless const_defined?(:USE_SHOWER_TILES, false)
    # Kill switch: false = the raised floor gets no curb and keeps its
    # whole loop, exactly as before (2026-09-22).
    USE_CURB = true unless const_defined?(:USE_CURB, false)
    # Kill switch: false = "Line up with the wall joints" is ignored and the
    # shower's grid is laid as before (2026-09-22).
    USE_WALL_JOINTS = true unless const_defined?(:USE_WALL_JOINTS, false)
    # THE CURB (2026-09-22, his choice "1"): 4" wide, INSIDE the line he
    # drew, only on the sides with no wall behind them. Its height is the
    # window's Curb height, over the bathroom floor.
    CURB_W = 4.0 unless const_defined?(:CURB_W, false)
    # How far out past a side we look for a wall (the tile skin on his
    # walls is 0.6" thick, the wall right behind it).
    WALL_PROBE = 0.5 unless const_defined?(:WALL_PROBE, false)

    # The same window the walls use (CLAUDE.md, "זווית ישרה מנצחת").
    ORTHO_SNAP_DEG = 12.0 unless const_defined?(:ORTHO_SNAP_DEG, false)
    # How near the first corner a click has to be to CLOSE the loop.
    CLOSE_TOL = 3.0 unless const_defined?(:CLOSE_TOL, false)
    # How high the RAISED floor stands over the room floor, and how tall
    # the curb round it is (his numbers, 2026-09-22 - 1" and 4").
    DEFAULT_RISE = 1.0 unless const_defined?(:DEFAULT_RISE, false)
    DEFAULT_CURB_H = 4.0 unless const_defined?(:DEFAULT_CURB_H, false)
    # THE TWO FLOORS HE ASKED FOR (2026-09-22):
    #   'flat'  - the same height as the room. The room floor gets a HOLE
    #             cut in it and the shower floor drops into it, dead level
    #             (his call: "נחתוך חור ברצפת החדר והמקלחת נכנסת בדיוק
    #             במקום, באותו גובה").
    #   'curb'  - the floor is raised 1" and a curb goes round it. The
    #             sides that sit against a tiled wall get NO curb.
    KINDS = %w[flat curb].freeze unless const_defined?(:KINDS, false)
    SAME_AS_ROOM = 'Same as the room floor' unless const_defined?(:SAME_AS_ROOM, false)
    AXES = [[1.0, 0.0], [0.0, 1.0], [-1.0, 0.0], [0.0, -1.0]].freeze unless const_defined?(:AXES, false)

    # ---- pure -----------------------------------------------------------

    # The next corner, with the direction taken from the axis and the
    # LENGTH taken from where he is pointing (the projection onto that
    # axis). Outside the window the raw point is kept as it is, so a real
    # diagonal is still possible. PURE.
    def self.ortho_point(px, py, x, y, tol_deg = ORTHO_SNAP_DEG)
      px = px.to_f; py = py.to_f
      dx = x.to_f - px; dy = y.to_f - py
      len = Math.hypot(dx, dy)
      return [x.to_f, y.to_f] if len < 1.0e-9
      best = nil
      AXES.each do |ux, uy|
        c = (dx * ux + dy * uy) / len
        next if c <= 0.0
        ang = Math.acos([[c, 1.0].min, -1.0].max) * 180.0 / Math::PI
        best = [ang, ux, uy] if best.nil? || ang < best[0]
      end
      return [x.to_f, y.to_f] if best.nil? || best[0] > tol_deg.to_f
      _a, ux, uy = best
      reach = dx * ux + dy * uy
      [px + ux * reach, py + uy * reach]
    end

    # A click this near the first corner closes the loop. PURE.
    def self.closes?(pts, x, y, tol = CLOSE_TOL)
      return false if pts.nil? || pts.length < 3
      fx, fy = pts.first
      Math.hypot(x.to_f - fx.to_f, y.to_f - fy.to_f) <= tol.to_f
    end

    # Drop points that sit on top of each other and the repeated closing
    # point - add_face dies on both. PURE.
    def self.clean_loop(pts, tol = 0.01)
      out = []
      Array(pts).each do |p|
        x = p[0].to_f; y = p[1].to_f
        next if out.any? && Math.hypot(x - out.last[0], y - out.last[1]) <= tol
        out << [x, y]
      end
      out.pop if out.length > 1 && Math.hypot(out.first[0] - out.last[0], out.first[1] - out.last[1]) <= tol
      out
    end

    # Square feet of the loop. PURE.
    def self.area_sqft(pts)
      p = clean_loop(pts)
      return 0.0 if p.length < 3
      s = 0.0
      p.each_with_index do |(x, y), i|
        x2, y2 = p[(i + 1) % p.length]
        s += x * y2 - x2 * y
      end
      (s.abs / 2.0) / 144.0
    end

    # Is the point inside the loop? Ray casting, PURE (tests/rt200).
    def self.point_in?(pts, x, y)
      p = clean_loop(pts)
      return false if p.length < 3
      x = x.to_f; y = y.to_f
      inside = false
      j = p.length - 1
      p.each_with_index do |(xi, yi), i|
        xj, yj = p[j]
        if ((yi > y) != (yj > y)) &&
           (x < (xj - xi) * (y - yi) / ((yj - yi).abs < 1.0e-12 ? 1.0e-12 : (yj - yi)) + xi)
          inside = !inside
        end
        j = i
      end
      inside
    end

    # The middle of the loop - the point used to ask which room floor it
    # was drawn on. PURE.
    def self.centroid(pts)
      p = clean_loop(pts)
      return nil if p.empty?
      [p.map { |q| q[0] }.inject(:+) / p.length, p.map { |q| q[1] }.inject(:+) / p.length]
    end

    # WHERE THE LOOP CROSSES A LINE THAT IS ALREADY THERE (2026-09-22).
    #
    # Measured on his model: two tiles crossed his line and were never
    # split. SketchUp does NOT cut a face with a new line that runs over
    # its border - the new line needs a POINT sitting right on that
    # border. The loop had only its four corners, so a tile the line ran
    # through stayed whole. Here every crossing with an existing line
    # becomes a corner of the loop, so each piece of the loop starts and
    # ends on a tile edge and SketchUp splits the tile there. PURE
    # (tests/rt201.rb).
    def self.seg_cross_t(ax, ay, bx, by, cx, cy, dx, dy, tol = 1.0e-9)
      rx = bx - ax; ry = by - ay
      sx = dx - cx; sy = dy - cy
      den = rx * sy - ry * sx
      return nil if den.abs < 1.0e-12
      qx = cx - ax; qy = cy - ay
      t = (qx * sy - qy * sx) / den
      u = (qx * ry - qy * rx) / den
      return nil if u < -tol || u > 1.0 + tol
      t
    end

    def self.split_loop(loop_xy, segs, tol = 1.0e-6)
      p = clean_loop(loop_xy)
      return p if p.length < 3
      out = []
      p.each_with_index do |(ax, ay), i|
        bx, by = p[(i + 1) % p.length]
        ts = []
        Array(segs).each do |(c, d)|
          t = seg_cross_t(ax, ay, bx, by, c[0].to_f, c[1].to_f, d[0].to_f, d[1].to_f)
          ts << t if t && t > tol && t < 1.0 - tol
        end
        out << [ax, ay]
        ts.sort.each { |t| out << [ax + (bx - ax) * t, ay + (by - ay) * t] }
      end
      clean_loop(out)
    end

    # The outward normal of each side of the loop (unit), whichever way
    # round it was drawn. PURE.
    def self.out_normals(lp)
      area2 = 0.0
      lp.each_with_index { |(x1, y1), i| x2, y2 = lp[(i + 1) % lp.length]; area2 += x1 * y2 - x2 * y1 }
      sgn = area2 >= 0 ? 1.0 : -1.0 # counter-clockwise: outside is to the right
      lp.each_with_index.map do |(x1, y1), i|
        x2, y2 = lp[(i + 1) % lp.length]
        len = Math.hypot(x2 - x1, y2 - y1)
        len < 1.0e-9 ? [0.0, 0.0] : [(y2 - y1) / len * sgn, -(x2 - x1) / len * sgn]
      end
    end

    # WHICH SIDES HAVE A WALL BEHIND THEM (2026-09-22, his rule: "הדפנות
    # שנוגעות בקיר לא מקבלות סכר"). A point WALL_PROBE out past the middle
    # of each side is tested against the walls' floor boxes
    # [xmin, ymin, xmax, ymax]. true = wall, no curb. PURE (tests/rt209).
    def self.wall_sides(loop_xy, boxes, probe = WALL_PROBE)
      lp = clean_loop(loop_xy)
      return [] if lp.length < 3
      ns = out_normals(lp)
      lp.each_with_index.map do |(x1, y1), i|
        x2, y2 = lp[(i + 1) % lp.length]
        px = (x1 + x2) / 2.0 + ns[i][0] * probe
        py = (y1 + y2) / 2.0 + ns[i][1] * probe
        Array(boxes).any? { |x0, y0, xa, ya| px >= x0 - 1.0e-6 && px <= xa + 1.0e-6 && py >= y0 - 1.0e-6 && py <= ya + 1.0e-6 }
      end
    end

    # The loop with each side pulled IN by its own distance (0 = stays
    # where he drew it). Corner i is where the pulled lines of the side
    # before it and the side after it meet - so two curbs meeting at a
    # corner share one 45 degree cut, and a curb running into a wall
    # ends flush on the wall's line. PURE (tests/rt209).
    def self.inset_loop(loop_xy, dists)
      lp = clean_loop(loop_xy)
      n = lp.length
      return lp if n < 3
      ns = out_normals(lp)
      lines = lp.each_with_index.map do |(x1, y1), i|
        x2, y2 = lp[(i + 1) % n]
        d = dists[i].to_f
        [x1 - ns[i][0] * d, y1 - ns[i][1] * d, x2 - x1, y2 - y1]
      end
      lp.each_index.map do |i|
        ax, ay, ux, uy = lines[(i - 1) % n]
        bx, by, vx, vy = lines[i]
        den = ux * vy - uy * vx
        if den.abs < 1.0e-9
          [bx, by] # the two sides run straight on - no corner to meet at
        else
          t = ((bx - ax) * vy - (by - ay) * vx) / den
          [ax + ux * t, ay + uy * t]
        end
      end
    end

    # One curb piece per open side: the side he drew, and the same side
    # pulled in. PURE.
    def self.curb_pieces(loop_xy, walled, width = CURB_W)
      lp = clean_loop(loop_xy)
      return [] if lp.length < 3
      inner = inset_loop(lp, walled.map { |w| w ? 0.0 : width.to_f })
      n = lp.length
      (0...n).reject { |i| walled[i] }.map { |i| [lp[i], lp[(i + 1) % n], inner[(i + 1) % n], inner[i]] }
    end

    # ---- the model ------------------------------------------------------

    # THE WALL'S GROUT LINES (2026-09-22, his ask: with a curb, the shower
    # floor can line up with the WALL joints instead of the bathroom
    # floor's). Every edge position of the wall's tiles along the wall,
    # sorted; two edges exactly one grout apart are a joint, and its
    # middle is returned. Measured on his walls: 48x48 tiles, 1/8" grout,
    # one joint in the middle of each wall. PURE (tests/rt210).
    def self.joints_from_edges(coords, grout, tol = 0.03)
      g = grout.to_f
      return [] if g <= 0.0
      cs = Array(coords).map(&:to_f).uniq.sort
      cs.each_cons(2).select { |a, b| ((b - a) - g).abs <= tol }.map { |a, b| (a + b) / 2.0 }
    end

    # For each axis, the joint to line the shower up with: from the tile
    # wall behind the LONGEST side running along that axis, the joint
    # nearest the middle of that side. `walls` is one entry per side:
    # nil (no tile wall) or the joints along it. PURE (tests/rt210).
    def self.pick_anchors(loop_xy, side_joints)
      lp = clean_loop(loop_xy)
      out = { 'x' => nil, 'y' => nil }
      best = { 'x' => -1.0, 'y' => -1.0 }
      lp.each_with_index do |(x1, y1), i|
        js = side_joints[i]
        next if js.nil? || js.empty?
        x2, y2 = lp[(i + 1) % lp.length]
        ax = (x2 - x1).abs >= (y2 - y1).abs ? 'x' : 'y'
        len = Math.hypot(x2 - x1, y2 - y1)
        next unless len > best[ax]
        mid = ax == 'x' ? (x1 + x2) / 2.0 : (y1 + y2) / 2.0
        best[ax] = len
        out[ax] = js.min_by { |j| (j - mid).abs }
      end
      out
    end

    # Every face of a group, however deep, with its world transformation.
    def self.faces_deep(ents, tr, out = [])
      ents.each do |e|
        if e.is_a?(Sketchup::Face)
          out << [e, tr]
        elsif e.is_a?(Sketchup::Group)
          faces_deep(e.entities, tr * e.transformation, out)
        elsif e.is_a?(Sketchup::ComponentInstance)
          faces_deep(e.definition.entities, tr * e.transformation, out)
        end
      end
      out
    end

    # The joints of the tile wall behind each side of the loop - MEASURED
    # off the tiles themselves, so it works for whatever tile each shower
    # has on its walls.
    def self.wall_joints_by_side(loop_xy, model = nil)
      model ||= Sketchup.active_model
      lp = clean_loop(loop_xy)
      ns = out_normals(lp)
      skins = model.entities.grep(Sketchup::Group).select { |g| g.valid? && g.get_attribute('InteriorPro', 'type').to_s == 'tile_wall' }
      lp.each_with_index.map do |(x1, y1), i|
        x2, y2 = lp[(i + 1) % lp.length]
        px = (x1 + x2) / 2.0 + ns[i][0] * WALL_PROBE
        py = (y1 + y2) / 2.0 + ns[i][1] * WALL_PROBE
        along_x = (x2 - x1).abs >= (y2 - y1).abs
        skin = skins.find do |g|
          b = g.bounds
          px >= b.min.x - 1.0e-6 && px <= b.max.x + 1.0e-6 && py >= b.min.y - 1.0e-6 && py <= b.max.y + 1.0e-6
        rescue StandardError
          false
        end
        next nil unless skin
        faces = faces_deep(skin.entities, skin.transformation).select do |f, t|
          next false unless f.valid?
          next false if f.material && f.material.name.to_s.start_with?('InteriorPro_Grout_')
          n = f.normal.transform(t)
          along_x ? n.y.abs > 0.9 : n.x.abs > 0.9
        end
        coords = faces.flat_map { |f, t| f.vertices.map { |v| q = v.position.transform(t); (along_x ? q.x : q.y).to_f.round(4) } }
        js = joints_from_edges(coords, skin.get_attribute('InteriorPro', 'pattern_grout').to_f)
        trace("wall joints: side #{i} #{skin.get_attribute('InteriorPro', 'id')} along #{along_x ? 'x' : 'y'} -> #{js.map { |j| j.round(3) }.inspect}")
        js
      end
    rescue StandardError => e
      trace("wall_joints_by_side raised #{e.class}: #{e.message} #{e.backtrace.first}")
      puts "[ShowerFloor] wall joints: #{e.message}"
      []
    end

    # The floor boxes of every wall and tile skin in the model.
    def self.wall_boxes(model = nil)
      model ||= Sketchup.active_model
      model.entities.grep(Sketchup::Group).map do |g|
        next nil unless g.valid? && %w[wall tile_wall].include?(g.get_attribute('InteriorPro', 'type').to_s)
        begin
          b = g.bounds
          [b.min.x.to_f, b.min.y.to_f, b.max.x.to_f, b.max.y.to_f]
        rescue StandardError => e
          puts "[ShowerFloor] wall box skipped (#{g.get_attribute('InteriorPro', 'id')}): #{e.message}"
          nil
        end
      end.compact
    end

    # The curbs standing on one shower floor.
    def self.curbs_of(shower_id, model = nil)
      return [] if shower_id.nil?
      model ||= Sketchup.active_model
      model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'shower_curb' &&
          g.get_attribute('InteriorPro', 'shower_id') == shower_id
      end
    end

    # Each curb piece in a group of its own (CLAUDE.md: every board in its
    # own group), standing on the bathroom floor, curb_h tall.
    def self.build_curbs!(pieces, base_z, curb_h, mat, shower_id, model)
      pieces.each_with_index.map do |pc, i|
        g = model.entities.add_group
        g.name = 'InteriorPro_ShowerCurb'
        begin
          InteriorPro.assign_tag(g, 'IP/Floors')
        rescue StandardError => e
          puts "[ShowerFloor] curb: no tag: #{e.message}"
        end
        f = begin
          g.entities.add_face(pc.map { |x, y| Geom::Point3d.new(x, y, base_z) })
        rescue StandardError => e
          puts "[ShowerFloor] curb #{i} could not be drawn: #{e.message}"
          nil
        end
        if f.nil?
          g.erase! if g.valid?
          next nil
        end
        f.pushpull(f.normal.z > 0 ? curb_h : -curb_h)
        g.entities.grep(Sketchup::Face).each { |x| x.material = mat } if mat
        g.set_attribute('InteriorPro', 'type', 'shower_curb')
        g.set_attribute('InteriorPro', 'shower_id', shower_id)
        g.set_attribute('InteriorPro', 'poly_xy', pc.flatten)
        g.set_attribute('InteriorPro', 'base_z', base_z.to_f)
        g.set_attribute('InteriorPro', 'height_in', curb_h.to_f)
        g
      end.compact
    end

    # The tile layout laid on one shower floor.
    def self.tiles_of(shower_id, model = nil)
      return [] if shower_id.nil?
      model ||= Sketchup.active_model
      model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'shower_pattern' &&
          g.get_attribute('InteriorPro', 'shower_id') == shower_id
      end
    end

    def self.pads_in_model(model = nil)
      model ||= Sketchup.active_model
      model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'shower_floor'
      end
    end

    # The tile on the shower floor. His ask (2026-09-22): it can be a
    # tile of its own, and it can also be the SAME one as the room floor.
    def self.material(model, tile, floor_grp = nil, preset = nil)
      if tile.nil? || tile.to_s.empty? || tile.to_s == SAME_AS_ROOM
        m = preset || room_floor_material(floor_grp)
        return m if m
        tile = InteriorPro::FloorManager::DEFAULT_TYPE
      end
      InteriorPro::FloorManager.floor_material(model, tile.to_s)
    rescue StandardError => e
      puts "[ShowerFloor] material fell back to plain: #{e.message}"
      plain_material(model)
    end

    # The material most of the flat faces wear - on a tile layout that
    # is the tile, not the one grout backing face under it (2026-09-22:
    # the shower came out in the SLAB's material, "טקסטורות שלא קשורות").
    def self.room_floor_material(floor_grp)
      return nil unless floor_grp && floor_grp.valid?
      mats = floor_grp.entities.grep(Sketchup::Face).select { |x| x.valid? && x.material }
      return nil if mats.empty?
      mats.group_by(&:material).max_by { |_m, fs| fs.length }[0]
    rescue StandardError
      nil
    end

    # THE ROOM'S TILE, AS NUMBERS (2026-09-22, his words: "שהוא יזהה בדיוק
    # איזה חומר ואני יכול לשחק איתו בעצמי"). From the slab's own attributes
    # when the room has a floor; when it only has a tile layout (his room
    # 2), MEASURED off the layout: the material most faces wear (and the
    # card or texture it came from), the tile size, and the joint.
    def self.room_settings(floor_grp, pat_grp = nil, model = nil)
      model ||= Sketchup.active_model
      out = {}
      slab = floor_grp && floor_grp.valid? && floor_grp.get_attribute('InteriorPro', 'type').to_s == 'floor' ? floor_grp : nil
      pat = pat_grp || (slab && patterns_of(slab, model).first) ||
            (floor_grp && floor_grp.valid? && floor_grp.get_attribute('InteriorPro', 'type').to_s == 'floor_pattern' ? floor_grp : nil)
      if slab && !%w[None].include?((slab.get_attribute('InteriorPro', 'pattern') || 'None').to_s)
        at = lambda { |k| slab.get_attribute('InteriorPro', k) }
        out = { 'pattern' => at.call('pattern').to_s, 'unit_w' => at.call('unit_w').to_f, 'unit_l' => at.call('unit_l').to_f,
                'ox' => at.call('pattern_ox').to_f, 'oy' => at.call('pattern_oy').to_f, 'angle' => at.call('pattern_angle').to_f,
                'center' => at.call('pattern_center') ? true : false, 'texture' => at.call('floor_texture').to_s,
                'grout' => at.call('pattern_grout').to_f, 'grout_color' => (at.call('pattern_grout_color') || 'light').to_s,
                'stagger' => at.call('pattern_stagger').to_f, 'material_card_id' => at.call('material_card_id').to_s,
                'spec' => at.call('floor_spec').to_s, 'grout_spec' => at.call('grout_spec').to_s }
        return out if !out['material_card_id'].empty? || !out['texture'].empty?
      end
      return out unless pat && pat.valid?
      mat = room_floor_material(pat)
      return out unless mat
      out['pattern'] = 'Tile'
      id = defined?(InteriorPro::MaterialIds) ? (InteriorPro::MaterialIds.id_of(mat) rescue nil) : nil
      out['material_card_id'] = id.to_s
      out['texture'] = mat.name.to_s.sub(/\AInteriorPro_FloorTex_/, '') if id.to_s.empty? && mat.name.to_s.start_with?('InteriorPro_FloorTex_')
      # the tile size: the most common width and length among the whole tiles
      faces = pat.entities.grep(Sketchup::Face).select { |f| f.valid? && f.material == mat && f.normal.z.abs > 0.9 }
      span = lambda { |f, ax| vs = f.vertices.map { |v| v.position.send(ax).to_f }; [vs.min, vs.max] }
      ws = faces.map { |f| a, b = span.call(f, :x); (b - a).round(2) }
      ls = faces.map { |f| a, b = span.call(f, :y); (b - a).round(2) }
      # THE CARD KNOWS THE TILE SIZE (measured 2026-09-22: counting the cut
      # pieces gave 19.49 x 0.63 - the slivers round the walls won). The
      # card first, like floor_pattern.rb; the biggest whole piece only if
      # there is no card.
      card = nil
      if !id.to_s.empty? && defined?(InteriorPro::MaterialLibrary)
        card = (InteriorPro::MaterialLibrary.cards.find { |c| c['id'].to_s == id.to_s } rescue nil)
      end
      cw = card ? (card['tile_w_inches'] || card['texture_width_inches']).to_f : 0.0
      ch = card ? (card['tile_l_inches'] || card['texture_height_inches']).to_f : 0.0
      mode = lambda { |a| a.empty? ? 0.0 : a.group_by { |v| v }.max_by { |_v, g| [g.length, _v] }[0] }
      out['unit_w'] = cw > 0.25 ? cw : mode.call(ws)
      out['unit_l'] = ch > 0.25 ? ch : mode.call(ls)
      # the joint: the smallest gap between two neighbouring tiles
      xs = faces.flat_map { |f| span.call(f, :x).map { |v| v.round(3) } }.uniq.sort
      gaps = xs.each_cons(2).map { |a, b| (b - a).round(3) }.select { |g| g > 0.02 && g < 1.0 }
      out['grout'] = gaps.empty? ? 0.0 : gaps.min
      # WHERE THE JOINTS ARE (2026-09-22, "צריך להמשיך גם את הקווים של
      # הגראוט"): the shower's grid is pushed so a joint passes where the
      # room's joints are. Measured on his room: NO whole tile exists (a
      # 48x24 tile in a 42 sq ft bath is always cut), so the anchor is the
      # most common tile-start, modulo the pitch, over EVERY piece - a cut
      # piece still starts (or ends) on a joint.
      pw = out['unit_w'].to_f + out['grout'].to_f
      pl = out['unit_l'].to_f + out['grout'].to_f
      residue = lambda do |vals, pitch|
        next nil if pitch <= 0.25 || vals.empty?
        vals.map { |v| (v % pitch).round(2) }.group_by { |v| v }.max_by { |_v, g| g.length }[0]
      end
      xs_start = faces.flat_map { |f| a, b = span.call(f, :x); [a, b + out['grout'].to_f] }
      ys_start = faces.flat_map { |f| a, b = span.call(f, :y); [a, b + out['grout'].to_f] }
      ax = residue.call(xs_start, pw)
      ay = residue.call(ys_start, pl)
      if ax && ay
        out['anchor_x'] = ax
        out['anchor_y'] = ay
      end
      grout_face = pat.entities.grep(Sketchup::Face).find { |f| f.valid? && f.material && f.material.name.to_s.start_with?('InteriorPro_Grout_') }
      out['grout_color'] = grout_face.material.name.to_s.sub('InteriorPro_Grout_', '').downcase if grout_face
      trace("room tile measured: #{out.inspect}")
      out
    rescue StandardError => e
      trace("room_settings raised #{e.class}: #{e.message} #{e.backtrace.first}")
      puts "[ShowerFloor] room_settings: #{e.message}"
      {}
    end

    # The name the count shows for the shower's floor.
    def self.floor_type_name(settings, tile, src)
      if settings && !settings['same_room']
        id = settings['material_card_id'].to_s
        if !id.empty? && defined?(InteriorPro::MaterialLibrary)
          card = (InteriorPro::MaterialLibrary.cards.find { |c| c['id'].to_s == id } rescue nil)
          return card['name'].to_s if card
        end
        return settings['texture'].to_s unless settings['texture'].to_s.empty?
        return settings['pattern'].to_s
      end
      t = src && src.valid? ? src.get_attribute('InteriorPro', 'floor_type').to_s : ''
      t.empty? ? tile.to_s : t
    rescue StandardError
      tile.to_s
    end

    # The shower's OWN tile material: the card first, the texture next.
    def self.own_material(model, settings)
      id = settings['material_card_id'].to_s
      if !id.empty? && defined?(InteriorPro::MaterialLibrary)
        card = (InteriorPro::MaterialLibrary.cards.find { |c| c['id'].to_s == id } rescue nil)
        m = card && (InteriorPro::MaterialLibraryDialog.material_from_card(model, card) rescue nil)
        return m if m
        puts "[ShowerFloor] material card '#{id}' gave no material"
      end
      tex = settings['texture'].to_s
      unless tex.empty?
        m = InteriorPro::FloorManager.texture_material(model, tex)
        return m if m
      end
      plain_material(model)
    rescue StandardError => e
      puts "[ShowerFloor] own material fell back to plain: #{e.message}"
      plain_material(model)
    end

    def self.plain_material(model)
      name = 'InteriorPro_ShowerFloor'
      m = model.materials[name]
      return m if m
      m = model.materials.add(name)
      m.color = Sketchup::Color.new(224, 220, 210)
      m
    end

    # WHAT IS UNDER THE LOOP - MEASURED, NOT ASSUMED (2026-09-22).
    #
    # His model had TWO floors on screen and the finder saw one, and he
    # was right to call it: only ROOM 1 has a `floor` slab. Room 2's
    # floor is a `floor_pattern` group - the tile layout - with no slab
    # under it at all. So both kinds count as "the floor he drew on",
    # and BOTH have to be opened, or the tile stays over the hole.
    FLOOR_TYPES_UNDER = %w[floor floor_pattern].freeze unless const_defined?(:FLOOR_TYPES_UNDER, false)

    def self.floors_under(pts, floor_z = nil, model = nil)
      model ||= Sketchup.active_model
      c = centroid(pts)
      return [] if c.nil?
      out = []
      model.entities.grep(Sketchup::Group).each do |g|
        next unless g.valid?
        next unless FLOOR_TYPES_UNDER.include?(g.get_attribute('InteriorPro', 'type').to_s)
        hit = g.entities.grep(Sketchup::Face).any? do |f|
          next false unless f.valid? && f.normal.z.abs > 0.9
          z = f.vertices.first.position.z.to_f
          next false if floor_z && (z - floor_z.to_f).abs > 2.0
          f.classify_point(Geom::Point3d.new(c[0], c[1], z)) == Sketchup::Face::PointInside
        end
        # DRAWN AGAIN ON THE SAME LOOP (2026-09-22, measured on his model):
        # the middle of the loop now sits in the HOLE the first shower cut,
        # so no face is under it and he got "no room floor". The floor that
        # already carries this exact hole is the floor under it.
        mid_hit = hit
        hit ||= holed_here?(g, pts, model)
        trace("under? #{g.get_attribute('InteriorPro', 'type')} #{g.get_attribute('InteriorPro', 'id')} " \
              "floor_id #{g.get_attribute('InteriorPro', 'floor_id').inspect} room #{g.get_attribute('InteriorPro', 'room_id')} " \
              "middle #{mid_hit ? 'yes' : 'no'} holes #{holes_of(g).length} -> #{hit ? 'YES' : 'no'}")
        out << g if hit
      end
      # THE HOLE IS ALREADY THERE BUT NOBODY WROTE IT DOWN (his room 2,
      # 2026-09-22): nothing under the middle, so look just OUTSIDE each
      # side of the loop - the floor round the hole is the floor under it.
      # 1" out lands inside a wall on the wall sides, so only the room's
      # own floor answers.
      out = floor_round(pts, floor_z, model) if out.empty?
      trace("loop #{clean_loop(pts).map { |x, y| [x.round(3), y.round(3)] }.inspect} middle #{c.map { |v| v.round(3) }.inspect} z #{floor_z.inspect} found #{out.length}")
      puts '[ShowerFloor] nothing under the middle of the loop - no floor and no tile' if out.empty?
      out
    rescue StandardError => e
      trace("floors_under raised #{e.class}: #{e.message} #{e.backtrace.first}")
      puts "[ShowerFloor] floors_under: #{e.message}"
      []
    end

    def self.floor_round(pts, floor_z = nil, model = nil)
      model ||= Sketchup.active_model
      lp = clean_loop(pts)
      return [] if lp.length < 3
      area2 = 0.0
      lp.each_with_index { |(x1, y1), i| x2, y2 = lp[(i + 1) % lp.length]; area2 += x1 * y2 - x2 * y1 }
      sgn = area2 >= 0 ? 1.0 : -1.0 # counter-clockwise: outside is to the right
      probes = lp.each_with_index.map do |(x1, y1), i|
        x2, y2 = lp[(i + 1) % lp.length]
        len = Math.hypot(x2 - x1, y2 - y1)
        next nil if len < 1.0e-6
        nx = (y2 - y1) / len * sgn
        ny = -(x2 - x1) / len * sgn
        [(x1 + x2) / 2.0 + nx, (y1 + y2) / 2.0 + ny]
      end.compact
      score = {}
      model.entities.grep(Sketchup::Group).each do |g|
        next unless g.valid? && FLOOR_TYPES_UNDER.include?(g.get_attribute('InteriorPro', 'type').to_s)
        faces = g.entities.grep(Sketchup::Face).select do |f|
          f.valid? && f.normal.z.abs > 0.9 &&
            (floor_z.nil? || (f.vertices.first.position.z.to_f - floor_z.to_f).abs <= 2.0)
        end
        n = probes.count do |px, py|
          faces.any? { |f| f.classify_point(Geom::Point3d.new(px, py, f.vertices.first.position.z)) == Sketchup::Face::PointInside }
        end
        score[g] = n if n > 0
      end
      trace("round the loop: #{score.map { |g, n| "#{g.get_attribute('InteriorPro', 'type')} #{g.get_attribute('InteriorPro', 'room_id')} #{n}/#{probes.length}" }.join(', ')}")
      return [] if score.empty?
      best = score.values.max
      score.select { |_g, n| n == best }.keys
    rescue StandardError => e
      trace("floor_round raised #{e.message}")
      []
    end

    # One line to the click trace (shower_tool_trace.txt) - so a build that
    # says "no floor" shows WHY without him pasting anything.
    def self.trace(msg)
      File.open(File.join(__dir__, 'shower_tool_trace.txt'), 'a:UTF-8') { |f| f.puts "#{Time.now.strftime('%H:%M:%S')}   #{msg}" }
    rescue StandardError
      nil
    end

    # Does this floor (or the floor behind this tile layout) already
    # carry a shower hole on exactly this loop?
    def self.holed_here?(g, pts, model = nil)
      owner = g.get_attribute('InteriorPro', 'type').to_s == 'floor_pattern' ? floor_of_pattern(g, model) : g
      # A tile layout with no slab behind it (his room 2, measured
      # 2026-09-22) carries the hole on itself.
      hit = [owner, g].compact.uniq.any? { |x| holes_of(x).any? { |h| same_loop?(h, pts) } }
      # A shower built before the hole was remembered anywhere (his room 2,
      # 14:17 on 2026-09-22): the pad itself says which room it belongs to.
      rid = g.get_attribute('InteriorPro', 'room_id')
      hit ||= !rid.nil? && pads_in_model(model).any? do |pad|
        pad.get_attribute('InteriorPro', 'room_id') == rid &&
          same_loop?(Array(pad.get_attribute('InteriorPro', 'poly_xy')).map(&:to_f).each_slice(2).to_a, pts)
      end
      puts "[ShowerFloor] #{g.get_attribute('InteriorPro', 'type')} already has this hole - drawing over it" if hit
      hit
    rescue StandardError => e
      puts "[ShowerFloor] holed_here?: #{e.message}"
      false
    end

    # The top of a slab: its stored level, which is what FloorManager
    # built it at. Never a face picked by height - a loose face left by
    # an older cut sat higher than the real top.
    def self.slab_top_z(grp)
      v = grp.get_attribute('InteriorPro', 'floor_level')
      return v.to_f unless v.nil?
      zs = grp.entities.grep(Sketchup::Face).select { |f| f.valid? && f.normal.z > 0.9 }
              .map { |f| f.vertices.first.position.z.to_f }
      zs.empty? ? 0.0 : zs.max
    rescue StandardError
      0.0
    end

    # THE HOLE LIVES ON THE FLOOR, LIKE A WINDOW ON A WALL (2026-09-22,
    # his words: "תתקן את זה כמו חלון לקיר"). The loop is stored on the
    # room's floor group as `shower_holes` - a flat list, each hole as
    # its corner count followed by x,y pairs - and every rebuild of the
    # slab (FloorManager) and of the tile layout (FloorPattern) cuts it
    # again through `cut_floor!` / `cut_pattern!`. So the hole survives
    # Build Floors, exactly as a door opening survives a wall rebuild.
    def self.holes_of(floor_grp)
      raw = Array(floor_grp.get_attribute('InteriorPro', 'shower_holes')).map(&:to_f)
      out = []
      i = 0
      while i < raw.length
        n = raw[i].to_i
        break if n < 3 || i + 1 + n * 2 > raw.length
        out << raw[i + 1, n * 2].each_slice(2).to_a
        i += 1 + n * 2
      end
      out
    rescue StandardError
      []
    end

    def self.same_loop?(a, b, tol = 0.1)
      a = clean_loop(a); b = clean_loop(b)
      return false unless a.length == b.length
      a.all? { |x, y| b.any? { |x2, y2| (x - x2).abs <= tol && (y - y2).abs <= tol } }
    end

    def self.add_hole!(floor_grp, loop_xy)
      loop_xy = clean_loop(loop_xy)
      holes = holes_of(floor_grp).reject { |h| same_loop?(h, loop_xy) }
      holes << loop_xy
      floor_grp.set_attribute('InteriorPro', 'shower_holes',
                              holes.flat_map { |h| [h.length.to_f] + h.flatten })
      refresh_area!(floor_grp)
      holes.length
    end

    # TWO FLOORS IN THE COUNT (2026-09-22, his choice "2"): the room's
    # floor is the room minus its showers, and each shower is a floor of
    # its own. The room's gross area is kept once; area_sqft is the net.
    def self.refresh_area!(floor_grp)
      return unless floor_grp && floor_grp.valid?
      gross = floor_grp.get_attribute('InteriorPro', 'gross_area_sqft')
      if gross.nil?
        gross = floor_grp.get_attribute('InteriorPro', 'area_sqft').to_f
        floor_grp.set_attribute('InteriorPro', 'gross_area_sqft', gross)
      end
      taken = holes_of(floor_grp).sum { |h| area_sqft(h) }
      net = [gross.to_f - taken, 0.0].max
      floor_grp.set_attribute('InteriorPro', 'area_sqft', net.round(2))
      net
    rescue StandardError => e
      puts "[ShowerFloor] refresh_area!: #{e.message}"
      nil
    end

    # Called by FloorManager at the end of every slab build.
    def self.cut_floor!(floor_grp)
      return 0 unless USE_SHOWER_FLOOR && floor_grp && floor_grp.valid?
      holes = holes_of(floor_grp)
      holes.each { |h| cut_out!(floor_grp, h, nil) }
      refresh_area!(floor_grp)
      holes.length
    rescue StandardError => e
      puts "[ShowerFloor] cut_floor!: #{e.message}"
      0
    end

    # Called by FloorPattern at the end of every tile layout build.
    def self.cut_pattern!(pat_grp, floor_grp)
      return 0 unless USE_SHOWER_FLOOR && pat_grp && pat_grp.valid? && floor_grp && floor_grp.valid?
      holes = holes_of(floor_grp)
      holes.each { |h| cut_out!(pat_grp, h, nil) }
      holes.length
    rescue StandardError => e
      puts "[ShowerFloor] cut_pattern!: #{e.message}"
      0
    end

    def self.patterns_of(floor_grp, model = nil)
      model ||= Sketchup.active_model
      fid = floor_grp.get_attribute('InteriorPro', 'id')
      model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type').to_s == 'floor_pattern' &&
          (fid.nil? ? false : g.get_attribute('InteriorPro', 'floor_id') == fid)
      end
    end

    def self.floor_of_pattern(pat_grp, model = nil)
      model ||= Sketchup.active_model
      fid = pat_grp.get_attribute('InteriorPro', 'floor_id')
      return nil if fid.nil?
      model.entities.grep(Sketchup::Group).find do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type').to_s == 'floor' &&
          g.get_attribute('InteriorPro', 'id') == fid
      end
    end

    def self.slab_of(groups)
      Array(groups).find { |g| g.get_attribute('InteriorPro', 'type').to_s == 'floor' }
    end

    # The FINISHED top he sees: the tile layout if there is one, the slab
    # if there is not.
    def self.finished_top(groups, fallback = 0.0)
      tops = Array(groups).map do |g|
        g.entities.grep(Sketchup::Face).select { |f| f.valid? && f.normal.z.abs > 0.9 }
         .map { |f| f.vertices.first.position.z.to_f }.max
      end.compact
      tops.empty? ? fallback.to_f : tops.max
    rescue StandardError
      fallback.to_f
    end

    # OPEN ONE GROUP (2026-09-22). A slab is cut with a face pushed all
    # the way through it; a tile layout is flat, so the loop is drawn on
    # it - which splits the tiles that cross the line - and everything
    # inside is taken away. Returns how deep the hole went.
    def self.cut_out!(grp, pts, top_z)
      return 0.0 unless grp && grp.valid?
      loop_xy = clean_loop(pts)
      if grp.get_attribute('InteriorPro', 'type').to_s == 'floor'
        th = grp.get_attribute('InteriorPro', 'thickness_in').to_f
        th = 0.75 if th <= 0.05
        # THE SLAB IS CUT AT ITS OWN TOP (2026-09-22). Measured on his
        # model: the loop was drawn at the TILE's height (0.05) inside the
        # slab group, 0.05" above the slab's top (0.0) - a loose face
        # floating over the slab, no hole, and a white square fighting
        # the shower floor for the same plane.
        z = slab_top_z(grp)
        face = begin
          grp.entities.add_face(loop_xy.map { |x, y| Geom::Point3d.new(x, y, z) })
        rescue StandardError => e
          puts "[ShowerFloor] the hole could not be drawn on the slab: #{e.message}"
          nil
        end
        return 0.0 if face.nil?
        face.pushpull(-th)
        sweep_inside!(grp, loop_xy, z - th)
        return th
      end
      # A tile layout is flat, so the loop is DRAWN on it - which splits
      # the tiles that cross the line - and everything inside is taken
      # away.
      #
      # THE Z MUST BE THE FACE'S OWN, TO THE LAST DECIMAL (2026-09-22).
      # The first version rounded the level to four places before drawing
      # the loop on it. Half a thousandth of an inch is enough for
      # SketchUp to call the line "not on that face", so the tiles that
      # crossed the line were never split - they kept their middle
      # outside the loop, survived the sweep, and lay over the shower.
      # That is the picture he sent ("נכנסות אחת לתוך השנייה").
      2.times do
        over = overlapping(grp, loop_xy)
        break if over.empty?
        over.map { |f| f.vertices.first.position.z.to_f }.uniq.each { |z| draw_loop!(grp, split_loop(loop_xy, segs_at(grp, z)), z) }
        sweep_inside!(grp, loop_xy, nil)
      end
      left = overlapping(grp, loop_xy)
      puts "[ShowerFloor] #{left.length} face(s) of #{grp.name} still lie over the shower" if left.any?
      0.0
    rescue StandardError => e
      puts "[ShowerFloor] cut_out! failed on #{grp && grp.name}: #{e.class}: #{e.message}"
      0.0
    end

    # Every flat face of this group that is over the loop at all - its
    # middle inside, a corner of it inside, or a corner of the loop on
    # it. A tile that only OVERLAPS the loop is exactly the one that has
    # to be split, so it counts.
    def self.overlapping(grp, loop_xy)
      grp.entities.grep(Sketchup::Face).select do |f|
        next false unless f.valid? && f.normal.z.abs > 0.9
        vs = f.vertices.map(&:position)
        next false if vs.empty?
        mid = face_middle(f)
        next true if mid && point_in?(loop_xy, mid[0], mid[1])
        next true if vs.any? { |p| point_in?(loop_xy, p.x.to_f, p.y.to_f) }
        z = vs.first.z.to_f
        loop_xy.any? do |x, y|
          begin
            f.classify_point(Geom::Point3d.new(x, y, z)) == Sketchup::Face::PointInside
          rescue StandardError
            false
          end
        end
      end
    rescue StandardError => e
      puts "[ShowerFloor] overlapping: #{e.message}"
      []
    end

    # Every line of the group lying flat at this z, as 2D pairs - the
    # tile borders and the joint lines the loop has to be split against.
    def self.segs_at(grp, z)
      grp.entities.grep(Sketchup::Edge).map do |e|
        next nil unless e.valid?
        a = e.start.position
        b = e.end.position
        next nil if (a.z.to_f - z).abs > 0.01 || (b.z.to_f - z).abs > 0.01
        [[a.x.to_f, a.y.to_f], [b.x.to_f, b.y.to_f]]
      end.compact
    rescue StandardError => e
      puts "[ShowerFloor] segs_at: #{e.message}"
      []
    end

    def self.draw_loop!(grp, loop_xy, z)
      pts = loop_xy.map { |x, y| Geom::Point3d.new(x, y, z) }
      pts << pts.first
      if grp.entities.respond_to?(:add_edges)
        grp.entities.add_edges(pts)
      else
        pts.each_cons(2) { |a, b| grp.entities.add_line(a, b) }
      end
    rescue StandardError => e
      puts "[ShowerFloor] the loop could not be drawn at z #{z}: #{e.message}"
    end

    # Take away every flat face inside the loop (and, for a slab, the lid
    # left at the bottom of the cut). Silence here is what left the hole
    # shut, so the count is printed.
    # The middle of a face, straight off its own corners - no bounds
    # object, which is one more thing that can be missing. PURE enough.
    def self.face_middle(f)
      vs = f.vertices.map(&:position)
      return nil if vs.empty?
      [vs.map { |p| p.x.to_f }.inject(:+) / vs.length, vs.map { |p| p.y.to_f }.inject(:+) / vs.length]
    rescue StandardError
      nil
    end

    # Is the point ON the loop's line (within tol)? PURE.
    def self.on_loop?(pts, x, y, tol = 0.01)
      p = clean_loop(pts)
      return false if p.length < 2
      x = x.to_f; y = y.to_f
      p.each_with_index do |(ax, ay), i|
        bx, by = p[(i + 1) % p.length]
        dx = bx - ax; dy = by - ay
        len2 = dx * dx + dy * dy
        t = len2 < 1.0e-12 ? 0.0 : [[((x - ax) * dx + (y - ay) * dy) / len2, 0.0].max, 1.0].min
        return true if Math.hypot(x - (ax + dx * t), y - (ay + dy * t)) <= tol
      end
      false
    end

    def self.inside_or_on?(pts, x, y)
      point_in?(pts, x, y) || on_loop?(pts, x, y)
    end

    # ONLY WHAT IS WHOLLY INSIDE THE LOOP GOES (2026-09-22, measured on
    # his model). "Middle inside" took out the slab's whole bottom face
    # (its middle fell 0.05" inside the loop) and the grout backing under
    # the whole room. Now a face goes only when EVERY corner is inside
    # or on the line, and a line only when both ends are inside or on it
    # and its middle is strictly inside - so the loop's own lines, which
    # now border the tiles round the hole, are never touched.
    def self.sweep_inside!(grp, loop_xy, only_z)
      gone = grp.entities.grep(Sketchup::Face).select do |f|
        next false unless f.valid? && f.normal.z.abs > 0.9
        z = f.vertices.first.position.z.to_f
        next false if only_z && (z - only_z).abs > 0.01
        vs = f.vertices.map(&:position)
        next false if vs.empty?
        c = face_middle(f)
        c && point_in?(loop_xy, c[0], c[1]) && vs.all? { |q| inside_or_on?(loop_xy, q.x.to_f, q.y.to_f) }
      end
      # The joint lines inside the loop are drawn edges, not faces, and
      # they stay behind when their face goes - a line hanging over the
      # shower floor.
      grp.entities.erase_entities(gone) unless gone.empty?
      # A LINE THAT STILL HOLDS A FACE IS NEVER TOUCHED (2026-09-22,
      # measured on his model: the tile next to the shower sat 0.01" off
      # the loop line, its edge counted as "inside", and erasing that
      # edge killed the whole tile - the white spot on the bathroom
      # floor). So the faces go first, and then only the lines left with
      # NO face on them, both ends inside or on the loop.
      edges = grp.entities.grep(Sketchup::Edge).select do |e|
        next false unless e.valid?
        next false if e.respond_to?(:faces) && e.faces.any?
        a = e.start.position
        b = e.end.position
        next false if only_z && ((a.z.to_f - only_z).abs > 0.01 || (b.z.to_f - only_z).abs > 0.01)
        inside_or_on?(loop_xy, a.x.to_f, a.y.to_f) && inside_or_on?(loop_xy, b.x.to_f, b.y.to_f)
      end
      return 0 if gone.empty? && edges.empty?
      puts "[ShowerFloor] took out #{gone.length} face(s) and #{edges.length} line(s) inside the loop of #{grp.name}"
      grp.entities.erase_entities(edges) unless edges.empty?
      gone.length
    rescue StandardError => e
      puts "[ShowerFloor] sweep_inside!: #{e.message}"
      0
    end

    # Build the floor he drew.
    #   kind 'flat' - a hole in the room floor, the pad dead level in it.
    #   kind 'curb' - the pad `rise` above the room floor (the curb round
    #                 it: CURB_W inside the line, open sides only).
    OWN_TILE = 'Own tile' unless const_defined?(:OWN_TILE, false)

    # settings: the window's numbers (ShowerFloorDialog.KEYS). With them,
    # kind/rise/curb_h come from the window, and "same_room" false means
    # the shower lays ITS OWN tile from those numbers (2026-09-22).
    def self.build!(pts, floor_z, kind: 'flat', rise: DEFAULT_RISE, curb_h: DEFAULT_CURB_H,
                    tile: SAME_AS_ROOM, model: nil, settings: nil)
      if settings
        kind = settings['kind'].to_s
        rise = settings['rise'].to_f
        curb_h = settings['curb_h'].to_f
        tile = settings['same_room'] ? SAME_AS_ROOM : OWN_TILE
      end
      unless USE_SHOWER_FLOOR
        puts '[ShowerFloor] USE_SHOWER_FLOOR is off - nothing built'
        return nil
      end
      model ||= Sketchup.active_model
      loop_xy = clean_loop(pts)
      if loop_xy.length < 3
        puts "[ShowerFloor] not built: only #{loop_xy.length} corner(s)"
        return nil
      end
      kind = 'flat' unless KINDS.include?(kind.to_s)
      trace("build! kind #{kind} tile #{tile} settings #{settings ? settings.reject { |k, _| %w[spec grout_spec].include?(k) }.inspect : 'none'}")
      unders = floors_under(loop_xy, floor_z, model)
      pats = unders.select { |g| g.get_attribute('InteriorPro', 'type').to_s == 'floor_pattern' }
      slab = slab_of(unders) || (pats.first && floor_of_pattern(pats.first, model))
      floor_grp = slab || unders.first
      # A shower floor drawn again on the same loop REPLACES the old one
      # (two pads on one plane fight for it and show white).
      pads_in_model(model).each do |old|
        op = Array(old.get_attribute('InteriorPro', 'poly_xy')).map(&:to_f).each_slice(2).to_a
        next unless same_loop?(op, loop_xy)
        oid = old.get_attribute('InteriorPro', 'id')
        tiles_of(oid, model).each(&:erase!)
        curbs_of(oid, model).each(&:erase!)
        old.erase!
      end
      # The room's tile is read BEFORE the layout is rebuilt round the
      # hole (the rebuild throws the old layout group away).
      room_mat = room_floor_material(pats.first || floor_grp)
      # REAL TILES, THE ROOM'S GRID RUNNING ON (2026-09-22, his words: "בדיוק
      # כמו הטיל של הריצפות"). "Same as the room floor" lays the room's own
      # layout inside the loop. Read now - the layout group may be rebuilt.
      src = slab || (pats.first && floor_of_pattern(pats.first, model))
      # "Same as the room floor" in a room with a tile layout but no slab
      # to run the grid from (his room 2): the room's tile is MEASURED and
      # laid as the shower's own, so it is tiles, not one big face.
      if settings && settings['same_room'] && !(src && !%w[None].include?((src.get_attribute('InteriorPro', 'pattern') || 'None').to_s))
        got = room_settings(src || floor_grp, pats.first, model)
        if got['pattern'].to_s == 'Tile' && (got['unit_w'].to_f > 0.25) && (!got['material_card_id'].to_s.empty? || !got['texture'].to_s.empty?)
          settings = settings.merge(got).merge('same_room' => false)
          if got['anchor_x']
            xs = loop_xy.map { |x, _y| x }
            ys = loop_xy.map { |_x, y| y }
            settings['ox'] = got['anchor_x'].to_f - xs.min
            settings['oy'] = got['anchor_y'].to_f - ys.min
            settings['center'] = false
            settings['angle'] = 0.0
          end
          tile = OWN_TILE
          puts '[ShowerFloor] the room has no floor settings - its tile was measured and laid as the shower\'s own'
        end
      end
      # LINE UP WITH THE WALL JOINTS (2026-09-22, his ask, an option that
      # only comes with a curb): the shower floor's grout lines run on
      # from the tile walls round it, not from the bathroom floor. The
      # joint is measured off each shower's own walls.
      wall_joints = settings && kind == 'curb' && settings['wall_joints'] ? true : false
      if wall_joints && USE_WALL_JOINTS
        settings = settings.dup # never change the caller's numbers
        if settings['same_room']
          got = room_settings(src || floor_grp, pats.first, model)
          if got['pattern'].to_s == 'Tile' && got['unit_w'].to_f > 0.25
            settings = settings.merge(got).merge('same_room' => false)
            tile = OWN_TILE
          end
        end
        an = pick_anchors(loop_xy, wall_joints_by_side(loop_xy, model))
        if settings['same_room']
          trace('wall joints: the room tile could not be read - grid left as it was')
          puts '[ShowerFloor] the room tile could not be read - the shower grid is left as it was'
        elsif an['x'] && an['y']
          half = settings['grout'].to_f / 2.0
          settings['ox'] = an['x'] + half - loop_xy.map { |x, _y| x }.min
          settings['oy'] = an['y'] + half - loop_xy.map { |_x, y| y }.min
          settings['center'] = false
          settings['angle'] = 0.0
          trace("wall joints: grid on x #{an['x'].round(3)} y #{an['y'].round(3)} -> ox #{settings['ox'].round(3)} oy #{settings['oy'].round(3)}")
        else
          trace("wall joints: not found on both axes #{an.inspect} - grid left as it was")
          puts '[ShowerFloor] no wall grout line found on both directions - the shower grid is left as it was'
        end
      end
      own = settings && !settings['same_room'] && settings['pattern'].to_s != 'None' && !settings['pattern'].to_s.empty?
      lay = USE_SHOWER_TILES && defined?(InteriorPro::FloorPattern) &&
            (own || (tile.to_s == SAME_AS_ROOM && src &&
                     !%w[None].include?((src.get_attribute('InteriorPro', 'pattern') || 'None').to_s)))
      puts "[ShowerFloor] no room tile layout to run on - one plain face (tile: #{tile})" unless lay
      if kind == 'flat'
        # NO FLOOR, NO FLAT SHOWER FLOOR (2026-09-22, measured on his
        # model: he drew in a room whose floor had never been built, the
        # hole had nothing to be cut in, and the pad ended up hanging
        # under the slab - "הריצפה של המקלחת ביכלל הפוכה". A silent skip
        # is the bug CLAUDE.md warns about, so it stops and says so.)
        if unders.empty?
          puts '[ShowerFloor] there is no room floor here - build the floor for this room first'
          return :no_floor
        end
        # The top he sees: the tile layout if there is one, the slab if
        # not - so the shower floor lands DEAD LEVEL with the room, which
        # is what he chose (2026-09-22, "באותו גובה").
        top = finished_top(unders, floor_z)
        deep = 0.0
        if slab
          add_hole!(slab, loop_xy)
          deep = cut_floor!(slab) > 0 ? slab.get_attribute('InteriorPro', 'thickness_in').to_f : 0.0
          # The layout is REBUILT with the hole in it (FloorPattern clips
          # every tile round the stored holes). If it cannot be rebuilt
          # here, the standing layout is cut instead.
          rebuilt = begin
            defined?(InteriorPro::FloorPattern) && InteriorPro::FloorPattern.build_for_floor!(slab)
          rescue StandardError => e
            puts "[ShowerFloor] layout rebuild: #{e.message}"
            false
          end
          (pats | patterns_of(slab, model)).each { |g| cut_pattern!(g, slab) if g.valid? } unless rebuilt
        else
          # No slab: the layout itself remembers the hole, so drawing the
          # same shower again still finds this floor (2026-09-22).
          pats.each { |g| add_hole!(g, loop_xy); cut_out!(g, loop_xy, top) }
        end
        th = deep > 0.05 ? deep : 0.5
      else
        room_top = finished_top(unders, floor_z)
        top = room_top + rise.to_f
        th = rise.to_f
        th = 0.25 if th < 0.25
      end
      # THE CURB (2026-09-22, his choice "1": inside the line). The sides
      # with no wall behind them get a 4" curb; the pad and its tiles
      # shrink to what is left inside the curb, so the two never run
      # into each other (CLAUDE.md: boards meet).
      floor_xy = loop_xy
      curb_pc = []
      if kind == 'curb' && USE_CURB
        walled = wall_sides(loop_xy, wall_boxes(model))
        curb_pc = curb_pieces(loop_xy, walled)
        floor_xy = inset_loop(loop_xy, walled.map { |w| w ? 0.0 : CURB_W })
        trace("curb: sides walled #{walled.inspect} -> #{curb_pc.length} curb piece(s), floor inside #{floor_xy.map { |x, y| [x.round(3), y.round(3)] }.inspect}")
        puts '[ShowerFloor] every side has a wall behind it - no curb built' if curb_pc.empty?
      end
      grp = model.entities.add_group
      grp.name = 'InteriorPro_ShowerFloor'
      begin
        InteriorPro.assign_tag(grp, 'IP/Floors')
      rescue StandardError => e
        puts "[ShowerFloor] no tag: #{e.message}"
      end
      # Tiles sit LINE_Z over their base, exactly as in the room - so the
      # pad under them drops by that much and the tile top stays level.
      pad_top = lay ? top - InteriorPro::FloorPattern::LINE_Z : top
      face = begin
        grp.entities.add_face(floor_xy.map { |x, y| Geom::Point3d.new(x, y, pad_top) })
      rescue StandardError => e
        puts "[ShowerFloor] add_face failed: #{e.message}"
        nil
      end
      if face.nil?
        grp.erase! if grp.valid?
        return nil
      end
      face.pushpull(face.normal.z > 0 ? -th : th)
      mat = own ? own_material(model, settings) : material(model, tile, floor_grp, room_mat)
      grp.entities.grep(Sketchup::Face).each { |f| f.material = mat }
      grp.set_attribute('InteriorPro', 'type', 'shower_floor')
      grp.set_attribute('InteriorPro', 'id', format('shfloor-%s-%04d', Time.now.to_i.to_s(36), rand(10_000)))
      grp.set_attribute('InteriorPro', 'poly_xy', loop_xy.flatten)
      grp.set_attribute('InteriorPro', 'floor_z', floor_z.to_f)
      grp.set_attribute('InteriorPro', 'kind', kind)
      grp.set_attribute('InteriorPro', 'rise_in', kind == 'curb' ? rise.to_f : 0.0)
      grp.set_attribute('InteriorPro', 'curb_h_in', curb_h.to_f)
      grp.set_attribute('InteriorPro', 'thickness_in', th)
      grp.set_attribute('InteriorPro', 'tile', tile.to_s)
      # THE SAME NAMES A FLOOR USES - so FloorPattern and the takeoff read
      # the shower exactly like a floor (2026-09-22).
      if settings
        grp.set_attribute('InteriorPro', 'pattern', settings['pattern'].to_s)
        grp.set_attribute('InteriorPro', 'unit_w', settings['unit_w'].to_f)
        grp.set_attribute('InteriorPro', 'unit_l', settings['unit_l'].to_f)
        grp.set_attribute('InteriorPro', 'pattern_ox', settings['ox'].to_f)
        grp.set_attribute('InteriorPro', 'pattern_oy', settings['oy'].to_f)
        grp.set_attribute('InteriorPro', 'pattern_angle', settings['angle'].to_f)
        grp.set_attribute('InteriorPro', 'pattern_center', settings['center'] ? true : false)
        grp.set_attribute('InteriorPro', 'pattern_grout', settings['grout'].to_f)
        grp.set_attribute('InteriorPro', 'pattern_stagger', settings['stagger'].to_f)
        grp.set_attribute('InteriorPro', 'pattern_grout_color', settings['grout_color'].to_s)
        grp.set_attribute('InteriorPro', 'floor_texture', settings['texture'].to_s)
        grp.set_attribute('InteriorPro', 'material_card_id', settings['material_card_id'].to_s)
        grp.set_attribute('InteriorPro', 'floor_spec', settings['spec'].to_s)
        grp.set_attribute('InteriorPro', 'grout_spec', settings['grout_spec'].to_s)
        grp.set_attribute('InteriorPro', 'floor_level', pad_top)
      end
      src = grp if own
      grp.set_attribute('InteriorPro', 'room_id', floor_grp && floor_grp.get_attribute('InteriorPro', 'room_id'))
      grp.set_attribute('InteriorPro', 'area_sqft', area_sqft(loop_xy))
      # What the count calls it: its own card / texture, or the room's.
      grp.set_attribute('InteriorPro', 'floor_type', floor_type_name(settings, tile, src))
      grp.set_attribute('InteriorPro', 'created_at', Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
      trace("build! own #{own ? 'yes' : 'no'} lay #{lay ? 'yes' : 'no'} src #{src ? src.get_attribute('InteriorPro', 'type') : 'none'} pad_top #{pad_top.round(3)} mat #{mat && mat.name}")
      if lay
        sp = begin
          InteriorPro::FloorPattern.build_for_floor!(src, clip: floor_xy, base_z: pad_top,
                                                     shower_id: grp.get_attribute('InteriorPro', 'id'))
        rescue StandardError => e
          puts "[ShowerFloor] shower tiles: #{e.message}"
          nil
        end
        trace("build! tiles #{sp ? 'laid' : 'NOT laid'}")
        if sp
          grp.set_attribute('InteriorPro', 'tiles', 'room')
        else
          # No tiles after all: the pad goes back up to the finished level.
          puts '[ShowerFloor] shower tiles were not laid - the pad is lifted back to the room level'
          grp.transform!(Geom::Transformation.translation(Geom::Vector3d.new(0, 0, InteriorPro::FloorPattern::LINE_Z)))
        end
      end
      # "Curb same as the bathroom floor" (2026-09-22, his ask): the curb
      # wears the room's tile, whatever tile the shower floor has.
      curb_room = settings && settings['curb_room'] ? true : false
      grp.set_attribute('InteriorPro', 'curb_room', curb_room)
      grp.set_attribute('InteriorPro', 'wall_joints', wall_joints)
      unless curb_pc.empty?
        curb_mat = curb_room ? (room_mat || material(model, SAME_AS_ROOM, floor_grp)) : mat
        trace("curb: wears #{curb_room ? 'the bathroom floor' : 'the shower floor'} - #{curb_mat && curb_mat.name}")
        made = build_curbs!(curb_pc, room_top, curb_h.to_f, curb_mat, grp.get_attribute('InteriorPro', 'id'), model)
        grp.set_attribute('InteriorPro', 'curb_count', made.length)
        trace("curb: #{made.length} of #{curb_pc.length} built, #{curb_h.to_f}\" tall from z #{room_top.round(3)}")
      end
      grp
    rescue StandardError => e
      trace("build! raised #{e.class}: #{e.message} #{e.backtrace.first(2).join(' | ')}")
      puts "[ShowerFloor] build! failed: #{e.class}: #{e.message}"
      puts e.backtrace.first(4).join("\n")
      nil
    end
  end
end
