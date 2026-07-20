# Interior Pro - Floor Pattern (Tile / Straight / Herringbone / Chevron)
# Revit-style split (2026-07-18): the RENDER texture and the DOCUMENTATION
# pattern are independent layers on tag IP/FloorPatterns.
#
# Two modes per floor:
#  - No material chosen: layout LINES only (documentation), as before.
#  - Material chosen (floor_texture) + plank pattern (Straight/Herringbone/
#    Chevron): real plank FACES, each textured ALONG ITS OWN direction with a
#    random offset — the wood follows the installation direction (2026-07-18).
#    Tile keeps the uniform floor texture + grid lines (direction is uniform).
#
# Floor attributes read (stored on the floor group):
#   pattern, unit_w, unit_l, pattern_ox/oy, pattern_angle, pattern_center,
#   floor_texture (base name of a file in textures/floors).
# NOTE: grain is assumed to run along the IMAGE's horizontal axis.
module InteriorPro
  module FloorPattern
    PATTERNS = ['None', 'Tile', 'Straight', 'Herringbone', 'Chevron'].freeze unless const_defined?(:PATTERNS, false)
    LINE_Z = 0.05 unless const_defined?(:LINE_Z, false) # above floor top (z=0)

    def self.patterns_in_model
      Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'floor_pattern'
      end
    end

    def self.remove_for_floor!(floor_id)
      patterns_in_model.each do |g|
        g.erase! if g.valid? && g.get_attribute('InteriorPro', 'floor_id') == floor_id
      end
    end

    # Rebuild patterns for all floors; remove orphan pattern groups.
    def self.refresh_all!
      floors = InteriorPro::FloorManager.floors_in_model
      floor_ids = floors.map { |f| f.get_attribute('InteriorPro', 'id') }
      patterns_in_model.each do |g|
        g.erase! if g.valid? && !floor_ids.include?(g.get_attribute('InteriorPro', 'floor_id'))
      end
      n = 0
      floors.each { |f| n += 1 if build_for_floor!(f) }
      puts "[FloorPattern] #{n} pattern(s)" if n > 0
      n
    rescue StandardError => e
      puts "[FloorPattern] refresh_all! failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      0
    end

    def self.build_for_floor!(floor)
      fid = floor.get_attribute('InteriorPro', 'id')
      remove_for_floor!(fid)
      pattern = (floor.get_attribute('InteriorPro', 'pattern') || 'None').to_s
      return false if pattern == 'None' || pattern.empty?
      unless PATTERNS.include?(pattern)
        puts "[FloorPattern] pattern '#{pattern}' not supported yet"
        return false
      end

      room = InteriorPro::RoomManager.rooms_in_model.find do |r|
        r.get_attribute('InteriorPro', 'id') == floor.get_attribute('InteriorPro', 'room_id')
      end
      return false unless room
      flat = room.get_attribute('InteriorPro', 'boundary_xy')
      return false unless flat && flat.length >= 6
      poly = flat.each_slice(2).map { |x, y| Geom::Point3d.new(x.to_f, y.to_f, 0) }

      w = floor.get_attribute('InteriorPro', 'unit_w').to_f
      l = floor.get_attribute('InteriorPro', 'unit_l').to_f
      w = 12.0 if w <= 0.25
      if l <= 0.25
        l = case pattern
            when 'Straight' then 48.0
            when 'Herringbone', 'Chevron' then w * 4.0
            else w
            end
      end
      ox = floor.get_attribute('InteriorPro', 'pattern_ox').to_f
      oy = floor.get_attribute('InteriorPro', 'pattern_oy').to_f
      ang = floor.get_attribute('InteriorPro', 'pattern_angle').to_f * Math::PI / 180.0
      centered = floor.get_attribute('InteriorPro', 'pattern_center') ? true : false

      grout = floor.get_attribute('InteriorPro', 'pattern_grout').to_f
      grout = 0.0 if grout.negative?
      grout = [grout, [w, l].min * 0.4].min

      # Plank/tile material: only when the floor has a chosen texture.
      mat = nil
      tex = floor.get_attribute('InteriorPro', 'floor_texture')
      if tex && %w[Straight Herringbone Chevron Tile].include?(pattern)
        m = InteriorPro::FloorManager.texture_material(Sketchup.active_model, tex)
        mat = m if m && m.texture
      end

      model = Sketchup.active_model
      grp = model.entities.add_group
      grp.name = 'InteriorPro_FloorPattern'
      InteriorPro.assign_tag(grp, 'IP/FloorPatterns')
      ge = grp.entities

      planks = case pattern
               when 'Herringbone' then herringbone_planks(poly, ang, w, l, ox, oy, centered)
               when 'Chevron'     then chevron_planks(poly, ang, w, l, ox, oy, centered)
               when 'Straight'    then straight_planks(poly, ang, w, l, ox, oy, centered)
               when 'Tile'        then mat ? tile_planks(poly, ang, w, l, ox, oy, centered, grout) : nil
               end
      if pattern == 'Tile' && mat.nil?
        draw_tile_lines!(ge, poly, ang, w, l, ox, oy, centered)
      elsif planks
        if mat
          # Tiles with grout: a grout-colored backing face under the tiles
          # (the joints ARE the grout) — no line layer needed.
          if pattern == 'Tile' && grout > 0.02
            build_grout_backing!(ge, poly, floor.get_attribute('InteriorPro', 'pattern_grout_color'))
            emit_plank_faces!(ge, planks, poly, mat)
          else
            # Material layer (all face edges hidden) + a clean uniform line
            # layer slightly above it — line weight is identical everywhere.
            emit_plank_faces!(ge, planks, poly, mat)
            emit_plank_edges!(ge, planks, poly, LINE_Z + 0.02)
          end
        else
          emit_plank_edges!(ge, planks, poly)
        end
      end

      if grp.valid? && ge.length.zero?
        grp.erase!
        return false
      end
      grp.set_attribute('InteriorPro', 'type', 'floor_pattern')
      grp.set_attribute('InteriorPro', 'floor_id', fid)
      grp.set_attribute('InteriorPro', 'room_id', floor.get_attribute('InteriorPro', 'room_id'))
      true
    rescue StandardError => e
      puts "[FloorPattern] build_for_floor!: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      false
    end

    # ---------- frames ----------

    def self.frame(poly, ang)
      u_axis = Geom::Vector3d.new(Math.cos(ang), Math.sin(ang), 0)
      v_axis = Geom::Vector3d.new(-Math.sin(ang), Math.cos(ang), 0)
      pu = ->(p) { p.x * u_axis.x + p.y * u_axis.y }
      pv = ->(p) { p.x * v_axis.x + p.y * v_axis.y }
      us = poly.map { |p| pu.call(p) }
      vs = poly.map { |p| pv.call(p) }
      cen = InteriorPro::RoomManager.centroid(poly)
      { u: u_axis, v: v_axis, pu: pu, pv: pv,
        u_min: us.min, u_max: us.max, v_min: vs.min, v_max: vs.max,
        cu: pu.call(cen), cv: pv.call(cen) }
    end

    def self.world_pt(fr, uu, vv)
      [fr[:u].x * uu + fr[:v].x * vv, fr[:u].y * uu + fr[:v].y * vv]
    end

    # ---------- plank enumerators ----------
    # Each plank: { c: [[x,y]x4] (convex, in order), origin: [x,y], dir: [dx,dy] }

    def self.straight_planks(poly, ang, w, l, ox, oy, centered)
      fr = frame(poly, ang)
      o_u = (centered ? fr[:cu] - l / 2.0 : fr[:u_min]) + ox
      o_v = (centered ? fr[:cv] - w / 2.0 : fr[:v_min]) + oy
      u_start = o_u - ((o_u - fr[:u_min]) / l).ceil * l
      v_start = o_v - ((o_v - fr[:v_min]) / w).ceil * w
      planks = []
      ri = 0
      vv = v_start
      while vv <= fr[:v_max] + 0.001
        uu = u_start + (ri.odd? ? l / 2.0 : 0.0) - l
        while uu <= fr[:u_max] + 0.001
          planks << {
            c: [world_pt(fr, uu, vv), world_pt(fr, uu + l, vv),
                world_pt(fr, uu + l, vv + w), world_pt(fr, uu, vv + w)],
            origin: world_pt(fr, uu, vv),
            dir: [fr[:u].x, fr[:u].y]
          }
          uu += l
        end
        vv += w
        ri += 1
      end
      return nil if planks.length > 60_000
      planks
    end

    def self.herringbone_planks(poly, ang, w, l, ox, oy, centered)
      m = [(l / w).round, 1].max
      fr = frame(poly, ang + Math::PI / 4.0)
      o_u = (centered ? fr[:cu] : fr[:u_min]) + ox
      o_v = (centered ? fr[:cv] : fr[:v_min]) + oy
      a0 = ((fr[:u_min] - o_u) / w).floor - m
      a1 = ((fr[:u_max] - o_u) / w).ceil + m
      b0 = ((fr[:v_min] - o_v) / w).floor - m
      b1 = ((fr[:v_max] - o_v) / w).ceil + m
      if (a1 - a0) * (b1 - b0) > 400_000
        puts '[FloorPattern] herringbone grid too dense — increase plank width'
        return nil
      end
      two_m = 2 * m
      planks = []
      (a0..a1).each do |a|
        cu = o_u + a * w
        (b0..b1).each do |b|
          r = ((a - b) % two_m + two_m) % two_m
          next unless r.zero? || r == m
          cv = o_v + b * w
          if r.zero? # runs along u
            planks << {
              c: [world_pt(fr, cu, cv), world_pt(fr, cu + m * w, cv),
                  world_pt(fr, cu + m * w, cv + w), world_pt(fr, cu, cv + w)],
              origin: world_pt(fr, cu, cv),
              dir: [fr[:u].x, fr[:u].y]
            }
          else # runs along v
            planks << {
              c: [world_pt(fr, cu, cv - (m - 1) * w), world_pt(fr, cu + w, cv - (m - 1) * w),
                  world_pt(fr, cu + w, cv + w), world_pt(fr, cu, cv + w)],
              origin: world_pt(fr, cu, cv - (m - 1) * w),
              dir: [fr[:v].x, fr[:v].y]
            }
          end
        end
      end
      planks
    end

    # Tile grid (2026-07-18): one image per tile ("photo tile", showers etc).
    # Cells are l (u) x w (v); each tile is inset by grout/2 on every side and
    # its texture is anchored so the IMAGE maps exactly onto the tile —
    # no random offset (every tile shows the full image).
    def self.tile_planks(poly, ang, w, l, ox, oy, centered, grout = 0.0)
      fr = frame(poly, ang)
      o_u = (centered ? fr[:cu] - l / 2.0 : fr[:u_min]) + ox
      o_v = (centered ? fr[:cv] - w / 2.0 : fr[:v_min]) + oy
      u_start = o_u - ((o_u - fr[:u_min]) / l).ceil * l
      v_start = o_v - ((o_v - fr[:v_min]) / w).ceil * w
      g2 = grout / 2.0
      tiles = []
      vv = v_start
      while vv <= fr[:v_max] + 0.001
        uu = u_start
        while uu <= fr[:u_max] + 0.001
          ua = uu + g2
          ub = uu + l - g2
          va = vv + g2
          vb = vv + w - g2
          if ub - ua > 0.1 && vb - va > 0.1
            tiles << {
              c: [world_pt(fr, ua, va), world_pt(fr, ub, va),
                  world_pt(fr, ub, vb), world_pt(fr, ua, vb)],
              origin: world_pt(fr, ua, va),
              dir: [fr[:u].x, fr[:u].y],
              tex_w: ub - ua, tex_h: vb - va, no_rand: true
            }
          end
          uu += l
        end
        vv += w
      end
      return nil if tiles.length > 60_000
      tiles
    end

    GROUT_COLORS = {
      'light' => [210, 208, 204],
      'gray'  => [165, 163, 160],
      'dark'  => [92, 90, 88],
      'white' => [245, 245, 243]
    }.freeze unless const_defined?(:GROUT_COLORS, false)

    # Grout-colored backing face covering the whole room, under the tiles.
    def self.build_grout_backing!(ge, poly, color_key = nil)
      model = Sketchup.active_model
      key = GROUT_COLORS.key?(color_key.to_s) ? color_key.to_s : 'light'
      name = "InteriorPro_Grout_#{key.capitalize}"
      m = model.materials[name]
      unless m
        m = model.materials.add(name)
        m.color = Sketchup::Color.new(*GROUT_COLORS[key])
      end
      pts = poly.map { |p| Geom::Point3d.new(p.x, p.y, LINE_Z - 0.02) }
      f = begin
        ge.add_face(pts)
      rescue StandardError
        nil
      end
      return unless f
      f.reverse! if f.normal.z < 0
      f.material = m
      f.back_material = nil
      f.edges.each do |e|
        e.hidden = true
        e.soft = true
      end
    end

    def self.chevron_planks(poly, ang, w, l, ox, oy, centered)
      fr = frame(poly, ang)
      c = l / Math.sqrt(2.0)
      s = w * Math.sqrt(2.0)
      o_u = (centered ? fr[:cu] : fr[:u_min]) + ox
      o_v = (centered ? fr[:cv] : fr[:v_min]) + oy
      k0 = ((fr[:u_min] - o_u) / c).floor - 1
      k1 = ((fr[:u_max] - o_u) / c).ceil
      n0 = ((fr[:v_min] - o_v - c) / s).floor - 1
      n1 = ((fr[:v_max] - o_v) / s).ceil + 1
      if (k1 - k0) * (n1 - n0) > 400_000
        puts '[FloorPattern] chevron grid too dense — increase sizes'
        return nil
      end
      inv = 1.0 / Math.sqrt(2.0)
      planks = []
      (k0..k1).each do |k|
        su = o_u + k * c
        slope = k.even? ? 1.0 : -1.0
        v_base = k.odd? ? c : 0.0
        dirw = [(fr[:u].x + slope * fr[:v].x) * inv, (fr[:u].y + slope * fr[:v].y) * inv]
        (n0..n1).each do |n|
          v0 = o_v + n * s + v_base
          planks << {
            c: [world_pt(fr, su, v0), world_pt(fr, su + c, v0 + slope * c),
                world_pt(fr, su + c, v0 + slope * c + s), world_pt(fr, su, v0 + s)],
            origin: world_pt(fr, su, v0),
            dir: dirw
          }
        end
      end
      planks
    end

    # ---------- emitters ----------

    # Textured mode: each plank becomes a face clipped to the room, painted
    # with the material oriented ALONG the plank + random offset.
    # Textured mode (final approach 2026-07-18): the room polygon is
    # TRIANGULATED once; each plank is clipped against each triangle
    # (convex-vs-convex Sutherland-Hodgman = exact, no bridges, no misses).
    # All pieces of one plank share the same texture anchor, and the seams
    # between them (triangulation lines) are hidden — so a plank reads as one
    # continuous board, clipped perfectly at the room boundary.
    def self.emit_plank_faces!(ge, planks, poly, mat)
      t = mat.texture
      tw = t ? t.width.to_f : 48.0
      tw = 48.0 if tw < 1.0
      th = t ? t.height.to_f : tw
      th = tw if th < 1.0
      tris = triangulate(poly.map { |p| [p.x, p.y] })
      if tris.empty?
        puts '[FloorPattern] triangulation failed — no plank faces'
        return
      end
      face_fails = 0
      uv_fails = 0
      planks.each do |pl|
        # texture anchor computed ONCE per plank — shared by all its pieces.
        # Tiles override the mapping scale (image spans exactly one tile)
        # and disable the random offset (every tile shows the full image).
        tw_pl = pl[:tex_w] || tw
        th_pl = pl[:tex_h] || th
        d = pl[:dir]
        o = Geom::Point3d.new(pl[:origin][0], pl[:origin][1], LINE_Z)
        pu = Geom::Point3d.new(o.x + d[0] * tw_pl, o.y + d[1] * tw_pl, LINE_Z)
        pv = Geom::Point3d.new(o.x - d[1] * th_pl, o.y + d[0] * th_pl, LINE_Z)
        off_u = pl[:no_rand] ? 0.0 : rand
        off_v = pl[:no_rand] ? 0.0 : rand
        faces = []
        tris.each do |tri|
          piece = clip_poly_convex(tri, pl[:c])
          clean = []
          piece.each do |p|
            clean << p if clean.empty? ||
                          (p[0] - clean.last[0]).abs > 0.01 || (p[1] - clean.last[1]).abs > 0.01
          end
          if clean.length > 1 &&
             (clean.first[0] - clean.last[0]).abs < 0.01 && (clean.first[1] - clean.last[1]).abs < 0.01
            clean.pop
          end
          next if clean.length < 3
          next if poly_area_abs(clean) < 0.05
          pts = clean.map { |x, y| Geom::Point3d.new(x, y, LINE_Z) }
          f = begin
            ge.add_face(pts)
          rescue StandardError
            nil
          end
          unless f
            face_fails += 1
            next
          end
          f.reverse! if f.normal.z < 0
          f.material = mat
          f.back_material = nil
          begin
            f.position_material(mat, [
                                  o,  Geom::Point3d.new(off_u,       off_v,       0),
                                  pu, Geom::Point3d.new(off_u + 1.0, off_v,       0),
                                  pv, Geom::Point3d.new(off_u,       off_v + 1.0, 0)
                                ], true)
          rescue StandardError
            uv_fails += 1
          end
          faces << f
        end
      end
      # Hide ALL face edges — the visible joints come from the separate
      # uniform line layer above, so no bold profile edges anywhere.
      ge.grep(Sketchup::Edge).each do |e|
        e.hidden = true
        e.soft = true
        e.smooth = true
      end
      puts "[FloorPattern] plank faces: #{face_fails} face fail(s), #{uv_fails} uv fail(s)" if face_fails > 0 || uv_fails > 0
    end

    # Ear-clipping triangulation of a simple polygon ([[x,y]], any winding).
    def self.triangulate(pts)
      return [] if pts.length < 3
      # normalize to counter-clockwise
      a2 = 0.0
      pts.each_with_index do |p, i|
        q = pts[(i + 1) % pts.length]
        a2 += p[0] * q[1] - q[0] * p[1]
      end
      pts = pts.reverse if a2 < 0
      idx = (0...pts.length).to_a
      tris = []
      guard = 0
      while idx.length > 3 && guard < 10_000
        guard += 1
        n = idx.length
        clipped = false
        n.times do |i|
          ia = idx[(i - 1) % n]
          ib = idx[i]
          ic = idx[(i + 1) % n]
          a = pts[ia]
          b = pts[ib]
          c = pts[ic]
          cross = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
          next if cross <= 1e-9 # reflex/degenerate corner — not an ear
          blocked = idx.any? do |j|
            next false if j == ia || j == ib || j == ic
            pt_in_tri?(pts[j], a, b, c)
          end
          next if blocked
          tris << [a, b, c]
          idx.delete_at(i)
          clipped = true
          break
        end
        break unless clipped
      end
      tris << [pts[idx[0]], pts[idx[1]], pts[idx[2]]] if idx.length == 3
      tris
    end

    def self.pt_in_tri?(p, a, b, c)
      d1 = (p[0] - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (p[1] - b[1])
      d2 = (p[0] - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (p[1] - c[1])
      d3 = (p[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (p[1] - a[1])
      neg = d1 < -1e-9 || d2 < -1e-9 || d3 < -1e-9
      pos = d1 > 1e-9 || d2 > 1e-9 || d3 > 1e-9
      !(neg && pos)
    end

    # Plank outlines clipped to the room (also used as the uniform line
    # layer above the material faces).
    def self.emit_plank_edges!(ge, planks, poly, z = LINE_Z)
      planks.each do |pl|
        cs = pl[:c]
        4.times do |i|
          a = cs[i]
          b = cs[(i + 1) % 4]
          draw_seg!(ge, a[0], a[1], b[0], b[1], poly, z)
        end
      end
    end

    def self.poly_area_abs(pts)
      a = 0.0
      pts.each_with_index do |p, i|
        q = pts[(i + 1) % pts.length]
        a += p[0] * q[1] - q[0] * p[1]
      end
      (a / 2.0).abs
    end

    # Sutherland–Hodgman: clip `subject` ([[x,y]]) by CONVEX `clip` ([[x,y]]).
    def self.clip_poly_convex(subject, clip)
      # normalize clip to counter-clockwise
      a2 = 0.0
      clip.each_with_index do |p, i|
        q = clip[(i + 1) % clip.length]
        a2 += p[0] * q[1] - q[0] * p[1]
      end
      clip = clip.reverse if a2 < 0
      out = subject
      clip.length.times do |i|
        break if out.empty?
        ax, ay = clip[i]
        bx, by = clip[(i + 1) % clip.length]
        ex = bx - ax
        ey = by - ay
        inside = ->(p) { ex * (p[1] - ay) - ey * (p[0] - ax) >= -1e-9 }
        inp = out
        out = []
        inp.each_with_index do |p, j|
          q = inp[(j + 1) % inp.length]
          pin = inside.call(p)
          qin = inside.call(q)
          out << p if pin
          if pin != qin
            dx = q[0] - p[0]
            dy = q[1] - p[1]
            den = ex * dy - ey * dx
            next if den.abs < 1e-12
            tt = (ey * (p[0] - ax) - ex * (p[1] - ay)) / den
            out << [p[0] + dx * tt, p[1] + dy * tt]
          end
        end
      end
      out
    end

    # ---------- tile lines (unchanged behavior) ----------

    def self.draw_tile_lines!(ge, poly, ang, w, l, ox, oy, centered)
      fr = frame(poly, ang)
      o_u = (centered ? fr[:cu] - l / 2.0 : fr[:u_min]) + ox
      o_v = (centered ? fr[:cv] - w / 2.0 : fr[:v_min]) + oy
      u_start = o_u - ((o_u - fr[:u_min]) / l).ceil * l
      v_start = o_v - ((o_v - fr[:v_min]) / w).ceil * w
      vv = v_start
      while vv <= fr[:v_max] + 0.001
        draw_clipped_line!(ge, fr[:v], vv, fr[:u], poly) if vv > fr[:v_min] + 0.001 && vv < fr[:v_max] - 0.001
        vv += w
      end
      uu = u_start
      while uu <= fr[:u_max] + 0.001
        draw_clipped_line!(ge, fr[:u], uu, fr[:v], poly) if uu > fr[:u_min] + 0.001 && uu < fr[:u_max] - 0.001
        uu += l
      end
    end

    # ---------- line clipping helpers ----------

    # Infinite line through (base_x, base_y) along `dir`, clipped to the
    # polygon (even-odd). Returns [t0, t1] inside intervals along `dir`.
    def self.line_poly_intervals(base_x, base_y, dir, poly)
      ts = []
      n = poly.length
      n.times do |i|
        p = poly[i]
        q = poly[(i + 1) % n]
        ex = q.x - p.x
        ey = q.y - p.y
        denom = dir.x * ey - dir.y * ex
        next if denom.abs < 1e-9
        rx = p.x - base_x
        ry = p.y - base_y
        t = (rx * ey - ry * ex) / denom
        s = (rx * dir.y - ry * dir.x) / denom
        ts << t if s >= 0.0 && s < 1.0
      end
      ts.sort.each_slice(2).select { |pair| pair.length == 2 && pair[1] - pair[0] > 0.1 }
    end

    def self.draw_clipped_line!(ge, off_axis, off, dir, poly)
      base_x = off_axis.x * off
      base_y = off_axis.y * off
      line_poly_intervals(base_x, base_y, dir, poly).each do |t0, t1|
        ge.add_edges(
          Geom::Point3d.new(base_x + dir.x * t0, base_y + dir.y * t0, LINE_Z),
          Geom::Point3d.new(base_x + dir.x * t1, base_y + dir.y * t1, LINE_Z)
        )
      end
    end

    # Finite segment (ax,ay)->(bx,by) clipped to the polygon.
    def self.draw_seg!(ge, ax, ay, bx, by, poly, z = LINE_Z)
      dx = bx - ax
      dy = by - ay
      len = Math.sqrt(dx * dx + dy * dy)
      return if len < 0.1
      dir = Geom::Vector3d.new(dx / len, dy / len, 0)
      line_poly_intervals(ax, ay, dir, poly).each do |t0, t1|
        a = [t0, 0.0].max
        b = [t1, len].min
        next if b - a < 0.1
        ge.add_edges(
          Geom::Point3d.new(ax + dir.x * a, ay + dir.y * a, z),
          Geom::Point3d.new(ax + dir.x * b, ay + dir.y * b, z)
        )
      end
    end
  end
end
