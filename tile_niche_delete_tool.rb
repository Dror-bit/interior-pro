# encoding: utf-8
# Interior Pro - DELETE A NICHE (2026-09-22, his ask: "כפתור מחיקה לניצ").
#
# Hover a niche, it is outlined in red; click, and it is gone: the wall
# comes back whole from its own numbers and the tile on it is laid again
# over the spot. Esc leaves. The tool owns no geometry: TileNiche.niche_at
# says which niche, TileNiche.remove_at! takes it off.
module InteriorPro
  class TileNicheDeleteTool
    RED = [200, 40, 40].freeze unless const_defined?(:RED, false)

    def activate
      @hit = nil
      @ip = Sketchup::InputPoint.new
      Sketchup.set_status_text('Delete Niche: click a niche to take it off. Esc = done.', SB_PROMPT)
    end

    def deactivate(view)
      view.invalidate
    end

    def onCancel(_reason, _view)
      Sketchup.active_model.select_tool(nil)
    end

    def onMouseMove(_flags, x, y, view)
      @hit = pick(view, x, y)
      view.tooltip = @hit ? 'Click to delete this niche' : ''
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      hit = pick(view, x, y)
      if hit.nil?
        Sketchup.set_status_text('Delete Niche: that is not a niche - click inside one.', SB_PROMPT)
        return
      end
      wall, idx, = hit
      InteriorPro::TileNiche.remove_at!(wall, idx)
      @hit = nil
      view.invalidate
    end

    def pick(view, x, y)
      @ip.pick(view, x, y)
      InteriorPro::TileNiche.niche_at(@ip.position)
    rescue StandardError => e
      puts "[TileNiche] delete pick failed: #{e.message}"
      nil
    end

    def draw(view)
      return unless @hit
      wall, _i, n = @hit
      fr = InteriorPro::TileWall.frame_for(wall, n[:side])
      return if fr.nil?
      u0 = n[:u0]
      u1 = n[:u0] + n[:w]
      z0 = n[:z0]
      z1 = n[:z0] + n[:h]
      pts = [[u0, z0], [u1, z0], [u1, z1], [u0, z1]].map do |u, z|
        Geom::Point3d.new(*InteriorPro::TileWall.world(fr, u, z, 1.0))
      end
      view.drawing_color = Sketchup::Color.new(*color, 70)
      view.draw(GL_QUADS, pts)
      view.drawing_color = Sketchup::Color.new(*color)
      view.line_width = 4
      view.line_stipple = ''
      view.draw(GL_LINE_LOOP, pts)
    end

    # The edit tool paints its pick another colour.
    def color
      RED
    end

    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@hit[0].bounds) if @hit && @hit[0]&.valid?
      bb
    end
  end
end
