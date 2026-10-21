require './sketchup_stub'
class Numeric
  def degrees; self*Math::PI/180; end unless method_defined?(:degrees)
end
require './door_library'
require './door_tool'
require './door_library_dialog'
def check(label,value)
  raise "FAIL #{label}" unless value
  puts "PASS #{label}"
end
check('exterior geometry kill switch',defined?(InteriorPro::DoorExteriorDetails::ENABLED))
check('independent patio handle kill switch',defined?(InteriorPro::DoorExteriorDetails::PATIO_HANDLES))
class ExteriorDispatchHarness < InteriorPro::DoorTool
  attr_reader :built
  def build_french_hinged_geometry!(*);@built=true;true;end
  def exterior_effective_n(data,n);n.reverse;end
end
received=[]
InteriorPro::DoorExteriorDetails.define_singleton_method(:apply!) do |*args|
  received << args;true
end
t=ExteriorDispatchHarness.new;t.apply_category_defaults('exterior')
t.handle_style='Patio Lever'
n=Geom::Vector3d.new(0,1,0);u=Geom::Vector3d.new(1,0,0);ents=Sketchup::Entities.new
check('actual body route builds',t.send(:build_door_body_geometry!,ents,{},u,n,7.5))
check('postprocessor runs once after body',t.built && received.length==1)
args=received.first
check('resolved exterior normal reaches details',args[3].y==-1)
check('actual wall thickness reaches sill',args[4]==7.5)
check('saved handle and stile reach geometry',args[5][:handle_style]=='Patio Lever' && args[5][:stile_width]==5)
received.clear
t.define_singleton_method(:build_french_hinged_geometry!){|*|false}
check('failed body does not build hardware',!t.send(:build_door_body_geometry!,ents,{},u,n,5) && received.empty?)
t.door_category='interior';t.door_type='French Hinged'
t.define_singleton_method(:build_french_hinged_geometry!){|*|true}
check('interior body excluded',t.send(:build_door_body_geometry!,ents,{},u,n,5) && received.empty?)
%w[French\ Hinged Sliding 4-Panel\ Center\ Hinged 4-Panel\ Sliding 6-Panel\ Sliding 3-Panel\ Folding 4-Panel\ Folding 6-Panel\ Folding].each do |type|
  s=InteriorPro::DoorLibrary.defaults_for_type('exterior',type)
  expected=['French Hinged','4-Panel Center Hinged'].include?(type) ? 'Patio Lever' : 'Sliding Flush Pull'
  check("#{type} appropriate handle default",s['handle_style']==expected)
end
%w[Front\ Door Garage\ Door Arched].each{|type|check("#{type} retains handle opt-in",InteriorPro::DoorLibrary.defaults_for_type('exterior',type)['handle_style']=='none')}
puts 'ALL PASS'
