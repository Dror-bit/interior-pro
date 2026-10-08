# encoding: utf-8
# Interior Pro - Elevations (2026-10-08)
#
# Four elevations of a room - one per wall - taken straight off the model:
# a parallel camera inside the room looking at the wall, with a section
# plane `cut` inches from the wall so only what stands between the plane and
# the wall is seen (the user: "אני יוכל לבחור מה המרחק מהקיר שהוא יראה").
# Every piece in the room draws as itself - the toilet, the shower head, the
# vanity, the tiles - because it IS the model, in hidden-line.
#
# Measured on his model (debug_elevation.rb, 2026-10-08):
#   - a room's `boundary_xy` is written in the coordinates of the room group's
#     CONTAINER (the world at the top level); the group itself only carries
#     the label. So only what is outside the group is applied to it.
#   - SketchUp KEEPS what is on the side a section plane's normal points to.
#     The normal points at the wall, away from the eye.
#   - the eye must stand INSIDE the room: half an inch inside the far wall it
#     saw only that wall.
#
# Each elevation is a picture file beside the model
# (<model folder>/InteriorPro_sheet/elevations/) and goes onto the Sheet
# window as a picture sheet of its own, exactly like a dropped render, so the
# box, the crop, the turn and the PDF all work on it with nothing new.
# Dimensions and layers come later, one step at a time.
#
# Kill switch: USE_ELEVATIONS = false - the button says so and does nothing.
require 'fileutils'
require 'tmpdir'
module InteriorPro
  module ElevationTool
    USE_ELEVATIONS = true unless const_defined?(:USE_ELEVATIONS, false)
    D = 'InteriorPro' unless const_defined?(:D, false)
    NEST_DEPTH = 4 unless const_defined?(:NEST_DEPTH, false)
    MARGIN = 12.0 unless const_defined?(:MARGIN, false)         # inches of air round the wall
    PX_PER_IN = 12.0 unless const_defined?(:PX_PER_IN, false)   # picture resolution
    MAX_PX = 4800 unless const_defined?(:MAX_PX, false)
    OUT_DIR = 'InteriorPro_sheet/elevations' unless const_defined?(:OUT_DIR, false)
    TRACE = 'elevation_trace.txt' unless const_defined?(:TRACE, false)

    Thing = Struct.new(:ent, :xf, :type) unless const_defined?(:Thing, false)
    Side = Struct.new(:name, :a, :b, :len, :inward, :depth) unless const_defined?(:Side, false)

    class << self
      # ---- rooms ---------------------------------------------------------

      # every room of ours, also inside a plain group (the house in one group)
      def rooms(model = Sketchup.active_model)
        out = []
        collect(model.entities, nil, 0, out)
        out.select { |t| t.type == 'room' && room_poly(t) }
      end

      def collect(ents, outer, depth, out)
        ents.each do |e|
          next unless e.is_a?(Sketchup::Group) ||
                      (defined?(Sketchup::ComponentInstance) && e.is_a?(Sketchup::ComponentInstance))
          next unless e.valid?
          t = e.get_attribute(D, 'type')
          if t
            xf = outer ? outer * e.transformation : e.transformation
            out << Thing.new(e, xf, t.to_s)
            next
          end
          next if depth >= NEST_DEPTH
          next if e.respond_to?(:hidden?) && e.hidden?
          kids = defined?(Sketchup::ComponentInstance) && e.is_a?(Sketchup::ComponentInstance) ? e.definition.entities : e.entities
          collect(kids, outer ? outer * e.transformation : e.transformation, depth + 1, out)
        end
      rescue StandardError => e
        puts "[Elevation] collect: #{e.class}: #{e.message}"
      end

      def room_name(th)
        n = th.ent.get_attribute(D, 'name').to_s
        n.empty? ? "Room #{th.ent.get_attribute(D, 'number')}" : n
      end

      # the room's floor outline in the WORLD (see the note at the top)
      def room_poly(th)
        flat = th.ent.get_attribute(D, 'boundary_xy')
        return nil unless flat.is_a?(Array) && flat.size >= 6
        outer = th.xf * th.ent.transformation.inverse
        pts = flat.each_slice(2).map { |x, y| Geom::Point3d.new(x.to_f, y.to_f, 0).transform(outer) }
        pts.size >= 3 ? pts : nil
      rescue StandardError
        nil
      end

      def room_height(th, model = Sketchup.active_model)
        ids = Array(th.ent.get_attribute(D, 'bounding_wall_ids'))
        hs = []
        collect(model.entities, nil, 0, (all = []))
        all.each do |t|
          next unless t.type == 'wall' && ids.include?(t.ent.get_attribute(D, 'id'))
          h = t.ent.get_attribute(D, 'height').to_f
          hs << h if h > 0
        end
        hs.empty? ? 96.0 : hs.max
      end

      # ---- geometry (pure) -------------------------------------------------

      def signed_area(poly)
        a = 0.0
        poly.each_with_index { |p, i| q = poly[(i + 1) % poly.size]; a += p.x * q.y - q.x * p.y }
        a / 2.0
      end

      # One Side per edge of the outline, A, B, C... - its length, the way INTO
      # the room, and how deep the room is behind it. Edges under 12" are skipped.
      def sides(poly)
        ccw = signed_area(poly) > 0
        out = []
        poly.each_with_index do |a, i|
          b = poly[(i + 1) % poly.size]
          len = a.distance(b)
          next if len < 12.0
          dir = Geom::Vector3d.new(b.x - a.x, b.y - a.y, 0).normalize
          left = Geom::Vector3d.new(-dir.y, dir.x, 0)
          inward = ccw ? left : left.reverse
          depth = poly.map { |p| (p.x - a.x) * inward.x + (p.y - a.y) * inward.y }.max
          out << Side.new(('A'.ord + out.size).chr, a, b, len, inward, depth)
        end
        out
      end

      # Where the camera and the plane stand for one side. cut = inches from
      # the wall that are seen; nil or 0 = the whole room.
      def shot(side, wall_h, cut = nil, base_z = 0.0)
        c = cut.to_f
        c = side.depth - 0.5 if c <= 0 || c > side.depth - 0.5
        c = 1.0 if c < 1.0
        mid = Geom::Point3d.new((side.a.x + side.b.x) / 2.0, (side.a.y + side.b.y) / 2.0, base_z + wall_h / 2.0)
        n = side.inward
        plane_pt = Geom::Point3d.new(mid.x + n.x * c, mid.y + n.y * c, mid.z)
        eye = Geom::Point3d.new(mid.x + n.x * (c - 0.5), mid.y + n.y * (c - 0.5), mid.z)
        h_px = ((wall_h + 2 * MARGIN) * PX_PER_IN).round
        w_px = ((side.len + 2 * MARGIN) * PX_PER_IN).round
        if w_px > MAX_PX
          h_px = (h_px * MAX_PX / w_px.to_f).round
          w_px = MAX_PX
        end
        { eye: eye, target: mid, plane_pt: plane_pt, normal: n.reverse, cut: c,
          height: wall_h + 2 * MARGIN, w_px: w_px, h_px: h_px }
      end

      # ---- files -------------------------------------------------------------

      def model_dir(model = Sketchup.active_model)
        p = model.path.to_s.tr('\\', '/')
        p.empty? ? nil : File.dirname(p)
      end

      def out_dir(model = Sketchup.active_model)
        tmp = Sketchup.respond_to?(:temp_dir) ? Sketchup.temp_dir.to_s.tr('\\', '/') : Dir.tmpdir
        base = model_dir(model) || File.join(tmp, 'InteriorPro')
        File.join(base, OUT_DIR)
      end

      def slug(name)
        s = name.to_s.gsub(/[^A-Za-z0-9\u0590-\u05FF]+/, '_').gsub(/\A_+|_+\z/, '')
        s.empty? ? 'room' : s
      end

      def file_for(dir, room_name, side_name, style)
        File.join(dir, "#{slug(room_name)}_#{side_name}_#{style}.png")
      end

      # ---- the shot itself (SketchUp only) ---------------------------------

      RENDER_KEYS = %w[RenderMode DrawHorizon DrawGround BackgroundColor DisplaySectionPlanes
                       SectionCutFilled DisplayText DisplayDims DisplaySketchAxes
                       EdgeDisplayMode DrawSilhouettes ExtendLines
                       DisplaySectionCuts].freeze unless const_defined?(:RENDER_KEYS, false)

      # Takes every side of the room. Returns the picture paths, in A, B, C
      # order. style: 'lines' (hidden line) or 'shaded' (as he sees it).
      def shoot!(room, cut: nil, style: 'lines', model: Sketchup.active_model)
        raise 'Elevations are switched off (USE_ELEVATIONS)' unless USE_ELEVATIONS
        poly = room_poly(room)
        raise 'this room has no outline' unless poly
        view = model.active_view
        wall_h = room_height(room, model)
        base_z = poly.first.z
        dir = out_dir(model)
        FileUtils.mkdir_p(dir)
        name = room_name(room)
        paths = []
        cam0 = view.camera
        keep = [cam0.eye, cam0.target, cam0.up, cam0.perspective?, (cam0.perspective? ? cam0.fov : cam0.height)]
        ro = model.rendering_options
        saved = {}
        RENDER_KEYS.each { |k| saved[k] = ro[k] }
        model.start_operation('Elevations', true)
        begin
          ro['DrawHorizon'] = false
          ro['DrawGround'] = false
          ro['BackgroundColor'] = Sketchup::Color.new(255, 255, 255)
          ro['DisplaySectionPlanes'] = false
          ro['DisplaySectionCuts'] = true
          ro['SectionCutFilled'] = true
          ro['DisplayText'] = false
          ro['DisplayDims'] = false
          ro['DisplaySketchAxes'] = false
          ro['RenderMode'] = (style == 'shaded' ? 3 : 1)
          sides(poly).each do |side|
            s = shot(side, wall_h, cut, base_z)
            sp = model.entities.add_section_plane([s[:plane_pt], s[:normal]])
            sp.activate
            cam = Sketchup::Camera.new(s[:eye], s[:target], Geom::Vector3d.new(0, 0, 1), false)
            cam.height = s[:height]
            view.camera = cam
            view.refresh
            path = file_for(dir, name, side.name, style)
            ok = view.write_image(path, s[:w_px], s[:h_px], true)
            sp.erase!
            trace("#{name} side #{side.name}: #{side.len.round(1)}\" long, cut #{s[:cut].round(1)}\", " \
                  "#{s[:w_px]}x#{s[:h_px]} -> #{File.basename(path)} #{ok ? 'written' : 'NOT written'}")
            paths << path if ok
          end
        ensure
          model.abort_operation
          saved.each { |k, v| ro[k] = v unless v.nil? }
          begin
            cam = Sketchup::Camera.new(keep[0], keep[1], keep[2], keep[3])
            keep[3] ? cam.fov = keep[4] : cam.height = keep[4]
            view.camera = cam
          rescue StandardError => e
            puts "[Elevation] camera not put back: #{e.message}"
          end
        end
        paths
      end

      # ---- onto the sheet ----------------------------------------------------

      # Each picture becomes a picture sheet of its own in the Sheet window,
      # exactly as a dropped render does (st['images']). If the window is open
      # it is told to draw again.
      def add_to_sheet!(paths)
        return 0 if paths.empty?
        psd = InteriorPro::PlanSheetDialog
        st = psd.load_state
        have = Array(st['images']).map { |p| p.to_s.tr('\\', '/') }
        fresh = paths.map { |p| p.to_s.tr('\\', '/') }
        st['images'] = have.reject { |p| fresh.include?(p) } + fresh
        psd.save_state(st)
        begin
          dlg = psd.instance_variable_get(:@dialog)
          if dlg
            psd.instance_variable_set(:@doc, nil)
            psd.send(:push_all, dlg)
          end
        rescue StandardError => e
          puts "[Elevation] sheet window not refreshed: #{e.message}"
        end
        fresh.size
      end

      # the whole job from the panel: shoot, then onto the sheet
      def make!(room, cut: nil, style: 'lines')
        paths = shoot!(room, cut: cut, style: style)
        n = add_to_sheet!(paths)
        trace("#{room_name(room)}: #{paths.size} pictures, #{n} onto the sheet")
        paths
      end

      def trace(line)
        dir = (ENV['IP_PROBE_DIR'] || 'C:/Users/rordt/OneDrive/InteriorPro')
        return unless File.directory?(dir)
        File.open(File.join(dir, TRACE), 'a:UTF-8') { |f| f.puts "#{Time.now.strftime('%H:%M:%S')} #{line}" }
      rescue StandardError
        nil
      end
    end
  end
end
