# encoding: utf-8
# Interior Pro - THE TILE LAYOUT SHEET (2026-09-06)
#
# The second of the three outputs he asked for: render, LAYOUT DRAWING,
# quantities. It draws the same cells tile_count.rb counts - one
# calculation, three outputs - so the picture and the order can never
# disagree.
#
# What he wanted on it, and what he did NOT:
#   "אני רק מזמין את החומר אני לא אומר לו איך לחתוך כי לפעמים יש כל מיני
#    דברים שאין בסירטוטים... אז ניתן לקבלן להסתדר עם זה בעצמו"
# So: the layout, the room's dimensions, and the number to order. NO cut
# schedule. The three colours stay, because they are where the number
# comes from - and the pieces under 20% are a line of their own, which
# is the one he prices with the contractor separately.
#
# The drawing itself is PURE (numbers in, an SVG string out), so
# tests/rt169.rb pins it without SketchUp. Only write_all! touches the
# model, and it only READS - nothing is built and nothing is changed.
require_relative 'tile_grid'
require_relative 'tile_count'

module InteriorPro
  module TileSheet
    FILL = { full: '#ffffff', cut: '#cfe0ef', small: '#f2c9a8' }.freeze unless const_defined?(:FILL, false)
    INK = '#1d2733'.freeze unless const_defined?(:INK, false)
    HAIR = '#5a5f66'.freeze unless const_defined?(:HAIR, false)
    MUTED = '#6b7280'.freeze unless const_defined?(:MUTED, false)
    PAPER = '#fbfaf8'.freeze unless const_defined?(:PAPER, false)
    BOX_W = 620.0 unless const_defined?(:BOX_W, false)
    BOX_H = 760.0 unless const_defined?(:BOX_H, false)

    # PURE. Inches as feet and inches, to the sixteenth: 283.071 -> 23'-7 1/16"
    def self.ftin(v)
      neg = v.to_f.negative?
      v = v.to_f.abs
      f = (v / 12.0).floor
      s = ((v - f * 12) * 16).round
      if s == 192
        f += 1
        s = 0
      end
      whole = s / 16
      frac = s % 16
      txt = f.positive? ? "#{f}'-" : ''
      txt += if frac.zero?
               "#{whole}\""
             else
               g = frac.gcd(16)
               "#{whole} #{frac / g}/#{16 / g}\""
             end
      (neg ? '-' : '') + txt
    end

    def self.esc(s)
      s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
    end

    # PURE. Every piece of tile that actually lies in the room, as the
    # polygon it really is - clipped, so an L-shaped room and a turned
    # layout both draw true. Classified exactly the way the count does.
    def self.pieces(poly, tw, tl, grout: 0.0, angle: 0.0, ox: 0.0, oy: 0.0,
                    centered: false, stagger: 0.0, pct: InteriorPro::TileCount::MIN_REUSE_PCT)
      cells = InteriorPro::TileGrid.cells(poly, u_size: tw, v_size: tl,
                                               grout: grout, angle: angle,
                                               ox: ox, oy: oy,
                                               centered: centered, stagger: stagger)
      return [] if cells.nil?
      fr = InteriorPro::TileGrid.degrees(angle)
      cell_area = tw.to_f * tl.to_f
      out = []
      cells.each do |c|
        shape = InteriorPro::TileCount.clip_convex(poly, c[:quad])
        a = InteriorPro::TileCount.area(shape)
        next if a <= cell_area * 0.0005
        kind = if a >= cell_area - InteriorPro::TileCount::EPS * 100
                 :full
               else
                 uv = shape.map { |p| InteriorPro::TileGrid.to_uv(p[0], p[1], fr) }
                 w = InteriorPro::TileCount.r16(uv.map { |q| q[0] }.max - uv.map { |q| q[0] }.min)
                 h = InteriorPro::TileCount.r16(uv.map { |q| q[1] }.max - uv.map { |q| q[1] }.min)
                 InteriorPro::TileCount.small?([w, h], tw, tl, pct) ? :small : :cut
               end
        out << { shape: shape, kind: kind }
      end
      out
    end

    # PURE. The sheet, as an SVG string.
    def self.svg(name, poly, tw, tl, grout: 0.0, angle: 0.0, ox: 0.0, oy: 0.0,
                 centered: false, stagger: 0.0, pct: InteriorPro::TileCount::MIN_REUSE_PCT,
                 area_sqft: nil)
      parts = pieces(poly, tw, tl, grout: grout, angle: angle, ox: ox, oy: oy,
                                   centered: centered, stagger: stagger, pct: pct)
      res = InteriorPro::TileCount.plan(poly, tw, tl, grout: grout, ox: ox, oy: oy,
                                              angle: angle, centered: centered,
                                              stagger: stagger, pct: pct)
      xs = poly.map { |p| InteriorPro::TileGrid.xy(p)[0] }
      ys = poly.map { |p| InteriorPro::TileGrid.xy(p)[1] }
      rw = xs.max - xs.min
      rh = ys.max - ys.min
      return nil if rw <= 0 || rh <= 0
      sc = [BOX_W / rw, BOX_H / rh].min
      dw = rw * sc
      dh = rh * sc

      pad_l = 108
      pad_t = 84
      pad_r = 292
      pad_b = 96
      sw = (pad_l + dw + pad_r).round
      sh = (pad_t + dh + pad_b).round
      px = ->(x) { (pad_l + (x - xs.min) * sc).round(2) }
      py = ->(y) { (pad_t + dh - (y - ys.min) * sc).round(2) }

      s = []
      s << %(<svg xmlns="http://www.w3.org/2000/svg" width="#{sw}" height="#{sh}" ) +
           %(viewBox="0 0 #{sw} #{sh}" font-family="Helvetica, Arial, sans-serif">)
      s << %(<rect width="#{sw}" height="#{sh}" fill="#{PAPER}"/>)

      parts.each do |pc|
        pts = pc[:shape].map { |p| "#{px.call(p[0])},#{py.call(p[1])}" }.join(' ')
        s << %(<polygon points="#{pts}" fill="#{FILL[pc[:kind]]}" stroke="#{HAIR}" stroke-width="0.7"/>)
      end
      room = poly.map { |p| q = InteriorPro::TileGrid.xy(p); "#{px.call(q[0])},#{py.call(q[1])}" }.join(' ')
      s << %(<polygon points="#{room}" fill="none" stroke="#{INK}" stroke-width="2"/>)

      # overall dimensions
      dy = (pad_t + dh + 34).round
      s << %(<line x1="#{pad_l}" y1="#{dy}" x2="#{(pad_l + dw).round(2)}" y2="#{dy}" stroke="#{INK}" stroke-width="1"/>)
      [pad_l, (pad_l + dw).round(2)].each do |x|
        s << %(<line x1="#{x}" y1="#{dy - 6}" x2="#{x}" y2="#{dy + 6}" stroke="#{INK}" stroke-width="1"/>)
      end
      s << %(<text x="#{(pad_l + dw / 2).round}" y="#{dy + 22}" font-size="14" text-anchor="middle" fill="#{INK}">#{ftin(rw)}</text>)
      dx = pad_l - 40
      cy = (pad_t + dh / 2).round
      s << %(<line x1="#{dx}" y1="#{pad_t}" x2="#{dx}" y2="#{(pad_t + dh).round(2)}" stroke="#{INK}" stroke-width="1"/>)
      [pad_t, (pad_t + dh).round(2)].each do |y|
        s << %(<line x1="#{dx - 6}" y1="#{y}" x2="#{dx + 6}" y2="#{y}" stroke="#{INK}" stroke-width="1"/>)
      end
      s << %(<text x="#{dx - 12}" y="#{cy}" font-size="14" text-anchor="middle" fill="#{INK}" ) +
           %(transform="rotate(-90 #{dx - 12} #{cy})">#{ftin(rh)}</text>)

      sub = []
      sub << format('%.1f sq ft', area_sqft) if area_sqft
      sub << "tile #{fmt(tw)} x #{fmt(tl)}"
      sub << "joint #{fmt(grout)}\"" if grout.to_f > 0
      sub << "#{fmt(angle)}&#176;" if angle.to_f.abs > 0.001
      sub << 'centred' if centered
      s << %(<text x="#{pad_l}" y="38" font-size="19" fill="#{INK}">#{esc(name)}</text>)
      s << %(<text x="#{pad_l}" y="60" font-size="13" fill="#{MUTED}">#{sub.join(' &#183; ')}</text>)

      # what to order
      lx = (pad_l + dw + 34).round
      ly = pad_t + 4
      rows = [[:full, 'whole tiles', res[:full]],
              [:cut, 'cut pieces', res[:cut_pieces]],
              [:small, "under #{fmt(pct)}% (waste)", res[:small_pieces]]]
      rows.each_with_index do |(k, label, n), i|
        y = ly + 14 + i * 26
        s << %(<rect x="#{lx}" y="#{y - 11}" width="15" height="15" fill="#{FILL[k]}" stroke="#{HAIR}" stroke-width="0.8"/>)
        s << %(<text x="#{lx + 24}" y="#{y}" font-size="13" fill="#{INK}">#{label}</text>)
        s << %(<text x="#{lx + 232}" y="#{y}" font-size="13" text-anchor="end" fill="#{INK}">#{n}</text>)
      end
      s << %(<line x1="#{lx}" y1="#{ly + 84}" x2="#{lx + 232}" y2="#{ly + 84}" stroke="#c8ccd2" stroke-width="1"/>)
      s << %(<text x="#{lx}" y="#{ly + 106}" font-size="14" font-weight="600" fill="#{INK}">TILES TO BUY</text>)
      s << %(<text x="#{lx + 232}" y="#{ly + 106}" font-size="18" font-weight="700" text-anchor="end" fill="#{INK}">#{res[:tiles]}</text>)
      s << %(<text x="#{lx}" y="#{ly + 128}" font-size="11" fill="#{MUTED}">) +
           %(#{res[:cut_pieces]} cuts from #{res[:cut_tiles]} tiles &#183; #{res[:paired]} reused</text>)
      cov = InteriorPro::TileGrid.coverage(tw, tl, grout)
      s << %(<text x="#{lx}" y="#{ly + 148}" font-size="11" fill="#{MUTED}">) +
           %(one tile covers #{fmt(cov[0])} x #{fmt(cov[1])} = #{format('%.3f', cov[0] * cov[1] / 144.0)} sq ft</text>)
      s << '</svg>'
      s.join("\n")
    end

    def self.fmt(v)
      f = v.to_f
      f == f.round ? f.round.to_s : format('%g', f)
    end

    # PURE. A file name that is safe on Windows and on the Mac.
    def self.file_name(room_name)
      base = room_name.to_s.strip
      base = 'room' if base.empty?
      base = base.gsub(/[^0-9A-Za-z֐-׿ _-]/, '').gsub(/\s+/, '_')
      "tile_layout_#{base}.svg"
    end

    # PURE. A path on disk as a link a browser will open. Windows gives
    # back backslashes, and a folder like "My Projects" has a space in
    # it - both stop the browser dead if they are not turned first.
    def self.file_url(path)
      s = path.to_s.tr(92.chr, '/')
      'file:///' + s.sub(%r{\A/+}, '').gsub(' ', '%20').gsub('#', '%23')
    end

    # Reads the model, writes one sheet per floor that is laid in a unit.
    # NOTHING is built and nothing is changed. Sheets land next to the
    # .skp file, or in the plugin folder when the model is unsaved.
    def self.write_all!(model = nil, dir = nil)
      model ||= Sketchup.active_model
      dir ||= (model.path.to_s.empty? ? File.dirname(__FILE__) : File.dirname(model.path))
      written = []
      skipped = []
      InteriorPro::TileTakeoff.floors(model).each do |f|
        unless InteriorPro::TileTakeoff.countable?(f)
          skipped << [f[:name], InteriorPro::TileTakeoff.why_not(f)]
          next
        end
        body = svg(f[:name], f[:poly], f[:tw], f[:tl],
                   grout: f[:grout], angle: f[:angle].to_f,
                   ox: f[:ox], oy: f[:oy],
                   centered: f[:centered] ? true : false,
                   stagger: InteriorPro::TileTakeoff.stagger_for(f[:pattern]),
                   area_sqft: f[:area])
        if body.nil?
          skipped << [f[:name], 'the outline has no size']
          next
        end
        path = File.join(dir, file_name(f[:name]))
        File.write(path, body)
        written << path
      end
      written.each { |p| puts "[TileSheet] #{p}" }
      skipped.each { |n, why| puts "[TileSheet] #{n}: #{why}" }
      puts "[TileSheet] #{written.length} sheet(s) in #{dir}"
      written
    rescue StandardError => e
      puts "[TileSheet] #{e.class}: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
      []
    end
  end
end
