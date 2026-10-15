load File.join(__dir__,'kitchen_molding_profiles.rb')
module InteriorPro
 module MoldingLibrary
  def self.crown_names;['Test crown'];end
  def self.crown_profile_by_name(name,height);[[0,10],[1,10],[2,12],[0,12]];end
 end
end
entry=KitchenLab::MoldingProfiles.catalog.first
raise 'Not normalized' unless entry['points'].map(&:last).min==0
s=KitchenLab::MoldingProfiles.settings({'crown_profile'=>entry['id'],'crown_height'=>4})
raise 'Wrong proportional depth' unless s['crown_depth']==4
raise 'Wrong shape' unless KitchenLab::MoldingProfiles.shape(s).map(&:last).max==4
saved=Marshal.load(Marshal.dump(s))
module InteriorPro::MoldingLibrary
 def self.crown_names;[];end
end
raise 'Saved selection lost' unless KitchenLab::MoldingProfiles.settings(saved)==s
begin;KitchenLab::MoldingProfiles.settings({'crown_profile'=>'house:missing','crown_height'=>4});raise 'Missing profile accepted';rescue RuntimeError=>e;raise if e.message=='Missing profile accepted';end
puts 'PASS shared catalog, proportional dimensions, persistent snapshot, missing profile rejection'
