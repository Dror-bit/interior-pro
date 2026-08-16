# encoding: utf-8
# Landscape Pro - Fence maths (2026-08-15)
#
# PURE NUMBERS. No SketchUp API, no model, no geometry, no materials. Plain
# numbers in, plain numbers out - exactly like arc_math.rb, and for the same
# reason: the maths can be proved right in the cloud, before a single line of
# it is allowed near the model. If this file needs SketchUp to be tested, it
# has already gone wrong.
#
# WHY A FENCE IS NOT A WALL
#
# A wall is one solid box with a flat top, and the whole plugin is built on
# that: build_wall_group pushpulls a face straight up. A fence is a row of
# POSTS with BAYS between them, and its top does not have to be flat - it
# follows the ground. So it gets its own maths rather than bending the wall.
#
# THE GROUND, TODAY AND LATER
#
# Every function here takes the ground height at the two ends (z0, z1) as
# ordinary numbers. Today the tool always passes 0 and 0, so the fence is
# level and nothing looks different from a wall. The day topography exists,
# the terrain fills those two numbers in and the SAME code makes the fence
# run downhill. That is the whole point of storing two numbers instead of one
# ground_z: a single number can never slope.
#
# THE TWO WAYS A FENCE CROSSES A SLOPE (both are real, both are built here)
#
#   :rake - the fence follows the ground. Each panel is a parallelogram, its
#           top parallel to the slope. This is what a good wood fence does.
#   :step - each panel stays LEVEL and steps down at every post, like stairs.
#           This is what a panel fence or a masonry fence has to do, because
#           a preassembled panel cannot be tilted.
#
# Both are implemented. Which one is the default is the user's call, not this
# file's - the tool passes it in.

