module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
Vector=Struct.new(:x,:y,:z) do
 def length;Math.sqrt(x*x+y*y+z*z);end
 def dot(v);x*v.x+y*v.y+z*v.z;end
 def cross(v);Vector.new(y*v.z-z*v.y,z*v.x-x*v.z,x*v.y-y*v.x);end
end
Frame=Struct.new(:origin,:xaxis,:yaxis,:zaxis)
d={'id'=>'test','kind'=>'doors','width'=>36,'depth'=>24,'height'=>34.5,'flip_x'=>true,'flip_y'=>true}
s={'kitchen_pose'=>{'z'=>120}}
count=0
[0,30,90,180,270].product([-1,1]).each do |angle,hand|
 a=angle*Math::PI/180;x=Vector.new(Math.cos(a),Math.sin(a),0);y=Vector.new(-Math.sin(a)*hand,Math.cos(a)*hand,0)
 frame=Frame.new(Vector.new(80,50,124),x,y,Vector.new(0,0,1))
 result=KitchenLab.unit_pose(d,frame,s)
 [[0,0],[36,0],[0,-24]].each do |u,v|
  actual=KitchenLab::Spatial.cabinet_point(result,u,v,s);expected=[80+x.x*u+y.x*v,50+x.y*u+y.y*v]
  raise 'Native pose differs from 2D' unless actual.zip(expected).all?{|m,n|(m-n).abs<0.00001}
 end
 raise 'Wrong elevation' unless result['z']==4
 raise 'Panel/cabinet dimensions changed' unless result.values_at('width','depth','height')==[36,24,34.5]
 raise 'Roundtrip lost' unless JSON.parse(JSON.generate(result))==result
 count+=1
end
begin
 KitchenLab.unit_pose(d,Frame.new(Vector.new(0,0,0),Vector.new(2,0,0),Vector.new(0,1,0),Vector.new(0,0,1)),s)
 raise 'Scaling accepted'
rescue RuntimeError=>e
 raise unless e.message.include?('support Move')
end
puts "PASS: #{count} native rotations/reflections agree with 2D, elevation and JSON roundtrip; scaling rejected."
