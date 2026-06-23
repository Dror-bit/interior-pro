# Interior Pro — boolean door opening cut (Stage 2).
# Uses vendored Eneroth solid operations; falls back to legacy cut in door_tool.rb.

module InteriorPro
  module DoorBoolean

    USE_BOOLEAN_CUT = true unless const_defined?(:USE_BOOLEAN_CUT, false)

    def self.cut_opening!(wall_group, data, geo, tool)
      return nil unless USE_BOOLEAN_CUT
      return nil unless wall_group&.valid?

      modifier = nil
      modifier = build_opening_modifier(wall_group, data, geo, tool)
      return nil unless modifier&.valid?

      ops = InteriorPro::SolidBoolean::Operations
      unless ops.solid?(wall_group)
        modifier.erase!
        door_log 'boolean cut: wall is not a solid — fallback'
        return nil
      end
      unless ops.solid?(modifier)
        modifier.erase!
        door_log 'boolean cut: modifier is not a solid — fallback'
        return nil
      end

      wall_group.make_unique if wall_group.is_a?(Sketchup::Group)
      result = ops.subtract(wall_group, modifier)
      if result
        door_log 'boolean cut: ok'
        true
      else
        door_log 'boolean cut: subtract failed — fallback'
        nil
      end
    rescue => e
      modifier.erase! if modifier&.valid?
      door_log "boolean cut error: #{e.message}"
      nil
    end

    def self.build_opening_modifier(wall_group, data, geo, tool)
      parent_ents = wall_group.parent.entities
      modifier = parent_ents.add_group
      modifier.name = 'InteriorPro_OpeningCut_TMP'
      modifier.transformation = wall_group.transformation

      local_xform = Geom::Transformation.new
      local_outward = data[:outward].transform(wall_group.transformation.inverse)
      ext, int = tool.parallel_wall_faces(wall_group, data)
      unless ext&.valid?
        modifier.erase!
        return nil
      end

      plane = ext.plane
      corners_local = tool.opening_corners_local(data, local_xform, plane)
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
        return nil
      end

      depth = if int&.valid?
                corners_local[0].distance_to_plane(int.plane).abs
              else
                data[:thickness].to_f
              end
      depth = data[:thickness].to_f if depth < 0.1

      if face.normal.dot(local_outward) < 0
        face.reverse!
      end
      sign = face.normal.dot(local_outward) > 0 ? 1 : -1
      face.pushpull(sign * depth)

      modifier
    end

    def self.door_log(msg)
      InteriorPro::DoorTool::DOOR_DEBUG_LOG ? puts("[DoorBoolean] #{msg}") : nil
    end

  end
end
