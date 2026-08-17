# encoding: utf-8
# Landscape Pro - Reference Fence Tool (2026-08-16)
#
#   click 1 = where the fence starts
#   click 2 = where the fence ends
#
# WHAT THIS IS
#
# The user builds a fence in SketchUp - a real one, with every rail and cable
# and post foot exactly as he wants it - and drops the .skp into
# landscape/reference. This tool takes THAT model and lays it along a line.
# It draws NOTHING of its own. There is no post code, no rail code, no board
# code in here: if a fence comes out looking wrong, the answer is in the .skp
# he made, not in this file.
#
# This replaced the parametric fence engine as the way fences get built
# (2026-08-16), on his instruction, after two rounds of "the numbers say a
# fence" produced something he did not recognise as one. The parametric files
# (fence_math, fence_tool, fence_library) stay on disk and stay tested, but
# nothing on the toolbar reaches them any more.
#
# HOW A REFERENCE FENCE IS SHAPED
#
# Read off his 'cable railing.skp' with debug_fence_parts.rb, and this is the
# ordinary Profile Builder shape, so it is the shape this tool expects:
#
#   * The model contains ONE repeating UNIT: a post plus the panel after it,
#     as a single component (his was Component#2, 78.7" wide, three of them
#     in a row). The tool finds it as "the component that appears the most
#     times, and is wide".
#   * At the far end there is a CLOSER: a lone post that shuts the last bay
#     (his was Component#38 on its own). The tool finds it as "the tallest
#     narrow piece that is NOT inside the unit". If there is none, the last
#     unit simply ends the run.
#   * The run of the model may be along X OR along Y - his was along Y. The
#     tool reads which and turns the unit so its run lies along the fence.
#
# LAYING IT ALONG A LINE (changed 2026-08-17 - see layout_for)
#
#   Whole units at their true size, and the remainder is ONE more unit sliced
#   by a plane at the far end (cut_stub!). A stretch under 6% is kept instead
#   of a cut, because nobody sees 6% and everybody sees a seam. This replaced
#   "stretch n units to fit", which was fine on a one-bay unit and awful on
#   his three-bay cable railing (a 240" fence stretched a 180" unit by a
#   third). USE_CUT = false is the old behaviour.
#
#   Three ways his file can be shaped, and all three are read (shape_of):
#   UNIT (one big repeating component), PARTS (loose posts + loose parts,
#   a unit is assembled from the first bay), WHOLE (loose faces present, or
#   nothing recognised - the whole model is the unit, pitch = post to post).
#
# GROUND
#
# ground_start / ground_end are stored, two numbers, exactly as on the
# parametric fence, and today they are 0. When terrain arrives they get filled
# in and each unit gets its own base height. Nothing else changes.

