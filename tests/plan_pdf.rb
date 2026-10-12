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

    # font: the lettering he picked (a family name, see shipped_fonts), or nil. A
    # run with letters Helvetica has not got (Hebrew, for one) is measured in
    # the font it will be printed in - the same table the window is given
    # (text_rules['fonts']), so the two break lines at the same places.
    def self.text_width(str, size, bold = false, font = nil)
      tab = USE_TTF_FONTS ? width_table_for(str, font) : nil
      total = str.to_s.each_char.inject(0) do |sum, ch|
        c = ch.ord
        sum + (tab ? (tab[:w][c] || tab[:dw]) : ((c >= 32 && c <= 126) ? W[c - 32] : 556))
      end
      w = total / 1000.0 * size
      bold ? w * BOLD_BUMP : w
    end

    # ------------------------------------------- TrueType fonts (2026-10-07)
    #
    # The three Helvetica fonts are built into every PDF reader, but they know
    # no Hebrew, and he wants a choice of lettering ("בהגדרות טקסט צריך לתת
    # סוגים שונים של פונטים, כמו בלייאאוט"). So a piece of writing in a
    # lettering he picked, or with letters Helvetica has not got, is set in a
    # TrueType font read from the computer's own fonts and written INTO the
    # PDF: a Type0 / CIDFontType2 font, glyph ids (Identity-H), the whole
    # font file deflated, a ToUnicode map so the words can still be searched
    # and copied. Hebrew is laid right to left the way the browser lays it
    # (visual). Nothing else changes: Latin writing in no particular
    # lettering is Helvetica, as it always was, and the file stays small.
    # false = the three Helveticas only, letters they lack print as spaces.
    USE_TTF_FONTS = true unless const_defined?(:USE_TTF_FONTS, false)

    # The letterings on offer ship WITH THE PLUGIN: assets/FONTS/*.ttf, free
    # fonts with their licences beside them (2026-10-08). He said "אני לא באמת
    # צריך יותר מ-3 או 4 פונטים" and picked Architects Daughter, Shadows Into
    # Light, David Libre and Suez One, beside the plain lettering. A family is
    # named by the font itself (its name table) and its faces by their
    # subfamily (Regular / Bold / Italic / Bold Italic); a face that is
    # missing falls back to the plain one. The same files are handed to the
    # window as @font-face, so the sheet and the PDF draw the very same letters
    # on both of his computers, whatever is installed on them.
    def self.font_dir
      @font_dir || File.join(plugin_root, 'assets', 'FONTS')
    end

    # (the tests point this at a folder of their own)
    def self.font_dir=(d)
      @font_dir = d
      forget_fonts!
    end

    def self.plugin_root
      defined?(InteriorPro::PLUGIN_DIR) ? InteriorPro::PLUGIN_DIR.to_s.tr('\\', '/') : File.dirname(File.expand_path(__FILE__))
    end

    # { family => { plain: path, bold: path, italic: path, bold_italic: path } },
    # the families in alphabetical order.
    def self.shipped_fonts
      @shipped ||= begin
        out = {}
        Dir.glob(File.join(font_dir, '*.{ttf,TTF}')).sort.each do |path|
          t = ttf(path)
          next unless t
          fam = t.family.to_s.strip
          next if fam.empty?
          out[fam] ||= {}
          out[fam][t.face] ||= path
        end
        out.sort.to_h
      end
    end

    def self.families_present
      shipped_fonts.keys
    end

    # The file of one face of a family, or nil for a family that is not there.
    def self.font_file(family, bold = false, italic = false)
      faces = shipped_fonts[family.to_s]
      return nil unless faces
      order = []
      order << :bold_italic if bold && italic
      order << :bold if bold
      order << :italic if italic
      order << :plain
      order.each { |k| return faces[k] if faces[k] }
      faces.values.first
    end

    def self.forget_fonts!
      @shipped = nil
      @ttf_cache = nil
      @width_tables = nil
    end

    # The family Hebrew is set in when he picked none: the first that has it.
    def self.hebrew_family
      families_present.find { |f| (t = ttf(font_file(f))) && t.has?(0x5D0) }
    end

    # The letters the window and this file measure by the same table. Any
    # other letter is counted at the font's own default width.
    TABLE_CODES = ((32..126).to_a + (0x00A0..0x00FF).to_a + (0x05D0..0x05F4).to_a +
                   [0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2026, 0x20AC]).freeze unless const_defined?(:TABLE_CODES, false)

    HEB = /[֐-׿יִ-ﭏ]/ unless const_defined?(:HEB, false)

    # Does this run need a TrueType font: letters Helvetica has not got?
    def self.needs_ttf?(str)
      str.to_s.each_char.any? { |ch| ch.ord > 126 }
    end

    # Which family this run is set in: the one he picked if it is on offer,
    # else the Hebrew one when the run needs it, else nil = Helvetica.
    def self.family_for(str, font)
      return nil unless USE_TTF_FONTS
      f = font.to_s
      return f if !f.empty? && families_present.include?(f)
      needs_ttf?(str) ? hebrew_family : nil
    end

    def self.ttf(path)
      @ttf_cache ||= {}
      key = path.to_s
      mt = (File.mtime(key).to_f rescue 0)
      c = @ttf_cache[key]
      return c[1] if c && c[0] == mt
      t = TrueType.new(key)
      @ttf_cache[key] = [mt, t]
      t
    rescue StandardError => e
      puts "[PlanPDF] cannot read font #{path}: #{e.message}"
      nil
    end

    def self.ttf_for(str, font, bold = false, italic = false)
      fam = family_for(str, font)
      return nil unless fam
      path = font_file(fam, bold, italic)
      path && ttf(path)
    end

    # The width table of a family's plain face: { w: {code => 1/1000 em},
    # dw: the default }. THE TABLE THE WINDOW IS GIVEN (text_rules['fonts']).
    def self.width_table(family)
      @width_tables ||= {}
      return @width_tables[family] if @width_tables.key?(family)
      path = font_file(family)
      t = path && ttf(path)
      @width_tables[family] = t && begin
        w = {}
        TABLE_CODES.each { |c| w[c] = t.width_of(c).round if t.has?(c) }
        { w: w, dw: t.advance(0).round }
      end
    end

    def self.width_table_for(str, font)
      fam = family_for(str, font)
      fam && width_table(fam)
    end

    # The tables for the window, one a family on offer, and which family
    # Hebrew is set in: { 'Arial' => { 'w' => {...}, 'dw' => 750 }, ... }.
    def self.font_tables
      return {} unless USE_TTF_FONTS
      out = {}
      families_present.each do |f|
        t = width_table(f)
        next unless t
        out[f] = { 'w' => t[:w], 'dw' => t[:dw], 'path' => font_file(f) }
        b = font_file(f, true)
        out[f]['pathb'] = b if b && b != out[f]['path']
        out[f]['heb'] = true if (ft = ttf(out[f]['path'])) && ft.has?(0x5D0)
      end
      out
    end

    # The letters of one run in the order they are PRINTED, left to right -
    # the way the browser lays the same run in a page that reads left to
    # right (measured against Chromium, 21 runs: tests/browser/bidi.js). The
    # Unicode bidi rules, the few that matter here:
    #   a Hebrew stretch reads right to left; a number inside it keeps its
    #   own order (and its own separators: 2026-10-07, 12/3, 3.5); a number
    #   after Latin letters reads as Latin; spaces and marks between two
    #   sides of one direction take it, otherwise the paragraph's; a pair of
    #   brackets takes the direction of what is inside it; brackets turned
    #   round are mirrored.
    def self.visual(str)
      s = str.to_s
      return s unless s =~ HEB
      ch = s.chars
      t = ch.map { |c| c =~ HEB ? :R : (c =~ /[A-Za-zÀ-ɏ]/ ? :L : (c =~ /[0-9]/ ? :E : :N)) }
      # a separator between two digits is part of the number (W4)
      (1...(t.length - 1)).each { |i| t[i] = :E if t[i] == :N && ch[i] =~ %r{[-/:.,]} && t[i - 1] == :E && t[i + 1] == :E }
      # a number after Latin letters reads as Latin (W7)
      strong = :L
      t.each_with_index do |k, i|
        if k == :R || k == :L
          strong = k
        elsif k == :E && strong == :L
          t[i] = :L
        end
      end
      dir_of = ->(k) { (k == :L || k == :l) ? :L : :R }
      # a pair of brackets: the paragraph's direction if Latin is inside; Hebrew
      # inside and Hebrew before it -> right to left; else the paragraph's (N0)
      pairs = { '(' => ')', '[' => ']', '{' => '}' }
      stack = []
      ch.each_with_index do |c, i|
        if pairs.key?(c)
          stack << [c, i]
        elsif pairs.value?(c)
          k = stack.rindex { |o| pairs[o[0]] == c }
          next unless k
          o = stack[k][1]
          stack = stack[0...k]
          has_l = ((o + 1)...i).any? { |m| t[m] == :L }
          has_r = ((o + 1)...i).any? { |m| t[m] == :R || t[m] == :E }
          before = :L
          (o - 1).downto(0) do |m|
            if t[m] == :L || t[m] == :R
              before = t[m]
              break
            end
          end
          d = has_l ? :L : ((has_r && before == :R) ? :R : :L)
          t[o] = t[i] = (d == :L ? :l : :r)
        end
      end
      # the rest of the marks and spaces: between two sides of one direction
      # they take it (a number counts as Hebrew here), otherwise the paragraph's (N1, N2)
      i = 0
      while i < t.length
        if t[i] == :N
          j = i
          j += 1 while j < t.length && t[j] == :N
          left  = i > 0 ? dir_of.call(t[i - 1]) : :L
          right = j < t.length ? dir_of.call(t[j]) : :L
          d = left == right ? left : :L
          (i...j).each { |k| t[k] = (d == :L ? :l : :r) }
          i = j
        else
          i += 1
        end
      end
      lv  = t.map { |k| (k == :L || k == :l) ? 0 : (k == :E ? 2 : 1) }
      out = ch.dup
      # from the deepest level up, every stretch at that level or deeper is turned round (L2)
      [2, 1].each do |level|
        i = 0
        while i < out.length
          if lv[i] >= level
            j = i
            j += 1 while j < out.length && lv[j] >= level
            out[i...j] = out[i...j].reverse
            lv[i...j]  = lv[i...j].reverse
            i = j
          else
            i += 1
          end
        end
      end
      mirror = { '(' => ')', ')' => '(', '[' => ']', ']' => '[', '{' => '}', '}' => '{', '<' => '>', '>' => '<' }
      out.each_with_index.map { |c, i| (lv[i].odd? && mirror[c]) ? mirror[c] : c }.join
    end

    # One TrueType font file, read far enough to print with: the glyph of
    # each letter (cmap, format 4), how wide each glyph is (hmtx), and what the
    # font descriptor wants to know. Pure Ruby, no gems.
    class TrueType
      attr_reader :path, :data, :units, :ascent, :descent, :bbox, :cap_height, :italic_angle, :ps_name, :nglyphs, :family, :subfamily

      def initialize(path)
        @path = path
        @data = File.binread(path)
        raise 'not a TrueType font' if @data.bytesize < 12 || @data[0, 4] == 'ttcf'
        @tables = {}
        u16(4).times do |i|
          tag = @data[12 + i * 16, 4]
          @tables[tag] = [u32(12 + i * 16 + 8), u32(12 + i * 16 + 12)]
        end
        head = tbl('head')
        hhea = tbl('hhea')
        maxp = tbl('maxp')
        raise 'not a TrueType font' unless head && hhea && maxp && tbl('cmap') && tbl('hmtx') && tbl('glyf')
        @units = u16(head + 18)
        @units = 1000 if @units.zero?
        @bbox = [s16(head + 36), s16(head + 38), s16(head + 40), s16(head + 42)].map { |v| em(v) }
        @ascent  = em(s16(hhea + 4))
        @descent = em(s16(hhea + 6))
        nhm = u16(hhea + 34)
        @nglyphs = u16(maxp + 4)
        hm = tbl('hmtx')
        @adv = Array.new(nhm) { |g| u16(hm + g * 4) }
        os2 = tbl('OS/2')
        @cap_height = (os2 && u16(os2) >= 2) ? em(s16(os2 + 88)) : 0
        @cap_height = (@ascent * 0.8).round if @cap_height <= 0
        post = tbl('post')
        @italic_angle = post ? (s16(post + 4) + u16(post + 6) / 65536.0) : 0.0
        @ps_name = read_ps_name || File.basename(path, '.*').gsub(/[^A-Za-z0-9\-]/, '')
        @family    = read_name(1) || File.basename(path, '.*')
        @subfamily = read_name(2) || 'Regular'
        @ps_name = 'Font' if @ps_name.empty?
        @cmap = read_cmap
      end

      def em(v); (v * 1000.0 / @units).round; end
      def tbl(tag); t = @tables[tag]; t && t[0]; end
      def u16(o); @data[o, 2].unpack1('n'); end
      def s16(o); v = u16(o); v >= 0x8000 ? v - 0x10000 : v; end
      def u32(o); @data[o, 4].unpack1('N'); end

      def gid(code); @cmap[code] || 0; end
      def has?(code); @cmap.key?(code); end
      # how wide a glyph is, per 1000 em
      def advance(g)
        a = @adv[g] || @adv.last || 0
        a * 1000.0 / @units
      end
      def width_of(code); advance(gid(code)); end

      # letter -> glyph, from the first format 4 subtable (the (3,1) one if there is one)
      def read_cmap
        base = tbl('cmap')
        map = {}
        best = nil
        u16(base + 2).times do |i|
          pid = u16(base + 4 + i * 8)
          eid = u16(base + 6 + i * 8)
          sub = base + u32(base + 8 + i * 8)
          next unless u16(sub) == 4
          best = sub if best.nil? || (pid == 3 && eid == 1)
        end
        return map unless best
        segx2 = u16(best + 6)
        ends = best + 14
        starts = ends + segx2 + 2
        deltas = starts + segx2
        ranges = deltas + segx2
        (segx2 / 2).times do |i|
          e = u16(ends + i * 2)
          st = u16(starts + i * 2)
          d = u16(deltas + i * 2)
          ro = u16(ranges + i * 2)
          next if st == 0xFFFF
          (st..e).each do |c|
            if ro.zero?
              g = (c + d) & 0xFFFF
            else
              gi = ranges + i * 2 + ro + (c - st) * 2
              g = u16(gi)
              g = (g + d) & 0xFFFF unless g.zero?
            end
            map[c] = g unless g.zero?
          end
        end
        map
      end

      # which face this file is, from its subfamily name
      def face
        s = @subfamily.to_s
        b = s =~ /bold/i
        i = s =~ /italic|oblique/i
        b && i ? :bold_italic : (b ? :bold : (i ? :italic : :plain))
      end

      def read_ps_name
        read_name(6)
      end

      # a string of the name table (1 = family, 2 = subfamily, 6 = PostScript
      # name): the Windows English one if there is one, else the first
      def read_name(id)
        nm = tbl('name')
        return nil unless nm
        count = u16(nm + 2)
        str = nm + u16(nm + 4)
        best = nil
        count.times do |i|
          r = nm + 6 + i * 12
          next unless u16(r + 6) == id
          pid = u16(r)
          lang = u16(r + 4)
          raw = @data[str + u16(r + 10), u16(r + 8)].to_s
          txt = (pid == 3 || pid == 0) ? raw.dup.force_encoding('UTF-16BE').encode('UTF-8', invalid: :replace, undef: :replace) :
                                         raw.dup.force_encoding('ASCII-8BIT').encode('UTF-8', invalid: :replace, undef: :replace)
          txt = id == 6 ? txt.gsub(/[^A-Za-z0-9\-]/, '') : txt.strip
          next if txt.empty?
          return txt if pid == 3 && lang == 0x409
          best ||= txt
        end
        best
      rescue StandardError
        nil
      end
    end

    # The TrueType fonts one PDF uses: each gets a name (/F4 on) and remembers
    # which glyphs it set, for the widths and the ToUnicode map.
    class FontSet
      attr_reader :entries

      def initialize
        @by = {}
        @entries = []
      end

      def use(ttf)
        e = @by[ttf.path]
        unless e
          e = { name: "F#{@entries.length + 4}", ttf: ttf, used: {} }
          @entries << e
          @by[ttf.path] = e
        end
        e
      end
    end

    # The font set of the export under way, or nil when nothing is being exported.
    def self.font_set
      @font_set
    end

    def self.to_unicode_stream(used)
      body = +"/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n" \
             "/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n" \
             "/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n" \
             "1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n"
      used.keys.sort.each_slice(100) do |gs|
        body << "#{gs.length} beginbfchar\n"
        gs.each do |g|
          cp = used[g]
          u = cp > 0xFFFF ? '003F' : format('%04X', cp)
          body << "<#{format('%04X', g)}> <#{u}>\n"
        end
        body << "endbfchar\n"
      end
      body << "endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n"
      "<< /Length #{body.bytesize} >>\nstream\n#{body}\nendstream"
    end

    # The PDF objects of one embedded font; returns the id of the Type0 font.
    def self.font_objects(e, add)
      t = e[:ttf]
      raw = t.data
      comp = Zlib::Deflate.deflate(raw)
      ff = add.call("<< /Length #{comp.bytesize} /Length1 #{raw.bytesize} /Filter /FlateDecode >>\nstream\n#{comp}\nendstream")
      flags = 32 | (t.italic_angle.abs > 1e-6 ? 64 : 0)
      fd = add.call("<< /Type /FontDescriptor /FontName /#{t.ps_name} /Flags #{flags} " \
                    "/FontBBox [#{t.bbox.join(' ')}] /ItalicAngle #{n(t.italic_angle)} /Ascent #{t.ascent} " \
                    "/Descent #{t.descent} /CapHeight #{t.cap_height} /StemV 80 /FontFile2 #{ff} 0 R >>")
      w = e[:used].keys.sort.map { |g| "#{g} [#{n(t.advance(g))}]" }.join(' ')
      cid = add.call("<< /Type /Font /Subtype /CIDFontType2 /BaseFont /#{t.ps_name} " \
                     "/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> " \
                     "/FontDescriptor #{fd} 0 R /DW 1000 /W [#{w}] /CIDToGIDMap /Identity >>")
      tu = add.call(to_unicode_stream(e[:used]))
      add.call("<< /Type /Font /Subtype /Type0 /BaseFont /#{t.ps_name} /Encoding /Identity-H " \
               "/DescendantFonts [#{cid} 0 R] /ToUnicode #{tu} 0 R >>")
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
      @size_cache  = {}
    end

    # How many pixels across and down a picture is: [w, h], or nil if the file
    # cannot be read as a JPEG or a PNG (2026-10-07).
    #
    # A picture in a box of its own is laid out from its PROPORTIONS, and the
    # sheet is laid out again on every click in the window - so this must not
    # read an 8 MB render each time, nor unpack a see-through PNG to learn two
    # numbers. Only the head of the file is read (a JPEG's size can sit behind
    # a long EXIF block, so the read grows until it is found), and the answer
    # is remembered until the file changes.
    def self.image_size(path)
      p = path.to_s
      return nil if p.empty? || !File.file?(p)
      @size_cache ||= {}
      stamp = [File.size(p), File.mtime(p).to_f]
      hit = @size_cache[p]
      return hit[1] if hit && hit[0] == stamp
      size = nil
      File.open(p, 'rb') do |f|
        head = f.read(65_536).to_s.b
        if head.byteslice(0, 8) == PNG_MAGIC
          w, h = head.byteslice(16, 8).to_s.unpack('N2')
          size = [w, h] if w.to_i > 0 && h.to_i > 0
        elsif head.byteslice(0, 2) == "\xFF\xD8".b
          loop do
            info = jpeg_info(head)
            if info
              size = [info[:w], info[:h]]
              break
            end
            more = f.read(head.bytesize * 3)
            break if more.nil? || more.empty?
            head << more.b
          end
        end
      end
      @size_cache[p] = [stamp, size]
      size
    rescue StandardError => e
      puts "[PlanPDF] cannot size image #{p}: #{e.message}"
      nil
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
    # `turn` is how far the window these shapes are seen through is turned, in
    # degrees: the lines are already turned by to_paper, the writing needs telling.
    def self.draw_shapes(st, shapes, to_paper, scale = 1.0, imgs = nil, turn = 0.0)
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
          draw_text(st, s, to_paper, scale, turn)
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
      return draw_placed_image(st, s, to_paper, scale, imgs) if s[:placed]
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

    # A picture in a box of its own (2026-10-07, PlanCanvas.place_pictures!).
    #
    # Not the rule above. The box IS the picture: x, y, w, h is where the part
    # of it that is seen lies on the paper, :crop says how much of the file is
    # cut off each side - [left, bottom, right, top], each a share of the whole
    # picture - and :rot turns the box about its own middle, anticlockwise.
    # The window draws the same four numbers the same way (shapeSVG).
    def self.draw_placed_image(st, s, to_paper, scale, imgs)
      x, y = to_paper.call(s[:x], s[:y])
      w = s[:w].to_f * scale
      h = s[:h].to_f * scale
      nm   = imgs && imgs.name_for(s[:path])
      info = nm && imgs.info_for(nm)
      cl, cb, cr, ct = Array(s[:crop]).map(&:to_f)
      cl ||= 0.0; cb ||= 0.0; cr ||= 0.0; ct ||= 0.0
      rot = s[:rot].to_f

      st.save
      unless rot.zero?
        r  = rot * Math::PI / 180.0
        c  = Math.cos(r)
        sn = Math.sin(r)
        cx = (x + w / 2.0) * PT
        cy = (y + h / 2.0) * PT
        # six places, not three: this is multiplied by a point that can be
        # 2,500 points from the corner of the sheet
        m = [c, sn, -sn, c].map { |v| format('%.6f', v) }.join(' ')
        st << "#{m} #{n(cx - c * cx + sn * cy)} #{n(cy - sn * cx - c * cy)} cm"
      end
      if nm && info
        fw = w / [1.0 - cl - cr, 0.01].max           # the WHOLE picture, on the paper
        fh = h / [1.0 - cb - ct, 0.01].max
        st.save
        st << "#{n(x * PT)} #{n(y * PT)} #{n(w * PT)} #{n(h * PT)} re W n"
        st << "#{n(fw * PT)} 0 0 #{n(fh * PT)} #{n((x - cl * fw) * PT)} #{n((y - cb * fh) * PT)} cm"
        st << "/#{nm} Do"
        st.restore
      end
      if s[:frame] || !(nm && info)
        st << '0.75 w 0.6 G'
        st << "#{n(x * PT)} #{n(y * PT)} #{n(w * PT)} #{n(h * PT)} re S"
        st << '0 G'
      end
      st.restore
    end

    def self.draw_text(st, s, to_paper, scale, turn = 0.0)
      str = s[:text].to_s
      return if str.empty?
      x, y = to_paper.call(s[:x], s[:y])
      size = (s[:h].to_f * scale) * PT / CAP_RATIO
      return if size < 0.8   # smaller than this is a smudge on paper
      bold  = s[:bold]
      key   = bold ? :bold : (s[:italic] ? :italic : :plain)
      fnt   = { plain: '/F1', bold: '/F2', italic: '/F3' }[key]
      # a lettering he picked, or letters Helvetica has not got (Hebrew): a
      # TrueType font written into the file, the glyphs by id (2026-10-07)
      ttf = font_set ? ttf_for(str, s[:font], bold, s[:italic]) : nil
      shown = nil
      if ttf
        e = font_set.use(ttf)
        fnt = "/#{e[:name]}"
        gids = visual(str).each_char.map { |ch| g = ttf.gid(ch.ord); e[:used][g] = ch.ord; g }
        shown = '<' + gids.map { |g| format('%04X', g) }.join + '>'
      end
      w     = text_width(str, size, bold, s[:font])
      cap   = size * CAP_RATIO

      # A shape drawn by plan_generator is centred on its point; one placed on
      # the sheet by hand sits on its baseline at the left.
      align = s[:align] || :left
      dx = align == :center ? -w / 2.0 : 0.0
      dy = align == :center ? -cap / 2.0 : 0.0

      ang = ((s[:rotation] || 0.0) + turn.to_f) * Math::PI / 180.0
      # a colour of its own (2026-10-07): "#rrggbb" set on the label at the side
      col = s[:color].to_s =~ /\A#([0-9a-fA-F]{6})\z/ ? [$1[0, 2], $1[2, 2], $1[4, 2]].map { |h| h.to_i(16) } : nil
      st << 'BT'
      st << (col ? "#{grey(col)} rg" : '0 g')
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
      st << (shown ? "#{shown} Tj" : "(#{esc(str)}) Tj")
      st << '0 Tc' if s[:tracking]
      st << 'ET'
      st << '0 g' if col
      # a line under the words (2026-10-07), drawn in the words' own frame so
      # it turns with them: a little under the baseline, as wide as the words
      if s[:underline]
        c  = Math.cos(ang)
        sn = Math.sin(ang)
        st.save
        st << "#{n(c)} #{n(sn)} #{n(-sn)} #{n(c)} #{n(x * PT)} #{n(y * PT)} cm"
        st << "#{grey(col)} RG" if col
        st << "#{n(size * 0.06)} w"
        st << "#{n(dx)} #{n(dy - size * 0.12)} m #{n(dx + w)} #{n(dy - size * 0.12)} l S"
        st.restore
      end
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
        # a window whose frame turns with the drawing is clipped to the turned
        # rectangle - four corners, not `re` (2026-10-07); any other, as before
        turned = v.respond_to?(:box_turn) && v.box_turn && v.rotation.to_f != 0.0
        if turned
          st << v.frame_corners.each_with_index.map { |(px, py), i| "#{n(px * PT)} #{n(py * PT)} #{i.zero? ? 'm' : 'l'}" }.join(' ') + ' h W n'
        else
          st << "#{n(v.x * PT)} #{n(v.y * PT)} #{n(v.w * PT)} #{n(v.h * PT)} re W n"
        end
        canvas.layers.each do |lay|
          next unless lay.visible
          draw_shapes(st, lay.shapes, to_paper, s, imgs,
                      v.respond_to?(:rotation) ? v.rotation.to_f : 0.0)
        end
        st.restore

        if v.frame
          st << '0.5 G 0.4 w'
          if turned
            st << v.frame_corners.each_with_index.map { |(px, py), i| "#{n(px * PT)} #{n(py * PT)} #{i.zero? ? 'm' : 'l'}" }.join(' ') + ' h S'
          else
            st << "#{n(v.x * PT)} #{n(v.y * PT)} #{n(v.w * PT)} #{n(v.h * PT)} re S"
          end
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

      # Every page is drawn FIRST, so the fonts it set its writing in are
      # known before the font objects are written (2026-10-07).
      @font_set = USE_TTF_FONTS ? FontSet.new : nil
      begin
        drawn = pages.map do |pg|
          imgs = ImageSet.new
          [pg, imgs, page_stream(pg, doc, imgs)]
        end
      ensure
        fonts = @font_set
        @font_set = nil
      end

      font_ids = {}
      FONTS.each do |key, name|
        font_ids[key] = add.call("<< /Type /Font /Subtype /Type1 /BaseFont /#{name} /Encoding /WinAnsiEncoding >>")
      end
      extra = fonts ? fonts.entries.map { |e| "/#{e[:name]} #{font_objects(e, add)} 0 R" } : []
      res = "<< /Font << /F1 #{font_ids[:plain]} 0 R /F2 #{font_ids[:bold]} 0 R " \
            "/F3 #{font_ids[:italic]} 0 R#{extra.empty? ? '' : ' ' + extra.join(' ')} >> >>"

      pages_id = add.call('PLACEHOLDER')
      page_ids = []
      drawn.each do |pg, imgs, content|
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
