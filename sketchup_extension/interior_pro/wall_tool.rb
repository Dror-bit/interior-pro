# Interior Pro - Wall Tool

module InteriorPro
  class WallTool
    attr_accessor :height, :thickness, :exterior_material, :interior_material, :wall_type_name, :anchor, :wall_category

    def initialize
      @start_point = nil
      @end_point = nil
      @height = 96.0
      @thickness = 6.0
      @exterior_material = 'Stucco'
      @interior_material = 'Gypsum'
      @wall_type_name = 'Default'
      @anchor = 'bottom-center'
      @wall_category = 'both'
      @drawing = false
      @locked_axis = nil
      @ip = nil
    end

    def activate
      @ip = Sketchup::InputPoint.new
      Sketchup.set_status_text('Click to start drawing a wall. Press Escape to cancel.', SB_PROMPT)
      Sketchup.active_model.active_view.invalidate
    end

    def deactivate(view)
      view.invalidate
    end

    def draw(view)
      return unless @drawing && @end_point

      dx = @end_point.x - @start_point.x
      dy = @end_point.y - @start_point.y
      len = Math.sqrt(dx**2 + dy**2)
      return if len < 0.1

      nx = -dy / len * @thickness / 2
      ny = dx / len * @thickness / 2

      if @anchor == 'center'
        v_anchor = 'center'
        h_anchor = 'center'
      else
        parts = @anchor.split('-')
        v_anchor = parts[0]
        h_anchor = parts[1] || 'center'
      end

      # Vertical Z range
      case v_anchor
      when 'top'
        z1 = -@height
        z2 = 0
      when 'center'
        z1 = -@height / 2.0
        z2 = @height / 2.0
      else # bottom
        z1 = 0
        z2 = @height
      end

      # Horizontal corner points (bottom face)
      case h_anchor
      when 'left'
        b1 = Geom::Point3d.new(@start_point.x, @start_point.y, z1)
        b2 = Geom::Point3d.new(@end_point.x, @end_point.y, z1)
        b3 = Geom::Point3d.new(@end_point.x + nx * 2, @end_point.y + ny * 2, z1)
        b4 = Geom::Point3d.new(@start_point.x + nx * 2, @start_point.y + ny * 2, z1)
      when 'right'
        b1 = Geom::Point3d.new(@start_point.x - nx * 2, @start_point.y - ny * 2, z1)
        b2 = Geom::Point3d.new(@end_point.x - nx * 2, @end_point.y - ny * 2, z1)
        b3 = Geom::Point3d.new(@end_point.x, @end_point.y, z1)
        b4 = Geom::Point3d.new(@start_point.x, @start_point.y, z1)
      else # center
        b1 = Geom::Point3d.new(@start_point.x + nx, @start_point.y + ny, z1)
        b2 = Geom::Point3d.new(@end_point.x + nx, @end_point.y + ny, z1)
        b3 = Geom::Point3d.new(@end_point.x - nx, @end_point.y - ny, z1)
        b4 = Geom::Point3d.new(@start_point.x - nx, @start_point.y - ny, z1)
      end

      # Top face points
      t1 = Geom::Point3d.new(b1.x, b1.y, z2)
      t2 = Geom::Point3d.new(b2.x, b2.y, z2)
      t3 = Geom::Point3d.new(b3.x, b3.y, z2)
      t4 = Geom::Point3d.new(b4.x, b4.y, z2)

      view.line_width = 2
      view.drawing_color = Sketchup::Color.new(0, 120, 255, 180)

      # Bottom edges
      view.draw_line(b1, b2)
      view.draw_line(b2, b3)
      view.draw_line(b3, b4)
      view.draw_line(b4, b1)

      # Top edges
      view.draw_line(t1, t2)
      view.draw_line(t2, t3)
      view.draw_line(t3, t4)
      view.draw_line(t4, t1)

      # Vertical edges
      view.draw_line(b1, t1)
      view.draw_line(b2, t2)
      view.draw_line(b3, t3)
      view.draw_line(b4, t4)
    end

    def onMouseMove(flags, x, y, view)
      @ip.pick(view, x, y)
      if @drawing
        raw = @ip.position
        @end_point = snap_to_axis(raw)
      end
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      @ip.pick(view, x, y)
      raw = @ip.position
      pt = snap_to_axis(raw)
      if !@drawing
        @start_point = pt
        @drawing = true
        Sketchup.set_status_text('Click endpoint. Double-click or Escape to finish.', SB_PROMPT)
      else
        @end_point = pt
        create_wall
        @start_point = @end_point
      end
    end

    def onLButtonDoubleClick(flags, x, y, view)
      finish_drawing
    end

    def onKeyDown(key, repeat, flags, view)
      finish_drawing if key == 27
      if key == 16 && @drawing
        if @locked_axis.nil?
          dx = @end_point ? (@end_point.x - @start_point.x).abs : 0
          dy = @end_point ? (@end_point.y - @start_point.y).abs : 0
          @locked_axis = dx > dy ? :x : :y
          Sketchup.set_status_text('Direction locked. Press Shift again to unlock.', SB_PROMPT)
        else
          @locked_axis = nil
          Sketchup.set_status_text('Click endpoint. Double-click or Escape to finish.', SB_PROMPT)
        end
        view.invalidate
      end
    end

    def snap_to_axis(pt)
      return Geom::Point3d.new(pt.x, pt.y, 0) unless @drawing && @start_point
      if @locked_axis == :x
        Geom::Point3d.new(pt.x, @start_point.y, 0)
      elsif @locked_axis == :y
        Geom::Point3d.new(@start_point.x, pt.y, 0)
      else
        Geom::Point3d.new(pt.x, pt.y, 0)
      end
    end

    def create_wall
      return unless @start_point && @end_point
      return if @start_point.distance(@end_point) < 0.1

      model = Sketchup.active_model
      model.start_operation('Create Wall', true)

      dx = @end_point.x - @start_point.x
      dy = @end_point.y - @start_point.y
      len = Math.sqrt(dx**2 + dy**2)
      nx = -dy / len * @thickness / 2
      ny = dx / len * @thickness / 2

      if @anchor == 'center'
        v_anchor = 'center'
        h_anchor = 'center'
      else
        parts = @anchor.split('-')
        v_anchor = parts[0]
        h_anchor = parts[1] || 'center'
      end

      Sketchup.set_status_text("anchor=#{@anchor} v=#{v_anchor} h=#{h_anchor} nx=#{nx.round(2)} ny=#{ny.round(2)}", SB_PROMPT)

      # Vertical (Z) offset
      case v_anchor
      when 'top'
        z_offset = -@height
      when 'center'
        z_offset = -@height / 2.0
      else # bottom
        z_offset = 0
      end

      # Horizontal offset based on anchor
      case h_anchor
      when 'left'
        pt1 = Geom::Point3d.new(@start_point.x, @start_point.y, z_offset)
        pt2 = Geom::Point3d.new(@end_point.x, @end_point.y, z_offset)
        pt3 = Geom::Point3d.new(@end_point.x + nx * 2, @end_point.y + ny * 2, z_offset)
        pt4 = Geom::Point3d.new(@start_point.x + nx * 2, @start_point.y + ny * 2, z_offset)
      when 'right'
        pt1 = Geom::Point3d.new(@start_point.x - nx * 2, @start_point.y - ny * 2, z_offset)
        pt2 = Geom::Point3d.new(@end_point.x - nx * 2, @end_point.y - ny * 2, z_offset)
        pt3 = Geom::Point3d.new(@end_point.x, @end_point.y, z_offset)
        pt4 = Geom::Point3d.new(@start_point.x, @start_point.y, z_offset)
      else # center
        pt1 = Geom::Point3d.new(@start_point.x + nx, @start_point.y + ny, z_offset)
        pt2 = Geom::Point3d.new(@end_point.x + nx, @end_point.y + ny, z_offset)
        pt3 = Geom::Point3d.new(@end_point.x - nx, @end_point.y - ny, z_offset)
        pt4 = Geom::Point3d.new(@start_point.x - nx, @start_point.y - ny, z_offset)
      end

      group = model.active_entities.add_group
      group.name = 'InteriorPro_Wall'
      group.set_attribute('InteriorPro', 'type', 'wall')
      group.set_attribute('InteriorPro', 'wall_type', @wall_type_name)
      group.set_attribute('InteriorPro', 'height', @height)
      group.set_attribute('InteriorPro', 'thickness', @thickness)
      group.set_attribute('InteriorPro', 'exterior_material', @exterior_material)
      group.set_attribute('InteriorPro', 'interior_material', @interior_material)
      group.set_attribute('InteriorPro', 'anchor', @anchor)

      w_ents = group.entities
      face = w_ents.add_face(pt1, pt2, pt3, pt4)
      if face.normal.z >= 0
        face.pushpull(@height)
      else
        face.pushpull(-@height)
      end
      apply_materials(face)

      model.commit_operation
    end

    def apply_materials(face)
      mats = Sketchup.active_model.materials
      ext_mat = mats[@exterior_material] || mats.add(@exterior_material)
      int_mat = mats[@interior_material] || mats.add(@interior_material)
      face.material = int_mat
      face.back_material = ext_mat
    end

    def finish_drawing
      @drawing = false
      @start_point = nil
      @end_point = nil
      Sketchup.active_model.select_tool(nil)
    end
  end
end
