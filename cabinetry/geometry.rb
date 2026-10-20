require_relative 'core'
module InteriorPro
  module Cabinetry
    # Explicit entities/material inputs; one solid per board, no KitchenLab state.
    module Geometry
      module_function
      def box(entities,name,x,y,z,w,d,h,material)
        raise ArgumentError, 'Invalid board dimensions' unless [w,d,h].all? { |v| v.finite? && v>0.001 }
        group=entities.add_group;group.name=name
        face=group.entities.add_face([x,y,z],[x+w,y,z],[x+w,y+d,z],[x,y+d,z])
        face.reverse! if face.normal.z<0
        face.pushpull(h);group.material=material
        group.entities.grep(Sketchup::Face).each { |f|f.material=material;f.back_material=material }
        group
      end

      def front(entities,x,z,w,h,depth,style,material)
        if style=='shaker'
          rail=2.0
          raise ArgumentError,'Front is too small for a shaker frame' if [w,h].min<=rail*2+0.25
          box(entities,'Front panel',x+rail,-depth+0.25,z+rail,w-2*rail,0.5,h-2*rail,material)
          box(entities,'Left stile',x,-depth,z,rail,0.75,h,material)
          box(entities,'Right stile',x+w-rail,-depth,z,rail,0.75,h,material)
          box(entities,'Top rail',x+rail,-depth,z+h-rail,w-2*rail,0.75,rail,material)
          box(entities,'Bottom rail',x+rail,-depth,z,w-2*rail,0.75,rail,material)
        else
          box(entities,'Slab front',x,-depth,z,w,0.75,h,material)
        end
      end
    end
  end
end
