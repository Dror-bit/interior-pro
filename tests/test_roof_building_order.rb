ENV['REAL_ROOMS']='1'
require './sketchup_stub'
require './room_manager'
require './level_manager'
require './roof_manager'
require 'json'
def loop_walls(prefix,points)
 points.each_with_index.map do |pt,i|
  w=Sketchup.active_model.entities.add_group
  finish=points[(i+1)%points.length]
  {'type'=>'wall','id'=>prefix+i.to_s,'start_x'=>pt[0],'start_y'=>pt[1],'end_x'=>finish[0],'end_y'=>finish[1],'thickness'=>5.0,'anchor'=>'bottom-center','height'=>96.0,'base_z'=>0.0,'level'=>1,'wall_category'=>'exterior'}.each{|k,v|w.set_attribute('InteriorPro',k,v)}
  w
 end
end
large=loop_walls('house',[[0,0],[480,0],[480,360],[0,360]])
small=loop_walls('adu',[[840,0],[960,0],[1080,0],[1080,96],[1080,192],[960,192],[840,192],[840,96]])
all=small+large
before=all.map{|w|Marshal.dump(w.instance_variable_get(:@attrs))}
rf=InteriorPro::RoofManager
groups=rf.buildings_of(all)
raise 'Count of walls won over physical building area' unless groups.first.sort_by(&:object_id)==large.sort_by(&:object_id)
raise 'Lost or duplicated a wall' unless groups.flatten.sort_by(&:object_id)==all.sort_by(&:object_id)
raise 'Grouping changed wall attributes' unless before==all.map{|w|Marshal.dump(w.instance_variable_get(:@attrs))}
rf.send(:remove_const,:USE_BUILDING_AREA_ORDER);rf.const_set(:USE_BUILDING_AREA_ORDER,false)
raise 'Kill switch failed' unless rf.buildings_of(all).first.size==8
puts 'PASS roof building area beats wall count, stable ownership, read-only wall data and kill switch'
