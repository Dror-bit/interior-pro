# fix_wall_ends.rb - close corners whose two ends drifted apart (2026-08-17).
#
# WHAT IT DOES
#   Ends that should be one point, but sit a fraction of an inch apart, are
#   invisible to the corner code: find_neighbor_at matches DRAWN ends within
#   0.001". So no miter is cut and the end stays a plain square cap - and only
#   the long faces of a wall get painted, so that cap shows up white.
#   This welds each such pair to the point exactly between them, rebuilds the
#   two walls, and re-joins the corners around them.
#
# IT ONLY TOUCHES PAIRS THAT ARE REALLY THE SAME CORNER:
#   - same storey (a wall below stands on the same footprint by definition)
#   - same anchor side (a left-anchored and a right-anchored wall have their
#     drawn lines a full thickness apart even when the corner is perfect -
#     that is not drift, and welding them would BREAK a good corner)
#   - closer together than a wall thickness, so a gap you drew on purpose is
#     never closed behind your back
#
# HOW TO RUN - it shows you everything before it touches anything.
#
#   1) Preview only (changes nothing):
#      load 'C:/Users/rordt/AppData/Roaming/SketchUp/SketchUp 2024/SketchUp/Plugins/interior_pro/fix_wall_ends.rb'
#
#   2) Do it (one undo step - Ctrl+Z puts everything back):
#      InteriorPro::FixWallEnds.run(apply: true)
#
# Either way it writes fix_ends_report.txt beside this file.

