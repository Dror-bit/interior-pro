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
require File.join(File.dirname(__FILE__), 'plan_geometry') unless
  defined?(InteriorPro::PlanGeometry)

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
        @ang += Math.atan2(p1.y.to_f - p0.y.to_f, p1.x.to_f - p0.x.to_f)
        @pos = @pos.transform(t)
        # to_f is not decoration: SketchUp hands back Length objects, and a
        # Length turns into a STRING in JSON. That is what made the sheet
        # window come up blank on 2026-08-12.
        @shape[:x]        = @pos.x.to_f
        @shape[:y]        = @pos.y.to_f
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
        cx = center.x.to_f
        cy = center.y.to_f
        r  = radius.to_f
        pts = (0...n).map do |i|
          a = 2.0 * Math::PI * i / n
          [cx + Math.cos(a) * r, cy + Math.sin(a) * r]
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
          # numbers!: SketchUp Lengths in, plain Floats out (see plan_doc.rb)
          keep.each { |s| lay.shapes << lay.numbers!(s) }
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
    def self.build(model, doc, canvas_name = 'MODEL', opts = {})
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

      # Hand-drawn SketchUp geometry, if the user picked any. Its own layer,
      # so turning it off leaves everything else exactly as it was.
      if defined?(InteriorPro::PlanGeometry)
        safely { InteriorPro::PlanGeometry.build!(model, cv, opts[:site] || {}) }
      end
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

      build(model, doc, 'MODEL', site: opts[:site] || {})

      st = {
        'size'            => opts[:size] || pd::DEFAULT_PAGE_SIZE,
        'orientation'     => (opts[:orientation] || :landscape).to_s,
        'scale'           => opts[:scale] || pd::DEFAULT_SCALE,
        'sheet_number'    => opts[:sheet_number],
        'sheet_title'     => opts[:sheet_title],
        'tables_own_page' => opts.key?(:tables_own_page) ? opts[:tables_own_page] : true,
        'images'          => Array(opts[:images]),
        'image_title'     => opts[:image_title],
        'marks'           => Array(opts[:marks]),
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

      # The hand-drawn marks are redrawn here rather than when the model is
      # read, so a dimension the user just stretched shows up on the very next
      # frame instead of waiting for the next trip through SketchUp.
      apply_marks!(doc, st)

      size   = st['size'] || pd::DEFAULT_PAGE_SIZE
      orient = (st['orientation'] || 'landscape').to_sym
      title  = st['sheet_title'].to_s.empty? ? 'FLOOR PLAN' : st['sheet_title'].to_s
      num    = st['sheet_number'].to_s.empty? ? 'A-101' : st['sheet_number'].to_s

      # The plan sheet thrown away with the x in the page list (2026-08-19).
      # It is the only page that needs a flag of its own: a picture sheet is
      # removed by taking the picture out of st['images'] and the schedules
      # sheet by hiding its layer, and both of those already existed. The plan
      # sheet is built out of nothing, so the only way to not have one is to
      # be told not to build it.
      drop_plan = st['drop_plan'] == true

      p1 = nil
      unless drop_plan
        p1 = pd.new_sheet(doc, title,
                          size: size, orientation: orient,
                          scale: st['scale'] || pd::DEFAULT_SCALE, canvas: 'MODEL',
                          sheet_number: num, sheet_title: title)
        p1.kind = 'plan'
        p1.sheet_number = num
      end

      own       = st['tables_own_page'] != false
      tables_on = pt.any?(doc) && !hidden.include?(pt::LAYER)
      # With no plan sheet there is nothing to tuck the tables into a corner
      # of, so they take a sheet of their own whatever the setting says.
      own = true if p1.nil?

      tbl_zoom = text_pct(st, 'tables') / 100.0

      if tables_on && !own && p1
        pt.place!(p1, doc, zoom: tbl_zoom)
        shrink_view_for_tables!(p1, doc, hidden, tbl_zoom)
      end

      if p1
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
      end

      # Sheet numbers run on from the plan. With the plan sheet thrown away
      # nobody has claimed A-101 yet, so the first sheet that IS built takes
      # it - otherwise the set would start at A-102 with a hole in front of it.
      last  = num
      taken = !p1.nil?
      if tables_on && own
        last = taken ? next_sheet_number(last) : num
        taken = true
        p2 = doc.add_page('SCHEDULES', size, orient)
        pt.place!(p2, doc, full: true, zoom: tbl_zoom)
        pd.build_title_block!(p2, doc, sheet_number: last,
                                       sheet_title: 'SCHEDULES')
        p2.kind = 'schedules'
        p2.sheet_number = last
      end

      # One picture, one sheet, in the order the user put them in. Renders come
      # after the drawings, so A-101 stays the floor plan whatever he adds.
      img_title = st['image_title'].to_s.empty? ? 'RENDERING' : st['image_title'].to_s
      Array(st['images']).each_with_index do |path, i|
        next if path.to_s.empty?
        last = taken ? next_sheet_number(last) : num
        taken = true
        pg = pd.new_image_sheet(doc, "#{img_title} #{i + 1}", path,
                                size: size, orientation: orient,
                                sheet_number: last, sheet_title: img_title)
        pg.kind = 'image'
        pg.ref  = i                 # which picture in the user's list this is
        pg.sheet_number = last
      end

      # Belt and braces (2026-08-19). The window refuses to throw away the last
      # remaining sheet, but a model saved in some other state must never open
      # onto nothing - a set with no pages draws a blank window and PDF export
      # refuses to print at all. If it somehow happens, the plan comes back.
      if doc.pages.empty?
        puts '[Sheet] every page was dropped - putting the plan sheet back'
        pb = pd.new_sheet(doc, title,
                          size: size, orientation: orient,
                          scale: st['scale'] || pd::DEFAULT_SCALE, canvas: 'MODEL',
                          sheet_number: num, sheet_title: title)
        pb.kind = 'plan'
        pb.sheet_number = num
        pb.views.first.centre_on!(doc.canvas('MODEL').bounds)
      end

      # LAST, after every page exists.
      #
      # doc.pages.clear runs at the top of this method and the pages are built
      # below it, so a sizing pass at the top would only ever see the canvas -
      # the title block and the schedules would be named and resized on a set
      # of pages that is about to be thrown away, and the settings would look
      # like they did nothing.
      apply_text_scale!(doc, st)
      # One label's own settings come after its group's, so they win.
      apply_text_overrides!(doc, st)

      apply_visibility!(doc, hidden)
      doc
    end

    # --------------------------------------------- dimensions and notes by hand
    #
    # The plan already dimensions itself. This is the other half: a line the
    # user stretches between two points he chose, and a word written where he
    # wants it. Without them the free geometry he traces is only a picture
    # (2026-08-14).
    #
    # They live in MODEL inches on the canvas, not on the paper, so they sit on
    # the thing they describe: move the plan, change the scale, change the page
    # size, and the dimension stays on the wall it measures.
    #
    # The text height is the same 5 model inches the automatic dimensions use,
    # so a hand-drawn one and a machine-drawn one look like the same drawing.
    MARK_LAYER = 'NOTES' unless const_defined?(:MARK_LAYER, false)
    MARK_TICK  = 4.0 unless const_defined?(:MARK_TICK, false)

    # NOT PlanGenerator::DIM_TEXT_H, which is what everyone writes first and
    # what rt52 caught (2026-08-14). The constant is declared inside
    # `class << self`, so it belongs to the singleton class and the obvious
    # spelling raises NameError. It used to be swallowed by a rescue that
    # returned 5.0 - the same number DIM_TEXT_H happens to hold, so nothing
    # looked wrong, and the day anyone changed it the hand-drawn dimensions
    # would have quietly stayed behind. It says so out loud now.
    def self.mark_text_h
      InteriorPro::PlanGenerator.singleton_class.const_get(:DIM_TEXT_H)
    rescue StandardError, NameError => e
      puts "[PlanCanvas] cannot read the dimension text height (#{e.class}), using 5.0"
      5.0
    end

    # --------------------------------------------------- how big the words are
    #
    # (2026-08-17) The user asked to choose the size of the writing on the
    # sheet. It turns out nothing new has to be measured: every text already
    # arrives carrying its own height - the Recorder takes it straight off
    # add_3d_text - and already sits on a NAMED layer, because build sets
    # rec.layer_name before each group. So the sizes are changed HERE, in one
    # pass over the finished document, and plan_generator is not touched at
    # all. The window and the PDF read the same document, so they cannot end
    # up disagreeing about how big a room name is.
    #
    # Sizes are PERCENTAGES, 100 being the drawing as it has always looked.
    # The user should not have to think in model inches to decide that a tag
    # is too small.
    TEXT_GROUPS = {
      # the numbers on the automatic dimensions AND on the hand-drawn ones,
      # which are meant to look like the same drawing
      'dims'  => [LAYERS[:dimensions], MARK_LAYER],
      # ROOM 2 and its 42 SF
      'rooms' => [LAYERS[:rooms]],
      # W101, D103
      'tags'  => [LAYERS[:doors], LAYERS[:windows]]
    }.freeze unless const_defined?(:TEXT_GROUPS, false)

    # Small enough to be unreadable and large enough to cover the plan are both
    # the user's business, but a zero or a minus sign is a typo, not a choice.
    TEXT_PCT_MIN = 25.0  unless const_defined?(:TEXT_PCT_MIN, false)
    TEXT_PCT_MAX = 400.0 unless const_defined?(:TEXT_PCT_MAX, false)

    def self.text_pct(st, key)
      raw = (st['text_scale'] || st[:text_scale] || {})
      v   = (raw[key] || raw[key.to_sym])
      return 100.0 if v.nil?
      v = v.to_f
      return 100.0 if v <= 0
      [[v, TEXT_PCT_MIN].max, TEXT_PCT_MAX].min
    end

    # THE ORIGINAL HEIGHT IS KEPT IN :h0, and every size is worked out from
    # that, never from the height as it stands.
    #
    # layout_pages! runs on every click in the window. Multiplying :h by the
    # percentage each time would compound: the user types 110 once and then
    # watches the writing swell every time he touches a control, with no way
    # back short of closing the window. Deriving from :h0 makes running this
    # twice the same as running it once.
    def self.apply_text_scale!(doc, st)
      want = {}
      TEXT_GROUPS.each do |key, layers|
        f = text_pct(st, key) / 100.0
        layers.each { |name| want[name] = f }
      end
      (doc.canvases + doc.pages).each do |holder|
        holder.layers.each do |lay|
          name_texts!(lay)
          f = want[lay.name]
          next unless f
          lay.shapes.each do |s|
            next unless s[:type] == :text
            s[:h0] = s[:h].to_f unless s.key?(:h0)
            s[:h]  = s[:h0] * f
          end
        end
      end
      doc
    end

    # ------------------------------------------------- a name for every text
    #
    # (2026-08-17) The user wants to double-click ONE label and change it -
    # bigger, bold, later a colour. That needs the override to find its way
    # back to the same label after the sheet is redrawn, and the automatic
    # labels are thrown away and rebuilt from the model every single time.
    # Without a name there is nothing to hang the choice on: he formats W101,
    # presses "read the model again", and it comes back plain.
    #
    # THE NAME IS layer | the words | which one, counting from the top of the
    # layer among labels with the SAME words.
    #
    # This was chosen because it costs plan_generator nothing. The alternative
    # was to thread an id down through every draw_ method, and this file's
    # whole design is that the generator does not know the sheet exists.
    #
    # WHAT IT CANNOT DO, said out loud rather than discovered later:
    #   - Rename a room and its label is a new label; the formatting stays
    #     behind on a name nothing answers to any more.
    #   - Two dimensions that read the same, say two walls both 12'-0", are
    #     told apart only by their order down the layer. Add a wall between
    #     them and the formatting swaps.
    # Both are recoverable in one click - format it again - and neither can
    # lose anything but the formatting itself. A sturdier name means teaching
    # the generator about ids, and that is a bigger change than this earns.
    def self.text_key(layer_name, text, nth)
      "#{layer_name}|#{text}|#{nth}"
    end

    def self.name_texts!(lay)
      seen = Hash.new(0)
      lay.shapes.each do |s|
        next unless s[:type] == :text
        t = s[:text].to_s
        seen[t] += 1
        s[:key] = text_key(lay.name, t, seen[t])
      end
      lay
    end

    # One label's own settings, which beat whatever its group says.
    #
    #   st['text_marks'] = { "ROOMS|ROOM 2|1" => { 'pct' => 150, 'bold' => true } }
    #
    # 'pct' is a percentage of that label's ORIGINAL height, exactly like the
    # group numbers, so the two cannot drift into different units. An override
    # REPLACES its group's percentage rather than multiplying with it: the user
    # who typed 150 on this label means 150, not 150 of whatever the group
    # happened to be set to that day.
    def self.apply_text_overrides!(doc, st)
      marks = st['text_marks'] || st[:text_marks]
      return doc unless marks.is_a?(Hash) && !marks.empty?
      (doc.canvases + doc.pages).each do |holder|
        holder.layers.each do |lay|
          lay.shapes.each do |s|
            next unless s[:type] == :text
            o = marks[s[:key]]
            next unless o.is_a?(Hash)
            s[:h0] = s[:h].to_f unless s.key?(:h0)
            pct = (o['pct'] || o[:pct]).to_f
            s[:h] = s[:h0] * ([[pct, TEXT_PCT_MIN].max, TEXT_PCT_MAX].min / 100.0) if pct > 0
            b = o.key?('bold')   ? o['bold']   : o[:bold]
            i = o.key?('italic') ? o['italic'] : o[:italic]
            s[:bold]   = !!b unless b.nil?
            s[:italic] = !!i unless i.nil?
            # Where he shoved it (2026-08-19). The user could already pick any
            # ONE label on the sheet and change its size; what he could not do
            # was move it, and the labels he most wanted to move - the
            # dimensions the plugin draws on the walls by itself - are not
            # marks and so had nothing to grab at all.
            #
            # x0/y0 are kept the way h0 is: the position the label was BUILT
            # at, so a second pass over the same document shifts it once and
            # not twice. The plan is redrawn from the model on every change,
            # and without this the label would walk across the sheet.
            dx = (o.key?('dx') ? o['dx'] : o[:dx]).to_f
            dy = (o.key?('dy') ? o['dy'] : o[:dy]).to_f
            if dx != 0.0 || dy != 0.0
              s[:x0] = s[:x].to_f unless s.key?(:x0)
              s[:y0] = s[:y].to_f unless s.key?(:y0)
              s[:x] = s[:x0] + dx
              s[:y] = s[:y0] + dy
            end
          end
        end
      end
      doc
    end

    def self.apply_marks!(doc, st)
      cv  = doc.canvas('MODEL')
      lay = cv.layer(MARK_LAYER)
      lay.shapes.clear
      Array(st['marks']).each do |m|
        h = m['t'] || m[:t]
        case h.to_s
        when 'dim'  then safely { draw_mark_dim(lay, m) }
        when 'note' then safely { draw_mark_note(lay, m) }
        end
      end
      cv
    end

    def self.mark_num(m, key)
      (m[key.to_s] || m[key.to_sym]).to_f
    end

    # How far a hand dimension's LINE stands off the two points that were
    # clicked (2026-08-19). The user's complaint, in his own words:
    # "המידה יושבת על האובייקט" - it lands on top of the wall it measures and
    # there is nothing to read and nothing to grab.
    #
    # `off` is that distance, measured across the line, signed: positive is to
    # the LEFT of start -> end, so which side it goes to follows the direction
    # he drew it. No `off` on the mark means 0 - dead on the two points, which
    # is where every dimension drawn before today sits, so old drawings open
    # unchanged.
    #
    # WITNESS_GAP leaves the little breath between the object and the start of
    # the witness line that a drafted dimension has; WITNESS_OVER is how far
    # the witness line carries on past the dimension line.
    WITNESS_GAP  = 0.35 unless const_defined?(:WITNESS_GAP, false)  # of the tick
    WITNESS_OVER = 0.75 unless const_defined?(:WITNESS_OVER, false) # of the tick

    # The two ends of the DIMENSION LINE - the clicked points pushed off by
    # `off`. Pure, and the one place that knows it: the ticks, the number and
    # the window's hit test all read the line from here.
    def self.dim_line(m)
      x1 = mark_num(m, :x1); y1 = mark_num(m, :y1)
      x2 = mark_num(m, :x2); y2 = mark_num(m, :y2)
      dx = x2 - x1
      dy = y2 - y1
      len = Math.hypot(dx, dy)
      return [x1, y1, x2, y2, 0.0, 0.0, len] if len < 1.0e-9
      ux = dx / len
      uy = dy / len
      off = mark_has?(m, :off) ? mark_num(m, :off) : 0.0
      nx = -uy * off
      ny = ux * off
      [x1 + nx, y1 + ny, x2 + nx, y2 + ny, ux, uy, len]
    end

    def self.draw_mark_dim(lay, m)
      x1 = mark_num(m, :x1); y1 = mark_num(m, :y1)
      x2 = mark_num(m, :x2); y2 = mark_num(m, :y2)
      ax, ay, bx, by, ux, uy, len = dim_line(m)
      return if len < 0.5                       # a stray double click, not a line
      nx = -uy                                  # across the line
      ny = ux

      lay.line(ax, ay, bx, by)
      # a slash through each end, the way a plan dimension is ticked
      t = MARK_TICK / 2.0
      [[ax, ay], [bx, by]].each do |px, py|
        tx = (ux + nx) * t
        ty = (uy + ny) * t
        lay.line(px - tx, py - ty, px + tx, py + ty)
      end

      # The witness lines - the thin pair running from the thing being measured
      # out to the dimension line. Only drawn when the dimension actually
      # stands off something; on top of the object they would be zero long.
      off = mark_has?(m, :off) ? mark_num(m, :off) : 0.0
      if off.abs > MARK_TICK * WITNESS_GAP
        sgn = off.negative? ? -1.0 : 1.0
        g   = MARK_TICK * WITNESS_GAP * sgn
        o   = MARK_TICK * WITNESS_OVER * sgn
        [[x1, y1, ax, ay], [x2, y2, bx, by]].each do |px, py, qx, qy|
          lay.line(px + nx * g, py + ny * g, qx + nx * o, qy + ny * o)
        end
      end

      # Never upside down: past vertical, read it from the other side.
      ang = Math.atan2(y2 - y1, x2 - x1) * 180.0 / Math::PI
      ang -= 180.0 while ang > 90.0
      ang += 180.0 while ang < -90.0

      h   = mark_num(m, :h)
      h   = mark_text_h if h <= 0
      lx, ly = dim_label_xy(m, h)
      lay.text(InteriorPro::PlanGenerator.send(:fmt_feet, len),
               lx, ly, h: h, align: :center, rotation: ang)
    end

    # Where a dimension's NUMBER sits (2026-08-19).
    #
    # The user asked to be able to shove it out of the way: "אני רוצה שיהיה לי
    # אפשרות להזיז אותן ימינה ושמאלה ולמטה ולמעלה, תלוי איך אני מצייר אותן
    # לאיזה כיוון" - and that last clause is the whole design.
    #
    # The offset is kept in the LINE'S OWN frame, never the sheet's:
    #   oa  along the line   - his right/left
    #   oc  across the line  - his up/down
    # so the number holds its place relative to the dimension whichever way the
    # line was drawn, and it still holds it after he drags an end somewhere
    # else. Stored in the sheet's units, inches, like every other mark number.
    #
    # No `oc` on the mark at all means h * DIM_LABEL_OFF, which is exactly
    # where every dimension has sat since they were built - so a drawing made
    # before today opens looking identical. rt81 fails if that stops being true.
    #
    # The sheet window has the same arithmetic in dimLabelXY(), because it has
    # to know where the number is before it can let him grab it. Two copies of
    # one formula is a drift risk and it is treated as one: rt81 and t50 check
    # BOTH against the same numbers, so if either side moves, one goes red.
    DIM_LABEL_OFF = 0.8 unless const_defined?(:DIM_LABEL_OFF, false)

    def self.mark_has?(m, key)
      m.key?(key.to_s) || m.key?(key.to_sym)
    rescue StandardError
      false
    end

    # Measured from the DIMENSION LINE, not from the clicked points: when the
    # dimension stands off the wall, the number goes with it (2026-08-19).
    def self.dim_label_xy(m, h = nil)
      h = mark_num(m, :h) if h.nil?
      h = mark_text_h if h.nil? || h <= 0
      ax, ay, bx, by, ux, uy, len = dim_line(m)
      mx = (ax + bx) / 2.0
      my = (ay + by) / 2.0
      return [mx, my] if len < 1.0e-9
      oa = mark_has?(m, :oa) ? mark_num(m, :oa) : 0.0
      oc = mark_has?(m, :oc) ? mark_num(m, :oc) : h * DIM_LABEL_OFF
      # across the line is (-uy, ux), the same normal the ticks are drawn on
      [mx + (ux * oa) - (uy * oc), my + (uy * oa) + (ux * oc)]
    end

    # A note is the SketchUp Text tool: words in a box, and a line with an
    # arrow running from the box to the thing being talked about. The user sent
    # a picture of it rather than describe it, which is the right way round for
    # anything that has to LOOK like something (2026-08-14).
    #
    # The box is measured, not guessed: plan_pdf already carries the real
    # Helvetica letter widths, because it has to centre every label on the
    # sheet. Feeding it model inches gives a box back in model inches.
    MARK_PAD   = 0.45 unless const_defined?(:MARK_PAD, false)    # of the text height
    MARK_ARROW = 1.6  unless const_defined?(:MARK_ARROW, false)  # ditto

    def self.text_width(str, h)
      require File.join(File.dirname(__FILE__), 'plan_pdf') unless
        defined?(InteriorPro::PlanPDF)
      pp = InteriorPro::PlanPDF
      pp.text_width(str, h / pp::CAP_RATIO)
    rescue StandardError, NameError
      str.to_s.length * h * 0.6         # only if plan_pdf is not there at all
    end

    def self.draw_mark_note(lay, m)
      txt = (m['text'] || m[:text]).to_s
      return if txt.strip.empty?
      h = mark_num(m, :h)
      h = mark_text_h if h <= 0
      x = mark_num(m, :x)
      y = mark_num(m, :y)

      lay.text(txt, x, y, h: h, align: :center)

      w   = text_width(txt, h)
      pad = h * MARK_PAD
      bw  = w / 2.0 + pad
      bh  = h / 2.0 + pad
      lay.polygon([[x - bw, y - bh], [x + bw, y - bh],
                   [x + bw, y + bh], [x - bw, y + bh]])

      # the leader, if the user pointed at something
      return unless m.key?('lx') || m.key?(:lx)
      lx = mark_num(m, :lx)
      ly = mark_num(m, :ly)

      # Two segments, not one (2026-08-14, from the user's third picture): a
      # short shoulder straight out of the label, a knee, then the slant down to
      # the thing itself. That is how SketchUp, Revit and every drawing on his
      # desk do it, and it keeps the slanted line clear of the words.
      #
      # A note written before this existed has no knee and keeps its single
      # straight line - it is still a perfectly good leader.
      knee = (m.key?('kx') || m.key?(:kx))
      if knee
        kx = mark_num(m, :kx)
        ky = mark_num(m, :ky)
        sx, sy = box_exit(x, y, bw, bh, kx, ky)
        lay.line(sx, sy, kx, ky) if Math.hypot(kx - sx, ky - sy) >= 0.5
        return if Math.hypot(lx - kx, ly - ky) < 0.5
        lay.line(kx, ky, lx, ly)
        arrow = m.key?('arrow') ? m['arrow'] : (m.key?(:arrow) ? m[:arrow] : true)
        arrow_head(lay, kx, ky, lx, ly, h * MARK_ARROW) unless arrow == false
        return
      end

      sx, sy = box_exit(x, y, bw, bh, lx, ly)
      return if Math.hypot(lx - sx, ly - sy) < 0.5
      lay.line(sx, sy, lx, ly)

      # With or without a head on the end. SketchUp's own text leader is a bare
      # line, and the user sent a picture of one - so both are offered and he
      # picks per note. A note written before this existed has no say in the
      # matter and keeps the head it already had.
      arrow = m.key?('arrow') ? m['arrow'] : (m.key?(:arrow) ? m[:arrow] : true)
      arrow_head(lay, sx, sy, lx, ly, h * MARK_ARROW) unless arrow == false
    end

    # Where the line from the middle of the box leaves the box. Without this the
    # leader would start in the middle of the words and strike them through.
    def self.box_exit(x, y, bw, bh, lx, ly)
      dx = lx - x
      dy = ly - y
      return [x, y] if dx.abs < 1e-9 && dy.abs < 1e-9
      tx = dx.abs < 1e-9 ? Float::INFINITY : bw / dx.abs
      ty = dy.abs < 1e-9 ? Float::INFINITY : bh / dy.abs
      t  = [tx, ty].min
      [x + dx * t, y + dy * t]
    end

    def self.arrow_head(lay, sx, sy, lx, ly, size)
      dx = lx - sx
      dy = ly - sy
      len = Math.hypot(dx, dy)
      return if len < 1e-9
      ux = dx / len
      uy = dy / len
      nx = -uy
      ny = ux
      back = size
      side = size * 0.38
      lay.line(lx, ly, lx - ux * back + nx * side, ly - uy * back + ny * side)
      lay.line(lx, ly, lx - ux * back - nx * side, ly - uy * back - ny * side)
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
    def self.shrink_view_for_tables!(page, doc, hidden = [], zoom = 1.0)
      v = page.views.first
      return unless v
      fx, _fy, fw, _fh = page.frame
      pad = 0.25
      right = fx + fw - pad -
              InteriorPro::PlanTables.reserved_width(doc, hidden, zoom)
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
