# encoding: utf-8
# Interior Pro - THE MATERIAL LIBRARY (2026-09-15)
#
# WHY. He wants the materials he likes to follow him: saved once, then
# picked again in any project, on either machine, and handed to V-Ray
# ready to render. Today a material he tuned lives inside one .skp and
# dies with it.
#
# WHAT A LIBRARY MATERIAL IS. Data, not a texture on a face
# (VRAY_POC_PLAN.md 2ב - the same rule that lets Tile give three outputs):
#
#   <folder>/<IP_MAT_0001>.json      the card: name, colour, texture file,
#                                    texture size, and the V-Ray numbers
#   <folder>/textures/<id>.png       the image itself, copied in
#
# so the card can come from his own model today and from the Invoice
# Studio clipper tomorrow - it is the same shape either way: a picture
# plus numbers.
#
# THE NUMBERS come from the BRDFVRayMtl of the material, measured live on
# 2026-09-15 (HANDOFF_VRAY_STEP1.md): :reflect_glossiness, :roughness,
# :reflect. A material V-Ray never touched simply has none, and saves
# without them - the picture is still worth keeping.
#
# THE FOLDER is remembered PER INSTALLATION (Sketchup.write_default), not
# per model, so a new project already knows it. Default: the same
# OneDrive folder the Invoice Studio bridge uses, so one synced place
# holds everything.
#
# Kill switch: InteriorPro::MaterialLibrary::USE_MATERIAL_LIBRARY = false
require 'json'
require 'fileutils'

