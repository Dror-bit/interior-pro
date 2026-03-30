# Interior Pro - Wall Library

require 'json'

module InteriorPro
  module WallLibrary

    LIBRARY_FILE = File.join(ENV['APPDATA'] || ENV['HOME'], 'InteriorPro', 'wall_library.json')

    def self.ensure_dir
      dir = File.dirname(LIBRARY_FILE)
      Dir.mkdir(dir) unless Dir.exist?(dir)
    end

    def self.load
      return [] unless File.exist?(LIBRARY_FILE)
      JSON.parse(File.read(LIBRARY_FILE), symbolize_names: false)
    rescue
      []
    end

    def self.save(library)
      ensure_dir
      File.write(LIBRARY_FILE, JSON.pretty_generate(library))
    end

    def self.add(wall_type)
      library = load
      library << wall_type
      save(library)
      library
    end

    def self.update(index, wall_type)
      library = load
      library[index] = wall_type
      save(library)
      library
    end

    def self.delete(index)
      library = load
      library.delete_at(index)
      save(library)
      library
    end

  end
end
