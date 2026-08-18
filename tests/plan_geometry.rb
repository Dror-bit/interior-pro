# encoding: utf-8
# plan_geometry.rb - anything you drew by hand in SketchUp, onto the sheet.
#
# The plugin's own walls, doors and windows carry attributes, so the plan can
# be worked out from them. A back yard modelled by hand carries nothing - it
# is just edges. This file takes those edges, flattens them to the ground and
# writes them into the drawing document as a layer of its own.
#
# What you get is a PICTURE, not information: lines on paper. No schedules, no
# dimensions that follow the model, no material lists. Those need real
# elements. The day the back yard is built with proper tools, turn this layer
# off and nothing else changes.
#
# Nothing here touches the model. It only reads.

require File.join(File.dirname(__FILE__), 'plan_doc') unless
  defined?(InteriorPro::PlanDoc)

module InteriorPro
  module PlanGeometry
    LAYER = 'SITE' unless const_defined?(:LAYER, false)

    MAX_DEPTH  = 8      unless const_defined?(:MAX_DEPTH, false)
    MAX_EDGES  = 60_000 unless const_defined?(:MAX_EDGES, false)
    MIN_LEN    = 0.25   unless const_defined?(:MIN_LEN, false)   # inches
    GRID       = 16.0   unless const_defined?(:GRID, false)      # 1/16" for de-duping

    # The plugin's own things are drawn from their attributes, so they must not
    # come in here a second time as raw edges.
    OWN_TYPES = %w[wall door window room floor ceiling roof foundation
                   molding plan2d].freeze unless const_defined?(:OWN_TYPES, false)

    class << self
      # ------------------------------------------------------------- pure part

      # edges: [[[x,y,z],[x,y,z]], ...] in world inches.
      # Returns polyline point pairs, flattened to the ground, de-duped.
      def flatten(edges, opts = {})
        zmin = opts[:z_min]
        zmax = opts[:z_max]
        seen = {}
        out  = []
        edges.each do |a, b|
          next if zmax && a[2] > zmax && b[2] > zmax
          next if zmin && a[2] < zmin && b[2] < zmin
          x1 = a[0].to_f
          y1 = a[1].to_f
          x2 = b[0].to_f
          y2 = b[1].to_f
          next if Math.hypot(x2 - x1, y2 - y1) < MIN_LEN
          k = key(x1, y1, x2, y2)
          next if seen[k]
          seen[k] = true
          out << [[x1, y1], [x2, y2]]
        end
        out
      end

      # Two edges that land on the same line after flattening are one line on
      # paper. Rounded to 1/16" so floating point noise does not fool it.
      def key(x1, y1, x2, y2)
        a = [(x1 * GRID).round, (y1 * GRID).round]
        b = [(x2 * GRID).round, (y2 * GRID).round]
        (a <=> b) <= 0 ? [a, b] : [b, a]
      end

      # ------------------------------------------------------- reading the model

      def own?(entity)
        t = entity.get_attribute('InteriorPro', 'type')
        !t.nil? && OWN_TYPES.include?(t.to_s)
      rescue StandardError
        false
      end

      # One awkward entity must not lose the whole selection.
      #
      # On 2026-08-14 the user's console showed, twice:
      #
      #   [Sheet] add_selection: no implicit conversion to Transformation
      #
      # and the button did nothing at all. Whatever raised it, thousands of
      # perfectly good edges were thrown away with it. The cause is still
      # unknown - there was no backtrace to read - so this does not pretend to
      # fix it. It makes it survivable and countable: the entity that misbehaves
      # is skipped, the rest go through, and the window says how many were
      # skipped instead of quietly showing less of the yard than there is.
      def skipped
        @skipped ||= 0
      end

      def harvest(entities, xform, out, opts, depth = 0)
        return out if depth > MAX_DEPTH || out.length > MAX_EDGES
        entities.each do |e|
          break if out.length > MAX_EDGES
          begin
            next unless e.respond_to?(:valid?) ? e.valid? : true
            if e.is_a?(Sketchup::Edge)
              next if opts[:hide_soft] && soft?(e)
              a = e.start.position
              b = e.end.position
              # nil is NOT a transformation in SketchUp - it raises. At the top
              # level there simply is nothing to apply (2026-08-13).
              if xform
                a = a.transform(xform)
                b = b.transform(xform)
              end
              out << [[a.x.to_f, a.y.to_f, a.z.to_f], [b.x.to_f, b.y.to_f, b.z.to_f]]
            elsif e.is_a?(Sketchup::Group)
              next if depth.zero? && own?(e)
              harvest(e.entities, mul(xform, e.transformation), out, opts, depth + 1)
            elsif defined?(Sketchup::ComponentInstance) && e.is_a?(Sketchup::ComponentInstance)
              next if depth.zero? && own?(e)
              harvest(e.definition.entities, mul(xform, e.transformation), out, opts, depth + 1)
            end
          rescue StandardError => err
            @skipped = skipped + 1
            # The first few say what and where. After that it would be noise.
            if @skipped <= 3
              puts "[PlanGeometry] skipped #{e.class}: #{err.class}: #{err.message}"
              puts "  #{Array(err.backtrace).first(3).join("\n  ")}"
            end
          end
        end
        out
      end

      def soft?(e)
        (e.respond_to?(:soft?) && e.soft?) || (e.respond_to?(:smooth?) && e.smooth?)
      rescue StandardError
        false
      end

      # Multiplying two placements together. Either side may be missing - the
      # top level has no placement of its own - and either side may turn out not
      # to be a placement at all, which is what raises
      # "no implicit conversion to Transformation". Rather than lose the branch,
      # keep whichever side IS usable and carry on.
      def mul(a, b)
        return b if a.nil?
        return a if b.nil?
        a * b
      rescue StandardError => e
        puts "[PlanGeometry] cannot combine placements (#{e.class}: #{e.message}); " \
             "keeping the outer one"
        a
      end

      # ------------------------------------------------------------- the layer

      # Which things in the model to draw. Stored as persistent ids so the
      # choice survives closing SketchUp.
      def pids_from(entities)
        entities.map do |e|
          next nil unless e.respond_to?(:persistent_id)
          begin
            e.persistent_id
          rescue StandardError
            nil
          end
        end.compact.uniq
      end

      # SketchUp 2021 and up can look a persistent id straight up, and it finds
      # things nested inside groups too. The old scan only ever saw the top
      # level, which is why a selection made inside a group came back empty
      # (2026-08-13).
      def entities_for(model, pids)
        wanted = Array(pids).map(&:to_i)
        return [] if wanted.empty?
        if model.respond_to?(:find_entity_by_persistent_id)
          begin
            found = Array(model.find_entity_by_persistent_id(*wanted)).compact
            return found unless found.empty?
          rescue StandardError => e
            puts "[PlanGeometry] find_entity_by_persistent_id: #{e.message}"
          end
        end
        set = {}
        wanted.each { |i| set[i] = true }
        model.entities.to_a.select do |e|
          e.respond_to?(:persistent_id) &&
            begin
              set[e.persistent_id]
            rescue StandardError
              false
            end
        end
      end

      # Take the lines NOW, while the entities are in our hands.
      #
      # Looking them up again later by persistent id turned out not to work on
      # the user's model (2026-08-13: 4632 selected, 0 found), and there is no
      # need for it - a hand-drawn back yard is a snapshot anyway. Press the
      # button again after changing it.
      #
      # Returns [[[x1,y1],[x2,y2]], ...] in model inches, rounded to 1/100".
      def snapshot(entities, opts = {})
        o = { hide_soft: opts.key?(:hide_soft) ? opts[:hide_soft] : true,
              z_min: opts[:z_min], z_max: opts[:z_max] }
        edges = []
        @skipped = 0
        Array(entities).each do |e|
          next if e.respond_to?(:get_attribute) && own?(e)
          harvest([e], nil, edges, o, 0)
        end
        @last_report = { asked: Array(entities).length, found: Array(entities).length,
                         edges: edges.length, lines: 0, skipped: skipped }
        lines = flatten(edges, o).map do |a, b|
          [[a[0].round(2), a[1].round(2)], [b[0].round(2), b[1].round(2)]]
        end
        @last_report[:lines] = lines.length
        lines
      end

      # Writes the layer into the canvas. opts:
      #   lines     - what snapshot gave us, the normal road
      #   pids      - which top level things to take (nil = everything not ours)
      #   z_min     - inches, ignore anything entirely below this
      #   z_max     - inches, ignore anything entirely above this
      #   hide_soft - leave out the softened edges inside curved surfaces
      # What the last build! saw, so the window can say where it went wrong
      # instead of just showing an empty page.
      def last_report
        @last_report ||= { asked: 0, found: 0, edges: 0, lines: 0, skipped: 0 }
      end

      def build!(model, canvas, opts = {})
        # Do not leave an empty layer lying about - the checkbox list should
        # only show what is really on the sheet.
        old = canvas.layers.find { |l| l.name == LAYER }
        canvas.layers.delete(old) if old

        # The normal road: lines taken when the user pressed the button.
        lines = Array(opts[:lines])

        if lines.empty? && opts[:pids] && !Array(opts[:pids]).empty?
          asked = Array(opts[:pids]).length
          list  = entities_for(model, opts[:pids])
          @last_report = { asked: asked, found: list.length, edges: 0, lines: 0 }
          return nil if list.empty?
          o = { hide_soft: opts.key?(:hide_soft) ? opts[:hide_soft] : true,
                z_min: opts[:z_min], z_max: opts[:z_max] }
          edges = []
          list.each { |e| harvest([e], nil, edges, o, 0) }
          lines = flatten(edges, o)
          @last_report[:edges] = edges.length
          @last_report[:lines] = lines.length
        end
        return nil if lines.empty?

        lay = canvas.layer(LAYER)
        lines.each { |pts| lay.polyline(pts, weight: 0.010) }
        lay
      end

      def count(canvas)
        l = canvas.layers.find { |x| x.name == LAYER }
        l ? l.shapes.length : 0
      end
    end
  end
end
