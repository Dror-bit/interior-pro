# Interior Pro - Wall Tool

module InteriorPro
  class WallTool
    attr_accessor :height, :thickness, :exterior_material, :interior_material, :wall_type_name, :anchor

    def initialize
      @start_point = nil
      @end_point = nil
      @height = 96.0
      @thickness = 6.0
      @exterior_material = 'Stucco'
      @interior_material = 'Gypsum'
      @wall_type_name = 'Default'
      @anchor = 'center'
      @drawing = false
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
    end

    def draw(view)
      return unless @drawing && @start_point && @end_point
      view.line_width = 2
      view.drawing_color = 'blue'
      view.draw_line(@start_point, @end_point)
    end

    def snap_to_axis(pt)
      return pt unless @drawing && @start_point
      dx = (pt.x - @start_point.x).abs
      dy = (pt.y - @start_point.y).abs
      if dx > dy
        Geom::Point3d.new(pt.x, @start_point.y, 0)
      else
        Geom::Point3d.new(@start_point.x, pt.y, 0)
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

      case @anchor
      when 'left'
        o = [@thickness / 2, 0]
        sx = @start_point.x + nx * 2
        sy = @start_point.y + ny * 2
        ex = @end_point.x + nx * 2
        ey = @end_point.y + ny * 2
        pt1 = Geom::Point3d.new(@start_point.x, @start_point.y, 0)
        pt2 = Geom::Point3d.new(@end_point.x, @end_point.y, 0)
        pt3 = Geom::Point3d.new(ex, ey, 0)
        pt4 = Geom::Point3d.new(sx, sy, 0)
      when 'right'
        sx = @start_point.x - nx * 2
        sy = @start_point.y - ny * 2
        ex = @end_point.x - nx * 2
        ey = @end_point.y - ny * 2
        pt1 = Geom::Point3d.new(sx, sy, 0)
        pt2 = Geom::Point3d.new(ex, ey, 0)
        pt3 = Geom::Point3d.new(@end_point.x, @end_point.y, 0)
        pt4 = Geom::Point3d.new(@start_point.x, @start_point.y, 0)
      else
        pt1 = Geom::Point3d.new(@start_point.x + nx, @start_point.y + ny, 0)
        pt2 = Geom::Point3d.new(@end_point.x + nx, @end_point.y + ny, 0)
        pt3 = Geom::Point3d.new(@end_point.x - nx, @end_point.y - ny, 0)
        pt4 = Geom::Point3d.new(@start_point.x - nx, @start_point.y - ny, 0)
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
      face.pushpull(@height)
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
