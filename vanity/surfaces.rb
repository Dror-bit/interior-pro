require_relative 'muse_sink'
module InteriorPro
  module Vanity
    remove_const(:USE_VANITY_SURFACES) if const_defined?(:USE_VANITY_SURFACES,false)
    USE_VANITY_SURFACES=true
    remove_const(:USE_CONTINUOUS_VANITY_TOP) if const_defined?(:USE_CONTINUOUS_VANITY_TOP,false)
    USE_CONTINUOUS_VANITY_TOP=true
    # Generic design geometry, in inches. No manufacturer installation claims.
    module Surfaces
      module_function
      def settings(c)
        {'countertop_color'=>c['countertop']||'white','countertop_thickness'=>0.75,
         'backsplash_height'=>0.0,'sink_width'=>17.0,'sink_depth'=>12.0,
         'sink_height'=>6.0,'sink_color'=>'white','sink_shape'=>'oval','faucet_finish'=>'chrome'}.merge(c.fetch('surfaces',{}))
      end
      def new_defaults
        settings({}).merge(USE_ICERA_MUSE ? MuseSink.defaults : {})
      end
      def centers(c)
        return [] unless c['product_id']=='vanity'
        cols=Domain.front_columns(c);layout=Domain.column_layout(c)
        usable=cols.each_index.select { |i|cols[i]['kind']!='makeup' }
        return [] if usable.empty?
        if c['sink_parts']
          indices=c['sink_parts']
          raise ArgumentError,'בחר חלק תקין לכל כיור; אי אפשר להציב כיור במייק־אפ' unless indices.is_a?(Array) && indices.length==c['basins'] && indices.all? { |i|i.is_a?(Integer) && usable.include?(i) }
          if indices.length==2 && indices.uniq.length==1
            row=layout[indices.first];return [row['x']+row['width']/4,row['x']+3*row['width']/4]
          end
          return indices.map { |i|layout[i]['x']+layout[i]['width']/2 }.sort
        end
        if c['basins']==2 && usable.length==1
          i=usable.first;x=layout[i]['x'];bay=layout[i]['width'];[x+bay/4,x+3*bay/4]
        else
          indices=c['basins']==1 ? [usable.min_by { |i|[(i-(cols.length-1)/2.0).abs,cols[i]['kind']=='doors' ? 0 : 1] }] : [usable.first,usable.last]
          indices.map { |i|layout[i]['x']+layout[i]['width']/2 }
        end
      end
      def validate(c)
        return unless c.key?('surfaces')
        s=settings(c)
        raise ArgumentError,'צורת כיור לא תקינה' unless %w[oval square icera_muse].include?(s['sink_shape'])
        if s['sink_shape']=='icera_muse'
          raise ArgumentError,'כיור ICERA אינו פעיל' unless USE_ICERA_MUSE
          %w[sink_width sink_depth sink_height].each do |key|
            raise ArgumentError,'לכיור ICERA מידות קבועות; למידה אחרת בחר כיור בהתאמה אישית' unless s[key]==MuseSink.defaults[key]
          end
        end
        %w[countertop_color sink_color].each { |k|raise ArgumentError,'צבע משטח או כיור לא תקין' unless %w[white ivory gray black].include?(s[k]) }
        raise ArgumentError,'גימור ברז לא תקין' unless %w[chrome brass black matte_black brushed_nickel satin_brass].include?(s['faucet_finish'])
        {'countertop_thickness'=>[0.5,3],'backsplash_height'=>[0,12],'sink_width'=>[10,24],'sink_depth'=>[8,18],'sink_height'=>[4,9]}.each do |k,r|
          Cabinetry.number!(s[k])
          raise ArgumentError,"מידה לא תקינה: #{k}" unless s[k].between?(*r) && (s[k]*8-(s[k]*8).round).abs<1e-6
        end
        return unless c['product_id']=='vanity'
        raise ArgumentError,'הכיור עמוק מדי לארון' if s['sink_depth']+6>c['depth']
        raise ArgumentError,'הכיור גבוה מדי לארון' if s['sink_height']+2>c['height']-Domain.body_bottom(c)
        layout=Domain.column_layout(c)
        centers(c).each do |x|
          part=layout.find { |row|x>=row['x'] && x<row['x']+row['width'] }
          raise ArgumentError,'הכיור רחב מדי לאזור הנבחר; הגדל את הארון או הקטן את הכיור' if x-s['sink_width']/2-1.25<part['x']+0.75 || x+s['sink_width']/2+1.25>part['x']+part['width']-0.75
        end
        raise ArgumentError,'אין מקום לשני כיורים' if centers(c).each_cons(2).any? { |a,b|b-a<s['sink_width']+3 }
      end
      def outline(a,rx,ry,shape)
        return MuseSink.outline(a) if shape=='icera_muse' && USE_ICERA_MUSE
        values=[Math.cos(a),Math.sin(a)]
        values=values.map { |v|(v<0 ? -1 : 1)*Math.sqrt(v.abs) } if shape=='square'
        [rx*values[0],ry*values[1]]
      end
      def ring(cx,cy,rx,ry,z,n=64,shape='oval')
        Array.new(n) { |i|x,y=outline(i*2*Math::PI/n,rx,ry,shape);[cx+x,cy+y,z] }
      end
      def shell(rings)
        faces=[]
        rings.each_with_index do |a,j|
          b=rings[(j+1)%rings.length]
          a.length.times do |i|
            k=(i+1)%a.length
            faces<<[a[i],a[k],b[k]]<<[a[i],b[k],b[i]]
          end
        end
        faces
      end
      def mesh(entities,name,faces,mat)
        g=entities.add_group;g.name=name;g.material=mat
        vertices,polygons=mesh_data(faces)
        pm=Geom::PolygonMesh.new(vertices.length,polygons.length)
        vertices.each { |p|pm.add_point(p) }
        polygons.each { |p|pm.add_polygon(p) }
        flags=Geom::PolygonMesh::HIDE_BASED_ON_INDEX|Geom::PolygonMesh::SOFTEN_BASED_ON_INDEX|Geom::PolygonMesh::SMOOTH_SOFT_EDGES
        g.entities.fill_from_mesh(pm,true,flags,mat,mat)
        g
      end
      # Smooth only coplanar triangles and gentle curves. Slab rims/corners stay
      # sharp. Signed indices specify the outgoing edge, before bulk insertion.
      def mesh_data(faces)
        vertices=[];lookup={};edges=Hash.new { |h,k|h[k]=[] }
        polygons=faces.map do |points|
          ids=points.map do |p|
            key=p.map { |v|v.round(8) }
            lookup[key]||=begin;vertices<<p;vertices.length;end
          end
          a,b,c=points;u=3.times.map { |i|b[i]-a[i] };v=3.times.map { |i|c[i]-a[i] }
          n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
          length=Math.sqrt(n.sum { |x|x*x });n=n.map { |x|x/length }
          ids.each_with_index { |id,i|edges[[id,ids[(i+1)%3]].sort]<<n }
          ids
        end
        smooth=edges.transform_values { |ns|ns.length==2 && ns[0].zip(ns[1]).sum { |a,b|a*b }>Math.cos(Math::PI/6) }
        polygons=polygons.map { |ids|ids.each_with_index.map { |id,i|smooth[[id,ids[(i+1)%3]].sort] ? -id : id } }
        [vertices,polygons]
      end
      def build(e,c,material)
        s=settings(c);w=c['width'];d=c['depth'];h=c['height'];t=s['countertop_thickness']
        top=material.call(s['countertop_color'])
        holes=centers(c);cy=-d/2.0;rx=s['sink_width']/2;ry=s['sink_depth']/2
        continuous_top(e,c,holes,top) if USE_CONTINUOUS_VANITY_TOP && !holes.empty?
        # Each sink owns a rectangular counter cell, with one elliptical opening.
        edges=[0]+holes.each_cons(2).map { |a,b|(a+b)/2 }+[w]
        if holes.empty?
          Cabinetry::Geometry.box(e,'Countertop',0,-d-0.5,h,w,d+0.5,t,top)
        else
          holes.each_with_index do |cx,j|
            inner=ring(cx,cy,rx,ry,h)
            outer=inner.map do |x,y,_|
              dx=x-cx;dy=y-cy
              scale=[dx>0 ? (edges[j+1]-cx)/dx : dx<0 ? (edges[j]-cx)/dx : Float::INFINITY,
                     dy>0 ? -cy/dy : dy<0 ? (-d-0.5-cy)/dy : Float::INFINITY].min
              [cx+dx*scale,cy+dy*scale,h]
            end
            # Add exact rectangle corners; otherwise radial sampling cuts corners.
            angles=MuseSink.selected(s) ? MuseSink.opening.map { |x,y,_|Math.atan2(y,x)%(2*Math::PI) } : (0...64).map { |i|i*2*Math::PI/64 }
            [edges[j],edges[j+1]].product([-d-0.5,0]).each do |x,y|
              dx=(x-cx)/(MuseSink.selected(s) ? 1 : rx);dy=(y-cy)/(MuseSink.selected(s) ? 1 : ry)
              if s['sink_shape']=='square'
                dx*=dx.abs;dy*=dy.abs
              end
              angles<<Math.atan2(dy,dx)%(2*Math::PI)
            end
            angles=angles.sort.uniq
            inner=angles.map { |a|x,y=outline(a,rx,ry,s['sink_shape']);[cx+x,cy+y,h] }
            outer=inner.map do |x,y,_|
              dx=x-cx;dy=y-cy
              scale=[dx>1e-10 ? (edges[j+1]-cx)/dx : dx< -1e-10 ? (edges[j]-cx)/dx : Float::INFINITY,
                     dy>1e-10 ? -cy/dy : dy< -1e-10 ? (-d-0.5-cy)/dy : Float::INFINITY].min
              [cx+dx*scale,cy+dy*scale,h]
            end
            mesh(e,'Countertop',shell([outer,outer.map { |x,y,z|[x,y,z+t] },inner.map { |x,y,z|[x,y,z+t] },inner]),top) unless USE_CONTINUOUS_VANITY_TOP
            ceramic=material.call(s['sink_color']);depth=s['sink_height']
            if MuseSink.selected(s)
              MuseSink.build(e,cx,cy,h,ceramic)
              # Drain location is offset toward the back, as dimensioned.
              dy=cy+MuseSink.asset['drain'][1];z=h-MuseSink.asset['bowl_depth']
              drain=[ring(cx,dy,0.81,0.81,z+0.06),ring(cx,dy,0.65,0.65,z+0.06),
                     ring(cx,dy,0.65,0.65,z-0.3),ring(cx,dy,0.81,0.81,z-0.3)]
              mesh(e,'Drain / '+s['faucet_finish'],shell(drain),material.call(s['faucet_finish']))
              next
            end
            # Closed ceramic wall: flange, inner bowl, drain hole and outer skin.
            basin=lambda { |a,b,z|ring(cx,cy,a,b,z,64,s['sink_shape']) }
            rings=[basin.call(rx+0.65,ry+0.65,h),basin.call(rx,ry,h),
                   basin.call(rx*0.88,ry*0.88,h-1),basin.call(rx*0.65,ry*0.65,h-depth+0.5),
                   ring(cx,cy,0.8,0.8,h-depth),ring(cx,cy,0.8,0.8,h-depth-0.25),
                   basin.call(rx*0.65+0.25,ry*0.65+0.25,h-depth+0.25),
                   basin.call(rx*0.88+0.25,ry*0.88+0.25,h-1),
                   basin.call(rx+0.65,ry+0.65,h-0.3)]
            mesh(e,'Ceramic undermount sink',shell(rings),ceramic)
            drain=[ring(cx,cy,0.79,0.79,h-depth+0.06),ring(cx,cy,0.65,0.65,h-depth+0.06),
                   ring(cx,cy,0.65,0.65,h-depth-0.3),ring(cx,cy,0.79,0.79,h-depth-0.3)]
            mesh(e,'Drain / '+s['faucet_finish'],shell(drain),material.call(s['faucet_finish']))
          end
        end
        bh=s['backsplash_height']
        Cabinetry::Geometry.box(e,'Backsplash',0,-t,h+t,w,t,bh,top) if bh>0
      end
      def continuous_top(entities,c,holes,material)
        s=settings(c);w=c['width'];d=c['depth'];h=c['height']
        group=entities.add_group;group.name='Countertop';group.material=material
        e=group.entities
        e.add_face([0,-d-0.5,h],[w,-d-0.5,h],[w,0,h],[0,0,h])
        holes.each do |cx|
          points=MuseSink.selected(s) ? MuseSink.opening.map { |x,y,_|[cx+x,-d/2.0+y,h] } : ring(cx,-d/2.0,s['sink_width']/2.0,s['sink_depth']/2.0,h,64,s['sink_shape'])
          cut=e.add_face(points)
          raise 'Could not form sink opening' unless cut
          cut.erase!
        end
        face=e.grep(Sketchup::Face).max_by(&:area)
        raise 'Could not form continuous countertop' unless face
        face.reverse! if face.normal.z<0
        face.pushpull(s['countertop_thickness'])
        smooth_counter_openings(group)
        e.grep(Sketchup::Face).each { |f|f.material=material;f.back_material=material }
        group
      end
      def smooth_counter_openings(group)
        changed=0
        group.entities.grep(Sketchup::Edge).each do |edge|
          faces=edge.faces
          next unless faces.length==2 && edge.line[1].parallel?(Z_AXIS)
          next unless faces.all? { |f|f.normal.z.abs<1e-6 } && faces[0].normal.dot(faces[1].normal)>Math.cos(Math::PI/6)
          changed+=1 unless edge.soft? && edge.smooth?
          edge.soft=true;edge.smooth=true
        end
        changed
      end
      # Split drawer boards around basin and plumbing clearance, never overlap.
      def clear_drawer(c,box)
        return [box] unless c.key?('surfaces') && USE_VANITY_SURFACES
        s=settings(c);d=c['depth'];h=c['height'];pieces=[box]
        centers(c).each do |cx|
          outer_w=MuseSink.selected(s) ? 20.5 : s['sink_width']+1.5
          outer_d=MuseSink.selected(s) ? 14.625 : s['sink_depth']+1.5
          cuts=[[cx-outer_w/2-0.25,-d/2-outer_d/2-0.25,h-s['sink_height']-0.75,
                 outer_w+0.5,outer_d+0.5,s['sink_height']+1],
                [cx-2,-d/2-2,0,4,d/2+2,h]]
          cuts.each { |cut|pieces=pieces.flat_map { |p|subtract(p,cut) } }
        end
        pieces
      end
      def subtract(a,b)
        lo=3.times.map { |i|[a[i],b[i]].max };hi=3.times.map { |i|[a[i]+a[i+3],b[i]+b[i+3]].min }
        return [a] if 3.times.any? { |i|hi[i]-lo[i]<=0.001 }
        left=a.dup;out=[]
        3.times do |i|
          if lo[i]-left[i]>0.001
            p=left.dup;p[i+3]=lo[i]-left[i];out<<p
          end
          finish=left[i]+left[i+3]
          if finish-hi[i]>0.001
            p=left.dup;p[i]=hi[i];p[i+3]=finish-hi[i];out<<p
          end
          left[i]=lo[i];left[i+3]=hi[i]-lo[i]
        end
        out
      end
    end
  end
end
