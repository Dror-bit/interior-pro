# Pure dimension queries. Directions follow the kitchen axes; endpoints are on
# actual projected edges, not the bounding rectangle of a rotated cabinet.
module KitchenLab
  module Dimensions
    DIRECTIONS={'right'=>[1,0],'left'=>[-1,0],'up'=>[0,1],'down'=>[0,-1]}.freeze unless const_defined?(:DIRECTIONS)
    NO_TOP=%w[wall tall fridge oven wall_oven oven_tower micro_tower fridge_surround hood microwave corner_upper].freeze unless const_defined?(:NO_TOP)
    def self.outline(d,s,basis)
      return nil if basis=='countertop' && NO_TOP.include?(d['kind'])
      w=d['width'];dep=d['depth'];dep+=1 if basis=='countertop' && d['kind']!='corner'
      pts=if %w[corner_base corner_lazy corner_upper].include?(d['kind'])
        [[0,0],[w,0],[w,-dep],[dep,-dep],[dep,-w],[0,-w]]
      else
        [[0,0],[w,0],[w,-dep],[0,-dep]]
      end
      pts.map { |x,y| Spatial.cabinet_point(d,x,y,s) }
    end
    def self.interval(poly,v)
      hits=[]
      poly.each_with_index do |a,i|
        b=poly[(i+1)%poly.length]
        next if v<[a[1],b[1]].min-1e-7 || v>[a[1],b[1]].max+1e-7
        if (b[1]-a[1]).abs<1e-8
          hits.concat([a[0],b[0]]) if (v-a[1]).abs<1e-7
        else
          t=(v-a[1])/(b[1]-a[1]);hits<<a[0]+t*(b[0]-a[0])
        end
      end
      hits.empty? ? nil : [hits.min,hits.max]
    end
    def self.between(a,b,normal)
      nx,ny=normal;tx=-ny;ty=nx
      project=->(p) { p.map { |x,y| [x*nx+y*ny,x*tx+y*ty] } }
      aa=project.call(a);bb=project.call(b)
      lo=[aa.map(&:last).min,bb.map(&:last).min].max;hi=[aa.map(&:last).max,bb.map(&:last).max].min
      return nil if hi-lo<1e-6
      knots=([lo,hi]+(aa+bb).map(&:last).select { |v| v>lo && v<hi }).uniq.sort
      samples=knots+knots.each_cons(2).map { |x,y| (x+y)/2 }
      choices=samples.filter_map do |v|
        ai=interval(aa,v);bi=interval(bb,v);next unless ai && bi
        gap=bi[0]-ai[1];next if gap< -1e-6
        {'distance'=>[gap,0].max,'from'=>[ai[1]*nx+v*tx,ai[1]*ny+v*ty],'to'=>[bi[0]*nx+v*tx,bi[0]*ny+v*ty],'v'=>v}
      end
      best=choices.min_by { |c| [c['distance'].round(6),(c['v']-(lo+hi)/2).abs] }
      best&.reject { |k,_| k=='v' }
    end
    def self.overlap?(a,b)
      [a,b].all? do |poly|
        poly.each_with_index.all? do |p,i|
          q=poly[(i+1)%poly.length];dx=q[0]-p[0];dy=q[1]-p[1];len=Math.hypot(dx,dy)
          next true if len<1e-8
          aa=a.map { |x,y| (-dy*x+dx*y)/len };bb=b.map { |x,y| (-dy*x+dx*y)/len }
          [aa.max,bb.max].min-[aa.min,bb.min].max>0.001
        end
      end
    end
    def self.measure(data,s,basis='body',refs=[])
      raise 'Invalid measurement basis' unless %w[body countertop wall].include?(basis)
      local=s.merge('kitchen_pose'=>{'x'=>0,'y'=>0,'z'=>0,'angle'=>0,'level'=>1})
      island=data.select { |d| d.fetch('wall','A')=='I' };return [] if island.empty?
      ip=island.filter_map { |d| outline(d,local,basis=='wall' ? 'body' : basis) };return [] if ip.empty?
      targets=if basis=='wall'
        pose=Spatial.pose(s)
        refs.select { |r| r['type']=='wall' && r['measurement_safe'] }.map do |r|
          {'id'=>r['id'],'points'=>r['points'].map { |x,y| Spatial.rotate(x-pose['x'],y-pose['y'],-pose['angle']) }}
        end
      else
        data.filter_map do |d|
          next if d.fetch('wall','A')=='I'
          next unless island.any? { |i| [i['z']+i['height'],d['z']+d['height']].min>[i['z'],d['z']].max+0.001 }
          p=outline(d,local,basis);p && {'id'=>d['id'],'points'=>p}
        end
      end
      DIRECTIONS.filter_map do |side,n|
        values=ip.flat_map { |p| targets.filter_map { |r| m=between(p,r['points'],n);m && m.merge('target_id'=>r['id']) } }
        m=values.min_by { |v| [v['distance'].round(6),v['target_id'].to_s] }
        m && m.merge('side'=>side,'basis'=>basis)
      end
    end
  end
end
