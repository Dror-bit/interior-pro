# encoding: utf-8
# plan_canvas.rb - fills a PlanDoc canvas with the 2D plan.
#
# It does NOT re-draw the plan. plan_generator.rb already works out every
# poche, door swing, window symbol, mark and dimension chain; this file just
# hands it a fake "entities" that writes shapes into a canvas instead of
# building SketchUp geometry. So there is exactly ONE plan drawing in the
# project, and it stays the one the user already checks in SketchUp.
#
# Everything lands in model inches. Paper and scale are the sheet's problem.

require File.join(File.dirname(__FILE__), 'plan_doc') unless
  defined?(InteriorPro::PlanDoc)
require File.join(File.dirname(__FILE__), 'plan_tables') unless
  defined?(InteriorPro::PlanTables)

module InteriorPro
  module PlanCanvas
    # plan_generator paints faces with named materials; the name tells us what
    # the fill should be on paper.
    FILL_BY_MATERIAL = {
      'InteriorPro_Plan_Exterior' => [64, 64, 64],
      'InteriorPro_Plan_Interior' => [205, 205, 205],
      'InteriorPro_Plan_Line'     => [0, 0, 0]
    }.freeze unless const_defined?(:FILL_BY_MATERIAL, false)

    DEFAULT_FILL = [128, 128, 128].freeze unless const_defined?(:DEFAULT_FILL, false)
    CIRCLE_SEGMENTS = 32 unless const_defined?(:CIRCLE_SEGMENTS, false)

    def self.fill_for(mat)
      name = mat.respond_to?(:name) ? mat.name.to_s : mat.to_s
      FILL_BY_MATERIAL[name] || DEFAULT_FILL
    end

    # ------------------------------------------------------------- recorder

    # Stands in for a Sketchup::Face. plan_generator only ever paints it.
    class RecFace
      def initialize(shape); @shape = shape; end
      def material=(m); @shape[:fill] = PlanCanvas.fill_for(m); end
      def back_material=(m); material = m; end
      def valid?; true; end
    end

    class RecBounds
      attr_reader :center
      def initialize(center); @center = center; end
    end

    # Stands in for the little group plan_generator makes for a piece of 3D
    # text. It is created at the origin, then rotated and slid into place; we
    # follow the same moves and remember where it ended up.
    class RecTextGroup
      attr_reader :shape

      def initialize(shape)
        @shape = shape
        @pos   = Geom::Point3d.new(0, 0, 0)
        @ang   = 0.0
      end

      def entities; self; end

      # add_3d_text(str, align, font, bold, italic, height, ...)
      def add_3d_text(str, _align = nil, _font = nil, bold = false,
                      italic = false, height = 1.0, *_rest)
        @shape[:text]   = str.to_s
        @shape[:h]      = height.to_f
        @shape[:bold]   = !!bold
        @shape[:italic] = !!italic
        true
      end

      def bounds; RecBounds.new(@pos); end

      def transform!(t)
        p0 = Geom::Point3d.new(0, 0, 0).transform(t)
        p1 = Geom::Point3d.new(1, 0, 0).transform(t)
        @ang += Math.atan2(p1.y - p0.y, p1.x - p0.x)
        @pos = @pos.transform(t)
        @shape[:x]        = @pos.x
        @shape[:y]        = @pos.y
        @shape[:rotation] = @ang * 180.0 / Math::PI
        self
      end

      def grep(_klass); []; end
      def valid?; true; end
      def erase!; @shape[:dead] = true; end
      def name=(_n); end
    end

    # The fake entities. Same handful of calls plan_generator makes on a real
    # Sketchup::Entities, nothing more.
    class Recorder
      attr_accessor :layer_name
      attr_reader :buckets

      def initialize
        @buckets    = {}
        @layer_name = 'PLAN'
      end

      def shapes
        @buckets[@layer_name] ||= []
      end

      def add_edges(*args)
        pts = args.length == 1 && args[0].is_a?(Array) ? args[0] : args
        pts = pts.compact
        return [] if pts.length < 2
        push(type: :polyline, points: xy(pts), closed: false)
        []
      end

      def add_face(pts)
        shape = { type: :polygon, points: xy(pts), closed: true, fill: DEFAULT_FILL }
        push(shape)
        RecFace.new(shape)
      end

      def add_circle(center, _normal, radius, segments = CIRCLE_SEGMENTS)
        n = [segments.to_i, 3].max
        pts = (0...n).map do |i|
          a = 2.0 * Math::PI * i / n
          [center.x + Math.cos(a) * radius, center.y + Math.sin(a) * radius]
        end
        push(type: :polyline, points: pts + [pts.first], closed: true)
        []
      end

      def add_group
        shape = { type: :text, text: '', x: 0.0, y: 0.0, h: 1.0,
                  align: :center, rotation: 0.0 }
        push(shape)
        RecTextGroup.new(shape)
      end

      # plan_generator never reads these back, but keep the surface honest.
      def grep(_klass); []; end
      def length; @buckets.values.map(&:length).inject(0) { |a, b| a + b }; end
      def to_a; @buckets.values.flatten; end

      # Pour everything into a canvas, one layer per bucket, dropping the
      # empty text groups plan_generator throws away on error.
      def flush_into(canvas)
        @buckets.each do |name, list|
          keep = list.reject { |s| s[:dead] || (s[:type] == :text && s[:text].to_s.empty?) }
          next if keep.empty?
          lay = canvas.layer(name)
          keep.each { |s| lay.shapes << s }
        end
        canvas
      end

      private

      def push(shape)
        shapes << shape
        shape
      end

      def xy(pts)
        pts.map { |p| p.respond_to?(:x) ? [p.x.to_f, p.y.to_f] : [p[0].to_f, p[1].to_f] }
      end
    end

    # -------------------------------------------------------------- builder

    LAYERS = {
      walls:      'WALLS',
      doors:      'DOORS',
      windows:    'WINDOWS',
      dimensions: 'DIMENSIONS',
      rooms:      'ROOMS',
      sketch:     'SKETCH'
    }.freeze unless const_defined?(:LAYERS, false)

    # Reads the model through plan_generator and fills doc's canvas.
    # Returns the canvas.
    def self.build(model, doc, canvas_name = 'MODEL')
      pg = InteriorPro::PlanGenerator
      cv = doc.canvas(canvas_name)
      cv.layers.clear

      doors, windows = pg.send(:hosted_bodies, model)
      pg.send(:assign_marks!, doors.select { |b| b[:category] != 'interior' }, 'D')
      pg.send(:assign_marks!, doors.select { |b| b[:category] == 'interior' }, 'IN')
      pg.send(:assign_marks!, windows, 'W')

      rec = Recorder.new
      pg.send(:walls, model).each do |wall|
        d = pg.send(:wall_attrs, wall)
        next unless d
        rec.layer_name = LAYERS[:walls]
        next unless safely { pg.send(:draw_wall_plan, rec, d) }
        rec.layer_name = LAYERS[:doors]
        safely { pg.send(:draw_door_symbols, rec, d, doors.select { |b| b[:host] == d[:id] }) }
        rec.layer_name = LAYERS[:windows]
        safely { pg.send(:draw_window_symbols, rec, d, windows.select { |b| b[:host] == d[:id] }) }
        if d[:category] != 'interior'
          rec.layer_name = LAYERS[:dimensions]
          safely { pg.send(:draw_wall_dim, rec, d) }
        end
      end

      rec.layer_name = LAYERS[:dimensions]
      safely { pg.send(:draw_dim_chains, rec, model) }
      rec.layer_name = LAYERS[:rooms]
      safely { pg.send(:draw_room_labels, rec, model) }
      rec.layer_name = LAYERS[:sketch]
      safely { pg.send(:draw_sketches, rec, model) }

      rec.flush_into(cv)
      doc.schedules = InteriorPro::PlanTables.rows_from(doors, windows) if
        defined?(InteriorPro::PlanTables)
      cv
    end

    def self.safely
      yield
    rescue StandardError => e
      puts "[PlanCanvas] #{e.class}: #{e.message}"
      nil
    end

    # --------------------------------------------------------- one sheet out

    # model -> drawing document -> PDF, in one call. The user picks the page
    # size and the scale; nothing here changes them behind his back.
    #
    #   InteriorPro::PlanCanvas.export_pdf!('C:/Users/me/Desktop/plan.pdf',
    #                                       size: 'ARCH D', scale: '1/4"')
    def self.export_pdf!(path, opts = {})
      require File.join(File.dirname(__FILE__), 'plan_pdf') unless
        defined?(InteriorPro::PlanPDF)
      model = opts[:model] || Sketchup.active_model
      doc   = build_document(model, opts)
      InteriorPro::PlanPDF.export(doc, path)
      puts "[PlanCanvas] wrote #{path}"
      path
    end

    # The document behind that PDF, on its own, so tests and the LayOut engine
    # can use exactly the same thing.
    def self.build_document(model, opts = {})
      pd  = InteriorPro::PlanDoc
      doc = pd::Document.new(opts[:project_name].to_s)
      doc.job_address = opts[:address].to_s
      doc.date        = opts[:date]
      doc.logo_path   = opts[:logo]

      build(model, doc, 'MODEL')

      st = {
        'size'            => opts[:size] || pd::DEFAULT_PAGE_SIZE,
        'orientation'     => (opts[:orientation] || :landscape).to_s,
        'scale'           => opts[:scale] || pd::DEFAULT_SCALE,
        'sheet_number'    => opts[:sheet_number],
        'sheet_title'     => opts[:sheet_title],
        'tables_own_page' => opts.key?(:tables_own_page) ? opts[:tables_own_page] : true,
        'hidden'          => []
      }
      layout_pages!(doc, st)
      doc
    end

    # Builds every page from scratch out of the user's choices. Cheap - a page
    # is a title block, maybe the tables, and one window on the plan - so the
    # window can call this on every click and never drift from the PDF.
    def self.layout_pages!(doc, st)
      pd     = InteriorPro::PlanDoc
      pt     = InteriorPro::PlanTables
      hidden = Array(st['hidden']).map(&:to_s)
      doc.pages.clear

      size   = st['size'] || pd::DEFAULT_PAGE_SIZE
      orient = (st['orientation'] || 'landscape').to_sym
      title  = st['sheet_title'].to_s.empty? ? 'FLOOR PLAN' : st['sheet_title'].to_s
      num    = st['sheet_number'].to_s.empty? ? 'A-101' : st['sheet_number'].to_s

      p1 = pd.new_sheet(doc, title,
                        size: size, orientation: orient,
                        scale: st['scale'] || pd::DEFAULT_SCALE, canvas: 'MODEL',
                        sheet_number: num, sheet_title: title)

      own       = st['tables_own_page'] != false
      tables_on = pt.any?(doc) && !hidden.include?(pt::LAYER)

      if tables_on && !own
        pt.place!(p1, doc)
        shrink_view_for_tables!(p1, doc, hidden)
      end

      v = p1.views.first
      b = doc.canvas('MODEL').bounds
      if st['origin_x'] && st['origin_y']
        v.origin_x = st['origin_x'].to_f
        v.origin_y = st['origin_y'].to_f
        # A position remembered from a model that has since changed can leave
        # the drawing completely off the sheet, and the page looks empty. If
        # not one inch of it is on the paper, come back to the middle.
        v.centre_on!(b) unless overlaps?(v.model_window, b)
      else
        v.centre_on!(b)
      end

      if tables_on && own
        p2 = doc.add_page('SCHEDULES', size, orient)
        pt.place!(p2, doc, full: true)
        pd.build_title_block!(p2, doc, sheet_number: next_sheet_number(num),
                                       sheet_title: 'SCHEDULES')
      end

      apply_visibility!(doc, hidden)
      doc
    end

    # Do two [minx, miny, maxx, maxy] boxes touch at all?
    def self.overlaps?(a, b)
      return false unless a && b
      a[0] <= b[2] && b[0] <= a[2] && a[1] <= b[3] && b[1] <= a[3]
    end

    # A-101 -> A-102. Anything we cannot read just gets a 2 on the end.
    def self.next_sheet_number(num)
      s = num.to_s
      m = s.match(/\A(.*?)(\d+)\z/)
      return "#{s}-2" unless m
      format("%s%0#{m[2].length}d", m[1], m[2].to_i + 1)
    end

    def self.apply_visibility!(doc, hidden)
      doc.canvases.each { |c| c.layers.each { |l| l.visible = !hidden.include?(l.name) } }
      doc.pages.each { |p| p.layers.each { |l| l.visible = !hidden.include?(l.name) } }
      doc
    end

    # The tables live on the right, so the plan window stops short of them.
    def self.shrink_view_for_tables!(page, doc, hidden = [])
      v = page.views.first
      return unless v
      fx, _fy, fw, _fh = page.frame
      pad = 0.25
      right = fx + fw - pad - InteriorPro::PlanTables.reserved_width(doc, hidden)
      v.w = [right - v.x, 1.0].max
    end

    # What would fit, said out loud and nothing else. The user decides.
    def self.report_fit(doc, page_name = nil)
      page = page_name ? doc.page(page_name) : doc.pages.first
      return nil unless page && page.views.first
      v = page.views.first
      b = doc.canvases.find { |c| c.name == v.canvas }&.bounds
      return nil unless b
      { fits: v.fits?(b), scale: v.scale, largest_that_fits: v.fit_scale(b) }
    end
  end
end
