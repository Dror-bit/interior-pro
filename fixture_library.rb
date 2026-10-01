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
#   assets/PLUMBING/VANITIES/<name>.skp   (2026-09-29)
#   assets/PLUMBING/TUBS/<name>.skp       (2026-09-29)
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
    # Kill switch: false = a tub stands on the wall again, the gap ignored.
    USE_WALL_GAP = true unless const_defined?(:USE_WALL_GAP, false)
    # Kill switch: false = a toilet file is placed as it is drawn, unturned.
    USE_TURN_FRONT = true unless const_defined?(:USE_TURN_FRONT, false)
    # Kill switch: false = a tub is placed at its file's own size.
    USE_RESIZE = true unless const_defined?(:USE_RESIZE, false)
    # Kill switch: false = a tub / toilet can stand on the outside of the house again.
    USE_INSIDE_ONLY = true unless const_defined?(:USE_INSIDE_ONLY, false)
    # Kill switch: false = a drop-in tub is placed bare, no deck around it.
    USE_DECK = true unless const_defined?(:USE_DECK, false)
    # THE DECK OF A DROP-IN TUB (2026-10-01). His words on the first one:
    # "צריך שהטיל יהיה גם למעלה באותו גובה של האמבטיה ... רק הלפנים יהיה
    # 3\" מרווח מהאמבטיה ואת שאר הצדדים ברירת מחדל של 0 ואני יכניס ידנית
    # לכל צד". Front 3", left and right 0, the back = From the wall.
    DECK_FRONT_IN = 3.0 unless const_defined?(:DECK_FRONT_IN, false)
    # Kill switch: false = the deck front stays plain white, no tile.
    USE_DECK_TILE = true unless const_defined?(:USE_DECK_TILE, false)
    # Kill switch: false = the top tile simply runs over the front tile's edge.
    USE_DECK_MITER = true unless const_defined?(:USE_DECK_MITER, false)

    # The kinds. A method, not a guarded constant, so reload! sees changes.
    # on_tile: only on a tiled area, standing on its face (his call,
    # "רק מהפנים של הבית ורק על קירות טיל").
    def self.kinds
      {
        'shower_set' => { dir: 'SHOWER SETS', label: 'Shower set', height: 80.0, on_tile: true, set: true },
        # A toilet off the wall too (2026-09-30, his pick "1 ו2"): a real
        # tank stands about 1" off the wall on a 12" rough-in.
        # FACING THE ROOM (2026-09-30, his words: "האסלה הפוכה והכיוון של
        # הפנים שלה פונה כרגע לקיר"). Measured in toilets_report.txt: all
        # three of his toilet files have the tank at +green (back at y 0)
        # and the bowl toward -green. front_neg: turn the file half a turn.
        'toilet'     => { dir: 'TOILETS',     label: 'Toilet',     height: 0.0, gap: 1.0, front_neg: true },
        # VANITY AND TUB (2026-09-29, his words: "אני רוצה את הוונטי בנפרד
        # ואז לשמור אותו ולהכניס אותו"). One .skp each, like a toilet:
        # back on the wall, bottom on the floor, middle on the line.
        'vanity'     => { dir: 'VANITIES',    label: 'Vanity',     height: 0.0 },
        # FROM THE WALL (2026-09-30, his words: "שיהיה אפשרות לקבוע מרחק
        # מהקיר ... ברירת מחדל 4\""). gap: its back stands this far off.
        # resize (2026-10-01, his pick "להקליד לבד"): Length along the wall
        # and Width out of it, typed; the file is stretched to them.
        'tub'        => { dir: 'TUBS',        label: 'Tub',        height: 0.0, gap: 4.0, resize: true }
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

    # How far its back stands off the wall. nil = this kind has no such
    # number (it sits on the wall). PURE.
    # AN ALCOVE TUB SITS ON THE WALL (2026-10-01, his words: "האלקוב מבחינת
    # ברירת מחדל לא צריכה להיות רחוקה מהקיר") - it stands between three
    # walls, so a product with "alcove" in its name starts at 0.
    def self.default_gap(kind, product = nil)
      g = kinds[kind_ok(kind)][:gap]
      return g if g.nil?
      # a drop-in tub too: its back side of the deck is this number (0)
      kind_ok(kind) == 'tub' && product.to_s =~ /alcove|drop/i ? 0.0 : g
    end

    # The gap to use: the window's number, else the kind's default. 0 for
    # a kind without one, and when USE_WALL_GAP is off. Never below 0. PURE.
    def self.wall_gap(kind, cfg)
      return 0.0 unless USE_WALL_GAP
      dg = default_gap(kind, cfg.is_a?(Hash) ? cfg['product'] : nil)
      return 0.0 if dg.nil?
      g = cfg.is_a?(Hash) && !cfg['gap'].nil? && cfg['gap'].to_s != '' ? cfg['gap'].to_f : dg.to_f
      g < 0.0 ? 0.0 : g
    end

    # THE OUTSIDE OF THE HOUSE (2026-10-01, his words: "הציג לי את הפרי
    # סטנדיינג ... בכלל מחוץ לבית"). Measured in fixture_side_report.txt:
    # it stood on side "b" of an exterior wall, the house middle on "a".
    # Exterior = the right of start->end (WallTool rule) = side "b". PURE
    # apart from reading the wall's category.
    def self.outside?(wall, side)
      return false unless USE_INSIDE_ONLY
      return false unless wall.respond_to?(:get_attribute)
      cat = (wall.get_attribute('InteriorPro', 'wall_category') || 'exterior').to_s
      cat == 'exterior' && side.to_s == 'b'
    end

    # A tub with "drop" in its name ("Drop-in tub") gets a deck. PURE.
    # AN ALCOVE TUB GETS SIDES ONLY (2026-10-01, his words: "באלקוב צריך
    # להיות אופציה גם בצדדים"): left / right typed, both 0 by default, no
    # front (its own apron is the front).
    def self.deck?(kind, product)
      USE_DECK && kind_ok(kind) == 'tub' && product.to_s =~ /drop|alcove/i ? true : false
    end

    # Does this product's deck have a front strip at all? PURE.
    def self.deck_front?(product)
      product.to_s =~ /alcove/i ? false : true
    end

    # The window's deck numbers: front, left, right (inches past the tub,
    # LEFT and RIGHT as he stands in the room facing the wall). PURE.
    def self.deck_sides(cfg)
      num = lambda do |k, dflt|
        v = cfg.is_a?(Hash) ? cfg[k] : nil
        v = v.nil? || v.to_s == '' ? dflt : v.to_f
        v < 0.0 ? 0.0 : v
      end
      fr = deck_front?(cfg.is_a?(Hash) ? cfg['product'] : nil) ? num.call('deck_front', DECK_FRONT_IN) : 0.0
      [fr, num.call('deck_left', 0.0), num.call('deck_right', 0.0)]
    end

    # Facing the wall from the room, +u runs to the LEFT on side "a" and to
    # the RIGHT on side "b" (side a's normal is left of start->end). PURE.
    def self.deck_lo_hi(side, left, right)
      side.to_s == 'b' ? [left, right] : [right, left]
    end

    # The deck on the face, from the placed tub part p at line u, standing
    # `out` off the wall. o = inches out of the wall. h = the deck body's
    # top: under the tub's top by the tile on it (dp), so the tile's face
    # lands level with the tub. PURE.
    #   { u0:, u1:, o0:, o1:, h:, tub: [u0, u1, o0, o1], front: }
    def self.deck_box(p, u, out, front, lo, hi, dp = 0.0)
      cu = u.to_f + p[:du].to_f
      tu0 = cu + p[:minx] - p[:ax]
      tu1 = cu + p[:maxx] - p[:ax]
      to0 = out.to_f
      to1 = to0 + (p[:maxy] - p[:miny])
      { u0: tu0 - lo.to_f, u1: tu1 + hi.to_f, o0: 0.0, o1: to1 + front.to_f,
        h: (p[:maxz] - p[:minz]) - dp.to_f, tub: [tu0, tu1, to0, to1], front: front.to_f }
    end

    # The deck as STRIPS round the tub, each in its own group (CLAUDE.md:
    # every board in its own group): [u0, u1, o0, o1] for each side wider
    # than nothing. PURE.
    def self.deck_strips(d)
      tu0, tu1, to0, to1 = d[:tub]
      [[d[:u0], d[:u1], to1, d[:o1]],    # front
       [d[:u0], d[:u1], d[:o0], to0],    # back (From the wall)
       [d[:u0], tu0, to0, to1],          # the low-u end
       [tu1, d[:u1], to0, to1]]          # the high-u end
        .select { |a0, a1, b0, b1| a1 - a0 > 0.01 && b1 - b0 > 0.01 }
    end

    def self.deck_pt(fr, uu, oo, zz)
      x, y, z = InteriorPro::TileWall.world(fr, uu, zz, oo)
      Geom::Point3d.new(x, y, z)
    end

    # Build the deck body: each strip a box from the floor, white.
    def self.build_deck!(grp, fr, d)
      model = Sketchup.active_model
      mat = model.materials['InteriorPro_Deck'] || model.materials.add('InteriorPro_Deck')
      mat.color = Sketchup::Color.new(245, 245, 245)
      g = grp.entities.add_group
      g.name = 'InteriorPro_TubDeck'
      deck_strips(d).each do |a0, a1, b0, b1|
        sg = g.entities.add_group
        f = sg.entities.add_face([[a0, b0], [a1, b0], [a1, b1], [a0, b1]].map { |a, b| deck_pt(fr, a, b, 0.0) })
        if f.nil?
          puts "[Fixture] deck: a strip #{[a0, a1, b0, b1].map { |v| v.round(2) }.inspect} could not be made"
          sg.erase!
          next
        end
        f.reverse! if f.normal.z > 0
        f.pushpull(-d[:h])
        sg.entities.grep(Sketchup::Face).each { |fc| fc.material = mat }
      end
      if g.entities.length.zero?
        puts '[Fixture] deck: every side is 0 - no deck'
        g.erase!
        return nil
      end
      g
    end

    # THE DECK WEARS THE WALL'S TILE (2026-10-01, his words: "שהריצפה
    # תהיה כמו או הריצפה או נטיל של הקירות" - default "הקיר"). The tiled
    # area on the SAME wall and side that overlaps the deck the most. nil =
    # no tile on that wall - the deck stays white.
    def self.deck_source(wall, side, u0, u1, model = Sketchup.active_model)
      wid = wall.get_attribute('InteriorPro', 'id').to_s
      best = nil
      most = 0.0
      InteriorPro::TileWall.areas_in_model(model).each do |g|
        at = lambda { |k| g.get_attribute('InteriorPro', k) }
        next unless at.call('wall_id').to_s == wid && at.call('side').to_s == side.to_s
        a0 = (at.call('built_u0') || at.call('u0')).to_f
        a1 = a0 + (at.call('built_w') || at.call('area_w')).to_f
        ov = [a1, u1].min - [a0, u0].max
        ov = 0.001 if ov <= 0.0 && best.nil? # same wall, not over it: still better than nothing
        if ov > most
          most = ov
          best = g
        end
      end
      best
    end

    # Where the wall's grid puts its first joint, so the deck's joints run
    # on from the wall's: [u, v] to hand to the grid as its push. PURE.
    def self.grid_phase(first_u, first_v, deck_u0, deck_z0 = 0.0)
      [first_u.to_f - deck_u0.to_f, first_v.to_f - deck_z0.to_f]
    end

    # Everything the deck's tile takes from the wall's tiled area.
    def self.deck_tile_spec(src)
      tw_mod = InteriorPro::TileWall
      at = lambda { |k| src.get_attribute('InteriorPro', k) }
      c = tw_mod.card(at.call('material_card_id'))
      tw = at.call('tile_w').to_f
      tl = at.call('tile_l').to_f
      tw = 12.0 if tw <= 0.25
      tl = tw if tl <= 0.25
      sp = { id: at.call('id'), tw: tw, tl: tl, g: at.call('pattern_grout').to_f, st: at.call('pattern_stagger').to_f,
             dp: at.call('tile_depth').nil? ? tw_mod::DEFAULT_DEPTH : at.call('tile_depth').to_f,
             gc: at.call('pattern_grout_color'), first_u: nil, first_v: nil,
             img_w: c && c['texture_width_inches'].to_f > 0.25 ? c['texture_width_inches'].to_f : nil,
             img_l: c && c['texture_height_inches'].to_f > 0.25 ? c['texture_height_inches'].to_f : nil,
             mat: c ? (InteriorPro::MaterialLibraryDialog.material_from_card(Sketchup.active_model, c) rescue nil) : nil }
      sp[:dp] = 0.0 if sp[:dp] < 0.02
      if at.call('pattern_angle').to_f.abs < 1.0e-9
        bu0 = (at.call('built_u0') || at.call('u0')).to_f
        bw = (at.call('built_w') || at.call('area_w')).to_f
        cen = tw_mod.center_for_grid(tw_mod.center_value(at.call('pattern_center')), at.call('pattern_center_axis'))
        cells = InteriorPro::TileGrid.cells(tw_mod.rect(bu0, at.call('z0').to_f, bw, at.call('area_h').to_f),
                                            u_size: tw, v_size: tl, grout: sp[:g], ox: at.call('pattern_ox').to_f,
                                            oy: at.call('pattern_oy').to_f, centered: cen, stagger: 0.0, limit: 200_000) || []
        unless cells.empty?
          sp[:first_u] = cells.first[:u0]
          sp[:first_v] = cells.first[:v0]
        end
      end
      sp
    end

    # The deck's FRONT, tiled like a wall (same pieces, grout, solids as
    # TileWall) on a frame standing at the deck's front face. Its tiles
    # stop under the top tile, which runs over them (boards meet).
    def self.build_deck_front_tile!(ge, fr, d, sp, a0 = d[:u0], a1 = d[:u1])
      tw_mod = InteriorPro::TileWall
      frd = fr.merge(ox: fr[:ox] + fr[:nx] * d[:o1], oy: fr[:oy] + fr[:ny] * d[:o1])
      w = a1 - a0
      ht = d[:h] + (miter_on?(sp) ? sp[:dp] : 0.0)
      pu, pv = sp[:first_u] ? grid_phase(sp[:first_u], sp[:first_v], a0) : [0.0, 0.0]
      ps = tw_mod.pieces_rect(a0, 0.0, w, ht, [], u_size: sp[:tw], v_size: sp[:tl], grout: sp[:g],
                              ox: pu, oy: pv, centered: false, stagger: sp[:st]) || []
      solid = tw_mod::USE_SOLID_TILES && sp[:dp] > 0.02 && sp[:mat] && ps.length <= tw_mod::MAX_SOLID
      if sp[:mat]
        back = solid ? [sp[:dp] - tw_mod::GROUT_BACK, tw_mod::GROUT_OFF].max : tw_mod::GROUT_OFF
        # the grout stops at the deck's corner, never inside the 45 degree edge
        tw_mod.emit_area_faces!(ge, frd, [tw_mod.rect(a0, 0.0, w, d[:h])],
                                tw_mod.grout_material(Sketchup.active_model, sp[:gc]), back)
      end
      if solid
        tw_mod.emit_tile_solids!(ge, frd, ps, sp[:mat], sp[:img_w] || sp[:tw], sp[:img_l] || sp[:tl], sp[:dp])
      elsif sp[:mat]
        tw_mod.emit_tile_faces!(ge, frd, ps, sp[:mat], sp[:img_w] || sp[:tw], sp[:img_l] || sp[:tl])
      else
        tw_mod.emit_tile_edges!(ge, frd, ps)
      end
      ps.length
    end

    # The deck's TOP: the same grid laid flat, u along the wall and v out
    # of it, round the tub's hole. Each tile its own little box standing
    # up from the deck body to the tub's height.
    def self.build_deck_top_tile!(ge, fr, d, sp, o_end)
      tw_mod = InteriorPro::TileWall
      w = d[:u1] - d[:u0]
      depth = o_end - d[:o0]
      tu0, tu1, to0, to1 = d[:tub]
      # no front strip: the tub's own front is open, nothing runs out over it
      holes = [[tu0, to0, tu1, d[:front] > 0.01 ? to1 : [to1, o_end].max]]
      pu = sp[:first_u] ? sp[:first_u] - d[:u0] : 0.0
      ps = tw_mod.pieces_rect(d[:u0], d[:o0], w, depth, holes, u_size: sp[:tw], v_size: sp[:tl], grout: sp[:g],
                              ox: pu, oy: 0.0, centered: false, stagger: sp[:st]) || []
      flat = lambda do |ents, ring, z|
        f = ents.add_face(ring.map { |a, b| deck_pt(fr, a, b, z) }) rescue nil
        return nil if f.nil?
        tw_mod.ring_holes(ring).each do |hr|
          inner = ents.add_face(hr.map { |a, b| deck_pt(fr, a, b, z) }) rescue nil
          inner.erase! if inner && inner.valid? && !inner.equal?(f)
        end
        f.reverse! if f.valid? && f.normal.z < 0
        f.valid? ? f : nil
      end
      dp = sp[:dp]
      if sp[:mat]
        back = dp > 0.02 ? [dp - tw_mod::GROUT_BACK, tw_mod::GROUT_OFF].max : tw_mod::GROUT_OFF
        gm = tw_mod.grout_material(Sketchup.active_model, sp[:gc])
        tw_mod.area_polys(d[:u0], d[:o0], w, [d[:o1] - d[:o0], depth].min, holes).each do |poly|
          f = flat.call(ge, poly, d[:h] + back)
          next unless f
          f.material = gm
          f.back_material = gm
          f.edges.each { |e| e.hidden = true; e.soft = true; e.smooth = true }
        end
      end
      tex_u = sp[:img_w] || sp[:tw]
      tex_v = sp[:img_l] || sp[:tl]
      ps.each do |p|
        sub = ge.add_group
        f = flat.call(sub.entities, p[:poly], d[:h])
        if f.nil?
          sub.erase!
          next
        end
        f.pushpull(dp) if dp > 0.02
        next unless sp[:mat]
        sub.entities.grep(Sketchup::Face).each { |q| q.material = sp[:mat]; q.back_material = sp[:mat] }
        top = sub.entities.grep(Sketchup::Face).max_by { |q| q.bounds.max.z }
        o = deck_pt(fr, p[:u0], p[:v0], d[:h] + dp)
        pu = deck_pt(fr, p[:u0] + tex_u, p[:v0], d[:h] + dp)
        pv = deck_pt(fr, p[:u0], p[:v0] + tex_v, d[:h] + dp)
        begin
          top.position_material(sp[:mat], [o, Geom::Point3d.new(0, 0, 0), pu, Geom::Point3d.new(1, 0, 0),
                                           pv, Geom::Point3d.new(0, 1, 0)], true)
        rescue StandardError
          nil
        end
      end
      ps.length
    end

    # THE DECK STOPS AT THE SIDE WALLS (2026-10-01, his words: "הצדדים ...
    # לא יכולים להיכנס לתוך הקיר לא משנה כמה אינצים אני רוצה המקסימום הוא
    # לגעת בטיל שעל הקיר"). Clip its two ends to [lo, hi]. PURE.
    def self.clamp_deck(d, lo, hi)
      d.merge(u0: [d[:u0], lo.to_f].max, u1: [d[:u1], hi.to_f].min)
    end

    # How far the deck may run along the wall: the faces of the walls at
    # each side (TileWall.face_limits), then back to the face of any tile
    # standing on them beside the deck. [lo, hi] in this face's u.
    def self.deck_limits(wall, fr, d, model = Sketchup.active_model)
      tu0, tu1, = d[:tub]
      lo, hi = InteriorPro::TileWall.face_limits(wall, fr, (tu0 + tu1) / 2.0, model)
      wid = wall.get_attribute('InteriorPro', 'id').to_s
      z0 = fr[:floor_z].to_f
      InteriorPro::TileWall.areas_in_model(model).each do |g|
        next if g.get_attribute('InteriorPro', 'wall_id').to_s == wid
        b = g.bounds
        us = []
        os = []
        8.times do |k|
          c = b.corner(k)
          us << (c.x - fr[:ox]) * fr[:ux] + (c.y - fr[:oy]) * fr[:uy]
          os << (c.x - fr[:ox]) * fr[:nx] + (c.y - fr[:oy]) * fr[:ny]
        end
        # only a tile beside the deck: in front of the wall, low enough
        next if os.max <= d[:o0] + 0.01 || os.min >= d[:o1] - 0.01
        next if b.min.z.to_f >= z0 + d[:h] + 1.0
        if us.max <= tu0 + 0.01
          lo = us.max if us.max > lo
        elsif us.min >= tu1 - 0.01
          hi = us.min if us.min < hi
        end
      end
      [lo, hi]
    rescue StandardError => e
      puts "[Fixture] deck limits: #{e.message}"
      [-1.0e9, 1.0e9]
    end

    # ONE SIDE 0, THE OTHER A NUMBER = THE TUB GOES TO THE WALL ON THE 0
    # SIDE (2026-10-01, his words: "אם אני לוחץ 0 בצד אחד ומספר בצד שני
    # האמבטיה צריכה להידבק לקיר בצד של ה-0"). The new line u. PURE.
    def self.snap_deck_u(u, tu0, tu1, lim_lo, lim_hi, lo, hi)
      if lo.to_f <= 0.0 && hi.to_f > 0.0
        u.to_f + (lim_lo.to_f - tu0.to_f)
      elsif hi.to_f <= 0.0 && lo.to_f > 0.0
        u.to_f + (lim_hi.to_f - tu1.to_f)
      else
        u.to_f
      end
    end

    def self.snap_to_side_wall(wall, side, fr, u, cfg, parts, outs)
      return u unless deck?(cfg['kind'], cfg['product']) && parts.length == 1
      _front, left, right = deck_sides(cfg)
      lo, hi = deck_lo_hi(side, left, right)
      return u if (lo <= 0.0) == (hi <= 0.0)
      d0 = deck_box(parts[0], u, outs[0], 0.0, 0.0, 0.0)
      lim_lo, lim_hi = deck_limits(wall, fr, d0)
      nu = snap_deck_u(u, d0[:tub][0], d0[:tub][1], lim_lo, lim_hi, lo, hi)
      if (nu - u).abs > 1.0e5
        puts '[Fixture] deck: no side wall found to put the tub against - left where it was clicked'
        return u
      end
      puts "[Fixture] deck: tub moved #{(nu - u).round(2)}\" to the wall on its 0 side" if (nu - u).abs > 0.001
      nu
    end

    # Where the deck shows a front face to the room, as [u0, u1] spans. PURE.
    def self.deck_front_spans(d)
      tu0, tu1, = d[:tub]
      spans = d[:front] > 0.01 ? [[d[:u0], d[:u1]]] : [[d[:u0], tu0], [tu1, d[:u1]]]
      spans.select { |a0, a1| a1 - a0 > 0.01 }
    end

    def self.miter_on?(sp)
      USE_DECK_MITER && sp[:dp].to_f > 0.02 && sp[:mat] && InteriorPro::TileWall::USE_SOLID_TILES
    end

    # THE FRONT EDGE AT 45 DEGREES (2026-10-01, his words: "שהחיבור פה יהיה
    # 45 מעלות"). The front tiles run up to the top of the top tile; the
    # top tiles run out to the face of the front tile. Then the two inner
    # corners are pulled back along the 45 degree line, the same way the
    # niche corners are bevelled: on a front tile the top INNER corner
    # comes down by the tile's depth, on a top tile the bottom OUTER corner
    # comes in by it. They meet on one plane, nothing runs inside the other.
    # Returns [front tiles cut, top tiles cut].
    def self.miter_deck_edge!(gf, gt, fr, d, dp)
      tol = 0.01
      z_top = fr[:floor_z].to_f + d[:h] + dp
      z_bed = fr[:floor_z].to_f + d[:h]
      o_of = lambda { |p| (p.x - fr[:ox]) * fr[:nx] + (p.y - fr[:oy]) * fr[:ny] }
      move = lambda do |grp, pick, vec|
        n = 0
        grp.entities.grep(Sketchup::Group).each do |tg|
          vs = tg.entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq.select { |v| pick.call(v.position) }
          next if vs.empty?
          tg.entities.transform_by_vectors(vs, Array.new(vs.length) { vec })
          n += 1
        end
        n
      end
      down = Geom::Vector3d.new(0, 0, -dp)
      back = Geom::Vector3d.new(-fr[:nx] * dp, -fr[:ny] * dp, 0)
      mf = move.call(gf, ->(p) { (p.z - z_top).abs < tol && (o_of.call(p) - d[:o1]).abs < tol }, down)
      mt = move.call(gt, ->(p) { (p.z - z_bed).abs < tol && (o_of.call(p) - (d[:o1] + dp)).abs < tol }, back)
      [mf, mt]
    rescue StandardError => e
      puts "[Fixture] the 45 degree edge could not be cut: #{e.message}"
      [0, 0]
    end

    # Tile the deck - its top always, its front when it has one - in its
    # OWN group inside the fixture group.
    def self.build_deck_tile!(grp, fr, d, sp)
      return nil unless USE_DECK_TILE
      sub = grp.entities.add_group
      sub.name = 'InteriorPro_TubDeckTile'
      gf = sub.entities.add_group
      gt = sub.entities.add_group
      # THE FRONT FACES (2026-10-01, his words on the alcove: "שהצדדים פה
      # יהיה עליהם גם טיל בחיתוך של 45 מעלות"): with a front strip, one face
      # the whole deck wide; without one, the front of each side strip.
      nf = deck_front_spans(d).sum { |a0, a1| build_deck_front_tile!(gf.entities, fr, d, sp, a0, a1) }
      # the top runs over the front tile's edge (boards meet, not inside each other)
      nt = build_deck_top_tile!(gt.entities, fr, d, sp, d[:o1] + (nf > 0 ? sp[:dp] : 0.0))
      mf = mt = 0
      if nf > 0 && miter_on?(sp)
        mf, mt = miter_deck_edge!(gf, gt, fr, d, sp[:dp])
      end
      puts "[Fixture] deck tile from area #{sp[:id]}: front #{nf} piece(s), top #{nt} piece(s), #{sp[:tw]}x#{sp[:tl]}, " \
           "45 deg edge: #{mf} front + #{mt} top tile(s) cut"
      sub
    rescue StandardError => e
      puts "[Fixture] deck tile failed: #{e.class}: #{e.message} #{e.backtrace.first}"
      nil
    end

    def self.resize?(kind)
      USE_RESIZE && kinds[kind_ok(kind)][:resize] ? true : false
    end

    # How much to stretch along red (length) and green (width) so the
    # file's w0 x d0 becomes len x wid. Empty / 0 = its own size. PURE.
    def self.scale_for(len, wid, w0, d0)
      f = lambda do |want, have|
        w = want.to_s == '' ? 0.0 : want.to_f
        w > 0.0 && have.to_f > 1.0e-6 ? w / have.to_f : 1.0
      end
      [f.call(len, w0), f.call(wid, d0)]
    end

    # The file's own size along red and green (the window shows it).
    def self.size_of(model, kind, name)
      d = definition_for(model, kind, name)
      return nil unless d
      b = visible_bounds(d)
      [(b.max.x - b.min.x).to_f.round(2), (b.max.y - b.min.y).to_f.round(2)]
    rescue StandardError => e
      puts "[Fixture] size of #{kind}/#{name}: #{e.message}"
      nil
    end

    # Is this product's file drawn with its front toward -green? Then it
    # is turned half a turn before placing. The stand-in never is. PURE.
    def self.turn_front?(kind, product)
      return false unless USE_TURN_FRONT
      return false if product.to_s.empty? || product.to_s == SIMPLE
      # HIS ALCOVE TUB IS DRAWN BACKWARDS (2026-10-01, his words: "האלקוב
      # היא הפוכה" - the other three tubs are right). Same rule as its gap.
      return true if kind_ok(kind) == 'tub' && product.to_s =~ /alcove/i
      kinds[kind_ok(kind)][:front_neg] ? true : false
    end

    # The box after half a turn about the blue axis: x and y flip sign.
    # [minx, maxx, miny, maxy, ax]. PURE.
    def self.turned_box(minx, maxx, miny, maxy, ax)
      [-maxx, -minx, -maxy, -miny, -ax]
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
    # NO STAND-IN NEXT TO HIS OWN (2026-10-01, his words: "תוריד את
    # הסאמפלים מכל האופציות"). 'Simple' shows only while a kind has no
    # file of its own yet, so the window is never empty.
    def self.products(kind)
      n = names(kind)
      n.empty? ? [SIMPLE] : n
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
        # THE TUB SPOUT STARTS OFF (2026-09-29, his pick "ברירת מחדל"): most
        # showers have no tub - he ticks it in the window when there is one.
        on = have.include?(k) && k != 'spout'
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
      return [[-15.0, 15.0, 0.0, 21.0, 0.0, 33.0], [-15.5, 15.5, 0.0, 22.0, 33.0, 34.5]] if kind == 'vanity'
      return [[-30.0, 30.0, 0.0, 30.0, 0.0, 20.0]] if kind == 'tub'
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

    # "SAVE SELECTED" (2026-09-29, his words: "אני רוצה את הוונטי בנפרד ואז
    # לשמור אותו ולהכניס אותו ... ספרייה של וונטיס ואמבטיות"). He builds a
    # vanity or a tub in the model, selects it, and it is saved into the
    # kind's folder as its own .skp - a new product in the list. ONE group
    # or component, and only a single-file kind (a set is a folder).
    def self.saveable?(ent)
      (ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)) && ent.valid? &&
        ent.respond_to?(:definition)
    end

    def self.save_selected!(kind, ent, name)
      kind = kind_ok(kind)
      if set_kind?(kind)
        puts "[Fixture] save selected: #{kind} is a set (a folder) - not saved"
        return nil
      end
      unless saveable?(ent)
        puts "[Fixture] save selected: not one group or component (#{ent.class}) - not saved"
        return nil
      end
      dir = dir_for(kind)
      FileUtils.mkdir_p(dir)
      nm = clean_name(name, names(kind) + [SIMPLE])
      path = File.join(dir, "#{nm}.skp")
      ok = ent.definition.save_as(path)
      unless ok && File.exist?(path)
        puts "[Fixture] save selected: SketchUp did not write #{path} (save_as #{ok.inspect})"
        return nil
      end
      puts "[Fixture] saved the selected #{ent.class.name.split('::').last} as #{kind}/#{nm} -> #{path}"
      ensure_thumb(Sketchup.active_model, kind, nm)
      nm
    rescue StandardError => e
      puts "[Fixture] save selected failed: #{e.message}"
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
      gap = set_kind?(kind) ? 0.0 : wall_gap(kind, cfg)
      list.map do |k, du, h|
        d = definition_for(model, kind, cfg['product'], k)
        if d.nil?
          puts "[Fixture] no definition for #{kind}/#{cfg['product']}/#{k} - that part is left out"
          next nil
        end
        b = visible_bounds(d)
        ax, az = anchor_xz(b.min.x, b.max.x, b.min.z, b.max.z, !k.nil?)
        minx, maxx, miny, maxy = b.min.x.to_f, b.max.x.to_f, b.min.y.to_f, b.max.y.to_f
        sx, sy = resize?(kind) ? scale_for(cfg['len'], cfg['wid'], maxx - minx, maxy - miny) : [1.0, 1.0]
        minx, maxx, ax = minx * sx, maxx * sx, ax.to_f * sx
        miny, maxy = miny * sy, maxy * sy
        turn = turn_front?(kind, cfg['product'])
        minx, maxx, miny, maxy, ax = turned_box(minx, maxx, miny, maxy, ax.to_f) if turn
        { part: k, defn: d, du: du, h: h, ax: ax, az: az, gap: gap, turn: turn, sx: sx, sy: sy,
          minx: minx, maxx: maxx, miny: miny, maxy: maxy,
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
        # a tub's gap: its back stands this far off the wall (ghost, place, edit)
        res[:outs] << out + p[:gap].to_f
      end
      # a tub or toilet is not even caught on the outside of the house
      res[:outside] = !on_tile?(kind) && outside?(wall, side)
      res[:ok] = false if res[:no_tile] || res[:on_hole] || res[:outside]
      res
    end

    # ---- placing --------------------------------------------------------

    # Put the fixture on the face: ONE group holding one instance per part.
    def self.place!(wall:, side:, fr:, u:, cfg:, parts:, outs:, op: true)
      model = Sketchup.active_model
      model.start_operation('Place Fixture', true) if op
      grp = model.entities.add_group
      grp.name = 'InteriorPro_Fixture'
      u = snap_to_side_wall(wall, side, fr, u, cfg, parts, outs)
      parts.each_with_index do |p, i|
        shift = Geom::Transformation.translation(Geom::Vector3d.new(-p[:ax], -p[:miny], -p[:az]))
        x, y, zz = InteriorPro::TileWall.world(fr, u + p[:du], p[:h], outs[i].to_f)
        face = Geom::Transformation.axes(Geom::Point3d.new(x, y, zz),
                                         Geom::Vector3d.new(fr[:ux], fr[:uy], 0),
                                         Geom::Vector3d.new(fr[:nx], fr[:ny], 0),
                                         Geom::Vector3d.new(0, 0, 1))
        # a file drawn facing -green is turned half a turn first (front_neg)
        shift = shift * Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), Math::PI) if p[:turn]
        # a tub stretched to the typed length / width (applied first)
        if (p[:sx] && (p[:sx] - 1.0).abs > 1.0e-9) || (p[:sy] && (p[:sy] - 1.0).abs > 1.0e-9)
          shift = shift * Geom::Transformation.scaling(Geom::Point3d.new(0, 0, 0), p[:sx].to_f, p[:sy].to_f, 1.0)
        end
        inst = grp.entities.add_instance(p[:defn], face * shift)
        inst.set_attribute('InteriorPro', 'part', p[:part].to_s) if p[:part]
      end
      if deck?(cfg['kind'], cfg['product']) && parts.length == 1
        front, left, right = deck_sides(cfg)
        lo, hi = deck_lo_hi(side, left, right)
        dk = deck_box(parts[0], u, outs[0], front, lo, hi)
        src = USE_DECK_TILE ? deck_source(wall, side, dk[:u0], dk[:u1]) : nil
        sp = src ? deck_tile_spec(src) : nil
        # the body stops under the top tile, so the tile's face is level with the tub
        dk = deck_box(parts[0], u, outs[0], front, lo, hi, sp ? sp[:dp] : 0.0) if sp
        lim_lo, lim_hi = deck_limits(wall, fr, dk)
        if dk[:u0] < lim_lo - 0.001 || dk[:u1] > lim_hi + 0.001
          puts "[Fixture] deck: its ends stop at the side walls' tile (#{dk[:u0].round(2)}..#{dk[:u1].round(2)} " \
               "-> #{[dk[:u0], lim_lo].max.round(2)}..#{[dk[:u1], lim_hi].min.round(2)})"
          dk = clamp_deck(dk, lim_lo, lim_hi)
        end
        built = build_deck!(grp, fr, dk)
        if sp && built
          build_deck_tile!(grp, fr, dk, sp)
        elsif USE_DECK_TILE
          puts '[Fixture] deck: no tiled area on this wall - the deck is left white'
        end
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
      # placed before the gap existed = it stands on the wall; keep it there
      out['gap'] = out.key?('gap') ? out['gap'].to_f : 0.0 unless default_gap(out['kind']).nil?
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
