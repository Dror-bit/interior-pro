# encoding: utf-8
# Interior Pro - A NICHE IN A TILED WALL (2026-09-20)
#
# His words: "נישה בקיר אריחים - אותו מנגנון של שטח, עם עומק פנימה",
# and the depth is his: typed every time, 4" by default.
#
# THE SAME FOUR NUMBERS AS A TILED AREA. A niche is a rectangle on one
# face of a wall - u0 along the wall, z0 up from the wall's own floor,
# how wide and how tall - plus ONE more number, how deep it goes IN.
# So the drawing tool is the tiled-area tool with a different build,
# and the plane maths is TileWall's, not a second copy.
#
# HOW IT IS CUT. A box is built on the face, standing a hair proud of it
# and reaching `depth` inches into the wall, and that box is subtracted
# from the wall solid (the vendored Eneroth operations, the same ones
# the door opening uses). Nothing is ever cut through: the depth is held
# back from the far face so a stud bay's worth of wall is always left.
#
# THE NUMBERS LIVE ON THE WALL, not on the geometry. `niches` is an
# attribute on the wall group, so a wall that is rebuilt can have its
# niches cut again from the same numbers, and a tiled area on that face
# reads them as holes - the tile goes AROUND the niche, it does not run
# over it.
#
# HIS LAW FOR THE NEXT STEP (2026-09-20, in his words: "החיתוך בין הניש
# לטיל של הקירות החיבור יהיה 45 מעלות"): when the inside of the niche is
# tiled, the tile of the wall and the tile of the niche MEET ON A 45
# DEGREE MITRE at the opening - not a butt joint with a cut edge showing.
# Nothing here builds that yet; it is written down so it is not lost.
#
# EVERYTHING ABOVE `---- the model ----` IS PURE - tests/rt192.rb.
require_relative 'tile_wall'

