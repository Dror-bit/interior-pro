require './sketchup_stub'
require './elevation_tool'
e=InteriorPro::ElevationTool
area=[0.75,1.85,34.5,21.4];sizes=[[3336,2862],[2862,1440],[3336,1440],[2237,1440]];cols=[[0,0],[1,3],[0,2],[1,2]]
b=e.kitchen_boxes(area,sizes,cols,1);old=e.row_boxes(area,sizes,cols,1)
raise 'wrong box count' unless b.size==4
raise 'not enlarged' unless (1..3).all?{|i|b[i][2]>old[i][2]*1.5}
scale=b[1][2]/sizes[1][0];raise 'unequal elevation scale' unless (1..3).all?{|i|(b[i][2]/sizes[i][0]-scale).abs<1e-9}
b.each{|x,y,w,h|raise 'outside printable area' unless w>0 && h>0 && x>=area[0] && y>=area[1] && x+w<=area[0]+area[2]+1e-6 && y+h<=area[1]+area[3]+1e-6}
b.combination(2){|a,c|raise 'overlap' if a[0]<c[0]+c[2] && c[0]<a[0]+a[2] && a[1]<c[1]+c[3] && c[1]<a[1]+a[3]}
raise 'aspect ratio' unless b.each_with_index.all?{|q,i|(q[2]/q[3]-sizes[i][0].to_f/sizes[i][1]).abs<1e-9}
e.send(:remove_const,:USE_KITCHEN_SHEET_GRID);e.const_set(:USE_KITCHEN_SHEET_GRID,false)
raise 'disabled fallback' unless e.kitchen_boxes(area,sizes,cols,1)==old
puts 'PASS kitchen layout: enlargement, scale, bounds, no overlaps, aspect ratios and switch'
