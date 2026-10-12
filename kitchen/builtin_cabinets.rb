# Built-in appliance exterior layouts; all dimensions in inches.
module KitchenLab
  def self.builtin?(d)
    %w[oven_tower micro_tower fridge_surround].include?(d['kind'])
  end

  def self.builtin_defaults(d)
    {'appliance_width'=>d['kind']=='fridge_surround' ? 36.0 : 28.0,
     'appliance_height'=>d['kind']=='fridge_surround' ? 72.0 : 28.0,
     'appliance_bottom'=>d['kind']=='micro_tower' ? 24.0 : 28.0,'microwave_height'=>18.0}
  end

  def self.builtin_rows(d)
    p=builtin_defaults(d).merge(d)
    w=Float(p['appliance_width']);ah=Float(p['appliance_height'])
    raise 'Appliance width must fit between the ¾ inch side panels' unless w.finite? && w>=12 && w<=d['width']-1.5
    raise 'Appliance height must be at least 12 inches' unless ah.finite? && ah>=12
    toe=d['kind']=='fridge_surround' ? 0 : d.fetch('toe_height',4)
    available=d['height']-toe-0.25
    device={'kind'=>'appliance','height'=>ah,'width'=>w,'device'=>d['kind']=='fridge_surround' ? 'fridge' : 'wall_oven'}
    rows=[device]
    if d['kind']=='micro_tower'
      mh=Float(p['microwave_height'])
      raise 'Microwave height must be at least 10 inches' unless mh.finite? && mh>=10
      rows.unshift({'kind'=>'appliance','height'=>mh,'width'=>w,'device'=>'microwave'})
    end
    unless d['kind']=='fridge_surround'
      lower=Float(p['appliance_bottom'])-toe-0.25
      raise 'Leave at least 8 inches below the appliance' unless lower.finite? && lower>=8
      rows<<{'kind'=>'doors','height'=>lower,'doors'=>2}
    end
    upper=available-rows.sum { |r| r['height'] }-0.125*rows.length
    raise 'Appliances leave less than 8 inches for the upper doors. Increase cabinet height or lower the appliances.' unless upper.finite? && upper>=8
    [{'kind'=>'doors','height'=>upper,'doors'=>2}]+rows
  end

  def self.builtin_front(e,row,z,d,finish)
    w=row['width'];h=row['height'];x=(d['width']-w)/2;y=-d['depth']
    metal=material('Built-in steel',{'black'=>'#303538','white'=>'#ECEDE9'}.fetch(d['appliance_finish'],'#B8C0C4'))
    glass=material('Appliance glass','#18262D');trim=material('Appliance handle','#DCE1E2')
    side=(d['width']-w)/2
    [0,d['width']-side].each { |sx| box(e,'Appliance filler',sx,y,z,side,0.75,h,finish) } if side>0.001
    box(e,'Built-in appliance exterior',x,y,z,w,0.75,h,metal)
    if row['device']=='fridge'
      split=h*0.3
      box(e,'Fridge door seam',x+w/2-0.04,y-0.02,z+split,0.08,0.03,h-split,glass)
      box(e,'Freezer seam',x,y-0.02,z+split,w,0.03,0.08,glass)
      [x+w/2-1.4,x+w/2+1.1].each { |hx| box(e,'Fridge pull',hx,y-0.9,z+split+3,0.3,0.3,12,trim) }
      box(e,'Freezer pull',x+w*0.2,y-0.9,z+split-2,w*0.6,0.3,0.3,trim)
    else
      box(e,'Appliance glass window',x+w*0.08,y-0.03,z+h*0.12,w*0.84,0.04,h*0.68,glass)
      box(e,'Appliance display',x+w*0.38,y-0.04,z+h*0.88,w*0.24,0.05,h*0.05,glass)
      if row['device']=='microwave'
        box(e,'Microwave pull',x+w*0.89,y-0.8,z+h*0.22,0.3,0.3,h*0.48,trim)
      else
        box(e,'Wall oven pull',x+w*0.12,y-0.8,z+h*0.76,w*0.76,0.3,0.3,trim)
      end
    end
  end
end
