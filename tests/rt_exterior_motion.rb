require './sketchup_stub'
class Numeric
  def degrees;self*Math::PI/180;end unless method_defined?(:degrees)
end
Z_AXIS=Geom::Vector3d.new(0,0,1) unless defined?(Z_AXIS)
X_AXIS=Geom::Vector3d.new(1,0,0) unless defined?(X_AXIS)
Y_AXIS=Geom::Vector3d.new(0,1,0) unless defined?(Y_AXIS)
ORIGIN=Geom::Point3d.new(0,0,0) unless defined?(ORIGIN)
Geom.const_set(:BoundingBox,Sketchup::BoundsBox) unless defined?(Geom::BoundingBox)
class Geom::Transformation
  def to_a;[m00,m01,m10,m11,ox,oy,oz];end unless method_defined?(:to_a)
end
require './door_tool'
require './door_library'
require './door_library_dialog'
require './door_manager'
def check(label,value)
  raise "FAIL #{label}" unless value
  puts "PASS #{label}"
end
check('independent exterior switch',defined?(InteriorPro::DoorExteriorMotion::ENABLED) && InteriorPro::DoorExteriorMotion::ENABLED)
class Sketchup::Entities
  def transform_entities(tr,parts);parts.each{|p|p.transform!(tr)};end
end
def part(ents,name,x0,x1,y0=1.0,y1=2.5,z0=-40,z1=40)
  g=ents.add_group;g.name=name
  b=Geom::BoundingBox.new;b.add(Geom::Point3d.new(x0,y0,z0));b.add(Geom::Point3d.new(x1,y1,z1))
  g.define_singleton_method(:bounds){b};g
end
motion=InteriorPro::DoorExteriorMotion
[-1,1].each do |sign|
  %w[left right].each do |direction|
    ents=Sketchup::Entities.new
    leaf=part(ents,'Leaf_Front',-17,17)
    glass=part(ents,'Leaf_Front_ArchGlass',-13,13)
    fixed=part(ents,'Leaf_Sidelite_L',-30,-20)
    jamb=part(ents,'Jamb',-19,19)
    hinge=part(ents,"Hinge_#{direction=='right' ? 'Right' : 'Left'}_1",-17,-16)
    moving=part(hinge.entities,'Leaf plate',0,1)
    pin=part(hinge.entities,'Knuckle',0,1)
    motion.apply!(ents,'Front Door',{door_state:'half_open',opening_sign:sign,swing_direction:direction})
    side=direction=='right' ? 1 : -1
    v=Geom::Vector3d.new(-side,0,0).transform(leaf.transformation)
    check('hinged leaf opens 45 toward actual side',(v.y*sign-Math.sqrt(0.5)).abs<1e-7)
    check('separate steel-arch glass follows leaf',glass.transformation.to_a==leaf.transformation.to_a)
    check('sidelite and jamb remain fixed',fixed.transformation.identity? && jamb.transformation.identity?)
    check('leaf hinge plate moves; pin stays local',!moving.transformation.identity? && pin.transformation.identity?)
  end
end
%w[left right].each do |direction|
  ents=Sketchup::Entities.new
  ls=[part(ents,'Leaf_Left',-36,0),part(ents,'Leaf_Right',0.25,36.25)]
  motion.apply!(ents,'Sliding',{door_state:'half_open',slide_direction:direction})
  active=direction=='right' ? 0 : 1
  check('sliding active panel and half travel',(ls[active].transformation.origin.x-(direction=='right' ? 18 : -18)).abs<1e-7 && ls[1-active].transformation.identity?)
end
[4,6].each do |count|
  %w[left right].each do |direction|
    ents=Sketchup::Entities.new
    ls=count.times.map{|i|part(ents,"Leaf_#{i}",i*36,i*36+35.75,1+i*2,2.5+i*2)}
    motion.apply!(ents,"#{count}-Panel Sliding",{door_state:'half_open',slide_direction:direction})
    anchor=direction=='right' ? count-1 : 0
    check('multipanel stacking anchor fixed',ls[anchor].transformation.identity?)
    check('multipanel half travel',(ls[0].transformation.origin.x-(direction=='right' ? (count-1)*18 : 0)).abs<1e-7)
  end
