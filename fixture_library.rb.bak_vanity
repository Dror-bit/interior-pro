# encoding: utf-8
# Interior Pro - THE PLUMBING FIXTURE LIBRARY (2026-09-25)
#
# His call (2026-09-24): the fixtures are REAL .skp files in a folder,
# picked from a list with pictures, like the door handles.
#
# SHOWER SETS (2026-09-25, his words: "בראש מקלחת יש 3 חלקים בדרך כלל או
# 4 ... אני רוצה שיהיו לי סטים ... אם אני פותח את הסט אני יכול להגדיר בו
# את הגובה של כל אחד מהאלמנטים ... ברירת מחדל"). One folder per set, the
# folder name is the set name, one file per part with a FIXED name:
#
#   assets/PLUMBING/SHOWER SETS/<set>/head.skp   shower head
#                                    /valve.skp  handles
#                                    /hand.skp   hand shower  (optional)
#                                    /spout.skp  tub spout    (optional)
#   assets/PLUMBING/TOILETS/<name>.skp
#
# THE POINT A HEIGHT IS MEASURED TO (his pick, "2"): in a set part the
# file's ORIGIN is the point where the pipe leaves the wall. He sets it
# himself in each file. If the origin is nowhere near the part (a file
# not prepared), the middle of its box is used instead. The part's BACK
# (lowest green) goes on the wall face; +green is out of the wall.
# A toilet still sits by its box: middle of the width, bottom on the floor.
#
# 'Simple' is a built-in stand-in made of boxes, so it can be tested
# before any file exists.
require 'fileutils'
require 'json'

