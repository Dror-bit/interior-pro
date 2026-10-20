# Crown envelope joins apply to products and rotations, not one cabinet ID.
require './geom_stub'
module Geom
  def self.point_in_polygon_2D(p,polygon,border)
    inside=false
    polygon.each_with_index do |a,i|
      b=polygon[(i+1)%polygon.length]
      if (a.y>p.y)!=(b.y>p.y) && p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x
        inside=!inside
      end
    end
    inside
  end
end
load File.expand_path('../kitchen/kitchen_crown.rb',__dir__)
module KitchenLab
  FINISHES={'ivory'=>'ivory'} unless const_defined?(:FINISHES,false)
  def self.material(name,color);color;end
  def self.cabinet_transform(d);d.fetch('test_transform');end
end
j=KitchenLab::CrownJoints
assert=->(condition,message){raise message unless condition}
s={'crown_profile'=>'crown','crown_height'=>6.0,'crown_depth'=>4.5,'crown_color'=>'cabinet'}
cab=->(id,x,y,angle,depth=24,height=90) do
  t=Geom::Transformation.new(Geom::Point3d.new(x,y,0),[Math.cos(angle),-Math.sin(angle),Math.sin(angle),Math.cos(angle)])
  {'id'=>id,'kind'=>'wall','width'=>30,'depth'=>depth,'height'=>height,'finish'=>'ivory','test_transform'=>t}
end
[0,Math::PI/2,Math::PI,0.4].each do |angle|
  a=cab.call('left',0,0,angle)
  b=cab.call('right',33*Math.cos(angle),33*Math.sin(angle),angle,23)
  bridges,connectors=j.close_crown_gaps([a,b],s,[])
  assert.call(bridges.length==1,'Small fitting gap was not joined')
  assert.call(connectors.length==1,'Back edge gained an unwanted crown')
  runs=j.kitchen_runs([a,b],s,bridges)
  merged=j.merge_straight_runs(runs+connectors)
  assert.call(merged.length<runs.length+connectors.length,'Short connector was not merged with its straight neighbor')
end
a=cab.call('a',0,0,0)
b=cab.call('b',45,0,0)
assert.call(j.close_crown_gaps([a,b],s,[]).first.empty?,'Large opening was bridged')
b=cab.call('b',33,0,0,24,84)
assert.call(j.close_crown_gaps([a,b],s,[]).first.empty?,'Different molding heights were bridged')
b=cab.call('b',33,0,0)
assert.call(j.close_crown_gaps([a,b],s.merge('crown_profile'=>'flat','crown_depth'=>0.75),[]).first.empty?,'Flush flat molding was extended across a gap')
assert.call(j.close_crown_gaps([a],s,[]).first.empty?,'Single cabinet changed')
puts 'PASS: crown gap envelope, stepped depths, rotated placements, straight-run merge, height and gap isolation, flush flat crown.'