module InteriorPro
  module Landscape
    class FenceRefTool

      DICT = 'LandscapePro' unless const_defined?(:DICT, false)

      GHOST = [120, 120, 120].freeze unless const_defined?(:GHOST, false)
      DOT   = [40, 90, 200].freeze   unless const_defined?(:DOT, false)

      MIN_LEN = 1.0 unless const_defined?(:MIN_LEN, false)

      # A stretch bigger than this is not a fence any more, it is a mistake -
      # the run was shorter than one unit and we would be squashing a post to
      # a plank. Below one unit, one unit is placed and trimmed by nothing.
      MAX_STRETCH = 1.35 unless const_defined?(:MAX_STRETCH, false)
      MIN_STRETCH = 0.70 unless const_defined?(:MIN_STRETCH, false)

      attr_accessor :ground_start, :ground_end
      attr_reader :ref_name, :ref_path

      def self.reference_dir
        File.join(InteriorPro::PLUGIN_DIR, 'landscape', 'reference')
      end

      # Every fence he has dropped in the folder, by display name.
      def self.references
        Dir.glob(File.join(reference_dir, '*.skp')).sort.map do |p|
          { name: File.basename(p, '.skp'), path: p }
        end
      rescue StandardError
        []
      end

      def initialize(ref_path)
        @ref_path     = ref_path
        @ref_name     = File.basename(ref_path.to_s, '.skp')
        @ground_start = 0.0
        @ground_end   = 0.0
        @shape        = nil
        reset
      end

      # ------------------------------------------------------------- tool API

      def activate
        @ip = Sketchup::InputPoint.new
        reset
        # Read the model once, up front, so the preview knows the unit width
        # and a bad file complains before the first click, not after the last.
        @shape = read_shape!
        unless @shape
          UI.messagebox("Could not read a fence out of:\n#{@ref_path}")
          Sketchup.active_model.select_tool(nil)
          return
        end
        status
        Sketchup.active_model.active_view.invalidate
      end

      def deactivate(view)
        view.invalidate
      end

      def enableVCB?
        true
      end

      def onCancel(_reason, view)
        reset
        status
        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        return unless key == 27
        reset
        status
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        @cursor = flat_point(view, x, y)
        if @p1
          Sketchup.vcb_label = 'Length'
          Sketchup.vcb_value = Sketchup.format_length(@cursor.distance(@p1))
          refresh_ghost
        end
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        pt = flat_point(view, x, y)
        if @p1.nil?
          @p1 = pt
        else
          return if pt.distance(@p1) < MIN_LEN
          @p2 = pt
          build_it(view)
        end
        status
        view.invalidate
      end

      def onLButtonDoubleClick(_flags, _x, _y, _view); end

      def onUserText(text, view)
        return unless @p1 && @cursor
        v = parse_length(text)
        return UI.messagebox("Invalid length: #{text.inspect}") if v.nil?
        return if v.abs < MIN_LEN
        dir = @cursor - @p1
        return if dir.length < 1e-6
        dir.normalize!
        @p2 = @p1.offset(dir, v.abs)
        build_it(view)
        status
        view.invalidate
      end

      def draw(view)
        @ip.draw(view) if @ip && @ip.display?
        view.line_width = 2
        view.line_stipple = '-'
        view.drawing_color = Sketchup::Color.new(*GHOST)
        if @ghost
          @ghost.each { |seg| view.draw(GL_LINES, seg) }
        elsif @p1 && @cursor
          view.draw(GL_LINES, [@p1, @cursor])
        end
        view.line_stipple = ''
        [@p1, @p2].compact.each do |pt|
          view.draw_points([pt], 8, 2, Sketchup::Color.new(*DOT))
        end
      rescue StandardError
        nil
      end

      def getExtents
        bb = Geom::BoundingBox.new
        bb.add(@p1) if @p1
        bb.add(@cursor) if @cursor
        @ghost&.each { |seg| seg.each { |p| bb.add(p) } }
        bb
      end

      # ------------------------------------------------------------- private

      private

      def reset
        @p1 = nil
        @p2 = nil
        @cursor = nil
        @ghost = nil
      end

      def status
        msg = if @p1.nil?
                "#{@ref_name} (1/2): click where the fence starts. Esc = cancel."
              else
                "#{@ref_name} (2/2): click where it ends, or type a length."
              end
        Sketchup.set_status_text(msg, SB_PROMPT)
      end

      def flat_point(view, x, y)
        p = view.inputpoint(x, y).position
        Geom::Point3d.new(p.x, p.y, 0)
      end

      def parse_length(text)
        s = text.to_s.strip
        return nil if s.empty?
        begin
          return s.to_l.to_f
        rescue StandardError
          f = s.to_f
          return f.zero? ? nil : f
        end
      end

      # ------------------------------------------------------- reading the skp
      #
      # Load the definition, find the unit and the closer, remember them. The
      # definitions stay in the model - they ARE the fence, every instance
      # placed later points at them.

      def read_shape!
        model = Sketchup.active_model
        return nil unless @ref_path && File.exist?(@ref_path)
        defn = model.definitions.load(@ref_path)
        return nil unless defn
        shape_of(defn)
      rescue StandardError => e
        puts "[FenceRef] read: #{e.class}: #{e.message}"
        nil
      end

      # Pure inspection of a loaded definition. Split out so a test can hand it
      # a stub definition and check the reading without a file.
      #
      # TWO WAYS HIS FILE CAN BE PUT TOGETHER (both seen, 2026-08-16/17):
      #
      #   UNIT mode   - the model is a few copies of one big component, each
      #                 "post + the panel after it" (his first cable railing:
      #                 3 x Component#2, then a lone post). The unit is that
      #                 component; the closer is the lone post.
      #   PARTS mode  - the model is loose parts, all direct children: posts
      #                 every so often, and rails / cables / spacers between
      #                 them (his second cable railing: 30 cables, posts...).
      #                 There is no ready-made unit, so one is ASSEMBLED: the
      #                 first post plus every part whose centre falls in the
      #                 first bay. That assembled list is what gets repeated,
      #                 and the last post is the closer.
      #
      # Either way the caller gets the same answer: a list of [definition,
      # transformation] pairs that make one repeating unit, its pitch, its
      # box, and a closer.
      def shape_of(defn)
        kids = defn.entities.select { |e|
          e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)
        }
        loose_faces = defn.entities.grep(Sketchup::Face)
        return nil if kids.empty? && loose_faces.empty?

        boxes = kids.map { |k| [k, world_box(k, Geom::Transformation.new)] }
                    .reject { |(_k, b)| b.nil? }

        # Which way does the model run? Along whichever of X / Y is longer.
        # Loose faces count towards the box too - in his second cable railing
        # they were most of the geometry (5868 of them).
        all_min = [Float::INFINITY, Float::INFINITY, Float::INFINITY]
        all_max = [-Float::INFINITY, -Float::INFINITY, -Float::INFINITY]
        grow = lambda do |lo, hi|
          3.times do |i|
            all_min[i] = lo[i] if lo[i] < all_min[i]
            all_max[i] = hi[i] if hi[i] > all_max[i]
          end
        end
        boxes.each { |(_k, b)| grow.call(b[0], b[1]) }
        loose_faces.each do |f|
          f.vertices.each do |v|
            p = v.position
            a = [p.x.to_f, p.y.to_f, p.z.to_f]
            grow.call(a, a)
          end
        end
        return nil if all_min[0] == Float::INFINITY

        run_axis = (all_max[0] - all_min[0]) >= (all_max[1] - all_min[1]) ? 0 : 1
        across   = run_axis == 0 ? 1 : 0
        total_h  = all_max[2] - all_min[2]

        base = { defn: defn, run_axis: run_axis, across: across,
                 height: total_h, model_min: all_min, model_max: all_max,
                 loose_faces: loose_faces.length }

        # Loose faces at the top level cannot be sorted into bays without
        # cutting his geometry, and unit / parts mode would silently leave
        # them behind - which is exactly what he saw on 2026-08-17: cables in
        # one bay, nothing in the next. So a model with loose faces is always
        # placed WHOLE.
        if loose_faces.empty?
          unit = unit_mode(boxes, run_axis, across, total_h)
          return base.merge(unit) if unit

          parts = parts_mode(boxes, run_axis, across, total_h)
          return base.merge(parts) if parts
        end

        # WHOLE mode: the model as it is, repeated. Rather than refuse (which
        # is what happened on 2026-08-17 - "could not read a fence out of it"
        # on five of his seven files, one of them a fence that had built fine
        # an hour before), take the whole model as one unit and repeat THAT.
        base.merge(whole_mode(defn, boxes, run_axis, across, total_h, all_min, all_max))
      end

      # The whole definition is the unit - ONE instance of it per bay, loose
      # faces and all. The pitch is post-to-post, not the box width: his model
      # has a post at each end, so unit i's end post and unit i+1's start post
      # land on the same spot and read as one post. If no two posts can be
      # found, the box width is the pitch and the seam is a plain butt.
      def whole_mode(defn, boxes, run_axis, across, total_h, all_min, all_max)
        posts = boxes.select do |(_k, b)|
          along = b[1][run_axis] - b[0][run_axis]
          tall  = b[1][2] - b[0][2]
          along < 12.0 && tall >= total_h * 0.5
        end
        pitch = nil
        if posts.length >= 2
          starts = posts.map { |(_k, b)| b[0][run_axis] }
          pitch = starts.max - starts.min
        end
        box_along = all_max[run_axis] - all_min[run_axis]
        pitch = box_along if pitch.nil? || pitch < box_along * 0.5

        {
          mode: :whole,
          pieces: [[defn, Geom::Transformation.new]],
          unit_min: all_min.dup, unit_max: all_max.dup,
          unit_along: pitch,
          unit_across: all_max[across] - all_min[across],
          unit_count_in_model: 1,
          closer_pieces: [],
          closer_min: nil, closer_max: nil,
          post_count: posts.length
        }
      end

      # UNIT mode: the biggest component that repeats, as long as it is really
      # a unit - at least half the fence tall and at least a foot along. A
      # cable is neither, which is how his second file was NOT mistaken for
      # unit mode (2026-08-17: the first rule, "appears the most", chose a
      # cable and drew a pencil line).
      def unit_mode(boxes, run_axis, across, total_h)
        by_def = Hash.new { |h, k| h[k] = [] }
        boxes.each do |(k, b)|
          # In SketchUp a Group has a definition too, so his groups count.
          next unless k.respond_to?(:definition) && k.definition
          along = b[1][run_axis] - b[0][run_axis]
          tall  = b[1][2] - b[0][2]
          next if along < 12.0 || tall < total_h * 0.5
          by_def[k.definition] << [k, b]
        end
        repeating = by_def.select { |_d, l| l.length >= 2 }
        return nil if repeating.empty?
        unit_def, unit_list = repeating.max_by do |_d, l|
          b = l.first[1]
          [b[1][2] - b[0][2], b[1][run_axis] - b[0][run_axis]]
        end
        u_inst, u_box = unit_list.min_by { |(_k, b)| b[0][run_axis] }

        # The pitch is post-to-post, i.e. instance-to-instance - NOT the box
        # width, which can be a hair more or less than the pitch if the panel
        # overhangs or falls short of the next post.
        starts = unit_list.map { |(_k, b)| b[0][run_axis] }.sort
        pitch = starts.length >= 2 ? (starts[1] - starts[0]) : (u_box[1][run_axis] - u_box[0][run_axis])
        pitch = u_box[1][run_axis] - u_box[0][run_axis] if pitch <= 0.0

        closer = find_closer(boxes, run_axis, total_h) { |k| k.respond_to?(:definition) && k.definition == unit_def }

        {
          mode: :unit,
          pieces: [[unit_def, u_inst.transformation]],
          unit_min: u_box[0], unit_max: u_box[1],
          unit_along: pitch,
          unit_across: u_box[1][across] - u_box[0][across],
          unit_count_in_model: unit_list.length,
          closer_pieces: closer ? [[closer[0].respond_to?(:definition) ? closer[0].definition : nil, closer[0].transformation]].reject { |(d, _t)| d.nil? } : [],
          closer_min: closer ? closer[1][0] : nil,
          closer_max: closer ? closer[1][1] : nil
        }
      end

      # PARTS mode: find the posts, take the first bay, call that the unit.
      def parts_mode(boxes, run_axis, across, total_h)
        # Posts: tall, narrow along the run, and the same definition at least
        # twice. Among candidates, the tallest definition wins.
        by_def = Hash.new { |h, k| h[k] = [] }
        boxes.each do |(k, b)|
          next unless k.respond_to?(:definition) && k.definition
          along = b[1][run_axis] - b[0][run_axis]
          tall  = b[1][2] - b[0][2]
          next unless along < 12.0 && tall >= total_h * 0.5
          by_def[k.definition] << [k, b]
        end
        cands = by_def.select { |_d, l| l.length >= 2 }
        return nil if cands.empty?
        post_def, posts = cands.max_by { |_d, l| l.first[1][1][2] - l.first[1][0][2] }
        posts = posts.sort_by { |(_k, b)| b[0][run_axis] }

        centre = ->(b) { (b[0][run_axis] + b[1][run_axis]) / 2.0 }

        # DUPLICATE POSTS (2026-08-17, his vinyl fence). That file had two
        # copies of the same post standing in exactly the same place at x=0.
        # Left in, the first bay measured 0" wide, parts mode bailed out, and
        # the whole 198" model became the unit instead of one 96" bay. Two
        # posts closer than an inch are the SAME post: keep one, drop the rest.
        kept = []
        posts.each do |p|
          last = kept.last
          next if last && (centre.call(p[1]) - centre.call(last[1])).abs < 1.0
          kept << p
        end
        posts = kept
        return nil if posts.length < 2

        c0 = centre.call(posts[0][1])
        c1 = centre.call(posts[1][1])
        pitch = c1 - c0
        return nil if pitch <= 1.0

        # The first bay: the first post, plus every non-post part whose centre
        # sits between the first two post centres.
        first_post = posts[0]
        in_bay = boxes.select do |(k, b)|
          next false if k.respond_to?(:definition) && k.definition == post_def
          cx = centre.call(b)
          cx >= c0 - 0.01 && cx < c1 - 0.01
        end
        pieces = [[first_post[0].definition, first_post[0].transformation]]
        in_bay.each do |(k, _b)|
          d = k.respond_to?(:definition) ? k.definition : nil
          next if d.nil?
          pieces << [d, k.transformation]
        end

        # The unit box: from the first post's start, one pitch along; across
        # and height from everything in the bay.
        umin = first_post[1][0].dup
        umax = first_post[1][1].dup
        in_bay.each do |(_k, b)|
          3.times do |i|
            umin[i] = b[0][i] if b[0][i] < umin[i]
            umax[i] = b[1][i] if b[1][i] > umax[i]
          end
        end
        umax[run_axis] = umin[run_axis] + pitch

        last_post = posts.last
        {
          mode: :parts,
          pieces: pieces,
          unit_min: umin, unit_max: umax,
          unit_along: pitch,
          unit_across: umax[across] - umin[across],
          unit_count_in_model: posts.length - 1,
          closer_pieces: [[last_post[0].definition, last_post[0].transformation]],
          closer_min: last_post[1][0],
          closer_max: last_post[1][1],
          post_def: post_def
        }
      end

      # The lone tall narrow thing at the far end that is not part of the unit.
      def find_closer(boxes, run_axis, total_h)
        closer = nil
        boxes.each do |(k, b)|
          next if yield(k)
          along = b[1][run_axis] - b[0][run_axis]
          tall  = b[1][2] - b[0][2]
          next unless along < 12.0 && tall > total_h * 0.5
          closer = [k, b] if closer.nil? || b[0][run_axis] > closer[1][0][run_axis]
        end
        closer
      end

      def world_box(e, tr, depth = 0)
        return nil if depth > 8
        min = nil
        max = nil
        add = lambda do |p|
          a = [p.x.to_f, p.y.to_f, p.z.to_f]
          if min.nil?
            min = a.dup
            max = a.dup
          else
            3.times do |i|
              min[i] = a[i] if a[i] < min[i]
              max[i] = a[i] if a[i] > max[i]
            end
          end
        end
        t = tr * e.transformation
        sub = e.respond_to?(:definition) && e.definition ? e.definition.entities : e.entities
        sub.grep(Sketchup::Face).each { |f| f.vertices.each { |v| add.call(v.position.transform(t)) } }
        sub.each do |k|
          next unless k.is_a?(Sketchup::Group) || k.is_a?(Sketchup::ComponentInstance)
          b = world_box(k, t, depth + 1)
          next unless b
          add.call(Geom::Point3d.new(*b[0]))
          add.call(Geom::Point3d.new(*b[1]))
        end
        min ? [min, max] : nil
      rescue StandardError
        nil
      end

      # ----------------------------------------------------------- the layout
      #
      # How many units, and how much each is stretched. Pure numbers.
      # Two ways to make n units fill a length exactly (2026-08-17):
      #
      #   STRETCH  - n whole units, each scaled along the run so they fill.
      #              Fine when the unit is one bay (a few percent). Ugly when
      #              his file is three bays wide: a 240" fence stretched a
      #              180" unit by a third and he saw it at once.
      #   CUT      - whole units at their true size, and the remainder is ONE
      #              more unit sliced by a plane at the far end. Nothing is
      #              stretched, nothing needs recognising - a knife through
      #              whatever geometry is there. He approved this after the
      #              stretch was too big to live with (2026-08-17).
      #
      # CUT is OFF (2026-08-17, same day it was written): on his raw cable
      # railing the knife (intersect_with on 20k loose faces, some hidden)
      # hung SketchUp and popped "visible geometry merged with hidden". The
      # code stays, tested in rt63, for a model that is NOT raw. Turn it on
      # only after it has been watched on a small clean file first. A stretch
      # under SMALL_STRETCH is still preferred to a cut either way.
      USE_CUT       = false unless const_defined?(:USE_CUT, false)
      SMALL_STRETCH = 0.06  unless const_defined?(:SMALL_STRETCH, false)

      # HIS RULE (2026-08-17): post to post is 8 feet AT MOST. That is a
      # building rule, not a preference - a bay wider than 96" is wrong even
      # if it looks fine. So a unit is NEVER stretched past its true size.
      # The count is rounded UP and every bay is squeezed by the same amount
      # instead; he chose equal bays over "full bays plus a short last one".
      # MAX_STRETCH therefore no longer applies on this path.
      # NEVER_STRETCH = false brings back the old round-to-nearest.
      NEVER_STRETCH = true unless const_defined?(:NEVER_STRETCH, false)

      def layout_for(length)
        return nil unless @shape
        ua = @shape[:unit_along].to_f
        return nil if ua <= 0.0 || length < MIN_LEN

        n = (length / ua).round
        n = 1 if n < 1
        s = length / (n * ua)

        # A stretch nobody would notice: keep it, no seam.
        if !USE_CUT || (s - 1.0).abs <= SMALL_STRETCH
          if NEVER_STRETCH
            # Round UP, always. The tiny epsilon keeps an exact multiple from
            # becoming one bay too many on floating-point noise: 3 * 78.688
            # divides to 3.0000000000000004, and ceil would make that 4.
            n = ((length / ua) - 1e-9).ceil
            n = 1 if n < 1
            s = length / (n * ua)
          elsif s > MAX_STRETCH
            # Prefer one more unit slightly squeezed over one fewer badly
            # stretched - a fence with too few posts reads wrong at once.
            n += 1
            s = length / (n * ua)
          elsif s < MIN_STRETCH && n > 1
            n -= 1
            s = length / (n * ua)
          end
          return { n: n, stretch: s, unit: ua, pitch: ua * s, length: length,
                   whole: n, cut: 0.0 }
        end

        # CUT: as many whole units as fit, then the rest.
        whole = (length / ua).floor
        rest  = length - whole * ua
        # A sliver of a bay is worse than a hair of stretch: under a quarter
        # of a unit, stretch the whole ones instead of adding a stub.
        if rest < ua * 0.25 && whole >= 1
          s = length / (whole * ua)
          # ...but the 8-foot rule beats "avoid a sliver". Stretching the whole
          # units here is exactly how a 102" run over a 96" unit came out as
          # ONE 102" bay (caught by rt63, 2026-08-17). Add a bay instead.
          if NEVER_STRETCH && s > 1.0
            whole += 1
            s = length / (whole * ua)
          end
          return { n: whole, stretch: s, unit: ua, pitch: ua * s, length: length,
                   whole: whole, cut: 0.0 }
        end
        { n: whole + 1, stretch: 1.0, unit: ua, pitch: ua, length: length,
          whole: whole, cut: rest }
      end

      def refresh_ghost
        @ghost = nil
        return unless @p1 && @cursor && @shape
        len = @cursor.distance(@p1)
        lay = layout_for(len)
        return unless lay
        u, n = axes(@p1, @cursor)
        h = @shape[:height].to_f
        segs = []
        # A stroke per post: the whole units at their pitch, then the far end
        # of the run (which is the closer, whether the last unit is whole or
        # cut). Never a stroke past the cursor.
        whole = lay[:whole] || lay[:n]
        (0..whole).each do |i|
          d = i * lay[:pitch]
          next if d > len + 1e-6
          base = @p1.offset(u, d)
          segs << [base, base.offset(Geom::Vector3d.new(0, 0, 1), h)]
        end
        endp = @p1.offset(u, len)
        segs << [endp, endp.offset(Geom::Vector3d.new(0, 0, 1), h)]
        top = @p1.offset(Geom::Vector3d.new(0, 0, 1), h)
        segs << [top, top.offset(u, len)]
        segs << [@p1, endp]
        @ghost = segs
        msg = if lay[:cut].to_f > 0.0
                format("%s | %.2f' | %d whole + %.1f\" cut", @ref_name, len / 12.0, whole, lay[:cut])
              else
                format("%s | %.2f' | %d units, stretch %.1f%%", @ref_name, len / 12.0, lay[:n], (lay[:stretch] - 1.0) * 100.0)
              end
        Sketchup.set_status_text(msg, SB_PROMPT)
      rescue StandardError => e
        puts "[FenceRef] preview: #{e.class}: #{e.message}"
        @ghost = nil
      end

      def axes(a, b)
        dx = b.x - a.x
        dy = b.y - a.y
        len = Math.sqrt(dx * dx + dy * dy)
        u = Geom::Vector3d.new(dx / len, dy / len, 0)
        n = Geom::Vector3d.new(-u.y, u.x, 0)
        [u, n]
      end

      # ----------------------------------------------------------- building

      def build_it(view)
        model = Sketchup.active_model
        a = @p1
        b = @p2
        return reset_and_redraw(view) unless a && b && @shape

        begin
          if defined?(InteriorPro::WallTool) &&
             InteriorPro::WallTool.respond_to?(:apply_axis_magnet)
            a, b = InteriorPro::WallTool.apply_axis_magnet(a, b, model)
          end
        rescue StandardError => e
          puts "[FenceRef] axis magnet skipped: #{e.message}"
        end

        len = a.distance(b)
        lay = layout_for(len)
        unless lay
          UI.messagebox('That fence is too short to build.')
          return reset_and_redraw(view)
        end

        model.start_operation('Create Fence', true)
        begin
          group = place!(a, b, lay, model)
          model.commit_operation
          puts format('[FenceRef] built %s: %d units, stretch %.3f', @ref_name, lay[:n], lay[:stretch]) if group
        rescue StandardError => e
          model.abort_operation
          puts "[FenceRef] build failed: #{e.class}: #{e.message}\n" +
               Array(e.backtrace).first(6).join("\n")
          UI.messagebox("Could not build the fence: #{e.message}")
        end
        reset_and_redraw(view)
      end

      def reset_and_redraw(view)
        reset
        view.invalidate
        nil
      end

      # One instance of the unit per bay, plus the closer. Every instance is
      # his definition, untouched; only its transformation is ours.
      def place!(a, b, lay, model)
        group = model.active_entities.add_group
        group.name = 'LandscapePro_Fence'
        begin
          InteriorPro.assign_tag(group, 'LP/Fences')
        rescue StandardError
          nil
        end

        group.set_attribute(DICT, 'type', 'fence')
        group.set_attribute(DICT, 'kind', 'reference')
        group.set_attribute(DICT, 'reference', @ref_name)
        group.set_attribute(DICT, 'reference_path', @ref_path.to_s)
        group.set_attribute(DICT, 'start_x', a.x.to_f)
        group.set_attribute(DICT, 'start_y', a.y.to_f)
        group.set_attribute(DICT, 'end_x', b.x.to_f)
        group.set_attribute(DICT, 'end_y', b.y.to_f)
        group.set_attribute(DICT, 'ground_start', @ground_start.to_f)
        group.set_attribute(DICT, 'ground_end', @ground_end.to_f)
        group.set_attribute(DICT, 'length_in', lay[:length])
        group.set_attribute(DICT, 'units', lay[:n])
        group.set_attribute(DICT, 'stretch', lay[:stretch])
        group.set_attribute(DICT, 'unit_along', lay[:unit])
        group.set_attribute(DICT, 'height', @shape[:height].to_f)
        group.set_attribute(DICT, 'id', new_id)
        group.set_attribute(DICT, 'created_at', Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
        group.set_attribute(DICT, 'plugin_version', '0.2')

        ents = group.entities
        u, n = axes(a, b)

        # The frame that turns "model space" into "along this fence":
        #   1. slide the unit so its start sits at the origin and its centre
        #      line (across) sits on y=0
        #   2. if the model runs along Y, swap it onto X
        #   3. stretch along X by lay[:stretch]
        #   4. rotate X onto u, translate to the click point (+ ground)
        into_x = to_run_frame(@shape)

        # A unit may be ONE component (unit mode) or a LIST of his parts
        # (parts mode). Either way every piece keeps its own transformation
        # from his file; only the frame around it is ours.
        #
        # lay[:whole] units are placed as they are. If lay[:cut] > 0 there is
        # one more, the stub, sliced at the far end (see cut_stub!).
        whole = lay[:whole] || lay[:n]
        (0...whole).each do |i|
          gz = ground_at(i.to_f / lay[:n])
          @shape[:pieces].each_with_index do |(d, tr), j|
            place_one(ents, d, tr, into_x, lay[:stretch], a, u, n,
                      i * lay[:pitch], gz, "Unit #{i + 1}#{j.zero? ? '' : " part #{j}"}")
          end
        end

        if lay[:cut].to_f > 0.0
          gz = ground_at(whole.to_f / lay[:n])
          stub = ents.add_group
          stub.name = "Unit #{whole + 1} (cut)"
          @shape[:pieces].each_with_index do |(d, tr), j|
            place_one(stub.entities, d, tr, into_x, 1.0, a, u, n,
                      whole * lay[:pitch], gz, "part #{j}")
          end
          cut_stub!(stub, a, u, n, whole * lay[:pitch] + lay[:cut], model)
        end

        # The closer goes at the far end of the LAST unit, whole or cut.
        unless @shape[:closer_pieces].empty?
          gz = ground_at(1.0)
          # into_x already puts the closer where it sits in his model: just
          # past his LAST unit, i.e. at x = (units in model) * unit_along plus
          # whatever small inset it has. We want it at the end of OUR run
          # instead, so slide it by the difference between the two.
          end_along = whole * lay[:pitch] + lay[:cut].to_f
          along = end_along - @shape[:unit_count_in_model] * @shape[:unit_along]
          @shape[:closer_pieces].each do |(d, tr)|
            place_one(ents, d, tr, into_x, 1.0, a, u, n, along, gz, 'Closer')
          end
        end

        group
      end

      # model space -> unit-local run frame: unit start at x=0, its across
      # centre at y=0, its base at z=0, running along +X.
      def to_run_frame(shape)
        ra = shape[:run_axis]
        ac = shape[:across]
        umin = shape[:unit_min]
        umax = shape[:unit_max]
        cx = umin[ra]                        # unit start, along the run
        cy = (umin[ac] + umax[ac]) / 2.0     # unit centre, across
        # Z is HIS: whatever height he modelled the fence at is where it goes,
        # ground_start / ground_end are added on top. Sliding the lowest point
        # to zero would lift a fence whose anchor bolts hang below the plate
        # (his cable railing) 1.5" off the ground.
        cz = 0.0
        if ra == 0
          Geom::Transformation.translation(Geom::Vector3d.new(-cx, -cy, -cz))
        else
          # Y -> X: rotate -90 about Z, so +Y becomes +X and +X becomes -Y.
          # A model point (x, y) lands at (y, -x); the unit start (y = cx)
          # therefore lands at x = cx and the across centre (x = cy) at
          # y = -cy - so the slide AFTER the turn is (-cx, +cy).
          rot = Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0),
                                              Geom::Vector3d.new(0, 0, 1),
                                              -Math::PI / 2.0)
          Geom::Transformation.translation(Geom::Vector3d.new(-cx, cy, -cz)) * rot
        end
      end

      def place_one(ents, defn, own_tr, into_x, stretch, a, u, n, along, gz, name)
        stretch_t = Geom::Transformation.scaling(Geom::Point3d.new(0, 0, 0), stretch, 1.0, 1.0)
        # X onto u, Y onto n, Z up, origin at the click.
        frame = Geom::Transformation.axes(a.offset(u, along).offset(Geom::Vector3d.new(0, 0, gz)),
                                          u, n, Geom::Vector3d.new(0, 0, 1))
        inst = ents.add_instance(defn, frame * stretch_t * into_x * own_tr)
        inst.name = name
        inst
      end

      # Slice a placed unit at a plane across the run, keep the near side.
      #
      # This is a knife, not a reader: it does not know what a post or a
      # cable is, so it cannot get that wrong. It explodes the stub group down
      # to loose geometry (component instances inside are made unique first,
      # so his library definitions are never edited), intersects it with a
      # big face on the plane, and erases everything whose far edge is beyond
      # the plane. What is left is his fence, cut clean.
      def cut_stub!(stub, a, u, n, along, model)
        return unless stub && stub.valid?
        origin = a.offset(u, along)
        far = lambda do |pt|
          # signed distance along u from the plane
          (pt.x - origin.x) * u.x + (pt.y - origin.y) * u.y
        end

        # Explode everything down to faces and edges, keeping his definitions
        # untouched by making the instances unique first.
        3.times do
          insts = stub.entities.to_a.select { |e| e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group) }
          break if insts.empty?
          insts.each do |i|
            next unless i.valid?
            i.make_unique if i.respond_to?(:make_unique)
            i.explode
          end
        end

        # A knife: one big face on the cutting plane, in its own group.
        big = 10_000.0
        up  = Geom::Vector3d.new(0, 0, 1)
        knife = model.active_entities.add_group
        knife.entities.add_face([
          origin.offset(n, -big).offset(up, -big),
          origin.offset(n,  big).offset(up, -big),
          origin.offset(n,  big).offset(up,  big),
          origin.offset(n, -big).offset(up,  big)
        ])
        begin
          stub.entities.intersect_with(false, stub.transformation, stub.entities,
                                       stub.transformation, true, knife.entities.to_a)
        rescue StandardError => e
          puts "[FenceRef] cut: intersect failed: #{e.message}"
        ensure
          knife.erase! if knife.valid?
        end

        # Anything wholly beyond the plane goes. Faces are judged by their
        # vertices; edges by their two ends. A tiny tolerance keeps the new
        # cut faces (which sit exactly on the plane) on the near side.
        tol = 1e-4
        gone = []
        stub.entities.each do |e|
          pts = if e.is_a?(Sketchup::Face) then e.vertices.map(&:position)
                elsif e.is_a?(Sketchup::Edge) then [e.start.position, e.end.position]
                else next
                end
          gone << e if pts.all? { |p| far.call(p) > tol }
        end
        stub.entities.erase_entities(gone) unless gone.empty?
      rescue StandardError => e
        puts "[FenceRef] cut_stub!: #{e.class}: #{e.message}"
      end

      def ground_at(f)
        @ground_start.to_f + (@ground_end.to_f - @ground_start.to_f) * f
      end

      def new_id
        "fence-#{Time.now.to_i.to_s(36)}-#{rand(36**4).to_s(36)}"
      end

    end
  end
end
