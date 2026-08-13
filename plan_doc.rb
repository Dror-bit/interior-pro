# encoding: utf-8
# plan_doc.rb - the drawing document. Pure Ruby, NO SketchUp API at all,
# so the whole thing can be built and checked outside SketchUp (tests/rt39.rb).
#
# The shape of it, copied from how the user already works in Rayon:
#
#   Document
#     canvases                 a 2D space drawn in REAL model inches
#       layers -> shapes       line / polyline / polygon / hatch / text /
#                              table / image
#     pages                    a sheet of paper, sized in PAPER inches
#       views                  a window on the sheet showing one canvas at one
#                              scale (scale belongs to the VIEW, not the page)
#       layers -> shapes       drawn straight in paper inches (title block...)
#
# Nothing here decides anything for the user: page size, orientation and scale
# are values he sets. fit_scale only REPORTS what would fit; it never changes
# a view.
#
# Paper coordinates: inches, origin at the BOTTOM-LEFT of the sheet, Y up.
# Model coordinates: inches, the same X/Y the plugin already stores on walls.

module InteriorPro
  module PlanDoc
    VERSION = 1 unless const_defined?(:VERSION, false)

    # ---------------------------------------------------------------- paper

    # [short side, long side] in inches. Four to start with; the user asked to
    # add more later.
    PAGE_SIZES = {
      'ARCH D'  => [24.0, 36.0],
      'ARCH C'  => [18.0, 24.0],
      'TABLOID' => [11.0, 17.0],
      'LETTER'  => [8.5,  11.0]
    }.freeze unless const_defined?(:PAGE_SIZES, false)

    DEFAULT_PAGE_SIZE   = 'ARCH D'   unless const_defined?(:DEFAULT_PAGE_SIZE, false)
    DEFAULT_ORIENTATION = :landscape unless const_defined?(:DEFAULT_ORIENTATION, false)
    DEFAULT_MARGIN      = 0.5        unless const_defined?(:DEFAULT_MARGIN, false)

    # Returns [width, height] in paper inches. :landscape puts the long side
    # across. A custom size is [w, h] straight through.
    def self.page_size(name, orientation = DEFAULT_ORIENTATION)
      if name.is_a?(Array)
        short, long = name.map { |v| v.to_f.abs }.sort
      else
        key = name.to_s.strip.upcase
        pair = PAGE_SIZES[key]
        raise ArgumentError, "unknown page size #{name.inspect}" unless pair
        short, long = pair
      end
      orientation.to_sym == :portrait ? [short, long] : [long, short]
    end

    def self.page_size_names
      PAGE_SIZES.keys
    end

    # ---------------------------------------------------------------- scale

    # label => paper inches per foot of building. '3/4"' means 3/4" = 1'-0".
    SCALES = [
      ['12"',    12.0],
      ['6"',      6.0],
      ['3"',      3.0],
      ['1-1/2"',  1.5],
      ['1"',      1.0],
      ['3/4"',    0.75],
      ['1/2"',    0.5],
      ['3/8"',    0.375],
      ['1/4"',    0.25],
      ['3/16"',   0.1875],
      ['1/8"',    0.125],
      ['3/32"',   0.09375],
      ['1/16"',   0.0625],
      ['1/32"',   0.03125],
      ['1/64"',   0.015625],
      ['1/128"',  0.0078125]
    ].freeze unless const_defined?(:SCALES, false)

    DEFAULT_SCALE = '1/4"' unless const_defined?(:DEFAULT_SCALE, false)

    def self.scale_labels
      SCALES.map(&:first)
    end

    # How many paper inches one MODEL inch becomes.
    def self.scale_factor(label)
      row = SCALES.assoc(label.to_s)
      raise ArgumentError, "unknown scale #{label.inspect}" unless row
      row[1] / 12.0
    end

    def self.scale_text(label)
      "#{label} = 1'-0\""
    end

    # ---------------------------------------------------------------- shapes

    SHAPE_TYPES = [:line, :polyline, :polygon, :hatch, :text, :table,
                   :image].freeze unless const_defined?(:SHAPE_TYPES, false)

    # A layer is just a named, ordered bag of shapes. Shapes are plain hashes
    # so any engine (PDF, LayOut, SVG, screen) can read them without knowing
    # about this file.
    class Layer
      attr_reader :name, :shapes
      attr_accessor :visible, :locked

      def initialize(name)
        @name    = name.to_s
        @shapes  = []
        @visible = true
        @locked  = false
      end

      def add(type, props = {})
        t = type.to_sym
        raise ArgumentError, "unknown shape #{type.inspect}" unless SHAPE_TYPES.include?(t)
        shape = { type: t }.merge(props)
        @shapes << shape
        shape
      end

      def line(x1, y1, x2, y2, opts = {})
        add(:line, { x1: x1.to_f, y1: y1.to_f, x2: x2.to_f, y2: y2.to_f }.merge(opts))
      end

      def polyline(points, opts = {})
        add(:polyline, { points: pts(points), closed: false }.merge(opts))
      end

      def polygon(points, opts = {})
        add(:polygon, { points: pts(points), closed: true }.merge(opts))
      end

      def hatch(points, opts = {})
        add(:hatch, { points: pts(points), spacing: 0.125, angle: 45.0 }.merge(opts))
      end

      # h is the text height in the layer's own units.
      def text(str, x, y, opts = {})
        add(:text, { text: str.to_s, x: x.to_f, y: y.to_f, h: 0.1,
                     align: :left, rotation: 0.0 }.merge(opts))
      end

      def table(x, y, headers, rows, opts = {})
        add(:table, { x: x.to_f, y: y.to_f, headers: Array(headers).map(&:to_s),
                      rows: rows.map { |r| Array(r).map(&:to_s) },
                      col_widths: nil, row_h: 0.22, h: 0.1 }.merge(opts))
      end

      def image(path, x, y, w, h, opts = {})
        add(:image, { path: path.to_s, x: x.to_f, y: y.to_f,
                      w: w.to_f, h: h.to_f }.merge(opts))
      end

      def empty?
        @shapes.empty?
      end

      def to_h
        { name: @name, visible: @visible, locked: @locked, shapes: @shapes }
      end

      private

      def pts(points)
        points.map { |p| [p[0].to_f, p[1].to_f] }
      end
    end

    # Anything that owns layers.
    module HasLayers
      def layers
        @layers ||= []
      end

      # Find or create, in order.
      def layer(name)
        found = layers.find { |l| l.name == name.to_s }
        return found if found
        made = Layer.new(name)
        layers << made
        made
      end

      def layer?(name)
        !layers.find { |l| l.name == name.to_s }.nil?
      end
    end

    # ---------------------------------------------------------------- canvas

    # A canvas is drawn in REAL model inches. Layer generators (walls, tiles,
    # electrical, furniture...) write into it and know nothing about paper.
    class Canvas
      include HasLayers
      attr_reader :name

      def initialize(name)
        @name = name.to_s
      end

      # [min_x, min_y, max_x, max_y] over every visible shape, or nil if empty.
      def bounds
        xs = []
        ys = []
        layers.each do |l|
          next unless l.visible
          l.shapes.each do |s|
            case s[:type]
            when :line
              xs << s[:x1] << s[:x2]
              ys << s[:y1] << s[:y2]
            when :polyline, :polygon, :hatch
              s[:points].each { |p| xs << p[0]; ys << p[1] }
            when :text, :table
              xs << s[:x]
              ys << s[:y]
            when :image
              xs << s[:x] << (s[:x] + s[:w])
              ys << s[:y] << (s[:y] + s[:h])
            end
          end
        end
        return nil if xs.empty?
        [xs.min, ys.min, xs.max, ys.max]
      end

      def to_h
        { name: @name, layers: layers.map(&:to_h) }
      end
    end

    # ------------------------------------------------------------------ view

    # A window on a sheet. Holds the three things the user sets: where the
    # model sits (origin), how big it is drawn (scale), and what it shows
    # (canvas). The origin lands at the CENTRE of the frame, like Rayon's
    # Anchor = Middle.
    class View
      attr_accessor :name, :x, :y, :w, :h, :canvas, :scale,
                    :origin_x, :origin_y, :frame

      def initialize(name, x, y, w, h, canvas, scale = DEFAULT_SCALE)
        @name     = name.to_s
        @x        = x.to_f
        @y        = y.to_f
        @w        = w.to_f
        @h        = h.to_f
        @canvas   = canvas.to_s
        @scale    = scale
        @origin_x = 0.0
        @origin_y = 0.0
        @frame    = false   # draw a thin box round the window
      end

      def scale_factor
        PlanDoc.scale_factor(@scale)
      end

      def centre
        [@x + @w / 2.0, @y + @h / 2.0]
      end
      alias center centre

      # Model inches -> paper inches on this sheet.
      def model_to_paper(mx, my)
        s = scale_factor
        cx, cy = centre
        [cx + (mx.to_f - @origin_x) * s, cy + (my.to_f - @origin_y) * s]
      end

      # Paper inches -> model inches.
      def paper_to_model(px, py)
        s = scale_factor
        cx, cy = centre
        [@origin_x + (px.to_f - cx) / s, @origin_y + (py.to_f - cy) / s]
      end

      # Which slice of the model this window can show, as model inches.
      def model_window
        s = scale_factor
        half_w = (@w / 2.0) / s
        half_h = (@h / 2.0) / s
        [@origin_x - half_w, @origin_y - half_h,
         @origin_x + half_w, @origin_y + half_h]
      end

      # Put the middle of the drawing in the middle of the window.
      def centre_on!(bounds)
        return self unless bounds
        @origin_x = (bounds[0] + bounds[2]) / 2.0
        @origin_y = (bounds[1] + bounds[3]) / 2.0
        self
      end
      alias center_on! centre_on!

      def fits?(bounds)
        return true unless bounds
        s = scale_factor
        (bounds[2] - bounds[0]) * s <= @w + 1e-9 &&
          (bounds[3] - bounds[1]) * s <= @h + 1e-9
      end

      # REPORTING ONLY. The biggest scale in the list that would hold this
      # drawing. Never changes the view - the user chooses.
      def fit_scale(bounds)
        return @scale unless bounds
        mw = bounds[2] - bounds[0]
        mh = bounds[3] - bounds[1]
        return nil if mw <= 0 && mh <= 0
        row = SCALES.find do |(_label, per_foot)|
          s = per_foot / 12.0
          mw * s <= @w + 1e-9 && mh * s <= @h + 1e-9
        end
        row && row[0]
      end

      def to_h
        { name: @name, x: @x, y: @y, w: @w, h: @h, canvas: @canvas,
          scale: @scale, origin_x: @origin_x, origin_y: @origin_y,
          frame: @frame }
      end
    end

    # ------------------------------------------------------------------ page

    class Page
      include HasLayers
      attr_reader :name, :width, :height
      attr_accessor :number, :size_name, :orientation, :margin, :views

      def initialize(name, size_name = DEFAULT_PAGE_SIZE,
                     orientation = DEFAULT_ORIENTATION, number = nil)
        @name        = name.to_s
        @number      = number
        @views       = []
        @margin      = DEFAULT_MARGIN
        resize!(size_name, orientation)
      end

      def resize!(size_name, orientation = @orientation || DEFAULT_ORIENTATION)
        @size_name   = size_name
        @orientation = orientation.to_sym
        @width, @height = PlanDoc.page_size(size_name, @orientation)
        self
      end

      # The rectangle inside the margins: [x, y, w, h] in paper inches.
      def frame
        [@margin, @margin, @width - 2 * @margin, @height - 2 * @margin]
      end

      def add_view(name, x, y, w, h, canvas, scale = DEFAULT_SCALE)
        v = View.new(name, x, y, w, h, canvas, scale)
        @views << v
        v
      end

      def view(name)
        @views.find { |v| v.name == name.to_s }
      end

      def to_h
        { name: @name, number: @number, size_name: @size_name,
          orientation: @orientation, width: @width, height: @height,
          margin: @margin, views: @views.map(&:to_h),
          layers: layers.map(&:to_h) }
      end
    end

    # -------------------------------------------------------------- document

    class Document
      attr_reader :pages, :canvases
      attr_accessor :project_name, :job_address, :logo_path, :date, :units,
                    :schedules

      def initialize(project_name = '')
        @project_name = project_name.to_s
        @job_address  = ''
        @logo_path    = nil
        @date         = nil
        @units        = :inch
        @pages        = []
        @canvases     = []
        # plain rows for the door/window tables, filled by plan_canvas
        @schedules    = { 'doors' => [], 'windows' => [] }
      end

      def canvas(name)
        found = @canvases.find { |c| c.name == name.to_s }
        return found if found
        made = Canvas.new(name)
        @canvases << made
        made
      end

      def canvas?(name)
        !@canvases.find { |c| c.name == name.to_s }.nil?
      end

      def add_page(name, size_name = DEFAULT_PAGE_SIZE,
                   orientation = DEFAULT_ORIENTATION)
        p = Page.new(name, size_name, orientation, @pages.length + 1)
        @pages << p
        p
      end

      def page(name)
        @pages.find { |pg| pg.name == name.to_s }
      end

      def to_h
        { version: VERSION, project_name: @project_name,
          job_address: @job_address, logo_path: @logo_path, date: @date,
          units: @units, schedules: @schedules,
          canvases: @canvases.map(&:to_h), pages: @pages.map(&:to_h) }
      end
    end

    # ----------------------------------------------------------- title block

    TITLE_LAYER  = 'TITLE'  unless const_defined?(:TITLE_LAYER, false)
    TITLE_HEIGHT = 1.1      unless const_defined?(:TITLE_HEIGHT, false)

    # Draws the user's own title block along the bottom of the sheet, in paper
    # inches. Left: job address over scale, each on a rule. Right: the logo.
    # Between them: sheet number + name, and the date.
    #
    # scale_from: the name of the view whose scale is printed. nil = blank.
    def self.build_title_block!(page, doc, opts = {})
      lay = page.layer(TITLE_LAYER)
      lay.shapes.clear

      fx, fy, fw, _fh = page.frame
      h   = (opts[:height] || TITLE_HEIGHT).to_f
      top = fy + h

      # the rule that separates the title block from the drawing
      lay.line(fx, top, fx + fw, top, weight: 0.03)

      txt_h  = opts[:text_height] || 0.10
      lab_h  = opts[:label_height] || 0.085
      left   = fx + 0.15
      col_w  = opts[:label_width] || 2.6

      view = opts[:scale_from] ? page.view(opts[:scale_from]) : page.views.first
      # a sheet with no drawing on it (a table sheet) is not to any scale
      scale_str = view ? PlanDoc.scale_text(view.scale) : 'N.T.S.'

      rows = [
        ['Job address :', doc.job_address.to_s],
        ['Scale :',       scale_str]
      ]
      rows.each_with_index do |(label, value), i|
        y = top - 0.34 - i * 0.30
        lay.text(label, left, y, h: lab_h, bold: true)
        lay.text(value, left + 0.95, y, h: txt_h)
        lay.line(left, y - 0.08, left + col_w, y - 0.08, weight: 0.012)
      end

      # sheet number + name, and the date
      mid = fx + fw * 0.55
      if opts[:sheet_number] || opts[:sheet_title]
        lay.text([opts[:sheet_number], opts[:sheet_title]].compact.join('  '),
                 mid, top - 0.34, h: txt_h, bold: true)
      end
      lay.text(doc.date.to_s, mid, top - 0.64, h: lab_h) if doc.date

      # the logo, bottom right
      logo_w = opts[:logo_width] || 2.2
      logo_x = fx + fw - logo_w
      if doc.logo_path
        lay.image(doc.logo_path, logo_x, fy + 0.15, logo_w, h - 0.35)
      else
        lay.text('VISUALIZE', logo_x, top - 0.55, h: 0.24, bold: true,
                 tracking: 0.06)
        lay.text('by Dror', logo_x + logo_w - 0.95, top - 0.80, h: 0.13,
                 italic: true)
      end

      lay
    end

    # --------------------------------------------------------------- helpers

    # A ready empty sheet: page + title block + one empty view window.
    def self.new_sheet(doc, name, opts = {})
      page = doc.add_page(name,
                          opts[:size] || DEFAULT_PAGE_SIZE,
                          opts[:orientation] || DEFAULT_ORIENTATION)
      fx, fy, fw, fh = page.frame
      tb = (opts[:title_height] || TITLE_HEIGHT).to_f
      pad = opts[:view_pad] || 0.25
      page.add_view(opts[:view_name] || 'PLAN',
                    fx + pad, fy + tb + pad,
                    fw - 2 * pad, fh - tb - 2 * pad,
                    opts[:canvas] || 'MODEL',
                    opts[:scale] || DEFAULT_SCALE)
      build_title_block!(page, doc, opts)
      page
    end
  end
end
