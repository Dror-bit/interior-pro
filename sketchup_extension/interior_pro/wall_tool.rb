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
      @auto_snap = nil
      @length_input = ''
      @ip = nil
    end

    def activate
      @ip = Sketchup::InputPoint.new
      Sketchup.set_status_text('Click to start drawing a wall. Press Escape to cancel.', SB_PROMPT)
      view = Sketchup.active_model.active_view
      view.vcb_label = 'Length'
      view.invalidate
    end

    def deactivate(view)
      view.invalidate
    end

    def draw(view)
      @ip.draw(view) if @ip && @ip.display?
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

      color = case @auto_snap
              when :manual
                Sketchup::Color.new(0, 120, 255, 180)
              when :auto
                @locked_axis == :x ? Sketchup::Color.new(220, 0, 0, 200) : Sketchup::Color.new(0, 200, 0, 200)
              else
                Sketchup::Color.new(0, 120, 255, 180)
              end

      view.line_width = 2
      view.drawing_color = color
      edges = [b1,b2, b2,b3, b3,b4, b4,b1, t1,t2, t2,t3, t3,t4, t4,t1, b1,t1, b2,t2, b3,t3, b4,t4]
      view.draw(GL_LINES, edges)
    end

    def onMouseMove(flags, x, y, view)
      @ip.pick(view, x, y)
      if @drawing
        if @auto_snap == :manual
          @end_point = snap_to_axis(@ip.position)
        elsif snapped_to_geometry?
          @end_point = @ip.position
          @auto_snap = nil
          @locked_axis = nil
        else
          detect_auto_snap(@ip.position)
          @end_point = snap_to_axis(@ip.position)
        end
      end
      view.invalidate
    end

    def snapped_to_geometry?
      !@ip.vertex.nil? || !@ip.edge.nil?
    end

    def onLButtonDown(flags, x, y, view)
      @ip.pick(view, x, y)
      pt = if @auto_snap == :manual
             snap_to_axis(@ip.position)
           elsif snapped_to_geometry?
             @ip.position
           else
             snap_to_axis(@ip.position)
           end
      if !@drawing
        @start_point = pt
        @drawing = true
        @length_input = ''
        Sketchup.set_status_text('Click endpoint. Double-click or Escape to finish.', SB_PROMPT)
      else
        @end_point = pt
        create_wall
        @start_point = @end_point
        @length_input = ''
      end
    end

    def onLButtonDoubleClick(flags, x, y, view)
      finish_drawing
    end

    def onKeyDown(key, repeat, flags, view)
      if key == 27
        finish_drawing
        return
      end
      if key == 16 && @drawing && @start_point
        dx = @end_point ? (@end_point.x - @start_point.x).abs : 0
        dy = @end_point ? (@end_point.y - @start_point.y).abs : 0
        @locked_axis = dx > dy ? :x : :y
        @auto_snap = :manual
        Sketchup.set_status_text('Direction locked (hold Shift).', SB_PROMPT)
        view.invalidate
        return
      end

      return unless @drawing && @start_point

      if key >= 48 && key <= 57
        @length_input += (key - 48).to_s
        Sketchup.set_status_text("Length: #{@length_input}", SB_PROMPT)
        view.vcb_value = @length_input
      elsif key == 190 || key == 110 || key == 46
        @length_input += '.' unless @length_input.include?('.')
        Sketchup.set_status_text("Length: #{@length_input}", SB_PROMPT)
        view.vcb_value = @length_input
      elsif key == 222 || key == 39
        @length_input += "'"
        Sketchup.set_status_text("Length: #{@length_input}", SB_PROMPT)
        view.vcb_value = @length_input
      elsif key == 186 || key == 34
        @length_input += '"'
        Sketchup.set_status_text("Length: #{@length_input}", SB_PROMPT)
        view.vcb_value = @length_input
      elsif key == 8
        @length_input = @length_input[0...-1] if @length_input.length > 0
        Sketchup.set_status_text("Length: #{@length_input}", SB_PROMPT)
        view.vcb_value = @length_input
      elsif key == 13
        apply_length_input if @length_input.length > 0
      end
    end

    def apply_length_input
      return unless @start_point && @end_point
      length = @length_input.to_l
      @length_input = ''
      return if length <= 0
      dx = @end_point.x - @start_point.x
      dy = @end_point.y - @start_point.y
      cur_len = Math.sqrt(dx**2 + dy**2)
      return if cur_len < 0.001
      new_x = @start_point.x + dx / cur_len * length
      new_y = @start_point.y + dy / cur_len * length
      @end_point = Geom::Point3d.new(new_x, new_y, 0)
      create_wall
      @start_point = @end_point
      Sketchup.set_status_text('Click endpoint. Double-click or Escape to finish.', SB_PROMPT)
    end

    def onKeyUp(key, repeat, flags, view)
      if key == 16
        @locked_axis = nil
        @auto_snap = nil
        view.invalidate
      end
    end

    def detect_auto_snap(pt)
      return unless @start_point
      dx = pt.x - @start_point.x
      dy = pt.y - @start_point.y
      if dx.abs < 0.1 && dy.abs < 0.1
        @locked_axis = nil
        @auto_snap = nil
        return
      end
      angle = Math.atan2(dy, dx) * 180 / Math::PI
      angle += 360 if angle < 0
      if angle < 10 || angle > 350 || (angle > 170 && angle < 190)
        @locked_axis = :x
        @auto_snap = :auto
      elsif (angle > 80 && angle < 100) || (angle > 260 && angle < 280)
        @locked_axis = :y
        @auto_snap = :auto
      else
        @locked_axis = nil
        @auto_snap = nil
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
      face.pushpull(-@height)
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
