module Sketchup; class ModelObserver; end; end
require_relative 'kitchen_lab'
# A document command must not ask a live model for its settings. In particular
# a preview for one kitchen must not use another open kitchen's countertop.
module KitchenLab
 def self.settings; raise 'Read active model settings while validating a document'; end
end
product=KitchenLab::Accessories.catalog['products'].find{|p|p['role']=='main' && p['mount']!='wall'}
raise 'Missing deck faucet fixture' unless product
[1.5,2.75].each do |thickness|
 source=KitchenLab::Document.create({'shaker_width'=>2.25,'shaker_inset'=>0.25,'countertop_thickness'=>thickness},[])
 raw={'type'=>'create_cabinet','payload'=>{'kind'=>'sink','overrides'=>{'accessories'=>[{'id'=>'doc-faucet','product_id'=>product['id']}]}}}
 doc=KitchenLab.command_engine.plan(source,[raw])['document']
 cabinet=doc['cabinets'].first
 anchor=cabinet['accessories'].first['anchor']
 raise 'Used another document countertop thickness' unless (anchor[2]-cabinet['height']-thickness).abs<0.0001
 raise 'Document source mutated' unless source['cabinets'].empty?
 raise 'Saved faucet moved on load' unless KitchenLab::Document.read(JSON.generate(doc))==doc
end
puts 'PASS accessory anchors use the supplied document, custom countertop thickness, no bound model, source immutability and save/load'
