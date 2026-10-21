require './sketchup_stub'
class Numeric
  def degrees; self*Math::PI/180; end unless method_defined?(:degrees)
end
Z_AXIS=Geom::Vector3d.new(0,0,1) unless defined?(Z_AXIS)
require './door_library'
require './door_leaf_styles'
require './door_tool'
require './door_manager'
require './door_library_dialog'
def check(label,value)
  raise "FAIL #{label}" unless value
  puts "PASS #{label}"
end
check('kill switch enabled', InteriorPro::DoorTool.const_defined?(:USE_INTERIOR_SWING) && InteriorPro::DoorTool::USE_INTERIOR_SWING)
check('existing doors default closed',InteriorPro::DoorLibrary.defaults_for('interior')['door_state']=='closed')
tool=InteriorPro::DoorTool.new
settings=InteriorPro::DoorLibrary.defaults_for('interior').merge('door_state'=>'half_open','swing_side'=>'reverse')
InteriorPro::DoorLibraryDialog.apply_to_tool(tool,settings)
check('dialog settings reach actual tool',tool.door_state=='half_open' && tool.swing_side=='reverse')
d=Sketchup::Group.new
def d.attribute_dictionary(key,create=false); @attrs[key]; end
params=settings.merge('clicked_side'=>-1)
InteriorPro::DoorManager.write_door_params!(d,params)
check('state survives legacy settings read',InteriorPro::DoorManager.settings_from_door(d)['door_state']=='half_open')
check('state survives parametric filter',InteriorPro::DoorManager.settings_from_params(params)['door_state']=='half_open')
check('parametric dictionary stores state',d.get_attribute('InteriorPro_door','door_state')=='half_open')

class SwingBodyHarness < InteriorPro::DoorTool
  def door_frame_material(*);nil;end
  def door_leaf_material(*);nil;end
  def hardware_material;nil;end
  def wall_v_span_from_faces(*);[0,5];end
  def build_u_jamb(ents,*);g=ents.add_group;g.name='Jamb';end
  def build_door_stop!(ents,*);g=ents.add_group;g.name='Stop';end
  def handle_enabled?;false;end
end
ds=InteriorPro::DoorLeafStyles
ds.define_singleton_method(:build_leaf_body!) do |ents,style,u0,u1,w0,w1,vf,vb,unit,n,**kw|
  g=ents.add_group;g.name=kw[:name];g.set_attribute('Test','depth',[vf,vb]);g
end
ds.define_singleton_method(:build_hinges!) do |ents,u,side,*|
  h=ents.add_group;h.name="Hinge_#{side<0 ? 'Left' : 'Right'}_1"
  %w[Fixed].concat(['Leaf plate','Leaf screw']).each{|name|g=h.entities.add_group;g.name=name}
end
%w[Single Double].each do |type|
  %w[left right].each do |swing|
    [-1,1].each do |click|
      %w[auto reverse].each do |mode|
        t=SwingBodyHarness.new;t.apply_category_defaults('interior')
        t.door_type=type;t.swing_direction=swing;t.swing_side=mode;t.door_state='half_open'
        ents=Sketchup::Entities.new
        data={half_w:32,door_bot_z:0,door_top_z:80,cx:0,cy:0,fx:0,fy:0,clicked_side:click,wall_group:nil}
        check('actual body dispatcher builds half-open',t.send(:build_door_body_geometry!,ents,data,Geom::Vector3d.new(1,0,0),Geom::Vector3d.new(0,1,0),5))
        open_sign=mode=='reverse' ? -click : click
        leaves=ents.grep(Sketchup::Group).select{|g|g.name.start_with?('Leaf')}
        leaves.each do |leaf|
          side=type=='Double' ? (leaf.name=='Leaf_Left' ? -1 : 1) : (swing=='right' ? 1 : -1)
          vector=Geom::Vector3d.new(-side,0,0).transform(leaf.transformation)
          check('leaf opens 45 degrees toward requested side',(vector.y*open_sign-Math.sqrt(0.5)).abs<1e-7)
          depth=leaf.get_attribute('Test','depth')
          check('closed leaf depth follows opening side',(depth.sum/2>2.5)==(open_sign>0))
        end
        check('jamb remains fixed',ents.grep(Sketchup::Group).find{|g|g.name=='Jamb'}.transformation.identity?)
        ents.grep(Sketchup::Group).select{|g|g.name.start_with?('Hinge_')}.each do |h|
          check('fixed hinge parts stay fixed',h.entities.grep(Sketchup::Group).find{|p|p.name=='Fixed'}.transformation.identity?)
          check('leaf hinge plates move',!h.entities.grep(Sketchup::Group).find{|p|p.name=='Leaf plate'}.transformation.identity?)
        end
      end
    end
  end
end
InteriorPro::DoorTool.send(:remove_const,:USE_INTERIOR_SWING)
InteriorPro::DoorTool.const_set(:USE_INTERIOR_SWING,false)
check('kill switch disables swing feature',!tool.send(:interior_swing_enabled?))
puts 'ALL PASS'