end
[3,4,6].each do |count|
  %w[left right].each do |direction|
    [-1,1].each do |sign|
    ents=Sketchup::Entities.new
    ls=count.times.map{|i|part(ents,"Leaf_#{i}",i*36,i*36+35.75)}
    pins=(0...count-1).map{|i|part(ents,'Folding joint barrel',i*36+35.875-0.18,i*36+35.875+0.18,0.58,0.94,-1.5,1.5)}
    motion.apply!(ents,"#{count}-Panel Folding",{door_state:'half_open',slide_direction:direction,opening_sign:sign})
    check('all folding leaves articulate',ls.all?{|p|!p.transformation.identity?})
    check('folded leaf width projection is 45 degrees',ls.all?{|p|(Geom::Vector3d.new(1,0,0).transform(p.transformation).x.abs-Math.sqrt(0.5)).abs<1e-7})
    continuity=(0...count-1).all? do |i|
      k=direction=='right' ? count-2-i : i
      y=sign*(k.even? ? 1 : -1)>0 ? 0.76 : 2.74
      a=Geom::Point3d.new(i*36+35.75,y,0).transform(ls[i].transformation)
      b=Geom::Point3d.new((i+1)*36,y,0).transform(ls[i+1].transformation)
      pin=Geom::Point3d.new(i*36+35.875,0.76,0).transform(pins[i].transformation)
      (a.distance(b)-0.25).abs<1e-7 && pin.distance(Geom::Point3d.new((a.x+b.x)/2,(a.y+b.y)/2,0))<1e-7
    end
    check('alternating hinge axes stay connected and pins follow',continuity)
    end
  end
end
ents=Sketchup::Entities.new
leaf=part(ents,'Leaf',-17,17)
motion.apply!(ents,'Front Door',{door_state:'closed',opening_sign:-1})
check('closed retains original leaf',leaf.transformation.identity?)
check('other side action consumes sign correctly',motion.side(-1,'reverse')==1 && motion.side(1,'auto')==1)
check('exterior default closed',InteriorPro::DoorLibrary.defaults_for('exterior')['door_state']=='closed')
settings=InteriorPro::DoorLibrary.defaults_for('exterior').merge('door_state'=>'half_open','swing_side'=>'reverse')
t=InteriorPro::DoorTool.new
InteriorPro::DoorLibraryDialog.apply_to_tool(t,settings)
check('actual dialog populates exterior state',t.door_state=='half_open' && t.swing_side=='reverse')
g=Sketchup::Group.new
def g.attribute_dictionary(key,create=false);@attrs[key];end
InteriorPro::DoorManager.write_door_params!(g,settings)
check('exterior edit dictionary round trip',InteriorPro::DoorManager.settings_from_door(g)['door_state']=='half_open')
manager=InteriorPro::DoorManager
manager.define_singleton_method(:find_wall_by_id){|*|Object.new}
manager.define_singleton_method(:wall_geometry){|*|{unit:X_AXIS,n:Y_AXIS,thickness:5}}
manager.define_singleton_method(:opening_context) do |door,geo|
  {t:20,clicked_side:door.get_attribute('InteriorPro','clicked_side'),fx:19,fy:2.5,outward:Y_AXIS}
end
manager.define_singleton_method(:clear_door_geometry!){|*|true}
class InteriorPro::DoorTool
  def build_opening_data(wall,geo,**kw);kw;end
  def apply_door_transform!(*);true;end
  def regen_door_body!(door,data,*);door.set_attribute('Test','rebuilt_side',data[:clicked_side]);true;end
end
g.set_attribute('InteriorPro','type','door')
manager.write_door_params!(g,settings.merge('clicked_side'=>-1,'swing_side'=>'auto'))
check('actual edit consumes reverse once',manager.door_regen!(g,settings:{'swing_side'=>'reverse'}) && g.get_attribute('InteriorPro','clicked_side')==1 && g.get_attribute('InteriorPro','swing_side')=='auto' && g.get_attribute('Test','rebuilt_side')==1)
manager.door_regen!(g)
check('subsequent regeneration keeps chosen side',g.get_attribute('Test','rebuilt_side')==1)
manager.door_regen!(g,settings:{'swing_side'=>'reverse'})
check('second reverse returns original side',g.get_attribute('Test','rebuilt_side')==-1)
motion.send(:remove_const,:ENABLED);motion.const_set(:ENABLED,false)
motion.apply!(ents,'Front Door',{door_state:'half_open',opening_sign:-1})
check('kill switch leaves geometry closed',leaf.transformation.identity?)
puts 'ALL PASS'
