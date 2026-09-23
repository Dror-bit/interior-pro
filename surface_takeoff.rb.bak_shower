# encoding: utf-8
# Interior Pro - QUANTITIES PER NAMED SURFACE (2026-09-18)
#
# WHAT HE ASKED FOR. Not "how much of each material in the whole model" -
# that number counts every side of every solid and cannot be ordered by
# (measured 2026-09-18: the roof tiles alone came to 10,564 sq ft over
# 144,376 faces). What he orders by is the FINISH SURFACE, named by him:
# "tile for the kitchen", "tile for the patio", "wood floor Y". Floors
# and walls, inside and out. Net area, never gross - "כן רק השטח נטו".
#
# WHERE THE NUMBERS COME FROM. Nothing new is modelled; the model
# already knows all of it (measured, takeoff_survey.txt):
#   a room  carries name and area_sqft
#   a floor carries room_id, floor_type, area_sqft, and its tile size
#           (unit_l / unit_w) - which is what piece counting will use
#   a wall  carries gross_area_sqft, its two materials, and the ids of
#           the doors and windows in it
#   a door / window carries its own area_sqft and host_wall_id
#
# NET. A floor's area is the room's own boundary - already net. A wall's
# gross area is what is saved, so every opening in it is taken off here.
# Both sides of a wall lose the same opening.
#
# No kill switch: it reads and writes a text file, builds nothing.
module InteriorPro
  module SurfaceTakeoff
    # PURE. Gross minus its openings, never below zero.
    def self.net_area(gross_sqft, openings_sqft)
      n = gross_sqft.to_f - openings_sqft.to_f
      n < 0.0 ? 0.0 : n.round(2)
    end

    # PURE. A row per surface, biggest first.
    def self.sort_rows(rows)
      rows.sort_by { |r| -r[:sqft].to_f }
    end

    # PURE. The csv his own software reads.
    def self.to_csv(rows)
      out = ['kind,name,category,face,material,area_sqft,unit,note']
      rows.each do |r|
        out << [r[:kind], q(r[:name]), r[:category], r[:face], q(r[:material]),
                r[:sqft], r[:unit], q(r[:note])].join(',')
      end
      out.join("\n")
    end

    def self.q(s)
      t = s.to_s.gsub('"', '""')
      t =~ /[,"]/ ? %("#{t}") : t
    end

    # PURE. The tile size written as he says it: 24x48.
    def self.unit_text(l, w)
      l = l.to_f
      w = w.to_f
      return '' if l <= 0.0 || w <= 0.0
      format('%gx%g', w, l)
    end

    # ---- reading the model -------------------------------------------
    def self.groups_by_type(model)
      out = Hash.new { |h, k| h[k] = [] }
      model.entities.grep(Sketchup::Group).each do |g|
        next unless g.valid?
        out[g.get_attribute('InteriorPro', 'type').to_s] << g
      end
      # a door or a window may have been turned into a component
      model.entities.grep(Sketchup::ComponentInstance).each do |c|
        next unless c.valid?
        t = c.get_attribute('InteriorPro', 'type').to_s
        out[t] << c unless t.empty?
      end
      out
    end

    # sq ft of openings, per host wall id
    def self.openings_by_wall(by_type)
      out = Hash.new(0.0)
      (by_type['door'] + by_type['window']).each do |o|
        id = o.get_attribute('InteriorPro', 'host_wall_id').to_s
        next if id.empty?
        out[id] += o.get_attribute('InteriorPro', 'area_sqft').to_f
      end
      out
    end

    # The whole answer: one row per surface.
    def self.take(model = nil)
      model ||= Sketchup.active_model
      by = groups_by_type(model)
      rooms = {}
      by['room'].each do |r|
        # A room bound to Invoice Studio uses the name COPIED from
        # rooms.json: its importer matches a floor row to a room by exact
        # string, so a retyped name silently loses the link (2026-09-18).
        bound = r.get_attribute('InteriorPro', 'studio_room_name').to_s
        nm = bound.empty? ? r.get_attribute('InteriorPro', 'name').to_s : bound
        rooms[r.get_attribute('InteriorPro', 'id').to_s] = nm
      end
      opens = openings_by_wall(by)
      rows = []

      by['floor'].each do |f|
        rid = f.get_attribute('InteriorPro', 'room_id').to_s
        rows << { kind: 'floor',
                  name: (rooms[rid] || rid),
                  category: '', face: '',
                  material: f.get_attribute('InteriorPro', 'floor_type').to_s,
                  sqft: f.get_attribute('InteriorPro', 'area_sqft').to_f.round(2),
                  unit: unit_text(f.get_attribute('InteriorPro', 'unit_l'),
                                  f.get_attribute('InteriorPro', 'unit_w')),
                  note: '' }
      end

      by['wall'].each do |w|
        id = w.get_attribute('InteriorPro', 'id').to_s
        gross = w.get_attribute('InteriorPro', 'gross_area_sqft').to_f
        op = opens[id]
        net = net_area(gross, op)
        # his own label if he gave one, otherwise the wall's mark, else id
        nm = w.get_attribute('InteriorPro', 'mark').to_s
        nm = id[0, 8] if nm.empty?
        note = op > 0.0 ? format('gross %.2f, openings %.2f', gross, op) : ''
        cat = w.get_attribute('InteriorPro', 'wall_category').to_s
        # `category` is what KIND of wall it is (exterior / interior);
        # `face` is which SIDE of it we are pricing (outside / inside).
        # They used to be two columns both reading "exterior/interior"
        # and nobody could tell them apart (2026-09-18).
        [['outside', w.get_attribute('InteriorPro', 'exterior_material')],
         ['inside',  w.get_attribute('InteriorPro', 'interior_material')]].each do |face, mat|
          rows << { kind: 'wall', name: nm, category: cat, face: face,
                    material: mat.to_s, sqft: net, unit: '', note: note }
        end
      end
      sort_rows(rows)
    rescue StandardError => e
      puts "[SurfaceTakeoff] take: #{e.message}"
      []
    end

    def self.report!(model = nil, dir = nil)
      model ||= Sketchup.active_model
      dir ||= File.dirname(__FILE__)
      rs = take(model)
      fl = rs.select { |r| r[:kind] == 'floor' }
      wl = rs.reject { |r| r[:kind] == 'floor' }
      t = []
      t << "TIME #{Time.now}"
      t << "model: #{model.title}"
      t << ''
      t << 'FLOORS (net - the room boundary)'
      t << format('   %-24s %-18s %-10s %10s', 'name', 'material', 'tile', 'sq ft')
      fl.each do |r|
        t << format('   %-24s %-18s %-10s %10.2f',
                    r[:name].to_s[0, 24], r[:material].to_s[0, 18], r[:unit], r[:sqft])
      end
      t << format('   %-54s %10.2f', 'total', fl.sum { |r| r[:sqft] })
      t << ''
      t << 'WALLS (net - openings taken off)'
      t << format('   %-14s %-9s %-8s %-20s %10s', 'name', 'wall is', 'face', 'material', 'sq ft')
      wl.each do |r|
        t << format('   %-14s %-9s %-8s %-20s %10.2f',
                    r[:name].to_s[0, 14], r[:category], r[:face],
                    r[:material].to_s[0, 20], r[:sqft])
      end
      t << format('   %-55s %10.2f', 'total', wl.sum { |r| r[:sqft] })
      File.write(File.join(dir, 'surface_takeoff.txt'), t.join("\n") + "\n")
      File.write(File.join(dir, 'surface_takeoff.csv'), to_csv(rs) + "\n")
      rs.length
    rescue StandardError => e
      puts "[SurfaceTakeoff] report!: #{e.message}"
      0
    end
  end
end
