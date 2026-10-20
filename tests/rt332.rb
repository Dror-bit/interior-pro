# Baseboard endpoints follow cabinet bodies, including nested/rotated units.
require 'json'
require './sketchup_stub'
require './molding_tool'
b = InteriorPro::MoldingBuilder
m = Sketchup.active_model
unit = m.entities.add_group
unit.set_attribute('KitchenLab','kind','kitchen_unit')
unit.transformation = Geom::Transformation.translation(Geom::Vector3d.new(100,200,0))
cab = unit.entities.add_group
cab.set_attribute('KitchenLab','kind','cabinet')
cab.set_attribute('KitchenLab','data', {width:30,depth:24,height:90}.to_json)
cab.transformation = Geom::Transformation.rotation(Geom::Point3d.new,Geom::Vector3d.new(0,0,1),Math::PI/2)
crown = unit.entities.add_group
crown.set_attribute('KitchenLab','kind','crown')
rows = b.baseboard_cabinet_stoppers
raise 'Includes crown or duplicates' unless rows.length == 1
xs,ys,zs = [:x,:y,:z].map { |axis| rows[0][:pts].map { |p|p.send(axis) }.minmax }
raise 'Lost nested transform or body dimensions' unless [xs,ys,zs].flatten.zip([100,124,200,230,0,90]).all? { |a,c|(a-c).abs<0.0001 }
wall = Object.new
def wall.get_attribute(d,k,default=nil); k=='base_z' ? 0.0 : default; end
def wall.transformation; Geom::Transformation.new; end
geo = {p0:Geom::Point3d.new(100,0,0),u:Geom::Vector3d.new(0,1,0),nd:Geom::Vector3d.new(1,0,0),len:400.0}
original = [{kind: :cab,pts: [96,128].product([196,234],[0,96]).map { |a|Geom::Point3d.new(*a) }}]
b.instance_variable_set(:@stoppers,original)
old = b.stop_gaps(wall,geo,0,6)
fresh = b.baseboard_stop_gaps(wall,geo,0,6)
raise 'Original crown envelope fixture missing' unless old[0][:a]==196
raise 'Baseboard not seated against body' unless fresh[0][:a]==200 && fresh[0][:b]==230
raise 'Leaked cache into crown' unless b.instance_variable_get(:@stoppers).equal?(original)
raise 'Changed crown clipping' unless b.stop_gaps(wall,geo,90,95)==old
puts 'PASS: nested rotated cabinet body, crown exclusion, exact baseboard contact, crown cache isolation.'
