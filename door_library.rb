# Interior Pro - Door Types Library
# Built-in types per category; custom type names persisted per category.

require 'json'

module InteriorPro
  module DoorLibrary

    %i[
      EXTERIOR_TYPES INTERIOR_TYPES BUILT_IN_BY_CATEGORY
      EXTERIOR_CASING_STYLES INTERIOR_CASING_STYLES CASING_LEGACY_MAP CATEGORY_DEFAULTS
    ].each { |c| remove_const(c) if const_defined?(c, false) }

    LIBRARY_FILE = File.join(ENV['APPDATA'] || ENV['HOME'], 'InteriorPro', 'door_types.json')

    EXTERIOR_TYPES = ['Sliding', 'French Sliding', 'French Hinged'].freeze
    INTERIOR_TYPES = ['Single', 'Double', 'Sliding', 'Pocket', 'French Hinged'].freeze

    BUILT_IN_BY_CATEGORY = {
      'exterior' => EXTERIOR_TYPES,
      'interior' => INTERIOR_TYPES
    }.freeze

    EXTERIOR_CASING_STYLES = %w[none kb103 kb106 kb117].freeze
    INTERIOR_CASING_STYLES = %w[
      none flat ranch colonial stafford windsor belly
      bm325 bm400 bm325_bevel bm425 bm388_ogee bm525_cove
    ].freeze

    CASING_LEGACY_MAP = {
      'brick_mold' => 'kb106',
      'flat'       => 'flat'
    }.freeze

    CATEGORY_DEFAULTS = {
      'exterior' => {
        'door_category'          => 'exterior',
        'door_type'              => 'French Hinged',
        'width'                  => 60.0,
        'height'                 => 80.0,
        'frame_width'            => 1.5,
        'glass_frame_width'      => 5.0,
        'interior_depth'         => 1.0,
        'floor_offset'           => 0.0,
        'swing_direction'        => 'left',
        'swing_side'             => 'auto',
        'slide_direction'        => 'left',
        'glass_grid_style'       => '2x2',
        'exterior_casing_style'  => 'none',
        'interior_casing_style'  => 'none',
        'exterior_threshold'     => true
      },
      'interior' => {
        'door_category'          => 'interior',
        'door_type'              => 'Single',
        'width'                  => 32.0,
        'height'                 => 80.0,
        'frame_width'            => 1.5,
        'glass_frame_width'      => 3.0,
        'interior_depth'         => 1.0,
        'floor_offset'           => 0.0,
        'swing_direction'        => 'left',
        'swing_side'             => 'auto',
        'slide_direction'        => 'left',
        'glass_grid_style'       => 'none',
        'exterior_casing_style'  => 'none',
        'interior_casing_style'  => 'none',
        'exterior_threshold'     => false
      }
    }.freeze

    def self.ensure_dir
      dir = File.dirname(LIBRARY_FILE)
      Dir.mkdir(dir) unless Dir.exist?(dir)
    end

    def self.normalize_category(category)
      category.to_s == 'interior' ? 'interior' : 'exterior'
    end

    def self.normalize_casing_style(settings, side)
      key = "#{side}_casing_style"
      legacy = "#{side}_casing"
      styles = side == 'exterior' ? EXTERIOR_CASING_STYLES : INTERIOR_CASING_STYLES

      if settings[key] && !settings[key].to_s.empty?
        style = settings[key].to_s
        mapped = CASING_LEGACY_MAP[style] || style
        return mapped if styles.include?(mapped)
      end

      settings[legacy] ? 'flat' : 'none'
    end

    def self.defaults_for(category)
      CATEGORY_DEFAULTS[normalize_category(category)]
    end

    def self.built_in_types(category)
      BUILT_IN_BY_CATEGORY[normalize_category(category)] || EXTERIOR_TYPES
    end

    def self.load_custom_by_category
      return { 'exterior' => [], 'interior' => [] } unless File.exist?(LIBRARY_FILE)
      data = JSON.parse(File.read(LIBRARY_FILE))
      if data.is_a?(Array)
        { 'exterior' => data, 'interior' => [] }
      elsif data.is_a?(Hash)
        {
          'exterior' => (data['exterior'] || []).dup,
          'interior' => (data['interior'] || []).dup
        }
      else
        { 'exterior' => [], 'interior' => [] }
      end
    rescue
      { 'exterior' => [], 'interior' => [] }
    end

    def self.save_custom_by_category(custom)
      ensure_dir
      File.write(LIBRARY_FILE, JSON.pretty_generate(custom))
    end

    def self.all_types(category = 'exterior')
      cat = normalize_category(category)
      built_in_types(cat) + load_custom_by_category[cat]
    end

    def self.add_custom(name, category = 'exterior')
      cat = normalize_category(category)
      name = name.to_s.strip
      return all_types(cat) if name.empty?

      custom = load_custom_by_category
      return all_types(cat) if custom[cat].include?(name)

      custom[cat] << name
      save_custom_by_category(custom)
      all_types(cat)
    end

    # Backward compatibility for any code calling all_types without category.
    def self.all_types_legacy
      all_types('exterior')
    end

  end
end
