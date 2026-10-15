module KitchenLab
  module MoldingProfiles
    def self.catalog
      return [] unless defined?(InteriorPro::MoldingLibrary)
      lib=InteriorPro::MoldingLibrary
      lib.crown_names.filter_map do |name|
        pts=lib.crown_profile_by_name(name,12.0)
        next unless pts && pts.length>=3
        bottom=pts.map(&:last).min;left=pts.map(&:first).min
        points=pts.map{|x,z|[x.to_f-left,z.to_f-bottom]}
        next unless points.map(&:last).max>0.001 && points.map(&:first).max>0.001
        {'id'=>'house:'+name,'name'=>name,'points'=>points}
      end
    end
    def self.house_selection
      return {'profile'=>'none','message'=>'No crown molding is applied to this house yet.'} unless defined?(Sketchup) && Sketchup.respond_to?(:active_model)
      rows=Sketchup.active_model.entities.grep(Sketchup::Group).select { |g| g.get_attribute('InteriorPro','type')=='crown' }.map { |g| [g.get_attribute('InteriorPro','profile'),g.get_attribute('InteriorPro','profile_h')] }.uniq
      return {'profile'=>'none','message'=>'No crown molding is applied to this house yet.'} if rows.empty?
      return {'error'=>'The house has different crown moldings. Choose a cabinet profile manually.'} if rows.length>1
      name,height=rows.first;entry=catalog.find { |p| p['name']==name }
      return {'error'=>'The house crown profile is unavailable.'} unless entry
      {'profile'=>entry['id'],'height'=>height.to_f>0.01 ? height.to_f : entry['points'].map(&:last).max,'name'=>name}
    end
    def self.settings(s)
      if s['crown_match_house']
        selection=house_selection;raise selection['error'] if selection['error']
        s['crown_profile']=selection['profile'];s['crown_height']=selection['height'] if selection['height']
      end
      return s unless s['crown_profile'].to_s.start_with?('house:')
      snapshot=s['crown_shape']
      unless snapshot.is_a?(Hash) && snapshot['id']==s['crown_profile']
        snapshot=catalog.find{|p|p['id']==s['crown_profile']}
        raise 'This house molding profile is unavailable.' unless snapshot
        s['crown_shape']=Marshal.load(Marshal.dump(snapshot))
      end
      pts=snapshot['points'];h=Float(s['crown_height'])
      raise 'Invalid molding height' unless h.finite? && h.between?(0.5,12)
      s['crown_depth']=h*pts.map(&:first).max/pts.map(&:last).max
      s
    end
    def self.shape(s)
      pts=s.fetch('crown_shape').fetch('points');factor=s['crown_height']/pts.map(&:last).max
      pts.map{|x,z|[x*factor,z*factor]}
    end
  end
end
