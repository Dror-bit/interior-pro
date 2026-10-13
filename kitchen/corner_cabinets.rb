module KitchenLab
  def self.open_corner?(d);%w[corner_base corner_upper corner_lazy].include?(d['kind']);end
  def self.any_corner?(d);d['kind']=='corner'||open_corner?(d);end
  def self.corner_outline(w,arm,z)
    [[0,0,z],[w,0,z],[w,-arm,z],[arm,-arm,z],[arm,-w,z],[0,-w,z]]
  end
  def self.corner_panel(e,name,w,arm,z,thickness,mat)
    g=e.add_group;g.name=name;f=g.entities.add_face(corner_outline(w,arm,z));f.reverse! if f.normal.z<0;f.pushpull(thickness)
    g.material=mat;g.entities.grep(Sketchup::Face).each { |face| face.material=mat;face.back_material=mat };g
  end
  def self.build_corner_cabinet(e,d)
    w=d['width'];arm=d['depth'];h=d['height'];toe=d['toe_height'];mat=material(d['finish'],FINISHES[d['finish']]);metal=material(d['handle'],d['handle']=='brass' ? '#B39456' : '#242729')
    box(e,'Corner back A',0,-0.75,0,w,0.75,h,mat)
    box(e,'Corner back B',0,-w,0,0.75,w-0.75,h,mat)
    cabinet_side(e,'Corner end A',w-0.75,arm,h,toe,d['toe_setback'],mat)
    corner_turn=Geom::Transformation.axes(ORIGIN,Geom::Vector3d.new(0,-1,0),Geom::Vector3d.new(-1,0,0),Z_AXIS)
    end_b=cabinet_side(e,'Corner end B',w-0.75,arm,h,toe,d['toe_setback'],mat);end_b.transformation=corner_turn
    # Fronts occupy the outer 3/4 inch on both legs; keep the carcass behind them.
    body_arm=arm-0.75
    corner_panel(e,'Corner bottom',w,body_arm,toe,0.75,mat)
    corner_panel(e,'Corner top',w,body_arm,h-0.75,0.75,mat)
    fd=d.merge('kind'=>d['kind']=='corner_upper' ? 'wall' : 'doors')
    door_width=w-arm-0.25;fh=h-toe-0.25
    front(e,'Corner door left',arm+0.125,toe+0.125,door_width,fh,fd,mat,metal)
    wing=e.add_group;wing.name='Corner door B';wing.transformation=corner_turn
    front(wing.entities,'Corner door right',arm+0.125,toe+0.125,door_width,fh,fd,mat,metal)
    if toe>0
      setback=d['toe_setback']
      box(e,'Corner toe A',arm-setback,-arm+setback,0,w-arm+setback,0.6,toe,mat)
      box(e,'Corner toe B',arm-setback-0.6,-w,0,0.6,w-arm+setback,toe,mat)
    end
  end
end
