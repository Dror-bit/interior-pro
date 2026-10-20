# Shared cabinet data and section layout. Pure Ruby; no SketchUp or kitchen globals.
require 'json'

module InteriorPro
  module Cabinetry
    VERSION = 1 unless const_defined?(:VERSION, false)
    # Product domains are storage namespaces, not separate toolbar tools.
    remove_const(:DOMAINS) if const_defined?(:DOMAINS, false)
    DOMAINS = %w[laundry wardrobe vanity].freeze
    remove_const(:TOOL_DOMAINS) if const_defined?(:TOOL_DOMAINS, false)
    TOOL_DOMAINS = {'storage'=>%w[laundry wardrobe].freeze,
                    'vanity'=>%w[vanity].freeze}.freeze
    module_function

    def domains_for_tool(tool)
      raise ArgumentError, 'Unknown cabinet tool' unless TOOL_DOMAINS.key?(tool)
      TOOL_DOMAINS.fetch(tool).dup
    end

    def tool_for_domain(domain)
      domain!(domain)
      TOOL_DOMAINS.find { |_, domains| domains.include?(domain) }.first
    end

    def copy(value)
      JSON.parse(JSON.generate(value))
    end

    def identifier!(value)
      raise ArgumentError, 'Invalid identifier' unless value.is_a?(String) && value.match?(/\A[a-zA-Z0-9_-]{1,64}\z/)
      value
    end

    def domain!(domain)
      raise ArgumentError, 'Unknown cabinet tool' unless DOMAINS.include?(domain)
      domain
    end

    def number!(value, positive: false)
      raise ArgumentError, 'Expected a finite dimension' unless value.is_a?(Numeric) && value.finite?
      raise ArgumentError, 'Dimension must be positive' if positive && value <= 0
      value
    end

    def create(domain:, assembly_id:, settings: {})
      validate({'schema_version'=>VERSION, 'units'=>'inches', 'domain'=>domain,
        'assembly_id'=>assembly_id, 'revision'=>0, 'settings'=>settings, 'cabinets'=>[]})
    end

    def validate(source)
      d = copy(source)
      raise ArgumentError, 'Unsupported cabinet document' unless d.is_a?(Hash) && d['schema_version']==VERSION && d['units']=='inches'
      domain!(d['domain']); identifier!(d['assembly_id'])
      raise ArgumentError, 'Invalid revision' unless d['revision'].is_a?(Integer) && d['revision']>=0
      raise ArgumentError, 'Invalid settings or cabinets' unless d['settings'].is_a?(Hash) && d['cabinets'].is_a?(Array)
      ids = d['cabinets'].map do |c|
        raise ArgumentError, 'Invalid cabinet' unless c.is_a?(Hash)
        identifier!(c['id']); identifier!(c['product_id'])
        %w[width height depth].each { |k| number!(c[k], positive:true) }
        position = c['position']
        raise ArgumentError, 'Missing placement' unless position.is_a?(Hash)
        %w[x y z angle].each { |k| number!(position[k]) }
        sections = c.fetch('sections',[])
        raise ArgumentError, 'Invalid sections' unless sections.is_a?(Array)
        section_ids = sections.map do |s|
          raise ArgumentError, 'Invalid section' unless s.is_a?(Hash)
          identifier!(s['id']); identifier!(s['kind']); number!(s['height'],positive:true)
          s['id']
        end
        raise ArgumentError, 'Duplicate section IDs' unless section_ids.uniq==section_ids
        raise ArgumentError, 'Sections exceed cabinet height' if sections.sum { |s|s['height'] }>c['height']+1e-6
        c['id']
      end
      raise ArgumentError, 'Duplicate cabinet IDs' unless ids.uniq==ids
      d
    end

    # Nominal sections include reveals. Four drawers in 28 inches are 7 inches each.
    # Renderers subtract reveals from faces, never from editable nominal heights.
    def divide(height, count, step:0.125)
      number!(height,positive:true); number!(step,positive:true)
      raise ArgumentError, 'Invalid division count' unless count.is_a?(Integer) && count.between?(1,100)
      ticks = (height/step).round
      raise ArgumentError, 'Height must match the selected increment' if (ticks*step-height).abs>1e-6
      raise ArgumentError, 'Sections are too small' if ticks<count
      base, remainder = ticks.divmod(count)
      Array.new(count) { |i| (base+(i<remainder ? 1 : 0))*step }
    end

    # Section order is bottom to top. Exact nominal dimensions are preserved.
    def section_layout(sections, start:0, reveal:0.125)
      number!(start); number!(reveal)
      raise ArgumentError, 'Negative reveal' if reveal<0
      z=start
      sections.map do |s|
        h=number!(s.fetch('height'),positive:true)
        raise ArgumentError, 'Reveal consumes section' if reveal>=h
        row={'id'=>s.fetch('id'),'bottom'=>z,'height'=>h,'top'=>z+h,
             'face_bottom'=>z+reveal/2.0,'face_height'=>h-reveal}
        z+=h
        row
      end
    end

    # Pure edit batch; each tool supplies its product and collision validator.
    # Nothing is saved or built until the whole candidate passes validation.
    def plan(source, commands, expected_revision:, validator:)
      before=validate(source)
      raise ArgumentError, 'Design changed; refresh first' unless before['revision']==expected_revision
      raise ArgumentError, 'Provide 1-100 commands' unless commands.is_a?(Array) && commands.length.between?(1,100)
      d=copy(before)
      commands.each do |command|
        case command.fetch('type')
        when 'add'
          d['cabinets'] << copy(command.fetch('cabinet'))
        when 'update'
          c=d['cabinets'].find { |v|v['id']==command.fetch('id') }
          raise ArgumentError, 'Cabinet not found' unless c
          changes=copy(command.fetch('changes'))
          raise ArgumentError, 'Identity cannot be edited' unless changes.is_a?(Hash) && (changes.keys & %w[id product_id]).empty?
          c.merge!(changes)
        when 'remove'
          raise ArgumentError, 'Cabinet not found' unless d['cabinets'].reject! { |c|c['id']==command.fetch('id') }
        when 'settings'
          changes=copy(command.fetch('changes'))
          raise ArgumentError, 'Invalid settings' unless changes.is_a?(Hash)
          d['settings'].merge!(changes)
        else
          raise ArgumentError, 'Unknown edit command'
        end
      end
      d=validate(d)
      raise ArgumentError, 'Product or placement validation failed' unless validator.call(copy(d))
      d['revision']+=1 if d!=before
      d
    end
  end
end
