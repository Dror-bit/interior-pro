# encoding: utf-8
# plan_pdf.rb - draws a PlanDoc document into a PDF file.
#
# Pure Ruby, no gems, no SketchUp API: the whole thing can be run and looked
# at in the cloud. Writes a plain PDF 1.4 with the three base Helvetica fonts,
# so nothing has to be embedded and the file stays small.
#
# PDF and the drawing document agree on where the origin is: bottom-left of
# the sheet, Y up. One paper inch is 72 points.
#
# Real pictures (2026-08-14): a JPEG goes into the file exactly as it lies on
# disk - PDF speaks JPEG natively, so a render stays a render. A PNG is
# unpacked far enough to hand the pixels over, and its see-through parts
# become a separate grey mask.

require 'zlib'

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

    # ---------------------------------------------------------------- images
    #
    # A picture reaches the PDF as an XObject: a little stream of pixels with a
    # name, painted by scaling a 1x1 square onto the page. Everything below
    # turns a file on disk into that stream, or gives back nil and lets the
    # caller draw the old empty frame instead of blowing up an export.

    # Refuse anything silly before allocating room for it.
    MAX_PIXELS = 40_000_000 unless const_defined?(:MAX_PIXELS, false)

    JPEG_SOF = [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF].freeze unless
      const_defined?(:JPEG_SOF, false)

    PNG_MAGIC = "\x89PNG\r\n\x1A\n".b.freeze unless const_defined?(:PNG_MAGIC, false)

    def self.image_cache
      @image_cache ||= {}
    end

    def self.forget_images!
      @image_cache = {}
    end

    # nil, or:
    #   { w:, h:, bpc:, cs:, filter:, data:, parms:, extra:, smask: {w:,h:,data:} }
    def self.load_image(path)
      p = path.to_s
      return nil if p.empty?
      return image_cache[p] if image_cache.key?(p)
      info =
        begin
          raw = File.open(p, 'rb') { |f| f.read }
          raw = raw.b
          if raw.byteslice(0, 2) == "\xFF\xD8".b
            jpeg_info(raw)
          elsif raw.byteslice(0, 8) == PNG_MAGIC
            png_info(raw)
          end
        rescue StandardError => e
          puts "[PlanPDF] cannot read image #{p}: #{e.message}"
          nil
        end
      image_cache[p] = info
    end

    # ----------------------------------------------------------------- JPEG
    # Nothing is decoded. We only walk the markers far enough to learn how big
    # the picture is and how many colours it carries, then hand the bytes over.
    def self.jpeg_info(raw)
      len = raw.bytesize
      i = 2
      while i < len - 3
        if raw.getbyte(i) != 0xFF
          i += 1
          next
        end
        m = raw.getbyte(i + 1)
        if m == 0xFF || m == 0xD8 || m == 0xD9 || m == 0x01 ||
           (m >= 0xD0 && m <= 0xD7)
          i += (m == 0xFF ? 1 : 2)
          next
        end
        break if m == 0xDA                       # the pixels start here
        seg = (raw.getbyte(i + 2) << 8) | raw.getbyte(i + 3)
        break if seg < 2
        if JPEG_SOF.include?(m)
          bpc   = raw.getbyte(i + 4)
          h     = (raw.getbyte(i + 5) << 8) | raw.getbyte(i + 6)
          w     = (raw.getbyte(i + 7) << 8) | raw.getbyte(i + 8)
          ncomp = raw.getbyte(i + 9)
          cs = { 1 => '/DeviceGray', 3 => '/DeviceRGB', 4 => '/DeviceCMYK' }[ncomp]
          return nil unless cs && w.to_i > 0 && h.to_i > 0
          return nil if w * h > MAX_PIXELS
          # Photoshop writes CMYK JPEGs upside down; the Adobe marker says so.
          inv = (ncomp == 4 && raw.include?('Adobe'.b))
          return { w: w, h: h, bpc: bpc, cs: cs, filter: '/DCTDecode',
                   data: raw,
                   extra: inv ? '/Decode [1 0 1 0 1 0 1 0]' : nil }
        end
        i += 2 + seg
      end
      nil
    end

    # ------------------------------------------------------------------ PNG
    def self.png_chunks(raw)
      out = { idat: +''.b }
      i = 8
      len = raw.bytesize
      while i + 8 <= len
        n    = raw.byteslice(i, 4).unpack1('N').to_i
        kind = raw.byteslice(i + 4, 4)
        body = raw.byteslice(i + 8, n).to_s
        case kind
        when 'IHDR'.b then out[:ihdr] = body
        when 'PLTE'.b then out[:plte] = body
        when 'tRNS'.b then out[:trns] = body
        when 'IDAT'.b then out[:idat] << body
        when 'IEND'.b then break
        end
        i += 12 + n                              # length + type + body + crc
      end
      out
    end

    def self.png_info(raw)
      ch = png_chunks(raw)
      return nil unless ch[:ihdr] && ch[:ihdr].bytesize >= 13
      w, h = ch[:ihdr].byteslice(0, 8).unpack('N2')
      bd   = ch[:ihdr].getbyte(8)
      ct   = ch[:ihdr].getbyte(9)
      inter = ch[:ihdr].getbyte(12)
      return nil if w.to_i <= 0 || h.to_i <= 0 || w * h > MAX_PIXELS
      if inter != 0
        puts '[PlanPDF] interlaced PNG is not supported - save it again without interlacing'
        return nil
      end
      return nil if ch[:idat].empty?

      # No see-through part: the compressed rows go straight in, predictor and
      # all. Nothing is unpacked, so even a huge screenshot costs nothing.
      plain = (ct == 0 || ct == 2 || (ct == 3 && ch[:trns].nil?))
      if plain
        colors = ct == 2 ? 3 : 1
        cs =
          if ct == 3
            return nil unless ch[:plte]
            "[/Indexed /DeviceRGB #{(ch[:plte].bytesize / 3) - 1} <#{ch[:plte].unpack1('H*')}>]"
          else
            ct == 2 ? '/DeviceRGB' : '/DeviceGray'
          end
        return { w: w, h: h, bpc: bd, cs: cs, filter: '/FlateDecode',
                 data: ch[:idat],
                 parms: "<< /Predictor 15 /Colors #{colors} " \
                        "/BitsPerComponent #{bd} /Columns #{w} >>" }
      end

      # There IS a see-through part, so the rows have to be unpacked.
      return nil unless bd == 8
      png_with_alpha(ch, w, h, ct)
    end

    def self.png_with_alpha(ch, w, h, ct)
      chan = { 0 => 1, 2 => 3, 3 => 1, 4 => 2, 6 => 4 }[ct]
      return nil unless chan
      flat = png_unfilter(Zlib::Inflate.inflate(ch[:idat]), w, h, chan)
      return nil unless flat

      if ct == 3                                  # palette + a tRNS table
        table = ch[:trns].bytes
        alpha = flat.bytes.map { |ix| table[ix] || 255 }.pack('C*')
        cs = "[/Indexed /DeviceRGB #{(ch[:plte].bytesize / 3) - 1} " \
             "<#{ch[:plte].unpack1('H*')}>]"
        return { w: w, h: h, bpc: 8, cs: cs, filter: '/FlateDecode',
                 data: Zlib::Deflate.deflate(flat),
                 smask: { w: w, h: h, data: Zlib::Deflate.deflate(alpha) } }
      end

      keep  = ct == 6 ? 3 : 1                     # colour bytes per pixel
      color = +''.b
      alpha = +''.b
      fmt   = "a#{keep}a1" * w
      h.times do |r|
        parts = flat.byteslice(r * w * chan, w * chan).unpack(fmt)
        j = 0
        while j < parts.length
          color << parts[j]
          alpha << parts[j + 1]
          j += 2
        end
      end
      { w: w, h: h, bpc: 8, cs: ct == 6 ? '/DeviceRGB' : '/DeviceGray',
        filter: '/FlateDecode', data: Zlib::Deflate.deflate(color),
        smask: { w: w, h: h, data: Zlib::Deflate.deflate(alpha) } }
    end

    # Undo the per-row filter PNG applies before compressing. Returns the bare
    # pixels, rows one after another, with the filter bytes gone.
    def self.png_unfilter(data, w, h, bpp)
      stride = w * bpp
      return nil if data.bytesize < (stride + 1) * h
      out  = +''.b
      prev = "\x00".b * stride
      pos  = 0
      h.times do
        ft  = data.getbyte(pos)
        row = data.byteslice(pos + 1, stride).bytes
        pv  = prev.bytes
        pos += stride + 1
        case ft
        when 0 then nil
        when 1
          i = bpp
          while i < stride
            row[i] = (row[i] + row[i - bpp]) & 0xFF
            i += 1
          end
        when 2
          i = 0
          while i < stride
            row[i] = (row[i] + pv[i]) & 0xFF
            i += 1
          end
        when 3
          i = 0
          while i < stride
            a = i >= bpp ? row[i - bpp] : 0
            row[i] = (row[i] + ((a + pv[i]) >> 1)) & 0xFF
            i += 1
          end
        when 4
          i = 0
          while i < stride
            a = i >= bpp ? row[i - bpp] : 0
            b = pv[i]
            c = i >= bpp ? pv[i - bpp] : 0
            p  = a + b - c
            pa = (p - a).abs
            pb = (p - b).abs
            pc = (p - c).abs
            pr = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)
            row[i] = (row[i] + pr) & 0xFF
            i += 1
          end
        else
          return nil
        end
        prev = row.pack('C*')
        out << prev
      end
      out
    end

    # Every picture used on ONE page, each with the name the page calls it by.
    class ImageSet
      attr_reader :entries

      def initialize
        @by_path = {}
        @entries = []
      end

      def name_for(path)
        key = path.to_s
        return @by_path[key] if @by_path.key?(key)
        info = PlanPDF.load_image(key)
        if info
          nm = "Im#{@entries.length + 1}"
          @entries << { name: nm, info: info }
          @by_path[key] = nm
        else
          @by_path[key] = nil
        end
        @by_path[key]
      end

      def info_for(name)
        e = @entries.find { |x| x[:name] == name }
        e && e[:info]
      end

      def empty?
        @entries.empty?
      end
    end

    # A photo is not the shape of its box. Keep its proportions and sit it in
    # the middle, unless the shape asks to be stretched.
    def self.fit_box(iw, ih, x, y, w, h, stretch)
      return [x, y, w, h] if stretch || iw.to_f <= 0 || ih.to_f <= 0 ||
                             w.to_f <= 0 || h.to_f <= 0
      ar_img = iw.to_f / ih.to_f
      ar_box = w.to_f / h.to_f
      if ar_img > ar_box
        dw = w.to_f
        dh = w.to_f / ar_img
      else
        dh = h.to_f
        dw = h.to_f * ar_img
      end
      [x + (w - dw) / 2.0, y + (h - dh) / 2.0, dw, dh]
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
    def self.draw_shapes(st, shapes, to_paper, scale = 1.0, imgs = nil)
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
          draw_image(st, s, to_paper, scale, imgs)
        when :table
          draw_table(st, s, to_paper, scale)
        end
      end
    end

    # The picture itself if the file could be read; the old empty frame if it
    # could not, so a missing render never loses the whole sheet.
    def self.draw_image(st, s, to_paper, scale, imgs)
      x, y = to_paper.call(s[:x], s[:y])
      w = s[:w].to_f * scale
      h = s[:h].to_f * scale
      nm = imgs && imgs.name_for(s[:path])
      info = nm && imgs.info_for(nm)

      unless nm && info
        st << '0.75 w 0.6 G'
        st << "#{n(x * PT)} #{n(y * PT)} #{n(w * PT)} #{n(h * PT)} re S"
        st << '0 G'
        return
      end

      dx, dy, dw, dh = fit_box(info[:w], info[:h], x, y, w, h, s[:stretch])
      st.save
      st << "#{n(dw * PT)} 0 0 #{n(dh * PT)} #{n(dx * PT)} #{n(dy * PT)} cm"
      st << "/#{nm} Do"
      st.restore
      return unless s[:frame]
      st << '0.75 w 0.6 G'
      st << "#{n(dx * PT)} #{n(dy * PT)} #{n(dw * PT)} #{n(dh * PT)} re S"
      st << '0 G'
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

    def self.page_stream(page, doc, imgs = nil)
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
          draw_shapes(st, lay.shapes, to_paper, s, imgs)
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
        draw_shapes(st, lay.shapes, same, 1.0, imgs)
      end

      st.to_s
    end

    # ---------------------------------------------------------------- writer

    # One picture as a PDF object. The bytes are binary, so the body is built
    # as binary from the start - a UTF-8 string would corrupt a JPEG.
    def self.image_object(info)
      data = info[:data].to_s.b
      head = +"<< /Type /XObject /Subtype /Image /Width #{info[:w]} " \
              "/Height #{info[:h]} /ColorSpace #{info[:cs]} " \
              "/BitsPerComponent #{info[:bpc]} /Filter #{info[:filter]}"
      head << " /DecodeParms #{info[:parms]}" if info[:parms]
      head << " #{info[:extra]}" if info[:extra]
      head << " /SMask #{info[:smask_ref]} 0 R" if info[:smask_ref]
      head << " /Length #{data.bytesize} >>\nstream\n"
      out = head.b
      out << data
      out << "\nendstream".b
      out
    end

    # Slip an /XObject entry into the shared resource dictionary.
    def self.resources_with(res, xobj)
      res.sub(/\s*>>\s*\z/, " /XObject << #{xobj.join(' ')} >> >>")
    end

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
        imgs    = ImageSet.new
        content = page_stream(pg, doc, imgs)
        cid = add.call("<< /Length #{content.bytesize} >>\nstream\n#{content}\nendstream")

        # Each picture becomes its own object, and its see-through mask another.
        xobj = imgs.entries.map do |e|
          info = e[:info]
          mask_ref = nil
          if info[:smask]
            sm = info[:smask]
            mask_ref = add.call(image_object(w: sm[:w], h: sm[:h], bpc: 8,
                                             cs: '/DeviceGray',
                                             filter: '/FlateDecode',
                                             data: sm[:data]))
          end
          id = add.call(image_object(info.merge(smask_ref: mask_ref)))
          "/#{e[:name]} #{id} 0 R"
        end
        page_res = xobj.empty? ? res : resources_with(res, xobj)

        pid = add.call("<< /Type /Page /Parent #{pages_id} 0 R /MediaBox " \
                       "[0 0 #{n(pg.width * PT)} #{n(pg.height * PT)}] " \
                       "/Resources #{page_res} /Contents #{cid} 0 R >>")
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
