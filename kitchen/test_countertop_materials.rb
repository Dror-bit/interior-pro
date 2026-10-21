require 'json'
module KitchenLab; def self.settings; {}; end; end
load File.join(__dir__,'countertop_materials.rb')
module InteriorPro
  module MaterialLibrary
    def self.texture_path(card);card['texture_file'];end
  end
end
card={'id'=>'stone-1','name'=>'Stone','color'=>[210,210,205]}
value=KitchenLab::CountertopMaterials.snapshot(card)
card['name']='Changed later'
raise 'Snapshot aliases library data' unless value['card']['name']=='Stone'
roundtrip=JSON.parse(JSON.generate(value))
raise 'Persistence failed' unless KitchenLab::CountertopMaterials.validate(roundtrip)==value
roundtrip['card']['name']='Tampered'
begin
  KitchenLab::CountertopMaterials.validate(roundtrip)
  raise 'Accepted invalid snapshot'
rescue RuntimeError=>e
  raise unless e.message=='Countertop material snapshot changed'
end
raise unless KitchenLab::CountertopMaterials.validate(nil).nil?
puts 'PASS countertop snapshot, persistence, validation and default'