module InteriorPro
  module FixtureLibrary
    # Kill switch: false = the Plumbing button does nothing, nothing placed.
    USE_FIXTURES = true unless const_defined?(:USE_FIXTURES, false)
    SIMPLE = 'Simple' unless const_defined?(:SIMPLE, false)
    # Kill switch: false = hidden things inside a part file are kept.
    USE_STRIP_HIDDEN = true unless const_defined?(:USE_STRIP_HIDDEN, false)

    # The kinds. A method, not a guarded constant, so reload! sees changes.
    # on_tile: only on a tiled area, standing on its face (his call,
    # "רק מהפנים של הבית ורק על קירות טיל").
    def self.kinds
      {
        'shower_set' => { dir: 'SHOWER SETS', label: 'Shower set', height: 80.0, on_tile: true, set: true },
        'toilet'     => { dir: 'TOILETS',     label: 'Toilet',     height: 0.0 }
      }
    end

    # The parts of a set: key (= file name), label, height, sideways.
    # Heights to the pipe point, from the floor (found on the web,
    # 2026-09-25: head 80, valve 48, tub spout ~4" over the rim).
    def self.parts_spec
      [['head',  'Shower head', 80.0, 0.0],
       ['valve', 'Handles',     48.0, 0.0],
       ['hand',  'Hand shower', 60.0, 12.0],
       ['spout', 'Tub spout',   22.0, 0.0]]
    end

    def self.part_keys
      parts_spec.map(&:first)
    end

    def self.kind_ok(kind)
      kinds.key?(kind.to_s) ? kind.to_s : kinds.keys.first
    end

    def self.on_tile?(kind)
      kinds[kind_ok(kind)][:on_tile] ? true : false
    end

    def self.set_kind?(kind)
      kinds[kind_ok(kind)][:set] ? true : false
    end

    def self.default_height(kind)
      kinds[kind_ok(kind)][:height]
    end

    def self.dir_for(kind)
      File.join(InteriorPro::PLUGIN_DIR, 'assets', 'PLUMBING', kinds[kind_ok(kind)][:dir])
    end

    # Where a part's file lives. part nil = a single-file kind.
    def self.file_for(kind, name, part = nil)
      if set_kind?(kind)
        File.join(dir_for(kind), name.to_s, "#{part}.skp")
      else
        File.join(dir_for(kind), "#{name}.skp")
      end
    end

    # The names in the folder: set folders that hold at least one part
    # file, or .skp files. Sorted. [] when no folder.
    def self.names(kind)
      dir = dir_for(kind)
      return [] unless Dir.exist?(dir)
      if set_kind?(kind)
        # A SET WITH COLOURS (2026-09-28, his words: "אני בוחר את הסט ואז
        # אני יכול לבחור את הצבע של הסט"). A set folder holding the part
        # files itself is one set, as before. A set folder holding COLOUR
        # folders gives one name per colour: "Set 1/Black". Everything
        # else (file_for, the picture) just joins the name as a path.
        has_parts = lambda { |path| part_keys.any? { |p| File.exist?(File.join(path, "#{p}.skp")) } }
        Dir.children(dir).sort.flat_map do |d|
          path = File.join(dir, d)
          next [] unless File.directory?(path)
          next [d] if has_parts.call(path)
          Dir.children(path).sort.select { |c| File.directory?(File.join(path, c)) && has_parts.call(File.join(path, c)) }
             .map { |c| "#{d}/#{c}" }
        end
      else
        Dir.glob(File.join(dir, '*.skp')).map { |f| File.basename(f, '.skp') }.sort
      end
    end

    # His own products FIRST, the stand-in last (2026-09-25: with 'Simple'
    # first and chosen by default, his Set 1 was never the one placed).
    def self.products(kind)
      names(kind) + [SIMPLE]
    end

    # Which parts this set really has. The stand-in has all four.
    def self.parts_available(kind, name)
      return [] unless set_kind?(kind)
      return part_keys if name.to_s == SIMPLE
      part_keys.select { |p| File.exist?(file_for(kind, name, p)) }
    end

    # The window's starting numbers for a set: every part it has is on,
    # except the tub spout on the stand-in. PURE apart from the folder.
    def self.default_parts(kind, name)
      have = parts_available(kind, name)
      out = {}
      parts_spec.each do |k, _l, h, s|
        on = have.include?(k) && !(name.to_s == SIMPLE && k == 'spout')
        out[k] = { 'on' => on, 'h' => h, 'side' => s }
      end
      out
    end

    # A name that is safe as a file name and does not clash. PURE.
    def self.clean_name(base, taken = [])
      n = base.to_s.gsub(/[^0-9A-Za-z _\-]/, '').strip
      n = 'Fixture' if n.empty?
      out = n
      i = 2
      while taken.include?(out)
        out = "#{n} #{i}"
        i += 1
      end
      out
    end

    # ---- the definitions ----------------------------------------------

    def self.def_name(kind, name, part = nil)
      ["InteriorPro_Fixture_#{kind_ok(kind)}_#{name.to_s.sub('/', ' - ')}", part].compact.join('_')
    end

    # Load (or reuse) a definition. nil on failure, with the reason.
    # CAUTION (CLAUDE.md): an old definition in the model wins over the
    # file - after changing a file, purge unused components first.
    def self.definition_for(model, kind, name, part = nil)
      kind = kind_ok(kind)
      return simple_definition(model, kind, part) if name.to_s.empty? || name.to_s == SIMPLE
      dn = def_name(kind, name, part)
      d = model.definitions[dn]
      if d && d.valid?
        strip_hidden!(d)
        return d
      end
      path = file_for(kind, name, part)
      unless File.exist?(path)
        puts "[Fixture] file not found: #{path}"
        return nil
      end
      d = model.definitions.load(path, allow_newer: true)
      if d && d.valid?
        d.name = dn
        strip_hidden!(d)
      end
      d
    rescue StandardError => e
      puts "[Fixture] load failed for #{kind}/#{name}/#{part}: #{e.message}"
      nil
    end

    # The stand-ins, made of boxes. For a set part the origin is the pipe
    # point on the wall; for a toilet it is the back, middle, bottom.
    def self.simple_boxes(kind, part)
      return [[-9.5, 9.5, 0.5, 8.5, 15.0, 30.0], [-7.0, 7.0, 8.5, 28.0, 0.0, 15.0]] if kind == 'toilet'
      case part.to_s
      when 'valve' then [[-3.5, 3.5, 0.0, 0.5, -3.5, 3.5], [-1.0, 1.0, 0.5, 3.5, -1.0, 1.0]]
      when 'hand'  then [[-0.5, 0.5, 0.0, 1.0, -12.0, 12.0], [-1.5, 1.5, 1.0, 3.0, -2.0, 4.0]]
      when 'spout' then [[-1.5, 1.5, 0.0, 6.0, -1.0, 1.5]]
      else [[-1.5, 1.5, 0.0, 0.5, -1.5, 1.5], [-0.5, 0.5, 0.5, 8.0, -0.5, 0.5], [-3.0, 3.0, 5.0, 11.0, -2.0, -1.0]]
      end
    end

    def self.simple_definition(model, kind, part = nil)
      dn = def_name(kind, SIMPLE, part)
      d = model.definitions[dn]
      return d if d && d.valid? && !d.entities.to_a.empty?
      d ||= model.definitions.add(dn)
      mat = model.materials['InteriorPro_Fixture_White'] || model.materials.add('InteriorPro_Fixture_White')
      mat.color = Sketchup::Color.new(235, 237, 240)
      # EACH BOX IN ITS OWN GROUP (CLAUDE.md, 2026-09-12): boxes that touch
      # face to face in one group get merged, and a pushpull into that can
      # take SketchUp down.
      simple_boxes(kind, part).each { |b| add_box(d.entities.add_group.entities, *b, mat) }
      d
    end

    def self.add_box(ents, x0, x1, y0, y1, z0, z1, mat)
      f = ents.add_face([x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0])
      return if f.nil?
      f.reverse! if f.normal.z > 0
      f.pushpull(-(z1 - z0))
      ents.grep(Sketchup::Face).each { |fc| fc.material = mat }
    end

    # ---- the pictures ---------------------------------------------------

    # A set's picture is its head's (or first part's). Made by SketchUp.
    def self.thumb_path(kind, name)
      if set_kind?(kind)
        File.join(dir_for(kind), name.to_s, 'thumb.png')
      else
        File.join(dir_for(kind), 'thumbs', "#{name}.png")
      end
    end

    # THE SET'S OWN PICTURE (2026-09-28, his words: "תמונה כללית לכל סט ולכל
    # צבע יהיה את התמונה עם הצבע שלו"). <set>/thumb.png, next to the colour
    # folders. nil for a set with no colours - its thumb.png is its picture.
    def self.set_thumb_path(kind, name)
      return nil unless set_kind?(kind) && name.to_s.include?('/')
      File.join(dir_for(kind), name.to_s.split('/', 2).first, 'thumb.png')
    end

    def self.ensure_thumb(model, kind, name)
      return nil if name.to_s == SIMPLE
      tp = thumb_path(kind, name)
      return tp if File.exist?(tp)
      part = set_kind?(kind) ? parts_available(kind, name).first : nil
      d = definition_for(model, kind, name, part)
      return nil unless d
      FileUtils.mkdir_p(File.dirname(tp))
      d.save_thumbnail(tp) ? tp : nil
    rescue StandardError => e
      puts "[Fixture] no picture for #{kind}/#{name}: #{e.message}"
      nil
    end

    # "Add new" for a single-file kind: copy any .skp into its folder.
    def self.add_file!(kind, src)
      return nil if set_kind?(kind)
      return nil unless src && File.exist?(src) && src.downcase.end_with?('.skp')
      dir = dir_for(kind)
      FileUtils.mkdir_p(dir)
      name = clean_name(File.basename(src, '.*'), names(kind) + [SIMPLE])
      FileUtils.cp(src, File.join(dir, "#{name}.skp"))
      puts "[Fixture] added #{kind}/#{name} from #{src}"
      ensure_thumb(Sketchup.active_model, kind, name)
      name
    rescue StandardError => e
      puts "[Fixture] could not add #{src}: #{e.message}"
      nil
    end

    # ---- the maths (PURE) -------------------------------------------------

    # The point a height is measured to, in the part's own x / z.
    # A set part: its origin, if the origin is on or near the part
    # (within 1"); else the middle of its box. A toilet: bottom middle.
    def self.anchor_xz(minx, maxx, minz, maxz, set_part, near = 1.0)
      if set_part
        inside = 0.0 >= minx - near && 0.0 <= maxx + near && 0.0 >= minz - near && 0.0 <= maxz + near
        return [0.0, 0.0] if inside
        return [(minx + maxx) / 2.0, (minz + maxz) / 2.0]
      end
      [(minx + maxx) / 2.0, minz]
    end

    # One part's rectangle on the face: [u0, u1, z0, z1].
    # p = { du:, h:, ax:, az:, minx:, maxx:, minz:, maxz: }. PURE.
    def self.part_rect(p, u_line)
      cu = u_line.to_f + p[:du].to_f
      [cu + p[:minx] - p[:ax], cu + p[:maxx] - p[:ax], p[:h] + p[:minz] - p[:az], p[:h] + p[:maxz] - p[:az]]
    end

    # The distance he TYPES is from the corner NEARER the mouse to the
    # line of the fixture (its pipe line / middle). Returns that u.
    def self.u_from_corner(dist, lo, hi, mouse_u)
      if mouse_u.to_f - lo.to_f <= hi.to_f - mouse_u.to_f
        lo.to_f + dist.to_f
      else
        hi.to_f - dist.to_f
      end
    end

    def self.corner_dist(u, lo, hi)
      [u.to_f - lo.to_f, hi.to_f - u.to_f].min
    end

    # Does this tiled area cover the whole part? a = { bu0:, bw:, z0:, h: }.
    def self.tile_covers?(a, u0, u1, z0, z1, eps = 1.0e-6)
      u0.to_f >= a[:bu0].to_f - eps && u1.to_f <= a[:bu0].to_f + a[:bw].to_f + eps &&
        z0.to_f >= a[:z0].to_f - eps && z1.to_f <= a[:z0].to_f + a[:h].to_f + eps
    end

    # A SPLIT TILE IS STILL ONE TILE (2026-09-27, his words: "חיתוך הטיל לא
    # משנה להצבת הסט"). Measured on wall 849179b2: Split Tile cut it at
    # 59.7", the hand shower runs 29..67.6, and no ONE area covered it - so
    # no ghost at all. The part is on tile when the areas TOGETHER cover it:
    # every cell between their edges has an area over its middle. PURE.
    def self.tiles_cover?(areas, u0, u1, z0, z1, eps = 1.0e-6)
      areas = Array(areas)
      return false if areas.empty?
      us = [u0.to_f, u1.to_f]
      zs = [z0.to_f, z1.to_f]
      areas.each do |a|
        [a[:bu0].to_f, a[:bu0].to_f + a[:bw].to_f].each { |v| us << v if v > u0.to_f && v < u1.to_f }
        [a[:z0].to_f, a[:z0].to_f + a[:h].to_f].each { |v| zs << v if v > z0.to_f && v < z1.to_f }
      end
      us = us.uniq.sort
      zs = zs.uniq.sort
      us.each_cons(2).all? do |ua, ub|
        zs.each_cons(2).all? do |za, zb|
          next true if ub - ua < eps || zb - za < eps
          cu = (ua + ub) / 2.0
          cz = (za + zb) / 2.0
          areas.any? { |a| tile_covers?(a, cu, cu, cz, cz, eps) }
        end
      end
    end

    # NOT ON A WINDOW OR A NICHE, AND NOT ABOVE ONE (2026-09-25, his words:
    # "שלא יהיה מעל חלון או ניצ כי במציאות אי אפשר להעביר שם פלמינג").
    # The pipe comes UP inside the wall, so any hole sharing the part's
    # width that starts below its top is in the way.
    def self.pipe_blocked?(u0, u1, z1, holes, eps = 1.0e-6)
      Array(holes).any? do |h|
        u0.to_f < h[2].to_f - eps && u1.to_f > h[0].to_f + eps && h[1].to_f < z1.to_f - eps
      end
    end

    # ---- what gets placed -------------------------------------------------

    # THE BOX OF WHAT CAN BE SEEN (2026-09-25). Measured in his head.skp
    # (debug_part_file.rb): six HIDDEN specks of edge 55-64" off the head
    # made its box 68" wide and 51" tall, so it never fitted on the tile.
    # Hidden things, and things on a hidden tag, do not count.
    def self.visible_bounds(defn)
      bb = Geom::BoundingBox.new
      defn.entities.each do |e|
        next unless e.respond_to?(:bounds)
        next if e.respond_to?(:hidden?) && e.hidden?
        next if e.respond_to?(:layer) && e.layer && !e.layer.visible?
        bb.add(e.bounds)
      end
      bb.empty? ? defn.bounds : bb
    end

    # THE HIDDEN THINGS GO (2026-09-27, his pick "שידלג עליהם בעצמו").
    # Measured: Set 2 valve.skp and hand.skp carry hidden things up to 47"
    # off the part, Set 1 head.skp 64" - the placed set was selected as a
    # box reaching out of the house. The copy loaded into the model drops
    # them; his files are never touched. Same rule as visible_bounds.
    def self.strip_hidden!(defn)
      return 0 unless USE_STRIP_HIDDEN
      gone = defn.entities.to_a.select do |e|
        (e.respond_to?(:hidden?) && e.hidden?) || (e.respond_to?(:layer) && e.layer && !e.layer.visible?)
      end
      return 0 if gone.empty? || gone.length == defn.entities.length
      defn.entities.erase_entities(gone)
      puts "[Fixture] #{defn.name}: #{gone.length} hidden things left out"
      gone.length
    rescue StandardError => e
      puts "[Fixture] hidden things could not be left out of #{defn.name}: #{e.message}"
      0
    end

    # The parts to place, from the window's numbers:
    # [{ part:, defn:, du:, h:, ax:, az:, minx:, maxx:, miny:, maxy:, minz:, maxz: }]
    def self.layout(model, cfg)
      kind = kind_ok(cfg['kind'])
      list = if set_kind?(kind)
               parts = cfg['parts'] || default_parts(kind, cfg['product'])
               part_keys.map do |k|
                 pc = parts[k] || {}
                 next nil unless pc['on']
                 [k, pc['side'].to_f, pc['h'].to_f]
               end.compact
             else
               [[nil, 0.0, cfg['height'].to_f]]
             end
      list.map do |k, du, h|
        d = definition_for(model, kind, cfg['product'], k)
        if d.nil?
          puts "[Fixture] no definition for #{kind}/#{cfg['product']}/#{k} - that part is left out"
          next nil
        end
        b = visible_bounds(d)
        ax, az = anchor_xz(b.min.x, b.max.x, b.min.z, b.max.z, !k.nil?)
        { part: k, defn: d, du: du, h: h, ax: ax, az: az,
          minx: b.min.x.to_f, maxx: b.max.x.to_f, miny: b.min.y.to_f, maxy: b.max.y.to_f,
          minz: b.min.z.to_f, maxz: b.max.z.to_f }
      end.compact
    end

    # The tiled area on THIS wall and side covering [u0,u1]x[z0,z1], and
    # how far its face stands off the wall. nil = no tile there.
    def self.tile_under(wall, side, u0, u1, z0, z1, model = Sketchup.active_model)
      wid = wall.get_attribute('InteriorPro', 'id').to_s
      mine = []
      InteriorPro::TileWall.areas_in_model(model).each do |g|
        at = lambda { |k| g.get_attribute('InteriorPro', k) }
        next unless at.call('wall_id').to_s == wid && at.call('side').to_s == side.to_s
        a = { bu0: (at.call('built_u0') || at.call('u0')).to_f, bw: (at.call('built_w') || at.call('area_w')).to_f,
              z0: at.call('z0').to_f, h: at.call('area_h').to_f, group: g, depth: at.call('tile_depth').to_f }
        # one area covers it all: exactly as before
        return { group: g, out: a[:depth] > 0.0 ? a[:depth] : 0.0 } if tile_covers?(a, u0, u1, z0, z1)
        mine << a
      end
      return nil unless tiles_cover?(mine, u0, u1, z0, z1)
      # split areas: the tile face is where the deepest of them stands
      touch = mine.select { |a| a[:bu0] < u1.to_f && a[:bu0] + a[:bw] > u0.to_f && a[:z0] < z1.to_f && a[:z0] + a[:h] > z0.to_f }
      best = touch.max_by { |a| a[:depth] }
      { group: best[:group], out: best[:depth] > 0.0 ? best[:depth] : 0.0 }
    rescue StandardError => e
      puts "[Fixture] the tile under it could not be read: #{e.message}"
      nil
    end

    # Every hole on this face: doors, windows, and this side's niches.
    def self.holes_on(wall, fr, side)
      out = InteriorPro::TileWall.openings_for(wall, fr) rescue []
      if defined?(InteriorPro::TileNiche)
        out += InteriorPro::TileNiche.holes_for_side(InteriorPro::TileNiche.read(wall), side)
      end
      out
    end

    # ONE CHECK for the tool and the edit: does the whole thing fit with
    # its line at u? { ok:, lo:, hi:, outs:, rects:, no_tile:, on_hole: }
    def self.check(wall, side, fr, u, parts, kind, wall_h)
      lo, hi = InteriorPro::TileWall.face_limits(wall, fr, u)
      holes = holes_on(wall, fr, side)
      res = { ok: !parts.empty?, lo: lo, hi: hi, outs: [], rects: [], no_tile: false, on_hole: false }
      parts.each do |p|
        u0, u1, z0, z1 = part_rect(p, u)
        res[:rects] << [u0, u1, z0, z1]
        res[:ok] = false if u0 < lo - 1.0e-6 || u1 > hi + 1.0e-6 || z0 < -1.0e-6 || z1 > wall_h.to_f + 1.0e-6
        res[:on_hole] = true if pipe_blocked?(u0, u1, z1, holes)
        out = 0.0
        if on_tile?(kind)
          t = tile_under(wall, side, u0, u1, z0, z1)
          if t
            out = t[:out]
          else
            res[:no_tile] = true
          end
        end
        res[:outs] << out
      end
      res[:ok] = false if res[:no_tile] || res[:on_hole]
      res
    end

    # ---- placing --------------------------------------------------------

    # Put the fixture on the face: ONE group holding one instance per part.
    def self.place!(wall:, side:, fr:, u:, cfg:, parts:, outs:, op: true)
      model = Sketchup.active_model
      model.start_operation('Place Fixture', true) if op
      grp = model.entities.add_group
      grp.name = 'InteriorPro_Fixture'
      parts.each_with_index do |p, i|
        shift = Geom::Transformation.translation(Geom::Vector3d.new(-p[:ax], -p[:miny], -p[:az]))
        x, y, zz = InteriorPro::TileWall.world(fr, u + p[:du], p[:h], outs[i].to_f)
        face = Geom::Transformation.axes(Geom::Point3d.new(x, y, zz),
                                         Geom::Vector3d.new(fr[:ux], fr[:uy], 0),
                                         Geom::Vector3d.new(fr[:nx], fr[:ny], 0),
                                         Geom::Vector3d.new(0, 0, 1))
        inst = grp.entities.add_instance(p[:defn], face * shift)
        inst.set_attribute('InteriorPro', 'part', p[:part].to_s) if p[:part]
      end
      keep = cfg.reject { |k, _| k == 'corner' }
      {
        'type' => 'fixture', 'kind' => kind_ok(cfg['kind']), 'product' => cfg['product'].to_s,
        'u_in' => u.to_f, 'side' => side.to_s, 'cfg_json' => keep.to_json,
        'host_wall_id' => wall.get_attribute('InteriorPro', 'id').to_s,
        'id' => "fix-#{Time.now.to_i.to_s(36)}-#{rand(10_000)}", 'created_at' => Time.now.to_s
      }.each { |k, v| grp.set_attribute('InteriorPro', k, v) }
      InteriorPro.assign_tag(grp, 'IP/Plumbing') if InteriorPro.respond_to?(:assign_tag)
      model.commit_operation if op
      puts "[Fixture] placed #{cfg['kind']}/#{cfg['product']} (#{parts.map { |p| p[:part] || 'body' }.join(', ')}) " \
           "on wall #{wall.get_attribute('InteriorPro', 'id')} side #{side} u #{u.round(2)}"
      grp
    rescue StandardError => e
      model&.abort_operation if op
      puts "[Fixture] place failed: #{e.message}"
      nil
    end

    # ---- edit (2026-09-25) ------------------------------------------------
    # NO DELETE TOOL (his call: "אפשר פשוט לסמן ולעשות דליט") - a fixture
    # cuts nothing, so SketchUp's own Delete is the delete.

    def self.fixture?(e)
      (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && e.valid? &&
        e.get_attribute('InteriorPro', 'type') == 'fixture'
    end

    def self.host_wall(inst, model = Sketchup.active_model)
      id = inst.get_attribute('InteriorPro', 'host_wall_id').to_s
      return nil if id.empty?
      InteriorPro::TileWall.wall_by_id(id, model)
    end

    # What the edit window opens with: its own numbers, and how far its
    # line is from the nearer corner.
    def self.settings_of(inst)
      at = lambda { |k| inst.get_attribute('InteriorPro', k) }
      out = begin
        JSON.parse(at.call('cfg_json').to_s)
      rescue StandardError
        {}
      end
      out['kind'] = kind_ok(at.call('kind'))
      out['product'] = (at.call('product') || out['product'] || SIMPLE).to_s
      out['height'] = (out['height'] || at.call('height_in') || default_height(out['kind'])).to_f
      wall = host_wall(inst)
      fr = wall && InteriorPro::TileWall.frame_for(wall, at.call('side').to_s)
      if fr
        lo, hi = InteriorPro::TileWall.face_limits(wall, fr, at.call('u_in').to_f)
        out['corner'] = corner_dist(at.call('u_in').to_f, lo, hi).round(3)
      end
      out
    end

    # Rebuild in place with the window's numbers, same wall and side, the
    # line kept - or moved to the typed distance from the SAME nearer
    # corner. ONE undo step. Nothing changes if it no longer fits.
    def self.update!(inst, cfg)
      return nil unless fixture?(inst)
      at = lambda { |k| inst.get_attribute('InteriorPro', k) }
      wall = host_wall(inst)
      side = at.call('side').to_s
      fr = wall && InteriorPro::TileWall.frame_for(wall, side)
      if fr.nil?
        puts "[Fixture] edit: the wall it stood on (#{at.call('host_wall_id')}) is not found - nothing changed"
        return nil
      end
      u = at.call('u_in').to_f
      if cfg['corner']
        lo, hi = InteriorPro::TileWall.face_limits(wall, fr, u)
        u = u_from_corner(cfg['corner'].to_f, lo, hi, u)
      end
      model = Sketchup.active_model
      parts = layout(model, cfg)
      chk = check(wall, side, fr, u, parts, cfg['kind'], InteriorPro::TileWall.wall_height(wall))
      unless chk[:ok]
        puts "[Fixture] edit: it does not fit there (tile missing #{chk[:no_tile]}, window/niche under it " \
             "#{chk[:on_hole]}, parts #{chk[:rects].map { |r| r.map { |v| v.round(1) } }.inspect}) - nothing changed"
        return nil
      end
      model.start_operation('Edit Fixture', true)
      old_id = at.call('id')
      made = place!(wall: wall, side: side, fr: fr, u: u, cfg: cfg, parts: parts, outs: chk[:outs], op: false)
      if made.nil?
        model.abort_operation
        return nil
      end
      made.set_attribute('InteriorPro', 'id', old_id) if old_id
      inst.erase!
      model.commit_operation
      made
    rescue StandardError => e
      model&.abort_operation
      puts "[Fixture] edit failed: #{e.message}"
      nil
    end
  end
end