module InteriorPro
  module MaterialLibrary
    USE_MATERIAL_LIBRARY = true unless const_defined?(:USE_MATERIAL_LIBRARY, false)

    PREF_SECTION = 'InteriorPro'.freeze
    PREF_FOLDER  = 'material_library_folder'.freeze
    SUBFOLDER    = 'materials'.freeze
    CARD_VERSION = 1

    # ---- the folder --------------------------------------------------
    # Never guessed into existence. Same law as the sync bridge: a wrong
    # path that silently does nothing is worse than a question.
    def self.folder
      saved = (Sketchup.read_default(PREF_SECTION, PREF_FOLDER, nil) rescue nil)
      return saved.to_s if saved && !saved.to_s.empty?
      nil
    end

    def self.folder?
      f = folder
      !f.nil? && File.directory?(f)
    end

    # The best place to OFFER him, from the bridge folder he may already
    # have set, else next to it.
    def self.guess_folder
      if defined?(InteriorPro::SyncBridge)
        b = (InteriorPro::SyncBridge.folder rescue nil)
        return File.join(b, SUBFOLDER) if b && !b.to_s.empty?
        g = (InteriorPro::SyncBridge.guess_folder rescue nil)
        return File.join(g, SUBFOLDER) if g
      end
      home = (ENV['USERPROFILE'] || ENV['HOME'] || Dir.home).to_s
      File.join(home, 'OneDrive', 'InteriorPro', SUBFOLDER)
    end

    def self.choose_folder!
      start = guess_folder
      start = File.dirname(start) until start.to_s.empty? || File.directory?(start) || File.dirname(start) == start
      picked = UI.select_directory(title: 'תיקיית החומרים של Interior Pro',
                                   directory: (File.directory?(start.to_s) ? start : nil))
      return nil if picked.nil? || picked.to_s.empty?
      set_folder!(picked.to_s)
    end

    def self.set_folder!(path)
      Sketchup.write_default(PREF_SECTION, PREF_FOLDER, path.to_s)
      ensure_folder!
      path.to_s
    end

    # Creates the folder (and its textures/ child) only once we have one.
    def self.ensure_folder!
      f = folder
      return nil if f.nil? || f.empty?
      FileUtils.mkdir_p(f) unless File.directory?(f)
      tex = File.join(f, 'textures')
      FileUtils.mkdir_p(tex) unless File.directory?(tex)
      f
    rescue StandardError => e
      warn "[MaterialLibrary] could not create #{f}: #{e.message}"
      nil
    end

    # Asks once, if it was never set. Returns the folder or nil.
    def self.folder_or_ask!
      return folder if folder?
      choose_folder!
      folder? ? folder : nil
    end

    # ---- reading the V-Ray numbers off a material --------------------
    # Nothing here converts anything. A material V-Ray has not touched
    # answers nil, and that is a fine answer.
    # THE RELIABLE READ (2026-09-15). The live plugin object is only handed
    # back when a conversion actually happens: on a material V-Ray already
    # owns, convert_to_vray answers nil and there is no documented way back
    # to it (VRay::Context.active, the obvious one, CRASHES SketchUp).
    # But V-Ray serialises the whole graph as JSON into the VRayPlugins
    # attribute dictionary on the SketchUp material - plain, readable, and
    # ours. So reading numbers never touches the V-Ray API at all.
    def self.vray_numbers_from_dict(mat)
      d = (mat.attribute_dictionary('VRayPlugins') rescue nil)
      return nil if d.nil?
      raw = nil
      d.each_pair { |k, v| raw = v if k.to_s.end_with?('BRDFVRayMtl') }
      return nil if raw.nil?
      g = JSON.parse(raw.to_s)
      pr = g['params'] || {}
      out = {}
      out['reflect_glossiness']   = num(pr['reflect_glossiness'])
      out['roughness']            = num(pr['roughness'])
      out['option_use_roughness'] = num(pr['option_use_roughness'])
      out['reflect']              = parse_colour(pr['reflect'])
      out['diffuse_is_texture']   = (pr['diffuse'].to_s.include?('/') ? 1 : 0)
      out.reject { |_, v| v.nil? }
    rescue StandardError => e
      trace(nil, "vray_numbers_from_dict: #{e.class} #{e.message}")
    end

    # "Color(0.5,0.5,0.5)" -> [0.5, 0.5, 0.5]. Anything else -> nil.
    def self.parse_colour(v)
      s = v.to_s
      m = s.match(/Color\(([^)]*)\)/)
      return nil if m.nil?
      parts = m[1].split(',').map { |x| Float(x.strip) rescue nil }
      return nil if parts.length < 3 || parts.any?(&:nil?)
      parts[0, 3].map { |x| x.round(4) }
    rescue StandardError
      nil
    end

    def self.vray_numbers(mat)
      LAST_TRACE.clear
      return trace(nil, 'VRay not loaded') unless Object.const_defined?(:VRay)
      unless (VRay::Material.valid?(mat) rescue false)
        return trace(nil, 'material is not a V-Ray material yet')
      end
      vm = VRay::Material.load(mat)
      return trace(nil, 'Material.load gave nil') if vm.nil?

      # convert_to_vray answers nil when the material is ALREADY converted
      # (measured 2026-09-15 - it cost a whole report). Then the top plugin
      # is reached through find(main_plugin) instead.
      plug = (vm.convert_to_vray rescue nil)
      if plug.nil? || !plug.respond_to?(:[])
        trace(nil, "convert_to_vray gave #{plug.inspect} - trying find(main_plugin)")
        mp = (vm.main_plugin rescue nil)
        other = mp ? (VRay::Material.find(mp) rescue nil) : nil
        plug = (other.convert_to_vray rescue nil) if other.respond_to?(:convert_to_vray)
      end
      return trace(nil, 'no top plugin') if plug.nil? || !plug.respond_to?(:[])

      brdf = (plug[:brdf] rescue nil)
      if brdf.nil?
        plug.each_child { |c| brdf = c if c.respond_to?(:type) && c.type == :BRDFVRayMtl }
      end
      return trace(nil, 'no BRDFVRayMtl under the plugin') if brdf.nil?

      out = {}
      out['reflect_glossiness']   = num(brdf[:reflect_glossiness])
      out['roughness']            = num(brdf[:roughness])
      out['option_use_roughness'] = (brdf[:option_use_roughness] ? 1 : 0)
      out['reflect'] = colour_triplet(brdf[:reflect])
      out = out.reject { |_, v| v.nil? }
      trace(out, "read #{out.keys.join(', ')}")
    rescue StandardError => e
      trace(nil, "#{e.class}: #{e.message}")
    end

    # Why the last read gave what it gave - so "no numbers" is never silent.
    LAST_TRACE = [] unless const_defined?(:LAST_TRACE)
    # Also on DISK. He does not paste console output back - a report file in
    # the plugin folder is how every diagnosis in this project actually gets
    # read (CLAUDE.md, "\u05ea\u05de\u05d3\u05d5\u05d3, \u05d0\u05dc \u05ea\u05e0\u05d7\u05e9").
    TRACE_LOG = File.join(File.dirname(__FILE__), 'material_library_log.txt')
    def self.trace(value, why)
      LAST_TRACE << why.to_s
      puts "[MaterialLibrary] #{why}"
      begin
        File.open(TRACE_LOG, 'a') do |f|
          f.puts("#{Time.now.strftime('%H:%M:%S')}  #{why}")
          f.flush
          begin ; f.fsync ; rescue StandardError ; nil ; end
        end
      rescue StandardError
        nil
      end
      value
    end

    def self.num(v)
      return nil if v.nil?
      Float(v).round(4)
    rescue StandardError
      nil
    end

    # VRay::Color -> [r,g,b], each 0..1. Its accessors are not documented,
    # so try the usual ones and give up quietly rather than guess.
    def self.colour_triplet(c)
      return nil if c.nil?
      %i[r red].each do |rr|
        next unless c.respond_to?(rr)
        g = c.respond_to?(:g) ? c.g : (c.respond_to?(:green) ? c.green : nil)
        b = c.respond_to?(:b) ? c.b : (c.respond_to?(:blue) ? c.blue : nil)
        next if g.nil? || b.nil?
        return [Float(c.send(rr)).round(4), Float(g).round(4), Float(b).round(4)]
      end
      nil
    rescue StandardError
      nil
    end

    # ---- WRITING the card's V-Ray numbers onto a material ------------
    # THE CARD IS THE SOURCE OF TRUTH. And the write goes to the LIVE scene
    # (HANDOFF_VRAY_STEP3.md, 2026-09-16 - the first path a render showed):
    #
    #   scene = VRay::Context.active.scene
    #   m     = scene[main_plugin]
    #   scene.change { b = m[:brdf]; b[:reflect_glossiness_float] = 0.05 }
    #
    # Three laws, each one measured:
    #  1. SYMBOLS ONLY inside scene.change. A string key crashes SketchUp.
    #  2. Every knob that can take a texture has a userdata TWIN
    #     (reflect_glossiness_float, roughness_float, reflect_color ...).
    #     V-Ray rebuilds the real param FROM the twin after every commit, so
    #     writing the real param is undone one step later. Write the twin.
    #     A knob without a twin (fresnel, option_use_roughness) is written
    #     straight. `m[:brdf].dump` shows the userdata section.
    #  3. m[:brdf] is fetched INSIDE the block.
    #
    # Card fields read here (all optional): reflect_glossiness, roughness,
    # option_use_roughness, reflect [r,g,b], bump_amount, bump_file (relative
    # to the library folder, e.g. "maps/stucco_bump.jpg").
    #
    # The old convert_to_vray path stuck to a handle outside the live scene
    # and never reached the renderer (HANDOFF_VRAY_STEP2.md).
    #
    # Call this AFTER commit_operation, never inside one: a V-Ray failure
    # must not be able to roll back the paint the user already saw.
    # Returns true only if a number actually landed.
    # ---- a BUMP map on the live material --------------------------------
    # THE RECIPE (debug_vray_bump.rb, 2026-09-16, render confirmed): V-Ray holds
    # the SketchUp texture as  brdf[:diffuse] -> TexBitmap "<brdf>/SUDiffuse"
    # -> [:bitmap] -> BitmapBuffer[:file].  A bump map is the SAME chain,
    # copied with Plugin#duplicate, pointed at another file and hung on the
    # bump_map_tex TWIN (the twin drives the real bump_map). The uvwgen is
    # shared with the diffuse, so the map scales exactly like the texture.
    # Runs INSIDE the caller's scene.change. Returns the TexBitmap or nil.
    # Idempotent: a second call re-points the existing copy's file.
    def self.bump_tex_for!(scene, brdf, file)
      existing = (brdf[:bump_map_tex] rescue nil)
      if existing.respond_to?(:[]) && (existing.type rescue nil) == :TexBitmap
        buf = (existing[:bitmap] rescue nil)
        if buf.respond_to?(:[]=)
          buf[:file] = file
          return existing
        end
      end
      diff = (brdf[:diffuse_tex] rescue nil)
      diff = (brdf[:diffuse] rescue nil) unless diff.respond_to?(:[])
      unless diff.respond_to?(:[]) && (diff.type rescue nil) == :TexBitmap
        trace(nil, 'bump: material has no SketchUp texture chain (SUDiffuse) to copy')
        return nil
      end
      src_buf = diff[:bitmap]
      return trace(nil, 'bump: diffuse has no BitmapBuffer') unless src_buf.respond_to?(:[])
      buf = src_buf.duplicate
      buf[:file] = file
      tex = diff.duplicate
      tex[:bitmap] = buf
      tex[:uvwgen] = diff[:uvwgen]
      tex
    end

    def self.apply_vray_numbers!(mat, nums)
      LAST_TRACE.clear
      return trace(false, 'kill switch off') unless USE_MATERIAL_LIBRARY
      return trace(false, 'no material') if mat.nil?
      return trace(false, 'card has no vray numbers') if nums.nil? || nums.empty?
      return trace(false, 'VRay not loaded') unless Object.const_defined?(:VRay)

      unless (VRay::Material.valid?(mat) rescue false)
        # a plain SketchUp material must be handed to V-Ray first
        (VRay::MaterialSync.to_vray(mat) rescue nil)
      end
      vm = (VRay::Material.load(mat) rescue nil)
      return trace(false, 'Material.load gave nil') if vm.nil?
      path = (vm.main_plugin rescue nil)
      return trace(false, 'no main_plugin') if path.nil?

      ctx = (VRay::Context.active rescue nil)
      return trace(false, 'no active V-Ray context') if ctx.nil?
      scene = (ctx.scene rescue nil)
      return trace(false, 'no live scene') if scene.nil?
      m = (scene[path] rescue nil)
      return trace(false, "#{path} not in the live scene") if m.nil?

      g = num(nums['reflect_glossiness'])
      r = num(nums['roughness'])
      u = nums['option_use_roughness']
      c = nums['reflect']
      c = nil unless c.is_a?(Array) && c.length >= 3
      ba = num(nums['bump_amount'])
      bf = nums['bump_file'].to_s
      bf = bf.empty? ? nil : File.join(folder.to_s, bf)
      if bf && !File.exist?(bf)
        trace(nil, "bump file missing, skipped: #{bf}")
        bf = nil
      end
      return trace(false, 'card had no usable number') if g.nil? && r.nil? && u.nil? && c.nil? && ba.nil? && bf.nil?

      wrote = []
      scene.change do
        b = m[:brdf]                       # inside the block, always
        raise 'no brdf on live plugin' if b.nil?
        unless g.nil?
          b[:reflect_glossiness_float] = g
          wrote << "gloss=#{g}"
        end
        unless r.nil?
          b[:roughness_float] = r
          wrote << "rough=#{r}"
        end
        unless u.nil?
          b[:option_use_roughness] = (num(u).to_f > 0.5)
          wrote << "use_rough=#{num(u).to_f > 0.5}"
        end
        unless c.nil?
          b[:reflect_color] = VRay::Color.new(c[0].to_f, c[1].to_f, c[2].to_f)
          wrote << "reflect=#{c[0, 3].inspect}"
        end
        unless bf.nil?
          tex = bump_tex_for!(scene, b, bf)
          unless tex.nil?
            b[:bump_map_tex]    = tex
            b[:bump_map_tex_on] = true
            b[:bump_type]       = 0
            wrote << "bump_file=#{File.basename(bf)}"
          end
        end
        unless ba.nil?
          b[:bump_amount_float] = ba
          wrote << "bump=#{ba}"
        end
      end

      # read back through a FRESH handle - the proof, not the intent
      back = (scene[path][:brdf][:reflect_glossiness] rescue nil)
      trace(true, "wrote #{wrote.join(', ')} onto #{mat.display_name} via scene.change; reflect_glossiness reads back #{back.inspect}")
    rescue StandardError => e
      trace(false, "#{e.class}: #{e.message}")
    end

    # LEGACY (unused since 2026-09-16): the convert_to_vray handle. Kept
    # only so nothing else breaks; the live write above is the way.
    # Hands back the top V-Ray plugin for a material, or nil. Converting is
    # what creates it: on a material V-Ray already owns, convert_to_vray
    # answers nil and Material.find(main_plugin) gives back another Material,
    # not a Plugin (measured 2026-09-16) - so nil here means "no way in".
    def self.reach_brdf_owner(mat)
      unless (VRay::Material.valid?(mat) rescue false)
        # a plain SketchUp material must be handed to V-Ray first, or
        # Material.load raises "Failed to load special object"
        (VRay::MaterialSync.to_vray(mat) rescue nil)
      end
      vm = (VRay::Material.load(mat) rescue nil)
      return nil if vm.nil?
      plug = (vm.convert_to_vray rescue nil)
      return nil unless plug.respond_to?(:[])
      plug
    rescue StandardError
      nil
    end

    # Makes V-Ray forget it owns this material: its whole claim is these two
    # attribute dictionaries on the SketchUp material (VRayInfo carries
    # class / main_plugin / type / version, VRayPlugins the serialised graph).
    # Only ever called on a material the library itself just built from a
    # card, never on one the user tuned by hand.
    def self.forget_vray!(mat)
      dicts = (mat.attribute_dictionaries rescue nil)
      return trace(false, 'no attribute dictionaries to drop') if dicts.nil?
      %w[VRayPlugins VRayInfo].each do |name|
        next if dicts[name].nil?
        dicts.delete(name)
        puts "[MaterialLibrary] dropped #{name} from #{mat.display_name}"
      end
      true
    rescue StandardError => e
      trace(false, "forget_vray!: #{e.class} #{e.message}")
    end

    # ---- saving one material into the library ------------------------
    # The texture is COPIED out of the model with a TextureWriter, which
    # is the only way to get at it: a material's texture filename often
    # points at a file that is not on this machine (wood2's bitmap says
    # D:\Calismalar\... - a path from whoever made it).
    def self.save!(mat, path: nil, category: nil, note: nil)
      return nil unless USE_MATERIAL_LIBRARY
      return nil if mat.nil?
      dir = folder_or_ask!
      return nil if dir.nil?
      ensure_folder!

      id = nil
      if defined?(InteriorPro::MaterialIds)
        # ensure_id! stamps one if this material never had it, so a card
        # is never written against a material with no permanent handle.
        id = (InteriorPro::MaterialIds.ensure_id!(mat) rescue nil)
        id ||= (InteriorPro::MaterialIds.id_of(mat) rescue nil)
      end
      id ||= "IP_MAT_#{mat.display_name.to_s.gsub(/[^A-Za-z0-9_]/, '_')}"

      card = {
        'card_version' => CARD_VERSION,
        'id'           => id,
        'name'         => mat.display_name.to_s,
        'path'         => clean_path(path),
        'category'     => (path.nil? ? category.to_s : clean_path(path)),
        'note'         => note.to_s,
        'saved_at'     => Time.now.strftime('%Y-%m-%d %H:%M'),
        'color'        => colour_of(mat),
        'alpha'        => (mat.alpha rescue 1.0),
      }

      tex = (mat.texture rescue nil)
      if tex
        card['texture_width_inches']  = (tex.width rescue nil)
        card['texture_height_inches'] = (tex.height rescue nil)
        file = write_texture(mat, id, dir)
        card['texture_file'] = file if file
      end

      nums = vray_numbers_from_dict(mat)
      nums = vray_numbers(mat) if nums.nil? || nums.empty?
      card['vray'] = nums if nums && !nums.empty?

      path = File.join(dir, "#{id}.json")
      write_atomic(path, JSON.pretty_generate(card))
      path
    end

    def self.colour_of(mat)
      c = (mat.color rescue nil)
      return nil if c.nil?
      [c.red, c.green, c.blue]
    rescue StandardError
      nil
    end

    # Pulls the image out of the model and drops it in textures/<id>.png.
    def self.write_texture(mat, id, dir)
      ext = File.extname((mat.texture.filename rescue '').to_s)
      ext = '.png' if ext.nil? || ext.empty? || ext.length > 5
      out = File.join(dir, 'textures', "#{id}#{ext}")
      tw = Sketchup.create_texture_writer

      # A face carrying the material is the reliable source; the material
      # on its own works too but only through the two-argument write.
      face = find_face_with(Sketchup.active_model, mat)
      if face
        begin
          tw.load(face, true)
          tw.write(face, true, out)
        rescue StandardError => e
          trace(nil, "write via face: #{e.class} #{e.message}")
        end
      end
      unless File.exist?(out)
        begin
          tw.load(mat)
          tw.write(mat, out)
        rescue StandardError => e
          trace(nil, "write via material: #{e.class} #{e.message}")
        end
      end
      # 2026-10-14: no face found and TextureWriter refused the material
      # ("does not support the loading of the passed object type") - the
      # Countertop card was saved with no picture. Texture#write (SU 2021+)
      # writes the image straight from the material.
      unless File.exist?(out)
        begin
          mat.texture.write(out)
        rescue StandardError => e
          trace(nil, "write via texture: #{e.class} #{e.message}")
        end
      end
      return trace(File.join('textures', "#{id}#{ext}"), "texture -> #{out}") if File.exist?(out)
      trace(nil, 'no texture file was written')
    rescue StandardError => e
      trace(nil, "write_texture: #{e.class} #{e.message}")
    end

    def self.find_face_with(model, mat, limit = 20000)
      seen = {}
      walk = lambda do |ents, depth|
        return nil if depth > 6 || limit <= 0
        ents.each do |e|
          limit -= 1
          return nil if limit <= 0
          if e.is_a?(Sketchup::Face)
            return e if e.material == mat || e.back_material == mat
          elsif e.is_a?(Sketchup::Group)
            r = walk.call(e.entities, depth + 1)
            return r if r
          elsif e.is_a?(Sketchup::ComponentInstance)
            d = e.definition
            next if d.nil? || seen[d.entityID]
            seen[d.entityID] = true
            r = walk.call(d.entities, depth + 1)
            return r if r
          end
        end
        nil
      end
      walk.call(model.entities, 0)
    rescue StandardError
      nil
    end

    # Never leave half a file where OneDrive can sync it.
    def self.write_atomic(path, text)
      tmp = "#{path}.tmp"
      File.open(tmp, 'w:UTF-8') { |f| f.write(text) ; f.flush }
      File.delete(path) if File.exist?(path)
      File.rename(tmp, path)
      path
    end

    # ---- reading the library back ------------------------------------
    # THE FOLDERS LIVE IN THE WINDOW, NOT ON THE DISK (2026-09-15).
    # He said it plainly: "כל עניין התיקיות זה צריך להיות בחלון בסקאצאפ
    # ולא במחשב. לא איכפת לי שכל החומרים ישמרו ביחד במחשב אבל כשאני פותח
    # חומר אני רוצה שזה יהיה מסודר" - a tree like
    #     חומרי חוץ / סטאקו , אבנים , לנדסקייפ
    # So every card carries a "path", the files all sit flat in one
    # folder, and the tree itself is kept in folders.json so an empty
    # folder he just made does not vanish.
    FOLDERS_FILE = 'folders.json'.freeze

    def self.folders_path
      f = folder
      f.nil? ? nil : File.join(f, FOLDERS_FILE)
    end

    # Every folder that exists: the ones he made, plus any path a card
    # already uses, plus every parent along the way.
    def self.folders
      out = []
      fp = folders_path
      if fp && File.exist?(fp)
        begin
          out.concat(Array(JSON.parse(File.read(fp, encoding: 'UTF-8'))['folders']))
        rescue StandardError
          nil
        end
      end
      cards.each { |c| out << c['path'].to_s }
      with_parents(out)
    end

    def self.with_parents(list)
      out = []
      list.each do |p|
        next if p.nil? || p.to_s.strip.empty?
        parts = p.to_s.split('/').map { |x| x.strip }.reject(&:empty?)
        parts.each_index { |i| out << parts[0..i].join('/') }
      end
      out.uniq.sort
    end

    def self.save_folders!(list)
      fp = folders_path
      return nil if fp.nil?
      ensure_folder!
      write_atomic(fp, JSON.pretty_generate({ 'folders' => with_parents(list) }))
      list
    end

    def self.add_folder!(path)
      p = clean_path(path)
      return nil if p.empty?
      save_folders!(folders + [p])
      p
    end

    # Removing a folder never deletes a material: its cards move up to
    # the parent. Losing a picture because a folder was tidied away is
    # exactly the kind of thing that would cost him a whole evening.
    def self.remove_folder!(path)
      p = clean_path(path)
      return nil if p.empty?
      parent = p.include?('/') ? p[0...p.rindex('/')] : ''
      cards.each do |c|
        cp = c['path'].to_s
        move!(c['id'], parent) if cp == p || cp.start_with?("#{p}/")
      end
      save_folders!(folders.reject { |f| f == p || f.start_with?("#{p}/") })
      parent
    end

    # Move a whole folder inside another one (right-click in the window).
    # Every card under it follows, and so does every sub-folder. A folder
    # cannot be dropped into itself or into its own child.
    def self.move_folder!(from, to_parent)
      src = clean_path(from)
      dst = clean_path(to_parent)
      return nil if src.empty?
      return nil if dst == src || dst.start_with?("#{src}/")
      name = src.split('/').last
      target = dst.empty? ? name : "#{dst}/#{name}"
      return target if target == src

      cards.each do |c|
        cp = c['path'].to_s
        next unless cp == src || cp.start_with?("#{src}/")
        move!(c['id'], target + cp[src.length..-1].to_s)
      end
      kept = folders.map do |f|
        if f == src || f.start_with?("#{src}/")
          target + f[src.length..-1].to_s
        else
          f
        end
      end
      save_folders!(kept)
      target
    end

    def self.rename_folder!(path, new_name)
      src = clean_path(path)
      nm = new_name.to_s.tr('/\\', '').strip
      return nil if src.empty? || nm.empty?
      parent = src.include?('/') ? src[0...src.rindex('/')] : ''
      target = parent.empty? ? nm : "#{parent}/#{nm}"
      return target if target == src
      cards.each do |c|
        cp = c['path'].to_s
        next unless cp == src || cp.start_with?("#{src}/")
        move!(c['id'], target + cp[src.length..-1].to_s)
      end
      save_folders!(folders.map { |f| (f == src || f.start_with?("#{src}/")) ? target + f[src.length..-1].to_s : f })
      target
    end

    def self.clean_path(path)
      path.to_s.tr('\\', '/').split('/').map { |x| x.strip }.reject(&:empty?).join('/')
    end

    # Move one card to another folder. The file does not move - only the
    # line inside it.
    def self.move!(id, path)
      c = cards.find { |x| x['id'].to_s == id.to_s }
      return nil if c.nil?
      c = c.dup
      file = c.delete('_path')
      c.delete('_folder')
      c['path'] = clean_path(path)
      c['category'] = c['path']
      write_atomic(file, JSON.pretty_generate(c))
      c['path']
    rescue StandardError => e
      trace(nil, "move!: #{e.class} #{e.message}")
    end

    # Rename one material. The file name never changes - it is the id -
    # so only the label he reads moves.
    def self.rename!(id, new_name)
      c = cards.find { |x| x['id'].to_s == id.to_s }
      return nil if c.nil? || new_name.to_s.strip.empty?
      c = c.dup
      file = c.delete('_path')
      c.delete('_folder')
      c['name'] = new_name.to_s.strip
      write_atomic(file, JSON.pretty_generate(c))
      c['name']
    rescue StandardError => e
      trace(nil, "rename!: #{e.class} #{e.message}")
    end

    # Remove one material from the library. The picture goes too, but
    # only if no other card points at it.
    def self.delete!(id)
      c = cards.find { |x| x['id'].to_s == id.to_s }
      return nil if c.nil?
      tex = texture_path(c)
      File.delete(c['_path']) if File.exist?(c['_path'].to_s)
      if tex && File.exist?(tex)
        still = cards.any? { |x| texture_path(x) == tex }
        File.delete(tex) unless still
      end
      true
    rescue StandardError => e
      trace(nil, "delete!: #{e.class} #{e.message}")
    end

    MAX_DEPTH = 4

    def self.cards
      dir = folder
      return [] if dir.nil? || !File.directory?(dir)
      out = []
      Dir.glob(File.join(dir, '**', '*.json')).sort.each do |p|
        rel = p[(dir.length + 1)..-1].to_s.tr('\\', '/')
        next if rel == FOLDERS_FILE
        next if rel.split('/').length > MAX_DEPTH
        next if rel.split('/').first.to_s.downcase == 'textures'
        begin
          c = JSON.parse(File.read(p, encoding: 'UTF-8'))
        rescue StandardError
          next
        end
        next unless c.is_a?(Hash) && c['id']
        sub = File.dirname(rel)
        c['_path'] = p
        # a card that really does sit in a sub-folder on disk keeps that
        # as its path, so nothing he arranged by hand earlier is lost.
        c['path'] = (sub == '.' ? c['path'].to_s : sub)
        c['category'] = c['path']
        out << c
      end
      out
    end

    def self.categories
      folders
    end

    # The picture for a card: next to the card first, then the root.
    def self.texture_path(card)
      f = card['texture_file'].to_s
      return nil if f.empty?
      dir = folder
      return nil if dir.nil?
      here = File.join(File.dirname(card['_path'].to_s), File.basename(f))
      return here if File.exist?(here)
      near = File.join(File.dirname(card['_path'].to_s), f)
      return near if File.exist?(near)
      root = File.join(dir, f)
      return root if File.exist?(root)
      base = File.join(dir, 'textures', File.basename(f))
      File.exist?(base) ? base : nil
    end

    def self.summary
      cs = cards
      return 'התיקייה לא נבחרה עדיין.' if folder.nil?
      "#{cs.length} חומרים ב-#{folder}"
    end
  end
end
