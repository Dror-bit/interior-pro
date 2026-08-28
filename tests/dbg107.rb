require './sketchup_stub'
require './roof_tile_math'
require './roof_tile_parts'
require './roof_tile_place'
RTM=InteriorPro::RoofTileMath; PLACE=InteriorPro::RoofTilePlace
NRM=[0.0,-1.0/3.0,1.0]
FACE=[[0.0,0.0,100.0],[200.0,0.0,100.0],[200.0,90.0,130.0],[0.0,90.0,130.0]]
HOLE=[[80.0,30.0,110.0],[120.0,30.0,110.0],[120.0,60.0,120.0],[80.0,60.0,120.0]]
class SV; def initialize(p);@p=Geom::Point3d.new(p[0],p[1],p[2]);end; def position;@p;end; end
class SL; def initialize(p,o);@p=p;@o=o;end; def outer?;@o;end; def vertices;@p.map{|x|SV.new(x)};end; end
class HF
  def initialize(o,h,n);@o=o;@h=h;@n=Geom::Vector3d.new(n[0],n[1],n[2]);end
  def normal;@n;end
  def outer_loop;SL.new(@o,true);end
  def loops;[SL.new(@o,true)]+@h.map{|x|SL.new(x,false)};end
  def vertices;(@o+@h.flatten(1)).map{|p|SV.new(p)};end
end
holed=PLACE.planes_from_faces([HF.new(FACE,[HOLE],NRM)])
after=PLACE.run_slots(holed,'slate')
pu=RTM.plane_uv(holed[0][:points],holed[0][:n])
huv=HOLE.map{|p|RTM.project(p,pu[:origin],pu[:u],pu[:v])}
hu=huv.map{|p|p[0]}; hv=huv.map{|p|p[1]}
exp=RTM.shape('slate')[:exposure].to_f
puts "hole u #{hu.min.round(2)}..#{hu.max.round(2)}  v #{hv.min.round(2)}..#{hv.max.round(2)}  exposure #{exp}"
after.each do |s|
  o=RTM.project(s[:origin],pu[:origin],pu[:u],pu[:v])
  vm=o[1]+exp/2.0
  next unless o[0]>hu.min+1.0 && o[0]<hu.max-1.0 && vm>hv.min+1.0 && vm<hv.max-1.0
  puts format('u %.2f v %.2f..%.2f  cut? %s  area %.2f', o[0], o[1], o[1]+s[:length].to_f, !s[:cut].nil?, s[:cut] ? RTM.poly_area(s[:cut]).abs : -1)
end
