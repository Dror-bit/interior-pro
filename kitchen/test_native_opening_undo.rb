# Uses the existing model double, but calls the production observer and new
# dependency code. The wall owns native holes; its rendered door does not.
load File.join(__dir__,'test_local_opening_sync.rb')
b=KitchenLab::Backsplash
b.send(:remove_const,:USE_LOCAL_OPENING_SIGNATURE);b.const_set(:USE_LOCAL_OPENING_SIGNATURE,true)
InteriorPro::WallTool.const_set(:USE_NATIVE_OPENINGS,true)
m=LocalModel.new
wall=LocalEntity.new(20,'wall',[-5,-5,0],[80,0,96])
wall.attrs.merge!('start_x'=>0,'start_y'=>0,'end_x'=>80,'end_y'=>0,'height'=>96,'thickness'=>5,'door_openings'=>[{t:20,width:24,height:80,floor_offset:0}])
door=LocalEntity.new(21,'door',[8,-5,0],[32,0,80])
door.attrs.merge!('host_wall_id'=>'20','position_along_wall_in'=>20,'width_in'=>24,'height_in'=>80)
m.entities=[wall,door];KitchenLab.instance_variable_set(:@model,m)
baseline=signature(m)
m.set_attribute('KitchenLab','backsplash_opening_signature',baseline)
door.bounds=Bounds.new(Geom::Point3d.new([8,-30,0]),Geom::Point3d.new([45,0,80]))
door.transformation=Transform.new([8,3,0]);door.attrs['leaf_style']='2 Panel Shaker';observer(m)
check(m.starts==0 && signature(m)==baseline,'Door style/half-open body triggered kitchen sync')
# Body replacement during Edit Window must not depend on persistent id.
m.entities.delete(door)
window=LocalEntity.new(22,'window',[8,-5,0],[32,0,80]);window.attrs.merge!(door.attrs).merge!('type'=>'window','id'=>'22')
m.entities<<window;observer(m)
check(m.starts==0,'Regenerated window identity triggered sync')
wall.attrs['door_openings'].first[:width]=30;observer(m)
check(m.starts==1,'Native opening resize was missed')
m.set_attribute('KitchenLab','backsplash_opening_signature',signature(m))
wall.attrs['door_openings'].first[:t]=25;observer(m)
check(m.starts==2,'Native opening move was missed')
m.set_attribute('KitchenLab','backsplash_opening_signature',signature(m))
wall.attrs['door_openings'].clear;observer(m)
check(m.starts==3,'Native opening deletion was missed')
# Existing local-v1 documents migrate in memory: no model attribute/undo write.
wall.attrs['door_openings']=[{t:20,width:24,height:80,floor_offset:0}]
window.attrs['position_along_wall_in']=20
previous=b.opening_signature(m,native:false)
m.set_attribute('KitchenLab','backsplash_opening_signature',previous)
b.prime_opening_signature!(m)
starts=m.starts
window.bounds=Bounds.new(Geom::Point3d.new([8,-50,0]),Geom::Point3d.new([50,0,80]));observer(m)
check(m.starts==starts,'First body edit after local-v1 migration rebuilt kitchen')
check(m.get_attribute('KitchenLab','backsplash_opening_signature')==previous,'Migration wrote model state')
# Do not bless a genuinely changed opening during migration.
previous=b.opening_signature(m,native:false)
m.set_attribute('KitchenLab','backsplash_opening_signature',previous)
b.instance_variable_set(:@opening_baselines,{})
wall.attrs['door_openings'].first[:height]=72
check(b.openings_changed?(m),'Migration hid a real unsynchronized opening change')
# A missing/legacy native host keeps the conservative previous behavior.
m.set_attribute('KitchenLab','backsplash_opening_signature',signature(m))
window.attrs['host_wall_id']='missing'
check(b.openings_changed?(m),'Missing host was silently ignored')
window.attrs['host_wall_id']='20'
# Feature switch returns to exact local-v1 hashing, including rendered bodies.
b.send(:remove_const,:USE_NATIVE_OPENING_DEPENDENCIES);b.const_set(:USE_NATIVE_OPENING_DEPENDENCIES,false)
check(signature(m)==b.opening_signature(m,native:false),'Kill switch did not restore previous signature')
before=signature(m);window.transformation=Transform.new([18,3,0])
check(signature(m)!=before,'Disabled feature still ignored the rendered body')
puts 'PASS: native door/window body edits do not add kitchen Undo operations; native opening resize/move/delete, legacy fallback, safe v1 migration and kill switch remain correct.'
