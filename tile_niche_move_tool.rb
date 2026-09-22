# encoding: utf-8
# Interior Pro - MOVE A NICHE (2026-09-22, his ask: "הזזה").
#
# Click a niche, and it comes off the wall onto the mouse: the SAME ghost
# box the placing tool draws, held by its middle - along the wall AND up
# it - green where it fits, red where it does not. Click again to put it
# down; another wall face is fine too. Esc puts it back where it was.
# It is the placing tool with a first click: no maths of its own.
module InteriorPro
  class TileNicheMoveTool < TileNicheTool
    def activate
      @from = nil
      @cfg = nil
      reset
      @fits = false
      @ip = Sketchup::InputPoint.new
      status
    end

    def status
      if @from
        Sketchup.set_status_text('Move Niche: click where it goes - on this wall or another. Esc = put it back.', SB_PROMPT)
      else
        Sketchup.set_status_text('Move Niche: click the niche to move. Esc = done.', SB_PROMPT)
      end
    end

    def onCancel(_reason, view)
      if @from
        @from = nil
        @cfg = nil
        reset
        status
        view.invalidate
      else
        Sketchup.active_model.select_tool(nil)
      end
    end

    # Held by its MIDDLE up the wall as well - the placing tool holds the
    # bottom at the typed sill; a niche being carried follows the mouse.
    def sill_for(z)
      z.to_f - @cfg[:h] / 2.0
    end

    def onMouseMove(flags, x, y, view)
      unless @from
        @ip.pick(view, x, y)
        @hit = InteriorPro::TileNiche.niche_at(@ip.position)
        view.tooltip = @hit ? 'Click to pick this niche up' : ''
        view.invalidate
        return
      end
      @hover = face_point(view, x, y)
      @fits = false
      if @hover && @frame
        @cfg[:sill] = sill_for(@hover[:z])
        u0 = InteriorPro::TileNicheTool.ghost_u0(@hover[:u], @cfg[:w])
        lo, hi = InteriorPro::TileWall.face_limits(@wall, @frame, @hover[:u])
        @fits = InteriorPro::TileNicheTool.fits?(u0, @cfg[:w], @cfg[:sill], @cfg[:h], lo, hi, @hgt)
        view.tooltip = @fits ? 'Click to put it here' : 'Does not fit here'
      end
      view.invalidate
    end

    def onLButtonDown(_flags, x, y, view)
      unless @from
        @ip.pick(view, x, y)
        hit = InteriorPro::TileNiche.niche_at(@ip.position)
        if hit.nil?
          Sketchup.set_status_text('Move Niche: that is not a niche - click inside one.', SB_PROMPT)
          return
        end
        wall, idx, n = hit
        @from = { wall: wall, idx: idx }
        @cfg = { w: n[:w], h: n[:h], depth: n[:depth], sill: n[:z0], height: nil, run: false, wrap: false }
        @hit = nil
        status
        view.invalidate
        return
      end
      p = face_point(view, x, y)
      trace_click(x, y, p)
      if p.nil? || @frame.nil?
        Sketchup.set_status_text('Move Niche: click on the FACE of an Interior Pro wall.', SB_PROMPT)
        return
      end
      @cfg[:sill] = sill_for(p[:z])
      u0 = InteriorPro::TileNicheTool.ghost_u0(p[:u], @cfg[:w])
      lo, hi = InteriorPro::TileWall.face_limits(@wall, @frame, p[:u])
      unless InteriorPro::TileNicheTool.fits?(u0, @cfg[:w], @cfg[:sill], @cfg[:h], lo, hi, @hgt)
        Sketchup.set_status_text('Move Niche: it does not fit there (red) - move it along the wall.', SB_PROMPT)
        return
      end
      ok = InteriorPro::TileNiche.move_at!(@from[:wall], @from[:idx], to_wall: @wall, side: @side,
                                           u0: u0, z0: @cfg[:sill])
      UI.messagebox('The niche was not moved - see the Ruby Console for the reason.') unless ok
      @from = nil
      @cfg = nil
      reset
      status
      view.invalidate
    end

    def draw(view)
      if @from
        super
      elsif @hit
        wall, _i, n = @hit
        fr = InteriorPro::TileWall.frame_for(wall, n[:side])
        return if fr.nil?
        pts = [[n[:u0], n[:z0]], [n[:u0] + n[:w], n[:z0]], [n[:u0] + n[:w], n[:z0] + n[:h]], [n[:u0], n[:z0] + n[:h]]].map do |u, z|
          Geom::Point3d.new(*InteriorPro::TileWall.world(fr, u, z, GHOST_OUT))
        end
        view.drawing_color = Sketchup::Color.new(40, 110, 200, 70)
        view.draw(GL_QUADS, pts)
        view.drawing_color = Sketchup::Color.new(40, 110, 200)
        view.line_width = 4
        view.line_stipple = ''
        view.draw(GL_LINE_LOOP, pts)
      end
    end
  end
end
