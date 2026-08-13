# encoding: utf-8
# plan_pdf.rb - draws a PlanDoc document into a PDF file.
#
# Pure Ruby, no gems, no SketchUp API: the whole thing can be run and looked
# at in the cloud. Writes a plain PDF 1.4 with the three base Helvetica fonts,
# so nothing has to be embedded and the file stays small.
#
# PDF and the drawing document agree on where the origin is: bottom-left of
# the sheet, Y up. One paper inch is 72 points.

require File.join(File.dirname(__FILE__), 'plan_doc') unless
  defined?(InteriorPro::PlanDoc)

module InteriorPro
  module PlanPDF
    PT = 72.0 unless const_defined?(:PT, false)

    # Helvetica cap height as a fraction of the font size. SketchUp's 3D text
    # height is a cap height, so this converts one to the other.
    CAP_RATIO = 0.717 unless const_defined?(:CAP_RATIO, false)

    DEFAULT_WEIGHT = 0.012 unless const_defined?(:DEFAULT_WEIGHT, false) # paper inches

    FONTS = { plain: 'Helvetica', bold: 'Helvetica-Bold',
              italic: 'Helvetica-Oblique' }.freeze unless const_defined?(:FONTS, false)

    # Helvetica advance widths, 1/1000 em, for ASCII 32..126. Used to centre
    # text; without them every label would sit off to one side.
    W = [278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333,
         278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278,
         584, 584, 584, 556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278,
         500, 667, 556, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944,
         667, 667, 611, 278, 278, 278, 469, 556, 333, 556, 556, 500, 556, 556,
         278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500,
         278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584].freeze unless
      const_defined?(:W, false)

    BOLD_BUMP = 1.06 unless const_defined?(:BOLD_BUMP, false)

    def self.text_width(str, size, bold = false)
      total = str.to_s.each_char.inject(0) do |sum, ch|
        c = ch.ord
        sum + ((c >= 32 && c <= 126) ? W[c - 32] : 556)
      end
      w = total / 1000.0 * size
      bold ? w * BOLD_BUMP : w
    end

    # --------------------------------------------------------------- helpers

    def self.esc(str)
      str.to_s.gsub("\\", "\\\\\\\\").gsub('(', '\\(').gsub(')', '\\)')
          .each_char.map { |c| c.ord < 32 || c.ord > 126 ? ' ' : c }.join
    end

    def self.n(v)
      format('%.3f', v.to_f)
    end

    def self.grey(rgb)
      r, g, b = rgb
      "#{n(r / 255.0)} #{n(g / 255.0)} #{n(b / 255.0)}"
    end

    # ---------------------------------------------------------------- stream

    class Stream
      def initialize; @o = []; end
      def <<(s); @o << s; self; end
      def to_s; @o.join("\n"); end

      def save;    self << 'q'; end
      def restore; self << 'Q'; end
    end

    # Draws one page. `to_paper` maps a shape's own units to paper inches.
    def self.draw_shapes(st, shapes, to_paper, scale = 1.0)
      shapes.each do |s|
        case s[:type]
        when :line
          x1, y1 = to_paper.call(s[:x1], s[:y1])
          x2, y2 = to_paper.call(s[:x2], s[:y2])
          st << "#{n((s[:weight] || DEFAULT_WEIGHT) * PT)} w"
          st << "#{n(x1 * PT)} #{n(y1 * PT)} m #{n(x2 * PT)} #{n(y2 * PT)} l S"
        when :polyline, :polygon
          pts = s[:points].map { |p| to_paper.call(p[0], p[1]) }
          next if pts.length < 2
          st << "#{n((s[:weight] || DEFAULT_WEIGHT) * PT)} w"
          st << "#{n(pts[0][0] * PT)} #{n(pts[0][1] * PT)} m"
          pts[1..-1].each { |p| st << "#{n(p[0] * PT)} #{n(p[1] * PT)} l" }
          st << 'h' if s[:closed]
          if s[:fill]
            fill = s[:fill].is_a?(Array) ? s[:fill] : [128, 128, 128]
            st << "#{grey(fill)} rg"
            st << 'f'
            st << '0 0 0 RG'
            st << '0 g'          # back to black, or the next label comes out grey
          else
            st << 'S'
          end
        when :text
          draw_text(st, s, to_paper, scale)
        when :image
          x, y = to_paper.call(s[:x], s[:y])
          w = s[:w] * scale
          h = s[:h] * scale
          st << '0.75 w 0.6 G'
          st << "#{n(x * PT)} #{n(y * PT)} #{n(w * PT)} #{n(h * PT)} re S"
          st << '0 G'
        when :table
          draw_table(st, s, to_paper, scale)
        end
      end
    end

    def self.draw_text(st, s, to_paper, scale)
      str = s[:text].to_s
      return if str.empty?
      x, y = to_paper.call(s[:x], s[:y])
      size = (s[:h].to_f * scale) * PT / CAP_RATIO
      return if size < 0.8   # smaller than this is a smudge on paper
      bold  = s[:bold]
      key   = bold ? :bold : (s[:italic] ? :italic : :plain)
      fnt   = { plain: '/F1', bold: '/F2', italic: '/F3' }[key]
      w     = text_width(str, size, bold)
      cap   = size * CAP_RATIO

      # A shape drawn by plan_generator is centred on its point; one placed on
      # the sheet by hand sits on its baseline at the left.
      align = s[:align] || :left
      dx = align == :center ? -w / 2.0 : 0.0
      dy = align == :center ? -cap / 2.0 : 0.0

      ang = (s[:rotation] || 0.0) * Math::PI / 180.0
      st << 'BT'
      st << '0 g'
      st << "#{fnt} #{n(size)} Tf"
      if ang.abs > 1e-6
        c = Math.cos(ang)
        sn = Math.sin(ang)
        ox = x * PT + (dx * c - dy * sn)
        oy = y * PT + (dx * sn + dy * c)
        st << "#{n(c)} #{n(sn)} #{n(-sn)} #{n(c)} #{n(ox)} #{n(oy)} Tm"
      else
        st << "1 0 0 1 #{n(x * PT + dx)} #{n(y * PT + dy)} Tm"
      end
      st << "#{n(s[:tracking] ? s[:tracking] * scale * PT : 0)} Tc" if s[:tracking]
      st << "(#{esc(str)}) Tj"
      st << '0 Tc' if s[:tracking]
      st << 'ET'
    end

    def self.draw_table(st, s, to_paper, scale)
      headers = s[:headers] || []
      rows    = s[:rows] || []
      cols    = s[:col_widths] || Array.new([headers.length, 1].max) { 1.2 }
      row_h   = (s[:row_h] || 0.22)
      total_w = cols.inject(0.0) { |a, b| a + b }
      lines   = rows.length + 1

      # the grid
      st << "#{n(DEFAULT_WEIGHT * PT)} w"
      (0..lines).each do |i|
        yy = s[:y] - i * row_h
        x1, y1 = to_paper.call(s[:x], yy)
        x2, y2 = to_paper.call(s[:x] + total_w, yy)
        st << "#{n(x1 * PT)} #{n(y1 * PT)} m #{n(x2 * PT)} #{n(y2 * PT)} l S"
      end
      xacc = 0.0
      ([0.0] + cols).each do |cw|
        xacc += cw
        x1, y1 = to_paper.call(s[:x] + xacc, s[:y])
        x2, y2 = to_paper.call(s[:x] + xacc, s[:y] - lines * row_h)
        st << "#{n(x1 * PT)} #{n(y1 * PT)} m #{n(x2 * PT)} #{n(y2 * PT)} l S"
      end

      # the words
      ([headers] + rows).each_with_index do |row, ri|
        xacc = 0.0
        row.each_with_index do |cell, ci|
          draw_text(st,
                    { text: cell, x: s[:x] + xacc + 0.05,
                      y: s[:y] - (ri + 1) * row_h + row_h * 0.3,
                      h: s[:h] || 0.1, align: :left, bold: ri.zero? },
                    to_paper, scale)
          xacc += cols[ci] || 1.2
        end
      end
    end

    # ------------------------------------------------------------ page draw

    def self.page_stream(page, doc)
      st = Stream.new
      st << '0 G'
      st << '0 g'

      # every view window, clipped to its frame
      page.views.each do |v|
        canvas = doc.canvases.find { |c| c.name == v.canvas }
        next unless canvas
        s = v.scale_factor
        to_paper = ->(mx, my) { v.model_to_paper(mx, my) }

        st.save
        st << "#{n(v.x * PT)} #{n(v.y * PT)} #{n(v.w * PT)} #{n(v.h * PT)} re W n"
        canvas.layers.each do |lay|
          next unless lay.visible
          draw_shapes(st, lay.shapes, to_paper, s)
        end
        st.restore

        if v.frame
          st << '0.5 G 0.4 w'
          st << "#{n(v.x * PT)} #{n(v.y * PT)} #{n(v.w * PT)} #{n(v.h * PT)} re S"
          st << '0 G'
        end
      end

      # then whatever is drawn straight on the paper (title block...)
      same = ->(x, y) { [x, y] }
      page.layers.each do |lay|
        next unless lay.visible
        draw_shapes(st, lay.shapes, same, 1.0)
      end

      st.to_s
    end

    # ---------------------------------------------------------------- writer

    def self.export(doc, path, opts = {})
      pages = opts[:pages] || doc.pages
      raise ArgumentError, 'nothing to print' if pages.empty?

      objs = []          # 1-based; objs[i] is object i+1
      add = lambda do |body|
        objs << body
        objs.length
      end

      font_ids = {}
      FONTS.each do |key, name|
        font_ids[key] = add.call("<< /Type /Font /Subtype /Type1 /BaseFont /#{name} /Encoding /WinAnsiEncoding >>")
      end
      res = "<< /Font << /F1 #{font_ids[:plain]} 0 R /F2 #{font_ids[:bold]} 0 R " \
            "/F3 #{font_ids[:italic]} 0 R >> >>"

      pages_id = add.call('PLACEHOLDER')
      page_ids = []
      pages.each do |pg|
        content = page_stream(pg, doc)
        cid = add.call("<< /Length #{content.bytesize} >>\nstream\n#{content}\nendstream")
        pid = add.call("<< /Type /Page /Parent #{pages_id} 0 R /MediaBox " \
                       "[0 0 #{n(pg.width * PT)} #{n(pg.height * PT)}] " \
                       "/Resources #{res} /Contents #{cid} 0 R >>")
        page_ids << pid
      end
      objs[pages_id - 1] = "<< /Type /Pages /Count #{page_ids.length} " \
                           "/Kids [#{page_ids.map { |i| "#{i} 0 R" }.join(' ')}] >>"
      cat_id = add.call("<< /Type /Catalog /Pages #{pages_id} 0 R >>")

      out = +"%PDF-1.4\n%\xE2\xE3\xCF\xD3\n"
      out.force_encoding(Encoding::BINARY)
      offsets = []
      objs.each_with_index do |body, i|
        offsets << out.bytesize
        out << "#{i + 1} 0 obj\n".dup.force_encoding(Encoding::BINARY)
        out << body.dup.force_encoding(Encoding::BINARY)
        out << "\nendobj\n".dup.force_encoding(Encoding::BINARY)
      end
      xref = out.bytesize
      out << "xref\n0 #{objs.length + 1}\n".dup.force_encoding(Encoding::BINARY)
      out << "0000000000 65535 f \n".dup.force_encoding(Encoding::BINARY)
      offsets.each { |o| out << format("%010d 00000 n \n", o).force_encoding(Encoding::BINARY) }
      out << "trailer\n<< /Size #{objs.length + 1} /Root #{cat_id} 0 R >>\n".dup.force_encoding(Encoding::BINARY)
      out << "startxref\n#{xref}\n%%EOF\n".dup.force_encoding(Encoding::BINARY)

      File.open(path, 'wb') { |f| f.write(out) }
      path
    end
  end
end
