# encoding: utf-8
# Interior Pro - MATERIALS FROM INVOICE STUDIO (2026-09-17)
#
# His words: "לקחת את החומרים מהתוכנה ולשים אותם ברינדור", and then: "צריך
# להיות סימון ליד כל חומר האם לשלוח אותו לרינדור". So:
#
#   Invoice Studio      materials.json (bridge folder, next to rooms.json)
#   ------------------  ----------------------------------------------------
#   3D checkbox on      { projects: [ { id, name, materials: [ { id, name,
#   a material          room, image_url, vendor, sku, category, color, size,
#                       render: true ... } ] } ] }
#
# This reads that file, keeps ONLY render:true, downloads each picture into
# the library's textures/ and writes a card the wall of thumbnails already
# knows how to show and apply. The card id is the Invoice Studio UUID
# ("IS_<uuid>"), so importing twice updates, never duplicates. Cards land in
# a folder named after the project.
#
# No V-Ray numbers are invented here - a card without 'vray' just paints the
# picture; the numbers are Interior Pro's job (material_library.rb).
#
# Kill switch: InteriorPro::MaterialImport::USE_MATERIAL_IMPORT = false
require 'json'
require 'net/http'
require 'uri'
require 'openssl'
require 'fileutils'

module InteriorPro
  module MaterialImport
    USE_MATERIAL_IMPORT = true unless const_defined?(:USE_MATERIAL_IMPORT, false)
    MATERIALS_FILE = 'materials.json'.freeze
    ID_PREFIX      = 'IS_'.freeze
    DEFAULT_TEXTURE_INCHES = 24.0   # a tile picture without a known size

    LOG = File.join(File.dirname(__FILE__), 'material_import_log.txt')
    def self.log(msg)
      puts "[MaterialImport] #{msg}"
      File.open(LOG, 'a') { |f| f.puts("#{Time.now.strftime('%H:%M:%S')}  #{msg}") ; f.flush }
    rescue StandardError
      nil
    end

    def self.lib
      InteriorPro::MaterialLibrary
    end

    # The bridge folder is the one SyncBridge already knows (rooms.json).
    def self.materials_path
      d = defined?(InteriorPro::SyncBridge) ? (InteriorPro::SyncBridge.folder rescue nil) : nil
      return nil if d.nil? || d.to_s.empty?
      File.join(d, MATERIALS_FILE)
    end

    # PURE. materials.json text -> [{project:, material:}] for render:true only.
    def self.flagged(text)
      data = JSON.parse(text)
      out = []
      Array(data['projects']).each do |p|
        Array(p['materials']).each do |m|
          next unless m['render'] == true
          out << { 'project' => { 'id' => p['id'].to_s, 'name' => p['name'].to_s }, 'material' => m }
        end
      end
      out
    end

    # PURE. "24x48" / "24 X 48" / '24" x 48"' -> [24.0, 48.0]. nil when the
    # vendor wrote something else. NOTE: \d is written [0-9] on purpose -
    # see the rule in CLAUDE.md.
    def self.parse_size(s)
      m = s.to_s.match(/([0-9]+(?:\.[0-9]+)?)\s*["\u2019\u201d]?\s*[xX]\s*([0-9]+(?:\.[0-9]+)?)/)
      return nil unless m
      a = m[1].to_f
      b = m[2].to_f
      (a > 0 && b > 0) ? [a, b] : nil
    end

    # Pixel size of a JPEG or PNG, straight out of its header. No image
    # library anywhere near SketchUp - it reads the bytes we just fetched.
    def self.image_pixels(bytes)
      b = bytes.to_s.b
      return nil if b.bytesize < 24
      if b[0, 8] == "\x89PNG\r\n\x1a\n".b
        return [b[16, 4].unpack1('N'), b[20, 4].unpack1('N')]
      end
      return nil unless b[0, 2] == "\xFF\xD8".b
      i = 2
      while i < b.bytesize - 9
        return nil unless b.getbyte(i) == 0xFF
        marker = b.getbyte(i + 1)
        if marker >= 0xC0 && marker <= 0xCF && ![0xC4, 0xC8, 0xCC].include?(marker)
          return [b[i + 7, 2].unpack1('n'), b[i + 5, 2].unpack1('n')]
        end
        len = b[i + 2, 2].unpack1('n')
        return nil if len.nil? || len < 2
        i += 2 + len
      end
      nil
    end

    # PURE. A vendor photo usually shows the tile MORE THAN ONCE - two
    # 24x48 tiles stacked is what Bedrosians ships, and the joint baked
    # into that photo is what he saw on his floor. Nothing is read from
    # the pixels: the SHAPE of the photo against the SHAPE of the tile
    # says how many tiles are in it. Returns [across, down], 1..4 each,
    # and [1, 1] when nothing fits - a crop has to be earned.
    def self.tile_fit(tile_w, tile_l, px_w, px_h)
      tw = tile_w.to_f; tl = tile_l.to_f
      pw = px_w.to_f; ph = px_h.to_f
      return [1, 1] if tw <= 0 || tl <= 0 || pw <= 0 || ph <= 0
      want = Math.log(pw / ph)
      best = [1, 1]
      best_err = nil
      (1..4).each do |nx|
        (1..4).each do |ny|
          err = (Math.log((tw * nx) / (tl * ny)) - want).abs
          err += (nx + ny) * 0.001          # a tie goes to the simpler answer
          if best_err.nil? || err < best_err
            best_err = err
            best = [nx, ny]
          end
        end
      end
      # 3% is the whole guard: an exact fit is 0, and the shape that
      # fits nothing was 3.5% off. Loose here means eating his picture.
      best_err < 0.03 ? best : [1, 1]
    end

    # PURE. What a card looks like for one flagged material.
    def self.card_for(project, m, texture_file, bytes = nil)
      tile = parse_size(m['size'])
      tile_w, tile_l = tile || [DEFAULT_TEXTURE_INCHES, DEFAULT_TEXTURE_INCHES]
      px = image_pixels(bytes)
      tiles_x, tiles_y = px ? tile_fit(tile_w, tile_l, px[0], px[1]) : [1, 1]
      log("#{m['name']}: size=#{m['size'].inspect} tile=#{tile_w}x#{tile_l} " \
          "photo=#{px ? px.join('x') : 'unknown'} -> #{tiles_x}x#{tiles_y} tile(s) in the photo")
      {
        'card_version' => lib::CARD_VERSION,
        'id'           => "#{ID_PREFIX}#{m['id']}",
        'name'         => m['name'].to_s.strip.empty? ? 'Material' : m['name'].to_s.strip,
        'path'         => folder_name(project),
        'category'     => folder_name(project),
        'note'         => [m['vendor'], m['sku'], m['size'], m['color']].map(&:to_s).reject(&:empty?).join(' · '),
        'saved_at'     => Time.now.strftime('%Y-%m-%d %H:%M'),
        'color'        => [200, 200, 200],
        'alpha'        => 1.0,
        # the TILE is what the layout repeats; the TEXTURE is how much of
        # the world the photo covers. They differ whenever the photo shows
        # more than one tile - that is the crop, done by the mapping.
        'tile_w_inches'  => tile_w,
        'tile_l_inches'  => tile_l,
        'image_tiles_x'  => tiles_x,
        'image_tiles_y'  => tiles_y,
        'texture_width_inches'  => tile_w * tiles_x,
        'texture_height_inches' => tile_l * tiles_y,
        'texture_file' => texture_file,
        'source'       => { 'app' => 'invoice_studio', 'material_id' => m['id'].to_s,
                            'project_id' => project['id'], 'project_name' => project['name'],
                            'room' => m['room'].to_s, 'image_url' => m['image_url'].to_s,
                            'link' => m['link'].to_s },
      }
    end

    # A folder name the library accepts: the project's name, no slashes.
    def self.folder_name(project)
      n = project['name'].to_s.strip
      n = project['id'].to_s if n.empty?
      n.tr('/\\', '--').strip
    end

    # Downloads one picture. Returns the bytes or nil. Follows up to 5 redirects.
    def self.fetch(url, hops = 5)
      return nil if url.to_s.empty? || hops <= 0
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 20
      http.read_timeout = 60
      begin
        store = OpenSSL::X509::Store.new
        store.set_default_paths
        http.cert_store = store
      rescue StandardError
        nil
      end
      req = Net::HTTP::Get.new(uri.request_uri)
      req['User-Agent'] = 'Mozilla/5.0 (InteriorPro SketchUp)'
      res = http.request(req)
      case res
      when Net::HTTPSuccess then res.body
      when Net::HTTPRedirection then fetch(URI.join(url, res['location']).to_s, hops - 1)
      else
        log("download #{res.code} for #{url[0, 80]}")
        nil
      end
    rescue StandardError => e
      log("download failed: #{e.class} #{e.message} for #{url[0, 80]}")
      nil
    end

    def self.ext_for(url, bytes)
      return '.png'  if bytes && bytes[0, 8] == "\x89PNG\r\n\x1A\n".b
      return '.jpg'  if bytes && bytes[0, 3] == "\xFF\xD8\xFF".b
      return '.webp' if bytes && bytes[8, 4] == 'WEBP'
      e = File.extname(URI(url).path.to_s).downcase rescue ''
      %w[.jpg .jpeg .png .webp].include?(e) ? e : '.jpg'
    end

    # THE ENTRY POINT. Returns { imported: n, skipped: n, failed: n, problems: [...] }.
    def self.import!
      res = { 'imported' => 0, 'updated' => 0, 'failed' => 0, 'problems' => [] }
      return res.merge('problems' => ['kill switch off']) unless USE_MATERIAL_IMPORT
      path = materials_path
      if path.nil?
        return res.merge('problems' => ['תיקיית הגשר לא הוגדרה (Extensions > Interior Pro > Sync folder)'])
      end
      unless File.exist?(path)
        return res.merge('problems' => ["אין #{MATERIALS_FILE} בתיקיית הגשר. ב-Invoice Studio: Settings > Write materials.json now"])
      end
      dir = lib.folder_or_ask!
      return res.merge('problems' => ['לא נבחרה תיקיית ספרייה']) if dir.nil?
      lib.ensure_folder!

      items = flagged(File.read(path, encoding: 'UTF-8'))
      log("#{items.length} flagged material(s) in #{path}")
      return res.merge('problems' => ['שום חומר לא מסומן 3D בתוכנה']) if items.empty?

      existing = {}
      lib.cards.each { |c| existing[c['id'].to_s] = c }

      items.each do |it|
        m = it['material']; p = it['project']
        id = "#{ID_PREFIX}#{m['id']}"
        url = m['image_url'].to_s
        if url.empty?
          res['failed'] += 1
          res['problems'] << "#{m['name']}: אין תמונה"
          next
        end
        bytes = fetch(url)
        if bytes.nil? || bytes.bytesize < 200
          res['failed'] += 1
          res['problems'] << "#{m['name']}: התמונה לא ירדה"
          next
        end
        ext = ext_for(url, bytes)
        tex_rel = File.join('textures', "#{id}#{ext}")
        File.binwrite(File.join(dir, tex_rel), bytes)

        card = card_for(p, m, tex_rel, bytes)
        old = existing[id]
        if old
          # keep what he tuned: V-Ray numbers, a folder he moved it to, a name he gave
          card['vray'] = old['vray'] if old['vray']
          card['path'] = old['path'] if old['path'] && !old['path'].to_s.empty?
          card['category'] = card['path']
          card['name'] = old['name'] if old['name'] && !old['name'].to_s.empty?
          # sizes he corrected by hand win over what we work out
          %w[tile_w_inches tile_l_inches image_tiles_x image_tiles_y
             texture_width_inches texture_height_inches].each do |k|
            card[k] = old[k] if old[k]
          end
          res['updated'] += 1
        else
          res['imported'] += 1
        end
        lib.add_folder!(card['path']) rescue nil
        out = old && old['_path'] ? old['_path'] : File.join(dir, "#{id}.json")
        lib.write_atomic(out, JSON.pretty_generate(card))
        log("#{old ? 'updated' : 'imported'} #{card['name']} -> #{out}")
      end
      res
    rescue StandardError => e
      log("import!: #{e.class} #{e.message}")
      res.merge('problems' => res['problems'] + ["#{e.class}: #{e.message}"])
    end

    def self.summary(res)
      lines = []
      lines << "יובאו: #{res['imported']}" if res['imported'] > 0
      lines << "עודכנו: #{res['updated']}" if res['updated'] > 0
      lines << "נכשלו: #{res['failed']}" if res['failed'] > 0
      lines.concat(res['problems'].first(6))
      lines.empty? ? 'לא קרה כלום.' : lines.join("\n")
    end
  end
end
