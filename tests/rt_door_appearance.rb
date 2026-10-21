# Standalone regression: run from tests after copying current plugin sources.
require './sketchup_stub'
Z_AXIS = Geom::Vector3d.new(0,0,1) unless defined?(Z_AXIS)
class Numeric
  def degrees; self*Math::PI/180; end unless method_defined?(:degrees)
end
require './door_leaf_styles'
require './door_tool'

def check(label, value)
  raise "FAIL #{label}" unless value
  puts "PASS #{label}"
end
ds = InteriorPro::DoorLeafStyles
check('details enabled', ds.const_defined?(:REALISTIC_DETAILS) && ds::REALISTIC_DETAILS)
check('actual 1.524mm round', (ds::EDGE_RADIUS - 0.06).abs < 1e-8)
spec = ds::STYLES['2 Panel Shaker']
[-40.0, 0.0].each do |bottom|
  [78.375, 94.375].each do |height|
    p = ds.panel_rects(spec, -14.375, 14.375, bottom, bottom+height)
    check('rail centered at handle datum', ((p[0][:w0]+p[1][:w1])/2-bottom-36).abs < 1e-8)
    check('rail width preserved', (p[0][:w0]-p[1][:w1]-7.4375).abs < 1e-8)
  end
end

# Exercise the real DoorTool body dispatcher. Only the native geometry API
# is replaced here; the companion native test checks the resulting solids.
class DoorAppearanceHarness < InteriorPro::DoorTool
  def initialize(type, swing)
    @door_category='interior'; @door_type=type; @swing_direction=swing
    @frame_width=1.5; @leaf_style='2 Panel Shaker'; @interior_casing_style='none'
  end
  def door_frame_material(*); nil; end
  def door_leaf_material(*); nil; end
  def hardware_material; nil; end
  def wall_v_span_from_faces(*); nil; end
  def build_u_jamb(*); end
  def build_door_stop!(*); end
  def handle_enabled?; false; end
end
calls=[]
ds.singleton_class.alias_method :appearance_original_leaf, :build_leaf_body!
ds.singleton_class.alias_method :appearance_original_hinges, :build_hinges!
ds.define_singleton_method(:build_leaf_body!) { |*args, **kw| calls << [:leaf,args,kw]; true }
ds.define_singleton_method(:build_hinges!) { |*args| calls << [:hinge,args] }
data={half_w:16.0,door_bot_z:0.0,door_top_z:80.0,cx:0,cy:0,fx:0,fy:0,clicked_side:-1,wall_group:nil}
[['Single','left',[-1]], ['Single','right',[1]], ['Double','left',[-1,1]]].each do |type,swing,sides|
  calls.clear
  tool=DoorAppearanceHarness.new(type,swing)
  check('body dispatcher succeeds', tool.send(:build_door_body_geometry!, [], data, Geom::Vector3d.new(1,0,0), Geom::Vector3d.new(0,1,0), 5.0))
  hinges=calls.select{|c|c[0]==:hinge}
  check("#{type} #{swing} correct hinge sides", hinges.map{|c|c[1][2]}==sides)
  check('hinges follow exact leaf edge', hinges.all?{|c|(c[1][1]-c[1][2]*14.375).abs<1e-8})
end
ds.singleton_class.alias_method :build_leaf_body!, :appearance_original_leaf
ds.singleton_class.alias_method :build_hinges!, :appearance_original_hinges
# Exercise the real hinge assembly, intercepting only SketchUp mesh primitives.
class HingeAssemblySink
  attr_accessor :name, :material
  def add_group; self.class.new; end
  def entities; self; end
end
geometry=[]
[:hinge_plate!, :hinge_cylinder!, :get_or_create_material].each do |method|
  ds.singleton_class.alias_method "saved_#{method}", method
end
ds.define_singleton_method(:hinge_plate!) { |*a| geometry << [:plate,a] }
ds.define_singleton_method(:hinge_cylinder!) { |*a, **kw| geometry << [:cylinder,a,kw] }
ds.define_singleton_method(:get_or_create_material) { |*_| nil }
[-1,1].each do |side|
  [-1,1].each do |out|
    geometry.clear
    u=side*14.375
    ds.build_hinges!(HingeAssemblySink.new,u,side,-40,38.375,3.375,4.75,out,
      Geom::Vector3d.new(1,0,0),Geom::Vector3d.new(0,1,0),nil)
    plates=geometry.select{|x|x[0]==:plate}
    check('three pairs of mounting plates',plates.length==6)
    plates.each do |_,a|
      span=[side*(a[2]-u),side*(a[3]-u)].minmax
      expected=a[1]=='Leaf plate' ? [0.0,0.055] : [0.070,0.125]
      check('plate projects into reveal, outside its host',span.zip(expected).all?{|x,y|(x-y).abs<1e-8})
    end
    screws=geometry.select{|x|x[0]==:cylinder && x[1][1].end_with?('screw')}
    check('six visible screw heads per hinge',screws.length==18)
    check('screw crosses use actual recessed geometry',screws.all?{|x|x[2][:slot_axis] && x[1][5]==0.024})
    check('screws face away from their host',screws.all?{|x|x[1][3].x*side==(x[1][1]=='Leaf screw' ? 1 : -1)})
  end
end
[:hinge_plate!, :hinge_cylinder!, :get_or_create_material].each do |method|
  ds.singleton_class.alias_method method, "saved_#{method}"
end
ds.send(:remove_const,:REALISTIC_DETAILS)
ds.const_set(:REALISTIC_DETAILS,false)
p=ds.panel_rects(spec,-14.375,14.375,-40,38.375)
check('kill switch restores legacy rail', ((p[0][:w0]+p[1][:w1])/2+40-41.625).abs<1e-8)
check('kill switch skips hardware without touching entities', ds.build_hinges!(nil,0,-1,0,80,0,1.375,1,nil,nil,nil).nil?)
puts 'ALL PASS'
