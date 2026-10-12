# Kitchen data contract. No SketchUp, window, or geometry dependencies.
require 'json'

module KitchenLab
  module Document
    VERSION = 1 unless const_defined?(:VERSION, false)

    def self.create(settings, cabinets, revision = 0)
      read(JSON.generate({'schema_version'=>VERSION, 'units'=>'inches',
        'revision'=>revision, 'settings'=>settings, 'cabinets'=>cabinets}))
    end

    def self.read(json)
      d=JSON.parse(json)
      raise 'Unsupported kitchen document version' unless d.is_a?(Hash) && d['schema_version']==VERSION
      raise 'Unsupported kitchen units' unless d['units']=='inches'
      raise 'Invalid kitchen revision' unless d['revision'].is_a?(Integer) && d['revision']>=0
      raise 'Invalid kitchen document' unless d['settings'].is_a?(Hash) && d['cabinets'].is_a?(Array)
      ids=d['cabinets'].map do |c|
        raise 'Invalid cabinet record' unless c.is_a?(Hash) && c['id'].is_a?(String) && c['id'].match?(/\A[a-zA-Z0-9-]{1,64}\z/)
        c['id']
      end
      raise 'Duplicate cabinet IDs' unless ids.uniq.length==ids.length
      d
    end

    def self.state(d)
      {'revision'=>d['revision'],'settings'=>d['settings'], 'cabinets'=>d['cabinets'].sort_by { |c| [c['x'],c['z']] }}
    end
  end
end
