# encoding: utf-8
# Interior Pro <-> Invoice Studio - THE FILE BRIDGE (2026-09-18)
#
# No API, no server. Two sides, one synced folder, two files:
#   rooms.json          the web app writes it, we read it
#   surface_takeoff.csv we write it, the web app reads it
#
# WHAT THE OTHER SIDE PROMISED (its spec, kept here so nobody has to go
# looking for it):
#   - it writes rooms.json atomically, so we never see half a file - but
#     it can be missing or malformed and we must survive that;
#   - projects[].id is a database UUID, globally unique, never changes;
#   - rooms[].id looks like room-0001 and is numbered PER PROJECT, so
#     room-0001 in one project is NOT room-0001 in another. THE KEY IS
#     THE PAIR. Everything here stores both;
#   - a room id never changes and is never reused, even on a rename. So
#     we bind to the id and treat the name as a label that can move;
#   - its importer matches a floor row's `name` to a room name by EXACT
#     string. So a bound room's name is COPIED from rooms.json, never
#     retyped, or the row imports without its room link.
#
# OneDrive syncs with a delay of seconds - nothing here assumes a file
# appears the moment the other side writes it.
#
# Kill switch: USE_SYNC_BRIDGE = false - the folder is never touched.
require 'json'

module InteriorPro
  module SyncBridge
    USE_SYNC_BRIDGE = true unless const_defined?(:USE_SYNC_BRIDGE, false)

    ROOMS_FILE = 'rooms.json'.freeze
    # ONE CSV PER PROJECT (their update, 2026-09-18): the csv has no
    # project column and their importer DELETES and REPLACES every row of
    # one project, so the project's UUID goes in the FILENAME. Their
    # "read from folder" looks for exactly this name and has no fallback
    # to a shared file - on purpose, so one project can never import
    # another's quantities.
    TAKEOFF_PREFIX = 'surface_takeoff_'.freeze
    DEFAULT_FOLDER_NAME = 'InteriorPro'.freeze
    # where the binding lives on a SketchUp room group
    DICT = 'InteriorPro'.freeze
    KEY_PROJECT = 'studio_project_id'.freeze
    KEY_ROOM = 'studio_room_id'.freeze
    KEY_NAME = 'studio_room_name'.freeze
    # remembered per installation, not per model
    PREF_SECTION = 'InteriorPro'.freeze
    PREF_FOLDER = 'sync_folder'.freeze

    # ---- the folder --------------------------------------------------

    # NOTHING IS HARDCODED (their update, 2026-09-18). There is no
    # OneDrive folder under C:\Users\rordt on his machine - a business
    # account gives "OneDrive - <Org>", and it can sit on another drive.
    # The web app lets him pick the folder in a browser; the extension is
    # the only side where a wrong path breaks the bridge in silence. So
    # the path is a SETTING with a picker, and the guesses below are only
    # offered, never assumed.
    #
    # PURE. Folders worth trying, best first, for a home directory.
    def self.candidate_folders(home, entries = nil)
      h = home.to_s
      out = []
      list = entries || (Dir.entries(h) rescue [])
      list.sort.each do |n|
        next unless n.to_s.start_with?('OneDrive')
        out << File.join(h, n, DEFAULT_FOLDER_NAME)
      end
      out << File.join(h, 'OneDrive', DEFAULT_FOLDER_NAME)
      out << File.join(h, 'Documents', DEFAULT_FOLDER_NAME)
      out.uniq
    end

    # The first candidate whose PARENT really exists - we are willing to
    # create InteriorPro inside an existing OneDrive, never to invent a
    # OneDrive that is not there.
    def self.guess_folder(home = nil)
      home ||= home_dir
      candidate_folders(home).find { |c| File.directory?(File.dirname(c)) }
    end

    def self.home_dir
      ENV['USERPROFILE'] || ENV['HOME'] || Dir.home
    rescue StandardError
      ''
    end

    # The folder in use: what he set, else the default. Never created
    # here - see ensure_folder!.
    # What he chose, or nil. NEVER a guess - a guessed path that does not
    # exist is exactly the silent breakage their spec warns about.
    def self.folder
      saved = (Sketchup.read_default(PREF_SECTION, PREF_FOLDER, nil) rescue nil)
      return saved.to_s if saved && !saved.to_s.empty?
      nil
    end

    def self.folder?
      f = folder
      !f.nil? && File.directory?(f)
    end

    # Ask him where it is. Starts at the best guess so the usual case is
    # one click.
    def self.choose_folder!
      start = guess_folder
      start = File.dirname(start) if start && !File.directory?(start)
      picked = UI.select_directory(title: 'Interior Pro <-> Invoice Studio folder',
                                   directory: start)
      return nil if picked.nil? || picked.to_s.empty?
      self.folder = picked.to_s
      picked.to_s
    rescue StandardError => e
      puts "[SyncBridge] choose_folder!: #{e.message}"
      nil
    end

    def self.folder=(path)
      Sketchup.write_default(PREF_SECTION, PREF_FOLDER, path.to_s)
      path.to_s
    end

    def self.ensure_folder!
      d = folder
      if d.nil?
        puts '[SyncBridge] no exchange folder set yet - run choose_folder!'
        return nil
      end
      Dir.mkdir(d) unless File.directory?(d)
      d
    rescue StandardError => e
      puts "[SyncBridge] could not make #{d}: #{e.message}"
      nil
    end

    def self.rooms_path
      d = folder
      d.nil? ? nil : File.join(d, ROOMS_FILE)
    end

    # PURE. The one filename their importer looks for.
    def self.takeoff_name(project_id)
      "#{TAKEOFF_PREFIX}#{project_id}.csv"
    end

    def self.takeoff_path(project_id)
      d = folder
      return nil if d.nil? || project_id.to_s.empty?
      File.join(d, takeoff_name(project_id))
    end

    # Which Studio project this MODEL belongs to. Stored on the model, so
    # it travels with the .skp.
    def self.project_id(model = nil)
      model ||= Sketchup.active_model
      v = model.get_attribute(DICT, KEY_PROJECT).to_s
      v.empty? ? nil : v
    rescue StandardError
      nil
    end

    def self.set_project!(model, id, name = nil)
      model.set_attribute(DICT, KEY_PROJECT, id.to_s)
      model.set_attribute(DICT, 'studio_project_name', name.to_s) if name
      id.to_s
    end

    # ---- reading rooms.json ------------------------------------------

    # PURE. Turn the parsed json into what the pickers need. Anything
    # missing or the wrong shape gives [] rather than an exception - the
    # file is written by another program and we do not control it.
    def self.parse_rooms(data)
      return [] unless data.is_a?(Hash)
      projs = data['projects']
      return [] unless projs.is_a?(Array)
      out = []
      projs.each do |p|
        next unless p.is_a?(Hash)
        pid = p['id'].to_s
        next if pid.empty?
        rooms = []
        list = p['rooms']
        if list.is_a?(Array)
          list.each do |r|
            next unless r.is_a?(Hash)
            rid = r['id'].to_s
            next if rid.empty?
            rooms << { id: rid, name: r['name'].to_s }
          end
        end
        out << { id: pid, name: p['name'].to_s, rooms: rooms }
      end
      out
    end

    # Returns { ok:, projects:, error:, mtime: }. `ok` false with a plain
    # reason is a normal answer here, not a failure to hide.
    def self.read_rooms(path = nil)
      return { ok: false, projects: [], error: 'switched off' } unless USE_SYNC_BRIDGE
      path ||= rooms_path
      if path.nil?
        return { ok: false, projects: [], error: :no_folder }
      end
      unless File.file?(path)
        return { ok: false, projects: [], error: :missing, path: path }
      end
      raw = File.read(path, encoding: 'bom|utf-8')
      data = JSON.parse(raw)
      { ok: true, projects: parse_rooms(data), path: path,
        mtime: (File.mtime(path) rescue nil),
        updated_at: (data['updated_at'] if data.is_a?(Hash)) }
    rescue JSON::ParserError => e
      { ok: false, projects: [], error: :malformed, detail: e.message, path: path }
    rescue StandardError => e
      { ok: false, projects: [], error: :unreadable, detail: e.message, path: path }
    end

    # PURE. Find one room by the PAIR. Never by id alone - room-0001
    # exists in every project.
    def self.find_room(projects, project_id, room_id)
      pr = Array(projects).find { |p| p[:id] == project_id.to_s }
      return nil if pr.nil?
      rm = pr[:rooms].find { |r| r[:id] == room_id.to_s }
      return nil if rm.nil?
      { project_id: pr[:id], project_name: pr[:name],
        room_id: rm[:id], room_name: rm[:name] }
    end

    # ---- binding a SketchUp room to a Studio room --------------------

    def self.bind_room!(group, project_id, room_id, room_name)
      return false if group.nil?
      group.set_attribute(DICT, KEY_PROJECT, project_id.to_s)
      group.set_attribute(DICT, KEY_ROOM, room_id.to_s)
      # the label is COPIED, never retyped - the importer matches it
      # character for character
      group.set_attribute(DICT, KEY_NAME, room_name.to_s)
      group.set_attribute(DICT, 'name', room_name.to_s)
      true
    rescue StandardError => e
      puts "[SyncBridge] bind_room!: #{e.message}"
      false
    end

    def self.binding_of(group)
      return nil if group.nil?
      pid = group.get_attribute(DICT, KEY_PROJECT).to_s
      rid = group.get_attribute(DICT, KEY_ROOM).to_s
      return nil if pid.empty? || rid.empty?
      { project_id: pid, room_id: rid,
        room_name: group.get_attribute(DICT, KEY_NAME).to_s }
    rescue StandardError
      nil
    end

    # A bound room follows its Studio name after a rename there. Returns
    # [how many were refreshed, how many are bound to something that is
    # no longer in the file].
    def self.refresh_names!(model = nil, projects = nil)
      return [0, 0] unless USE_SYNC_BRIDGE
      model ||= Sketchup.active_model
      if projects.nil?
        r = read_rooms
        return [0, 0] unless r[:ok]
        projects = r[:projects]
      end
      moved = 0
      lost = 0
      model.entities.grep(Sketchup::Group).each do |g|
        next unless g.valid?
        next unless g.get_attribute(DICT, 'type').to_s == 'room'
        b = binding_of(g)
        next if b.nil?
        found = find_room(projects, b[:project_id], b[:room_id])
        if found.nil?
          lost += 1
          next
        end
        next if found[:room_name] == b[:room_name]
        bind_room!(g, found[:project_id], found[:room_id], found[:room_name])
        moved += 1
      end
      [moved, lost]
    end

    # ---- the pickers -------------------------------------------------
    # THE NAMES ARE NOT CLEANED (their update, 2026-09-05). Real project
    # names carry a DOUBLE SPACE ("...Hacienda Heights, CA  91745") and a
    # room is called "Bathroom 2 (scond floor)". Both are correct as far
    # as the bridge is concerned - matching is exact, so trimming,
    # collapsing spaces or fixing a typo would silently break the link.
    # Nothing here calls strip, squeeze or capitalize. Ever.

    # PURE. The lines a dropdown shows, and the objects behind them.
    # SketchUp's inputbox separates its choices with "|", so a name
    # holding one is numbered instead of being altered.
    def self.menu_lines(items)
      names = items.map { |i| i[:name].to_s }
      if names.any? { |n| n.include?('|') }
        names.each_with_index.map { |n, i| "#{i + 1}. #{n.tr('|', '/')}" }
      else
        names
      end
    end

    # PURE. Which item a chosen line belongs to - by POSITION, never by
    # comparing the text back, so a numbered or "|"-swapped line still
    # lands on the right object.
    def self.item_for_line(items, line)
      idx = menu_lines(items).index(line.to_s)
      idx.nil? ? nil : items[idx]
    end

    # Pick the project this MODEL belongs to.
    def self.pick_project!(model = nil)
      model ||= Sketchup.active_model
      r = read_rooms
      unless r[:ok]
        UI.messagebox(rooms_problem(r))
        return nil
      end
      projs = r[:projects]
      if projs.empty?
        UI.messagebox('rooms.json has no active projects in it.')
        return nil
      end
      lines = menu_lines(projs)
      cur = project_id(model)
      here = projs.index { |p| p[:id] == cur }
      res = UI.inputbox(['Project'], [lines[here || 0]], [lines.join('|')],
                        'Invoice Studio - which project is this model?')
      return nil unless res
      pr = item_for_line(projs, res[0])
      return nil if pr.nil?
      set_project!(model, pr[:id], pr[:name])
      pr
    rescue StandardError => e
      puts "[SyncBridge] pick_project!: #{e.message}"
      nil
    end

    # Pick the Studio room for one SketchUp room group.
    def self.pick_room!(group, model = nil)
      return nil if group.nil?
      model ||= Sketchup.active_model
      pid = project_id(model)
      if pid.nil?
        UI.messagebox('Pick the project first.')
        return nil
      end
      r = read_rooms
      unless r[:ok]
        UI.messagebox(rooms_problem(r))
        return nil
      end
      pr = r[:projects].find { |p| p[:id] == pid }
      if pr.nil?
        UI.messagebox("This model is linked to a project that is not in " \
                      "rooms.json any more (#{pid}).")
        return nil
      end
      rooms = pr[:rooms]
      if rooms.empty?
        UI.messagebox("#{pr[:name]} has no rooms in rooms.json.")
        return nil
      end
      # SHOW HIM WHICH ROOM HE IS NAMING (2026-09-06, he asked: "how do
      # I know which room"). The group is selected before the dropdown
      # opens, so it is highlighted in the model behind the dialog.
      begin
        model.selection.clear
        model.selection.add(group)
      rescue StandardError
        nil
      end
      lines = menu_lines(rooms)
      b = binding_of(group)
      here = b ? rooms.index { |x| x[:id] == b[:room_id] } : nil
      own = group.get_attribute(DICT, 'name').to_s
      own = 'the highlighted room' if own.empty?
      res = UI.inputbox(['Room'], [lines[here || 0]], [lines.join('|')],
                        "#{own} (highlighted) - which room in #{pr[:name]}?")
      return nil unless res
      rm = item_for_line(rooms, res[0])
      return nil if rm.nil?
      bind_room!(group, pr[:id], rm[:id], rm[:name])
      rm
    rescue StandardError => e
      puts "[SyncBridge] pick_room!: #{e.message}"
      nil
    end

    # PURE. What to tell him when rooms.json will not read.
    def self.rooms_problem(res)
      case res[:error]
      when :no_folder
        'No exchange folder chosen yet. Run SyncBridge.choose_folder!'
      when :missing
        "rooms.json is not in the folder yet:\n#{res[:path]}\n" \
        'Link the folder in Invoice Studio (Settings -> Interior Pro Sync).'
      when :malformed
        "rooms.json is there but is not valid JSON:\n#{res[:detail]}"
      else
        "rooms.json could not be read: #{res[:error]} #{res[:detail]}"
      end
    end

    # ---- the room table ----------------------------------------------
    # He did not want to hunt for groups in the model ("זה פשוט מלא
    # קבוצות" - a room is not one group; its walls and its floor are
    # separate). What he asked for is ONE table: every room in the model
    # on a line, and per line either a room from the chosen Invoice
    # Studio project, or a name he types himself.

    # Every room entity in the model, as the table shows it.
    def self.model_rooms(model = nil)
      model ||= Sketchup.active_model
      out = []
      model.entities.grep(Sketchup::Group).each do |g|
        next unless g.valid?
        next unless g.get_attribute(DICT, 'type').to_s == 'room'
        b = binding_of(g)
        out << { gid: g.get_attribute(DICT, 'id').to_s,
                 name: g.get_attribute(DICT, 'name').to_s,
                 area: g.get_attribute(DICT, 'area_sqft').to_f.round(1),
                 level: g.get_attribute(DICT, 'level').to_i,
                 room_id: (b ? b[:room_id] : nil),
                 group: g }
      end
      out.sort_by { |r| [-r[:area], r[:name]] }
    end

    def self.room_group(model, gid)
      model.entities.grep(Sketchup::Group).find do |g|
        g.valid? && g.get_attribute(DICT, 'type').to_s == 'room' &&
          g.get_attribute(DICT, 'id').to_s == gid.to_s
      end
    end

    # PURE. What one line of the table decides:
    #   :link  - a room was chosen from the project (bind, copy its name)
    #   :name  - he typed a name (no link, his text is the label)
    #   :clear - neither
    def self.choice_kind(room_id, typed)
      return :link unless room_id.to_s.empty?
      return :name unless typed.to_s.empty?
      :clear
    end

    # Apply the whole table. `choices` is [{gid:, room_id:, name:}].
    # Returns [linked, named, cleared].
    def self.apply_choices!(model, choices, projects = nil)
      pid = project_id(model)
      if projects.nil?
        r = read_rooms
        projects = r[:ok] ? r[:projects] : []
      end
      pr = projects.find { |p| p[:id] == pid }
      linked = 0
      named = 0
      cleared = 0
      Array(choices).each do |c|
        g = room_group(model, c[:gid] || c['gid'])
        next if g.nil?
        rid = (c[:room_id] || c['room_id']).to_s
        typed = (c[:name] || c['name']).to_s
        case choice_kind(rid, typed)
        when :link
          rm = pr && pr[:rooms].find { |x| x[:id] == rid }
          next if rm.nil?
          # the name is COPIED from rooms.json, never retyped
          bind_room!(g, pr[:id], rm[:id], rm[:name])
          linked += 1
        when :name
          g.delete_attribute(DICT, KEY_ROOM) rescue nil
          g.delete_attribute(DICT, KEY_NAME) rescue nil
          g.set_attribute(DICT, 'name', typed)
          named += 1
        else
          cleared += 1
        end
      end
      [linked, named, cleared]
    rescue StandardError => e
      puts "[SyncBridge] apply_choices!: #{e.message}"
      [0, 0, 0]
    end

    # Which rooms of the project are already taken by another line - the
    # table greys those out so two model rooms cannot claim one.
    def self.taken_room_ids(rooms, choices, skip_gid = nil)
      Array(choices).each_with_object([]) do |c, acc|
        next if (c[:gid] || c['gid']).to_s == skip_gid.to_s
        rid = (c[:room_id] || c['room_id']).to_s
        acc << rid unless rid.empty?
      end
    end

    def self.highlight!(model, gid)
      g = room_group(model, gid)
      return false if g.nil?
      model.selection.clear
      model.selection.add(g)
      true
    rescue StandardError
      false
    end

    # ---- writing, atomically -----------------------------------------

    # Temp file then rename, for the same reason the other side does it:
    # nobody ever reads half a file. Same folder, so the rename cannot
    # cross a device.
    # PURE. Every line ending becomes CRLF, and one that already is is
    # not doubled.
    def self.crlf(text)
      text.to_s.gsub(/\r\n|\r|\n/, "\r\n")
    end

    def self.write_atomic(path, text)
      dir = File.dirname(path)
      tmp = File.join(dir, ".#{File.basename(path)}.tmp#{Process.pid}")
      File.open(tmp, 'wb') { |f| f.write(text.to_s.encode('UTF-8')) }
      File.delete(path) if File.exist?(path) && Sketchup.platform == :platform_win
      File.rename(tmp, path)
      path
    rescue StandardError => e
      puts "[SyncBridge] write_atomic #{path}: #{e.message}"
      begin
        File.delete(tmp) if tmp && File.exist?(tmp)
      rescue StandardError
        nil
      end
      nil
    end

    # The takeoff, written where the web app reads it.
    def self.export_takeoff!(model = nil)
      return nil unless USE_SYNC_BRIDGE
      model ||= Sketchup.active_model
      return nil unless ensure_folder!
      pid = project_id(model)
      if pid.nil?
        puts '[SyncBridge] this model is not linked to an Invoice Studio ' \
             'project yet - nothing written (their importer needs the ' \
             'project UUID in the filename)'
        return nil
      end
      rows = InteriorPro::SurfaceTakeoff.take(model)
      # CRLF, because their spec asks for it (2026-09-05). The csv is
      # built with plain newlines and converted once, here.
      write_atomic(takeoff_path(pid),
                   crlf(InteriorPro::SurfaceTakeoff.to_csv(rows) + "\n"))
    end
  end
end
