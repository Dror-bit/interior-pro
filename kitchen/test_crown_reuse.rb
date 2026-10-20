require 'json'
root=ARGV.fetch(0,__dir__)
load File.join(root,'kitchen_crown.rb')
j=KitchenLab::CrownJoints
# The signature test supplies already-resolved run vertices, independent of SU.
def j.run_points(r);r.fetch(:points);end
mat=Struct.new(:name).new('ivory');point=Struct.new(:x,:y)
a={owner:'a',mat:mat,points:[[0,0,90],[20,0,90],[20,4,96],[0,4,96]]}
b={owner:'b',mat:mat,points:[[100,0,90],[120,0,90],[120,4,96]]}
cut={owner:'wall',poly:[point.new(10,0),point.new(11,0),point.new(11,1)],lo:0,hi:100}
key=j.crown_signature([a],[a],[])
raise 'Distant cabinet invalidated cache' unless key==j.crown_signature([a],[a,b],[])
near=b.merge(points:[[19,0,90],[21,0,90],[21,4,96]])
raise 'Nearby crown ignored' if key==j.crown_signature([a],[a,near],[])
raise 'Nearby wall ignored' if key==j.crown_signature([a],[a],[cut])
raise 'Profile edit ignored' if key==j.crown_signature([a.merge(points:[[0,0,90],[20,0,90],[20,5,96]])],[a],[])
raise 'Material edit ignored' if key==j.crown_signature([a.merge(mat:Struct.new(:name).new('oak'))],[a],[])
key=j.crown_signature([a],[a,near],[cut])
raise 'Ordering caused miss' unless key==j.crown_signature([a],[near,a],[cut])
noisy=a.merge(points:a[:points].map{|p|p.map{|v|v+1e-9}})
raise 'Floating point noise caused miss' unless j.crown_signature([a],[a],[])==j.crown_signature([noisy],[noisy],[])
puts 'PASS crown reuse: distant/nearby cabinets, wall cutters, shape, finish, ordering and numeric stability'
raise 'Fully occluded house side failed' unless j.crown_signature([],[a],[]).is_a?(String)
house=a.merge(owner:nil,house:true)
house_key=j.crown_signature([house],[house,a],[])
raise 'House joint partner ignored' if house_key==j.crown_signature([house],[house,near],[])
puts 'PASS house crown cache: empty side and changed kitchen joint'
