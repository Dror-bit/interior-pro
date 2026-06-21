# Interior Pro - Door Tool
# Cuts a door opening through a wall and (for French Hinged) builds a real body.
# Modeled on WindowTool, but the opening sits on the wall floor + an optional
# threshold offset instead of being measured down from a header height.

module InteriorPro
  remove_const(:DoorTool) if const_defined?(:DoorTool, false)

  class DoorTool

    attr_accessor :door_category, :door_type, :width, :height, :frame_width, :glass_frame_width,
                  :interior_depth, :floor_offset, :swing_direction, :swing_side,
                  :slide_direction, :glass_grid_style, :exterior_casing_style,
                  :interior_casing_style, :exterior_threshold, :preset_name

    def initialize
      apply_category_defaults('exterior')
    end

    def apply_category_defaults(category)
      d = InteriorPro::DoorLibrary.defaults_for(category)
      @door_category       = d['door_category']
      @door_type           = d['door_type']
      @width               = d['width'].to_f
      @height              = d['height'].to_f
      @frame_width         = d['frame_width'].to_f
      @glass_frame_width   = d['glass_frame_width'].to_f
      @interior_depth      = d['interior_depth'].to_f
      @floor_offset        = d['floor_offset'].to_f
      @swing_direction     = d['swing_direction']
      @swing_side          = d['swing_side']
      @slide_direction     = d['slide_direction']
      @glass_grid_style         = d['glass_grid_style']
      @exterior_casing_style    = InteriorPro::DoorLibrary.normalize_casing_style(d, 'exterior')
      @interior_casing_style    = InteriorPro::DoorLibrary.normalize_casing_style(d, 'interior')
      @exterior_threshold       = d['exterior_threshold'] ? true : false
      @preset_name         = ''
    end

    def activate
      Sketchup.set_status_text(
        "Door Tool: hover over a wall and click to cut opening. Press Escape to exit.",
        SB_PROMPT
      )
    end

    def deactivate(view)
      view.invalidate
    end

    def onMouseMove(flags, x, y, view)
      wall, _ = find_wall_under_cursor(view, x, y)
      view.tooltip = wall ? "Click to place #{@width}\" x #{@height}\" door opening" : ''
    end

    def onLButtonDown(flags, x, y, view)
      wall, picked_point, picked_face = find_wall_under_cursor(view, x, y)
      unless wall
        Sketchup.set_status_text("No wall under cursor. Hover over a wall to place a door.", SB_PROMPT)
        return
      end
      cut_door_opening(wall, picked_point, picked_face)
    end

    def onCancel(reason, view)
      Sketchup.active_model.select_tool(nil)
    end

    def onKeyDown(key, repeat, flags, view)
      onCancel(0, view) if key == 27
    end

    # Used by edit/replace — cut opening and build a new door component.
    def place_door_on_wall(wall_group, picked_point, picked_face = nil)
      data = prepare_door_placement(wall_group, picked_point, picked_face)
      return false unless data
      return false unless apply_wall_cut(wall_group, data)
      build_door_at(wall_group, data)
      true
    end

    # Cut wall opening only (move tool — existing door instance is kept).
    def cut_opening_only(wall_group, picked_point, picked_face = nil)
      data = prepare_door_placement(wall_group, picked_point, picked_face)
      return false unless data
      apply_wall_cut(wall_group, data)
    end

    # Cut opening from known door position (move/edit — no pick ambiguity).
    def cut_opening_from_data(wall_group, data, geo = nil)
      apply_wall_cut(wall_group, data, geo) || apply_wall_cut_snapped!(wall_group, data, geo)
    end

    # Cut opening then build door body — same sequence as interactive placement.
    def cut_and_build_door_at(wall_group, data, geo = nil, mark: nil, use_operations: true, clean_cut: false)
      model = Sketchup.active_model
      cut_ok = lambda {
        if clean_cut
          # Resize/edit on a non-pristine wall: deterministic tunnel rebuild,
          # falling back to the raw pushpull cut if it cannot find the faces.
          cut_opening_clean!(wall_group, data, geo) ||
            apply_wall_cut(wall_group, data, geo) ||
            apply_wall_cut_snapped!(wall_group, data, geo)
        else
          apply_wall_cut(wall_group, data, geo) || apply_wall_cut_snapped!(wall_group, data, geo)
        end
      }
      if use_operations
        model.start_operation('Cut Door Opening', true)
        begin
          unless cut_ok.call
            raise 'Wall cut failed'
          end
          model.commit_operation
        rescue => e
          model.abort_operation rescue nil
          puts "[DoorTool] cut error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
          return false
        end
      elsif !cut_ok.call
        puts '[DoorTool] cut failed (no operation wrap)'
        return false
      end

      build_door_at(wall_group, data, mark: mark, use_operations: use_operations)
    end

    # Build door body in an EXISTING opening (edit when opening is unchanged).
    # Does NOT cut the wall — just creates the door component.
    def build_door_in_existing_opening(wall_group, data, mark: nil)
      build_door_at(wall_group, data, mark: mark, use_operations: false)
    end

    # Place door using pre-built placement data (edit/replace).
    def place_door_from_data(wall_group, data, mark: nil)
      cut_and_build_door_at(wall_group, data, mark: mark)
    end

    # Build cut/fill data from stored door position (no click required).
    def build_opening_data(wall_group, geo, width:, height:, floor_offset:, t:, clicked_side:, fx: nil, fy: nil)
      thickness = geo[:thickness]
      half_w = width / 2.0
      door_bot_z = geo[:floor_z] + floor_offset.to_f
      door_top_z = door_bot_z + height.to_f
      n_side = geo[:n_side]
      unit = geo[:unit]
      n = geo[:n]

      cx = geo[:cline_start].x + unit.x * t + n.x * n_side
      cy = geo[:cline_start].y + unit.y * t + n.y * n_side

      if fx.nil? || fy.nil?
        offset = clicked_side * thickness / 2.0 - n_side
        fx = cx + n.x * offset
        fy = cy + n.y * offset
      end

      ux = unit.x * half_w
      uy = unit.y * half_w
      picked_point = Geom::Point3d.new(fx, fy, door_bot_z)
      outward = Geom::Vector3d.new(n.x * clicked_side, n.y * clicked_side, 0)

      {
        wall_group: wall_group,
        picked_point: picked_point,
        picked_face: nil,
        unit: unit,
        n: n,
        thickness: thickness,
        t: t.to_f,
        clicked_side: clicked_side,
        half_w: half_w,
        door_bot_z: door_bot_z,
        door_top_z: door_top_z,
        cx: cx,
        cy: cy,
        ux: ux,
        uy: uy,
        fx: fx,
        fy: fy,
        outward: outward
      }
    end

    # Close a door opening in the wall (inverse of apply_wall_cut).
    def fill_wall_opening(wall_group, data, geo = nil)
      puts "[DoorTool] fill v5: half_w=#{data[:half_w].round(2)} z=#{data[:door_bot_z].round(2)}-#{data[:door_top_z].round(2)} loops=#{collect_inner_loops_near(wall_group, data, geo).length}"

      cap_all_inner_loops_in_volume!(wall_group, data, geo)
      cap_inner_loops_at_door_position!(wall_group, data, geo)
      close_large_sheet_holes!(wall_group, data, geo)
      cap_hole_from_sheet_boundary_edges!(wall_group, data, geo)
      heal_opening_after_fill!(wall_group, data, geo)

      unless opening_still_open_after_fill?(wall_group, data, geo)
        soften_opening_sheet_edges!(wall_group, data, geo)
        log_fill_v5_result(wall_group, data, geo)
        return true
      end

      erase_opening_tunnel!(wall_group, data, geo)
      erase_parallel_batten_faces_in_volume!(wall_group, data, geo)
      erase_cap_faces_in_opening_hole!(wall_group, data, geo)
      cap_all_inner_loops_in_volume!(wall_group, data, geo)
      close_large_sheet_holes!(wall_group, data, geo)
      cap_hole_from_sheet_boundary_edges!(wall_group, data, geo)
      heal_opening_after_fill!(wall_group, data, geo)

      unless opening_still_open_after_fill?(wall_group, data, geo)
        soften_opening_sheet_edges!(wall_group, data, geo)
        log_fill_v5_result(wall_group, data, geo)
        return true
      end

      if opening_void_through_wall?(wall_group, data, geo) || tunnel_faces_in_volume?(wall_group, data, geo)
        fill_tunnel_through_opening!(wall_group, data, geo) ||
          reconstruct_solid_patch!(wall_group, data)
        cap_all_inner_loops_in_volume!(wall_group, data, geo)
        close_large_sheet_holes!(wall_group, data, geo)
        cap_hole_from_sheet_boundary_edges!(wall_group, data, geo)
        heal_opening_after_fill!(wall_group, data, geo)
      end

      soften_opening_sheet_edges!(wall_group, data, geo)
      log_fill_v5_result(wall_group, data, geo)

      if opening_still_open_after_fill?(wall_group, data, geo)
        puts '[DoorTool] fill v5: opening still open after fill'
        return false
      end

      true
    rescue => e
      puts "[DoorTool] fill_wall_opening error: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      false
    end

    def opening_still_open?(wall_group, data, geo = nil)
      collect_inner_loops_near(wall_group, data, geo).any? ||
        tunnel_faces_in_volume?(wall_group, data, geo)
    end

    # Fill still needed when hole on sheets or tunnel/jamb faces remain.
    # Do NOT use opening_void_through_wall? here — it false-fails on patched
    # walls and causes delete to abort_operation (door comes back).
    def opening_still_open_after_fill?(wall_group, data, geo = nil)
      opening_hole_at_center?(wall_group, data, geo) ||
        tunnel_faces_in_volume?(wall_group, data, geo)
    end

    def log_fill_v5_result(wall_group, data, geo = nil)
      loops = collect_inner_loops_near(wall_group, data, geo).length
      hole = opening_hole_at_center?(wall_group, data, geo)
      void = opening_void_through_wall?(wall_group, data, geo)
      tunnel = tunnel_faces_in_volume?(wall_group, data, geo)
      puts "[DoorTool] fill v5: half_w=#{data[:half_w].round(2)} z=#{data[:door_bot_z].round(2)}-#{data[:door_top_z].round(2)} loops=#{loops} hole=#{hole} void=#{void} tunnel=#{tunnel}"
    end

    def cap_all_inner_loops_in_volume!(wall_group, data, geo = nil)
      xform = wall_group.transformation
      found = 0
      capped = 0
      wall_group.entities.grep(Sketchup::Face).each do |f|
        next unless f.valid?
        f.loops.each do |lp|
          next if lp.outer?
          c = loop_centroid(lp).transform(xform)
          next unless opening_point_in_heal_volume?(c, data, geo)
          found += 1
          capped += 1 if cap_loop_flat!(wall_group, lp)
        end
      end
      puts "[DoorTool] cap_inner_loops: found=#{found} capped=#{capped}"
      capped > 0
    end

    def cap_inner_loops_at_door_position!(wall_group, data, geo = nil)
      if geo
        mid_z = (data[:door_bot_z] + data[:door_top_z]) / 2.0
        lp = find_inner_loop_near_position(wall_group, geo, data[:t], mid_z, data[:half_w])
        cap_loop_flat!(wall_group, lp) if lp
      end
      close_all_sheet_inner_loops!(wall_group, data, geo)
    end

    def close_large_sheet_holes!(wall_group, data, geo = nil)
      local_xform = wall_group.transformation.inverse
      local_outward = data[:outward].transform(local_xform)
      center_local = opening_center_local(data, local_xform)
      ok = false

      sheets = parallel_wall_faces(wall_group, data)
      puts "[DoorTool] close_large_sheet_holes: sheets=#{sheets.compact.length}"
      sheets.each_with_index do |sheet, idx|
        next unless sheet&.valid?

        inner_loops = sheet.loops.reject(&:outer?)
        inner_loops.each do |lp|
          ok = true if cap_loop_flat!(wall_group, lp)
        end

        covered = point_covered_on_wall_sheet?(wall_group, center_local, sheet, local_outward)
        puts "[DoorTool] close_large_sheet_holes: sheet#{idx} inner_loops=#{inner_loops.length} center_covered=#{covered}"
        unless covered
          closed = close_sheet_hole_with_lines!(wall_group, data, geo, sheet, local_xform, local_outward)
          puts "[DoorTool] close_large_sheet_holes: sheet#{idx} close_lines=#{closed}"
          ok = true if closed
        end
      end
      ok
    end

    def large_parallel_sheets_at_opening(wall_group, data, geo = nil)
      local_xform = wall_group.transformation.inverse
      local_outward = data[:outward].transform(local_xform)
      mid_z = (data[:door_bot_z] + data[:door_top_z]) / 2.0
      test_local = Geom::Point3d.new(data[:fx], data[:fy], mid_z).transform(local_xform)
      max_plane_dist = data[:thickness] * 0.55

      wall_group.entities.grep(Sketchup::Face).select do |f|
        next false unless f.valid? && face_matches_outward_local?(f, local_outward)
        next false unless test_local.distance_to_plane(f.plane) < max_plane_dist

        proj = test_local.project_to_plane(f.plane)
        f.classify_point(proj) == Sketchup::Face::PointOutside
      end
    end

    def close_sheet_hole_with_lines!(wall_group, data, geo, sheet, local_xform, local_outward)
      plane = sheet.plane
      # Try EXACT door-data corners first (no vertex snapping). For a fresh
      # delete these are precise; snapping can grab a wrong vertex up to 8" away
      # and place the cap off-position, leaving the real hole open.
      exact = opening_corners_local(data, local_xform, plane)
      snapped = find_snapped_opening_corners_local(wall_group, data, geo, plane)
      orders = [
        ordered_opening_loop(exact, data[:clicked_side]),
        ordered_opening_loop(exact, -data[:clicked_side]),
        ordered_opening_loop(snapped, data[:clicked_side]),
        ordered_opening_loop(snapped, -data[:clicked_side])
      ]

      orders.each_with_index do |ordered, oi|
        begin
          cap = wall_group.entities.add_face(ordered)
          cap ||= wall_group.entities.add_face(ordered.reverse)
          if cap&.valid?
            puts "[DoorTool] close_sheet_hole_with_lines! add_face ok order=#{oi} area=#{cap.area.round(1)}"
            return true
          end
        rescue ArgumentError => e
          puts "[DoorTool] close_sheet_hole_with_lines! add_face skip order=#{oi}: #{e.message}"
        end

        begin
          new_edges = []
          4.times do |i|
            new_edges << wall_group.entities.add_line(ordered[i], ordered[(i + 1) % 4])
          end
          new_edges.compact!
          new_edges.each(&:find_faces)

          cap_face = new_edges.flat_map { |e| e.faces }.uniq.find do |f|
            f.valid? && f.normal.parallel?(local_outward)
          end
          if cap_face
            puts "[DoorTool] close_sheet_hole_with_lines! add_line ok order=#{oi}"
            return true
          end
        rescue ArgumentError => e
          puts "[DoorTool] close_sheet_hole_with_lines! add_line skip order=#{oi}: #{e.message}"
        end
      end
      puts '[DoorTool] close_sheet_hole_with_lines! all orders failed'
      false
    end

    def fill_tunnel_through_opening!(wall_group, data, geo = nil)
      return true unless tunnel_faces_in_volume?(wall_group, data, geo) ||
                         opening_void_through_wall?(wall_group, data, geo)

      depth = effective_wall_depth(wall_group, data)
      local_xform = wall_group.transformation.inverse
      local_outward = data[:outward].transform(local_xform)
      mid_z = (data[:door_bot_z] + data[:door_top_z]) / 2.0
      test_local = Geom::Point3d.new(data[:fx], data[:fy], mid_z).transform(local_xform)

      target = wall_group.entities.grep(Sketchup::Face).find do |f|
        next false unless f.valid? && face_matches_outward_local?(f, local_outward)
        proj = test_local.project_to_plane(f.plane)
        f.classify_point(proj) == Sketchup::Face::PointInside
      end
      target ||= parallel_wall_faces(wall_group, data).first

      return fill_by_snapped_corners!(wall_group, data, geo) unless target

      corners = find_snapped_opening_corners_local(wall_group, data, geo, target.plane)
      ordered = ordered_opening_loop(corners, data[:clicked_side])
      cap = wall_group.entities.add_face(ordered)
      cap ||= wall_group.entities.add_face(ordered.reverse)
      if cap&.valid?
        pushfill_cap!(cap, target.normal, depth)
        return true
      end

      fill_by_draw_and_pull!(wall_group, data) || fill_by_snapped_corners!(wall_group, data, geo)
    end

    def opening_hole_at_center?(wall_group, data, geo = nil)
      return true if collect_inner_loops_near(wall_group, data, geo).any?

      local_xform = wall_group.transformation.inverse
      local_outward = data[:outward].transform(local_xform)
      center_local = opening_center_local(data, local_xform)
      ext, int = parallel_wall_faces(wall_group, data)
      return true unless ext&.valid? && int&.valid?

      !point_covered_on_wall_sheet?(wall_group, center_local, ext, local_outward) ||
        !point_covered_on_wall_sheet?(wall_group, center_local, int, local_outward)
    end

    def point_covered_on_wall_sheet?(wall_group, point_local, sheet_face, local_outward)
      return false unless sheet_face&.valid?

      proj = point_local.project_to_plane(sheet_face.plane)
      cls = sheet_face.classify_point(proj)
      cls == Sketchup::Face::PointInside ||
        cls == Sketchup::Face::PointOnEdge ||
        cls == Sketchup::Face::PointOnVertex
    end

    def opening_void_through_wall?(wall_group, data, geo = nil)
      local_xform = wall_group.transformation.inverse
      local_outward = data[:outward].transform(local_xform)
      mid_z = (data[:door_bot_z] + data[:door_top_z]) / 2.0
      base = Geom::Point3d.new(data[:fx], data[:fy], mid_z).transform(local_xform)
      outward = local_outward.clone
      outward.normalize! if outward.length > 0.001

      [0.15, 0.5, 0.85].any? do |frac|
        pt = base.offset(outward, frac * data[:thickness])
        !point_inside_any_parallel_face?(wall_group, pt, local_outward)
      end
    end

    def point_inside_any_parallel_face?(wall_group, local_pt, local_outward)
      wall_group.entities.grep(Sketchup::Face).any? do |f|
        next false unless f.valid? && face_matches_outward_local?(f, local_outward)
        proj = local_pt.project_to_plane(f.plane)
        f.classify_point(proj) == Sketchup::Face::PointInside
      end
    end

    def count_inner_loops(wall_group)
      n = 0
      wall_group.entities.grep(Sketchup::Face).each do |f|
        next unless f.valid?
        f.loops.each { |lp| n += 1 unless lp.outer? }
      end
      n
    end

    def prepare_opening_for_sheet_cap!(wall_group, data, geo = nil)
      erase_opening_tunnel!(wall_group, data, geo)
      erase_parallel_batten_faces_in_volume!(wall_group, data, geo)
      erase_cap_faces_in_opening_hole!(wall_group, data, geo)
    end

    # Erase pushpull caps sitting in the hole (face contains opening center).
    def erase_cap_faces_in_opening_hole!(wall_group, data, geo = nil)
      local_xform = wall_group.transformation.inverse
      local_outward = data[:outward].transform(local_xform)
      center_local = opening_center_local(data, local_xform)
      min_area = data[:half_w] * (data[:door_top_z] - data[:door_bot_z]) * 0.08

      wall_group.entities.grep(Sketchup::Face).each do |f|
        next unless f.valid? && face_matches_outward_local?(f, local_outward)
        next unless f.area >= min_area

        proj = center_local.project_to_plane(f.plane)
        next unless f.classify_point(proj) == Sketchup::Face::PointInside

        f.erase!
      end
    end

    def close_all_sheet_inner_loops!(wall_group, data, geo = nil)
      xform = wall_group.transformation
      capped = false

      wall_group.entities.grep(Sketchup::Face).each do |f|
        next unless f.valid?

        f.loops.each do |lp|
          next if lp.outer?
          c = loop_centroid(lp).transform(xform)
          next unless opening_point_in_heal_volume?(c, data, geo)

          if cap_loop_flat!(wall_group, lp)
            capped = true
          else
            puts "[DoorTool] cap_loop_flat failed (#{lp.vertices.length} verts)"
          end
        end
      end
      capped
    end

    def cap_loop_flat!(wall_group, lp)
      edges = order_edges_chain(lp.edges)
      if edges.length >= 3
        cap = wall_group.entities.add_face(edges)
        return true if cap&.valid?
      end

      verts = lp.vertices
      attempts = [
        verts,
        verts.reverse,
        verts.rotate(1),
        verts.rotate(2),
        verts.rotate(3),
        verts.map(&:position),
        verts.map(&:position).reverse
      ]
      attempts.each do |pts|
        cap = wall_group.entities.add_face(pts)
        cap ||= wall_group.entities.add_face(pts.reverse)
        return true if cap&.valid?
      end
      false
    rescue => e
      puts "[DoorTool] cap_loop_flat error: #{e.message}"
      false
    end

    def order_edges_chain(edges)
      return edges if edges.length < 2

      chain = [edges.first]
      pool = edges[1..-1].dup
      while pool.any?
        last = chain.last
        idx = pool.find_index { |e| edges_share_vertex?(last, e) }
        break unless idx
        chain << pool.delete_at(idx)
      end
      chain
    end

    def edges_share_vertex?(e1, e2)
      e1.start == e2.start || e1.start == e2.end || e1.end == e2.start || e1.end == e2.end
    end

    def cap_hole_from_sheet_boundary_edges!(wall_group, data, geo = nil)
      local_outward = data[:outward].transform(wall_group.transformation.inverse)
      xform = wall_group.transformation
      capped = 0

      parallel_wall_faces(wall_group, data).each do |sheet|
        next unless sheet&.valid?

        hole_edges = sheet.edges.select do |e|
          next false unless e.valid?
          next false unless e.faces.length == 1
          next unless edge_in_opening_frame?(e, xform, data, geo)

          mid = edge_midpoint_world(e, xform)
          opening_point_in_heal_volume?(mid, data, geo)
        end
        next if hole_edges.length < 3

        cap = wall_group.entities.add_face(hole_edges)
        if cap&.valid?
          capped += 1
          next
        end

        corners = find_snapped_opening_corners_local(wall_group, data, geo, sheet.plane)
        orders = [
          ordered_opening_loop(corners, data[:clicked_side]),
          ordered_opening_loop(corners, -data[:clicked_side])
        ]
        orders.each do |ordered|
          cap = wall_group.entities.add_face(ordered)
          cap ||= wall_group.entities.add_face(ordered.reverse)
          capped += 1 if cap&.valid?
        end
      end
      puts "[DoorTool] cap_boundary_edges: capped=#{capped}"
      capped > 0
    end

    def find_snapped_opening_corners_local(wall_group, data, geo, plane)
      local_xform = wall_group.transformation.inverse
      corners_world_from_data(data, geo).map do |wpt|
        local = wpt.transform(local_xform).project_to_plane(plane)
        snapped = snap_local_vertex_near(wall_group, local, 8.0)
        # Re-project after snapping: the nearest vertex may sit on another
        # sheet/plane, which would make the 4 corners non-planar.
        snapped.project_to_plane(plane)
      end
    end

    def soften_opening_sheet_edges!(wall_group, data, geo = nil)
      local_outward = data[:outward].transform(wall_group.transformation.inverse)
      xform = wall_group.transformation
      wall_group.entities.grep(Sketchup::Edge).each do |e|
        next unless e.valid?
        mid = edge_midpoint_world(e, xform)
        next unless opening_point_in_heal_volume?(mid, data, geo)
        on_sheet = e.faces.any? { |f| f.valid? && face_matches_outward_local?(f, local_outward) }
        # Also hide the seam left where the fill patch meets the original sheet:
        # two coplanar faces sharing an edge that heal couldn't merge away.
        seam = e.faces.length == 2 && faces_coplanar?(e.faces[0], e.faces[1])
        next unless on_sheet || seam
        e.soft = true
        e.smooth = true
      end
    end

    def run_pushpull_fill_strategies!(wall_group, data, geo = nil)
      return true if fill_by_snapped_corners!(wall_group, data, geo)
      return true if fill_by_draw_and_pull!(wall_group, data)
      return true if fill_both_parallel_sheets!(wall_group, data, geo)
      return true if fill_by_corner_cap!(wall_group, data)
      false
    end

    # Merge coplanar faces and remove stray edges left after patching.
    def heal_opening_after_fill!(wall_group, data, geo = nil)
      8.times do
        erased = erase_coplanar_edges_in_volume!(wall_group, data, geo)
        erased += erase_dangling_edges_in_volume!(wall_group, data, geo)
        break if erased == 0
      end
    end

    def erase_coplanar_edges_in_volume!(wall_group, data, geo = nil)
      xform = wall_group.transformation
      erased = 0
      wall_group.entities.grep(Sketchup::Edge).each do |e|
        next unless e.valid?
        next unless e.faces.length == 2

        f1, f2 = e.faces
        next unless faces_coplanar?(f1, f2)

        mid = edge_midpoint_world(e, xform)
        next unless opening_point_in_heal_volume?(mid, data, geo)

        e.erase!
        erased += 1
      end
      erased
    end

    def faces_coplanar?(f1, f2)
      return false unless f1.valid? && f2.valid?
      return false unless f1.normal.parallel?(f2.normal)

      # Tight tolerance + check ALL vertices: merging faces that are only
      # *nearly* coplanar makes the merged face non-planar, which SketchUp
      # triangulates into a visible diagonal/shading warp across the wall.
      # An exact cap (project_to_plane) deviates ~0 and still merges.
      plane2 = f2.plane
      f1.vertices.all? { |vx| vx.position.distance_to_plane(plane2) < 0.02 }
    end

    def erase_dangling_edges_in_volume!(wall_group, data, geo = nil)
      xform = wall_group.transformation
      erased = 0
      wall_group.entities.grep(Sketchup::Edge).each do |e|
        next unless e.valid?
        next unless e.faces.empty?

        mid = edge_midpoint_world(e, xform)
        next unless opening_point_in_heal_volume?(mid, data, geo)

        e.erase!
        erased += 1
      end
      erased
    end

    def opening_solid_enough?(wall_group, data, geo = nil)
      !tunnel_faces_in_volume?(wall_group, data, geo) &&
        collect_inner_loops_near(wall_group, data, geo).empty?
    end

    def edge_in_opening_frame?(edge, xform, data, geo)
      s = edge.start.position.transform(xform)
      t = edge.end.position.transform(xform)
      opening_point_in_heal_volume?(s, data, geo) && opening_point_in_heal_volume?(t, data, geo)
    end

    def edge_midpoint_world(edge, xform)
      s = edge.start.position.transform(xform)
      t = edge.end.position.transform(xform)
      Geom::Point3d.new((s.x + t.x) / 2.0, (s.y + t.y) / 2.0, (s.z + t.z) / 2.0)
    end

    # Find inner loop nearest stored opening coordinates (public for DoorManager).
    def find_opening_inner_loop(wall_group, data)
      find_best_inner_loop(wall_group, data)
    end

    # Broad search along wall centerline when stored coordinates are off.
    def find_inner_loop_near_position(wall_group, geo, t, mid_z, half_w = 24.0)
      local_xform = wall_group.transformation.inverse
      cx = geo[:cline_start].x + geo[:unit].x * t + geo[:n].x * geo[:n_side]
      cy = geo[:cline_start].y + geo[:unit].y * t + geo[:n].y * geo[:n_side]
      center_local = Geom::Point3d.new(cx, cy, mid_z).transform(local_xform)
      max_dist = half_w + 6.0

      best_lp = nil
      best_dist = Float::INFINITY
      wall_group.entities.grep(Sketchup::Face).each do |f|
        next unless f.valid?
        f.loops.each do |lp|
          next if lp.outer?
          dist = loop_centroid(lp).distance(center_local)
          next unless dist < max_dist && dist < best_dist
          best_dist = dist
          best_lp = lp
        end
      end
      best_lp
    end

    private

    def find_wall_under_cursor(view, x, y)
      ph = view.pick_helper
      ph.do_pick(x, y)
      return [nil, nil, nil] if ph.count == 0

      ph.count.times do |i|
        path = ph.path_at(i)
        next unless path
        wall = path.find { |e|
          e.is_a?(Sketchup::Group) && e.valid? &&
            e.get_attribute('InteriorPro', 'type') == 'wall'
        }
        next unless wall

        leaf = ph.leaf_at(i)
        face = leaf.is_a?(Sketchup::Face) ? leaf : nil
        point = world_pick_point(view, x, y, ph, i)
        return [wall, point, face] if point
      end
      [nil, nil, nil]
    end

    # PickHelper has no picked_point method. Recover the 3D world-space pick
    # by intersecting the view's pickray with the leaf face's plane (transformed
    # from the group's local space to world space).
    def world_pick_point(view, x, y, ph, index)
      leaf = ph.leaf_at(index)
      if leaf.is_a?(Sketchup::Face)
        transform = ph.transformation_at(index)
        ray = view.pickray(x, y)
        plane_pt = leaf.vertices.first.position.transform(transform)
        plane_normal = leaf.normal.transform(transform)
        pt = Geom.intersect_line_plane(ray, [plane_pt, plane_normal])
        return pt if pt
      end
      # Fallback for non-face leaves (edge picks, etc.)
      ip = Sketchup::InputPoint.new
      ip.pick(view, x, y)
      ip.valid? ? ip.position : nil
    end

    def cut_door_opening(wall_group, picked_point, picked_face = nil)
      data = prepare_door_placement(wall_group, picked_point, picked_face)
      return unless data

      unless cut_and_build_door_at(wall_group, data)
        UI.messagebox("Error cutting or building door: see Ruby Console for details.")
        return
      end

      Sketchup.set_status_text(
        "Door opening cut. Click another wall or press Escape to exit.",
        SB_PROMPT
      )
    end

    def prepare_door_placement(wall_group, picked_point, picked_face)
      sx = wall_group.get_attribute('InteriorPro', 'start_x')
      sy = wall_group.get_attribute('InteriorPro', 'start_y')
      ex = wall_group.get_attribute('InteriorPro', 'end_x')
      ey = wall_group.get_attribute('InteriorPro', 'end_y')
      thickness = wall_group.get_attribute('InteriorPro', 'thickness').to_f
      wall_height = wall_group.get_attribute('InteriorPro', 'height').to_f
      anchor = wall_group.get_attribute('InteriorPro', 'anchor') || 'bottom-center'

      unless sx && sy && ex && ey && thickness > 0 && wall_height > 0
        UI.messagebox("Wall is missing required attributes.")
        return nil
      end

      drawn_start = Geom::Point3d.new(sx, sy, 0)
      drawn_end = Geom::Point3d.new(ex, ey, 0)
      wall_vec = drawn_end - drawn_start
      wall_length = wall_vec.length
      if wall_length < 0.1
        UI.messagebox("Wall is too short.")
        return nil
      end

      unit = wall_vec.clone
      unit.normalize!
      n = Geom::Vector3d.new(-unit.y, unit.x, 0)

      v_anchor, h_anchor = parse_anchor(anchor)

      # Adjust drawn line to true centerline based on horizontal anchor (same
      # convention as build_wall_group / WindowTool).
      center_offset = case h_anchor
                      when 'left'  then thickness / 2.0
                      when 'right' then -thickness / 2.0
                      else 0.0
                      end
      cline_start = Geom::Point3d.new(
        drawn_start.x + n.x * center_offset,
        drawn_start.y + n.y * center_offset,
        0
      )

      # Floor of wall (bottom z) depends on vertical anchor.
      floor_z = case v_anchor
                when 'top'    then -wall_height
                when 'center' then -wall_height / 2.0
                else 0.0
                end
      ceiling_z = floor_z + wall_height

      # Project picked point (XY) onto centerline.
      click_xy = Geom::Point3d.new(picked_point.x, picked_point.y, 0)
      to_click = click_xy - cline_start
      t = to_click.dot(unit)
      n_offset = to_click.dot(n)
      clicked_side = n_offset >= 0 ? 1 : -1

      # Validate fit along wall length.
      half_w = @width / 2.0
      if t - half_w < 0 || t + half_w > wall_length
        UI.messagebox(
          "Door does not fit in wall.\n\n" \
          "Wall length: #{wall_length.round(2)}\"\n" \
          "Door width: #{@width}\"\n" \
          "Click position: #{t.round(2)}\" from wall start\n" \
          "Need at least #{half_w}\" from each end."
        )
        return nil
      end

      door_bot_z = floor_z + @floor_offset
      door_top_z = door_bot_z + @height
      if door_top_z > ceiling_z + 0.001
        UI.messagebox(
          "Door does not fit in wall height.\n\n" \
          "Floor offset (#{@floor_offset}\") + door height (#{@height}\") " \
          "exceeds wall height (#{wall_height}\")."
        )
        return nil
      end

      n_side = -thickness / 2.0
      cx = cline_start.x + unit.x * t + n.x * n_side
      cy = cline_start.y + unit.y * t + n.y * n_side
      ux = unit.x * half_w
      uy = unit.y * half_w
      fx = picked_point.x
      fy = picked_point.y
      outward = Geom::Vector3d.new(n.x * clicked_side, n.y * clicked_side, 0)

      {
        wall_group: wall_group,
        picked_point: picked_point,
        picked_face: picked_face,
        unit: unit,
        n: n,
        thickness: thickness,
        t: t,
        clicked_side: clicked_side,
        half_w: half_w,
        door_bot_z: door_bot_z,
        door_top_z: door_top_z,
        cx: cx,
        cy: cy,
        ux: ux,
        uy: uy,
        fx: fx,
        fy: fy,
        outward: outward
      }
    end

    def apply_wall_cut(wall_group, data, geo = nil)
      local_xform = wall_group.transformation.inverse
      local_picked = data[:picked_point].transform(local_xform)
      local_outward = data[:outward].transform(local_xform)
      depth = wall_cut_depth(wall_group, data)
      picked_face = data[:picked_face]

      target_face = nil
      if picked_face && picked_face.valid? &&
         picked_face.parent == wall_group.entities.parent &&
         face_matches_outward_local?(picked_face, local_outward)
        target_face = picked_face
      end
      target_face ||= find_cut_target_face(wall_group, data, local_xform, local_outward, local_picked)
      unless target_face
        puts '[DoorTool] apply_wall_cut: no target face'
        return false
      end

      target_plane = target_face.plane
      local_corners = [
        Geom::Point3d.new(data[:fx] - data[:ux], data[:fy] - data[:uy], data[:door_bot_z]),
        Geom::Point3d.new(data[:fx] + data[:ux], data[:fy] + data[:uy], data[:door_bot_z]),
        Geom::Point3d.new(data[:fx] + data[:ux], data[:fy] + data[:uy], data[:door_top_z]),
        Geom::Point3d.new(data[:fx] - data[:ux], data[:fy] - data[:uy], data[:door_top_z])
      ].map { |p| p.transform(local_xform).project_to_plane(target_plane) }
      ordered = data[:clicked_side] >= 0 ?
        [local_corners[0], local_corners[3], local_corners[2], local_corners[1]] :
        [local_corners[0], local_corners[1], local_corners[2], local_corners[3]]

      unless cut_face_from_ordered_loop!(wall_group, ordered, local_outward, depth)
        puts '[DoorTool] apply_wall_cut: could not create opening face'
        return false
      end

      void = opening_void_through_wall?(wall_group, data, geo)
      hole = opening_hole_at_center?(wall_group, data, geo)
      puts "[DoorTool] apply_wall_cut: ok depth=#{depth.round(2)} void=#{void} hole=#{hole}"
      true
    rescue => e
      puts "[DoorTool] apply_wall_cut error: #{e.message}"
      false
    end

    def apply_wall_cut_snapped!(wall_group, data, geo = nil)
      local_xform = wall_group.transformation.inverse
      local_picked = data[:picked_point].transform(local_xform)
      local_outward = data[:outward].transform(local_xform)
      depth = wall_cut_depth(wall_group, data)

      target_face = find_cut_target_face(wall_group, data, local_xform, local_outward, local_picked)
      unless target_face
        puts '[DoorTool] apply_wall_cut_snapped: no target face'
        return false
      end

      corners_local = find_snapped_opening_corners_local(wall_group, data, geo, target_face.plane)
      orders = [
        ordered_opening_loop(corners_local, data[:clicked_side]),
        ordered_opening_loop(corners_local, -data[:clicked_side])
      ]

      orders.each do |ordered|
        if cut_face_from_ordered_loop!(wall_group, ordered, local_outward, depth)
          puts '[DoorTool] apply_wall_cut_snapped: ok'
          return true
        end
      end

      puts '[DoorTool] apply_wall_cut_snapped: failed'
      false
    rescue => e
      puts "[DoorTool] apply_wall_cut_snapped error: #{e.message}"
      false
    end

    def cut_face_from_ordered_loop!(wall_group, ordered, local_outward, depth)
      min_area = 4.0
      loop_center = Geom::Point3d.new(
        (ordered[0].x + ordered[2].x) / 2.0,
        (ordered[0].y + ordered[2].y) / 2.0,
        (ordered[0].z + ordered[2].z) / 2.0
      )

      new_edges = []
      4.times do |i|
        new_edges << wall_group.entities.add_line(ordered[i], ordered[(i + 1) % 4])
      end
      new_edges.compact!
      new_edges.each(&:find_faces)

      new_face = wall_group.entities.grep(Sketchup::Face).find do |f|
        f.valid? &&
          f.normal.parallel?(local_outward) &&
          f.classify_point(loop_center) == Sketchup::Face::PointInside &&
          f.area >= min_area
      end
      unless new_face
        puts '[DoorTool] cut_face: no inner face found'
        return false
      end

      puts "[DoorTool] cut_face: inner face area=#{new_face.area.round(1)} depth=#{depth.round(2)}"
      pushpull_through_wall!(new_face, local_outward, depth)
      true
    end

    # Robust opening cut that does NOT rely on pushpull. Rebuilds a clean
    # rectangular tunnel between the two main wall sheets. Used for edit/resize
    # where the wall is no longer pristine (old patched opening) and raw pushpull
    # fails to punch a real hole ("door stuck on surface"). Deterministic — no
    # pushpull direction quirks.
    def cut_opening_clean!(wall_group, data, geo = nil)
      local_xform = wall_group.transformation.inverse

      # De-fragment the opening region so each sheet is a single clean face
      # (removes leftover rim edges from a previous patched opening).
      heal_opening_after_fill!(wall_group, data, geo)

      ext, int = parallel_wall_faces(wall_group, data)
      unless ext&.valid? && int&.valid?
        puts "[DoorTool] clean cut: missing wall face ext=#{!ext.nil?} int=#{!int.nil?}"
        return false
      end

      ext_normal = ext.normal
      int_normal = int.normal
      ext_corners = opening_corners_local(data, local_xform, ext.plane)
      int_corners = opening_corners_local(data, local_xform, int.plane)

      ext_face = imprint_opening_face!(wall_group, ext_corners, ext_normal)
      int_face = imprint_opening_face!(wall_group, int_corners, int_normal)
      unless ext_face && int_face
        puts "[DoorTool] clean cut: imprint failed ext=#{!ext_face.nil?} int=#{!int_face.nil?}"
        return false
      end

      # Open the hole on both sheets first, then connect with tunnel walls.
      ext_face.erase! if ext_face.valid?
      int_face.erase! if int_face.valid?

      sides = 0
      4.times do |i|
        a = ext_corners[i]
        b = ext_corners[(i + 1) % 4]
        c = int_corners[(i + 1) % 4]
        d = int_corners[i]
        begin
          f = wall_group.entities.add_face(a, b, c, d)
          sides += 1 if f&.valid?
        rescue ArgumentError => e
          puts "[DoorTool] clean cut: side#{i} skip #{e.message}"
        end
      end

      void = opening_void_through_wall?(wall_group, data, geo)
      ext2, int2 = parallel_wall_faces(wall_group, data)
      puts "[DoorTool] clean cut: sides=#{sides} void=#{void} ext_flat=#{face_planar_dev(ext2)} int_flat=#{face_planar_dev(int2)}"
      void
    rescue => e
      puts "[DoorTool] cut_opening_clean! error: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      false
    end

    # Max distance of a face's vertices from its own plane (0 = perfectly flat).
    def face_planar_dev(face)
      return 'nil' unless face&.valid?
      pl = face.plane
      face.vertices.map { |v| v.position.distance_to_plane(pl) }.max.round(4)
    end

    # Draw the opening rectangle on a wall sheet plane and return the inner face.
    def imprint_opening_face!(wall_group, corners, face_normal)
      edges = []
      4.times do |i|
        edges << wall_group.entities.add_line(corners[i], corners[(i + 1) % 4])
      end
      edges.compact!
      edges.each(&:find_faces)

      center = Geom::Point3d.new(
        (corners[0].x + corners[2].x) / 2.0,
        (corners[0].y + corners[2].y) / 2.0,
        (corners[0].z + corners[2].z) / 2.0
      )
      wall_group.entities.grep(Sketchup::Face).find do |f|
        f.valid? && f.normal.parallel?(face_normal) &&
          f.classify_point(center) == Sketchup::Face::PointInside
      end
    rescue ArgumentError => e
      puts "[DoorTool] imprint_opening_face! skip: #{e.message}"
      nil
    end

    def prepare_wall_for_cut!(wall_group, data, geo = nil)
      # Do NOT erase_cap_faces here — on a solid patched wall that would
      # delete the main exterior sheet (center is PointInside on a filled face).
      erase_opening_tunnel!(wall_group, data, geo)
      heal_opening_after_fill!(wall_group, data, geo)
      erase_dangling_edges_in_volume!(wall_group, data, geo)
    end

    def erase_opening_tunnel!(wall_group, data, geo = nil)
      local_xform = wall_group.transformation.inverse
      local_outward = data[:outward].transform(local_xform)
      xform = wall_group.transformation
      to_erase = wall_group.entities.grep(Sketchup::Face).select do |f|
        next false unless f.valid?
        next false if face_matches_outward_local?(f, local_outward)
        ctr = face_centroid_world(f, xform)
        opening_point_in_volume?(ctr, data, geo)
      end
      to_erase.each { |f| f.erase! if f.valid? }
    end

    def opening_volume_faces?(wall_group, data, geo = nil)
      tunnel_faces_in_volume?(wall_group, data, geo)
    end

    def tunnel_faces_in_volume?(wall_group, data, geo = nil)
      local_xform = wall_group.transformation.inverse
      local_outward = data[:outward].transform(local_xform)
      xform = wall_group.transformation
      wall_group.entities.grep(Sketchup::Face).any? do |f|
        next false unless f.valid?
        next false if face_matches_outward_local?(f, local_outward)
        opening_point_in_volume?(face_centroid_world(f, xform), data, geo)
      end
    end

    def opening_point_in_volume?(pt, data, geo = nil)
      opening_point_in_axis_box?(pt, data, geo, along_pad: 2.0, z_pad: 2.0, perp_pad: 3.0)
    end

    def opening_point_in_heal_volume?(pt, data, geo = nil)
      opening_point_in_axis_box?(pt, data, geo, along_pad: 4.0, z_pad: 4.0, perp_pad: 5.0)
    end

    def opening_point_in_axis_box?(pt, data, geo, along_pad:, z_pad:, perp_pad:)
      unit = data[:unit]
      n = data[:n]
      cx, cy = opening_axis_center_xy(data, geo)
      along = (pt.x - cx) * unit.x + (pt.y - cy) * unit.y
      perp = (pt.x - cx) * n.x + (pt.y - cy) * n.y
      half_h = (data[:door_top_z] - data[:door_bot_z]) / 2.0
      mid_z = (data[:door_bot_z] + data[:door_top_z]) / 2.0
      along.abs <= data[:half_w] + along_pad &&
        (pt.z - mid_z).abs <= half_h + z_pad &&
        perp.abs <= data[:thickness] + perp_pad
    end

    def opening_axis_center_xy(data, geo)
      if geo
        t = data[:t]
        unit = geo[:unit]
        n = geo[:n]
        cx = geo[:cline_start].x + unit.x * t + n.x * geo[:n_side]
        cy = geo[:cline_start].y + unit.y * t + n.y * geo[:n_side]
        [cx, cy]
      else
        [data[:fx], data[:fy]]
      end
    end

    def all_inner_loops(wall_group)
      loops = []
      wall_group.entities.grep(Sketchup::Face).each do |f|
        next unless f.valid?
        f.loops.each do |lp|
          next if lp.outer?
          loops << lp
        end
      end
      loops
    end

    def collect_inner_loops_near(wall_group, data, geo = nil)
      xform = wall_group.transformation
      unit = data[:unit]
      n = data[:n]
      cx = data[:fx]
      cy = data[:fy]
      half_w = data[:half_w]
      half_h = (data[:door_top_z] - data[:door_bot_z]) / 2.0
      mid_z = (data[:door_bot_z] + data[:door_top_z]) / 2.0
      max_along = half_w + 8.0
      max_z = half_h + 8.0
      max_perp = data[:thickness] + 6.0

      all_inner_loops(wall_group).select do |lp|
        c = loop_centroid(lp).transform(xform)
        along = (c.x - cx) * unit.x + (c.y - cy) * unit.y
        perp = (c.x - cx) * n.x + (c.y - cy) * n.y
        along.abs <= max_along &&
          (c.z - mid_z).abs <= max_z &&
          perp.abs <= max_perp
      end
    end

    def erase_parallel_batten_faces_in_volume!(wall_group, data, geo = nil)
      local_xform = wall_group.transformation.inverse
      local_outward = data[:outward].transform(local_xform)
      xform = wall_group.transformation
      max_area = data[:half_w] * (data[:door_top_z] - data[:door_bot_z]) * 0.6
      to_erase = wall_group.entities.grep(Sketchup::Face).select do |f|
        next false unless f.valid?
        next false unless face_matches_outward_local?(f, local_outward)
        next false unless opening_point_in_volume?(face_centroid_world(f, xform), data, geo)
        f.area < max_area
      end
      to_erase.each { |f| f.erase! if f.valid? }
    end

    def effective_wall_depth(wall_group, data)
      t = data[:thickness].to_f
      return t if t <= 0

      ext, int = parallel_wall_faces(wall_group, data)
      unless ext&.valid? && int&.valid?
        return t
      end

      local_xform = wall_group.transformation.inverse
      center_local = Geom::Point3d.new(
        data[:fx], data[:fy], (data[:door_bot_z] + data[:door_top_z]) / 2.0
      ).transform(local_xform)
      span = (center_local.distance_to_plane(ext.plane) - center_local.distance_to_plane(int.plane)).abs
      span > 0.1 && span <= t * 1.25 ? span : t
    end

    # Wall cut pushpull depth — match WindowTool (wall thickness attribute).
    def wall_cut_depth(wall_group, data)
      data[:thickness].to_f
    end

    def parallel_wall_faces(wall_group, data)
      local_xform = wall_group.transformation.inverse
      local_outward = data[:outward].transform(local_xform)
      parallel = wall_group.entities.grep(Sketchup::Face).select do |f|
        f.valid? && face_matches_outward_local?(f, local_outward)
      end
      return [nil, nil] if parallel.empty?

      # Pick the largest faces on each side — not battens/small fragments
      # (max_by dot used to select the outermost batten face on Board-and-Batten walls).
      exterior_candidates = parallel.select { |f| f.normal.dot(local_outward) > 0.25 }
      interior_candidates = parallel.select { |f| f.normal.dot(local_outward) < -0.25 }

      exterior = exterior_candidates.max_by(&:area)
      interior = interior_candidates.max_by(&:area)
      [exterior, interior].compact.uniq
    end

    def fill_both_parallel_sheets!(wall_group, data, geo = nil)
      local_xform = wall_group.transformation.inverse
      depth = effective_wall_depth(wall_group, data)
      ok = false
      parallel_wall_faces(wall_group, data).each do |target_face|
        next unless target_face
        if cap_on_face_sheet!(wall_group, data, geo, target_face, local_xform, depth)
          ok = true
        end
      end
      ok
    end

    def cap_on_face_sheet!(wall_group, data, geo, target_face, local_xform, depth)
      plane = target_face.plane
      corners_local = corners_world_from_data(data, geo).map do |wpt|
        local = wpt.transform(local_xform).project_to_plane(plane)
        snapped = snap_local_vertex_near(wall_group, local, 6.0)
        snapped.project_to_plane(plane)
      end
      orders = [
        ordered_opening_loop(corners_local, data[:clicked_side]),
        ordered_opening_loop(corners_local, -data[:clicked_side])
      ]
      orders.each do |ordered|
        cap = wall_group.entities.add_face(ordered)
        cap ||= wall_group.entities.add_face(ordered.reverse)
        next unless cap&.valid?
        pushfill_cap!(cap, target_face.normal, depth)
        return true
      end
      false
    rescue => e
      puts "[DoorTool] cap_on_face_sheet: #{e.message}"
      false
    end

    def snap_local_vertex_near(wall_group, local_pt, tol)
      best = local_pt
      best_d = tol
      wall_group.entities.grep(Sketchup::Edge).each do |e|
        next unless e.valid?
        e.vertices.each do |v|
          d = v.position.distance(local_pt)
          if d < best_d
            best_d = d
            best = v.position
          end
        end
      end
      best
    end

    def corners_world_from_data(data, geo = nil)
      if data[:mesh_pts] && data[:mesh_pts].length >= 4
        mesh_corners_world(data, geo)
      else
        raw_corners_world(data)
      end
    end

    def raw_corners_world(data)
      [
        Geom::Point3d.new(data[:fx] - data[:ux], data[:fy] - data[:uy], data[:door_bot_z]),
        Geom::Point3d.new(data[:fx] + data[:ux], data[:fy] + data[:uy], data[:door_bot_z]),
        Geom::Point3d.new(data[:fx] + data[:ux], data[:fy] + data[:uy], data[:door_top_z]),
        Geom::Point3d.new(data[:fx] - data[:ux], data[:fy] - data[:uy], data[:door_top_z])
      ]
    end

    def mesh_corners_world(data, geo)
      near = data[:mesh_pts]
      unit = data[:unit]
      n = data[:n]
      cx, cy = opening_axis_center_xy(data, geo)
      along = near.map { |p| (p.x - cx) * unit.x + (p.y - cy) * unit.y }
      perp = near.map { |p| (p.x - cx) * n.x + (p.y - cy) * n.y }
      z = near.map(&:z)
      a0, a1 = along.minmax
      z0, z1 = z.minmax
      p_mid = perp.sum / perp.length.to_f
      [[a0, z0], [a1, z0], [a1, z1], [a0, z1]].map do |a, zz|
        Geom::Point3d.new(cx + unit.x * a + n.x * p_mid, cy + unit.y * a + n.y * p_mid, zz)
      end
    end

    def snap_world_to_local_vertex(wall_group, world_pt, local_xform, tol = 4.0)
      snap_local_vertex_near(wall_group, world_pt.transform(local_xform), tol)
    end

    def ordered_opening_loop(corners_local, clicked_side)
      if clicked_side >= 0
        [corners_local[0], corners_local[3], corners_local[2], corners_local[1]]
      else
        [corners_local[0], corners_local[1], corners_local[2], corners_local[3]]
      end
    end

    def find_cut_target_face(wall_group, data, local_xform, local_outward, local_picked)
      test_locals = [
        local_picked,
        Geom::Point3d.new(data[:cx], data[:cy], data[:door_bot_z]).transform(local_xform),
        Geom::Point3d.new(data[:fx], data[:fy], data[:door_bot_z]).transform(local_xform)
      ]
      wall_group.entities.grep(Sketchup::Face).each do |f|
        next unless f.valid? && face_matches_outward_local?(f, local_outward)
        test_locals.each do |pt|
          proj = pt.project_to_plane(f.plane)
          cls = f.classify_point(proj)
          if cls == Sketchup::Face::PointInside ||
             cls == Sketchup::Face::PointOnEdge ||
             cls == Sketchup::Face::PointOnVertex
            return f
          end
        end
      end

      parallel = wall_group.entities.grep(Sketchup::Face).select do |f|
        f.valid? && face_matches_outward_local?(f, local_outward)
      end
      return nil if parallel.empty?

      if data[:clicked_side] >= 0
        parallel.max_by { |f| f.normal.dot(local_outward) }
      else
        parallel.min_by { |f| f.normal.dot(local_outward) }
      end
    end

    def fill_by_snapped_corners!(wall_group, data, geo = nil)
      depth = effective_wall_depth(wall_group, data)
      local_xform = wall_group.transformation.inverse
      local_outward = data[:outward].transform(local_xform)
      target = find_cut_target_face(wall_group, data, local_xform, local_outward,
                                    data[:picked_point].transform(local_xform))
      plane = target ? target.plane : nil

      corners_local = corners_world_from_data(data, geo).map do |wpt|
        local = wpt.transform(local_xform)
        local = plane ? local.project_to_plane(plane) : local
        snap_local_vertex_near(wall_group, local, 6.0)
      end
      orders = [
        ordered_opening_loop(corners_local, data[:clicked_side]),
        ordered_opening_loop(corners_local, -data[:clicked_side])
      ]

      orders.each do |ordered|
        cap = wall_group.entities.add_face(ordered)
        cap ||= wall_group.entities.add_face(ordered.reverse)
        next unless cap&.valid?

        normal = target ? target.normal : local_outward
        pushfill_cap!(cap, normal, depth)
        return true
      end

      puts '[DoorTool] fill_by_snapped_corners: add_face failed'
      false
    rescue => e
      puts "[DoorTool] fill_by_snapped_corners: #{e.message}"
      false
    end

    # Same edge loop + pushpull strategy as apply_wall_cut (closes openings without inner loops).
    def fill_by_draw_and_pull!(wall_group, data, geo = nil)
      local_xform = wall_group.transformation.inverse
      local_picked = data[:picked_point].transform(local_xform)
      local_outward = data[:outward].transform(local_xform)
      depth = effective_wall_depth(wall_group, data)

      target_face = find_cut_target_face(wall_group, data, local_xform, local_outward, local_picked)
      unless target_face
        puts '[DoorTool] fill_by_draw_and_pull: no target face'
        return false
      end

      target_plane = target_face.plane
      corners_local = corners_world_from_data(data, geo).map do |wpt|
        local = wpt.transform(local_xform).project_to_plane(target_plane)
        snapped = snap_local_vertex_near(wall_group, local, 6.0)
        snapped.project_to_plane(target_plane)
      end
      orders = [
        ordered_opening_loop(corners_local, data[:clicked_side]),
        ordered_opening_loop(corners_local, -data[:clicked_side])
      ]

      orders.each do |ordered|
        cap = wall_group.entities.add_face(ordered)
        cap ||= wall_group.entities.add_face(ordered.reverse)
        if cap&.valid?
          pushfill_cap!(cap, target_face.normal, depth)
          return true
        end

        new_edges = []
        4.times do |i|
          new_edges << wall_group.entities.add_line(ordered[i], ordered[(i + 1) % 4])
        end
        new_edges.each(&:find_faces)

        cap_face = new_edges.flat_map { |e| e.faces }.uniq.find do |f|
          f.valid? && f.normal.parallel?(local_outward)
        end
        cap_face ||= wall_group.entities.grep(Sketchup::Face).find do |f|
          f.valid? &&
            f.normal.parallel?(local_outward) &&
            f.classify_point(ordered[0]) != Sketchup::Face::PointOutside
        end
        if cap_face
          pushfill_cap!(cap_face, local_outward, depth)
          return true
        end
      end

      puts '[DoorTool] fill_by_draw_and_pull: no cap face after find_faces'
      false
    rescue => e
      puts "[DoorTool] fill_by_draw_and_pull: #{e.message}"
      false
    end

    def pushfill_cap!(cap, outward_normal, thickness)
      cap.reverse! if cap.normal.dot(outward_normal) < 0
      sign = cap.normal.dot(outward_normal) > 0 ? -1 : 1
      cap.pushpull(sign * thickness)
      true
    end

    def fill_by_corner_cap!(wall_group, data)
      local_xform = wall_group.transformation.inverse
      depth = effective_wall_depth(wall_group, data)
      local_outward = data[:outward].transform(local_xform)
      corners_raw = opening_corners_local_raw(data, local_xform)

      face_sets = [
        wall_group.entities.grep(Sketchup::Face).select { |f| f.valid? && face_matches_outward_local?(f, local_outward) },
        wall_group.entities.grep(Sketchup::Face).select { |f| f.valid? && f.normal.z.abs < 0.01 }
      ]

      face_sets.each do |faces|
        next if faces.empty?
        faces.each do |target_face|
          plane = target_face.plane
          corners = corners_raw.map { |p| p.project_to_plane(plane) }
          orders = if data[:clicked_side] >= 0
                     [[corners[0], corners[3], corners[2], corners[1]],
                      [corners[0], corners[1], corners[2], corners[3]]]
                   else
                     [[corners[0], corners[1], corners[2], corners[3]],
                      [corners[0], corners[3], corners[2], corners[1]]]
                   end
          orders << corners_raw

          orders.each do |ordered|
            cap = wall_group.entities.add_face(ordered)
            cap ||= wall_group.entities.add_face(ordered.reverse)
            next unless cap&.valid?

            normal = target_face.normal
            cap.reverse! if cap.normal.dot(normal) < 0
            sign = cap.normal.dot(normal) > 0 ? -1 : 1
            cap.pushpull(sign * depth)
            return true
          end
        end
      end

      puts '[DoorTool] fill_by_corner_cap: add_face failed'
      false
    rescue => e
      puts "[DoorTool] fill_by_corner_cap: #{e.message}"
      false
    end

    def opening_corners_local_raw(data, local_xform)
      [
        Geom::Point3d.new(data[:fx] - data[:ux], data[:fy] - data[:uy], data[:door_bot_z]),
        Geom::Point3d.new(data[:fx] + data[:ux], data[:fy] + data[:uy], data[:door_bot_z]),
        Geom::Point3d.new(data[:fx] + data[:ux], data[:fy] + data[:uy], data[:door_top_z]),
        Geom::Point3d.new(data[:fx] - data[:ux], data[:fy] - data[:uy], data[:door_top_z])
      ].map { |p| p.transform(local_xform) }
    end

    def cap_inner_loop!(wall_group, lp, thickness)
      parent = find_parent_face(wall_group, lp)
      unless parent
        puts '[DoorTool] cap_inner_loop: no parent face'
        return false
      end

      pts = lp.vertices.map(&:position)
      cap = wall_group.entities.add_face(pts)
      cap ||= wall_group.entities.add_face(pts.reverse)
      unless cap&.valid?
        puts '[DoorTool] cap_inner_loop: add_face failed'
        return false
      end

      normal = parent.normal
      cap.reverse! if cap.normal.dot(normal) < 0
      sign = cap.normal.dot(normal) > 0 ? -1 : 1
      cap.pushpull(sign * thickness)
      true
    rescue => e
      puts "[DoorTool] cap_inner_loop: #{e.message}"
      false
    end

    def face_matches_outward_local?(face, local_outward)
      n = face.normal
      n.parallel?(local_outward) || n.parallel?(local_outward.reverse)
    end

    def find_best_inner_loop(wall_group, data)
      local_xform = wall_group.transformation.inverse
      center_local = opening_center_local(data, local_xform)
      half_h = (data[:door_top_z] - data[:door_bot_z]) / 2.0
      max_dist = [data[:half_w], half_h].max + 3.0

      best_lp = nil
      best_dist = Float::INFINITY

      wall_group.entities.grep(Sketchup::Face).each do |f|
        next unless f.valid?
        f.loops.each do |lp|
          next if lp.outer?
          dist = loop_centroid(lp).distance(center_local)
          next unless dist < max_dist && dist < best_dist
          best_dist = dist
          best_lp = lp
        end
      end

      best_lp
    end

    def opening_center_local(data, local_xform)
      Geom::Point3d.new(
        data[:fx], data[:fy], (data[:door_bot_z] + data[:door_top_z]) / 2.0
      ).transform(local_xform)
    end

    def face_matches_outward?(face, local_outward)
      n = face.normal
      n.parallel?(local_outward) || n.parallel?(local_outward.reverse)
    end

    def cap_best_inner_loop!(wall_group, data)
      lp = find_best_inner_loop(wall_group, data)
      return false unless lp

      local_xform = wall_group.transformation.inverse
      thickness = data[:thickness]
      parent_face = find_parent_face(wall_group, lp)
      fill_normal = parent_face ? parent_face.normal : data[:outward].transform(local_xform)

      pts = lp.vertices.map(&:position)
      cap = wall_group.entities.add_face(pts)
      cap ||= wall_group.entities.add_face(pts.reverse)
      unless cap && cap.valid?
        puts '[DoorTool] cap_best_inner_loop: add_face failed'
        return false
      end

      pushpull_through_wall!(cap, fill_normal, thickness)
      true
    end

    def find_parent_face(wall_group, loop)
      wall_group.entities.grep(Sketchup::Face).find { |f| f.valid? && f.loops.include?(loop) }
    end

    def reconstruct_solid_patch!(wall_group, data)
      local_xform = wall_group.transformation.inverse
      local_outward = data[:outward].transform(local_xform)
      thickness = data[:thickness]

      lp = find_best_inner_loop(wall_group, data)
      if lp
        parent_face = find_parent_face(wall_group, lp)
        fill_normal = parent_face ? parent_face.normal : local_outward
        pts = lp.vertices.map(&:position)
        cap = wall_group.entities.add_face(pts)
        cap ||= wall_group.entities.add_face(pts.reverse)
        if cap && cap.valid?
          pushpull_through_wall!(cap, fill_normal, thickness)
          return true
        end
      end

      target_face = find_wall_face_near_opening(wall_group, data, local_xform, local_outward)
      unless target_face
        puts '[DoorTool] reconstruct_solid_patch: no target face'
        return false
      end

      target_plane = target_face.plane
      local_corners = opening_corners_local(data, local_xform, target_plane)
      ordered = data[:clicked_side] >= 0 ?
        [local_corners[0], local_corners[3], local_corners[2], local_corners[1]] :
        [local_corners[0], local_corners[1], local_corners[2], local_corners[3]]

      cap = wall_group.entities.add_face(ordered)
      cap ||= wall_group.entities.add_face(ordered.reverse)
      unless cap && cap.valid?
        puts '[DoorTool] reconstruct_solid_patch: add_face on corners failed'
        return false
      end

      pushpull_through_wall!(cap, local_outward, thickness)
      true
    end

    def find_wall_face_near_opening(wall_group, data, local_xform, local_outward)
      ext, _int = parallel_wall_faces(wall_group, data)
      return ext if ext&.valid?

      local_picked = data[:picked_point].transform(local_xform)
      test_local = Geom::Point3d.new(data[:fx], data[:fy], data[:door_bot_z]).transform(local_xform)

      wall_group.entities.grep(Sketchup::Face).find do |f|
        next false unless f.valid? && face_matches_outward?(f, local_outward)
        proj = local_picked.project_to_plane(f.plane)
        next true if local_picked.distance(proj) < 2.0
        proj2 = test_local.project_to_plane(f.plane)
        test_local.distance(proj2) < 2.0
      end
    end

    def opening_corners_local(data, local_xform, plane)
      [
        Geom::Point3d.new(data[:fx] - data[:ux], data[:fy] - data[:uy], data[:door_bot_z]),
        Geom::Point3d.new(data[:fx] + data[:ux], data[:fy] + data[:uy], data[:door_bot_z]),
        Geom::Point3d.new(data[:fx] + data[:ux], data[:fy] + data[:uy], data[:door_top_z]),
        Geom::Point3d.new(data[:fx] - data[:ux], data[:fy] - data[:uy], data[:door_top_z])
      ].map { |p| p.transform(local_xform).project_to_plane(plane) }
    end

    def pushpull_through_wall!(face, local_outward, thickness)
      face.reverse! if face.normal.dot(local_outward) < 0
      sign = face.normal.dot(local_outward) > 0 ? -1 : 1
      face.pushpull(sign * thickness)
      true
    end

    def face_centroid_world(face, xform)
      verts = face.outer_loop.vertices
      return Geom::Point3d.new(0, 0, 0) if verts.empty?
      sx = sy = sz = 0.0
      verts.each do |v|
        p = v.position.transform(xform)
        sx += p.x
        sy += p.y
        sz += p.z
      end
      n = verts.length.to_f
      Geom::Point3d.new(sx / n, sy / n, sz / n)
    end

    def loop_centroid(loop)
      verts = loop.vertices
      return Geom::Point3d.new(0, 0, 0) if verts.empty?
      sx = sy = sz = 0.0
      verts.each do |v|
        p = v.position
        sx += p.x
        sy += p.y
        sz += p.z
      end
      n = verts.length.to_f
      Geom::Point3d.new(sx / n, sy / n, sz / n)
    end

    def build_door_at(wall_group, data, mark: nil, use_operations: true)
      unit = data[:unit]
      n = data[:n]
      thickness = data[:thickness]
      t = data[:t]
      clicked_side = data[:clicked_side]
      door_bot_z = data[:door_bot_z]
      door_top_z = data[:door_top_z]
      cx = data[:cx]
      cy = data[:cy]
      model = Sketchup.active_model
      comp = nil

      if use_operations
        model.start_operation('Door Data', true)
        begin
          door_group = create_door_group_with_attrs!(wall_group, data, unit, n, t, clicked_side,
                                                     door_bot_z, door_top_z, cx, cy, mark: mark)
          comp = convert_door_group_to_component!(door_group)
          model.commit_operation
        rescue => e
          model.abort_operation rescue nil
          puts "[DoorTool] door data error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
          return false
        end
      else
        begin
          door_group = create_door_group_with_attrs!(wall_group, data, unit, n, t, clicked_side,
                                                     door_bot_z, door_top_z, cx, cy, mark: mark)
          comp = convert_door_group_to_component!(door_group)
        rescue => e
          puts "[DoorTool] door data error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
          return false
        end
      end

      unless comp&.valid?
        puts '[DoorTool] door component missing after Door Data'
        return false
      end

      puts "[DoorTool] build_door_at: comp=#{comp.entityID} french=#{french_hinged_type?} type=#{@door_type.inspect} use_op=#{use_operations}"

      if french_hinged_type?
        if use_operations
          return build_french_hinged_in_component!(comp, data, unit, n, thickness)
        end

        ok = build_french_hinged_geometry!(comp.definition.entities, data, unit, n, thickness)
        if ok && door_body_present?(comp.definition)
          true
        else
          puts '[DoorTool] French Hinged body missing after build'
          false
        end
      else
        puts "[DoorTool] build_door_at: opening only (type=#{@door_type.inspect})"
        true
      end
    end

    def create_door_group_with_attrs!(wall_group, data, unit, n, t, clicked_side,
                                      door_bot_z, door_top_z, cx, cy, mark: nil)
      door_group = wall_group.parent.entities.add_group
      door_group.name = 'InteriorPro_Door'
      door_group.entities.add_cpoint(Geom::Point3d.new(0, 0, 0))
      door_group.transformation = Geom::Transformation.new(
        Geom::Point3d.new(cx, cy, (door_bot_z + door_top_z) / 2.0)
      )

      door_id      = generate_door_id
      host_wall_id = wall_group.get_attribute('InteriorPro', 'id')
      area_sqft    = (@width * @height) / 144.0

      door_group.set_attribute('InteriorPro', 'type',                   'door')
      door_group.set_attribute('InteriorPro', 'id',                     door_id)
      door_group.set_attribute('InteriorPro', 'mark', mark.nil? ? '' : mark.to_s)
      door_group.set_attribute('InteriorPro', 'door_category',          @door_category.to_s)
      door_group.set_attribute('InteriorPro', 'door_type',              @door_type)
      door_group.set_attribute('InteriorPro', 'preset_name',            @preset_name)
      door_group.set_attribute('InteriorPro', 'width_in',               @width.to_f)
      door_group.set_attribute('InteriorPro', 'height_in',              @height.to_f)
      door_group.set_attribute('InteriorPro', 'frame_width_in',         @frame_width.to_f)
      door_group.set_attribute('InteriorPro', 'glass_frame_width_in',   @glass_frame_width.to_f)
      door_group.set_attribute('InteriorPro', 'interior_depth_in',      @interior_depth.to_f)
      door_group.set_attribute('InteriorPro', 'glass_grid_style',         @glass_grid_style.to_s)
      door_group.set_attribute('InteriorPro', 'exterior_casing_style',    @exterior_casing_style.to_s)
      door_group.set_attribute('InteriorPro', 'interior_casing_style',    @interior_casing_style.to_s)
      door_group.set_attribute('InteriorPro', 'exterior_casing',          casing_enabled?(@exterior_casing_style))
      door_group.set_attribute('InteriorPro', 'interior_casing',          casing_enabled?(@interior_casing_style))
      door_group.set_attribute('InteriorPro', 'exterior_threshold',     @exterior_threshold ? true : false)
      door_group.set_attribute('InteriorPro', 'floor_offset_in',        @floor_offset.to_f)
      door_group.set_attribute('InteriorPro', 'swing_direction',        @swing_direction)
      door_group.set_attribute('InteriorPro', 'swing_side',             @swing_side)
      door_group.set_attribute('InteriorPro', 'slide_direction',        @slide_direction)
      door_group.set_attribute('InteriorPro', 'area_sqft',              area_sqft)
      door_group.set_attribute('InteriorPro', 'host_wall_id',           host_wall_id)
      door_group.set_attribute('InteriorPro', 'position_along_wall_in', t.to_f)
      door_group.set_attribute('InteriorPro', 'face_x',                 data[:fx].to_f)
      door_group.set_attribute('InteriorPro', 'face_y',                 data[:fy].to_f)
      door_group.set_attribute('InteriorPro', 'clicked_side',           clicked_side)
      door_group.set_attribute('InteriorPro', 'bottom_z',               door_bot_z.to_f)
      door_group.set_attribute('InteriorPro', 'top_z',                  door_top_z.to_f)
      door_group.set_attribute('InteriorPro', 'created_at',             Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
      door_group.set_attribute('InteriorPro', 'plugin_version',         '0.1')

      connected = (wall_group.get_attribute('InteriorPro', 'connected_doors') || []).dup
      connected << door_id
      wall_group.set_attribute('InteriorPro', 'connected_doors', connected)
      door_group
    end

    def convert_door_group_to_component!(door_group)
      saved_attrs = {}
      dict = door_group.attribute_dictionary('InteriorPro', false)
      dict.each_pair { |k, v| saved_attrs[k] = v } if dict

      comp = door_group.to_component
      definition = comp.definition

      saved_attrs.each do |k, v|
        comp.set_attribute('InteriorPro', k, v)
      end

      d_id = saved_attrs['id'] || comp.get_attribute('InteriorPro', 'id')
      definition.name = "InteriorPro_Door_#{d_id}"
      comp.name = 'InteriorPro_Door'
      comp
    end

    def build_french_hinged_in_component!(comp, data, unit, n, thickness)
      model = Sketchup.active_model
      model.start_operation('Build French Hinged Body', true)
      begin
        puts "[DoorTool] french body: comp=#{comp.entityID} valid=#{comp.valid?} def_ents=#{comp.definition.entities.length}"
        ok = build_french_hinged_geometry!(comp.definition.entities, data, unit, n, thickness)
        puts "[DoorTool] french body: build_ok=#{ok} ents_after=#{comp.definition.entities.length} body_present=#{door_body_present?(comp.definition)}"
        model.commit_operation
        if ok && door_body_present?(comp.definition)
          true
        else
          puts '[DoorTool] French Hinged body missing after build'
          false
        end
      rescue => e
        model.abort_operation rescue nil
        puts "[DoorTool] french hinged body error: #{e.message}\n#{e.backtrace.first(8).join("\n")}"
        false
      end
    end

    def door_body_present?(definition)
      definition.entities.any? do |e|
        next false unless e.valid?
        if e.is_a?(Sketchup::Face)
          e.area > 0.5
        elsif e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          definition_has_faces?(e.definition.entities)
        else
          false
        end
      end
    end

    def definition_has_faces?(entities)
      entities.any? do |e|
        next false unless e.valid?
        if e.is_a?(Sketchup::Face)
          e.area > 0.5
        elsif e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          definition_has_faces?(e.definition.entities)
        else
          false
        end
      end
    end

    def build_french_hinged_geometry!(parent_ents, data, unit, n, thickness)
      puts "[DoorTool] french geom: half_w=#{data[:half_w].to_f.round(2)} h=#{(data[:door_top_z].to_f - data[:door_bot_z].to_f).round(2)} thickness=#{thickness.round(2)} type=#{@door_type.inspect}"
      model = Sketchup.active_model
      frame_mat = get_or_create_material(model, 'InteriorPro_Door_Frame',
                                         Sketchup::Color.new(245, 245, 240), 1.0)
      glass_mat = get_or_create_material(model, 'InteriorPro_Glass',
                                         Sketchup::Color.new(180, 180, 180), 0.4)

      half_w = data[:half_w].to_f
      half_h = (data[:door_top_z].to_f - data[:door_bot_z].to_f) / 2.0
      if half_w < 3.0 || half_h < 3.0
        puts "[DoorTool] invalid door size for French body: half_w=#{half_w} half_h=#{half_h}"
        return false
      end

      jamb_width = (@frame_width && @frame_width > 0) ? @frame_width : 1.5
      stile_w = (@glass_frame_width && @glass_frame_width > 0) ? @glass_frame_width : 5.0
      leaf_depth = [1.5, thickness * 0.4].min

      iw = half_w - jamb_width
      if iw < 1.0
        puts "[DoorTool] door too narrow for jamb: iw=#{iw}"
        return false
      end

      head_inner = half_h - jamb_width
      leaf_top   = head_inner
      leaf_bot   = -half_h

      jamb_outer_v = 0.0
      jamb_inner_v = thickness

      build_u_jamb(parent_ents, half_w, half_h, head_inner, iw, jamb_outer_v, jamb_inner_v,
                   unit, n, frame_mat, 'Jamb')

      if @exterior_threshold && @door_category.to_s != 'interior'
        build_threshold(parent_ents, half_w, half_h, iw, thickness, unit, n, frame_mat)
      end

      meeting_gap = 0.125
      leaf_front_v = LEAF_FRAME_INSET
      leaf_back_v  = LEAF_FRAME_INSET + leaf_depth

      build_leaf(parent_ents, -iw, -meeting_gap, leaf_bot, leaf_top,
                 leaf_front_v, leaf_back_v, stile_w, unit, n,
                 frame_mat, glass_mat)
      build_leaf(parent_ents, meeting_gap, iw, leaf_bot, leaf_top,
                 leaf_front_v, leaf_back_v, stile_w, unit, n,
                 frame_mat, glass_mat)

      if casing_enabled?(@exterior_casing_style) && @door_category.to_s != 'interior'
        safe_build_casing(parent_ents, half_w, half_h, @exterior_casing_style, 0.0,
                          unit, n, frame_mat, 'Exterior_Casing', exterior: true)
      end
      if casing_enabled?(@interior_casing_style)
        safe_build_casing(parent_ents, half_w, half_h, @interior_casing_style, thickness,
                          unit, n, frame_mat, 'Interior_Casing', exterior: false)
      end

      smooth_door_body(parent_ents)
      true
    end

    # Legacy entry — builds inside a group (prefer build_french_hinged_in_component!).
    def build_french_hinged_body(door_group, unit, n, thickness, data: nil, in_parent_operation: false)
      data ||= {
        half_w: @width / 2.0,
        door_bot_z: -@height / 2.0,
        door_top_z: @height / 2.0
      }
      if in_parent_operation
        build_french_hinged_geometry!(door_group.entities, data, unit, n, thickness)
      else
        model = Sketchup.active_model
        model.start_operation('Build French Hinged Body', true)
        begin
          ok = build_french_hinged_geometry!(door_group.entities, data, unit, n, thickness)
          model.commit_operation
          ok
        rescue => e
          model.abort_operation rescue nil
          puts "[DoorTool] french hinged body error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
          false
        end
      end
    end

    # U-shaped jamb: left leg + right leg + head (no sill at floor).
    def build_u_jamb(parent_ents, half_w, half_h, head_inner, iw, v_start, v_end, unit, n, mat, name)
      grp = parent_ents.add_group
      grp.name = name
      ge = grp.entities
      extrude_rect(ge, -half_w, -iw, -half_h, half_h, v_start, v_end, unit, n)
      extrude_rect(ge, iw, half_w, -half_h, half_h, v_start, v_end, unit, n)
      extrude_rect(ge, -half_w, half_w, head_inner, half_h, v_start, v_end, unit, n)
      grp.material = mat
      grp
    end

    def safe_build_casing(parent_ents, half_w, half_h, style, v_wall, unit, n, mat, name, exterior: true)
      build_casing(parent_ents, half_w, half_h, style, v_wall, unit, n, mat, name, exterior: exterior)
    rescue => e
      puts "[DoorTool] casing error (#{style}): #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      nil
    end

    def ensure_casing_profiles!
      return if defined?(InteriorPro::DoorCasingProfiles)
      load File.join(File.dirname(__FILE__), 'door_casing_profiles.rb')
    end

    # Build U-shaped casing — single Follow Me sweep for clean mitered corners.
    def build_casing(parent_ents, half_w, half_h, style, v_wall, unit, n, mat, name, exterior: true)
      ensure_casing_profiles!
      spec = InteriorPro::DoorCasingProfiles.spec(style.to_s)
      dir = exterior ? -1.0 : 1.0

      grp = parent_ents.add_group
      grp.name = name
      ge = grp.entities

      unless build_u_casing_followme(ge, half_w, half_h, spec, v_wall, dir, unit, n)
        puts "[DoorTool] casing followme failed for #{style}, skipping trim"
      end

      grp.material = mat
      grp
    end

    # Sweep profile along inner jamb path: up left leg → head → down right leg.
    def build_u_casing_followme(ge, half_w, half_h, spec, v_wall, dir, unit, n)
      profile = spec[:profile]
      cw = spec[:width]
      max_d = spec[:depth]

      p_bl = local_uvw(-half_w, v_wall, -half_h, unit, n)
      p_tl = local_uvw(-half_w, v_wall,  half_h, unit, n)
      p_tr = local_uvw( half_w, v_wall,  half_h, unit, n)
      p_br = local_uvw( half_w, v_wall, -half_h, unit, n)

      u_outer = -(half_w + cw)
      prof_pts = profile.map do |u_frac, v_frac|
        u = -half_w + u_frac * (u_outer - (-half_w))
        v = v_wall + dir * v_frac * max_d
        local_uvw(u, v, -half_h, unit, n)
      end

      prof_face = ge.add_face(prof_pts)
      return false unless prof_face && prof_face.valid?

      path_edges = []
      [[p_bl, p_tl], [p_tl, p_tr], [p_tr, p_br]].each do |a, b|
        e = ge.add_line(a, b)
        path_edges << e if e
      end
      return false if path_edges.length < 3

      begin
        prof_face.followme(path_edges)
        smooth_profile_edges(ge)
      rescue => e
        puts "[DoorTool] followme error: #{e.message}"
        return false
      ensure
        path_edges.each { |edge| edge.erase! if edge && edge.valid? }
      end

      true
    end

    def smooth_profile_edges(entities, angle_limit = 50.degrees)
      smooth_entity_edges(entities, angle_limit)
    end

    # Soften small-angle edges throughout the door body (casing curves, etc.).
    # Sharp 90° frame corners stay visible.
    def smooth_door_body(entities, angle_limit = 50.degrees)
      entities.each do |ent|
        next unless ent.valid?
        if ent.is_a?(Sketchup::Group)
          smooth_entity_edges(ent.entities, angle_limit)
          smooth_door_body(ent.entities, angle_limit)
        end
      end
    end

    def smooth_entity_edges(entities, angle_limit)
      entities.grep(Sketchup::Edge).each do |edge|
        next unless edge.valid?
        faces = edge.faces
        next unless faces.length == 2
        ang = faces[0].normal.angle_between(faces[1].normal)
        next if ang >= angle_limit
        edge.soft = true
        edge.smooth = true
      end
    end

    def french_hinged_type?
      @door_type.to_s.strip == 'French Hinged'
    end

    def casing_enabled?(style)
      style.to_s != '' && style.to_s != 'none'
    end

    # Legacy rectangular U-casing (kept for jamb-like strips if needed).
    def build_u_casing(parent_ents, half_w, half_h, cw, v_start, v_end, unit, n, mat, name)
      grp = parent_ents.add_group
      grp.name = name
      ge = grp.entities
      ou_lo = -(half_w + cw)
      ou_hi = half_w + cw
      extrude_rect(ge, ou_lo, -half_w, -half_h, half_h + cw, v_start, v_end, unit, n)
      extrude_rect(ge, half_w, ou_hi, -half_h, half_h + cw, v_start, v_end, unit, n)
      extrude_rect(ge, ou_lo, ou_hi, half_h, half_h + cw, v_start, v_end, unit, n)
      grp.material = mat
      grp
    end

    # Threshold (סף): flat sill under the door (through wall) + ~1" stepped exterior nose.
    def build_threshold(parent_ents, half_w, half_h, iw, thickness, unit, n, mat)
      grp = parent_ents.add_group
      grp.name = 'Threshold'
      ge = grp.entities
      wf = -half_h

      # Sill through the wall (exterior face -> interior face).
      extrude_rect(ge, -iw, iw, wf - SILL_UNDER_DOOR_DEPTH, wf, 0.0, thickness, unit, n)

      # Stepped nose outside the wall only (0 -> -overhang).
      exterior_tiers = [
        { vf0: 0.00, vf1: 0.35, wt: 0.000,  wb: -0.125  },
        { vf0: 0.35, vf1: 0.65, wt: -0.125, wb: -0.250  },
        { vf0: 0.65, vf1: 0.88, wt: -0.250, wb: -0.375  },
        { vf0: 0.88, vf1: 1.00, wt: -0.375, wb: -0.500  }
      ]

      exterior_tiers.each do |tier|
        va = -THRESHOLD_OVERHANG * tier[:vf0]
        vb = -THRESHOLD_OVERHANG * tier[:vf1]
        extrude_rect(ge, -half_w, half_w, wf + tier[:wb], wf + tier[:wt], va, vb, unit, n)
      end

      grp.material = mat
      grp
    end

    # Solid rectangular strip extruded through the wall (v_start -> v_end).
    def extrude_rect(entities, u0, u1, w0, w1, v_start, v_end, unit, n)
      return if u1 <= u0 + 0.01 || w1 <= w0 + 0.01

      corners = [
        local_uvw(u0, v_start, w0, unit, n),
        local_uvw(u1, v_start, w0, unit, n),
        local_uvw(u1, v_start, w1, unit, n),
        local_uvw(u0, v_start, w1, unit, n)
      ]
      face = entities.add_face(corners)
      unless face&.valid?
        puts "[DoorTool] extrude_rect: add_face failed u=#{u0.round(1)}-#{u1.round(1)} w=#{w0.round(1)}-#{w1.round(1)}"
        return
      end

      depth = v_end - v_start
      depth = -depth if face.normal.dot(n) < 0
      face.pushpull(depth)
    end

    # One glazed leaf: frame ring, glass, optional grid muntins, and handle.
    def build_leaf(parent_ents, u0, u1, w_bot, w_top, vf, vb, stile_w, unit, n,
                   frame_mat, glass_mat)
      leaf = parent_ents.add_group
      leaf.name = u0 < 0 ? 'Leaf_Left' : 'Leaf_Right'
      le = leaf.entities

      outer = [
        local_uvw(u0, vf, w_bot, unit, n),
        local_uvw(u1, vf, w_bot, unit, n),
        local_uvw(u1, vf, w_top, unit, n),
        local_uvw(u0, vf, w_top, unit, n)
      ]
      hu0 = u0 + stile_w
      hu1 = u1 - stile_w
      wg_bot = w_bot + stile_w
      wg_top = w_top - stile_w
      inner = [
        local_uvw(hu0, vf, wg_bot, unit, n),
        local_uvw(hu1, vf, wg_bot, unit, n),
        local_uvw(hu1, vf, wg_top, unit, n),
        local_uvw(hu0, vf, wg_top, unit, n)
      ]
      face = le.add_face(outer)
      if face
        hole = le.add_face(inner)
        hole.erase! if hole
        depth = vb - vf
        depth = -depth if face.normal.dot(n) < 0
        face.pushpull(depth)
        leaf.material = frame_mat
      end

      vmid = (vf + vb) / 2.0
      style = (@glass_grid_style || 'none').to_s.downcase
      cols, rows = parse_grid_style(style)
      has_grid = style != 'none' && cols >= 1 && rows >= 1 &&
                 hu1 > hu0 + 1.0 && wg_top > wg_bot + 1.0

      if has_grid
        build_glass_lites(le, hu0, hu1, wg_bot, wg_top, vmid, unit, n, glass_mat, cols, rows)
        build_glass_muntins(le, hu0, hu1, wg_bot, wg_top, vmid, unit, n, frame_mat, cols, rows)
      else
        glass = [
          local_uvw(hu0, vmid, wg_bot, unit, n),
          local_uvw(hu1, vmid, wg_bot, unit, n),
          local_uvw(hu1, vmid, wg_top, unit, n),
          local_uvw(hu0, vmid, wg_top, unit, n)
        ]
        gface = le.add_face(glass)
        if gface
          gface.material = glass_mat
          gface.back_material = glass_mat
        end
      end

      leaf
    end

    def parse_grid_style(style)
      return [0, 0] if style.nil? || style.empty? || style == 'none'
      if style =~ /^(\d+)x(\d+)$/i
        [$1.to_i, $2.to_i]
      else
        [0, 0]
      end
    end

    # One glass lite per grid cell, inset so it sits centered between muntins.
    def build_glass_lites(le, hu0, hu1, w_bot, w_top, vmid, unit, n, glass_mat, cols, rows)
      half_m = MUNTIN_WIDTH / 2.0
      u_span = hu1 - hu0
      w_span = w_top - w_bot

      cols.times do |i|
        rows.times do |j|
          u_l = hu0 + u_span * i / cols.to_f
          u_r = hu0 + u_span * (i + 1) / cols.to_f
          w_b = w_bot + w_span * j / rows.to_f
          w_t = w_bot + w_span * (j + 1) / rows.to_f

          gu0 = i > 0 ? u_l + half_m : u_l
          gu1 = i < cols - 1 ? u_r - half_m : u_r
          gw0 = j > 0 ? w_b + half_m : w_b
          gw1 = j < rows - 1 ? w_t - half_m : w_t

          next if gu1 <= gu0 + 0.01 || gw1 <= gw0 + 0.01

          glass = [
            local_uvw(gu0, vmid, gw0, unit, n),
            local_uvw(gu1, vmid, gw0, unit, n),
            local_uvw(gu1, vmid, gw1, unit, n),
            local_uvw(gu0, vmid, gw1, unit, n)
          ]
          gface = le.add_face(glass)
          next unless gface
          gface.material = glass_mat
          gface.back_material = glass_mat
        end
      end
    end

    # Muntin grid on the glass opening (cols × rows lites per leaf).
    def build_glass_muntins(le, hu0, hu1, w_bot, w_top, vmid, unit, n, mat, cols, rows)
      mw = MUNTIN_WIDTH
      half_m = mw / 2.0
      u_span = hu1 - hu0
      w_span = w_top - w_bot

      (1...cols).each do |i|
        u = hu0 + u_span * i / cols.to_f
        build_muntin_bar(le, u - half_m, u + half_m, w_bot, w_top, vmid, unit, n, mat)
      end

      (1...rows).each do |j|
        w = w_bot + w_span * j / rows.to_f
        build_muntin_bar(le, hu0, hu1, w - half_m, w + half_m, vmid, unit, n, mat, vertical: false)
      end
    end

    def build_muntin_bar(le, u0, u1, w0, w1, vmid, unit, n, mat, vertical: true)
      bar = le.add_group
      bar.name = vertical ? 'Muntin_V' : 'Muntin_H'
      be = bar.entities
      # Extrude symmetrically about vmid so glass at vmid sits in the muntin mid-depth.
      half_d = MUNTIN_DEPTH / 2.0
      v_face = vmid - half_d
      corners = [
        local_uvw(u0, v_face, w0, unit, n),
        local_uvw(u1, v_face, w0, unit, n),
        local_uvw(u1, v_face, w1, unit, n),
        local_uvw(u0, v_face, w1, unit, n)
      ]
      face = be.add_face(corners)
      return unless face
      depth = MUNTIN_DEPTH
      depth = -depth if face.normal.dot(n) < 0
      face.pushpull(depth)
      bar.material = mat
    end

    def local_uvw(u, v, w, unit, n)
      Geom::Point3d.new(u * unit.x + v * n.x, u * unit.y + v * n.y, w)
    end

    def get_or_create_material(model, name, color, alpha = 1.0)
      mat = model.materials[name]
      if mat.nil?
        mat = model.materials.add(name)
        mat.color = color
        mat.alpha = alpha
      end
      mat
    end

    def parse_anchor(anchor)
      if anchor == 'center'
        ['center', 'center']
      else
        parts = anchor.split('-')
        [parts[0] || 'bottom', parts[1] || 'center']
      end
    end

    def generate_door_id
      require 'securerandom'
      SecureRandom.uuid
    rescue StandardError
      "door-#{Time.now.to_f}-#{rand(1_000_000)}"
    end

    %i[SWING_ANGLE MUNTIN_WIDTH MUNTIN_DEPTH THRESHOLD_OVERHANG SILL_UNDER_DOOR_DEPTH
       LEAF_FRAME_INSET].each do |c|
      remove_const(c) if const_defined?(c, false)
    end
    SWING_ANGLE             = 35.degrees
    MUNTIN_WIDTH            = 0.5
    MUNTIN_DEPTH            = 0.375
    THRESHOLD_OVERHANG      = 1.0
    SILL_UNDER_DOOR_DEPTH   = 0.625
    LEAF_FRAME_INSET        = 1.0

  end
end
