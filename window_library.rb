# Interior Pro - Window Types Library
# Stores ONLY a list of window type names (strings).
# Window parameters are entered fresh each time in the dialog.

require 'json'

module InteriorPro
  module WindowLibrary

    LIBRARY_FILE = File.join(ENV['APPDATA'] || ENV['HOME'], 'InteriorPro', 'window_types.json')

    # Casement first: it is the only type with a real built body. The others cut
    # the opening (native) but still need per-style body geometry built.
    BUILT_IN_TYPES = [
      'Casement', 'Casement XX',
      'Single Hung',
      'XOX Single Hung',
      'Slider XO', 'Slider XOX',
      'Garden Window',
      'Arched'
    ].freeze

    # Default unit (frame) size + frame depth per type, in inches (Milgard ref).
    # Used to prefill the dialog when a type is selected.
    PRESETS = {
      'Casement'       => { 'width' => 24, 'height' => 48, 'frame_depth' => 3.25 },
      'Casement XX'    => { 'width' => 48, 'height' => 48, 'frame_depth' => 3.25 },
      'Single Hung'    => { 'width' => 24, 'height' => 36, 'frame_depth' => 3.25 },
      'XOX Single Hung' => { 'width' => 96, 'height' => 48, 'frame_depth' => 3.25 },
      'Single Hung XL' => { 'width' => 36, 'height' => 60, 'frame_depth' => 3.25 },
      'Double Hung'    => { 'width' => 32, 'height' => 48, 'frame_depth' => 3.25 },
      'Slider XO'      => { 'width' => 48, 'height' => 36, 'frame_depth' => 3.25 },
      'Slider XOX'     => { 'width' => 72, 'height' => 48, 'frame_depth' => 3.25 },
      'Awning'         => { 'width' => 36, 'height' => 24, 'frame_depth' => 3.25 },
      'Picture'        => { 'width' => 60, 'height' => 48, 'frame_depth' => 3.25 },
      'Garden Window'  => { 'width' => 60, 'height' => 48, 'frame_depth' => 3.25 },
      'Arched'         => { 'width' => 36, 'height' => 60, 'frame_depth' => 3.25 }
    }.freeze

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