module InteriorPro
  module TileNiche
    EPS = 1.0e-6 unless const_defined?(:EPS, false)
    # His number.
    DEFAULT_DEPTH = 4.0 unless const_defined?(:DEFAULT_DEPTH, false)
    # Never cut through: this much wall is always left behind the niche.
    MIN_BACK = 0.5 unless const_defined?(:MIN_BACK, false)
    # How far the cutting box stands proud of the face, so the face is
    # really taken away and not left as a skin 1/1000" thick.
    OVER = 0.25 unless const_defined?(:OVER, false)
    MIN_SIZE = 1.0 unless const_defined?(:MIN_SIZE, false)
    # Kill switch (CLAUDE.md: every feature that builds geometry gets one
    # the day it is written). false = no niche is cut, nothing standing is
    # touched and the stored numbers stay where they are.
    USE_NICHES = true unless const_defined?(:USE_NICHES, false)

    # ---- pure ------------------------------------------------------------

    # How deep this niche may really go in a wall of this thickness.
    def self.clamp_depth(depth, thickness)
      d = depth.to_f
      d = DEFAULT_DEPTH if d <= 0.0
      t = thickness.to_f
      return d if t <= 0.0
      room = t - MIN_BACK
      return 0.0 if room <= 0.0
      d < room ? d : room
    end

    # One stored row -> a hash. Rows are [side, u0, z0, w, h, depth].
    def self.normalize(row)
      return nil if row.nil?
      if row.is_a?(Array) && row.length >= 6
        return { side: row[0].to_s == 'b' ? 'b' : 'a', u0: row[1].to_f, z0: row[2].to_f,
                 w: row[3].to_f, h: row[4].to_f, depth: row[5].to_f }
      end
      return nil unless row.is_a?(Hash)
      g = lambda { |k| row[k] || row[k.to_s] }
      w = g.call(:w)
      h = g.call(:h)
      return nil if w.nil? || h.nil?
      { side: g.call(:side).to_s == 'b' ? 'b' : 'a', u0: g.call(:u0).to_f,
        z0: g.call(:z0).to_f, w: w.to_f, h: h.to_f,
        depth: g.call(:depth).to_f }
    end

    def self.to_row(n)
      [n[:side], n[:u0], n[:z0], n[:w], n[:h], n[:depth]]
    end

    # The niches on ONE face, as [u0, z0, u1, z1] - exactly the shape
    # TileWall wants a hole in.
    def self.holes_for_side(niches, side)
      Array(niches).select { |n| n[:side].to_s == side.to_s }.map do |n|
        [n[:u0], n[:z0], n[:u0] + n[:w], n[:z0] + n[:h]]
      end
    end

    # The eight corners of the cutting box, in world coordinates:
    # four a hair PROUD of the face, four `depth` inches inside it.
    # `fr` is a TileWall frame. PURE.
    def self.box_corners(fr, u0, z0, w, h, depth, over = OVER)
      front = InteriorPro::TileWall.rect(u0, z0, w, h).map do |u, z|
        InteriorPro::TileWall.world(fr, u, z, over)
      end
      back = InteriorPro::TileWall.rect(u0, z0, w, h).map do |u, z|
        InteriorPro::TileWall.world(fr, u, z, -depth.to_f)
      end
      [front, back]
    end

    # ---- the model --------------------------------------------------------

    def self.read(wall)
      return [] unless wall&.valid?
      raw = wall.get_attribute('InteriorPro', 'niches')
      case raw
      when Array then raw.compact.map { |r| normalize(r) }.compact
      when String
        require 'json'
        JSON.parse(raw).map { |r| normalize(r) }.compact
      else []
      end
    rescue StandardError => e
      puts "[TileNiche] the niches on this wall could not be read: #{e.message}"
      []
    end

    def self.persist!(wall, niches)
      wall.set_attribute('InteriorPro', 'niches',
                         Array(niches).compact.map { |n| to_row(n) })
    end

    def self.thickness_of(wall)
      wall.get_attribute('InteriorPro', 'thickness').to_f
    end

    # ADD ONE NICHE AND CUT IT. Returns the niche hash, or nil - and says
    # why, every time (CLAUDE.md: a silent `next unless` is a bug waiting).
    def self.add!(wall:, side: 'a', u0: 0.0, z0: 0.0, w: 0.0, h: 0.0,
                  depth: DEFAULT_DEPTH, wrap_operation: true)
      unless wall&.valid? && wall.get_attribute('InteriorPro', 'type') == 'wall'
        puts '[TileNiche] that is not a wall'
        return nil
      end
      unless USE_NICHES
        puts '[TileNiche] niches are switched off (USE_NICHES = false)'
        return nil
      end
      w = w.to_f
      h = h.to_f
      if w < MIN_SIZE || h < MIN_SIZE
        puts "[TileNiche] the niche is too small (#{w.round(2)} x #{h.round(2)})"
        return nil
      end
      th = thickness_of(wall)
      d = clamp_depth(depth, th)
      if d < 0.25
        puts "[TileNiche] a wall #{th.round(2)}\" thick has no room for a niche"
        return nil
      end
      puts "[TileNiche] the wall is #{th.round(2)}\" thick - the niche goes #{d.round(2)}\" in" if (d - depth.to_f).abs > 0.01
      n = { side: side.to_s == 'b' ? 'b' : 'a', u0: u0.to_f, z0: z0.to_f,
            w: w, h: h, depth: d }

      model = Sketchup.active_model
      model.start_operation('Interior Pro - Niche', true) if wrap_operation
      begin
        ok = cut_one!(wall, n, model)
        unless ok
          model.abort_operation if wrap_operation
          return nil
        end
        persist!(wall, read(wall) + [n])
        model.commit_operation if wrap_operation
        # The tile on this face has to go round the new hole.
        InteriorPro::TileWall.refresh_wall!(wall.get_attribute('InteriorPro', 'id'))
        puts "[TileNiche] niche on side #{n[:side]}: u #{n[:u0].round(2)}, z #{n[:z0].round(2)}, " \
             "#{n[:w].round(2)} x #{n[:h].round(2)}, #{n[:depth].round(2)}\" deep"
        n
      rescue StandardError => e
        model.abort_operation if wrap_operation
        puts "[TileNiche] the niche could not be cut: #{e.class}: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
        nil
      end
    end

    # Cut ONE niche out of the wall solid. No operation of its own - the
    # caller owns the undo step.
    def self.cut_one!(wall, n, model = Sketchup.active_model)
      fr = InteriorPro::TileWall.frame_for(wall, n[:side])
      if fr.nil?
        puts '[TileNiche] this wall has no face to cut'
        return false
      end
      mod = build_box!(model, fr, n)
      return false if mod.nil?
      ops = InteriorPro::SolidBoolean::Operations
      unless ops.solid?(wall)
        mod.erase! if mod.valid?
        puts '[TileNiche] the wall is not a closed solid - the niche was not cut'
        return false
      end
      unless ops.solid?(mod)
        mod.erase! if mod.valid?
        puts '[TileNiche] the cutting box is not a closed solid - the niche was not cut'
        return false
      end
      wall.make_unique if wall.is_a?(Sketchup::Group)
      unless ops.subtract(wall, mod)
        mod.erase! if mod.valid?
        puts '[TileNiche] the subtraction failed - the niche was not cut'
        return false
      end
      true
    rescue StandardError => e
      puts "[TileNiche] cut_one! failed: #{e.message}"
      false
    end

    # The box that gets taken out of the wall: the niche rectangle
    # standing OVER inches proud of the face, pushed `depth + OVER` in.
    def self.build_box!(model, fr, n)
      front, = box_corners(fr, n[:u0], n[:z0], n[:w], n[:h], n[:depth])
      grp = model.entities.add_group
      grp.name = 'InteriorPro_NicheBox_TMP'
      pts = front.map { |x, y, z| Geom::Point3d.new(x, y, z) }
      f = begin
        grp.entities.add_face(pts)
      rescue StandardError
        nil
      end
      f ||= begin
        grp.entities.add_face(pts.reverse)
      rescue StandardError
        nil
      end
      if f.nil? || !f.valid?
        grp.erase! if grp.valid?
        puts '[TileNiche] the face of the cutting box could not be drawn'
        return nil
      end
      outward = Geom::Vector3d.new(fr[:nx], fr[:ny], 0)
      dist = n[:depth].to_f + OVER
      f.pushpull(f.normal.dot(outward) > 0 ? -dist : dist)
      grp
    rescue StandardError => e
      puts "[TileNiche] the cutting box could not be built: #{e.message}"
      nil
    end

    # CUT EVERY STORED NICHE AGAIN. This is what a wall that was rebuilt
    # needs - the geometry came back whole, the numbers never went away.
    def self.recut_wall!(wall, model = Sketchup.active_model)
      return 0 unless USE_NICHES
      ns = read(wall)
      return 0 if ns.empty?
      n = 0
      ns.each { |x| n += 1 if cut_one!(wall, x, model) }
      puts "[TileNiche] #{n} of #{ns.length} niche(s) cut again on wall #{wall.get_attribute('InteriorPro', 'id')}"
      n
    rescue StandardError => e
      puts "[TileNiche] the niches could not be cut again: #{e.message}"
      0
    end

    # Take the LAST niche off this face and heal the wall by rebuilding it
    # from its own numbers, then cutting the ones that are left.
    def self.remove_last!(wall)
      ns = read(wall)
      if ns.empty?
        puts '[TileNiche] this wall has no niche to take off'
        return false
      end
      ns.pop
      persist!(wall, ns)
      InteriorPro::WallTool.rebuild_wall_native_geometry!(wall)
      recut_wall!(wall)
      InteriorPro::TileWall.refresh_wall!(wall.get_attribute('InteriorPro', 'id'))
      true
    rescue StandardError => e
      puts "[TileNiche] the niche could not be taken off: #{e.message}"
      false
    end
  end
end
