# Interior Pro - Window Library

require 'json'

module InteriorPro
  module WindowLibrary

    LIBRARY_FILE = File.join(ENV['APPDATA'] || ENV['HOME'], 'InteriorPro', 'window_library.json')

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

    def self.add(window_type)
      library = load
      library << window_type
      save(library)
      library
    end

    def self.update(index, window_type)
      library = load
      library[index] = window_type
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
