load File.join(__dir__,'countertop_materials.rb')
load File.join(__dir__,'kitchen_backsplash.rb')
b=KitchenLab::Backsplash
raise unless b.validate(nil)=={'mode'=>'none'}
cfg=b.validate({'mode'=>'countertop','height'=>18})
rects=b.rectangles(36,36,cfg,[[12,40,24,50]])
area=rects.sum{|x,z,r,t|(r-x)*(t-z)}
raise 'Opening not subtracted' unless (area-(36*18-12*10)).abs<0.001
raise 'Hole intersection' if rects.any?{|x,z,r,t|[r,24].min>[x,12].max && [t,50].min>[z,40].max}
tiles=b.rectangles(36,36,b.validate({'mode'=>'tile'}),[[12,40,24,50]])
raise 'No tile joints' unless tiles.sum{|x,z,r,t|(r-x)*(t-z)}<area
raise 'Tile outside panel' unless tiles.all?{|x,z,r,t|x>=0 && z>=36 && r<=36 && t<=54}
raise 'Window covered' if tiles.any?{|x,z,r,t|[r,24].min>[x,12].max && [t,50].min>[z,40].max}
%w[height thickness tile_width tile_height grout].each do |key|
  begin;b.validate({'mode'=>'tile',key=>-1});raise 'Accepted invalid '+key;rescue RuntimeError=>e;raise unless e.message.start_with?('Invalid backsplash');end
end
raise if b.eligible?({'kind'=>'wall'}) || b.eligible?({'kind'=>'filler','surround_for'=>'parent'})
raise unless b.eligible?({'kind'=>'corner_base'})
puts 'PASS backsplash dimensions, bounds, window clipping, tile joints and cabinet eligibility'
