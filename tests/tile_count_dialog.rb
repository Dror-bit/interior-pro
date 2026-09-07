# encoding: utf-8
# Interior Pro - HOW MANY TILES, ON SCREEN (2026-09-07)
#
# Why this replaced the file the button used to write, in his words:
#   "אם זה לי זה צריך להיות בקובץ זמין שאני יכול לפתוח וכרגע זה כמו שולח
#    לי את זה כPDF או פותח קובץ בראוזר חדש כל הזמן."
# The quantities are FOR HIM, while he is designing - so they are a
# window he opens when he wants them, showing the model as it is right
# now. No file is written and no browser is opened.
#
# The layout DRAWING is a different thing on a different day: it goes to
# the contractor only after the render, the material and the client's
# approval, and it belongs in the plans - not in this window.
#
# rows/totals/html are PURE - plain numbers in, a table out - so
# tests/rt171.rb pins them. Only show/refresh touch the model, and they
# only READ it.
module InteriorPro
  module TileCountDialog
    TT = InteriorPro::TileTakeoff
    TG = InteriorPro::TileGrid

    # PURE. One line per floor: either the count, or the reason there
    # isn't one. A floor is never given a made-up number.
    def self.rows(floors, pct = InteriorPro::TileCount::MIN_REUSE_PCT)
      Array(floors).map do |f|
        row = { name: f[:name].to_s, area: f[:area].to_f,
                tw: f[:tw].to_f, tl: f[:tl].to_f, grout: f[:grout].to_f,
                pattern: f[:pattern].to_s }
        if TT.countable?(f)
          row[:res] = TT.count_floor(f, pct)
          cov = TG.coverage(f[:tw], f[:tl], f[:grout])
          row[:cov] = cov
          row[:cov_sqft] = cov[0] * cov[1] / 144.0
        else
          row[:why] = TT.why_not(f).to_s
        end
        row
      end
    end

    # PURE. What he actually orders: one line per tile SIZE, because two
    # rooms laid in the same tile are one order. Rooms laid in different
    # sizes are never added together.
    def self.totals(rows)
      out = {}
      Array(rows).each do |r|
        next unless r[:res]
        k = [r[:tw], r[:tl], r[:grout]]
        t = (out[k] ||= { tw: r[:tw], tl: r[:tl], grout: r[:grout],
                          tiles: 0, small: 0, area: 0.0, rooms: 0 })
        t[:tiles] += r[:res][:tiles].to_i
        t[:small] += r[:res][:small_pieces].to_i
        t[:area] += r[:area]
        t[:rooms] += 1
      end
      out.values.sort_by { |t| -t[:tiles] }
    end

    def self.esc(s)
      s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
    end

    def self.num(v)
      f = v.to_f
      f == f.round ? f.round.to_s : format('%g', f)
    end

    # PURE. The window.
    def self.html(rows, totals, pct = InteriorPro::TileCount::MIN_REUSE_PCT)
      body = if rows.empty?
               '<tr><td colspan="7" class="none">No floors in this model.</td></tr>'
             else
               rows.map { |r| row_html(r) }.join
             end
      sums = if totals.empty?
               '<div class="none">Nothing to order yet.</div>'
             else
               totals.map do |t|
                 joint = t[:grout] > 0 ? " &middot; joint #{num(t[:grout])}\"" : ''
                 rooms = t[:rooms] > 1 ? " &middot; #{t[:rooms]} rooms" : ''
                 small = t[:small].positive? ? "<span class=\"sm\">#{t[:small]} of them under #{num(pct)}%</span>" : ''
                 <<~SUM
                   <div class="sum">
                     <div class="sl">#{num(t[:tw])} &times; #{num(t[:tl])}#{joint}#{rooms}
                       <span class="ar">#{format('%.1f', t[:area])} sq ft</span></div>
                     <div class="sr"><b>#{t[:tiles]}</b> tiles #{small}</div>
                   </div>
                 SUM
               end.join
             end

      <<~HTML
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
          body { font: 13px system-ui, Arial; margin: 14px; color: #222; }
          h2 { font-size: 15px; margin: 0 0 2px; }
          .sub { color: #666; margin-bottom: 12px; }
          table { border-collapse: collapse; width: 100%; }
          th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid #eee; }
          th { color: #666; font-weight: 600; font-size: 12px; }
          td.n, th.n { text-align: right; white-space: nowrap;
                       font-variant-numeric: tabular-nums; }
          td.buy { font-weight: 700; }
          .rm { font-weight: 600; }
          .dim { color: #666; }
          .none { color: #a00; }
          .why { color: #a06000; font-style: italic; }
          .sum { display: flex; justify-content: space-between; align-items: baseline;
                 padding: 8px 8px; border-bottom: 1px solid #eee; }
          .sl { color: #222; }
          .sr b { font-size: 17px; }
          .ar { color: #888; margin-left: 8px; }
          .sm { color: #a06000; margin-left: 8px; font-size: 12px; }
          h3 { font-size: 13px; margin: 18px 0 4px; color: #444; }
          .bar { margin-top: 16px; display: flex; gap: 10px; align-items: center; }
          button { padding: 7px 16px; }
          .note { color: #777; font-size: 12px; }
        </style></head><body>
          <h2>Tiles to order</h2>
          <div class="sub">The model as it is right now. Nothing is saved and nothing is drawn.</div>
          <table>
            <tr><th>room</th><th class="n">area</th><th>tile</th><th class="n">whole</th>
                <th class="n">cut</th><th class="n">under #{num(pct)}%</th><th class="n">to buy</th></tr>
            #{body}
          </table>
          <h3>Order</h3>
          #{sums}
          <div class="bar">
            <button onclick="sketchup.refresh('')">Refresh</button>
            <span class="note">a tile cut in two, both halves used, is one tile bought</span>
          </div>
        </body></html>
      HTML
    end

    def self.row_html(r)
      if r[:why]
        return "<tr><td class=\"rm\">#{esc(r[:name])}</td>" \
               "<td class=\"n\">#{format('%.1f', r[:area])}</td>" \
               "<td class=\"why\" colspan=\"5\">#{esc(r[:why])}</td></tr>"
      end
      res = r[:res]
      "<tr><td class=\"rm\">#{esc(r[:name])}</td>" \
        "<td class=\"n\">#{format('%.1f', r[:area])}</td>" \
        "<td class=\"dim\">#{num(r[:tw])} &times; #{num(r[:tl])}" \
        "#{r[:grout] > 0 ? " + #{num(r[:grout])}\"" : ''}</td>" \
        "<td class=\"n\">#{res[:full]}</td>" \
        "<td class=\"n\">#{res[:cut_pieces]}</td>" \
        "<td class=\"n\">#{res[:small_pieces]}</td>" \
        "<td class=\"n buy\">#{res[:tiles]}</td></tr>"
    end

    # Reads the model. Builds nothing, changes nothing, saves nothing.
    def self.page(model = nil)
      model ||= Sketchup.active_model
      rs = rows(TT.floors(model))
      html(rs, totals(rs))
    end

    def self.show
      @dlg = UI::HtmlDialog.new(dialog_title: 'Interior Pro - Tiles',
                                preferences_key: 'InteriorProTiles',
                                width: 760, height: 520, resizable: true)
      @dlg.set_html(page)
      @dlg.add_action_callback('refresh') { |_c, _x| @dlg.set_html(page) }
      @dlg.show
      @dlg
    rescue StandardError => e
      puts "[Tiles] show: #{e.class}: #{e.message}"
      nil
    end
  end
end
