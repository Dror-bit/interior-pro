module Sketchup
  class Face
    attr_accessor :edges
    def initialize;@edges=[];end
  end
end
load File.join(__dir__,'kitchen_crown.rb')
Edge=Struct.new(:faces)
Part=Struct.new(:solid) { def manifold?;solid;end }
class GroupingEntities < Array
  attr_reader :grouped
  def initialize(faces,valid=true);super(faces);@grouped=[];@valid=valid;end
  def add_group(selected)
    @grouped<<selected
    Part.new(@valid)
  end
end
ShellGroup=Struct.new(:entities,:solid,:valid) do
  def valid?;valid;end
  def manifold?;solid;end
end
def check(value,message);raise message unless value;end
def joined_shells(valid=true)
  f=4.times.map{Sketchup::Face.new}
  shared=Edge.new(f)
  a=Edge.new(f[0,2]);b=Edge.new(f[2,2])
  f[0].edges=f[1].edges=[a,shared]
  f[2].edges=f[3].edges=[b,shared]
  ShellGroup.new(GroupingEntities.new(f,valid),false,true)
end
j=KitchenLab::CrownJoints
group=joined_shells
parts=j.closed_crown_parts(group)
check(parts.length==2 && parts.all?(&:manifold?),'Edge-touching shells were not separated into closed pieces')
check(group.entities.grouped.map{|s|s.grep(Sketchup::Face).length}==[2,2],'Faces were lost or put into the wrong shell')
check(group.entities.grouped.all?{|s|s.grep(Edge).length==2},'Boundary edges were not included')
solid=ShellGroup.new(GroupingEntities.new([]),true,true)
check(j.closed_crown_parts(solid)==[solid] && solid.entities.grouped.empty?,'Existing solid was changed')
check(j.closed_crown_parts(nil).empty?,'Missing boolean result accepted')
check(j.closed_crown_parts(ShellGroup.new(GroupingEntities.new([Sketchup::Face.new]),false,true)).empty?,'Open connected shell accepted')
check(j.closed_crown_parts(joined_shells(false)).empty?,'Invalid reconstructed parts accepted')
j.send(:remove_const,:USE_SEPARATE_CROWN_SHELLS);j.const_set(:USE_SEPARATE_CROWN_SHELLS,false)
off=joined_shells
check(j.closed_crown_parts(off).empty? && off.entities.grouped.empty?,'Kill switch did not preserve legacy failure')
puts 'PASS: separated shells retain every face and boundary; existing solids untouched; open/invalid results rejected; kill switch restores legacy behavior.'
