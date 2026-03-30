# Interior Pro - Wall Tool

module InteriorPro
  class WallTool
    WALL_HEIGHT_DEFAULT = 96.0   # inches (8 feet)
    WALL_THICKNESS_DEFAULT = 6.0 # inches

    def initialize
      @start_point = nil
      @end_point = nil
      @height = WALL_HEIGHT_DEFAULT
      @thickness = WALL_THICKNESS_DEFAULT
      @exterior_material = 'Stucco'
      @interior_material = 'Gypsum'
      @drawing = false
    end

    def activate
      @ip = Sketchup::InputPoint.new
      update_status_bar
      Sketchup.active_model.active_view.invalidate
    end

    def deactivate(view)
      view.invalidate
    end

    def onMouseMove(flags, x, y, view)
      @ip.pick(view, x, y)
      @end_point = @ip.position if @drawing
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      @ip.pick(view, x, y)
      if !@drawing
        @start_point = @ip.position
        @drawing = true
        update_status_bar
      else
        @end_point = @ip.position
        create_wall
        @start_point = @end_point
      end
    end

    def onLButtonDoubleClick(flags, x, y, view)
      finish_drawing
    end

    def onKeyDown(key, repeat, flags, view)
      if key == 27 # Escape
        finish_drawing
      end
    end

    def draw(view)
      return unless @drawing && @start_point && @end_point
      view.set_color_from_line(@start_point, @end_point)
      view.line_width = 2
      view.draw_line(@start_point, @end_point)
    end

    def create_wall
      return unless @start_point && @end_point
      length = @start_point.distance(@end_point)
      return if length < 0.1

      model = Sketchup.active_model
      model.start_operation('Create Wall', true)

      entities = model.active_entities
      dx = @end_point.x - @start_point.x
      dy = @end_point.y - @start_point.y
      len = Math.sqrt(dx**2 + dy**2)
      nx = -dy / len * @thickness / 2
      ny = dx / len * @thickness / 2

      pt1 = Geom::Point3d.new(@start_point.x + nx, @start_point.y + ny, 0)
      pt2 = Geom::Point3d.new(@end_point.x + nx, @end_point.y + ny, 0)
      pt3 = Geom::Point3d.new(@end_point.x - nx, @end_point.y - ny, 0)
      pt4 = Geom::Point3d.new(@start_point.x - nx, @start_point.y - ny, 0)

      group = entities.add_group
      group.name = 'InteriorPro_Wall'
      group.set_attribute('InteriorPro', 'type', 'wall')
      group.set_attribute('InteriorPro', 'height', @height)
      group.set_attribute('InteriorPro', 'thickness', @thickness)
      group.set_attribute('InteriorPro', 'exterior_material', @exterior_material)
      group.set_attribute('InteriorPro', 'interior_material', @interior_material)
      group.set_attribute('InteriorPro', 'start', @start_point.to_a.inspect)
      group.set_attribute('InteriorPro', 'end', @end_point.to_a.inspect)

      w_ents = group.entities
      face = w_ents.add_face(pt1, pt2, pt3, pt4)
      face.pushpull(@height)

      apply_materials(group, face)

      model.commit_operation
    end

    def apply_materials(group, face)
      model = Sketchup.active_model
      mats = model.materials

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

    def update_status_bar
      if @drawing
        Sketchup.set_status_text('Click to add point. Double-click or Escape to finish.', SB_PROMPT)
      else
        Sketchup.set_status_text('Click to start drawing a wall.', SB_PROMPT)
      end
    end

    def show_settings_dialog
      InteriorPro::UIDialogs.wall_settings(self)
    end

    attr_accessor :height, :thickness, :exterior_material, :interior_material
  end
end
