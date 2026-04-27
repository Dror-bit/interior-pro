# Interior Pro - Window Tool (skeleton - placement logic comes in Step 2)

module InteriorPro
  class WindowTool

    attr_accessor :window_type, :width, :height, :header_height,
                  :frame_width, :install_window, :exterior_trim,
                  :interior_casing, :preset_name

    def initialize
      @window_type = 'Single Hung'
      @width = 36.0
      @height = 48.0
      @header_height = 80.0
      @frame_width = 1.5
      @install_window = true
      @exterior_trim = false
      @interior_casing = false
      @preset_name = ''
    end

    def activate
      Sketchup.status_text = "Window Tool: click on a wall to place a #{@width}\" x #{@height}\" window (Step 2 will implement actual cut)."
      @ip = Sketchup::InputPoint.new
    end

    def deactivate(view)
      view.invalidate
    end

    def onMouseMove(flags, x, y, view)
      @ip.pick(view, x, y)
      view.tooltip = "Click on wall - window: #{@width}\"W x #{@height}\"H"
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      UI.messagebox(
        "Window placement clicked.\n\n" \
        "Preset: #{@preset_name}\n" \
        "Type: #{@window_type}\n" \
        "Size: #{@width}\" x #{@height}\"\n" \
        "Header: #{@header_height}\"\n" \
        "Install: #{@install_window ? 'YES (frame+glass)' : 'NO (opening only)'}\n\n" \
        "Step 2 will implement the actual wall cut."
      )
    end

    def onCancel(reason, view)
      Sketchup.active_model.select_tool(nil)
    end

  end
end
