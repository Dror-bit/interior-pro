module KitchenLab
  module HoodMiters
    def self.outline(role,w,depth)
      t=0.75
      case role
      when 'left' then [[0,-depth],[w,-depth+t],[w,0],[0,0]]
      when 'right' then [[0,-depth+t],[w,-depth],[w,0],[0,0]]
      when 'hood_front' then [[-t,-t],[w+t,-t],[w,0],[0,0]]
      else raise 'Unknown hood cover part'
      end
    end
    def self.prism(entities,name,points,z,height,finish)
      group=entities.add_group;group.name=name
      face=group.entities.add_face(points.map{|x,y|[x,y,z]})
      raise 'Invalid hood cover polygon' unless face
      face.reverse! if face.normal.z<0
      face.pushpull(height)
      group.material=finish
      group.entities.grep(Sketchup::Face).each{|f|f.material=finish;f.back_material=finish}
      group
    end
    def self.build(entities,d,finish)
      role=d['surround_part'];w=d['width'];h=d['height']
      if role=='hood_front' && d['style']=='shaker'
        rail=KitchenLab.settings['shaker_width'];inset=KitchenLab.settings['shaker_inset'];t=0.75
        prism(entities,'Hood cover / left miter',[[-t,-t],[rail,-t],[rail,0],[0,0]],0,h,finish)
        prism(entities,'Hood cover / right miter',[[w-rail,-t],[w+t,-t],[w,0],[w-rail,0]],0,h,finish)
        KitchenLab.box(entities,'Hood cover / top',rail,-t,h-rail,w-2*rail,t,rail,finish)
        KitchenLab.box(entities,'Hood cover / bottom',rail,-t,0,w-2*rail,t,rail,finish)
        KitchenLab.box(entities,'Hood cover / panel',rail,-t+inset,rail,w-2*rail,t-inset,h-2*rail,finish)
      else
        prism(entities,'Hood cover / '+role+' / 45 degree miter',outline(role,w,d['depth']),0,h,finish)
      end
    end
  end
end
