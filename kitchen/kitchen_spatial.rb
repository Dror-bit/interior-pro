# Pure inch-based placement math, independent of SketchUp and the planner.
module KitchenLab
  module Spatial
    def self.pose(s)
      {'x'=>0.0,'y'=>0.0,'z'=>0.0,'angle'=>0.0,'level'=>1}.merge(s.fetch('kitchen_pose',{}))
    end
    def self.rotate(x,y,angle)
      a=angle*Math::PI/180.0;c=Math.cos(a);s=Math.sin(a)
      [x*c-y*s,x*s+y*c]
    end
    def self.local_point(wall,x,y,s)
      return [-y,-x] if wall=='B'
      if wall=='I'
        xx,yy=rotate(x,y,s.fetch('island_angle',0))
        return [xx+s.fetch('island_x',48),yy-s.fetch('island_y',84)]
      end
      [x,y]
    end
    def self.point(wall,x,y,s)
      xx,yy=local_point(wall,x,y,s);p=pose(s)
      xx,yy=rotate(xx,yy,p['angle'])
      [xx+p['x'],yy+p['y']]
    end
    def self.cabinet_pivot(d)
      case d.fetch('rotation_pivot','center')
      when 'back_left';[0,0]
      when 'back_right';[d['width'],0]
      when 'front_left';[0,-d['depth']]
      when 'front_right';[d['width'],-d['depth']]
      else;[d['width']/2.0,-d['depth']/2.0]
      end
    end
    def self.cabinet_point(d,x,y,s)
      x=d['width']-x if d.fetch('flip_x',false)
      y=-d['depth']-y if d.fetch('flip_y',false)
      if (p=d['house_placement'])
        xx,yy=rotate(x,y*p.fetch('handedness',1),p['angle'])
        return [xx+p['x'],yy+p['y']]
      end
      cx,cy=cabinet_pivot(d)
      xx,yy=rotate(x-cx,y-cy,d.fetch('rotation',0))
      point(d.fetch('wall','A'),d['x']+cx+xx,cy+yy+d.fetch('offset_y',0),s)
    end
    def self.polygon(d,s)
      size=%w[corner_base corner_lazy corner_upper].include?(d['kind']) ? d['width'] : d['depth']
      [[0,0],[d['width'],0],[d['width'],-size],[0,-size]].map { |x,y| cabinet_point(d,x,y,s) }
    end
    def self.overlap?(a,b,s)
      return false if [a['z']+a['height'],b['z']+b['height']].min-[a['z'],b['z']].max<=0.001
      aa=polygon(a,s);bb=polygon(b,s)
      [aa,bb].all? do |poly|
        poly.each_index.all? do |i|
          p=poly[i];q=poly[(i+1)%poly.length];dx=q[0]-p[0];dy=q[1]-p[1];length=Math.hypot(dx,dy)
          axis=[-dy/length,dx/length]
          av=aa.map { |v| v[0]*axis[0]+v[1]*axis[1] };bv=bb.map { |v| v[0]*axis[0]+v[1]*axis[1] }
          [av.max,bv.max].min-[av.min,bv.min].max>0.001
        end
      end
    end
  end
end
