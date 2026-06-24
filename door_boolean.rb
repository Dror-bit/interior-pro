# Interior Pro — boolean door opening cut/fill (Stage 2).
# Uses vendored Eneroth solid operations; falls back to legacy in door_tool.rb / door_manager.rb.

module InteriorPro
  module DoorBoolean

    USE_BOOLEAN_CUT = true unless const_defined?(:USE_BOOLEAN_CUT, false)

    def self.cut_opening!(wall_group, data, geo, tool)
      return nil unless USE_BOOLEAN_CUT
      return nil unless wall_group&.valid?

      modifier = nil
      modifier = build_opening_box(wall_group, data, geo, tool)
      return nil unless modifier&.valid?

      ops = InteriorPro::SolidBoolean::Operations

      unless ops.solid?(wall_group)
        modifier.erase!
        door_warn "boolean cut: wall is not a solid (#{odd_face_edge_count(wall_group)} odd edges) — fallback"
        return nil
      end
      unless ops.solid?(modifier)
        modifier.erase!
        door_warn 'boolean cut: modifier is not a solid — fallback'
        return nil
      end

      wall_group.make_unique if wall_group.is_a?(Sketchup::Group)
      result = ops.subtract(wall_group, modifier)
      if result
        door_log 'boolean cut: ok'
        true
      else
        door_warn 'boolean cut: subtract failed — fallback'
        nil
      end
    rescue => e
      modifier.erase! if modifier&.valid?
      door_warn "boolean cut error: #{e.message}"
      nil
    end

    def self.patch_opening!(wall_group, data, geo, tool)
      return nil unless USE_BOOLEAN_CUT
      return nil unless wall_group&.valid?

      modifier = nil
      modifier = build_opening_box(wall_group, data, geo, tool)
      return nil unless modifier&.valid?

      ops = InteriorPro::SolidBoolean::Operations

      wall_solid = ops.solid?(wall_group)
      mod_solid = ops.solid?(modifier)

      unless mod_solid
        modifier.erase!
        door_warn 'patch: modifier is not a solid — fallback'
        return nil
      end

      wall_group.make_unique if wall_group.is_a?(Sketchup::Group)
      ok = false

      if wall_solid
        ok = ops.union(wall_group, modifier)
        if ok
          modifier.erase! if modifier&.valid?
          door_log 'patch: union ok'
        else
          door_warn 'patch: union failed — trying geometry merge'
        end
      else
        door_warn "patch: wall not solid (#{odd_face_edge_count(wall_group)} odd edges) — geometry merge"
      end

      unless ok
        ok = merge_opening_box_into_wall!(wall_group, modifier)
        if ok
          door_log 'patch: geometry merge ok'
        else
          modifier.erase! if modifier&.valid?
          door_warn 'patch: geometry merge failed — fallback'
        end
      end

      if ok
        merge_coplanar_on_floor_band!(wall_group, geo, tool)
        tool.heal_opening_after_fill!(wall_group, data, geo)
        tool.seal_opening_bottom!(wall_group, data, geo, after_fill: true)
        merge_coplanar_on_floor_band!(wall_group, geo, tool)
        true
      else
        nil
      end
    rescue => e
      modifier.erase! if modifier&.valid?
      door_warn "patch error: #{e.message}"
      nil
    end

    # Shared opening volume — same box for subtract (cut) and union/fill (patch).
    def self.build_opening_box(wall_group, data, geo, tool)
      parent_ents = wall_group.parent.entities
      modifier = parent_ents.add_group
      modifier.name = 'InteriorPro_OpeningBox_TMP'
      modifier.transformation = wall_group.transformation

      local_xform = wall_group.transformation.inverse
      local_outward = data[:outward].transform(local_xform)
      ext, int = tool.send(:parallel_wall_faces, wall_group, data)
      unless ext&.valid?
        modifier.erase!
        return nil
      end

      plane = ext.plane
      corners_local = tool.send(:opening_corners_local, data, local_xform, plane)
      orders = [
        [corners_local[0], corners_local[3], corners_local[2], corners_local[1]],
        [corners_local[0], corners_local[1], corners_local[2], corners_local[3]]
      ]

      face = nil
      orders.each do |ordered|
        begin
          face = modifier.entities.add_face(ordered)
          face ||= modifier.entities.add_face(ordered.reverse)
        rescue ArgumentError
          face = nil
        end
        break if face&.valid?
      end

      unless face&.valid?
        modifier.erase!
        door_warn 'build_opening_box: could not create face'
        return nil
      end

      depth = if int&.valid?
                corners_local[0].distance_to_plane(int.plane).abs
              else
                data[:thickness].to_f
              end
      depth = data[:thickness].to_f if depth < 0.1

      tool.send(:pushpull_through_wall!, face, local_outward, depth)

      modifier
    end

    # Explode opening box into wall when Eneroth union cannot run (wall with hole is not solid?).
    def self.merge_opening_box_into_wall!(wall_group, modifier)
      return false unless modifier&.valid?

      tr = wall_group.transformation.inverse * modifier.transformation
      temp = wall_group.entities.add_instance(modifier.definition, tr)
      modifier.erase!
      temp.explode
      true
    rescue => e
      modifier.erase! if modifier&.valid?
      door_warn "merge_opening_box: #{e.message}"
      false
    end
    private_class_method :merge_opening_box_into_wall!

    def self.heal_wall_for_boolean!(wall_group)
      ents = wall_group.entities
      stray = ents.grep(Sketchup::Edge).select { |e| e.valid? && e.faces.length < 2 }
      ents.erase_entities(stray)
      stray.length
    end
    private_class_method :heal_wall_for_boolean!

    def self.odd_face_edge_count(wall_group)
      wall_group.entities.grep(Sketchup::Edge).count { |e| e.valid? && e.faces.length.odd? }
    end
    private_class_method :odd_face_edge_count

    def self.merge_coplanar_on_floor_band!(wall_group, geo, tool)
      return 0 unless geo

      tool.merge_coplanar_on_floor_band!(wall_group, geo)
    end
    private_class_method :merge_coplanar_on_floor_band!

    def self.door_log(msg)
      InteriorPro::DoorTool::DOOR_DEBUG_LOG ? puts("[DoorBoolean] #{msg}") : nil
    end

    def self.door_warn(msg)
      puts "[DoorBoolean] #{msg}"
    end

  end
end