module InteriorPro
  module FixWallEnds
    OUT = File.join(File.dirname(__FILE__), 'fix_ends_report.txt')

    # Two ends further apart than a wall thickness are a gap the user drew on
    # purpose; closer than that, on the same storey and the same anchor side,
    # is drift. Measured against this model: a thickness catches all three
    # broken corners and nothing else, and doubling it finds nothing new.
    SAME = 0.001       # inches - already one point, nothing to do

    def self.at(g, k)
      g.get_attribute('InteriorPro', k)
    rescue StandardError
      nil
    end

    def self.wp(g, x, y)
      Geom::Point3d.new(x.to_f, y.to_f, 0).transform(g.transformation)
    end

    def self.d2(a, b)
      Math.sqrt((a.x.to_f - b.x.to_f)**2 + (a.y.to_f - b.y.to_f)**2)
    end

    def self.ps(p)
      "(#{p.x.to_f.round(3)},#{p.y.to_f.round(3)})"
    end

    def self.walls
      Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && at(g, 'type') == 'wall'
      end
    end

    def self.h_anchor_of(g)
      (at(g, 'anchor') || 'bottom-center').to_s.split('-').last
    end

    # World footprint of a wall, from its stored corners.
    def self.footprint(g)
      flat = at(g, 'corners_xy')
      return nil unless flat.is_a?(Array) && flat.length == 8
      flat.each_slice(2).map { |x, y| wp(g, x, y) }
    end

    def self.gap(a, b)
      fa = footprint(a)
      fb = footprint(b)
      return nil unless fa && fb
      fa.product(fb).map { |p, q| d2(p, q) }.min
    end

    # Every wall end, in world coordinates.
    def self.all_ends(ws)
      out = []
      ws.each_with_index do |g, i|
        sx = at(g, 'start_x'); sy = at(g, 'start_y')
        ex = at(g, 'end_x');   ey = at(g, 'end_y')
        next if sx.nil? || ex.nil?
        th = at(g, 'thickness').to_f
        out << { i: i, g: g, which: :start, p: wp(g, sx, sy), th: th,
                 lvl: (at(g, 'level') || 1).to_i, anc: h_anchor_of(g) }
        out << { i: i, g: g, which: :end, p: wp(g, ex, ey), th: th,
                 lvl: (at(g, 'level') || 1).to_i, anc: h_anchor_of(g) }
      end
      out
    end

    # Pairs that belong to the same corner but are not the same point.
    def self.find_pairs(ends)
      pairs = []
      ends.each_with_index do |a, ia|
        ends.each_with_index do |b, ib|
          next if ib <= ia
          next if a[:i] == b[:i]              # the same wall's own two ends
          next unless a[:lvl] == b[:lvl]
          next unless a[:anc] == b[:anc]      # mixed anchors are NOT drift
          max_weld = [a[:th], b[:th]].max
          max_weld = 1.0 if max_weld < 1.0
          d = d2(a[:p], b[:p])
          next if d <= SAME || d > max_weld
          pairs << { a: a, b: b, d: d }
        end
      end
      pairs.sort_by { |x| -x[:d] }
    end

    # Every end that lands on the same welded point moves together, so a
    # corner where three walls meet ends up as ONE point, not three.
    def self.clusters(pairs)
      groups = []
      pairs.each do |pr|
        hit = groups.select do |gr|
          gr.any? { |e| e[:g] == pr[:a][:g] && e[:which] == pr[:a][:which] } ||
            gr.any? { |e| e[:g] == pr[:b][:g] && e[:which] == pr[:b][:which] }
        end
        if hit.empty?
          groups << [pr[:a], pr[:b]]
        else
          merged = hit.flatten
          merged << pr[:a] unless merged.any? { |e| e[:g] == pr[:a][:g] && e[:which] == pr[:a][:which] }
          merged << pr[:b] unless merged.any? { |e| e[:g] == pr[:b][:g] && e[:which] == pr[:b][:which] }
          groups -= hit
          groups << merged
        end
      end
      groups
    end

    def self.centre(list)
      Geom::Point3d.new(
        list.map { |e| e[:p].x.to_f }.inject(:+) / list.length,
        list.map { |e| e[:p].y.to_f }.inject(:+) / list.length,
        0
      )
    end

    # WHO IS THE ONE THAT DRIFTED, measured instead of guessed.
    #
    # A wall end that sits exactly on a wall end of the storey BELOW is the
    # one the user lined up on purpose - stacking the upstairs wall over the
    # downstairs one is the thing he was doing when this broke. That end is
    # the anchor: it does not move, and the drifted end comes to it.
    #
    # Nothing to lean on (no storey below, or both ends anchored, or neither)
    # -> the point exactly between them, which moves each of them least.
    #
    # Do NOT decide this by which coordinate looks rounder. This house is
    # drawn on angles; no wall in it runs along an axis.
    def self.anchored?(e, ends)
      return false if e[:lvl] <= 1
      ends.any? do |o|
        o[:lvl] == e[:lvl] - 1 && d2(o[:p], e[:p]) <= 0.01
      end
    end

    def self.target_for(gr, ends)
      anchors = gr.select { |e| anchored?(e, ends) }
      return [centre(gr), :midpoint] unless anchors.length == 1
      [anchors.first[:p], :"anchored on the storey below"]
    end

    def self.rebuild!(wt, g)
      data = wt.wall_data(g)
      return false unless data
      corners = wt.perpendicular_corners_xy(
        Geom::Point3d.new(data[:drawn_start][0], data[:drawn_start][1], 0),
        Geom::Point3d.new(data[:drawn_end][0],   data[:drawn_end][1],   0),
        data[:thickness], data[:h_anchor]
      )
      return false unless corners
      wt.save_corners_attr(g, corners)
      wt.rebuild_wall_geometry(g, corners, data)
      true
    end

    def self.run(apply: false)
      out = []
      out << "InteriorPro fix_wall_ends  #{Time.now}"
      out << (apply ? '*** APPLY - the model is being changed ***' : 'PREVIEW ONLY - nothing is changed')
      out << ''

      ws = walls
      pairs = find_pairs(all_ends(ws))
      cls = clusters(pairs)

      out << "#{ws.length} wall(s), #{pairs.length} drifted pair(s), #{cls.length} corner(s) to weld"
      out << ''

      if cls.empty?
        out << 'Nothing to do - every corner already meets at one point.'
        File.open(OUT, 'w') { |fh| fh.puts(out.join("\n")) }
        puts "[fix_ends] nothing to do. wrote #{OUT}"
        return 0
      end

      # ---- what is about to happen, measured before anything moves --------
      before = {}
      all = all_ends(ws)
      cls.each_with_index do |gr, n|
        tgt, why = target_for(gr, all)
        out << "corner #{n + 1}: weld to #{ps(tgt)}  (level #{gr.first[:lvl]}, #{why})"
        gr.each do |e|
          out << format('    w%-3d %-5s moves %s"  %s -> %s',
                        e[:i], e[:which] == :start ? 'START' : 'END',
                        d2(e[:p], tgt).round(3), ps(e[:p]), ps(tgt))
          op = at(e[:g], 'door_openings')
          out << '      (this wall hosts openings - they are re-cut on rebuild)' if op.is_a?(Array) && !op.empty?
        end
        gr.combination(2).each do |a, b|
          g0 = gap(a[:g], b[:g])
          before["#{n}-#{a[:i]}-#{b[:i]}"] = g0
          out << format('    gap between w%d and w%d now: %s"', a[:i], b[:i], g0.nil? ? '?' : g0.round(3))
        end
        out << ''
      end

      unless apply
        out << 'To do it, paste this in the Ruby Console:'
        out << '  InteriorPro::FixWallEnds.run(apply: true)'
        File.open(OUT, 'w') { |fh| fh.puts(out.join("\n")) }
        puts "[fix_ends] PREVIEW: #{cls.length} corner(s) would be welded. wrote #{OUT}"
        return cls.length
      end

      # ---- do it, in ONE undo step ----------------------------------------
      model = Sketchup.active_model
      wt = InteriorPro::WallTool.new
      touched = []
      model.start_operation('InteriorPro Close Wall Corners', true)
      begin
        all_now = all_ends(ws)
        cls.each do |gr|
          tgt, = target_for(gr, all_now)
          gr.each do |e|
            local = tgt.transform(e[:g].transformation.inverse)
            if e[:which] == :start
              e[:g].set_attribute('InteriorPro', 'start_x', local.x.to_f)
              e[:g].set_attribute('InteriorPro', 'start_y', local.y.to_f)
            else
              e[:g].set_attribute('InteriorPro', 'end_x', local.x.to_f)
              e[:g].set_attribute('InteriorPro', 'end_y', local.y.to_f)
            end
            touched << e[:g] unless touched.include?(e[:g])
          end
        end

        # Fresh square corners first - join_corners miters from these.
        touched.each { |g| rebuild!(wt, g) }

        # Re-join the moved walls and everything that shares a point with
        # them. Two passes: a neighbour's cut can change what the first one
        # should have been (the fix_corners_once pattern).
        neigh = []
        ends = all_ends(ws)
        touched.each do |g|
          ends.each do |e|
            next if e[:g] == g
            next unless (at(e[:g], 'level') || 1).to_i == (at(g, 'level') || 1).to_i
            gp = gap(g, e[:g])
            neigh << e[:g] if gp && gp < 1.0 && !neigh.include?(e[:g])
          end
        end
        ring = (touched + neigh).uniq
        2.times { ring.each { |g| wt.join_corners(g, model) if g.valid? } }
        model.commit_operation
      rescue StandardError => e
        model.abort_operation rescue nil
        out << "FAILED, nothing changed: #{e.class}: #{e.message}"
        out += e.backtrace.first(5)
        File.open(OUT, 'w') { |fh| fh.puts(out.join("\n")) }
        puts "[fix_ends] FAILED: #{e.message}"
        return 0
      end

      # ---- prove it worked -------------------------------------------------
      out << '== AFTER =='
      still = find_pairs(all_ends(walls))
      out << "  drifted pairs left: #{still.length}"
      still.each { |x| out << format('    w%d <-> w%d still %s" apart', x[:a][:i], x[:b][:i], x[:d].round(3)) }
      out << format('  walls rebuilt: %d', touched.length)
      out << ''
      out << 'If it looks wrong in SketchUp, Ctrl+Z once puts everything back.'

      File.open(OUT, 'w') { |fh| fh.puts(out.join("\n")) }
      puts "[fix_ends] welded #{cls.length} corner(s), #{still.length} left. wrote #{OUT}"
      cls.length
    rescue StandardError => e
      puts "[fix_ends] FAILED: #{e.class}: #{e.message}"
      puts e.backtrace.first(6)
      0
    end
  end
end

InteriorPro::FixWallEnds.run(apply: false)
