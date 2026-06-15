# Interior Pro - Window Types Library
# Stores ONLY a list of window type names (strings).
# Window parameters are entered fresh each time in the dialog.

require 'json'

module InteriorPro
  module WindowLibrary

    LIBRARY_FILE = File.join(ENV['APPDATA'] || ENV['HOME'], 'InteriorPro', 'window_types.json')

    BUILT_IN_TYPES = ['Single Hung', 'Double Hung', 'Slider', 'Casement', 'Picture'].freeze

    def self.ensure_dir
      dir = File.dirname(LIBRARY_FILE)
      Dir.mkdir(dir) unless Dir.exist?(dir)
    end

    def self.load_custom
      return [] unless File.exist?(LIBRARY_FILE)
      data = JSON.parse(File.read(LIBRARY_FILE))
      data.is_a?(Array) ? data : []
    rescue
      []
    end

    def self.save_custom(types)
      ensure_dir
      File.write(LIBRARY_FILE, JSON.pretty_generate(types))
    end

    def self.all_types
      BUILT_IN_TYPES + load_custom
    end

    def self.add_custom(name)
      name = name.to_s.strip
      return all_types if name.empty?
      return all_types if all_types.include?(name)
      custom = load_custom
      custom << name
      save_custom(custom)
      all_types
    end

  end
end
