module KitchenLab
  def self.build_overhead(e,d)
    w=d['width'];h=d['height'];dep=d['depth']
    metal=material("Appliance #{d['appliance_finish']}",{'black'=>'#303538','white'=>'#ECEDE9'}.fetch(d['appliance_finish'],'#B8C0C4'))
    glass=material('Appliance glass','#18262D');trim=material('Appliance handle','#DCE1E2')
    if d['kind']=='hood'
      box(e,'Hood canopy',0,-dep,0,w,dep,2,metal)
      g=e.add_group;g.name='Tapered hood'
      low=[[0,-dep,2],[w,-dep,2],[w,0,2],[0,0,2]]
      high=[[w*0.35,-dep*0.55,h*0.35],[w*0.65,-dep*0.55,h*0.35],[w*0.65,0,h*0.35],[w*0.35,0,h*0.35]]
      g.entities.add_face(low.reverse);g.entities.add_face(high)
      4.times { |i| j=(i+1)%4;g.entities.add_face(low[i],low[j],high[j],high[i]) }
      g.material=metal;g.entities.grep(Sketchup::Face).each { |f| f.material=metal;f.back_material=metal }
      ceiling=USE_HOOD_CHIMNEY_CEILING && crown_ceiling_for(d)
      chimney_top=ceiling ? ceiling-cabinet_transform(d).origin.z.to_f : h
      raise 'Hood canopy is above the ceiling.' if chimney_top<=h*0.35
      box(e,'Hood chimney',w*0.35,-dep*0.55,h*0.35,w*0.3,dep*0.55,chimney_top-h*0.35,metal)
      box(e,'Hood controls',w*0.42,-dep-0.025,0.6,w*0.16,0.03,0.5,glass)
      box(e,'Hood filter',w*0.15,-dep*0.85,-0.025,w*0.7,dep*0.65,0.03,glass)
    else
      box(e,'Microwave body',0,-dep+0.75,0,w,dep-0.75,h,metal)
      box(e,'Microwave front',0,-dep,0,w,0.75,h,metal)
      box(e,'Microwave glass',w*0.05,-dep-0.025,h*0.16,w*0.7,0.03,h*0.65,glass)
      box(e,'Microwave display',w*0.82,-dep-0.03,h*0.64,w*0.12,0.035,h*0.18,glass)
      box(e,'Microwave handle',w*0.76,-dep-1.0,h*0.25,0.35,0.35,h*0.5,trim)
      [h*0.27,h*0.7].each { |z| box(e,'Microwave handle mount',w*0.76,-dep-0.75,z,0.35,0.75,0.3,trim) }
      3.times { |i| box(e,'Vent grille',w*0.08,-dep-0.025,h*(0.87+i*0.03),w*0.65,0.03,0.08,glass) }
      3.times { |i| 3.times { |j| box(e,'Microwave button',w*(0.82+i*0.04),-dep-0.03,h*(0.22+j*0.1),w*0.02,0.035,h*0.05,glass) } }
    end
  end
end
