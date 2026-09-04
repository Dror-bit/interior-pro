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
    TAKEOFF_FILE = 'surface_takeoff.csv'.freeze
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

    # PURE. The default exchange folder for a home directory.
    def self.default_folder(home)
      File.join(home.to_s, 'OneDrive', DEFAULT_FOLDER_NAME)
    end

    def self.home_dir
      ENV['USERPROFILE'] || ENV['HOME'] || Dir.home
    rescue StandardError
      ''
    end

    # The folder in use: what he set, else the default. Never created
    # here - see ensure_folder!.
    def self.folder
      saved = (Sketchup.read_default(PREF_SECTION, PREF_FOLDER, nil) rescue nil)
      return saved.to_s if saved && !saved.to_s.empty?
      default_folder(home_dir)
    end

    def self.folder=(path)
      Sketchup.write_default(PREF_SECTION, PREF_FOLDER, path.to_s)
      path.to_s
    end

    def self.ensure_folder!
      d = folder
      Dir.mkdir(d) unless File.directory?(d)
      d
    rescue StandardError => e
      puts "[SyncBridge] could not make #{folder}: #{e.message}"
      nil
    end

    def self.rooms_path
      File.join(folder, ROOMS_FILE)
    end

    def self.takeoff_path
      File.join(folder, TAKEOFF_FILE)
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

    # ---- writing, atomically -----------------------------------------

    # Temp file then rename, for the same reason the other side does it:
    # nobody ever reads half a file. Same folder, so the rename cannot
    # cross a device.
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
      rows = InteriorPro::SurfaceTakeoff.take(model)
      write_atomic(takeoff_path, InteriorPro::SurfaceTakeoff.to_csv(rows) + "\n")
    end
  end
end