module InteriorPro
  module Landscape
    module FenceMath

      # A run shorter than this is a mis-click, not a fence.
      MIN_LEN = 1.0 unless const_defined?(:MIN_LEN, false)

      # Longest bay we will leave between two posts, in inches. 8 feet is the
      # ordinary residential spacing.
      DEFAULT_SPACING = 96.0 unless const_defined?(:DEFAULT_SPACING, false)

      DEFAULT_HEIGHT = 72.0 unless const_defined?(:DEFAULT_HEIGHT, false)

      MODES = [:rake, :step].freeze unless const_defined?(:MODES, false)

      # Below this the two ends count as the same height and the fence is
      # treated as dead level, so a flat fence can never pick up a hair of
      # slope from floating point noise.
      FLAT_TOL = 1e-6 unless const_defined?(:FLAT_TOL, false)

      # ------------------------------------------------------------ basics

      # Plan length of the run - the ground height is deliberately NOT in it.
      # A fence is laid out from above: posts are spaced by their spacing on
      # the plan, the way a person measures with a tape on the site, not by
      # the longer sloped distance.
      def self.length_xy(sx, sy, ex, ey)
        dx = ex.to_f - sx.to_f
        dy = ey.to_f - sy.to_f
        Math.sqrt(dx * dx + dy * dy)
      end

      # How many bays a run of this length needs so that no bay is longer
      # than max_spacing. Always at least 1 - a 3" fence is still one bay,
      # not zero.
      def self.bay_count(length, max_spacing = DEFAULT_SPACING)
        len = length.to_f
        sp  = max_spacing.to_f
        return 1 if len <= 0.0 || sp <= 0.0
        n = (len / sp).ceil
        n < 1 ? 1 : n
      end

      # Where the posts stand, as distances along the run starting at 0.
      # Evenly divided: every bay identical, both ends carrying a post. Even
      # bays are not a nicety - an odd short bay at the end is the thing that
      # makes a fence look home-made.
      def self.post_stations(length, max_spacing = DEFAULT_SPACING)
        len = length.to_f
        return [0.0] if len < MIN_LEN
        n = bay_count(len, max_spacing)
        step = len / n
        (0..n).map { |i| i == n ? len : i * step }
      end

      # Ground height at a distance t along the run. Straight line between
      # the two ends - which is all a straight fence can know today, and
      # exactly what terrain will hand it later.
      def self.ground_z(t, length, z0, z1)
        len = length.to_f
        a = z0.to_f
        b = z1.to_f
        return a if len <= 0.0
        f = t.to_f / len
        f = 0.0 if f < 0.0
        f = 1.0 if f > 1.0
        a + (b - a) * f
      end

      # The XY point at distance t along the run.
      def self.point_at(sx, sy, ex, ey, t)
        len = length_xy(sx, sy, ex, ey)
        return [sx.to_f, sy.to_f] if len <= 0.0
        f = t.to_f / len
        [sx.to_f + (ex.to_f - sx.to_f) * f,
         sy.to_f + (ey.to_f - sy.to_f) * f]
      end

      # True when both ends sit at the same height, so no slope work is
      # needed and rake and step must give identical answers.
      def self.flat?(z0, z1)
        (z1.to_f - z0.to_f).abs < FLAT_TOL
      end

      # Signed slope of the run, in degrees, positive when it climbs from
      # start to end. For the status bar and for the report - nothing here
      # makes a decision from it.
      def self.slope_deg(length, z0, z1)
        len = length.to_f
        return 0.0 if len <= 0.0
        Math.atan2(z1.to_f - z0.to_f, len) * 180.0 / Math::PI
      end

      # ------------------------------------------------------------ layout
      #
      # The one function the tool calls. Everything above is a piece of it,
      # kept public so a test can pin each piece on its own.
      #
      # opts:
      #   :height       fence height ABOVE THE GROUND, inches (default 72)
      #   :max_spacing  longest bay, inches (default 96)
      #   :mode         :rake or :step (default :rake)
      #   :z0, :z1      ground height at start / end, inches (default 0, 0)
      #   :embed        how far the posts go INTO the ground (default 0)
      #   :gap_below    ground clearance under the panels (default 0)
      #
      # Returns nil for a run too short to be a fence - the caller must check.
      def self.layout(sx, sy, ex, ey, opts = {})
        len = length_xy(sx, sy, ex, ey)
        return nil if len < MIN_LEN

        height      = (opts[:height]      || DEFAULT_HEIGHT).to_f
        max_spacing = (opts[:max_spacing] || DEFAULT_SPACING).to_f
        z0          = (opts[:z0]          || 0.0).to_f
        z1          = (opts[:z1]          || 0.0).to_f
        embed       = (opts[:embed]       || 0.0).to_f
        gap_below   = (opts[:gap_below]   || 0.0).to_f
        mode        = (opts[:mode]        || :rake).to_sym
        mode        = :rake unless MODES.include?(mode)

        # A level fence has no steps to take, so both modes collapse to the
        # same thing. Saying so out loud here means the step branch can never
        # introduce a rounding difference on a flat run.
        mode = :rake if flat?(z0, z1)

        return nil if height <= 0.0

        stations = post_stations(len, max_spacing)

        # Every post first: where it is, and what the ground does there.
        posts = stations.each_with_index.map do |t, i|
          gz = ground_z(t, len, z0, z1)
          x, y = point_at(sx, sy, ex, ey, t)
          { i: i, t: t, x: x, y: y, ground_z: gz,
            z_base: gz - embed,
            z_top: nil }              # filled in below - it depends on mode
        end

        # Then the bays between them.
        bays = []
        (0...(posts.length - 1)).each do |i|
          a = posts[i]
          b = posts[i + 1]
          if mode == :step
            # A level panel. It sits at the HIGHER of its two ends, so the
            # fence never dips into the ground on the uphill side. The gap
            # that opens underneath on the downhill side is what a stepped
            # fence looks like, and is correct.
            top = [a[:ground_z], b[:ground_z]].max + height
            top0 = top
            top1 = top
          else
            top0 = a[:ground_z] + height
            top1 = b[:ground_z] + height
          end
          bays << { i: i,
                    t0: a[:t], t1: b[:t], span: b[:t] - a[:t],
                    x0: a[:x], y0: a[:y], x1: b[:x], y1: b[:y],
                    z_bottom0: a[:ground_z] + gap_below,
                    z_bottom1: b[:ground_z] + gap_below,
                    z_top0: top0, z_top1: top1,
                    level: (top0 - top1).abs < FLAT_TOL }
        end

        # A post must reach the top of every panel it carries, otherwise a
        # stepped fence shows a panel floating above its own post.
        posts.each do |p|
          tops = []
          bays.each do |bay|
            tops << bay[:z_top0] if bay[:i] == p[:i]
            tops << bay[:z_top1] if bay[:i] == p[:i] - 1
          end
          tops << p[:ground_z] + height if tops.empty?
          p[:z_top] = tops.max
        end

        { length: len,
          mode: mode,
          height: height,
          z0: z0, z1: z1,
          slope_deg: slope_deg(len, z0, z1),
          flat: flat?(z0, z1),
          bay_span: bays.empty? ? 0.0 : bays.first[:span],
          posts: posts,
          bays: bays }
      end

      # ------------------------------------------------- inside one bay
      #
      # Everything above lays out the fence. What follows fills a single bay
      # with boards, so the tool never has to work out a height of its own.

      DEFAULT_POST_SIZE  = 4.0  unless const_defined?(:DEFAULT_POST_SIZE, false)
      DEFAULT_BOARD_W    = 5.5  unless const_defined?(:DEFAULT_BOARD_W, false)
      DEFAULT_BOARD_GAP  = 0.0  unless const_defined?(:DEFAULT_BOARD_GAP, false)
      DEFAULT_BOARD_T    = 0.75 unless const_defined?(:DEFAULT_BOARD_T, false)

      # A board narrower than this is a splinter, not a board.
      MIN_BOARD_W = 0.5 unless const_defined?(:MIN_BOARD_W, false)

      # The top of a raked bay at any distance t along the run. On a stepped
      # bay both ends are equal, so this returns that same level everywhere -
      # which is why the board builder needs no mode of its own.
      def self.top_at(bay, t)
        t0 = bay[:t0].to_f
        t1 = bay[:t1].to_f
        return bay[:z_top0].to_f if (t1 - t0).abs < FLAT_TOL
        f = (t.to_f - t0) / (t1 - t0)
        f = 0.0 if f < 0.0
        f = 1.0 if f > 1.0
        bay[:z_top0].to_f + (bay[:z_top1].to_f - bay[:z_top0].to_f) * f
      end

      # Same, for the bottom edge.
      def self.bottom_at(bay, t)
        t0 = bay[:t0].to_f
        t1 = bay[:t1].to_f
        return bay[:z_bottom0].to_f if (t1 - t0).abs < FLAT_TOL
        f = (t.to_f - t0) / (t1 - t0)
        f = 0.0 if f < 0.0
        f = 1.0 if f > 1.0
        bay[:z_bottom0].to_f + (bay[:z_bottom1].to_f - bay[:z_bottom0].to_f) * f
      end

      # The boards that fill one bay, as [t_start, t_end] pairs measured along
      # the run.
      #
      # The clear space is what is left between the two posts. Rather than
      # running full-width boards and trimming whatever is left over - which
      # leaves a sliver at one end and is the thing that makes a fence look
      # home-made - the boards are made very slightly narrower so they divide
      # the bay evenly. Same reasoning as the even bays: one small change
      # shared by every board beats one ugly board.
      def self.board_runs(bay, board_w = DEFAULT_BOARD_W,
                          gap = DEFAULT_BOARD_GAP,
                          post_size = DEFAULT_POST_SIZE)
        half  = post_size.to_f / 2.0
        a     = bay[:t0].to_f + half
        b     = bay[:t1].to_f - half
        clear = b - a
        return [] if clear < MIN_BOARD_W

        w = board_w.to_f
        g = gap.to_f
        g = 0.0 if g < 0.0
        w = MIN_BOARD_W if w < MIN_BOARD_W

        pitch = w + g
        n = ((clear + g) / pitch).round
        n = 1 if n < 1
        # Never make a board WIDER than asked for - a fence with 7" boards
        # where 5.5" was ordered is wrong in a way nobody notices until it is
        # built. Rounding up the count only ever makes them narrower.
        n += 1 while ((clear + g) / n) - g > w && n < 10_000
        return [] if ((clear + g) / n) - g < MIN_BOARD_W

        actual_pitch = (clear + g) / n
        bw = actual_pitch - g
        (0...n).map do |i|
          t0 = a + i * actual_pitch
          [t0, t0 + bw]
        end
      end

      # A one-line summary for the status bar. Reads the layout, decides
      # nothing.
      def self.describe(lay)
        return 'no fence' unless lay
        ft = (lay[:length] / 12.0).round(2)
        s  = "#{ft}' | #{lay[:bays].length} bays | #{lay[:posts].length} posts"
        return s if lay[:flat]
        s + " | #{lay[:mode]} #{lay[:slope_deg].round(2)} deg"
      end

    end
  end
end
