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
    # The drawing can be TURNED on its sheet (2026-10-07, st['rotation'], see
    # turn_texts!). false = the number is ignored and every drawing is laid
    # square to the paper, as before.
    USE_VIEW_ROTATION = true unless const_defined?(:USE_VIEW_ROTATION, false)
    # The drawing sits in a BOX he can move about the sheet and make bigger or
    # smaller (2026-10-07, st['view_box'] and st['scale_f'], see place_view_box!).
    # false = both are ignored: the box fills the sheet and the drawing is at
    # the scale picked from the list, as before.
    USE_VIEW_BOX = true unless const_defined?(:USE_VIEW_BOX, false)
    VIEW_BOX_MIN = 1.0 unless const_defined?(:VIEW_BOX_MIN, false)   # paper inches, either way
    # A PICTURE sits in a box of its own too: moved, made bigger or smaller,
    # cut from its sides, turned - and there can be more than one on a sheet,
    # on the plan sheet as well (2026-10-07, st['image_geo'] and st['pics'],
    # see place_pictures!). false = both are ignored: one picture to a sheet,
    # filling it, as before.
    USE_PIC_BOX = true unless const_defined?(:USE_PIC_BOX, false)
    PIC_MIN     = 0.5  unless const_defined?(:PIC_MIN, false)        # paper inches, either way
    # A piece of WRITING sits in a box of its own as well: put anywhere on any
    # sheet, moved, made bigger or smaller, made wider or narrower, turned
    # (2026-10-07, st['texts'], see place_texts!). false = the list is ignored
    # and no sheet carries any.
    USE_TEXT_BOX = true unless const_defined?(:USE_TEXT_BOX, false)
    # The automatic dimensions of an elevation (2026-10-08, st['image_dims'], see
    # place_elev_dims!). false = they are kept but not drawn: the picture alone.
    USE_ELEV_DIMS = true unless const_defined?(:USE_ELEV_DIMS, false)
    # The dimensions he draws on an elevation's picture with the sheet's own dimension tool (2026-10-08
    # 19:46, st['image_hand'][path] = [{ 'p' => [u1, v1, u2, v2], 'o' => 'h' | 'v', 'at' => share, 'n' => inches }],
    # shares of the picture so they follow its box). false = kept but not drawn.
    USE_PIC_DIMS = true unless const_defined?(:USE_PIC_DIMS, false)
    # The NUMBER of a dimension - and any other label - can be written over by
    # hand (2026-10-07, "אני רוצה שיהיה אפשרי לערוך את המידות - את המספרים
    # שלהם בתוך"; asked whether the words replace the number for good or sit
    # beside a number that keeps counting, he chose: they REPLACE it). false =
    # a hand dimension's `label` and a label's `text` override are ignored.
    USE_TEXT_WORDS = true unless const_defined?(:USE_TEXT_WORDS, false)
    # A box of writing can be lettered BOLD, ITALIC, UNDERLINED and in a COLOUR,
    # from the settings at the side of the sheet window (2026-10-07, "כשאני רוצה
    # להקליד פה זה לא נותן לי לשחק עם ההגדרות של הכיתוב"; st['texts'][n]['bold'],
    # 'italic', 'underline', 'color' - see text_style). false = the four are
    # ignored: plain black letters, as before.
    USE_TEXT_STYLE = true unless const_defined?(:USE_TEXT_STYLE, false)
    # The sheets go into the PDF in the order he dragged them into in the page
    # list (2026-10-07, "להחליף את מיקום הסדר של הדפים בפידיאף ע"י גרירה";
    # st['page_order'] = page keys, see page_order). The sheet numbers run in
    # that order. false = the old fixed order: plan, schedules, pictures.
    USE_PAGE_ORDER = true unless const_defined?(:USE_PAGE_ORDER, false)
    # The drawing's box turns AS A WHOLE (2026-10-07, stage 5 of the box:
    # "הקופסה כולה מסתובבת"): its frame, its clip and its handles turn with the
    # lines, about the middle of the box, and a box that would hang off the
    # margins once turned is made smaller and pushed in - the way a picture
    # is. false = the frame stays square to the paper and only the lines
    # inside it turn, as on the day the turn was built. Needs USE_VIEW_ROTATION.
    USE_BOX_TURN = true unless const_defined?(:USE_BOX_TURN, false)
    TEXT_LAYER   = 'TEXT' unless const_defined?(:TEXT_LAYER, false)
    TEXT_PT      = 24.0   unless const_defined?(:TEXT_PT, false)      # the size a new one starts at, in points
    TEXT_PT_MIN  = 4.0    unless const_defined?(:TEXT_PT_MIN, false)
    TEXT_PT_MAX  = 400.0  unless const_defined?(:TEXT_PT_MAX, false)
    TEXT_PAD     = 0.25   unless const_defined?(:TEXT_PAD, false)     # round the words, of the letter size
    TEXT_LEAD    = 1.25   unless const_defined?(:TEXT_LEAD, false)    # line to line, of the letter size
    TEXT_ASCENT  = 0.8    unless const_defined?(:TEXT_ASCENT, false)  # top of a line to its baseline, of the letter size
    TEXT_MAX_CHARS = 4000 unless const_defined?(:TEXT_MAX_CHARS, false)
    # A lettering of its own on a box of writing or a label (2026-10-07,
    # "סוגים שונים של פונטים כמו בלייאאוט"): 'font' = a family name from
    # PlanPDF.shipped_fonts (assets/FONTS). The PDF sets it in that TrueType font and the window
    # shows it in the same; both measure by the same table. Hebrew with no
    # lettering picked is set in PlanPDF.hebrew_family. false = 'font' is
    # ignored, and Hebrew prints as before (blank in the PDF).
    USE_TEXT_FONT = true unless const_defined?(:USE_TEXT_FONT, false)
    # A note's box and leader are drawn again from its words as they FINALLY
    # are (2026-10-08, see fit_notes!): the words are a label like any other
    # and take a size, a weight and a lettering from the panel at the side, so
    # the box has to fit the words he sees. false = the box is the one drawn
    # with the marks, at the built size, whatever was done to the words.
    USE_NOTE_FIT = true unless const_defined?(:USE_NOTE_FIT, false)
    # The editor's own drawing pages ("שרטוט 1", "שרטוט 2" - the tabs beside
    # "בית" in the 2D editor) can be put on sheets of their own (2026-10-07,
    # "לבחור איזה שרטוט נכנס לאיזה דף"): st['drawn'] = [{'src' => 'draft:0'}].
    # Each is a canvas DRAWN:i (the blue walls as bands, the lines, the
    # dimensions) seen whole on a sheet of kind 'drawing'. false = no such
    # sheets, whatever was saved.
    USE_DRAWN_SHEETS = true unless const_defined?(:USE_DRAWN_SHEETS, false)
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
      # the editor's own drawing pages, each a canvas of its own (2026-10-07)
      build_drawn!(doc, draft_pages(model), opts[:drawn]) if USE_DRAWN_SHEETS

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

      # The writing is put back the way it was built before anything else
      # looks at it; it is turned again, for the angle of THIS pass, at the
      # very end. See turn_texts!.
      unturn_texts!(doc)
      rot = view_rotation(st)

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

      # The order the sheets go in, worked out BEFORE any is built, because
      # each sheet's number is written into its title block as it is built.
      # The first sheet in the order takes the plan's number (A-101) and each
      # after it the next one - with nothing dragged that is exactly the old
      # numbering, the plan sheet thrown away included.
      present = []
      present << 'plan' unless drop_plan
      if pt.any?(doc) && !hidden.include?(pt::LAYER) && (st['tables_own_page'] != false || drop_plan)
        present << 'schedules'
      end
      drawn_list(st, doc).each { |dr| present << "drawing:#{dr[:j]}" }
      Array(st['images']).each_with_index { |path, i| present << "image:#{i}" unless path.to_s.empty? }
      order = page_order(st, present)
      nums  = {}
      order.each_with_index { |k, i| nums[k] = i.zero? ? num : next_sheet_number(nums[order[i - 1]]) }
      # and a picture sheet is named by its place too: the one dragged to the
      # front of the pictures is RENDERING 1 (2026-10-07, "אם דף 2 עלה להיות
      # במקום דף 1 הוא עכשיו דף אחד"). Switched off: by its place in his list.
      img_n = {}
      order.select { |k| k.start_with?('image:') }.each_with_index { |k, j| img_n[k] = j + 1 } if USE_PAGE_ORDER

      p1 = nil
      unless drop_plan
        p1 = pd.new_sheet(doc, title,
                          size: size, orientation: orient,
                          scale: st['scale'] || pd::DEFAULT_SCALE, canvas: 'MODEL',
                          scale_free: view_scale_free(st),
                          sheet_number: nums['plan'] || num, sheet_title: title)
        p1.kind = 'plan'
        p1.sheet_number = nums['plan'] || num
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
        # what the margins, the title block and the tables leave: the box may not leave it
        p1.view_area = [v.x, v.y, v.w, v.h]
        place_view_box!(v, st, p1.view_area, rot)
        v.rotation = rot
        v.box_turn = USE_BOX_TURN && USE_VIEW_ROTATION
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
        last = nums['schedules'] || (taken ? next_sheet_number(last) : num)
        taken = true
        p2 = doc.add_page('SCHEDULES', size, orient)
        pt.place!(p2, doc, full: true, zoom: tbl_zoom)
        pd.build_title_block!(p2, doc, sheet_number: last,
                                       sheet_title: 'SCHEDULES')
        p2.kind = 'schedules'
        p2.sheet_number = last
      end

      # The editor's drawings, one a sheet, after the schedules and before the
      # pictures (2026-10-07). Each is seen whole, in the middle of its sheet,
      # at the biggest scale from the list that holds it; the sheet is named
      # after the drawing ("שרטוט 1") and numbered on from the plan.
      drawn_list(st, doc).each do |dr|
        j = dr[:j]
        cvn = dr[:canvas]
        last = nums["drawing:#{j}"] || (taken ? next_sheet_number(last) : num)
        taken = true
        pg = pd.new_sheet(doc, dr[:name], size: size, orientation: orient,
                          scale: st['scale'] || pd::DEFAULT_SCALE, canvas: cvn,
                          sheet_number: last, sheet_title: dr[:name])
        pg.kind = 'drawing'
        pg.ref  = j
        pg.sheet_number = last
        dv = pg.views.first
        db = doc.canvas(cvn).bounds
        if db
          fs = dv.fit_scale(db)
          dv.scale = fs if fs
          dv.centre_on!(db)
        end
      end

      # One picture, one sheet, in the order the user put them in. Renders come
      # after the drawings, so A-101 stays the floor plan whatever he adds.
      img_title = st['image_title'].to_s.empty? ? 'RENDERING' : st['image_title'].to_s
      # a picture with a name of its own (2026-10-08, the elevations: "Room 2 - A"):
      # st['image_titles'] by path. Named that way it is not numbered.
      own_titles = st['image_titles'].is_a?(Hash) ? st['image_titles'] : {}
      Array(st['images']).each_with_index do |path, i|
        next if path.to_s.empty?
        last = nums["image:#{i}"] || (taken ? next_sheet_number(last) : num)
        taken = true
        own = own_titles[path.to_s].to_s
        t_sheet = own.empty? ? img_title : own
        t_page = own.empty? ? "#{img_title} #{img_n["image:#{i}"] || i + 1}" : own
        pg = pd.new_image_sheet(doc, t_page, path,
                                size: size, orientation: orient,
                                sheet_number: last, sheet_title: t_sheet)
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
        pb.views.first.rotation = rot
        pb.views.first.box_turn = USE_BOX_TURN && USE_VIEW_ROTATION
        pb.views.first.centre_on!(doc.canvas('MODEL').bounds)
      end

      # and the sheets stand in his order (nothing after this cares where a sheet is)
      sort_pages!(doc, order)

      # every picture that has a box of its own goes into it, on its sheet
      place_pictures!(doc, st)
      # the elevations' own dimensions, over their pictures - BEFORE the sizing passes, so
      # each number gets a name (name_texts!) and can be picked in the window like any label;
      # its size, weight and colour are ONE setting for all of them (ELEV_SHARED_KEY)
      place_elev_dims!(doc, st)

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
      # and a note's box is drawn again around its words as they are now
      fit_notes!(doc, st)
      # and now the writing is turned, or held level, for this angle
      turn_texts!(doc, rot)
      # The writing he put on the sheets in boxes of its own. AFTER the sizing
      # passes above, on purpose: those name every piece of writing so it can
      # be picked on its own, and a line of a box is not picked on its own -
      # the box is.
      place_texts!(doc, st)

      apply_visibility!(doc, hidden)
      doc
    end

    # ------------------------------------------ the editor's drawings on sheets
    #
    # 2026-10-07. The 2D editor has pages of its own beside the house
    # ("שרטוט 1", "שרטוט 2": blue walls that never go to 3D, lines, dimensions),
    # saved on the model in plan_draft. He asked to choose which drawing goes
    # on which sheet. So st['drawn'] = [{'src' => 'draft:0'}, ...]: each entry
    # is a sheet of kind 'drawing' (page key 'drawing:j', j its place in the
    # list - thrown away and renumbered like a picture sheet), and each
    # editor page named in it is read into a canvas 'DRAWN:i'.

    # The editor's pages out of the draft on the model: [{name, pending,
    # sketches, dims}], or [] (no draft, no pages, a draft that cannot be read).
    def self.draft_pages(model)
      raw = model.respond_to?(:get_attribute) ? model.get_attribute('InteriorPro', 'plan_draft') : nil
      return [] if raw.to_s.empty?
      d = JSON.parse(raw.to_s)
      Array(d['pages']).each_with_index.map do |pg, i|
        next nil unless pg.is_a?(Hash)
        { i: i, name: (pg['name'].to_s.strip.empty? ? "שרטוט #{i + 1}" : pg['name'].to_s.strip),
          pending: Array(pg['pending']), sketches: Array(pg['sketches']), dims: Array(pg['dims']) }
      end.compact
    rescue StandardError => e
      puts "[PlanCanvas] draft_pages: #{e.class}: #{e.message}"
      []
    end

    # What the window offers: [{i, name}] - the editor's pages by name.
    def self.draft_names(model)
      draft_pages(model).map { |p| { 'i' => p[:i], 'name' => p[:name] } }
    end

    # The sheets asked for, each with the canvas it shows - only those whose
    # drawing exists (a page deleted in the editor leaves no sheet).
    def self.drawn_list(st, doc)
      return [] unless USE_DRAWN_SHEETS
      # (j = its place in the saved list - the sheet's ref and key, so the x
      # in the page list throws away the right one even past an entry that
      # made no sheet)
      Array(st['drawn'] || st[:drawn]).each_with_index.map do |dr, j|
        next nil unless dr.is_a?(Hash)
        src = (dr['src'] || dr[:src]).to_s
        next nil unless src =~ /\Adraft:(\d+)\z/
        cvn = "DRAWN:#{$1}"
        next nil unless doc.canvas?(cvn)
        { src: src, canvas: cvn, name: doc.canvas(cvn).drawn_name.to_s, j: j }
      end.compact
    end

    # The canvases: every editor page a sheet asks for (wanted = st['drawn'];
    # nil = all of them). Blue walls are bands (plan_editor's bandQuad:
    # 'left' = the thickness to the left of start -> end), lines are
    # polylines, the editor's dimension tags are drawn by the same routine
    # as a hand dimension on the plan.
    def self.build_drawn!(doc, pages, wanted = nil)
      want = wanted.is_a?(Array) ? wanted.map { |d| d.is_a?(Hash) ? (d['src'] || d[:src]).to_s[/\Adraft:(\d+)\z/, 1] : nil }.compact.map(&:to_i) : nil
      pages.each do |pg|
        next if want && !want.include?(pg[:i])
        cv = doc.canvas("DRAWN:#{pg[:i]}")
        cv.layers.clear
        cv.drawn_name = pg[:name] if cv.respond_to?(:drawn_name=)
        walls = cv.layer(LAYERS[:walls])
        pg[:pending].each do |w|
          next unless w.is_a?(Hash)
          sx, sy, ex, ey, th = %w[sx sy ex ey th].map { |k| w[k].to_f }
          dx = ex - sx
          dy = ey - sy
          len = Math.hypot(dx, dy)
          next if len < 0.01 || th <= 0
          ux = dx / len
          uy = dy / len
          nx = -uy
          ny = ux
          ha = w['ha'].to_s
          pq = ha == 'left' ? [th, 0.0] : (ha == 'right' ? [0.0, -th] : [th / 2.0, -th / 2.0])
          pts = [[sx + nx * pq[0], sy + ny * pq[0]], [ex + nx * pq[0], ey + ny * pq[0]],
                 [ex + nx * pq[1], ey + ny * pq[1]], [sx + nx * pq[1], sy + ny * pq[1]]]
          walls.polygon(pts, fill: (w['cat'].to_s == 'interior' ? [205, 205, 205] : [64, 64, 64]), weight: 0.012)
        end
        lines = cv.layer(LAYERS[:sketch])
        pg[:sketches].each do |k|
          next unless k.is_a?(Hash) && k['pts'].is_a?(Array) && k['pts'].length >= 4
          pts = k['pts'].each_slice(2).map { |x, y| [x.to_f, y.to_f] }
          wt = k['weight'].to_f
          wt = wt > 0 ? [[wt * 0.006, 0.006].max, 0.06].min : 0.012
          lines.polyline(pts, weight: wt, closed: k['closed'] == true)
        end
        dims = cv.layer(LAYERS[:dimensions])
        pg[:dims].each do |d|
          next unless d.is_a?(Hash)
          m = { t: 'dim', x1: d['x1'].to_f, y1: d['y1'].to_f, x2: d['x2'].to_f, y2: d['y2'].to_f, off: d['off'].to_f }
          safely { draw_mark_dim(dims, m) }
        end
      end
      doc
    end

    # --------------------------------------------- the order of the sheets
    #
    # 2026-10-07. He drags a sheet up or down the page list; st['page_order'] is
    # the page keys in the order he left them ('plan', 'schedules', 'image:2' -
    # the same keys the ticks use, so a picture thrown away renumbers them the
    # same way, shift_image_keys). `present` is the sheets this pass builds, in
    # the old order. Keys he ordered come first, in his order; a sheet he never
    # placed (a picture added after the drag) goes to the end.
    def self.page_order(st, present)
      return present.dup unless USE_PAGE_ORDER
      want = Array(st['page_order']).map(&:to_s)
      head = want.select { |k| present.include?(k) }.uniq
      head + (present - head)
    end

    # Puts doc.pages in that order and numbers them 1, 2, 3 down the set.
    def self.sort_pages!(doc, order)
      return doc if order.nil? || order.empty?
      at = {}
      order.each_with_index { |k, i| at[k] = i }
      n = order.length
      sorted = doc.pages.each_with_index
                        .sort_by { |pg, i| [at.fetch(pic_page_key(pg), n + i), i] }
                        .map(&:first)
      doc.pages.replace(sorted)
      doc.pages.each_with_index { |pg, i| pg.number = i + 1 }
      doc
    end

    # --------------------------------------------- the drawing's own box
    #
    # 2026-10-07. What he likes in Rayon, in his words: "השרטוט הוא כאילו חצי
    # תמונה - הוא נמצא בתוך כמו קופסה משל עצמו. את הקופסה אני יכול להגדיל
    # ולהקטין בעיקר מהפינות... ולהזיז אותה על הדף." And when the plan was
    # shown to him: "הקופסה לא צריכה להיצמד, אבל כן טוב לקבוע שוליים לדף
    # שהקופסה לא תוכל לצאת מהם. לא רוצה שקנה המידה יקפוץ - אני רוצה שתהיה
    # אופציה להגדיל ידנית, ושלהגדיר בגדלים נכונים."
    #
    # So the window on the plan sheet is no longer always the whole sheet:
    #   st['view_box'] = [x, y, w, h]   where the box is, paper inches from the
    #                                   bottom left of the sheet. nil = the
    #                                   whole of what the margins leave, which
    #                                   is every sheet made before this.
    #   st['scale_f']  = a number       paper inches to the foot, set by pulling
    #                                   a corner: any size, nothing snaps. nil =
    #                                   the scale picked from the list (and
    #                                   picking one from the list clears this).
    # The box is HELD INSIDE THE MARGINS here, every time, whatever was saved -
    # a smaller page, the tables switched on beside the plan, a model from
    # another day - so the paper can never print a box hanging off the sheet.
    def self.view_scale_free(st)
      return nil unless USE_VIEW_BOX
      f = st['scale_f'] || st[:scale_f]
      return nil unless f.is_a?(Numeric)
      f = f.to_f
      (f.finite? && f > 0.0005 && f < 48.0) ? f : nil
    end

    # [x, y, w, h] held inside area [x, y, w, h]: first small enough, then in.
    def self.box_inside(box, area)
      ax, ay, aw, ah = area.map(&:to_f)
      x, y, w, h = box.map(&:to_f)
      w = [[w, VIEW_BOX_MIN].max, aw].min
      h = [[h, VIEW_BOX_MIN].max, ah].min
      x = [[x, ax].max, ax + aw - w].min
      y = [[y, ay].max, ay + ah - h].min
      [x, y, w, h]
    end

    # rot: how far the box is turned. A TURNED box (USE_BOX_TURN) is held
    # inside the margins the way a picture is - first small enough, then in,
    # by the room it takes up turned - the box he saved and the whole-of-the-
    # margins box alike. Not turned: the same sums as always, to the digit.
    def self.place_view_box!(view, st, area, rot = 0.0)
      return view unless USE_VIEW_BOX
      box = st['view_box'] || st[:view_box]
      saved = box.is_a?(Array) && box.length == 4 &&
              box.all? { |n| n.is_a?(Numeric) && n.to_f.finite? } &&
              box[2].to_f > 0 && box[3].to_f > 0
      turned = USE_BOX_TURN && USE_VIEW_ROTATION && rot.to_f != 0.0
      return view unless saved || turned
      box = [view.x, view.y, view.w, view.h] unless saved
      view.x, view.y, view.w, view.h =
        turned ? pic_inside(box, rot, area, VIEW_BOX_MIN) : box_inside(box, area)
      view
    end

    # ------------------------------------------- pictures in boxes of their own
    #
    # 2026-10-07. "אני רוצה שתהיה אפשרות לסובב את השרטוט וגם את התמונות", "אני גם
    # יכול לבחור מה יראו מהתמונה או מהשרטוט - חיתוך", "שיהיה אפשרי להוסיף כמה
    # תמונות בדף, או תמונות גם בדף השרטוט". And on how: "הסקייל הוא רק לבחירה
    # של שרטוטים, התמונות לא צריכות סקייל."
    #
    # So a picture is a BOX on its sheet, the way the drawing is, with no scale:
    #   box   [x, y, w, h]   where the part of the picture that is SEEN lies,
    #                        paper inches from the bottom left of the sheet
    #   crop  [l, b, r, t]   how much of the file is cut off each side, each a
    #                        share (0..1) of the whole picture
    #   rot   degrees        the box turned about its own middle, anticlockwise
    # A corner makes the box and the picture bigger or smaller together; a side
    # changes the crop and leaves the picture where it is; nothing here knows
    # which was pulled - the window writes the three and this lays them out.
    #
    # Two places hold them, because there are two kinds of picture:
    #   st['image_geo'] = { "2" => {box, crop, rot} }
    #       the picture that OWNS picture sheet number 2 (st['images'][2]).
    #       Nothing saved = it fills its sheet, at its own proportions, exactly
    #       as every picture did before this.
    #   st['pics'] = [ { 'path' =>, 'on' => 'plan' | 'schedules' | 'image:2',
    #                    'box' =>, 'crop' =>, 'rot' => } ]
    #       a picture ADDED to a sheet that already exists - the plan sheet, or
    #       beside another picture. No box yet = a place is given to it here.
    #
    # Every picture shape that can be handled carries :pic - "m:2" for the
    # owner of sheet 2, "x:5" for st['pics'][5] - so the window can tell Ruby
    # which one he moved, and :iw / :ih, its size in pixels.
    #
    # HELD ON THE SHEET here, every time, whatever was saved: a box bigger than
    # the sheet is made smaller, one hanging off it is pushed back in.
    def self.pic_page_key(pg)
      k = pg.kind.to_s
      k = 'plan' if k.empty?
      return "image:#{pg.ref}" if k == 'image'     # the same lines as PlanSheetDialog.page_key
      return "drawing:#{pg.ref}" if k == 'drawing'
      k
    end

    # Inside the margins, above the title block: [x, y, w, h].
    def self.pic_area(pg)
      fx, fy, fw, fh = pg.frame
      tb  = InteriorPro::PlanDoc::TITLE_HEIGHT
      pad = 0.25
      [fx + pad, fy + tb + pad, fw - 2 * pad, fh - tb - 2 * pad]
    end

    def self.pic_size(path)
      require File.join(File.dirname(__FILE__), 'plan_pdf') unless defined?(InteriorPro::PlanPDF)
      InteriorPro::PlanPDF.image_size(path)
    rescue StandardError, NameError
      nil
    end

    # What was saved for one picture, checked. nil = nothing usable.
    def self.pic_geo(raw)
      return nil unless raw.is_a?(Hash)
      box = raw['box'] || raw[:box]
      return nil unless box.is_a?(Array) && box.length == 4 &&
                        box.all? { |n| n.is_a?(Numeric) && n.to_f.finite? } &&
                        box[2].to_f > 0 && box[3].to_f > 0
      crop = raw['crop'] || raw[:crop]
      crop = [0.0, 0.0, 0.0, 0.0] unless crop.is_a?(Array) && crop.length == 4 &&
                                         crop.all? { |n| n.is_a?(Numeric) && n.to_f.finite? }
      crop = crop.map { |n| [[n.to_f, 0.0].max, 0.95].min }
      crop[0] = crop[2] = 0.0 if crop[0] + crop[2] > 0.95
      crop[1] = crop[3] = 0.0 if crop[1] + crop[3] > 0.95
      rot = (raw['rot'] || raw[:rot]).to_f
      rot = 0.0 unless rot.finite?
      rot -= 360.0 while rot > 180.0
      rot += 360.0 while rot <= -180.0
      { box: box.map(&:to_f), crop: crop, rot: rot }
    end

    # A box turned by rot, held inside area: first small enough, then in.
    # Returns [x, y, w, h] - still the box before turning, about its middle.
    # (least: how small a side may be - a picture's, or the drawing's box's)
    def self.pic_inside(box, rot, area, least = PIC_MIN)
      ax, ay, aw, ah = area.map(&:to_f)
      x, y, w, h = box.map(&:to_f)
      cx = x + w / 2.0
      cy = y + h / 2.0
      w = [w, least].max
      h = [h, least].max
      r = rot.to_f * Math::PI / 180.0
      c = Math.cos(r).abs
      s = Math.sin(r).abs
      bw = w * c + h * s                    # the room it takes up once turned
      bh = w * s + h * c
      f  = [aw / bw, ah / bh, 1.0].min
      if f < 1.0
        w *= f; h *= f; bw *= f; bh *= f
      end
      cx = [[cx, ax + bw / 2.0].max, ax + aw - bw / 2.0].min
      cy = [[cy, ay + bh / 2.0].max, ay + ah - bh / 2.0].min
      [cx - w / 2.0, cy - h / 2.0, w, h]
    end

    # Where a picture just added to a sheet is put: in the middle, two fifths
    # of the width, at its own proportions - and each one a little down and to
    # the right of the last, so three added together do not hide each other.
    def self.default_pic_box(area, size, nth)
      ax, ay, aw, ah = area
      ar = (size && size[1].to_f > 0) ? size[0].to_f / size[1].to_f : 1.5
      w = aw * 0.4
      h = w / ar
      if h > ah * 0.6
        h = ah * 0.6
        w = h * ar
      end
      off = 0.4 * (nth % 6)
      pic_inside([ax + (aw - w) / 2.0 + off, ay + (ah - h) / 2.0 - off, w, h], 0.0, area)
    end

    def self.place_pictures!(doc, st)
      pd = InteriorPro::PlanDoc
      doc.pages.each { |pg| pg.pic_area = pic_area(pg) if pg.respond_to?(:pic_area=) }
      return doc unless USE_PIC_BOX
      geo  = st['image_geo'] || st[:image_geo]
      geo  = {} unless geo.is_a?(Hash)
      pics = st['pics'] || st[:pics]
      pics = [] unless pics.is_a?(Array)
      doc.pages.each do |pg|
        area = pg.pic_area
        key  = pic_page_key(pg)
        if pg.kind.to_s == 'image'
          main = pg.layer(pd::IMAGE_LAYER).shapes.find { |s| s[:type] == :image }
          if main
            size = pic_size(main[:path])
            main[:pic] = "m:#{pg.ref}"
            if size
              main[:iw] = size[0].to_f
              main[:ih] = size[1].to_f
            end
            g = pic_geo(geo[pg.ref.to_s] || geo[pg.ref])
            if g
              main[:x], main[:y], main[:w], main[:h] = pic_inside(g[:box], g[:rot], area)
              main[:placed] = true
              main[:rot]    = g[:rot]
              main[:crop]   = g[:crop]
            end
          end
        end
        nth = 0
        pics.each_with_index do |raw, j|
          next unless raw.is_a?(Hash)
          next unless (raw['on'] || raw[:on]).to_s == key
          path = (raw['path'] || raw[:path]).to_s
          next if path.empty?
          size = pic_size(path)
          g    = pic_geo(raw)
          box  = g ? pic_inside(g[:box], g[:rot], area) : default_pic_box(area, size, nth)
          nth += 1
          s = pg.layer(pd::IMAGE_LAYER).image(path, box[0], box[1], box[2], box[3],
                                              placed: true, pic: "x:#{j}",
                                              rot: (g ? g[:rot] : 0.0),
                                              crop: (g ? g[:crop] : [0.0, 0.0, 0.0, 0.0]))
          if size
            s[:iw] = size[0].to_f
            s[:ih] = size[1].to_f
          end
        end
      end
      doc
    end

    # --------------------------------------------- writing in boxes of its own
    #
    # 2026-10-07. "אני רוצה להוסיף אופציה של קופסא עם כיתוב. כמובן שהקופסא צריכה
    # להתנהג כמו שאר הקופסאות, ובקופסא יהיה אפשר לכתוב ולקבוע את גודל הכיתוב."
    #
    # So a piece of writing is a BOX on its sheet, the way a picture is:
    #   st['texts'] = [ { 'text' => "the words, \n between lines",
    #                     'on'   => 'plan' | 'schedules' | 'image:2',
    #                     'box'  => [x, y, w, h],   paper inches from the bottom left
    #                     'rot'  => degrees,        about the middle of the box
    #                     'pt'   => 24 } ]          how big the letters are, in points
    #
    # The WIDTH of the box is his: the words are laid in lines that fit it. The
    # HEIGHT is not - it is however many lines that took, worked out here every
    # time, with the TOP LEFT corner of the box staying where it was. A corner
    # of the box makes box and letters bigger together (the window scales 'pt'
    # and the width by the same amount, so the lines break in the same places);
    # a side makes it wider or narrower and the lines are laid again.
    #
    # What goes on the sheet is PLAIN TEXT SHAPES, one a line, on the sheet's
    # own TEXT layer - turned about the middle of the box, each hung from the
    # left end of its baseline. So plan_pdf and the window draw them with the
    # code they already had, and cannot disagree about a rule neither knows.
    # The window is also told the box itself (Page#text_boxes), to put the
    # same handles on it that a picture has.
    #
    # The window lays the same lines by the same sums (tbWrap, tbShapes in
    # plan_sheet_dialog.rb) so that the words move under his hand without a
    # trip to Ruby. Two copies of one rule: rt275 and t75 check BOTH against
    # the same numbers.
    def self.text_rules
      require File.join(File.dirname(__FILE__), 'plan_pdf') unless defined?(InteriorPro::PlanPDF)
      pp = InteriorPro::PlanPDF
      r = { 'pad' => TEXT_PAD, 'lead' => TEXT_LEAD, 'ascent' => TEXT_ASCENT,
            'pt' => TEXT_PT, 'pt_min' => TEXT_PT_MIN, 'pt_max' => TEXT_PT_MAX,
            'cap' => pp::CAP_RATIO, 'w' => pp::W, 'bold' => pp::BOLD_BUMP }
      # the letterings on offer and their width tables, and which one Hebrew
      # is set in when none is picked - the window measures by these
      if USE_TEXT_FONT && pp.const_defined?(:USE_TTF_FONTS) && pp::USE_TTF_FONTS
        r['fonts'] = pp.font_tables
        r['heb']   = pp.hebrew_family
      end
      r
    end

    def self.text_clean(t)
      t.to_s.gsub(/\r\n?/, "\n").tr("\t", ' ')
    end

    # How wide a run of words is at pt points, in paper inches. The real
    # Helvetica widths plan_pdf prints with.
    def self.text_width_in(str, pt, bold = false, font = nil)
      require File.join(File.dirname(__FILE__), 'plan_pdf') unless defined?(InteriorPro::PlanPDF)
      InteriorPro::PlanPDF.text_width(str, pt.to_f, bold, USE_TEXT_FONT ? font : nil) / 72.0
    end

    # The words, in lines no wider than avail (paper inches). A line he broke
    # himself stays broken; a word wider than the box stays whole.
    def self.text_wrap(text, avail, pt, bold = false, font = nil)
      out = []
      text_clean(text).split("\n", -1).each do |para|
        words = para.split(/ +/).reject(&:empty?)
        if words.empty?
          out << ''
          next
        end
        cur = ''
        words.each do |w|
          try = cur.empty? ? w : "#{cur} #{w}"
          if cur.empty? || text_width_in(try, pt, bold, font) <= avail + 1.0e-6
            cur = try
          else
            out << cur
            cur = w
          end
        end
        out << cur
      end
      out.empty? ? [''] : out
    end

    def self.text_height(lines, pt)
      fs = pt.to_f / 72.0
      2.0 * TEXT_PAD * fs + (lines - 1) * TEXT_LEAD * fs + fs
    end

    # The width a box needs to hold the words with no line broken but his own.
    def self.text_natural_width(text, pt, bold = false, font = nil)
      text_wrap(text, 1.0e9, pt, bold, font).map { |l| text_width_in(l, pt, bold, font) }.max.to_f +
        2.0 * TEXT_PAD * pt.to_f / 72.0
    end

    # How one box of writing is lettered, checked: { bold: true, italic: true,
    # underline: true, color: "#rrggbb" } - only what is set. Black is "no
    # colour" and is not kept, the same rule a label's own settings have.
    # THE SAME RULE AS tbStyle IN THE WINDOW.
    def self.text_style(raw)
      out = {}
      return out unless USE_TEXT_STYLE && raw.is_a?(Hash)
      %w[bold italic underline].each do |k|
        v = raw.key?(k) ? raw[k] : raw[k.to_sym]
        out[k.to_sym] = true if v == true
      end
      col = (raw.key?('color') ? raw['color'] : raw[:color]).to_s.downcase
      out[:color] = col if col =~ /\A#[0-9a-f]{6}\z/ && col != '#000000'
      # a lettering of its own: a family name, kept as written (the PDF and the
      # window both know which are on offer)
      f = (raw.key?('font') ? raw['font'] : raw[:font]).to_s.strip
      out[:font] = f if USE_TEXT_FONT && !f.empty? && f.length <= 40
      out
    end

    def self.text_pt(raw)
      v = (raw['pt'] || raw[:pt])
      v = v.is_a?(Numeric) ? v.to_f : TEXT_PT
      v = TEXT_PT unless v.finite? && v > 0
      [[v, TEXT_PT_MIN].max, TEXT_PT_MAX].min
    end

    # A box turned by rot, held inside area: first small enough, then in.
    # Returns [[x, y, w, h], f] - f is how much smaller it had to be made, and
    # the letters are made smaller by the same amount. (Not pic_inside: that
    # one will not let a box be under half an inch, and one line of small
    # writing is.)
    def self.text_inside(box, rot, area)
      ax, ay, aw, ah = area.map(&:to_f)
      x, y, w, h = box.map(&:to_f)
      cx = x + w / 2.0
      cy = y + h / 2.0
      r = rot.to_f * Math::PI / 180.0
      c = Math.cos(r).abs
      s = Math.sin(r).abs
      bw = w * c + h * s
      bh = w * s + h * c
      f  = [aw / bw, ah / bh, 1.0].min
      if f < 1.0
        w *= f; h *= f; bw *= f; bh *= f
      end
      cx = [[cx, ax + bw / 2.0].max, ax + aw - bw / 2.0].min
      cy = [[cy, ay + bh / 2.0].max, ay + ah - bh / 2.0].min
      [[cx - w / 2.0, cy - h / 2.0, w, h], f]
    end

    # What was saved for one piece of writing, checked and laid out.
    # nil = nothing to draw. nth = how many came before it on this sheet.
    def self.text_geo(raw, area, nth = 0)
      return nil unless raw.is_a?(Hash)
      txt = text_clean(raw['text'] || raw[:text])[0, TEXT_MAX_CHARS]
      return nil if txt.strip.empty?
      pt  = text_pt(raw)
      sty  = text_style(raw)
      bold = sty[:bold] == true        # bold letters are wider: the lines break by their widths
      rot = (raw['rot'] || raw[:rot]).to_f
      rot = 0.0 unless rot.finite?
      rot -= 360.0 while rot > 180.0
      rot += 360.0 while rot <= -180.0
      pad = TEXT_PAD * pt / 72.0
      box = raw['box'] || raw[:box]
      if box.is_a?(Array) && box.length == 4 &&
         box.all? { |n| n.is_a?(Numeric) && n.to_f.finite? } && box[2].to_f > 0
        x, y, w, h0 = box.map(&:to_f)
        h0 = 0.0 if h0 < 0
      else
        # no place saved: in the middle of the sheet, as wide as its words,
        # each one a little down and to the right of the last
        ax, ay, aw, ah = area.map(&:to_f)
        w   = [text_natural_width(txt, pt, bold, sty[:font]), aw].min
        h0  = text_height(text_wrap(txt, w - 2.0 * pad, pt, bold, sty[:font]).length, pt)
        off = 0.4 * (nth % 6)
        x   = ax + (aw - w) / 2.0 + off
        y   = ay + (ah - h0) / 2.0 - off
      end
      lines = text_wrap(txt, w - 2.0 * pad, pt, bold, sty[:font])
      h     = text_height(lines.length, pt)
      # the top left corner of the box stays where it was
      r = rot * Math::PI / 180.0
      c = rot.zero? ? 1.0 : Math.cos(r)
      s = rot.zero? ? 0.0 : Math.sin(r)
      cx  = x + w / 2.0
      cy  = y + h0 / 2.0
      tlx = cx + (-w / 2.0) * c - (h0 / 2.0) * s
      tly = cy + (-w / 2.0) * s + (h0 / 2.0) * c
      ncx = tlx - ((-w / 2.0) * c - (h / 2.0) * s)
      ncy = tly - ((-w / 2.0) * s + (h / 2.0) * c)
      held, f = text_inside([ncx - w / 2.0, ncy - h / 2.0, w, h], rot, area)
      pt *= f if f < 1.0
      { text: txt, pt: pt, rot: rot, box: held, lines: lines, style: sty }
    end

    # One plain text shape a line: [ {text:, x:, y:, h:, rotation:, li:} ].
    # THE SAME SUMS AS tbShapes IN THE WINDOW.
    def self.text_line_shapes(g)
      require File.join(File.dirname(__FILE__), 'plan_pdf') unless defined?(InteriorPro::PlanPDF)
      x, y, w, h = g[:box]
      fs    = g[:pt] / 72.0
      pad   = TEXT_PAD * fs
      pitch = TEXT_LEAD * fs
      rot   = g[:rot].to_f
      r = rot * Math::PI / 180.0
      c = rot.zero? ? 1.0 : Math.cos(r)
      s = rot.zero? ? 0.0 : Math.sin(r)
      cx = x + w / 2.0
      cy = y + h / 2.0
      out = []
      g[:lines].each_with_index do |str, i|
        next if str.empty?
        lx = -w / 2.0 + pad
        ly = h / 2.0 - (pad + TEXT_ASCENT * fs + i * pitch)
        out << { text: str, x: cx + lx * c - ly * s, y: cy + lx * s + ly * c,
                 h: fs * InteriorPro::PlanPDF::CAP_RATIO, rotation: rot, li: i }
      end
      out
    end

    def self.place_texts!(doc, st)
      doc.pages.each { |pg| pg.text_boxes = [] if pg.respond_to?(:text_boxes=) }
      return doc unless USE_TEXT_BOX
      list = st['texts'] || st[:texts]
      return doc unless list.is_a?(Array) && !list.empty?
      doc.pages.each do |pg|
        next unless pg.respond_to?(:text_boxes=)
        area = (pg.respond_to?(:pic_area) && pg.pic_area) || pic_area(pg)
        key  = pic_page_key(pg)
        nth  = 0
        list.each_with_index do |raw, j|
          next unless raw.is_a?(Hash)
          next unless (raw['on'] || raw[:on]).to_s == key
          g = safely { text_geo(raw, area, nth) }
          next unless g
          nth += 1
          lay = pg.layer(TEXT_LAYER)
          id  = "t:#{j}"
          sty = g[:style] || {}
          text_line_shapes(g).each do |ln|
            sh = lay.text(ln[:text], ln[:x], ln[:y], h: ln[:h], align: :left,
                                                     rotation: ln[:rotation], tbox: id, li: ln[:li])
            # lettered the way he set it at the side. plan_pdf and the window
            # already draw these four on any piece of writing (draw_text, shapeSVG)
            sty.each { |k, v| sh[k] = v }
          end
          bx = g[:box]
          # shaped like a picture's shape on purpose: the window handles both
          # with the same squares, bars, grip and round arrow
          pg.text_boxes << { pic: id, txt: true, placed: true,
                             x: bx[0], y: bx[1], w: bx[2], h: bx[3], rot: g[:rot],
                             crop: [0.0, 0.0, 0.0, 0.0], pt: g[:pt],
                             text: g[:text], lines: g[:lines] }.merge(sty)
        end
      end
      doc
    end

    # ------------------------------------------------- an elevation's dimensions
    #
    # 2026-10-08. The Elevations tool writes, for each picture it takes,
    #   st['image_dims'][path] = [ { 'k' => 'h' | 'v', 'u', 'v', 'row' | 'col', 't' } ]
    # in shares of the WHOLE picture (ElevationTool.dims_for). Here they are
    # laid over the picture where it stands on its sheet - through its box,
    # its crop and its turn - as plain lines and words on a layer of the page,
    # so the window and plan_pdf draw them with nothing new. The rows and
    # columns stand off the picture by paper inches, and the words are the size
    # of writing, however big the picture was made.
    ELEV_DIM_LAYER = 'ELEV_DIMS' unless const_defined?(:ELEV_DIM_LAYER, false)
    ELEV_ROW    = 0.45 unless const_defined?(:ELEV_ROW, false)     # paper inches between rows
    ELEV_TEXT_H = 0.11 unless const_defined?(:ELEV_TEXT_H, false) # capital height, paper inches
    ELEV_TICK   = 0.06 unless const_defined?(:ELEV_TICK, false)
    ELEV_GAP    = 0.03 unless const_defined?(:ELEV_GAP, false)     # air between the thing and its witness line
    ELEV_OVER   = 0.05 unless const_defined?(:ELEV_OVER, false)    # the witness line past the dimension line

    # His choice (13:09, "2"): the size of the elevations' numbers is ONE setting for all of
    # them. The window's panel sends a picked number's size / B / I / U / colour / lettering
    # under that number's own key; set_text_mark keeps them under this one key instead
    # (PlanSheetDialog.shared_text_key), and they are read back here, before the words are
    # laid, so a bigger number is still in the middle of its line.
    ELEV_SHARED_KEY = 'ELEV_DIMS|*' unless const_defined?(:ELEV_SHARED_KEY, false)

    def self.elev_style(st)
      marks = st['text_marks'] || st[:text_marks]
      o = marks.is_a?(Hash) ? marks[ELEV_SHARED_KEY] : nil
      o = {} unless o.is_a?(Hash)
      pct = o['pct'].to_f
      pct = 100.0 if pct <= 0
      pct = [[pct, TEXT_PCT_MIN].max, TEXT_PCT_MAX].min
      sty = {}
      %w[bold italic underline].each { |k| sty[k.to_sym] = true if o[k] }
      col = o['color'].to_s
      sty[:color] = col.downcase if col =~ /\A#[0-9a-fA-F]{6}\z/ && col.downcase != '#000000'
      fo = o['font'].to_s.strip
      sty[:font] = fo if USE_TEXT_FONT && !fo.empty? && fo.length <= 40
      [ELEV_TEXT_H * pct / 100.0, sty]
    end

    def self.place_elev_dims!(doc, st)
      return doc unless USE_ELEV_DIMS
      all = st['image_dims'] || st[:image_dims]
      all = {} unless all.is_a?(Hash)
      hand = USE_PIC_DIMS ? (st['image_hand'] || st[:image_hand]) : nil
      hand = {} unless hand.is_a?(Hash)
      return doc if all.empty? && hand.empty?
      @elev_h, @elev_sty = elev_style(st)
      @elev_marks = st['text_marks'] || st[:text_marks]
      @elev_marks = {} unless @elev_marks.is_a?(Hash)
      pd = InteriorPro::PlanDoc
      doc.pages.each do |pg|
        next unless pg.kind.to_s == 'image'
        next unless pg.layer?(pd::IMAGE_LAYER)
        # every picture on the sheet that has dimensions - the one that owns it and, since
        # 14:00 (a room's walls on one sheet), the ones added beside it
        shots = pg.layer(pd::IMAGE_LAYER).shapes.select { |s| s[:type] == :image }
        lay = nil
        @elev_seen = Hash.new(0)
        shots.each do |main|
          key = main[:path].to_s.tr('\\', '/')
          dims = all[key]
          dims = [] unless dims.is_a?(Array)
          # and the ones he drew himself, after the automatic ones (USE_PIC_DIMS)
          mine = hand[key].is_a?(Array) ? hand[key].map { |h| pic_dim(h) }.compact : []
          next if dims.empty? && mine.empty?
          lay ||= pg.layer(ELEV_DIM_LAYER)
          (dims + mine).each { |d| safely { draw_elev_dim(lay, main, d) } }
        end
      end
      doc
    end

    # Where the picture really lies on the paper: a placed picture IS its box; one
    # that was never moved is fitted into its box at its own proportions, in the
    # middle (PlanPDF.fit_box - the same sums the PDF and the window draw it by).
    # Measured 13:58: without this the chain ran past both corners of the room.
    def self.elev_rect(main)
      x, y, w, h = main[:x].to_f, main[:y].to_f, main[:w].to_f, main[:h].to_f
      return [x, y, w, h] if main[:placed] || main[:iw].to_f <= 0 || main[:ih].to_f <= 0
      InteriorPro::PlanPDF.fit_box(main[:iw], main[:ih], x, y, w, h, main[:stretch])
    end

    # one share of the picture (u from its left, v from its bottom) -> the paper
    def self.elev_pt(main, u, v)
      x, y, w, h = elev_rect(main)
      l, b, r, t = (main[:crop].is_a?(Array) && main[:crop].length == 4 ? main[:crop] : [0, 0, 0, 0]).map(&:to_f)
      [x + (u.to_f - l) / (1.0 - l - r) * w, y + (v.to_f - b) / (1.0 - b - t) * h]
    end

    # One dimension he drew on a picture (USE_PIC_DIMS) as draw_elev_dim takes it: 'k' => 'f', the two
    # points he locked onto, which way it measures, where its line stands, and its number. nil = not one.
    def self.pic_dim(h)
      return nil unless h.is_a?(Hash)
      pp = Array(h['p']).map(&:to_f)
      return nil unless pp.size == 4 && %w[h v].include?(h['o'].to_s)
      n = h['n'].to_f
      words = defined?(InteriorPro::ElevationTool) ? InteriorPro::ElevationTool.fmt_in(n) : format('%.1f"', n)
      { 'k' => 'f', 'o' => h['o'].to_s, 'p' => pp, 'at' => h['at'].to_f, 't' => words }
    end

    def self.draw_elev_dim(lay, main, d)
      rot = main[:rot].to_f
      ra = rot * Math::PI / 180.0
      rx, ry, rw, rh = elev_rect(main)
      cx = rx + rw / 2.0
      cy = ry + rh / 2.0
      tr = lambda do |px, py|
        return [px, py] if rot.zero?
        dx = px - cx
        dy = py - cy
        [cx + dx * Math.cos(ra) - dy * Math.sin(ra), cy + dx * Math.sin(ra) + dy * Math.cos(ra)]
      end
      ln = ->(x1, y1, x2, y2) { a = tr.call(x1, y1); b = tr.call(x2, y2); lay.line(a[0], a[1], b[0], b[1], elev_dim: true) }
      t = ELEV_TICK / 2.0
      words = d['t'].to_s
      th = @elev_h || ELEV_TEXT_H
      sty = (@elev_sty || {}).dup
      # ONE number's own look and words (two clicks on it, 13:26), under the name
      # name_texts! will give it - the same count of the same words down the layer
      built = words
      @elev_seen ||= Hash.new(0)
      @elev_seen[built] += 1
      own = (@elev_marks || {})[text_key(ELEV_DIM_LAYER, built, @elev_seen[built])]
      t0 = nil
      if own.is_a?(Hash)
        pct = own['pct'].to_f
        th = ELEV_TEXT_H * [[pct, TEXT_PCT_MIN].max, TEXT_PCT_MAX].min / 100.0 if pct > 0
        %w[bold italic underline].each { |k| sty[k.to_sym] = !!own[k] if own.key?(k) }
        col = own['color'].to_s
        sty[:color] = col.downcase if col =~ /\A#[0-9a-fA-F]{6}\z/ && col.downcase != '#000000'
        fo = own['font'].to_s.strip
        sty[:font] = fo if USE_TEXT_FONT && !fo.empty? && fo.length <= 40
        tx = own['text']
        if USE_TEXT_WORDS && tx.is_a?(String) && !tx.strip.empty?
          t0 = built
          words = tx
        end
      end
      sty.delete_if { |_, v| v == false }
      fs = th / InteriorPro::PlanPDF::CAP_RATIO * 72.0
      tw = text_width_in(words, fs, sty[:bold], sty[:font])
      opts = { h: th, h0: ELEV_TEXT_H, align: :left, elev_dim: true }.merge(sty)
      opts[:t0] = t0 if t0
      if d['k'].to_s == 'f'
        # one he drew (USE_PIC_DIMS): from his two points to its line, across or up
        u1, v1, u2, v2 = d['p']
        a = elev_pt(main, u1, v1)
        b = elev_pt(main, u2, v2)
        if d['o'] == 'h'
          yl = elev_pt(main, u1, d['at'])[1]
          ln.call(a[0], yl, b[0], yl)
          [a, b].each do |q|
            sg = yl >= q[1] ? 1.0 : -1.0
            ln.call(q[0] - t, yl - t, q[0] + t, yl + t)
            ln.call(q[0], q[1] + sg * ELEV_GAP, q[0], yl + sg * ELEV_OVER) if (yl - q[1]).abs > ELEV_GAP
          end
          p = tr.call((a[0] + b[0]) / 2.0 - tw / 2.0, yl + 0.035)
          lay.text(words, p[0], p[1], opts.merge(rotation: rot))
        else
          xl = elev_pt(main, d['at'], v1)[0]
          ln.call(xl, a[1], xl, b[1])
          [a, b].each do |q|
            sg = xl >= q[0] ? 1.0 : -1.0
            ln.call(xl - t, q[1] - t, xl + t, q[1] + t)
            ln.call(q[0] + sg * ELEV_GAP, q[1], xl + sg * ELEV_OVER, q[1]) if (xl - q[0]).abs > ELEV_GAP
          end
          p = tr.call(xl - 0.035, (a[1] + b[1]) / 2.0 - tw / 2.0)
          lay.text(words, p[0], p[1], opts.merge(rotation: rot + 90.0))
        end
      elsif d['k'].to_s == 'h'
        u1, u2 = Array(d['u']).map(&:to_f)
        x1 = elev_pt(main, u1, d['v'])[0]
        x2 = elev_pt(main, u2, d['v'])[0]
        yf = elev_pt(main, u1, d['v'])[1]
        yl = yf - d['row'].to_i * ELEV_ROW
        ln.call(x1, yl, x2, yl)
        reach = d['r'].is_a?(Array) ? d['r'] : []
        [[x1, u1, reach[0]], [x2, u2, reach[1]]].each do |x, uu, rv|
          ln.call(x - t, yl - t, x + t, yl + t)
          # a part's line runs up to its middle (ElevationTool::USE_PART_REACH, 13:54)
          top = rv ? elev_pt(main, uu, rv)[1] : yf - ELEV_GAP
          ln.call(x, top, x, yl - ELEV_OVER)
        end
        p = tr.call((x1 + x2) / 2.0 - tw / 2.0, yl + 0.035)
        lay.text(words, p[0], p[1], opts.merge(rotation: rot))
      elsif d['k'].to_s == 'hi'
        # inside the picture, by the thing itself (USE_CLEAN_DIMS, 15:57)
        u1, u2 = Array(d['u']).map(&:to_f)
        a = elev_pt(main, u1, d['v'])
        b = elev_pt(main, u2, d['v'])
        y = a[1]
        ln.call(a[0], y, b[0], y)
        yf = d['from'] ? elev_pt(main, u1, d['from'])[1] : nil
        [a[0], b[0]].each do |x|
          ln.call(x - t, y - t, x + t, y + t)
          ln.call(x, yf - ELEV_GAP, x, y - ELEV_OVER) if yf
        end
        p = tr.call((a[0] + b[0]) / 2.0 - tw / 2.0, d['below'] ? y - 0.035 - th : y + 0.035)
        lay.text(words, p[0], p[1], opts.merge(rotation: rot))
      elsif d['side'].to_s == 'L'
        # a column by the picture's LEFT wall (USE_CLEAN_DIMS, 15:57)
        v1, v2 = Array(d['v']).map(&:to_f)
        y1 = elev_pt(main, d['u'], v1)[1]
        y2 = elev_pt(main, d['u'], v2)[1]
        xr = elev_pt(main, d['u'], v1)[0]
        xl = [xr, rx].min - d['col'].to_i * ELEV_ROW
        ln.call(xl, y1, xl, y2)
        [y1, y2].each_with_index do |y, i|
          ln.call(xl - t, y - t, xl + t, y + t)
          x0 = i == 1 && d['u0'] ? elev_pt(main, d['u0'], v2)[0] : xr - ELEV_GAP
          ln.call(x0, y, xl - ELEV_OVER, y)
        end
        p = tr.call(xl - 0.035, (y1 + y2) / 2.0 - tw / 2.0)
        lay.text(words, p[0], p[1], opts.merge(rotation: rot + 90.0))
      else
        v1, v2 = Array(d['v']).map(&:to_f)
        y1 = elev_pt(main, d['u'], v1)[1]
        y2 = elev_pt(main, d['u'], v2)[1]
        xr = elev_pt(main, d['u'], v1)[0]
        # the columns stand off the picture's right EDGE (past the cut wall beside the
        # corner); the witness lines start at the corner and cross that wall, where
        # they do not show (13:58: off the corner the first column sat on the wall)
        xl = [xr, rx + rw].max + d['col'].to_i * ELEV_ROW
        ln.call(xl, y1, xl, y2)
        [y1, y2].each_with_index do |y, i|
          ln.call(xl - t, y - t, xl + t, y + t)
          # the top of a part's height runs across from its middle (USE_PART_REACH, 13:54)
          x0 = i == 1 && d['u0'] ? elev_pt(main, d['u0'], v2)[0] : xr + ELEV_GAP
          ln.call(x0, y, xl + ELEV_OVER, y)
        end
        p = tr.call(xl - 0.035, (y1 + y2) / 2.0 - tw / 2.0)
        lay.text(words, p[0], p[1], opts.merge(rotation: rot + 90.0))
      end
    end

    # ------------------------------------------------- turning the drawing
    #
    # 2026-10-07. He asked to turn the drawing on its sheet with a handle on
    # its corner, the way Rayon does it, and was shown his own house turned
    # 35 degrees two ways. His answer, in two messages: "הכל צריך להסתובב" -
    # and then - "רגע, הכל מסתובב התכוונתי למידות, אבל הכל חייב להישאר קריא".
    #
    # So, for a drawing turned by `rot` degrees:
    #   - every LINE turns. That is the window on the sheet (PlanDoc::View)
    #     and nothing in this file.
    #   - a DIMENSION'S NUMBER turns with the line it measures, and so does
    #     any writing that was laid along something, and a hand-written note
    #     with its box. None of them is ever left upside down: past vertical
    #     it is read from the other side, the same rule draw_mark_dim has
    #     always had.
    #   - a ROOM NAME, its area under it, and a door or window TAG stay level
    #     on the page. They go where the room or the badge went, but they do
    #     not tip over. A name and the area under it stay one above the other.
    #
    # HOW: the two things that draw a sheet - the window and plan_pdf - are
    # kept simple. Each puts a piece of writing where the turned drawing puts
    # its point and turns it by ITS OWN angle PLUS the sheet's. Everything
    # that is a decision is made here, once, by rewriting the writing's point
    # and angle so that simple rule gives the answer above. Two drawing
    # routines cannot disagree about a rule neither of them knows.
    #
    # What a piece of writing was BUILT with is kept in :rk and put back by
    # unturn_texts! at the top of every layout pass - the same reason :h0 and
    # :x0 exist: layout_pages! runs on every click, on the same shapes.
    def self.view_rotation(st)
      return 0.0 unless USE_VIEW_ROTATION
      d = (st['rotation'] || st[:rotation]).to_f
      return 0.0 unless d.finite?
      d -= 360.0 while d > 180.0
      d += 360.0 while d <= -180.0
      d
    end

    def self.unturn_texts!(doc)
      doc.canvases.each do |cv|
        cv.layers.each do |lay|
          lay.shapes.each do |s|
            next unless s[:type] == :text && s.key?(:rk)
            s[:x], s[:y], s[:rotation] = s.delete(:rk)
          end
        end
      end
      doc
    end

    # Does this writing run WITH the drawing (true) or stay level (false)?
    def self.text_follows?(layer_name, s)
      return true if layer_name == LAYERS[:dimensions]
      return true if s[:follow]
      s[:rotation].to_f.abs > 0.01           # it was laid along something
    end

    # A room's name and the area under it are two pieces of writing built one
    # above the other. Turned separately they would end up side by side, so
    # each pair turns about the point half way between them and keeps its own
    # up-and-down. Returns { shape => [ax, ay] }, by identity.
    def self.room_anchors(lay)
      out   = {}.compare_by_identity
      texts = lay.shapes.select { |s| s[:type] == :text }
      built = ->(s) { [s.key?(:x0) ? s[:x0].to_f : s[:x].to_f, s.key?(:y0) ? s[:y0].to_f : s[:y].to_f] }
      i = 0
      while i < texts.length - 1
        a = texts[i]
        b = texts[i + 1]
        ax, ay = built.call(a)
        bx, by = built.call(b)
        if b[:text].to_s =~ /\A\d+ SF\z/ && a[:text].to_s !~ /\A\d+ SF\z/ && (ax - bx).abs < 1.0e-6
          mid = [ax, (ay + by) / 2.0]
          out[a] = mid
          out[b] = mid
          i += 2
        else
          i += 1
        end
      end
      out
    end

    def self.turn_texts!(doc, rot)
      return doc if rot.to_f.abs < 1.0e-9
      r = rot * Math::PI / 180.0
      c = Math.cos(r)
      n = Math.sin(r)
      cv = doc.canvas('MODEL')
      cv.layers.each do |lay|
        anchors = lay.name == LAYERS[:rooms] ? room_anchors(lay) : nil
        lay.shapes.each do |s|
          next unless s[:type] == :text
          own = s[:rotation].to_f
          s[:rk] = [s[:x], s[:y], s[:rotation]]
          if text_follows?(lay.name, s)
            # with the drawing, and never upside down
            want = own + rot
            want -= 180.0 while want > 90.0
            want += 180.0 while want < -90.0
            s[:rotation] = want - rot
          else
            # level on the page: the sheet's turn is taken back out
            s[:rotation] = own - rot
            an = anchors && anchors[s]
            if an
              # built at b, shoved by d, hanging off the anchor a:
              #   on paper = where a went + (b - a) kept upright + d turned
              bx = s.key?(:x0) ? s[:x0].to_f : s[:x].to_f
              by = s.key?(:y0) ? s[:y0].to_f : s[:y].to_f
              dx = s[:x].to_f - bx
              dy = s[:y].to_f - by
              ox = bx - an[0]
              oy = by - an[1]
              s[:x] = an[0] + (ox * c + oy * n) + dx
              s[:y] = an[1] + (-ox * n + oy * c) + dy
            end
          end
        end
      end
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
        # the words as BUILT: a label written over by hand (:t0, see
        # apply_text_overrides!) is keyed by the words it was built with,
        # and goes back to them here - layout_pages! runs on every click
        s[:text] = s[:t0] if s.key?(:t0)
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
            # underline and colour (2026-10-07): "גודל כיתוב, אפשרות להדגשה,
            # קו מתחת, סוג כתב וצבע" - in the one panel at the side, like Word.
            # Colour is "#rrggbb"; black means "no colour" and is not kept.
            u = o.key?('underline') ? o['underline'] : o[:underline]
            s[:underline] = !!u unless u.nil?
            col = (o.key?('color') ? o['color'] : o[:color]).to_s
            s[:color] = col.downcase if col =~ /\A#[0-9a-fA-F]{6}\z/ && col.downcase != '#000000'
            # a lettering of its own (2026-10-07)
            fo = (o.key?('font') ? o['font'] : o[:font]).to_s.strip
            s[:font] = fo if USE_TEXT_FONT && !fo.empty? && fo.length <= 40
            # His own words in place of the label's (2026-10-07): a dimension
            # number written over, a room renamed on the sheet. The KEY was
            # made from the words as built (name_texts! ran first), so the
            # choice finds its label again after the sheet is rebuilt.
            if USE_TEXT_WORDS
              t = o.key?('text') ? o['text'] : o[:text]
              if t.is_a?(String) && !t.strip.empty?
                s[:t0] = s[:text].to_s unless s.key?(:t0)
                s[:text] = t.to_s
              end
            end
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
      Array(st['marks']).each_with_index do |m, i|
        h = m['t'] || m[:t]
        case h.to_s
        when 'dim'  then safely { draw_mark_dim(lay, m) }
        when 'note' then safely { draw_mark_note(lay, m, i) }
        end
      end
      cv
    end

    # A note's box and leader, drawn again from its words as they finally are
    # (2026-10-08). The words were drawn with the marks, before the sizing
    # passes; by now they may be bigger, bold, or in a lettering of their own
    # (text_marks on their key, or their group's size), or shoved. Every shape
    # of a note carries its number (:note), so the frame is taken off and put
    # back around the words - only when something about them changed.
    def self.fit_notes!(doc, st)
      return doc unless USE_NOTE_FIT
      cv = doc.canvas('MODEL')
      return doc unless cv.layer?(MARK_LAYER)
      lay = cv.layer(MARK_LAYER)
      notes = {}
      Array(st['marks']).each_with_index do |m, i|
        notes[i] = m if (m['t'] || m[:t]).to_s == 'note'
      end
      lay.shapes.select { |s| s[:type] == :text && !s[:note].nil? }.each do |s|
        i = s[:note]
        m = notes[i]
        next unless m
        h  = s[:h].to_f
        h0 = s.key?(:h0) ? s[:h0].to_f : h
        x  = s[:x].to_f
        y  = s[:y].to_f
        same = (h - h0).abs < 1.0e-9 && !s[:bold] && s[:font].to_s.empty? &&
               !s.key?(:t0) && (x - mark_num(m, :x)).abs < 1.0e-9 && (y - mark_num(m, :y)).abs < 1.0e-9
        next if same
        lay.shapes.reject! { |q| q[:note] == i && q[:type] != :text }
        w = begin
          pp = InteriorPro::PlanPDF
          pp.text_width(s[:text].to_s, h / pp::CAP_RATIO, !!s[:bold], (USE_TEXT_FONT ? s[:font] : nil))
        rescue StandardError, NameError
          text_width(s[:text].to_s, h)
        end
        safely { note_frame(lay, m, x, y, h, w, i) }
      end
      doc
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
      # His own words instead of the measured number, if he wrote any
      # (2026-10-07). They stay whatever the dimension is stretched to.
      words = USE_TEXT_WORDS ? (m['label'] || m[:label]).to_s.strip : ''
      lay.text(words.empty? ? InteriorPro::PlanGenerator.send(:fmt_feet, len) : words,
               lx, ly, h: h, align: :center, rotation: ang, follow: true)
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

    def self.draw_mark_note(lay, m, i = nil)
      txt = (m['text'] || m[:text]).to_s
      return if txt.strip.empty?
      h = mark_num(m, :h)
      h = mark_text_h if h <= 0
      x = mark_num(m, :x)
      y = mark_num(m, :y)

      opts = { h: h, align: :center, follow: true }   # turns with its box
      opts[:note] = i unless i.nil?                    # its number, for fit_notes!
      lay.text(txt, x, y, opts)

      note_frame(lay, m, x, y, h, text_width(txt, h), i)
    end

    # The box around a note's words and the leader out of it, for words that
    # are w wide and h tall with their middle at x, y. tag = the note's number
    # on every shape (nil = none), so fit_notes! can find them again.
    def self.note_frame(lay, m, x, y, h, w, tag = nil)
      op  = tag.nil? ? {} : { note: tag }
      pad = h * MARK_PAD
      bw  = w / 2.0 + pad
      bh  = h / 2.0 + pad
      lay.polygon([[x - bw, y - bh], [x + bw, y - bh],
                   [x + bw, y + bh], [x - bw, y + bh]], op)

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
        lay.line(sx, sy, kx, ky, op) if Math.hypot(kx - sx, ky - sy) >= 0.5
        return if Math.hypot(lx - kx, ly - ky) < 0.5
        lay.line(kx, ky, lx, ly, op)
        arrow = m.key?('arrow') ? m['arrow'] : (m.key?(:arrow) ? m[:arrow] : true)
        arrow_head(lay, kx, ky, lx, ly, h * MARK_ARROW, op) unless arrow == false
        return
      end

      sx, sy = box_exit(x, y, bw, bh, lx, ly)
      return if Math.hypot(lx - sx, ly - sy) < 0.5
      lay.line(sx, sy, lx, ly, op)

      # With or without a head on the end. SketchUp's own text leader is a bare
      # line, and the user sent a picture of one - so both are offered and he
      # picks per note. A note written before this existed has no say in the
      # matter and keeps the head it already had.
      arrow = m.key?('arrow') ? m['arrow'] : (m.key?(:arrow) ? m[:arrow] : true)
      arrow_head(lay, sx, sy, lx, ly, h * MARK_ARROW, op) unless arrow == false
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

    def self.arrow_head(lay, sx, sy, lx, ly, size, op = {})
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
      lay.line(lx, ly, lx - ux * back + nx * side, ly - uy * back + ny * side, op)
      lay.line(lx, ly, lx - ux * back - nx * side, ly - uy * back - ny * side, op)
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
