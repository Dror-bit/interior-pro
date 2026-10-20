# Regression: world-space crown joints with non-unit directions and fitting gaps.
require './geom_stub'
module Geom
  class Vector3d
    def +(o);self.class.new(x+o.x,y+o.y,z+o.z);end
    def -(o);self.class.new(x-o.x,y-o.y,z-o.z);end
    def length=(value);scale=value/length;self.x*=scale;self.y*=scale;self.z*=scale;end
  end
end
load File.expand_path('../kitchen/kitchen_crown.rb',__dir__)
j=KitchenLab::CrownJoints
check=->(value,message) { raise message unless value }
hit=j.line_hit(j.pt(0,0),j.v(24,0),j.pt(0.4,-20),j.v(0,80))
check.call(hit.distance(j.pt(0.4,0))<1e-8,'Non-unit directions changed intersection')
profile=[[0,0],[4,6],[0,6]]
cab=j.segment(j.pt(0,0),j.pt(24,0),j.v(0,1),profile,90,'cab',nil)
house=j.segment(j.pt(0.4,0),j.pt(0.4,80),j.v(1,0),profile,90,nil,nil)
j.resolve!([cab,house])
check.call(cab[:a].distance(house[:a])<1e-8,'House and cabinet ends do not meet')
check.call((cab[:a_offset]-house[:a_offset]).length<1e-8,'Miter planes differ')
profile.each do |d,z|
  a=cab[:a].offset(cab[:a_offset],d*cab[:a_offset].length)
  b=house[:a].offset(house[:a_offset],d*house[:a_offset].length)
  check.call(a.distance(b)<1e-8,'Profile ring has an overlap or gap')
end
other=j.segment(j.pt(24,0),j.pt(24,30),j.v(1,0),profile,80,'other',nil)
j.resolve!([cab,other])
check.call(!other[:a_offset],'Different levels were joined')
different=j.segment(j.pt(24,0),j.pt(24,30),j.v(1,0),[[0,0],[1,6],[0,6]],90,'different',nil)
j.resolve!([cab,different])
check.call(!different[:a_offset],'Different profiles were forced into a miter')
puts 'PASS: shared crown rings, non-unit directions, level and profile isolation.'
