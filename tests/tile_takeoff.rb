# encoding: utf-8
# Interior Pro - TILE COUNTS FOR THE REAL FLOORS (2026-09-06)
#
# TileCount does the arithmetic on plain numbers. This is the thin layer
# that feeds it from the model: every floor that is laid in a UNIT - a
# tile or a plank - is counted on its own room outline, with its own tile
# size, joint and start point.
#
# Nothing is modelled and nothing is changed; it reads and writes a
# report. A floor with no unit size (a poured slab, carpet) is listed
# with its area only - there is nothing to count there.
module InteriorPro
  module TileTakeoff
    DICT = 'InteriorPro'.freeze

    # PURE. The room outline as x/y pairs, from the flat list a room
    # group saves.
    def self.outline(flat)
      a = Array(flat).map(&:to_f)
      return [] if a.length < 6
      a.each_slice(2).to_a
    end

    # Every floor worth counting, with what it needs.
    def self.floors(model = nil)
      model ||= Sketchup.active_model
      rooms = {}
      model.entities.grep(Sketchup::Group).each do |g|
        next unless g.valid?
        next unless g.get_attribute(DICT, 'type').to_s == 'room'
        rooms[g.get_attribute(DICT, 'id').to_s] = g
      end
      out = []
      model.entities.grep(Sketchup::Group).each do |g|
        next unless g.valid?
        next unless g.get_attribute(DICT, 'type').to_s == 'floor'
        rid = g.get_attribute(DICT, 'room_id').to_s
        room = rooms[rid]
        next if room.nil?
        bound = room.get_attribute(DICT, 'studio_room_name').to_s
        nm = bound.empty? ? room.get_attribute(DICT, 'name').to_s : bound
        out << { name: nm,
                 type: g.get_attribute(DICT, 'floor_type').to_s,
                 area: g.get_attribute(DICT, 'area_sqft').to_f,
                 poly: outline(room.get_attribute(DICT, 'boundary_xy')),
                 tw: g.get_attribute(DICT, 'unit_w').to_f,
                 tl: g.get_attribute(DICT, 'unit_l').to_f,
                 grout: g.get_attribute(DICT, 'pattern_grout').to_f,
                 ox: g.get_attribute(DICT, 'pattern_ox').to_f,
                 oy: g.get_attribute(DICT, 'pattern_oy').to_f,
                 pattern: g.get_attribute(DICT, 'pattern').to_s }
      end
      out.sort_by { |f| -f[:area] }
    end

    # PURE. A running bond is staggered half a tile; everything else is
    # laid straight. (Herringbone and the rest are not counted yet - see
    # the note in the report.)
    def self.stagger_for(pattern)
      pattern.to_s =~ /run|brick|offset|stagger/i ? 0.5 : 0.0
    end

    # PURE. Can this floor be counted at all?
    def self.countable?(f)
      f[:tw].to_f > 0.5 && f[:tl].to_f > 0.5 && f[:poly].length >= 3
    end

    def self.count_floor(f, pct = InteriorPro::TileCount::MIN_REUSE_PCT)
      return nil unless countable?(f)
      InteriorPro::TileCount.plan(f[:poly], f[:tw], f[:tl],
                                  grout: f[:grout], ox: f[:ox], oy: f[:oy],
                                  stagger: stagger_for(f[:pattern]), pct: pct)
    end

    def self.report!(model = nil, dir = nil, pct = nil)
      model ||= Sketchup.active_model
      dir ||= File.dirname(__FILE__)
      pct ||= InteriorPro::TileCount::MIN_REUSE_PCT
      t = []
      t << "TIME #{Time.now}"
      t << "model: #{model.title}"
      t << "a leftover under #{pct}% of a tile is waste - never paired"
      t << ''
      list = floors(model)
      if list.empty?
        t << '(no floors in this model)'
      end
      list.each do |f|
        t << format('%s  -  %s  -  %.1f sq ft', f[:name], f[:type], f[:area])
        res = count_floor(f, pct)
        if res.nil?
          t << '   laid without a unit size - area only, nothing to count'
        else
          InteriorPro::TileCount.lines(res, f[:tw], f[:tl]).each { |l| t << '   ' + l }
          t << format('   pattern %s%s', f[:pattern].empty? ? 'grid' : f[:pattern],
                      f[:grout] > 0 ? format(', joint %g"', f[:grout]) : '')
        end
        t << ''
      end
      File.write(File.join(dir, 'tile_report.txt'), t.join("\n") + "\n")
      list.length
    rescue StandardError => e
      puts "[TileTakeoff] report!: #{e.message}"
      0
    end
  end
end
