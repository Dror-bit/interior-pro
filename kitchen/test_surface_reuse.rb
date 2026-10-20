require 'json'
load File.join(__dir__,'kitchen_continuous_surfaces.rb')
j=KitchenLab::ContinuousSurfaces
base={'id'=>'base','kind'=>'doors','box'=>[[0,0,0],[36,24,35]]}
fridge={'id'=>'fridge','kind'=>'fridge','box'=>[[100,100,0],[130,130,90]]}
upper={'id'=>'upper','kind'=>'wall','surround_for'=>'fridge','box'=>[[100,100,80],[130,130,90]]}
doc=->(rows,settings={}){{'cabinets'=>rows,'settings'=>settings}}
surfaces=[{owners:['base'],box:[[0,0,35],[36,24,55]]}]
check=->(a,b){j.isolated_changes?(a,b,surfaces){|d|d.fetch('box')}}
raise 'Remote fridge deletion rebuilds surfaces' unless check.call(doc.call([base,fridge,upper]),doc.call([base]))
raise 'Remote addition rebuilds surfaces' unless check.call(doc.call([base]),doc.call([base,fridge,upper]))
near=fridge.merge('box'=>[[35,0,0],[60,24,90]])
raise 'Nearby deletion skipped' if check.call(doc.call([base,near]),doc.call([base]))
raise 'Move toward backsplash skipped' if check.call(doc.call([base,fridge]),doc.call([base,near]))
raise 'Move away from backsplash skipped' if check.call(doc.call([base,near]),doc.call([base,fridge]))
raise 'Base deletion skipped' if check.call(doc.call([base]),doc.call([]))
raise 'Hood change skipped' if check.call(doc.call([base,fridge.merge('kind'=>'hood')]),doc.call([base]))
raise 'Material change skipped' if check.call(doc.call([base,fridge]),doc.call([base],{'countertop_material'=>'new'}))
raise 'Microwave support change skipped' if check.call(doc.call([base,fridge.merge('kind'=>'microwave'),upper]),doc.call([base,fridge.merge('kind'=>'microwave')]))
raise 'Missing surfaces skipped' if j.isolated_changes?(doc.call([fridge]),doc.call([]),[]){|d|d['box']}
raise 'Unknown kind skipped' if check.call(doc.call([base,fridge.merge('kind'=>'future_appliance')]),doc.call([base]))
puts 'PASS isolated surface reuse: remote add/delete, nearby add/delete/move, producer, hood, settings, microwave supports, missing surfaces, unknown kind'
