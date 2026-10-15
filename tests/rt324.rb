require './sketchup_stub'
require './elevation_tool'
require 'json'
e=InteriorPro::ElevationTool;sc=e.singleton_class
poly=[[0,0],[120,0],[120,100],[0,100]].map{|p|Geom::Point3d.new(*p,0)}
side=e::Side.new('North',poly[3],poly[2],120,Geom::Vector3d.new(0,-1,0),100)
sc.define_method(:sides){|_|[side]}
sc.define_method(:kitchen_island_views){|*_|[]}
sc.define_method(:kitchen_cab){|g|g}
sc.define_method(:kitchen_on){|_,g,*_|g.box}
cab=Struct.new(:kind,:box) do
  def get_attribute(*_);JSON.generate('kind'=>kind);end
end
kit=[[cab.new('doors',[0,36]),'cabinet',nil],[cab.new('doors',[36,60]),'cabinet',nil],[cab.new('wall',[0,30]),'cabinet',nil],[cab.new('wall',[30,60]),'cabinet',nil]]
d=e.kitchen_plan_dimension_rows(poly,kit,0)
raise 'Expected two chains' unless d.size==4
b=d.select{|x|x['cabinet_level']=='base'};u=d.select{|x|x['cabinet_level']=='upper'}
raise 'Base widths' unless b.map{|x|x['t']}==['36"','24"']
raise 'Upper widths' unless u.map{|x|x['t']}==['30"','30"']
raise 'Rows overlap' unless u.first['at']>b.first['at']
raise 'Dimensions not editable kitchen vectors' unless d.all?{|x|x['k']=='f'&&x['g']=='kitchen'&&x['o']=='h'}
e.send(:remove_const,:USE_KITCHEN_PLAN_DIMS);e.const_set(:USE_KITCHEN_PLAN_DIMS,false)
raise 'Kill switch' unless e.kitchen_plan_dimension_rows(poly,kit,0).empty?
puts 'PASS separate upper/base plan chains, actual widths, editable vectors and kill switch'
