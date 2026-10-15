require './sketchup_stub'
require './elevation_tool'
e=InteriorPro::ElevationTool
s=e::Side.new('West',Geom::Point3d.new(0,0,0),Geom::Point3d.new(120,0,0),120,Geom::Vector3d.new(0,1,0),240)
raise 'wall override ignored' unless e.kitchen_view_cut(s,[],0,{'house'=>72,'walls'=>{'West'=>36}})==36
raise 'room override ignored' unless e.kitchen_view_cut(s,[],0,{'house'=>72,'room'=>48})==48
raise 'empty wall fallback' unless e.kitchen_view_cut(s,[],0,nil).nil?
s.instance_variable_set(:@kitchen_island,{depth:27})
raise 'island depth wrong' unless e.kitchen_view_cut(s,[],0,nil)==29
raise 'island manual ignored' unless e.kitchen_view_cut(s,[],0,24)==24
raise 'island marker' unless e.kitchen_island?(s)
s.remove_instance_variable(:@kitchen_island)
raise 'ordinary wall marked island' if e.kitchen_island?(s)
sc=e.singleton_class
sc.define_method(:kitchen_on){|*_|true}
unless defined?(InteriorPro::ElectricalLibrary)
  module InteriorPro::ElectricalLibrary;end
end
InteriorPro::ElectricalLibrary.define_singleton_method(:box_in_frame){|g,*_|[0,36,0,34.5,0,g]}
sc.define_method(:side_frame){|*_|{}}
raise 'deepest cabinet not used' unless e.kitchen_view_cut(s,[[24,'cabinet',nil],[38,'kitchen_unit',nil]],0,nil)==40
s.depth=30
raise 'room depth not capped' unless e.kitchen_view_cut(s,[[38,'cabinet',nil]],0,nil)==29.5
e.send(:remove_const,:USE_KITCHEN_AUTO_DEPTH);e.const_set(:USE_KITCHEN_AUTO_DEPTH,false)
raise 'kill switch ignored' unless e.kitchen_view_cut(s,[[38,'cabinet',nil]],0,nil).nil?
puts 'PASS kitchen automatic depth, per-wall overrides, island depth, room cap and kill switch'
record=[]
sc.define_method(:add_room_sheet!){|paths,title,dims|record << [paths,title];paths.size}
paths=%w[Kitchen_Plan_lines.png Kitchen_West_lines.png Kitchen_IslandFront1_lines.png Kitchen_IslandRight1_lines.png Kitchen_IslandBack1_lines.png Kitchen_IslandLeft1_lines.png]
e.kitchen_add_sheets!(paths,{})
raise 'Wall elevations mixed with island' unless record[0]==[paths.first(2),'Kitchen']
raise 'Island sheet missing' unless record[1]==[paths.last(4),'Kitchen - Island 1']
boxes=e.kitchen_boxes([0.75,1.85,34.5,21.4],[[756,1440],[630,1440],[756,1440],[630,1440]],[[1,2]]*4,0,plan:false)
raise 'Island first elevation shrunk like plan' unless (boxes[0][2]-boxes[2][2]).abs<1e-6
raise 'Island views too small' unless boxes.all?{|b|b[3]>7}
puts 'PASS separate island sheet and equally scaled elevations'
sc.define_method(:dims_for){|*_|[{'k'=>'hi','g'=>'electric','v'=>0.89,'from'=>0.73},{'k'=>'hi','g'=>'electric','v'=>0.89,'from'=>0.90}]}
rows=e.kitchen_island_dims(s,96,[])
raise 'Ceiling dimensions collide' unless (rows[0]['v']-rows[1]['v']).abs>0.08
puts 'PASS island ceiling dimension rows remain separated'
