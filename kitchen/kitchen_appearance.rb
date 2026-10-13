# Explicit appearance inheritance. Resolved legacy fields remain usable by builders.
module KitchenLab
  module Appearance
    def self.appliance?(d);%w[fridge oven wall_oven dishwasher hood microwave].include?(d['kind']);end
    def self.overrides(d)
      # Existing designs have no linkage metadata: preserve their exact appearance.
      d.fetch('appearance_overrides') { d.slice('finish','handle') }
    end
    def self.resolve(d,s)
      return PanelReady.resolve(d,s) if defined?(PanelReady) && PanelReady.appliance?(d)
      return d if appliance?(d)
      o=overrides(d)
      raise 'Invalid appearance overrides' unless o.is_a?(Hash) && (o.keys-%w[finish handle]).empty?
      raise 'Invalid custom cabinet color' if o.key?('finish') && !%w[ivory sage charcoal oak].include?(o['finish'])
      raise 'Invalid custom handles' if o.key?('handle') && !%w[brass black none].include?(o['handle'])
      finish=s.fetch('global_finish','');finish='ivory' if finish.empty?
      color=s.fetch('global_handle_color','');color='brass' if color.empty?
      handle=s['global_handle_type']=='none' ? 'none' : color
      resolved=d.merge('appearance_overrides'=>o.dup,'finish'=>o.fetch('finish',finish),'handle'=>o.fetch('handle',handle))
      resolved['handle']='none' if %w[filler corner].include?(d['kind'])
      resolved
    end
    def self.edit(old,changes,s)
      d=old.merge(changes)
      unless changes.key?('appearance_overrides')
        o=overrides(old).dup
        %w[finish handle].each { |key| o[key]=changes[key] if changes.key?(key) && changes[key]!=old[key] }
        d['appearance_overrides']=o
      end
      resolve(d,s)
    end
  end
end
